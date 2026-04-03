![GNOME](https://img.shields.io/badge/GNOME-black?style=plastic&logo=gnome)
![Zig](https://img.shields.io/badge/Zig-F7A41D?style=plastic&logo=zig)
![AUR Version](https://img.shields.io/aur/version/gwin-git?style=plastic&label=AUR)
[![CI workflow](https://github.com/vncsmyrnk/gwin/actions/workflows/ci.yml/badge.svg)](https://github.com/vncsmyrnk/gwin/actions/workflows/ci.yml)
[![contributions](https://img.shields.io/badge/contributions-welcome-brightgreen.svg?style=flat)](https://github.com/vncsmyrnk/shell-utils/issues)

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

### Switching to opening windows via `rofi`

```sh
gwin list windows --rofi | rofi -x11 -normal-window -dmenu | xargs -I{} gwin switch {}
```

### Running or raising applications

```sh
gwin list applications --rofi | rofi -x11 -normal-window -dmenu | xargs -I{} gwin raise {}
```

## Install

### AUR

Install it with your favorite AUR helper.

```sh
yay -S gwin-git
```

### From source

```sh
git clone git@github.com:vncsmyrnk/gwin.git
just build
./zig-out/bin/gwin
```

## Roadmap and new features

Check out [issues](https://github.com/vncsmyrnk/gwin/issues) for upcoming changes or bug fixes.
