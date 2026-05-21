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

if [[ "$FTYPE" == "RegionalHybrid Flasher" ]]; then
  # ===== RegionalHybrid =====
  if [[ "$REGION" == "CN" ]]; then
    reg_src="$script_dir/RegionalHybrid Flasher CN"
    reg_dest="$input_dir/RegionalHybrid Flasher CN"
    cos_here="$reg_dest/COS_FILES_HERE"
  else
    reg_src="$script_dir/RegionalHybrid Flasher"
    reg_dest="$input_dir/RegionalHybrid Flasher"
    oos_here="$reg_dest/OOS_FILES_HERE"
  fi

else
  # ===== Regional (non-hybrid) =====
  if [[ "$REGION" == "CN" ]]; then
    reg_src="$script_dir/Regional Flasher CN"
    reg_dest="$input_dir/Regional Flasher CN"
    cos_here="$reg_dest/COS_FILES_HERE"
  else
    reg_src="$script_dir/Regional Flasher"
    reg_dest="$input_dir/Regional Flasher"
    oos_here="$reg_dest/OOS_FILES_HERE"
  fi
fi


if [[ ! -d "$reg_src" ]]; then
  echo "ERROR: Template 'RegionalHybrid Flasher' NOT FOUND!: $reg_src"
  exit 1
fi

#----------------------------------
# Copy flasher dir to build folder
#----------------------------------

echo "Copying $reg_src to build folder"
rm -rf "$reg_dest"
mkdir -p "$reg_dest"
rsync -a "$reg_src/" "$reg_dest/"

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
"$otaripper_bin" "$input_file" -n
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

#-------------------------------------------
# Move extracted images into XOS_FILES_HERE
#-------------------------------------------

echo "Move extracted images into XOS_FILES_HERE"
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

echo "BUILD DONE!!!"
