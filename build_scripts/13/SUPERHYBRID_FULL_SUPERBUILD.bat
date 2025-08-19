@echo off
setlocal EnableExtensions EnableDelayedExpansion

echo ==========================================================
echo   SUPERHYBRID FULL SUPERBUILD  (Dry-Run Compatible)
echo ==========================================================

:: ------------------------------------------------------------
:: 1) INPUT (drag & drop OTA.zip OR dry-run if none provided)
:: ------------------------------------------------------------
set "IS_DRYRUN=0"
if "%~1"=="" (
  echo [INFO] No OTA zip provided. Running in DRY-RUN mode...
  set "IS_DRYRUN=1"
  set "input_file=DUMMY_OTA.zip"
  set "input_dir=%~dp0DUMMY_OTA"
  if not exist "%input_dir%" mkdir "%input_dir%"
) else (
  set "input_file=%~1"
  set "input_dir=%~dp1"
)

set "self_dir=%~dp0"
if "%self_dir:~-1%"=="\" set "self_dir=%self_dir:~0,-1%"
if "%input_dir:~-1%"=="\" set "input_dir=%input_dir:~0,-1%"

set "flasher_src=%self_dir%\SuperHybrid Flasher"
set "flasher_dest=%input_dir%\SuperHybrid Flasher"

:: ------------------------------------------------------------
:: 2) Locate otaripper.exe
:: ------------------------------------------------------------
set "otaripper=%self_dir%\..\..\otaripper\otaripper.exe"
if not exist "%otaripper%" (
  echo Error: otaripper.exe not found at: %otaripper%
  exit /b 1
)

echo [INFO] Mode     : %IS_DRYRUN% (1=dry-run, 0=real)
echo [INFO] OTA file : "%input_file%"
echo [INFO] OTA dir  : "%input_dir%\"
echo [INFO] Builder  : "%~nx0"
echo [INFO] Ripper   : "%otaripper%"
echo [INFO] Template : "%flasher_src%"
echo.

:: ------------------------------------------------------------
:: 3) Copy template
:: ------------------------------------------------------------
echo [STEP] Copying flasher template...
echo [DEBUG] flasher_src: [%flasher_src%]
echo [DEBUG] flasher_dest: [%flasher_dest%]
if exist "%flasher_dest%" rmdir /s /q "%flasher_dest%"
xcopy "%flasher_src%" "%flasher_dest%" /E /I /Y >nul
if errorlevel 1 (
  echo Error: failed to copy flasher template.
  exit /b 1
)

:: ------------------------------------------------------------
:: 4) Extract OTA or skip in dry-run
:: ------------------------------------------------------------
set "new_folder="
if "%IS_DRYRUN%"=="1" (
  echo [INFO] Skipping OTA extraction (dry-run).
) else (
  echo [STEP] Extracting OTA using otaripper.exe...
  set "tmp_before=%temp%\before_%random%%random%.lst"
  set "tmp_after=%temp%\after_%random%%random%.lst"
  dir /b /ad "%input_dir%" > "%tmp_before%"

  pushd "%input_dir%" >nul
  "%otaripper%" "%input_file%"
  set "rip_rc=%errorlevel%"
  popd >nul

  if not "%rip_rc%"=="0" (
    echo Error: otaripper failed with exit code %rip_rc%.
    del "%tmp_before%" >nul 2>&1
    exit /b %rip_rc%
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
    echo Error: Could not detect extracted folder.
    exit /b 1
  )
  echo [INFO] Detected extracted folder: "%new_folder%"
)

:: ------------------------------------------------------------
:: 5) Move files to super and OOS_FILES_HERE
:: ------------------------------------------------------------
if not exist "%flasher_dest%\super" mkdir "%flasher_dest%\super"
if not exist "%flasher_dest%\OOS_FILES_HERE" mkdir "%flasher_dest%\OOS_FILES_HERE"

if defined new_folder (
  echo [STEP] Moving selected partitions to \super...
  for %%F in (
    my_bigball.img my_carrier.img my_engineering.img my_heytap.img
    my_manifest.img my_product.img my_region.img my_stock.img
    odm.img product.img system.img system_dlkm.img system_ext.img
    vendor.img vendor_dlkm.img
  ) do (
    if exist "%new_folder%\%%F" move /Y "%new_folder%\%%F" "%flasher_dest%\super\" >nul
  )

  echo [STEP] Moving remaining files to \OOS_FILES_HERE...
  move /Y "%new_folder%\*" "%flasher_dest%\OOS_FILES_HERE\" >nul
  rmdir /s /q "%new_folder%" >nul
) else (
  echo [INFO] Dry-run: skipped moving files (no new_folder).
)

:: ------------------------------------------------------------
:: 6) dtbo patching and replacement
:: ------------------------------------------------------------
echo [STEP] Handling dtbo.img...

if exist "%flasher_dest%\OOS_FILES_HERE\dtbo.img" (
  copy /Y "%flasher_dest%\OOS_FILES_HERE\dtbo.img" "%flasher_dest%" >nul
  if exist "%flasher_dest%\dtbo_patcher.bat" (
    echo [STEP] Running dtbo_patcher.bat...
    call "%flasher_dest%\dtbo_patcher.bat"
  ) else (
    echo [WARN] dtbo_patcher.bat not found.
  )
) else (
  echo [WARN] No dtbo.img to patch.
)

if exist "%self_dir%\..\..\16DTBO\dtbo.img" (
  echo [STEP] Replacing dtbo.img in OOS_FILES_HERE with 16DTBO version...
  copy /Y "%self_dir%\..\..\16DTBO\dtbo.img" "%flasher_dest%\OOS_FILES_HERE\" >nul
) else (
  echo [WARN] 16DTBO version of dtbo.img not found.
)

:: ------------------------------------------------------------
:: 7) Build super.img using super_oos.bat
:: ------------------------------------------------------------
echo [STEP] Packing super.img with super_oos.bat...
if exist "%flasher_dest%\Super\super_oos.bat" (
  pushd "%flasher_dest%\Super" >nul
  call "super_oos.bat"
  set "super_rc=%errorlevel%"
  popd >nul

  if "%super_rc%" NEQ "0" (
    echo Error: super_oos.bat failed with code %super_rc%.
    exit /b %super_rc%
  )

  if exist "%flasher_dest%\Super\super.img" (
    echo [STEP] Moving super.img to flasher root...
    move /Y "%flasher_dest%\Super\super.img" "%flasher_dest%\" >nul
  ) else (
    echo [WARN] super.img not found after build.
  )
) else (
  echo [WARN] super_oos.bat not found; skipping super build.
)

:: ------------------------------------------------------------
:: 8) Cleanup
:: ------------------------------------------------------------
echo [STEP] Cleaning up temporary files...
if exist "%flasher_dest%\Super" rmdir /s /q "%flasher_dest%\Super" >nul
if exist "%flasher_dest%\dtbo.img" del /f /q "%flasher_dest%\dtbo.img" >nul
if exist "%flasher_dest%\dtbo_patcher.bat" del /f /q "%flasher_dest%\dtbo_patcher.bat" >nul

echo.
echo ==========================================================
echo   BUILD DONE! (Dry-run OK if no OTA was given)
echo ==========================================================
exit /b 0
