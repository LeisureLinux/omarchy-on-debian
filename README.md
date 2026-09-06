# omarchy-on-debian

Run the **Omarchy 4 (Quattro) shell** — the Quickshell UI from the Arch-based
Omarchy distro — on **Debian 13 (trixie) + Hyprland**.

The shell itself is portable: 2 MB of QML/JS plugins that shell out to ~90
`omarchy-*` bash scripts. What is *not* portable is everything around it —
Arch session tooling, the package set, the icon font, and a couple of Qt
version quirks. This repo is that gap, packaged as numbered, idempotent steps.

Tested on: Debian 13.6, Hyprland 0.55.2 (bpo13), Quickshell 0.3.0 (bpo13), Qt 6.8.2.

```
git clone https://github.com/LeisureLinux/omarchy-on-debian
cd omarchy-on-debian
./install.sh --dry-run     # look first
./install.sh               # then run
```

Then log out and back in. `Super+D` opens the menu, `Super+Alt+T` the theme
picker. `./steps/70-verify.sh` prints a health table at any time.

---

## What the steps do

| Step | Script | What it fixes |
|---|---|---|
| 10 | `steps/10-deps.sh` | Packages. Quickshell/Hyprland need `trixie-backports` (pinned to 100 so it only fills gaps). Nerd Font is downloaded because Debian ships none. |
| 20 | `steps/20-fetch.sh` | Gets the Omarchy source: clone (`--branch quattro`), local checkout, or tarball. Handles the `install/omarchy/` payload layout. |
| 30 | `steps/30-deploy.sh` | rsyncs `shell/ bin/ config/ default/ themes/` into `~/.local/share/omarchy`, installs the launcher, the `uwsm-app` shim, and the login-shell PATH. |
| 40 | `steps/40-patch.sh` | The compatibility patches (below). Idempotent — reverse-applies to detect "already done". |
| 50 | `steps/50-fonts.sh` | Installs `omarchy.ttf` and forces `monospace` → Nerd Font. |
| 60 | `steps/60-hyprland.sh` | Autostart, menu key, minimised-window workspace, About window rules. |
| 65 | `steps/65-about.sh` | The About screen: `/etc/fastfetch/config.jsonc`, the Omarchy logo, and the xdg-terminal-exec glue that makes the `org.omarchy.about` class resolvable. |
| 70 | `steps/70-verify.sh` | Health checks + a lunar-table spot check. |

Steps are standalone: `./install.sh --only 40` re-applies patches after an
upstream refresh. Backups of anything overwritten land in
`~/.local/share/omarchy/.omarchy-on-debian/backups/`.

## Packages

Step 10 installs three groups. Nothing is removed — it only ever adds.

**Core** (installed unconditionally; the shell and its QML plugins exec these):

`quickshell` `hyprland` `xdg-desktop-portal-hyprland` `jq` `bc` `curl` `wget`
`unzip` `rsync` `imagemagick` `inotify-tools` `libxkbcommon-tools` (xkbcli)
`libnotify-bin` `polkitd` `pkexec` `wireplumber` `network-manager` `bluez`
`power-profiles-daemon` `grim` `slurp` `wl-clipboard` `pipewire`
`pipewire-pulse` `fonts-firacode`

`quickshell`, `hyprland` and `xdg-desktop-portal-hyprland` come from
`trixie-backports`, which the step adds with `Pin-Priority: 100` — backports
only fills gaps, it never upgrades stable packages.

**Optional** (installed if the repo carries them; each gates a feature, and the
shell hides the entry when the binary is missing — no errors, just an absent
menu row):

| Package | Gates | In Debian 13 |
|---|---|---|
| `gum` | TUI pickers in some `omarchy-*` scripts | yes |
| `brightnessctl` | brightness OSD / keys | yes |
| `pamixer` | volume OSD | yes |
| `wtype` | typing into the focused window | yes |
| `hyprpicker` | colour picker | yes (backports) |
| `hyprsunset` | night light | yes (backports) |
| `cliphist` | clipboard history | yes |
| `swayidle` `swaylock` | idle / lock | yes |

On the reference machine these are intentionally **not** installed — the
matching menu entries simply stay hidden. Install any of them later and the
feature appears after a shell restart.

**Deliberately not installed:**

| Package | Why not |
|---|---|
| `mako` | The shell's notifications plugin runs Quickshell's own `NotificationServer` (`plugins/notifications/Service.qml`). A second daemon just fights it for the notification bus — you get double or zero notifications. |
| `waybar` | The Omarchy bar replaces it. If already installed, comment it out of `hyprland.conf` autostart or you get two bars. Step 60 warns but does not edit existing lines. |
| `uwsm` / `uwsm-app` | Not packaged for Debian. Upstream wraps every app launch in it; the `uwsm-app` shim in `dotfiles/` makes those launches plain `exec "$@"` instead. |
| Nerd Fonts | Debian ships none. Step 10 downloads FiraCode Nerd Font to `~/.local/share/fonts` if no Nerd Font is present. |

`fc-list` and `apt-cache` output is locale-dependent — `apt-cache policy` prints
候选版本 under zh_CN, so step 10 parses it with `LC_ALL=C`.

## The patches (the actual port)

| Patch | Symptom without it | Cause |
|---|---|---|
| `001-notifications-isTransient.patch` | Notifications panel throws / notifications vanish | `transient` is a reserved word in Qt 6.8 QML |
| `002-menu-timezone-pkexec.patch` | Timezone menu entry silently does nothing | `sudo` in a detached process has no tty; upstream assumes an askpass |
| `003-clock-barwidget-zh.patch` | Bar date blank | `Qt.formatDateTime(date, fmt, locale)` — this Qt build refuses QLocale args from QML JS and throws |
| `004-clock-panel-zh.patch` | Month header + hero date English | same, plus hardcoded `en_US` weekday locale |
| `extras/clock-zh/Model.js` | — | Full replacement: adds lunar calendar, 24 solar terms, Chinese festivals |

`uwsm-app` shim (not a patch, a new file): upstream launches apps through
`uwsm-app`, Arch's Wayland session manager. Debian has no `uwsm`, and without
the shim every menu launch is a **silent no-op**.

## Chinese lunar clock (optional, on by default)

`extras/clock-zh/Model.js` adds:

- Lunar date on every calendar cell; the 1st shows the month name (e.g. `七月`)
- 24 solar terms from a real ephemeris table (1900–2099)
- Festivals: 元旦 劳动节 国庆节 · 春节 元宵 端午 七夕 中秋 重阳 腊八 除夕
- Priority: **festival > solar term > lunar day**
- Hero row shows e.g. `丙午年七月廿四`

Tables are generated, not hand-typed:

```bash
pip install lunardate      # lunar month structure
python3 extras/gen-lunar-table.py > /tmp/lunarInfo.js
pip install sxtwl          # 寿星天文历 — authoritative solar terms
python3 extras/gen-term-table.py > /tmp/termInfo.js
```

Skip it with `./install.sh --no-clock-zh`.

## Menu i18n — Simplified / Traditional Chinese overlays (optional)

`extras/menu-i18n/` ships a Chinese overlay for the Super+D menu. Translation
sources live in `extras/menu-i18n/locales/omarchy-menu.zh-{CN,TW}.jsonc`
(331 entries each, only `label` is written — every other field inherits from
the default menu). The switcher `extras/menu-i18n/omarchy-menu-locale` deep-merges
the chosen locale into `~/.config/omarchy/extensions/omarchy-menu.jsonc` and
re-tags it with `_locale: "<lang>"`, so re-running the switcher leaves your
non-locale custom entries alone.

```bash
~/.local/bin/omarchy-menu-locale             # show current
~/.local/bin/omarchy-menu-locale zh-CN       # apply 简体中文
~/.local/bin/omarchy-menu-locale zh-TW       # apply 繁體中文
~/.local/bin/omarchy-menu-locale en          # back to English (clears user ext)
~/.local/bin/omarchy-menu-locale list        # list installed locales
```

Switching is hot-applied: the menu plugin watches the user-extension file and
re-reads it. `hyprctl layers` will show `namespace: omarchy-menu` come and go
as Super+D toggles — use it to confirm the PanelWindow really instantiates
instead of trusting a silent log line.

### Why the locale scripts alone are not enough

`MenuModel.mergeMenuSources(default, user)` does **whole-entry replacement**:
if the user extension contains `id: "about"` it overwrites the default
`about` entry entirely. A translation line like `{"label":"关于"}` gets
completed by `MenuModel.normalizeItem()` into `{id:"about", parent:"root",
kind:"menu", icon:"", label:"关于", action:"", target:"", ...}` — and that
overwrites the real `about`'s `kind/action/icon`, leaving the menu full of
inert stubs that render as **「Go… + Nothing here yet」**.

The fix lives in Quickshell core (`~/.local/share/omarchy/shell/plugins/menu/`,
not in this repo): `parseMenuJsonc` / `normalizeItem` accept a `sparse`
flag, the user extension is parsed with `sparse=true` (only the fields you
actually wrote, no completion, no `kind/parent` auto-inference), and the
default menu still parses `sparse=false`. Then `{"label":"关于"}` only
overwrites the `label` of `about` — `kind/action/icon/parent` keep their
default values and the menu renders normally with Chinese text.

If your core files are upstream-clean, the sparse patch is the only edit
you need. See `extras/menu-i18n/README.md` for the exact code change and
[`TROUBLESHOOTING.md §11`](TROUBLESHOOTING.md) for the silent-failure mode
that motivated it.

## kitty + IME: `linux_display_server x11` kills Chinese input

kitty only supports input methods on its **Wayland** backend (text-input-v3).
Its `linux_display_server x11` option forces it onto XWayland, where kitty has
**no IME support at all** — fcitx5 is healthy, XIM is even registered
(`xprop -root XIM_SERVERS` lists it), but kitty never speaks XIM. Typing is
literal: no preedit, no candidate window, ever. This bites on Debian/Hyprland
ports where an old `kitty.conf` carried over from an X11 desktop still sets
`x11`.

Symptoms: no soft keyboard / candidate popup in kitty when switching to
Chinese; `fcitx5-diagnose` and every GTK/Qt app are fine.

Fix — one line in `~/.config/kitty/kitty.conf`:

```
linux_display_server wayland
```

Then restart kitty (config is read at startup). Verify the backend with
`hyprctl clients` (`xwayland: 0`) or by checking which socket kitty holds:
`ls -l /proc/$(pgrep -x kitty)/fd | grep -c wayland`.

Debugging tip that settles this class of problem fast: `hyprctl clients`
shows `xwayland: 1` for XWayland apps; `ss -xp` resolves each process's
sockets to `/tmp/.X11-unix/X0` vs `wayland-1`. If the "broken" app turns out
to be on X11, the whole fcitx5 config is a red herring.

## Layout

```
install.sh          orchestrator (--dry-run / --only N / --src PATH)
lib/common.sh       logging, backup-on-overwrite, guarded file append
steps/1x..7x        the numbered steps
patches/            unified diffs against upstream, applied with -p1 in ~/.local/share/omarchy
dotfiles/           omarchy-port, omarchy-menu-toggle, uwsm-app, fontconfig, hypr snippet
extras/clock-zh/    replacement Model.js + table generators
extras/menu-i18n/   zh-CN / zh-TW menu overlays, locale switcher, sparse-merge notes
```

## Scope / known limits

- Hyprland only. The shell assumes `hyprctl`, `hyprpicker`, `hyprsunset`.
- Hyprland has **no** minimize dispatcher; the bind parks windows on a special
  workspace instead. X11 apps' min/max buttons still do nothing.
- Optional packages gate features: no `gum` / `brightnessctl` / `pamixer` →
  those menu entries and OSDs stay hidden.
- The clock patch replaces `Model.js` wholesale. After an upstream update,
  re-diff it rather than re-applying blindly.

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for the failure modes that cost
the most time — including the Quickshell crash-restart env-var trap.

## Upstream

Omarchy: <https://github.com/omacom/omarchy> (branch `quattro`).
This repo ships no Omarchy code of its own beyond patches — it is a port kit.
