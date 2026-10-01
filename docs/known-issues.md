# Known issues

## Online login fails: `Unknown error "-2146893783"`

`-2146893783` = `0x80090029` = `NTE_NOT_SUPPORTED`.

When you log in to a device (also seen with Simulation), CODESYS imports the device's RSA public key and encrypts with it through CNG:

```
NCryptImportKey(RSAPUBLICBLOB, 2048 bit)
NCryptEncrypt(..., flags = NCRYPT_PAD_OAEP_FLAG)
```

WINE's `dlls/ncrypt/main.c` rejects `NCRYPT_PAD_OAEP_FLAG` up front. This is still the case in WINE master as of September 2026. The bcrypt side of RSA-OAEP is fixed in WINE 11.5 ([bug 59460](https://bugs.winehq.org/show_bug.cgi?id=59460)). There is no WINE bug or wine-staging patch for the ncrypt part yet. Work on a fix is in progress.

To trace it yourself:

```sh
WINEDEBUG=+ncrypt,+bcrypt ~/.local/bin/codesys-3.5.22.40
```

## Other limitations

- **CodeMeter** isn't installed, so licensed add-ons and dongles are unavailable.
- **CODESYS Installer (APInstaller)** hangs under WINE. Install packages with `PackageManagerCLI.exe` instead.
- **Visualization 4.10** fails to install. WINE doesn't implement `IShellLinkDataList::RemoveDataBlock`.
- **Start page "Latest news"** stays empty because WebView2 runs with the GPU turned off.
- **Gateway / PLC scan:** the Windows Gateway service isn't installed. Use a gateway running natively on Linux, such as CODESYS Control for Linux SL or Edge Gateway for Linux, and add it by IP (port 1217). This is untested until online login works.
- **First start** takes a few minutes.
