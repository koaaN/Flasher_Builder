#!/usr/bin/env bash
set -euo pipefail

# Usage: ./REGIONAL_IN_FULL_BUILD.sh /path/to/OTA.zip

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 /path/to/OTA.zip"
  exit 64
fi

input_file="$(realpath "$1")"
input_dir="$(dirname "$input_file")"

# Ordner dieses Skripts (enthält Template/Bloat/16DTBO)
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# otaripper (Linux)
otaripper_bin="$script_dir/../../otaripper/otaripper"
if [[ ! -x "$otaripper_bin" ]]; then
  echo "ERROR: otaripper (Linux) nicht gefunden/ausführbar: $otaripper_bin"
  exit 1
fi

# Template-Quellen/Ziele (mit Leerzeichen!)
regional_flasher_src="$script_dir/Regional Flasher"
regional_flasher_dest="$input_dir/Regional Flasher"

# 1) Template neben die ZIP spiegeln
mkdir -p "$regional_flasher_dest"
rsync -a "$regional_flasher_src/" "$regional_flasher_dest/"

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

# 5) Alle extrahierten Dateien in OOS_FILES_HERE verschieben
oos_here="$regional_flasher_dest/OOS_FILES_HERE"
mkdir -p "$oos_here"
shopt -s dotglob
if compgen -G "$new_folder/*" >/dev/null; then
  mv -f "$new_folder"/* "$oos_here/" || true
fi
shopt -u dotglob

# 6) IN_BLOAT -> OOS_FILES_HERE: my_preload.img & my_company.img
in_bloat="$script_dir/IN_BLOAT"
for f in my_preload.img my_company.img; do
  if [[ -f "$in_bloat/$f" ]]; then
    cp -f "$in_bloat/$f" "$oos_here/"
  else
    echo "WARN: $f nicht gefunden in $in_bloat"
  fi
done

# 7) temporären Extraktordner löschen
rm -rf "$new_folder"

echo "Done moving files into Regional Flasher."
echo "Copying 16.0.0.1_dtbo.img into Regional Flasher..."

# 8) 16.0.0.1_dtbo.img ins Flasher-Root kopieren
dtbo_src="$script_dir/16DTBO/16.0.0.1_dtbo.img"
if [[ -f "$dtbo_src" ]]; then
  cp -f "$dtbo_src" "$regional_flasher_dest/"
else
  echo "WARN: 16DTBO image nicht gefunden: $dtbo_src"
fi
