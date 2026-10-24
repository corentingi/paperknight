#!/bin/sh
# Paperknight installer: installs or updates Paperknight on a Kindle with
# KOReader. Run it on the Kindle (kterm or SSH):
#   curl -fkL <server>/install.sh | sh
#   curl -fkL <server>/install.sh | sh -s -- --yes      (no questions)
# Options: -y/--yes takes the default answers (also when there is no
# terminal to ask on); -n/--dry-run shows the plan and changes nothing;
# --parts=plugin,puzzles,... only these parts; --list prints, for each part
# offered, `part|installed version|offered version|size` and changes
# nothing (the in-app updater, pkupdate.lua, reads it).
# Environment: KOREADER_DIR (default /mnt/us/koreader), SF_PLATFORM (the
# Stockfish build, default from `uname -m`), PK_TTY (where answers are read,
# default /dev/tty: under `curl | sh` the script itself is on stdin).
#
# The parts (PARTS below, filled in by build-dist.sh, docs/releasing.md):
# the plugin, the puzzle pack, the emoji font, studies (local builds only)
# and Stockfish, each an archive checked against its sha256. What is
# installed is recorded in koreader/paperknight/.parts/<part> (its version,
# then the files it installed): a part already at the offered version is
# skipped, and an update first removes the files the previous version
# installed (studies you added yourself are kept).
#
# Safe against a download cut short (everything is in main(), called on the
# last line), a corrupted download (every part is downloaded and checked
# before anything changes) and a failed extraction (a staging folder; the
# plugin folder is swapped with mv and restored on failure). A part that
# fails leaves the parts before it installed: run the installer again.

PARTS='
@PARTS@
'
VERSION='@VERSION@'
DIST_URL='@DIST_URL@'

PLUGIN=plugins/paperknight.koplugin
STATE=paperknight/.parts
DL=.paperknight-download
NEW=.paperknight-new

say() { printf '%s\n' "$*"; }
cleanup() { rm -rf "$DL" "$NEW"; }
fail() { say "$*" >&2; cleanup; exit 1; }

label() {
    case "$1" in
        plugin) echo "Plugin" ;;
        puzzles) echo "Puzzle pack" ;;
        fonts) echo "Emoji font" ;;
        studies) echo "Studies" ;;
        stockfish) echo "Stockfish" ;;
        *) echo "$1" ;;
    esac
}

human() { # bytes
    if [ "$1" -ge 1048576 ]; then
        echo "$(( ($1 + 524288) / 1048576 )) MB"
    else
        echo "$(( ($1 + 1023) / 1024 )) KB"
    fi
}

first_line() { # file
    line=
    IFS= read -r line < "$1" || true
    echo "$line"
}

# the installed version of a part, "?" when installed by an older installer
# (no record), empty when not installed
installed_version() {
    if [ -f "$STATE/$1" ]; then
        first_line "$STATE/$1"
        return
    fi
    case "$1" in
        plugin)
            if [ -s "$PLUGIN/version.txt" ]; then
                first_line "$PLUGIN/version.txt"
            elif [ -f "$PLUGIN/main.lua" ]; then
                echo "?"
            fi ;;
        puzzles) [ -f "$PLUGIN/packs/puzzles.sqlite" ] && echo "?" ;;
        fonts) [ -f fonts/NotoEmoji.ttf ] && echo "?" ;;
        studies) [ -f paperknight/.pka-files ] && echo "?" ;;
        stockfish) [ -f "$PLUGIN/bin/stockfish" ] && echo "?" ;;
    esac
    return 0
}

ask() { # question, default (y or n); true for yes
    if [ "$YES" = 1 ]; then
        [ "$2" = y ]
        return
    fi
    if [ "$2" = y ]; then hint="[Y/n]"; else hint="[y/N]"; fi
    printf '%s %s ' "$1" "$hint"
    answer=
    IFS= read -r answer <&3 || true
    case "$answer" in
        [yY]*) return 0 ;;
        [nN]*) return 1 ;;
        *) [ "$2" = y ] ;;
    esac
}

platform() {
    if [ -n "${SF_PLATFORM:-}" ]; then
        echo "$SF_PLATFORM"
        return
    fi
    case "$(uname -m)" in
        armv7*) echo pw2 ;; # Stockfish for the PW2's Cortex-A9 (NEON)
    esac
}

wanted() { # part: true if in --parts (or no --parts)
    case ",${ONLY:-$1}," in
        *",$1,"*) return 0 ;;
    esac
    return 1
}

# decides what to install, in PARTS' order; prints the plan
plan() {
    SELECTED=
    sf_offered=
    sf_any=
    while IFS='|' read -r name version file sha size; do
        [ -n "$name" ] || continue
        case "$name" in
            stockfish-*)
                sf_any=1
                [ "$name" = "stockfish-$PLATFORM" ] || continue
                sf_offered=1
                part=stockfish ;;
            *) part=$name ;;
        esac
        wanted "$part" || continue
        have=$(installed_version "$part")
        if [ "$LIST" = 1 ]; then
            echo "$part|$have|$version|$size"
            continue
        fi
        what="$(label "$part")"
        if [ "$have" = "$version" ]; then
            printf '  %-12s %s\n' "$what" "up to date ($version)"
            continue
        fi
        if [ -z "$have" ]; then
            change="install $version"
        else
            change="$have -> $version"
        fi
        printf '  %-12s %s (%s)\n' "$what" "$change" "$(human "$size")"
        case "$part" in
            puzzles) [ -z "$have" ] || ask "    Update the puzzle pack?" y || continue ;;
            stockfish)
                if [ -z "$have" ]; then
                    ask "    Install Stockfish (analysis board, playing the engine)?" y || continue
                else
                    ask "    Update Stockfish?" y || continue
                fi ;;
        esac
        SELECTED="$SELECTED$part|$version|$file|$sha|$size
"
    done <<EOF
$PARTS
EOF
    if [ -n "$sf_any" ] && [ -z "$sf_offered" ] && [ "$LIST" = 0 ] && wanted stockfish; then
        printf '  %-12s %s\n' "Stockfish" "no build for this device ($(uname -m))"
    fi
    return 0
}

download() { # part, file, sha256, size -> the checked download in $DL
    case "$2" in
        *://*) url=$2 ;;
        *) url="$DIST_URL/$2" ;;
    esac
    out="$DL/${2##*/}"
    # no progress bar: kterm prints every redraw on a new line
    say "Downloading ${2##*/} ($(human "$4"))"
    curl -fksSL -o "$out.part" "$url" || fail "Download failed ($url): nothing changed."
    if command -v sha256sum >/dev/null 2>&1; then
        echo "$3  $out.part" | sha256sum -c - >/dev/null 2>&1 \
            || fail "Download corrupted or outdated installer (checksum of ${2##*/}): nothing changed."
    fi
    gzip -t "$out.part" 2>/dev/null || fail "Incomplete download (${2##*/}): nothing changed."
    case "$out" in
        *.tar.gz) gzip -dc "$out.part" | tar tf - >/dev/null 2>&1 \
            || fail "Incomplete download (${2##*/}): nothing changed." ;;
    esac
    mv "$out.part" "$out"
}

extract() { # archive -> $NEW
    rm -rf "$NEW"
    mkdir "$NEW"
    gzip -dc "$1" | tar xf - -C "$NEW" || fail "Extraction failed (disk full?): run the installer again."
}

install_plugin() { # archive, version
    extract "$1"
    [ -f "$NEW/$PLUGIN/main.lua" ] || fail "The plugin archive is incomplete: run the installer again."
    # the old plugin folder is set aside (a rename: no space needed) and
    # restored if the new one cannot be put in place
    rm -rf "$PLUGIN.old"
    [ -d "$PLUGIN" ] && mv "$PLUGIN" "$PLUGIN.old"
    mkdir -p plugins
    if ! mv "$NEW/$PLUGIN" "$PLUGIN"; then
        [ -d "$PLUGIN.old" ] && mv "$PLUGIN.old" "$PLUGIN"
        fail "Could not install the plugin: the previous version is kept."
    fi
    if [ -d "$PLUGIN.old" ]; then
        # parts of their own: the puzzle pack and Stockfish
        for dir in packs bin; do
            if [ -d "$PLUGIN.old/$dir" ]; then
                rm -rf "${PLUGIN:?}/$dir"
                mv "$PLUGIN.old/$dir" "$PLUGIN/$dir"
            fi
        done
        rm -rf "$PLUGIN.old"
    fi
    mkdir -p "$STATE"
    echo "$2" > "$STATE/plugin"
}

remove_listed() { # file listing paths (koreader-relative); only our folders
    while IFS= read -r file; do
        case "$file" in
            *..*|/*) ;;
            fonts/*|paperknight/*|"$PLUGIN"/packs/*|"$PLUGIN"/bin/*) rm -f "$file" ;;
        esac
    done < "$1"
}

install_files() { # part, archive, version
    extract "$2"
    # the files of the version installed before
    if [ -f "$STATE/$1" ]; then
        { IFS= read -r _ ; while IFS= read -r file; do echo "$file"; done; } < "$STATE/$1" > "$DL/old.files"
        remove_listed "$DL/old.files"
    elif [ "$1" = studies ] && [ -f paperknight/.pka-files ]; then
        # installed by pka.sh, which listed the fonts too: the studies only
        while IFS= read -r file; do
            case "$file" in paperknight/*) echo "$file" ;; esac
        done < paperknight/.pka-files > "$DL/old.files"
        remove_listed "$DL/old.files"
    fi
    if [ "$1" = studies ]; then
        # folders left empty (a renamed category); the two roots come back below
        find paperknight/studies paperknight/repertoires -depth -type d -exec rmdir {} \; 2>/dev/null || true
    fi
    (cd "$NEW" && find . -type f) > "$DL/new.files"
    : > "$DL/state"
    while IFS= read -r file; do
        file=${file#./}
        mkdir -p "$(dirname "$file")"
        mv "$NEW/$file" "$file" || fail "Could not install $file (disk full?): run the installer again."
        echo "$file" >> "$DL/state"
    done < "$DL/new.files"
    mkdir -p "$STATE"
    { echo "$3"; while IFS= read -r file; do echo "$file"; done < "$DL/state"; } > "$STATE/$1"
    [ "$1" = studies ] && rm -f paperknight/.pka-files
    rm -rf "$NEW"
}

install_stockfish() { # archive, version
    mkdir -p "$PLUGIN/bin"
    gzip -dc "$1" > "$PLUGIN/bin/stockfish.part" || {
        rm -f "$PLUGIN/bin/stockfish.part"
        fail "Could not unpack Stockfish (disk full?): run the installer again."
    }
    chmod +x "$PLUGIN/bin/stockfish.part"
    mv "$PLUGIN/bin/stockfish.part" "$PLUGIN/bin/stockfish"
    mkdir -p "$STATE"
    printf '%s\n%s\n' "$2" "$PLUGIN/bin/stockfish" > "$STATE/stockfish"
    if ! echo quit | "$PLUGIN/bin/stockfish" 2>/dev/null | grep -q Stockfish; then
        say "Stockfish is installed but did not start on this device."
    fi
}

main() {
    set -e
    YES=0
    DRY=0
    LIST=0
    ONLY=
    for arg in "$@"; do
        case "$arg" in
            -y|--yes) YES=1 ;;
            -n|--dry-run) DRY=1 ;;
            --list) LIST=1 ;;
            --parts=*) ONLY=${arg#--parts=} ;;
            *) fail "unknown option: $arg (options: --yes, --dry-run, --parts=a,b, --list)" ;;
        esac
    done
    [ "$DRY" = 1 ] || [ "$LIST" = 1 ] && YES=1 # the plan with the default answers
    KOREADER_DIR=${KOREADER_DIR:-/mnt/us/koreader}
    PK_TTY=${PK_TTY:-/dev/tty}
    # answers are read on fd 3; no terminal to ask on (run by a script):
    # the default answers
    if [ "$YES" = 0 ]; then
        if (: < "$PK_TTY") 2>/dev/null; then
            exec 3< "$PK_TTY"
        else
            YES=1
        fi
    fi
    PLATFORM=$(platform)

    [ -d "$KOREADER_DIR" ] || fail "KOReader not found in $KOREADER_DIR (set KOREADER_DIR)."
    cd "$KOREADER_DIR"
    if [ "$LIST" = 1 ]; then
        plan
        return 0
    fi
    say "Paperknight $VERSION"
    say "KOReader: $KOREADER_DIR"
    plan
    if [ -z "$SELECTED" ]; then
        say "Everything is up to date."
        return 0
    fi
    if [ "$DRY" = 1 ]; then
        say "Dry run: nothing changed."
        return 0
    fi
    ask "Go?" y || { say "Nothing changed."; return 0; }

    cleanup
    mkdir -p "$DL"
    trap cleanup EXIT
    while IFS='|' read -r part version file sha size; do
        [ -n "$part" ] || continue
        download "$part" "$file" "$sha" "$size"
    done <<EOF
$SELECTED
EOF
    while IFS='|' read -r part version file sha size; do
        [ -n "$part" ] || continue
        say "Installing $(label "$part" | tr 'A-Z' 'a-z') $version"
        archive="$DL/${file##*/}"
        case "$part" in
            plugin) install_plugin "$archive" "$version" ;;
            stockfish) install_stockfish "$archive" "$version" ;;
            *) install_files "$part" "$archive" "$version" ;;
        esac
    done <<EOF
$SELECTED
EOF
    mkdir -p paperknight/studies paperknight/repertoires
    # left by the installers before this one
    rm -rf pka.tar.gz pkc.tar.gz .pka-new
    cleanup
    say "Done. Restart KOReader."
}

main "$@"
