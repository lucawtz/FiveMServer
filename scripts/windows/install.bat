@echo off
setlocal
rem ------------------------------------------------------------------
rem FiveM Server - Installation unter Windows (Wrapper fuer install.ps1)
rem Doppelklick reicht. Alle Parameter werden an install.ps1 durchgereicht:
rem   install.bat -Channel latest
rem   install.bat -UpdateArtifacts -UpdateResources
rem   install.bat -UpdateArtifacts -SkipResources   (nur die Artifacts aktualisieren)
rem ------------------------------------------------------------------
cd /d "%~dp0..\.."

echo.
echo  FiveM Server - Installation (Windows)
echo  Repo: %CD%
echo.

where powershell >nul 2>&1
if errorlevel 1 (
    echo [FEHLER] powershell.exe wurde nicht gefunden. Windows PowerShell 5.1 ist Voraussetzung.
    echo.
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
set "RC=%ERRORLEVEL%"

echo.
if "%RC%"=="0" (
    echo [OK] Installation abgeschlossen. Naechster Schritt: server-data\secrets.cfg ausfuellen, dann start.bat ausfuehren.
) else if "%RC%"=="2" (
    echo [WARNUNG] Installation abgeschlossen, aber die Ressourcen sind unvollstaendig. Bitte die Warnungen oben pruefen.
) else (
    echo [FEHLER] Installation mit Exit-Code %RC% abgebrochen. Bitte die Meldungen oben pruefen.
)
echo.
pause
exit /b %RC%
