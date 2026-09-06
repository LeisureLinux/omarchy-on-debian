# Troubleshooting

Ordered by how much time each one cost, not by likelihood.

---

## 1. Quickshell won't start: `FATAL Launching config: ''`

`qs` decides it is a crash-restart child by reading env vars
`__QUICKSHELL_CRASH_DUMP_PID`, `__QUICKSHELL_CRASH_INFO_FD`,
`__QUICKSHELL_CRASH_SIGNAL`. A crashed instance leaves them in the environment
of the process tree that spawned it — including a terminal multiplexer or an
IDE's shell. Any `qs` started from there inherits a bogus restart mode and dies
reading an empty config path.

```bash
env -u __QUICKSHELL_CRASH_DUMP_PID \
    -u __QUICKSHELL_CRASH_INFO_FD \
    -u __QUICKSHELL_CRASH_SIGNAL \
    qs -p ~/.local/share/omarchy/shell
```

`omarchy-port` and `omarchy-menu-toggle` already unset all three. If a terminal
still can't start the shell, open a fresh one — the pollution came from its
parent.

## 2. Every menu item does nothing (no error anywhere)

Two independent causes, both hit on Debian:

**a) PATH.** Menu actions run via `Quickshell.execDetached(["bash", "-lc", cmd])`.
A login shell re-reads `/etc/profile` and resets `PATH`, so
`~/.local/share/omarchy/bin` disappears and every `omarchy-menu-*` is
`command not found` — silently.

Fix: export the PATH from `~/.profile` (step 30 does this).
Verify: `bash -lc 'command -v omarchy-menu'`.

**b) `uwsm-app`.** Upstream wraps launches in `uwsm-app` (Arch's Wayland session
manager). Debian has no `uwsm`, so each launch is a no-op. Fixed by the
`~/.local/share/omarchy/bin/uwsm-app` shim (`exec "$@"`).

## 3. Bar date / month header blank

Binding expressions that throw render as empty text with no visual error. Start
`qs` with output captured and grep it:

```bash
pkill -x qs
qs -p ~/.local/share/omarchy/shell > /tmp/qs.log 2>&1 &
grep -i "could not convert\|incompatible arguments\|TypeError" /tmp/qs.log
```

On Qt 6.8.2, `Qt.formatDate(dt, fmt, locale)` / `Qt.formatDateTime(...)` reject
both a locale *name* string and a `QLocale` object passed from QML JS. Use the
two-arg form and localize month names in JS (`Model.localizeMonthNames`).

**Always check the log after touching QML.** A failed binding is invisible.

## 4. Weather / update / system icons render as tofu

`fc-match monospace` resolves to a CJK font (e.g. Sun-ExtA) because it claims
200+ languages and wins the locale score under `zh_CN`. Qt then falls back
there for the Nerd Font PUA glyphs (U+E30D etc).

A plain `<alias><prefer>` is too weak. Force it with a strong prepend —
`dotfiles/61-nerd-font-monospace.conf` — then `fc-cache -f`.

## 5. Left-corner launcher icon is a box

That glyph (U+E900) is **not** a Nerd Font glyph. It lives in Omarchy's own
`default/fonts/omarchy/omarchy.ttf`, covering U+E900–E90A (Omarchy, Pi,
OpenCode, omp, Grok, Codex, LM Studio, Ollama, T3, Ori, Hermes). Copy it to
`~/.local/share/fonts/omarchy/` and `fc-cache -f` (step 50).

## 6. Super+D opens an empty panel

`default/omarchy/omarchy-menu.jsonc` is the menu definition. If it wasn't
deployed, the panel opens with nothing in it. Step 30 installs it to
`~/.config/omarchy/`. `FileView` watchers don't always pick up files created
after startup — restart the shell after copying.

## 7. Timezone menu entry silently fails

`omarchy-menu-timezone` calls `sudo timedatectl`. In a detached process with no
tty, `sudo` cannot prompt, and upstream ships no askpass. The shell registers a
polkit agent, so `pkexec` gives a GUI password prompt instead (patch 002).

## 8. Two bars / duplicate notifications

`waybar` and `mako` are still in `hyprland.conf` autostart. Comment them out;
step 60 warns but does not edit existing lines.

## 9. Killing the shell kills your own command

```bash
pkill -f 'qs -p'      # matches your own command line -> SIGTERM to yourself
pkill -x qs           # correct
```

The Quickshell process is named **`qs`**, not `quickshell`
(`pgrep -x quickshell` never matches).

## 10. X11 apps' minimize button does nothing

Not a bug you can fix. Hyprland 0.55 has no `minimize` dispatcher
(`hyprctl dispatch minimize` → `Invalid dispatcher`). The shipped binds park
windows on `special:minimized` and toggle that workspace instead.

## 11. Super+D does nothing — no panel appears, `hyprctl layers` shows no `omarchy-menu` namespace

Two distinct silent failures look identical from the keyboard: Super+D pressed,
nothing on screen, no log line pointing at the menu. The truth is in
`hyprctl layers` — if there is **no Layer with `namespace: omarchy-menu`**,
the menu's `PanelWindow` never instantiated.

**a) Stale Hyprland instance signature.** A dead `Hyprland` (e.g. you `pkill`'d
the compositor to reset it) leaves its `~/.local/share/omarchy/.../shell`
Quickshell pointed at the dead compositor's socket. The shell starts, tries
to talk IPC, fails, the PanelWindow never gets the layer-shell ack and stays
hidden. The diagnostic is in the launcher's hands, not yours:

```bash
ls -l /proc/$(pgrep -f 'qs -p.*omarchy/shell' | head -1)/environ | tr '\0' '\n' | grep HYPRLAND_INSTANCE_SIGNATURE
find /run/user/$(id -u)/hypr -mindepth 1 -maxdepth 1 -type d \
  -exec sh -c '[ -S "$1/.socket.sock" ] && [ -S "$1/.socket2.sock" ] && echo "LIVE $1"' _ {} \;
```

If the `HYPRLAND_INSTANCE_SIGNATURE` does not appear in the `LIVE` list, the
shell is talking to a dead compositor. The `dotfiles/omarchy-port` and
`dotfiles/omarchy-menu-toggle` shipped here both auto-discover the live HIS
and re-export it before exec'ing `qs` — kill the orphaned shell, rerun the
launcher, retry Super+D.

**b) `PanelWindow` fails to instantiate from a duplicated QML signal handler.**
If a custom `Menu.qml` edit accidentally declares the same property binding
twice (e.g. an `onVisibleChanged` and an `onWidthChanged` both overriding
existing handlers in the upstream file), Qt prints
`WARN: Property value set multiple times Menu.qml[NNNN:5]` and **silently
drops the `PanelWindow` itself** — no error, no layer, no menu. No log line
to grep for, because the warning is buried in `/tmp/qsp-fresh.log` (or
similar) if at all. Diagnostic:

```bash
pkill -x qs
qs -p ~/.local/share/omarchy/shell > /tmp/qs.log 2>&1 &
# press Super+D
grep -nE 'set multiple times|Property value|QQmlContext' /tmp/qs.log
hyprctl layers | grep omarchy-menu   # still empty? PanelWindow is dead
```

Fix: re-edit `~/.local/share/omarchy/shell/plugins/menu/Menu.qml`, remove
the duplicate handler, `omarchy-restart-shell`. Verify with
`hyprctl layers | grep omarchy-menu` — the namespace must appear.

The menu plugin already wraps a `summon → openPanelIds[id]=true →
deliverIfLoaded() → visible = opened && rowsLoaded` chain. If
`isPluginOpen` is `true` and `hyprctl layers` still has no menu namespace,
the `PanelWindow` is the broken component, not the IPC path.

---

## 12. Menu → About opens nothing (or a small clipped window)

`omarchy-launch-about` renders fastfetch inside a terminal found by
`xdg-terminal-exec`. Three independent things break it on Debian:

**a) `xdg-terminal-exec` missing** — `omarchy-launch-tui` execs
`uwsm-app -- xdg-terminal-exec ...`; when the binary is absent the chain
dies silently and no window ever appears. Fix: `apt install
xdg-terminal-exec` (it is in trixie; step 10 installs it).

**b) The resolved terminal cannot carry the app-id** — Debian's
`foot.desktop` declares no `X-TerminalArgAppId`, so the window's class
stays `foot` and the `org.omarchy.about` float/size rules never match;
kitty's entry declares `X-TerminalArgAppId=--class`. Fix: put
`kitty.desktop` first in `~/.config/hyprland-xdg-terminals.list`, and if a
user-level `~/.local/share/applications/kitty.desktop` (the common
`env GLFW_IM_MODULE=ibus kitty` IME variant) shadows the system entry,
append the `X-Terminal*` keys to it — step 65 does both. The resolver
caches its pick in `~/.cache/xdg-terminal-exec`; the hash covers the list
files, so editing the list is enough.

**c) A user fastfetch config shadows the Omarchy layout** — any
`~/.config/fastfetch/config.jsonc` makes `omarchy-launch-about` skip its
window-fit and logo-sheen code paths (`custom_fastfetch_config()`), so
the window opens at the static rule size and clips. Move it aside:

```bash
mv ~/.config/fastfetch/config.jsonc ~/.config/fastfetch/config.jsonc.bak
```

Verify the whole chain:

```bash
omarchy-launch-about
hyprctl clients -j | jq -r '.[] | select((.class // "") | test("omarchy.about"))'
# expect: class=org.omarchy.about, floating=true, size≈[1100,580]
```

---

## Useful commands

```bash
~/.local/bin/omarchy-port &                 # start the shell
omarchy-shell -q shell ping                 # IPC health
omarchy-shell shell toggle omarchy.menu '{"menu":"root"}'
hyprctl reload                              # re-read binds
hyprctl binds | grep -i omarchy
qs -p ~/.local/share/omarchy/shell 2>&1 | tee /tmp/qs.log
hyprctl layers | grep omarchy-menu         # is the Super+D panel alive?
omarchy-menu-locale zh-CN                   # switch menu to 简体中文
omarchy-menu-locale en                     # back to English
omarchy-launch-about                        # About (fastfetch) screen
hyprctl clients -j | jq '.[] | select(.class == "org.omarchy.about")'
```
