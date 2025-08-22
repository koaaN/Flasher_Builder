#!/usr/bin/env bash
set -euo pipefail

# Usage: ./SUPER_CN_FULL_SUPERBUILD.sh /path/to/OTA.zip

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 /path/to/OTA.zip"
  exit 64
fi

input_file="$(realpath "$1")"
input_dir="$(dirname "$input_file")"

# Ordner dieses Skripts
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# otaripper (Linux)
otaripper_bin="$script_dir/otaripper"
if [[ ! -x "$otaripper_bin" ]]; then
  echo "ERROR: otaripper (Linux) nicht gefunden/ausführbar: $otaripper_bin"
  exit 1
fi

# Template-Quellen/Ziele (mit Leerzeichen!)
super_src="$script_dir/Super Flasher CN"
super_dest="$input_dir/Super Flasher CN"
super_work="$super_dest/Super"
cos_here="$super_dest/COS_FILES_HERE"
oos_here="$super_dest/OOS_FILES_HERE"

# 1) Template neben die ZIP spiegeln
mkdir -p "$super_dest"
rsync -a "$super_src/" "$super_dest/"

# 2) Ordnerliste vor der Extraktion merken
declare -A before
while IFS= read -r -d '' d; do
  before["$(basename "$d")"]=1
done < <(find "$input_dir" -mindepth 1 -maxdepth 1 -type d -print0)

# 3) otaripper im ZIP-Ordner ausführen
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

# 5) Zuerst definierte Partitionen in Super/ verschieben
mkdir -p "$super_work"
echo "Moving logical partitions into Super/ ..."
part_list=(
  my_bigball.img my_carrier.img my_engineering.img my_heytap.img
  my_manifest.img my_product.img my_region.img my_stock.img
  odm.img product.img system.img system_dlkm.img system_ext.img
  vendor.img vendor_dlkm.img
)
for f in "${part_list[@]}"; do
  [[ -f "$new_folder/$f" ]] && mv -f "$new_folder/$f" "$super_work/"
done

# 6) CN_BLOAT → Super/: my_preload.img & my_company.img
cn_bloat="$script_dir/CN_BLOAT"
for f in my_preload.img my_company.img; do
  if [[ -f "$cn_bloat/$f" ]]; then
    cp -f "$cn_bloat/$f" "$super_work/"
  else
    echo "WARN: $f nicht gefunden in $cn_bloat"
  fi
done

# 7) A5_DEBLOAT → OOS_FILES_HERE/: my_preload.img & my_company.img
mkdir -p "$oos_here"
a5_debloat="$script_dir/A5_DEBLOAT"
for f in my_preload.img my_company.img; do
  if [[ -f "$a5_debloat/$f" ]]; then
    cp -f "$a5_debloat/$f" "$oos_here/"
  else
    echo "WARN: $f nicht gefunden in $a5_debloat"
  fi
done

# 8) Restliche Dateien nach COS_FILES_HERE/
mkdir -p "$cos_here"
shopt -s dotglob
if compgen -G "$new_folder/*" >/dev/null; then
  mv -f "$new_folder"/* "$cos_here/" || true
fi
shopt -u dotglob

# 9) temporären Extraktordner löschen
rm -rf "$new_folder"

echo "Done moving files into Super Flasher CN."
echo "Packing super.img"

# 10) super.img packen (Linux-Packer erwartet)
packer="$super_work/super_cos.sh"
if [[ ! -x "$packer" ]]; then
  echo "ERROR: super_cos.sh nicht gefunden/ausführbar: $packer"
  echo "Bitte Linux-Packer im Template unter 'Super Flasher CN/Super/super_cos.sh' bereitstellen."
  exit 1
fi
( cd "$super_work" && bash "./super_cos.sh" )

# 11) super.img ins Flasher-Root verschieben
if [[ -f "$super_work/super.img" ]]; then
  mv -f "$super_work/super.img" "$super_dest/"
else
  echo "ERROR: super.img wurde nicht erzeugt."
  exit 1
fi

# 12) Arbeitsordner entfernen
rm -rf "$super_work"
