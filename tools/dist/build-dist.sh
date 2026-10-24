#!/bin/sh
# Builds the files a release serves, in build/dist/out (docs/releasing.md):
#   install.sh                           the installer, with the parts below baked in
#   paperknight-plugin-<version>.tar.gz  the plugin (without packs/ and bin/)
#   paperknight-puzzles-<date>.tar.gz    the puzzle pack (<date>: the Lichess download)
#   paperknight-emoji-font-<hash>.tar.gz Noto Emoji and its licence
#   paperknight-studies-<hash>.tar.gz    studies and repertoires, only when staged
#   paperknight-<version>-usb.zip        the same as a koreader/ folder to copy over USB
#   stockfish-<platform>.gz, its source and patch: when served from here
#   SHA256SUMS
# Each archive holds paths relative to the koreader folder. Versions name the
# files, so an unchanged part keeps its name and install.sh skips it.
#
# PK_STAGE: the staged assets (default build/dist/all, your local stage;
#   stage-release.sh fills build/dist/release): fonts/, paperknight/studies
#   and repertoires, plugins/paperknight.koplugin/packs/puzzles.sqlite.
# PAPERKNIGHT_DIST_URL: where these files are served from (required).
# PAPERKNIGHT_UPDATE_URL: where the plugin looks for updates, written into
#   update-url.txt (default: install.sh in PAPERKNIGHT_DIST_URL).
# PK_OUT: the output folder (default build/dist/out).
# PAPERKNIGHT_VERSION: the plugin's version (default: git describe).
# Stockfish: the stockfish-<platform>.gz in SF_DIR (default
#   build/dist/stockfish, build-stockfish.sh). With PAPERKNIGHT_STOCKFISH_URL
#   (the folder serving them, e.g. a Stockfish release) they are downloaded
#   from there; otherwise they are copied next to the other files.
#   PAPERKNIGHT_STOCKFISH_VERSION names them (default: their hash).
set -eu
DIST_URL="${PAPERKNIGHT_DIST_URL:?set PAPERKNIGHT_DIST_URL to the base URL of the served files}"
cd "$(dirname "$0")/../.."
STAGE="${PK_STAGE:-build/dist/all}"
SF_DIR="${SF_DIR:-build/dist/stockfish}"
VERSION="${PAPERKNIGHT_VERSION:-$(git describe --tags --always --dirty 2>/dev/null || echo dev)}"
OUT="${PK_OUT:-build/dist/out}"
WORK="$OUT.work"
PLUGIN=plugins/paperknight.koplugin
PACK="$STAGE/$PLUGIN/packs/puzzles.sqlite"

sha() { sha256sum "$1" | cut -d' ' -f1; }
size() { wc -c < "$1" | tr -d ' '; }
PARTS=
add_part() { # name, version, file in $OUT or URL, local file
    PARTS="$PARTS$1|$2|$3|$(sha "$4")|$(size "$4")
"
}
pack() { # archive name, folder, paths...
    name=$1 dir=$2
    shift 2
    tar czf "$OUT/$name" --sort=name --owner=0 --group=0 --numeric-owner -C "$dir" "$@"
}

[ -f "$PACK" ] || { echo "missing $PACK (make packs, then stage it)" >&2; exit 1; }
[ -f "$STAGE/fonts/NotoEmoji.ttf" ] || { echo "missing $STAGE/fonts/NotoEmoji.ttf" >&2; exit 1; }
rm -rf "$OUT" "$WORK"
mkdir -p "$OUT" "$WORK/plugin/$PLUGIN"

# the plugin: not the chess library's development files, a local bin/
# (Stockfish) or packs/ (parts of their own)
rsync -a --exclude pkchesslib/spec/ --exclude pkchesslib/perft.lua --exclude pkchesslib/example.lua \
    --exclude .travis.yml --exclude .gitignore --exclude .gitkeep --exclude /bin/ --exclude /packs/ \
    plugin/paperknight.koplugin/ "$WORK/plugin/$PLUGIN/"
echo "$VERSION" > "$WORK/plugin/$PLUGIN/version.txt"
echo "${PAPERKNIGHT_UPDATE_URL:-$DIST_URL/install.sh}" > "$WORK/plugin/$PLUGIN/update-url.txt"
pack "paperknight-plugin-$VERSION.tar.gz" "$WORK/plugin" "$PLUGIN"
add_part plugin "$VERSION" "paperknight-plugin-$VERSION.tar.gz" "$OUT/paperknight-plugin-$VERSION.tar.gz"

# the puzzle pack, versioned by the day its Lichess database was downloaded
PACK_VERSION="$(python3 - "$PACK" <<'EOF'
import re, sqlite3, sys
meta = dict(sqlite3.connect(sys.argv[1]).execute("SELECT key, value FROM meta"))
day = re.search(r"downloaded (\d{4}-\d{2}-\d{2})", meta.get("source", ""))
print(day.group(1) if day else meta.get("built_at", "unknown")[:10])
EOF
)"
pack "paperknight-puzzles-$PACK_VERSION.tar.gz" "$STAGE" "$PLUGIN/packs/puzzles.sqlite"
add_part puzzles "$PACK_VERSION" "paperknight-puzzles-$PACK_VERSION.tar.gz" "$OUT/paperknight-puzzles-$PACK_VERSION.tar.gz"

FONT_VERSION="$(cat "$STAGE"/fonts/* | sha256sum | cut -c1-8)"
pack "paperknight-emoji-font-$FONT_VERSION.tar.gz" "$STAGE" fonts
add_part fonts "$FONT_VERSION" "paperknight-emoji-font-$FONT_VERSION.tar.gz" "$OUT/paperknight-emoji-font-$FONT_VERSION.tar.gz"

# studies and repertoires, when the stage has some (never in public releases)
STUDIES="$(cd "$STAGE" && find paperknight/studies paperknight/repertoires -type f 2>/dev/null | LC_ALL=C sort)"
if [ -n "$STUDIES" ]; then
    STUDIES_VERSION="$(cd "$STAGE" && echo "$STUDIES" | while IFS= read -r f; do echo "$f"; cat "$f"; done | sha256sum | cut -c1-8)"
    pack "paperknight-studies-$STUDIES_VERSION.tar.gz" "$STAGE" paperknight/studies paperknight/repertoires
    add_part studies "$STUDIES_VERSION" "paperknight-studies-$STUDIES_VERSION.tar.gz" "$OUT/paperknight-studies-$STUDIES_VERSION.tar.gz"
fi

# Stockfish, one binary per platform
for gz in "$SF_DIR"/stockfish-*.gz; do
    case "$gz" in *.tar.gz) continue ;; esac
    [ -f "$gz" ] || continue
    file="$(basename "$gz")"
    platform="${file#stockfish-}"
    platform="${platform%.gz}"
    if [ -n "${PAPERKNIGHT_STOCKFISH_URL:-}" ]; then
        where="$PAPERKNIGHT_STOCKFISH_URL/$file"
    else
        cp "$gz" "$OUT/"
        # the corresponding source (GPL)
        for src in "$SF_DIR"/stockfish-*-src.tar.gz "$SF_DIR"/stockfish-*.patch; do
            if [ -f "$src" ]; then cp "$src" "$OUT/"; fi
        done
        where="$file"
    fi
    add_part "stockfish-$platform" "${PAPERKNIGHT_STOCKFISH_VERSION:-$(sha "$gz" | cut -c1-8)}" "$where" "$gz"
done

# the installer
awk -v parts="$(printf '%s' "$PARTS")" -v version="$VERSION" -v url="$DIST_URL" '
    $0 == "@PARTS@" { print parts; next }
    { gsub(/@VERSION@/, version); gsub(/@DIST_URL@/, url); print }
' tools/dist/install.sh > "$OUT/install.sh"

# the USB zip: every part laid out in koreader/, with the install records, so
# that install.sh updates it later
USB="$WORK/usb/koreader"
mkdir -p "$USB/paperknight/.parts" "$USB/paperknight/studies" "$USB/paperknight/repertoires"
echo "$PARTS" | while IFS='|' read -r name version file _ _; do
    [ -n "$name" ] || continue
    case "$name" in
        stockfish-pw2) # the Kindle build
            mkdir -p "$USB/$PLUGIN/bin"
            gzip -dc "$SF_DIR/stockfish-pw2.gz" > "$USB/$PLUGIN/bin/stockfish"
            chmod +x "$USB/$PLUGIN/bin/stockfish"
            printf '%s\n%s\n' "$version" "$PLUGIN/bin/stockfish" > "$USB/paperknight/.parts/stockfish" ;;
        stockfish-*) ;;
        plugin)
            tar xzf "$OUT/$file" -C "$USB"
            echo "$version" > "$USB/paperknight/.parts/plugin" ;;
        *)
            tar xzf "$OUT/$file" -C "$USB"
            { echo "$version"; tar tzf "$OUT/$file" | grep -v '/$'; } > "$USB/paperknight/.parts/$name" ;;
    esac
done
python3 - "$WORK/usb" "$OUT/paperknight-$VERSION-usb.zip" <<'EOF'
import os, sys, zipfile
root, out = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for folder, dirs, files in os.walk(root):
        dirs.sort()
        rel = os.path.relpath(folder, root)
        if not files and not dirs:
            z.write(folder, rel + "/")  # empty folders: studies/, repertoires/
        for name in sorted(files):
            path = os.path.join(folder, name)
            z.write(path, os.path.join(rel, name))
EOF
rm -rf "$WORK"

(cd "$OUT" && sha256sum -- * > SHA256SUMS)
echo "$OUT:"
(cd "$OUT" && ls -sh1 --hide=SHA256SUMS)
