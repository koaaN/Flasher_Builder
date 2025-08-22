#!/usr/bin/env bash
set -euo pipefail

# Usage: ./SUPERHYBRID_CN_FULL_SUPERBUILD.sh /path/to/OTA.zip
# Steps:
# 1) Spiegel "SuperHybrid Flasher CN" neben die ZIP
# 2) Extrahiere mit otaripper (Linux)
# 3) Verschiebe logische Partitionen in Super/
# 4) Restliche Files nach COS_FILES_HERE/
# 5) Packe super.img via Super/super_cos.sh
# 6) Lege super.img ins Flasher-Root & räume auf

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 /path/to/OTA.zip"
  exit 64
fi

input_file="$(realpath "$1")"
input_dir="$(dirname "$input_file")"

# Ordner dieses Skripts
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Tools/Quellen/Ziele
otaripper_bin="$script_dir/otaripper"  # passe an, falls dein Pfad anders ist
if [[ ! -x "$otaripper_bin" ]]; then
  echo "ERROR: otaripper (Linux) nicht gefunden oder nicht ausführbar: $otaripper_bin"
  exit 1
fi

super_src="$script_dir/SuperHybrid Flasher CN"
super_dest="$input_dir/SuperHybrid Flasher CN"
super_work="$super_dest/Super"               # Arbeitsordner (Groß-/Kleinschreibung vereinheitlicht)
cos_here="$super_dest/COS_FILES_HERE"        # Restablage

# 1) Template rüberkopieren
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

# 5) Partitionen in Super/ verschieben
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
    mv -f "$new_folder/$f" "$super_work/"
  fi
done

# 6) Rest nach COS_FILES_HERE/
mkdir -p "$cos_here"
shopt -s dotglob
if compgen -G "$new_folder/*" >/dev/null; then
  mv -f "$new_folder"/* "$cos_here/" || true
fi
shopt -u dotglob

# 7) temporären Extraktordner löschen
rm -rf "$new_folder"

# 8) super.img packen (Super/super_cos.sh muss im Template liegen)
packer="$super_work/super_cos.sh"
if [[ ! -x "$packer" ]]; then
  echo "ERROR: Super packer script nicht gefunden/ausführbar: $packer"
  echo "Erwarte es im Template unter 'SuperHybrid Flasher CN/Super/super_cos.sh'."
  exit 1
fi

echo "Packing super.img ..."
pushd "$super_work" >/dev/null
bash "$packer"
popd >/dev/null

# 9) super.img ins Flasher-Root verschieben
if [[ -f "$super_work/super.img" ]]; then
  echo "Moving super.img into SuperHybrid Flasher CN/ ..."
  mv -f "$super_work/super.img" "$super_dest/"
else
  echo "ERROR: super.img wurde nicht erzeugt."
  exit 1
fi

# 10) Arbeitsordner entfernen
echo "Removing Super/ work directory ..."
rm -rf "$super_work"

echo "BUILD DONE!!! (SuperHybrid Flasher CN)"
