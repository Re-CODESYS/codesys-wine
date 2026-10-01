# codesys-wine

Run the **CODESYS V3.5 Development System** (64-bit IDE) on Linux with WINE.

> Unofficial. CODESYS GmbH does not support this setup. This repository has no CODESYS binaries. Download the installer from the [CODESYS Store](https://store.codesys.com) yourself.

## Status

| Version | WINE | Host | Result |
|---|---|---|---|
| V3.5 SP22 Patch 4 (3.5.22.40) | winehq-stable 11.0 | Debian 13 (trixie), x86-64 | IDE starts; a project builds with 0 errors |
| V3.5 SP22 Patch 1 (3.5.22.10) | winehq-stable 11.0 | Debian 13 (trixie), x86-64 | IDE starts; a project builds with 0 errors |
| V3.5 SP22 Patch 4 (3.5.22.40) | WINE master 11.18 + [wine-patches](wine-patches/) | Debian 13 (trixie), x86-64 | Simulation login works; Visualization 4.10 installs including its start-menu links |

| Feature | State |
|---|---|
| Editors, project handling, compile | Works |
| Online login (simulation, and very likely real PLCs) | **Fails on stock WINE** with `Unknown error "-2146893783"` (0x80090029), caused by a WINE ncrypt gap. **Works with [patched WINE](wine-patches/)** (simulation tested; real PLCs not yet). See [docs/troubleshooting.md](docs/troubleshooting.md) |
| CodeMeter licensing, USB dongles | Not installed |
| CODESYS Installer 2.6.1, add-on packages incl. Visualization 4.10 and its editors | Works (`--installer`, `--packages`). On stock WINE, start-menu links for the editors aren't created. With [patched WINE](wine-patches/), `PackageManagerCLI --cancelOnException` works and the links are created. |

The WINE fixes are being submitted upstream. Until they land in a WINE release, [wine-patches/](wine-patches/) builds a patched WINE that runs in place, and [tests/](tests/) has a headless login test. To diagnose other failures, see [docs/troubleshooting.md](docs/troubleshooting.md).

## Requirements

- x86-64 Linux with WINE **11.0 or newer**, 64-bit and 32-bit (WineHQ packages: `winehq-stable`), `winetricks`, `python3`.
- Locale `en_US.UTF-8` generated (`locale -a`).
- About 6 GB of free disk space, and internet access for winetricks.
- The official `CODESYS 64 3.5.x.y.exe` installer.

## Install

```sh
git clone <this repo> && cd codesys-wine
install/install.sh ~/Downloads/"CODESYS 64 3.5.22.40.exe"
```

The script:
1. Creates a dedicated win64 prefix at `~/.local/share/wineprefixes/codesys`. You can override this with `WINEPREFIX=`.
2. Installs `dotnet48 vcrun2022 msxml6 win10 webview2` with winetricks.
3. Sets a per-application `*security=native` DLL override for the CODESYS tools. Without it, WINE's own `security.dll` shadows the managed `Security.dll` that CODESYS ships, causing a `BadImageFormatException`.
4. Re-registers `oleaut32` and turns off WPF hardware acceleration.
5. Unpacks the InstallShield EXE with `install/tools/is_extract.py`, then runs the CODESYS MSI silently. It skips CodeMeter, the Windows services and the CODESYS Installer.
6. Creates the launcher `~/.local/bin/codesys-<version>` and a desktop menu entry. With a non-default `WINEPREFIX`, the prefix name is appended, for example `codesys-3.5.22.40-test`.

Optional extras:

| Option | What it adds |
|---|---|
| `--installer` | **CODESYS Installer 2.6.1** (APInstaller) and the .NET 8 Desktop Runtime it needs. It lists installations and installs add-ons. Installing add-ons needs admin rights: use its **Restart as Administrator** button, or `install/tools/runas.vbs` for `APInstaller.CLI.exe`. |
| `--packages` | The **add-on packages bundled with the setup**, as a Windows install would include: Scripting, Visualization, the Visual Style and HTML5 control editors, fieldbuses, SoftMotion and so on. They are installed with `PackageManagerCLI`. It's slow, about an hour. Needs `7z`. |
| `--full` | Both. |

`--packages` skips **Application Composer**. It is a licensed add-on, and its plug-in is protected with CodeMeter (AxProtector). Without the CodeMeter runtime it shows a modal "cpsrt library not found" dialog and fails.

Installers this was tested with (SHA256):

```
4dae598fc3d2143b8ebdddceba34ac2a73009b1eb001d8d553085a8fb0478ad7  CODESYS 64 3.5.22.40.exe
c3d493c2d1df71a539fdb34a31dbaec4e53610ec6a2b817b388b4e1e2a4ba1a9  CODESYS 64 3.5.22.10.exe
```

The script can be re-run safely. Running it with another installer version adds that version side by side in the same prefix.

The silent install passes `AgreeToLicense=Yes`. Read the CODESYS license before you run it.

## Credits

- The recipe follows the macOS guide in [livingforjesus/codesys-macos-install-guide](https://github.com/livingforjesus/codesys-macos-install-guide), adapted to Linux and tested there.
- The InstallShield stream format is documented by [ISx](https://github.com/lifenjoiner/ISx). `install/tools/is_extract.py` is an independent pure-Python implementation.
- Older work: [CODESYS Forge: codesys-4-linux](https://forge.codesys.com/tol/codesys-4-linux/home/Manual%20Installation/).
