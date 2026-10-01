#!/usr/bin/env bash
# CodeMeter client for CODESYS under WINE: puts WIBU's API DLLs (WibuCm64.dll,
# WibuCm32.dll) into the prefix, without the Windows CodeMeter service.
# CODESYS then talks to a CodeMeter runtime running natively on Linux (or on
# another machine) over TCP port 22350: dongles, soft containers, network
# licenses.
#
# Usage: install/codemeter-client.sh apply <CodeMeterRuntime64.msi>
#        install/codemeter-client.sh remove
#        install/codemeter-client.sh status
#
# The MSI ships inside the CODESYS setup (install.sh extracts it). Needs 7z.
# WINEPREFIX selects the prefix (default ~/.local/share/wineprefixes/codesys).
set -euo pipefail

export WINEPREFIX="${WINEPREFIX:-$HOME/.local/share/wineprefixes/codesys}"
export WINEDEBUG="${WINEDEBUG:--all}"
STATE="$WINEPREFIX/codesys-wine-codemeter"
SYS64="$WINEPREFIX/drive_c/windows/system32"
SYS32="$WINEPREFIX/drive_c/windows/syswow64"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

apply() {
  local msi="${1:?usage: $0 apply <CodeMeterRuntime64.msi>}" tmp
  [ -f "$msi" ] || die "not found: $msi"
  command -v 7z >/dev/null || die "missing: 7z (Debian/Ubuntu package 7zip)"
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' RETURN
  7z e -y -o"$tmp/cab" "$msi" '*.cab' >/dev/null
  # Files in the cabinets are named <file>.<component GUID>.
  local c
  for c in "$tmp/cab/"*.cab; do
    7z e -y -o"$tmp/files" "$c" 'WibuCm64.dll.*' 'WibuCm32.dll.*' >/dev/null
  done
  local w64 w32
  w64="$(ls "$tmp/files"/WibuCm64.dll.* 2>/dev/null | head -n1)"
  w32="$(ls "$tmp/files"/WibuCm32.dll.* 2>/dev/null | head -n1)"
  [ -n "$w64" ] && [ -n "$w32" ] || die "WibuCm64.dll/WibuCm32.dll not found in $msi"
  if ! timeout 20 wineserver -w 2>/dev/null; then
    die "programs are still running in $WINEPREFIX; close CODESYS and run this again."
  fi
  mkdir -p "$STATE"
  cp "$w64" "$SYS64/WibuCm64.dll.new" && mv "$SYS64/WibuCm64.dll.new" "$SYS64/WibuCm64.dll"
  cp "$w32" "$SYS32/WibuCm32.dll.new" && mv "$SYS32/WibuCm32.dll.new" "$SYS32/WibuCm32.dll"
  (cd "$WINEPREFIX/drive_c/windows" && sha256sum system32/WibuCm64.dll syswow64/WibuCm32.dll) > "$STATE/installed.sha256"
  echo "CodeMeter client: installed (WibuCm64.dll, WibuCm32.dll)."
  if ! (exec 3<>/dev/tcp/127.0.0.1/22350) 2>/dev/null; then
    echo "CodeMeter client: note, no CodeMeter runtime answers on localhost:22350."
    echo "  For dongles and licenses, install CodeMeter for Linux (WIBU, or the"
    echo "  'CODESYS CodeMeter for Linux SL' package), or set a network server."
  fi
}

remove() {
  [ -d "$STATE" ] || { echo "CodeMeter client: not installed by this script."; return 0; }
  timeout 20 wineserver -w 2>/dev/null || die "programs are still running in $WINEPREFIX; close them first."
  rm -f "$SYS64/WibuCm64.dll" "$SYS32/WibuCm32.dll"
  rm -rf "$STATE"
  echo "CodeMeter client: removed."
}

status() {
  if [ -f "$STATE/installed.sha256" ]; then
    (cd "$WINEPREFIX/drive_c/windows" && sha256sum --quiet -c "$STATE/installed.sha256") \
      && echo "CodeMeter client: installed" || echo "CodeMeter client: changed since install"
  else
    echo "CodeMeter client: not installed"
  fi
  if (exec 3<>/dev/tcp/127.0.0.1/22350) 2>/dev/null; then
    echo "CodeMeter runtime on localhost:22350: reachable"
  else
    echo "CodeMeter runtime on localhost:22350: not reachable"
  fi
}

case "${1:-}" in
  apply) shift; apply "$@" ;;
  remove) remove ;;
  status) status ;;
  *) sed -n '2,13p' "$0"; exit 1 ;;
esac
