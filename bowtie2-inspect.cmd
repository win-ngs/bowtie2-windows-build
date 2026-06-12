@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\bowtie2-inspect.ps1" %*
exit /b %ERRORLEVEL%
