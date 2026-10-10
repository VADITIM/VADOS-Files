---
name: default-file-manager
description: Make VAD/OS Files the default file manager everywhere on this machine (Arch, Hyprland). Load when asked to set it as default, to re-apply that after a reinstall, or to debug why Nemo/Thunar still opens.
---

# VAD/OS Files as the default, everywhere

Installed binary: `/home/vn/Apps/vados-files`. Four places decide who opens a folder; all four must point at it.

## 1. Install and set the defaults

```bash
VADOS_APPS=/home/vn/Apps scripts/install.sh --default
```

This builds a release, installs it, and:

- `xdg-mime default vados-files.desktop inode/directory` (apps opening a folder)
- rewrites `~/.local/share/dbus-1/services/org.freedesktop.FileManager1.service` (the "show in folder" service) with the binary's full path, because D-Bus activation goes through systemd, which does not search `~/.local/bin`
- installs the portal backend (`org.freedesktop.impl.portal.desktop.vados`) and sets `org.freedesktop.impl.portal.FileChooser=vados` under `[preferred]` in `~/.config/xdg-desktop-portal/hyprland-portals.conf` (every app's open/save dialog), then restarts `xdg-desktop-portal`

## 2. Hyprland keybinds (Lua config)

- `~/.config/hypr/variables.lua`: `fileExplorer = "/home/vn/Apps/vados-files"`
- `~/.config/caelestia/hypr-vars.lua` overrides the above (loaded by `hyprland.lua` via `require("hypr-vars")`); set the same value there too, or SUPER + E keeps opening the old one
- `~/.config/caelestia/hypr-user.lua`: `hl.bind("SUPER + ALT + E", run("/home/vn/Apps/vados-files"))`, and add `"vados-files"` to the float/1200x800/center window-rule loop (the window class is `vados-files`)
- `hyprctl reload`

## 3. Verify

```bash
xdg-mime query default inode/directory                       # vados-files.desktop
busctl --user status org.freedesktop.FileManager1 | grep Comm  # Comm=vados-files
grep FileChooser ~/.config/xdg-desktop-portal/hyprland-portals.conf
```

If FileManager1 is still Nemo or Thunar, the `/usr/share/dbus-1/services/*.FileManager1.service` files win when the user one is missing; reinstall, then `busctl --user` again (a running owner keeps the name until it quits).

## Not touched

Nemo and Thunar stay installed; other packages may depend on them.
