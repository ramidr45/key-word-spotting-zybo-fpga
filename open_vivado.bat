@echo off
REM open_vivado.bat -- ouvre le projet Vivado genere par build_all.bat
set XILINX=C:\Xilinx
set VER=2018.2
cd /d "%~dp0"
if not exist hw\build\kws_zybo.xpr (
  echo Projet introuvable : lancez d'abord build_all.bat ou clean_rebuild.bat
  pause
  exit /b 1
)
call "%XILINX%\Vivado\%VER%\settings64.bat"
start "" vivado hw\build\kws_zybo.xpr
