@echo off
for /r %%i in (*.frag, *.vert) do %VULKAN_SDK%\Bin\glslc %%i -o %%~ni.spv
