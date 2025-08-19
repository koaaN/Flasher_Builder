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
  if "%input_dir:~-1%"=="\" set "input_dir=%input_dir:~0,-1%"
  if not exist "%input_dir%" mkdir "%input_dir%"
  set "dryrun=1"
) else (
  set "input_file=%~1"
  set "input_dir=%~dp1"
  if "%input_dir:~-1%"=="\" set "input_dir=%input_dir:~0,-1%"
  set "dryrun=0"
)

set "self_dir=%~dp0"
if "%self_dir:~-1%"=="\" set "self_dir=%self_dir:~0,-1%"

set "flasher_src=%self_dir%\SuperHybrid Flasher"
set "flasher_dest=%input_dir%\SuperHybrid Flasher"
set "otaripper=%self_dir%\..\..\otaripper\otaripper.exe"

echo [INFO] Mode     : %dryrun% (1=dry-run, 0=real)
echo [INFO] OTA file : "%input_file%"
echo [INFO] OTA dir  : "%input_dir%\"
echo [INFO] Builder  : "%~nx0"
echo [INFO] Ripper   : "%otaripper%"
echo [INFO] Template : "%flasher_src%"
echo.

:: ------------------------------------------------------------
:: 2) Copy template to working dir
:: ------------------------------------------------------------
echo [STEP] Copying flasher template...
echo [DEBUG] flasher_src: [%flasher_src%]
echo [DEBUG] flasher_dest: [%flasher_dest%]

if exist "%flasher_dest%" rmdir /s /q "%flasher_dest%"
xcopy "%flasher_src%" "%flasher_dest%" /E /I /Y >nul
if errorlevel 1 (
  echo [ERROR] Failed to copy template.
  exit /b 1
)

:: ------------------------------------------------------------
:: 3) Extract OTA using otaripper (unless dry-run)
:: ------------------------------------------------------------
set "new_folder="

if "%dryrun%"=="1" (
  echo [INFO] Dry-run: Skipping otaripper extraction.
) else (
  if not exist "%otaripper%" (
    echo [ERROR] otaripper.exe not found at: %otaripper%
    exit /b 1
  )

  echo [STEP] Extracting OTA using otaripper.exe...
  for /f "delims=" %%B in ('dir /b /ad "%input_dir%"') do (
    set "before=!before! %%~nxB"
  )

  pushd "%input_dir%" >nul
  "%otaripper%" "%input_file%"
  set "rip_rc=%errorlevel%"
  popd >nul

  if not "%rip_rc%"=="0" (
    echo [ERROR] otaripper failed with exit code %rip_rc%.
    exit /b %rip_rc%
  )

  for /d %%D in ("%input_dir%\*") do (
    echo !before! | find " %%~nxD" >nul || set "new_folder=%%~fD"
  )

  if not defined new_folder (
    echo [ERROR] Could not detect new folder after OTA extraction.
    exit /b 1
  )
  echo [INFO] Detected extracted folder: %new_folder%
)

:: ------------------------------------------------------------
:: 4) Move selected .img to super, rest to OOS_FILES_HERE
:: ------------------------------------------------------------
if not exist "%flasher_dest%\super" mkdir "%flasher_dest%\super"
if not exist "%flasher_dest%\OOS_FILES_HERE" mkdir "%flasher_dest%\OOS_FILES_HERE"

if defined new_folder (
  echo [STEP] Moving selected partitions to \super...
  pushd "%new_folder%" >nul
  for %%F in (
    my_bigball.img my_carrier.img my_engineering.img my_heytap.img
    my_manifest.img my_product.img my_region.img my_stock.img
    odm.img product.img system.img system_dlkm.img system_ext.img
    vendor.img vendor_dlkm.img
  ) do (
    if exist "%%F" move /Y "%%F" "%flasher_dest%\super\" >nul
  )
  popd >nul

  echo [STEP] Moving remaining files to \OOS_FILES_HERE...
  move /Y "%new_folder%\*" "%flasher_dest%\OOS_FILES_HERE\" >nul
  rmdir /s /q "%new_folder%" >nul
) else (
  echo [INFO] Dry-run: created empty folders to validate structure.
)

:: ------------------------------------------------------------
:: 5) Handle dtbo patching and override
:: ------------------------------------------------------------
echo [STEP] Handling dtbo.img...
if exist "%flasher_dest%\OOS_FILES_HERE\dtbo.img" (
  copy /Y "%flasher_dest%\OOS_FILES_HERE\dtbo.img" "%flasher_dest%\" >nul
  if exist "%flasher_dest%\dtbo_patcher.bat" (
    echo [INFO] Patching dtbo.img...
    call "%flasher_dest%\dtbo_patcher.bat"
  ) else (
    echo [WARN] dtbo_patcher.bat not found. Skipping patch.
  )
)

if exist "%self_dir%\..\..\16DTBO\dtbo.img" (
  echo [STEP] Replacing OTA dtbo.img with 16DTBO version...
  copy /Y "%self_dir%\..\..\16DTBO\dtbo.img" "%flasher_dest%\OOS_FILES_HERE\" >nul
) else (
  echo [WARN] No dtbo.img found in 16DTBO folder. Skipping replace.
)

:: ------------------------------------------------------------
:: 6) Build super.img using super_oos.bat
:: ------------------------------------------------------------
echo [STEP] Packing super.img...
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
    move /Y "%flasher_dest%\Super\super.img" "%flasher_dest%\" >nul
    echo [STEP] super.img moved to flasher root.
  ) else (
    echo [WARN] super.img not found after packing.
  )
) else (
  echo [WARN] super_oos.bat not found. Skipping super build.
)

:: ------------------------------------------------------------
:: 7) Clean-up
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
