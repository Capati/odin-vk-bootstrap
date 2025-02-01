@echo off
setlocal enabledelayedexpansion

:: Check if VULKAN_SDK is set
if "%VULKAN_SDK%" == "" (
    echo Error: VULKAN_SDK environment variable is not set
    exit /b 1
)

:: Check if glslc exists
if not exist "%VULKAN_SDK%\Bin\glslc.exe" (
    echo Error: glslc.exe not found in %VULKAN_SDK%\Bin
    exit /b 1
)

echo Starting shader compilation...
set "count=0"
set "errors=0"

for /r %%i in (*.frag *.vert) do (
    echo Compiling: %%i
    %VULKAN_SDK%\Bin\glslc.exe "%%i" -o "%%~ni.spv"
    if !errorlevel! neq 0 (
        echo Failed to compile %%i
        set /a "errors+=1"
    ) else (
        set /a "count+=1"
    )
)

echo Compilation complete:
echo Successfully compiled: !count! files
if !errors! gtr 0 (
    echo Failed to compile: !errors! files
    exit /b 1
)

endlocal
