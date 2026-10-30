#!/usr/bin/env python3
"""Launch the Flasher Builder desktop application."""
import sys

if __name__ == '__main__':
    try:
        from flasher_builder.gui import main
    except ImportError as exc:
        print(f'GUI could not load: {exc}\nInstall the GUI engine with: python -m pip install -r requirements.txt', file=sys.stderr)
        sys.exit(1)
    sys.exit(main())
