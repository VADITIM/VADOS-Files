# Frontend rules

- **`qml/design/` is the only place a colour, a face, a size, a curve or a duration is written down.**
- **Squircle everywhere** via `shaders/squircle.frag` (superellipse, exponent 4). Never a `Rectangle { radius }` for a box; a `Rectangle` is only for hairlines, bars and fills inside a squircle.
- **Every size flexes down to a phone-width tile.** Below 34rem the sidebar folds to an icon rail; below 30rem the zoom slider leaves the top band; tab pills shrink to their icon; in the folder header the name outranks the sort chips (full → the current one → none) and the forward button. Hyprland ignores `minimumWidth`, so nothing may assume one.
