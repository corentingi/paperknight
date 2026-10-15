#!/bin/sh
# Paperknight: install or update from the latest pka.tar.gz (plugin, studies,
# repertoires, emoji font). Run it on the Kindle (kterm or SSH):
#   curl -fkL <server>/pka.sh | sh
# KOREADER_DIR and PKA_URL override the defaults below.
#
# Safe against a download cut short (everything is in main(), called on the
# last line; the archive is checked: checksum, gzip, tar) and against a
# failed extraction (into a staging folder first: the current install is
# only replaced once the new one is complete).
#
# Cleaning: the plugin folder is replaced, except packs/ (the archive's
# puzzle pack replaces it; a pack copied there by hand survives otherwise)
# and bin/ (Stockfish, installed by stockfish.sh). Asset files are removed
# only if the previous archive installed them (listed in
# paperknight/.pka-files): studies or repertoires you added are kept. The
# archive is left in the koreader folder. A code-only archive (pkc.sh,
# build-pka.sh --code) brings no assets: the ones installed are kept.
main() {
    set -e
    KOREADER_DIR=${KOREADER_DIR:-/mnt/us/koreader}
    PKA_URL=${PKA_URL:-@DIST_URL@/pka.tar.gz}
    PKA_SHA256="@PKA_SHA256@" # filled in by build-pka.sh
    PLUGIN=plugins/paperknight.koplugin
    LIST=paperknight/.pka-files
    NEW=.pka-new

    cd "$KOREADER_DIR"

    echo "Downloading $PKA_URL"
    curl -fkL -o pka.tar.gz.part "$PKA_URL"
    if command -v sha256sum >/dev/null 2>&1 && [ "${PKA_SHA256#@}" = "$PKA_SHA256" ]; then
        if ! echo "$PKA_SHA256  pka.tar.gz.part" | sha256sum -c - >/dev/null 2>&1; then
            rm -f pka.tar.gz.part
            echo "Download corrupted or outdated installer (checksum): nothing changed." >&2
            exit 1
        fi
    fi
    if ! gzip -t pka.tar.gz.part 2>/dev/null || ! gzip -dc pka.tar.gz.part | tar tf - >/dev/null; then
        rm -f pka.tar.gz.part
        echo "Incomplete download: nothing changed." >&2
        exit 1
    fi
    mv pka.tar.gz.part pka.tar.gz

    echo "Extracting"
    rm -rf "$NEW"
    mkdir "$NEW"
    if ! gzip -dc pka.tar.gz | tar xf - -C "$NEW" || [ ! -f "$NEW/$PLUGIN/main.lua" ]; then
        rm -rf "$NEW"
        echo "Extraction failed (disk full?): nothing changed." >&2
        exit 1
    fi

    echo "Replacing the plugin"
    # the old plugin folder is set aside (a rename: no space needed) and
    # restored if the new one cannot be put in place
    rm -rf "$PLUGIN.old"
    [ -d "$PLUGIN" ] && mv "$PLUGIN" "$PLUGIN.old"
    mkdir -p plugins
    if ! mv "$NEW/$PLUGIN" "$PLUGIN"; then
        [ -d "$PLUGIN.old" ] && mv "$PLUGIN.old" "$PLUGIN"
        rm -rf "$NEW"
        echo "Could not install the plugin: the previous version is kept." >&2
        exit 1
    fi
    if [ -d "$PLUGIN.old" ]; then
        # kept from the previous install: Stockfish, and a pack the archive
        # does not bring
        [ -d "$PLUGIN.old/bin" ] && rm -rf "$PLUGIN/bin" && mv "$PLUGIN.old/bin" "$PLUGIN/bin"
        if [ ! -f "$PLUGIN/packs/puzzles.sqlite" ] && [ -f "$PLUGIN.old/packs/puzzles.sqlite" ]; then
            mkdir -p "$PLUGIN/packs"
            mv "$PLUGIN.old/packs/puzzles.sqlite" "$PLUGIN/packs/puzzles.sqlite"
        fi
        rm -rf "$PLUGIN.old"
    fi

    if [ ! -f "$NEW/$LIST" ]; then # code only: the assets stay as they are
        rm -rf "$NEW"
        echo "Paperknight updated (code only). Restart KOReader."
        return 0
    fi
    echo "Replacing the studies and fonts"
    if [ -f "$LIST" ]; then
        while IFS= read -r file; do
            case "$file" in
                *..*) ;;                                # never outside the asset folders
                fonts/*|paperknight/*) rm -f "$file" ;;
            esac
        done < "$LIST"
        # folders left empty (a renamed study category)
        find paperknight -depth -type d -exec rmdir {} \; 2>/dev/null || true
    fi
    for dir in fonts paperknight; do
        if [ -d "$NEW/$dir" ]; then
            mkdir -p "$dir"
            cp -R "$NEW/$dir/." "$dir/"
        fi
    done
    rm -rf "$NEW"

    echo "Paperknight updated. Restart KOReader."
}

main "$@"
