@echo off
REM run_board.bat -- reprogramme le FPGA et relance l'application (sans recompiler)
REM Double-clic possible. Ouvrir PuTTY (115200) AVANT.
set XILINX=C:\Xilinx
set VER=2018.2
cd /d "%~dp0"
call "%XILINX%\SDK\%VER%\settings64.bat"
call xsct sw\scripts\run_on_board.tcl
if errorlevel 1 (
  echo.
  echo ECHEC : carte branchee sur PROG/UART, allumee, cavalier JP5 sur JTAG ?
) else (
  echo.
  echo OK : application lancee, regardez PuTTY.
)
pause
