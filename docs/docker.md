# Docker: FXServer + MariaDB mit Compose

Der Docker-Weg ist eine Alternative zu systemd auf einem Linux-Host. Das Image enthält nur die
FXServer-Artifacts; `server-data/` und `txData/` kommen als Volumes von außen. FXServer für Linux ist
x86_64-only; die Compose-Datei pinnt deshalb `platform: linux/amd64` (ein eigener `--platform`-Hinweis beim Build
ist damit auch auf Apple Silicon nicht mehr nötig), auf Apple Silicon und ARM-VPS läuft der Container emuliert
(langsam). Der Artifact-Kanal kommt optional aus `FX_CHANNEL` in der `.env` (Standard `recommended`).

## Dateien

- `docker/Dockerfile`: `FROM ubuntu:24.04`, `ARG FX_CHANNEL=recommended` (erlaubt: `recommended`, `latest`,
  `optional`), `ARG FX_CHANGELOG_API` (Linux-Endpunkt). Installiert nur `curl xz-utils ca-certificates`
  (`git` und `unzip` braucht allein `scripts/linux/install-resources.sh`, das auf dem Host läuft),
  liest URL und Build aus der Changelog-API (dieselbe sed-Logik wie `lib.sh`), entpackt `fx.tar.xz` nach
  `/opt/fxserver` und schreibt `/opt/fxserver/VERSION.txt`. Entfernt den User `ubuntu` (uid 1000) des
  Basis-Images und legt `fivem` mit uid/gid 1000 an. `VOLUME /server-data /txData`,
  `EXPOSE 30120/tcp 30120/udp 40120/tcp`, `USER fivem`, `WORKDIR /server-data`,
  `ENTRYPOINT /usr/local/bin/entrypoint.sh`. Build-Kontext ist der Repo-Root.
- `docker/entrypoint.sh`: prüft `run.sh` und `/server-data` (Exit 1, wenn sie fehlen), warnt bei fehlender
  `server.cfg`, nicht beschreibbaren Volumes und leerem `[cfx-default]`. Fehlt `/server-data/secrets.cfg` und
  ist `FIVEM_LICENSE_KEY` gesetzt, schreibt es die Datei (chmod 600) mit `sv_licenseKey` und, wenn nicht leer,
  `set rcon_password`, `set steam_webApiKey`, `set mysql_connection_string` aus `RCON_PASSWORD`,
  `STEAM_WEBAPI_KEY`, `MYSQL_CONNECTION_STRING`. Kein `set onesync on`: OneSync steht in keiner cfg-Datei,
  txAdmin verwaltet es selbst (Settings > FXServer, Standard "on") und würde die Zeile sonst auskommentieren.
  Eine vorhandene `secrets.cfg` bleibt unverändert (Warnung bei `changeme`). Dann `cd /server-data`,
  `export TXHOST_DATA_PATH=/txData TXHOST_TXA_PORT=40120` und `exec /opt/fxserver/run.sh "$@"`. Zusätzliche
  Container-Argumente werden angehängt.
- `docker/docker-compose.yml`: Services `fxserver` (`platform: linux/amd64`, Build aus `..` mit
  `docker/Dockerfile`, Build-Arg `FX_CHANNEL` aus `${FX_CHANNEL:-recommended}`, Image `fivem-fxserver:local`,
  Ports `30120:30120/tcp`, `30120:30120/udp`, `127.0.0.1:40120:40120/tcp`, Volumes `../server-data:/server-data`
  und `txdata:/txData`, `environment:` nur mit `FIVEM_LICENSE_KEY`, `RCON_PASSWORD`, `STEAM_WEBAPI_KEY` und
  `MYSQL_CONNECTION_STRING` aus der `.env` (kein `env_file`, das MariaDB-Root-Passwort bleibt draußen),
  `depends_on db: service_healthy`, `restart unless-stopped`, `stop_grace_period 30s`) und `db`
  (`mariadb:11`, kein `env_file`, sondern ein `environment:`-Block mit `MARIADB_ROOT_PASSWORD`,
  `MARIADB_DATABASE`, `MARIADB_USER`, `MARIADB_PASSWORD` aus den `${MYSQL_*}`-Variablen der `.env`, damit
  Lizenz-, RCON- und Steam-Key nicht im DB-Container landen; Volume `dbdata:/var/lib/mysql`, Healthcheck
  `healthcheck.sh --connect --innodb_initialized`, Port 3306 nicht veröffentlicht, Beispielzeile
  `127.0.0.1:3306:3306` auskommentiert). Named Volumes `txdata`, `dbdata`.
- `.env.example`: Vorlage für `.env` im Repo-Root.

## Erststart

Auf dem Docker-Host, aus dem Repo-Root:

```bash
cp .env.example .env
nano .env                                  # FIVEM_LICENSE_KEY, Passwörter setzen
scripts/linux/install-resources.sh         # [cfx-default] und resources.txt auf dem Host installieren
sudo chown -R 1000:1000 server-data        # Container läuft als uid 1000
docker compose --env-file .env -f docker/docker-compose.yml up -d --build
docker compose --env-file .env -f docker/docker-compose.yml logs -f fxserver   # txAdmin-PIN
```

`install-resources.sh` braucht auf dem Host `git` und `unzip`. Das Image enthält die Skripte nicht; der
Entrypoint warnt nur, wenn `[cfx-default]` leer ist.

`--env-file .env` ist nötig: die Compose-Datei nutzt kein `env_file`, sondern `${...}`-Interpolation in den
`environment:`-Blöcken beider Services, und die liest Compose nur aus einer `.env` neben der Compose-Datei
oder aus `--env-file`. Aus `docker/` heraus entsprechend
`cd docker && docker compose --env-file ../.env ...`.

### .env

| Variable                  | Bedeutung                                                                                   |
|---------------------------|---------------------------------------------------------------------------------------------|
| `FIVEM_LICENSE_KEY`       | Lizenzschlüssel aus dem Portal. Wird nur beim ersten Start in `secrets.cfg` geschrieben.    |
| `RCON_PASSWORD`           | Leer = RCON aus. Erzeugen mit `openssl rand -hex 16`.                                        |
| `STEAM_WEBAPI_KEY`        | Optional, für `steam:`-Identifier.                                                          |
| `MYSQL_ROOT_PASSWORD`     | root-Passwort des `db`-Containers. Compose reicht die `MYSQL_*`-Werte als `MARIADB_*` an `db` weiter. |
| `MYSQL_DATABASE`          | Datenbankname, Standard `fivem`.                                                            |
| `MYSQL_USER` / `MYSQL_PASSWORD` | Anwendungs-User, Standard `fivem`.                                                    |
| `MYSQL_CONNECTION_STRING` | `mysql://fivem:<MYSQL_PASSWORD>@db/fivem?charset=utf8mb4`; Host ist der Service-Name `db`.  |

Wichtig: Der Container erzeugt `server-data/secrets.cfg` nur, wenn die Datei fehlt. Änderst du später
Werte in `.env`, musst du `secrets.cfg` von Hand anpassen oder löschen (dann wird sie neu erzeugt).
Die `.env` ist gitignored.

### Rechte: uid 1000

Der Prozess im Container läuft als `fivem` mit uid/gid 1000. Der Bind-Mount `server-data/` muss auf dem
Host uid 1000 gehören, sonst kann txAdmin `secrets.cfg` nicht schreiben, keine `cache/` anlegen und
`server.cfg` nicht anpassen. Deshalb `sudo chown -R 1000:1000 server-data`. Ist dein eigener Host-User
zufällig uid 1000 (erster User auf vielen Ubuntu-Installationen), ist nichts zu tun. Nach dem `chown` brauchst
du für Änderungen an den Dateien eventuell `sudo` oder machst dich per `usermod -aG` zum Mitglied der
Gruppe 1000. `txData` liegt in einem Named Volume, dort stimmt der Besitzer automatisch.

Docker Desktop unter Windows: nur mit dem Repo im WSL2-Dateisystem sinnvoll und nicht getestet. Der
empfohlene Weg unter Windows ist `scripts\windows\start.bat`.

## txAdmin und Verbindung

- txAdmin ist auf dem Host nur unter `127.0.0.1:40120` erreichbar. Lokal: <http://localhost:40120>.
  Auf einem VPS: `ssh -L 40120:127.0.0.1:40120 root@<server-ip>` und dann dieselbe Adresse.
- Im Container lauscht txAdmin auf `0.0.0.0`, damit die Port-Weiterleitung von Docker funktioniert.
  Da das der Schnittstelle der `endpoint_add_*`-Zeilen (`0.0.0.0`) entspricht, meckert der cfg-Validator nicht.
- Erster Start: PIN aus `logs -f fxserver`, "Link Account", dann "Existing Server Data" mit Ordner
  `/server-data` und CFG `server.cfg` (die Pfade aus Sicht des Containers).
- Spieler verbinden auf `<host-ip>:30120`. 30120/tcp und udp in der Host-Firewall öffnen.

Direktmodus ohne txAdmin (der Entrypoint reicht alle Argumente an `run.sh` durch; `--service-ports` ist
nötig, weil `run` die Ports sonst nicht veröffentlicht). `+set onesync on` kommt als Argument vor `+exec`
mit, weil keine cfg-Datei OneSync setzt:

```bash
docker compose --env-file .env -f docker/docker-compose.yml run --rm --service-ports fxserver +set onesync on +exec server.cfg
```

## Datenbank

Der `db`-Service legt beim ersten Start Datenbank und User aus `.env` an. SQL importieren:

```bash
docker compose --env-file .env -f docker/docker-compose.yml exec -T db mariadb -u fivem -p"$(grep '^MYSQL_PASSWORD=' .env | cut -d= -f2-)" fivem < "server-data/resources/[vendor]/[esx]/[SQL]/legacy.sql"
```

Mit einem grafischen Client: die auskommentierten `ports`-Zeilen beim `db`-Service einkommentieren
(`127.0.0.1:3306:3306`) und lokal verbinden, auf einem VPS per SSH-Tunnel.

Dump: `docker compose --env-file .env -f docker/docker-compose.yml exec db mariadb-dump -u root -p"<root-pw>" fivem | gzip > fivem.sql.gz`.

## Aktualisieren

- Eigener Code und Ressourcen: `git pull`, `scripts/linux/install-resources.sh --update`, dann
  `docker compose --env-file .env -f docker/docker-compose.yml restart fxserver`.
- Neue FXServer-Artifacts: das Image neu bauen. Der Download-Layer ist gecacht, deshalb `--no-cache`:

  ```bash
  docker compose --env-file .env -f docker/docker-compose.yml build --no-cache fxserver
  docker compose --env-file .env -f docker/docker-compose.yml up -d
  ```

  Anderer Kanal: `docker compose --env-file .env -f docker/docker-compose.yml build --no-cache --build-arg FX_CHANNEL=latest fxserver`
  oder `FX_CHANNEL=latest` in die `.env` eintragen (die Compose-Datei liest `${FX_CHANNEL:-recommended}`). Version prüfen:
  `docker compose --env-file .env -f docker/docker-compose.yml exec fxserver cat /opt/fxserver/VERSION.txt`.
- Stoppen: `docker compose --env-file .env -f docker/docker-compose.yml down` (Volumes bleiben). `down -v` löscht `txdata`
  und `dbdata`, also txAdmin-Admins und die Datenbank.

## Backup

- `server-data/` liegt auf dem Host (inkl. `secrets.cfg`).
- txData: `docker run --rm -v docker_txdata:/txData -v "$PWD":/backup ubuntu tar -czf /backup/txData.tar.gz -C / txData`
  (der Volume-Name ist `<projektname>_txdata`, prüfen mit `docker volume ls`).
- Datenbank: Dump wie oben.

## Hinweise

- Der Build-Kontext ist der Repo-Root. Die `.dockerignore` im Root schließt alles außer `docker/entrypoint.sh`
  aus; `artifacts/`, `txData/`, `.git/`, `secrets.cfg` und `.env` gehen also nicht an den Docker-Daemon.
- txAdmin-Port und txData-Pfad setzt `entrypoint.sh` als Umgebungsvariablen `TXHOST_TXA_PORT` und
  `TXHOST_DATA_PATH` (wie `start.bat` und die systemd-Unit). Die alten ConVars `serverProfile`, `txAdminPort`,
  `txAdminInterface`, `txDataPath` sind in txAdmin 8.x veraltet und werden nicht mehr benutzt.
- `optional` (Build 7290) ist ein alter Stand von Januar 2024 mit txAdmin 7.0.0 und nur für Notfälle gedacht.
