"""Check whether an Android v2 payload can reconstruct images without a base.

Field numbers follow AOSP system/update_engine/update_metadata.proto. Only the
bounded manifest is read; image data is verified by the native extractor.
"""
import struct


def fields(data):
    position = 0

    def varint():
        nonlocal position
        result = 0
        for shift in range(0, 70, 7):
            if position >= len(data): break
            value = data[position]; position += 1
            result |= (value & 127) << shift
            if value < 128: return result
        raise ValueError('Truncated payload manifest integer')

    while position < len(data):
        tag = varint(); field, wire = tag >> 3, tag & 7
        if not field: raise ValueError('Invalid payload manifest field')
        if wire == 0:
            value = varint()
        elif wire in (1, 2, 5):
            length = varint() if wire == 2 else 8 if wire == 1 else 4
            end = position + length
            if end > len(data): raise ValueError('Truncated payload manifest field')
            value = data[position:end]; position = end
        else:
            raise ValueError('Unsupported payload manifest field encoding')
        yield field, value


def verify_full_payload(stream, payload_size):
    header = stream.read(24)
    if len(header) != 24 or header[:4] != b'CrAU':
        raise ValueError('Invalid Android payload header')
    major, length, signature = struct.unpack('>QQI', header[4:])
    data_start = 24 + length + signature
    if major != 2 or not 0 < length <= 16 * 1024**2 or data_start > payload_size:
        raise ValueError('Invalid Android payload manifest size or version')
    manifest = stream.read(length)
    if len(manifest) != length: raise ValueError('Truncated payload manifest')
    top = list(fields(manifest)); block_size = dict(top).get(3, 4096)
    if not isinstance(block_size, int) or block_size <= 0:
        raise ValueError('Invalid payload block size')
    names = set()
    for field, partition in top:
        if field != 13: continue
        entries = list(fields(partition)); info = dict(entries)
        name = info.get(1)
        if not isinstance(name, bytes) or not name or name in names:
            raise ValueError('Invalid or duplicate payload partition')
        names.add(name)
        size = dict(fields(info.get(7, b''))).get(1, 0)
        if not isinstance(size, int) or size <= 0:
            raise ValueError('Missing payload partition size')
        extents = []
        for key, operation in entries:
            if key != 8: continue
            values = list(fields(operation)); op = dict(values)
            if op.get(1) not in (0, 1, 6, 7, 8, 14) or any(k == 4 for k, _ in values) or op.get(5) or op.get(9):
                raise ValueError('Incremental payload operations require an older image')
            if op[1] in (0, 1, 8, 14):
                offset, count = op.get(2, 0), op.get(3, 0)
                if not isinstance(offset, int) or not isinstance(count, int) or offset < 0 or count <= 0 or data_start + offset + count > payload_size:
                    raise ValueError('Invalid payload operation data range')
            for k, extent in values:
                if k != 6: continue
                e = dict(fields(extent)); start, count = e.get(1), e.get(2)
                if not isinstance(start, int) or not isinstance(count, int) or start < 0 or count <= 0:
                    raise ValueError('Invalid payload destination extent')
                extents.append((start, start + count))
        end = 0
        for first, last in sorted(extents):
            if first != end: raise ValueError('Payload does not contain a complete partition image')
            end = last
        if end != (size + block_size - 1) // block_size:
            raise ValueError('Payload does not contain a complete partition image')
    if not names: raise ValueError('Payload has no partition images')
    return len(names)
