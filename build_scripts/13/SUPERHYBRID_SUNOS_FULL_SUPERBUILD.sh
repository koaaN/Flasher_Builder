#!/usr/bin/env bash
set -euo pipefail

# Usage: ./SUPERHYBRID_SUNOS_FULL_SUPERBUILD.sh /path/to/payload.bin

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 /path/to/payload.bin"
  exit 64
fi

input_file="$(realpath "$1")"
input_dir="$(dirname "$input_file")"

# Ordner dieses Skripts
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Tools
otaripper_bin="$script_dir/../../otaripper/otaripper"
if [[ ! -x "$otaripper_bin" ]]; then
  echo "ERROR: otaripper (Linux) nicht gefunden/ausführbar: $otaripper_bin"
  exit 1
fi

# Flasher-Template
flasher_source="$script_dir/SuperHybrid SunOS Flasher"
flasher_dest="$input_dir/SuperHybrid SunOS Flasher"

# 1) Ordnerliste vor der Extraktion merken
declare -A before
while IFS= read -r -d '' d; do
  before["$(basename "$d")"]=1
done < <(find "$input_dir" -mindepth 1 -maxdepth 1 -type d -print0)

# 2) otaripper im payload-Ordner ausführen
pushd "$input_dir" >/dev/null
"$otaripper_bin" "$input_file"
popd >/dev/null

# 3) neuen Extraktionsordner erkennen
extracted_folder=""
while IFS= read -r -d '' d; do
  base="$(basename "$d")"
  if [[ -z "${before[$base]+x}" ]]; then
    extracted_folder="$d"
    break
  fi
done < <(find "$input_dir" -mindepth 1 -maxdepth 1 -type d -print0)

if [[ -z "$extracted_folder" ]]; then
  echo "Error: Could not detect extracted folder."
  exit 1
fi

# 4) Flasher-Template neben payload spiegeln
mkdir -p "$flasher_dest"
rsync -a "$flasher_source/" "$flasher_dest/"

# 5) Alle Dateien/Ordner aus dem Extrakt in den Flasher-Ordner verschieben
shopt -s dotglob
if compgen -G "$extracted_folder/*" >/dev/null; then
  mv -f "$extracted_folder"/* "$flasher_dest/"
fi
shopt -u dotglob
rm -rf "$extracted_folder"

# 6) Dateien in FASTBOOTD_FILES_HERE verschieben
mkdir -p "$flasher_dest/FASTBOOTD_FILES_HERE"
for f in \
  abl.img aop.img aop_config.img bluetooth.img cpucp.img cpucp_dtb.img \
  devcfg.img dsp.img engineering_cdt.img featenabler.img hyp.img imagefv.img \
  keymaster.img oplus_sec.img oplusstanvbk.img qupfw.img shrm.img splash.img \
  tz.img uefi.img uefisecapp.img xbl.img xbl_config.img xbl_ramdump.img
do
  [[ -f "$flasher_dest/$f" ]] && mv -f "$flasher_dest/$f" "$flasher_dest/FASTBOOTD_FILES_HERE/"
done

# 7) Dateien in FASTBOOT_FILES_HERE verschieben
mkdir -p "$flasher_dest/FASTBOOT_FILES_HERE"
for f in \
  boot.img dtbo.img init_boot.img modem.img recovery.img super.img \
  vbmeta.img vbmeta_system.img vbmeta_vendor.img vendor_boot.img
do
  [[ -f "$flasher_dest/$f" ]] && mv -f "$flasher_dest/$f" "$flasher_dest/FASTBOOT_FILES_HERE/"
done

# 8) SUPER-relevante Images in Super/ verschieben
mkdir -p "$flasher_dest/Super"
for f in odm.img product.img system.img system_dlkm.img system_ext.img vendor.img vendor_dlkm.img; do
  [[ -f "$flasher_dest/$f" ]] && mv -f "$flasher_dest/$f" "$flasher_dest/Super/"
done

echo
echo "All files sorted into folders inside: $flasher_dest"
echo "Packing super.img"

# 9) super.img packen (Linux-Packer erwartet)
packer="$flasher_dest/Super/super_sunos.sh"
if [[ ! -x "$packer" ]]; then
  echo "ERROR: super_sunos.sh nicht gefunden/ausführbar: $packer"
  echo "Bitte Linux-Packer im Template unter 'SuperHybrid SunOS Flasher/Super/super_sunos.sh' bereitstellen."
  exit 1
fi
( cd "$flasher_dest/Super" && bash "./super_sunos.sh" )

# 10) super.img nach FASTBOOT_FILES_HERE verschieben
if [[ -f "$flasher_dest/Super/super.img" ]]; then
  echo "Moving super.img into SuperHybrid SunOS Flasher/FASTBOOT_FILES_HERE/."
  mv -f "$flasher_dest/Super/super.img" "$flasher_dest/FASTBOOT_FILES_HERE/"
else
  echo "ERROR: super.img wurde nicht erzeugt."
  exit 1
fi

# 11) Super-Arbeitsordner entfernen
echo "Removing scrap files"
rm -rf "$flasher_dest/Super"

echo "BUILD DONE!!!"
