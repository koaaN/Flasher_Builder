#!/usr/bin/env bash
# dtbo_patcher.sh
set -eu
# pipefail optional, falls Shell das Flag nicht kennt
set -o pipefail 2>/dev/null || true

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
in="$script_dir/dtbo.img"
out="$script_dir/dtbo_patched.img"

if [[ ! -f "$in" ]]; then
  echo "ERROR: $in nicht gefunden."
  exit 1
fi

# 1) Ausgang nach *_patched kopieren
cp -f "$in" "$out"

# 2) Erstes Vorkommen binär ersetzen (gleiche Länge -> sicher)
search='oplus,hmbird'
replace='oplus,xxbird'

# Byte-Offset des ersten Treffers holen (-a: binär, -b: Offset, -o: nur Match, -m1: erstes Vorkommen)
off="$(LC_ALL=C grep -abo -m1 "$search" "$out" | cut -d: -f1 || true)"

if [[ -n "${off:-}" ]]; then
  # Bytes ab Offset überschreiben (keine Größenänderung)
  printf '%s' "$replace" | dd of="$out" bs=1 seek="$off" conv=notrunc status=none
  echo "dtbo patched successfully!"
else
  echo "WARN: pattern '$search' nicht gefunden – Datei unverändert."
fi

echo "Saved as $out"
