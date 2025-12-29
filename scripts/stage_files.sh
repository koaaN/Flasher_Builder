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

# ------------------------------
#     Helper: Copy debloat
# ------------------------------

copy_debloat_pair () {
  local debloat_dir="$1" dest="$2"
  [ -d "$debloat_dir" ] || return 0
  mkdir -p "$dest"
  for f in "my_company.img" "my_preload.img"; do
    if [ -f "$debloat_dir/$f" ]; then
      cp -f "$debloat_dir/$f" "$dest/"
    else
      local stub="$debloat_dir/${f%.img}"
      [ -f "$stub" ] || continue
      local url; url="$(tr -d '\r' < "$stub" | xargs || true)"
      [ -n "$url" ] && echo "Downloading $f from $url" && curl -L --fail --retry 3 --retry-delay 5 -o "$dest/$f" "$url" || echo "WARN: download failed for $f"
    fi
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
  case "$dev" in
    "Ace5")
      case "$region" in
        CN) echo "CN_BLOAT" ;;
        EU|GLO) echo "EUGLO_BLOAT" ;;
        IN) echo "IN_BLOAT" ;;
        NA) echo "NA_BLOAT" ;;
        *) echo "" ;;
      esac ;;
    "Ace5Pro")
      [[ "$region" == "CN" ]] && echo "A5P_BLOAT" || echo "" ;;
    "15")
      case "$region" in
        CN) echo "CN_BLOAT" ;;
        EU) echo "EU_BLOAT" ;;
        GLO) echo "GLO_BLOAT" ;;
        IN) echo "IN_BLOAT" ;;
        *) echo "" ;;
      esac ;;
    "Pad3")
      case "$region" in
        EU) echo "EU_BLOAT" ;;
        GLO) echo "GLO_BLOAT" ;;
        IN) echo "IN_BLOAT" ;;
        *) echo "" ;;
      esac ;;
    *)
      case "$region" in
        CN) echo "CN_BLOAT" ;;
        EU|GLO) echo "EUGLO_BLOAT" ;;
        IN) echo "IN_BLOAT" ;;
        NA) echo "NA_BLOAT" ;;
        *) echo "" ;;
      esac ;;
  esac
}

# ------------------------------
#     Helper: Get OS subtree
# ------------------------------

get_os_subtree () {
  local dev="$1" ftype="$2" region="$3"
  if [[ "$ftype" == *Hybrid* || "$ftype" == "Regional Flasher" ]]; then
    [[ "$region" == "CN" ]] && echo "cos" || echo "oos"
    return
  fi
  if [[ "$ftype" == "Super Flasher" ]]; then
    if { [[ "$dev" == "13T" || "$dev" == "Ace5" || "$dev" == "Ace6" || "$dev" == "Ace6T" ]] && [[ "$region" == "CN" ]]; }; then
      echo "cos"
    else
      echo "oos"
    fi
    return
  fi
  echo "oos"
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
#       Inputs / Paths
# -----------------------------

dev_raw="$DEV"
if [[ "$dev_raw" =~ (Ace6T|Ace6|Ace5Pro|Ace5|13T|13S|13R|13|15R|Pad3) ]]; then
  dev="${BASH_REMATCH[1]}"
else
  dev="${dev_raw%% *}"
fi
ftype="$FTYPE"
region="$REGION"
root="$GITHUB_WORKSPACE"

echo "DEVICE='$dev' • FLASHER TYPE='$ftype' • REGION='$region'"

script_dev="$dev"
[[ "$dev" == "Ace5Pro" || "$dev" == "Ace5" ]] && script_dev="Ace5"

builder_dir="$root/build_scripts/$script_dev"
bloat_base="$root/bloat/$script_dev"

rm -rf "$OUT_DIR" || true
mkdir -p "$OUT_DIR"

# -----------------------------
#        Add otaripper
# -----------------------------
echo "Adding Otaripper"
[ -f "$root/otaripper/otaripper" ] && cp -f "$root/otaripper/otaripper" "$OUT_DIR/" && chmod +x "$OUT_DIR/otaripper"
[ -n "${BUILDER_SH:-}" ] && [ -f "$builder_dir/$BUILDER_SH" ] && cp -f "$builder_dir/$BUILDER_SH" "$OUT_DIR/" && chmod +x "$OUT_DIR/$BUILDER_SH"

# -----------------------------
#        Working folder
# -----------------------------
echo "Calculating Working Folder"
case "$ftype" in
  "SuperHybrid Flasher")
    [[ "$dev" == "13" && "$region" == "CN" ]] && work_name="SuperHybrid Flasher CN" || work_name="SuperHybrid Flasher"
    ;;
  "SuperHybrid Flasher")
    [[ "$dev" == "15" && "$region" == "CN" ]] && work_name="SuperHybrid Flasher CN" || work_name="SuperHybrid Flasher"
    ;;
  "RegionalHybrid Flasher")
    [[ "$region" == "CN" ]] && work_name="RegionalHybrid Flasher CN" || work_name="RegionalHybrid Flasher"
    ;;
  "Super Flasher")
    { [[ "$dev" == "13R" || "$dev" == "13T" || "$dev" == "Ace5" || "$dev" == "Ace6" || "$dev" == "Ace6T" || "$dev" == "15R" || "$dev" == "Pad3" ]] && [[ "$region" == "CN" ]]; } && work_name="Super Flasher CN" || work_name="Super Flasher"
    ;;
  "Regional Flasher")
    { [[ "$dev" == "13R" || "$dev" == "Ace5" || "$dev" == "Ace5Pro" ]] && [[ "$region" == "CN" ]]; } && work_name="Regional Flasher CN" || work_name="Regional Flasher"
    ;;
  *) work_name="$ftype" ;;
esac

work_dir="$OUT_DIR/$work_name"
mkdir -p "$work_dir"

tpl_dev="$dev"
[[ "$dev" == "Ace5" || "$dev" == "Ace5Pro" ]] && tpl_dev="Ace5"

os_sub="$(get_os_subtree "$dev" "$ftype" "$region")"
kind="$([[ "$ftype" == *Super* ]] && echo "super" || echo "regional")"
tpl_base="$root/flasher_scripts/$tpl_dev/$os_sub/$kind"

[[ "$dev" == "Ace5Pro" && "$ftype" == "Regional Flasher" && "$region" == "CN" ]] && tpl_base="$root/flasher_scripts/Ace5/cos/regional"

echo "Using flasher_script: $tpl_base"
[ ! -d "$tpl_base" ] && echo "ERROR: Flasher template not found: $tpl_base (dev=$dev, ftype=$ftype, region=$region)" >&2 && exit 1

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

  if [[ "$region" == "CN" ]]; then
    packer="super_cos.sh"
  else
    packer="super_oos.sh"
  fi

  # -----------------------------
  #      Super: Packer path
  # -----------------------------

  pdir="$root/super_packers/$dev"
  script="$pdir/$packer"

  if [[ -f "$script" ]]; then
    cp -f "$script" "$super_dir/$packer"
    chmod +x "$super_dir/$packer"
    echo "Using super_packer: $script"
  else
    echo "ERROR: Missing $packer for $dev at $script" >&2
    exit 1
  fi

  # -----------------------------
  #          Super: BLOAT
  # -----------------------------

  bloat_folder="$(get_bloat_folder "$dev" "$region")"
  echo "Adding bloat"

  if [[ "$dev" == "13T" && "$ftype" == "Super Flasher" && "$region" == "IN" ]]; then
    copy_bloat_from_folder "$bloat_base" "$bloat_folder" "$super_dir" "my_region.img" "oplusstanvbk.img" "odm.img"
    cos_here="$work_dir/COS_FILES_HERE"
    mkdir -p "$cos_here"
    in_bloat="$bloat_base/IN_BLOAT"
    for f in my_region oplusstanvbk odm; do copy_or_download "$in_bloat" "$f" "$cos_here/$f.img"; done
    for f in my_region.img oplusstanvbk.img odm.img; do [ -f "$super_dir/$f" ] && rm -f "$super_dir/$f"; done
  else
    copy_bloat_from_folder "$bloat_base" "$bloat_folder" "$super_dir"
  fi

  # -----------------------------
  # OP13 Signal-Fix (SuperHybrid)
  # -----------------------------

  if [[ "$dev" == "13" && "$ftype" == "SuperHybrid Flasher" && "$region" != "CN" ]]; then
    repo_cos="$root/bloat/13/COS_FILES_HERE"
    cos_here="$work_dir/COS_FILES_HERE"

    echo "Adding OP13 Signal-fix files: $repo_cos → $cos_here"

    if [[ -d "$repo_cos" ]]; then
      mkdir -p "$cos_here"
      for f in my_region.img oplusstanvbk.img; do
        [[ -f "$repo_cos/$f" ]] && cp -f "$repo_cos/$f" "$cos_here/"
      done
    else
      echo "WARN: Signal-fix folder not found: $repo_cos"
    fi
  fi
fi



# -----------------------------
# CN DEBLOAT (my_preload ONLY)
# -----------------------------

if [[ "$region" == "CN" ]]; then
  oos_here="$work_dir/OOS_FILES_HERE"
  mkdir -p "$oos_here"

  case "$dev" in
    13|13T|15|Ace5|Ace5Pro|Ace6|Ace6T)
      preload_dir="$bloat_base/GLO_BLOAT"
      echo "CN debloat: Copying my_preload from $preload_dir → $oos_here"
      copy_or_download "$preload_dir" "my_preload" "$oos_here/my_preload.img"
      ;;
  esac
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

    bloat_folder_oos="$(
      [[ "$dev" == "13" && "$ftype" == "RegionalHybrid Flasher" ]] \
        && echo "EUGLO_BLOAT" \
        || get_bloat_folder "$dev" "$region"
    )"

    skip_oos=()
    [[ "$ftype" == "RegionalHybrid Flasher" ]] \
      && skip_oos=("odm.img" "oplusstanvbk.img" "my_region.img")

    copy_bloat_from_folder "$bloat_base" "$bloat_folder_oos" "$oos_here" "${skip_oos[@]}"
  fi

  # -----------------------------
  #         ColorOS BLOAT
  # -----------------------------
  if [[ "$region" == "CN" ]]; then
    cos_here="$work_dir/COS_FILES_HERE"
    mkdir -p "$cos_here"

    case "$dev" in
      Ace5Pro)
        bloat_folder_cos="A5P_BLOAT"
        ;;
      13)
        if [[ "$ftype" == "RegionalHybrid Flasher" ]]; then
          bloat_folder_cos="CN_BLOAT"
          skip_cos=("odm.img" "oplusstanvbk.img" "my_region.img")
        else
          bloat_folder_cos="CN_BLOAT"
          skip_cos=()
        fi
        ;;
      *)
        bloat_folder_cos="CN_BLOAT"
        skip_cos=()
        ;;
    esac

    copy_bloat_from_folder "$bloat_base" "$bloat_folder_cos" "$cos_here" "${skip_cos[@]:-}"
  fi
fi

# ----------------------------
#  OnePlus 13 + Hybrid extras
# ----------------------------

if [[ "$dev" == "13" && ( "$ftype" == "SuperHybrid Flasher" || "$ftype" == "RegionalHybrid Flasher" ) ]]; then
  work16="$work_dir/16DTBO"
  [ -d "$work16" ] && { rm -rf "$main16"; mv "$work16" "$main16"; echo "Moved stray 16DTBO from working folder to MAIN."; }
  [[ "$region" == "CN" && "$ftype" == "SuperHybrid Flasher" ]] && [ -d "$work_dir/COS_FILES_HERE" ] && echo "Removing stray COS_FILES_HERE for 13 SuperHybrid CN..." && rm -rf "$work_dir/COS_FILES_HERE"
fi

# Expose for next steps
echo "WORK_DIR=$work_dir" >> "$GITHUB_ENV"


