"""Native platform tools and the bundled console worker entry point."""
from pathlib import Path
import os
import sys


def tool(root, name):
    return Path(root) / name / (name + ('.exe' if sys.platform == 'win32' else ''))


def worker_command(root):
    if getattr(sys, 'frozen', False):
        # The GUI has no stdout on Windows; the separate console worker does.
        return [str(Path(root) / ('FlasherBuilderWorker.exe' if sys.platform == 'win32' else 'FlasherBuilderWorker'))]
    return [sys.executable, '-u', str(Path(__file__).resolve().parent.parent / 'flasher-worker.py')]


def helper_command(root, helper, *args):
    return worker_command(root) + ['--helper', helper] + [str(a) for a in args]


def configure_path(root):
    directory = Path(root) / 'tools/github'
    if directory.is_dir():
        os.environ['PATH'] = str(directory.resolve()) + os.pathsep + os.environ.get('PATH', '')
