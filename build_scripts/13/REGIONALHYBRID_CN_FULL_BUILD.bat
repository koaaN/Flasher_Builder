@echo off
setlocal enabledelayedexpansion

:: Path to dropped ZIP
set "input_file=%~1"
set "input_dir=%~dp1"

:: Paths to tools and folders
set "tool=%~dp0otaripper.exe"
set "tool_name=otaripper.exe"
set "regional_flasher_src=%~dp0RegionalHybrid Flasher CN"
set "regional_flasher_dest=%input_dir%RegionalHybrid Flasher CN"

:: Copy Regional Flasher CN folder to zip location
xcopy /E /I /Y "%regional_flasher_src%" "%regional_flasher_dest%"

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

:: Move all extracted files and handle bloat
if defined new_folder (
    echo Moving all extracted files into COS_FILES_HERE...
    if not exist "%regional_flasher_dest%\COS_FILES_HERE" mkdir "%regional_flasher_dest%\COS_FILES_HERE"
    move /Y "!new_folder!\*" "%regional_flasher_dest%\COS_FILES_HERE\" >nul

    echo Copying my_preload.img ^& my_company.img from EUGLO_BLOAT into OOS_FILES_HERE
    copy /Y "%~dp0EUGLO_BLOAT\my_preload.img" "%regional_flasher_dest%\OOS_FILES_HERE\"
    copy /Y "%~dp0EUGLO_BLOAT\my_company.img" "%regional_flasher_dest%\OOS_FILES_HERE\"

    rd /s /q "!new_folder!"
)

echo Done moving files into Regional Flasher CN.
pause
