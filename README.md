[![GNOME](https://img.shields.io/badge/GNOME-50-blue?style=plastic&logo=gnome)](https://wiki.archlinux.org/title/GNOME)
[![Zig](https://img.shields.io/badge/dynamic/regex?url=https%3A%2F%2Fraw.githubusercontent.com%2Fvncsmyrnk%2Fgwin%2Frefs%2Fheads%2Fmain%2Fbuild.zig.zon&search=%5C.minimum_zig_version%20%3D%20%22(.*)%22&replace=%241&style=plastic&logo=zig&label=Zig&color=F7A41D)](https://ziglang.org/)
[![AUR Version](https://img.shields.io/aur/version/gwin-git?style=plastic&label=AUR&logo=archlinux)](https://aur.archlinux.org/packages/gwin-git)
[![APT Version](https://img.shields.io/badge/dynamic/regex?url=https%3A%2F%2Fapt.fury.io%2Fvncsmyrnk%2FPackages&search=.*Filename%3A%20.*%2Fgwin_(%5Ba-z0-9%5C.%5C%2B%5D*)_&replace=%241&flags=s&style=plastic&logo=debian&label=apt&color=d70a53)](https://repo.fury.io/vncsmyrnk/)
<br>
[![CI workflow](https://github.com/vncsmyrnk/gwin/actions/workflows/ci.yml/badge.svg)](https://github.com/vncsmyrnk/gwin/actions/workflows/ci.yml)
[![contributions](https://img.shields.io/badge/contributions-welcome-brightgreen?labelColor=384047&color=33cb56)](https://github.com/vncsmyrnk/shell-utils/issues)

# gwin

A "Run or raise" CLI tool for Wayland GNOME, leveraging the [window-calls extension](https://github.com/ickyicky/window-calls) D-Bus interface for opened windows.

## Context

GNOME's Wayland implementation does not support native ways to securely access window lists due to security risks. If you want to use a custom _dmenu_ tool or have special bindings for switching between opened windows, the only solution to achieve this until now is using Mutter to fetch the windows state via an extension.

Fortunately, this extension already exists: [window-calls extension](https://github.com/ickyicky/window-calls). It also export this state over D-Bus, making it possible to view and manipulate it.

## Goal

This project aims to provide ways to open currently opened instances or launch new ones when there is no instance already opened. GNOME's default finder already achieves this but offers minimal customization and GNOME itself does not offer native ways to use external _dmenus_ like `rofi`.

The primary goal is to provide useful, predefined and optimized use cases for switching between opened windows via `window-calls` and its D-Bus interface, avoiding the overhead of connections and fragile parsing when using multi-purpose D-Bus tools like `bustcl`.

### Secondary goals

- Provide a list of opened windows and ways to switch to them via _dmenus_
- Provide a list of installed applications and ways to run or raise them via _dmenus_

> [!NOTE]
> **Why Zig?** It can directly import C bindings for GDBus, already included as part of GNOME project's GLib (`gio/gdbus`).

## Examples

### Switching to opening windows using `rofi`

```sh
gwin list windows --rofi | rofi -x11 -normal-window -dmenu | xargs -I{} gwin switch --id {}
```

### Running or raising applications using `rofi`

```sh
gwin list applications --rofi | rofi -x11 -normal-window -dmenu | xargs -I{} gwin raise {}
```

## Install

### AUR

Install it with your favorite AUR helper.

```sh
yay -S gwin-git
```

### APT (Debian and its derivatives)

```sh
echo "deb [trusted=yes] https://apt.fury.io/vncsmyrnk /" | sudo tee /etc/apt/sources.list.d/fury.list
sudo apt update && sudo apt install gwin
```

### From source

```sh
git clone git@github.com:vncsmyrnk/gwin.git
just build
./zig-out/bin/gwin
```

> [!IMPORTANT]
> Make sure to have the [window-calls extension](https://github.com/ickyicky/window-calls) installed before running `gwin`. Restart the GNOME session after installing the extension.

## Roadmap and new features

Check out [issues](https://github.com/vncsmyrnk/gwin/issues) for upcoming changes or bug fixes.
