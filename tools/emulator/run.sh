#!/usr/bin/env bash
# Run the desktop KOReader with Paperknight loaded (ADR-0007).
#   run.sh window                 visible window (needs a display)
#   run.sh e2e <scenario.lua>...  headless scenarios; exit 1 if any fails
#
# The plugin is linked into KOReader's own plugins/ folder, so KOReader loads it
# through the relative path "plugins/paperknight.koplugin" exactly like on a
# Kindle (a user-dir install would hide relative-path bugs).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD="$ROOT/build"
KOREADER="$BUILD/koreader/bin/koreader"
KO_PLUGINS="$BUILD/koreader/lib/koreader/plugins"
HOME_DIR="$BUILD/emulator-home"
OUT="$BUILD/e2e"

[[ -x "$KOREADER" ]] || { echo "KOReader missing: run 'make koreader'" >&2; exit 2; }

install_plugins() {
    ln -sfn "$ROOT/plugin/paperknight.koplugin" "$KO_PLUGINS/paperknight.koplugin"
    ln -sfn "$ROOT/tools/emulator/harness.koplugin" "$KO_PLUGINS/pkharness.koplugin"
    mkdir -p "$HOME_DIR/books"
}

# Isolate from the developer's own KOReader: with KO_MULTIUSER (set by the
# launcher) KOReader honours KO_HOME and XDG_CONFIG_HOME before HOME.
unset KO_HOME XDG_CONFIG_HOME PK_SCENARIO PK_RESULT
export HOME="$HOME_DIR"
export EMULATE_READER_W="${EMULATE_READER_W:-758}"   # Kindle Paperwhite 2
export EMULATE_READER_H="${EMULATE_READER_H:-1024}"

mode="${1:-}"; shift || true
install_plugins
case "$mode" in
    window)
        exec "$KOREADER" "$HOME_DIR/books"
        ;;
    e2e)
        [[ $# -gt 0 ]] || { echo "e2e: no scenarios given" >&2; exit 2; }
        mkdir -p "$OUT"
        failed=0
        for scenario in "$@"; do
            name="$(basename "$scenario" .lua)"
            log="$OUT/$name.log"; result="$OUT/$name.result"
            rm -f "$result"
            # Fresh KOReader state every run: each scenario is a first launch.
            rm -rf "$HOME_DIR/.config/koreader"
            set +e
            SDL_VIDEODRIVER=offscreen PK_SCENARIO="$(realpath "$scenario")" PK_RESULT="$result" \
                PK_SHOTS_DIR="$OUT" timeout "${PK_TIMEOUT:-120}" "$KOREADER" "$HOME_DIR/books" >"$log" 2>&1
            code=$?
            set -e
            status="$(head -n1 "$result" 2>/dev/null || true)"
            [[ -n "$status" ]] || status="FAIL: no result written"
            if [[ "$status" == PASS && $code -ne 0 ]]; then
                status="FAIL: KOReader exited with code $code"
            fi
            # Any error in the log fails the run (the baseline log has none).
            # Handler errors span several lines, so don't filter by plugin name.
            if [[ "$status" == PASS ]] && grep -qE "ERROR|stack traceback" "$log"; then
                status="FAIL: errors in log"
            fi
            echo "$name: $status (log: ${log#"$ROOT"/})"
            if [[ "$status" != PASS ]]; then
                failed=1
                sed -n '2,40p' "$result" 2>/dev/null || true
                grep -nE -A8 "ERROR|stack traceback" "$log" | head -40 || true
            fi
        done
        exit $failed
        ;;
    *)
        echo "usage: $0 window | e2e <scenario.lua>..." >&2; exit 2
        ;;
esac
