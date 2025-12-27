#!/usr/bin/env bash
set -euo pipefail

# Usage: ./SUPER_IN_DTBO_SUPERBUILD.sh /path/to/OTA.zip

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 /path/to/OTA.zip"
  exit 64
fi

input_file="$(realpath "$1")"
input_dir="$(dirname "$input_file")"

# Skriptverzeichnis (enthält Template)
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# otaripper (Linux)
otaripper_bin="$script_dir/otaripper"
if [[ ! -x "$otaripper_bin" ]]; then
  echo "ERROR: otaripper nicht gefunden/ausführbar: $otaripper_bin"
  exit 1
fi

# Pfade
super_src="$script_dir/Super Flasher"
super_dest="$input_dir/Super Flasher"
super_work="$super_dest/Super"
oos_here="$super_dest/OOS_FILES_HERE"

# 1) Template kopieren
mkdir -p "$super_dest"
rsync -a "$super_src/" "$super_dest/"

# 2) Ordner vor Extraktion merken
declare -A before
while IFS= read -r -d '' d; do
  before["$(basename "$d")"]=1
done < <(find "$input_dir" -mindepth 1 -maxdepth 1 -type d -print0)

# 3) otaripper ausführen
pushd "$input_dir" >/dev/null
"$otaripper_bin" "$input_file"
popd >/dev/null

# 4) Neuen Ordner finden
new_folder=""
while IFS= read -r -d '' d; do
  base="$(basename "$d")"
  if [[ -z "${before[$base]+x}" ]]; then
    new_folder="$d"
    break
  fi
done < <(find "$input_dir" -mindepth 1 -maxdepth 1 -type d -print0)

[[ -n "$new_folder" ]] || { echo "ERROR: kein neuer Ordner nach Extraktion."; exit 1; }

# 5) Partitionen in Super/
mkdir -p "$super_work"
part_list=(
  my_bigball.img my_carrier.img my_engineering.img my_heytap.img
  my_manifest.img my_product.img my_region.img my_stock.img product.img system.img system_dlkm.img system_ext.img
  vendor.img vendor_dlkm.img
)
for f in "${part_list[@]}"; do
  [[ -f "$new_folder/$f" ]] && mv -f "$new_folder/$f" "$super_work/"
done

# 6) (entfällt) IN_BLOAT -> Super/  (wie in der .bat: keine zusätzlichen Bloat-Images)

# 7) odm.img in OOS_FILES_HERE löschen (falls vorhanden)
if [[ -f "$oos_here/odm.img" ]]; then
  rm -f "$oos_here/odm.img"
fi

# 7) Rest nach OOS_FILES_HERE/
mkdir -p "$oos_here"
shopt -s dotglob
if compgen -G "$new_folder/*" >/dev/null; then
  mv -f "$new_folder"/* "$oos_here/" || true
fi
shopt -u dotglob
rm -rf "$new_folder"
echo "Done moving files into Super Flasher."

# 8) (entfällt) 16DTBO/dtbo.img -> OOS_FILES_HERE  (wie in der .bat: kein zusätzliches dtbo.img)

# 9) super.img packen
packer="$super_work/super_oos.sh"
if [[ ! -x "$packer" ]]; then
  echo "ERROR: super_oos.sh nicht gefunden/ausführbar im Template"
  exit 1
fi
( cd "$super_work" && bash "./super_oos.sh" )

# 10) super.img verschieben
if [[ -f "$super_work/super.img" ]]; then
  mv -f "$super_work/super.img" "$super_dest/"
  echo "super.img moved into Super Flasher."
else
  echo "ERROR: super.img wurde nicht erzeugt."
  exit 1
fi

# 11) Arbeitsordner löschen
rm -rf "$super_work"
echo "BUILD DONE!!!"
