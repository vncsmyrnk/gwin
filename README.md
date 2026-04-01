![GNOME](https://img.shields.io/badge/GNOME-black?style=plastic&logo=gnome)
![Zig](https://img.shields.io/badge/Zig-F7A41D?style=plastic&logo=zig)
![AUR Version](https://img.shields.io/aur/version/gnome-window-calls-git)
[![contributions](https://img.shields.io/badge/contributions-welcome-brightgreen.svg?style=flat)](https://github.com/vncsmyrnk/shell-utils/issues)

# GNOME Window Calls D-Bus client

A D-Bus client utility for GNOME Wayland window management, leveraging the [window-calls extension](https://github.com/ickyicky/window-calls).

## Context

GNOME's Wayland implementation does not support native ways to securely access window lists due to security risks. The only solution to achieve this until now is using Mutter to fetch the windows state via an extension.

Fortunately, this extension already exists: [window-calls extension](https://github.com/ickyicky/window-calls). It also export this state over D-Bus, making it possible to view and manipulate it.

## Goal

This project aims to provide useful, predefined and optimized use cases for this extension, avoiding the overhead of connections and fragile parsing when using multi-purpose D-Bus tools like `bustcl`.

**Why Zig?** It can directly import C bindings for GDBus, already included as part of GNOME project's GLib (`gio/gdbus`).

### Secondary goals

- Provide a listing of opened windows and switch to them using `rofi`

## Install

### AUR

Install it with your favorite AUR helper.

```sh
yay -S gnome-window-calls
```

### From source

```sh
git clone git@github.com:vncsmyrnk/gnome-window-calls.git
just build
./zig-out/bin/gwc
```
