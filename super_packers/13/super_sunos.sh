#!/usr/bin/env bash
set -euo pipefail

# Optional per Env übersteuerbar
SUPER_SIZE="${SUPER_SIZE:-13329498112}"

# In Skriptordner wechseln (wie pushd "%~dp0")
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir"

# lpmake suchen: lokale Kopie bevorzugt, sonst PATH
LPM="$script_dir/lpmake"
if [[ ! -x "$LPM" ]]; then
  if command -v lpmake >/dev/null 2>&1; then
    LPM="$(command -v lpmake)"
  else
    echo "ERROR: lpmake nicht gefunden. Lege eine Linux-Binary als '$script_dir/lpmake' ab oder installiere lpmake im PATH." >&2
    exit 1
  fi
fi

# Basis-Args
args=(
  --metadata-size 65536
  --metadata-slots 3
  --virtual-ab
  --super-name super
  --device "super:${SUPER_SIZE}"
  --group "qti_dynamic_partitions_a:${SUPER_SIZE}"
  --group "qti_dynamic_partitions_b:${SUPER_SIZE}"
)

# A-Slot-Partitionen mit Image-Dateien
parts_a=(odm product system system_dlkm system_ext vendor vendor_dlkm)
for p in "${parts_a[@]}"; do
  f="${p}.img"
  if [[ -f "$f" ]]; then
    size="$(stat -c%s "$f")"
    args+=( --partition "${p}_a:readonly:${size}:qti_dynamic_partitions_a" --image "${p}_a=${f}" )
  else
    echo "Warning: ${f} not found!" >&2
  fi
done

# B-Slot-Partitionen (0-Byte)
parts_b=(odm product system system_dlkm system_ext vendor vendor_dlkm)
for p in "${parts_b[@]}"; do
  args+=( --partition "${p}_b:readonly:0:qti_dynamic_partitions_b" )
done

# Ausgabe
args+=( --sparse --output "${PWD}/super.img" )

echo "Running command:"
printf '%q ' "$LPM" "${args[@]}"; echo
"$LPM" "${args[@]}"

echo "Done. Wrote super.img to: ${PWD}/super.img"
