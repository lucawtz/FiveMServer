# Linux-VPS: Installation, Betrieb, Deploy

Zielsystem: Ubuntu 24.04 x86_64 (Ubuntu 22.04 und Debian 12 sollten ebenfalls funktionieren) mit systemd.
FXServer für Linux läuft nur auf x86_64; `update-artifacts.sh` warnt auf anderen Architekturen.

Alle Skripte liegen in `scripts/linux/`, haben `-h`/`--help`, akzeptieren `--option wert` und
`--option=wert`, loggen deutsch auf stderr (`[INFO]`, `[WARN]`, `[FEHLER]`, `[OK]`, `==> Schritt`) und
ermitteln den Repo-Root aus ihrem eigenen Pfad, laufen also aus jedem Verzeichnis. Temporäre Ordner
werden unter `$FX_TMPDIR`, sonst `$TMPDIR`, sonst `/tmp` als `fxserver.XXXXXX` angelegt und beim Ende entfernt.

Umgebungsvariablen zum Überschreiben: `FX_CHANGELOG_API` (Standard
`https://changelogs-live.fivem.net/api/changelog/versions/linux/server`), `FX_SERVER_DATA_REPO`
(Standard `https://github.com/citizenfx/cfx-server-data.git`), `FX_TMPDIR`.

## Installation mit install.sh

Voraussetzung: Repo ist geklont (z. B. nach `/opt/fivem`), du bist root.

```bash
apt-get update && apt-get install -y git
git clone https://github.com/<dein-account>/<dein-repo>.git /opt/fivem
cd /opt/fivem
sudo bash scripts/linux/install.sh [--user fivem] [--channel recommended] [--with-mariadb] [--enable-firewall] [--txadmin-public] [--no-firewall]
```

Auf einem frischen VPS, der nur den Spielserver trägt: `sudo bash scripts/linux/install.sh --enable-firewall`
(mit `--with-mariadb`, wenn du eine Datenbank brauchst). Laufen dort schon andere Dienste oder eine andere
Firewall, lass `--enable-firewall` weg und lies die Warnung in Schritt 8.

| Option              | Bedeutung                                                                                     |
|---------------------|-----------------------------------------------------------------------------------------------|
| `--user <name>`     | Service-User, Standard `fivem`, wird bei Bedarf angelegt. Erlaubt: `a-z 0-9 _ -`.             |
| `--channel <name>`  | Artifact-Kanal `recommended` (Standard), `latest`, `optional`.                                |
| `--with-mariadb`    | MariaDB installieren, Datenbank `fivem` und User `fivem`@`localhost` anlegen.                 |
| `--enable-firewall` | Ein installiertes, aber inaktives ufw einschalten; vorher werden die erkannten SSH-Ports und 30120/tcp+udp freigegeben. Ohne die Option wird nur gewarnt. |
| `--txadmin-public`  | 40120/tcp in ufw öffnen, txAdmin ist damit öffentlich (nicht empfohlen). txAdmin lauscht ohnehin auf `0.0.0.0`. |
| `--no-firewall`     | Schritt 8 komplett überspringen: keine ufw-Regeln anlegen, ufw nicht einschalten, keine Warnung. |

Das Skript bricht ab, wenn es nicht als root läuft, nicht auf Linux läuft, `systemctl` fehlt oder der
Repo-Pfad Leerzeichen oder Sonderzeichen außerhalb von `A-Z a-z 0-9 / . _ + : -` enthält (also z. B.
`/opt/fivem` verwenden). Es ist idempotent: ein zweiter Lauf legt nichts doppelt an und ändert eine vorhandene
`secrets.cfg` nur, um bei einem nachträglichen `--with-mariadb` den Verbindungs-String einzutragen;
Lizenzschlüssel, `rcon_password`, vorhandene DB-Passwörter und txData bleiben unangetastet.

Die acht Schritte im Detail:

1. **Systempakete**: `apt-get update` und `apt-get install git curl xz-utils unzip ca-certificates sudo`
   (`DEBIAN_FRONTEND=noninteractive`). Ohne `apt-get` nur eine Warnung.
2. **Service-User und Rechte**: `useradd -m -s /bin/bash <user>`, falls nicht vorhanden. `mkdir <repo>/txData`,
   `chown -R <user>: <repo>` (primäre Gruppe des Users), `chmod +x scripts/linux/*.sh docker/entrypoint.sh`. Ist `<repo>/.git`
   vorhanden, wird der Pfad für root und für den Service-User als `safe.directory` in Git eingetragen.
   Alles, was als Service-User läuft, geht über `runuser -u <user> -- env HOME=<home> GIT_TERMINAL_PROMPT=0 ...`
   (Fallback `sudo -u <user> -H`).
3. **Artifacts und Ressourcen** als Service-User: `update-artifacts.sh --channel <kanal> --if-missing`, dann
   `install-resources.sh`. Fehlgeschlagene Manifest-Einträge sind hier nur eine Warnung.
4. **secrets.cfg**: fehlt `server-data/secrets.cfg`, wird sie aus `secrets.cfg.example` kopiert und die erste
   Zeile, die auf `rcon_password` passt (auch auskommentiert), durch `set rcon_password "<32 Hex-Zeichen>"`
   ersetzt (sonst angehängt). Immer: `chown <user>`, `chmod 600`. Danach prüft `check_license_key` auf
   `changeme` (nur Warnung).
5. **MariaDB** (nur mit `--with-mariadb`): `apt-get install mariadb-server`, falls das Paket `mariadb-server`
   laut `dpkg -s` noch nicht installiert ist (ein reiner `mariadb-client` reicht nicht und überspringt den
   Schritt nicht); `systemctl enable --now mariadb` (Fallback `mysql`). Zugriff als root über
   unix_socket. Existiert `fivem`@`localhost` bereits, wird nur `CREATE DATABASE IF NOT EXISTS fivem` ausgeführt
   und das Passwort bleibt unverändert. Sonst: 32-Hex-Passwort erzeugen, Datenbank `fivem`
   (utf8mb4 / utf8mb4_unicode_ci), User anlegen, `GRANT ALL ON fivem.*`, und in `secrets.cfg` die Zeile
   `set mysql_connection_string "mysql://fivem:<pw>@localhost/fivem?charset=utf8mb4"` eintragen (ersetzt die
   auskommentierte Vorlage). `secrets.cfg` behält dabei Besitzer `<user>` und Modus 0600. Das Passwort wird am
   Ende einmal ausgegeben.
6. **systemd-Unit**: `fxserver.service.template` wird mit `__ROOT__` und `__USER__` gefüllt und nach
   `/etc/systemd/system/fxserver.service` (0644) geschrieben, `daemon-reload`, `systemctl enable fxserver`.
   txData-Pfad und txAdmin-Port kommen als `Environment=TXHOST_DATA_PATH=...` und `Environment=TXHOST_TXA_PORT=40120`
   in die Unit, `ExecStart` ist nur `run.sh` ohne Argumente; txAdmin lauscht auf `0.0.0.0:40120`.
   Der Dienst wird **nicht** gestartet, weil der Lizenzschlüssel noch fehlt. Läuft er schon (zweiter Lauf),
   greift die neue Unit erst nach `systemctl restart fxserver`.
7. **sudoers**: `/etc/sudoers.d/fivem-deploy` (0440) erlaubt dem Service-User ohne Passwort
   `systemctl start|stop|restart fxserver` (und `fxserver.service`) für jeden vorhandenen Pfad aus
   `/usr/bin/systemctl` und `/bin/systemctl`. Die Datei wird vor der Installation mit `visudo -cf` geprüft.
8. **Firewall** (entfällt mit `--no-firewall`):
   - ufw installiert und aktiv: `ufw allow 30120/tcp` und `30120/udp` (Kommentar `FXServer`) kommen dazu,
     40120/tcp nur mit `--txadmin-public` (mit Warnung).
   - ufw installiert, aber inaktiv (Standard auf Ubuntu), **ohne** `--enable-firewall`: das Skript schaltet
     nichts ein, weil ufw sonst alle anderen Dienste auf dem Server sperren würde. Es ermittelt die SSH-Ports
     (aus `sshd -T` und `systemctl show ssh.socket`, Fallback 22) und warnt:
     `ACHTUNG: ufw ist installiert, aber AUS. Ohne aktive Firewall ist txAdmin (0.0.0.0:40120) aus dem Internet erreichbar!`,
     gefolgt von `Erkannte SSH-Port(s): 22. Entweder dieses Skript erneut ausfuehren:` mit dem passenden
     Befehl (`sudo bash .../install.sh --enable-firewall`, ergänzt um deine `--user`/`--with-mariadb`/
     `--txadmin-public`-Optionen) und `Oder von Hand (erst SSH freigeben, sonst sperrst du dich aus):`
     `ufw allow 22/tcp && ufw allow 30120/tcp && ufw allow 30120/udp && ufw enable`. In der Zusammenfassung
     steht `ufw: installiert, aber AUS und nicht eingeschaltet. txAdmin 40120 ist offen! (--enable-firewall)`
     und die nächsten Schritte bekommen einen Punkt 6 "Firewall einschalten".
   - ufw installiert, aber inaktiv, **mit** `--enable-firewall`: `Schalte ufw ein (--enable-firewall). Standard:
     eingehend alles zu ausser SSH (22) und 30120.`, dann `ufw allow <ssh-port>/tcp` für jeden erkannten
     SSH-Port, 30120/tcp+udp, 40120/tcp nur mit `--txadmin-public`, und `ufw --force enable`. Danach warnt
     das Skript, dass andere Dienste (Webserver, Panel, Datenbank von außen) jetzt gesperrt sind
     (`ufw allow <port>/tcp` zum Nachholen).
   - ufw fehlt komplett (z. B. Debian): nichts angelegt, laute Warnung, dass txAdmin (40120/tcp) aus dem
     Internet erreichbar ist, plus `apt install ufw && ufw allow OpenSSH && ufw allow 30120/tcp && ufw allow 30120/udp && ufw enable`.

Am Ende steht eine Zusammenfassung und die nächsten Schritte:

```bash
nano /opt/fivem/server-data/secrets.cfg   # sv_licenseKey eintragen
systemctl start fxserver
journalctl -fu fxserver                   # txAdmin-PIN
ssh -L 40120:127.0.0.1:40120 root@<server-ip>   # vom eigenen PC aus, dann http://localhost:40120
```

Der Tunnel funktioniert mit jedem SSH-User, der sich einloggen darf (`fivem@<server-ip>` geht genauso,
sobald der Service-User einen SSH-Key hat, siehe Deploy-Key unten).

## txAdmin einrichten

1. `journalctl -fu fxserver`: die Zeile mit der PIN kopieren.
2. Tunnel von deinem PC: `ssh -L 40120:127.0.0.1:40120 root@<server-ip>`, dann <http://localhost:40120>.
3. PIN eingeben, "Link Account" mit dem Cfx.re-Account, Admin-Passwort setzen.
4. Servername, dann **"Existing Server Data"**: Server Data Folder `/opt/fivem/server-data`, CFG File `server.cfg`.
5. Speichern. txAdmin startet FXServer mit `+exec server.cfg`; der Lizenzschlüssel kommt aus `secrets.cfg`.

OneSync: steht absichtlich in keiner cfg-Datei, weder in `server.cfg` noch in der von `install.sh` angelegten
`secrets.cfg`. txAdmin verwaltet OneSync selbst (Settings > FXServer, Standard "on") und würde ein
`set onesync on` in jeder geladenen cfg-Datei auskommentieren (Zeile mit `## [txAdmin CFG validator]`); in
`server.cfg` wäre die committete Datei damit dauerhaft geändert und `deploy.sh` (`git pull --ff-only`) würde
beim nächsten Commit an dieser Datei stolpern. Der Direktmodus (unten) übergibt OneSync als Startargument.

Die Unit übergibt txData-Pfad und txAdmin-Port als Umgebungsvariablen `TXHOST_DATA_PATH` und
`TXHOST_TXA_PORT` (wie `start.bat` und `entrypoint.sh`). Die alten ConVars `serverProfile`, `txAdminPort`,
`txDataPath` meldet txAdmin 8.x als veraltet, eine solche Warnung erscheint im Log deshalb nicht.

Ohne txAdmin (Direktmodus, z. B. zum Debuggen): Dienst stoppen und als Service-User starten:

```bash
systemctl stop fxserver
runuser -u fivem -- bash -c 'cd /opt/fivem/server-data && bash ../artifacts/run.sh +set onesync on +exec server.cfg'
```

`+set onesync on` muss vor `+exec server.cfg` stehen; ohne das Argument läuft der Direktmodus ohne OneSync
(`sv_maxclients 32`, ox_lib und alle Frameworks brauchen es).

## Die systemd-Unit

`scripts/linux/fxserver.service.template`, gerendert nach `/etc/systemd/system/fxserver.service`:

```ini
[Unit]
Description=FiveM FXServer (txAdmin)
After=network-online.target mariadb.service
Wants=network-online.target

[Service]
Type=simple
User=fivem
WorkingDirectory=/opt/fivem/server-data
Environment=TXHOST_DATA_PATH=/opt/fivem/txData
Environment=TXHOST_TXA_PORT=40120
ExecStart=/opt/fivem/artifacts/run.sh
Restart=on-failure
RestartSec=5
TimeoutStopSec=30
KillSignal=SIGTERM
LimitNOFILE=65535
StandardOutput=journal
StandardError=journal
SyslogIdentifier=fxserver

[Install]
WantedBy=multi-user.target
```

Steuerung: `systemctl start|stop|restart|status fxserver`. Logs: `journalctl -fu fxserver` (live),
`journalctl -u fxserver -n 200` (letzte Zeilen), `journalctl -u fxserver --since today`.
txAdmin überwacht und startet FXServer selbst neu; systemd überwacht nur den txAdmin-Prozess.
`+set txAdminInterface 127.0.0.1` fehlt bewusst: txAdmin 8.x verlangt dann dieselbe Schnittstelle für die
`endpoint_add_*`-Zeilen in `server.cfg` (dort `0.0.0.0`) und startet den Server sonst nicht. txAdmin lauscht
deshalb auf `0.0.0.0:40120`; zu bleibt der Port über ufw, das `install.sh --enable-firewall` einschaltet (siehe
"Firewall und Ports").

## Skripte für den Betrieb

### update-artifacts.sh

```bash
scripts/linux/update-artifacts.sh [--channel recommended|latest|optional] [--force] [--if-missing]
```

- Ohne Optionen: Changelog-API abfragen, laden, wenn `artifacts/run.sh` fehlt oder die API eine andere Version
  als `artifacts/VERSION.txt` meldet. Sonst `[OK] Artifacts sind aktuell`.
- `--force`: immer neu laden. `--if-missing`: nur laden, wenn `run.sh` fehlt (nutzt `install.sh`; wird von
  `--force` überstimmt).
- Ablauf: `fx.tar.xz` in einen Temp-Ordner laden, mit `tar -tJf` prüfen, altes `artifacts.bak` löschen,
  `artifacts` nach `artifacts.bak` verschieben, neu entpacken (`tar -xJf`), `chmod +x run.sh`. Schlägt das
  Entpacken fehl, wird `artifacts.bak` zurückgeschoben. Ein verirrtes `artifacts/txData` (jemand hat `run.sh`
  im Artifact-Ordner gestartet) wandert mit nach `artifacts.bak` und wird danach nach `artifacts/txData`
  zurückgeholt. `<repo>/txData` wird nie berührt.
- Schreibt `artifacts/VERSION.txt` mit `channel=`, `version=`, `url=`, `downloaded_at=` (UTC), `platform=linux`.
- Braucht `curl`, `tar`, `xz` (Meldung mit `apt install xz-utils`). Exit 1 bei ungültigem Kanal,
  API-, Download- oder Entpackfehler.

Nach dem Update: `systemctl restart fxserver` (oder `deploy.sh --update-artifacts` nutzen, das macht beides).

### install-resources.sh

```bash
scripts/linux/install-resources.sh [--update] [--force] [--manifest <pfad>]
```

Klont `cfx-server-data` nach `server-data/resources/[cfx-default]` (übersprungen, wenn nicht leer; der
leere `[local]`-Ordner des Repos wird nicht übernommen) und verarbeitet `server-data/resources.txt`
(Format in [ressourcen.md](ressourcen.md)). `--update` macht `git pull --ff-only` in vorhandenen Git-Zielen,
`--force` installiert `[cfx-default]` neu und löscht und lädt jedes Manifest-Ziel neu, `--manifest` nimmt eine
andere Datei. Braucht `git`, für zip-Einträge `unzip`. Exit 1, wenn mindestens ein Eintrag fehlgeschlagen ist
(nach Abarbeitung aller Einträge), sonst 0. Fehlt das Standard-Manifest, nur eine Warnung; ein mit `--manifest`
angegebenes, fehlendes Manifest bricht mit `Das angegebene Manifest wurde nicht gefunden: <pfad>` ab (Exit 1,
wie `-ManifestPath` unter Windows).

### deploy.sh

```bash
scripts/linux/deploy.sh [--no-restart] [--update-artifacts] [--channel <name>]
```

Läuft als Service-User oder als root. Den Service-User liest es aus `User=` der Unit, sonst nimmt es den
Besitzer des Repo-Ordners, sonst den aktuellen User. Als root werden Git und die Ressourcen-Skripte per
`runuser` an den Service-User delegiert; als anderer Nicht-root-User gibt es eine Warnung wegen Dateirechten.

Schritte:

1. `git pull --ff-only --autostash` (nur wenn `<repo>/.git` existiert; Abbruch bei Fehler; loggt `alt -> neu`
   oder `bereits aktuell`), danach `chmod +x scripts/linux/*.sh`. `--autostash` legt lokale Änderungen an
   versionierten Dateien vor dem Pull beiseite und wendet sie danach wieder an (Git >= 2.27). Kollidieren sie
   mit dem Upstream, meldet Git trotzdem Exit 0 ("Applying autostash resulted in conflicts") und lässt
   Konfliktmarker zurück; `deploy.sh` prüft deshalb `git ls-files --unmerged` und bricht dann mit
   `git pull hat Konflikte hinterlassen ...` ab (Exit 1, kein Ressourcen-Update, kein Neustart).
2. `install-resources.sh --update` (Abbruch bei Fehler).
3. Mit `--update-artifacts`: `update-artifacts.sh --channel <kanal>` (Standard `recommended`).
4. `check_license_key` (nur Warnung).
5. Neustart: `systemctl restart fxserver` als root, sonst `sudo -n systemctl restart fxserver` (Fehler verweist
   auf `/etc/sudoers.d/fivem-deploy`). Nach 2 s `systemctl is-active fxserver`, sonst Exit 1.
   `--no-restart` überspringt den Neustart. Ohne `systemctl` nur eine Warnung.

Am Ende: `Deploy abgeschlossen in N s` plus Liste der Schritte. Exit 0 nur, wenn alles geklappt hat.

Warum `server.cfg` sauber bleiben soll: `git pull --ff-only` schlägt fehl, sobald ein Commit eine Datei
anfasst, die auf dem Server lokal geändert ist ("Your local changes to the following files would be
overwritten"). Deshalb steht kein `set onesync on` in `server.cfg` (txAdmin würde es auskommentieren) und
alles Maschinenspezifische in `secrets.cfg` (nicht in Git). Sollten trotzdem einmal lokale Änderungen an
versionierten Dateien auf dem Server liegen (txAdmin schreibt z. B. in `server.cfg`, wenn du Einstellungen
über die Oberfläche änderst), fängt `--autostash` sie ab; bei einem Konflikt bricht `deploy.sh` ab und
`git -C /opt/fivem status` zeigt, was zu tun ist (siehe Fehlerbilder).

## Deploy per GitHub Actions

`.github/workflows/deploy.yml` verbindet sich per SSH mit dem Server und führt
`cd <DEPLOY_PATH> && bash scripts/linux/deploy.sh` aus. Der Workflow läuft manuell über "Run workflow"
(mit den Eingaben "Artifacts aktualisieren" und Kanal); der Trigger bei Push auf `main` ist in der Datei
auskommentiert und kann aktiviert werden. Die Concurrency-Gruppe `deploy` verhindert parallele Deploys.

Secrets im Repo (Settings -> Secrets and variables -> Actions):

| Secret            | Wert                                                           |
|-------------------|----------------------------------------------------------------|
| `DEPLOY_HOST`     | IP oder Hostname des Servers                                   |
| `DEPLOY_USER`     | SSH-User, empfohlen der Service-User `fivem`                   |
| `DEPLOY_SSH_KEY`  | Privater Schlüssel (kompletter Inhalt inkl. BEGIN/END-Zeilen)  |
| `DEPLOY_PATH`     | Repo-Pfad auf dem Server, z. B. `/opt/fivem`                   |
| `DEPLOY_PORT`     | optional, SSH-Port, Standard 22                                |
| `DEPLOY_KNOWN_HOSTS` | optional, Host-Key des Servers im `known_hosts`-Format (Ausgabe von `ssh-keyscan -p <port> -H <server-ip>`); wenn gesetzt, entfällt `ssh-keyscan` im Workflow |

Deploy-Key für den Service-User anlegen (auf deinem PC oder auf dem Server):

```bash
ssh-keygen -t ed25519 -C "github-deploy fxserver" -f deploy_key -N ""
# öffentlicher Teil auf den Server:
sudo -u fivem mkdir -p /home/fivem/.ssh
sudo -u fivem chmod 700 /home/fivem/.ssh
cat deploy_key.pub | sudo -u fivem tee -a /home/fivem/.ssh/authorized_keys
sudo -u fivem chmod 600 /home/fivem/.ssh/authorized_keys
# privater Teil (deploy_key) als Secret DEPLOY_SSH_KEY eintragen, Datei danach löschen
```

Der User `fivem` darf dank `/etc/sudoers.d/fivem-deploy` den Dienst ohne Passwort neu starten; mehr
Rechte braucht der Workflow nicht. Ohne `DEPLOY_KNOWN_HOSTS` holt der Workflow den Host-Key bei jedem Lauf per
`ssh-keyscan` frisch (GitHub-Runner sind Wegwerf-Maschinen, es wird also nichts dauerhaft gepinnt; ein
Man-in-the-Middle beim Scan würde nicht auffallen). Wer das strenger will, legt den Host-Key einmal als Secret
`DEPLOY_KNOWN_HOSTS` ab: `ssh-keyscan -p 22 -H <server-ip>` auf einem vertrauenswürdigen Rechner ausführen und
die Ausgabe komplett als Secret eintragen. Dann schreibt der Workflow genau diesen Key in `known_hosts` und
`StrictHostKeyChecking=yes` greift wirklich.

Privates GitHub-Repo: `git pull` auf dem Server läuft als `fivem` und braucht Lesezugriff. Entweder das Repo
per HTTPS mit einem Fine-grained Token in der Remote-URL klonen (nur Contents: Read) oder einen zweiten
Schlüssel in `/home/fivem/.ssh/` als GitHub-Deploy-Key (read-only) hinterlegen und die Remote-URL auf
`git@github.com:<account>/<repo>.git` umstellen. Öffentliche Repos brauchen nichts davon.

Manuell testen, bevor du den Workflow nutzt: `ssh -i deploy_key -p 22 fivem@<server-ip> 'cd /opt/fivem && bash scripts/linux/deploy.sh --no-restart'`.

## Firewall und Ports

- 30120/tcp und 30120/udp: Spielserver, müssen offen sein.
- 40120/tcp: txAdmin, nur HTTP, lauscht auf `0.0.0.0`. Zu bleibt der Port über ufw: `install.sh` legt ohne
  `--txadmin-public` keine Regel für 40120 an und schaltet mit `--enable-firewall` ein installiertes, aber
  inaktives ufw ein (SSH-Ports und 30120 vorher freigegeben). Ohne `--enable-firewall`, ohne ufw oder mit
  `--no-firewall` bleibt 40120 offen; das Skript warnt dann laut (außer bei `--no-firewall`) und du sperrst
  den Port selbst, mit den ufw-Befehlen aus der Warnung oder im Provider-Panel.
  Zugriff per SSH-Tunnel oder über einen TLS-Reverse-Proxy (WebSockets und alle Header durchreichen; hinter
  einem Proxy sieht txAdmin nur die Proxy-IP).
- 3306: MariaDB lauscht standardmäßig nur auf `127.0.0.1`. Für HeidiSQL & Co. einen SSH-Tunnel nutzen:
  `ssh -L 3306:127.0.0.1:3306 root@<server-ip>`.
- Regeln prüfen: `ufw status numbered`. Hetzner, Netcup & Co. haben oft eine zweite Firewall im Panel.

## Datenbank (MariaDB)

Mit `--with-mariadb` steht der Verbindungs-String in `secrets.cfg`. Root-Login lokal: `sudo mariadb`
(unix_socket, kein Passwort). SQL-Dateien importieren:

```bash
mariadb fivem < "/opt/fivem/server-data/resources/[vendor]/[esx]/[SQL]/legacy.sql"
```

Passwort verloren: `sudo mariadb -e "ALTER USER 'fivem'@'localhost' IDENTIFIED BY 'neuesPasswort';"` und
den String in `secrets.cfg` anpassen. `install.sh` rotiert vorhandene Passwörter nicht.

## Backup

Was zu sichern ist:

- `txData/`: txAdmin-Admins, Einstellungen, Spieler-Datenbank (Bans, Warnungen, Whitelist), Logs.
- `server-data/secrets.cfg`: Lizenz, RCON, DB-Zugang.
- MariaDB: `mariadb-dump --single-transaction fivem | gzip > fivem-$(date +%F).sql.gz` (als root per unix_socket).
- Alles unter `server-data/resources/[local]/` und die Konfiguration sind in Git.

Beispiel als Cronjob (root, täglich um 04:00 über `/etc/cron.d`; `cron.daily` wäre auch möglich, läuft aber
zur Zeit aus `/etc/crontab` bzw. wann immer anacron nachholt):

```bash
mkdir -p /var/backups/fivem
cat > /usr/local/sbin/fivem-backup <<'CRON'
#!/bin/bash
set -euo pipefail
d="/var/backups/fivem/$(date +%F)"
mkdir -p "$d"
tar -czf "$d/txData.tar.gz" -C /opt/fivem txData
cp /opt/fivem/server-data/secrets.cfg "$d/secrets.cfg"
if command -v mariadb-dump >/dev/null 2>&1; then
    mariadb-dump --single-transaction fivem | gzip > "$d/fivem.sql.gz"
fi
find /var/backups/fivem -mindepth 1 -maxdepth 1 -type d -mtime +14 -exec rm -rf {} +
CRON
chmod 700 /usr/local/sbin/fivem-backup
echo '0 4 * * * root /usr/local/sbin/fivem-backup' > /etc/cron.d/fivem-backup
chmod 644 /etc/cron.d/fivem-backup
```

Wiederherstellen: Dienst stoppen, `txData/` zurückkopieren (Besitzer `fivem:fivem`), SQL mit
`gunzip -c fivem.sql.gz | mariadb fivem` einspielen, Dienst starten.

## Fehlerbilder

| Symptom                                                            | Lösung                                                                                              |
|--------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------|
| `Dieses Skript muss als root laufen`                               | `sudo bash scripts/linux/install.sh ...`                                                            |
| `Der Projektpfad ... enthaelt Leerzeichen oder Sonderzeichen`      | Repo in einen einfachen Pfad wie `/opt/fivem` klonen bzw. verschieben, dann `install.sh` erneut ausführen. |
| `Unable to start the server due to error(s) in your config file(s)`| Meldung in `journalctl -fu fxserver` lesen; Ports 40120 bis 40150 tabu, Endpoints tcp+udp identisch.|
| `no license key was specified`                                     | `secrets.cfg` bearbeiten, `systemctl restart fxserver`.                                             |
| `git pull --ff-only fehlgeschlagen`                                | `git -C /opt/fivem status`. Zeigt es `UU` (Folge eines früheren Autostash-Konflikts, Git meldet davor `Exiting because of an unresolved conflict`): `git -C /opt/fivem reset --hard && git -C /opt/fivem stash drop`, denn `git checkout -- <datei>` scheitert dort mit `path ... is unmerged`. Sonst lokale Änderungen verwerfen (`git checkout -- <datei>`) oder abweichenden Branch prüfen. |
| `git pull hat Konflikte hinterlassen (lokale Aenderungen kollidieren mit dem Upstream)` | Der Autostash ließ sich nicht sauber anwenden, in Dateien wie `server.cfg` stehen Konfliktmarker (`git -C /opt/fivem status` zeigt `UU`). Entweder von Hand auflösen und `git -C /opt/fivem stash drop`, oder die lokalen Änderungen verwerfen: `git -C /opt/fivem reset --hard && git -C /opt/fivem stash drop`. Danach `deploy.sh` erneut. |
| `sudo systemctl restart fxserver fehlgeschlagen`                   | `/etc/sudoers.d/fivem-deploy` fehlt, `install.sh` erneut ausführen.                                 |
| Spieler kommen nicht drauf                                         | `ss -lunp | grep 30120`, `ufw status`, Provider-Firewall, `sv_master1` nicht gesetzt?               |
| `Zum Entpacken von fx.tar.xz wird 'xz' benoetigt`                  | `apt install xz-utils`.                                                                             |
| Fehlermeldung zu Nicht-ASCII-Pfaden (txAdmin Fehler 7)             | Repo-Pfad ohne Umlaute wählen, z. B. `/opt/fivem`.                                                  |
