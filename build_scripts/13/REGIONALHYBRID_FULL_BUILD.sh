#!/usr/bin/env bash
set -euo pipefail

# Usage: ./REGIONALHYBRID_FULL_BUILD.sh /path/to/OTA.zip

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 /path/to/OTA.zip"
  exit 64
fi

# Pfade
input_file="$(realpath "$1")"
input_dir="$(dirname "$input_file")"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

otaripper_bin="$script_dir/otaripper"                       # Linux-Binary im OUT_DIR
template_src="$script_dir/Regional Hybrid Flasher"          # Template-Quelle (immer von hier!)
flasher_dest="$input_dir/Regional Hybrid Flasher"           # Ziel neben der ZIP
oos_here="$flasher_dest/OOS_FILES_HERE"

# Checks
[[ -x "$otaripper_bin" ]] || { echo "ERROR: otaripper nicht gefunden/ausführbar: $otaripper_bin"; exit 1; }
[[ -d "$template_src" ]] || { echo "ERROR: Template-Ordner fehlt: $template_src"; exit 1; }

# 1) Zielordner NEU anlegen (immer frisch)
echo "Refreshing template at: $flasher_dest"
rm -rf "$flasher_dest"
mkdir -p "$flasher_dest"
rsync -a "$template_src/" "$flasher_dest/"

# 2) otaripper neben der ZIP ablegen
cp -f "$otaripper_bin" "$input_dir/otaripper"
chmod +x "$input_dir/otaripper"

# 3) Ordnerliste vor der Extraktion merken
declare -A before
while IFS= read -r -d '' d; do
  before["$(basename "$d")"]=1
done < <(find "$input_dir" -mindepth 1 -maxdepth 1 -type d -print0)

# 4) OTA extrahieren (ohne --partitions)
pushd "$input_dir" >/dev/null
"./otaripper" "$input_file"
popd >/dev/null

# 5) otaripper wieder weg
rm -f "$input_dir/otaripper"

# 6) Neu entstandenen Ordner ermitteln
new_folder=""
while IFS= read -r -d '' d; do
  base="$(basename "$d")"
  if [[ -z "${before[$base]+x}" ]]; then
    new_folder="$d"
    break
  fi
done < <(find "$input_dir" -mindepth 1 -maxdepth 1 -type d -print0)

[[ -n "$new_folder" ]] || { echo "ERROR: kein neuer Ordner nach Extraktion gefunden."; exit 1; }

# 7) Alles nach OOS_FILES_HERE verschieben
echo "Moving all extracted files into OOS_FILES_HERE..."
mkdir -p "$oos_here"
shopt -s dotglob
if compgen -G "$new_folder/*" >/dev/null; then
  mv -f "$new_folder"/* "$oos_here/" || true
fi
shopt -u dotglob
rm -rf "$new_folder"

# 8) Optional: 16DTBO ins Flasher-Root kopieren (falls vorhanden)
dtbo_src="$script_dir/16DTBO/16.0.0.1_dtbo.img"
if [[ -f "$dtbo_src" ]]; then
  echo "Copying 16.0.0.1_dtbo.img into Regional Hybrid Flasher..."
  cp -f "$dtbo_src" "$flasher_dest/"
else
  echo "NOTE: dtbo nicht gefunden (übersprungen): $dtbo_src"
fi

echo "Done moving files into Regional Hybrid Flasher."
