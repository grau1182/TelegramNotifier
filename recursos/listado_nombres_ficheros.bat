@echo off
setlocal enabledelayedexpansion

set "SALIDA=listado_ficheros.txt"

if exist "%SALIDA%" del "%SALIDA%"

for /r %%F in (*) do (
    if /I not "%%~nxF"=="%SALIDA%" (
        echo %%~nxF>>"%SALIDA%"
    )
)

echo Listado generado en %SALIDA%
pause