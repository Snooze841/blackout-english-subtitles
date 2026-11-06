@echo off
rem Blackout - English subtitles: starts the PowerShell script (see README.txt).
rem (-ExecutionPolicy Bypass only applies to this one script; nothing in Windows is changed.)
if not exist "%~dp0Blackout - English subtitles.ps1" goto notextracted
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Blackout - English subtitles.ps1" %*
exit /b %errorlevel%

:notextracted
echo The script 'Blackout - English subtitles.ps1' is missing next to this file. First extract
echo the WHOLE zip file (right-click ^> Extract All) and then start 'Patch Blackout.bat' in the
echo extracted folder. See README.txt.
echo.
echo (Het script ontbreekt naast dit bestand: pak eerst het HELE zip-bestand uit - rechtermuisknop
echo ^> Alles uitpakken - en start daarna 'Patch Blackout.bat' in de uitgepakte map. Zie LEESMIJ.txt.)
echo.
pause
exit /b 1
