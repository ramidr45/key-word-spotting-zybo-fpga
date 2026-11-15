@echo off
set XILINX=C:\Xilinx
set VER=2018.2
cd /d "%~dp0"
call "%XILINX%\SDK\%VER%\settings64.bat"
call xsct sw\scripts\debug_boot.tcl > debug_boot.txt 2>&1
type debug_boot.txt
echo.
echo Resultat enregistre dans debug_boot.txt
pause
