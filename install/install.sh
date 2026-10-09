#!/usr/bin/env bash
# Install the CODESYS V3.5 Development System (64-bit) into its own WINE prefix.
#
# Usage: install/install.sh [options] "/path/to/CODESYS 64 3.5.22.40.exe"
#
# Options:
#   --no-installer     skip the CODESYS Installer (APInstaller) and the .NET 8
#                      Desktop Runtime it needs (installed by default)
#   --no-packages      install only Visualization and Visualization Support of
#                      the bundled add-on packages. By default all bundled
#                      packages are installed in this run, as the Windows
#                      setup does (slow: about an hour).
#   --full             accepted for compatibility (everything is on by default)
#   --no-crypto-fix    don't add the patched WINE crypto DLLs for online login
#                      (see install/crypto-fix.sh; on by default)
#   --no-codemeter     don't add the CodeMeter client DLLs (see
#                      install/codemeter-client.sh; on by default)
#   --crypto-fix-dlls DIR  where the patched DLLs are (default: see crypto-fix.sh)
#   --dpi N            set WINE's DPI in the prefix, e.g. 120 (125 %) or 144
#                      (150 %) for HiDPI screens (default: leave as is, 96)
#   --yes              don't ask questions
#   --unsupported-wine try on WINE older than 11 (not supported)
#
# Environment overrides:
#   WINEPREFIX   prefix to create/use   (default ~/.local/share/wineprefixes/codesys)
#   CDS_WORK     scratch dir for the extracted setup (default ~/.cache/codesys-wine)
#
# Steps that already completed are skipped, so the script can be re-run, and a
# second CODESYS version can be installed side by side into the same prefix.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
WITH_INSTALLER=1 WITH_PACKAGES=1 CRYPTO_FIX=1 CODEMETER=1 UNSUPPORTED_WINE=0 DPI="" SETUP_EXE="" FIX_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --installer) WITH_INSTALLER=1 ;;  # default; kept for compatibility
    --no-installer) WITH_INSTALLER=0 ;;
    --packages) WITH_PACKAGES=1 ;;  # default; kept for compatibility
    --no-packages) WITH_PACKAGES=0 ;;
    --full) WITH_INSTALLER=1 WITH_PACKAGES=1 ;;
    --no-crypto-fix) CRYPTO_FIX=0 ;;
    --no-codemeter) CODEMETER=0 ;;
    --crypto-fix-dlls) FIX_ARGS+=(--dlls "$2"); shift ;;
    --yes) FIX_ARGS+=(--yes) ;;
    --dpi) DPI="$2"; shift ;;
    --unsupported-wine) UNSUPPORTED_WINE=1 ;;
    -*) echo "unknown option: $1" >&2; exit 1 ;;
    *) SETUP_EXE="$1" ;;
  esac
  shift
done
[ -n "$SETUP_EXE" ] || { echo "usage: $0 [--no-installer] [--no-packages] [--no-codemeter] [--no-crypto-fix] [--dpi N] [--yes] <CODESYS 64 3.5.x.y.exe>" >&2; exit 1; }
case "$DPI" in "") ;; *[!0-9]*) echo "--dpi needs a number, e.g. 144" >&2; exit 1 ;; esac
export WINEPREFIX="${WINEPREFIX:-$HOME/.local/share/wineprefixes/codesys}"
export WINEARCH=win64
export LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
export WINEDEBUG="${WINEDEBUG:--all}"
export WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=--disable-gpu
# Keep WINE's menu builder off from the very first wineboot; it would copy
# Windows shortcuts and file associations into the Linux desktop menus.
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:+$WINEDLLOVERRIDES;}winemenubuilder.exe=d"
CDS_WORK="${CDS_WORK:-$HOME/.cache/codesys-wine}"

log() { printf '\n== %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# --- 0. Checks ---------------------------------------------------------------
[ -f "$SETUP_EXE" ] || die "installer not found: $SETUP_EXE"
VER="$(basename "$SETUP_EXE" | grep -oE '3\.5\.[0-9]+\.[0-9]+' || true)"
[ -n "$VER" ] || die "cannot read a 3.5.x.y version from the installer file name"
case "$(basename "$SETUP_EXE")" in *"CODESYS 64"*) ;; *) die "use the 64-bit installer (CODESYS 64 $VER.exe)";; esac
for c in wine wineserver winetricks python3; do command -v "$c" >/dev/null || die "missing: $c"; done
command -v 7z >/dev/null || die "missing: 7z (Debian/Ubuntu package 7zip)"
WINE_MAJOR="$(wine --version | sed -E 's/^wine-([0-9]+).*/\1/')"
if ! [ "$WINE_MAJOR" -ge 11 ] 2>/dev/null; then
  [ "$UNSUPPORTED_WINE" = 1 ] || die "$(wine --version) is not supported. Install WineHQ WINE 11 (winehq-stable):
       https://gitlab.winehq.org/wine/wine/-/wikis/Download
       (--unsupported-wine tries anyway)"
  echo "warning: $(wine --version) is not supported, continuing because of --unsupported-wine"
fi
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
# Don't let WINE's menu builder copy every Windows shortcut (CODESYS, its
# editors, Gateway, Control Win, ...) into the Linux menu; install.sh creates
# its own launchers and menu entries instead.
wine reg add 'HKCU\Software\Wine\DllOverrides' /v winemenubuilder.exe /t REG_SZ /d '' /f >/dev/null
if [ -n "$DPI" ]; then
  # WINE's screen resolution (winecfg > Graphics). Both values are needed.
  wine reg add 'HKCU\Software\Wine\Fonts' /v LogPixels /t REG_DWORD /d "$DPI" /f >/dev/null
  wine reg add 'HKLM\System\CurrentControlSet\Hardware Profiles\Current\Software\Fonts' /v LogPixels /t REG_DWORD /d "$DPI" /f >/dev/null
fi

# --- 3. Extract the MSI from the InstallShield EXE --------------------------
MSI="$CDS_WORK/$VER/CODESYS 64 $VER.msi"
if [ ! -f "$MSI" ]; then
  log "Extracting setup files to $CDS_WORK/$VER"
  python3 "$HERE/tools/is_extract.py" "$SETUP_EXE" "$CDS_WORK/$VER" >/dev/null
fi
[ -f "$MSI" ] || die "MSI not found after extraction: $MSI"

# --- 4. Install the development system --------------------------------------
# Skips CodeMeter, the Gateway/Control Win services and the bundled add-on
# packages (installed in step 6); the CODESYS Installer is step 5.
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
PROFILE_XML="$(ls "$INSTALLDIR_UNIX/CODESYS/Profiles/"*.profile.xml | head -n1)"
PROFILE="$(basename "$PROFILE_XML" .profile.xml)"

# --- 5. CODESYS Installer (default on) ----------------------------------------
# APInstaller 2.6.x is a .NET 8 app; with the Desktop Runtime from its own
# setup it runs. Installing add-ons with it needs admin rights: use the
# "Restart as Administrator" button, or tools/runas.vbs for APInstaller.CLI.
APINST="$WINEPREFIX/drive_c/Program Files (x86)/CODESYS/APInstaller/APInstaller.CLI.exe"
if [ "$WITH_INSTALLER" = 1 ] && [ ! -f "$APINST" ]; then
  log "Installing the CODESYS Installer and .NET 8 Desktop Runtime"
  AP_EXE="$(ls "$CDS_WORK/$VER/"*".CODESYS Installer.exe" | head -n1)"
  [ -f "$AP_EXE" ] || die "CODESYS Installer not found in the setup"
  python3 "$HERE/tools/is_extract.py" "$AP_EXE" "$CDS_WORK/$VER/apinstaller" >/dev/null
  for rt in "$CDS_WORK/$VER/apinstaller/"*windowsdesktop-runtime-*-win-x64.exe \
            "$CDS_WORK/$VER/apinstaller/"*windowsdesktop-runtime-*-win-x86.exe; do
    wine "$rt" /install /quiet /norestart
  done
  wine msiexec /i "$CDS_WORK/$VER/apinstaller/CODESYS Installer.msi" /qn /norestart \
    '/L*v' 'C:\codesys-installer-install.log'
  wineserver -w
  [ -f "$APINST" ] || die "CODESYS Installer install failed, see $WINEPREFIX/drive_c/codesys-installer-install.log"
fi

# --- 6. Bundled add-on packages ---------------------------------------------
# Visualization Support and Visualization are always installed: without them
# CODESYS's library and device repositories end up inconsistent, which is hard
# to repair later. All other bundled packages follow unless --no-packages;
# installing them here, in the same run, is the recommended practice.
# Installed one at a time with PackageManagerCLI (no admin rights needed),
# with all packages beside each other so dependencies resolve. Do not pass
# --cancelOnException: creating Start-menu links fails under stock WINE
# (IShellLinkDataList::RemoveDataBlock), and cancelling there leaves a package
# half installed. Without it only the links are skipped.
PKGDIR="$WINEPREFIX/drive_c/codesys-packages/$VER"
DONE="$WINEPREFIX/codesys-wine-packages-$VER.done"
if [ -z "$(ls "$PKGDIR"/*.package 2>/dev/null)" ]; then
  log "Extracting bundled packages"
  python3 "$HERE/tools/extract_packages.py" "$MSI" "$PKGDIR" >/dev/null
fi
printf '@echo off\r\ncd /d %s\\CODESYS\\Common\r\nPackageManagerCLI.exe --profile="%s" --install="C:\\codesys-packages\\%s\\%%~1" --verbose\r\n' \
  "$INSTALLDIR" "$PROFILE" "$VER" > "$WINEPREFIX/drive_c/install-package-$VER.cmd"
touch "$DONE"; failed=()
install_package() {  # file name in $PKGDIR
  local n="$1"
  grep -qxF "$n" "$DONE" && return 0
  log "Package: $n"
  if wine cmd /c "C:\\install-package-$VER.cmd" "$n" > "$PKGDIR/${n%.package}.log" 2>&1; then
    echo "$n" >> "$DONE"
  else
    failed+=("$n"); echo "   failed, see $PKGDIR/${n%.package}.log"
  fi
  wineserver -w
}
REQUIRED=()
for pat in "CODESYS Visualization Support" "CODESYS Visualization"; do
  f="$(cd "$PKGDIR" && ls -- *.package | grep -E "^$pat [0-9][0-9.]*\.package\$" | sort -V | tail -n1 || true)"
  [ -n "$f" ] || die "required package missing from the setup: $pat"
  REQUIRED+=("$f")
done
for n in "${REQUIRED[@]}"; do install_package "$n"; done
if [ "$WITH_PACKAGES" = 1 ]; then
  for p in "$PKGDIR"/*.package; do
    n="$(basename "$p")"
    case "$n" in
      "CODESYS Compatibility Package "*) continue ;;  # part of the MSI install
      # Licensed add-on with an AxProtector-protected plug-in and its own
      # licensing model: fails ("cpsrt library not found" dialog).
      "CODESYS Application Composer "*) echo "   skipping $n (licensed, not supported)"; continue ;;
    esac
    install_package "$n"
  done
fi
[ "${#failed[@]}" = 0 ] || echo "warning: ${#failed[@]} package(s) failed: ${failed[*]}"

# Visualization's post-install step CreateVisuRepositoryInfo.bat should create
# "Visual Elements\formatinfo", but WINE's cmd drops the quotes of a redirection
# inside a pipe and writes "C:\ProgramData\CODESYS\Visual" instead. Without the
# file CODESYS finds no visualization profile and the Visualization Toolbox is
# empty (docs/troubleshooting.md). Also repairs prefixes installed earlier.
REPO="$WINEPREFIX/drive_c/ProgramData/CODESYS"
for d in "Visual Elements" "Visualization Styles"; do
  if [ -d "$REPO/$d" ] && [ ! -f "$REPO/$d/formatinfo" ]; then
    printf '1.0' > "$REPO/$d/formatinfo"; echo "   created $d\\formatinfo (WINE cmd workaround)"
  fi
done
if [ -f "$REPO/Visual" ] && [ "$(cat "$REPO/Visual")" = "1.0" ]; then rm -f "$REPO/Visual"; fi

# --- 7. Online-login crypto fix (default on) -------------------------------
# Temporary until the ncrypt/bcrypt patches are in a WINE release; it skips
# itself on untested WINE versions or when the patched DLLs aren't available.
if [ "$CRYPTO_FIX" = 1 ]; then
  log "Online-login crypto fix"
  "$HERE/crypto-fix.sh" apply ${FIX_ARGS[@]+"${FIX_ARGS[@]}"}
fi

# --- 8. CodeMeter client (default on) --------------------------------------
# WIBU's API DLLs only, no Windows CodeMeter service: CODESYS uses the
# CodeMeter runtime running natively on Linux (dongles, soft licenses).
if [ "$CODEMETER" = 1 ]; then
  log "CodeMeter client"
  CM_MSI="$(ls "$CDS_WORK/$VER/"*CodeMeterRuntime64.msi 2>/dev/null | head -n1)"
  if [ -z "$CM_MSI" ]; then
    echo "CodeMeter client: skipped, CodeMeterRuntime64.msi not found in the setup."
  elif ! command -v 7z >/dev/null; then
    echo "CodeMeter client: skipped, needs 7z (Debian/Ubuntu package 7zip)."
  else
    "$HERE/codemeter-client.sh" apply "$CM_MSI"
  fi
fi

# --- 9. Launcher and menu entry ---------------------------------------------
BIN="$HOME/.local/bin"; APPS="$HOME/.local/share/applications"
mkdir -p "$BIN" "$APPS"
printf '@echo off\r\ncd /d %s\\CODESYS\\Common\r\nCODESYS.exe --profile="%s" %%*\r\n' \
  "$INSTALLDIR" "$PROFILE" > "$WINEPREFIX/drive_c/launch-codesys-$VER.cmd"
# Name launchers after the prefix unless it is the default one, so test
# prefixes don't replace the launcher of the main installation.
SUFFIX=""; [ "$WINEPREFIX" = "$HOME/.local/share/wineprefixes/codesys" ] || SUFFIX="-$(basename "$WINEPREFIX")"
LAUNCHER="$BIN/codesys-$VER$SUFFIX"
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
cat > "$APPS/codesys-$VER$SUFFIX.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=$PROFILE (WINE${SUFFIX:+, ${SUFFIX#-}})
Exec=$LAUNCHER
Icon=$INSTALLDIR_UNIX/CODESYS/Common/CoDeSys.ico
Categories=Development;
StartupWMClass=codesys.exe
EOF

# CODESYS Installer launcher and menu entry, with the icon from its exe.
if [ -f "$APINST" ]; then
  APGUI="$(dirname "$APINST")/APInstaller.GUI.exe"
  APICON="$WINEPREFIX/codesys-installer.ico"
  python3 "$HERE/tools/pe_icon.py" "$APGUI" "$APICON" 2>/dev/null || APICON=""
  APLAUNCHER="$BIN/codesys-installer$SUFFIX"
  cat > "$APLAUNCHER" <<EOF
#!/bin/sh
# CODESYS Installer under WINE (generated by codesys-wine/install.sh)
export WINEPREFIX="$WINEPREFIX"
export LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
export WINEDEBUG="\${WINEDEBUG:--all}"
exec wine "$APGUI" "\$@" >> "\$WINEPREFIX/codesys-installer.log" 2>&1
EOF
  chmod +x "$APLAUNCHER"
  cat > "$APPS/codesys-installer$SUFFIX.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=CODESYS Installer (WINE${SUFFIX:+, ${SUFFIX#-}})
Exec=$APLAUNCHER
Icon=$APICON
Categories=Development;
StartupWMClass=apinstaller.gui.exe
EOF
fi

log "Done. Start with: $LAUNCHER  (first start can take a few minutes)"
