#!/usr/bin/env bash
# Builds a release and installs it for the current user: the binary to ~/.local/bin, the launcher entry to ~/.local/share/applications.
# Set VADOS_APPS=/some/dir to put the binary there instead of ~/.local/bin (the launcher entry then points at it).
# Pass --default to also make it the file manager every app opens folders with (inode/directory) and the file picker every app asks through the portal.
set -euo pipefail
cd "$(dirname "$0")/.."
cmake -B build-release -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build-release
cmake --install build-release --prefix "$HOME/.local"
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
if [[ "${1:-}" == "--default" ]]; then
    xdg-mime default vados-files.desktop inode/directory
    echo "VAD/OS Files now opens folders."
fi
if [[ -n "${VADOS_APPS:-}" ]]; then
    mkdir -p "$VADOS_APPS"
    install -m755 build-release/vados-files "$VADOS_APPS/vados-files"
    sed "s|^Exec=vados-files|Exec=$VADOS_APPS/vados-files|" packaging/vados-files.desktop > "$HOME/.local/share/applications/vados-files.desktop"
    echo "Installed to $VADOS_APPS/vados-files"
else
    echo "Installed to $HOME/.local/bin/vados-files"
fi
# D-Bus activation goes through systemd, which does not search ~/.local/bin; the service files name the binary by its full path.
binary="${VADOS_APPS:-$HOME/.local/bin}/vados-files"
for service in org.freedesktop.FileManager1 org.freedesktop.impl.portal.desktop.vados; do
    sed -i "s|^Exec=vados-files|Exec=$binary|" "$HOME/.local/share/dbus-1/services/$service.service"
done
if [[ "${1:-}" == "--default" ]]; then
    desktop="${XDG_CURRENT_DESKTOP:-Hyprland}"
    config="$HOME/.config/xdg-desktop-portal/${desktop,,}-portals.conf"
    mkdir -p "$(dirname "$config")"
    if [[ ! -f "$config" ]]; then
        system="/usr/share/xdg-desktop-portal/${desktop,,}-portals.conf"
        if [[ -f "$system" ]]; then cp "$system" "$config"; else printf '[preferred]\ndefault=gtk\n' > "$config"; fi
    fi
    sed -i '/^org.freedesktop.impl.portal.FileChooser=/d' "$config"
    sed -i '/^\[preferred\]/a org.freedesktop.impl.portal.FileChooser=vados' "$config"
    systemctl --user restart xdg-desktop-portal.service 2>/dev/null || true
    echo "VAD/OS Files now picks files for every app that asks through the portal ($config)."
fi
