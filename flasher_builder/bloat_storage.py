"""Delete only a selection's local images and cache objects no other image uses."""
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from scripts.materialize_bloat import selected_paths


class BloatStorageError(Exception):
    pass


def local_file(root, relative):
    try:
        resolved = root.resolve()
    except (OSError, RuntimeError) as e:
        raise BloatStorageError('Could not resolve the bloat folder safely.') from e
    if resolved != root or root.is_symlink() or getattr(root, 'is_junction', lambda: False)():
        raise BloatStorageError('The bloat folder changed or is now linked. Choose its real location before deleting.')
    parts = PurePosixPath(relative).parts
    if PurePosixPath(relative).is_absolute() or not parts or any(p in ('', '.', '..') or '\\' in p or ':' in p for p in parts):
        raise BloatStorageError('Invalid local bloat path.')
    path = root
    for part in parts:
        path = path / part
        if path.is_symlink() or getattr(path, 'is_junction', lambda: False)():
            raise BloatStorageError('Cannot delete through linked folders or files: ' + str(path))
    if path.exists() and not path.is_file():
        raise BloatStorageError('Expected a bloat file, but found a folder: ' + str(path))
    return path


@dataclass(frozen=True)
class DeletionPlan:
    root: Path
    files: tuple
    cache: tuple
    bytes: int


def plan_deletion(manifest, destination, device, kind, region):
    root = Path(destination).expanduser().resolve()
    selected = set(selected_paths(manifest, device, kind, region))
    files = []
    for relative in sorted(selected):
        path = local_file(root, PurePosixPath(relative).relative_to('bloat').as_posix())
        if path.is_file():
            files.append(path)
    cache = []
    for key in {manifest['files'][p] for p in selected}:
        # Keep shared download objects while another selection has a local copy.
        other_local = any(sha == key and p not in selected and
            (root / PurePosixPath(p).relative_to('bloat')).exists()
            for p, sha in manifest['files'].items())
        if other_local:
            continue
        asset = manifest['assets'][key]
        suffix = '.img.gz' if asset['encoding'] == 'gzip' else '.img'
        path = local_file(root, '.cache/' + asset['sha256'] + suffix)
        if path.is_file():
            cache.append(path)
    return DeletionPlan(root, tuple(files), tuple(cache), sum(p.stat().st_size for p in (*files, *cache)))


def delete_bloat(plan):
    # Revalidate every path before removing anything, including after a dialog.
    paths = [local_file(plan.root, p.relative_to(plan.root).as_posix()) for p in (*plan.files, *plan.cache)]
    for path in paths:
        path.unlink(missing_ok=True)
    for path in paths:
        parent = path.parent
        while parent != plan.root:
            try:
                parent.rmdir()
            except OSError:
                break
            parent = parent.parent
