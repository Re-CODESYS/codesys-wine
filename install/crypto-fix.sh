#!/usr/bin/env bash
# Online-login fix for CODESYS under WINE: patched ncrypt.dll and bcrypt.dll
# ("Route A" in wine-patches/README.md), used by CODESYS.exe only.
#
# Usage: install/crypto-fix.sh apply  [--dlls DIR] [--yes] [--force]
#        install/crypto-fix.sh remove
#        install/crypto-fix.sh status
#
#   --dlls DIR  where the patched DLLs are. Either a release folder with
#               x86_64-windows/ and i386-windows/ (and optionally SHA256SUMS),
#               or a WINE build tree (DIR/dlls/<name>/<arch>-windows/).
#               Default: $CODESYS_WINE_FIX_DLLS, then ~/wine-dev/build.
#   --yes       don't ask, just print the explanation and continue
#   --force     apply on an untested WINE version
#
# WINEPREFIX selects the prefix (default ~/.local/share/wineprefixes/codesys).
# The originals are backed up in $WINEPREFIX/codesys-wine-crypto-fix/ and
# restored by "remove".
set -euo pipefail

export WINEPREFIX="${WINEPREFIX:-$HOME/.local/share/wineprefixes/codesys}"
export WINEDEBUG="${WINEDEBUG:--all}"
STATE="$WINEPREFIX/codesys-wine-crypto-fix"
DLLS=(ncrypt bcrypt)
# WINE versions the drop-in was tested on. The DLLs are PE-only (no unix
# side), but they import from WINE's ntdll/kernel32/ucrtbase, so keep the
# list to versions that were actually tried.
TESTED_WINE=(wine-11.0)
MARKER='Wine builtin DLL'
REPLACEMENT='codesys-wine fix'
OVR='HKCU\Software\Wine\AppDefaults\CODESYS.exe\DllOverrides'
INFO='https://github.com/Re-CODESYS/codesys-wine/tree/main/wine-patches'

log() { printf '\n== %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

marker_of() { python3 -c 'import sys; print(open(sys.argv[1],"rb").read()[0x40:0x50].decode("latin1"))' "$1"; }

set_marker() {  # file: replace the builtin marker so WINE loads the file as native
  python3 - "$1" "$MARKER" "$REPLACEMENT" <<'EOF'
import sys
p, old, new = sys.argv[1], sys.argv[2].encode(), sys.argv[3].encode()
b = bytearray(open(p, 'rb').read())
if b[0x40:0x50] == new:
    sys.exit(0)  # already marked (e.g. from a release zip)
if b[0x40:0x50] != old:
    sys.exit(f'{p}: unexpected header, not a WINE-built DLL')
b[0x40:0x50] = new
open(p, 'wb').write(b)
EOF
}

prefix_programs() {  # Windows programs running in this prefix (for the error message)
  local p
  for p in /proc/[0-9]*; do
    { tr '\0' '\n' < "$p/environ" | grep -qx "WINEPREFIX=$WINEPREFIX"; } 2>/dev/null || continue
    tr '\0' ' ' < "$p/cmdline" 2>/dev/null | grep -oiE '[^\\/ ]+\.exe' | head -n1
  done | sort -u | grep -viE '^(services|plugplay|winedevice|svchost|explorer|rpcss|conhost)\.exe$' || true
}

require_idle() {
  # WINE's own background processes exit a few seconds after the last program;
  # if the prefix doesn't go idle, something (CODESYS?) is still running.
  if ! timeout 20 wineserver -w 2>/dev/null; then
    die "programs are still running in $WINEPREFIX: $(prefix_programs | tr '\n' ' ')
       Close them (CODESYS, CODESYS Installer, ...) and run this again."
  fi
}

src_of() {  # name arch -> path of the patched DLL in $SRC
  local n=$1 a=$2
  for f in "$SRC/$a-windows/$n.dll" "$SRC/dlls/$n/$a-windows/$n.dll"; do
    [ -f "$f" ] && { echo "$f"; return; }
  done
  return 1
}

sysdir_of() { [ "$1" = x86_64 ] && echo "$WINEPREFIX/drive_c/windows/system32" || echo "$WINEPREFIX/drive_c/windows/syswow64"; }

status() {
  local n a f m
  for n in "${DLLS[@]}"; do
    for a in x86_64 i386; do
      f="$(sysdir_of $a)/$n.dll"
      [ -f "$f" ] || { echo "$a/$n.dll: missing"; continue; }
      m="$(marker_of "$f")"
      if [ "$m" = "$REPLACEMENT" ]; then echo "$a/$n.dll: patched"; else echo "$a/$n.dll: WINE original"; fi
    done
  done
  wine reg query "$OVR" 2>/dev/null | grep -E 'ncrypt|bcrypt' || echo "CODESYS.exe overrides: not set"
}

explain() {
  cat <<EOF

  Online login: CODESYS encrypts its login with RSA-OAEP, which this WINE version
  doesn't support yet. This step adds two patched WINE crypto DLLs (ncrypt, bcrypt)
  to this prefix and enables them for CODESYS.exe only. Nothing outside the prefix
  changes, and "install/crypto-fix.sh remove" undoes it. This is a temporary fix
  until the patches are in WINE. Patches, sources and license (LGPL-2.1+):
  $INFO

EOF
}

apply() {
  local yes=0 force=0
  SRC="${CODESYS_WINE_FIX_DLLS:-$HOME/wine-dev/build}"
  while [ $# -gt 0 ]; do
    case "$1" in
      --dlls) SRC="$2"; shift ;;
      --yes) yes=1 ;;
      --force) force=1 ;;
      *) die "unknown option: $1" ;;
    esac
    shift
  done
  [ -f "$WINEPREFIX/system.reg" ] || die "no WINE prefix at $WINEPREFIX"
  local wv; wv="$(wine --version)"
  if [[ " ${TESTED_WINE[*]} " != *" $wv "* ]] && [ "$force" = 0 ]; then
    echo "crypto fix: skipped, not tested with $wv (tested: ${TESTED_WINE[*]}; use --force to try)."
    return 0
  fi
  local n a s
  for n in "${DLLS[@]}"; do for a in x86_64 i386; do
    s="$(src_of $n $a)" || { echo "crypto fix: skipped, patched DLLs not found in $SRC (see $INFO)."; return 0; }
  done; done

  explain
  if [ "$yes" = 0 ] && [ -t 0 ]; then
    read -r -p "  Apply the crypto fix? [Y/n] " ans
    case "$ans" in [nN]*) echo "crypto fix: skipped."; return 0 ;; esac
  fi

  if [ -f "$SRC/SHA256SUMS" ]; then
    (cd "$SRC" && sha256sum --quiet -c SHA256SUMS) || die "checksum mismatch in $SRC"
  fi
  require_idle
  mkdir -p "$STATE"
  : > "$STATE/installed.sha256.new"
  for n in "${DLLS[@]}"; do for a in x86_64 i386; do
    local dst; dst="$(sysdir_of $a)/$n.dll"
    mkdir -p "$STATE/backup/$a"
    # Back up the WINE original once (not an earlier patched copy).
    if [ ! -f "$STATE/backup/$a/$n.dll" ] && [ "$(marker_of "$dst")" = "$MARKER" ]; then
      cp -p "$dst" "$STATE/backup/$a/$n.dll"
    fi
    cp "$(src_of $n $a)" "$dst.new"
    set_marker "$dst.new"
    mv "$dst.new" "$dst"
    (cd "$(dirname "$dst")" && sha256sum "$n.dll" | sed "s#  #  $a/#") >> "$STATE/installed.sha256.new"
  done; done
  mv "$STATE/installed.sha256.new" "$STATE/installed.sha256"
  echo "$wv" > "$STATE/wine-version"
  for n in "${DLLS[@]}"; do wine reg add "$OVR" /v "$n" /t REG_SZ /d native,builtin /f >/dev/null; done
  wineserver -w 2>/dev/null || true
  echo "crypto fix: applied (backup in $STATE)."
}

remove() {
  [ -d "$STATE" ] || { echo "crypto fix: not applied in $WINEPREFIX."; return 0; }
  require_idle
  local n a dst
  # Files first, while nothing runs in the prefix; replace by rename so a
  # mapped DLL is never rewritten in place.
  for n in "${DLLS[@]}"; do
    for a in x86_64 i386; do
      dst="$(sysdir_of $a)/$n.dll"
      if [ -f "$STATE/backup/$a/$n.dll" ]; then
        cp -p "$STATE/backup/$a/$n.dll" "$dst.new" && mv "$dst.new" "$dst"
      else
        echo "warning: no backup for $a/$n.dll; run 'wineboot -u' to restore WINE's copy"
      fi
    done
  done
  for n in "${DLLS[@]}"; do wine reg delete "$OVR" /v "$n" /f >/dev/null 2>&1 || true; done
  wineserver -w 2>/dev/null || true
  rm -rf "$STATE"
  echo "crypto fix: removed."
}

case "${1:-}" in
  apply) shift; apply "$@" ;;
  remove) remove ;;
  status) status ;;
  *) sed -n '2,17p' "$0"; exit 1 ;;
esac
