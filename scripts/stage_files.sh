#!/usr/bin/env bash
set -euo pipefail

# Erwartet via Env: DEV, FTYPE, REGION, BUILDER_SH, OUT_DIR, GITHUB_WORKSPACE, OTA_PATH, OTA_DIR

# ------------------------------
# Helper: Copy bloat from folder
# ------------------------------

copy_bloat_from_folder () {
  local base="$1" folder="$2" dest="$3"; shift 3 || true
  local skip_list=("$@")
  [ -n "${folder:-}" ] || return 0
  local src="${base}/${folder}"
  [ -d "$src" ] || return 0
  mkdir -p "$dest"
  echo "Copying bloat from $src → $dest"
  local needed=( "my_preload.img" "my_company.img" "odm.img" "oplusstanvbk.img" "my_region.img" "system_dlkm_oki.img" "system_dlkm_gki.img" )
  for f in "${needed[@]}"; do
    local skip=0
    for s in "${skip_list[@]}"; do
      [[ "$f" == "$s" ]] && skip=1 && break
    done
    [ "$skip" -eq 1 ] && continue
    if [ -f "$src/$f" ]; then
      cp -f "$src/$f" "$dest/"
      continue
    fi
    local stub="$src/${f%.img}"
    [ -f "$stub" ] || continue
    local url; url="$(tr -d '\r' < "$stub" | xargs || true)"
    [ -n "$url" ] && echo "Downloading $f from $url" && curl -L --fail --retry 3 --retry-delay 5 -o "$dest/$f" "$url" || echo "WARN: download failed for $f"
  done
}

# --------------------------------
# Helper: Normalize updater-script
# --------------------------------

normalize_updater_script_lf () {
  local meta_root="$1"
  local up="$meta_root/com/google/android/updater-script"
  [ -f "$up" ] || return 0
  awk '{ sub(/\r$/,""); print }' "$up" > "$up.tmp" && mv "$up.tmp" "$up"
}

# ------------------------------
#  Helper: Decide bloat folder
# ------------------------------

get_bloat_folder () {
  local dev="$1" region="$2"

  case "$region" in
    CN|EU|GLO|IN|NA)
      echo "${region}_BLOAT"
      ;;
    *)
      echo "ERROR: Unknown region '$region' (dev=$dev)" >&2
      return 1
      ;;
  esac
}

# ------------------------------
#  Helper: Calculate oos or cos
# ------------------------------

get_os_subtree () {
  local dev="$1" ftype="$2" region="$3"

  if [[ "$region" == "CN" ]]; then
    echo "cos"
  else
    echo "oos"
  fi
}

# ------------------------------
#   Helper: Copy/Download .img
# ------------------------------

copy_or_download () {
  local dir="$1" base="$2" dest="$3"
  if [ -f "$dir/${base}.img" ]; then
    cp -f "$dir/${base}.img" "$dest"
  else
    local stub="$dir/${base}"
    [ -f "$stub" ] || return
    local url; url="$(tr -d '\r' < "$stub" | xargs || true)"
    [ -n "$url" ] && echo "Downloading ${base}.img from $url" && curl -L --fail --retry 3 --retry-delay 5 -o "$dest" "$url" || echo "WARN: download failed for ${base}.img"
  fi
}

# -----------------------------
#      Device Configuration
# -----------------------------
dev="$DEV"
ftype="$FTYPE"
region="$REGION"
root="$GITHUB_WORKSPACE"

echo "DEVICE='$dev' • FLASHER TYPE='$ftype' • REGION='$region'"

if [[ "$FTYPE" == *Super* ]]; then
  builder_dir="$root/build_scripts"
else
  builder_dir="$root/build_scripts/$dev"
fi
bloat_base="$root/bloat/$dev"

# -----------------------------
#        Create out dir
# -----------------------------

echo "Creating $OUT_DIR dir"
rm -rf "$OUT_DIR" || true
mkdir -p "$OUT_DIR"

# -----------------------------
#        Add otaripper
# -----------------------------

echo "Adding Otaripper to: $OUT_DIR"
[ -f "$root/otaripper/otaripper" ] && cp -f "$root/otaripper/otaripper" "$OUT_DIR/" && chmod +x "$OUT_DIR/otaripper"
[ -n "${BUILDER_SH:-}" ] && [ -f "$builder_dir/$BUILDER_SH" ] && cp -f "$builder_dir/$BUILDER_SH" "$OUT_DIR/" && chmod +x "$OUT_DIR/$BUILDER_SH"

# -----------------------------
#    Calculate Working folder
# -----------------------------

echo "Calculating Working Folder"
work_name="$ftype"
[[ "$region" == "CN" ]] && work_name="$ftype CN"
echo "Calculated Working Folder: $work_name"

# -----------------------------
#     Create Working folder
# -----------------------------

echo "Creating Working Folder: $OUT_DIR/$work_name"
work_dir="$OUT_DIR/$work_name"
mkdir -p "$work_dir"

# -----------------------------
#      Add Flasher-Script
# -----------------------------

tpl_dev="$dev"

os_sub="$(get_os_subtree "$dev" "$ftype" "$region")"
kind="$([[ "$ftype" == *Super* ]] && echo "super" || echo "regional")"
tpl_base="$root/flasher_scripts/$tpl_dev/$os_sub/$kind"

echo "Adding flasher_script: $tpl_base"

if [ ! -d "$tpl_base" ]; then
  echo "ERROR: Flasher template not found: $tpl_base (dev=$dev, ftype=$ftype, region=$region)" >&2
  exit 1
fi

rsync -a "$tpl_base/" "$work_dir/"

# -----------------------------
#      HYBRID: Add META-INF
# -----------------------------

if [[ "$ftype" == *Hybrid* ]]; then
 echo "Adding META-INF for Hybrid build"
  mi="$tpl_base/META-INF"
  [ -d "$mi" ] && { mkdir -p "$work_dir/META-INF"; rsync -a "$mi/" "$work_dir/META-INF/"; normalize_updater_script_lf "$work_dir/META-INF"; }
fi

# -----------------------------
#      Add Platform-Tools
# -----------------------------

echo "Adding Platform-Tools"
pt_src="$root/Platform-Tools"
[ -d "$pt_src" ] && { mkdir -p "$work_dir/Platform-Tools"; rsync -a "$pt_src/" "$work_dir/Platform-Tools/"; } || echo "WARN: Platform-Tools not found at repo root: $pt_src"

# -----------------------------
#   Super: Create super dir
# -----------------------------

if [[ "$ftype" =~ Super ]]; then
  echo "Creating super dir"
  super_dir="$work_dir/Super"
  mkdir -p "$super_dir"

# -----------------------------
#      Super: Add lpmake
# -----------------------------

  if [ -f "$root/lpmake/lpmake" ]; then
    echo "Adding lpmake to super dir"
    cp -f "$root/lpmake/lpmake" "$super_dir/"
    chmod +x "$super_dir/lpmake"
  fi

# -----------------------------
#   Super: Decide Super_Packer
# -----------------------------

  packer="super.sh"

# -----------------------------
#      Super: Packer path
# -----------------------------


  pdir="$root/super_packers"
  script="$pdir/$packer"

  if [[ -f "$script" ]]; then
    cp -f "$script" "$super_dir/$packer"
    chmod +x "$super_dir/$packer"
    echo "Using super_packer: $script"
  else
    echo "ERROR: Missing $packer at $script" >&2
    exit 1
  fi
  
  # ------------------------------
  #  Super: Device Specific Fixes 
  # ------------------------------

  if [[ "$dev" == "13" && "$ftype" == "SuperHybrid Flasher" && "$region" != "CN" ]]; then
    repo_cos="$root/bloat/13/COS_FILES_HERE"
    cos_here="$work_dir/COS_FILES_HERE"

    echo "Adding OP13 Signal-fix files: $repo_cos → $cos_here"

    if [[ -d "$repo_cos" ]]; then
      mkdir -p "$cos_here"

      for f in my_region.img oplusstanvbk.img; do
        if [[ -f "$repo_cos/$f" ]]; then
          cp -f "$repo_cos/$f" "$cos_here/"
        else
          echo "WARN: Missing signal-fix file: $repo_cos/$f"
        fi
      done

    else
      echo "WARN: Signal-fix folder not found: $repo_cos"
    fi
  fi
  
  
  if [[ "$dev" == "13T" && "$ftype" == "Super Flasher" && "$region" == "IN" ]]; then    

    fixes_dir="$bloat_base/FIXES"
    cos_here="$work_dir/COS_FILES_HERE"
    echo "Adding OP13T Fixes to: $cos_here"
    mkdir -p "$cos_here"

    for f in my_region oplusstanvbk odm; do
      copy_or_download "$fixes_dir" "$f" "$cos_here/$f.img"
    done
  fi

  # -----------------------------
  #          Super: BLOAT
  # -----------------------------

  bloat_folder="$(get_bloat_folder "$dev" "$region")"
  echo "Adding bloat"
  copy_bloat_from_folder "$bloat_base" "$bloat_folder" "$super_dir"
fi


# -----------------------------
# CN DEBLOAT (my_preload ONLY)
# -----------------------------

if [[ "$region" == "CN" ]]; then
  oos_here="$work_dir/OOS_FILES_HERE"
  mkdir -p "$oos_here"

  preload_dir="$bloat_base/GLO_BLOAT"
  echo "CN debloat: Copying my_preload from $preload_dir → $oos_here"
  copy_or_download "$preload_dir" "my_preload" "$oos_here/my_preload.img"
fi

# --------------------------------
#        Regional: BLOAT
# --------------------------------

if [[ "$ftype" == "Regional Flasher" || "$ftype" == "RegionalHybrid Flasher" ]]; then

  # -----------------------------
  #       OxygenOS BLOAT
  # -----------------------------
  if [[ "$region" != "CN" ]]; then
    oos_here="$work_dir/OOS_FILES_HERE"
    mkdir -p "$oos_here"

    bloat_folder_oos="$(get_bloat_folder "$dev" "$region")"

    copy_bloat_from_folder "$bloat_base" "$bloat_folder_oos" "$oos_here"
  fi

  # -----------------------------
  #         ColorOS BLOAT
  # -----------------------------
  if [[ "$region" = "CN" ]]; then
    cos_here="$work_dir/COS_FILES_HERE"
    mkdir -p "$oos_here"

    bloat_folder_oos="$(get_bloat_folder "$dev" "$region")"

    copy_bloat_from_folder "$bloat_base" "$bloat_folder_oos" "$cos_here"
  fi
fi

# ----------------------------
#    Expose for next steps
# ----------------------------

echo "WORK_DIR=$work_dir" >> "$GITHUB_ENV"



