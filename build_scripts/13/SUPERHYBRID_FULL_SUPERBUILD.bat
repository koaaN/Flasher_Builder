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
) else (
  set "input_file=%~1"
  set "input_dir=%~dp1"
)

:: Strip trailing backslash from input_dir if present
if "%input_dir:~-1%"=="\" set "input_dir=%input_dir:~0,-1%"

:: Create dummy folder if dry-run
if /I "%input_file%"=="DUMMY_OTA.zip" (
  if not exist "%input_dir%" mkdir "%input_dir%"
)

:: ------------------------------------------------------------
:: 2) Define working paths
:: ------------------------------------------------------------
set "self_dir=%~dp0"
if "%self_dir:~-1%"=="\" set "self_dir=%self_dir:~0,-1%"

set "flasher_src=%self_dir%\SuperHybrid Flasher"
set "flasher_dest=%input_dir%\SuperHybrid Flasher"

:: ------------------------------------------------------------
:: 3) Locate otaripper.exe (optional in dry-run)
:: ------------------------------------------------------------
set "otaripper="
for %%P in (
  "%self_dir%\otaripper.exe"
  "%self_dir%\otaripper\otaripper.exe"
  "%self_dir%\..\otaripper\otaripper.exe"
) do (
  if exist "%%~fP" set "otaripper=%%~fP"
)

if not defined otaripper (
  for /f "delims=" %%A in ('where otaripper.exe 2^>nul') do (
    if not defined otaripper set "otaripper=%%~fA"
  )
)

:: ------------------------------------------------------------
:: 4) Echo paths and check template
:: ------------------------------------------------------------
echo [INFO] Mode     : %input_file%
echo [INFO] OTA file : "%input_file%"
echo [INFO] OTA dir  : "%input_dir%"
echo [INFO] Builder  : "%~nx0"
if defined otaripper echo [INFO] Ripper   : "%otaripper%"
echo [INFO] Template : "%flasher_src%"
echo.

if not exist "%flasher_src%" (
  echo [ERROR] Template not found: "%flasher_src%"
  exit /b 1
)

:: ------------------------------------------------------------
:: 5) Copy template into OTA folder
:: ------------------------------------------------------------
echo [STEP] Copying flasher template...
if exist "%flasher_dest%" rmdir /s /q "%flasher_dest%" >nul
xcopy "%flasher_src%" "%flasher_dest%" /E /I /Y >nul
if errorlevel 1 (
  echo [ERROR] Failed to copy template.
  exit /b 1
)

:: ------------------------------------------------------------
:: 6) Extract OTA (only if real input)
:: ------------------------------------------------------------
set "new_folder="
if /I "%input_file%"=="DUMMY_OTA.zip" (
  echo [INFO] Skipping extraction (dry-run).
) else (
  set "tmp_before=%temp%\before_%random%%random%.lst"
  set "tmp_after=%temp%\after_%random%%random%.lst"
  dir /b /ad "%input_dir%" > "%tmp_before%"

  echo [STEP] Extracting OTA...
  pushd "%input_dir%" >nul
  "%otaripper%" "%input_file%"
  set "rip_rc=%errorlevel%"
  popd >nul

  if not "%rip_rc%"=="0" (
    echo [ERROR] otaripper failed with code %rip_rc%.
    if exist "%tmp_before%" del "%tmp_before%"
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
    echo [ERROR] Could not detect extracted folder.
    exit /b 1
  )
  echo [INFO] Detected extracted folder: "%new_folder%"
)

:: ------------------------------------------------------------
:: 7) Organize partitions
:: ------------------------------------------------------------
if not exist "%flasher_dest%\super" mkdir "%flasher_dest%\super"
if not exist "%flasher_dest%\OOS_FILES_HERE" mkdir "%flasher_dest%\OOS_FILES_HERE"

if defined new_folder (
  echo [STEP] Moving images to super and OOS folders...
  for %%F in (
    my_bigball.img my_carrier.img my_engineering.img my_heytap.img
    my_manifest.img my_product.img my_region.img my_stock.img
    odm.img product.img system.img system_dlkm.img system_ext.img
    vendor.img vendor_dlkm.img
  ) do (
    if exist "%new_folder%\%%F" move /Y "%new_folder%\%%F" "%flasher_dest%\super\" >nul
  )
  move /Y "%new_folder%\*" "%flasher_dest%\OOS_FILES_HERE\" >nul
  rd /s /q "%new_folder%" >nul 2>&1
) else (
  echo [INFO] Dry-run: just created empty folders.
)

:: ------------------------------------------------------------
:: 8) dtbo patching and replacement
:: ------------------------------------------------------------
echo [STEP] Handling dtbo.img...
if exist "%flasher_dest%\OOS_FILES_HERE\dtbo.img" (
  copy /Y "%flasher_dest%\OOS_FILES_HERE\dtbo.img" "%flasher_dest%\" >nul
  if exist "%flasher_dest%\dtbo_patcher.bat" (
    echo [STEP] Patching dtbo.img...
    call "%flasher_dest%\dtbo_patcher.bat"
  ) else (
    echo [WARN] dtbo_patcher.bat not found.
  )
) else (
  echo [WARN] No dtbo.img in OOS_FILES_HERE.
)

if exist "%self_dir%\16DTBO\dtbo.img" (
  echo [STEP] Replacing with patched 16DTBO version...
  copy /Y "%self_dir%\16DTBO\dtbo.img" "%flasher_dest%\OOS_FILES_HERE\" >nul
) else (
  echo [WARN] 16DTBO\dtbo.img not found.
)

:: ------------------------------------------------------------
:: 9) Build super.img
:: ------------------------------------------------------------
echo [STEP] Building super.img...
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
    echo [WARN] super.img not found after build.
  )
) else (
  echo [WARN] No super.bat found.
)

:: ------------------------------------------------------------
:: 10) Cleanup
:: ------------------------------------------------------------
echo [STEP] Cleaning up...
if exist "%flasher_dest%\Super" rmdir /S /Q "%flasher_dest%\Super"
if exist "%flasher_dest%\dtbo.img" del /F /Q "%flasher_dest%\dtbo.img"
if exist "%flasher_dest%\dtbo_patcher.bat" del /F /Q "%flasher_dest%\dtbo_patcher.bat"

echo.
echo ==========================================================
echo   BUILD DONE!  (Dry-run OK if no OTA was given)
echo ==========================================================
if /I "%PAUSE_AFTER%"=="1" pause
exit /b 0
