@echo off
REM open_sdk.bat -- ouvre le workspace SDK (projets hw0, bsp0, kws_app)
set XILINX=C:\Xilinx
set VER=2018.2
cd /d "%~dp0"
if not exist sw\workspace\kws_app (
  echo Workspace introuvable : lancez d'abord build_all.bat ou clean_rebuild.bat
  pause
  exit /b 1
)
call "%XILINX%\SDK\%VER%\settings64.bat"
start "" xsdk -workspace "%~dp0sw\workspace"
