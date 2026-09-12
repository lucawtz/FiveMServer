@echo off
setlocal
rem ------------------------------------------------------------------
rem FiveM Server - Start mit txAdmin (Standardmodus)
rem Arbeitsverzeichnis: Repo-Root. txAdmin legt seine Daten in <repo>\txData ab
rem und ist danach unter http://localhost:40120 erreichbar.
rem Beim ersten Start steht die PIN fuer txAdmin in dieser Konsole.
rem ------------------------------------------------------------------
for %%I in ("%~dp0..\..") do set "ROOT=%%~fI"
cd /d "%ROOT%"

if not exist "%ROOT%\artifacts\FXServer.exe" (
    echo [FEHLER] artifacts\FXServer.exe wurde nicht gefunden.
    echo          Bitte zuerst scripts\windows\install.bat ausfuehren.
    echo.
    pause
    exit /b 1
)

if not exist "%ROOT%\artifacts\VERSION.txt" (
    echo [WARNUNG] artifacts\VERSION.txt fehlt. Die Artifacts sind vermutlich unvollstaendig,
    echo           zum Beispiel nach einem abgebrochenen Entpacken. Bitte scripts\windows\install.bat
    echo           erneut ausfuehren, es laedt die Artifacts dann neu.
    echo.
)

if not exist "%ROOT%\server-data\resources\[cfx-default]\[managers]\spawnmanager\fxmanifest.lua" (
    echo [WARNUNG] Die Basis-Ressourcen aus cfx-server-data fehlen, zum Beispiel spawnmanager.
    echo           Der Server startet, aber im Spiel spawnt niemand. Bitte scripts\windows\install.bat
    echo           ohne -SkipResources ausfuehren.
    echo           Trotzdem starten: beliebige Taste. Abbrechen: Fenster schliessen.
    echo.
    pause
)

if not exist "%ROOT%\server-data\secrets.cfg" (
    echo [WARNUNG] server-data\secrets.cfg fehlt. Bitte secrets.cfg.example nach secrets.cfg kopieren
    echo           und den Lizenzschluessel eintragen. txAdmin startet trotzdem, der Spielserver
    echo           kann ohne Lizenzschluessel aber nicht hochfahren.
    echo.
) else (
    findstr /I /R /C:"^[ ]*sv_licenseKey.*changeme" /C:"^[ ]*set[ ][ ]*sv_licenseKey.*changeme" "%ROOT%\server-data\secrets.cfg" >nul 2>&1
    if not errorlevel 1 (
        echo [WARNUNG] In server-data\secrets.cfg steht sv_licenseKey noch auf "changeme".
        echo           Einen kostenlosen Schluessel gibt es unter https://portal.cfx.re/
        echo.
    )
)

echo.
echo  FiveM Server (txAdmin-Modus)
echo  Repo:    %ROOT%
echo  txData:  %ROOT%\txData
echo  txAdmin: http://localhost:40120   (PIN erscheint gleich hier in der Konsole)
echo  Hinweis: PIN abtippen, nicht mit der Maus markieren. Ein Klick ins Fenster haelt
echo           den Server an, bis du Esc drueckst.
echo  Beenden: Strg+C oder Fenster schliessen
echo.

rem txAdmin-Konfiguration per Umgebungsvariablen (TXHOST_*), die alten ConVars
rem txAdminPort/txDataPath gelten seit txAdmin 8 als veraltet. Profil bleibt "default".
set "TXHOST_DATA_PATH=%ROOT%\txData"
set "TXHOST_TXA_PORT=40120"

"%ROOT%\artifacts\FXServer.exe"
set "RC=%ERRORLEVEL%"

echo.
echo [INFO] FXServer wurde beendet (Exit-Code %RC%).
pause
exit /b %RC%
