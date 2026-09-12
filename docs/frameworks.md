# Frameworks: ESX Legacy, QBCore, Qbox

Dieses Repo ist framework-frei. Diese Seite beschreibt ehrlich, was nötig ist, um eines der drei großen
Frameworks aufzusetzen. Die offiziellen Wege sind bei allen dreien txAdmin-Rezepte; eine dokumentierte
"manuelle" Installation gibt es bei ESX und Qbox nicht. Die Schritte unten sind aus den offiziellen
Rezepten (`recipe.yaml`) und den `server.cfg`-Vorlagen der Projekte abgeleitet (Stand September 2026).

Entscheide dich für **eines**. Qbox stellt `qb-core` bereit (`provide 'qb-core'`), QBCore und Qbox
gleichzeitig geht nicht.

| Framework   | Quelle                                        | Braucht                                                   | SQL                                            |
|-------------|-----------------------------------------------|-----------------------------------------------------------|------------------------------------------------|
| ESX Legacy  | `esx-framework/esx_core`, Branch `main`, 1.15.x | oxmysql, OneSync, eigene `esx_lib` (kein ox_lib nötig)     | `[SQL]/legacy.sql` (eine Datei)                |
| QBCore      | `qbcore-fivem/qb-*`, Branch `main`            | oxmysql, OneSync (kein ox_lib nötig)                      | `qb-core/qbcore.sql`                           |
| Qbox        | `Qbox-project/qbx_*`, Branch `main`           | oxmysql, ox_lib, OneSync, FXServer >= 10731, MariaDB >= 10.9 | `qbx_core.sql` plus SQL pro Ressource       |

## Gemeinsame Voraussetzungen

### 1. MariaDB

Alle drei wollen MariaDB (nicht MySQL 8, kein XAMPP). Datenbankname in diesem Repo: `fivem`, User `fivem`.

**Windows, nativ:**

```
winget install --id MariaDB.Server -e
```

Der Installer fragt nach einem root-Passwort und legt den Dienst `MariaDB` an. Danach in einer
Eingabeaufforderung (Versionsnummer im Pfad anpassen, z. B. `MariaDB 12.3`):

```
"C:\Program Files\MariaDB 12.3\bin\mariadb.exe" -u root -p -e "CREATE DATABASE IF NOT EXISTS fivem CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci; CREATE USER IF NOT EXISTS 'fivem'@'localhost' IDENTIFIED BY 'DEIN_PASSWORT'; GRANT ALL PRIVILEGES ON fivem.* TO 'fivem'@'localhost'; FLUSH PRIVILEGES;"
```

**Windows, Docker Desktop:** nur den `db`-Service starten, vorher in `docker/docker-compose.yml` die
`ports`-Zeilen `127.0.0.1:3306:3306` beim `db`-Service einkommentieren und `.env` aus `.env.example` anlegen:

```
docker compose --env-file .env -f docker/docker-compose.yml up -d db
```

Datenbank und User kommen dann aus `MYSQL_DATABASE`, `MYSQL_USER`, `MYSQL_PASSWORD` der `.env`. Host für den
Verbindungs-String ist `localhost`.

**Linux:** `sudo bash scripts/linux/install.sh --with-mariadb` (auch nachträglich möglich). Legt Datenbank und
User an und schreibt `mysql_connection_string` in `secrets.cfg`. Root-Zugang: `sudo mariadb`.
Ubuntu 24.04 liefert MariaDB 10.11, das reicht für alle drei (Qbox braucht mindestens 10.9).

**Docker Compose:** der `db`-Service, Host im Verbindungs-String ist `db`.

### 2. Verbindungs-String in secrets.cfg

```
set mysql_connection_string "mysql://fivem:DEIN_PASSWORT@localhost/fivem?charset=utf8mb4"
```

Diese Sonderzeichen im Passwort vermeiden: `; , / ? : @ & = + $ #`. Auf Linux mit `--with-mariadb` und in
Docker ist die Zeile schon eingetragen.

### 3. oxmysql und ox_lib installieren

In `server-data/resources.txt` die Zeilen aktivieren (`#` entfernen):

```
zip [vendor]/oxmysql https://github.com/overextended/oxmysql/releases/latest/download/oxmysql.zip
zip [vendor]/ox_lib https://github.com/overextended/ox_lib/releases/latest/download/ox_lib.zip
```

ox_lib nur, wenn du es brauchst (Qbox: Pflicht; ESX und QBCore: optional, viele Zusatzskripte wollen es).
Dann installieren: Windows `scripts\windows\install.bat`, Linux `scripts/linux/install-resources.sh`.
In `server.cfg` im Abschnitt "Ressourcen" einkommentieren:

```
ensure oxmysql
ensure ox_lib
```

`exec secrets.cfg` steht in `server.cfg` bereits vor dem ensure-Block, oxmysql kennt den Verbindungs-String
also beim Start. OneSync steht in keiner cfg-Datei: im txAdmin-Modus verwaltet txAdmin es selbst
(Settings > FXServer, Standard "on"), im Direktmodus übergeben `start-direct.bat` bzw.
`bash ../artifacts/run.sh +set onesync on +exec server.cfg` es als Startargument.

### 4. SQL importieren

Die SQL-Dateien legen keine Datenbank an, `fivem` muss existieren.

```
Windows (cmd):  "C:\Program Files\MariaDB 12.3\bin\mariadb.exe" -u fivem -p fivem < "server-data\resources\[vendor]\[esx]\[SQL]\legacy.sql"
Linux:          mariadb fivem < "/opt/fivem/server-data/resources/[vendor]/[esx]/[SQL]/legacy.sql"     (als root, unix_socket)
Docker:         docker compose --env-file .env -f docker/docker-compose.yml exec -T db mariadb -u fivem -pPASSWORT fivem < "server-data/resources/[vendor]/[esx]/[SQL]/legacy.sql"
```

In PowerShell funktioniert `<` nicht; dort `cmd /c "..."` nutzen oder HeidiSQL
(`winget install --id HeidiSQL.HeidiSQL -e`, Datei > SQL-Datei ausführen).

## Zwei Wege zur Installation

**Weg A, resources.txt (reproduzierbar, git-freundlich):** die vorbereiteten Blöcke im Manifest aktivieren,
Installer laufen lassen, SQL importieren, `ensure`-Zeilen setzen. Nachteil: Du bekommst nur die Ressourcen,
die im Manifest stehen. Bei ESX ist das der komplette Kern, bei QBCore ein Startsatz, bei Qbox nur der Kern.

**Weg B, txAdmin-Rezept in einen frischen Ordner, dann kopieren:** txAdmin kann ein Rezept nur in einen
leeren Ordner deployen, nicht in das bestehende `server-data`. Ablauf:

1. Server per `start.bat` (Windows) bzw. `systemctl start fxserver` (Linux) starten und txAdmin öffnen.
2. Server in txAdmin stoppen. Unter Settings > FXServer die Server-Einstellungen zurücksetzen ("Reset FXServer
   Settings"), danach zeigt txAdmin wieder die Setup-Seite (sonst <http://localhost:40120/setup> aufrufen).
   Dort "Popular Recipes" wählen: "ESX Legacy", "QBCore" oder "Qbox".
3. Zielordner: der Vorschlag liegt unter `txData/<name>_<zeit>.base` (gitignored, passt). Datenbank-Daten
   eingeben (Host, Port 3306, User `fivem`, Passwort, Datenbank `fivem`), Lizenzschlüssel eingeben,
   "Run Recipe". Das Rezept lädt alle Ressourcen und importiert die SQL-Dateien selbst.
4. Nach dem Deploy den Server **nicht** aus diesem Ordner laufen lassen, sondern kopieren:
   - Ressourcen-Kategorien aus `txData/<name>.base/resources/` (z. B. `[core]`, `[esx_addons]`, `[standalone]`,
     `[qb]`, `[qbx]`, `[ox]`, `[voice]`) nach `server-data/resources/[vendor]/` verschieben.
     `[cfx-default]` nicht doppelt übernehmen.
   - Die `server.cfg` des Rezepts mit der eigenen vergleichen: `ensure`-Zeilen, `setr`/`set`-Convars und
     `add_ace`/`add_principal`-Zeilen in die eigene `server.cfg` übernehmen. Den `sv_licenseKey` und den
     `mysql_connection_string` daraus **nicht** übernehmen (gehören in `secrets.cfg`, sind dort schon).
   - Weitere cfg-Dateien des Rezepts (`ox.cfg`, `permissions.cfg`, `voice.cfg` bei Qbox) nach `server-data/`
     kopieren und per `exec` einbinden, wenn du sie brauchst.
5. In txAdmin Settings > FXServer den Server Data Folder wieder auf `server-data` und die CFG auf `server.cfg`
   stellen, Server starten.
6. Dokumentiere die kopierten Ressourcen im Manifest (als `git`/`zip`-Einträge), damit ein frischer Checkout
   sie wieder holt; `[vendor]` selbst ist gitignored.

Weg B ist der sicherste Weg zu einem vollständigen, lauffähigen Framework-Server, Weg A der sauberste für Git.

## ESX Legacy

Repo `esx-framework/esx_core` hat keine Release-Zips, deshalb wird es komplett geklont. Die Ressourcen
liegen darin unter `[core]/` (es_extended, esx_lib, esx_menu_*, esx_identity, esx_skin, skinchanger, ...),
das SQL unter `[SQL]/legacy.sql`. Ordner wie `.github/` oder `[SQL]/` ignoriert FXServer. Der Submodul-Ordner
`esx_multicharacter` bleibt bei `--depth 1` leer, das ist unkritisch.

1. MariaDB, Verbindungs-String, oxmysql wie oben (ox_lib optional).
2. In `resources.txt` aktivieren:

   ```
   git [vendor]/[esx] https://github.com/esx-framework/esx_core.git main
   ```

   Installer laufen lassen. Ergebnis: `server-data/resources/[vendor]/[esx]/[core]/...`.
3. SQL importieren: `[vendor]/[esx]/[SQL]/legacy.sql` (Befehle oben).
4. In `server.cfg` einkommentieren bzw. ergänzen (Reihenfolge wichtig):

   ```
   ensure oxmysql
   ensure esx_lib
   ensure es_extended
   ensure [core]
   ```

   Zusätzlich die ACE-Zeilen aus der ESX-Vorlage in den Abschnitt "Admin-Rechte":

   ```
   add_ace resource.es_extended command.add_ace allow
   add_ace resource.es_extended command.add_principal allow
   add_ace resource.es_extended command.remove_principal allow
   add_ace resource.es_extended command.stop allow
   ```

   Optional: `setr esx:locale "de"` (sofern `[core]/es_extended/locales/de.lua` existiert),
   `set mysql_ui true` für den `/mysql`-Befehl (braucht `command`-ACE).
5. Server starten und in der Konsole prüfen, dass `es_extended` ohne SQL-Fehler hochkommt.

Das offizielle Rezept (`https://raw.githubusercontent.com/esx-framework/ESX-recipes/legacy/recipe.yaml`)
holt zusätzlich `ESX-Legacy-Addons` (`[esx_addons]`), `bob74_ipl`, `pma-voice`, `ox_lib` und das
`sd-phone`. Wenn du das alles willst, nimm Weg B.

## QBCore

Die Organisation ist nach `github.com/qbcore-fivem` umgezogen (alte `qbcore-framework`-URLs leiten um).
Es gibt keine offizielle Minimal-Liste; das Rezept installiert rund 60 `qb-*`-Ressourcen. Der Block in
`resources.txt` ist ein Startsatz aus zwölf Repos (qb-core, qb-multicharacter, qb-spawn, qb-apartments,
qb-clothing, qb-weathersync, qb-smallresources, qb-inventory, qb-target, qb-menu, qb-input, qb-hud).
Ob dieser Satz ohne Anpassung spielbar ist, wurde nicht verifiziert; fehlende Abhängigkeiten stehen dann in
der Serverkonsole und lassen sich nach demselben Muster ergänzen.

1. MariaDB, Verbindungs-String, oxmysql wie oben (qb-core braucht kein ox_lib).
2. In `resources.txt` den QBCore-Block aktivieren, Installer laufen lassen. Ergebnis
   `server-data/resources/[vendor]/[qb]/qb-*`.
3. SQL importieren: `[vendor]/[qb]/qb-core/qbcore.sql`.
4. In `server.cfg`:

   ```
   ensure oxmysql
   ensure qb-core
   ensure [qb]

   setr qb_locale "de"
   setr UseTarget false          # true, wenn qb-target genutzt werden soll

   add_ace resource.qb-core command allow
   add_ace qbcore.god command allow
   add_principal qbcore.god group.admin
   add_principal qbcore.god qbcore.admin
   add_principal qbcore.admin qbcore.mod
   ```

   Das Rezept ensured außerdem `baseevents` (liegt in `[cfx-default]/[system]`) und `pma-voice` (`[voice]`).
5. Server starten, per `/setjob` oder txAdmin-Menü testen. Rezept-URL für Weg B:
   `https://raw.githubusercontent.com/qbcore-framework/txAdminRecipe/main/qbcore.yaml`.

## Qbox

Qbox baut vollständig auf ox_lib, oxmysql und den ox-Ressourcen auf. `qbx_core` verlangt FXServer >= 10731,
OneSync, `ox_lib` und `oxmysql` (alles hier erfüllt) sowie MariaDB >= 10.9 (Qbox empfiehlt 12.3 LTS,
Ubuntu 24.04 liefert 10.11, `mariadb:11` in Docker passt). XAMPP wird von Qbox ausdrücklich nicht unterstützt.

Der Block in `resources.txt` installiert nur `ox_target`, `ox_inventory` und `qbx_core`. Ein spielbarer
Qbox-Server besteht laut Rezept aus rund 50 `qbx_*`-Ressourcen, `ox_doorlock`, `ox_fuel`, `npwd` und mehreren
SQL-Dateien. Für Qbox ist deshalb **Weg B** (Rezept in frischen Ordner, dann kopieren) klar zu empfehlen.

Weg A, nur der Kern:

1. MariaDB, Verbindungs-String, **oxmysql und ox_lib** wie oben.
2. In `resources.txt` aktivieren:

   ```
   zip [vendor]/ox_target https://github.com/overextended/ox_target/releases/latest/download/ox_target.zip
   zip [vendor]/ox_inventory https://github.com/overextended/ox_inventory/releases/latest/download/ox_inventory.zip
   git [vendor]/[qbx]/qbx_core https://github.com/Qbox-project/qbx_core.git main
   ```

3. SQL importieren: `[vendor]/[qbx]/qbx_core/qbx_core.sql` (weitere Ressourcen bringen eigene SQL-Dateien mit,
   z. B. `qbx_vehicles/vehicles.sql`).
4. In `server.cfg` (Reihenfolge aus dem Rezept):

   ```
   ensure oxmysql
   ensure ox_lib
   ensure qbx_core
   ensure ox_target
   ensure ox_inventory
   ensure [qbx]

   setr qb_locale "de"
   setr ox:locale "de"
   setr inventory:framework "qbx"
   setr qbx:enableBridge "true"
   set qbx:enableQueue "true"
   set qbx:max_jobs_per_player 1
   ```

   Das Rezept stoppt außerdem `basic-gamemode` (`stop basic-gamemode` statt `ensure`), damit Spieler nicht
   ohne Charakterauswahl spawnen. Rezept-URL: `https://raw.githubusercontent.com/Qbox-project/txAdminRecipe/refs/heads/main/qbox.yaml`.
5. Server starten, Konsole auf fehlende Abhängigkeiten prüfen.

## Prüfen und Fehlersuche

- `oxmysql` meldet beim Start `Database server connection established`. Fehlt das: Verbindungs-String,
  Passwort-Sonderzeichen, läuft MariaDB (`systemctl status mariadb`, Windows: Dienst `MariaDB`)?
- `Couldn't find resource ...`: Ressource nicht installiert, falsche Reihenfolge der `ensure`-Zeilen oder
  Ordnername weicht vom Ressourcennamen ab. Betrifft es `mapmanager`, `spawnmanager` oder `basic-gamemode`,
  fehlt `[cfx-default]`: unter Windows `install.bat` ohne `-SkipResources` ausführen (bei einem kaputten Ordner
  `install.bat -ForceResources`), unter Linux `scripts/linux/install-resources.sh` (bei einem kaputten Ordner
  mit `--force`). Sonst `refresh` in der Konsole, dann `ensure <name>`.
- `Table 'fivem.users' doesn't exist`: SQL nicht oder in die falsche Datenbank importiert.
- ox_lib startet nicht: OneSync aus. Im txAdmin-Modus Settings > FXServer > OneSync "on". Im Direktmodus
  `start-direct.bat` nutzen bzw. `+set onesync on` vor `+exec server.cfg` mitgeben; kein `set onesync on` in
  `server.cfg` oder `secrets.cfg` eintragen, txAdmin würde die Zeile beim nächsten Start auskommentieren.
- Alte `mysql-async`/`ghmattimysql`-Skripte funktionieren mit oxmysql weiter (`provide`-Einträge).
- Sprachdateien: ESX, QBCore und Qbox bringen `de`-Locales mit; fehlt eine Übersetzung in einer Zusatzressource,
  fällt sie auf Englisch zurück.
