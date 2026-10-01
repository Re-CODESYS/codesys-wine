#!/usr/bin/env python3
"""Write the main icon of a Windows .exe as an .ico file.

Usage: pe_icon.py <program.exe> <out.ico>
Takes the first RT_GROUP_ICON resource and the RT_ICON images it references.
"""
import struct, sys

RT_ICON, RT_GROUP_ICON = 3, 14


def sections(b):
    pe = struct.unpack_from('<I', b, 0x3C)[0]
    n, = struct.unpack_from('<H', b, pe + 6)
    opt, = struct.unpack_from('<H', b, pe + 20)
    magic, = struct.unpack_from('<H', b, pe + 24)
    dd = pe + 24 + (112 if magic == 0x20B else 96)
    rsrc_rva, _ = struct.unpack_from('<II', b, dd + 2 * 8)
    secs = []
    for i in range(n):
        o = pe + 24 + opt + 40 * i
        vsize, va, rsize, raw = struct.unpack_from('<IIII', b, o + 8)
        secs.append((va, max(vsize, rsize), raw))
    return rsrc_rva, secs


def rva2off(rva, secs):
    for va, size, raw in secs:
        if va <= rva < va + size:
            return rva - va + raw
    raise ValueError(f'RVA {rva:#x} not in any section')


def entries(b, base, off):
    named, ids = struct.unpack_from('<HH', b, off + 12)
    for i in range(named + ids):
        name, target = struct.unpack_from('<II', b, off + 16 + 8 * i)
        yield name, target


def resources(b, rtype):
    """Yield (id, data) of all resources of one type (first language)."""
    rsrc, secs = sections(b)
    base = rva2off(rsrc, secs)
    for name, target in entries(b, base, base):
        if name != rtype:
            continue
        for rid, t2 in entries(b, base, base + (target & 0x7FFFFFFF)):
            _, t3 = next(entries(b, base, base + (t2 & 0x7FFFFFFF)))
            rva, size = struct.unpack_from('<II', b, base + t3)
            o = rva2off(rva, secs)
            yield rid, b[o:o + size]


def main(exe, out):
    b = open(exe, 'rb').read()
    icons = dict(resources(b, RT_ICON))
    _, grp = next(resources(b, RT_GROUP_ICON))
    _, _, count = struct.unpack_from('<HHH', grp, 0)
    items = [struct.unpack_from('<BBBBHHIH', grp, 6 + 14 * i) for i in range(count)]
    items = [it for it in items if it[7] in icons]
    head = struct.pack('<HHH', 0, 1, len(items))
    dirs, data, offset = b'', b'', 6 + 16 * len(items)
    for w, h, colors, res, planes, bits, _, iid in items:
        img = icons[iid]
        dirs += struct.pack('<BBBBHHII', w, h, colors, res, planes, bits, len(img), offset + len(data))
        data += img
    open(out, 'wb').write(head + dirs + data)


if __name__ == '__main__':
    main(*sys.argv[1:3])
