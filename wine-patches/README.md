# WINE patches for CODESYS

These patches fix WINE gaps that break CODESYS V3.5. They are written against WINE master.

> **Origin and upstream status.** The patches were written with an AI assistant (Claude). WineHQ's contributor policy doesn't accept LLM-generated contributions ([policy](https://gitlab.winehq.org/winehq/winehq/-/wikis/home), "No LLM-generated code"), so they are **not submitted to WINE** and must not be. Upstream, the two problems are reported as WINE bugs instead, written by a human, with traces and the code locations, so WINE developers can fix them. Once a WINE release fixes them, this directory only needs to say which WINE version to use.

| Patches | Fixes | Upstream WINE bug |
|---|---|---|
| `0001`–`0003` ncrypt | **Online login** (Simulation, very likely real PLCs too): `Unknown error "-2146893783"` (`0x80090029 NTE_NOT_SUPPORTED`). `NCryptEncrypt` refused RSA OAEP padding, and `NCryptDecrypt` was a stub. | to be filed |
| `0004`–`0005` shell32 | **Package install** aborting at `Link: ….exe` with "The method or operation is not implemented" (for example Visualization 4.10). `IShellLinkDataList::RemoveDataBlock` was a stub; CODESYS removes the `EXP_SZ_ICON_SIG` block. | to be filed |

The patches follow WINE's submission conventions: conformance tests go in their own commit with `todo_wine` markers, and the fix commit removes those markers. The tests in `dlls/ncrypt/tests` and `dlls/shell32/tests` pass on WINE in 32-bit and 64-bit at every commit.

The RSA-OAEP fix also depends on bcrypt fixes that first shipped in WINE 11.5 ([bug 59460](https://bugs.winehq.org/show_bug.cgi?id=59460)). So applying the patches to the WINE 11.0 source isn't enough. Use one of the two routes below.

## Route A: drop-in DLLs for stock `winehq-stable` 11.0

This needs no WINE rebuild on the target machine. Only CODESYS uses the patched DLLs; every other program in the prefix keeps WINE's own DLLs.

**Use [install/crypto-fix.sh](../install/crypto-fix.sh)** (`apply`, `remove`, `status`). `install.sh` runs it by default when patched DLLs are available. It does the steps below, with these extras:
- backups of WINE's DLLs
- a check that no WINE programs are running
- a gate on tested WINE versions
- checksum verification for release folders

What it does, if you want to do it by hand:

1. Take `ncrypt.dll` and `bcrypt.dll` from the release [crypto-fix-20261002](https://github.com/Re-CODESYS/codesys-wine/releases/tag/crypto-fix-20261002), which comes with `SHA256SUMS`, `BUILD-INFO`, the patches and a tarball of the patched source. `crypto-fix.sh` downloads and verifies it automatically. You can also take them from your own build (Route B).
2. Copy the `x86_64-windows` versions to `$WINEPREFIX/drive_c/windows/system32/` and the `i386-windows` versions to `.../syswow64/`.
3. In those copies, overwrite the 16-byte marker `Wine builtin DLL` at file offset `0x40` with any other text. Otherwise WINE recognizes the files as its own builtins and loads its unpatched copy instead (`WINEDLLPATH` doesn't help either).
4. Set per-application overrides for CODESYS only:
   ```sh
   wine reg add 'HKCU\Software\Wine\AppDefaults\CODESYS.exe\DllOverrides' /v ncrypt /d native,builtin /f
   wine reg add 'HKCU\Software\Wine\AppDefaults\CODESYS.exe\DllOverrides' /v bcrypt /d native,builtin /f
   ```

To undo: delete the two registry values, and copy back the originals from `/opt/wine-stable/lib/wine/*-windows/`.

To check that it works, look for these lines in a `WINEDEBUG=+loaddll` trace: `Loaded L"C:\\windows\\system32\\ncrypt.dll" … : native`, and the same for `bcrypt.dll`.

shell32 isn't part of the drop-in. Replacing WINE's shell32 affects all file and shortcut handling, and it's only needed while installing packages. On stock WINE, install packages without `--cancelOnException`; only the editors' start-menu links are then missing.

## Route B: build patched WINE

```sh
wine-patches/build-wine.sh --deps   # first time: installs build dependencies with sudo
wine-patches/build-wine.sh          # later runs
```

This clones WINE into `~/wine-dev/src`, applies the patches on top of the tested commit (`6d1b094`, 30 Sep 2026), and builds out of tree in `~/wine-dev/build`. Nothing is installed system-wide.

- The first build takes 1–2 hours on a 2-core laptop. After a source change, only the affected DLL is rebuilt, which takes seconds.
- It needs about 1.4 GB of `-dev` packages and roughly 6 GB in `~/wine-dev`.

Run it on a **copy** of your prefix:

```sh
cp -a ~/.local/share/wineprefixes/codesys ~/.local/share/wineprefixes/codesys-dev
WINEPREFIX=~/.local/share/wineprefixes/codesys-dev ~/wine-dev/build/wine <command>
```

The first start updates the prefix to the newer WINE version, and stable WINE can't undo that.

## Tested

| CODESYS | WINE | Login (Simulation) | Visualization 4.10 with `--cancelOnException` |
|---|---|---|---|
| V3.5 SP22 Patch 4 | 11.0 (stable) | fails, `0x80090029` | aborts at the Link step |
| V3.5 SP22 Patch 4 | master `6d1b094` + patches (11.18) | **OK** | **OK**, links created |
| V3.5 SP22 Patch 4 | 11.0 (stable) + drop-in ncrypt/bcrypt (Route A) | **OK** | not tested (no shell32 drop-in) |

These were tested with the headless login test in [tests/](../tests/). The GUI and real PLCs haven't been tested yet.

## License

These patches modify WINE and so fall under WINE's license, LGPL-2.1-or-later. See [COPYING](COPYING). The same applies to DLLs built from them. This differs from the MIT license that covers the rest of the repository.
