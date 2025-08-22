#!/usr/bin/env bash
set -euo pipefail

# Usage: ./REGIONALHYBRID_FULL_BUILD.sh /path/to/OTA.zip

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 /path/to/OTA.zip"
  exit 64
fi

# Entspricht: set "input_file=%~1" / set "input_dir=%~dp1"
input_file="$(realpath "$1")"
input_dir="$(dirname "$input_file")"

# Entspricht: set "tool=%~dp0otaripper.exe" / set "tool_name=otaripper.exe"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
tool="$script_dir/otaripper"   # Linux-Binary (im selben Ordner wie dieses Skript)

# Entspricht:
# set "regional_flasher_src=%~dp0Regional Hybrid Flasher"
# set "regional_flasher_dest=%input_dir%Regional Hybrid Flasher"
regional_flasher_src="$script_dir/Regional Hybrid Flasher"
regional_flasher_dest="$input_dir/Regional Hybrid Flasher"

# --- Copy Regional Hybrid Flasher folder to zip location (xcopy-Äquivalent, ohne Löschen) ---
if [[ ! -d "$regional_flasher_src" ]]; then
  echo "ERROR: Template-Ordner fehlt: $regional_flasher_src"
  exit 1
fi
mkdir -p "$regional_flasher_dest"
# xcopy /E /I /Y  ⇒ rekursiv, anlegen, überschreiben (aber NICHT löschen)
rsync -a "$regional_flasher_src/" "$regional_flasher_dest/"

# --- Copy otaripper to the zip's folder ---
if [[ ! -x "$tool" ]]; then
  echo "ERROR: otaripper nicht gefunden/ausführbar: $tool"
  exit 1
fi
cp -f "$tool" "$input_dir/otaripper"
chmod +x "$input_dir/otaripper"

# --- Save list of folders before extraction ---
declare -A before_folders=()
while IFS= read -r -d '' d; do
  before_folders["$(basename "$d")"]=1
done < <(find "$input_dir" -mindepth 1 -maxdepth 1 -type d -print0)

# --- Run otaripper (no --partitions) ---
pushd "$input_dir" >/dev/null
"./otaripper" "$input_file"
popd >/dev/null

# --- Delete temporary otaripper ---
rm -f "$input_dir/otaripper"

# --- Detect the new folder created by extraction (wie im .bat: letzter unbekannter Ordner gewinnt) ---
new_folder=""
while IFS= read -r -d '' d; do
  base="$(basename "$d")"
  if [[ -z "${before_folders[$base]+x}" ]]; then
    new_folder="$d"   # wie im .bat wird hier nicht gebrochen -> letztes Match
  fi
done < <(find "$input_dir" -mindepth 1 -maxdepth 1 -type d -print0)

if [[ -z "$new_folder" ]]; then
  echo "ERROR: kein neuer Ordner nach Extraktion gefunden."
  exit 1
fi

# --- Move all extracted files into OOS_FILES_HERE ---
echo "Moving all extracted files into OOS_FILES_HERE..."
mkdir -p "$regional_flasher_dest/OOS_FILES_HERE"
shopt -s dotglob
if compgen -G "$new_folder/*" >/dev/null; then
  mv -f "$new_folder"/* "$regional_flasher_dest/OOS_FILES_HERE/" || true
fi
shopt -u dotglob

# --- rd /s /q "!new_folder!" ---
rm -rf "$new_folder"

echo "Done moving files into Regional Hybrid Flasher."
echo "Copying 16.0.0.1_dtbo.img into Regional Hybrid Flasher..."

# Entspricht: copy /Y "%~dp016DTBO\16.0.0.1_dtbo.img" "%Regional Hybrid Flasher_dest%"
dtbo_src="$script_dir/16DTBO/16.0.0.1_dtbo.img"
if [[ -f "$dtbo_src" ]]; then
  cp -f "$dtbo_src" "$regional_flasher_dest/"
else
  echo "WARN: dtbo nicht gefunden: $dtbo_src"
fi
