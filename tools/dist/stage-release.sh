#!/bin/sh
# Assembles the assets of a public release in build/dist/release (the
# PKA_STAGE of build-pka.sh): the puzzle pack built by `make packs`, the Noto
# Emoji font (OFL, from google/fonts at a pinned commit, checksums checked)
# and empty studies and repertoires folders: no third-party study is shipped
# (Lichess study text has no clear licence). build/dist/all, the local stage
# with your own studies, is not touched.
set -eu
cd "$(dirname "$0")/../.."
STAGE=build/dist/release
PACK=build/packs/puzzles.sqlite
FONTS_COMMIT=47d54ca1ebb14fd864695f1d39dc734f39017c33
FONT_BASE="https://raw.githubusercontent.com/google/fonts/$FONTS_COMMIT/ofl/notoemoji"
FONT_SHA256=de6c18832938afc99caf132b39d6a30a19bac7f2e812e28db2535b4608d27551
OFL_SHA256=500bb1ccf43df7bbb522112f9133a52b16e1c35e809632f5d8609b179152de5b

[ -f "$PACK" ] || { echo "missing $PACK (make packs)" >&2; exit 1; }
rm -rf "$STAGE"
mkdir -p "$STAGE/fonts" "$STAGE/paperknight/studies" "$STAGE/paperknight/repertoires" \
    "$STAGE/plugins/paperknight.koplugin/packs"
cp "$PACK" "$STAGE/plugins/paperknight.koplugin/packs/puzzles.sqlite"

fetch() { # url, file, sha256
    curl -fsSL --retry 3 -o "$2" "$1"
    echo "$3  $2" | sha256sum -c - >/dev/null || { echo "checksum mismatch: $1" >&2; exit 1; }
}
fetch "$FONT_BASE/NotoEmoji%5Bwght%5D.ttf" "$STAGE/fonts/NotoEmoji.ttf" "$FONT_SHA256"
fetch "$FONT_BASE/OFL.txt" "$STAGE/fonts/NotoEmoji-OFL.txt" "$OFL_SHA256"
echo "$STAGE: puzzle pack, Noto Emoji font, empty studies and repertoires folders"
