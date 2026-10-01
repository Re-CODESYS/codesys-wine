# WINE basics for CODESYS users

What you need to know to run and maintain CODESYS under WINE. Errors and how to trace them are covered in [troubleshooting.md](troubleshooting.md).

## The prefix: your "Windows installation"

WINE keeps a complete, separate Windows environment in a folder called a **prefix**. `install.sh` creates one just for CODESYS:

```
~/.local/share/wineprefixes/codesys/       # default, override with WINEPREFIX=
├── drive_c/                               # C:  (CODESYS is in C:\CODESYS-3.5.x.y)
├── dosdevices/                            # drive letters (z: → / , your whole Linux file system)
├── user.reg  system.reg                   # the Windows registry, as text files
└── codesys-launch.log                     # output of the launcher
```

- Every `wine …` command acts on the prefix named by **`WINEPREFIX`**. Always set it, or you'll end up working on `~/.wine`:
  ```sh
  export WINEPREFIX=~/.local/share/wineprefixes/codesys
  ```
- **Backup / experiment safely:** close CODESYS, then `cp -a` the whole folder. Restoring means copying it back.
- **Uninstall:** delete the prefix folder plus the launchers in `~/.local/bin/codesys-*` and `~/.local/share/applications/codesys-*.desktop`.
- A prefix is **not a sandbox**. Windows programs in it can read and write your files through `Z:`.

## Starting and stopping

| Task | Command |
|---|---|
| Start CODESYS | menu entry, or `~/.local/bin/codesys-3.5.22.40` |
| Start the CODESYS Installer | `~/.local/bin/codesys-installer…` |
| CODESYS hangs, or a dialog is stuck | `WINEPREFIX=… wineserver -k`. Kills **all** Windows programs in that prefix (only that prefix). Unsaved work is lost. |
| Wait until everything in the prefix has exited | `WINEPREFIX=… wineserver -w` |
| WINE's own settings window | `WINEPREFIX=… winecfg` |
| Registry editor | `WINEPREFIX=… wine regedit` |

The first start after installing or updating WINE takes a few minutes, because WINE updates the prefix and .NET compiles its caches.

## Screen size and font scaling (HiDPI)

WINE scales all windows and fonts by its **DPI setting**. The default is 96 dpi (100 %), which looks tiny on a laptop panel that the desktop runs at 125–150 %.

| Scale | dpi |
|---|---|
| 100 % | 96 |
| 125 % | 120 |
| 150 % | 144 |
| 200 % | 192 |

- **GUI:** `winecfg` → **Graphics** → *Screen resolution*.
- **Command** (CODESYS closed; takes effect on the next start):
  ```sh
  WINEPREFIX=… wine reg add 'HKCU\Software\Wine\Fonts' /v LogPixels /t REG_DWORD /d 144 /f
  ```
- WINE has **one DPI value for all monitors**. With a 150 % laptop panel and a 100 % external monitor, pick the one you work on most, or 120 as a compromise.
- On **KDE Plasma (Wayland)**, *System Settings → Display → Legacy applications (X11)*:
  - "Apply scaling themselves" (sharp) needs the WINE DPI above.
  - "Scaled by the system" scales WINE windows per monitor, but blurry.
- Only the code editor font: CODESYS *Tools → Options → Text Editor → Font*.

## Files and paths

- Linux paths appear as `Z:\home\<you>\…` inside CODESYS. Projects can stay in your Linux home folder.
- Convert paths with `winepath`:
  ```sh
  WINEPREFIX=… winepath -w ~/Documents/plant.project   # → Z:\home\you\Documents\plant.project
  WINEPREFIX=… winepath -u 'C:\CODESYS-3.5.22.40'      # → /home/you/.local/share/wineprefixes/…/drive_c/CODESYS-3.5.22.40
  ```
- Keep project paths free of exotic characters. CODESYS and WINE handle UTF-8, but `LC_ALL=en_US.UTF-8` must be available (`locale -a`).

## Settings you should not change

`install.sh` sets these on purpose. Changing them breaks CODESYS:

| Setting | Where | Why |
|---|---|---|
| Windows version **Windows 10** | `winecfg` → Applications | CODESYS requires Windows 10 or 11. |
| `*security` = native for CODESYS programs | `HKCU\Software\Wine\AppDefaults\<exe>\DllOverrides` | CODESYS's own `Security.dll` would otherwise be shadowed by WINE's. |
| `ncrypt`, `bcrypt` = native,builtin for `CODESYS.exe` | same | The [crypto fix](../wine-patches/) for online login. Manage it with `install/crypto-fix.sh status / remove / apply`. |
| .NET 4.8, VC++ 2022, MSXML6, WebView2 | installed with winetricks | Runtime components CODESYS needs. Don't uninstall them. |

## Updating WINE

- Stay on **WineHQ `winehq-stable` 11.x**; see the README section "Which WINE".
- After a WINE update, the next start updates the prefix automatically.
- Check that the crypto fix still matches: `WINEPREFIX=… install/crypto-fix.sh status`. It is tested with a specific WINE version and skips untested ones.
- Distribution WINE packages (Debian 13 / Ubuntu ship 10.x or 9.x) are too old. Use the WineHQ repository.

## PLC communication

- There's no Windows Gateway service in the prefix. Use the **native Linux** CODESYS Edge Gateway (or the Gateway of CODESYS Control for Linux), and add it in CODESYS as `localhost`, port `1217`, or by IP for another machine.
- Licensing: CodeMeter runs natively on Linux; see the README.

## Logs and when something goes wrong

- The launcher writes WINE's output to `$WINEPREFIX/codesys-launch.log`. It's quiet by default (`WINEDEBUG=-all`).
- For a diagnostic run, start the launcher with debug channels:
  ```sh
  WINEDEBUG=err+all,fixme+all ~/.local/bin/codesys-3.5.22.40
  ```
  Then look at the end of `codesys-launch.log`.
- `fixme:` lines are normal. They mark features WINE implements only partly. They matter only right before a failure.
- Negative error numbers in CODESYS dialogs are Windows HRESULTs: `printf '%x\n' $(( -2146893783 & 0xffffffff ))` → `80090029`.
- Known errors with their causes and fixes: [troubleshooting.md](troubleshooting.md).
