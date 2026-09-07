#!/usr/bin/env python3
"""wpaperd-ws-switch V4.0 — generic per-workspace wallpaper + 5-min timer.

Works on ANY Hyprland setup (single screen, laptop, multi-monitor). The
target output is auto-detected at runtime — nothing is hard-coded to a
specific monitor name.

Design
------
* State file ``~/.local/state/wpaperd-ws-state.json`` maps ws-id (str) to the
  absolute path of the wallpaper image currently shown for that workspace.
* On every ``workspacev2>>ID`` event from hyprland socket2 we query
  ``hyprctl monitors -j`` to find which output is currently focused
  (the one the active workspace lives on) and immediately push
  ``state[ID]`` to wpaperd by rewriting that output's ``[<name>].path``
  block (single-file mode) + ``wpaperctl reload-wallpaper``. wpaperd
  displays the already-decided image → no random re-pick on ws change.
* First time we see a ws we randomly pick from its pool and persist the
  choice so subsequent visits show the same image.
* Pool per workspace: ``~/Pictures/wallpapers/ws{ID}/`` if that
  sub-directory exists, otherwise fall back to the flat
  ``~/Pictures/wallpapers/`` shared by every workspace. So a plain user
  just drops images at the top level; per-workspace differences are
  opt-in by creating ``ws1/ ws2/ …`` folders.
* A background thread wakes every ``TIMER_PERIOD`` (default 300 s) and
  repicks a *different* image for the active ws only. Other workspaces
  stay frozen until visited. This is the "每5分钟后台切换" mechanic.
* Toml: only the ``[<focused monitor>]`` block is touched; it is created
  if missing (steps/73 ships only ``[default]`` + ``[any]``). The rest of
  the file is preserved for readability.

Target monitor detection (order of preference)
-----------------------------------------------
1. ``$WPAPERD_MONITOR`` environment override (for corner cases),
2. the monitor with ``"focused": true`` in ``hyprctl monitors -j``,
3. an internal panel (name matching ``eDP|LVDS|DSI|panel|builtin``),
4. the first connected monitor.

Why this replaces the V2.0 debounced switcher
---------------------------------------------
V2.0 deferred reload by 1.5 s but directory-mode + sorting=random caused
wpaperd to keep re-picking on every reload. Net effect: ws changes felt
jumpy. V3/V4 make switching *deterministic* by committing each ws to a
specific image up-front and using single-file mode to lock wpaperd onto
it. V4 removes the monitor hard-coding of V3.

Reconnect: socket closure (hyprland restart) triggers exponential backoff
1 s → 2 s → … → 30 s.

The script is started by ``~/.config/autostart/wpaperd-ws-switch-autostart.desktop``.
"""
from __future__ import annotations

import json
import os
import pathlib
import random
import re
import signal
import socket
import subprocess
import sys
import threading
import time
from typing import Optional

_HOME        = pathlib.Path.home()  # environment-neutral: resolves to the invoking user's $HOME
WS_BASE      = _HOME / "Pictures" / "wallpapers"
WALLPAPER_T  = _HOME / ".config" / "wpaperd" / "wallpaper.toml"
STATE_FILE   = _HOME / ".local" / "state" / "wpaperd-ws-state.json"
LOG_PATH     = "/tmp/wpaperd-ws-switch.log"
# Default 5 min — override with `WPAPERD_TIMER=30 python3 ...` for testing.
TIMER_PERIOD = int(os.environ.get("WPAPERD_TIMER", "300"))
# Optional monitor override — leave empty to auto-detect.
MONITOR_OVERRIDE = os.environ.get("WPAPERD_MONITOR", "").strip()

EVT_RE       = re.compile(rb"^workspacev2>>(-?\d+),")
IMG_SUFFIXES = (".jpg", ".jpeg", ".png", ".webp")
INTERNAL_RE  = re.compile(r"eDP|LVDS|DSI|\bpanel\b|builtin", re.IGNORECASE)


# ---------------------------------------------------------------------------
# Logging — both stderr (visible via `journalctl --user` if started via
# systemd) and the dedicated log file under /tmp.
# ---------------------------------------------------------------------------
def log(msg: str) -> None:
    line = f"[{time.strftime('%H:%M:%S')}] {msg}"
    print(line, file=sys.stderr, flush=True)
    try:
        with open(LOG_PATH, "a") as f:
            f.write(line + "\n")
    except OSError:
        pass


# ---------------------------------------------------------------------------
# State persistence
# ---------------------------------------------------------------------------
def load_state() -> dict[str, str]:
    """{ws_id_str: /abs/path/to/img.jpg}. ws_id is keyed as string for JSON."""
    if STATE_FILE.exists():
        try:
            with open(STATE_FILE) as f:
                return json.load(f)
        except Exception:                  # noqa: BLE001
            log(f"state file corrupt, starting fresh")
    return {}


def save_state(state: dict[str, str]) -> None:
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(STATE_FILE, "w") as f:
        json.dump(state, f, indent=2)


# ---------------------------------------------------------------------------
# Wallpaper pool helpers
# ---------------------------------------------------------------------------
def pool_images(ws_id: int) -> list[str]:
    """Resolve a workspace's image pool to absolute image paths.

    If ``~/Pictures/wallpapers/ws{ws_id}/`` exists it is used (per-ws
    pools are opt-in — make the folder to get a different image per
    workspace). Otherwise fall back to the flat ``~/Pictures/wallpapers/``
    shared by every workspace. De-dups so multiple symlinks to the same
    backing file are seen once. Returns a sorted list for determinism.
    """
    pool = WS_BASE / f"ws{ws_id}"
    if not pool.is_dir() or not any(pool.iterdir()):
        pool = WS_BASE  # flat, shared pool
    if not pool.is_dir():
        return []
    seen: set[str] = set()
    out: list[str] = []
    for entry in sorted(pool.iterdir()):
        if entry.is_symlink() or entry.is_file():
            target = entry.resolve()
            if target.is_file() and target.suffix.lower() in IMG_SUFFIXES:
                if str(target) not in seen:
                    seen.add(str(target))
                    out.append(str(target))
    return out


# ---------------------------------------------------------------------------
# Monitor auto-detection — no hard-coded output name anywhere.
# ---------------------------------------------------------------------------
def query_monitors() -> list[dict]:
    """Return ``hyprctl -j monitors`` parsed, or [] if unavailable."""
    try:
        out = subprocess.check_output(
            ["hyprctl", "-j", "monitors"],
            timeout=2, stderr=subprocess.DEVNULL,
        )
        data = json.loads(out)
        return data if isinstance(data, list) else []
    except Exception as e:                  # noqa: BLE001
        log(f"monitor query failed: {e!r}")
        return []


def detect_monitor() -> Optional[str]:
    """Pick the monitor whose wallpaper the switcher should drive.

    Preference: $WPAPERD_MONITOR → currently focused → an internal
    panel (eDP/LVDS/DSI/…) → the first connected monitor.
    """
    if MONITOR_OVERRIDE:
        return MONITOR_OVERRIDE
    mons = query_monitors()
    if not mons:
        return None
    for m in mons:
        if m.get("focused"):
            return m.get("name")
    for m in mons:
        if INTERNAL_RE.search(m.get("name", "")):
            return m.get("name")
    return mons[0].get("name")


def pick_random_img(ws_id: int, exclude: Optional[str]) -> Optional[str]:
    pool = pool_images(ws_id)
    if not pool:
        return None
    candidates = [p for p in pool if p != exclude] or pool
    return random.choice(candidates)


# ---------------------------------------------------------------------------
# wpaperd.toml + wpaperctl glue
# ---------------------------------------------------------------------------
def set_toml_path(monitor: str, abs_path: str) -> None:
    """Rewrite *only* the ``path`` line inside ``[{monitor}]``. If that
    block does not exist yet (steps/73 ships only ``[default]`` + ``[any]``)
    it is appended. Everything else in the file is preserved.

    wpaperd's TOML schema validator refuses a config that sets ``path`` to
    a single file *and* ``duration`` on the same monitor block
    (WARN: "Attribute path is set to a file and attribute duration is also
    set"). To stay on the single-file path we also strip any ``duration =``
    line inside the block (file-mode wallpapers don't rotate, so a
    duration there is meaningless).
    """
    text = WALLPAPER_T.read_text()
    block_re = re.compile(rf"(?ms)^\[{re.escape(monitor)}\].*?(?=^\[|\Z)")
    m = block_re.search(text)
    if m:
        block = m.group(0)
        new_block = re.sub(
            r"(?m)^[ \t]*duration\s*=\s*.*\n",
            "",
            block,
        )
        if re.search(r"(path\s*=\s*).*", new_block):
            new_block = re.sub(
                r"(path\s*=\s*).*",
                rf'\1"{abs_path}"',
                new_block,
                count=1,
            )
        else:
            new_block = new_block.rstrip() + f'\npath = "{abs_path}"\n'
        new_text = text[: m.start()] + new_block + text[m.end():]
    else:
        # No block yet — append a single-file [monitor] section at the end.
        new_text = text.rstrip() + (
            f"\n\n[{monitor}]\npath = \"{abs_path}\"\n"
        )
    WALLPAPER_T.write_text(new_text)


def reload_wpaperd() -> None:
    try:
        subprocess.run(
            ["wpaperctl", "reload-wallpaper"],
            check=True, timeout=5,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
        )
        log("wpaperctl reload ok")
    except subprocess.CalledProcessError as e:
        log(f"reload fail: {e.stderr.decode(errors='replace').strip()}")
    except (subprocess.TimeoutExpired, FileNotFoundError) as e:
        log(f"reload err: {e}")


# ---------------------------------------------------------------------------
# Push a wallpaper for ws_id — used both on ws-change and 5-min refresh.
# ---------------------------------------------------------------------------
def show_for_ws(ws_id: int, state: dict[str, str], reason: str,
                monitor: Optional[str]) -> None:
    """Pick/persist an image for ws_id and push it to wpaperd's given
    (focused) monitor.

    reason is a short string for logging: "switch" / "refresh" / etc.
    """
    if not monitor:
        log("no monitor detected — cannot switch wallpaper")
        return
    key = str(ws_id)
    cur = state.get(key)
    if not cur or not pathlib.Path(cur).exists():
        cur = pick_random_img(ws_id, None)
        if cur is None:
            log(f"ws{ws_id} pool empty — cannot show")
            return
        state[key] = cur
        save_state(state)
        log(f"ws{ws_id} first-pick ({reason}) → {pathlib.Path(cur).name}")
    set_toml_path(monitor, cur)
    reload_wpaperd()
    log(f"ws{ws_id} [{monitor}] ({reason}) → {pathlib.Path(cur).name}")


def pick_new_for_active(state: dict[str, str], monitor: Optional[str]) -> None:
    """Background 5-minute refresh — pick a different image for the
    currently-active ws. Other ws stay frozen.
    """
    if not monitor:
        return
    try:
        out = subprocess.check_output(
            ["hyprctl", "-j", "activeworkspace"],
            timeout=2, stderr=subprocess.DEVNULL,
        )
        data = json.loads(out)
        ws_id = int(data.get("id", 1))
    except Exception as e:                  # noqa: BLE001
        log(f"active-ws query failed: {e!r}")
        return
    key = str(ws_id)
    cur = state.get(key)
    new = pick_random_img(ws_id, cur)
    if new and new != cur:
        state[key] = new
        save_state(state)
        set_toml_path(monitor, new)
        reload_wpaperd()
        log(f"5min refresh ws{ws_id} [{monitor}] → {pathlib.Path(new).name}")
    else:
        log(f"5min refresh ws{ws_id}: no different image available "
            f"(pool has {len(pool_images(ws_id))} items)")


# ---------------------------------------------------------------------------
# Background thread — every TIMER_PERIOD, repick active ws.
# ---------------------------------------------------------------------------
def background_refresh(state: dict[str, str], stop: threading.Event) -> None:
    # Wait once at startup so the ws-change path settles first.
    if stop.wait(TIMER_PERIOD):
        return
    while not stop.is_set():
        try:
            mon = detect_monitor()
            pick_new_for_active(state, mon)
        except Exception as e:              # noqa: BLE001
            log(f"refresh error: {e!r}")
        if stop.wait(TIMER_PERIOD):
            return


# ---------------------------------------------------------------------------
# Hyprland IPC stream — workspacev2 events.
# ---------------------------------------------------------------------------
def socket_path() -> str:
    xrd = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    if not sig:
        raise RuntimeError("HYPRLAND_INSTANCE_SIGNATURE not set")
    return os.path.join(xrd, "hypr", sig, ".socket2.sock")


def stream_loop(state: dict[str, str]) -> None:
    path = socket_path()
    backoff = 1
    last_ws: Optional[int] = None
    last_mon: Optional[str] = None
    while True:
        try:
            log(f"connecting {path}")
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
                s.connect(path)
                f = s.makefile("rb", buffering=0)
                backoff = 1
                for raw in f:
                    m = EVT_RE.match(raw)
                    if not m:
                        continue
                    ws_id = int(m.group(1))
                    # Re-resolve the focused monitor on each event so a
                    # multi-monitor focus switch is followed correctly.
                    mon = detect_monitor()
                    if ws_id == last_ws and mon == last_mon:
                        continue
                    last_ws = ws_id
                    last_mon = mon
                    show_for_ws(ws_id, state, reason="switch", monitor=mon)
            log("socket closed, reconnecting")
        except (FileNotFoundError, ConnectionRefusedError) as e:
            log(f"socket unavailable ({e}); retry in {backoff}s")
            time.sleep(backoff)
            backoff = min(backoff * 2, 30)
        except Exception as e:                # noqa: BLE001
            log(f"unexpected error: {e!r}; retry in {backoff}s")
            time.sleep(backoff)
            backoff = min(backoff * 2, 30)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
def main() -> None:
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    state = load_state()
    mon = detect_monitor()
    log(f"V4.0 start — state={len(state)} ws remembered, "
        f"monitor={mon or '(none)'}, timer={TIMER_PERIOD}s")
    stop = threading.Event()
    refresh_thread = threading.Thread(
        target=background_refresh, args=(state, stop), daemon=True
    )
    refresh_thread.start()
    stream_loop(state)


if __name__ == "__main__":
    main()
