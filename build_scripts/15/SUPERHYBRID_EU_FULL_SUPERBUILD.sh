#!/usr/bin/env bash
set -euo pipefail

# Usage: ./SUPERHYBRID_EU_FULL_SUPERBUILD.sh /path/to/OTA.zip
# SuperHybrid EU (OOS) – OnePlus 15 – Port der BAT inkl. OOS_FILES_HERE-Cleanup

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 /path/to/OTA.zip"
  exit 64
fi

input_file="$(realpath "$1")"
input_dir="$(dirname "$input_file")"

# Ordner dieses Skripts (OUT_DIR)
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# otaripper liegt im selben Ordner (wurde von stage_files dort hingekopiert)
otaripper_bin="$script_dir/otaripper"
if [[ ! -x "$otaripper_bin" ]]; then
  echo "ERROR: otaripper (Linux) nicht gefunden/ausführbar: $otaripper_bin"
  exit 1
fi

super_src="$script_dir/SuperHybrid Flasher"
super_dest="$input_dir/SuperHybrid Flasher"
super_work="$super_dest/Super"
oos_here="$super_dest/OOS_FILES_HERE"

if [[ ! -d "$super_src" ]]; then
  echo "ERROR: Template 'SuperHybrid Flasher' nicht gefunden: $super_src"
  exit 1
fi

# 1) SuperHybrid-Flasher-Template neben die ZIP spiegeln
mkdir -p "$super_dest"
rsync -a "$super_src/" "$super_dest/"

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

# 5) Zuerst definierte Partitionen in Super/ verschieben
mkdir -p "$super_work"
echo "Moving logical partitions into Super/ ..."
part_list=(
  my_bigball.img my_carrier.img my_engineering.img my_heytap.img
  my_manifest.img my_product.img my_region.img my_stock.img
  odm.img product.img system.img system_dlkm.img system_ext.img
  vendor.img vendor_dlkm.img
)
for f in "${part_list[@]}"; do
  if [[ -f "$new_folder/$f" ]]; then
    echo "  moving $f"
    mv -f "$new_folder/$f" "$super_work/"
  fi
done

# 6) Restliche Dateien nach OOS_FILES_HERE/
mkdir -p "$oos_here"
shopt -s dotglob
if compgen -G "$new_folder/*" >/dev/null; then
  mv -f "$new_folder"/* "$oos_here/" || true
fi
shopt -u dotglob

# 7) temporären Extraktordner löschen
rm -rf "$new_folder"

# 8) OOS_FILES_HERE bereinigen – nur Whitelist behalten (wie im BAT)
echo "Cleaning OOS_FILES_HERE, keeping only required images..."
if [[ -d "$oos_here" ]]; then
  pushd "$oos_here" >/dev/null

  keep_names=(
    boot
    init_boot
    modem
    recovery
    vbmeta
    vbmeta_system
    vbmeta_vendor
    vendor_boot
    abl
    aop
    aop_config
    bluetooth
    cpucp
    devcfg
    dsp
    dtbo
    engineering_cdt
    featenabler
    hyp
    imagefv
    keymaster
    oplus_sec
    qupfw
    shrm
    splash
    tz
    uefi
    uefisecapp
    xbl
    xbl_config
    xbl_ramdump
  )

  shopt -s nullglob
  for f in *.*; do
    name="${f%.*}"
    keep=0
    for k in "${keep_names[@]}"; do
      if [[ "${name,,}" == "${k,,}" ]]; then
        keep=1
        break
      fi
    done
    if (( keep == 0 )); then
      rm -f -- "$f"
    fi
  done
  shopt -u nullglob

  popd >/dev/null
fi

echo "Done moving files into SuperHybrid Flasher"

# 9) super.img packen (Super/super_oos.sh wird vom stage_files-Template erwartet)
packer="$super_work/super_oos.sh"
if [[ ! -x "$packer" ]]; then
  echo "ERROR: Super packer script nicht gefunden/ausführbar: $packer"
  echo "Erwarte Linux-Packer unter 'SuperHybrid Flasher/Super/super_oos.sh'."
  exit 1
fi

echo "Packing super.img ..."
( cd "$super_work" && bash "./super_oos.sh" )

# 10) super.img ins Flasher-Root verschieben
if [[ -f "$super_work/super.img" ]]; then
  echo "Moving super.img into SuperHybrid Flasher ..."
  mv -f "$super_work/super.img" "$super_dest/"
else
  echo "ERROR: super.img wurde nicht erzeugt."
  exit 1
fi

# 11) Aufräumen: Super/ löschen, dtbo-Kram weg (falls vorhanden)
echo "Removing scrap files"
rm -rf "$super_work"
rm -f  "$super_dest/dtbo.img"
rm -f  "$super_dest/dtbo_patched.img"
rm -f  "$super_dest/dtbo_patcher.sh" "$super_dest/dtbo_patcher.py" "$super_dest/dtbo_patcher" || true

echo "BUILD DONE!!!"
