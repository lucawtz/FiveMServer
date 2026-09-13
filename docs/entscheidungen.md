# Designentscheidungen und bekannte Grenzen

Diese Seite erklärt die Stellen, an denen das Repo etwas anders macht, als du es vielleicht aus anderen
FiveM-Anleitungen kennst, und warum. Stand: September 2026 (Artifacts `recommended` 35245, txAdmin 8.1.1, Qbox-Rezept Commit `a4be9fc`).

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
`server.cfg` hochgehen. Das Qbox-Rezept setzt 3258 (Stand 2024); Qbox selbst nennt keinen Pflicht-Build, jeder
Build enthält die Inhalte der früheren, und `bob74_ipl` hat Code für neuere Builds. Deshalb bleibt es bei 3751,
bei Problemen mit einzelnen Innenräumen hilft ein Test mit 3258.

**Zugang nur über die txAdmin-Allowlist.** FXServer kennt kein Beitrittspasswort, und `sv_master1 ""` nimmt den
Server nicht aus der Serverliste, es deaktiviert nur den Verbinden-Button. Für einen reinen Freundes-Server ist die
License Allowlist von txAdmin der vorgesehene Weg: neue Spieler bekommen eine Request ID, ein Admin gibt sie frei
([linux-server.md](linux-server.md#nur-freunde-zulassen-license-allowlist)). Join-Passwort-Skripte aus der
Community wären eine zusätzliche Fremd-Ressource ohne Vorteil.

## Qbox als Framework

**Qbox statt ESX Legacy oder QBCore.** Stand September 2026: Qbox veröffentlicht regelmäßig (`qbx_core` v1.24.0
vom 22.08.2026), das Rezept bringt das ox-Paket (ox_lib, ox_inventory, ox_target, oxmysql) und eine komplette
Roleplay-Grundlage mit, Kern und ox-Ressourcen haben deutsche Sprachdateien, und über `provide 'qb-core'` samt
Brücke laufen die meisten QBCore-Skripte weiter. QBCore hatte in 90 Tagen 5 Commits und keine getaggten Releases.
ESX Legacy ist am aktivsten, sein Rezept nutzt aber ein eigenes Inventar ohne ox_inventory und ox_target. Die
harten Anforderungen von Qbox (OneSync, Artifact >= 10731, MariaDB >= 10.9) erfüllt das Repo. Die Wahl ist eine
Abwägung dieser Fakten, keine offizielle Empfehlung.

**Übersetzung des Rezepts statt txAdmin-Rezept-Deploy.** txAdmin kann ein Rezept nur in einen leeren Ordner
deployen und schreibt dabei eine eigene `server.cfg` mit Lizenzschlüssel und Datenbank-String. Damit gingen die
committete Konfiguration, die Trennung in `secrets.cfg`, `deploy.sh` und ein reproduzierbarer Checkout verloren.
Deshalb steht jeder Download-Schritt des Rezepts als Zeile in `resources.txt`, jeder `query_database`-Schritt als
Zeile in `database.txt` und die Konfiguration in committeten cfg-Dateien. Die Quellen bleiben wie im Rezept auf
`main` bzw. `releases/latest` (npwd fest auf 3.16.0); das Risiko wandernder Stände und das Festhalten per Tag
beschreibt [ressourcen.md](ressourcen.md#fester-stand-oder-immer-aktuell). Alle Abweichungen:
[frameworks.md](frameworks.md#abweichungen-vom-rezept).

**Dritter Manifest-Typ `copy`.** Das Rezept legt drei Dinge über andere Ressourcen: die Qbox-Items
(`ox_inventory/data/items.lua`), die Item-Bilder (`ox_inventory/web/images`) und die npwd-Konfiguration. Ohne die
Qbox-Items funktionieren viele qbx-Ressourcen nicht, und `git`/`zip` können das nicht ausdrücken. Ein einziger
Befehl deckt alle drei Fälle ab. Er läuft bei jedem Aufruf, damit die Überlagerung nach `git pull` oder Force wieder
stimmt, und schreibt Dateien nur bei Unterschieden. `config.json` wird kopiert statt verschoben, weil Verschieben
eine versionierte Datei im Git-Klon von `qbx_npwd` löschen und späteres `git pull --ff-only` stören würde.

**Quell-Repos unter `[vendor]/.sources`.** Das Rezept-Repository und `qbx_invimages` sind keine Ressourcen.
FXServer überspringt Ordner, deren Name mit `.` beginnt (geprüft in `ServerResourceList.cpp`), sie bleiben also
unsichtbar. Ihre Dateien werden bewusst nicht ins eigene Git kopiert: das Rezept-Repository hat keine Lizenzdatei.
`install-resources --check` stellt sicher, dass die Zeile einer Quelle über der `copy`-Zeile steht.

**Verschachtelte Kategorien.** `ensure [qbx]` löst FXServer über `FindByPathComponent` auf, jede Pfadkomponente
zählt, `[vendor]/[qbx]` wird also gefunden. MugShotBase64 hat seine Ressource im Unterordner des Repos und wird
deshalb in den Klammer-Ordner `[MugShotBase64]` geklont, statt das Manifest um Unterpfade zu erweitern.

**Basis-Ressourcen wie im Rezept, `basic-gamemode` gestoppt.** `mapmanager`, `chat` (Systemchat),
`spawnmanager` und `baseevents` bleiben. `sessionmanager` und `hardcap` gibt es in `cfx-server-data` nicht mehr.
`basic-gamemode` schaltet den automatischen Spawn ein und kollidiert mit der Charakterauswahl, deshalb
`stop basic-gamemode` (ein `stop` auf eine gestoppte Ressource ist still). `qbx_core` ruft `spawnmanager` in einem
`pcall` auf.

**`hello-world` hört auf mehrere Signale.** Mit gestartetem `qbx_spawn` laufen bestehende Charaktere über die
Spawn-Auswahl von `qbx_spawn` (auch "letzte Position") und neue Charaktere über die Apartment-Auswahl von
`qbx_properties`. Beide rufen `spawnmanager` nicht auf, `playerSpawned` kommt dort nie. Nur ohne `qbx_spawn` (und
ohne Apartment-Ressource) spawnt `qbx_core` selbst über `spawnmanager`. Die Beispiel-Ressource hört deshalb zusätzlich auf
den Eventnamen `QBCore:Client:OnPlayerLoaded` (nur der Name, keine Abhängigkeit) und begrüßt spätestens zwei
Minuten nach dem Verbinden, jeweils nur einmal.

**Interaktions-Hinweise zentral in ox_lib.** Fast alle Ressourcen zeigen "E - ..." über `lib.showTextUI`, mit
eigener oder ohne Position (Standard `right-center`). Einzelne Ressourcen anzupassen hieße Forks von rund 45
Repos. Eine eigene `textui.lua` per `copy`-Zeile (Weg B) erzwingt `bottom-center` und einen auffälligen Stil für
alle. Weil die Datei zum Stand von ox_lib passen muss, steht ox_lib fest auf v3.39.0.

**Probefahrt über eigene Ressource statt Fork.** `qbx_vehicleshop` hat keine Releases, eine Änderung am Code
bräuchte einen Fork (Weg C). `[local]/probefahrt` hört stattdessen auf denselben State Bag `isInTestDrive`, hält
kurz vor dem Ende das Fahrzeug an und schützt den Spieler, bis der Teleport des Servers durch ist. Grenze: Die
eigene Uhr startet beim Client etwas später als die des Servers; der Vorlauf von 3 Sekunden deckt das ab.
Ändert Qbox den Namen des State Bags, wirkt der Schutz nicht mehr.

**Deutsch über Convars.** `ox:locale "de"` gilt für alle qbx- und ox-Ressourcen mit `locales/*.json`; Ausnahmen
ohne deutsche Texte stehen in [frameworks.md](frameworks.md#sprache). `illenium-appearance:locale` gilt für
Aussehen und Kleidung. `qb_locale` liest keine Rezept-Ressource, es bleibt für QBCore-Skripte über die Brücke.

**Inhalte: nur Lore-Marken und eigene Designs.** In den Regeln von Cfx.re und Rockstar findet sich keine Ausnahme
für private oder reine Freundes-Server, deshalb gelten sie hier genauso ([inhalte-regeln.md](inhalte-regeln.md)). Technische Namen wie GitHub, Docker, Ubuntu, Steam oder
Discord (als Allowlist-Modus) bleiben in der Doku erlaubt, die Regeln betreffen Spielinhalte.

**Hinweis in `sv_projectDesc`.** Die committete `server.cfg` hängt an die Beschreibung den Hinweis
"<NAME> IS NOT APPROVED, SPONSORED, OR ENDORSED BY ROCKSTAR GAMES." an. PLA §2.3 verlangt ihn in allen Angaben, die
Spieler zum Server sehen, also auch im Eintrag der Serverliste und auch bei privaten Servern. `<NAME>` ist der
Projektname aus `sv_projectName`, im Standard `Mein RP-Projekt`, im Hinweis also "MEIN RP-PROJEKT". Der Platzhalter enthält bewusst
weder FiveM noch Rockstar, weil deren Namen nicht in den Servernamen gehören; bei einer Umbenennung ändert sich der
Name im Hinweis nicht von selbst. Betreiber und Kontakt-E-Mail gehören nicht in Git, deshalb überschreibt jeder
`sv_projectDesc` in `secrets.cfg` (Vorlage in `secrets.cfg.example`).

## Datenbank

**Eigene Buchführung der SQL-Dateien.** `server-data/database.txt` listet die Dateien in Rezept-Reihenfolge, die
Tabelle `repo_sql_imports` (`file_path`, `sha256`, `imported_at`, `applied_by`) merkt sich, was gelaufen ist.
`qbox.sql` und npwds `import.sql` sind nicht wiederholbar, also läuft jede Datei genau einmal. MariaDB führt
`CREATE`/`ALTER TABLE` mit implizitem Commit aus, eine fehlgeschlagene Datei lässt sich nicht zurückrollen: der Import
stoppt bei der ersten fehlerhaften Datei und trägt sie nicht ein. Eine geänderte Datei erzeugt nur eine Warnung,
außer sie ist mit `rerun` als wiederholbar markiert (Qbox liefert Spalten-Migrationen mit `IF NOT EXISTS`). Für
Datenbanken, die anders eingerichtet wurden, gibt es `--mark-applied`.

**Der Importer liest den Verbindungs-String wie oxmysql, ohne URL-Dekodierung.** oxmysql 2.14.1 reicht das
Passwort ohne `decodeURIComponent` an mysql2 weiter (`src/config.ts`). Ein dekodierender Importer würde sich mit
anderen Zugangsdaten anmelden als der laufende Server. Die Skripte übernehmen deshalb Regex, Aliase und
Groß-/Kleinschreibung von oxmysql, lassen wie oxmysql die Query-Parameter der URI (`host`, `port`, `user`,
`password`, `database`, `socketPath`) die Angaben davor überschreiben und warnen bei `%XX`. Erzeugte Passwörter sind hex und damit in beiden
Schreibweisen sicher.

**Zugangsdaten in `--defaults-file`, SQL per stdin.** `--defaults-file` als erstes Argument verhindert, dass eine
`~/.my.cnf` die Werte überschreibt. Im Batch-Modus über stdin stoppt der Client beim ersten Fehler mit Exit 1,
`source` würde Fehler ignorieren. Kein Passwort steht auf einer Kommandozeile. Unter Windows schreibt
`System.Diagnostics.Process` die Bytes direkt nach stdin; `Start-Process -RedirectStandardInput` kodiert in
PowerShell 5.1 über die Konsolen-Codepage um und liefert den Exit-Code nicht zuverlässig.

**MariaDB ab 10.9, zwei Accounts.** Qbox verlangt mindestens 10.9 und empfiehlt 12.3 LTS; Docker und winget nutzen
12.3, Ubuntu 24.04 liefert 10.11. `--create` legt `user@localhost` und `user@127.0.0.1` mit demselben Passwort an und
schreibt `127.0.0.1` in den String: eine TCP-Verbindung über Loopback passt nur ohne `skip-name-resolve` zu
`@localhost`, mit zwei Accounts klappt es in beiden Fällen, und `127.0.0.1` vermeidet, dass Node.js `localhost` zu
`::1` auflöst. Ein unbekanntes Passwort ändert `--create` nur mit `--reset-password`. Das schließt die Lücke des
alten `install.sh`, das bei vorhandenem User keinen String schrieb. Die Datenbank bekommt utf8mb4/utf8mb4_unicode_ci,
das Rezept legt sie mit utf8 an ([frameworks.md](frameworks.md#abweichungen-vom-rezept)).

**`--create` prüft so, wie oxmysql verbindet, und schreibt das Passwort in keine Logdatei.** Ohne neues Passwort
bleibt ein vorhandener String unverändert. Ein angegebenes `--db-port` bzw. `-Port`, das vom Port dieses Strings
(TCP, ohne `socketPath`) abweicht, bricht deshalb mit Exit 1 ab (außer mit `--reset-password`/`-ResetPassword`): sonst meldete das Skript
Erfolg, während oxmysql weiter den alten Port nutzt. Hat der behaltene String `socketPath`, prüft `--create` die
Anmeldung über diesen Socket (Windows: Named Pipe), sonst über TCP `127.0.0.1:<port>`. Unter Linux besteht ein
Server mit `skip-networking` die Prüfung damit. Unter Windows meldet sich `-Create` als root und beim Test des
vorhandenen Passworts weiter über TCP an, `skip-networking` geht dort nicht. Ein neues Passwort erscheint nur, wenn die Ausgabe ein Terminal ist
(Linux: stderr, Windows: Ausgabe nicht umgeleitet). Bei `install.sh 2>&1 | tee install.log` oder einer
umgeleiteten Windows-Ausgabe steht dort nur ein Hinweis auf `secrets.cfg`. Der Root-Batch nimmt vorher
`NO_BACKSLASH_ESCAPES` aus dem `sql_mode` der Sitzung, damit ein aus `secrets.cfg` übernommenes Passwort mit
Backslash-Maskierung ein einziges SQL-Literal bleibt.

**Einheitliche Exit-Codes 0/1/2/3.** `deploy.sh` und `install.sh` brauchen ein klares Fehlersignal, und du sollst
"Datenbank nicht erreichbar" (2) von "eine SQL-Datei ist fehlgeschlagen" (3) unterscheiden können. `install.ps1`
behält seine Codes 0/1/2 und macht aus jedem Datenbank-Fehler 2, damit `install.bat` gleich bleibt.


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
und `baseevents` aus `[cfx-default]`. Fehlen sie, fährt der Server trotzdem hoch, aber niemand spawnt.
`install.ps1` prüft deshalb nach dem Ressourcen-Schritt, auch mit `-SkipResources`, ob die drei Manifeste da
sind, und endet sonst mit Exit 2. `start.bat` und `start-direct.bat` warnen und warten auf eine Taste.

**MariaDB per winget, interaktiv.** `setup-database.bat -InstallMariaDB` ruft
`winget install --id MariaDB.Server -e --interactive` ohne `--silent`, `--override` oder `PASSWORD` auf. Eine stille
MSI-Installation ohne `SERVICENAME` legt keinen Windows-Dienst an, und ein mitgegebenes Passwort stünde sichtbar
bzw. protokolliert auf der Kommandozeile. winget installiert standardmäßig still, erst `--interactive` zeigt den
Assistenten mit maskiertem Passwortfeld und Dienstname `MariaDB`.

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

**MariaDB ist Standard in `install.sh`.** Qbox läuft nicht ohne Datenbank, der Standardweg soll einen
lauffähigen Server ergeben. Wer eine entfernte Datenbank nutzt, gibt `--no-mariadb` an; `--with-mariadb` wird als
wirkungslose Option weiter akzeptiert. Ein Fremd-Repository fügt das Skript nie selbst hinzu: eine fest
eingetragene Prüfsumme von `mariadb_repo_setup` würde bei jedem Update des Skripts veralten, und das Zielsystem
Ubuntu 24.04 braucht es nicht. Ist MariaDB zu alt, gibt es die Anleitung aus, markiert den Datenbank-Teil als
fehlgeschlagen, führt systemd, sudoers und Firewall trotzdem aus und endet mit Exit 1.

**`deploy.sh` importiert SQL vor dem Neustart.** Neue Zeilen in `database.txt` oder neue Ressourcen bekommen ihre
Tabellen, bevor der Server neu startet. Schlägt der Import fehl, bleibt der alte Prozess laufen. `--no-sql` und
die Eingabe `skip_sql` in `deploy.yml` überspringen den Schritt.

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

**`mariadb:12.3` mit Auto-Upgrade, SQL-Import vom Host.** Das Image passt zur Qbox-Empfehlung und zur
winget-Version, `MARIADB_AUTO_UPGRADE` hebt ein vorhandenes 11.x-Volume beim Start an. `setup-database.sh --docker`
startet den Client im `db`-Container mit dessen eigenem `MARIADB_USER`/`MARIADB_PASSWORD` (per `MYSQL_PWD` innerhalb
von `sh -c`): das Passwort steht auf dem Host in keiner Kommandozeile, und das FXServer-Image braucht keinen Client.
Vorher wartet das Skript bis zu 120 s auf den Healthcheck, weil beim ersten Init oder einem Upgrade ein
Hilfsserver ohne den User auf demselben Socket antwortet. Der Healthcheck hat deshalb `start_period: 120s`: vorher
zählen Fehlschläge nicht, sonst wäre `db` nach etwa 40 s `unhealthy` und `up -d --wait db` sowie
`depends_on: service_healthy` brächen ab. Ein erfolgreicher Check meldet auch in dieser Zeit sofort `healthy`.
`start_interval` fehlt bewusst: ältere Compose-Versionen lehnen den Schlüssel bei Docker Engine vor Version 25 ab.

**Das Image installiert nur `curl xz-utils ca-certificates`.** Mehr braucht der Artifact-Download beim Bauen
nicht. `git` und `unzip` benötigt allein `install-resources.sh`, das laut `docs/docker.md` auf dem Host läuft;
das Image enthält die Skripte nicht.

## Manifest resources.txt

**Kommentare:** Zeilen, die mit `#` beginnen, werden ignoriert; ` # Kommentar` am Zeilenende wird nur
abgeschnitten, wenn Leerraum vor dem `#` steht, damit URLs mit `#` heil bleiben. Überzählige Felder (bei `git`
ab dem fünften, bei `zip` und `copy` ab dem vierten) werden mit einer Warnung ignoriert, nicht als Fehler gezählt.

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

- Auf Windows 11 mit Windows PowerShell 5.1 liefen am 13.09.2026 `install.ps1` (Artifacts 35245, 80 von 80
  Manifest-Einträgen), `setup-database.ps1` mit `-InstallMariaDB`, `-Create -Import` und `-DryRun` gegen
  MariaDB 12.3.3 sowie `start.bat` mit txAdmin 8.1.1 erfolgreich. Noch nicht auf Windows ausgeführt:
  `start-direct.bat`, die Update- und Force-Pfade (`-UpdateArtifacts`, `-UpdateResources`, `-ForceResources`),
  `-ResetPassword`, `-MarkApplied` und die Fehlerpfade.
- `install.sh`, `setup-database.sh` und das Dockerfile wurden gelesen und in Teilen getestet (Firewall-Logik,
  `cfg_set_line`, Manifest-Parser, Verbindungs-String-Parser, Import mit einem Platzhalter-Client, `deploy.sh`-Konfliktfall
  in einer Git-Sandbox), aber noch nicht komplett auf einem echten Ubuntu-VPS, gegen eine echte MariaDB bzw. mit
  Docker durchlaufen. Die Tests liefen mit bash 3.2 und BSD-Werkzeugen, nicht mit GNU awk/grep. Der
  Healthcheck mit `start_period: 120s` folgt der Healthcheck-Logik von Docker und wurde nicht bei einem echten
  Auto-Upgrade gemessen.
- Ob `--create`/`-Create` das neue Datenbank-Passwort anzeigt, hängt nur daran, ob die Ausgabe ein Terminal ist.
  Mitschnitte über ein Terminal (`script` unter Linux, `Start-Transcript` in PowerShell) enthalten es trotzdem.
- Verschachtelte Kategorien (`ensure [qbx]` innerhalb von `[vendor]`) funktionieren, der erste Serverstart am
  13.09.2026 hat alle Ressourcen gestartet und oxmysql mit der Datenbank verbunden.
- Beim Start meldet FXServer zweimal `Argument count mismatch (passed 1, wanted 2)`. Das kommt nicht aus den
  cfg-Dateien: txAdmin 8.1.1 setzt bei ausgeschalteter Allowlist `sets sv_allowlistInstructions ""`, einmal als
  Startargument und einmal zur Laufzeit, und der leere Wert zählt nicht als Argument. Harmlos, mit
  eingeschalteter Allowlist und Ablehnungstext sollte die Meldung verschwinden.
- Die Spielbarkeit von Qbox (Charaktererstellung, Jobs, Handy) ist nicht im Spiel verifiziert.
- Git-Ressourcen auf `main` und zip-Ressourcen auf `releases/latest` bewegen sich: ein Deploy kann Stände
  zusammenbringen, die nicht zueinander passen (siehe [ressourcen.md](ressourcen.md#fester-stand-oder-immer-aktuell)).
- Fremd-Ressourcen können Namen echter Produkte oder Dienste enthalten, siehe [inhalte-regeln.md](inhalte-regeln.md).
- Die Menünamen der txAdmin-Allowlist stammen aus dem Quellcode, nicht aus einem Klick-Test in txAdmin 8.1.1.
- Docker Desktop unter Windows ist nicht getestet; empfohlen ist dort `scripts\windows\start.bat`.
