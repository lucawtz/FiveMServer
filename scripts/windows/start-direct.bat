@echo off
setlocal
rem ------------------------------------------------------------------
rem FiveM Server - Direktstart OHNE txAdmin (schneller Entwicklungsmodus)
rem Arbeitsverzeichnis: server-data. Der Server liest server.cfg direkt
rem (inkl. exec secrets.cfg). Kein Webinterface, Konsole = Serverkonsole.
rem OneSync wird hier als Startargument (+set onesync on, vor +exec)
rem uebergeben und steht bewusst in KEINER cfg-Datei: txAdmin kommentiert
rem onesync-Zeilen in cfg-Dateien aus, die Einstellung wuerde sonst nach dem
rem ersten txAdmin-Start still verloren gehen. Im txAdmin-Modus (start.bat)
rem setzt txAdmin OneSync selbst (Settings / FXServer).
rem ------------------------------------------------------------------
for %%I in ("%~dp0..\..") do set "ROOT=%%~fI"
set "DATA=%ROOT%\server-data"

if not exist "%ROOT%\artifacts\FXServer.exe" (
    echo [FEHLER] artifacts\FXServer.exe wurde nicht gefunden.
    echo          Bitte zuerst scripts\windows\install.bat ausfuehren.
    echo.
    pause
    exit /b 1
)

if not exist "%DATA%\server.cfg" (
    echo [FEHLER] server-data\server.cfg wurde nicht gefunden.
    echo.
    pause
    exit /b 1
)

if not exist "%DATA%\secrets.cfg" (
    echo [FEHLER] server-data\secrets.cfg fehlt. Ohne Lizenzschluessel startet der Server nicht.
    echo          Bitte secrets.cfg.example nach secrets.cfg kopieren und sv_licenseKey eintragen:
    echo            copy "%DATA%\secrets.cfg.example" "%DATA%\secrets.cfg"
    echo          Einen kostenlosen Schluessel gibt es unter https://portal.cfx.re/
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

findstr /I /R /C:"^[ ]*sv_licenseKey.*changeme" /C:"^[ ]*set[ ][ ]*sv_licenseKey.*changeme" "%DATA%\secrets.cfg" >nul 2>&1
if not errorlevel 1 (
    echo [WARNUNG] In server-data\secrets.cfg steht sv_licenseKey noch auf "changeme".
    echo           Der Server wird den Start vermutlich mit einem Lizenzfehler abbrechen.
    echo.
)

findstr /R /C:"^ *set  *mysql_connection_string" "%DATA%\secrets.cfg" >nul 2>&1
if errorlevel 1 (
    echo [WARNUNG] In secrets.cfg fehlt mysql_connection_string. Qbox braucht die Datenbank: scripts\windows\setup-database.bat -Create -Import
    echo.
)

cd /d "%DATA%"

echo.
echo  FiveM Server (Direktmodus, ohne txAdmin)
echo  Arbeitsverzeichnis: %DATA%
echo  Verbinden im Spiel:  F8 druecken, dann: connect localhost:30120
echo  Beenden: Strg+C oder in der Serverkonsole "quit" eingeben
echo  Hinweis: Nicht mit der Maus ins Fenster klicken. Eine Markierung haelt den Server
echo           an, bis du Esc drueckst.
echo.

"%ROOT%\artifacts\FXServer.exe" +set onesync on +exec server.cfg
set "RC=%ERRORLEVEL%"

echo.
echo [INFO] FXServer wurde beendet (Exit-Code %RC%).
pause
exit /b %RC%
