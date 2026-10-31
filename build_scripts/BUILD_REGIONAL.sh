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


if [[ "${DEV:-}" == "X9U" ]]; then
  cos_here="$reg_dest/OTA_FILES_HERE"
  oos_here="$reg_dest/OTA_FILES_HERE"
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

# Extract to an explicit directory; otaripper versions may otherwise
# produce nested or differently named output directories.
new_folder="$input_dir/extracted_images"
mkdir -p "$new_folder"
echo "Running otaripper"
"$otaripper_bin" --no-open --output-dir "$new_folder" "$input_file"
mapfile -t image_dirs < <(find "$new_folder" -type f -name '*.img' -printf '%h\n' | sort -u)
[[ "${#image_dirs[@]}" -eq 1 ]] || { echo "ERROR: OTA extraction has no unique image directory"; exit 1; }
new_folder="${image_dirs[0]}"
[[ -f "$new_folder/boot.img" ]] || { echo "ERROR: Full OTA boot.img missing"; exit 1; }

#-------------------------------------------
# Move extracted images into XOS_FILES_HERE
if [[ "${DEV:-}" == "X9U" ]]; then
  for image in "$new_folder"/*.img; do
    [[ -f "$image" ]] || continue
    if [[ -f "$cos_here/$(basename "$image")" ]]; then rm -f "$image"; fi
  done
fi
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
