# FiveM Server (FXServer + txAdmin + Qbox)

Ein versionierbares Grundgerüst für einen privaten deutschen Roleplay-Server. Du entwickelst und testest
lokal auf deinem Windows-PC und schiebst denselben Stand später unverändert auf einen
Linux-VPS (systemd + txAdmin). Docker Compose ist als zweiter Weg für Linux dabei.

Aktiv ist das Framework **Qbox** mit **MariaDB** (Übersetzung des offiziellen Qbox-txAdmin-Rezepts,
siehe [docs/frameworks.md](docs/frameworks.md)).

Was das Repo mitbringt:

- Skripte, die die FXServer-Artifacts über die offizielle Changelog-API laden und aktuell halten
- die Standard-Ressourcen aus `cfx-server-data` sowie ein Manifest (`resources.txt`) mit rund 80 Einträgen für Qbox und seine Ressourcen
- ein SQL-Manifest (`database.txt`) und `setup-database` für Windows und Linux: MariaDB einrichten, SQL-Dateien genau einmal importieren
- eine kommentierte `server.cfg` (deutsch) mit `permissions.cfg`, `ox.cfg`, `voice.cfg`, `misc.cfg` plus eine getrennte, nicht committete `secrets.cfg`
- eine Beispiel-Ressource `hello-world` unter `server-data/resources/[local]/`
- ein Linux-Installer (User, MariaDB, systemd, sudoers, ufw) und ein `deploy.sh` für GitHub Actions
- Docker-Image und Compose-Datei mit MariaDB 12.3

Inhalte auf dem Server: nur GTA-Lore-Marken und eigene Designs, keine echten Marken oder Fahrzeuge
(auch nicht auf privaten Servern), siehe [docs/inhalte-regeln.md](docs/inhalte-regeln.md).

## Voraussetzungen

Immer:

- Ein kostenloser Cfx.re-Account und ein Lizenzschlüssel: <https://portal.cfx.re/> -> Servers -> Registration Keys -> "Generate Key +". Es wird nur ein Anzeigename abgefragt, keine IP-Bindung.
- Git.
- MariaDB ab 10.9 (empfohlen 12.3 LTS). MySQL und XAMPP unterstützt Qbox nicht. Die Skripte installieren und prüfen das.

Windows (lokal testen):

- Windows 10/11 64-Bit mit Windows PowerShell 5.1 (ist vorinstalliert).
- Git: `winget install --id Git.Git -e` (danach ein neues Terminal öffnen).
- winget ("App Installer" aus dem Microsoft Store) für die MariaDB-Installation per `setup-database.bat -InstallMariaDB`.
- 7-Zip ist optional. Standardmäßig wird `server.zip` geladen und ohne Zusatztools entpackt.
- GTA V und der FiveM-Client auf demselben PC, um dich zu verbinden.
- Ein kurzer Pfad ohne Umlaute und andere Nicht-ASCII-Zeichen (Leerzeichen sind erlaubt), z. B. `C:\FiveMServer`. txAdmin startet nicht, wenn der Pfad zu `artifacts\` oder `txData\` Nicht-ASCII-Zeichen enthält.

Linux (VPS):

- Ubuntu 24.04 x86_64 (liefert MariaDB 10.11), root-Zugang per SSH. Debian 12 sollte ebenfalls funktionieren.
  Ubuntu 22.04 liefert MariaDB 10.6, dort MariaDB aus dem offiziellen Repository installieren
  ([docs/datenbank.md](docs/datenbank.md#welche-version)).
- Empfehlung: mindestens 2 vCPU und 4 GB RAM, mit Qbox und Datenbank eher mehr. Offizielle Mindestwerte gibt es nicht.
- systemd. Die Skripte installieren `git curl xz-utils unzip ca-certificates sudo` und MariaDB selbst.

## Ordnerstruktur

```
README.md
.gitignore                     Schließt Secrets, Artifacts, txData und installierte Fremd-Ressourcen aus
.gitattributes                 Zeilenenden pro Dateityp (LF; .ps1/.bat CRLF)
.editorconfig                  Einrückung und Zeilenenden für Editoren
.env.example                   Nur für Docker Compose (Lizenz, RCON, MariaDB)
.dockerignore                  Docker-Build-Kontext: nur docker/entrypoint.sh geht ins Image
server-data/
  server.cfg                   Gemeinsame Konfiguration (Qbox), committet, lädt die cfg-Dateien und secrets.cfg
  permissions.cfg              ACE-Rechte (admin > mod > support)
  ox.cfg                       ox_lib, ox_target, ox_inventory
  voice.cfg                    Sprachchat pma-voice
  misc.cfg                     weitere Server-Convars (fast alle auskommentiert)
  secrets.cfg.example          Vorlage für secrets.cfg (Lizenz, Datenbank, RCON, Tokens); secrets.cfg selbst ist gitignored
  resources.txt                Manifest für Fremd-Ressourcen (git/zip/copy), Qbox-Rezept
  database.txt                 SQL-Dateien für den Import, in Reihenfolge
  resources/
    [local]/                   Deine eigenen Ressourcen (committet), enthält hello-world
    [cfx-default]/             Standard-Ressourcen aus cfx-server-data (gitignored, Installer)
    [vendor]/                  Qbox und Zusatz-Ressourcen aus resources.txt (gitignored, Installer)
artifacts/                     FXServer-Binaries (gitignored). Windows: FXServer.exe, Linux: run.sh + alpine/
artifacts.bak/                 Linux: vorherige Artifact-Version nach einem Update (gitignored)
tools/                         Windows: 7zr.exe, falls per -ArchiveFormat 7z geladen (gitignored)
txData/                        txAdmin-Profil, Admins, Allowlist, Logs (gitignored, niemals löschen)
scripts/
  windows/                     install.bat, install.ps1, install-resources.ps1, setup-database.bat, setup-database.ps1, start.bat, start-direct.bat
  linux/                       lib.sh, install.sh, update-artifacts.sh, install-resources.sh, setup-database.sh, deploy.sh, fxserver.service.template
docker/                        Dockerfile, docker-compose.yml, entrypoint.sh
docs/                          Ausführliche Anleitungen (siehe unten), inkl. entscheidungen.md
.github/workflows/             ci.yml (Lint, Manifest-Prüfung), deploy.yml (SSH-Deploy auf den VPS)
```

## Schnellstart Windows

1. Repo klonen, am besten in einen kurzen Pfad:

   ```
   git clone https://github.com/<dein-account>/<dein-repo>.git C:\FiveMServer
   ```

2. `scripts\windows\install.bat` doppelklicken. Das Skript lädt die Artifacts (Kanal `recommended`),
   klont `cfx-server-data` nach `[cfx-default]`, installiert Qbox und alle Ressourcen aus `resources.txt` und
   legt `server-data\secrets.cfg` aus der Vorlage an. Die Warnung, dass `mysql_connection_string` fehlt, ist an
   dieser Stelle normal.
3. MariaDB installieren, in einer Eingabeaufforderung im Repo-Ordner:

   ```
   scripts\windows\setup-database.bat -InstallMariaDB
   ```

   Im Assistenten ein Root-Passwort setzen und merken, den Dienst `MariaDB` und Port 3306 lassen.
4. Datenbank anlegen und die SQL-Dateien importieren (fragt das Root-Passwort einmal ab):

   ```
   scripts\windows\setup-database.bat -Create -Import
   ```

   Das legt die Datenbank `fivem` und den User `fivem` an, schreibt `mysql_connection_string` in `secrets.cfg`
   und importiert alle Dateien aus `database.txt`. Gleichwertig: `scripts\windows\install.bat -SetupDatabase`.
5. `server-data\secrets.cfg` öffnen und `sv_licenseKey "changeme"` durch deinen Key ersetzen.
6. `scripts\windows\start.bat` doppelklicken (txAdmin-Modus). In der Konsole erscheint eine PIN. Tipp sie ab und
   klick nicht mit der Maus ins Fenster: eine Markierung hält den Server an, bis du `Esc` drückst. Fragt die
   Windows-Firewall nach, setz den Haken beim Netzwerkprofil deines PCs
   (siehe [Freunde verbinden](docs/windows-lokal.md#freunde-verbinden)).
   <http://localhost:40120> öffnen, PIN eingeben, "Link Account" mit deinem Cfx.re-Account, Passwort setzen.
   Im Setup "Existing Server Data" wählen: Ordner `C:\FiveMServer\server-data`, CFG-Datei `server.cfg`, speichern.
   txAdmin startet den Server. Der Lizenzschlüssel kommt aus `secrets.cfg`, txAdmin fragt bei diesem Weg nicht danach.
7. FiveM starten, `F8` drücken und `connect localhost:30120` eingeben. Qbox zeigt die Charakterauswahl, leg einen
   Charakter an. Im Chat `/hallo` testen.
8. Nur Freunde zulassen: in txAdmin die **License Allowlist** einschalten und Anfragen freigeben, siehe
   [Nur Freunde zulassen](docs/linux-server.md#nur-freunde-zulassen-license-allowlist). Dich selbst zum
   Qbox-Admin machen: `add_principal` in `server.cfg`, Abschnitt "Admin-Rechte".

Ohne txAdmin (schneller Entwicklungsstart mit Serverkonsole): `scripts\windows\start-direct.bat`.

Details, alle Parameter und Fehlerbilder: [docs/windows-lokal.md](docs/windows-lokal.md), Datenbank:
[docs/datenbank.md](docs/datenbank.md).

## Schnellstart Linux (VPS)

Als root (oder mit sudo) auf dem Server:

```bash
apt-get update && apt-get install -y git
git clone https://github.com/<dein-account>/<dein-repo>.git /opt/fivem
cd /opt/fivem
sudo bash scripts/linux/install.sh --enable-firewall
```

`install.sh` legt den User `fivem` an, lädt Artifacts und Ressourcen (Qbox), erzeugt `secrets.cfg` mit einem
zufälligen RCON-Passwort und installiert **standardmäßig MariaDB**: Datenbank `fivem`, User `fivem`,
`mysql_connection_string` in `secrets.cfg` und Import aller SQL-Dateien aus `database.txt`. Danach folgen
`fxserver.service` (aktiviert, aber noch nicht gestartet), eine sudoers-Regel für `deploy.sh` und ufw-Regeln
(30120/tcp+udp). `--enable-firewall` schaltet ein installiertes, aber inaktives ufw ein und gibt vorher die
erkannten SSH-Ports und 30120 frei; 40120 bleibt zu. Lass die Option weg, wenn auf dem Server schon andere Dienste
laufen oder eine andere Firewall aktiv ist: dann warnt das Skript nur und nennt dir die ufw-Befehle zum Nachholen.

- Liegt die Datenbank auf einem anderen Server: `--no-mariadb`. Dann den String selbst in `secrets.cfg` eintragen
  und `sudo -u fivem bash scripts/linux/setup-database.sh --import` ausführen.
- Ubuntu 22.04 (MariaDB 10.6) oder ein anderer Datenbank-Fehler: `install.sh` gibt die Anleitung aus, führt die
  übrigen Schritte trotzdem aus und endet mit Exit-Code 1. Nach dem Beheben erneut starten.

Danach:

```bash
nano /opt/fivem/server-data/secrets.cfg   # sv_licenseKey eintragen
systemctl start fxserver
journalctl -fu fxserver                   # hier steht die txAdmin-PIN
```

txAdmin ist standardmäßig nicht öffentlich. Von deinem PC aus einen Tunnel öffnen und dann
<http://localhost:40120> aufrufen:

```bash
ssh -L 40120:127.0.0.1:40120 root@<server-ip>
```

Im txAdmin-Setup wieder "Existing Server Data" mit `/opt/fivem/server-data` und `server.cfg` wählen. Dann die
[License Allowlist](docs/linux-server.md#nur-freunde-zulassen-license-allowlist) einschalten.

Docker statt systemd: [docs/docker.md](docs/docker.md) (MariaDB läuft dort als eigener Container,
SQL-Import mit `bash scripts/linux/setup-database.sh --docker`).

## Aktualisieren

| Was                      | Windows                                              | Linux                                                   |
|--------------------------|------------------------------------------------------|---------------------------------------------------------|
| FXServer-Artifacts       | `install.bat -UpdateArtifacts` (`-Channel latest`)   | `scripts/linux/update-artifacts.sh [--channel latest]`  |
| Artifacts neu erzwingen  | `install.bat -ForceArtifacts`                        | `scripts/linux/update-artifacts.sh --force`             |
| Git-Ressourcen (pull)    | `install.bat -UpdateResources`                       | `scripts/linux/install-resources.sh --update`           |
| Alles neu holen (auch zip "latest") | `install.bat -ForceResources`             | `scripts/linux/install-resources.sh --force`            |
| Neue SQL-Dateien importieren | `setup-database.bat`                             | `sudo -u fivem bash scripts/linux/setup-database.sh`    |
| Kompletter Deploy        | `git pull`, dann `install.bat -UpdateResources` (importiert SQL mit) | `scripts/linux/deploy.sh [--update-artifacts] [--no-sql]` |

`deploy.sh` macht `git pull --ff-only --autostash`, `install-resources.sh --update`, `setup-database.sh --import`
(sobald ein `mysql_connection_string` in `secrets.cfg` steht), optional das Artifact-Update und
`systemctl restart fxserver`. Hinterlässt der Pull Konflikte oder schlägt der SQL-Import fehl, bricht es vor dem
Neustart ab. `--no-sql` überspringt den SQL-Import. Genau das ruft auch `.github/workflows/deploy.yml` per SSH auf.
Vor jedem Update den Server stoppen (Windows: Konsole schließen; unter Linux erledigt `deploy.sh` den Neustart).

Die Qbox-Ressourcen stehen wie im Rezept auf `main` bzw. `releases/latest`: git-Ressourcen holen bei jedem Update
den neuesten Stand, zip-Ressourcen nur mit Force. Festen Stand einstellen:
[docs/ressourcen.md](docs/ressourcen.md#fester-stand-oder-immer-aktuell).

## Dokumentation

- [docs/checkliste.md](docs/checkliste.md): Plan und Checkliste: was auf den Server kommt, Reihenfolge, Umsetzung, offene Entscheidungen
- [docs/windows-lokal.md](docs/windows-lokal.md): Installation, Datenbank, Startmodi, alle Skript-Parameter, Fehlerbilder
- [docs/linux-server.md](docs/linux-server.md): install.sh im Detail, systemd, License Allowlist, Firewall, sudoers, Deploy per GitHub Actions, Backups
- [docs/docker.md](docs/docker.md): Image bauen, Compose, `.env`, uid 1000, SQL-Import, Updates
- [docs/datenbank.md](docs/datenbank.md): MariaDB-Versionen, `setup-database`, `database.txt`, Import-Buchführung, Backup
- [docs/ressourcen.md](docs/ressourcen.md): `resources.txt`-Format inkl. `copy` und `--check`, Klammer-Ordner, Update/Force, eigene Ressourcen
- [docs/frameworks.md](docs/frameworks.md): Qbox: was installiert ist, Abweichungen vom Rezept, Updates, Sprache, Fehlersuche
- [docs/inhalte-regeln.md](docs/inhalte-regeln.md): was an Inhalten erlaubt ist (Marken, Fahrzeuge, Musik), mit Quellen
- [docs/entscheidungen.md](docs/entscheidungen.md): Designentscheidungen (txAdmin, OneSync, Qbox, Datenbank, Manifeste, Firewall, Docker) und bekannte Grenzen
- [server-data/resources/[local]/README.md](server-data/resources/%5Blocal%5D/README.md): eigene Ressource anlegen

## Typische Probleme

- **"no license key was specified" / Server startet nicht**: In `server-data/secrets.cfg` steht noch `changeme`.
  Alle Skripte warnen davor. Key im Portal erstellen und eintragen. txAdmin speichert den Key bei
  "Existing Server Data" nicht, er muss in `secrets.cfg` stehen.
- **oxmysql meldet Verbindungsfehler, Qbox startet nicht**: `mysql_connection_string` fehlt oder passt nicht.
  `setup-database.bat -DryRun` bzw. `sudo -u fivem bash scripts/linux/setup-database.sh --dry-run` testet dieselben
  Zugangsdaten. Läuft MariaDB? Passwort nur aus `A-Z a-z 0-9`? Details: [docs/datenbank.md](docs/datenbank.md#fehlerbilder).
- **`MariaDB ... ist zu alt. Qbox braucht mindestens 10.9`**: neuere MariaDB installieren
  ([docs/datenbank.md](docs/datenbank.md#welche-version)).
- **`Table '...' doesn't exist`**: SQL-Dateien nicht importiert, `setup-database` ausführen.
- **Freunde können nicht verbinden**: `localhost` funktioniert nur auf dem Server-PC selbst. Freunde im selben
  Netz nutzen die IPv4-Adresse deines PCs (`ipconfig`), Freunde über das Internet deine öffentliche IPv4 plus
  Portweiterleitung 30120 TCP und UDP im Router. Bei DS-Lite- bzw. CGNAT-Anschlüssen (in Deutschland häufig)
  funktioniert eine IPv4-Portweiterleitung gar nicht. Test, Firewall und Auswege:
  [docs/windows-lokal.md, Freunde verbinden](docs/windows-lokal.md#freunde-verbinden). Mit eingeschalteter
  Allowlist sieht ein neuer Spieler zuerst eine Request ID, die ein Admin freigeben muss.
- **Windows-Firewall fragt beim ersten Start**: Die Haken "Privat" und "Öffentlich" meinen das Netzwerkprofil,
  in dem dein PC hängt, nicht die Herkunft der Spieler. Setz den Haken, der zu deinem Netz passt
  (`Get-NetConnectionProfile` in PowerShell zeigt es). Für das nicht angehakte Profil legt Windows
  Blockier-Regeln an, die Korrektur steht im verlinkten Abschnitt.
- **Server oder txAdmin hängt, Fenstertitel beginnt mit "Auswählen"**: Du hast ins Konsolenfenster geklickt
  (QuickEdit-Modus). `Esc` drücken. Dauerhaft abschalten: Rechtsklick auf die Titelleiste > Standardwerte >
  Optionen > "QuickEdit-Modus" abwählen. Betrifft vor allem das klassische Konsolenfenster (Standard unter
  Windows 10).
- **Im Spiel spawnt niemand, Konsole meldet `Couldn't find resource spawnmanager`**: Die Basis-Ressourcen in
  `[cfx-default]` fehlen. `install.bat` ohne `-SkipResources` ausführen (Linux: `scripts/linux/install-resources.sh`).
  `install.bat`, `start.bat` und `start-direct.bat` warnen in diesem Fall.
- **7-Zip fehlt**: Nur relevant bei `install.bat -ArchiveFormat 7z`. Das Skript lädt dann automatisch
  `7zr.exe` nach `tools\`. Der Standardweg (`server.zip`) braucht kein 7-Zip.
- **txAdmin lehnt die server.cfg ab** ("Unable to start the server due to error(s) in your config file(s)"):
  die Meldung darunter lesen. Typisch: 40120 bis 40150 als Spielport genutzt oder tcp- und udp-Endpoint
  unterschiedlich.
- **OneSync**: steht absichtlich in keiner cfg-Datei. Im txAdmin-Modus verwaltet txAdmin OneSync selbst
  (Settings > FXServer, Standard "on"); ein `set onesync on` in `server.cfg` oder `secrets.cfg` würde txAdmin
  auskommentieren (Zeile mit `## [txAdmin CFG validator]`). Der Direktmodus übergibt es als Startargument:
  `start-direct.bat` bzw. `bash ../artifacts/run.sh +set onesync on +exec server.cfg`. Qbox startet ohne OneSync nicht.
- **"Could not contact the server browser"**: Für lokale Tests `#sv_master1 ""` in `secrets.cfg` einkommentieren.
- **txAdmin startet nicht (Fehler 7, Pfad)**: Der Pfad zu `artifacts\` oder `txData\` enthält Umlaute oder
  Sonderzeichen. Repo nach `C:\FiveMServer` verschieben.
- Weitere Qbox-Fehlerbilder (Items, Tastenbelegung, Admin-Menü): [docs/frameworks.md](docs/frameworks.md#prüfen-und-fehlersuche).

## Sicherheit

- Keine Geheimnisse im Repo: `secrets.cfg`, `.env`, `txData/`, `artifacts/` und installierte Fremd-Ressourcen sind in `.gitignore`.
  Die CI bricht ab, wenn eine committete cfg-Datei einen Lizenzschlüssel, ein Passwort, einen Datenbank-String oder einen OneSync-Setter enthält.
- Nur Freunde auf den Server lassen: FXServer hat kein Beitrittspasswort und `sv_master1 ""` versteckt den Server
  nicht. Den Zugang regelt die License Allowlist von txAdmin
  ([docs/linux-server.md](docs/linux-server.md#nur-freunde-zulassen-license-allowlist)).
- txAdmin spricht nur HTTP und lauscht auf dem VPS auf `0.0.0.0:40120`. Zu bleibt der Port über ufw:
  `install.sh` legt keine Regel für 40120 an (außer mit `--txadmin-public`) und schaltet mit
  `--enable-firewall` ein installiertes, aber inaktives ufw ein (SSH-Ports aus `sshd -T` und `ssh.socket`,
  Fallback 22, plus 30120/tcp+udp werden vorher freigegeben). Ohne `--enable-firewall`, ohne ufw oder mit
  `--no-firewall` warnt das Skript laut, dass 40120 offen ist, und du sperrst den Port selbst (ufw-Befehle aus
  der Warnung oder Provider-Panel). Zugriff immer per SSH-Tunnel.
- MariaDB lauscht unter Linux (Ubuntu-Paket) nur lokal und unter Docker nur im Compose-Netz. Unter Windows lauscht
  der MSI-Dienst auf allen Schnittstellen; die angelegten User `fivem@localhost`/`fivem@127.0.0.1` und ein
  ausgeschalteter Remote-root verhindern Anmeldungen von außen. Wer den Port ganz schließen will, trägt
  `bind-address=127.0.0.1` in `my.ini` unter `[mysqld]` ein (Dienst danach neu starten). Das von
  `setup-database --create`/`-Create` erzeugte Datenbank-Passwort (32 Hex-Zeichen) steht nur in `secrets.cfg`
  (unter Linux 0600) und wird einmal angezeigt, aber nur im Terminal, nicht in einer umgeleiteten Ausgabe oder
  Logdatei. Unter Docker steht das selbst gewählte Passwort in `.env` (`MYSQL_PASSWORD`,
  `MYSQL_CONNECTION_STRING`), in der Umgebung der Container und in `secrets.cfg`. Die Import-Skripte geben es nie
  auf einer Kommandozeile weiter.
- `rcon_password` wird auf Linux zufällig erzeugt. RCON läuft über UDP, Port 30120 muss deshalb nicht extra geöffnet werden, aber ein starkes Passwort ist Pflicht.
- Alle Skripte sind idempotent und können jederzeit erneut laufen.
