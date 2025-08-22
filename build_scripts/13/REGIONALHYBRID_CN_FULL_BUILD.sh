#!/usr/bin/env bash
set -euo pipefail

# Usage: ./REGIONALHYBRID_CN_FULL_BUILD.sh /path/to/OTA.zip

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 /path/to/OTA.zip"
  exit 64
fi

input_file="$(realpath "$1")"
input_dir="$(dirname "$input_file")"

# Ordner dieses Skripts
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Pfade
tool="$script_dir/otaripper"
regional_flasher_src="$script_dir/RegionalHybrid Flasher CN"
regional_flasher_dest="$input_dir/RegionalHybrid Flasher CN"

# 1) Template in Zielordner kopieren
mkdir -p "$regional_flasher_dest"
rsync -a "$regional_flasher_src/" "$regional_flasher_dest/"

# 2) Liste vorhandener Ordner merken
declare -A before
while IFS= read -r -d '' d; do
  before["$(basename "$d")"]=1
done < <(find "$input_dir" -mindepth 1 -maxdepth 1 -type d -print0)

# 3) otaripper laufen lassen
pushd "$input_dir" >/dev/null
"$tool" "$input_file"
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

# 5) Dateien verschieben
cos_here="$regional_flasher_dest/COS_FILES_HERE"
mkdir -p "$cos_here"
shopt -s dotglob
mv -f "$new_folder"/* "$cos_here/" || true
shopt -u dotglob

# 6) Bloat-Dateien ins OOS_FILES_HERE kopieren
oos_here="$regional_flasher_dest/OOS_FILES_HERE"
mkdir -p "$oos_here"
euglo_bloat="$script_dir/EUGLO_BLOAT"

for f in my_preload.img my_company.img; do
  if [[ -f "$euglo_bloat/$f" ]]; then
    cp -f "$euglo_bloat/$f" "$oos_here/"
  else
    echo "WARN: $f nicht gefunden in $euglo_bloat"
  fi
done

# 7) temporären Ordner löschen
rm -rf "$new_folder"

echo "Done moving files into Regional Flasher CN."
