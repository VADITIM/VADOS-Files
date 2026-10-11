# Quirks

- **A property binds to itself, or reads as undefined.** `workspace: workspace` (or `pane: pane`, `list: list`) inside a child that has a property of that name binds the property to itself. Hand children `workspaceItem` / `paneItem`, and name such properties distinctly (`pinList`).
- **A property is shadowed inside its own component.** An element `id` that matches a property name (`id: icon` next to `required property string icon`) shadows the property.
- **Settings land in a strange file.** `QSettings()` with no arguments writes to `~/.config/vados/VAD/OS Files.conf` (the slash in the app name). Always open `QSettings("vados", "files")`.
- **An overlay never opens.** Its `visible` is bound to a child's `visible`; a child of a hidden item reports itself hidden. Bind to the child's `opacity`.
- **Captured frames look wrong in colour.** `grabToImage` frames carry alpha; composite over `#181818` before judging colours in them.
- **The window is narrower than `minimumWidth`.** Hyprland ignores it, so nothing may assume one.
- **"Show in folder" or the file dialog does not start the app.** D-Bus activation goes through systemd, which does not search `~/.local/bin`; the service files need the full path (`decisions.md`).
