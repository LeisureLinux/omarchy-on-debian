# wpaperd → deb via rust-crate-deb template

`wpaperd` is a Wayland wallpaper daemon with **native folder
rotation** — the closest equivalent to Budgie's `budgie-wallstreet`.

Debian trixie does **not** carry it. We build it here with the
generic `rust-crate-deb` template, then host the result on
repo.freelamp.com.

## Build

```bash
cd packaging/wpaperd
bash ../rust-crate-deb/build.sh
```

Or with explicit knobs (CI friendly):

```bash
CRATE=wpaperd VERSION=1.0.1 \
  CRATE_BIN=wpaperd \
  DESCRIPTION="Wayland wallpaper daemon with timed rotation" \
  HOMEPAGE="https://github.com/an-anonymous-coder/wpaperd" \
  LICENSE=MIT \
  DEPS='libwayland-client0,libwayland-cursor0,libdbus-1-3' \
  EXTRA_BINS=wpaperctl \
  bash ../rust-crate-deb/build.sh
```

Output:
`packaging/wpaperd/build/wpaperd_1.0.1_amd64.deb`

## Local install (skip freelamp, for development)

```bash
sudo dpkg -i build/wpaperd_1.0.1_amd64.deb
```

## Pushing to repo.freelamp.com

```bash
PUSH=1 bash ../rust-crate-deb/build.sh
```

## Runtime dependencies

| Library                | Debian package          |
|------------------------|-------------------------|
| libwayland client      | `libwayland-client0`    |
| libwayland cursor      | `libwayland-cursor0`    |
| D-Bus                  | `libdbus-1-3`           |
| systemd user bus       | `libsystemd0`           |
| image decoding         | `libpng16-16`, `libjpeg62-turbo` |

(Check `ldd target/release/wpaperd` for the actual list at build time.)

## Why not just `cargo install`?

`cargo install` works fine on one machine but leaves nothing
declarative. Once you want `apt-mark showmanual` / `omarchy-update`
/ `omarchy-remove-preinstalls` to manage it, you need an apt
package. fpm template is ~70 lines and reusable.
