# VAD/OS Files

This project is built on VAS (VADOS APPLICATION SYSTEMS), base register. Read `.claude/skills/vas/SKILL.md`.

A file manager for Hyprland on Arch. Qt 6 (QML + C++), CMake. VAS is the source of truth for how it looks, moves and reads; this file holds what is particular to this project.

## Commands

```bash
cmake -B build -G Ninja && cmake --build build      # build
./build/vados-files [path]                          # run
QT_FORCE_STDERR_LOGGING=1 ./build/vados-files       # see QML warnings (Qt logs to journald otherwise)
VADOS_REHEARSAL=/path/to/script.qml ./build/vados-files   # scripted run: drives the window, saves frames
scripts/install.sh [--default]                      # install to ~/.local; --default makes it open folders
scripts/fetch-fonts.sh                              # Space Mono + Audiowide into assets/fonts
```

Before reading VAS, `git -C .claude/skills/vas fetch && git -C .claude/skills/vas status -sb` and pull if behind.

## Layout

| Path | Holds |
|---|---|
| `src/core/` | C++: `FolderModel` (async listing, diffed refresh, selection, search, trash), `FileOperations` (jobs, conflicts, undo), `PlacesModel` (the room registry: XDG dirs, GTK bookmarks, drives via lsblk/udisksctl), `System` (launching, clipboard, drag out, file facts), image providers (freedesktop thumbnail cache, re-inked glyphs), `Settings` |
| `qml/design/` | `Theme` and `Motion` — VAS's `core/design`. **The only place a colour, a face, a size, a curve or a duration is written down.** |
| `qml/ui/` | VAS primitives: `Squircle` (the surface shader), `Module`, `Reveal` (bar sweep), `Glyph`, `FadeText`, `Slices`, `GooStepSlider`, `MenuSheet`, `Pill`, `IconButton` |
| `qml/feature/` | `Workspace` (the one command funnel, drag and drop, rooms, launch), `FolderPane`, `FileTile`/`FileRow`, the sidebar, toolbar, overlays |
| `shaders/` | `squircle`, `squircleImage`, `gooRail`, `fadeEdge`, `glyphInk` |

## Decisions

- **Register: base**, at the tool tempo VAD/OS TERMINAL set: navigation leaves in 130ms and enters in 260ms with a positional stagger; nothing in the folder view passes 0.3s. The launch is the one full-tempo moment.
- **A place is a room; a pin is a shortcut.** `PlacesModel` keeps the rooms (HOME, XDG folders, SYSTEM, TRASH, drives), each with an accent (`Theme.placeAccents`); a folder takes the accent of the deepest room containing it. The sidebar shows the user's **pins** (ordered, renamable, with an icon from `PlacesModel.iconChoices`), stored as JSON under `pins` in `~/.config/vados/files.conf` and seeded on first run from the rooms plus GTK bookmarks. A pin is coloured by its room. The accent changes on the cut. No background slices (removed at the user's request).
- **The scale lever reads the screen, not the window** (`Theme.rem`), so a tiled half-width window keeps its type size.
- **Squircle everywhere** via `shaders/squircle.frag` (superellipse, exponent 4). Never a `Rectangle { radius }` for a box; a `Rectangle` is only for hairlines, bars and fills inside a squircle.
- **Trashing is immediate, as on Windows** (Delete key, menu, drag to trash) and offers undo; only permanent deletes and emptying the trash wait on CONFIRM. Every reversible change offers undo (`FileOperations` keeps the stack).
- **Drop actions follow Windows:** Ctrl copies, Shift moves, Ctrl+Shift links; no key moves on one drive and copies across drives. The target performs the operation; the drag source never deletes.
- **One binary, three roles.** Plain run: the window. `--file-manager-service`: `org.freedesktop.FileManager1` ("show in folder"). `--portal-service`: `org.freedesktop.impl.portal.FileChooser`, the backend xdg-desktop-portal asks for every app's open/save dialog. Each portal request runs the binary again with `--pick <json>`; `Picker` (C++ singleton) holds the request, `PickerBar` is the band under the folder, `Workspace.pick` is the accept, and the answer leaves on stdout (`filter N`, then one URI per line); quitting without one is a cancel. Test a picker headless with `QT_QPA_PLATFORM=offscreen ./build-release/vados-files --pick '{"mode":"open","folder":"/tmp"}'`.
- **D-Bus service files carry the binary's full path.** Activation goes through systemd, which does not search `~/.local/bin`; `install.sh` rewrites `Exec=` after installing.
- **Loading is split from showing:** `FolderModel.load` reads while the old folder leaves, `commit` swaps rows in after. A refresh diffs, so the views animate inserts and removals instead of resetting.

## Traps already hit

- `workspace: workspace` (or `pane: pane`, `list: list`) inside a child that has a property of that name binds the property to itself. Hand children `workspaceItem` / `paneItem`, and name such properties distinctly (`pinList`).
- An element `id` that matches a property name (`id: icon` next to `required property string icon`) shadows the property inside the component.
- `QSettings()` with no arguments writes to `~/.config/vados/VAD/OS Files.conf` (the slash in the app name). Always open `QSettings("vados", "files")`.
- An overlay whose `visible` is bound to a child's `visible` never opens: a child of a hidden item reports itself hidden. Bind to the child's `opacity`.
- `grabToImage` frames carry alpha; composite over `#181818` before judging colours in them.

## New for VAS — candidates not yet promoted

Raised at the end of the turn that produced them; promote via `.claude/skills/vas/MAINTAINING.md` only when the user says yes.

- The squircle surface as one fragment shader with hairline, inset ring and hue ring (Qt Quick).
- The goo step slider as a smooth union of distance fields instead of blur-and-threshold.
- Rooms: per-place accents for a tool with no screens.
- The screen-width scale lever for desktop windows.
