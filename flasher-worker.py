#!/usr/bin/env python3
"""Console worker bundled beside the GUI; no system Python or shell is needed."""
import os
import signal
import sys
from flasher_builder.backend import ROOT, main
from flasher_builder.host import configure_path

if __name__ == '__main__':
    configure_path(ROOT)
    if sys.stdout is not None and hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8', errors='replace', line_buffering=True)
        sys.stderr.reconfigure(encoding='utf-8', errors='replace', line_buffering=True)
    if sys.argv[1:2] == ['--helper']:
        helper, arguments = sys.argv[2], sys.argv[3:]
        if helper == 'materialize':
            from scripts import materialize_bloat
            def interrupted(signum, frame):
                raise InterruptedError('Bloat download cancelled')
            signal.signal(signal.SIGTERM, interrupted)
            sys.argv = ['materialize_bloat'] + arguments
            sys.exit(materialize_bloat.main())
        elif helper == 'avbtool':
            from build_tools_assets import avbtool
            avbtool.AvbTool().run(['avbtool'] + arguments)
        else:
            raise SystemExit('Unknown worker helper')
    else:
        sys.exit(main())
