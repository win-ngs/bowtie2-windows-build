@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\bowtie2-build.ps1" %*
exit /b %ERRORLEVEL%
