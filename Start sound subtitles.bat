@echo off
rem Blackout - English text for the spoken moments without picture. Start this first, then play Blackout (see README.txt).
rem (-ExecutionPolicy Bypass only applies to this one script; nothing in Windows is changed.)
if not exist "%~dp0Blackout - sound subtitles.ps1" goto notextracted
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Blackout - sound subtitles.ps1"
exit /b %errorlevel%

:notextracted
echo The script 'Blackout - sound subtitles.ps1' is missing next to this file. First extract the
echo WHOLE zip file (right-click ^> Extract All). See README.txt.
echo.
pause
exit /b 1
