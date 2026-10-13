#!/usr/bin/env arch -x86_64 /bin/bash
set -euo pipefail

CX_VERSION="${CX_VERSION:-26.2.0}"
SOURCE_URL="${SOURCE_URL:-https://media.codeweavers.com/pub/crossover/source/crossover-sources-${CX_VERSION}.tar.gz}"
LLVM_MINGW_URL="${LLVM_MINGW_URL:-https://github.com/mstorsjo/llvm-mingw/releases/download/20231017/llvm-mingw-20231017-ucrt-macos-universal.tar.xz}"
MONO_URL="${MONO_URL:-https://github.com/madewokherd/wine-mono/releases/download/wine-mono-9.0.0/wine-mono-9.0.0-x86.tar.xz}"
WORKROOT="${WORKROOT:-$HOME/winecx-build}"
JOBS="${JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || echo 4)}"
OUT_DIR="${OUT_DIR:-$HOME/Library/Application Support/MacGamer/downloads}"
ARTIFACT_NAME="winecx-${CX_VERSION%.*}-osx64.tar.xz"

echo "deps: Intel Homebrew (/usr/local), bison pkg-config freetype gnutls molten-vk sdl2 coreutils"
echo "workroot: $WORKROOT (no spaces)"
echo "artifact: $OUT_DIR/$ARTIFACT_NAME"

if [[ "$WORKROOT" == *" "* ]]; then
  echo "error: WORKROOT must not contain spaces" >&2
  exit 1
fi

if [[ ! -x /usr/local/bin/brew ]]; then
  echo "error: need Intel Homebrew at /usr/local/bin/brew (Rosetta)" >&2
  exit 1
fi

export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_UPGRADE=1
export HOMEBREW_NO_ENV_HINTS=1
export NONINTERACTIVE=1
BREW=/usr/local/bin/brew
need_install=()
for formula in bison pkgconf coreutils freetype gnutls molten-vk sdl2; do
  if $BREW list --formula "$formula" &>/dev/null; then
    echo "brew: $formula already installed"
  elif $BREW list --formula pkg-config &>/dev/null && [[ "$formula" == "pkgconf" ]]; then
    echo "brew: pkg-config already installed"
  else
    need_install+=("$formula")
  fi
done
if ((${#need_install[@]})); then
  $BREW install "${need_install[@]}" || true
fi

mkdir -p "$WORKROOT" "$OUT_DIR"
cd "$WORKROOT"

if [[ ! -f "crossover-sources-${CX_VERSION}.tar.gz" ]]; then
  echo "download sources"
  curl -fL "$SOURCE_URL" -o "crossover-sources-${CX_VERSION}.tar.gz"
fi

if [[ ! -d sources/wine ]]; then
  echo "extract sources"
  rm -rf sources
  mkdir -p sources-tmp
  tar -xzf "crossover-sources-${CX_VERSION}.tar.gz" -C sources-tmp
  if [[ -d sources-tmp/sources ]]; then
    mv sources-tmp/sources .
  else
    inner=$(find sources-tmp -maxdepth 2 -type d -name wine | head -1)
    if [[ -z "$inner" ]]; then
      echo "error: wine tree not found in tarball" >&2
      exit 1
    fi
    mkdir -p sources
    mv "$(dirname "$inner")"/* sources/ 2>/dev/null || true
    if [[ ! -d sources/wine ]]; then
      parent=$(dirname "$inner")
      rm -rf sources
      mv "$parent" sources
    fi
  fi
  rm -rf sources-tmp
fi

WINE_CONFIGURE="$WORKROOT/sources/wine/configure"
if [[ ! -x "$WINE_CONFIGURE" && ! -f "$WINE_CONFIGURE" ]]; then
  echo "error: missing $WINE_CONFIGURE" >&2
  exit 1
fi
chmod +x "$WINE_CONFIGURE" || true

if [[ ! -d toolchains/llvm-mingw-20231017-ucrt-macos-universal ]]; then
  echo "download llvm-mingw"
  curl -fL "$LLVM_MINGW_URL" -o llvm-mingw.tar.xz
  mkdir -p toolchains
  tar -xJf llvm-mingw.tar.xz -C toolchains
fi
export PATH="$WORKROOT/toolchains/llvm-mingw-20231017-ucrt-macos-universal/bin:$PATH"

export CC="/usr/bin/clang"
export CXX="${CC}++"
export BISON="$($BREW --prefix bison)/bin/bison"
export x86_64_CC="x86_64-w64-mingw32-gcc"
export i386_CC="i686-w64-mingw32-gcc"
export CFLAGS="-O3 -Wno-implicit-function-declaration -Wno-deprecated-declarations -Wno-format"
export LDFLAGS="-Wl,-rpath,@loader_path/../../"
export MACOSX_DEPLOYMENT_TARGET=10.14
export CROSSCFLAGS="-O3"
export SDL2_CFLAGS="-I$($BREW --prefix sdl2)/include -I$($BREW --prefix sdl2)/include/SDL2"
export PKG_CONFIG_PATH="$($BREW --prefix)/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
export ac_cv_lib_soname_MoltenVK="libMoltenVK.dylib"
export ac_cv_lib_soname_vulkan=""

BUILDROOT="$WORKROOT/build"
INSTALLROOT="$WORKROOT/install"
PREFIX_NAME="winecx"
rm -rf "$BUILDROOT/wine64" "$INSTALLROOT/$PREFIX_NAME"
mkdir -p "$BUILDROOT/wine64" "$INSTALLROOT/$PREFIX_NAME"

echo "configure wine"
pushd "$BUILDROOT/wine64" >/dev/null
"$WINE_CONFIGURE" \
  --prefix=/usr/local \
  --disable-option-checking \
  --enable-win64 \
  --enable-archs=i386,x86_64 \
  --disable-tests \
  --without-alsa \
  --without-capi \
  --with-coreaudio \
  --with-cups \
  --without-dbus \
  --without-fontconfig \
  --with-freetype \
  --with-gettext \
  --without-gettextpo \
  --without-gphoto \
  --with-gnutls \
  --without-gssapi \
  --without-gstreamer \
  --without-inotify \
  --without-krb5 \
  --with-mingw \
  --without-netapi \
  --with-opencl \
  --with-opengl \
  --without-oss \
  --with-pcap \
  --with-pthread \
  --without-pulse \
  --without-sane \
  --with-sdl \
  --without-udev \
  --with-unwind \
  --without-usb \
  --without-v4l2 \
  --with-vulkan \
  --without-x
popd >/dev/null

echo "make wine (jobs=$JOBS)"
make -C "$BUILDROOT/wine64" -j"$JOBS"

echo "install wine"
make -C "$BUILDROOT/wine64" -j"$JOBS" install-lib DESTDIR="$INSTALLROOT/$PREFIX_NAME"

STAGE="$INSTALLROOT/$PREFIX_NAME/usr/local"
if [[ ! -d "$STAGE/bin" ]]; then
  echo "error: install layout missing $STAGE/bin" >&2
  exit 1
fi

if [[ ! -d "$STAGE/share/wine/mono" ]]; then
  echo "install wine-mono"
  curl -fL "$MONO_URL" -o "$WORKROOT/wine-mono.tar.xz"
  mkdir -p "$STAGE/share/wine/mono"
  tar -xJf "$WORKROOT/wine-mono.tar.xz" -C "$STAGE/share/wine/mono"
fi

MVK="$($BREW --prefix molten-vk)/lib/libMoltenVK.dylib"
if [[ -f "$MVK" ]]; then
  cp -f "$MVK" "$STAGE/lib/libMoltenVK.dylib"
fi

WINEMAC=$(find "$STAGE" -name 'winemac.so' | head -1 || true)
if [[ -z "$WINEMAC" ]]; then
  echo "error: winemac.so not found after install" >&2
  exit 1
fi
if ! nm -gU "$WINEMAC" | grep -q 'macdrv_functions'; then
  echo "error: $WINEMAC does not export macdrv_functions" >&2
  nm -gU "$WINEMAC" | head -40 >&2 || true
  exit 1
fi
echo "ok: macdrv_functions in $WINEMAC"

mkdir -p "$OUT_DIR"
ARTIFACT="$OUT_DIR/$ARTIFACT_NAME"
rm -f "$ARTIFACT"
tar -C "$STAGE" -cJf "$ARTIFACT" .
SHA=$(shasum -a 256 "$ARTIFACT" | awk '{print $1}')
echo "artifact=$ARTIFACT"
echo "sha256=$SHA"
echo "done"
