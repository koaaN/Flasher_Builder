@echo off
setlocal EnableExtensions EnableDelayedExpansion

echo ==========================================================
echo   SUPERHYBRID FULL SUPERBUILD  (Dry-Run Compatible)
echo ==========================================================

:: 1) INPUT - OTA ZIP or dummy dry-run
if "%~1"=="" (
    echo [INFO] No OTA zip provided. Running in DRY-RUN mode...
    set "input_file=DUMMY_OTA.zip"
    set "input_dir=%~dp0DUMMY_OTA"
    if not exist "!input_dir!" mkdir "!input_dir!"
    set "dry_run=1"
) else (
    set "input_file=%~1"
    set "input_dir=%~dp1"
    set "dry_run=0"
)

set "self_dir=%~dp0"
if "%self_dir:~-1%"=="\" set "self_dir=%self_dir:~0,-1%"

:: 2) Set flasher folders
set "flasher_src=%self_dir%\SuperHybrid Flasher"
set "flasher_dest=%input_dir%\SuperHybrid Flasher"

:: 3) Hardcode otaripper location
set "otaripper=%self_dir%\..\otaripper\otaripper.exe"

:: 4) Summary
echo [INFO] Mode     : !dry_run!
echo [INFO] OTA file : "!input_file!"
echo [INFO] OTA dir  : "!input_dir!"
echo [INFO] Builder  : "%~nx0"
echo [INFO] Ripper   : "!otaripper!"
echo [INFO] Template : "!flasher_src!"
echo.

:: 5) Copy template to OTA dir
echo [STEP] Copying flasher template...
if exist "!flasher_dest!" rmdir /s /q "!flasher_dest!"
xcopy "!flasher_src!" "!flasher_dest!" /E /I /Y >nul
if errorlevel 1 (
    echo [ERROR] Failed to copy flasher template.
    exit /b 1
)

:: 6) Extract OTA (skip in dry-run)
set "new_folder="
if "!dry_run!"=="1" (
    echo [INFO] Skipping extraction (dry-run).
) else (
    set "tmp_before=%temp%\before_%random%.lst"
    set "tmp_after=%temp%\after_%random%.lst"
    dir /b /ad "!input_dir!" > "!tmp_before!"

    echo [STEP] Extracting OTA...
    pushd "!input_dir!" >nul
    "!otaripper!" "!input_file!"
    set "rip_rc=!errorlevel!"
    popd >nul

    if not "!rip_rc!"=="0" (
        echo [ERROR] otaripper failed with code !rip_rc!
        del /f /q "!tmp_before!" >nul 2>&1
        exit /b !rip_rc!
    )

    dir /b /ad "!input_dir!" > "!tmp_after!"

    for /f "usebackq delims=" %%N in ("!tmp_after!") do (
        findstr /ix "%%N" "!tmp_before!" >nul || (
            set "new_folder=!input_dir!\%%N"
        )
    )

    del /f /q "!tmp_before!" "!tmp_after!" >nul 2>&1

    if not defined new_folder (
        echo [ERROR] Could not detect extracted folder.
        exit /b 1
    )
    echo [INFO] Detected extracted folder: "!new_folder!"
)

:: 7) Organize files
if not exist "!flasher_dest!\super" mkdir "!flasher_dest!\super"
if not exist "!flasher_dest!\OOS_FILES_HERE" mkdir "!flasher_dest!\OOS_FILES_HERE"

if defined new_folder (
    echo [STEP] Moving partitions to "super\"
    for %%F in (
        my_bigball.img my_carrier.img my_engineering.img my_heytap.img
        my_manifest.img my_product.img my_region.img my_stock.img
        odm.img product.img system.img system_dlkm.img system_ext.img
        vendor.img vendor_dlkm.img
    ) do (
        if exist "!new_folder!\%%F" move /Y "!new_folder!\%%F" "!flasher_dest!\super\" >nul
    )

    echo [STEP] Moving remaining files to "OOS_FILES_HERE\"
    move /Y "!new_folder!\*" "!flasher_dest!\OOS_FILES_HERE\" >nul
    rmdir /s /q "!new_folder!" >nul 2>&1
) else (
    echo [INFO] Dry-run: created empty "super\" and "OOS_FILES_HERE\" to verify structure.
)

:: 8) dtbo patching
echo [STEP] Handling dtbo.img...
if exist "!flasher_dest!\OOS_FILES_HERE\dtbo.img" (
    copy /Y "!flasher_dest!\OOS_FILES_HERE\dtbo.img" "!flasher_dest!" >nul
    if exist "!flasher_dest!\dtbo_patcher.bat" (
        echo [STEP] Patching dtbo.img...
        call "!flasher_dest!\dtbo_patcher.bat"
    ) else (
        echo [WARN] dtbo_patcher.bat missing; skipping.
    )
) else (
    echo [WARN] No dtbo.img found; skipping.
)

:: Replace with 16DTBO version if present
if exist "!self_dir!\16DTBO\dtbo.img" (
    echo [STEP] Replacing dtbo.img with 16DTBO variant...
    copy /Y "!self_dir!\16DTBO\dtbo.img" "!flasher_dest!\OOS_FILES_HERE\" >nul
)

:: 9) Call super.bat to pack super.img
echo [STEP] Packing super.img...
if exist "!flasher_dest!\Super\super.bat" (
    pushd "!flasher_dest!\Super" >nul
    call "super.bat"
    set "super_rc=!errorlevel!"
    popd >nul

    if not "!super_rc!"=="0" (
        echo [ERROR] super.bat failed with code !super_rc!
        exit /b !super_rc!
    )

    if exist "!flasher_dest!\Super\super.img" (
        move /Y "!flasher_dest!\Super\super.img" "!flasher_dest!\" >nul
    ) else (
        echo [WARN] super.img missing after build.
    )
) else (
    echo [WARN] super.bat not found; skipping super.img creation.
)

:: 10) Cleanup
echo [STEP] Cleaning up...
if exist "!flasher_dest!\Super" rmdir /s /q "!flasher_dest!\Super"
if exist "!flasher_dest!\dtbo.img" del /f /q "!flasher_dest!\dtbo.img"
if exist "!flasher_dest!\dtbo_patcher.bat" del /f /q "!flasher_dest!\dtbo_patcher.bat"

echo.
echo ==========================================================
echo   BUILD DONE!  (Dry-run OK if no OTA was given)
echo ==========================================================
exit /b 0
