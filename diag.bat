@echo off
REM diag.bat -- diagnostic de la carte (a lancer apres run_board.bat, PuTTY ouvert)
set XILINX=C:\Xilinx
set VER=2018.2
cd /d "%~dp0"
call "%XILINX%\SDK\%VER%\settings64.bat"
call xsct sw\scripts\diag_board.tcl > diag.txt 2>&1
type diag.txt
echo.
echo Resultat enregistre dans diag.txt
pause
