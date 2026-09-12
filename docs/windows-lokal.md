# Windows: lokal installieren und testen

Diese Anleitung beschreibt den lokalen Testbetrieb auf einem Windows-10/11-PC. Alles läuft mit
Bordmitteln (Windows PowerShell 5.1) plus Git.

## Voraussetzungen

- 64-Bit-Windows. `install.ps1` warnt bei 32-Bit.
- Git im PATH: `winget install --id Git.Git -e`, danach ein neues Terminal öffnen.
- Ein kurzer Pfad ohne Umlaute, Leerzeichen sind erlaubt, z. B. `C:\FiveMServer`.
  txAdmin bricht mit einem Fehler ab, wenn `artifacts\` oder `txData\` Nicht-ASCII-Zeichen im Pfad haben.
  `install.ps1` warnt in diesem Fall. Auch sehr tiefe Pfade vermeiden (260-Zeichen-Limit beim Entpacken).
- Optional 7-Zip (`winget install --id 7zip.7zip -e`), nur für `-ArchiveFormat 7z`.
- Ein Lizenzschlüssel aus <https://portal.cfx.re/> (Servers -> Registration Keys -> "Generate Key +").

## Installation

`scripts\windows\install.bat` doppelklicken. Der Wrapper wechselt in den Repo-Root, prüft, dass
`powershell.exe` vorhanden ist, und startet:

```
powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\windows\install.ps1" <alle Parameter>
```

Am Ende meldet der Wrapper `[OK]` (Exit 0), `[WARNUNG]` (Exit 2: einzelne Manifest-Einträge fehlgeschlagen)
oder `[FEHLER] ... Exit-Code N` und wartet auf einen Tastendruck. Alle Parameter werden durchgereicht,
zum Beispiel aus einer Eingabeaufforderung:

```
scripts\windows\install.bat -Channel latest -UpdateArtifacts
scripts\windows\install.bat -UpdateResources
scripts\windows\install.bat -SkipResources
```

### Was install.ps1 macht

Vorab-Prüfungen: PowerShell >= 5, 64-Bit, ASCII-Pfad (Warnung), `server-data\` vorhanden (sonst Abbruch),
TLS 1.2 aktivieren.

Schritt 1/3, Artifacts:

- Existiert `artifacts\FXServer.exe` und wurde weder `-UpdateArtifacts` noch `-ForceArtifacts` angegeben,
  wird der Download übersprungen (die installierte Version steht in `artifacts\VERSION.txt`).
- Sonst fragt das Skript `https://changelogs-live.fivem.net/api/changelog/versions/win32/server` ab und liest
  die Schlüssel `<channel>` (Build-Nummer) und `<channel>_download` (URL).
- Ist die installierte Version identisch und `-ForceArtifacts` nicht gesetzt: "bereits aktuell", nichts zu tun.
- Installation: Abbruch, wenn ein Prozess `FXServer` läuft. Download nach `%TEMP%\fivem-artifacts-xxxxxxxx\`
  (Abbruch unter 1 MB). Ein `artifacts\txData` (entsteht unter Windows normalerweise nicht: ein manueller
  Start von `FXServer.exe` schreibt nach `<repo>\txData`, weil txAdmin standardmäßig eine Ebene über dem
  FXServer-Ordner ablegt; der Schutz greift nur bei abweichenden Layouts oder von Linux kopierten Ordnern)
  wird nach `<repo>\artifacts.txData.tmp` geparkt und danach zurückgelegt. Der restliche Inhalt von
  `artifacts\` wird gelöscht (kein `artifacts.bak` unter Windows), das Archiv entpackt, ein eventueller
  Wrapper-Ordner aufgelöst. Danach wird `artifacts\VERSION.txt` geschrieben:

  ```
  channel=recommended
  version=35245
  url=https://runtime.fivem.net/artifacts/fivem/build_server_windows/master/....../server.zip
  downloaded_at=2026-09-12T11:40:02Z
  platform=windows
  ```

- `<repo>\txData` wird nie angefasst.

Schritt 2/3, Ressourcen: ruft `install-resources.ps1 -Update:<UpdateResources> -Force:<ForceResources>` auf
(siehe unten). Exit 2 dort wird zur Warnung und zum Gesamt-Exit 2, andere Fehler brechen ab.

Schritt 3/3, `secrets.cfg`: fehlt `server-data\secrets.cfg`, wird sie aus `secrets.cfg.example` kopiert.
Eine vorhandene Datei bleibt unverändert. Dann prüft das Skript die erste aktive Zeile
`sv_licenseKey <wert>` bzw. `set sv_licenseKey <wert>`; fehlt sie, ist sie leer oder `changeme`, gibt es die
Warnung `In secrets.cfg fehlt noch der Lizenzschlüssel (sv_licenseKey steht auf 'changeme' oder ist leer).`
und am Ende noch einmal `WICHTIG: Ohne Lizenzschlüssel startet der Spielserver nicht.`

Zum Schluss folgt eine Zusammenfassung (Repo, Artifacts, Ressourcen, secrets.cfg) und die nächsten Schritte.

### Parameter von install.ps1

| Parameter               | Bedeutung                                                                                                   |
|-------------------------|-------------------------------------------------------------------------------------------------------------|
| `-Channel <name>`       | `recommended` (Standard), `latest` oder `optional`. Ungültige Werte lehnt PowerShell ab (Exit 1).          |
| `-ArchiveFormat <fmt>`  | `auto` (Standard: URL aus der API, derzeit `server.zip`), `zip` (URL auf `.zip` umschreiben), `7z` (URL auf `.7z` umschreiben, kleinerer Download, braucht 7-Zip). |
| `-UpdateArtifacts`      | API abfragen und nur bei abweichender Version neu laden.                                                    |
| `-ForceArtifacts`       | Immer neu laden und installieren.                                                                           |
| `-UpdateResources`      | Wird als `-Update` an `install-resources.ps1` gereicht (`git pull --ff-only` für Git-Einträge).             |
| `-ForceResources`       | Wird als `-Force` an `install-resources.ps1` gereicht (alles löschen und neu holen).                        |
| `-SkipResources`        | Schritt 2 komplett überspringen.                                                                            |

`Get-Help .\scripts\windows\install.ps1 -Full` zeigt die eingebaute Hilfe. Exit-Codes: 0 ok, 1 Abbruch mit
Fehler, 2 fertig, aber mindestens ein Manifest-Eintrag fehlgeschlagen.

Zip-Archive werden mit .NET (`System.IO.Compression.ZipFile`) entpackt. Für `.7z` sucht das Skript in dieser
Reihenfolge: `7z` im PATH, `%ProgramFiles%\7-Zip\7z.exe`, `%ProgramFiles(x86)%\7-Zip\7z.exe`, zuletzt
`<repo>\tools\7zr.exe` (wird bei Bedarf von <https://www.7-zip.org/a/7zr.exe> geladen). Aufruf:
`7z x <archiv> -o<repo>\artifacts -y`; Exit 1 von 7-Zip ist eine Warnung, größer 1 ein Abbruch.

## Ressourcen: install-resources.ps1

Wird von `install.ps1` aufgerufen, geht aber auch einzeln:

```
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows\install-resources.ps1 -Update
```

| Parameter               | Bedeutung                                                                                       |
|-------------------------|-------------------------------------------------------------------------------------------------|
| `-Update`               | Bei vorhandenen Git-Zielen `git pull --ff-only`. Zip-Ziele bleiben unverändert.                 |
| `-Force`                | `[cfx-default]` neu installieren, alle Manifest-Ziele löschen und neu klonen bzw. neu laden.     |
| `-ManifestPath <datei>` | Anderes Manifest. Standard `<repo>\server-data\resources.txt`. Ein explizit angegebenes, fehlendes Manifest bricht ab (Exit 1); fehlt das Standard-Manifest, gibt es nur eine Warnung (Exit 0). |

Ablauf:

1. `server-data\resources\[cfx-default]` anlegen. Ist dort schon etwas drin und `-Force` nicht gesetzt,
   wird übersprungen. Sonst `git clone --depth 1 https://github.com/citizenfx/cfx-server-data.git` in
   `%TEMP%\fivem-cfx-default-xxxxxxxx\` und `resources\*` nach `[cfx-default]` kopieren. Der leere
   `[local]`-Ordner aus dem Repo wird bewusst nicht übernommen. Ergebnis: `[gamemodes] [gameplay] [managers] [system] [test]`.
2. Manifest verarbeiten (Format in [ressourcen.md](ressourcen.md)). Alle Einträge werden abgearbeitet, auch
   wenn einzelne fehlschlagen. Zusammenfassung: `Manifest-Einträge: N gesamt, a installiert, b aktualisiert,
   c übersprungen, d fehlgeschlagen` plus Liste der Fehler.

Fehlt `git`, bricht schon `install.ps1` vor dem Artifact-Download ab: `git wurde nicht gefunden, wird aber
für die Ressourcen benötigt. Bitte installieren: winget install Git.Git  (danach ein neues Terminal öffnen)
oder mit -SkipResources nur die Artifacts laden.` Startest du `install-resources.ps1` einzeln, lautet die
Meldung `git wurde nicht gefunden. Bitte installieren: winget install Git.Git  (danach ein neues Terminal
öffnen).` Das Skript setzt `GIT_TERMINAL_PROMPT=0`, private Repos schlagen also sofort fehl statt nach einem
Passwort zu fragen.

Exit-Codes: 0 ok, 1 Abbruch (git fehlt beim Basis-Schritt, Klonen von cfx-server-data fehlgeschlagen,
explizites Manifest fehlt, `server-data` fehlt), 2 mindestens ein Manifest-Eintrag fehlgeschlagen.

## Starten

### start.bat: txAdmin-Modus (Standard)

`scripts\windows\start.bat` doppelklicken. Das Skript:

1. wechselt in den Repo-Root (Arbeitsverzeichnis),
2. prüft `artifacts\FXServer.exe` (fehlt: `[FEHLER] ... install.bat ausfuehren`, Exit 1),
3. warnt, wenn `server-data\secrets.cfg` fehlt oder noch `changeme` enthält (txAdmin startet trotzdem),
4. setzt die Umgebungsvariablen `TXHOST_DATA_PATH=<repo>\txData` und `TXHOST_TXA_PORT=40120`,
5. startet `artifacts\FXServer.exe` ohne Argumente. Ohne `+exec` startet FXServer automatisch txAdmin.

Das txAdmin-Profil landet in `<repo>\txData\default\`. Nach dem Ende des Servers meldet das Skript
`[INFO] FXServer wurde beendet (Exit-Code N)` und wartet auf einen Tastendruck.

Hinweis: `start.bat` nutzt bewusst die `TXHOST_*`-Umgebungsvariablen, weil txAdmin 8.x die ConVars
`txAdminPort`, `txDataPath` und `serverProfile` als veraltet meldet. Mit `-Channel optional` (Build 7290,
txAdmin 7.0.0) werden die Variablen ignoriert, die Standardwerte (Port 40120, `txData` neben `artifacts\`)
ergeben aber denselben Pfad.

### Erster Start mit txAdmin

1. In der Konsole erscheint eine PIN. <http://localhost:40120> öffnen.
2. PIN eingeben, "Link Account", mit dem Cfx.re-Account anmelden und bestätigen, ein Admin-Passwort setzen.
3. Servername vergeben, dann als Deployment-Typ **"Existing Server Data"** wählen
   ("Only select this option if you already have a server.cfg and a resources folder").
4. Server Data Folder: `C:\FiveMServer\server-data` (txAdmin prüft, dass darin `resources\` liegt und nicht leer ist).
   CFG File: `server.cfg`. Speichern, der Server startet.
5. Im Spiel: `F8`, dann `connect localhost:30120`. Im Chat `/hallo` eingeben.

OneSync: steht absichtlich in keiner cfg-Datei, weder in `server.cfg` noch in `secrets.cfg`. Im txAdmin-Modus
verwaltet txAdmin OneSync selbst (Settings > FXServer, Standard "on"). Schreibst du trotzdem `set onesync on`
in eine der beiden Dateien, kommentiert txAdmin die Zeile beim ersten Start mit `## [txAdmin CFG validator]: ...`
aus (auch in per `exec` geladenen Dateien) und `server.cfg` wäre in Git dauerhaft geändert. Der Direktmodus
bekommt OneSync stattdessen als Startargument von `start-direct.bat` (siehe unten); `sv_maxclients 32` und
ox_lib brauchen es.

Der Lizenzschlüssel wird bei "Existing Server Data" nicht abgefragt. Er kommt über `exec secrets.cfg` in
`server.cfg` herein. Nur der Recipe-Deployer für komplett neue Server fragt nach dem Key.

txAdmin-Einstellungen wie Server Data Folder und CFG-Pfad änderst du später unter Settings > FXServer.
Die Warnung, dass `txAdminPort` und Co. veraltet sind, erscheint bei `start.bat` nicht (Umgebungsvariablen).

### start-direct.bat: Direktmodus ohne txAdmin

Für schnelles Entwickeln mit der Serverkonsole im Fenster. Das Skript:

1. prüft `artifacts\FXServer.exe`, `server-data\server.cfg` und `server-data\secrets.cfg`
   (jeweils `[FEHLER]`, Exit 1; bei fehlender `secrets.cfg` wird der `copy`-Befehl angezeigt),
2. warnt, wenn `sv_licenseKey` noch `changeme` ist,
3. wechselt nach `server-data\` und startet `..\artifacts\FXServer.exe +set onesync on +exec server.cfg`.

`+set onesync on` steht bewusst vor `+exec server.cfg`: so ist OneSync an, ohne dass eine cfg-Datei die Zeile
enthalten muss (txAdmin würde sie dort auskommentieren). Von Hand entsprechend
`cd server-data && ..\artifacts\FXServer.exe +set onesync on +exec server.cfg`.
Konsole beenden mit `quit` oder Strg+C. Kein Webinterface, kein txData.

## Aktualisieren

- Artifacts auf den aktuellen Build des Kanals: `install.bat -UpdateArtifacts`
  (Kanal wechseln: `install.bat -Channel latest -UpdateArtifacts`). Server vorher beenden, sonst bricht das
  Skript ab ("FXServer.exe läuft gerade").
- Neu erzwingen, z. B. nach kaputtem Entpacken: `install.bat -ForceArtifacts`.
- Git-Ressourcen aus `resources.txt` aktualisieren: `install.bat -UpdateResources`.
- Alle Fremd-Ressourcen und `[cfx-default]` frisch holen: `install.bat -ForceResources`.
- Eigener Code: `git pull`, dann bei Bedarf `install.bat -UpdateResources`.

Während eines Artifact-Updates ist `artifacts\` kurz leer. Schlägt das Entpacken fehl, einfach
`install.bat -ForceArtifacts` erneut ausführen. Bleibt nach einem abgebrochenen Lauf der Ordner
`<repo>\artifacts.txData.tmp` übrig, legt der nächste Artifact-Download (`install.bat -UpdateArtifacts` /
`-ForceArtifacts`) ihn automatisch nach `artifacts\txData` zurück; ohne Artifact-Download wird er ignoriert.
Nur wenn inzwischen wieder ein `artifacts\txData` entstanden ist, bricht `install.ps1` mit
`Es existiert bereits '...\artifacts.txData.tmp'` ab; dann beide Ordner von Hand zusammenführen.

## Datenbank lokal (optional)

Nur nötig für oxmysql und Frameworks. Zwei Wege:

- MariaDB nativ: `winget install --id MariaDB.Server -e`. Der Installer fragt nach einem root-Passwort und
  richtet den Dienst `MariaDB` ein. Client: `"C:\Program Files\MariaDB 12.3\bin\mariadb.exe"` (Versionsnummer
  im Pfad anpassen). Datenbank und User anlegen, siehe [frameworks.md](frameworks.md).
- Docker Desktop: nur den `db`-Service aus `docker/docker-compose.yml` starten. Vorher `cp .env.example .env`
  (bzw. `copy .env.example .env`) und darin `MYSQL_ROOT_PASSWORD`, `MYSQL_PASSWORD` sowie bei Bedarf
  `MYSQL_DATABASE`/`MYSQL_USER` setzen (die Compose-Datei bricht ohne diese Werte ab), in der Compose-Datei die
  Zeilen `ports: - "127.0.0.1:3306:3306"` beim `db`-Service einkommentieren und aus dem Repo-Root starten:

  ```
  docker compose --env-file .env -f docker/docker-compose.yml up -d db
  ```

  Datenbank und User kommen aus `MYSQL_DATABASE`, `MYSQL_USER`, `MYSQL_PASSWORD` der `.env`. Verbindungs-String
  dann mit Host `localhost`.

Grafischer Client: `winget install --id HeidiSQL.HeidiSQL -e`.

## Fehlerbilder

| Symptom                                                                 | Ursache und Lösung                                                                                       |
|-------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------|
| `git wurde nicht gefunden, wird aber für die Ressourcen benötigt`       | Git installieren (`winget install Git.Git`), neues Terminal öffnen, `install.bat` erneut (oder `-SkipResources`). |
| `Der Repo-Pfad enthält Sonderzeichen oder Umlaute`                      | Repo nach `C:\FiveMServer` verschieben, txAdmin akzeptiert nur ASCII-Pfade.                              |
| `FXServer.exe läuft gerade (PID ...)`                                   | Serverfenster schließen, dann Update erneut.                                                             |
| `In secrets.cfg fehlt noch der Lizenzschlüssel` / `no license key was specified` | `secrets.cfg` bearbeiten. Kein Key in `server.cfg`, kein Key in txAdmin.                          |
| Windows-Firewall-Dialog beim ersten Start                               | "Zugriff zulassen" für private Netzwerke.                                                                |
| Freunde kommen nicht drauf                                              | Router: 30120 TCP und UDP auf deinen PC weiterleiten; Firewall-Regel für `FXServer.exe` prüfen.          |
| `Could not contact the server browser`                                  | Lokal normal. `#sv_master1 ""` in `secrets.cfg` einkommentieren (Server erscheint dann als privat).       |
| txAdmin: `port 40120 ... dedicated for txAdmin`                         | 40120 bis 40150 nie als Spielport verwenden. Standard 30120 lassen.                                       |
| `## [txAdmin CFG validator]` vor einer `onesync`-Zeile                  | txAdmin verwaltet OneSync selbst. Zeile nicht wieder einkommentieren; `start-direct.bat` übergibt `+set onesync on` als Startargument. |
| `Es existiert bereits '...\artifacts.txData.tmp'`                       | Rest eines abgebrochenen Laufs und daneben ein neues `artifacts\txData`: beide Ordner von Hand zusammenführen, siehe Abschnitt Aktualisieren. |
| Manifest-Eintrag `git clone fehlgeschlagen`                             | `[ref]` muss Branch oder Tag sein, kein Commit-Hash. URL prüfen, private Repos brauchen Zugangsdaten.     |
