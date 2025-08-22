#!/usr/bin/env bash
set -euo pipefail

# Usage: ./REGIONALHYBRID_FULL_BUILD.sh /path/to/OTA.zip
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 /path/to/OTA.zip"
  exit 64
fi

# Eingaben/Orte
input_file="$(realpath "$1")"
input_dir="$(dirname "$input_file")"

# Ordner dieses Skripts
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Tools & Templates
otaripper_bin="$script_dir/otaripper"                # Linux-Binary erwartet
otaripper_name="otaripper"                           # so wird sie neben der ZIP platziert
hybrid_src="$script_dir/Regional Hybrid Flasher"     # Template-Ordner im Repo
hybrid_dest="$input_dir/Regional Hybrid Flasher"     # Zielordner neben der ZIP
oos_here="$hybrid_dest/OOS_FILES_HERE"

# Checks
[[ -x "$otaripper_bin" ]] || { echo "ERROR: otaripper nicht gefunden/ausführbar: $otaripper_bin"; exit 1; }
[[ -d "$hybrid_src" ]]     || { echo "ERROR: Template-Ordner fehlt: $hybrid_src"; exit 1; }

# 1) Template spiegeln
mkdir -p "$hybrid_dest"
rsync -a "$hybrid_src/" "$hybrid_dest/"

# 2) otaripper neben die ZIP legen (wie im BAT)
cp -f "$otaripper_bin" "$input_dir/$otaripper_name"
chmod +x "$input_dir/$otaripper_name"

# 3) Ordnerliste vor der Extraktion merken
declare -A before
while IFS= read -r -d '' d; do
  before["$(basename "$d")"]=1
done < <(find "$input_dir" -mindepth 1 -maxdepth 1 -type d -print0)

# 4) otaripper ausführen (ohne --partitions)
pushd "$input_dir" >/dev/null
"./$otaripper_name" "$input_file"
popd >/dev/null

# 5) otaripper wieder löschen
rm -f "$input_dir/$otaripper_name"

# 6) neu entstandenen Ordner finden
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

# 8) 16DTBO dtbo ins Flasher-Ziel kopieren (optional)
dtbo_src="$script_dir/16DTBO/16.0.0.1_dtbo.img"
if [[ -f "$dtbo_src" ]]; then
  echo "Copying 16.0.0.1_dtbo.img into Regional Hybrid Flasher..."
  cp -f "$dtbo_src" "$hybrid_dest/"
else
  echo "NOTE: dtbo nicht gefunden: $dtbo_src (überspringe)."
fi

echo "Done moving files into Regional Hybrid Flasher."
