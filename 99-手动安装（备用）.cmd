@echo off
setlocal
set "CAMPUSRUN_PS_DIR=%SystemRoot%\System32\WindowsPowerShell\v1.0"
set "PSModulePath=%CAMPUSRUN_PS_DIR%\Modules;%ProgramFiles%\WindowsPowerShell\Modules"
"%CAMPUSRUN_PS_DIR%\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-Apps.ps1"
set "CAMPUSRUN_EXIT=%errorlevel%"
pause
exit /b %CAMPUSRUN_EXIT%
