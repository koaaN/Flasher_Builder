"""Exercise actual OTA extraction, super packing and packaging with tiny fixtures.

The generated payload uses Android's update_metadata.proto wire format with
REPLACE operations. It contains test bytes, never flashable firmware.
"""
from __future__ import annotations
from argparse import Namespace
import hashlib
import io
from pathlib import Path
import shutil
import struct
import time
import uuid
import zipfile

if __package__:
    from .backend import BuildError, Worker, build, check_environment
    from .host import helper_command
else:
    from __main__ import BuildError, Worker, build, check_environment
    from host import helper_command


def varint(value):
    data = bytearray()
    while value > 127:
        data.append((value & 127) | 128)
        value >>= 7
    data.append(value)
    return bytes(data)


def number(field, value):
    return varint(field << 3) + varint(value)


def blob(field, data):
    return varint((field << 3) | 2) + varint(len(data)) + data


def make_ota(path, partitions):
    manifest = number(3, 4096) + number(12, 0)
    payload_data = b''
    for name, data in partitions.items():
        assert len(data) % 4096 == 0
        extent = number(1, 0) + number(2, len(data) // 4096)
        operation = (number(1, 0) + number(2, len(payload_data)) + number(3, len(data))
                     + blob(6, extent) + number(7, len(data)) + blob(8, hashlib.sha256(data).digest()))
        info = number(1, len(data)) + blob(2, hashlib.sha256(data).digest())
        partition = blob(1, name.encode()) + blob(7, info) + blob(8, operation)
        manifest += blob(13, partition)
        payload_data += data
    payload = b'CrAU' + struct.pack('>QQI', 2, len(manifest), 0) + manifest + payload_data
    with zipfile.ZipFile(path, 'w') as z:
        z.writestr('payload.bin', payload)
        z.writestr('META-INF/com/android/metadata', 'ota-type=AB\npre-device=TEST-ONLY\nversion_name=TEST_1.2.3.4\n')
    return partitions


def sparse_range(image, start, length):
    """Read a small range without expanding a multi-gigabyte sparse super image."""
    stream = io.BytesIO(image)
    magic, major, minor, header_size, chunk_size, block_size, blocks, count, checksum = struct.unpack('<IHHHHIIII', stream.read(28))
    if magic != 0xed26ff3a or major != 1: raise BuildError('Self-test: invalid sparse header.')
    stream.seek(header_size)
    position = 0; result = bytearray()
    for _ in range(count):
        kind, reserved, chunk_blocks, total = struct.unpack('<HHII', stream.read(12))
        stream.seek(chunk_size-12, 1)
        data_start = stream.tell(); expanded = chunk_blocks*block_size
        left = max(start, position); right = min(start+length, position+expanded)
        if right > left:
            offset = left-position; size = right-left
            if kind == 0xcac1:
                stream.seek(data_start+offset); result.extend(stream.read(size))
            elif kind == 0xcac2:
                stream.seek(data_start); pattern = stream.read(4)
                result.extend((pattern*((offset%4+size+3)//4))[offset%4:offset%4+size])
            elif kind == 0xcac3: result.extend(b'\0'*size)
            else: raise BuildError('Self-test: unsupported sparse chunk.')
        position += expanded
        stream.seek(data_start + total-chunk_size)
        if len(result) == length: return bytes(result)
    raise BuildError('Self-test: sparse range is truncated.')


def verify_super(image, expected):
    # LP primary metadata starts after the reserved region and two geometries.
    header = sparse_range(image, 12288, 256)
    if struct.unpack_from('<I', header)[0] != 0x414c5030:
        raise BuildError('Self-test: missing logical partition metadata.')
    header_size = struct.unpack_from('<I', header, 8)[0]
    tables_size = struct.unpack_from('<I', header, 44)[0]
    tables = sparse_range(image, 12288+header_size, tables_size)
    if hashlib.sha256(tables).digest() != header[48:80]: raise BuildError('Self-test: LP table checksum mismatch.')
    offset, count, size = struct.unpack_from('<III', header, 80)
    ext_offset, ext_count, ext_size = struct.unpack_from('<III', header, 92)
    partitions = {}
    for index in range(count):
        entry = tables[offset+index*size:offset+(index+1)*size]
        name = entry[:36].split(b'\0')[0].decode()
        first, extents = struct.unpack_from('<II', entry, 40)
        if extents:
            extent = tables[ext_offset+first*ext_size:ext_offset+(first+1)*ext_size]
            sectors, kind, sector, device = struct.unpack('<QIQI', extent)
            if kind != 0: raise BuildError('Self-test: expected a linear LP extent.')
            partitions[name] = (sector*512, sectors*512)
    for name, data in expected.items():
        if name+'_a' not in partitions: raise BuildError('Self-test: partition missing from super: '+name)
        offset, size = partitions[name+'_a']
        if sparse_range(image, offset, len(data)) != data:
            raise BuildError('Self-test: wrong source bytes in super: '+name)


def run_self_test(args):
    repo = Path(args.repo).resolve()
    check_environment(repo)
    worker = Worker(args.cancel)
    base = Path(args.output).resolve() / ('self-test-' + time.strftime('%Y%m%d-%H%M%S') + '-' + uuid.uuid4().hex[:6])
    base.mkdir(parents=True)
    fixture = base / 'fixture-repo'
    fixture.mkdir()
    print('SELF-TEST ONLY — generated images are NOT firmware. DO NOT FLASH.', flush=True)
    print(f'Self-test folder: {base}', flush=True)
    for directory in ('.github', 'build_scripts', 'scripts', 'otaripper', 'lpmake', 'build_tools_assets', 'Platform-Tools'):
        shutil.copytree(repo / directory, fixture / directory)
    for dev in ('13', 'Ace6'):
        shutil.copytree(repo / 'flasher_scripts' / dev, fixture / 'flasher_scripts' / dev)
        for region in ('GLO_BLOAT', 'CN_BLOAT', 'OOS_BLOAT', 'COS_FILES_HERE'):
            folder = fixture / 'bloat' / dev / region
            folder.mkdir(parents=True)
            for name in ('my_preload', 'my_company', 'my_region', 'oplusstanvbk'):
                (folder / (name + '.img')).write_bytes(b'\0' * 4096)
    partitions = {name: (('TEST ONLY ' + name + '\n').encode() * 300)[:4096].ljust(4096, b'\0')
                  for name in ('boot', 'init_boot', 'system', 'system_ext', 'product', 'vendor', 'vendor_dlkm', 'odm', 'system_dlkm', 'my_region', 'my_bigball', 'my_carrier', 'my_engineering', 'my_heytap', 'my_manifest', 'my_product', 'my_stock')}
    # Ace6's real builder reads and rewrites vbmeta using the bundled avbtool.
    vbmeta = base / 'vbmeta.img'
    worker.run(helper_command(repo, 'avbtool', 'make_vbmeta_image', '--output', vbmeta, '--padding_size', '4096'))
    for name in ('vbmeta', 'vbmeta_system', 'vbmeta_vendor'):
        partitions[name] = vbmeta.read_bytes()
    ota = base / 'TEST-ONLY-full-OTA.zip'
    make_ota(ota, partitions)
    target_parts = dict(partitions, system=b'TARGET SYSTEM\0'.ljust(4096, b'T'),
                        product=b'TARGET PRODUCT\0'.ljust(4096, b'P'))
    target_ota = base / 'TEST-ONLY-target-OTA.zip'
    make_ota(target_ota, target_parts)
    cases = [('Oneplus 13', 'SuperHybrid Flasher', 'GLO'),
             ('Oneplus 13', 'RegionalHybrid Flasher', 'CN'),
             ('Oneplus 13', 'RegionalHybrid Flasher', 'GLO'),
             ('Oneplus Ace 6', 'Super Flasher', 'CN'),
             ('Oneplus Ace 6', 'SuperHybrid Flasher', 'IN')]
    for device, kind, region in cases:
        worker.check()
        print(f'\nSELF-TEST: {device} / {kind} / {region}', flush=True)
        conversion = device == 'Oneplus Ace 6' and region == 'IN'
        dest = build(Namespace(repo=str(fixture), output=str(base / 'results'), device=device, kind=kind,
                               region=region, ota=str(target_ota if conversion else ota), base=str(ota), cancel=args.cancel, fixture=True))
        with zipfile.ZipFile(dest) as z:
            boot = ('COS_FILES_HERE' if region == 'CN' else 'OOS_FILES_HERE') + '/boot.img'
            if z.read(boot) != partitions['boot']:
                raise BuildError('Self-test: extracted boot image differs from payload.')
            if 'Super' in kind:
                if z.read('super.img')[:4] != b'\x3a\xff\x26\xed':
                    raise BuildError('Self-test: super.img is not an Android sparse image.')
                verify_super(z.read('super.img'), dict(system=(target_parts if conversion else partitions)['system'],
                                                      product=(target_parts if conversion else partitions)['product'], vendor=partitions['vendor']))
                if conversion:
                    for name in ('vbmeta', 'vbmeta_system', 'vbmeta_vendor'):
                        if struct.unpack_from('>I', z.read('OOS_FILES_HERE/'+name+'.img'), 120)[0] != 3:
                            raise BuildError('Self-test: base vbmeta flags were not patched.')
            bad = z.testzip()
            if bad:
                raise BuildError(f'Self-test: ZIP checksum failed: {bad}')
        expected = dest.with_suffix('.zip.sha256').read_text().split()[0]
        if hashlib.sha256(dest.read_bytes()).hexdigest() != expected:
            raise BuildError('Self-test: package SHA-256 mismatch.')
    (base / 'SELF-TEST-PASSED.txt').write_text('All five pipeline tests passed with the REAL otaripper, lpmake and avbtool.\nGenerated packages contain test bytes. DO NOT FLASH.\n', encoding='utf-8')
    print('\nSELF-TEST PASSED: extraction, three builders, sparse super image, vbmeta patching, ZIP integrity and SHA-256.', flush=True)
