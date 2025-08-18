@echo off
setlocal enabledelayedexpansion

:: Path to dropped payload.bin
set "input_file=%~1"
set "input_dir=%~dp1"

:: Path to otaripper.exe
set "tool=%~dp0otaripper.exe"
set "tool_name=otaripper.exe"

:: Copy otaripper.exe to the payload's folder
copy "%tool%" "%input_dir%" >nul

:: Save list of folders before extraction
set "before_folders="
for /d %%D in ("%input_dir%*") do (
    set "before_folders=!before_folders! %%~nxD"
)

:: Run otaripper.exe on payload.bin
pushd "%input_dir%"
"%tool_name%" "%input_file%"
popd

:: Delete temporary otaripper.exe
del "%input_dir%%tool_name%" >nul

:: Detect the new extraction folder
set "extracted_folder="
for /d %%D in ("%input_dir%*") do (
    echo !before_folders! | find "%%~nxD" >nul
    if errorlevel 1 (
        set "extracted_folder=%%D"
    )
)

:: Make sure we found an extracted folder
if not defined extracted_folder (
    echo Error: Could not detect extracted folder.
    pause
    exit /b 1
)

:: Copy Super Lineage Flasher to payload.bin directory
set "flasher_source=%~dp0SuperHybrid SunOS Flasher"
set "flasher_dest=%input_dir%\SuperHybrid SunOS Flasher"
xcopy /E /I /Y "%flasher_source%" "!flasher_dest!" >nul

:: Move all files/folders from extracted folder into flasher folder
move /Y "!extracted_folder!\*" "!flasher_dest!" >nul
rd "!extracted_folder!" >nul 2>nul

:: Move listed .img files into FASTBOOTD_FILES_HERE
if exist "!flasher_dest!\abl.img" move /Y "!flasher_dest!\abl.img" "!flasher_dest!\FASTBOOTD_FILES_HERE\" >nul
if exist "!flasher_dest!\aop.img" move /Y "!flasher_dest!\aop.img" "!flasher_dest!\FASTBOOTD_FILES_HERE\" >nul
if exist "!flasher_dest!\aop_config.img" move /Y "!flasher_dest!\aop_config.img" "!flasher_dest!\FASTBOOTD_FILES_HERE\" >nul
if exist "!flasher_dest!\bluetooth.img" move /Y "!flasher_dest!\bluetooth.img" "!flasher_dest!\FASTBOOTD_FILES_HERE\" >nul
if exist "!flasher_dest!\cpucp.img" move /Y "!flasher_dest!\cpucp.img" "!flasher_dest!\FASTBOOTD_FILES_HERE\" >nul
if exist "!flasher_dest!\cpucp_dtb.img" move /Y "!flasher_dest!\cpucp_dtb.img" "!flasher_dest!\FASTBOOTD_FILES_HERE\" >nul
if exist "!flasher_dest!\devcfg.img" move /Y "!flasher_dest!\devcfg.img" "!flasher_dest!\FASTBOOTD_FILES_HERE\" >nul
if exist "!flasher_dest!\dsp.img" move /Y "!flasher_dest!\dsp.img" "!flasher_dest!\FASTBOOTD_FILES_HERE\" >nul
if exist "!flasher_dest!\engineering_cdt.img" move /Y "!flasher_dest!\engineering_cdt.img" "!flasher_dest!\FASTBOOTD_FILES_HERE\" >nul
if exist "!flasher_dest!\featenabler.img" move /Y "!flasher_dest!\featenabler.img" "!flasher_dest!\FASTBOOTD_FILES_HERE\" >nul
if exist "!flasher_dest!\hyp.img" move /Y "!flasher_dest!\hyp.img" "!flasher_dest!\FASTBOOTD_FILES_HERE\" >nul
if exist "!flasher_dest!\imagefv.img" move /Y "!flasher_dest!\imagefv.img" "!flasher_dest!\FASTBOOTD_FILES_HERE\" >nul
if exist "!flasher_dest!\keymaster.img" move /Y "!flasher_dest!\keymaster.img" "!flasher_dest!\FASTBOOTD_FILES_HERE\" >nul
if exist "!flasher_dest!\oplus_sec.img" move /Y "!flasher_dest!\oplus_sec.img" "!flasher_dest!\FASTBOOTD_FILES_HERE\" >nul
if exist "!flasher_dest!\oplusstanvbk.img" move /Y "!flasher_dest!\oplusstanvbk.img" "!flasher_dest!\FASTBOOTD_FILES_HERE\" >nul
if exist "!flasher_dest!\qupfw.img" move /Y "!flasher_dest!\qupfw.img" "!flasher_dest!\FASTBOOTD_FILES_HERE\" >nul
if exist "!flasher_dest!\shrm.img" move /Y "!flasher_dest!\shrm.img" "!flasher_dest!\FASTBOOTD_FILES_HERE\" >nul
if exist "!flasher_dest!\splash.img" move /Y "!flasher_dest!\splash.img" "!flasher_dest!\FASTBOOTD_FILES_HERE\" >nul
if exist "!flasher_dest!\tz.img" move /Y "!flasher_dest!\tz.img" "!flasher_dest!\FASTBOOTD_FILES_HERE\" >nul
if exist "!flasher_dest!\uefi.img" move /Y "!flasher_dest!\uefi.img" "!flasher_dest!\FASTBOOTD_FILES_HERE\" >nul
if exist "!flasher_dest!\uefisecapp.img" move /Y "!flasher_dest!\uefisecapp.img" "!flasher_dest!\FASTBOOTD_FILES_HERE\" >nul
if exist "!flasher_dest!\xbl.img" move /Y "!flasher_dest!\xbl.img" "!flasher_dest!\FASTBOOTD_FILES_HERE\" >nul
if exist "!flasher_dest!\xbl_config.img" move /Y "!flasher_dest!\xbl_config.img" "!flasher_dest!\FASTBOOTD_FILES_HERE\" >nul
if exist "!flasher_dest!\xbl_ramdump.img" move /Y "!flasher_dest!\xbl_ramdump.img" "!flasher_dest!\FASTBOOTD_FILES_HERE\" >nul

:: Move listed .img files into FASTBOOT_FILES_HERE
if exist "!flasher_dest!\boot.img" move /Y "!flasher_dest!\boot.img" "!flasher_dest!\FASTBOOT_FILES_HERE\" >nul
if exist "!flasher_dest!\dtbo.img" move /Y "!flasher_dest!\dtbo.img" "!flasher_dest!\FASTBOOT_FILES_HERE\" >nul
if exist "!flasher_dest!\init_boot.img" move /Y "!flasher_dest!\init_boot.img" "!flasher_dest!\FASTBOOT_FILES_HERE\" >nul
if exist "!flasher_dest!\modem.img" move /Y "!flasher_dest!\modem.img" "!flasher_dest!\FASTBOOT_FILES_HERE\" >nul
if exist "!flasher_dest!\recovery.img" move /Y "!flasher_dest!\recovery.img" "!flasher_dest!\FASTBOOT_FILES_HERE\" >nul
if exist "!flasher_dest!\super.img" move /Y "!flasher_dest!\super.img" "!flasher_dest!\FASTBOOT_FILES_HERE\" >nul
if exist "!flasher_dest!\vbmeta.img" move /Y "!flasher_dest!\vbmeta.img" "!flasher_dest!\FASTBOOT_FILES_HERE\" >nul
if exist "!flasher_dest!\vbmeta_system.img" move /Y "!flasher_dest!\vbmeta_system.img" "!flasher_dest!\FASTBOOT_FILES_HERE\" >nul
if exist "!flasher_dest!\vbmeta_vendor.img" move /Y "!flasher_dest!\vbmeta_vendor.img" "!flasher_dest!\FASTBOOT_FILES_HERE\" >nul
if exist "!flasher_dest!\vendor_boot.img" move /Y "!flasher_dest!\vendor_boot.img" "!flasher_dest!\FASTBOOT_FILES_HERE\" >nul

:: Move SUPER-related .img files into super
if exist "!flasher_dest!\odm.img" move /Y "!flasher_dest!\odm.img" "!flasher_dest!\super\" >nul
if exist "!flasher_dest!\product.img" move /Y "!flasher_dest!\product.img" "!flasher_dest!\super\" >nul
if exist "!flasher_dest!\system.img" move /Y "!flasher_dest!\system.img" "!flasher_dest!\super\" >nul
if exist "!flasher_dest!\system_dlkm.img" move /Y "!flasher_dest!\system_dlkm.img" "!flasher_dest!\super\" >nul
if exist "!flasher_dest!\system_ext.img" move /Y "!flasher_dest!\system_ext.img" "!flasher_dest!\super\" >nul
if exist "!flasher_dest!\vendor.img" move /Y "!flasher_dest!\vendor.img" "!flasher_dest!\super\" >nul
if exist "!flasher_dest!\vendor_dlkm.img" move /Y "!flasher_dest!\vendor_dlkm.img" "!flasher_dest!\super\" >nul

echo.
echo All files sorted into folders inside: !flasher_dest!
echo Packing super.img
call "SuperHybrid SunOS Flasher\Super\super_sunos.bat"
echo Moving super.img into SuperHybrid SunOS Flasher\FASTBOOT_FILES_HERE\.
move /Y "SuperHybrid SunOS Flasher\Super\super.img" "SuperHybrid SunOS Flasher\FASTBOOT_FILES_HERE\"
echo Removing scrap files
rmdir /S /Q "SuperHybrid SunOS Flasher\Super"
echo BUILD DONE!!!
pause
