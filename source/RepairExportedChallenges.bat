@echo off
set /p "mods_folder=Ruta de la carpeta mods de Isaac (o del pack exportado): "
set /p "save_path=Ruta a save1.dat (INTRO si esta junto a mods\data\challenge_maker): "
if "%save_path%"=="" (
  py -3 "%~dp0repair_exported_packs.py" "%mods_folder%"
) else (
  py -3 "%~dp0repair_exported_packs.py" "%mods_folder%" --save "%save_path%"
)
if errorlevel 1 echo Se necesita Python 3 para ejecutar esta reparacion.
pause
