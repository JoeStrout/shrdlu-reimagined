#!/bin/bash

# Update the web version of SHRDLU Reimagined in docs/, for GitHub Pages.
#
# docs/index.html is hand-written and kept as it is.  This script refreshes
# everything else there:
#
#   raylib-miniscript.js, raylib-miniscript.wasm
#       the engine, copied from a web build of raylib-miniscript
#   game.data, game.data.js
#       our program and data, bundled into one Emscripten file package
#
# On the web, the engine always runs assets/main.ms, and `import` looks in
# that script's own folder.  So the package puts our src/*.ms files into
# /assets/, next to the contents of our assets/ folder (fonts, shaders, ...).
# The program refers to its data as "assets/...", relative to the working
# directory, which on the web is /, so those paths work unchanged.
#
# Usage: scripts/update-web.sh [raylib-miniscript-dir]
#   raylib-miniscript-dir   the engine's repo, with a web build in build-web/
#                           (default: ../raylib-miniscript)
#
# Test locally:  cd docs && python3 -m http.server 8000
# then open http://localhost:8000

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

cd "$(dirname "$0")/.."

ENGINE_REPO="${1:-../raylib-miniscript}"
BUILD="$ENGINE_REPO/build-web"
DOCS=docs

# The engine files.
for f in raylib-miniscript.js raylib-miniscript.wasm; do
    if [ ! -f "$BUILD/$f" ]; then
        echo -e "${RED}Error: $BUILD/$f is missing.  Run scripts/build-web.sh in $ENGINE_REPO first.${NC}"
        exit 1
    fi
done
mkdir -p "$DOCS"
cp "$BUILD/raylib-miniscript.js" "$BUILD/raylib-miniscript.wasm" "$DOCS/"

# Find Emscripten's file_packager.py: the active Emscripten first, then the
# emsdk inside the engine repo.
PACKAGER=""
if [ -n "$EMSDK" ] && [ -f "$EMSDK/upstream/emscripten/tools/file_packager.py" ]; then
    PACKAGER="$EMSDK/upstream/emscripten/tools/file_packager.py"
elif [ -f "$ENGINE_REPO/emsdk/upstream/emscripten/tools/file_packager.py" ]; then
    PACKAGER="$ENGINE_REPO/emsdk/upstream/emscripten/tools/file_packager.py"
else
    echo -e "${RED}Error: can't find Emscripten's file_packager.py.${NC}"
    exit 1
fi
PACKAGER="$(cd "$(dirname "$PACKAGER")" && pwd)/$(basename "$PACKAGER")"

# Stage the files as the program will see them: everything under /assets.
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/shrdlu-web.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/assets"
cp -R assets/. "$STAGE/assets/"
cp src/*.ms "$STAGE/assets/"

echo -e "${YELLOW}Packaging src/ and assets/...${NC}"
# file_packager writes the output name into the loader, so run it from docs/
# with plain names there.  --exclude drops dotfiles such as .DS_Store;
# --no-node leaves out Node.js support the page doesn't need.
(cd "$DOCS" && python3 "$PACKAGER" game.data \
    --preload "$STAGE/assets@/assets" \
    --exclude '*/.*' \
    --no-node --quiet \
    --js-output=game.data.js) || { echo -e "${RED}Packaging failed!${NC}"; exit 1; }

# Serve the files as they are, without running them through Jekyll.
touch "$DOCS/.nojekyll"

echo ""
ls -lh "$DOCS"
echo ""
echo -e "${GREEN}Web version updated in $DOCS/.${NC}"
echo "To test locally: cd $DOCS && python3 -m http.server 8000, then open http://localhost:8000"
