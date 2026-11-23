@echo off
setlocal
set "CAMPUSRUN_PS_DIR=%SystemRoot%\System32\WindowsPowerShell\v1.0"
set "PSModulePath=%CAMPUSRUN_PS_DIR%\Modules;%ProgramFiles%\WindowsPowerShell\Modules"
start "" "%CAMPUSRUN_PS_DIR%\powershell.exe" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File "%~dp0CampusRunControl.ps1"
