#!/usr/bin/env bash
# Install the CODESYS V3.5 Development System (64-bit) into its own WINE prefix.
#
# Usage: install/install.sh [options] "/path/to/CODESYS 64 3.5.22.40.exe"
#
# Options:
#   --installer        also install the CODESYS Installer (APInstaller) and the
#                      .NET 8 Desktop Runtime it needs
#   --packages         also install the add-on packages bundled with the setup,
#                      as the Windows setup does (slow: about an hour)
#   --full             both of the above
#   --no-crypto-fix    don't add the patched WINE crypto DLLs for online login
#                      (see install/crypto-fix.sh; on by default)
#   --no-codemeter     don't add the CodeMeter client DLLs (see
#                      install/codemeter-client.sh; on by default)
#   --crypto-fix-dlls DIR  where the patched DLLs are (default: see crypto-fix.sh)
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
WITH_INSTALLER=0 WITH_PACKAGES=0 CRYPTO_FIX=1 CODEMETER=1 UNSUPPORTED_WINE=0 SETUP_EXE="" FIX_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --installer) WITH_INSTALLER=1 ;;
    --packages) WITH_PACKAGES=1 ;;
    --full) WITH_INSTALLER=1 WITH_PACKAGES=1 ;;
    --no-crypto-fix) CRYPTO_FIX=0 ;;
    --no-codemeter) CODEMETER=0 ;;
    --crypto-fix-dlls) FIX_ARGS+=(--dlls "$2"); shift ;;
    --yes) FIX_ARGS+=(--yes) ;;
    --unsupported-wine) UNSUPPORTED_WINE=1 ;;
    -*) echo "unknown option: $1" >&2; exit 1 ;;
    *) SETUP_EXE="$1" ;;
  esac
  shift
done
[ -n "$SETUP_EXE" ] || { echo "usage: $0 [--installer] [--packages] [--full] [--no-crypto-fix] <CODESYS 64 3.5.x.y.exe>" >&2; exit 1; }
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
[ "$WITH_PACKAGES" = 0 ] || command -v 7z >/dev/null || die "missing: 7z (Debian/Ubuntu package 7zip) for --packages"
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

# --- 3. Extract the MSI from the InstallShield EXE --------------------------
MSI="$CDS_WORK/$VER/CODESYS 64 $VER.msi"
if [ ! -f "$MSI" ]; then
  log "Extracting setup files to $CDS_WORK/$VER"
  python3 "$HERE/tools/is_extract.py" "$SETUP_EXE" "$CDS_WORK/$VER" >/dev/null
fi
[ -f "$MSI" ] || die "MSI not found after extraction: $MSI"

# --- 4. Install the development system --------------------------------------
# Skips CodeMeter, the Gateway/Control Win services and the bundled add-on
# packages (see --packages); the CODESYS Installer is step 5 (--installer).
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

# --- 5. CODESYS Installer (optional) ----------------------------------------
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

# --- 6. Bundled add-on packages (optional) ----------------------------------
# Installed one at a time with PackageManagerCLI (no admin rights needed),
# with all packages beside each other so dependencies resolve. Do not pass
# --cancelOnException: creating Start-menu links fails under WINE
# (IShellLinkDataList::RemoveDataBlock), and cancelling there leaves a package
# half installed. Without it only the links are skipped.
if [ "$WITH_PACKAGES" = 1 ]; then
  PKGDIR="$WINEPREFIX/drive_c/codesys-packages/$VER"
  DONE="$WINEPREFIX/codesys-wine-packages-$VER.done"
  if [ -z "$(ls "$PKGDIR"/*.package 2>/dev/null)" ]; then
    log "Extracting bundled packages"
    python3 "$HERE/tools/extract_packages.py" "$MSI" "$PKGDIR" >/dev/null
  fi
  printf '@echo off\r\ncd /d %s\\CODESYS\\Common\r\nPackageManagerCLI.exe --profile="%s" --install="C:\\codesys-packages\\%s\\%%~1" --verbose\r\n' \
    "$INSTALLDIR" "$PROFILE" "$VER" > "$WINEPREFIX/drive_c/install-package-$VER.cmd"
  touch "$DONE"; failed=()
  for p in "$PKGDIR"/*.package; do
    n="$(basename "$p")"
    case "$n" in
      "CODESYS Compatibility Package "*) continue ;;  # part of the MSI install
      # AxProtector-protected plug-in: without the CodeMeter runtime it pops up
      # a modal "cpsrt library not found" dialog and fails. Licensed add-on.
      "CODESYS Application Composer "*) echo "   skipping $n (needs CodeMeter)"; continue ;;
    esac
    grep -qxF "$n" "$DONE" && continue
    log "Package: $n"
    if wine cmd /c "C:\\install-package-$VER.cmd" "$n" > "$PKGDIR/${n%.package}.log" 2>&1; then
      echo "$n" >> "$DONE"
    else
      failed+=("$n"); echo "   failed, see $PKGDIR/${n%.package}.log"
    fi
    wineserver -w
  done
  [ "${#failed[@]}" = 0 ] || echo "warning: ${#failed[@]} package(s) failed: ${failed[*]}"
fi

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
