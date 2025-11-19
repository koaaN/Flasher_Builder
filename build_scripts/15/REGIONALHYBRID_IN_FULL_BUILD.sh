#!/usr/bin/env bash
set -euo pipefail

# Usage: ./REGIONALHYBRID_IN_FULL_BUILD.sh /path/to/OTA.zip
# RegionalHybrid IN – OnePlus 15

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 /path/to/OTA.zip"
  exit 64
fi

input_file="$(realpath "$1")"
input_dir="$(dirname "$input_file")"

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

otaripper_bin="$script_dir/otaripper"
if [[ ! -x "$otaripper_bin" ]]; then
  echo "ERROR: otaripper (Linux) nicht gefunden/ausführbar: $otaripper_bin"
  exit 1
fi

reg_src="$script_dir/RegionalHybrid Flasher"
reg_dest="$input_dir/RegionalHybrid Flasher"
oos_here="$reg_dest/OOS_FILES_HERE"

if [[ ! -d "$reg_src" ]]; then
  echo "ERROR: Template 'RegionalHybrid Flasher' nicht gefunden: $reg_src"
  exit 1
fi

mkdir -p "$reg_dest"
rsync -a "$reg_src/" "$reg_dest/"

declare -A before
while IFS= read -r -d '' d; do
  before["$(basename "$d")"]=1
done < <(find "$input_dir" -mindepth 1 -maxdepth 1 -type d -print0)

pushd "$input_dir" >/dev/null
"$otaripper_bin" "$input_file"
popd >/dev/null

new_folder=""
while IFS= read -r -d '' d; do
  base="$(basename "$d")"
  if [[ -z "${before[$base]+x}" ]]; then
    new_folder="$d"
    break
  fi
done < <(find "$input_dir" -mindepth 1 -maxdepth 1 -type d -print0)

[[ -n "$new_folder" ]] || { echo "ERROR: kein neuer Ordner nach Extraktion gefunden."; exit 1; }

mkdir -p "$oos_here"
echo "Moving extracted files into RegionalHybrid Flasher/OOS_FILES_HERE ..."
shopt -s dotglob
if compgen -G "$new_folder/*" >/dev/null; then
  mv -f "$new_folder"/* "$oos_here/" || true
fi
shopt -u dotglob

rm -rf "$new_folder"

echo "Done moving files into Regional Hybrid Flasher."
echo "BUILD DONE!!!"
