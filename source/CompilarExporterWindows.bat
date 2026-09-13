@echo off
setlocal
set "compiler="
if exist "%ProgramFiles%\Go\bin\go.exe" set "compiler=%ProgramFiles%\Go\bin\go.exe"
if not defined compiler for %%G in (go.exe) do if not "%%~$PATH:G"=="" set "compiler=%%~$PATH:G"
if not defined compiler (
  echo Necesitas instalar el SDK completo de Go para Windows.
  echo El archivo go.exe por si solo no incluye el compilador ni la libreria estandar.
  pause
  exit /b 1
)
pushd "%~dp0source" || exit /b 1
"%compiler%" build -ldflags="-H windowsgui" -o "%~dp0ChallengeMakerExporter.new.exe" main.go
set "build_result=%errorlevel%"
popd
if not "%build_result%"=="0" (
  echo Error de compilacion: no se ha cambiado el exporter anterior.
  pause
  exit /b %build_result%
)
if exist "%~dp0ChallengeMakerExporter.exe" copy /y "%~dp0ChallengeMakerExporter.exe" "%~dp0ChallengeMakerExporter.previous.exe" >nul
move /y "%~dp0ChallengeMakerExporter.new.exe" "%~dp0ChallengeMakerExporter.exe" >nul
if errorlevel 1 (
  echo No se pudo reemplazar el exporter. Cierra su ventana y ejecuta otra vez este archivo.
  pause
  exit /b 1
)
echo ChallengeMakerExporter.exe compilado con las correcciones integradas.
echo Puedes usarlo directamente para las proximas exportaciones.
pause
