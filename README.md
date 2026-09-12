# FiveM Server (FXServer + txAdmin)

Ein versionierbares Grundgerüst für einen eigenen FiveM-Server. Du entwickelst und testest
lokal auf deinem Windows-PC und schiebst denselben Stand später unverändert auf einen
Linux-VPS (systemd + txAdmin). Docker Compose ist als zweiter Weg für Linux dabei.

Was das Repo mitbringt:

- Skripte, die die FXServer-Artifacts über die offizielle Changelog-API laden und aktuell halten
- die Standard-Ressourcen aus `cfx-server-data` sowie ein Manifest (`resources.txt`) für Fremd-Ressourcen
- eine kommentierte `server.cfg` (deutsch) plus eine getrennte, nicht committete `secrets.cfg`
- eine Beispiel-Ressource `hello-world` unter `server-data/resources/[local]/`
- ein Linux-Installer (User, systemd, sudoers, ufw, optional MariaDB) und ein `deploy.sh` für GitHub Actions
- Docker-Image und Compose-Datei mit MariaDB
- Framework-Vorbereitung für ESX Legacy, QBCore und Qbox (auskommentiert, siehe `docs/frameworks.md`)

Es ist kein Framework installiert. Der Server startet als "vanilla" Freeroam mit `basic-gamemode`.

## Voraussetzungen

Immer:

- Ein kostenloser Cfx.re-Account und ein Lizenzschlüssel: <https://portal.cfx.re/> -> Servers -> Registration Keys -> "Generate Key +". Es wird nur ein Anzeigename abgefragt, keine IP-Bindung.
- Git.

Windows (lokal testen):

- Windows 10/11 64-Bit mit Windows PowerShell 5.1 (ist vorinstalliert).
- Git: `winget install --id Git.Git -e` (danach ein neues Terminal öffnen).
- 7-Zip ist optional. Standardmäßig wird `server.zip` geladen und ohne Zusatztools entpackt.
- GTA V und der FiveM-Client auf demselben PC, um dich zu verbinden.
- Ein kurzer Pfad ohne Umlaute und andere Nicht-ASCII-Zeichen (Leerzeichen sind erlaubt), z. B. `C:\FiveMServer`. txAdmin startet nicht, wenn der Pfad zu `artifacts\` oder `txData\` Nicht-ASCII-Zeichen enthält.

Linux (VPS):

- Ubuntu 24.04 x86_64 (Ubuntu 22.04 und Debian 12 sollten ebenfalls funktionieren), root-Zugang per SSH.
- Empfehlung: mindestens 2 vCPU und 4 GB RAM, mit Framework und Datenbank eher mehr. Offizielle Mindestwerte gibt es nicht.
- systemd. Die Skripte installieren `git curl xz-utils unzip ca-certificates sudo` selbst.

## Ordnerstruktur

```
README.md
.gitignore                     Schließt Secrets, Artifacts, txData und installierte Fremd-Ressourcen aus
.gitattributes                 Zeilenenden pro Dateityp (LF; .ps1/.bat CRLF)
.editorconfig                  Einrückung und Zeilenenden für Editoren
.env.example                   Nur für Docker Compose (Lizenz, RCON, MariaDB)
.dockerignore                  Docker-Build-Kontext: nur docker/entrypoint.sh geht ins Image
server-data/
  server.cfg                   Gemeinsame Konfiguration, committet, lädt secrets.cfg
  secrets.cfg.example          Vorlage für secrets.cfg (Lizenz, RCON, DB); secrets.cfg selbst ist gitignored
  resources.txt                Manifest für Fremd-Ressourcen (git/zip), alles auskommentiert
  resources/
    [local]/                   Deine eigenen Ressourcen (committet), enthält hello-world
    [cfx-default]/             Standard-Ressourcen aus cfx-server-data (gitignored, Installer)
    [vendor]/                  Fremd-Ressourcen aus resources.txt (gitignored, Installer)
artifacts/                     FXServer-Binaries (gitignored). Windows: FXServer.exe, Linux: run.sh + alpine/
artifacts.bak/                 Linux: vorherige Artifact-Version nach einem Update (gitignored)
tools/                         Windows: 7zr.exe, falls per -ArchiveFormat 7z geladen (gitignored)
txData/                        txAdmin-Profil, Admins, Logs (gitignored, niemals löschen)
scripts/
  windows/                     install.bat, install.ps1, install-resources.ps1, start.bat, start-direct.bat
  linux/                       lib.sh, install.sh, update-artifacts.sh, install-resources.sh, deploy.sh, fxserver.service.template
docker/                        Dockerfile, docker-compose.yml, entrypoint.sh
docs/                          Ausführliche Anleitungen (siehe unten), inkl. entscheidungen.md
.github/workflows/             ci.yml (Lint), deploy.yml (SSH-Deploy auf den VPS)
```

## Schnellstart Windows

1. Repo klonen, am besten in einen kurzen Pfad:

   ```
   git clone https://github.com/<dein-account>/<dein-repo>.git C:\FiveMServer
   ```

2. `scripts\windows\install.bat` doppelklicken. Das Skript lädt die Artifacts (Kanal `recommended`),
   klont `cfx-server-data` nach `[cfx-default]`, verarbeitet `resources.txt` und legt
   `server-data\secrets.cfg` aus der Vorlage an. Bei Rückfragen der Windows-Firewall später "Zulassen" wählen.
3. `server-data\secrets.cfg` öffnen und `sv_licenseKey "changeme"` durch deinen Key ersetzen.
4. `scripts\windows\start.bat` doppelklicken (txAdmin-Modus). In der Konsole erscheint eine PIN.
5. <http://localhost:40120> öffnen, PIN eingeben, "Link Account" mit deinem Cfx.re-Account, Passwort setzen.
6. Im Setup "Existing Server Data" wählen: Ordner `C:\FiveMServer\server-data`, CFG-Datei `server.cfg`, speichern.
   txAdmin startet den Server. Der Lizenzschlüssel kommt aus `secrets.cfg`, txAdmin fragt bei diesem Weg nicht danach.
7. FiveM starten, `F8` drücken und `connect localhost:30120` eingeben. Im Chat `/hallo` testen.

Ohne txAdmin (schneller Entwicklungsstart mit Serverkonsole): `scripts\windows\start-direct.bat`.

Details, alle Parameter und Fehlerbilder: [docs/windows-lokal.md](docs/windows-lokal.md).

## Schnellstart Linux (VPS)

Als root (oder mit sudo) auf dem Server:

```bash
apt-get update && apt-get install -y git
git clone https://github.com/<dein-account>/<dein-repo>.git /opt/fivem
cd /opt/fivem
sudo bash scripts/linux/install.sh --enable-firewall                 # frischer VPS, ohne Datenbank
sudo bash scripts/linux/install.sh --enable-firewall --with-mariadb  # mit MariaDB, DB "fivem" und User "fivem"
```

`install.sh` legt den User `fivem` an, lädt Artifacts und Ressourcen, erzeugt `secrets.cfg` mit einem
zufälligen RCON-Passwort, installiert `fxserver.service` (aktiviert, aber noch nicht gestartet), eine
sudoers-Regel für `deploy.sh` und ufw-Regeln (30120/tcp+udp). `--enable-firewall` schaltet ein installiertes,
aber inaktives ufw ein (Ubuntu-Standard) und gibt vorher die erkannten SSH-Ports und 30120 frei; 40120 bleibt
zu. Lass die Option weg, wenn auf dem Server schon andere Dienste laufen oder eine andere Firewall aktiv ist:
dann warnt das Skript nur und nennt dir die ufw-Befehle zum Nachholen.

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

Im txAdmin-Setup wieder "Existing Server Data" mit `/opt/fivem/server-data` und `server.cfg` wählen.

Docker statt systemd: [docs/docker.md](docs/docker.md).

## Aktualisieren

| Was                      | Windows                                              | Linux                                                   |
|--------------------------|------------------------------------------------------|---------------------------------------------------------|
| FXServer-Artifacts       | `install.bat -UpdateArtifacts` (`-Channel latest`)   | `scripts/linux/update-artifacts.sh [--channel latest]`  |
| Artifacts neu erzwingen  | `install.bat -ForceArtifacts`                        | `scripts/linux/update-artifacts.sh --force`             |
| Git-Ressourcen (pull)    | `install.bat -UpdateResources`                       | `scripts/linux/install-resources.sh --update`           |
| Alles neu holen          | `install.bat -ForceResources`                        | `scripts/linux/install-resources.sh --force`            |
| Kompletter Deploy        | `git pull`, dann `install.bat -UpdateResources`      | `scripts/linux/deploy.sh [--update-artifacts]`          |

`deploy.sh` macht `git pull --ff-only --autostash`, `install-resources.sh --update`, optional das Artifact-Update und
`systemctl restart fxserver`; hinterlässt der Pull Konflikte, bricht es vor dem Neustart ab. Genau das ruft auch
`.github/workflows/deploy.yml` per SSH auf.
Vor jedem Update den Server stoppen (Windows: Konsole schließen; unter Linux erledigt `deploy.sh` den Neustart).

## Dokumentation

- [docs/windows-lokal.md](docs/windows-lokal.md): Installation, Startmodi, alle Skript-Parameter, Fehlerbilder
- [docs/linux-server.md](docs/linux-server.md): install.sh im Detail, systemd, Firewall, sudoers, Deploy per GitHub Actions, Backups
- [docs/docker.md](docs/docker.md): Image bauen, Compose, `.env`, uid 1000, Updates
- [docs/ressourcen.md](docs/ressourcen.md): `resources.txt`-Format, eigene Ressourcen, Klammer-Ordner, Update/Force
- [docs/frameworks.md](docs/frameworks.md): ESX Legacy, QBCore, Qbox inkl. Datenbank und SQL-Import
- [docs/entscheidungen.md](docs/entscheidungen.md): Designentscheidungen (txAdmin, OneSync, Firewall, Docker, Manifest) und bekannte Grenzen
- [server-data/resources/[local]/README.md](server-data/resources/%5Blocal%5D/README.md): eigene Ressource anlegen

## Typische Probleme

- **"no license key was specified" / Server startet nicht**: In `server-data/secrets.cfg` steht noch `changeme`.
  Alle Skripte warnen davor. Key im Portal erstellen und eintragen. txAdmin speichert den Key bei
  "Existing Server Data" nicht, er muss in `secrets.cfg` stehen.
- **Freunde können nicht verbinden**: 30120/tcp und 30120/udp müssen von außen erreichbar sein. Zu Hause
  heißt das Portweiterleitung im Router auf deinen PC plus Windows-Firewall-Freigabe für `FXServer.exe`.
  Lokal auf demselben PC geht `connect localhost:30120` immer.
- **Windows-Firewall fragt beim ersten Start**: "Zugriff zulassen" für private Netzwerke (öffentlich nur,
  wenn du Spieler aus dem Internet erwartest).
- **7-Zip fehlt**: Nur relevant bei `install.bat -ArchiveFormat 7z`. Das Skript lädt dann automatisch
  `7zr.exe` nach `tools\`. Der Standardweg (`server.zip`) braucht kein 7-Zip.
- **txAdmin lehnt die server.cfg ab** ("Unable to start the server due to error(s) in your config file(s)"):
  die Meldung darunter lesen. Typisch: 40120 bis 40150 als Spielport genutzt oder tcp- und udp-Endpoint
  unterschiedlich.
- **OneSync**: steht absichtlich in keiner cfg-Datei. Im txAdmin-Modus verwaltet txAdmin OneSync selbst
  (Settings > FXServer, Standard "on"); ein `set onesync on` in `server.cfg` oder `secrets.cfg` würde txAdmin
  auskommentieren (Zeile mit `## [txAdmin CFG validator]`). Der Direktmodus übergibt es als Startargument:
  `start-direct.bat` bzw. `bash ../artifacts/run.sh +set onesync on +exec server.cfg`.
- **"Could not contact the server browser"**: Für lokale Tests `#sv_master1 ""` in `secrets.cfg` einkommentieren.
- **txAdmin startet nicht (Fehler 7, Pfad)**: Der Pfad zu `artifacts\` oder `txData\` enthält Umlaute oder
  Sonderzeichen. Repo nach `C:\FiveMServer` verschieben.

## Sicherheit

- Keine Geheimnisse im Repo: `secrets.cfg`, `.env`, `txData/`, `artifacts/` und installierte Fremd-Ressourcen sind in `.gitignore`.
- txAdmin spricht nur HTTP und lauscht auf dem VPS auf `0.0.0.0:40120`. Zu bleibt der Port über ufw:
  `install.sh` legt keine Regel für 40120 an (außer mit `--txadmin-public`) und schaltet mit
  `--enable-firewall` ein installiertes, aber inaktives ufw ein (SSH-Ports aus `sshd -T` und `ssh.socket`,
  Fallback 22, plus 30120/tcp+udp werden vorher freigegeben). Ohne `--enable-firewall`, ohne ufw oder mit
  `--no-firewall` warnt das Skript laut, dass 40120 offen ist, und du sperrst den Port selbst (ufw-Befehle aus
  der Warnung oder Provider-Panel). Zugriff immer per SSH-Tunnel.
- `rcon_password` wird auf Linux zufällig erzeugt. RCON läuft über UDP, Port 30120 muss deshalb nicht extra geöffnet werden, aber ein starkes Passwort ist Pflicht.
- Alle Skripte sind idempotent und können jederzeit erneut laufen.
