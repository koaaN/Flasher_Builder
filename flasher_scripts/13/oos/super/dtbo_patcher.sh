#!/usr/bin/env bash
set -euo pipefail

# Pfade relativ zum Skript (wie im .bat)
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
input="${script_dir}/dtbo.img"
output="${script_dir}/dtbo_patched.img"

# 1) dtbo.img -> dtbo_patched.img kopieren
if [[ ! -f "$input" ]]; then
  echo "ERROR: ${input} nicht gefunden."
  exit 1
fi
cp -f "$input" "$output"

# 2) Binär-String ersetzen (erstes Vorkommen)
#    sucht ASCII "oplus,hmbird" und ersetzt durch "oplus,xxbird"
python3 - << 'PY' "$output"
import sys
from pathlib import Path

out_path = Path(sys.argv[1])
data = out_path.read_bytes()

search = b'oplus,hmbird'
replace = b'oplus,xxbird'

idx = data.find(search)
if idx != -1:
    data = data[:idx] + replace + data[idx+len(search):]
    out_path.write_bytes(data)
    print("dtbo patched successfully!")
    print(f"Saved as {out_path}")
else:
    # kein Vorkommen -> Datei bleibt unverändert (wie dein PS-Skript ohne Effekt)
    print("WARN: pattern 'oplus,hmbird' nicht gefunden – keine Änderung vorgenommen.")
    print(f"Left as {out_path}")
PY
