@echo off
setlocal enabledelayedexpansion

set OUTPUT_DIR=build
set EXECUTABLE_NAME=triangle_debug.exe
set RUN_AFTER_BUILD=false

for %%i in (%*) do (
    if /i "%%i"=="run" (
        set RUN_AFTER_BUILD=true
    )
)

call odin build .\triangle ^
    -debug ^
    -out:%OUTPUT_DIR%/%EXECUTABLE_NAME%
if errorlevel 1 (
    echo Failed to compile!
    exit /b 1
)

echo Compiled successfully!

if "%RUN_AFTER_BUILD%"=="true" (
    pushd build
    "%EXECUTABLE_NAME%"
    popd
)
exit /b 0
