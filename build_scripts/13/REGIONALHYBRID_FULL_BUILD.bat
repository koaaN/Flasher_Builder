@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem ================== Inputs / paths ==================
set "INPUT_FILE=%~1"
if not exist "%INPUT_FILE%" (
  echo ERROR: OTA zip not found: %INPUT_FILE%
  exit /b 2
)

set "INPUT_DIR=%~dp1"
set "SCRIPT_DIR=%~dp0"

set "TOOL=%SCRIPT_DIR%otaripper.exe"
set "TOOL_NAME=otaripper.exe"

rem Try both possible flasher folder names (with and without space)
set "FLASHER_SRC_A=%SCRIPT_DIR%RegionalHybrid Flasher"
set "FLASHER_SRC_B=%SCRIPT_DIR%Regional Hybrid Flasher"

if exist "%FLASHER_SRC_A%" (
  set "FLASHER_SRC=%FLASHER_SRC_A%"
  set "FLASHER_NAME=RegionalHybrid Flasher"
) else if exist "%FLASHER_SRC_B%" (
  set "FLASHER_SRC=%FLASHER_SRC_B%"
  set "FLASHER_NAME=Regional Hybrid Flasher"
) else (
  echo ERROR: Flasher template not found. Tried:
  echo   "%FLASHER_SRC_A%"
  echo   "%FLASHER_SRC_B%"
  exit /b 1
)

set "FLASHER_DEST=%INPUT_DIR%%FLASHER_NAME%"

rem ================== Stage flasher ==================
if not exist "%FLASHER_DEST%" mkdir "%FLASHER_DEST%"
xcopy "%FLASHER_SRC%\*" "%FLASHER_DEST%\" /E /I /Y >nul

rem Put otaripper next to the zip
if not exist "%TOOL%" (
  echo ERROR: Missing otaripper.exe at %TOOL%
  exit /b 4
)
copy /Y "%TOOL%" "%INPUT_DIR%" >nul

rem Snapshot existing folders
set "BEFORE="
for /d %%D in ("%INPUT_DIR%*") do set "BEFORE=!BEFORE!;%%~nxD"

rem ================== Extract ==================
pushd "%INPUT_DIR%" || (echo ERROR: pushd "%INPUT_DIR%" failed & exit /b 5)
"%TOOL_NAME%" "%INPUT_FILE%"
set "RC=%ERRORLEVEL%"
popd
del "%INPUT_DIR%%TOOL_NAME%" >nul 2>nul

if not "%RC%"=="0" (
  echo ERROR: otaripper failed with code %RC%
  exit /b %RC%
)

rem Detect new folder
set "NEW_FOLDER="
for /d %%D in ("%INPUT_DIR%*") do (
  echo !BEFORE! | findstr /i /c:";%%~nxD" >nul || set "NEW_FOLDER=%%~fD"
)

rem Move payload into OOS_FILES_HERE
if defined NEW_FOLDER (
  echo Moving all extracted files into OOS_FILES_HERE...
  if not exist "%FLASHER_DEST%\OOS_FILES_HERE" mkdir "%FLASHER_DEST%\OOS_FILES_HERE"
  move /Y "!NEW_FOLDER!\*" "%FLASHER_DEST%\OOS_FILES_HERE\" >nul
  rd /s /q "!NEW_FOLDER!" 2>nul
) else (
  echo WARNING: No new folder detected after extraction. Nothing moved.
)

rem Optional 16DTBO copy if available
if exist "%SCRIPT_DIR%16DTBO\16.0.0.1_dtbo.img" (
  copy /Y "%SCRIPT_DIR%16DTBO\16.0.0.1_dtbo.img" "%FLASHER_DEST%\" >nul
)

echo Done moving files into %FLASHER_NAME%.
exit /b 0
