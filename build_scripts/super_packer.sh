#!/usr/bin/env bash
set -euo pipefail

# Super Packer for OnePlus Phones

# Ordner des Scripts ermitteln
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# lpmake Pfad (Binary liegt im gleichen Ordner wie dieses Script)
LPM="$script_dir/lpmake"

if [[ ! -x "$LPM" ]]; then
  echo "ERROR: lpmake binary not found or not executable at: $LPM" >&2
  exit 1
fi

cd "$script_dir"

# The physical super partition is 4 MiB larger than each QTI dynamic
# partition group. SUPER_SIZE is the physical device size from the
# device's super metadata; keep the group size separate.
group_size_diff=$((4 * 1024 * 1024))
group_size=$((SUPER_SIZE - group_size_diff))
(( group_size > 0 )) || { echo "ERROR: Invalid SUPER_SIZE=${SUPER_SIZE}" >&2; exit 1; }

# Return the expanded size for Android sparse images and the file size
# otherwise. lpmake needs the logical partition's expanded size.
image_size() {
  local file="$1"
  local magic block_size total_blocks

  magic=$(od -An -tx4 -N4 "$file" | tr -d '[:space:]')
  if [[ "$magic" == "ed26ff3a" ]]; then
    read -r block_size total_blocks < <(od -An -tu4 -j12 -N8 "$file")
    printf '%s\n' "$((block_size * total_blocks))"
  else
    stat -c%s "$file"
  fi
}

# Reject incomplete extraction before creating a misleading super image.
for required in system.img vendor.img product.img; do
  [[ -s "$required" ]] || { echo "ERROR: Required partition missing: $required" >&2; exit 1; }
done

# Basis-Command als Array aufbauen
cmd=(
  "$LPM"
  --metadata-size 65536
  --metadata-slots 3
  --virtual-ab
  --super-name super
  --device "super:${SUPER_SIZE}"
  --group "qti_dynamic_partitions_a:${group_size}"
  --group "qti_dynamic_partitions_b:${group_size}"
)

# A-Slot Partitions with Images
parts_a=(my_bigball my_carrier my_company my_engineering my_heytap my_manifest my_preload my_product my_region my_stock odm product system system_dlkm system_dlkm_gki system_dlkm_oki system_ext vendor vendor_dlkm)
added_parts=()

for p in "${parts_a[@]}"; do
  file="${p}.img"
  if [[ -f "$file" ]]; then
    size=$(image_size "$file")
    cmd+=( --partition "${p}_a:readonly:${size}:qti_dynamic_partitions_a" )
    cmd+=( --image     "${p}_a=${file}" )
    added_parts+=( "$p" )
  else
    if [[ "$p" != "system_dlkm_gki" && "$p" != "system_dlkm_oki" ]]; then
      echo "Warning: ${file} not found!"
    fi
  fi
done

# B-Slot Partitions with 0 Bytes
for p in "${added_parts[@]}"; do
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
