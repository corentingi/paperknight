#!/bin/bash
# Tests install.sh against releases built by build-dist.sh from a fake stage
# (a tiny puzzle pack, a fake font, a fake Stockfish), served as file://
# URLs, into fake koreader folders. The installer runs under busybox (its
# sh and applets, as on the Kindle) when busybox is installed.
# Run by `make test-dist` (part of `make check`).
set -euo pipefail
cd "$(dirname "$0")/../.."
T="$PWD/build/test-dist"
rm -rf "$T"
mkdir -p "$T"
FAILS=0
ok() { echo "  ok: $1"; }
no() { echo "  FAIL: $1" >&2; FAILS=$((FAILS + 1)); }
check() { # description, command...
    local what=$1
    shift
    if "$@"; then ok "$what"; else no "$what"; fi
}
has() { grep -qF -- "$2" "$1"; }

# the installer's shell and tools: busybox's when there is one
SH=sh
if command -v busybox >/dev/null; then
    mkdir -p "$T/bb"
    for applet in sh tar gzip find sha256sum mv cp rm mkdir dirname chmod grep tr cat uname rmdir; do
        ln -s "$(command -v busybox)" "$T/bb/$applet"
    done
    SH="$T/bb/sh"
fi
echo "installer shell: $SH"

# --- a stage and two releases ------------------------------------------------
P=plugins/paperknight.koplugin
stage() { # folder, pack date, studies...
    local dir=$1 day=$2
    shift 2
    mkdir -p "$dir/$P/packs" "$dir/fonts" "$dir/paperknight/studies" "$dir/paperknight/repertoires"
    python3 - "$dir/$P/packs/puzzles.sqlite" "$day" <<'EOF'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
c.execute("CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT)")
c.execute("INSERT INTO meta VALUES ('source', ?)", (f"lichess (downloaded {sys.argv[2]})",))
c.commit()
EOF
    echo font > "$dir/fonts/NotoEmoji.ttf"
    echo licence > "$dir/fonts/NotoEmoji-OFL.txt"
    for study in "$@"; do
        mkdir -p "$(dirname "$dir/paperknight/$study")"
        echo "[Event \"$study\"]" > "$dir/paperknight/$study"
    done
}
mkdir -p "$T/sf"
printf '#!/bin/sh\necho "Stockfish (test)"\n' | gzip -c > "$T/sf/stockfish-pw2.gz"
release() { # name, version, stage, release notes (Markdown file, optional)
    # (not the settings of the release workflow these tests may run in)
    env -u PAPERKNIGHT_UPDATE_URL -u PAPERKNIGHT_STOCKFISH_URL -u PAPERKNIGHT_STOCKFISH_VERSION \
        PK_STAGE="$3" PK_OUT="$T/$1" SF_DIR="$T/sf" PAPERKNIGHT_VERSION="$2" PAPERKNIGHT_NOTES="${4:-}" \
        PAPERKNIGHT_DIST_URL="file://$T/$1" sh tools/dist/build-dist.sh > "$T/$1.build.log"
}
cat > "$T/notes.md" <<'EOF'

### New

- **Puzzles**: It's new, with a \ and $HOME

### Fixed

- **Studies**: A fix
EOF
stage "$T/stage1" 2026-01-01 "studies/A.pgn" "studies/Cat/C.pgn" "repertoires/W.pgn"
stage "$T/stage2" 2026-01-01 "studies/B.pgn" "repertoires/W.pgn"
release r1 v1 "$T/stage1"
release r2 v2 "$T/stage2" "$T/notes.md"

run() { # koreader folder, release, installer arguments... (answers on $ANSWERS)
    local k=$1 r=$2
    shift 2
    mkdir -p "$k"
    KOREADER_DIR="$k" SF_PLATFORM=pw2 PK_TTY="${ANSWERS:-/nonexistent}" PATH="$T/bb:$PATH" \
        "$SH" "$T/$r/install.sh" "$@" > "$T/out.log" 2>&1
}

echo "fresh install, answering no to Stockfish"
K="$T/k1"
printf 'n\ny\n' > "$T/answers"
ANSWERS="$T/answers" run "$K" r1 || no "installer exit status"
check "plugin installed" test -f "$K/$P/main.lua"
check "version.txt" has "$K/$P/version.txt" v1
check "update-url.txt" has "$K/$P/update-url.txt" "file://$T/r1/install.sh"
check "puzzle pack" test -f "$K/$P/packs/puzzles.sqlite"
check "font" test -f "$K/fonts/NotoEmoji.ttf"
check "studies, in a folder too" test -f "$K/paperknight/studies/Cat/C.pgn"
check "repertoire" test -f "$K/paperknight/repertoires/W.pgn"
check "Stockfish declined" test ! -e "$K/$P/bin/stockfish"
check "plugin record" has "$K/paperknight/.parts/plugin" v1
check "studies record lists the files" has "$K/paperknight/.parts/studies" paperknight/studies/A.pgn
check "no download folder left" test ! -e "$K/.paperknight-download"
check "downloads named with their size" has "$T/out.log" "Downloading paperknight-plugin-v1.tar.gz ("
check "no progress bar (kterm prints each redraw on a new line)" bash -c "! grep -q \$'\r' '$T/out.log'"

echo "second run without a terminal: Stockfish taken by default"
run "$K" r1 || no "installer exit status"
check "plugin up to date" has "$T/out.log" "up to date (v1)"
check "nothing else downloaded" bash -c "! grep -q 'Downloading paperknight' '$T/out.log'"
check "Stockfish installed" test -x "$K/$P/bin/stockfish"
check "Stockfish record" has "$K/paperknight/.parts/stockfish" "$P/bin/stockfish"

echo "third run: nothing to do"
run "$K" r1 --yes || no "installer exit status"
check "everything up to date" has "$T/out.log" "Everything is up to date."
check "no release notes in r1: none shown" bash -c "! grep -q \"What's new\" '$T/out.log'"

echo "update to r2, with a study of your own"
echo mine > "$K/paperknight/studies/Mine.pgn"
run "$K" r2 -y || no "installer exit status"
check "plugin updated" has "$K/$P/version.txt" v2
cat > "$T/notes.expected" <<'EOF'
What's new in v2:
New:
• Puzzles: It’s new, with a \ and $HOME
Fixed:
• Studies: A fix
EOF
check "release notes shown" bash -c "grep -A4 \"^What's new in v2:\" '$T/out.log' | diff - '$T/notes.expected'"
check "same pack: not downloaded" bash -c "! grep -q 'Downloading paperknight-puzzles' '$T/out.log'"
check "pack kept through the plugin swap" test -f "$K/$P/packs/puzzles.sqlite"
check "Stockfish kept through the plugin swap" test -x "$K/$P/bin/stockfish"
check "removed study gone" test ! -e "$K/paperknight/studies/A.pgn"
check "emptied category gone" test ! -e "$K/paperknight/studies/Cat"
check "new study" test -f "$K/paperknight/studies/B.pgn"
check "your own study kept" test -f "$K/paperknight/studies/Mine.pgn"

echo "dry run changes nothing"
K="$T/k2"
run "$K" r1 --dry-run || no "installer exit status"
check "dry run said so" has "$T/out.log" "Dry run: nothing changed."
check "nothing installed" test ! -e "$K/plugins"

echo "corrupted download changes nothing"
cp -r "$T/r1" "$T/r3"
sed -i "s#file://$T/r1#file://$T/r3#" "$T/r3/install.sh"
echo x >> "$T/r3/paperknight-puzzles-2026-01-01.tar.gz"
K="$T/k3"
if run "$K" r3 -y; then no "installer should fail"; else ok "installer failed"; fi
check "checksum reported" has "$T/out.log" "checksum of paperknight-puzzles"
check "nothing installed" test ! -e "$K/plugins"
check "no download folder left" test ! -e "$K/.paperknight-download"

echo "update of an install made by pka.sh"
K="$T/k4"
mkdir -p "$K/$P/packs" "$K/$P/bin" "$K/fonts" "$K/paperknight/studies"
echo old > "$K/$P/main.lua"
echo old > "$K/$P/version.txt"
echo old > "$K/$P/packs/puzzles.sqlite"
echo old > "$K/$P/bin/stockfish"
echo old > "$K/fonts/NotoEmoji.ttf"
echo old > "$K/paperknight/studies/Old.pgn"
echo mine > "$K/paperknight/studies/Mine.pgn"
printf 'fonts/NotoEmoji.ttf\npaperknight/studies/Old.pgn\n' > "$K/paperknight/.pka-files"
echo old > "$K/pka.tar.gz"
run "$K" r1 -y || no "installer exit status"
check "offered as updates" has "$T/out.log" "Puzzle pack  ? -> 2026-01-01"
check "old plugin version shown" has "$T/out.log" "Plugin       old -> v1"
check "plugin replaced" has "$K/$P/version.txt" v1
check "pack replaced" bash -c "! grep -q old '$K/$P/packs/puzzles.sqlite'"
check "Stockfish replaced" has "$K/$P/bin/stockfish" "Stockfish (test)"
check "font replaced, not removed" has "$K/fonts/NotoEmoji.ttf" font
check "old study gone" test ! -e "$K/paperknight/studies/Old.pgn"
check "your own study kept" test -f "$K/paperknight/studies/Mine.pgn"
check ".pka-files gone" test ! -e "$K/paperknight/.pka-files"
check "old archive gone" test ! -e "$K/pka.tar.gz"

echo "USB zip, then the installer"
K="$T/k5"
mkdir -p "$K"
python3 -c "import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$T/r1/paperknight-v1-usb.zip" "$T/k5usb"
cp -r "$T/k5usb/koreader/." "$K/"
check "zip has Stockfish" test -f "$K/$P/bin/stockfish"
run "$K" r1 -y || no "installer exit status"
check "everything up to date after a USB copy" has "$T/out.log" "Everything is up to date."

echo "no Stockfish build for the device"
K="$T/k6"
mkdir -p "$K"
KOREADER_DIR="$K" SF_PLATFORM=kobo PK_TTY=/nonexistent PATH="$T/bb:$PATH" "$SH" "$T/r1/install.sh" -n > "$T/out.log" 2>&1 || no "installer exit status"
check "said so" has "$T/out.log" "no build for this device"

echo "--list and --parts (the in-app updater)"
K="$T/k7"
run "$K" r1 --parts=plugin,fonts -y || no "installer exit status"
check "listed parts installed" test -f "$K/fonts/NotoEmoji.ttf"
check "others left out" test ! -e "$K/$P/packs/puzzles.sqlite"
check "Stockfish left out" test ! -e "$K/$P/bin/stockfish"
run "$K" r2 --list || no "installer exit status"
check "list: plugin update" has "$T/out.log" "plugin|v1|v2|"
check "list: missing pack" has "$T/out.log" "puzzles||2026-01-01|"
check "list: Stockfish for the device" has "$T/out.log" "stockfish||"
check "list only" test "$(grep -vc '|' "$T/out.log")" = 0
check "list changes nothing" has "$K/$P/version.txt" v1
run "$K" r2 --parts=stockfish -y || no "installer exit status"
check "only Stockfish installed" test -x "$K/$P/bin/stockfish"
check "plugin not updated" has "$K/$P/version.txt" v1

if [ "$FAILS" -gt 0 ]; then
    echo "test-install: $FAILS failed (last installer output: $T/out.log)" >&2
    exit 1
fi
echo "test-install: all passed"
