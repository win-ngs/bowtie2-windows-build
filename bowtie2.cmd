@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\bowtie2.ps1" %*
exit /b %ERRORLEVEL%
