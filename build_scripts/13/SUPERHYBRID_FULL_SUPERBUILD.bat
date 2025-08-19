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
  set "dry_run=1"
  set "input_file=DUMMY_OTA.zip"
  set "input_dir=%~dp0DUMMY_OTA"
  if "%input_dir:~-1%"=="\" set "input_dir=%input_dir:~0,-1%"
  if not exist "%input_dir%" mkdir "%input_dir%"
) else (
  set "dry_run=0"
  set "input_file=%~1"
  set "input_dir=%~dp1"
  if "%input_dir:~-1%"=="\" set "input_dir=%input_dir:~0,-1%"
)

set "self_dir=%~dp0"
if "%self_dir:~-1%"=="\" set "self_dir=%self_dir:~0,-1%"

set "flasher_src=%self_dir%\SuperHybrid Flasher"
set "flasher_dest=%input_dir%\SuperHybrid Flasher"

:: Path to otaripper.exe
set "otaripper=%self_dir%\..\..\otaripper\otaripper.exe"

echo [INFO] Mode     : %dry_run% (1=dry-run, 0=real)
echo [INFO] OTA file : "%input_file%"
echo [INFO] OTA dir  : "%input_dir%\"
echo [INFO] Builder  : "%~nx0"
echo [INFO] Ripper   : "%otaripper%"
echo [INFO] Template : "%flasher_src%"
echo.

:: ------------------------------------------------------------
:: 2) Copy flasher template
:: ------------------------------------------------------------
echo [STEP] Copying flasher template...
echo [DEBUG] flasher_src: [%flasher_src%]
echo [DEBUG] flasher_dest: [%flasher_dest%]
if exist "%flasher_dest%" rmdir /s /q "%flasher_dest%"
xcopy "%flasher_src%" "%flasher_dest%" /E /I /Y >nul
if errorlevel 1 (
  echo [ERROR] Failed to copy flasher template.
  exit /b 1
)

:: ------------------------------------------------------------
:: 3) Extract OTA using otaripper
:: ------------------------------------------------------------
if "%dry_run%"=="1" (
  echo [INFO] Skipping OTA extraction (dry-run).
  goto :organize
)

echo [STEP] Extracting OTA using otaripper.exe...
pushd "%input_dir%" >nul
"%otaripper%" "%input_file%"
set "rip_rc=%errorlevel%"
popd >nul
if not "%rip_rc%"=="0" (
  echo Error:  otaripper failed with exit code %rip_rc%.
  exit /b %rip_rc%
)

:: Detect new folder
set "new_folder="
for /f "delims=" %%D in ('dir /b /ad "%input_dir%"') do (
  if not exist "%flasher_dest%\%%D" (
    set "new_folder=%input_dir%\%%D"
  )
)

if not defined new_folder (
  echo [ERROR] Could not detect extracted folder.
  exit /b 1
)

echo [INFO] Detected extracted folder: "%new_folder%"

:organize
:: ------------------------------------------------------------
:: 4) Organize files
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
  echo [INFO] Dry-run: created empty folders for layout.
)

:: ------------------------------------------------------------
:: 5) Handle dtbo patching and replacement
:: ------------------------------------------------------------
echo [STEP] Handling dtbo.img...
if exist "%flasher_dest%\OOS_FILES_HERE\dtbo.img" (
  copy /Y "%flasher_dest%\OOS_FILES_HERE\dtbo.img" "%flasher_dest%" >nul
  if exist "%flasher_dest%\dtbo_patcher.bat" (
    echo [STEP] Patching dtbo.img ...
    call "%flasher_dest%\dtbo_patcher.bat"
  ) else (
    echo [WARN] dtbo_patcher.bat not found; skipping patch.
  )
) else (
  echo [WARN] dtbo.img not found; skipping patch.
)

if exist "%self_dir%\..\..\16DTBO\dtbo.img" (
  echo [STEP] Replacing dtbo.img with 16DTBO version...
  copy /Y "%self_dir%\..\..\16DTBO\dtbo.img" "%flasher_dest%\OOS_FILES_HERE\" >nul
)

:: ------------------------------------------------------------
:: 6) Pack super.img using super_oos.bat
:: ------------------------------------------------------------
echo [STEP] Building super.img using super_oos.bat...
if exist "%flasher_dest%\Super\super_oos.bat" (
  pushd "%flasher_dest%\Super" >nul
  call "super_oos.bat"
  set "super_rc=%errorlevel%"
  popd >nul
  if not "%super_rc%"=="0" (
    echo [ERROR] super_oos.bat failed with code %super_rc%.
    exit /b %super_rc%
  )
  if exist "%flasher_dest%\Super\super.img" (
    echo [STEP] Moving super.img into flasher root ...
    move /Y "%flasher_dest%\Super\super.img" "%flasher_dest%\" >nul
  )
) else (
  echo [WARN] super_oos.bat not found in Super folder.
)

:: ------------------------------------------------------------
:: 7) Cleanup
:: ------------------------------------------------------------
echo [STEP] Cleaning temporary files...
if exist "%flasher_dest%\Super" rmdir /S /Q "%flasher_dest%\Super"
if exist "%flasher_dest%\dtbo.img" del /F /Q "%flasher_dest%\dtbo.img"
if exist "%flasher_dest%\dtbo_patcher.bat" del /F /Q "%flasher_dest%\dtbo_patcher.bat"

echo.
echo ==========================================================
echo   BUILD DONE!  (Dry-run OK if no OTA was given)
echo ==========================================================
exit /b 0
