@echo off
setlocal
cd /d "%~dp0"
title Realme NEO8 - CN ColorOS Super Flasher
set "fastboot=%~dp0Platform-Tools\fastboot.exe"
if not exist "%fastboot%" (
    set "fastboot=fastboot"
    where fastboot >nul 2>nul || goto :missing_fastboot
)
if not exist "super.img" goto :incomplete
if not exist "COS_FILES_HERE\boot.img" goto :incomplete
echo Realme NEO8 - CN ColorOS Super Flasher
echo Use only with an unlocked Realme NEO8 and matching CN firmware.
echo Connect the phone in bootloader fastboot mode, then press any key to start.
pause >nul
for %%P in (boot dtbo init_boot modem recovery vbmeta vbmeta_system vbmeta_vendor vendor_boot) do (
    call :flash_boot %%P
    if errorlevel 1 goto :failed
)
call "%fastboot%" flash super super.img || goto :failed
call "%fastboot%" reboot fastboot || goto :failed
echo Wait for fastbootd on the phone, then press any key.
pause >nul
for %%G in ("COS_FILES_HERE\*.img") do (
    call :flash_extra "%%~fG" "%%~nG"
    if errorlevel 1 goto :failed
)
call "%fastboot%" --set-active=a || goto :failed
set "wipe="
set /p "wipe=Format data on the phone before booting? [y/N]: "
if /i "%wipe%"=="Y" (
    echo Use Format Data on the phone. Reboot after formatting completes.
) else (
    call "%fastboot%" reboot || goto :failed
)
exit /b 0

:flash_boot
if not exist "COS_FILES_HERE\%~1.img" exit /b 0
call "%fastboot%" flash %~1_a "COS_FILES_HERE\%~1.img" || exit /b 1
call "%fastboot%" flash %~1_b "COS_FILES_HERE\%~1.img" || exit /b 1
exit /b 0

:flash_extra
rem These images are already flashed individually or packed inside super.
for %%P in (boot dtbo init_boot modem recovery vbmeta vbmeta_system vbmeta_vendor vendor_boot my_bigball my_carrier my_company my_engineering my_heytap my_manifest my_preload my_product my_region my_stock odm product system system_dlkm system_dlkm_gki system_dlkm_oki system_ext vendor vendor_dlkm) do (
    if /i "%~2"=="%%P" exit /b 0
)
call "%fastboot%" flash --slot=all "%~2" "%~1"
exit /b %errorlevel%

:missing_fastboot
echo fastboot not found. Keep Platform-Tools beside the script or install fastboot on PATH.
pause
exit /b 1
:incomplete
echo Incomplete NEO8 package: super.img and COS_FILES_HERE\boot.img are required.
pause
exit /b 1
:failed
echo Flashing stopped after an error. Check the output before rebooting the phone.
pause
exit /b 1
