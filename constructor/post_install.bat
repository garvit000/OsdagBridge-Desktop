@echo off
setlocal

REM ---- Pip-only dependencies from the wheels bundled in the installer (offline) ----
set "WHEEL_DIR=%PREFIX%\osdagbridge_wheels"
if exist "%WHEEL_DIR%\" (
    echo Installing bundled openseespy/opsvis wheels...
    "%PREFIX%\python.exe" -m pip install --no-index --no-deps --find-links "%WHEEL_DIR%" --disable-pip-version-check --no-warn-script-location openseespy openseespywin opsvis
    if errorlevel 1 (
        echo WARNING: Could not install bundled openseespy/opsvis wheels.
        echo Analysis will not work until you run: pip install openseespy opsvis
    )
    rmdir /s /q "%WHEEL_DIR%"
)

REM ---- Shortcuts and Add/Remove Programs entry ----
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%PREFIX%\create_shortcuts.ps1" -InstallDir "%PREFIX%"

endlocal
exit /b 0
