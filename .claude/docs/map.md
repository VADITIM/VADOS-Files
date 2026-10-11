# Map

| Path | Holds |
|---|---|
| `src/core/` | C++: `FolderModel` (async listing, diffed refresh, selection, search, trash), `FileOperations` (jobs, conflicts, undo), `PlacesModel` (the room registry: XDG dirs, GTK bookmarks, drives via lsblk/udisksctl), `System` (launching, clipboard, drag out, file facts), image providers (freedesktop thumbnail cache, re-inked glyphs), `Settings` |
| `qml/design/` | `Theme` and `Motion` — V/AS's `core/design` |
| `qml/ui/` | V/AS primitives: `Squircle` (the surface shader), `Module`, `Reveal` (bar sweep), `Glyph`, `FadeText`, `Slices`, `GooStepSlider`, `MenuSheet`, `Pill`, `IconButton` |
| `qml/feature/` | `Workspace` (the one command funnel, drag and drop, rooms, launch), `FolderPane`, `FileTile`/`FileRow`, the sidebar, toolbar, overlays |
| `shaders/` | `squircle`, `squircleImage`, `gooRail`, `fadeEdge`, `glyphInk` |
| `packaging/` | Desktop entry, D-Bus service files, portal registration |
| `scripts/` | `install.sh`, `fetch-fonts.sh`, `make-icon.py` |
| `assets/` | Glyphs, fonts, icon |
| `docs/` | `preview.png` for the README (not agent docs) |
| `.claude/skills/default-file-manager/` | Skill: make this the default file manager on this machine |

Entry points: window `qml/Main.qml`; services and picker are roles of the one binary (`architecture.md`).
