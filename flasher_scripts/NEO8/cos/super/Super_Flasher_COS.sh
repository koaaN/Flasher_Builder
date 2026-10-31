#!/usr/bin/env bash
# Realme NEO8: CN ColorOS super package. No cross-region conversion.
set -euo pipefail
cd "$(dirname "$0")"
FASTBOOT="Platform-Tools/fastboot"
if [[ ! -x "$FASTBOOT" ]]; then
  FASTBOOT="$(command -v fastboot)" || { echo 'fastboot not found.'; exit 1; }
fi
[[ -f super.img && -f COS_FILES_HERE/boot.img ]] || {
  echo 'Incomplete NEO8 package: super.img and COS_FILES_HERE/boot.img are required.'
  exit 1
}
echo 'Realme NEO8 — CN ColorOS Super Flasher'
echo 'Use only with an unlocked Realme NEO8 and matching CN firmware.'
read -rp 'Connect the phone in bootloader fastboot mode, then press Enter to start: ' _
BOOT_PARTS=(boot dtbo init_boot modem recovery vbmeta vbmeta_system vbmeta_vendor vendor_boot)
for part in "${BOOT_PARTS[@]}"; do
  [[ -f "COS_FILES_HERE/$part.img" ]] || continue
  "$FASTBOOT" flash "${part}_a" "COS_FILES_HERE/$part.img"
  "$FASTBOOT" flash "${part}_b" "COS_FILES_HERE/$part.img"
done
"$FASTBOOT" flash super super.img
"$FASTBOOT" reboot fastboot
read -rp 'Wait for fastbootd on the phone, then press Enter: ' _
# All logical partitions, including the supplied NEO8 bloat, are already in super.
SUPER_PARTS=(my_bigball my_carrier my_company my_engineering my_heytap my_manifest
  my_preload my_product my_region my_stock odm product system system_dlkm
  system_dlkm_gki system_dlkm_oki system_ext vendor vendor_dlkm)
for image in COS_FILES_HERE/*.img; do
  [[ -f "$image" ]] || continue
  name="$(basename "$image" .img)"; skip=0
  for part in "${BOOT_PARTS[@]}" "${SUPER_PARTS[@]}"; do
    [[ "$name" != "$part" ]] || { skip=1; break; }
  done
  [[ "$skip" == 0 ]] || continue
  "$FASTBOOT" flash --slot=all "$name" "$image"
done
"$FASTBOOT" --set-active=a
read -rp 'Format data on the phone before booting? [y/N]: ' wipe
if [[ "$wipe" == [yY] ]]; then
  echo 'Use Format Data on the phone. Reboot after formatting completes.'
else
  "$FASTBOOT" reboot
fi
