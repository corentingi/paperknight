#!/bin/sh
# Builds the Kindle Stockfish (docs/stockfish.md): a static ARMv7 + NEON
# binary against musl (the PW2's kernel 3.0 is too old for a static glibc
# binary), with Zig's cross compiler. Output in build/dist/: stockfish,
# stockfish.gz, the source tarball, and stockfish.sh with the checksum.
# A patch tools/dist/stockfish-<tag>-*.patch is applied when there is one:
# for sf_18, the small network only (~4 MB binary, tens of MB of RAM instead
# of ~130 MB, ADR-0016).
# Usage: tools/dist/build-stockfish.sh [sf_tag]   (default sf_18)
# SF_PLATFORM: the device built for (default pw2, the only one so far); when
# given (releases), the outputs are named stockfish-<platform>.*.
set -eu
# where the files are served from, baked into the installers
DIST_URL="${PAPERKNIGHT_DIST_URL:?set PAPERKNIGHT_DIST_URL to the base URL of the served files}"
TAG="${1:-sf_18}"
ZIG_VERSION="0.17.0"
ZIG_SHA256=1cbe9df9f27e6b78d14ccbca43b6703a404ef79ef1c463de901d7f088d4e2026
PLATFORM="${SF_PLATFORM:-pw2}"
case "$PLATFORM" in
    # Kindle Paperwhite 2: Cortex-A9 with NEON, kernel 3.0 (a static musl
    # binary: no system library)
    pw2) SF_ARCH=armv7-neon; ZIG_TARGET=arm-linux-musleabihf; ZIG_CPU=cortex_a9 ;;
    *) echo "unknown platform: $PLATFORM (known: pw2)" >&2; exit 1 ;;
esac
NAME="stockfish${SF_PLATFORM:+-$SF_PLATFORM}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$ROOT/build/stockfish"
OUT="$ROOT/build/dist"
mkdir -p "$WORK" "$OUT"
cd "$WORK"

if [ ! -x "zig-x86_64-linux-$ZIG_VERSION/zig" ]; then
    curl -fsSL "https://ziglang.org/download/$ZIG_VERSION/zig-x86_64-linux-$ZIG_VERSION.tar.xz" -o zig.tar.xz
    echo "$ZIG_SHA256  zig.tar.xz" | sha256sum -c - >/dev/null || { echo "zig: checksum mismatch" >&2; exit 1; }
    tar xf zig.tar.xz
fi
[ -f "$TAG.tar.gz" ] || curl -fsSL "https://github.com/official-stockfish/Stockfish/archive/refs/tags/$TAG.tar.gz" -o "$TAG.tar.gz"
# always from a clean tree, so that the patch applies once
rm -rf "Stockfish-$TAG"
tar xzf "$TAG.tar.gz"
for patch in "$ROOT"/tools/dist/stockfish-"$TAG"-*.patch; do
    [ -f "$patch" ] || continue
    echo "applying $(basename "$patch")"
    patch -d "Stockfish-$TAG" -p1 < "$patch"
done
export PATH="$WORK/zig-x86_64-linux-$ZIG_VERSION:$PATH"
cd "Stockfish-$TAG/src"
make net
# -Wno-date-time: zig makes __DATE__ (the version string) an error; -s strips
make -j"$(nproc)" build ARCH="$SF_ARCH" COMP=clang \
    COMPCXX="zig c++ -target $ZIG_TARGET -mcpu=$ZIG_CPU" \
    EXTRACXXFLAGS="-Wno-date-time" EXTRALDFLAGS="-static -s"

cp stockfish "$OUT/$NAME"
gzip -9 -c stockfish > "$OUT/$NAME.gz"
# the corresponding source (GPL): the release and the patch applied
cp "$WORK/$TAG.tar.gz" "$OUT/stockfish-$TAG-src.tar.gz"
for patch in "$ROOT"/tools/dist/stockfish-"$TAG"-*.patch; do
    [ -f "$patch" ] && cp "$patch" "$OUT/"
done
SHA="$(sha256sum "$OUT/$NAME.gz" | cut -d' ' -f1)"
sed -e "s/@SF_SHA256@/$SHA/" -e "s#@DIST_URL@#$DIST_URL#" -e "s#@SF_ASSET@#$NAME.gz#" \
    "$ROOT/tools/dist/stockfish.sh" > "$OUT/$NAME.sh"
echo "build/dist: $NAME, $NAME.gz ($SHA), stockfish-$TAG-src.tar.gz, $NAME.sh"
