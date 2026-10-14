#!/bin/sh
# Paperknight: install Stockfish on the Kindle (plays "Play against the
# engine" and evaluates on the analysis board). Run it on the Kindle (kterm
# or SSH):
#   curl -fkL <server>/stockfish.sh | sh
# KOREADER_DIR and SF_URL override the defaults below. The binary (~100 MB:
# Stockfish 19 with its network, static, ARMv7 + NEON) goes to
# plugins/paperknight.koplugin/bin/stockfish; pka.sh updates keep it.
# Stockfish is GPLv3: its source is next to it on the server
# (stockfish-sf_19-src.tar.gz), the build is tools/dist/build-stockfish.sh.
#
# Everything is in main(), called on the last line: a download cut short
# runs nothing.
main() {
    set -e
    KOREADER_DIR="${KOREADER_DIR:-/mnt/us/koreader}"
    SF_URL="${SF_URL:-@DIST_URL@/stockfish.gz}"
    SF_SHA256="@SF_SHA256@"
    BIN="$KOREADER_DIR/plugins/paperknight.koplugin/bin"

    if [ ! -d "$KOREADER_DIR/plugins/paperknight.koplugin" ]; then
        echo "Paperknight is not installed in $KOREADER_DIR (run pka.sh first)."
        exit 1
    fi
    mkdir -p "$BIN"
    cd "$BIN"
    echo "Downloading Stockfish (about 80 MB)"
    curl -fkL "$SF_URL" -o stockfish.gz.part
    if command -v sha256sum >/dev/null 2>&1 && [ "${SF_SHA256#@}" = "$SF_SHA256" ]; then
        if ! echo "$SF_SHA256  stockfish.gz.part" | sha256sum -c - >/dev/null 2>&1; then
            rm -f stockfish.gz.part
            echo "Download corrupted (checksum): nothing changed."
            exit 1
        fi
    fi
    if ! gzip -dc stockfish.gz.part > stockfish.part; then
        rm -f stockfish.gz.part stockfish.part
        echo "Incomplete download: nothing changed."
        exit 1
    fi
    rm -f stockfish.gz.part
    chmod +x stockfish.part
    mv stockfish.part stockfish
    if echo quit | ./stockfish | grep -q "Stockfish"; then
        echo "Stockfish installed. Restart KOReader."
    else
        echo "Stockfish installed, but it did not start on this device."
        exit 1
    fi
}

main "$@"
