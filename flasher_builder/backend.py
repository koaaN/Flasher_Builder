"""Linux build worker; also invoked by the Windows GUI through WSL.

No GitHub runner or device connection is required. Private release assets
use GitHub CLI authentication in the Linux build environment.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import queue
import re
import shutil
import signal
import subprocess
import sys
import threading
import time
from urllib.parse import urlsplit
import uuid
import zipfile

if __package__:
    from . import ota_catalog
else:
    import ota_catalog

ROOT = Path(sys.executable).resolve().parent if getattr(sys, 'frozen', False) else Path(__file__).resolve().parent.parent
GIB = 1024 ** 3


class BuildError(Exception):
    pass


class Cancelled(BuildError):
    pass


class Catalog:
    """Read the explicit workflow tables without an extra YAML dependency."""
    def __init__(self, root=ROOT):
        self.root = Path(root)
        text = (self.root / '.github/workflows/build_tools.yml').read_text(encoding='utf-8')
        self.devices = dict(re.findall(r'\["([^"]+)"\]="([^"]+)"', text.split('declare -A DEV_MAP=(', 1)[1].split(')', 1)[0]))
        self.sizes = {k: int(v) for k, v in re.findall(r'\["([^"]+)"\]="(\d+) \d+"', text)}
        self.builders = {tuple(key.split('|')): value + '.sh' for key, value in re.findall(r'BUILDER_MAP\["([^"]+)"\]="([^"]+)"', text)}
        if not self.devices or not self.builders:
            raise BuildError('The workflow device/builder tables could not be read.')

    def types(self, device):
        dev = self.devices[device]
        return list(dict.fromkeys(t for t, d, r in self.builders if d == dev))

    def regions(self, device, kind):
        dev = self.devices[device]
        return [r for r in ('GLO', 'EU', 'IN', 'NA', 'CN') if (kind, dev, r) in self.builders]

    def selection(self, device, kind, region):
        dev = self.devices.get(device)
        builder = self.builders.get((kind, dev, region))
        if not builder:
            raise BuildError('This device, flasher type and region combination is unsupported.')
        subtree = 'cos' if region == 'CN' else 'oos'
        template = self.root / 'flasher_scripts' / dev / subtree / ('super' if 'Super' in kind else 'regional')
        if not template.is_dir():
            raise BuildError(f'The workflow lists this combination, but its template is missing: {template}')
        if 'Hybrid' in kind and not (template / 'META-INF').is_dir():
            raise BuildError(f'Hybrid recovery files are missing: {template / "META-INF"}')
        return dev, builder, template


def clean_source(value):
    return value.strip().strip('"\'').replace('\\u0026', '&')


def is_url(source):
    return urlsplit(source).scheme.lower() in ('http', 'https')


def validate_ota(path):
    try:
        with zipfile.ZipFile(path) as z:
            info = z.getinfo('payload.bin')
            if info.file_size < 24:
                raise BuildError('The OTA payload is empty or truncated.')
            with z.open(info) as f:
                if f.read(4) != b'CrAU':
                    raise BuildError('payload.bin has an invalid Android payload header.')
            metadata = z.read('META-INF/com/android/metadata').decode('utf-8')
    except (OSError, zipfile.BadZipFile, KeyError, UnicodeError) as e:
        raise BuildError(f'Choose a full Android OTA ZIP containing payload.bin and metadata: {e}') from e
    fields = dict(line.split('=', 1) for line in metadata.splitlines() if '=' in line)
    if fields.get('ota-type', 'AB') != 'AB' or fields.get('pre-build') or fields.get('pre-build-incremental'):
        raise BuildError('This appears to be an incremental OTA. A FULL OTA is required.')
    version = fields.get('version_name') or fields.get('ota_version') or fields.get('post-build-incremental', '')
    matches = re.findall(r'\d+(?:\.\d+){1,4}', version)
    version = max(matches, key=len) if matches else re.sub(r'[^\w.()+-]', '_', version)[:80]
    if not version:
        raise BuildError('No version_name, ota_version or post-build-incremental found in OTA metadata.')
    return version, info.file_size, fields


class Worker:
    def __init__(self, cancel=None):
        self.cancel = Path(cancel) if cancel else None

    def check(self):
        if self.cancel and self.cancel.exists():
            raise Cancelled('Build cancelled. Partial files have been retained in the job folder.')

    def metadata(self, function, *args):
        """Keep cancellation responsive during bounded catalog/link HTTP requests."""
        result = queue.Queue()
        def task():
            try:
                result.put((True, function(*args)))
            except Exception as e:
                result.put((False, e))
        threading.Thread(target=task, daemon=True).start()
        while True:
            self.check()
            try:
                ok, value = result.get(timeout=.15)
                self.check()
                if ok:
                    return value
                raise value
            except queue.Empty:
                pass

    def run(self, args, cwd=None, env=None):
        self.check()
        proc = subprocess.Popen([str(a) for a in args], cwd=cwd, env=env, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True, encoding='utf-8', errors='replace',
                                start_new_session=True, bufsize=1)
        lines = queue.Queue()
        def reader():
            for line in proc.stdout:
                lines.put(line)
            lines.put(None)
        thread = threading.Thread(target=reader, daemon=True)
        thread.start()
        try:
            done = False
            while not done or proc.poll() is None:
                self.check()
                try:
                    line = lines.get(timeout=.15)
                    if line is None:
                        done = True
                    else:
                        print(line, end='', flush=True)
                except queue.Empty:
                    pass
            if proc.wait():
                raise BuildError(f'{Path(str(args[0])).name} failed (exit {proc.returncode}). See the log above.')
        finally:
            if proc.poll() is None:
                os.killpg(proc.pid, signal.SIGTERM)
                try:
                    proc.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    os.killpg(proc.pid, signal.SIGKILL)
                    proc.wait()
            proc.stdout.close()
            thread.join(timeout=1)

    def copy(self, source, dest):
        """Chunked copies keep cancellation responsive with multi-gigabyte OTAs."""
        with open(source, 'rb') as src, open(dest, 'wb') as dst:
            while True:
                self.check()
                chunk = src.read(4 * 1024 * 1024)
                if not chunk:
                    break
                dst.write(chunk)
        shutil.copystat(source, dest)

    def source(self, source, dest):
        source = clean_source(source)
        if not source:
            raise BuildError('Select a full OTA file or enter its HTTPS download URL.')
        if is_url(source):
            print(f'Downloading {dest.name} from {urlsplit(source).hostname}', flush=True)
            self.run(['curl', '--location', '--fail', '--retry', '3', '--retry-delay', '3',
                      '--connect-timeout', '30', '--speed-limit', '1024', '--speed-time', '120',
                      '--proto', '=https,http', '--proto-redir', '=https,http',
                      '-H', 'User-Agent: Dalvik/2.1.0 (Linux; U; Android 16; CPH2653 Build/AP3A.240617.008)',
                      '-H', 'userId: oplus-ota|15002017', '-H', 'language: en-US', '-H', 'brand: oneplus-exp',
                      '-o', str(dest) + '.part', source])
            Path(str(dest) + '.part').replace(dest)
        else:
            path = Path(source).expanduser().resolve()
            if not path.is_file():
                raise BuildError(f'OTA file not found: {path}')
            validate_ota(path)
            print(f'Copying {path.name} into the job folder…', flush=True)
            self.copy(path, dest)
        return validate_ota(dest)


def check_environment(root=ROOT):
    if sys.platform != 'linux' or platform.machine().lower() not in ('x86_64', 'amd64'):
        raise BuildError('The build tools require x86-64 Linux. On Windows, install an x86-64 WSL Ubuntu distribution.')
    required = ('bash', 'curl', 'rsync', 'python3', 'find', 'realpath', 'stat', 'od', 'awk', 'xargs', 'tr')
    missing = [tool for tool in required if not shutil.which(tool)]
    if missing:
        raise BuildError('Missing build tools: ' + ', '.join(missing) + '. On Ubuntu run: sudo apt install python3 curl rsync coreutils findutils gawk gh')
    for rel in ('otaripper/otaripper', 'lpmake/lpmake', 'scripts/stage_files.sh', 'build_tools_assets/avbtool.py'):
        if not (Path(root) / rel).is_file():
            raise BuildError(f'Missing project asset: {rel}. Keep the full project beside the launcher.')
    print(f'Backend: Linux {platform.machine()} • Python {platform.python_version()}', flush=True)
    print('Required tools and bundled binaries found.', flush=True)
    print(f'Free space in project: {shutil.disk_usage(root).free / GIB:.1f} GiB', flush=True)


def normalize_assets(repo, target, dev, template):
    # Copy only the selected device. Build scripts may delete their OUT_DIR;
    # the GUI always gives them a fresh, private directory inside this job.
    for directory in ('build_scripts', 'scripts', 'otaripper', 'lpmake', 'build_tools_assets', 'Platform-Tools'):
        shutil.copytree(repo / directory, target / directory)
    for directory in ('bloat', 'flasher_scripts'):
        if directory == 'bloat' and (repo / 'bloat/assets-manifest.json').is_file():
            continue
        src = repo / directory / dev
        if src.exists():
            shutil.copytree(src, target / directory / dev)
    manifest = repo / 'bloat/assets-manifest.json'
    if manifest.is_file():
        (target / 'bloat').mkdir(exist_ok=True)
        shutil.copy2(manifest, target / 'bloat/assets-manifest.json')
    for p in target.rglob('*'):
        if p.is_file() and (p.suffix == '.sh' or p.name in ('otaripper', 'lpmake', 'update-binary', 'pack_super', 'unpack_super', 'pack_super_regional', 'volprompt')):
            if p.suffix == '.sh':
                p.write_bytes(p.read_bytes().replace(b'\r\n', b'\n'))
            p.chmod(p.stat().st_mode | 0o111)


def package(worker, result, dest):
    partial = dest.with_suffix('.zip.part')
    print('Compressing final ZIP…', flush=True)
    with zipfile.ZipFile(partial, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=3, allowZip64=True) as z:
        for path in sorted(result.rglob('*')):
            worker.check()
            if path.is_file():
                # ZipInfo preserves executable modes for Linux flasher scripts.
                info = zipfile.ZipInfo.from_file(path, path.relative_to(result).as_posix())
                info.compress_type = zipfile.ZIP_DEFLATED
                info._compresslevel = 3
                with path.open('rb') as src, z.open(info, 'w', force_zip64=True) as dst:
                    while True:
                        worker.check()
                        chunk = src.read(4 * 1024 * 1024)
                        if not chunk:
                            break
                        dst.write(chunk)
    worker.check()
    digest = hashlib.sha256()
    with partial.open('rb') as f:
        while True:
            worker.check()
            chunk = f.read(4 * 1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
    partial.replace(dest)
    dest.with_suffix('.zip.sha256').write_text(f'{digest.hexdigest()}  {dest.name}\n', encoding='utf-8')


def require_local_bloat(args, repo, dev):
    if (repo / 'bloat/assets-manifest.json').is_file():
        source = Path(getattr(args, 'bloat_dir', '') or os.environ.get('BLOAT_SOURCE_DIR', str(repo / 'bloat'))).expanduser().resolve()
        Worker(args.cancel).run(['python3', repo / 'scripts/materialize_bloat.py',
            '--root', repo, '--source', source, '--cache', source / '.cache', '--check-only',
            '--device', dev, '--kind', args.kind, '--region', args.region])


def selected_release(args, role):
    release_id = getattr(args, role + '_catalog_id', '')
    if not release_id:
        return None
    target = ota_catalog.targets(args.device, args.kind, args.region).get(role)
    if target is None:
        raise BuildError('A BASE OTA is not used for this selection.')
    return ota_catalog.find_release(Path(args.repo) / '.ota-catalog', release_id, *target)


def prepare_ota(worker, args, role, destination):
    entry = worker.metadata(selected_release, args, role) if getattr(args, role + '_catalog_id', '') else None
    source = getattr(args, role)
    if entry:
        print(f'Catalog OTA: {entry["device"]} / {entry["region"]} / {entry["version"]}', flush=True)
        size = entry.get('size')
        if isinstance(size, int) and size > 0 and shutil.disk_usage(destination.parent).free < size + GIB:
            raise BuildError('Not enough space to download this OTA. Choose another output drive.')
        worker.check()
        source = worker.metadata(ota_catalog.resolve_link, entry)
        worker.check()
    standalone = getattr(args, 'download_ota', False)
    if standalone: print('STEP 2/5 • Download full OTA', flush=True)
    result = worker.source(source, destination)
    if standalone: print('STEP 3/5 • Verify full OTA ZIP', flush=True)
    if entry:
        size = entry.get('size')
        if isinstance(size, int) and size > 0 and destination.stat().st_size != size:
            raise BuildError('Downloaded OTA size does not match the catalog. Retry the download.')
        md5 = entry.get('md5', '')
        if md5:
            if not re.fullmatch(r'[0-9a-fA-F]{32}', md5):
                raise BuildError('The catalog has an invalid OTA checksum.')
            print('Verifying catalog MD5 checksum…', flush=True)
            if standalone: print('STEP 4/5 • Verify catalog checksum', flush=True)
            digest = hashlib.md5()
            with destination.open('rb') as f:
                while chunk := f.read(4 * 1024 * 1024):
                    worker.check()
                    digest.update(chunk)
            if digest.hexdigest().lower() != md5.lower():
                raise BuildError('Downloaded OTA checksum does not match the catalog. Retry the download.')
    return result


def download_ota(args):
    import tempfile
    repo = Path(args.repo).resolve()
    dev, _, _ = Catalog(repo).selection(args.device, args.kind, args.region)
    require_local_bloat(args, repo, dev)
    role = args.download_role
    if not getattr(args, role + '_catalog_id', ''):
        raise BuildError('Select an OTA catalog version first.')
    destination = Path(args.download_path).expanduser().resolve()
    if destination.exists():
        raise BuildError('The destination already exists. Choose a new filename or use the existing local OTA.')
    destination.parent.mkdir(parents=True, exist_ok=True)
    worker = Worker(args.cancel)
    with tempfile.TemporaryDirectory(prefix='.ota-download-', dir=destination.parent) as temporary:
        downloaded = Path(temporary) / 'OTA.zip'
        print('STEP 1/5 • Resolve selected OTA', flush=True)
        version, _, _ = prepare_ota(worker, args, role, downloaded)
        worker.check()
        downloaded.replace(destination)
    print(f'STEP 5/5 • OTA {version} downloaded and verified', flush=True)
    print('@@OTA_RESULT ' + json.dumps({'role': role, 'file': str(destination)}), flush=True)


def build(args):
    repo = Path(args.repo).resolve()
    check_environment(repo)
    catalog = Catalog(repo)
    dev, builder, template = catalog.selection(args.device, args.kind, args.region)
    require_local_bloat(args, repo, dev)
    output = Path(args.output).resolve()
    output.mkdir(parents=True, exist_ok=True)
    if shutil.disk_usage(output).free < GIB and not getattr(args, 'fixture', False):
        raise BuildError('Less than 1 GiB available in the output folder.')
    needs_base = builder == 'BUILD_ACE6_OOS.sh'
    if needs_base and not args.base and not getattr(args, 'base_catalog_id', ''):
        raise BuildError('Ace 6 OxygenOS needs the Ace 6 ColorOS BASE full OTA and the 15R India TARGET full OTA.')
    job = output / (time.strftime('%Y%m%d-%H%M%S') + '-' + uuid.uuid4().hex[:6])
    job.mkdir()
    print(f'Job folder: {job}', flush=True)
    # Tee every worker message and child output into a persistent log.
    class Tee:
        def __init__(self, original, log):
            self.original, self.log = original, log
        def write(self, text):
            self.original.write(text)
            self.log.write(text)
        def flush(self):
            self.original.flush()
            self.log.flush()
    old_out, old_err = sys.stdout, sys.stderr
    with (job / 'build.log').open('w', encoding='utf-8') as logfile:
        sys.stdout = sys.stderr = Tee(old_out, logfile)
        try:
            worker = Worker(args.cancel)
            download = job / 'download'
            download.mkdir()
            print('STEP 1/5 • Prepare OTA', flush=True)
            version, payload_size, metadata = prepare_ota(worker, args, 'ota', download / 'OTA.zip')
            if needs_base:
                _, base_size, _ = prepare_ota(worker, args, 'base', download / 'BASE.zip')
                payload_size += base_size
            print(f'OTA version: {version}; target devices: {metadata.get("pre-device", "not specified")}', flush=True)
            # Sparse output + raw images + archive can coexist. Check again
            # after downloading; do not start extraction on a nearly full disk.
            required = max(2 * GIB, payload_size * (5 if needs_base else 4))
            free = shutil.disk_usage(job).free
            if free < required and not getattr(args, 'fixture', False):
                raise BuildError(f'Not enough disk space: {free / GIB:.1f} GiB free; allow at least {required / GIB:.1f} GiB for this payload. Choose another output drive.')
            print('STEP 2/5 • Stage flasher and device assets', flush=True)
            assets = job / 'assets'
            normalize_assets(repo, assets, dev, template)
            env = os.environ.copy()
            env.update(DEV=dev, FTYPE=args.kind, REGION=args.region, BUILDER_SH=builder,
                       GITHUB_WORKSPACE=str(assets), OUT_DIR=str(job / 'stage'),
                       GITHUB_ENV=str(job / 'build.env'), OTA_PATH=str(download / 'OTA.zip'),
                       OTA_DIR=str(download), SUPER_SIZE=str(catalog.sizes.get(dev, 0)),
                       BASE_OTA_PATH=str(download / 'BASE.zip'), PYTHONUNBUFFERED='1',
                       BLOAT_CACHE_DIR=str(Path(os.environ.get('BLOAT_CACHE_DIR', str(repo / '.bloat-cache'))).expanduser().resolve()),
                       BLOAT_SOURCE_DIR=os.environ.get('BLOAT_SOURCE_DIR', str(repo / 'bloat')),
                       BLOAT_REQUIRE_LOCAL='1')
            if getattr(args, 'bloat_dir', ''):
                source = Path(args.bloat_dir).expanduser().resolve()
                env['BLOAT_SOURCE_DIR'] = str(source)
                env['BLOAT_CACHE_DIR'] = str(Path(os.environ.get('BLOAT_CACHE_DIR', str(source / '.cache'))).expanduser().resolve())
            worker.run(['bash', assets / 'scripts/stage_files.sh'], cwd=assets, env=env)
            print('STEP 3/5 • Extract partitions and build flasher', flush=True)
            worker.run(['bash', job / 'stage' / builder, download / 'OTA.zip'], cwd=download, env=env)
            name = args.kind + (' CN' if args.region == 'CN' else '')
            result = download / name
            if not result.is_dir():
                raise BuildError(f'Builder did not create the expected output: {result}')
            boot_dir = result / ('COS_FILES_HERE' if args.region == 'CN' else 'OOS_FILES_HERE')
            if not (boot_dir / 'boot.img').is_file():
                raise BuildError('Build output has no boot.img. The OTA may be incomplete or incompatible.')
            if 'Super' in args.kind and not (result / 'super.img').is_file():
                raise BuildError('Build output has no super.img.')
            print('STEP 4/5 • Package ZIP and calculate SHA-256', flush=True)
            suffix = 'COS' if args.region == 'CN' else args.region
            filename = ('TEST-DO-NOT-FLASH ' if getattr(args, 'fixture', False) else '') + f'{args.kind} {dev} {suffix} {version}.zip'
            dest = job / filename
            package(worker, result, dest)
            manifest = dict(device=args.device, flasher_type=args.kind, region=args.region,
                            version=version, artifact=filename, created=time.strftime('%Y-%m-%dT%H:%M:%S'),
                            test_fixture=bool(getattr(args, 'fixture', False)))
            (job / 'build.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
            print('Removing temporary working files…', flush=True)
            for directory in (assets, job / 'stage', download):
                shutil.rmtree(directory)
            print('STEP 5/5 • Complete', flush=True)
            print(f'ZIP: {dest}', flush=True)
            print('@@RESULT ' + json.dumps({'job': str(job), 'zip': str(dest)}), flush=True)
            return dest
        except BaseException as e:
            print(f'ERROR: {e}', flush=True)
            raise
        finally:
            sys.stdout, sys.stderr = old_out, old_err



def download_bloat(args):
    repo = Path(args.repo).resolve()
    dev, _, _ = Catalog(repo).selection(args.device, args.kind, args.region)
    destination = Path(args.bloat_dir).expanduser().resolve()
    destination.mkdir(parents=True, exist_ok=True)
    cache = Path(os.environ.get('BLOAT_CACHE_DIR', str(destination / '.cache'))).expanduser().resolve()
    print('STEP 1/5 • Check selected bloat files', flush=True)
    print(f'Bloat folder: {destination}', flush=True)
    print('STEP 2/5 • Download and verify bloat', flush=True)
    try:
        Worker(args.cancel).run(['python3', repo / 'scripts/materialize_bloat.py',
            '--root', repo, '--destination', destination, '--cache', cache,
            '--device', dev, '--kind', args.kind, '--region', args.region])
    except Cancelled:
        raise Cancelled('Bloat download cancelled. Completed images have been kept in the chosen folder.')
    print('STEP 5/5 • Bloat files ready', flush=True)
    print('@@BLOAT_RESULT ' + json.dumps({'folder': str(destination)}), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', default=str(ROOT))
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--self-test', action='store_true')
    parser.add_argument('--download-bloat', action='store_true')
    parser.add_argument('--download-ota', action='store_true')
    parser.add_argument('--download-role', choices=('ota', 'base'), default='ota')
    parser.add_argument('--download-path', default='')
    parser.add_argument('--ota-catalog-id', default='')
    parser.add_argument('--base-catalog-id', default='')
    parser.add_argument('--bloat-dir', default='')
    parser.add_argument('--device', default='Oneplus 13')
    parser.add_argument('--kind', default='SuperHybrid Flasher')
    parser.add_argument('--region', default='GLO')
    parser.add_argument('--ota', default='')
    parser.add_argument('--base', default='')
    parser.add_argument('--output', default=str(ROOT / 'builds'))
    parser.add_argument('--cancel')
    args = parser.parse_args()
    try:
        if args.check:
            check_environment(Path(args.repo))
            print(f'{len(Catalog(args.repo).builders)} supported workflow combinations.', flush=True)
        elif args.download_bloat:
            if not args.bloat_dir:
                raise BuildError('Choose a bloat download folder.')
            download_bloat(args)
        elif args.download_ota:
            if not args.download_path:
                raise BuildError('Choose an OTA download destination.')
            download_ota(args)
        elif args.self_test:
            from selftest import run_self_test
            run_self_test(args)
        else:
            build(args)
        return 0
    except Cancelled as e:
        print(str(e), flush=True)
        return 130
    except (BuildError, ota_catalog.CatalogError, OSError, ValueError) as e:
        print(f'ERROR: {e}', flush=True)
        return 1


if __name__ == '__main__':
    sys.exit(main())
