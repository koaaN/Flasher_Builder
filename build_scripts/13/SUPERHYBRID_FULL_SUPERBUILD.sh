#!/usr/bin/env bash
set -euo pipefail

# Usage: ./SUPERHYBRID_FULL_SUPERBUILD.sh /path/to/OTA.zip

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 /path/to/OTA.zip"
  exit 64
fi

input_file="$(realpath "$1")"
input_dir="$(dirname "$input_file")"

# Ordner dieses Skripts
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Tools/Quellen/Ziele
otaripper_bin="$script_dir/otaripper"   # passe an, falls Pfad abweicht
if [[ ! -x "$otaripper_bin" ]]; then
  echo "ERROR: otaripper (Linux) nicht gefunden/ausführbar: $otaripper_bin"
  exit 1
fi

super_src="$script_dir/SuperHybrid Flasher"
super_dest="$input_dir/SuperHybrid Flasher"
super_work="$super_dest/Super"
oos_here="$super_dest/OOS_FILES_HERE"

# 1) Super Flasher-Template neben die ZIP spiegeln
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

echo "Done moving files into Super Flasher"
echo "Copying and Patching dtbo.img"

# 8) dtbo.img aus OOS_FILES_HERE ins Super-Flasher-Root kopieren
if [[ -f "$oos_here/dtbo.img" ]]; then
  cp -f "$oos_here/dtbo.img" "$super_dest/dtbo.img"
else
  echo "WARN: dtbo.img nicht in $oos_here gefunden (überspringe Patch-Schritt)."
fi

# 9) dtbo_patcher ausführen (Linux-Äquivalent erwartet)
#   LOGIK bleibt identisch: wir rufen den Patcher im Flasher-Root auf.
#   Akzeptierte Varianten (in dieser Reihenfolge): .sh, (Python) .py, ausführbare Binary.
#   Falls nur eine .bat existiert, brich mit Fehler ab (Windows-Tool).
if [[ -f "$super_dest/dtbo.img" ]]; then
  if [[ -x "$super_dest/dtbo_patcher.sh" ]]; then
    ( cd "$super_dest" && bash "./dtbo_patcher.sh" )
  elif [[ -f "$super_dest/dtbo_patcher.py" ]]; then
    ( cd "$super_dest" && python3 "./dtbo_patcher.py" )
  elif [[ -x "$super_dest/dtbo_patcher" ]]; then
    ( cd "$super_dest" && "./dtbo_patcher" )
  elif [[ -f "$super_dest/dtbo_patcher.bat" ]]; then
    echo "ERROR: dtbo_patcher.bat gefunden, aber kein Linux-Patcher (sh/py/bin). Bitte Linux-Variante bereitstellen."
    exit 1
  else
    echo "WARN: Kein dtbo_patcher gefunden (sh/py/bin) – Patch-Schritt übersprungen."
  fi
fi

# 10) 16DTBO/dtbo.img in OOS_FILES_HERE kopieren (entspricht deinem BAT)
dtbo16_src="$script_dir/16DTBO/dtbo.img"
if [[ -f "$dtbo16_src" ]]; then
  echo "Copying 16.0.0.1 dtbo.img into OOS_FILES_HERE..."
  cp -f "$dtbo16_src" "$oos_here/"
else
  echo "WARN: 16DTBO dtbo.img nicht gefunden: $dtbo16_src"
fi

# 11) super.img packen (Super/super_oos.sh wird im Template erwartet)
packer="$super_work/super_oos.sh"
if [[ ! -x "$packer" ]]; then
  echo "ERROR: Super packer script nicht gefunden/ausführbar: $packer"
  echo "Erwarte Linux-Packer unter 'SuperHybrid Flasher/Super/super_oos.sh'."
  exit 1
fi

echo "Packing super.img ..."
( cd "$super_work" && bash "./super_oos.sh" )

# 12) super.img ins Flasher-Root verschieben
if [[ -f "$super_work/super.img" ]]; then
  echo "Moving super.img into SuperHybrid Flasher ..."
  mv -f "$super_work/super.img" "$super_dest/"
else
  echo "ERROR: super.img wurde nicht erzeugt."
  exit 1
fi

# 13) Aufräumen: Super/ löschen, dtbo.img + Patcher entfernen (wie BAT)
echo "Removing scrap files"
rm -rf "$super_work"
rm -f  "$super_dest/dtbo.img"
rm -f  "$super_dest/dtbo_patcher.sh" "$super_dest/dtbo_patcher.py" "$super_dest/dtbo_patcher" || true
# (BAT löschte nur .bat; wir entfernen hier die Linux-Varianten. Wenn du die .bat mitlieferst, kannst du die nächste Zeile aktivieren:)
# rm -f  "$super_dest/dtbo_patcher.bat" || true

echo "BUILD DONE!!!"
