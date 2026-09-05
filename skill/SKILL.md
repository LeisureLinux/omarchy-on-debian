---
name: omarchy-on-debian
description: Port, debug and maintain the Omarchy 4 (Quattro) Quickshell shell on Debian/Ubuntu + Hyprland. Use when installing the Omarchy shell on a non-Arch distro, when the shell/menu/bar is blank or silent, when QML bindings fail silently, or when maintaining the omarchy-on-debian patch set (Qt reserved words, uwsm shim, login-shell PATH, QLocale formatter, Chinese lunar clock).
agent_created: true
---

# omarchy-on-debian

Run the Omarchy 4 shell on Debian 13 + Hyprland. The shell is portable QML;
everything around it is Arch-specific and needs a port layer.

Repo: <https://github.com/LeisureLinux/omarchy-on-debian>

## When to use

- Installing / re-installing the Omarchy shell on Debian, Ubuntu or any non-Arch distro
- "Bar is blank", "date missing", "menu items do nothing", "icons are tofu boxes"
- Regenerating patches after an upstream `quattro` update
- Touching the Chinese lunar / solar-term clock tables

## Version matrix (verified)

| Component | Version | Source |
|---|---|---|
| Debian | 13.6 trixie | — |
| Hyprland | 0.55.2 | `trixie-backports` |
| Quickshell | 0.3.0 (`qs`) | `trixie-backports` |
| Qt | 6.8.2 | — |

Quickshell and Hyprland are **not** in stable trixie — enable backports pinned to
100 so it only fills gaps.

## Quick start

```bash
git clone https://github.com/LeisureLinux/omarchy-on-debian
cd omarchy-on-debian
./install.sh --dry-run        # always look first
./install.sh                  # then run
./steps/70-verify.sh          # health table, works standalone
./install.sh --only 40        # re-apply patches after upstream refresh
```

Steps are numbered, idempotent, and individually runnable:
`10-deps 20-fetch 30-deploy 40-patch 50-fonts 60-hyprland 70-verify`.

## The five fixes that make it work

| # | Symptom | Root cause | Fix |
|---|---|---|---|
| 1 | Notifications break | `transient` is reserved in Qt 6.8 QML | rename to `isTransient` (`patches/001`) |
| 2 | Every menu item silent no-op | `bash -lc` resets PATH → `omarchy-*` not found | export PATH in `~/.profile` |
| 3 | Menu launches do nothing | upstream wraps launches in `uwsm-app` (Arch-only) | `uwsm-app` shim = `exec "$@"` |
| 4 | Bar date blank | `Qt.formatDate(t, fmt, locale)` rejects QLocale args from QML JS on Qt 6.8 | 2-arg call + `Model.localizeMonthNames` |
| 5 | Weather/icons tofu | `fc-match monospace` → CJK font beats Nerd Font under zh locale | fontconfig strong prepend |

## Debugging playbook

**Rule 0 — QML binding errors are invisible.** A thrown binding renders empty
text with no dialog. Always capture the log:

```bash
pkill -x qs                                    # NOT pkill -f 'qs -p' (kills you too)
qs -p ~/.local/share/omarchy/shell > /tmp/qs.log 2>&1 &
grep -iE "could not convert|incompatible|TypeError|Error:" /tmp/qs.log
```

**Rule 1 — process name is `qs`.** `pgrep -x quickshell` never matches.

**Rule 2 — menu actions run as login shells.** Reproduce with
`bash -lc 'command -v omarchy-menu'`. If empty → PATH, not permissions.

**Rule 3 — shell state:**
```bash
omarchy-shell -q shell ping
omarchy-shell shell toggle omarchy.menu '{"menu":"root"}'
hyprctl binds | grep -i omarchy
```

**Rule 4 — Quickshell crash-restart env trap.** After any crash, these vars
poison the *parent process tree*, and any `qs` started from there dies with
`FATAL Launching config: ''`:
```bash
env -u __QUICKSHELL_CRASH_DUMP_PID -u __QUICKSHELL_CRASH_INFO_FD \
    -u __QUICKSHELL_CRASH_SIGNAL qs -p ~/.local/share/omarchy/shell
```
`omarchy-port` / `omarchy-menu-toggle` unset them. If a terminal still fails,
open a new one.

**Rule 5 — pipefail + `grep -q` = false negative.**
`fc-list | grep -qi nerd` returns 141 (SIGPIPE kills the producer) under
`set -o pipefail`, so a successful match reads as a miss. Use `grep -c`
(which drains input) or the `has <pattern> <cmd…>` helper in `lib/common.sh`.

**Rule 6 — apt output is localized.** `apt-cache policy` prints 候选版本 under
zh_CN; parse it with `LC_ALL=C apt-cache policy …`.

**Rule 7 — Hyprland has no minimize dispatcher.** `minimize` is
`Invalid dispatcher` on 0.55. Park windows on `special:minimized` and toggle
that workspace instead. X11 apps' min/max buttons will still do nothing.

## Font rules

- Weather/update/system icons are **Nerd Font PUA** (U+E30D…). Install a Nerd
  Font — Debian ships none, download FiraCode NF.
- The launcher glyph U+E900 is **not** Nerd Font: it is Omarchy's own
  `default/fonts/omarchy/omarchy.ttf` (U+E900–E90A). Copy to
  `~/.local/share/fonts/omarchy/` + `fc-cache -f`.
- A plain `<alias><prefer>` loses to CJK fonts under zh locales. Use
  `<match target="pattern"><edit name="family" mode="prepend" binding="strong">`.

## Chinese lunar clock

`extras/clock-zh/Model.js` replaces the upstream model wholesale (it is a copy,
not a diff). Priority: **festival > solar term > lunar day**; the 1st shows the
month name.

Regenerate tables (never hand-edit):
```bash
pip install lunardate sxtwl
python3 extras/gen-lunar-table.py > /tmp/lunarInfo.js   # self-verifies 1900-2099
python3 extras/gen-term-table.py  > /tmp/termInfo.js    # 寿星天文历, ~1 min
```

Traps:
- **QML months are 0-based; tables are 1-based.** `solarTerm()` and the
  `solarFestivals` lookup must use `month + 1`. Off-by-one shows 白露 as 立秋.
- 除夕 = last day of lunar year; in a year with a leap 12th month the year ends
  in the leap month → guard `lunarLeapMonth(year) !== 12`.
- `lunardate.__init__` does **not** validate; only `to_solar_date()` raises.
  Validate month lengths by converting, not constructing.
- Don't derive month lengths from consecutive first-of-month solar dates: in a
  leap-month year (1900 = 闰八月) a regular month measures ~59 days.

## Patch maintenance after an upstream update

```bash
cd ~/.local/share/omarchy
for f in shell/plugins/notifications/Service.qml bin/omarchy-menu-timezone \
         shell/plugins/panels/clock/BarWidget.qml shell/plugins/panels/clock/Panel.qml; do
  diff -u --label "a/$f" --label "b/$f" <upstream>/$f $f
done > /tmp/new.patch
```
Keep patches `-p1`-applicable from `~/.local/share/omarchy` (paths `a/shell/…`,
`a/bin/…`). `steps/40-patch.sh` detects already-applied patches by testing the
reverse apply, so re-running it is safe.

## Verify before declaring done

```bash
./steps/70-verify.sh     # exits non-zero on any critical failure
```
It covers binaries, payload, shims, login-shell PATH, fonts, patch presence,
IPC ping, and a 5-case lunar spot check.
