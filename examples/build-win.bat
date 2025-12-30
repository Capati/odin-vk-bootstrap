@echo off
setlocal enabledelayedexpansion

set OUTPUT_DIR=build
set BUILD_TARGET=%1
set EXECUTABLE_NAME=%BUILD_TARGET%.exe
set RUN_AFTER_BUILD=false

:: Check for arguments
set ARG_COUNTER=0
for %%i in (%*) do (
	if !ARG_COUNTER! equ 0 (
		rem Skip the build target first argument
	) else (
		if /i "%%i"=="run" (
			set RUN_AFTER_BUILD=true
		)
	)
	set /a ARG_COUNTER+=1
)

call odin build .\%BUILD_TARGET% ^
    -debug ^
    -out:%OUTPUT_DIR%/%EXECUTABLE_NAME%
if errorlevel 1 (
    echo Failed to compile!
    exit /b 1
)

echo Compiled successfully!

if "%RUN_AFTER_BUILD%"=="true" (
    pushd build
    call "%EXECUTABLE_NAME%"
    popd
)
exit /b %ERRORLEVEL%
