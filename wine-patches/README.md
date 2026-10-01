# WINE patches for CODESYS

These patches fix WINE gaps that break CODESYS V3.5. They're written against WINE master and are meant to go upstream. Once WINE ships them, this directory only needs to say which WINE version to use.

| Patch | Fixes | Upstream |
|---|---|---|
| `0001-ncrypt-…` | **Online login** (Simulation, very likely real PLCs too): `Unknown error "-2146893783"` (`0x80090029 NTE_NOT_SUPPORTED`). `NCryptEncrypt` refused RSA OAEP padding, and `NCryptDecrypt` was a stub. | MR pending |
| `0002-shell32-…` | **Package install** aborting at `Link: ….exe` with "The method or operation is not implemented" (for example Visualization 4.10). `IShellLinkDataList::RemoveDataBlock` was a stub. | MR pending |

Both patches include WINE conformance tests (`dlls/ncrypt/tests`, `dlls/shell32/tests`). These pass on WINE in 32-bit and 64-bit.

The RSA-OAEP part also depends on bcrypt fixes that first shipped in WINE 11.5 ([bug 59460](https://bugs.winehq.org/show_bug.cgi?id=59460)). So the patches need **WINE ≥ 11.5**. WINE 11.0 doesn't work, even with the patches applied.

## Build

```sh
wine-patches/build-wine.sh --deps   # first time: installs build dependencies with sudo
wine-patches/build-wine.sh          # later runs
```

This clones WINE into `~/wine-dev/src`, applies the patches on top of the tested commit (`6d1b094`, 30 Sep 2026), and builds out of tree in `~/wine-dev/build`. Nothing is installed system-wide.

- The first build takes 1–2 hours on a 2-core laptop. After a source change, only the affected DLL is rebuilt, which takes seconds.
- It needs about 1.4 GB of `-dev` packages and roughly 6 GB in `~/wine-dev`.

## Use

```sh
cp -a ~/.local/share/wineprefixes/codesys ~/.local/share/wineprefixes/codesys-dev
WINEPREFIX=~/.local/share/wineprefixes/codesys-dev ~/wine-dev/build/wine <command>
```

Run it on a **copy** of your prefix. The first start updates the prefix to the newer WINE version, and you can't undo that with the stable WINE.

## Tested

| CODESYS | WINE | Result |
|---|---|---|
| V3.5 SP22 Patch 4 | 11.0 (stable) | Login fails, `0x80090029` |
| V3.5 SP22 Patch 4 | master `6d1b094` + patches (11.18) | **Simulation login OK** |

## License

These patches modify WINE and so fall under WINE's license, LGPL-2.1-or-later. See [COPYING](COPYING). This differs from the MIT license that covers the rest of the repository.
