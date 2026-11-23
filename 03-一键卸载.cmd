@echo off
setlocal
set "CAMPUS_RUN_UNINSTALL_SCRIPT=%~dp0Uninstall.ps1"
cd /d "%TEMP%" || exit /b 1
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe' -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File ""'+$env:CAMPUS_RUN_UNINSTALL_SCRIPT+'""') -Verb RunAs"
