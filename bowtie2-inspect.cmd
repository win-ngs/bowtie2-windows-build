@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0bowtie2-inspect.ps1" %*
exit /b %ERRORLEVEL%
