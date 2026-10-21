#!/bin/bash
set -euo pipefail

CX_APP="${1:-$HOME/Applications/CrossOver.app}"
OUT_DIR="${OUT_DIR:-$HOME/Library/Application Support/MacGamer/downloads}"
ARTIFACT_NAME="${ARTIFACT_NAME:-winecx-26.3-osx64.tar.xz}"
CX_ROOT="$CX_APP/Contents/SharedSupport/CrossOver"

if [[ ! -x "$CX_ROOT/bin/wineloader" ]]; then
  echo "error: wineloader not found in $CX_ROOT" >&2
  exit 1
fi

STAGE=$(mktemp -d /tmp/winecx-stage.XXXXXX)
cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT

mkdir -p "$STAGE/bin" "$STAGE/lib" "$STAGE/share"
cp -f "$CX_ROOT/bin/wineloader" "$STAGE/bin/wine"
cp -f "$CX_ROOT/bin/wineserver" "$STAGE/bin/wineserver"
chmod +x "$STAGE/bin/wine" "$STAGE/bin/wineserver"
ln -sf wine "$STAGE/bin/wine64"
ln -sf wineserver "$STAGE/bin/wineserver64" 2>/dev/null || true

rsync -a "$CX_ROOT/lib/wine/" "$STAGE/lib/wine/"
if [[ -d "$CX_ROOT/share/wine" ]]; then
  rsync -a "$CX_ROOT/share/wine/" "$STAGE/share/wine/"
fi

mkdir -p "$STAGE/lib64"
if [[ -d "$CX_ROOT/lib64" ]]; then
  for lib in libfreetype.6.dylib libfreetype.dylib libgnutls.30.dylib libgnutls.dylib \
    libMoltenVK.dylib libgmp.10.dylib libgmp.dylib libnettle.8.dylib libhogweed.6.dylib \
    libp11-kit.0.dylib libtasn1.6.dylib libintl.8.dylib libunistring.5.dylib libidn2.0.dylib \
    libSDL2-2.0.0.dylib libpng16.16.dylib; do
    if [[ -f "$CX_ROOT/lib64/$lib" ]]; then
      cp -f "$CX_ROOT/lib64/$lib" "$STAGE/lib64/"
      cp -f "$CX_ROOT/lib64/$lib" "$STAGE/lib/"
    fi
  done
fi
BREW_PREFIX="${BREW_PREFIX:-/usr/local}"
for lib in libfreetype.6.dylib libgnutls.30.dylib libSDL2-2.0.0.dylib libMoltenVK.dylib \
  libintl.8.dylib libpng16.16.dylib libbrotlidec.1.dylib libbrotlicommon.1.dylib \
  libp11-kit.0.dylib libtasn1.6.dylib libunistring.5.dylib libidn2.0.dylib \
  libhogweed.6.dylib libnettle.8.dylib libgmp.10.dylib; do
  if [[ -f "$STAGE/lib/$lib" ]]; then
    continue
  fi
  src=$(find "$BREW_PREFIX/opt" "$BREW_PREFIX/Cellar" "$CX_ROOT/lib" -name "$lib" 2>/dev/null | head -1 || true)
  if [[ -n "${src:-}" && -f "$src" ]]; then
    cp -f "$src" "$STAGE/lib/"
  fi
done

WINEMAC="$STAGE/lib/wine/x86_64-unix/winemac.so"
if [[ ! -f "$WINEMAC" ]]; then
  echo "error: missing $WINEMAC" >&2
  exit 1
fi
if ! nm -gU "$WINEMAC" | grep -q 'macdrv_functions'; then
  echo "error: packaged wine lacks macdrv_functions" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
ARTIFACT="$OUT_DIR/$ARTIFACT_NAME"
rm -f "$ARTIFACT"
tar -C "$STAGE" -cJf "$ARTIFACT" .
SHA=$(shasum -a 256 "$ARTIFACT" | awk '{print $1}')
echo "artifact=$ARTIFACT"
echo "sha256=$SHA"
echo "note: LGPL Wine tree packaged from CrossOver FOSS build; prefer tools/build-winecx.sh for a from-source artifact"
