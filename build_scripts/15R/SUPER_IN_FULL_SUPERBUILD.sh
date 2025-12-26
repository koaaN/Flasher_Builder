#!/usr/bin/env bash
set -euo pipefail

# Usage: ./SUPERHYBRID_IN_FULL_SUPERBUILD.sh /path/to/OTA.zip
# SuperHybrid IN (OOS) – OnePlus 15
# Port von SUPERHYBRID_IN_FULL_SUPERBUILD.bat inkl. OOS_FILES_HERE-Cleanup

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 /path/to/OTA.zip"
  exit 64
fi

input_file="$(realpath "$1")"
input_dir="$(dirname "$input_file")"

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

otaripper_bin="$script_dir/otaripper"
if [[ ! -x "$otaripper_bin" ]]; then
  echo "ERROR: otaripper (Linux) nicht gefunden/ausführbar: $otaripper_bin"
  exit 1
fi

super_src="$script_dir/Super Flasher"
super_dest="$input_dir/Super Flasher"
super_work="$super_dest/Super"
oos_here="$super_dest/OOS_FILES_HERE"

if [[ ! -d "$super_src" ]]; then
  echo "ERROR: Template 'Super Flasher' nicht gefunden: $super_src"
  exit 1
fi

# 1) SuperHybrid-Flasher-Template neben die ZIP spiegeln
mkdir -p "$super_dest"
rsync -a "$super_src/" "$super_dest/"

# 2) Ordnerliste vor der Extraktion merken
declare -A before
while IFS= read -r -d '' d; do
  before["$(basename "$d")"]=1
done < <(find "$input_dir" -mindepth 1 -maxdepth 1 -type d -print0)

# 3) otaripper im ZIP-Ordner ausführen (kein --partitions)
pushd "$input_dir" >/dev/null
"$otaripper_bin" "$input_file"
popd >/dev/null

# 4) Neu entstandenen Ordner finden
new_folder=""
while IFS= read -r -d '' d; do
  base="$(basename "$d")"
  if [[ -z "${before[$base]+x}" ]]; then
    new_folder="$d"
    break
  fi
done < <(find "$input_dir" -mindepth 1 -maxdepth 1 -type d -print0)

[[ -n "$new_folder" ]] || { echo "ERROR: kein neuer Ordner nach Extraktion gefunden."; exit 1; }

# 5) definierte Partitionen in Super/ verschieben
mkdir -p "$super_work"
echo "Moving logical partitions into Super/ ..."
part_list=(
  my_bigball.img my_carrier.img my_engineering.img my_heytap.img
  my_manifest.img my_product.img my_region.img my_stock.img
  odm.img product.img system.img system_dlkm.img system_ext.img
  vendor.img vendor_dlkm.img
)
for f in "${part_list[@]}"; do
  if [[ -f "$new_folder/$f" ]]; then
    echo "  moving $f"
    mv -f "$new_folder/$f" "$super_work/"
  fi
done

# 6) Restliche Dateien nach OOS_FILES_HERE/
mkdir -p "$oos_here"
shopt -s dotglob
if compgen -G "$new_folder/*" >/dev/null; then
  mv -f "$new_folder"/* "$oos_here/" || true
fi
shopt -u dotglob

# 7) temporären Extraktordner löschen
rm -rf "$new_folder"

echo "Done moving files into SuperHybrid Flasher"

# 9) super.img packen (Super/super_oos.sh)
packer="$super_work/super_oos.sh"
if [[ ! -x "$packer" ]]; then
  echo "ERROR: Super packer script nicht gefunden/ausführbar: $packer"
  exit 1
fi

echo "Packing super.img ..."
( cd "$super_work" && bash "./super_oos.sh" )

# 10) super.img ins Flasher-Root verschieben
if [[ -f "$super_work/super.img" ]]; then
  echo "Moving super.img into SuperHybrid Flasher ..."
  mv -f "$super_work/super.img" "$super_dest/"
else
  echo "ERROR: super.img wurde nicht erzeugt."
  exit 1
fi

# 11) Aufräumen: Super/ + dtbo-Kram
echo "Removing scrap files"
rm -rf "$super_work"
rm -f  "$super_dest/dtbo.img"
rm -f  "$super_dest/dtbo_patched.img"
rm -f  "$super_dest/dtbo_patcher.sh" "$super_dest/dtbo_patcher.py" "$super_dest/dtbo_patcher" || true

echo "BUILD DONE!!!"
