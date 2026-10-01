#!/usr/bin/env python3
"""Extract the add-on packages bundled in a CODESYS MSI.

The packages are stored as ISSetupFile.* streams of the MSI (an OLE compound
file). 7-Zip pulls the streams out; each package is a ZIP whose
package.manifest carries its display name and version.
Usage: extract_packages.py <CODESYS 64 x.msi> <outdir>
"""
import re, shutil, subprocess, sys, tempfile, zipfile
from pathlib import Path


def package_name(path: Path):
    try:
        with zipfile.ZipFile(path) as z:
            manifest = z.read('package.manifest').decode('utf-8-sig')
    except (zipfile.BadZipFile, KeyError):
        return None
    name = re.search(r'<String Id="GeneralName">\s*<Neutral>([^<]+)', manifest)
    version = re.search(r'<Version>([^<]+)</Version>', manifest)
    if not (name and version):
        return None
    return f'{name.group(1).replace("/", " ")} {version.group(1)}.package'


def main(msi, dst):
    out = Path(dst)
    out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run(['7z', 'e', '-y', f'-o{tmp}', msi, 'ISSetupFile.*'],
                       check=True, stdout=subprocess.DEVNULL)
        for f in sorted(Path(tmp).iterdir()):
            name = package_name(f)
            if name:
                shutil.move(str(f), out / name)
                print(name)


if __name__ == '__main__':
    main(*sys.argv[1:3])
