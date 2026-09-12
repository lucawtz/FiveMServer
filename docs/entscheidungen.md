# Designentscheidungen und bekannte Grenzen

Diese Seite erklärt die Stellen, an denen das Repo etwas anders macht, als du es vielleicht aus anderen
FiveM-Anleitungen kennst, und warum. Stand: September 2026 (Artifacts `recommended` 35245, txAdmin 8.1.1).

## txAdmin und FXServer

**txAdmin wird über Umgebungsvariablen konfiguriert, nicht über `+set`-ConVars.** `start.bat`, die
systemd-Unit und `docker/entrypoint.sh` setzen `TXHOST_DATA_PATH` (txData-Ordner) und `TXHOST_TXA_PORT=40120`
und starten `FXServer.exe` bzw. `run.sh` ohne Argumente. txAdmin 8.x meldet `txAdminPort`, `txDataPath` und
`serverProfile` als veraltet und kündigt ihre Entfernung an; mit den Variablen bleibt das Log frei von
solchen Warnungen. Für `serverProfile` gibt es keinen Ersatz, das Profil heißt weiterhin `default`
(`txData/default/`). Der Kanal `optional` (Build 7290, txAdmin 7.0.0) ignoriert die Variablen. Unter Windows
ergeben seine Standardwerte dieselben Pfade und Ports (siehe [windows-lokal.md](windows-lokal.md)). Unter
Linux/Docker ist `optional` nicht vorgesehen: ohne die Variablen legt txAdmin 7 txData innerhalb des
Artifact-Ordners bzw. im Container außerhalb des Volumes an; wer den Kanal dort braucht, muss
`+set txDataPath ...` selbst setzen.

**txAdmin lauscht auf dem VPS auf `0.0.0.0:40120`, zu bleibt der Port über die Firewall.** Naheliegend wäre
`txAdminInterface 127.0.0.1`, aber txAdmin 8.x behandelt diese Schnittstelle als verbindlich für txAdmin *und*
FXServer: der cfg-Validator lehnt jede `endpoint_add_tcp`/`endpoint_add_udp`-Zeile ab, deren IP davon
abweicht, und startet den Server nicht. Die committete `server.cfg` muss aber auf `0.0.0.0:30120` lauschen,
sonst kommt niemand drauf. Deshalb bleibt die Schnittstelle offen, `install.sh` legt keine ufw-Regel für 40120
an (außer mit `--txadmin-public`) und du erreichst txAdmin per SSH-Tunnel
(`ssh -L 40120:127.0.0.1:40120 root@<server-ip>`, dann <http://localhost:40120>). In Docker bindet Compose
den Port nur auf `127.0.0.1:40120` des Hosts, dort braucht es keine Firewall-Regel.

**OneSync steht in keiner cfg-Datei.** txAdmin kommentiert jeden `onesync`-Setter in den cfg-Dateien aus, die
es lädt (auch in per `exec` eingebundenen wie `secrets.cfg`), und verwaltet OneSync selbst unter
Settings > FXServer (Standard `on`). Stände die Zeile in `server.cfg`, wäre die committete Datei nach dem ersten
txAdmin-Start dauerhaft lokal geändert und `deploy.sh` (`git pull --ff-only`) würde beim nächsten Commit an
dieser Datei scheitern; stände sie in `secrets.cfg`, ginge sie nach dem ersten txAdmin-Start still verloren und
der Direktmodus liefe ohne OneSync. Deshalb: txAdmin-Modus, txAdmin setzt OneSync; Direktmodus, das
Startkommando übergibt es als Argument **vor** `+exec`: `start-direct.bat` startet
`FXServer.exe +set onesync on +exec server.cfg`, unter Linux und im Container entsprechend
`bash ../artifacts/run.sh +set onesync on +exec server.cfg`.

**Der Lizenzschlüssel steht in `secrets.cfg`, nicht in txAdmin.** Bei "Existing Server Data" fragt txAdmin
nicht nach dem Key und speichert auch keinen; nur der Recipe-Deployer für komplett neue Server tut das. Der Key
muss also in einer Datei stehen, die `server.cfg` per `exec` lädt. `secrets.cfg` ist gitignored, alle Skripte
warnen bei `changeme`. `exec secrets.cfg` steht in `server.cfg` bewusst nach den allgemeinen Einstellungen
(damit lokale Überschreibungen gewinnen) und vor dem `ensure`-Block (damit oxmysql den Verbindungs-String
schon kennt).

**`sv_enforceGameBuild 3751`.** Build 3751 ("A Safehouse in the Hills") ist der neueste Build, den alle Clients
im Release-Kanal laden. Build 3889 ("The Kortz Center Heist") gab es im September 2026 zunächst nur im
Canary-Kanal und er braucht Artifact >= 35245. Wenn alle deine Spieler 3889 laden können, kannst du in
`server.cfg` hochgehen.

## Windows

**`server.zip` und .NET statt 7-Zip.** `install.ps1 -ArchiveFormat auto` (Standard) nimmt die URL aus der
Changelog-API (derzeit `server.zip`) und entpackt mit `System.IO.Compression.ZipFile`, damit ein frisches
Windows ohne Zusatztools auskommt. Die 7-Zip-Kette (`7z` im PATH, `%ProgramFiles%\7-Zip\7z.exe`, zuletzt
`7zr.exe` nach `tools\` laden) greift nur mit `-ArchiveFormat 7z`, das Archiv ist dort kleiner.

**`install.bat` lädt Artifacts nur, wenn sie fehlen.** Der Doppelklick ist der Alltagsweg auf dem Entwicklungs-PC
und soll nicht nebenbei den Server austauschen. Ein Update gibt es nur ausdrücklich mit `-UpdateArtifacts`
(API abfragen, nur bei anderer Version laden) oder `-ForceArtifacts` (immer neu). `-ForceResources` gibt es
analog für die Ressourcen.

**`VERSION.txt` markiert eine vollständige Artifact-Installation.** Als installiert gelten die Artifacts nur,
wenn neben `FXServer.exe` (Windows) bzw. `run.sh` (Linux) auch `artifacts/VERSION.txt` liegt. Die Datei wird
erst nach erfolgreichem Entpacken geschrieben, unter Windows außerdem vor dem Leeren des Ordners gelöscht. Der
Grund: Im Windows-Archiv steht `FXServer.exe` vor `libnode22.dll` und der VC-Runtime. Nach einem abgebrochenen
Entpacken läge die Exe also schon da, der Server wäre aber nicht startfähig, und ein reiner Test auf die Exe
würde den nächsten Download überspringen. Fehlt `VERSION.txt`, laden `install.bat` und `update-artifacts.sh`
neu, `start.bat` und `start-direct.bat` warnen.

**Basis-Ressourcen werden geprüft, nicht nur installiert.** `server.cfg` startet `mapmanager`, `spawnmanager`
und `basic-gamemode` aus `[cfx-default]`. Fehlen sie, fährt der Server trotzdem hoch, aber niemand spawnt.
`install.ps1` prüft deshalb nach dem Ressourcen-Schritt, auch mit `-SkipResources`, ob die drei Manifeste da
sind, und endet sonst mit Exit 2. `start.bat` und `start-direct.bat` warnen und warten auf eine Taste.

## Linux

**`update-artifacts.sh` ohne Optionen ist ein Update-Lauf.** Auf dem VPS wird das Skript nur von `install.sh`
(mit `--if-missing`, lädt nur, wenn `run.sh` oder `VERSION.txt` fehlt) und von `deploy.sh --update-artifacts`
aufgerufen, also immer dann, wenn du ein Update willst. Ohne Optionen fragt es deshalb die Changelog-API ab und
lädt neu, wenn `run.sh` oder `VERSION.txt` fehlt oder sich die Build-Nummer von `artifacts/VERSION.txt`
unterscheidet, sonst `[OK] Artifacts sind aktuell`. `--force` lädt immer. Eine vollständige vorherige Version
bleibt in `artifacts.bak`. Ein unvollständiger Ordner wird nicht gesichert, damit er keine intakte Sicherung ersetzt.

**`deploy.sh` nutzt `git pull --ff-only --autostash` und bricht bei Konflikten ab.** `--ff-only` verhindert
Merge-Commits auf dem Server, `--autostash` legt lokale Änderungen an versionierten Dateien (typisch: txAdmin
schreibt in `server.cfg`) vor dem Pull beiseite und wendet sie danach wieder an (Git >= 2.27). Kollidieren sie
mit dem Upstream, meldet Git Exit 0 und lässt Konfliktmarker zurück; `deploy.sh` prüft deshalb
`git ls-files --unmerged` und bricht mit einer Meldung ab, statt den Server mit einer kaputten `server.cfg`
neu zu starten (Auflösen: `git -C /opt/fivem status`, verwerfen mit `reset --hard && stash drop`).

**Firewall ist Opt-in.** `install.sh` legt ufw-Regeln nur an, wenn ufw schon aktiv ist (30120/tcp+udp,
40120/tcp nur mit `--txadmin-public`). Ist ufw installiert, aber aus (Ubuntu-Standard), schaltet das Skript es
nicht von sich aus ein: das würde alle anderen Dienste auf dem Server sperren und dich bei einem falsch
erkannten SSH-Port aussperren. Es warnt stattdessen laut, nennt die erkannten SSH-Ports (aus `sshd -T` und
`ssh.socket`, Fallback 22) und die Befehle zum Nachholen. Mit `--enable-firewall` gibt es SSH und 30120 frei
und macht `ufw --force enable`; `--no-firewall` überspringt den Schritt komplett. Auf einem frischen VPS, der
nur den Spielserver trägt, ist `--enable-firewall` die richtige Wahl.

**sudoers-Regel so klein wie möglich.** `/etc/sudoers.d/fivem-deploy` erlaubt dem Service-User nur
`systemctl start|stop|restart fxserver` (und `fxserver.service`) über die vollen Pfade `/usr/bin/systemctl`
und `/bin/systemctl`. `status` braucht kein root und fehlt deshalb. Die Datei wird vor dem Installieren mit
`visudo -cf` geprüft. Die apt-Liste enthält `sudo`, weil `visudo` und der Fallback `sudo -u` daraus kommen.

**Optionales Secret `DEPLOY_KNOWN_HOSTS`.** Ohne das Secret holt `deploy.yml` den Host-Key bei jedem Lauf per
`ssh-keyscan`; wer Pinning will, legt den Key einmal als Secret ab.

## Docker

**`.dockerignore` lässt nur `docker/entrypoint.sh` in den Build-Kontext.** Der Kontext ist der Repo-Root
(Compose: `context: ..`); ohne die Datei gingen `artifacts/`, `txData/`, `.git/`, `secrets.cfg` und `.env` an
den Docker-Daemon.

**Compose nutzt `environment:` statt `env_file`, deshalb immer `--env-file .env`.** Jeder Container bekommt nur
die Variablen, die er braucht: `fxserver` die vier für `secrets.cfg` (`FIVEM_LICENSE_KEY`, `RCON_PASSWORD`,
`STEAM_WEBAPI_KEY`, `MYSQL_CONNECTION_STRING`), `db` die vier `MYSQL_*`-Werte als `MARIADB_*`. So landet das
MariaDB-Root-Passwort nicht im Spiel-Container und der Lizenzschlüssel nicht im DB-Container. Die Kehrseite:
Compose liest `${...}` nur aus einer `.env` neben der Compose-Datei oder aus `--env-file`, deshalb tragen alle
dokumentierten Befehle `docker compose --env-file .env -f docker/docker-compose.yml ...`. Zusätzlich pinnt die
Compose-Datei `platform: linux/amd64` (FXServer gibt es für Linux nur als x86_64), vergibt `image:` und
`container_name:` und setzt `stop_grace_period: 30s`. `FX_CHANNEL` in `.env.example` wählt den Artifact-Kanal
für den Image-Build.

**Das Image installiert nur `curl xz-utils ca-certificates`.** Mehr braucht der Artifact-Download beim Bauen
nicht. `git` und `unzip` benötigt allein `install-resources.sh`, das laut `docs/docker.md` auf dem Host läuft;
das Image enthält die Skripte nicht.

## Manifest resources.txt

**Kommentare:** Zeilen, die mit `#` beginnen, werden ignoriert; ` # Kommentar` am Zeilenende wird nur
abgeschnitten, wenn Leerraum vor dem `#` steht, damit URLs mit `#` heil bleiben. Überzählige Felder (bei `git`
ab dem fünften, bei `zip` ab dem vierten) werden mit einer Warnung ignoriert, nicht als Fehler gezählt.

**Ziele:** `<ziel>` muss relativ zu `server-data/resources/` sein. Abgelehnt werden absolute Pfade, jedes `:`
(Laufwerksbuchstaben), leere Segmente (`foo//bar`) und Segmente, die genau `.` oder `..` sind (`foo/./bar`,
`../x`). `[vendor]/my..script` ist erlaubt. Ein `/` am Ende wird entfernt, unter Windows auch `\`. Beide
Parser (`lib.sh`, `install-resources.ps1`) prüfen dieselben Regeln.

**Git-Ref:** `[ref]` ist ein Branch- oder Tag-Name (`git clone --depth 1 --branch <ref>`), kein Commit-Hash;
ein Hash lässt den Clone fehlschlagen. Unter Linux gibt es zusätzlich `--manifest <pfad>` für ein anderes
Manifest (Windows: `-ManifestPath`).

**`--force` unter Linux lädt erst, dann ersetzt es.** `lib.sh` klont bzw. entpackt in einen Temp-Ordner und
tauscht das Ziel erst nach Erfolg aus; bei einem Netzfehler bleibt der alte Ordner stehen.
`install-resources.ps1` lädt zip-Ziele ebenfalls erst in einen Temp-Ordner und ersetzt danach; nur git-Ziele
löscht es vor dem Neuklonen (`Entferne '<ziel>' (-Force) ...`).

## Bekannte Grenzen / ungetestet

- Die PowerShell-Skripte wurden nur statisch geprüft (Parser 5.1 und PSScriptAnalyzer in der CI, Review), aber
  noch nicht auf einem Windows mit Windows PowerShell 5.1 (oder unter `pwsh`) ausgeführt.
- `install.sh` und das Dockerfile wurden gelesen und in Teilen getestet (Firewall-Logik, `set_cfg_line`,
  Manifest-Parser, `deploy.sh`-Konfliktfall in einer Git-Sandbox), aber noch nicht komplett auf einem echten
  Ubuntu-VPS bzw. mit Docker durchlaufen.
- Der QBCore-Startsatz und der Qbox-Kern in `resources.txt` sind nicht als spielbar verifiziert (siehe
  `docs/frameworks.md`, dort ist Weg B über das txAdmin-Rezept empfohlen).
- Docker Desktop unter Windows ist nicht getestet; empfohlen ist dort `scripts\windows\start.bat`.
