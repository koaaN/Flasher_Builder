#!/usr/bin/env bash

set -euo pipefail

# Change to script directory
cd "$(dirname "$0")"

# Locate fastboot
FASTBOOT="Platform-Tools/fastboot"
if [[ ! -x "$FASTBOOT" ]]; then
  if command -v fastboot >/dev/null 2>&1; then
    FASTBOOT="$(command -v fastboot)"
  else
    echo "\"$FASTBOOT\" not found and no fastboot in \$PATH."
    read -rp "Press Enter to exit..." _
    exit 1
  fi
fi

echo "**********************************************************************"
echo
echo "                Oneplus 15R - OOS Super Flasher"
echo "          Packaged by docnok63, Jonas Salo and Daniel"
echo "         script inspired by FTH PHONE 1902 and Venkayy"
echo
echo "************************      START FLASH     ************************"

# Make sure slot A is active
"$FASTBOOT" --set-active=a

###############################################################################
# Flash the fastboot images first (from OOS_FILES_HERE)
###############################################################################

"$FASTBOOT" flash boot_a          OOS_FILES_HERE/boot.img
"$FASTBOOT" flash boot_b          OOS_FILES_HERE/boot.img
"$FASTBOOT" flash dtbo_a          OOS_FILES_HERE/dtbo.img
"$FASTBOOT" flash dtbo_b          OOS_FILES_HERE/dtbo.img
"$FASTBOOT" flash init_boot_a     OOS_FILES_HERE/init_boot.img
"$FASTBOOT" flash init_boot_b     OOS_FILES_HERE/init_boot.img
"$FASTBOOT" flash modem_a         OOS_FILES_HERE/modem.img
"$FASTBOOT" flash modem_b         OOS_FILES_HERE/modem.img
"$FASTBOOT" flash recovery_a      OOS_FILES_HERE/recovery.img
"$FASTBOOT" flash recovery_b      OOS_FILES_HERE/recovery.img
"$FASTBOOT" flash vbmeta_a        OOS_FILES_HERE/vbmeta.img
"$FASTBOOT" flash vbmeta_b        OOS_FILES_HERE/vbmeta.img
"$FASTBOOT" flash vbmeta_system_a OOS_FILES_HERE/vbmeta_system.img
"$FASTBOOT" flash vbmeta_system_b OOS_FILES_HERE/vbmeta_system.img
"$FASTBOOT" flash vbmeta_vendor_a OOS_FILES_HERE/vbmeta_vendor.img
"$FASTBOOT" flash vbmeta_vendor_b OOS_FILES_HERE/vbmeta_vendor.img
"$FASTBOOT" flash vendor_boot_a   OOS_FILES_HERE/vendor_boot.img
"$FASTBOOT" flash vendor_boot_b   OOS_FILES_HERE/vendor_boot.img

###############################################################################
# super.img handling
###############################################################################

if [[ -f super.img ]]; then
  "$FASTBOOT" flash super super.img
else
  echo "super.img not found. Skipping super.img..."
fi

###############################################################################
# Reboot to fastbootd
###############################################################################

"$FASTBOOT" reboot fastboot
echo "  *******************      REBOOTING TO FASTBOOTD     *******************"
echo "  #################################"
echo "  #     Hit English on Phone      #"
echo "  #################################"
read -rp "Once the phone is in fastbootd, press Enter to continue..." _

###############################################################################
# Flash remaining .img files in OOS_FILES_HERE (excluding the ones above)
###############################################################################

EXCLUDED_IMAGES=(
  boot.img
  dtbo.img
  init_boot.img
  modem.img
  recovery.img
  vbmeta.img
  vbmeta_system.img
  vbmeta_vendor.img
  vendor_boot.img
  my_bigball.img
  my_carrier.img
  my_company.img
  my_engineering.img
  my_heytap.img
  my_manifest.img
  my_preload.img
  my_product.img
  my_region.img
  my_stock.img
  odm.img
  product.img
  system.img
  system_dlkm.img
  system_dlkm_oki.img
  system_ext.img
  vendor.img
  vendor_dlkm.img
)

should_skip() {
  local name=$1
  for ex in "${EXCLUDED_IMAGES[@]}"; do
    if [[ "$name" == "$ex" ]]; then
      return 0
    fi
  done
  return 1
}

# Loop through all .img files in OOS_FILES_HERE but skip excluded images
for img in OOS_FILES_HERE/*.img; do
  [[ -e "$img" ]] || continue
  basename_img="$(basename "$img")"
  if should_skip "$basename_img"; then
    continue
  fi
  part="${basename_img%.img}"
  echo "Flashing ${part}..."
  "$FASTBOOT" flash --slot=all "$part" "$img"
done

###############################################################################
# Logical partitions handling when super.img is NOT used
###############################################################################

PARTITIONS=(
  my_bigball
  my_carrier
  my_engineering
  my_heytap
  my_manifest
  my_product
  my_region
  my_stock
  odm
  product
  system
  system_dlkm
  system_dlkm_oki
  system_ext
  vendor
  vendor_dlkm
  my_company
  my_preload
)

if [[ ! -f super.img ]]; then
  # Delete, create & flash logical partitions
  for p in "${PARTITIONS[@]}"; do
    "$FASTBOOT" delete-logical-partition "${p}_a"      || true
    "$FASTBOOT" delete-logical-partition "${p}_b"      || true
    "$FASTBOOT" delete-logical-partition "${p}_a-cow"  || true
    "$FASTBOOT" delete-logical-partition "${p}_b-cow"  || true

    "$FASTBOOT" create-logical-partition "${p}_a" 1
    "$FASTBOOT" create-logical-partition "${p}_b" 1
    "$FASTBOOT" flash "$p" "OOS_FILES_HERE/${p}.img"
  done
else
  echo "super.img found. Logical partition flashes skipped..."
fi

###############################################################################
# Final messages / wipe decisions
###############################################################################

echo "********************** CHECK ABOVE FOR ERRORS **************************"
echo "************** IF ERRORS, DO NOT BOOT INTO SYSTEM **********************"

# If super.img was NOT flashed, ask wipe question and then exit
if [[ ! -f super.img ]]; then
  read -rp "Do you want to wipe data? (y/N): " ans
  case "$ans" in
    [yY]*)
      echo "****************** FLASHING COMPLETE *****************"
      echo "Wipe data by tapping Format Data on the screen, enter the code, and press format data."
      echo "Phone will automatically reboot into Android after wipe is done."
      read -rp "Press Enter when you're done..." _
      exit 0
      ;;
    *)
      echo "*********************** NO NEED TO WIPE DATA ****************************"
      read -rp "Flashing complete. Press Enter to reboot the phone to Android..." _
      "$FASTBOOT" reboot
      exit 0
      ;;
  esac
fi

# If super.img *was* flashed, ask the ColorOS / wipe question
echo "Are you flashing from ColorOS or Want to WIPE DATA?? (y/n)"
read -r ans2

case "$ans2" in
  [nN]*)
    echo "*********************** NO NEED TO WIPE DATA ****************************"
    read -rp "Flashing complete. Press Enter to reboot the phone to Android..." _
    "$FASTBOOT" reboot
    ;;
  *)
    echo "****************** FLASHING COMPLETE *****************"
    echo "Wipe data by tapping Format Data on the screen, enter the code, and press format data."
    echo "Phone will automatically reboot into Android after wipe is done."
    read -rp "Press Enter when you're done..." _
    ;;
esac

