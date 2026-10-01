# codesys-wine

Run the **CODESYS V3.5 Development System** (64-bit IDE) on Linux with WINE.

> Unofficial. CODESYS GmbH does not support this setup. This repository has no CODESYS binaries. Download the installer from the [CODESYS Store](https://store.codesys.com) yourself.

## Status

| Version | WINE | Host | Result |
|---|---|---|---|
| V3.5 SP22 Patch 4 (3.5.22.40) | winehq-stable 11.0 | Debian 13 (trixie), x86-64 | IDE starts; a project builds with 0 errors |
| V3.5 SP22 Patch 1 (3.5.22.10) | winehq-stable 11.0 | Debian 13 (trixie), x86-64 | IDE starts; a project builds with 0 errors |

| Feature | State |
|---|---|
| Editors, project handling, compile | Works |
| Online login (simulation, and very likely real PLCs) | **Fails** with `Unknown error "-2146893783"` (0x80090029), caused by a WINE ncrypt gap. See [docs/known-issues.md](docs/known-issues.md) |
| CodeMeter licensing, USB dongles | Not installed |
| CODESYS Installer (APInstaller), Visualization 4.10 package | Not working under WINE |

## Requirements

- x86-64 Linux with WINE **11.0 or newer**, 64-bit and 32-bit (WineHQ packages: `winehq-stable`), `winetricks`, `python3`.
- Locale `en_US.UTF-8` generated (`locale -a`).
- About 6 GB of free disk space, and internet access for winetricks.
- The official `CODESYS 64 3.5.x.y.exe` installer.

## Install

```sh
git clone <this repo> && cd codesys-wine
./install.sh ~/Downloads/"CODESYS 64 3.5.22.40.exe"
```

The script:
1. Creates a dedicated win64 prefix at `~/.local/share/wineprefixes/codesys`. You can override this with `WINEPREFIX=`.
2. Installs `dotnet48 vcrun2022 msxml6 win10 webview2` with winetricks.
3. Sets a per-application `*security=native` DLL override for the CODESYS tools. Without it, WINE's own `security.dll` shadows the managed `Security.dll` that CODESYS ships, causing a `BadImageFormatException`.
4. Re-registers `oleaut32` and turns off WPF hardware acceleration.
5. Unpacks the InstallShield EXE with `tools/is_extract.py`, then runs the CODESYS MSI silently. It skips CodeMeter, the Windows services and the CODESYS Installer.
6. Creates the launcher `~/.local/bin/codesys-<version>` and a desktop menu entry.

The script can be re-run safely. Running it with another installer version adds that version side by side in the same prefix.

The silent install passes `AgreeToLicense=Yes`. Read the CODESYS license before you run it.

## Credits

- The recipe follows the macOS guide in [livingforjesus/codesys-macos-install-guide](https://github.com/livingforjesus/codesys-macos-install-guide), adapted to Linux and tested there.
- The InstallShield stream format is documented by [ISx](https://github.com/lifenjoiner/ISx). `tools/is_extract.py` is an independent pure-Python implementation.
- Older work: [CODESYS Forge: codesys-4-linux](https://forge.codesys.com/tol/codesys-4-linux/home/Manual%20Installation/).
