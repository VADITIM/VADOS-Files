# Architecture

Layers, top to bottom: `qml/feature/` (screens and the `Workspace` command funnel) → `qml/ui/` (V/AS primitives) → `qml/design/` (`Theme`, `Motion`) and `src/core/` (C++ models and services exposed to QML). Nothing depends upward.

## One binary, three roles

- Plain run: the window.
- `--file-manager-service`: `org.freedesktop.FileManager1` ("show in folder").
- `--portal-service`: `org.freedesktop.impl.portal.FileChooser`, the backend xdg-desktop-portal asks for every app's open/save dialog. Each portal request runs the binary again with `--pick <json>`; `Picker` (C++ singleton) holds the request, `PickerBar` is the band under the folder, `Workspace.pick` is the accept, and the answer leaves on stdout (`filter N`, then one URI per line); quitting without one is a cancel.

Test a picker headless: `QT_QPA_PLATFORM=offscreen ./build-release/vados-files --pick '{"mode":"open","folder":"/tmp"}'`.

## Data flow

- Loading is split from showing: `FolderModel.load` reads while the old folder leaves, `commit` swaps rows in after. A refresh diffs, so the views animate inserts and removals instead of resetting.
- Every command passes through `Workspace`. The drop target performs the operation; the drag source never deletes.
- `FileOperations` keeps the undo stack; every reversible change offers undo.
- Rooms live in `PlacesModel`; the sidebar shows the user's pins, stored as JSON under `pins` in `~/.config/vados/files.conf`.
