#!/bin/sh
# Paperknight: install or update from the latest pka.tar.gz (plugin, studies,
# repertoires, emoji font). Run it on the Kindle (kterm or SSH):
#   curl -fkL <server>/pka.sh | sh
# KOREADER_DIR and PKA_URL override the defaults below.
#
# Cleaning: the plugin folder is replaced, except packs/ (the archive's
# puzzle pack overwrites it; a pack copied there by hand survives otherwise). Asset files are removed only if the previous archive
# installed them (listed in paperknight/.pka-files): studies or repertoires
# you added yourself are kept. The archive is left in the koreader folder.
set -e

KOREADER_DIR=${KOREADER_DIR:-/mnt/us/koreader}
PKA_URL=${PKA_URL:-@DIST_URL@/pka.tar.gz}
PLUGIN=plugins/paperknight.koplugin
LIST=paperknight/.pka-files

cd "$KOREADER_DIR"

echo "Downloading $PKA_URL"
curl -fkL -o pka.tar.gz.part "$PKA_URL"
# a truncated download must not wipe the current install
if ! gzip -dc pka.tar.gz.part | tar tf - >/dev/null; then
    rm -f pka.tar.gz.part
    echo "Incomplete download: nothing changed." >&2
    exit 1
fi
mv pka.tar.gz.part pka.tar.gz

echo "Removing the old files"
if [ -d "$PLUGIN" ]; then
    for entry in "$PLUGIN"/* "$PLUGIN"/.[!.]*; do
        [ -e "$entry" ] || continue
        [ "$entry" = "$PLUGIN/packs" ] || rm -rf "$entry"
    done
fi
if [ -f "$LIST" ]; then
    while IFS= read -r file; do
        case "$file" in
            fonts/*|paperknight/*) rm -f "$file" ;; # never outside the asset folders
        esac
    done < "$LIST"
    # folders left empty (a renamed study category)
    find paperknight -depth -type d -exec rmdir {} \; 2>/dev/null || true
fi

echo "Extracting"
gzip -dc pka.tar.gz | tar xf -

echo "Paperknight updated. Restart KOReader."
