@echo off
setlocal enabledelayedexpansion

:: Path to dropped ZIP
set "input_file=%~1"
set "input_dir=%~dp1"

:: Path to otaripper.exe and Super Flasher CN folder
set "tool=%~dp0otaripper.exe"
set "tool_name=otaripper.exe"
set "super_flasher_src=%~dp0Super Flasher CN"
set "super_flasher_dest=%input_dir%Super Flasher CN"

:: Copy Super Flasher CN folder to zip location
xcopy /E /I /Y "%super_flasher_src%" "%super_flasher_dest%"

:: Copy otaripper.exe to the zip's folder
copy "%tool%" "%input_dir%" >nul

:: Save list of folders before extraction
set "before_folders="
for /d %%D in ("%input_dir%*") do (
    set "before_folders=!before_folders! %%~nxD"
)

:: Run otaripper.exe (no --partitions)
pushd "%input_dir%"
"%tool_name%" "%input_file%"
popd

:: Delete temporary otaripper.exe
del "%input_dir%%tool_name%" >nul

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
    :: First move selected .img files to the super folder
    if not exist "%super_flasher_dest%\super" mkdir "%super_flasher_dest%\super"

    echo Moving logical partitions into super folder...
    for %%F in (
        my_bigball.img my_carrier.img my_engineering.img my_heytap.img
        my_manifest.img my_product.img my_region.img my_stock.img
        odm.img product.img system.img system_dlkm.img system_ext.img
        vendor.img vendor_dlkm.img
    ) do (
        if exist "!new_folder!\%%F" move /Y "!new_folder!\%%F" "%super_flasher_dest%\super\"
    )

    :: Then move remaining files to COS_FILES_HERE
    if not exist "%super_flasher_dest%\COS_FILES_HERE" mkdir "%super_flasher_dest%\COS_FILES_HERE"
    move /Y "!new_folder!\*" "%super_flasher_dest%\COS_FILES_HERE\" >nul

    

    rd /s /q "!new_folder!"
)

echo Done moving files into Super Flasher CN.
echo Packing super.img
call "Super Flasher CN\Super\super_cos.bat"
move /Y "Super Flasher CN\Super\super.img" "Super Flasher CN\"
rmdir /S /Q "Super Flasher CN\Super"
