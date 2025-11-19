#!/usr/bin/env bash
set -euo pipefail

# Super OOS Packer for OnePlus 15 (Linux-Version von super_oos.bat)

# Ordner des Scripts ermitteln
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

# Super partition total size
SUPER_SIZE=18907922432

# lpmake Pfad (Binary liegt im gleichen Ordner wie dieses Script)
LPM="$script_dir/lpmake"

if [[ ! -x "$LPM" ]]; then
  echo "ERROR: lpmake binary not found or not executable at: $LPM" >&2
  exit 1
fi

cd "$script_dir"

# Basis-Command als Array aufbauen
cmd=(
  "$LPM"
  --metadata-size 65536
  --metadata-slots 3
  --virtual-ab
  --super-name super
  --device "super:${SUPER_SIZE}"
  --group "qti_dynamic_partitions_a:${SUPER_SIZE}"
  --group "qti_dynamic_partitions_b:${SUPER_SIZE}"
)

# A-Slot Partitionen mit Images
parts_a=(my_bigball my_carrier my_company my_engineering my_heytap my_manifest my_preload my_product my_region my_stock odm product system system_dlkm system_dlkm_oki system_ext vendor vendor_dlkm)

for p in "${parts_a[@]}"; do
  file="${p}.img"
  if [[ -f "$file" ]]; then
    size=$(stat -c%s "$file")
    cmd+=( --partition "${p}_a:readonly:${size}:qti_dynamic_partitions_a" )
    cmd+=( --image     "${p}_a=${file}" )
  else
    echo "Warning: ${file} not found!"
  fi
done

# B-Slot Partitionen mit 0 Bytes
parts_b=(my_bigball my_carrier my_company my_engineering my_heytap my_manifest my_preload my_product my_region my_stock odm product system system_dlkm system_dlkm_oki system_ext vendor vendor_dlkm)

for p in "${parts_b[@]}"; do
  cmd+=( --partition "${p}_b:readonly:0:qti_dynamic_partitions_b" )
done

# Finale Optionen
output_img="$script_dir/super.img"
cmd+=( --sparse --output "$output_img" )

# Command anzeigen
echo "Running command:"
printf '%q ' "${cmd[@]}"
echo

# Ausführen
"${cmd[@]}"

echo
echo "Done. Created: $output_img"
