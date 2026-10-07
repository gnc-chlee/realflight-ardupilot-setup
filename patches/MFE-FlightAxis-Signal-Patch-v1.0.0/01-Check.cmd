@echo off
setlocal
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Patch-MFE-Signals.ps1" -Interactive %*
set "MFE_PATCH_RESULT=%errorlevel%"
echo.
echo Exit code: %MFE_PATCH_RESULT%
pause
exit /b %MFE_PATCH_RESULT%
