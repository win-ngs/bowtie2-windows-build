@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0bowtie2.ps1" %*
exit /b %ERRORLEVEL%
