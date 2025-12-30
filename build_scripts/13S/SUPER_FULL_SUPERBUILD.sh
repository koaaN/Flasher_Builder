#!/usr/bin/env bash
set -euo pipefail

# Usage: ./SUPERHYBRID_FULL_SUPERBUILD.sh /path/to/OTA.zip
# SuperHybrid – OnePlus 15

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 /path/to/OTA.zip"
  exit 64
fi

input_file="$(realpath "$1")"
input_dir="$(dirname "$input_file")"

# OUT_DIR (da liegt der Builder + Template + otaripper)
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

otaripper_bin="$script_dir/otaripper"
if [[ ! -x "$otaripper_bin" ]]; then
  echo "ERROR: otaripper (Linux) NOT FOUND!: $otaripper_bin"
  exit 1
fi

#---------------------------
# Calculate working folders
#---------------------------

if [[ "$REGION" == "CN" ]]; then
  super_src="$script_dir/SuperHybrid Flasher CN"
  super_dest="$input_dir/SuperHybrid Flasher CN"
  super_work="$super_dest/Super"
  cos_here="$super_dest/COS_FILES_HERE"
  oos_here="$super_dest/OOS_FILES_HERE"
else
  super_src="$script_dir/SuperHybrid Flasher"
  super_dest="$input_dir/SuperHybrid Flasher"
  super_work="$super_dest/Super"
  oos_here="$super_dest/OOS_FILES_HERE"
fi


if [[ ! -d "$super_src" ]]; then
  echo "ERROR: Template 'SuperHybrid Flasher' NOT FOUND!: $super_src"
  exit 1
fi

#----------------------------------
# Copy flasher dir to build folder
#----------------------------------

echo "Copying $super_src to build folder"
rm -rf "$super_dest"
mkdir -p "$super_dest"
rsync -a "$super_src/" "$super_dest/"

#-----------------------------------------------
# Record existing directories before extraction
#-----------------------------------------------

declare -A before
while IFS= read -r -d '' d; do
  before["$(basename "$d")"]=1
done < <(find "$input_dir" -mindepth 1 -maxdepth 1 -type d -print0)

#---------------
# Run otaripper
#---------------

echo "Running otaripper"
pushd "$input_dir" >/dev/null
"$otaripper_bin" "$input_file"
popd >/dev/null

#----------------------
# Detect extracted dir
#----------------------

new_folder=""
while IFS= read -r -d '' d; do
  base="$(basename "$d")"
  if [[ -z "${before[$base]+x}" ]]; then
    new_folder="$d"
    break
  fi
done < <(find "$input_dir" -mindepth 1 -maxdepth 1 -type d -print0)

[[ -n "$new_folder" ]] || { echo "ERROR: No new folder found after extraction"; exit 1; }

#--------------------------------
# Find & Move Logical Partitions
#--------------------------------

mkdir -p "$super_work"
echo "Moving logical partitions into Super dir"
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

#-------------------------------------------
# Move remaining images into XOS_FILES_HERE
#-------------------------------------------

echo "Move remaining images into XOS_FILES_HERE"
if [[ "$REGION" == "CN" ]]; then
  mkdir -p "$cos_here"
  shopt -s dotglob
  if compgen -G "$new_folder/*" >/dev/null; then
    mv -f "$new_folder"/* "$cos_here/" || true
  fi
  shopt -u dotglob
else
  mkdir -p "$oos_here"
  shopt -s dotglob
  if compgen -G "$new_folder/*" >/dev/null; then
    mv -f "$new_folder"/* "$oos_here/" || true
  fi
  shopt -u dotglob
fi

#-------------------------------------------
# Delete the temporary extraction directory
#-------------------------------------------

rm -rf "$new_folder"

#--------------------------------------------
# OP15 OOS EXTRA: Keep "Convert" images ONLY
#--------------------------------------------

if [[ "$DEV" == "15" && "$REGION" != "CN" ]]; then
  echo "OP15: Cleaning OOS_FILES_HERE, Convert images ONLY"
  if [[ -d "$oos_here" ]]; then
    pushd "$oos_here" >/dev/null

    # Files to keep:
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
        # entspricht "del /q"
        rm -f -- "$f"
      fi
    done
    shopt -u nullglob

    popd >/dev/null
  fi
fi

echo "Done moving files into SuperHybrid Flasher"

#----------------
# Pack super.img
#----------------

packer="$super_work/super.sh"
if [[ ! -x "$packer" ]]; then
  echo "ERROR: Super packer script nicht gefunden/ausführbar: $packer"
  echo "Erwarte Linux-Packer unter 'SuperHybrid Flasher/Super/super.sh'."
  exit 1
fi

echo "Packing super.img"
( cd "$super_work" && bash "./super.sh" )

#-------------------------------
# Move super.img to $super_dest
#-------------------------------

if [[ -f "$super_work/super.img" ]]; then
  echo "Moving super.img into $super_dest"
  mv -f "$super_work/super.img" "$super_dest/"
else
  echo "ERROR: super.img NOT FOUND!"
  exit 1
fi

#--------------------
# Remove scrap files
#--------------------

echo "CLEAN UP!: Removing scrap files"
rm -rf "$super_work"
rm -f  "$super_dest/dtbo.img"
rm -f  "$super_dest/dtbo_patched.img"
rm -f  "$super_dest/dtbo_patcher.sh" "$super_dest/dtbo_patcher.py" "$super_dest/dtbo_patcher" || true

echo "BUILD DONE!!!"
