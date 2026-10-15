#!/bin/sh
# Builds build/dist/pka.tar.gz from the staged assets in build/dist/all
# (fonts/, paperknight/, the plugin's packs/puzzles.sqlite) and the current
# plugin, plus the installer
# build/dist/pka.sh. The archive lists its asset files in
# paperknight/.pka-files, so the next install removes exactly those.
#
# --code: the plugin's code only (build/dist/pkc.tar.gz + pkc.sh, a few
# hundred KB): the installer keeps the puzzle pack, studies, repertoires
# and fonts already on the device.
set -e
# where the files are served from, baked into the installers
DIST_URL="${PAPERKNIGHT_DIST_URL:?set PAPERKNIGHT_DIST_URL to the base URL of the served files}"
cd "$(dirname "$0")/../.."
SHA_OF() { sha256sum "$1" | cut -d' ' -f1; }
EXCLUDES="--exclude pkchesslib/spec/ --exclude pkchesslib/perft.lua --exclude pkchesslib/example.lua
    --exclude .travis.yml --exclude .gitignore --exclude .gitkeep --exclude /bin/"

if [ "$1" = "--code" ]; then
    STAGE=build/dist/code
    mkdir -p "$STAGE/plugins"
    # shellcheck disable=SC2086
    rsync -a --delete --delete-excluded $EXCLUDES --exclude '/packs/' \
        plugin/paperknight.koplugin/ "$STAGE/plugins/paperknight.koplugin/"
    tar czf build/dist/pkc.tar.gz --owner=0 --group=0 -C "$STAGE" plugins
    sed -e "s/@PKA_SHA256@/$(SHA_OF build/dist/pkc.tar.gz)/" -e "s#@DIST_URL@#$DIST_URL#" -e "s#/pka.tar.gz#/pkc.tar.gz#" \
        tools/dist/pka.sh > build/dist/pkc.sh
    echo "build/dist/pkc.tar.gz ($(du -h build/dist/pkc.tar.gz | cut -f1), code only), build/dist/pkc.sh"
    exit 0
fi

STAGE=build/dist/all
[ -d "$STAGE/paperknight" ] || { echo "missing $STAGE/paperknight (staged studies and repertoires)" >&2; exit 1; }

# not shipped: the chess library's development files, a local bin/ (Stockfish
# is installed by stockfish.sh); the staged puzzle pack is kept (P: protected)
# shellcheck disable=SC2086
rsync -a --delete --delete-excluded --filter='P packs/puzzles.sqlite' $EXCLUDES \
    plugin/paperknight.koplugin/ "$STAGE/plugins/paperknight.koplugin/"
(cd "$STAGE" && find fonts paperknight -type f ! -name .pka-files | LC_ALL=C sort > paperknight/.pka-files)
tar czf build/dist/pka.tar.gz --owner=0 --group=0 -C "$STAGE" fonts paperknight plugins
# the installer checks the archive it downloads
sed -e "s/@PKA_SHA256@/$(SHA_OF build/dist/pka.tar.gz)/" -e "s#@DIST_URL@#$DIST_URL#" tools/dist/pka.sh > build/dist/pka.sh
echo "build/dist/pka.tar.gz ($(wc -l < "$STAGE/paperknight/.pka-files") asset files), build/dist/pka.sh"
