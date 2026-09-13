@echo off
if not exist "%~dp0ChallengeMakerExporter.exe" (
  echo Copia estos archivos a la carpeta que contiene ChallengeMakerExporter.exe.
  pause
  exit /b 1
)
start "" /wait "%~dp0ChallengeMakerExporter.exe"
call "%~dp0RepairExportedChallenges.bat"
