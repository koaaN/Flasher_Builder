#!/usr/bin/env bash
set -euo pipefail

# Usage: ./Super_CN_FULL_SUPERBUILD.sh /path/to/OTA.zip
# Linux-Port des OnePlus-15-CN-Buildscripts (Super_CN_FULL_SUPERBUILD.bat)

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 /path/to/OTA.zip"
  exit 64
fi

input_file="$(realpath "$1")"
input_dir="$(dirname "$input_file")"

# Ordner dieses Skripts
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# Build_Tools Root (eine Ebene über build_scripts)
root_dir="$(cd "$script_dir/.." && pwd)"

echo "Script dir : $script_dir"
echo "Root dir   : $root_dir"
echo "Input dir  : $input_dir"
echo "Input file : $input_file"

# Tools
otaripper_bin="$root_dir/otaripper/otaripper"
if [[ ! -x "$otaripper_bin" ]]; then
  echo "ERROR: otaripper (Linux) nicht gefunden/ausführbar: $otaripper_bin"
  exit 1
fi

packer_src="$root_dir/super_packers/Ace6/super_cos.sh"
if [[ ! -f "$packer_src" ]]; then
  echo "ERROR: Packer super_cos.sh nicht gefunden: $packer_src"
  exit 1
fi

lpmake_src="$root_dir/lpmake/lpmake"
if [[ ! -x "$lpmake_src" ]]; then
  echo "ERROR: lpmake nicht gefunden/ausführbar: $lpmake_src"
  exit 1
fi

# Flasher-Template & Ziel
super_src="$script_dir/Super Flasher CN"
super_dest="$input_dir/Super Flasher CN"
super_work="$super_dest/Super"
cos_here="$super_dest/COS_FILES_HERE"
oos_here="$super_dest/OOS_FILES_HERE"

if [[ ! -d "$super_src" ]]; then
  echo "ERROR: Template-Ordner 'Super Flasher CN' nicht gefunden: $super_src"
  exit 1
fi

# CN/EU-GLO-Bloat
cn_bloat="$script_dir/CN_BLOAT"
euglo_bloat="$script_dir/CN_BLOAT/OOS_FILES_HERE"

if [[ ! -d "$cn_bloat" ]]; then
  echo "WARN: CN_BLOAT nicht gefunden: $cn_bloat"
fi
if [[ ! -d "$euglo_bloat" ]]; then
  echo "WARN: EUGLO_BLOAT nicht gefunden: $euglo_bloat"
fi

# 1) Super Flasher CN-Template neben die ZIP spiegeln
echo "Copying Super Flasher CN template to build folder..."
rm -rf "$super_dest"
mkdir -p "$super_dest"
rsync -a "$super_src/" "$super_dest/"

# 2) Ordnerliste vor der Extraktion merken
declare -A before
while IFS= read -r -d '' d; do
  before["$(basename "$d")"]=1
done < <(find "$input_dir" -mindepth 1 -maxdepth 1 -type d -print0)

# 3) otaripper im ZIP-Ordner ausführen (kein --partitions)
echo "Running otaripper ..."
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

if [[ -z "$new_folder" ]]; then
  echo "ERROR: kein neuer Ordner nach Extraktion gefunden."
  exit 1
fi

echo "New extracted folder: $new_folder"

# 5) definierte Partitionen in Super/ verschieben (wie im .bat)
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
  else
    echo "  Warning: $f not found in extracted folder."
  fi
done

# 6) Bloat aus CN_BLOAT nach Super/
echo "Copying my_preload.img, my_company.img and system_dlkm_oki.img system_dlkm_gki.img from CN_BLOAT into Super/ ..."
if [[ -d "$cn_bloat" ]]; then
  for f in my_preload.img my_company.img system_dlkm_oki.img system_dlkm_gki.img; do
    if [[ -f "$cn_bloat/$f" ]]; then
      cp -f "$cn_bloat/$f" "$super_work/"
    else
      echo "  Warning: $f not found in CN_BLOAT."
    fi
  done
fi

# 7) Bloat aus Bloat/OOS_FILES_HERE nach OOS_FILES_HERE/
echo "Copying my_preload.img Bloat/OOS_FILES_HERE into OOS_FILES_HERE/ ..."
mkdir -p "$oos_here"
if [[ -d "$euglo_bloat" ]]; then
  for f in my_preload.img my_company.img; do
    if [[ -f "$euglo_bloat/$f" ]]; then
      cp -f "$euglo_bloat/$f" "$oos_here/"
    else
      echo "  Warning: $f not found in EUGLO_BLOAT."
    fi
  done
fi

# 8) Restliche Dateien nach COS_FILES_HERE/
echo "Moving remaining extracted files into COS_FILES_HERE/ ..."
mkdir -p "$cos_here"
shopt -s dotglob
if compgen -G "$new_folder/*" >/dev/null; then
  mv -f "$new_folder"/* "$cos_here/" || true
fi
shopt -u dotglob

# 9) temporären Extraktordner löschen
rm -rf "$new_folder"
echo "Done moving files into Super Flasher CN."

# 🔟 super.img packen mit super_cos.sh aus super_packers/15
echo "Preparing COS super packer ..."
# Packer + lpmake ins Super-Arbeitsverzeichnis legen, damit super_cos.sh LPM="$script_dir/lpmake" benutzen kann
cp -f "$packer_src" "$super_work/super_cos.sh"
chmod +x "$super_work/super_cos.sh"

cp -f "$lpmake_src" "$super_work/lpmake"
chmod +x "$super_work/lpmake"

echo "Packing super.img ..."
(
  cd "$super_work"
  ./super_cos.sh
)

# 11) super.img ins Flasher-Root verschieben
if [[ -f "$super_work/super.img" ]]; then
  echo "Moving super.img into Super Flasher CN ..."
  mv -f "$super_work/super.img" "$super_dest/"
else
  echo "ERROR: super.img wurde nicht erzeugt."
  exit 1
fi

# 12) Aufräumen: Super/ löschen (wie im .bat)
echo "Removing Super/ workspace ..."
rm -rf "$super_work"

echo "BUILD DONE!!!"
echo "Final CN Super flasher folder:"

echo "  $super_dest"


