#!/usr/bin/env bash
# Fetches the two VAS faces that are openly licensed (SIL OFL) into assets/fonts, where the build bundles them.
# Wosker and Striker (the display faces) are not redistributable: copy Wosker.otf and Striker.otf from the PORTFOLIO25 font folder into assets/fonts yourself.
set -euo pipefail
cd "$(dirname "$0")/../assets/fonts"
curl -fsSLo SpaceMono-Regular.ttf https://github.com/google/fonts/raw/main/ofl/spacemono/SpaceMono-Regular.ttf
curl -fsSLo SpaceMono-Bold.ttf https://github.com/google/fonts/raw/main/ofl/spacemono/SpaceMono-Bold.ttf
curl -fsSLo Audiowide-Regular.ttf https://github.com/google/fonts/raw/main/ofl/audiowide/Audiowide-Regular.ttf
echo "Fonts in $(pwd). Re-run cmake (cmake -B build) so the new files are bundled."
