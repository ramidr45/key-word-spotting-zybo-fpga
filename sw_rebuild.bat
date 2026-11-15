@echo off
REM sw_rebuild.bat -- recompile SEULEMENT le logiciel (C) et relance la carte (~3 min)
REM A utiliser quand seuls les fichiers de sw\src ont change (pas le VHDL).
set XILINX=C:\Xilinx
set VER=2018.2
cd /d "%~dp0"
if not exist hw\build\out\top.hdf (
  echo Materiel absent : lancez d'abord clean_rebuild.bat
  pause
  exit /b 1
)
call "%XILINX%\SDK\%VER%\settings64.bat"
echo === Compilation du logiciel ===
call xsct sw\scripts\create_sdk.tcl > sw\create_sdk.log 2>&1
type sw\create_sdk.log | findstr /i "error erreur LOGICIEL"
if not exist sw\workspace\kws_app\Release\kws_app.elf (
  echo ECHEC LOGICIEL : voir sw\create_sdk.log
  pause
  exit /b 1
)
echo === Programmation de la carte ===
call xsct sw\scripts\run_on_board.tcl
echo.
echo TERMINE : regardez PuTTY.
pause
