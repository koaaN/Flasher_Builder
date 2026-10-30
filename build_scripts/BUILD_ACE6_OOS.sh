#!/usr/bin/env bash
set -euo pipefail

# Ace 6 OxygenOS Frankenstein builder
# BASE_OTA_PATH: OnePlus Ace 6 ColorOS full OTA
# argument $1:   OnePlus 15R India OxygenOS full OTA

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 /path/to/TARGET_OTA.zip"
  exit 64
fi

target_ota="$(realpath "$1")"
base_ota="${BASE_OTA_PATH:-}"
[[ -n "$base_ota" && -f "$base_ota" ]] || { echo "ERROR: BASE_OTA_PATH not found"; exit 1; }
base_ota="$(realpath "$base_ota")"
input_dir="$(dirname "$target_ota")"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

otaripper="$script_dir/otaripper"
avbtool="$script_dir/avbtool.py"
template="$script_dir/SuperHybrid Flasher"
output="$input_dir/SuperHybrid Flasher"
super_dir="$output/Super"
oos_dir="$output/OOS_FILES_HERE"
work_root="$input_dir/.ace6_oos_build"

[[ -x "$otaripper" ]] || { echo "ERROR: otaripper not found: $otaripper"; exit 1; }
[[ -f "$avbtool" ]] || { echo "ERROR: avbtool.py not found: $avbtool"; exit 1; }
[[ -d "$template" ]] || { echo "ERROR: Flasher template not found: $template"; exit 1; }

rm -rf "$output" "$work_root"
mkdir -p "$output" "$work_root/BASE" "$work_root/TARGET"
rsync -a "$template/" "$output/"

extract_ota() {
  local name="$1" ota="$2" dir="$work_root/$1"
  cp -f "$ota" "$dir/$name.zip"
  if [[ "$name" == "TARGET" ]]; then
    (
      cd "$dir"
      "$otaripper" "$name.zip" --output-dir "$dir/IMAGES" --partitions \
        my_bigball,my_carrier,my_engineering,my_heytap,my_manifest,my_product,my_region,my_stock,system,system_ext,product \
        >&2
    )
  else
    ( cd "$dir" && "$otaripper" "$name.zip" --output-dir "$dir/IMAGES" >&2 )
  fi

  [[ -d "$dir/IMAGES" ]] || { echo "ERROR: No extracted images for $name" >&2; exit 1; }
  printf '%s\n' "$dir/IMAGES"
}

echo "Extracting Ace 6 BASE OTA"
base_images="$(extract_ota BASE "$base_ota")"
echo "Extracting OnePlus 15R IN TARGET OTA"
target_images="$(extract_ota TARGET "$target_ota")"

declare -A super_files=()

copy_super_image() {
  local src="$1" file="$2"
  if [[ -f "$src/$file" ]]; then
    cp -f "$src/$file" "$super_dir/$file"
    super_files["$file"]=1
    echo "  + Super/$file"
  else
    echo "  ! Missing: $file"
  fi
}

target_parts=(
  my_bigball.img my_carrier.img my_engineering.img my_heytap.img
  my_manifest.img my_product.img my_region.img my_stock.img
  system.img system_ext.img product.img
)
base_parts=(odm.img system_dlkm.img vendor.img vendor_dlkm.img)

echo "Adding TARGET partitions to super.img"
for file in "${target_parts[@]}"; do
  copy_super_image "$target_images" "$file"
done

echo "Adding BASE partitions to super.img"
for file in "${base_parts[@]}"; do
  copy_super_image "$base_images" "$file"
done

mkdir -p "$oos_dir" "$work_root/VBMETA"
for file in vbmeta.img vbmeta_system.img vbmeta_vendor.img; do
  [[ -f "$base_images/$file" ]] || { echo "ERROR: Missing BASE $file"; exit 1; }
  cp -f "$base_images/$file" "$work_root/VBMETA/$file"
done

echo "Patching BASE vbmeta images"
for name in vbmeta vbmeta_system vbmeta_vendor; do
  python3 "$avbtool" make_vbmeta_image \
    --output "$oos_dir/$name.img" \
    --include_descriptors_from_image "$work_root/VBMETA/$name.img" \
    --flags 3 \
    --rollback_index 0
done

echo "Adding remaining BASE boot and firmware images"
shopt -s nullglob
for path in "$base_images"/*.img; do
  file="$(basename "$path")"
  [[ -n "${super_files[$file]+x}" ]] && continue
  case "$file" in
    vbmeta.img|vbmeta_system.img|vbmeta_vendor.img) continue ;;
  esac
  mv -f "$path" "$oos_dir/$file"
done
shopt -u nullglob

packer="$super_dir/super_packer.sh"
[[ -x "$packer" ]] || { echo "ERROR: super_packer.sh not found: $packer"; exit 1; }

echo "Packing Ace 6 super.img"
( cd "$super_dir" && bash ./super_packer.sh )
[[ -f "$super_dir/super.img" ]] || { echo "ERROR: super.img was not created"; exit 1; }
mv -f "$super_dir/super.img" "$output/super.img"

rm -rf "$super_dir" "$work_root"
echo "BUILD DONE!!!"
