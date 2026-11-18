@echo off
setlocal
cd /d "%~dp0"
set "OPTIMIZADORPC_LAUNCHER=%~dp0OptimizadorPc.ps1"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Command "$a = '-NoProfile -STA -ExecutionPolicy Bypass -File ' + [char]34 + $env:OPTIMIZADORPC_LAUNCHER + [char]34; try { Start-Process -FilePath ($env:SystemRoot + '\System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList $a -Verb RunAs -ErrorAction Stop } catch { Write-Host $_.Exception.Message; exit 1 }"
if errorlevel 1 pause
