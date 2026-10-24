#!/bin/sh
# Release notes (Markdown) from the Conventional Commits, with git-cliff
# (cliff.toml: features, fixes, performance, by area). docs/releasing.md.
#   tools/dist/release-notes.sh               the latest v* tag's changes
#   tools/dist/release-notes.sh --unreleased  the changes since that tag
set -eu
cd "$(dirname "$0")/../.."
# git-cliff: on the PATH, or in the pipeline's venv (make venv)
CLIFF=git-cliff
command -v git-cliff >/dev/null || CLIFF=pipeline/.venv/bin/git-cliff
[ -x "$(command -v "$CLIFF")" ] || { echo "release-notes: git-cliff not found (make venv, or pip install git-cliff)" >&2; exit 1; }
"$CLIFF" --config cliff.toml --strip all "${1:---latest}" 2>/dev/null | sed '/./,$!d'
