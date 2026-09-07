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
./preflight.sh            # NEW: preview everything it touches (sudo + ~/.config ~/.local)
./install.sh --dry-run    # also works: prints every command without running
./install.sh              # then run
```

Then log out and back in. `Super+Space` opens the menu, `Super+Alt+T` the theme
picker. `./steps/71-verify.sh` prints a health table at any time.

---


## What the steps do

Roughly: steps 10/65/66/68/72/73/74 touch **system-level** things and will
prompt for your password (`/etc`, apt packages); everything else only writes
under your `~/.config`, `~/.local`, `~/.cargo`, `~/bin` and `~/Pictures`.
Run `./preflight.sh` (or `./install.sh --preflight`) to see that sudo-vs-user
split on your machine before committing.

| Step | Script                 | What it fixes                                                                                                                                          |
| ---- | ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 10   | `steps/10-deps.sh`     | Packages. Quickshell/Hyprland need `trixie-backports` (pinned to 100 so it only fills gaps). Nerd Font is downloaded because Debian ships none.        |
| 20   | `steps/20-fetch.sh`    | Gets the Omarchy source: clone (`--branch quattro`), local checkout, or tarball. Handles the `install/omarchy/` payload layout.                        |
| 30   | `steps/30-deploy.sh`   | rsyncs `shell/ bin/ config/ default/ themes/` into `~/.local/share/omarchy`, installs the launcher, the `uwsm-app` shim, and the login-shell PATH.     |
| 40   | `steps/40-patch.sh`    | The compatibility patches (below). Idempotent — reverse-applies to detect "already done".                                                              |
| 50   | `steps/50-fonts.sh`    | Installs `omarchy.ttf` and forces `monospace` → Nerd Font.                                                                                             |
| 60   | `steps/60-hyprland.sh` | Autostart, menu key, minimised-window workspace, About window rules.                                                                                   |
| 65   | `steps/65-about.sh`    | The About screen: `/etc/fastfetch/config.jsonc`, the Omarchy logo, and the xdg-terminal-exec glue that makes the `org.omarchy.about` class resolvable. |
| 66   | `steps/66-calculator.sh` | A lightweight `omacalc` (rofi + `qalc`) in place of the upstream Qt/QML AUR calculator. Installs `qalc` if missing. |
| 67   | `steps/67-monitor-scaling.sh` | Patch `omarchy-hyprland-monitor-scaling` to use `hyprctl keyword monitor` first — `hyprctl eval` silently no-ops on a plain `hyprland.conf`. |
| 68   | `steps/68-pkg-apt.sh`    | Rewrite the 4 `omarchy-pkg-*` pickers against apt (was pacman/yay); installs `apt-utils` + `fzf` if missing. |
| 69   | `steps/69-show-desktop.sh` | Add a Super+D "show desktop" toggle (hide/restore the active workspace). |
| 70   | `steps/70-bar-overlay.sh` | Pin the Quickshell top bar to `WlrLayer.Overlay` so it stays visible above fullscreen windows. |
| 71   | `steps/71-verify.sh`   | Health checks + a lunar-table spot check.                                                                                                              |
| 72   | `steps/72-lockscreen-pam.sh` | Install `/etc/pam.d/omarchy-lock-password` so Quickshell's lock plugin can authenticate. Without it Super+Ctrl+L silently does nothing (`qs ipc call lock lock` returns `missing-pam`). Debian-only — drops the Arch `pam_systemd_home.so` and uses `pam_unix` + Debian's stock modules. |
| 73   | `steps/73-wallpaper-rotate.sh` | Install `wpaperd` (a Wayland wallpaper daemon with native folder rotation — the closest equivalent to `budgie-wallstreet`) via `cargo install`, with any dead proxy stripped (`NO_PROXY=*`). Creates `~/Pictures/wallpapers/` (seeds it from `/usr/share/backgrounds` on first run) and writes a **generic** `~/.config/wpaperd/wallpaper.toml` (`[default]`+`[any]` → that one directory — correct on any monitor layout, nothing hard-coded). Writes an XDG autostart entry and comments out the `hyprpaper` exec-once. Never fetches images; the user drops their own into the folder. |
| 74   | `steps/74-workspace-wallpaper.sh` | **Per-workspace wallpapers via `wpaperd` + a generic switcher.** Bins the `hyprpaper` daemon entirely (Cleanup removes every Arch-prebuilt artifact). `bin/wpaperd-ws-switch.py` listens on Hyprland `socket2.sock`; on each `workspacev2` event it **auto-detects the active/focused output** (`hyprctl monitors -j` — nothing hard-coded to a monitor name) and rewrites that output's block in `wallpaper.toml` so each workspace shows **the image you last saw on it**. Per-workspace distinct images are opt-in via `ws1/ ws2/ …` sub-folders under `~/Pictures/wallpapers/`; without them every workspace shares the flat pool. A background thread rotates the active workspace's image every 5 minutes (`WPAPERD_TIMER=30` to override). Also **defuses two compositor-crash time-bombs** that were killing Hyprland on every lock — `systemctl --user mask xdg-desktop-portal-hyprland.service` (screencopy SIGSEGV) and replacement of `/etc/pam.d/hyprlock` to drop the `pam_ecryptfs.so unwrap`. |

Steps are standalone: `./install.sh --only 40` re-applies patches after an  
upstream refresh. Backups of anything overwritten land in  
`~/.local/share/omarchy/.omarchy-on-debian/backups/`.


## Changelog

- **v0.5.0** — the installer is now a clean, third-party-friendly one-shot
  (no author-machine assumptions baked in). Wallpaper is **fully
  generic**: steps 73/74 only create `~/Pictures/wallpapers/` and write a
  `[default]+[any]` config (no hard-coded `[eDP-1]`/`[DP-4]`, no Bing
  fetch, no proxy hacks — you drop in your own images). The per-workspace
  switcher (`bin/wpaperd-ws-switch.py`) now **auto-detects the active
  output** at runtime and per-ws images are opt-in via `ws1/ ws2/ …`
  sub-folders. Also: step 66 now installs `rofi` (the calculator needs it),
  `omarchy-wallpaper-rotate init` writes the generic config, and
  `71-verify` checks the generic setup instead of stale per-ws pools.

- **v0.4.0** — `preflight.sh` (also `./install.sh --preflight`): a read-only
  preview that splits every install action into *"will prompt for sudo"*
  (apt packages, `/etc` writes) vs *"writes under your ~/.config ~/.local
  ~/.cargo ~/bin"*. Paths in the per-workspace wallpaper tooling are now
  derived from `$HOME` instead of a hard-coded home (works for any user).
  Installer help + README step table now cover steps 66–69 and the new flag.

- **v0.3.0** — bar overlay (Super+F), show-desktop (Super+D), about /
  calculator / monitor-scaling / apt-pkg steps, lock-screen PAM,
  wpaperd wallpaper rotation + per-workspace engine, and defusal of the
  two lock-time compositor crashes. The Arch-prebuilt `hyprpaper` stash
  (`.so` + GLIBC-2.43 math shim + `patchelf` rpath surgery) is gone —
  step 74 removes any leftover and wpaperd owns the wallpaper slot.


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
only fills gaps, it never upgrades stable packages. **Step 74 masks
`xdg-desktop-portal-hyprland.service`** because on Debian + Hyprland it
SIGSEGVs during `wlr-screencopy` (see `TROUBLESHOOTING.md §13a`). If
you actually rely on Flatpak/Snap apps for screen capture, unmask it
later with `systemctl --user unmask xdg-desktop-portal-hyprland.service`.

**Optional** (installed if the repo carries them; each gates a feature, and the  
shell hides the entry when the binary is missing — no errors, just an absent  
menu row):

| Package               | Gates                                   | In Debian 13    |
| --------------------- | --------------------------------------- | --------------- |
| `gum`                 | TUI pickers in some `omarchy-*` scripts | yes             |
| `brightnessctl`       | brightness OSD / keys                   | yes             |
| `pamixer`             | volume OSD                              | yes             |
| `wtype`               | typing into the focused window          | yes             |
| `hyprpicker`          | colour picker                           | yes (backports) |
| `hyprsunset`          | night light                             | yes (backports) |
| `cliphist`            | clipboard history                       | yes             |
| `swayidle` `swaylock` | idle / lock                             | yes             |

On the reference machine these are intentionally **not** installed — the  
matching menu entries simply stay hidden. Install any of them later and the  
feature appears after a shell restart.

**Deliberately not installed:**

| Package             | Why not                                                                                                                                                                                                            |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `mako`              | The shell's notifications plugin runs Quickshell's own `NotificationServer` (`plugins/notifications/Service.qml`). A second daemon just fights it for the notification bus — you get double or zero notifications. |
| `waybar`            | The Omarchy bar replaces it. If already installed, comment it out of `hyprland.conf` autostart or you get two bars. Step 60 warns but does not edit existing lines.                                                |
| `uwsm` / `uwsm-app` | Not packaged for Debian. Upstream wraps every app launch in it; the `uwsm-app` shim in `dotfiles/` makes those launches plain `exec "$@"` instead.                                                                 |
| Nerd Fonts          | Debian ships none. Step 10 downloads FiraCode Nerd Font to `~/.local/share/fonts` if no Ner1d Font is present.                                                                                                     |
| `wpaperd`           | The default wallpaper daemon. We *do* install this in step 73 (via `cargo install`); it's listed here to flag that Debian trixie has no apt package for it. Future: `repo.freelamp.com` will carry a `.deb` built by `packaging/rust-crate-deb/build.sh`. |


## Wallpaper rotation with `wpaperd`

Omarchy upstream uses a single static wallpaper via `hyprpaper`. Steps 73
and 74 replace that with **wpaperd** — a Wayland wallpaper daemon with
native folder rotation (the closest equivalent to Budgie's
`budgie-wallstreet`), plus a small per-workspace switcher on top.

> **One rule for every user:** this installer **never fetches images** (no
> Bing timer, no proxy hacks). It only creates one source directory,
> `~/Pictures/wallpapers/`, and points wpaperd at it. **Drop your own
> images in** (or symlink a folder of them) and the daemon rotates them.
> First run seeds the directory with a few stock `/usr/share/backgrounds`
> images so there is something to look at before you add your own.

### Step 73 — the daemon + a generic config

Step 73 `cargo install`s `wpaperd` + `wpaperctl` (stripping every
`HTTP(S)_PROXY` and forcing `NO_PROXY=*` so libproxy's PAC auto-detect
can't stall the build on a dead LAN proxy — works on any network, touches
nothing in `/etc`). It writes a **generic** `~/.config/wpaperd/wallpaper.toml`:

```toml
[default]
duration        = "5m"
mode            = "fit"
sorting         = "random"
transition_time = 1000     # 1s fade

[any]
path = "/home/<you>/Pictures/wallpapers"
```

Only `[default]` + `[any]` are written — no monitor-specific blocks, so it
is correct on **any** machine (single screen, laptop, multi-monitor).
wpaperd applies `[any]` to whatever outputs actually exist.

wpaperd 1.0.1 config quirks worth knowing before you start hacking:

| Quirk | Why |
|---|---|
| Filename **must** be `wallpaper.toml` (legacy) | `place_config_file("wallpaper.toml")` runs before `place_config_file("config.toml")` in `main.rs`. |
| Section names are monitor names directly | `[eDP-1]`, `[DP-4]`, `[HDMI-A-1]` — *not* `[output.DP-4]`. The `output.` prefix is 0.x syntax. |
| No `[socket]` section | The Unix socket path is hard-coded. |
| No `transition_type` field | Only `transition_time` (ms). `transition_type` is planned upstream but not in 1.0.1. |
| `path` as a single **file** + `duration` together is refused | The validator warns and falls back to `[any]`. File-mode wallpapers don't rotate, so the switcher strips `duration` when it writes one. |

Step 73 also:
- installs wpaperd via XDG autostart (`~/.config/autostart/wpaperd-autostart.desktop`)
  so `systemd-xdg-autostart-generator(8)` mints
  `app-wpaperd\x2dautostart@autostart.service` at each session start
  (no hand-written `~/.config/systemd/user/wpaperd.service`),
- comments out `exec-once = hyprpaper` in `hyprland.conf`,
- appends `Super+Shift+W → next` / `Super+Shift+Ctrl+W → prev` to `hyprland.conf`.

### Step 74 — per-workspace rotation

`wpaperd` rotates per **monitor** — it has no concept of workspaces.
Step 74 attaches a small in-house Python listener,
[`bin/wpaperd-ws-switch.py`](bin/wpaperd-ws-switch.py), that drives the
per-workspace behaviour on top.

```
Hyprland socket2 (workspacev2>>ID,NAME)
        │
        ▼
   wpaperd-ws-switch.py ── detects focused output (hyprctl monitors -j)
        │                        │
        │  reads state[ID]        │  writes [<focused-monitor>].path = state[ID]
        │                        ▼
        └──► wpaperctl reload-wallpaper ──► wpaperd shows that image
             (background thread: every 5 min, pick a different image
              for the active workspace)
```

The engine:
- **Auto-detects the active output** on every `workspacev2` event (env
  `WPAPERD_MONITOR` overrides; else focused → internal panel → first
  monitor). Nothing is hard-coded to `eDP-1`, so it works on any laptop or
  multi-monitor rig.
- **Per-workspace memory** — each workspace's last image is kept in
  `~/.local/state/wpaperd-ws-state.json`. Switch back to a workspace and you
  see the exact image you last saw there, not a random new pick.
- **5-minute refresh** — a background thread (`WPAPERD_TIMER` to override,
  default 300 s) picks a *different* image for the active workspace; others
  stay frozen until visited.
- The `[<monitor>]` block it writes is created if missing and kept
  single-file (no `duration`), so wpaperd locks onto it instead of re-picking.

**Per-workspace distinct images are opt-in.** The listener looks for
`~/Pictures/wallpapers/ws{ID}/`; if that sub-directory exists it uses it,
otherwise it falls back to the flat `~/Pictures/wallpapers/`. So:

```bash
# Shared wallpapers for every workspace (simplest — just drop files in):
~/Pictures/wallpapers/foo.jpg

# Distinct wallpaper per workspace (opt-in — make the folders):
~/Pictures/wallpapers/ws1/
~/Pictures/wallpapers/ws2/
...
```

Plain users can ignore the `wsN/` folders entirely; users who want per-ws
images just create and fill them.

### Step 74's crash-bomb defusal (a fresh install must do this)

Step 74 also **defuses two compositor-crash time-bombs** that kill Hyprland
the moment a screen lock captures the screen. See the box below for the
full story — in short it masks `xdg-desktop-portal-hyprland.service` and
replaces `/etc/pam.d/hyprlock`.

#### The two time-bombs

**Time-bomb 1 — `xdg-desktop-portal-hyprland.service`**

Every time `hyprlock` (or the Quickshell lock plugin) reaches for the
screencopy protocol, the portal daemon SIGSEGVs in
`libwayland-client.so` and takes Hyprland down with it. This is **not** a
Hyprland bug — Arch's upstream changelog reports the same. Mask it:

```bash
systemctl --user mask xdg-desktop-portal-hyprland.service
systemctl --user stop  xdg-desktop-portal-hyprland.service
```

It's only needed by flatpak/snap apps; on a native setup the generic
`xdg-desktop-portal` still handles on-demand screen sharing.

**Time-bomb 2 — `/etc/pam.d/hyprlock`**

Debian's `common-auth` (auto-injected by `ecryptfs-utils`) contains
`auth required pam_ecryptfs.so unwrap`. On a plain (non-ecryptfs) home it
makes hyprlock treat auth as failed and crash the compositor. Replace it
with shadow-only auth:

```bash
sudo tee /etc/pam.d/hyprlock <<'EOF'
auth     required    pam_unix.so nullok
account  required    pam_unix.so
EOF
```

Step 74 ships the same content and keeps the original at
`/etc/pam.d/hyprlock.bak-omarchy-on-debian`.

**Why the bind goes through `loginctl`** — `Super+Ctrl+L` is rebound to
`loginctl lock-session` (not `omarchy-system-lock`) so the lock path
matches the 5-minute idle trigger and never touches the Portal/PAM chain
that crashes the compositor. Trade-off: you lose the Quickshell lock panel
(date + alarm icons), you gain a lock screen that doesn't kill the
compositor.

### Verifying

`./steps/71-verify.sh` prints a pass/fail table. Relevant wallpaper/lock
checks:

```
==> lock chain (step 74 time-bomb defusal)
  ok /etc/pam.d/hyprlock is the omarchy-on-debian override (pam_unix only)
  ok xdg-desktop-portal-hyprland.service is masked (no screencopy segfault)
==> wallpaper config
  ok wpaperd config is generic ([any] → ~/Pictures/wallpapers)
  ok hyprland.conf: exec-once = wpaperd (live daemon)
  ok hyprland.conf: Super+Ctrl+L → loginctl lock-session
```

### Manual controls

```bash
omarchy-wallpaper-rotate status          # daemon + current wallpaper
omarchy-wallpaper-rotate next            # next wallpaper
omarchy-wallpaper-rotate prev            # previous
omarchy-wallpaper-rotate reload          # reload after editing wallpaper.toml
omarchy-wallpaper-rotate set-folder /path # repoint the pool
omarchy-wallpaper-rotate init            # write a generic default wallpaper.toml

wpaperctl get-wallpaper <monitor>        # e.g. run `hyprctl monitors -j` for names
wpaperctl reload-wallpaper               # reload (single-file mode → no re-pick)
tail -f /tmp/wpaperd-ws-switch.log       # switcher + timer log
WPAPERD_TIMER=30 python3 ~/bin/wpaperd-ws-switch.py   # override 5-min timer (testing)
```

### Why we abandoned `hyprpaper` entirely

Both Debian `0.8.4-1~bpo13+1` (GCC 14) **and** Arch `0.8.4-8` (GCC 16)
fail to render on this Hyprland stack: the Arch binary accepts IPC and
replies `ok` but never connects to the live Wayland socket (`wl_display_connect`
silently never returns); the Debian one SIGSEGVs earlier (use-after-free in
image swap). Either way the desktop stays a flat panel colour. `wpaperd`
connects cleanly and is the right long-term answer; the per-workspace layer
lives in the in-house switcher that step 74 ships.

## The patches (the actual port)

| Patch                                 | Symptom without it                                | Cause                                                                                              |
| ------------------------------------- | ------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| `001-notifications-isTransient.patch` | Notifications panel throws / notifications vanish | `transient` is a reserved word in Qt 6.8 QML                                                       |
| `002-menu-timezone-pkexec.patch`      | Timezone menu entry silently does nothing         | `sudo` in a detached process has no tty; upstream assumes an askpass                               |
| `003-clock-barwidget-zh.patch`        | Bar date blank                                    | `Qt.formatDateTime(date, fmt, locale)` — this Qt build refuses QLocale args from QML JS and throws |
| `004-clock-panel-zh.patch`            | Month header + hero date English                  | same, plus hardcoded `en_US` weekday locale                                                        |
| `extras/clock-zh/Model.js`            | —                                                 | Full replacement: adds lunar calendar, 24 solar terms, Chinese festivals                           |

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

## Top bar stays above fullscreen windows

The upstream Omarchy 4 (Quattro) Quickshell bar (`Bar.qml`, namespace
`omarchy-bar`) binds itself to `WlrLayer.Top` — Hyprland layer level 2. The
**only** layer drawn above fullscreen windows is `WlrLayer.Overlay` (level 3),
so pressing Super+F (any `dispatch fullscreen 1` path) hides the bar.

`steps/70-bar-overlay.sh` rewrites the bar's layer assignment from `Top` to
`Overlay`. After running it you must reload Quickshell for the change to
take effect — `qs kill --path ~/.local/share/omarchy/shell`, then
`~/.local/bin/omarchy-port &` (or just log out and back in). Hyprland does
**not** need a reload.

Verify the fix with `hyprctl layers` — `namespace: omarchy-bar` should appear
under `Layer level 3 (overlay)`, not `Layer level 2 (top)`.

Re-running `steps/30-deploy.sh` (e.g. after a `git pull` of omarchy-src)
overwrites `Bar.qml` with upstream defaults. Re-apply this patch by running
`bash steps/70-bar-overlay.sh` again — the marker comment makes it
idempotent.

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for the failure modes that cost
the most time — including the Quickshell crash-restart env-var trap.

## Show desktop (Super+D) — port feature

Hyprland has no native window-minimize concept, so upstream Omarchy has no
"show desktop" command. This port adds one:

- **Bin**: `bin/omarchy-show-desktop` (Bash + `jq` + `hyprctl`).
- **Bind**: `bind = $mainMod, D, exec, omarchy-show-desktop` (injected by
  `steps/69-show-desktop.sh`). Super+D was unbound in the official layout.
- **Toggle**: first press hides every non-pinned, non-fullscreen, mapped
  window on the **active** workspace into Hyprland's `special:hidden`
  scratchpad. Press again to restore the exact same set to their original
  workspaces.
- **State**: `$XDG_STATE_HOME/omarchy/show-desktop.json` (default
  `~/.local/state/omarchy/show-desktop.json`). Defensive on restore: an
  address is only moved back if it is *currently* still parked on
  `special:hidden`, so stale state (closed window, session reset) is
  silently skipped.
- **Dependencies**: `jq` and `libnotify` (for `notify-send`). Both ship
  in Debian's base; `steps/69` warns if either is missing.

### Hyprland 0.55.2 caveats this script handles

- `activeworkspace -j` and `monitors -j`'s `activeWorkspace` return
  sentinels (`id=-1337, name="active"`) and **cannot** be trusted to give
  the real active workspace. The script derives it from `clients -j` by
  taking the window with the smallest `focusHistoryID`.
- `movetoworksilent special:hidden` is rejected by 0.55.2 with
  `Invalid dispatcher` (only `movetoworkspace special:hidden` works). The
  script uses the non-silent variant and restores focus to the workspace
  afterwards.
- `togglespecialworkspace hidden` on 0.55.2 does **not** automatically
  move the focused window into the special workspace — it just shows or
  hides that workspace. So we move windows explicitly via `movetoworkspace`.

## Package management (apt, not pacman)

The Omarchy menu drives every package install / remove through five core
scripts. The Debian port re-implements all five against `apt` /
`apt-cache` / `dpkg-query` / `apt-mark` without touching any of the 90+
app-specific wrappers (`omarchy-install-spotify`,
`omarchy-remove-brave`, etc.) — they all call `omarchy-pkg-add` /
`omarchy-pkg-drop`, whose public interface is unchanged.

| Upstream (pacman / yay) | Debian port (apt) | Role                                                                  |
|-------------------------|-------------------|-----------------------------------------------------------------------|
| `omarchy-pkg-install`   | apt-cache / fzf   | TUI: list every installable package → `apt-get install -y`            |
| `omarchy-pkg-remove`    | apt-mark / fzf    | TUI: list manually-installed packages → `apt-get remove --purge -y`   |
| `omarchy-pkg-add`       | apt-get           | Idempotent installer (`<pkg...>`)                                     |
| `omarchy-pkg-drop`      | apt-get           | Idempotent remover  (`<pkg...>`)                                      |
| `omarchy-pkg-missing`   | dpkg-query        | Predicate: 0 if any `<pkg...>` is not installed                       |

Debian-specific choices:

- `apt-cache pkgnames` ↔ `pacman -Slq` (list every available package).
  Comes from **apt-utils**, which Debian does not install by default; the
  port ensures it via `steps/68-pkg-apt.sh`.
- `apt-cache show` ↔ `pacman -Sii` (TUI preview). About 8× faster than
  `apt show` on a populated cache and works offline.
- `apt-mark showmanual` ↔ `yay -Qqe` (manually installed set, exclude
  auto-pulled dependencies). Ships with `apt`, no extra package needed.
- `dpkg-query -f='${Package}\n' -W` ↔ `pacman -Qq` (total installed set).
- `apt-get install` is already idempotent (no `--needed`-equivalent flag).
- `apt-get remove --purge -y` ↔ `pacman -Rns`. Drop `--purge` to match
  `pacman -R` and keep `/etc` configurations across a removal.

If you want to roll a single host back to the upstream (pacman) scripts
manually, `steps/68` saves them to
`~/.local/share/omarchy/bin/.bak-20260906-pacman/` the first time it runs.

## Debian keybinding gaps (official shortcuts that need extra commands)

The shipped `~/.config/hypr/hyprland.conf` mirrors Omarchy's official  
keybindings (from `omarchy-src/manual/07-hotkeys.md`). Most work out of the  
box because the `omarchy-*` scripts live in `~/.local/share/omarchy/bin`, which  
the config prepends to Hyprland's PATH (`env = PATH, …`). A few shortcuts still  
need extra commands Debian does not install by default — listed below, each  
with the one-line install that closes the gap.


### Missing system tools

| Shortcut(s)                                                                           | Function                                                                    | Missing command                                                                       | Install to fix                                                        |
| ------------------------------------------------------------------------------------- | --------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- | --------------------------------------------------------------------- |
| `XF86MonBrightnessUp/Down`, `Shift`+…, `Alt`+… ; `XF86KbdBrightness*`                 | Screen / keyboard backlight                                                 | `brightnessctl` (or `light`)                                                          | `apt install brightnessctl`                                           |
| `XF86AudioNext/Prev/Play/Pause`, `Alt`+`XF86AudioPlay`, `Shift`+`XF86AudioPlay/Pause` | Media playback / source switch                                              | `playerctl`                                                                           | `apt install playerctl`                                               |
| `Super+Ctrl+V`                                                                        | Clipboard manager (history)                                                 | `cliphist`                                                                            | `apt install cliphist`                                                |
| `Super+C` / `Super+V` / `Super+X`                                                     | Universal copy / paste / cut (injects `Ctrl+C/V/X` into the focused window) | `wtype` (or `ydotool`)                                                                | `apt install wtype`                                                   |
| `Super+Print`                                                                         | Color picker                                                                | `hyprpicker`                                                                          | `apt install hyprpicker` (trixie-backports)                           |
| `Super+Ctrl+Print`                                                                    | OCR text extraction to clipboard                                            | `tesseract` is **installed** but its language data (`tessdata`) is **missing**        | `apt install tesseract-ocr-eng` (or `tessdata-*` for other languages) |
| `Alt+Print`                                                                           | Screen recording                                                            | `wf-recorder`                                                                         | `apt install wf-recorder`                                             |
| `Super+Ctrl+Q`, `XF86Calculator`                                                      | Calculator                                                                  | `qalc` is required; the `omacalc` wrapper is shipped by this port (steps/66)         | `apt install qalc`; also `apt install rofi` for the UI               |
| `Super+Print` (copy to clipboard)                                                     | Screenshot → clipboard                                                      | `wl-clipboard` (`wl-copy`)                                                            | `apt install wl-clipboard`                                            |

Until installed, pressing these does nothing (the `omarchy-*` wrapper runs but  
its backend binary is absent). Volume keys (`XF86AudioRaise/Lower/Mute`) work  
without `playerctl` — they go through `omarchy-audio-output-volume` → `wpctl`,  
which is present.

**Calculator (port patch):** upstream ships `omacalc` as a Qt/QML AUR
package. On Debian we install `qalc` and drop a rofi-based wrapper into
`~/.local/share/omarchy/bin/omacalc` (steps/66). It's functional but
plain — open the right-corner control panel and you will see a
`Super+Ctrl+Q` calc picker; pressing it copies the result of the
expression you type. For a button-based GUI equivalent, install a
Qt calculator (`apt install qalculate-gtk`) and point the bind at it.

**Monitor scale (port patch):** the right-corner scale widget and the
keyboard scale shortcuts go through `omarchy-hyprland-monitor-scaling`,
which calls `hyprctl eval "hl.monitor({...})"`. `hyprctl eval` is a
silent no-op on a plain `hyprland.conf` — it only works under the Lua
config manager used by upstream Omarchy. On this port the click looked
successful but nothing happened. steps/67 patches the script to try
`hyprctl keyword monitor` first (works on both Lua and plain configs)
and fall back to `eval` for Lua-only hosts.


### Missing applications (the launch script exists; the app does not)

| Shortcut             | Function              | App                     | How to install                                          |
| -------------------- | --------------------- | ----------------------- | ------------------------------------------------------- |
| `Super+Shift+M`      | Music (Spotify)       | `spotify`               | Flatpak / spotify.com `.deb`                            |
| `Super+Shift+Alt+M`  | Music TUI (cliamp)    | `cliamp`                | not packaged; build from source                         |
| `Super+Shift+G`      | Messenger (Signal)    | `signal-desktop`        | signal.org `.deb` or Flatpak                            |
| `Super+Shift+D`      | Docker (LazyDocker)   | `lazydocker`            | `go install github.com/jesseduffield/lazydocker@latest` |
| `Super+Shift+/`      | Passwords (1Password) | `1password`             | 1password.com `.deb`                                    |
| `Super+Shift+W`      | Writing (Omawrite)    | `omawrite`              | not packaged                                            |
| `Super+Shift+Ctrl+A` | Pick an AI agent      | `omarchy-agent` backend | needs the agent configured                              |

Web-app shortcuts (`Super+Shift+A` ChatGPT, `Super+Shift+C/E` HEY calendar/email,  
`Super+Shift+Y` YouTube, `Super+Shift+X` / `X Compose`, `Super+Shift+G` /  
`Alt+G` / `Shift+Ctrl+G` WhatsApp / Google Messages, `Super+Shift+P` Photos,  
`Super+Shift+S` Maps) **do work** — they open the URL in your browser via  
`omarchy-launch-or-focus-webapp`. They only fail if no browser is installed.

### Omarchy-Lua-only features with no native equivalent

- **Cursor zoom** (`Super+Ctrl+Z` / `Super+Ctrl+Alt+Z`): Omarchy sets  
  `cursor.zoom_factor` through its Lua engine. There is no native Hyprland bind,  
  so these are intentionally not mapped.
- **Jump to a specific window inside a group** (`Super+Alt+1..5`): native  
  Hyprland has no per-index group navigation, so these are bound to cycle  
  forward (`changegroupactive f`) as an approximation.

### Hyprland-build deviations (Debian Hyprland 0.55.2)

Two official dispatchers are not dispatchable on this Hyprland build, so the  
config maps them to the closest working form:

- **`Super+J`** (toggle split): official `togglesplit` is not a callable  
  dispatcher here → mapped to `layoutmsg, togglesplit` (comma-separated; a  
  space makes Hyprland treat the whole string as one dispatcher name).
- **Move-to-scratchpad without following** (`Super+Alt+S` / `Super+Shift+\``):
  official `movetoworkspace silent special:scratchpad`is invalid here → mapped
  to`movetoworkspacesilent special:scratchpad\`.
- **Move to workspace without following** (`Super+Shift+Alt+1..0`): same →  
  `movetoworkspacesilent <n>`.

## Upstream

Omarchy: <https://github.com/omacom/omarchy> (branch `quattro`).  
This repo ships no Omarchy code of its own beyond patches — it is a port kit.
