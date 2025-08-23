@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem ===== Inputs and locations =====
set "INPUT_FILE=%~1"
if not exist "%INPUT_FILE%" (
  echo ERROR: OTA zip not found: %INPUT_FILE%
  exit /b 2
)

set "INPUT_DIR=%~dp1"
set "SCRIPT_DIR=%~dp0"

set "TOOL=%SCRIPT_DIR%otaripper.exe"
set "TOOL_NAME=otaripper.exe"

rem Template flasher lives next to this .bat
set "FLASHER_SRC=%SCRIPT_DIR%Regional Hybrid Flasher"
rem We stage the flasher into the same folder as the OTA.zip
set "FLASHER_DEST=%INPUT_DIR%Regional Hybrid Flasher"

rem ===== Copy flasher template into the OTA folder =====
if not exist "%FLASHER_SRC%" (
  echo ERROR: Flasher template not found: %FLASHER_SRC%
  exit /b 3
)

if not exist "%FLASHER_DEST%" mkdir "%FLASHER_DEST%"
rem Copy the whole template (not src->src)
xcopy "%FLASHER_SRC%\*" "%FLASHER_DEST%\" /E /I /Y >nul

rem ===== Put otaripper next to the zip (some tools expect that) =====
if exist "%TOOL%" (
  copy /Y "%TOOL%" "%INPUT_DIR%" >nul
) else (
  echo ERROR: Missing otaripper.exe at %TOOL%
  exit /b 4
)

rem ===== Snapshot existing folders before extraction =====
set "BEFORE="
for /d %%D in ("%INPUT_DIR%*") do set "BEFORE=!BEFORE!;%%~nxD"

rem ===== Extract (no --partitions) =====
pushd "%INPUT_DIR%" || (echo ERROR: pushd "%INPUT_DIR%" failed & exit /b 5)
"%TOOL_NAME%" "%INPUT_FILE%"
set "RC=%ERRORLEVEL%"
popd

del "%INPUT_DIR%%TOOL_NAME%" >nul 2>nul

if not "%RC%"=="0" (
  echo ERROR: otaripper failed with code %RC%
  exit /b %RC%
)

rem ===== Detect the newly created folder =====
set "NEW_FOLDER="
for /d %%D in ("%INPUT_DIR%*") do (
  echo !BEFORE! | findstr /i /c:";%%~nxD" >nul || set "NEW_FOLDER=%%~fD"
)

rem ===== Move extracted files into OOS_FILES_HERE inside the staged flasher =====
if defined NEW_FOLDER (
  echo Moving all extracted files into OOS_FILES_HERE...
  if not exist "%FLASHER_DEST%\OOS_FILES_HERE" mkdir "%FLASHER_DEST%\OOS_FILES_HERE"
  move /Y "!NEW_FOLDER!\*" "%FLASHER_DEST%\OOS_FILES_HERE\" >nul
  rd /s /q "!NEW_FOLDER!" 2>nul
) else (
  echo WARNING: No new folder detected after extraction. Nothing moved.
)

rem ===== Optional: copy 16DTBO if present next to this script =====
if exist "%SCRIPT_DIR%16DTBO\16.0.0.1_dtbo.img" (
  copy /Y "%SCRIPT_DIR%16DTBO\16.0.0.1_dtbo.img" "%FLASHER_DEST%\" >nul
)

echo Done moving files into Regional Hybrid Flasher.
exit /b 0
