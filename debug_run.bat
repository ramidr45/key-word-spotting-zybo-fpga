@echo off
REM debug_run.bat -- relance l'application sous debogueur et enregistre debug.txt
set XILINX=C:\Xilinx
set VER=2018.2
cd /d "%~dp0"
call "%XILINX%\SDK\%VER%\settings64.bat"
call xsct sw\scripts\debug_run.tcl > debug.txt 2>&1
type debug.txt
echo.
echo Resultat enregistre dans debug.txt
pause
