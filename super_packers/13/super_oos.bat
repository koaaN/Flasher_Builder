@echo off
setlocal EnableDelayedExpansion

pushd "%~dp0"

:: Super partition total size
set SUPER_SIZE=15354134528

:: lpmake path (assumes this script is in the same folder as lpmake.exe)
set LPM=lpmake.exe

:: Start building the command
set CMD=%LPM% --metadata-size 65536 --metadata-slots 3 --virtual-ab --super-name super
set CMD=!CMD! --device super:%SUPER_SIZE%
set CMD=!CMD! --group qti_dynamic_partitions_a:%SUPER_SIZE%
set CMD=!CMD! --group qti_dynamic_partitions_b:%SUPER_SIZE%

:: Define list of A slot partitions with image files
set PARTS_A=my_bigball my_carrier my_company my_engineering my_heytap my_manifest my_preload my_product my_region my_stock odm product system system_dlkm system_ext vendor vendor_dlkm

:: Loop through A slot parts and get file size
for %%P in (!PARTS_A!) do (
    set FILE=%%P.img
    if exist "!FILE!" (
        for %%S in (!FILE!) do (
            set SIZE=%%~zS
            set CMD=!CMD! --partition %%P_a:readonly:!SIZE!:qti_dynamic_partitions_a --image %%P_a="%%P.img"
        )
    ) else (
        echo Warning: !FILE! not found!
    )
)

:: Add 0-byte B slot partitions
set PARTS_B=my_bigball my_carrier my_company my_engineering my_heytap my_manifest my_preload my_product my_region my_stock odm product system system_dlkm system_ext vendor vendor_dlkm

for %%P in (!PARTS_B!) do (
    set CMD=!CMD! --partition %%P_b:readonly:0:qti_dynamic_partitions_b
)

:: Final options
set CMD=!CMD! --sparse --output "%CD%\super.img"

:: Run and show command
echo Running command:
echo !CMD!
call !CMD!

popd
pause
