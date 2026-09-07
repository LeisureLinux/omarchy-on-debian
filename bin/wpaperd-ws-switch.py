#!/usr/bin/env python3
"""wpaperd-ws-switch V3.0 — silky-smooth per-workspace wallpaper + 5-min timer.

Design
------
* State file ``~/.local/state/wpaperd-ws-state.json`` maps ws-id (str) to the
  absolute path of the wallpaper image currently shown for that workspace.
* On every ``workspacev2>>ID`` event from hyprland socket2 we *immediately*
  push ``state[ID]`` to wpaperd (``[eDP-1].path = <abs-path>``, single-file
  mode, ``wpaperctl reload-wallpaper``). wpaperd displays the already-decided
  image → no random re-pick on ws change → "丝滑".
* First time we see a ws we randomly pick from ``~/Pictures/wallpapers/ws{ID}``
  and persist the choice so subsequent visits show the same image.
* A background thread wakes every ``TIMER_PERIOD`` (default 300 s) and
  repicks a *different* image for the *active* ws only. Other workspaces
  stay frozen until visited. This is the "每5分钟后台切换" mechanic.
* Toml structure preserved: only the path line inside the ``[eDP-1]`` block
  is rewritten so the file is still human-readable.

Why this replaces the V2.0 debounced switcher
---------------------------------------------
V2.0 deferred reload by 1.5 s but the underlying mechanism (path = directory,
sorting = random) caused wpaperd to keep re-picking on every reload. Net
effect: ws changes still felt jumpy and changed the image most of the time.
V3.0 makes the switching *deterministic* by committing each ws to a specific
image up-front and using single-file mode to lock wpaperd onto it.

The 5-minute timer is independent of workspace switching — even if the user
never moves workspaces, the active ws's image rotates automatically.

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
MONITOR      = "eDP-1"
LOG_PATH     = "/tmp/wpaperd-ws-switch.log"
# Default 5 min — override with `WPAPERD_TIMER=30 python3 ...` for testing.
TIMER_PERIOD = int(os.environ.get("WPAPERD_TIMER", "300"))

EVT_RE       = re.compile(rb"^workspacev2>>(-?\d+),")
IMG_SUFFIXES = (".jpg", ".jpeg", ".png", ".webp")


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
    """Resolve ``~/Pictures/wallpapers/ws{ws_id}`` symlinks to absolute image
    paths. De-dup so if multiple IMG* symlinks point at the same backing
    file we only see it once. Returns sorted list for determinism.
    """
    pool = WS_BASE / f"ws{ws_id}"
    if not pool.is_dir():
        return []
    seen: set[str] = set()
    out: list[str] = []
    for entry in sorted(pool.iterdir()):
        # We pull every image in the pool (BiodiverseCostaRica.jpg,
        # AndermattSwiss.jpg, ...). Earlier revisions filtered on
        # ``IMG*`` prefix but the populate-ws-pools script writes
        # real-name symlinks, so the filter zeroed-out the pool.
        if entry.is_symlink() or entry.is_file():
            target = entry.resolve()
            if target.is_file() and target.suffix.lower() in IMG_SUFFIXES:
                if str(target) not in seen:
                    seen.add(str(target))
                    out.append(str(target))
    return out


def pick_random_img(ws_id: int, exclude: Optional[str]) -> Optional[str]:
    pool = pool_images(ws_id)
    if not pool:
        return None
    candidates = [p for p in pool if p != exclude] or pool
    return random.choice(candidates)


# ---------------------------------------------------------------------------
# wpaperd.toml + wpaperctl glue
# ---------------------------------------------------------------------------
def set_toml_path(ws_id: int, abs_path: str) -> None:
    """Rewrite *only* the ``path`` line inside ``[eDP-1]``. Everything else
    (other sections, other fields inside [eDP-1], comments) is preserved.

    wpaperd's TOML schema validator refuses a config that sets ``path`` to
    a single file *and* ``duration`` on the same monitor block
    (WARN: "Attribute path is set to a file and attribute duration is also
    set"). To stay on the single-file "丝滑" path we also strip any
    ``duration =`` line inside ``[eDP-1]`` (file-mode wallpapers don't
    rotate, so duration is meaningless).
    """
    text = WALLPAPER_T.read_text()
    block_re = re.compile(rf"(?ms)^\[{re.escape(MONITOR)}\].*?(?=^\[|\Z)")
    m = block_re.search(text)
    if not m:
        log(f"no [{MONITOR}] section in {WALLPAPER_T} — cannot switch")
        return
    block = m.group(0)
    new_block = re.sub(
        r"(?m)^[ \t]*duration\s*=\s*.*\n",
        "",
        block,
    )
    new_block = re.sub(
        r"(path\s*=\s*).*",
        rf'\1"{abs_path}"',
        new_block,
        count=1,
    )
    new_text = text[: m.start()] + new_block + text[m.end():]
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
def show_for_ws(ws_id: int, state: dict[str, str], reason: str) -> None:
    """Pick/persist an image for ws_id and push it to wpaperd.

    reason is a short string for logging: "switch" / "refresh" / etc.
    """
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
    set_toml_path(ws_id, cur)
    reload_wpaperd()
    log(f"ws{ws_id} ({reason}) → {pathlib.Path(cur).name}")


def pick_new_for_active(state: dict[str, str]) -> None:
    """Background 5-minute refresh — pick a different image for the
    currently-active ws. Other ws stay frozen.
    """
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
        set_toml_path(ws_id, new)
        reload_wpaperd()
        log(f"5min refresh ws{ws_id} → {pathlib.Path(new).name}")
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
            pick_new_for_active(state)
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
                    if ws_id == last_ws:
                        continue
                    last_ws = ws_id
                    show_for_ws(ws_id, state, reason="switch")
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
    log(f"V3.0 start — state={len(state)} ws remembered, "
        f"timer={TIMER_PERIOD}s")
    stop = threading.Event()
    refresh_thread = threading.Thread(
        target=background_refresh, args=(state, stop), daemon=True
    )
    refresh_thread.start()
    stream_loop(state)


if __name__ == "__main__":
    main()
