@echo off
setlocal EnableExtensions EnableDelayedExpansion

:: ==========================================================
:: SUPERHYBRID FULL SUPER BUILD (NO bloat copying here)
:: - Detects otaripper.exe near the script or on PATH
:: - Copies "SuperHybrid Flasher" template into OTA dir
:: - Extracts OTA, moves logical partitions to \super
:: - Moves everything else to \OOS_FILES_HERE
:: - Patches dtbo.img, then replaces OTA dtbo with 16DTBO\dtbo.img
:: - Calls Super\super.bat, moves super.img up, cleans scrap
:: ==========================================================

:: ----- Validate arg -----
if not exist "%~1" (
  echo [ERROR] Usage: %~nx0 "FULL\PATH\TO\OTA.zip"
  exit /b 1
)

:: ----- Inputs / base paths -----
set "input_file=%~1"
set "input_dir=%~dp1"
set "self_dir=%~dp0"

set "flasher_src=%self_dir%SuperHybrid Flasher"
set "flasher_dest=%input_dir%SuperHybrid Flasher"

if not exist "%flasher_src%" (
  echo [ERROR] Template not found: "%flasher_src%"
  exit /b 1
)

:: ----- Locate otaripper.exe -----
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

if not defined otaripper (
  echo [ERROR] Could not find otaripper.exe near this script or on PATH.
  echo         Checked:
  echo           %self_dir%otaripper.exe
  echo           %self_dir%otaripper\otaripper.exe
  echo           %self_dir%..\otaripper\otaripper.exe
  exit /b 1
)

echo [INFO] OTA file : "%input_file%"
echo [INFO] OTA dir  : "%input_dir%"
echo [INFO] Builder  : "%~nx0"
echo [INFO] Ripper   : "%otaripper%"
echo [INFO] Template : "%flasher_src%"
echo.

:: ----- Copy template into the OTA folder -----
echo [STEP] Copy template to "%flasher_dest%"
if exist "%flasher_dest%" rmdir /s /q "%flasher_dest%"
xcopy "%flasher_src%" "%flasher_dest%" /E /I /Y >nul
if errorlevel 1 (
  echo [ERROR] Failed to copy template.
  exit /b 1
)

:: ----- Snapshot directories before extraction -----
set "before_list="
for /d %%D in ("%input_dir%*") do (
  set "before_list=!before_list! %%~nxD"
)

:: ----- Extract OTA (no --partitions) -----
echo [STEP] Extracting OTA with otaripper...
pushd "%input_dir%" >nul
"%otaripper%" "%input_file%"
set "rip_rc=%errorlevel%"
popd >nul
if not "%rip_rc%"=="0" (
  echo [ERROR] otaripper failed with code %rip_rc%.
  exit /b %rip_rc%
)

:: ----- Detect newly created folder -----
set "new_folder="
for /d %%D in ("%input_dir%*") do (
  echo !before_list! | find " %%~nxD" >nul
  if errorlevel 1 (
    set "new_folder=%%~fD"
  )
)

if not defined new_folder (
  echo [ERROR] Could not detect extracted folder.
  exit /b 1
)
echo [INFO] Detected extracted folder: "!new_folder!"

:: ----- Ensure working subfolders -----
if not exist "%flasher_dest%\super" md "%flasher_dest%\super"
if not exist "%flasher_dest%\OOS_FILES_HERE" md "%flasher_dest%\OOS_FILES_HERE"

:: ----- Move selected logical partitions into \super -----
echo [STEP] Moving logical partitions into super\ ...
for %%F in (
  my_bigball.img my_carrier.img my_engineering.img my_heytap.img
  my_manifest.img my_product.img my_region.img my_stock.img
  odm.img product.img system.img system_dlkm.img system_ext.img
  vendor.img vendor_dlkm.img
) do (
  if exist "!new_folder!\%%F" move /Y "!new_folder!\%%F" "%flasher_dest%\super\" >nul
)

:: ----- Move remaining files to \OOS_FILES_HERE -----
echo [STEP] Moving remaining files into OOS_FILES_HERE\ ...
move /Y "!new_folder!\*" "%flasher_dest%\OOS_FILES_HERE\" >nul
rd /s /q "!new_folder!" 2>nul

:: ----- dtbo: copy, patch, then replace OTA dtbo with 16DTBO\dtbo.img -----
echo [STEP] Copying dtbo.img for patch...
if exist "%flasher_dest%\OOS_FILES_HERE\dtbo.img" (
  copy /Y "%flasher_dest%\OOS_FILES_HERE\dtbo.img" "%flasher_dest%" >nul
  if exist "%flasher_dest%\dtbo_patcher.bat" (
    echo [STEP] Patching dtbo.img ...
    call "%flasher_dest%\dtbo_patcher.bat"
  ) else (
    echo [WARN] dtbo_patcher.bat not found in flasher root; skipping patch.
  )
) else (
  echo [WARN] No dtbo.img found in OOS_FILES_HERE; skipping patch.
)

:: Replace OTA dtbo with known-good version if present
if exist "%self_dir%16DTBO\dtbo.img" (
  echo [STEP] Replacing OOS_FILES_HERE\dtbo.img with 16DTBO\dtbo.img ...
  copy /Y "%self_dir%16DTBO\dtbo.img" "%flasher_dest%\OOS_FILES_HERE\" >nul
) else (
  echo [WARN] %self_dir%16DTBO\dtbo.img not found; leaving OTA dtbo as-is.
)

:: ----- Build super.img -----
echo [STEP] Packing super.img ...
if exist "%flasher_dest%\Super\super.bat" (
  pushd "%flasher_dest%\Super" >nul
  call super.bat
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
  echo [WARN] Super\super.bat not found; skipping super image packing.
)

:: ----- Cleanup -----
echo [STEP] Cleaning up temporary files ...
if exist "%flasher_dest%\Super" rmdir /S /Q "%flasher_dest%\Super"
if exist "%flasher_dest%\dtbo.img" del /F /Q "%flasher_dest%\dtbo.img"
if exist "%flasher_dest%\dtbo_patcher.bat" del /F /Q "%flasher_dest%\dtbo_patcher.bat"

echo [DONE] SuperHybrid build staging complete.
if /I "%PAUSE_AFTER%"=="1" pause
exit /b 0