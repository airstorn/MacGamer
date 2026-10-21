#!/bin/bash
set -euo pipefail
if [[ "$(sysctl -n sysctl.proc_translated 2>/dev/null || echo 0)" != "1" ]] \
  && [[ "$(uname -m)" == "arm64" ]]; then
  exec /usr/bin/arch -x86_64 /bin/bash "$0" "$@"
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PATCH="$ROOT/tools/patches/winecoreaudio-period-frames.patch"
CX_VERSION="${CX_VERSION:-26.3.0}"
WORKROOT="${WORKROOT:-$HOME/winecx-build-${CX_VERSION}}"
BUILD="$WORKROOT/build/wine64"
RUNTIME="${1:-$HOME/Library/Application Support/MacGamer/runtimes/winecx-26.2}"
SRC="$WORKROOT/sources/wine/dlls/winecoreaudio.drv/coreaudio.c"

if [[ ! -f "$SRC" ]]; then
  echo "error: missing sources at $SRC (run tools/build-winecx.sh first)" >&2
  exit 1
fi
if [[ ! -f "$PATCH" ]]; then
  echo "error: missing $PATCH" >&2
  exit 1
fi

if ! grep -q 'set_device_period_frame_size' "$SRC"; then
  patch -d "$WORKROOT/sources/wine" -p1 < "$PATCH"
fi

export PATH="$WORKROOT/toolchains/llvm-mingw-20231017-ucrt-macos-universal/bin:/usr/local/bin:/usr/bin:/bin"
export CC="/usr/bin/clang" CXX="/usr/bin/clang++"
export CFLAGS="-O3 -Wno-implicit-function-declaration -Wno-deprecated-declarations -Wno-format"
export LDFLAGS="-Wl,-rpath,@loader_path/../../"
export MACOSX_DEPLOYMENT_TARGET=10.14
export CROSSCFLAGS="-O3"

make -C "$BUILD/dlls/winecoreaudio.drv" -j"$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

DEST="$RUNTIME/lib/wine/x86_64-unix/winecoreaudio.so"
cp -f "$DEST" "${DEST}.bak-pre-period-patch" 2>/dev/null || true
cp -f "$BUILD/dlls/winecoreaudio.drv/winecoreaudio.so" "$DEST"
codesign -s - -f "$DEST" >/dev/null 2>&1 || true
echo "installed: $DEST"
