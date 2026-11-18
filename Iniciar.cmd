@echo off
setlocal
cd /d "%~dp0"
if not exist "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" (
  echo No se encontro Windows PowerShell. Esta aplicacion requiere Windows 10 u 11.
  pause
  exit /b 1
)
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0OptimizadorPc.ps1"
if errorlevel 1 (
  echo No se pudo abrir OptimizadorPc. Lee el mensaje anterior.
  pause
)
