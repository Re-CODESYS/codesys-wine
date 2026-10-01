#!/usr/bin/env bash
# Install the CODESYS V3.5 Development System (64-bit) into its own WINE prefix.
#
# Usage: ./install.sh "/path/to/CODESYS 64 3.5.22.40.exe"
#
# Environment overrides:
#   WINEPREFIX   prefix to create/use   (default ~/.local/share/wineprefixes/codesys)
#   CDS_WORK     scratch dir for the extracted setup (default ~/.cache/codesys-wine)
#
# Steps that already completed are skipped, so the script can be re-run, and a
# second CODESYS version can be installed side by side into the same prefix.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SETUP_EXE="${1:?usage: $0 <CODESYS 64 3.5.x.y.exe>}"
export WINEPREFIX="${WINEPREFIX:-$HOME/.local/share/wineprefixes/codesys}"
export WINEARCH=win64
export LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
export WINEDEBUG="${WINEDEBUG:--all}"
export WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=--disable-gpu
CDS_WORK="${CDS_WORK:-$HOME/.cache/codesys-wine}"

log() { printf '\n== %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# --- 0. Checks ---------------------------------------------------------------
[ -f "$SETUP_EXE" ] || die "installer not found: $SETUP_EXE"
VER="$(basename "$SETUP_EXE" | grep -oE '3\.5\.[0-9]+\.[0-9]+' || true)"
[ -n "$VER" ] || die "cannot read a 3.5.x.y version from the installer file name"
case "$(basename "$SETUP_EXE")" in *"CODESYS 64"*) ;; *) die "use the 64-bit installer (CODESYS 64 $VER.exe)";; esac
for c in wine wineserver winetricks python3; do command -v "$c" >/dev/null || die "missing: $c"; done
WINE_MAJOR="$(wine --version | sed -E 's/^wine-([0-9]+).*/\1/')"
[ "$WINE_MAJOR" -ge 11 ] 2>/dev/null || echo "warning: tested with WINE 11.x, found $(wine --version)"
locale -a | grep -qi '^en_US\.utf-\?8$' || die "locale en_US.UTF-8 missing (CODESYS tools fail with other cultures)"
INSTALLDIR="C:\\CODESYS-$VER"
INSTALLDIR_UNIX="$WINEPREFIX/drive_c/CODESYS-$VER"
echo "CODESYS $VER -> $WINEPREFIX ($INSTALLDIR)"

# --- 1. Prefix and prerequisites --------------------------------------------
if [ ! -f "$WINEPREFIX/system.reg" ]; then
  log "Creating win64 prefix"
  wine wineboot -u
  wineserver -w
fi
need_verbs=()
for v in dotnet48 vcrun2022 msxml6 win10 webview2; do
  grep -qx "$v" "$WINEPREFIX/winetricks.log" 2>/dev/null || need_verbs+=("$v")
done
if [ "${#need_verbs[@]}" -gt 0 ]; then
  log "winetricks: ${need_verbs[*]} (.NET 4.8 takes a while)"
  winetricks -q "${need_verbs[@]}"
  wineserver -w
fi

# --- 2. Fixes ------------------------------------------------------------------
# WINE's builtin security.dll shadows CODESYS's managed Security.dll
# (BadImageFormatException). Override per executable; a global override breaks
# other programs.
log "Applying per-application DLL overrides"
for e in CODESYS.exe PackageManagerCLI.exe IPMCLI.exe PackageManager.exe LACUtil.exe \
         ImportLibraryProfile.exe CoreInstallerSupport.exe CoreInstallerSupport2.exe \
         DeletePlugInCache.exe RepairMenuConfig.exe Dependencies.exe \
         PackageManagerSelfUpdater.exe VisualStylesEditor.exe Html5ControlEditor.exe; do
  wine reg add "HKCU\\Software\\Wine\\AppDefaults\\$e\\DllOverrides" /v '*security' /t REG_SZ /d native /f >/dev/null
done
wine regsvr32 /s oleaut32.dll
wine 'C:\windows\syswow64\regsvr32.exe' /s oleaut32.dll
wine reg add 'HKCU\Software\Microsoft\Avalon.Graphics' /v DisableHWAcceleration /t REG_DWORD /d 1 /f >/dev/null

# --- 3. Extract the MSI from the InstallShield EXE --------------------------
MSI="$CDS_WORK/$VER/CODESYS 64 $VER.msi"
if [ ! -f "$MSI" ]; then
  log "Extracting setup files to $CDS_WORK/$VER"
  python3 "$HERE/tools/is_extract.py" "$SETUP_EXE" "$CDS_WORK/$VER" >/dev/null
fi
[ -f "$MSI" ] || die "MSI not found after extraction: $MSI"

# --- 4. Install the development system --------------------------------------
# Skips CodeMeter, the Gateway/Control Win services and the separate
# CODESYS Installer (APInstaller), which hangs under WINE.
if [ ! -f "$INSTALLDIR_UNIX/CODESYS/Common/CODESYS.exe" ]; then
  log "Installing CODESYS $VER (silent MSI, by running it you accept the CODESYS license)"
  wine msiexec /i "$MSI" /qn /norestart \
    "INSTALLDIR=$INSTALLDIR" \
    'ADDLOCAL=Basic,CODESYS,CDS_Exe_x64,Compatibility,OEMCustomization_CDS,Only_x64,SubFeature' \
    CDS_INSTALL_SERVICES=0 CDS_INSTALL_NOPACK=1 AgreeToLicense=Yes CDSAgreeToReadMe=Yes \
    '/L*v' "C:\\codesys-$VER-install.log"
  wineserver -w
fi
[ -f "$INSTALLDIR_UNIX/CODESYS/Common/CODESYS.exe" ] \
  || die "install failed, see $WINEPREFIX/drive_c/codesys-$VER-install.log"

# --- 5. Launcher and menu entry ---------------------------------------------
PROFILE_XML="$(ls "$INSTALLDIR_UNIX/CODESYS/Profiles/"*.profile.xml | head -n1)"
PROFILE="$(basename "$PROFILE_XML" .profile.xml)"
BIN="$HOME/.local/bin"; APPS="$HOME/.local/share/applications"
mkdir -p "$BIN" "$APPS"
printf '@echo off\r\ncd /d %s\\CODESYS\\Common\r\nCODESYS.exe --profile="%s" %%*\r\n' \
  "$INSTALLDIR" "$PROFILE" > "$WINEPREFIX/drive_c/launch-codesys-$VER.cmd"
LAUNCHER="$BIN/codesys-$VER"
cat > "$LAUNCHER" <<EOF
#!/bin/sh
# $PROFILE under WINE (generated by codesys-wine/install.sh)
export WINEPREFIX="$WINEPREFIX"
export LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
export WINEDEBUG="\${WINEDEBUG:--all}"
export WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=--disable-gpu
exec wine cmd /c 'C:\\launch-codesys-$VER.cmd' "\$@" >> "\$WINEPREFIX/codesys-launch.log" 2>&1
EOF
chmod +x "$LAUNCHER"
cat > "$APPS/codesys-$VER.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=$PROFILE (WINE)
Exec=$LAUNCHER
Icon=$INSTALLDIR_UNIX/CODESYS/Common/CoDeSys.ico
Categories=Development;
StartupWMClass=codesys.exe
EOF

log "Done. Start with: $LAUNCHER  (first start can take a few minutes)"
