@echo off
setlocal
set "CAMPUSRUN_PS_DIR=%SystemRoot%\System32\WindowsPowerShell\v1.0"
set "PSModulePath=%CAMPUSRUN_PS_DIR%\Modules;%ProgramFiles%\WindowsPowerShell\Modules"
"%CAMPUSRUN_PS_DIR%\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Setup.ps1" %*
set "CAMPUSRUN_EXIT=%errorlevel%"
if /i "%~1"=="-CheckOnly" exit /b %CAMPUSRUN_EXIT%
pause
exit /b %CAMPUSRUN_EXIT%
