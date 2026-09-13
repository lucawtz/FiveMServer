@echo off
setlocal
rem ------------------------------------------------------------------
rem FiveM Server - Datenbank einrichten (Wrapper fuer setup-database.ps1)
rem Alle Parameter werden an setup-database.ps1 durchgereicht. Beispiele:
rem   setup-database.bat -InstallMariaDB     (MariaDB per winget installieren)
rem   setup-database.bat -Create -Import     (DB + User anlegen, SQL importieren)
rem   setup-database.bat                     (nur ausstehende SQL-Dateien importieren)
rem   setup-database.bat -DryRun             (nur anzeigen, nichts aendern)
rem   setup-database.bat -MarkApplied -Only [vendor]/[npwd]/npwd/import.sql
rem   setup-database.bat -Check              (nur database.txt pruefen)
rem Hilfe: powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows\setup-database.ps1 -?
rem ------------------------------------------------------------------
cd /d "%~dp0..\.."

echo.
echo  FiveM Server - Datenbank (MariaDB)
echo  Repo: %CD%
echo.

where powershell >nul 2>&1
if errorlevel 1 (
    echo [FEHLER] powershell.exe wurde nicht gefunden. Windows PowerShell 5.1 ist Voraussetzung.
    echo.
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-database.ps1" %*
set "RC=%ERRORLEVEL%"

echo.
if "%RC%"=="0" (
    echo [OK] Datenbank-Schritt abgeschlossen.
) else if "%RC%"=="2" (
    echo [FEHLER] Datenbank nicht erreichbar, Anmeldung fehlgeschlagen oder MariaDB zu alt. Meldungen oben pruefen.
) else if "%RC%"=="3" (
    echo [FEHLER] SQL-Import fehlgeschlagen. Meldungen oben pruefen.
) else (
    echo [FEHLER] Abbruch mit Exit-Code %RC%.
)
echo.
pause
exit /b %RC%
