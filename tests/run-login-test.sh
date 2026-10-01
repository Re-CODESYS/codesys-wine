#!/bin/sh
# Headless CODESYS simulation-login test.
#
# Usage: tests/run-login-test.sh <project.project> [wine-binary]
#
# Environment:
#   WINEPREFIX   prefix with CODESYS and the "CODESYS Scripting" package
#                (default: ~/.local/share/wineprefixes/codesys)
#   CDS_VERSION  installed version directory (default: 3.5.22.40)
#   CDS_PROFILE  profile name (default: "CODESYS V3.5 SP22 Patch 4")
#   TRACE        file for WINE debug output (default: ./login-test.trace)
#
# Prints LOGIN_OK or LOGIN_FAIL. Exit status: 0 = login OK, 1 = login failed, 2 = test error.
# CODESYS itself may crash after the script has finished (an IronPython
# AccessViolationException at shutdown). That doesn't affect the result.
set -u

[ $# -ge 1 ] || { sed -n '2,15p' "$0"; exit 2; }
PROJECT=$(realpath "$1")
WINEBIN=${2:-wine}
export WINEPREFIX=${WINEPREFIX:-$HOME/.local/share/wineprefixes/codesys}
CDS_VERSION=${CDS_VERSION:-3.5.22.40}
CDS_PROFILE=${CDS_PROFILE:-CODESYS V3.5 SP22 Patch 4}
TRACE=${TRACE:-$PWD/login-test.trace}
HERE=$(cd "$(dirname "$0")" && pwd)

export WINEARCH=win64 LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
export WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=--disable-gpu
export WINEDEBUG=${WINEDEBUG:-+ncrypt,err+all,fixme-all}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cp "$PROJECT" "$WORK/test.project"     # never touch the original project
RESULT="$WORK/result.txt"

winpath() { "$WINEBIN" winepath -w "$1" 2>/dev/null; }
export CWT_PROJECT=$(winpath "$WORK/test.project")
export CWT_RESULT=$(winpath "$RESULT")
WINEDEBUG=-all "$WINEBIN" reg add 'HKCU\Software\Wine\WineDbg' /v ShowCrashDialog /t REG_DWORD /d 0 /f >/dev/null 2>&1

# CODESYS parses --profile itself, so pass it through cmd.exe with literal quotes.
printf '@echo off\r\ncd /d C:\\CODESYS-%s\\CODESYS\\Common\r\nCODESYS.exe --profile="%s" --noUI --runscript="%s"\r\n' \
    "$CDS_VERSION" "$CDS_PROFILE" "$(winpath "$HERE/login_test.py")" > "$WORK/run.cmd"
timeout 900 "$WINEBIN" cmd /c "$(winpath "$WORK/run.cmd")" > "$TRACE" 2>&1
cat "$RESULT" 2>/dev/null || { echo "no result; see $TRACE"; exit 2; }
grep -q '^LOGIN_OK' "$RESULT" && exit 0
grep -q '^LOGIN_FAIL' "$RESULT" && exit 1
exit 2
