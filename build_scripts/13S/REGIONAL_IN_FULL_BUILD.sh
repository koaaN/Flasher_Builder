#!/usr/bin/env bash
set -euo pipefail

# Usage: ./REGIONAL_FULL_BUILD.sh /path/to/OTA.zip
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 /path/to/OTA.zip"
  exit 64
fi

# Eingaben/Orte
input_file="$(realpath "$1")"
input_dir="$(dirname "$input_file")"

# Ordner dieses Skripts
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Tools & Zielordner
otaripper_bin="$script_dir/otaripper"         # Linux-Binary erwartet
otaripper_name="otaripper"                     # Name nach dem Kopieren
regional_src="$script_dir/Regional Flasher"    # Template-Ordner
regional_dest="$input_dir/Regional Flasher"    # Ziel neben der ZIP

# Prüfen, ob otaripper vorhanden/ausführbar
if [[ ! -x "$otaripper_bin" ]]; then
  echo "ERROR: otaripper (Linux) nicht gefunden/ausführbar: $otaripper_bin"
  exit 1
fi

# Regional Flasher-Template zum ZIP-Ort spiegeln
mkdir -p "$regional_dest"
rsync -a "$regional_src/" "$regional_dest/"

# otaripper neben die ZIP kopieren (wie im BAT)
cp -f "$otaripper_bin" "$input_dir/$otaripper_name"
chmod +x "$input_dir/$otaripper_name"

# Ordnerliste vor der Extraktion merken
declare -A before
while IFS= read -r -d '' d; do
  before["$(basename "$d")"]=1
done < <(find "$input_dir" -mindepth 1 -maxdepth 1 -type d -print0)

# otaripper im ZIP-Ordner ausführen (ohne --partitions)
pushd "$input_dir" >/dev/null
"./$otaripper_name" "$input_file"
popd >/dev/null

# temporären otaripper löschen
rm -f "$input_dir/$otaripper_name"

# Neu entstandenen Ordner finden
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

# Alle extrahierten Dateien nach OOS_FILES_HERE verschieben
echo "Moving all extracted files into OOS_FILES_HERE..."
oos_here="$regional_dest/OOS_FILES_HERE"
mkdir -p "$oos_here"

shopt -s dotglob
if compgen -G "$new_folder/*" >/dev/null; then
  mv -f "$new_folder"/* "$oos_here/" || true
fi
shopt -u dotglob

# Extrakt-Ordner entfernen
rm -rf "$new_folder"

echo "Done moving files into Regional Flasher."
