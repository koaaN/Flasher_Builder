#!/usr/bin/env bash
set -euo pipefail

# Usage: ./REGIONAL_CN_FULL_BUILD.sh /path/to/OTA.zip

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 /path/to/OTA.zip"
  exit 64
fi

input_file="$(realpath "$1")"
input_dir="$(dirname "$input_file")"

# Ordner dieses Skripts (enthält Templates/Bloat)
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Tools & Quellen/Ziele
otaripper_bin="$script_dir/../../otaripper/otaripper"
if [[ ! -x "$otaripper_bin" ]]; then
  echo "ERROR: otaripper (Linux) nicht gefunden/ausführbar: $otaripper_bin"
  exit 1
fi

regional_flasher_src="$script_dir/Regional Flasher CN"
regional_flasher_dest="$input_dir/Regional Flasher CN"

# 1) Template zum ZIP-Ort kopieren
mkdir -p "$regional_flasher_dest"
rsync -a "$regional_flasher_src/" "$regional_flasher_dest/"

# 2) Ordnerliste vor der Extraktion merken
declare -A before
while IFS= read -r -d '' d; do
  before["$(basename "$d")"]=1
done < <(find "$input_dir" -mindepth 1 -maxdepth 1 -type d -print0)

# 3) otaripper im Zielordner ausführen
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

# 5) Alle extrahierten Dateien nach COS_FILES_HERE verschieben
cos_here="$regional_flasher_dest/COS_FILES_HERE"
mkdir -p "$cos_here"
shopt -s dotglob
if compgen -G "$new_folder/*" >/dev/null; then
  mv -f "$new_folder"/* "$cos_here/" || true
fi
shopt -u dotglob

# 6) A5_DEBLOAT -> OOS_FILES_HERE: my_preload.img & my_company.img
oos_here="$regional_flasher_dest/OOS_FILES_HERE"
mkdir -p "$oos_here"
a5_debloat="$script_dir/A5_DEBLOAT"
for f in my_preload.img my_company.img; do
  if [[ -f "$a5_debloat/$f" ]]; then
    cp -f "$a5_debloat/$f" "$oos_here/"
  else
    echo "WARN: $f nicht gefunden in $a5_debloat"
  fi
done

# 7) CN_BLOAT -> COS_FILES_HERE: my_preload.img & my_company.img
cn_bloat="$script_dir/CN_BLOAT"
for f in my_preload.img my_company.img; do
  if [[ -f "$cn_bloat/$f" ]]; then
    cp -f "$cn_bloat/$f" "$cos_here/"
  else
    echo "WARN: $f nicht gefunden in $cn_bloat"
  fi
done

# 8) temporären Extraktordner löschen
rm -rf "$new_folder"

echo "Done moving files into Regional Flasher CN."
