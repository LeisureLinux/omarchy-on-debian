# omarchy-on-debian

Run the **Omarchy 4 (Quattro) shell** — the Quickshell UI from the Arch-based
Omarchy distro — on **Debian 13 (trixie) + Hyprland**.

The shell itself is portable: 2 MB of QML/JS plugins that shell out to ~90
`omarchy-*` bash scripts. What is *not* portable is everything around it —
Arch session tooling, the package set, the icon font, and a couple of Qt
version quirks. This repo is that gap, packaged as numbered, idempotent steps.

Tested on: Debian 13.6, Hyprland 0.55.2 (bpo13), Quickshell 0.3.0 (bpo13), Qt 6.8.2.

```
git clone https://github.com/<you>/omarchy-on-debian
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
| 60 | `steps/60-hyprland.sh` | Autostart, menu key, minimised-window workspace. |
| 70 | `steps/70-verify.sh` | Health checks + a lunar-table spot check. |

Steps are standalone: `./install.sh --only 40` re-applies patches after an
upstream refresh. Backups of anything overwritten land in
`~/.local/share/omarchy/.omarchy-on-debian/backups/`.

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

## Layout

```
install.sh          orchestrator (--dry-run / --only N / --src PATH)
lib/common.sh       logging, backup-on-overwrite, guarded file append
steps/1x..7x        the numbered steps
patches/            unified diffs against upstream, applied with -p1 in ~/.local/share/omarchy
dotfiles/           omarchy-port, omarchy-menu-toggle, uwsm-app, fontconfig, hypr snippet
extras/clock-zh/    replacement Model.js + table generators
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
