# Decisions

## 2026-10-10

- **Register: base**, at the tool tempo VAD/OS TERMINAL set: navigation leaves in 130ms and enters in 260ms with a positional stagger; nothing in the folder view passes 0.3s. The launch is the one full-tempo moment.
- **A place is a room; a pin is a shortcut.** `PlacesModel` keeps the rooms (HOME, XDG folders, SYSTEM, TRASH, drives), each with an accent (`Theme.placeAccents`); a folder takes the accent of the deepest room containing it. The sidebar shows the user's **pins** (ordered, renamable, with an icon from `PlacesModel.iconChoices`), seeded on first run from the rooms plus GTK bookmarks. A pin is coloured by its room. The accent changes on the cut. No background slices (removed at the user's request).
- **The scale lever reads the screen, not the window** (`Theme.rem`), so a tiled half-width window keeps its type size.
- **Trashing is immediate, as on Windows** (Delete key, menu, drag to trash) and offers undo; only permanent deletes and emptying the trash wait on CONFIRM.
- **Drop actions follow Windows:** Ctrl copies, Shift moves, Ctrl+Shift links; no key moves on one drive and copies across drives.
- **D-Bus service files carry the binary's full path.** Activation goes through systemd, which does not search `~/.local/bin`; `install.sh` rewrites `Exec=` after installing.

## 2026-10-11

- **The details list's columns** (`FolderPane.columnCatalogue`): sortable header, dividers dragged to resize, right-click to choose; widths and choices persist as JSON under `listColumns`. A column that does not fit beside the name's minimum steps out by `rank`, not by position.
- **Every size flexes down to a phone-width tile**: see `rules/frontend.md`.
