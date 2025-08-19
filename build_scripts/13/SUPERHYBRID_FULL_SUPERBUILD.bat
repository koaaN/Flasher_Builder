@echo off
setlocal EnableExtensions EnableDelayedExpansion

echo ==========================================================
echo   SUPERHYBRID FULL SUPERBUILD  (Dry-Run Compatible)
echo ==========================================================

:: ------------------------------------------------------------
:: 1) INPUT (drag & drop OTA.zip OR dry-run if none provided)
:: ------------------------------------------------------------
if "%~1"=="" (
  echo [INFO] No OTA zip provided. Running in DRY-RUN mode...
  set "input_file=DUMMY_OTA.zip"
  set "input_dir=%~dp0DUMMY_OTA"
  if not exist "%input_dir%" mkdir "%input_dir%"
) else (
  set "input_file=%~1"
  set "input_dir=%~dp1"
)

set "self_dir=%~dp0"
set "flasher_src=%self_dir%SuperHybrid Flasher"
set "flasher_dest=%input_dir%SuperHybrid Flasher"

if not exist "%flasher_src%" (
  echo [ERROR] Template not found: "%flasher_src%"
  exit /b 1
)

:: ------------------------------------------------------------
:: 2) Locate otaripper.exe (only required when not dry-run)
:: ------------------------------------------------------------
set "otaripper="
for %%P in (
  "%self_dir%otaripper.exe"
  "%self_dir%otaripper\otaripper.exe"
  "%self_dir%..\otaripper\otaripper.exe"
) do (
  if exist "%%~fP" set "otaripper=%%~fP"
)

if not defined otaripper (
  for /f "delims=" %%A in ('where otaripper.exe 2^>nul') do (
    if not defined otaripper set "otaripper=%%~fA"
  )
)

if /I not "%input_file%"=="DUMMY_OTA.zip" if not defined otaripper (
  echo [ERROR] Could not find otaripper.exe near this script or on PATH.
  echo         Checked:
  echo           "%self_dir%otaripper.exe"
  echo           "%self_dir%otaripper\otaripper.exe"
  echo           "%self_dir%..\otaripper\otaripper.exe"
  exit /b 1
)

echo [INFO] OTA file : "%input_file%"
echo [INFO] OTA dir  : "%input_dir%"
echo [INFO] Builder  : "%~nx0"
if defined otaripper echo [INFO] Ripper   : "%otaripper%"
echo [INFO] Template : "%flasher_src%"
echo.

:: ------------------------------------------------------------
:: 3) Copy template into the OTA directory
:: ------------------------------------------------------------
echo [STEP] Copy template -> "%flasher_dest%"
if exist "%flasher_dest%" rmdir /s /q "%flasher_dest%"
xcopy "%flasher_src%" "%flasher_dest%" /E /I /Y >nul
if errorlevel 1 (
  echo [ERROR] Failed to copy template.
  exit /b 1
)

:: ------------------------------------------------------------
:: 4) Extract OTA (skipped in dry-run). Detect new folder safely.
:: ------------------------------------------------------------
set "new_folder="

if /I "%input_file%"=="DUMMY_OTA.zip" (
  echo [INFO] Skipping extraction (dry-run).
) else (
  set "tmp_before=%temp%\before_%random%%random%.lst"
  set "tmp_after=%temp%\after_%random%%random%.lst"
  dir /b /ad "%input_dir%" > "%tmp_before%"

  echo [STEP] Extracting OTA with otaripper...
  pushd "%input_dir%" >nul
  "%otaripper%" "%input_file%"
  set "rip_rc=%errorlevel%"
  popd >nul
  if not "%rip_rc%"=="0" (
    echo [ERROR] otaripper failed with code %rip_rc%.
    if exist "%tmp_before%" del "%tmp_before%" >nul 2>&1
    exit /b %rip_rc%
  )

  dir /b /ad "%input_dir%" > "%tmp_after%"

  for /f "usebackq delims=" %%N in ("%tmp_after%") do (
    findstr /ix "%%N" "%tmp_before%" >nul || (
      set "new_folder=%input_dir%%%N"
    )
  )

  if exist "%tmp_before%" del "%tmp_before%" >nul 2>&1
  if exist "%tmp_after%"  del "%tmp_after%"  >nul 2>&1

  if not defined new_folder (
    echo [ERROR] Could not detect extracted folder.
    exit /b 1
  )
  echo [INFO] Detected extracted folder: "%new_folder%"
)

:: ------------------------------------------------------------
:: 5) Organize files (selected partitions -> \super, rest -> \OOS_FILES_HERE)
:: ------------------------------------------------------------
if not exist "%flasher_dest%\super" md "%flasher_dest%\super"
if not exist "%flasher_dest%\OOS_FILES_HERE" md "%flasher_dest%\OOS_FILES_HERE"

if defined new_folder (
  echo [STEP] Moving logical partitions -> "super\"
  for %%F in (
    my_bigball.img my_carrier.img my_engineering.img my_heytap.img
    my_manifest.img my_product.img my_region.img my_stock.img
    odm.img product.img system.img system_dlkm.img system_ext.img
    vendor.img vendor_dlkm.img
  ) do (
    if exist "%new_folder%\%%F" move /Y "%new_folder%\%%F" "%flasher_dest%\super\" >nul
  )

  echo [STEP] Moving remaining files -> "OOS_FILES_HERE\"
  move /Y "%new_folder%\*" "%flasher_dest%\OOS_FILES_HERE\" >nul
  rd /s /q "%new_folder%" 2>nul
) else (
  echo [INFO] Dry-run: created empty "super\" and "OOS_FILES_HERE\" to verify layout.
)

:: ------------------------------------------------------------
:: 6) dtbo: patch in root, then replace OTA dtbo with 16DTBO\dtbo.img (if present)
:: ------------------------------------------------------------
echo [STEP] Handling dtbo.img...
if exist "%flasher_dest%\OOS_FILES_HERE\dtbo.img" (
  copy /Y "%flasher_dest%\OOS_FILES_HERE\dtbo.img" "%flasher_dest%" >nul
  if exist "%flasher_dest%\dtbo_patcher.bat" (
    echo [STEP] Patching dtbo.img ...
    call "%flasher_dest%\dtbo_patcher.bat"
  ) else (
    echo [WARN] dtbo_patcher.bat not found in flasher root; skipping patch.
  )
) else (
  echo [WARN] No dtbo.img in OOS_FILES_HERE; skipping patch.
)

if exist "%self_dir%16DTBO\dtbo.img" (
  echo [STEP] Replacing "OOS_FILES_HERE\dtbo.img" with "16DTBO\dtbo.img" ...
  copy /Y "%self_dir%16DTBO\dtbo.img" "%flasher_dest%\OOS_FILES_HERE\" >nul
) else (
  echo [WARN] "%self_dir%16DTBO\dtbo.img" not found; leaving OTA dtbo as-is.
)

:: ------------------------------------------------------------
:: 7) Build super.img
:: ------------------------------------------------------------
echo [STEP] Packing super.img...
if exist "%flasher_dest%\Super\super.bat" (
  pushd "%flasher_dest%\Super" >nul
  call "super.bat"
  set "super_rc=%errorlevel%"
  popd >nul
  if not "%super_rc%"=="0" (
    echo [ERROR] super.bat failed with code %super_rc%.
    exit /b %super_rc%
  )
  if exist "%flasher_dest%\Super\super.img" (
    echo [STEP] Moving super.img into flasher root ...
    move /Y "%flasher_dest%\Super\super.img" "%flasher_dest%\" >nul
  ) else (
    echo [WARN] super.img not found after packing.
  )
) else (
  echo [WARN] "%flasher_dest%\Super\super.bat" not found; skipping super image packing.
)

:: ------------------------------------------------------------
:: 8) Cleanup temporary items
:: ------------------------------------------------------------
echo [STEP] Cleaning temporary files...
if exist "%flasher_dest%\Super" rmdir /S /Q "%flasher_dest%\Super"
if exist "%flasher_dest%\dtbo.img" del /F /Q "%flasher_dest%\dtbo.img"
if exist "%flasher_dest%\dtbo_patcher.bat" del /F /Q "%flasher_dest%\dtbo_patcher.bat"

echo.
echo ==========================================================
echo   BUILD DONE!  (Dry-run OK if no OTA was given)
echo ==========================================================
if /I "%PAUSE_AFTER%"=="1" pause
exit /b 0