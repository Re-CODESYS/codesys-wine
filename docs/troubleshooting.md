# Troubleshooting

New to WINE? Start with [wine-basics.md](wine-basics.md): prefixes, starting and stopping, screen scaling, paths, updates.

## Known errors

| Symptom | Cause | Fix |
|---|---|---|
| Online login (Simulation or device): `Unknown error "-2146893783"` | WINE `ncrypt` refuses RSA-OAEP: `0x80090029 NTE_NOT_SUPPORTED` ([details](#online-login-fails-unknown-error--2146893783)) | Use a WINE build with [wine-patches](../wine-patches/) (needs WINE ≥ 11.5 as the base) |
| Package install aborts at `Link: ….exe` with "The method or operation is not implemented"; afterwards for example the Visual Style Editor fails with "Could not load type …IAlarmInstanceTemporaryStorage" | WINE's `IShellLinkDataList::RemoveDataBlock` was a stub. With `--cancelOnException`, `PackageManagerCLI` leaves the package half installed. | Install without `--cancelOnException` (the start-menu links are missing then), or use a WINE build with [wine-patches](../wine-patches/) |
| Visualization editor: the **Visualization Toolbox is empty** (no category tags, "0 items"); Messages show "The file 'inputs' is missing in the repository for visual elements … repository 'System', the profile ''" | WINE `cmd` drops the quotes of a redirection inside a pipe. The Visualization package's post-install step `CreateVisuRepositoryInfo.bat` therefore writes a stray file `C:\ProgramData\CODESYS\Visual` instead of `Visual Elements\formatinfo`. Without that file CODESYS finds no visualization profile ([details](#visualization-toolbox-is-empty)) | Create the file (see [details](#visualization-toolbox-is-empty)) and restart CODESYS, or use a WINE build with [wine-patches](../wine-patches/) before installing packages |
| "WIBU-SYSTEMS protected application: cpsrt library not found" | The package contains a CodeMeter/AxProtector-protected plug-in (for example Application Composer), and CodeMeter isn't installed | Skip that package (`install.sh --packages` does this by default) |
| `--noUI` with `--runscript`: "there is no script engine implementation available" | The **CODESYS Scripting** package isn't installed | `install.sh --packages` |
| `--noUI`: "you must specify a profile" even though `--profile=` is given | CODESYS parses its own command line and needs the quotes literally: `--profile="…"` | Start it through a `.cmd` file with `wine cmd /c` (see the launcher and `tests/run-login-test.sh`) |
| Headless script run: WINE "Program Error" after the script finished; `AccessViolationException` in `Microsoft.Scripting.Interpreter.HandleException` | Under investigation. Happens on WINE 11.0 and master, with and without the patches. | None yet. The script results are still valid. |
| `BadImageFormatException` around `Security.dll` | WINE's `security.dll` shadows the managed CODESYS `Security.dll` | `install.sh` sets a per-app `*security=native` DLL override |

## Online login fails: `Unknown error "-2146893783"`

`-2146893783` = `0x80090029` = `NTE_NOT_SUPPORTED`.

At login, CODESYS imports the device's RSA public key and encrypts a session secret with it through CNG:

```
NCryptOpenStorageProvider("Microsoft Software Key Storage Provider")
NCryptImportKey(RSAPUBLICBLOB, 2048 bit)
NCryptEncrypt(…, 60 bytes, flags = 0x4 NCRYPT_PAD_OAEP_FLAG)
```

Up to and including current master (September 2026), WINE's `dlls/ncrypt/main.c` rejects `NCRYPT_PAD_OAEP_FLAG` before doing anything. `NCryptDecrypt` was a stub. The RSA-OAEP support in bcrypt underneath it has been fixed since WINE 11.5 ([bug 59460](https://bugs.winehq.org/show_bug.cgi?id=59460), MR 10222). The patch in [wine-patches](../wine-patches/) passes OAEP through to bcrypt and implements `NCryptDecrypt`. With it, the SP22 Patch 4 simulation login works.

It's very likely that **real PLCs** with encrypted communication (the default in recent SP releases) take the same code path. That hasn't been tested yet.

## Visualization toolbox is empty

The Visualization package (4.9.1 and 4.10) runs `CreateVisuRepositoryInfo.bat` after installing. It contains:

```bat
IF NOT EXIST "%~1\Visual Elements\formatinfo" echo| set /p version="1.0" > "%~1\Visual Elements\formatinfo"
```

WINE's `cmd` runs built-in commands that are part of a pipe in a child `cmd`. When it rebuilds the command line for that child, it leaves out the quotes around the redirection target. The path is cut at the space, and the file `C:\ProgramData\CODESYS\Visual` is written instead. (Same in WINE 11.0 and master 11.18.)

Without `Visual Elements\formatinfo`, CODESYS treats the element repository as an old "legacy" repository and ignores the profiles in `Visual Elements\profiles`. So no visualization profile is available, and the toolbox stays empty.

Fix for an existing prefix (no rebuild needed; restart CODESYS afterwards):

```sh
cd ~/.local/share/wineprefixes/codesys/drive_c/ProgramData/CODESYS
printf '1.0' > "Visual Elements/formatinfo"    # exactly 3 bytes, no newline
[ "$(cat Visual 2>/dev/null)" = "1.0" ] && rm Visual   # stray file from the failed step
```

Then the toolbox shows its category tags (Basic, Common Controls, …). Click one to list its elements; this is CODESYS's normal behaviour, only "Favorite" is selected at first.

A Visualization object created while the file was missing can keep a build error, "Your current visualization profile does not work correctly with your current compiler version". Projects created afterwards build without it.

The `cmd` bug is fixed by patches `0006`/`0007` in [wine-patches](../wine-patches/).

## How to trace a failure

Turn on WINE's debug channels for the area you suspect, reproduce the problem, then search the log.

```sh
WINEDEBUG=+ncrypt,+bcrypt,err+all,fixme+all ~/.local/bin/codesys-3.5.22.40 2>&1 | tee codesys-trace.log
```

> If you start CODESYS through your own script that sources an env file with `WINEDEBUG=-all`, set `WINEDEBUG` **after** sourcing it. Otherwise the env file overrides your setting.

Useful channels:

| Channel | For |
|---|---|
| `+ncrypt`, `+bcrypt`, `+crypt` | Login, certificates, signatures. `+crypt` is very verbose: hundreds of MB at startup. |
| `+shell` | Shortcuts and `IShellLink` during package installs |
| `fixme+all` | Every "half-implemented" spot WINE reaches. This gives a good map of what's missing. |
| `err+all` | Real errors, including .NET exceptions WINE sees through the event log |

What to look for:
- `fixme:<dll>:<Function>` immediately before the error: the most likely culprit.
- An HRESULT shown as a negative number: convert it with `printf '%x\n' $(( -2146893783 & 0xffffffff ))`, which gives `80090029`. `0x8009xxxx` is crypto (`NTE_*`), `0x80004001` is `E_NOTIMPL`.

To check whether a fix already exists upstream, look at `dlls/<name>/` in [WINE master](https://gitlab.winehq.org/wine/wine), the [merge requests](https://gitlab.winehq.org/wine/wine/-/merge_requests), and [bugs.winehq.org](https://bugs.winehq.org).

## Other limitations

- **CodeMeter** isn't installed, so licensed add-ons, protected plug-ins and dongles are unavailable.
- **CODESYS Installer** needs the .NET 8 Desktop Runtime and admin rights for add-on installs; see the README.
- **Start page "Latest news"** may stay empty on some setups; WebView2 runs with the GPU turned off. In a fresh install on WINE 11.0 (2026-10-02) it renders fine.
- **Gateway / PLC scan:** the Windows Gateway service isn't installed. Use a gateway running natively on Linux, such as CODESYS Control for Linux SL or Edge Gateway for Linux, and add it by IP (port 1217). Not yet tested together with the ncrypt patch.
- **First start** takes a few minutes. A large part of that is certificate-store enumeration in `crypt32`: about 340,000 enumeration steps at startup.
