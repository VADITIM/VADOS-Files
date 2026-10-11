# VAD/OS Files

This project is built on V/AS (VAD/OS APPLICATION SYSTEMS), base register. Read `.claude/skills/vas/SKILL.md`.

A file manager for Hyprland on Arch. Qt 6 (QML + C++), CMake. V/AS is the source of truth for how it looks, moves and reads; the docs below hold what is particular to this project.

## Commands

```bash
cmake -B build -G Ninja && cmake --build build      # build
./build/vados-files [path]                          # run
QT_FORCE_STDERR_LOGGING=1 ./build/vados-files       # see QML warnings (Qt logs to journald otherwise)
VADOS_REHEARSAL=/path/to/script.qml ./build/vados-files   # scripted run: drives the window, saves frames
scripts/install.sh [--default]                      # install to ~/.local; --default makes it open folders
scripts/fetch-fonts.sh                              # Space Mono + Audiowide into assets/fonts
```

Before reading V/AS, `git -C .claude/skills/vas fetch && git -C .claude/skills/vas status -sb` and pull if behind.

## Releases

Releases: on command

The version is `project(vados-files VERSION …)` in `CMakeLists.txt`. Process: `.claude/skills/vas/guides/release-pipeline.md`.

## Docs

| File | Holds |
|---|---|
| `docs/map.md` | Folder to purpose, entry points |
| `docs/architecture.md` | Layers, the three roles of the binary, data flow |
| `docs/decisions.md` | What was decided, and why |
| `docs/quirks.md` | Traps already hit, written as the symptom |
| `docs/known-issues.md` | Bugs and debt that exist now |
| `docs/roadmap.md` | Planned work, V/AS promotion candidates |

## Rules

@docs/rules/frontend.md
