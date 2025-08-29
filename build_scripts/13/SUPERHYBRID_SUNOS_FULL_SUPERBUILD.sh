#!/usr/bin/env bash
set -euo pipefail

# Usage: ./SUPERHYBRID_SUNOS_FULL_SUPERBUILD.sh /path/to/OTA.zip

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 /path/to/OTA.zip"
  exit 64
fi

input_file="$(realpath "$1")"
input_dir="$(dirname "$input_file")"

# Ordner dieses Skripts (im Workflow: $OUT_DIR)
script_dir="$GITHUB_WORKSPACE/$OUT_DIR"

# Tools
otaripper_bin="$script_dir/otaripper"
if [[ ! -x "$otaripper_bin" ]]; then
  echo "ERROR: otaripper (Linux) nicht gefunden/ausführbar: $otaripper_bin"
  exit 1
fi

# Flasher-Template
flasher_source="$GITHUB_WORKSPACE/flasher_scripts/13/sunos/super"
flasher_dest="$input_dir/SuperHybrid SunOS Flasher"
fastboot_files="$flasher_dest/FASTBOOT_FILES_HERE"
super_work="$flasher_dest/Super"

# 1) Flasher-Template neben die ZIP spiegeln
mkdir -p "$flasher_dest"
rsync -a "$flasher_source/" "$flasher_dest/"

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

# 5) Definierte Partitionen in Super/ verschieben
mkdir -p "$super_work"
echo "Moving logical partitions into Super/ ..."
part_list=(
  odm.img product.img system.img system_dlkm.img system_ext.img
  vendor.img vendor_dlkm.img
)
for f in "${part_list[@]}"; do
  if [[ -f "$new_folder/$f" ]]; then
    mv -f "$new_folder/$f" "$super_work/"
  fi
done

# 6) Restliche Dateien nach FASTBOOT_FILES_HERE/
mkdir -p "$fastboot_files"
shopt -s dotglob
if compgen -G "$new_folder/*" >/dev/null; then
  mv -f "$new_folder"/* "$fastboot_files/" || true
fi
shopt -u dotglob

# 7) Temporären Extraktordner löschen
rm -rf "$new_folder"

echo "Done moving files into SuperHybrid SunOS Flasher"

# 8) super.img packen
packer="$super_work/super_sunos.sh"
if [[ ! -x "$packer" ]]; then
  echo "ERROR: super_sunos.sh nicht gefunden/ausführbar: $packer"
  echo "Erwarte Linux-Packer unter 'SuperHybrid SunOS Flasher/Super/super_sunos.sh'."
  exit 1
fi

echo "Packing super.img ..."
( cd "$super_work" && bash "./super_sunos.sh" )

# 9) super.img nach FASTBOOT_FILES_HERE verschieben
if [[ -f "$super_work/super.img" ]]; then
  echo "Moving super.img into SuperHybrid SunOS Flasher/FASTBOOT_FILES_HERE/..."
  mv -f "$super_work/super.img" "$fastboot_files/"
else
  echo "ERROR: super.img wurde nicht erzeugt."
  exit 1
fi

# 10) Aufräumen: Super/ löschen
echo "Removing scrap files"
rm -rf "$super_work"

echo "BUILD DONE!!!"
