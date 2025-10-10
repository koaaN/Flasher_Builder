@echo off
title OOS Super Flasher
echo.**********************************************************************
echo.
echo.              Oneplus 13T - OOS Super Flasher                      
echo.       Originally two scripts by FTH PHONE 1902 and Venkay
echo.            modified by docnok63, Jonas Salo & Daniel
echo.
@echo off

cd %~dp0
set fastboot=Platform-Tools\fastboot.exe
if not exist "%fastboot%" echo "%fastboot%" not found. & pause & exit /B 1
set file=vendor_boot
echo.************************      START FLASH     ************************
%fastboot% --set-active=a

:: Flash the fastboot images first
%fastboot% flash boot OOS_FILES_HERE\boot.img
%fastboot% flash dtbo OOS_FILES_HERE\dtbo.img
%fastboot% flash init_boot OOS_FILES_HERE\init_boot.img
%fastboot% flash modem OOS_FILES_HERE\modem.img
%fastboot% flash recovery OOS_FILES_HERE\recovery.img
%fastboot% flash vbmeta OOS_FILES_HERE\vbmeta.img
%fastboot% flash vbmeta_system OOS_FILES_HERE\vbmeta_system.img
%fastboot% flash vbmeta_vendor OOS_FILES_HERE\vbmeta_vendor.img
%fastboot% flash vendor_boot OOS_FILES_HERE\vendor_boot.img

:: Check if super.img exists
if exist "super.img" (
    %fastboot% flash super super.img
) else (
    echo super.img not found. Skipping super.img...
)

:: Reboot to fastbootd
%fastboot% reboot fastboot
echo.  *******************      REBOOTING TO FASTBOOTD     *******************
ECHO  #################################
ECHO  # Hit English on Phone          #
ECHO  #################################
pause

:: Excluded files list (these should not be flashed again)
set excluded_images=boot.img dtbo.img init_boot.img modem.img recovery.img vbmeta.img vbmeta_system.img vbmeta_vendor.img vendor_boot.img my_bigball.img my_carrier.img my_company.img my_engineering.img my_heytap.img my_manifest.img my_preload.img my_product.img my_region.img my_stock.img odm.img product.img system.img system_dlkm.img system_ext.img vendor.img vendor_dlkm.img   

:: Loop through all .img files in OOS_FILES_HERE but skip excluded images
for %%G in (OOS_FILES_HERE\*.img) do (
    echo %excluded_images% | findstr /i /c:"%%~nxG" >nul
    if errorlevel 1 (
        echo Flashing %%~nG...
        %fastboot% flash --slot=all "%%~nG" "%%G"
    )
)

:: Define partitions list outside the IF block
set "partitions=my_bigball my_carrier my_engineering my_heytap my_manifest my_product my_region my_stock odm product system system_dlkm system_ext vendor vendor_dlkm my_company my_preload"

:: Check if super.img exists, if not, delete, create & flash logical partitions
if not exist "super.img" (
    for %%P in (%partitions%) do (
        %fastboot% delete-logical-partition %%P_a
        %fastboot% delete-logical-partition %%P_b
        %fastboot% delete-logical-partition %%P_a-cow
        %fastboot% delete-logical-partition %%P_b-cow
        %fastboot% create-logical-partition %%P_a 1
        %fastboot% create-logical-partition %%P_b 1
        %fastboot% flash %%P OOS_FILES_HERE\%%P.img
    )
) else (
    echo super.img found. Logical partition flashes skipped...
)

echo.********************** CHECK ABOVE FOR ERRORS **************************
echo.************** IF ERRORS, DO NOT BOOT INTO SYSTEM **********************

:: If super.img was not flashed, exit here but keep window open
if not exist "super.img" (
    choice /C YN /M "Do you want to wipe data?:" 

    if errorlevel 2 (
        echo *********************** NO NEED TO WIPE DATA ****************************
        echo ***** Flashing complete. Hit any key to reboot the phone to Android *****
        pause
        %fastboot% reboot
        exit /B 0
    )

    if errorlevel 1 (
        echo ****************** FLASHING COMPLETE *****************
        echo Wipe data by tapping Format Data on the screen, enter the code, and press format data.
        echo Phone will automatically reboot into Android after wipe is done.
        pause
        exit /B 0
    )
)

:: Ask if user wants to prepare for root
echo Are you going to root your OP13T?
choice /c YN /m "Press Y to prepare for root or N to not prepare"

if errorlevel 2 (
    echo ***** Flashing COS omd,oplusstanvbk and GLO COS my_region *****
    %fastboot% flash oplusstanvbk COS_FILES_HERE\oplusstanvbk.img
    %fastboot% flash my_region COS_FILES_HERE\my_region.img
	%fastboot% delete-logical-partition odm_a
	%fastboot% delete-logical-partition odm_b
	%fastboot% delete-logical-partition odm_a-cow
	%fastboot% delete-logical-partition odm_b-cow
	%fastboot% create-logical-partition odm_a 1
	%fastboot% create-logical-partition odm_b 1
	%fastboot% flash odm COS_FILES_HERE\odm.img
) else (
    echo ***** No signal files flashed *****
    echo ***** After rooting, you must flash signal & odm module to get camera & signal working *****
)

:: Ask if flashing from ColorOS (press Y for yes or N for no)
echo Are you flashing from ColorOS or Want to WIPE DATA?? (y/n)
choice /c YN /n > nul

:: Check if the user pressed 'y' or 'n'
if errorlevel 2 (
    echo *********************** NO NEED TO WIPE DATA ****************************
    echo ***** Flashing complete. Hit any key to reboot the phone to Android *****
    pause
    %fastboot% reboot
) else if errorlevel 1 (
    echo ****************** FLASHING COMPLETE *****************
    echo Wipe data by tapping Format Data on the screen, enter the code, and press format data.
    echo Phone will automatically reboot into Android after wipe is done.
)

pause

