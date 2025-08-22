#!/usr/bin/env bash
set -euo pipefail

# Usage: ./REGIONAL_CN_FULL_BUILD.sh /path/to/OTA.zip

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 /path/to/OTA.zip"
  exit 64
fi

input_file="$(realpath "$1")"
input_dir="$(dirname "$input_file")"

# Verzeichnis dieses Skripts (enthält Template)
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# otaripper (Linux)
otaripper_bin="$script_dir/otaripper"
if [[ ! -x "$otaripper_bin" ]]; then
  echo "ERROR: otaripper (Linux) nicht gefunden/ausführbar: $otaripper_bin"
  exit 1
fi

# Template-Quellen/Ziele (mit Leerzeichen!)
regional_flasher_src="$script_dir/Regional Flasher CN"
regional_flasher_dest="$input_dir/Regional Flasher CN"

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

# 5) Alle extrahierten Dateien in COS_FILES_HERE verschieben
cos_here="$regional_flasher_dest/COS_FILES_HERE"
mkdir -p "$cos_here"
shopt -s dotglob
if compgen -G "$new_folder/*" >/dev/null; then
  mv -f "$new_folder"/* "$cos_here/" || true
fi
shopt -u dotglob

# 6) temporären Extraktordner löschen
rm -rf "$new_folder"

echo "Done moving files into Regional Flasher CN."
