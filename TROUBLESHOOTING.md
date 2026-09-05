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

---

## Useful commands

```bash
~/.local/bin/omarchy-port &                 # start the shell
omarchy-shell -q shell ping                 # IPC health
omarchy-shell shell toggle omarchy.menu '{"menu":"root"}'
hyprctl reload                              # re-read binds
hyprctl binds | grep -i omarchy
qs -p ~/.local/share/omarchy/shell 2>&1 | tee /tmp/qs.log
```
