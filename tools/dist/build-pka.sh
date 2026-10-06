#!/bin/sh
# Builds build/dist/pka.tar.gz from the staged assets in build/dist/all
# (fonts/, paperknight/, the plugin's packs/puzzles.sqlite) and the current
# plugin, plus the installer
# build/dist/pka.sh. The archive lists its asset files in
# paperknight/.pka-files, so the next install removes exactly those.
set -e
# where the files are served from, baked into the installers
DIST_URL="${PAPERKNIGHT_DIST_URL:?set PAPERKNIGHT_DIST_URL to the base URL of the served files}"
cd "$(dirname "$0")/../.."
STAGE=build/dist/all
[ -d "$STAGE/paperknight" ] || { echo "missing $STAGE/paperknight (staged studies and repertoires)" >&2; exit 1; }

rsync -a --delete --exclude packs/puzzles.sqlite plugin/paperknight.koplugin/ "$STAGE/plugins/paperknight.koplugin/"
(cd "$STAGE" && find fonts paperknight -type f ! -name .pka-files | LC_ALL=C sort > paperknight/.pka-files)
tar czf build/dist/pka.tar.gz --owner=0 --group=0 -C "$STAGE" fonts paperknight plugins
sed "s#@DIST_URL@#$DIST_URL#" tools/dist/pka.sh > build/dist/pka.sh
echo "build/dist/pka.tar.gz ($(wc -l < "$STAGE/paperknight/.pka-files") asset files), build/dist/pka.sh"
