#!/usr/bin/env bash
set -euo pipefail

# Erwartet via Env: DEV, FTYPE, REGION, BUILDER_SH, OUT_DIR, GITHUB_WORKSPACE, OTA_PATH, OTA_DIR

# -----------------------------
# Helpers
# -----------------------------
copy_bloat_from_folder () {
  local base="$1" folder="$2" dest="$3"; shift 3 || true
  local skip_list=("$@")  # array of exact filenames to skip
  [ -n "${folder:-}" ] || return 0
  local src="${base}/${folder}"
  [ -d "$src" ] || return 0
  mkdir -p "$dest"
  local needed=( "my_preload.img" "my_company.img" "odm.img" "oplusstanvbk.img" "my_region.img" "system_dlkm_oki.img" "system_dlkm_gki.img" )
  for f in "${needed[@]}"; do
    local skip=0
    for s in "${skip_list[@]}"; do
      if [[ "$f" == "$s" ]]; then skip=1; break; fi
    done
    [ "$skip" -eq 1 ] && continue
    if [ -f "$src/$f" ]; then
      cp -f "$src/$f" "$dest/"
      continue
    fi
    local stub="$src/${f%.img}"
    if [ -f "$stub" ]; then
      local url; url="$(tr -d '\r' < "$stub" | xargs || true)"
      if [ -n "$url" ]; then
        echo "Downloading $f from $url"
        curl -L --fail --retry 3 --retry-delay 5 -o "$dest/$f" "$url" || echo "WARN: download failed for $f"
      fi
    fi
  done
}

copy_debloat_pair () {
  local debloat_dir="$1" dest="$2"
  [ -d "$debloat_dir" ] || return 0
  mkdir -p "$dest"
  # my_company.img + my_preload.img (stub allowed for my_preload)
  for f in "my_company.img" "my_preload.img"; do
    if [ -f "$debloat_dir/$f" ]; then
      cp -f "$debloat_dir/$f" "$dest/"
    else
      local stub="$debloat_dir/${f%.img}"
      if [ -f "$stub" ]; then
        local url; url="$(tr -d '\r' < "$stub" | xargs || true)"
        if [ -n "$url" ]; then
          echo "Downloading $f from $url"
          curl -L --fail --retry 3 --retry-delay 5 -o "$dest/$f" "$url" || echo "WARN: download failed for $f"
        fi
      fi
    fi
  done
}

normalize_updater_script_lf () {
  local meta_root="$1"
  local up="$meta_root/com/google/android/updater-script"
  [ -f "$up" ] || return 0
  awk '{ sub(/\r$/,""); print }' "$up" > "$up.tmp" && mv "$up.tmp" "$up"
}

get_bloat_folder () {
  # args: dev region
  local dev="$1" region="$2"
  case "$dev" in
    "Ace5")
      case "$region" in
        CN) echo "CN_BLOAT" ;;
        EU|GLO) echo "EUGLO_BLOAT" ;;
        IN) echo "IN_BLOAT" ;;
        NA) echo "NA_BLOAT" ;;
        *) echo "" ;;
      esac
    ;;
    "Ace5Pro")
      if [[ "$region" == "CN" ]]; then echo "A5P_BLOAT"; else echo ""; fi
    ;;
    "15")
      case "$region" in
        CN) echo "CN_BLOAT" ;;
        EU) echo "EU_BLOAT" ;;
        GLO) echo "GLO_BLOAT" ;;
        IN) echo "IN_BLOAT" ;;
        *) echo "" ;;
      esac
    ;;
    "Pad3")
      case "$region" in
        EU) echo "EU_BLOAT" ;;
        GLO) echo "GLO_BLOAT" ;;
        IN) echo "IN_BLOAT" ;;
        *) echo "" ;;
      esac
    ;;
    *)
      case "$region" in
        CN) echo "CN_BLOAT" ;;
        EU|GLO) echo "EUGLO_BLOAT" ;;
        IN) echo "IN_BLOAT" ;;
        NA) echo "NA_BLOAT" ;;
        *) echo "" ;;
      esac
    ;;
  esac
}

get_os_subtree () {
  # args: dev ftype region -> prints 'oos' or 'cos'
  local dev="$1" ftype="$2" region="$3"
  if [[ "$ftype" == *Hybrid* ]]; then
    if [[ "$region" == "CN" ]]; then echo "cos"; else echo "oos"; fi
    return
  fi
  if [[ "$ftype" == "Regional Flasher" ]]; then
    if [[ "$region" == "CN" ]]; then echo "cos"; else echo "oos"; fi
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

copy_or_download () {
  local dir="$1" base="$2" dest="$3"
  if [ -f "$dir/${base}.img" ]; then
    cp -f "$dir/${base}.img" "$dest"
  else
    local stub="$dir/${base}"
    if [ -f "$stub" ]; then
      local url; url="$(tr -d '\r' < "$stub" | xargs || true)"
      if [ -n "$url" ]; then
        echo "Downloading ${base}.img from $url"
        curl -L --fail --retry 3 --retry-delay 5 -o "$dest" "$url" || echo "WARN: download failed for ${base}.img"
      fi
    fi
  fi
}

# -----------------------------
# Inputs / paths
# -----------------------------
dev_raw="$DEV"
# normalize device like Jonas: first matching token
if [[ "$dev_raw" =~ (Ace6T|Ace6|Ace5Pro|Ace5|13T|13S|13R|13|15R|Pad3) ]]; then
  dev="${BASH_REMATCH[1]}"
else
  dev="${dev_raw%% *}"
fi

ftype="$FTYPE"
region="$REGION"
root="$GITHUB_WORKSPACE"

echo "DEV(raw)='$dev_raw' → DEV(norm)='$dev' • FTYPE='$ftype' • REGION='$region'"

# Ace5Pro uses Ace5 trees
if [[ "$dev" == "Ace5Pro" || "$dev" == "Ace5" ]]; then
  script_dev="Ace5"
else
  script_dev="$dev"
fi

builder_dir="$root/build_scripts/$script_dev"
bloat_base="$root/bloat/$script_dev"

# Fresh OUT_DIR
rm -rf "$OUT_DIR" || true
mkdir -p "$OUT_DIR"

# Main folder: otaripper + builder .sh (Linux)
if [ -f "$root/otaripper/otaripper" ]; then
  cp -f "$root/otaripper/otaripper" "$OUT_DIR/"
  chmod +x "$OUT_DIR/otaripper"
fi
if [ -n "${BUILDER_SH:-}" ] && [ -f "$builder_dir/$BUILDER_SH" ]; then
  cp -f "$builder_dir/$BUILDER_SH" "$OUT_DIR/"
  chmod +x "$OUT_DIR/$BUILDER_SH"
fi

# Working folder name (CN variants where needed)
case "$ftype" in
  "SuperHybrid Flasher")
    if [[ "$dev" == "13" && "$region" == "CN" ]]; then work_name="SuperHybrid Flasher CN"; else work_name="SuperHybrid Flasher"; fi
  ;;
  "SuperHybrid Flasher")
    if [[ "$dev" == "15" && "$region" == "CN" ]]; then work_name="SuperHybrid Flasher CN"; else work_name="SuperHybrid Flasher"; fi
  ;;
  "RegionalHybrid Flasher")
    if [[ "$region" == "CN" ]]; then work_name="RegionalHybrid Flasher CN"; else work_name="RegionalHybrid Flasher"; fi
  ;;
  "Super Flasher")
    if { [[ "$dev" == "13R" || "$dev" == "13T" || "$dev" == "Ace5" || "$dev" == "Ace6" || "$dev" == "Ace6T" || "$dev" == "15R" || "$dev" == "Pad3" ]] && [[ "$region" == "CN" ]]; }; then
      work_name="Super Flasher CN"
    else
      work_name="Super Flasher"
    fi
  ;;
  "Regional Flasher")
    if { [[ "$dev" == "13R" || "$dev" == "Ace5" || "$dev" == "Ace5Pro" ]] && [[ "$region" == "CN" ]]; }; then
      work_name="Regional Flasher CN"
    else
      work_name="Regional Flasher"
    fi
  ;;
  *) work_name="$ftype" ;;
esac

work_dir="$OUT_DIR/$work_name"
mkdir -p "$work_dir"

# Template root selection
if [[ "$dev" == "Ace5" || "$dev" == "Ace5Pro" ]]; then
  tpl_dev="Ace5"
else
  tpl_dev="$dev"
fi

os_sub="$(get_os_subtree "$dev" "$ftype" "$region")"
kind="$([[ "$ftype" == *Super* ]] && echo "super" || echo "regional")"
tpl_base="$root/flasher_scripts/$tpl_dev/$os_sub/$kind"

# Ace5Pro • Regional Flasher • CN → force Ace5\cos\regional
if [[ "$dev" == "Ace5Pro" && "$ftype" == "Regional Flasher" && "$region" == "CN" ]]; then
  tpl_base="$root/flasher_scripts/Ace5/cos/regional"
fi

echo "Using flasher template: $tpl_base"
if [ ! -d "$tpl_base" ]; then
  echo "ERROR: Flasher template not found: $tpl_base (dev=$dev, ftype=$ftype, region=$region)" >&2
  exit 1
fi

# -----------------------------
# Generic (non-SunOS) copy template
# -----------------------------
rsync -a "$tpl_base/" "$work_dir/"

# HYBRID ONLY: ensure META-INF + LF normalize
if [[ "$ftype" == *Hybrid* ]]; then
  mi="$tpl_base/META-INF"
  if [ -d "$mi" ]; then
    if [ ! -d "$work_dir/META-INF" ]; then
      mkdir -p "$work_dir/META-INF"
      rsync -a "$mi/" "$work_dir/META-INF/"
    else
      echo "META-INF already present in $work_dir - skipping duplicate copy."
    fi
    normalize_updater_script_lf "$work_dir/META-INF"
  fi
fi

# ALWAYS copy Platform-Tools into flasher dir
pt_src="$root/Platform-Tools"
if [ -d "$pt_src" ]; then
  mkdir -p "$work_dir/Platform-Tools"
  rsync -a "$pt_src/" "$work_dir/Platform-Tools/"
else
  echo "WARN: Platform-Tools not found at repo root: $pt_src"
fi

# -----------------------------
# Super builds
# -----------------------------
if [[ "$ftype" =~ Super ]]; then
  super_dir="$work_dir/Super"
  mkdir -p "$super_dir"
  # lpmake (linux)
  if [ -f "$root/lpmake/lpmake" ]; then
    cp -f "$root/lpmake/lpmake" "$super_dir/"
    chmod +x "$super_dir/lpmake"
  fi

  # Packer scripts (existing logic)
  if [[ "$dev" == "13" ]]; then
    pdir="$root/super_packers/13"
    if [[ "$region" == "CN" && "$ftype" == "SuperHybrid Flasher" && -f "$pdir/super_cos.sh" ]]; then
      cp -f "$pdir/super_cos.sh" "$super_dir/super_cos.sh"; chmod +x "$super_dir/super_cos.sh"
    elif [[ -f "$pdir/super_oos.sh" ]]; then
      cp -f "$pdir/super_oos.sh" "$super_dir/super_oos.sh"; chmod +x "$super_dir/super_oos.sh"
    fi
  elif [[ "$dev" == "13T" ]]; then
    pdir="$root/super_packers/13T"
    if [[ "$region" == "CN" && -f "$pdir/super_cos.sh" ]]; then
      cp -f "$pdir/super_cos.sh" "$super_dir/super_cos.sh"; chmod +x "$super_dir/super_cos.sh"
    elif [[ -f "$pdir/super_oos.sh" ]]; then
      cp -f "$pdir/super_oos.sh" "$super_dir/super_oos.sh"; chmod +x "$super_dir/super_oos.sh"
    fi
  elif [[ "$dev" == "Ace5" ]]; then
    pdir="$root/super_packers/Ace5"
    if [[ "$region" == "CN" && -f "$pdir/super_cos.sh" ]]; then
      cp -f "$pdir/super_cos.sh" "$super_dir/super_cos.sh"; chmod +x "$super_dir/super_cos.sh"
    elif [[ -f "$pdir/super_oos.sh" ]]; then
      cp -f "$pdir/super_oos.sh" "$super_dir/super_oos.sh"; chmod +x "$super_dir/super_oos.sh"
    fi
  else
    p="$root/super_packers/$dev/super_oos.sh"
    [ -f "$p" ] && cp -f "$p" "$super_dir/super_oos.sh" && chmod +x "$super_dir/super_oos.sh"
  fi

  # Standard bloat into Super/
  bloat_folder="$(get_bloat_folder "$dev" "$region")"

  if [[ "$dev" == "13T" && "$ftype" == "Super Flasher" && "$region" == "IN" ]]; then
    # Copy all except 3 specific files into Super/
    copy_bloat_from_folder "$bloat_base" "$bloat_folder" "$super_dir" "my_region.img" "oplusstanvbk.img" "odm.img"
    # Then ensure the 3 go into COS_FILES_HERE
    cos_here="$work_dir/COS_FILES_HERE"
    mkdir -p "$cos_here"
    in_bloat="$bloat_base/IN_BLOAT"
    copy_or_download "$in_bloat" "my_region" "$cos_here/my_region.img"
    copy_or_download "$in_bloat" "oplusstanvbk" "$cos_here/oplusstanvbk.img"
    copy_or_download "$in_bloat" "odm" "$cos_here/odm.img"
    # Remove if accidentally landed in Super/
    for f in my_region.img oplusstanvbk.img odm.img; do
      [ -f "$super_dir/$f" ] && rm -f "$super_dir/$f"
    done
  else
    copy_bloat_from_folder "$bloat_base" "$bloat_folder" "$super_dir"
  fi

  # OP13 • SuperHybrid • non-CN → copy my_region & oplusstanvbk to COS_FILES_HERE
  if [[ "$dev" == "13" && "$ftype" == "SuperHybrid Flasher" && "$region" != "CN" ]]; then
    repo_cos="$root/bloat/13/COS_FILES_HERE"
    if [[ -d "$repo_cos" ]]; then
      cos_here="$work_dir/COS_FILES_HERE"
      mkdir -p "$cos_here"
      for f in my_region.img oplusstanvbk.img; do
        src="$repo_cos/$f"
        if [[ -f "$src" ]]; then
          cp -f "$src" "$cos_here/"
        else
          echo "WARN: wanted $f in $repo_cos but not found"
        fi
      done
    else
      echo "WARN: repo COS_FILES_HERE not found: $repo_cos"
    fi
  fi

  # CN extra OOS staging
  if [[ "$region" == "CN" ]]; then
    if [[ "$dev" == "13" && "$ftype" == "SuperHybrid Flasher" ]]; then
      oos_here="$work_dir/OOS_FILES_HERE"
      mkdir -p "$oos_here"
      copy_bloat_from_folder "$bloat_base" "EUGLO_BLOAT" "$oos_here"

    elif [[ "$dev" == "15" && "$ftype" == "SuperHybrid Flasher" ]]; then
      oos_here="$work_dir/OOS_FILES_HERE"
      mkdir -p "$oos_here"
      special_dir="$bloat_base/CN_BLOAT/OOS_FILES_HERE"
      copy_or_download "$special_dir" "my_preload" "$oos_here/my_preload.img"

    elif [[ ( "$dev" == "Ace6" || "$dev" == "Ace6T" ) && "$ftype" == "Super Flasher" ]]; then
      oos_here="$work_dir/OOS_FILES_HERE"
      mkdir -p "$oos_here"
      special_dir="$bloat_base/CN_BLOAT/OOS_FILES_HERE"
      copy_or_download "$special_dir" "my_preload" "$oos_here/my_preload.img"

    elif [[ "$dev" != "Ace5" && "$dev" != "Ace5Pro" ]]; then
      oos_here="$work_dir/OOS_FILES_HERE"
      mkdir -p "$oos_here"
      if [[ "$dev" == "13R" ]]; then
        copy_bloat_from_folder "$bloat_base" "A5_DEBLOAT" "$oos_here"
      else
        copy_bloat_from_folder "$bloat_base" "EUGLO_BLOAT" "$oos_here"
      fi
    fi
  fi

  # Ace5 CN: put A5_DEBLOAT pair into OOS_FILES_HERE
  if [[ "$dev" == "Ace5" && "$region" == "CN" ]]; then
    oos_here="$work_dir/OOS_FILES_HERE"
    mkdir -p "$oos_here"
    copy_debloat_pair "$bloat_base/A5_DEBLOAT" "$oos_here"
  fi
fi

# -----------------------------
# Regional / RegionalHybrid builds
# -----------------------------
if [[ "$ftype" == "Regional Flasher" || "$ftype" == "RegionalHybrid Flasher" ]]; then
  oos_here="$work_dir/OOS_FILES_HERE"
  mkdir -p "$oos_here"

  # Decide OOS bloat source
  if [[ "$dev" == "13" && "$ftype" == "RegionalHybrid Flasher" && "$region" == "CN" ]]; then
    bloat_folder_oos="EUGLO_BLOAT"
  else
    bloat_folder_oos="$(get_bloat_folder "$dev" "$region")"
  fi

  # For RegionalHybrid (non-CN), skip these files in OOS
  skip_oos=()
  if [[ "$ftype" == "RegionalHybrid Flasher" && "$region" =~ ^(GLO|EU|IN|NA)$ ]]; then
    skip_oos=("odm.img" "oplusstanvbk.img" "my_region.img")
  fi

  copy_bloat_from_folder "$bloat_base" "$bloat_folder_oos" "$oos_here" "${skip_oos[@]:-}"

  # COS side (only for CN regions)
  if [[ "$region" == "CN" ]]; then
    cos_here="$work_dir/COS_FILES_HERE"
    mkdir -p "$cos_here"
    if [[ "$dev" == "Ace5Pro" ]]; then
      copy_bloat_from_folder "$bloat_base" "A5P_BLOAT" "$cos_here"
    elif [[ "$dev" == "13" && "$ftype" == "RegionalHybrid Flasher" ]]; then
      copy_bloat_from_folder "$bloat_base" "CN_BLOAT" "$cos_here" "odm.img" "oplusstanvbk.img" "my_region.img"
    else
      copy_bloat_from_folder "$bloat_base" "CN_BLOAT" "$cos_here"
    fi
  fi

  # 13S + Regional IN: ensure two files in OOS_FILES_HERE
  if [[ "$dev" == "13S" && "$region" == "IN" ]]; then
    for f in my_preload.img my_company.img; do
      [ -f "$bloat_base/IN_BLOAT/$f" ] && cp -f "$bloat_base/IN_BLOAT/$f" "$oos_here/"
    done
  fi

  # Ace5 CN: A5_DEBLOAT pair into OOS_FILES_HERE
  if [[ "$dev" == "Ace5" && "$region" == "CN" ]]; then
    copy_debloat_pair "$bloat_base/A5_DEBLOAT" "$oos_here"
  fi
  # Ace5Pro CN: A5P_DEBLOAT pair into OOS_FILES_HERE
  if [[ "$dev" == "Ace5Pro" && "$region" == "CN" ]]; then
    copy_debloat_pair "$bloat_base/A5P_DEBLOAT" "$oos_here"
  fi
fi

# -----------------------------
# OnePlus 13 + Hybrid extras (SuperHybrid + RegionalHybrid)
# -----------------------------
if [[ "$dev" == "13" && ( "$ftype" == "SuperHybrid Flasher" || "$ftype" == "RegionalHybrid Flasher" ) ]]; then
  # If template dropped 16DTBO inside working dir, move up
  work16="$work_dir/16DTBO"
  if [ -d "$work16" ]; then
    rm -rf "$main16"
    mv "$work16" "$main16"
    echo "Moved stray 16DTBO from working folder to MAIN."
  fi

  # IMPORTANT: For 13 SuperHybrid CN, do NOT stage COS files here (ensure removed)
  if [[ "$region" == "CN" && "$ftype" == "SuperHybrid Flasher" ]]; then
    cos_folder="$work_dir/COS_FILES_HERE"
    if [ -d "$cos_folder" ]; then
      echo "Removing stray COS_FILES_HERE for 13 SuperHybrid CN..."
      rm -rf "$cos_folder"
    fi
  fi
fi

# Expose for next steps
echo "WORK_DIR=$work_dir" >> "$GITHUB_ENV"
