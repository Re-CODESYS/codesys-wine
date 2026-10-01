#!/usr/bin/env python3
"""Extract the embedded files of an InstallShield setup EXE (ISSetupStream format).

Pure-Python reimplementation of the stream decoding described by ISx and used in
livingforjesus/codesys-macos-install-guide (helpers/extract.py).
Usage: is_extract.py <setup.exe> <outdir>
"""
import mmap, struct, sys, zlib
from pathlib import Path

ROT4 = bytes(((b << 4) | (b >> 4)) & 0xFF for b in range(256))
NOT = bytes(0xFF - b for b in range(256))
CHUNK = 1 << 20  # multiple of 1024, so the key position restarts per chunk


def decode(data: bytes, key: bytes) -> bytes:
    # p = ~(k[(i % 1024) % len(k)] ^ rot4(p))
    block = bytes(key[(i % 1024) % len(key)] for i in range(1024))
    stream = (block * (len(data) // 1024 + 1))[:len(data)]
    x = int.from_bytes(data.translate(ROT4), 'little') ^ int.from_bytes(stream, 'little')
    return x.to_bytes(len(data), 'little').translate(NOT)


def overlay_offset(m) -> int:
    """End of the last PE section, where the appended setup stream begins."""
    pe = struct.unpack_from('<I', m, 0x3C)[0]
    nsec, = struct.unpack_from('<H', m, pe + 6)
    optsize, = struct.unpack_from('<H', m, pe + 20)
    sec = pe + 24 + optsize
    return max(sum(struct.unpack_from('<II', m, sec + 40 * i + 16)) for i in range(nsec))


def main(src, dst):
    out = Path(dst).resolve()
    out.mkdir(parents=True, exist_ok=True)
    with open(src, 'rb') as f:
        m = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ)
        # The string also occurs in the stub's code, so search from the overlay.
        pos = m.find(b'ISSetupStream\0', overlay_offset(m))
        if pos < 0:
            sys.exit('ISSetupStream header not found')
        count, typ = struct.unpack_from('<HI', m, pos + 14)
        pos += 46
        for _ in range(count):
            nl, flags, length, compressed = struct.unpack_from('<II2xI8xH', m, pos)
            pos += 48 if typ == 4 else 24
            name = m[pos:pos + nl].decode('utf-16le').rstrip('\0')
            pos += nl
            target = (out / name.replace('\\', '/')).resolve()
            if not target.is_relative_to(out):
                sys.exit(f'unsafe path {name!r}')
            target.parent.mkdir(parents=True, exist_ok=True)
            key = bytes(c ^ b'\x13\x35\x86\x07'[j % 4] for j, c in enumerate(name.encode()))
            print(name, length, flags, compressed, flush=True)
            z = zlib.decompressobj() if compressed else None
            with target.open('wb') as d:
                for off in range(0, length, CHUNK):
                    data = m[pos + off:pos + min(off + CHUNK, length)]
                    if flags & 4:
                        data = decode(data, key)
                    d.write(z.decompress(data) if z else data)
                if z:
                    d.write(z.flush())
                    assert z.eof
            pos += length


if __name__ == '__main__':
    main(*sys.argv[1:3])
