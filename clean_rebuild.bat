@echo off
REM clean_rebuild.bat -- efface tout ce qui a ete genere et reconstruit le projet depuis zero
REM (materiel + logiciel + programmation de la carte). Double-clic possible.
cd /d "%~dp0"
echo Suppression des anciens resultats (hw\build, sw\workspace, logs)...
if exist hw\build rmdir /s /q hw\build
if exist sw\workspace rmdir /s /q sw\workspace
if exist sw\boot rmdir /s /q sw\boot
del /q hw\build_hw.log sw\create_sdk.log 2>nul
del /q vivado*.jou vivado*.log 2>nul
if exist .Xil rmdir /s /q .Xil
echo Nettoyage termine. Reconstruction complete (15-25 min)...
call build_all.bat
