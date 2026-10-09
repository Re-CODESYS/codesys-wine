# Tests

## Online login (headless)

`run-login-test.sh` starts CODESYS without a UI, opens a **copy** of a project, switches its devices to simulation, and logs in. You don't have to click anything.

```sh
WINEPREFIX=~/.local/share/wineprefixes/codesys tests/run-login-test.sh ~/MyProject.project
WINEPREFIX=~/.local/share/wineprefixes/codesys-dev tests/run-login-test.sh ~/MyProject.project ~/wine-dev/build/wine
```

Requirements:
- the **CODESYS Scripting** package in the prefix (`install.sh --packages`),
- a project whose PLC device supports simulation (for example a Standard project with *CODESYS Control Win V3 x64*).

Output and exit status:

| Output | Exit | Meaning |
|---|---|---|
| `LOGIN_OK state=stop` | 0 | Login works |
| `LOGIN_FAIL … "-2146893783"` | 1 | The ncrypt OAEP gap: use a WINE with [the patches](../wine-patches/) |
| `SCRIPT_ERROR …` / `no result` | 2 | See the trace file (`TRACE=`, default `./login-test.trace`) |

The trace has `+ncrypt` turned on by default. `grep NCryptEncrypt login-test.trace` shows the RSA-OAEP call that the patch fixes.

> CODESYS may crash **after** the script has finished: an IronPython `AccessViolationException` at shutdown, followed by a WINE "Program Error". This happens with and without the patches, and it doesn't affect the result. The runner turns off WINE's crash dialog in the test prefix.

## Visualization profile (headless)

`run-visu-test.sh` opens a **copy** of a project without a UI, adds a Visualization object, checks that CODESYS finds a visualization profile, and builds. Without a profile the Visualization Toolbox stays empty ([troubleshooting](../docs/troubleshooting.md#visualization-toolbox-is-empty)).

```sh
WINEPREFIX=~/.local/share/wineprefixes/codesys tests/run-visu-test.sh ~/MyProject.project
```

It needs the same packages as the login test plus **CODESYS Visualization** (always installed by `install.sh`), and any project with an application.

| Output | Exit | Meaning |
|---|---|---|
| `VISU_OK profile=CODESYS Visualization 4.10.0.0` | 0 | A profile is available; the toolbox lists elements |
| `VISU_FAIL no visualization profile`, with messages like "The file 'inputs' is missing in the repository for visual elements" | 1 | `Visual Elements\formatinfo` is missing: re-run `install.sh`, or see troubleshooting |
| `SCRIPT_ERROR …` / `no result` | 2 | See the trace file (`TRACE=`, default `./visu-test.trace`) |

## WINE conformance tests

The patches include WINE unit tests. After `wine-patches/build-wine.sh`:

```sh
cd ~/wine-dev/build
export WINEPREFIX=~/wine-dev/testprefix WINEDLLOVERRIDES="mscoree,mshtml="   # throwaway prefix, no Mono/Gecko prompts
make dlls/ncrypt/tests/test dlls/bcrypt/tests/test \
     dlls/shell32/tests/x86_64-windows/shelllink.ok dlls/shell32/tests/i386-windows/shelllink.ok \
     programs/cmd/tests/x86_64-windows/batch.ok programs/cmd/tests/i386-windows/batch.ok
```

The command prints nothing and exits with 0 when all tests pass.
