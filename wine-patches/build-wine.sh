#!/bin/sh
# Build WINE master with the CODESYS patches in this directory.
# Nothing is installed system-wide: the result runs in place as $WINE_DEV/build/wine.
#
# Usage: wine-patches/build-wine.sh [--deps]
#   --deps   install the Debian/Ubuntu build dependencies first (uses sudo)
#
# Environment:
#   WINE_DEV     work directory (default: ~/wine-dev)
#   WINE_COMMIT  upstream commit the patches are tested against (default below)
#   JOBS         parallel make jobs (default: nproc)
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
WINE_DEV=${WINE_DEV:-$HOME/wine-dev}
WINE_COMMIT=${WINE_COMMIT:-6d1b094}
JOBS=${JOBS:-$(nproc)}

DEPS="gcc-mingw-w64 flex bison gettext libx11-dev libxext-dev libxrender-dev libxrandr-dev
libxi-dev libxcursor-dev libxcomposite-dev libxfixes-dev libxinerama-dev libxxf86vm-dev
libxkbcommon-dev libxkbregistry-dev libwayland-dev libfreetype-dev libfontconfig-dev
libgnutls28-dev libgl-dev libegl-dev libosmesa6-dev libvulkan-dev libpulse-dev libasound2-dev
libdbus-1-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev libsdl2-dev libudev-dev
libusb-1.0-0-dev libpcsclite-dev libcups2-dev libunwind-dev libkrb5-dev libsane-dev libv4l-dev
libpcap-dev libgphoto2-dev"

if [ "${1:-}" = "--deps" ]; then
    # shellcheck disable=SC2086
    sudo apt-get install -y build-essential git $DEPS
fi

mkdir -p "$WINE_DEV"
if [ ! -d "$WINE_DEV/src/.git" ]; then
    git clone https://gitlab.winehq.org/wine/wine.git "$WINE_DEV/src"
fi

cd "$WINE_DEV/src"
git fetch -q origin
if git rev-parse -q --verify codesys-wine >/dev/null; then
    echo "Branch codesys-wine already exists in $WINE_DEV/src, leaving it as is."
else
    git checkout -q -b codesys-wine "$WINE_COMMIT"
    git am "$HERE"/*.patch
fi

mkdir -p "$WINE_DEV/build"
cd "$WINE_DEV/build"
[ -f Makefile ] || ../src/configure --enable-archs=i386,x86_64
nice make -j"$JOBS"

echo
echo "Done: $("$WINE_DEV/build/wine" --version)"
echo "Run it in place, for example:"
echo "  WINEPREFIX=<copy of your CODESYS prefix> $WINE_DEV/build/wine ..."
echo "The first start updates the prefix to this WINE version. Use a copy."
