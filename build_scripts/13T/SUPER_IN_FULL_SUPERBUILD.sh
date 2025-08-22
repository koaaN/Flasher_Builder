#!/usr/bin/env bash
set -euo pipefail

# Usage: ./SUPER_IN_DTBO_SUPERBUILD.sh /path/to/OTA.zip

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 /path/to/OTA.zip"
  exit 64
fi

input_file="$(realpath "$1")"
input_dir="$(dirname "$input_file")"

# Skriptverzeichnis (enthält Template/BLOAT/16DTBO)
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# otaripper (Linux)
otaripper_bin="$script_dir/otaripper"
if [[ ! -x "$otaripper_bin" ]]; then
  echo "ERROR: otaripper nicht gefunden/ausführbar: $otaripper_bin"
  exit 1
fi

# Pfade
super_src="$script_dir/Super Flasher"
super_dest="$input_dir/Super Flasher"
super_work="$super_dest/Super"
oos_here="$super_dest/OOS_FILES_HERE"

# 1) Template kopieren
mkdir -p "$super_dest"
rsync -a "$super_src/" "$super_dest/"

# 2) Ordner vor Extraktion merken
declare -A before
while IFS= read -r -d '' d; do
  before["$(basename "$d")"]=1
done < <(find "$input_dir" -mindepth 1 -maxdepth 1 -type d -print0)

# 3) otaripper ausführen
pushd "$input_dir" >/dev/null
"$otaripper_bin" "$input_file"
popd >/dev/null

# 4) Neuen Ordner finden
new_folder=""
while IFS= read -r -d '' d; do
  base="$(basename "$d")"
  if [[ -z "${before[$base]+x}" ]]; then
    new_folder="$d"
    break
  fi
done < <(find "$input_dir" -mindepth 1 -maxdepth 1 -type d -print0)

[[ -n "$new_folder" ]] || { echo "ERROR: kein neuer Ordner nach Extraktion."; exit 1; }

# 5) Partitionen in Super/
mkdir -p "$super_work"
part_list=(
  my_bigball.img my_carrier.img my_engineering.img my_heytap.img
  my_manifest.img my_product.img my_region.img my_stock.img
  odm.img product.img system.img system_dlkm.img system_ext.img
  vendor.img vendor_dlkm.img
)
for f in "${part_list[@]}"; do
  [[ -f "$new_folder/$f" ]] && mv -f "$new_folder/$f" "$super_work/"
done

# 6) IN_BLOAT → Super/
in_bloat="$script_dir/IN_BLOAT"
for f in my_preload.img my_company.img; do
  if [[ -f "$in_bloat/$f" ]]; then
    cp -f "$in_bloat/$f" "$super_work/"
  else
    echo "WARN: $f fehlt in $in_bloat"
  fi
done

# 7) Rest nach OOS_FILES_HERE/
mkdir -p "$oos_here"
shopt -s dotglob
if compgen -G "$new_folder/*" >/dev/null; then
  mv -f "$new_folder"/* "$oos_here/" || true
fi
shopt -u dotglob

rm -rf "$new_folder"
echo "Done moving files into Super Flasher."

# 8) 16DTBO/dtbo.img → OOS_FILES_HERE
dtbo_src="$script_dir/16DTBO/dtbo.img"
if [[ -f "$dtbo_src" ]]; then
  cp -f "$dtbo_src" "$oos_here/"
  echo "16.0.0.1 dtbo.img copied into OOS_FILES_HERE."
else
  echo "WARN: dtbo.img nicht gefunden in $dtbo_src"
fi

# 9) super.img packen
packer="$super_work/super_oos.sh"
if [[ ! -x "$packer" ]]; then
  echo "ERROR: super_oos.sh nicht gefunden/ausführbar im Template"
  exit 1
fi
( cd "$super_work" && bash "./super_oos.sh" )

# 10) super.img verschieben
if [[ -f "$super_work/super.img" ]]; then
  mv -f "$super_work/super.img" "$super_dest/"
  echo "super.img moved into Super Flasher."
else
  echo "ERROR: super.img wurde nicht erzeugt."
  exit 1
fi

# 11) Arbeitsordner löschen
rm -rf "$super_work"
echo "BUILD DONE!!!"
