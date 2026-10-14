#!/bin/sh
# Builds the Kindle Stockfish (docs/stockfish.md): a static ARMv7 + NEON
# binary against musl (the PW2's kernel 3.0 is too old for a static glibc
# binary), with Zig's cross compiler. Output in build/dist/: stockfish,
# stockfish.gz, the source tarball, and stockfish.sh with the checksum.
# Usage: tools/dist/build-stockfish.sh [sf_tag]   (default sf_19)
set -eu
# where the files are served from, baked into the installers
DIST_URL="${PAPERKNIGHT_DIST_URL:?set PAPERKNIGHT_DIST_URL to the base URL of the served files}"
TAG="${1:-sf_19}"
ZIG_VERSION="0.17.0"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$ROOT/build/stockfish"
OUT="$ROOT/build/dist"
mkdir -p "$WORK" "$OUT"
cd "$WORK"

if [ ! -x "zig-x86_64-linux-$ZIG_VERSION/zig" ]; then
    curl -fsSL "https://ziglang.org/download/$ZIG_VERSION/zig-x86_64-linux-$ZIG_VERSION.tar.xz" -o zig.tar.xz
    tar xf zig.tar.xz
fi
if [ ! -d "Stockfish-$TAG" ]; then
    curl -fsSL "https://github.com/official-stockfish/Stockfish/archive/refs/tags/$TAG.tar.gz" -o "$TAG.tar.gz"
    tar xzf "$TAG.tar.gz"
fi
export PATH="$WORK/zig-x86_64-linux-$ZIG_VERSION:$PATH"
cd "Stockfish-$TAG/src"
make net
# -Wno-date-time: zig makes __DATE__ (the version string) an error; -s strips
make -j"$(nproc)" build ARCH=armv7-neon COMP=clang \
    COMPCXX="zig c++ -target arm-linux-musleabihf -mcpu=cortex_a9" \
    EXTRACXXFLAGS="-Wno-date-time" EXTRALDFLAGS="-static -s"

cp stockfish "$OUT/stockfish"
gzip -9 -c stockfish > "$OUT/stockfish.gz"
cp "$WORK/$TAG.tar.gz" "$OUT/stockfish-$TAG-src.tar.gz"
SHA="$(sha256sum "$OUT/stockfish.gz" | cut -d' ' -f1)"
sed -e "s/@SF_SHA256@/$SHA/" -e "s#@DIST_URL@#$DIST_URL#" "$ROOT/tools/dist/stockfish.sh" > "$OUT/stockfish.sh"
echo "build/dist: stockfish, stockfish.gz ($SHA), stockfish-$TAG-src.tar.gz, stockfish.sh"
