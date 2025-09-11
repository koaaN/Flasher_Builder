#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 /path/to/payload.bin"
  exit 64
fi

input_file="$(realpath "$1")"
input_dir="$(dirname "$input_file")"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Tools
otaripper_bin="$script_dir/otaripper"
if [[ ! -x "$otaripper_bin" ]]; then
  echo "ERROR: otaripper (Linux) nicht gefunden/ausführbar: $otaripper_bin"
  exit 1
fi

# Flasher-Template
flasher_source="$script_dir/SuperHybrid Matrixx Flasher"
flasher_dest="$input_dir/SuperHybrid Matrixx Flasher"
fastbootd_dir="$flasher_dest/FASTBOOTD_FILES_HERE"
fastboot_dir="$flasher_dest/FASTBOOT_FILES_HERE"
super_dir="$flasher_dest/Super"

# 1) Flasher kopieren
mkdir -p "$flasher_dest"
rsync -a "$flasher_source/" "$flasher_dest/"

# 2) Vorherige Ordner merken
declare -A before
while IFS= read -r -d '' d; do
  before["$(basename "$d")"]=1
done < <(find "$input_dir" -mindepth 1 -maxdepth 1 -type d -print0)

# 3) otaripper laufen lassen
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

[[ -n "$new_folder" ]] || { echo "ERROR: kein neuer Ordner nach Extraktion gefunden."; exit 1; }

# 5) Alles in Flasher-Ordner verschieben
shopt -s dotglob
mv -f "$new_folder"/* "$flasher_dest/" || true
shopt -u dotglob
rm -rf "$new_folder"

# 6) Sortierung der .img Dateien
mkdir -p "$fastbootd_dir" "$fastboot_dir" "$super_dir"

# FASTBOOTD_FILES_HERE
fastbootd_imgs=(
  abl aop aop_config bluetooth cpucp cpucp_dtb devcfg dsp engineering_cdt featenabler hyp
  imagefv keymaster oplus_sec oplusstanvbk qupfw shrm splash tz uefi uefisecapp
  xbl xbl_config xbl_ramdump pdp pdp_cdb pvmfw soccp_dcd soccp_debug spuservice
)
for p in "${fastbootd_imgs[@]}"; do
  [[ -f "$flasher_dest/$p.img" ]] && mv -f "$flasher_dest/$p.img" "$fastbootd_dir/"
done

# FASTBOOT_FILES_HERE
fastboot_imgs=(boot dtbo init_boot modem recovery super vbmeta vbmeta_system vbmeta_vendor vendor_boot)
for p in "${fastboot_imgs[@]}"; do
  [[ -f "$flasher_dest/$p.img" ]] && mv -f "$flasher_dest/$p.img" "$fastboot_dir/"
done

# super/
super_imgs=(odm product system system_dlkm system_ext vendor vendor_dlkm)
for p in "${super_imgs[@]}"; do
  [[ -f "$flasher_dest/$p.img" ]] && mv -f "$flasher_dest/$p.img" "$super_dir/"
done

echo "All files sorted into folders inside: $flasher_dest"

# 7) super.img packen
packer="$super_dir/super_matrixx.sh"
if [[ ! -x "$packer" ]]; then
  echo "ERROR: super_matrixx.sh nicht gefunden/ausführbar: $packer"
  exit 1
fi

echo "Packing super.img ..."
( cd "$super_dir" && bash "./super_matrixx.sh" )

# 8) super.img verschieben
if [[ -f "$super_dir/super.img" ]]; then
  echo "Moving super.img into FASTBOOT_FILES_HERE ..."
  mv -f "$super_dir/super.img" "$fastboot_dir/"
else
  echo "ERROR: super.img wurde nicht erzeugt."
  exit 1
fi

# 9) Aufräumen
rm -rf "$super_dir"

echo "BUILD DONE!!!"
