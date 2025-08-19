@echo off
setlocal EnableExtensions EnableDelayedExpansion

echo ==========================================================
echo   SUPERHYBRID FULL SUPERBUILD  (Dry-Run Compatible)
echo ==========================================================

:: ------------------------------------------------------------
:: 1) INPUT (drag & drop OTA.zip OR dry-run if none provided)
:: ------------------------------------------------------------
set "dry_run=0"
if "%~1"=="" (
  echo [INFO] No OTA zip provided. Running in DRY-RUN mode...
  set "dry_run=1"
  set "input_file=DUMMY_OTA.zip"
  set "input_dir=%~dp0DUMMY_OTA"
  if not exist "%input_dir%" mkdir "%input_dir%"
) else (
  set "input_file=%~1"
  set "input_dir=%~dp1"
)

set "input_dir=%input_dir:~0,-1%"
set "self_dir=%~dp0"
set "self_dir=%self_dir:~0,-1%"

set "flasher_src=%self_dir%\SuperHybrid Flasher"
set "flasher_dest=%input_dir%\SuperHybrid Flasher"

:: ------------------------------------------------------------
:: 2) Locate otaripper.exe
:: ------------------------------------------------------------
set "otaripper=%self_dir%\..\..\otaripper\otaripper.exe"
if not exist "%otaripper%" (
  echo [ERROR] otaripper.exe not found at: %otaripper%
  if "%dry_run%"=="0" exit /b 1
)

echo [INFO] Mode     : %dry_run% (1=dry-run, 0=real)
echo [INFO] OTA file : "%input_file%"
echo [INFO] OTA dir  : "%input_dir%\"
echo [INFO] Builder  : "%~nx0"
echo [INFO] Ripper   : "%otaripper%"
echo [INFO] Template : "%flasher_src%"
echo.

:: ------------------------------------------------------------
:: 3) Copy flasher template
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
:: 4) Extract OTA using otaripper (if not dry-run)
:: ------------------------------------------------------------
set "new_folder="

if "%dry_run%"=="1" (
  echo [INFO] Dry-run: skipping extraction.
) else (
  set "tmp_before=%temp%\before_%random%%random%.lst"
  set "tmp_after=%temp%\after_%random%%random%.lst"
  dir /b /ad "%input_dir%" > "%tmp_before%"

  echo [STEP] Extracting OTA using otaripper.exe...
  pushd "%input_dir%" >nul
  "%otaripper%" "%input_file%"
  set "rip_rc=%errorlevel%"
  popd >nul

  if not "%rip_rc%"=="0" (
    echo [ERROR] otaripper failed with exit code %rip_rc%.
    echo [INFO] Continuing build anyway for layout test...
    goto :SKIP_EXTRACTION
  )

  dir /b /ad "%input_dir%" > "%tmp_after%"

  for /f "usebackq delims=" %%N in ("%tmp_after%") do (
    findstr /ix "%%N" "%tmp_before%" >nul || (
      set "new_folder=%input_dir%\%%N"
    )
  )

  del "%tmp_before%" >nul 2>&1
  del "%tmp_after%" >nul 2>&1

  if not defined new_folder (
    echo [ERROR] Could not detect extracted folder.
    echo [INFO] Continuing build anyway for layout test...
  ) else (
    echo [INFO] Detected extracted folder: "%new_folder%"
  )
)

:SKIP_EXTRACTION

:: ------------------------------------------------------------
:: 5) Organize files (super and OOS_FILES_HERE)
:: ------------------------------------------------------------
if not exist "%flasher_dest%\super" mkdir "%flasher_dest%\super"
if not exist "%flasher_dest%\OOS_FILES_HERE" mkdir "%flasher_dest%\OOS_FILES_HERE"

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
  move /Y "%new_folder%\*" "%flasher_dest%\OOS_FILES_HERE\" >nul 2>&1
  rd /s /q "%new_folder%" 2>nul
) else (
  echo [INFO] Dry-run: created empty folders to validate layout.
)

:: ------------------------------------------------------------
:: 6) dtbo.img patching and replacement
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

if exist "%self_dir%\16DTBO\dtbo.img" (
  echo [STEP] Replacing "OOS_FILES_HERE\dtbo.img" with "16DTBO\dtbo.img" ...
  copy /Y "%self_dir%\16DTBO\dtbo.img" "%flasher_dest%\OOS_FILES_HERE\" >nul
) else (
  echo [WARN] "%self_dir%\16DTBO\dtbo.img" not found; leaving OTA dtbo as-is.
)

:: ------------------------------------------------------------
:: 7) Run super.bat to pack super.img
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
    echo [STEP] Moving super.img to flasher root...
    move /Y "%flasher_dest%\Super\super.img" "%flasher_dest%\" >nul
  ) else (
    echo [WARN] super.img not found after packing.
  )
) else (
  echo [WARN] super.bat not found in Super\ folder; skipping super.img.
)

:: ------------------------------------------------------------
:: 8) Cleanup temporary files
:: ------------------------------------------------------------
echo [STEP] Cleaning up temporary files...
if exist "%flasher_dest%\Super" rmdir /S /Q "%flasher_dest%\Super"
if exist "%flasher_dest%\dtbo.img" del /F /Q "%flasher_dest%\dtbo.img"
if exist "%flasher_dest%\dtbo_patcher.bat" del /F /Q "%flasher_dest%\dtbo_patcher.bat"

echo.
echo ==========================================================
echo   BUILD DONE!  (Dry-run OK if no OTA was given)
echo ==========================================================
exit /b 0
