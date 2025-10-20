@echo off
title Super Matrixx Flasher
echo.**********************************************************************
echo.
echo.          Oneplus 13 - Super Matrixx Flasher
echo.          Matrixx for OP13 created by Brian
echo.       Packaged by docnok63, Jonas Salo ^& Daniel
echo.     script inspired by FTH PHONE 1902 and Venkay
@echo off

cd %~dp0
set fastboot=Platform-Tools\fastboot.exe
if not exist "%fastboot%" echo "%fastboot%" not found. & pause & exit /B 1
set file=vendor_boot
echo.************************      START FLASH     ************************
"%fastboot%" -aa
for %%G in (FASTBOOT_FILES_HERE\*.img) do (
    echo Matrixx Flasher flashing %%~nG
    "%fastboot%" flash "%%~nG" "%%G"	
)
"%fastboot%" reboot fastboot
echo.  *******************      REBOOTING TO FASTBOOTD     *******************
ECHO  #################################
ECHO  # Make sure it says fastbootd   #
ECHO  #  at the top of the screen     #
ECHO  #################################
pause
for %%G in (FASTBOOTD_FILES_HERE\*.img) do (
    echo Matrixx Flasher flashing %%~nG
    "%fastboot%" flash --slot=all "%%~nG" "%%G"	
)
    echo.********************** CHECK ABOVE FOR ERRORS **************************
    echo.************** IF ERRORS, DO NOT BOOT INTO SYSTEM **********************
@echo off
echo Is your OP13 the Chinese (CN) variant?
choice /c YN /m "Press Y for yes  or N for GLO, EU, IN, or NA variant"

if errorlevel 2 (
    echo                ****************** FLASHING COMPLETE *****************
    echo         Wipe data by tapping Enter recovery on the screen. Then tap Factory reset
    echo                   Tap the power button to format data/factory reset
    echo            Phone will automatically reboot into Android after wipe is done

) else (
    echo ***** Flashing COS oplusstanvbk *****
	"%fastboot%" flash --slot=all oplusstanvbk COS_FILES_HERE\oplusstanvbk.img
	echo *****      REBOOTING TO FASTBOOT     *****
	"%fastboot%" reboot bootloader 
	echo *****  Wait for phone to boot into bootloader and *****
	echo *****        press enter to flash CN modem     *****
	pause
	echo ***** Flashing COS modem *****
	"%fastboot%" flash --slot=all modem COS_FILES_HERE\modem.img
	echo *****      REBOOTING TO FASTBOOTD     *****
	"%fastboot%" reboot fastboot
	echo *****  Wait for phone to boot into fastbootd and *****
	echo *****        press enter to continue     *****
	pause
	
    echo                ****************** FLASHING COMPLETE *****************
    echo         Wipe data by tapping Enter recovery on the screen. Then tap Factory reset
    echo                   Tap the power button to format data/factory reset
    echo            Phone will automatically reboot into Android after wipe is done

)

endlocal
pause
