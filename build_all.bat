@echo off
REM ===========================================================================
REM build_all.bat -- construit tout : bitstream + application, puis programme la carte
REM Double-clic possible : la fenetre reste ouverte a la fin.
REM Adapter XILINX / VER si Vivado n'est pas dans C:\Xilinx\...\2018.2
REM   build_all.bat          -> materiel + logiciel + programmation de la carte
REM   build_all.bat nobrd    -> materiel + logiciel seulement
REM ===========================================================================
set XILINX=C:\Xilinx
set VER=2018.2

cd /d "%~dp0"

echo === [1/3] Vivado : synthese, implementation, bitstream (10-20 min) ===
call "%XILINX%\Vivado\%VER%\settings64.bat" || goto :err
call vivado -mode batch -nojournal -log hw\build_hw.log -source hw\scripts\build_hw.tcl
if not exist hw\build\out\top.hdf goto :err_hw

echo === [2/3] SDK : BSP + application ===
call "%XILINX%\SDK\%VER%\settings64.bat"
call xsct sw\scripts\create_sdk.tcl > sw\create_sdk.log 2>&1
type sw\create_sdk.log | findstr /i "error erreur LOGICIEL"
if not exist sw\workspace\kws_app\Release\kws_app.elf goto :err_sw

if /I "%1"=="nobrd" goto :ok
echo === [3/3] Programmation de la carte (JTAG) ===
call xsct sw\scripts\run_on_board.tcl
if errorlevel 1 goto :err_brd

:ok
echo.
echo ==========================================================================
echo  TOUT EST OK. Regardez le terminal serie (PuTTY, 115200).
echo  Pour reprogrammer la carte seulement : run_board.bat
echo ==========================================================================
pause
exit /b 0

:err_hw
echo.
echo ECHEC MATERIEL : voir hw\build_hw.log (chercher ERROR)
pause
exit /b 1
:err_sw
echo.
echo ECHEC LOGICIEL : voir sw\create_sdk.log
pause
exit /b 1
:err_brd
echo.
echo ECHEC PROGRAMMATION : carte branchee / allumee ? cavalier JP5 sur JTAG ?
pause
exit /b 1
:err
echo.
echo ECHEC : Vivado introuvable dans %XILINX%\Vivado\%VER% (modifier XILINX/VER en haut du fichier)
pause
exit /b 1
