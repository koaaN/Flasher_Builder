#!/usr/bin/env bash
set -euo pipefail

# Usage: ./REGIONALHYBRID_FULL_BUILD.sh /path/to/OTA.zip
# Port der BAT:
# - kopiert "Regional Hybrid Flasher" neben die ZIP
# - extrahiert mit otaripper (Linux)
# - verschiebt alles nach OOS_FILES_HERE
# - kopiert 16DTBO/16.0.0.1_dtbo.img ins Flasher-Root
# - keine Pausen

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 /path/to/OTA.zip"
  exit 64
fi

input_file="$(realpath "$1")"
input_dir="$(dirname "$input_file")"

# Ordner dieses Skripts
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Tools/Basis
tool="$script_dir/otaripper"   # passe an, falls bei dir anders
if [[ ! -x "$tool" ]]; then
  echo "ERROR: otaripper (Linux) nicht gefunden oder nicht ausführbar: $tool"
  exit 1
fi

# Flasher-Template (mit Leerzeichen im Namen)
regional_flasher_src="$script_dir/Regional Hybrid Flasher"
regional_flasher_dest="$input_dir/Regional Hybrid Flasher"

# 1) Template zum ZIP-Ort spiegeln
mkdir -p "$regional_flasher_dest"
rsync -a "$regional_flasher_src/" "$regional_flasher_dest/"

# 2) Ordnerliste vor der Extraktion merken
declare -A before
while IFS= read -r -d '' d; do
  before["$(basename "$d")"]=1
done < <(find "$input_dir" -mindepth 1 -maxdepth 1 -type d -print0)

# 3) otaripper im ZIP-Ordner ausführen (wie Drag&Drop)
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

# 5) Alles in OOS_FILES_HERE verschieben
oos_here="$regional_flasher_dest/OOS_FILES_HERE"
mkdir -p "$oos_here"
shopt -s dotglob
mv -f "$new_folder"/* "$oos_here/" || true
shopt -u dotglob

# 6) Temporären Extraktordner löschen
rm -rf "$new_folder"

# 7) 16DTBO/16.0.0.1_dtbo.img ins Flasher-Root kopieren (falls vorhanden)
dtbo_src="$script_dir/16DTBO/16.0.0.1_dtbo.img"
if [[ -f "$dtbo_src" ]]; then
  cp -f "$dtbo_src" "$regional_flasher_dest/"
  echo "Copied $(basename "$dtbo_src") to Regional Hybrid Flasher."
else
  echo "WARN: DTBO nicht gefunden: $dtbo_src"
fi

echo "Done moving files into Regional Hybrid Flasher."
