@echo off
setlocal enabledelayedexpansion

echo ====================================================
echo   SUPERHYBRID FULL SUPERBUILD (Dry-Run Compatible)
echo ====================================================

:: Check if OTA zip was provided
if "%~1"=="" (
    echo [INFO] No OTA zip provided.
    echo [INFO] Running in DRY RUN mode just to create folder structure...
    set "input_file=DUMMY_OTA.zip"
    set "input_dir=%~dp0DUMMY_OTA\
    if not exist "%input_dir%" mkdir "%input_dir%"
) else (
    set "input_file=%~1"
    set "input_dir=%~dp1"
)

:: Paths to otaripper.exe and Super Flasher folder
set "tool=%~dp0otaripper.exe"
set "tool_name=otaripper.exe"
set "super_flasher_src=%~dp0SuperHybrid Flasher"
set "super_flasher_dest=%input_dir%SuperHybrid Flasher"

:: Copy SuperHybrid Flasher folder to OTA location
xcopy /E /I /Y "%super_flasher_src%" "%super_flasher_dest%" >nul

:: Copy otaripper.exe to input folder
if exist "%tool%" (
    copy "%tool%" "%input_dir%" >nul
) else (
    echo [WARN] otaripper.exe not found, skipping copy.
)

:: Save list of folders before extraction
set "before_folders="
for /d %%D in ("%input_dir%*") do (
    set "before_folders=!before_folders! %%~nxD"
)

:: Run otaripper.exe (skip if dummy run)
if not "%input_file%"=="DUMMY_OTA.zip" (
    pushd "%input_dir%"
    "%tool_name%" "%input_file%"
    popd
    del "%input_dir%%tool_name%" >nul
) else (
    echo [INFO] Skipping OTA extraction (dry run).
)

:: Detect the new folder created by extraction
set "new_folder="
for /d %%D in ("%input_dir%*") do (
    echo !before_folders! | find " %%~nxD" >nul
    if errorlevel 1 (
        set "new_folder=%%~fD"
    )
)

:: Move files
if defined new_folder (
    if not exist "%super_flasher_dest%\super" mkdir "%super_flasher_dest%\super"

    echo [INFO] Moving logical partitions into super folder...
    for %%F in (
        my_bigball.img my_carrier.img my_engineering.img my_heytap.img
        my_manifest.img my_product.img my_region.img my_stock.img
        odm.img product.img system.img system_dlkm.img system_ext.img
        vendor.img vendor_dlkm.img
    ) do (
        if exist "!new_folder!\%%F" move /Y "!new_folder!\%%F" "%super_flasher_dest%\super\"
    )

    echo [INFO] Copying region bloat (default: EUGLO_BLOAT)...
    copy /Y "%~dp0EUGLO_BLOAT\my_preload.img" "%super_flasher_dest%\super\" >nul
    copy /Y "%~dp0EUGLO_BLOAT\my_company.img" "%super_flasher_dest%\super\" >nul

    if not exist "%super_flasher_dest%\OOS_FILES_HERE" mkdir "%super_flasher_dest%\OOS_FILES_HERE"
    move /Y "!new_folder!\*" "%super_flasher_dest%\OOS_FILES_HERE\" >nul

    rd /s /q "!new_folder!"
) else (
    echo [INFO] No new OTA folder detected (dry run).
    if not exist "%super_flasher_dest%\super" mkdir "%super_flasher_dest%\super"
    if not exist "%super_flasher_dest%\OOS_FILES_HERE" mkdir "%super_flasher_dest%\OOS_FILES_HERE"
)

echo [INFO] Copying and patching dtbo.img...
if exist "%super_flasher_dest%\OOS_FILES_HERE\dtbo.img" (
    copy /Y "%super_flasher_dest%\OOS_FILES_HERE\dtbo.img" "%super_flasher_dest%"
    call "%super_flasher_dest%\dtbo_patcher.bat"
) else (
    echo [WARN] No dtbo.img found, skipping patch (dry run).
)

echo [INFO] Copying 16.0.0.1 dtbo.img into OOS_FILES_HERE...
if exist "%~dp016DTBO\dtbo.img" (
    copy /Y "%~dp016DTBO\dtbo.img" "%super_flasher_dest%\OOS_FILES_HERE\"
) else (
    echo [WARN] 16DTBO\dtbo.img not found, skipping.
)

echo [INFO] Packing super.img (dry run will just simulate)...
if exist "SuperHybrid Flasher\Super\super.bat" (
    call "SuperHybrid Flasher\Super\super.bat"
    if exist "SuperHybrid Flasher\Super\super.img" (
        move /Y "SuperHybrid Flasher\Super\super.img" "SuperHybrid Flasher\"
    )
) else (
    echo [WARN] super.bat not found, skipping pack.
)

echo [INFO] Cleaning up temporary files...
if exist "%super_flasher_dest%\Super" rmdir /S /Q "%super_flasher_dest%\Super"
if exist "%super_flasher_dest%\dtbo.img" del /f /q "%super_flasher_dest%\dtbo.img"
if exist "%super_flasher_dest%\dtbo_patcher.bat" del /f /q "%super_flasher_dest%\dtbo_patcher.bat"

echo ====================================================
echo   BUILD DONE! (Dry run OK if no OTA was given)
echo ====================================================
pause