@echo off
setlocal
title OPPO Find X9 Ultra - ColorOS Super Flasher
echo.**********************************************************************
echo.
echo.              OPPO Find X9 Ultra - ColorOS Super Flasher
echo.             Packaged by docnok63, Jonas Salo ^& Daniel
echo.        script inspired by FTH PHONE 1902 and Venkay
echo.
echo.**********************************************************************
@echo off

cd /d "%~dp0"
set "fastboot=Platform-Tools\fastboot.exe"
if not exist "%fastboot%" (
    set "fastboot=fastboot"
    where fastboot >nul 2>nul || exit /B 1
)
if not exist "OTA_FILES_HERE\boot.img" exit /B 1
if not exist "super.img" exit /B 1
echo.************************      START FLASH     ************************

:: Flash the fastboot images first
call "%fastboot%" flash boot_a OTA_FILES_HERE\boot.img || exit /B 1
call "%fastboot%" flash boot_b OTA_FILES_HERE\boot.img || exit /B 1
call "%fastboot%" flash dtbo_a OTA_FILES_HERE\dtbo.img || exit /B 1
call "%fastboot%" flash dtbo_b OTA_FILES_HERE\dtbo.img || exit /B 1
call "%fastboot%" flash init_boot_a OTA_FILES_HERE\init_boot.img || exit /B 1
call "%fastboot%" flash init_boot_b OTA_FILES_HERE\init_boot.img || exit /B 1
call "%fastboot%" flash modem_a OTA_FILES_HERE\modem.img || exit /B 1
call "%fastboot%" flash modem_b OTA_FILES_HERE\modem.img || exit /B 1
call "%fastboot%" flash recovery_a OTA_FILES_HERE\recovery.img || exit /B 1
call "%fastboot%" flash recovery_b OTA_FILES_HERE\recovery.img || exit /B 1
call "%fastboot%" flash vbmeta_a OTA_FILES_HERE\vbmeta.img || exit /B 1
call "%fastboot%" flash vbmeta_b OTA_FILES_HERE\vbmeta.img || exit /B 1
call "%fastboot%" flash vbmeta_system_a OTA_FILES_HERE\vbmeta_system.img || exit /B 1
call "%fastboot%" flash vbmeta_system_b OTA_FILES_HERE\vbmeta_system.img || exit /B 1
call "%fastboot%" flash vbmeta_vendor_a OTA_FILES_HERE\vbmeta_vendor.img || exit /B 1
call "%fastboot%" flash vbmeta_vendor_b OTA_FILES_HERE\vbmeta_vendor.img || exit /B 1
call "%fastboot%" flash vendor_boot_a OTA_FILES_HERE\vendor_boot.img || exit /B 1
call "%fastboot%" flash vendor_boot_b OTA_FILES_HERE\vendor_boot.img || exit /B 1

:: Check if super.img exists
if exist "super.img" (
    call "%fastboot%" flash super super.img || exit /B 1
)

:: Reboot to fastbootd
call "%fastboot%" reboot fastboot || exit /B 1
echo.  *******************      REBOOTING TO FASTBOOTD     *******************
ECHO  #################################
ECHO  #      Hit English on Phone     #
ECHO  #################################
pause

:: Excluded files list (these should not be flashed again)
set excluded_images=abl.img boot.img dtbo.img init_boot.img modem.img recovery.img vbmeta.img vbmeta_system.img vbmeta_vendor.img vendor_boot.img my_bigball.img my_carrier.img my_company.img my_engineering.img my_heytap.img my_manifest.img my_preload.img my_product.img my_region.img my_stock.img odm.img product.img system.img system_dlkm.img system_dlkm_oki.img system_dlkm_gki.img system_ext.img vendor.img vendor_dlkm.img

:: Loop through all .img files in OTA_FILES_HERE but skip excluded images
for %%G in (OTA_FILES_HERE\*.img) do (
    echo %excluded_images% | findstr /i /c:"%%~nxG" >nul
    if errorlevel 1 (
        echo Flashing %%~nG...
        call "%fastboot%" flash --slot=all "%%~nG" "%%G" || exit /B 1
    )
)

:: Define partitions list outside the IF block
set "partitions=my_bigball my_carrier my_engineering my_heytap my_manifest my_product my_region my_stock odm product system system_dlkm system_dlkm_oki system_dlkm_gki system_ext vendor vendor_dlkm my_company my_preload"

:: If super.img does not exist, prepare every matching partition before flashing any image
if not exist "super.img" (
    for %%P in (%partitions%) do (
        if exist "OTA_FILES_HERE\%%P.img" (
            echo Preparing %%P...
            call "%fastboot%" delete-logical-partition %%P_a || exit /B 1
            call "%fastboot%" delete-logical-partition %%P_b || exit /B 1
            call "%fastboot%" delete-logical-partition %%P_a-cow || exit /B 1
            call "%fastboot%" delete-logical-partition %%P_b-cow || exit /B 1
            call "%fastboot%" create-logical-partition %%P_a 1 || exit /B 1
            call "%fastboot%" create-logical-partition %%P_b 1 || exit /B 1
        )
    )

    for %%P in (%partitions%) do (
        if exist "OTA_FILES_HERE\%%P.img" (
            echo Flashing %%P...
            call "%fastboot%" flash %%P_a "OTA_FILES_HERE\%%P.img" || exit /B 1
        )
    )
)

:: Ask whether to keep the currently installed ABL
set "keep_abl=Y"
set /p "keep_abl=Do you want to keep the current ABL? [Y/n]: "
if /i "%keep_abl%"=="N" (
    echo Flashing abl...
    call "%fastboot%" flash --slot=all abl "OTA_FILES_HERE\abl.img" || exit /B 1
) else (
    echo Keeping the current ABL.
)

:: Change slot to a and reboot
call "%fastboot%" --set-active=a || exit /B 1
call "%fastboot%" reboot fastboot || exit /B 1

echo.********************** CHECK ABOVE FOR ERRORS **************************
echo.************** IF ERRORS, DO NOT BOOT INTO SYSTEM **********************

:: Ask for wipe data
set "wipe=N"
set /p "wipe=Do you want to wipe data? [y/N]: "

if /i not "%wipe%"=="Y" (
    echo *********************** NO NEED TO WIPE DATA ****************************
    echo ***** Flashing complete. Hit any key to reboot the phone to Android *****
    pause
    call "%fastboot%" reboot || exit /B 1
    exit /B 0
)

if /i "%wipe%"=="Y" (
    echo ****************** FLASHING COMPLETE *****************
    echo Wipe data by tapping Format Data on the screen, enter the code, and press format data.
    echo Phone will automatically reboot into Android after wipe is done.
    pause
    exit /B 0
)
