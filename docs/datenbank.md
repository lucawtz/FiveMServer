# Datenbank: MariaDB für Qbox

Qbox speichert Spieler, Charaktere, Fahrzeuge, Inventare, Konten und vieles mehr in MariaDB. Ohne Datenbank
startet `oxmysql` nicht und Qbox funktioniert nicht. Dieses Repo richtet die Datenbank mit
`setup-database` ein (Windows: `scripts\windows\setup-database.bat`, Linux und Docker:
`scripts/linux/setup-database.sh`) und importiert die SQL-Dateien aus `server-data/database.txt`.
Eine Tabelle in der Datenbank merkt sich, welche Datei schon importiert wurde.

| Weg     | MariaDB installieren                          | Datenbank und User anlegen                                | SQL-Dateien importieren                                  |
|---------|-----------------------------------------------|-----------------------------------------------------------|----------------------------------------------------------|
| Windows | `setup-database.bat -InstallMariaDB` (winget) | `setup-database.bat -Create -Import`                      | `setup-database.bat` oder `install.bat`                  |
| Linux   | `install.sh` (Standard)                       | `install.sh` bzw. `sudo bash scripts/linux/setup-database.sh --create` | `sudo -u fivem bash scripts/linux/setup-database.sh`, `deploy.sh` |
| Docker  | Image `mariadb:12.3`                          | der `db`-Container aus den Werten der `.env`              | `bash scripts/linux/setup-database.sh --docker`          |

## Welche Version

- **Mindestens MariaDB 10.9**, empfohlen **12.3 LTS** (Support bis Juni 2029). Qbox nutzt Funktionen, die es
  erst ab 10.9 gibt. MySQL wird von Qbox nicht unterstützt, XAMPP auch nicht.
- Beide Skripte fragen vor jeder Arbeit `SELECT VERSION();` ab. Meldet der Server kein MariaDB oder eine
  Version unter 10.9, brechen sie mit Exit-Code 2 ab:
  `MariaDB <version> ist zu alt. Qbox braucht mindestens 10.9 (empfohlen: 12.3 LTS). Anleitung: docs/datenbank.md`.
- **Ubuntu 24.04** liefert MariaDB 10.11, das reicht (Debian 12 ebenfalls 10.11).
- **Ubuntu 22.04** liefert 10.6, das ist zu alt. `install.sh` installiert dann kein Fremd-Repository von sich aus,
  sondern meldet den Fehler, gibt die Befehle unten aus und endet mit Exit-Code 1. MariaDB aus dem offiziellen
  Repository installieren:

  ```bash
  sudo mariadb-dump --all-databases > /root/mariadb-vor-upgrade.sql     # Backup, falls schon Daten da sind
  curl -LsSO https://r.mariadb.com/downloads/mariadb_repo_setup
  echo "<pruefsumme> mariadb_repo_setup" | sha256sum -c -
  sudo bash mariadb_repo_setup --mariadb-server-version="mariadb-12.3"
  sudo apt-get update && sudo apt-get install -y mariadb-server mariadb-client
  sudo bash scripts/linux/install.sh --enable-firewall                    # danach erneut ausführen
  ```

  Die aktuelle Prüfsumme steht auf
  <https://mariadb.com/docs/server/server-management/install-and-upgrade-mariadb/mariadb-package-repository-setup-and-usage>
  im Abschnitt "mariadb_repo_setup Versions". Alternative Anleitung: <https://mariadb.org/download/?t=repo-config>.
- **Docker** nutzt das Image `mariadb:12.3`, siehe [docker.md](docker.md).
- **Windows** installiert das winget-Paket `MariaDB.Server` (aktuelle Version des Pakets).

## Windows

### 1. MariaDB installieren

Eingabeaufforderung im Repo-Ordner öffnen und ausführen:

```
scripts\windows\setup-database.bat -InstallMariaDB
```

Das Skript braucht `winget` (fehlt es: "App Installer" aus dem Microsoft Store installieren oder aktualisieren).
Ist schon ein `mariadb.exe` zu finden, meldet es `MariaDB ist bereits installiert (...), die Installation wird
übersprungen.` Sonst startet es

```
winget install --id MariaDB.Server -e --source winget --interactive --accept-package-agreements --accept-source-agreements
```

und damit den normalen Installationsassistenten. So ausfüllen:

- ein **Root-Passwort** setzen und merken, `-Create` fragt es gleich danach ab,
- "Install as service" eingeschaltet lassen, Dienstname `MariaDB`,
- Port 3306 lassen,
- Zugriff für root von anderen Rechnern (remote root access) **aus** lassen,
- eine UTF8-Option nur anhaken, wenn der Assistent sie anbietet (die Datenbank bekommt ohnehin utf8mb4).

Das Passwort geht nie über die Kommandozeile, deshalb läuft die Installation bewusst interaktiv.

Der Windows-Dienst lauscht danach auf allen Netzwerkschnittstellen (in `my.ini` steht nur der Port). Anmelden
kann sich von außen trotzdem niemand: `-Create` legt nur `fivem@localhost` und `fivem@127.0.0.1` an, und
Remote-root bleibt aus. Soll der Port im LAN gar nicht erreichbar sein, in `my.ini` (im Datenordner, z. B.
`C:\Program Files\MariaDB 12.3\data\my.ini`) unter `[mysqld]` die Zeile `bind-address=127.0.0.1` ergänzen und
den Dienst neu starten (`net stop MariaDB` und `net start MariaDB` als Administrator).

`mariadb.exe` sucht das Skript in dieser Reihenfolge: `-MariaDbBin` (Ordner oder Datei), `mariadb.exe` im PATH,
dann die Ordner `MariaDB *` unter `%ProgramW6432%` und `%ProgramFiles%` (die neueste Version gewinnt).
`mysql.exe` wird nie verwendet. Findet es nach der Installation nichts: neues Terminal öffnen oder
`-MariaDbBin "C:\Program Files\MariaDB 12.3\bin"` angeben.

### 2. Datenbank anlegen und SQL importieren

Erst die Ressourcen installieren (`install.bat`), denn die SQL-Dateien kommen aus `[vendor]`. Dann in einem
**offenen Konsolenfenster** (nicht per Pipe, das Passwort wird interaktiv abgefragt):

```
scripts\windows\setup-database.bat -Create -Import
```

`-Create` macht Folgendes:

1. `server-data\secrets.cfg` aus der Vorlage anlegen, falls sie fehlt. Einen vorhandenen
   `mysql_connection_string` prüft es vorab: zeigt er auf einen anderen Rechner, bricht es ab
   (`secrets.cfg zeigt auf einen anderen Datenbankserver (...)`), ebenso bei anderem User oder Datenbanknamen
   ohne `-ResetPassword`. Ohne `-Port` übernimmt es den Port des vorhandenen Strings. Weicht ein angegebenes
   `-Port` davon ab, bricht es ohne `-ResetPassword` mit Exit 1 ab, weil der behaltene String seinen alten Port
   behielte: `secrets.cfg nutzt Port 3306, -Port ist 3307. Entweder -Port 3306 angeben oder mit -ResetPassword
   einen neuen String schreiben.` Strings mit `socketPath` prüft es dabei nicht.
2. `MariaDB-Root-Passwort` einmal abfragen und sich als root über TCP `127.0.0.1:<Port>` anmelden. Läuft der
   Windows-Dienst nicht, warnt es: `net start MariaDB (als Administrator)`.
3. `CREATE DATABASE IF NOT EXISTS fivem CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci`.
4. Die User `fivem@localhost` und `fivem@127.0.0.1` mit demselben Passwort anlegen und ihnen alle Rechte auf die
   Datenbank geben. Ein neues Passwort sind 32 Hex-Zeichen. Gibt es den User schon, testet es das Passwort aus
   `secrets.cfg`; ein unbekanntes Passwort ändert es nur mit `-ResetPassword`.
5. Bei neuem Passwort in `secrets.cfg` schreiben:
   `set mysql_connection_string "mysql://fivem:<passwort>@127.0.0.1:3306/fivem?charset=utf8mb4"`.
6. Die Anmeldung als `fivem` so prüfen, wie oxmysql sich verbindet: über `127.0.0.1:<Port>`, bei einem
   behaltenen String mit `socketPath` über diese Named Pipe (`Anmeldung als fivem über Socket ... funktioniert.`).
   Ein neues Passwort zeigt es einmal gelb an
   (`MariaDB-Passwort für fivem (steht in secrets.cfg, wird nicht erneut angezeigt): ...`). Ist die Ausgabe
   umgeleitet (z. B. in eine Logdatei), steht dort stattdessen
   `Neues MariaDB-Passwort für fivem steht in ...\secrets.cfg (Ausgabe ist umgeleitet, daher nicht angezeigt).`

`-Import` importiert danach die ausstehenden SQL-Dateien (siehe [So funktioniert der Import](#so-funktioniert-der-import)).

Alternativ in einem Rutsch: `scripts\windows\install.bat -SetupDatabase` ruft in Schritt 4 `setup-database.ps1 -Create -Import` auf.

### 3. Später

- `setup-database.bat` ohne Parameter (auch per Doppelklick) importiert nur ausstehende Dateien.
- `install.bat` importiert in Schritt 4 automatisch (`setup-database.ps1 -Import`), sobald in `secrets.cfg` ein
  aktives `set mysql_connection_string` steht.
- `start.bat` und `start-direct.bat` warnen, wenn der String fehlt.

### Parameter von setup-database.ps1

`setup-database.bat` reicht alle Parameter an `setup-database.ps1` durch, meldet am Ende das Ergebnis und wartet
auf eine Taste. Hilfe: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows\setup-database.ps1 -?`

| Parameter                | Bedeutung                                                                                               |
|--------------------------|---------------------------------------------------------------------------------------------------------|
| `-InstallMariaDB`        | MariaDB Server per winget installieren (interaktiver Assistent), wenn noch kein `mariadb.exe` gefunden wird. |
| `-Create`                | Datenbank und User anlegen, `mysql_connection_string` schreiben. Fragt das Root-Passwort ab.            |
| `-ResetPassword`         | Nur mit `-Create`: vorhandenem User ein neues Passwort geben und den String neu schreiben.              |
| `-DbName <name>`         | Nur mit `-Create`. Standard `fivem`. Erlaubt: `A-Z a-z 0-9 _`, 1 bis 32 Zeichen.                        |
| `-DbUser <name>`         | Nur mit `-Create`. Standard `fivem`, gleiche Regeln.                                                    |
| `-Port <n>`              | Nur mit `-Create`. Standard 3306 bzw. der Port des vorhandenen Strings. Weicht ein angegebener Wert vom Port eines behaltenen TCP-Strings ab, Abbruch mit Exit 1 (außer mit `-ResetPassword`). |
| `-Import`                | Ausstehende SQL-Dateien importieren. Standard, wenn weder `-Create`, `-InstallMariaDB`, `-MarkApplied` noch `-Check` angegeben ist. |
| `-MarkApplied`           | Ausstehende oder geänderte Dateien als importiert eintragen, ohne sie auszuführen.                     |
| `-Only <pfad>[,<pfad>]`  | Import, MarkApplied und DryRun auf diese Pfade aus `database.txt` beschränken (mehrere mit `,` oder `;`). |
| `-DryRun`                | Nur anzeigen, nichts ändern.                                                                            |
| `-Check`                 | Nur `database.txt` prüfen, keine Datenbank. Nur zusammen mit `-ManifestPath`.                           |
| `-MariaDbBin <pfad>`     | Ordner mit `mariadb.exe` oder Pfad zu `mariadb.exe`.                                                    |
| `-ManifestPath <datei>`  | Anderes SQL-Manifest. Standard `<repo>\server-data\database.txt`.                                       |
| `-SecretsPath <datei>`   | Andere `secrets.cfg`. Standard `<repo>\server-data\secrets.cfg`.                                        |

Reihenfolge bei Kombination: `-InstallMariaDB`, `-Create`, dann Import bzw. `-MarkApplied`. Unzulässige
Kombinationen brechen mit Exit 1 ab: `-Create` mit `-MarkApplied` oder `-DryRun`, `-Import` mit `-MarkApplied`,
`-ResetPassword`/`-DbName`/`-DbUser`/`-Port` ohne `-Create`, `-Only` ohne Import- oder Mark-Aktion.

## Linux (systemd)

`install.sh` erledigt alles ohne Zusatzoption (siehe [linux-server.md](linux-server.md)):

- Schritt 5/9 installiert `mariadb-server mariadb-client` (falls nötig), startet den Dienst und prüft die Version.
- Schritt 6/9 ruft als root `setup-database.sh --create` und danach als Service-User `setup-database.sh --import` auf.
- Mit `--no-mariadb` (Datenbank auf einem anderen Server) installiert es nur `mariadb-client`, falls weder
  `mariadb` noch `mysql` vorhanden ist. Den String trägst du dann selbst in `secrets.cfg` ein und importierst mit
  `sudo -u fivem bash scripts/linux/setup-database.sh --import`.

Von Hand:

```bash
sudo bash scripts/linux/setup-database.sh --create        # DB + User anlegen, String schreiben (als root)
sudo -u fivem bash scripts/linux/setup-database.sh         # ausstehende SQL-Dateien importieren (= --import)
sudo -u fivem bash scripts/linux/setup-database.sh --dry-run
```

`--create` meldet sich als root über den unix_socket an (kein Root-Passwort nötig) und arbeitet nach demselben
Ablauf wie unter Windows: Datenbank anlegen, `fivem@localhost` und `fivem@127.0.0.1` mit demselben Passwort,
String mit `127.0.0.1:3306` schreiben (`secrets.cfg` bleibt 0600 und behält den Besitzer), Anmeldung prüfen
(`Anmeldung als 'fivem' ueber TCP 127.0.0.1:3306 funktioniert.`, bei einem behaltenen String mit `socketPath`
`ueber Socket <pfad>`), neues Passwort einmal auf stderr ausgeben. Das Passwort erscheint nur, wenn stderr ein
Terminal ist. Bei umgeleiteter Ausgabe (`install.sh 2>&1 | tee install.log`, Logdatei, CI) steht dort nur
`Neues MariaDB-Passwort fuer fivem steht in <pfad> (keine Terminal-Ausgabe, daher nicht angezeigt).` Ein
vorhandener, funktionierender String bleibt unverändert, auch wenn er noch `localhost` enthält (so hat ihn das
alte `install.sh --with-mariadb` geschrieben). Der Test des vorhandenen Passworts läuft über den unix_socket.
Ohne `--db-port` übernimmt `--create` den Port des vorhandenen Strings. Ein abweichendes `--db-port` bricht ohne
`--reset-password` mit Exit 1 ab, bevor etwas angelegt wird
(`secrets.cfg nutzt Port 3306, --db-port ist 3307. Entweder --db-port 3306 angeben oder mit --reset-password einen neuen String schreiben.`);
Strings mit `socketPath` sind ausgenommen.

`deploy.sh` importiert nach dem Ressourcen-Update automatisch neue SQL-Dateien, sobald `secrets.cfg` einen aktiven
String enthält. Schlägt der Import fehl, startet es den Dienst **nicht** neu. `--no-sql` überspringt den Schritt.

### Optionen von setup-database.sh

Werte gehen als `--db fivem` oder `--db=fivem`. Ohne Aktion wird `--import` ausgeführt, `--dry-run` allein ist ein
Trockenlauf des Imports.

| Option               | Bedeutung                                                                                 |
|----------------------|-------------------------------------------------------------------------------------------|
| `--create`           | DB und User anlegen (root, unix_socket), `mysql_connection_string` schreiben. Braucht root. |
| `--reset-password`   | Nur mit `--create`: vorhandenem User ein neues Passwort geben.                            |
| `--db <name>`        | Standard `fivem` (nur `--create`).                                                        |
| `--db-user <name>`   | Standard `fivem` (nur `--create`).                                                        |
| `--db-port <n>`      | Standard 3306, sonst der Port aus dem vorhandenen `mysql_connection_string` (nur `--create`). Weicht ein angegebener Wert vom Port eines behaltenen TCP-Strings ab, Abbruch mit Exit 1 (außer mit `--reset-password`). |
| `--import`           | Ausstehende SQL-Dateien importieren (Standard ohne andere Aktion).                       |
| `--mark-applied`     | Ausstehende oder geänderte Dateien als importiert eintragen, ohne Ausführung.            |
| `--only <pfad>`      | Wiederholbar, beschränkt Import, `--mark-applied` und `--dry-run`.                        |
| `--dry-run`          | Nur anzeigen.                                                                             |
| `--check`            | Nur `database.txt` prüfen, keine Datenbank. Nur mit `--manifest` kombinierbar.            |
| `--docker`           | Client im `db`-Container (`docker compose ... exec -T db`).                               |
| `--manifest <datei>` | Anderes SQL-Manifest (Standard `server-data/database.txt`).                              |
| `--secrets <datei>`  | Andere `secrets.cfg` (Standard `server-data/secrets.cfg`).                               |

Reihenfolge bei Kombination: `--create`, dann `--import`. Unzulässig (Exit 1): `--create` mit `--docker`,
`--mark-applied` oder `--dry-run`; `--import` mit `--mark-applied`; `--reset-password`, `--db`, `--db-user`,
`--db-port` ohne `--create`; `--only` mit `--create` allein; `--secrets` mit `--docker`; `--create` ohne root
(`--create als root ausfuehren (sudo)`). Pfade für `--only` wegen der eckigen Klammern immer in einfache
Anführungszeichen setzen.

## Docker

Der `db`-Container legt Datenbank und User beim ersten Start selbst aus `MYSQL_DATABASE`, `MYSQL_USER` und
`MYSQL_PASSWORD` der `.env` an. `--create` gibt es deshalb nicht. Reihenfolge:

```bash
docker compose --env-file .env -f docker/docker-compose.yml up -d --wait db
bash scripts/linux/setup-database.sh --docker
```

`--docker` prüft `docker compose version` und `.env` (sonst Exit 1), dann ob der Service `db` läuft (sonst Exit 2
mit dem `up -d --wait db`-Befehl) und wartet bis zu 120 s, bis `healthcheck.sh --connect --innodb_initialized`
im Container klappt (`Warte, bis der db-Container bereit ist (bis 120 s) ...`). Grund: beim allerersten Start und
bei einem Versions-Upgrade antwortet vorübergehend ein Hilfsserver, der den User noch nicht kennt. Die Compose-Datei
gibt dem Healthcheck deshalb `start_period: 120s`, sonst bräche schon `up -d --wait db` nach etwa 40 s ab. Der Client läuft
im Container mit `MARIADB_USER`/`MARIADB_PASSWORD` aus dessen Umgebung, das Passwort taucht auf dem Host nie in
einer Kommandozeile auf. `--dry-run`, `--mark-applied` und `--only` funktionieren auch mit `--docker`.

## So funktioniert der Import

### database.txt

Eine SQL-Datei pro Zeile, relativ zu `server-data/resources/`, immer mit `/`:

```
# Kommentarzeilen und Leerzeilen werden ignoriert
[vendor]/.sources/qbox-recipe/qbox.sql
[vendor]/[qbx]/qbx_core/qbx_core.sql rerun
```

- Erlaubt im Pfad: `A-Z a-z 0-9 . _ - [ ] /`, keine Leerzeichen, Endung `.sql`, relativ, keine leeren, `.`- oder
  `..`-Segmente. Kein Kommentar am Zeilenende, jeder Pfad nur einmal.
- Optional ein zweites Wort `rerun` für Dateien, die gefahrlos mehrfach laufen können (nur
  `CREATE TABLE IF NOT EXISTS`, `ADD COLUMN IF NOT EXISTS` usw.). Ändert sich so eine Datei, zum Beispiel nach
  einem Qbox-Update mit neuer Spalte, wird sie automatisch erneut ausgeführt.
- Die Reihenfolge ist die Import-Reihenfolge (wie im Qbox-Rezept). Neue Zeilen nur **anhängen**. Ein
  geänderter Pfad gilt als neue Datei und würde erneut importiert.
- Prüfen ohne Datenbank: `bash scripts/linux/setup-database.sh --check` bzw. `setup-database.bat -Check`
  (Exit 0 gültig, 1 ungültig). Die CI prüft das bei jedem Push.

Aktuell stehen 9 Dateien darin: `qbox.sql` aus dem Rezept-Repository (Kleidung, Türschlösser, Banking, Mails;
nicht wiederholbar), die SQL-Dateien von `qbx_core`, `qbx_vehicles`, `qbx_vehiclesales`, `qbx_vehicleshop`,
`qbx_weed`, `qbx_lapraces`, `qbx_drugs` (alle `rerun`) und `import.sql` von npwd (nicht wiederholbar).

### Die Tabelle repo_sql_imports

Beim ersten Import legt das Skript in der Datenbank die Tabelle `repo_sql_imports` an: `file_path` (Pfad genau wie
in `database.txt`), `sha256` der Datei, `imported_at` und `applied_by` (`import` oder `mark-applied`). Pro Datei
ergibt sich einer dieser Zustände:

| Zustand       | Bedeutung                               | Was passiert                                                                 |
|---------------|-----------------------------------------|------------------------------------------------------------------------------|
| `importiert`  | eingetragen, Datei unverändert          | nichts                                                                       |
| `ausstehend`  | noch nicht eingetragen                  | wird importiert und danach eingetragen                                       |
| `erneut`      | eingetragen, Datei geändert, `rerun`    | wird erneut ausgeführt, der neue Hash wird eingetragen                       |
| `geaendert`   | eingetragen, Datei geändert, ohne `rerun` | **nur eine Warnung**, keine Ausführung (Windows zeigt `geändert`)          |
| `fehlt`       | Datei nicht vorhanden                   | schon eingetragen: nur Info. Noch nicht eingetragen: Abbruch mit Exit 3 (`<pfad> fehlt. Ist die Ressource installiert (install-resources)?`) |
| `unbekannt`   | nur im Trockenlauf ohne Verbindung      | nichts                                                                       |

Zum Schluss steht eine Zeile wie
`SQL: 9 importiert, 0 erneut ausgefuehrt, 0 bereits vorhanden, 0 geaendert (Warnung), 0 markiert`.

Die Zugangsdaten stehen nur in einer temporären Optionsdatei (`--defaults-file`, Linux 0600 in einem
0700-Temp-Ordner, Windows in `%TEMP%\fivem-db-*` mit eingeschränkten Rechten), die direkt danach gelöscht wird.
Die SQL-Datei geht per stdin an den Client, ein Passwort steht nie auf der Kommandozeile.

### Wenn ein Import fehlschlägt

Der Import stoppt bei der ersten fehlerhaften Datei (Exit 3):

```
FEHLER beim Import von <pfad> (Exit-Code N): <Meldung von MariaDB>
Achtung: MariaDB fuehrt CREATE/ALTER TABLE ohne Transaktion aus. ...
```

MariaDB kann `CREATE TABLE`/`ALTER TABLE` nicht zurückrollen. Befehle vor dem Fehler sind also schon angewendet,
die Datei ist aber **nicht** eingetragen, und alle folgenden Dateien wurden nicht importiert. Ursache beheben
(häufig: Ressource fehlt oder ist unvollständig, falsche Datenbank) und erneut starten. Hast du die restlichen
Befehle von Hand eingespielt, die Datei danach als erledigt eintragen:

```bash
sudo -u fivem bash scripts/linux/setup-database.sh --mark-applied --only '<pfad>'
```
```
scripts\windows\setup-database.bat -MarkApplied -Only <pfad>
```

### Geänderte Datei ohne rerun

Nach einem Update der Ressourcen kann sich eine nicht wiederholbare Datei ändern. Dann erscheint:

```
<pfad> wurde am <zeitpunkt> importiert, die Datei hat sich seitdem geaendert (alt 1a2b3c4d, neu 5e6f7a8b).
Sie wird NICHT erneut ausgefuehrt. ...
```

Der Exit-Code bleibt 0. Prüfe die Änderung (bei git-Zielen z. B.
`git -C "server-data/resources/[vendor]/[npwd]/..." log -p -- <datei>`), spiel nötige Befehle von Hand ein
(HeidiSQL oder `mariadb`-Konsole) und quittiere die Warnung mit `--mark-applied --only '<pfad>'` bzw.
`-MarkApplied -Only <pfad>`.

### Trockenlauf

`--dry-run` bzw. `-DryRun` ändert nichts, legt auch die Tabelle nicht an und zeigt pro Datei den Zustand:

```
==> SQL-Import aus database.txt
[INFO]  Trockenlauf (--dry-run): es wird nichts geaendert.
[INFO]  MariaDB 12.3.3-MariaDB
  ausstehend  [vendor]/.sources/qbox-recipe/qbox.sql
  ausstehend  [vendor]/[qbx]/qbx_core/qbx_core.sql
  ...
  ausstehend  [vendor]/[npwd]/npwd/import.sql
[INFO]  Trockenlauf, nichts geaendert. Geplant: SQL: 9 importiert, 0 erneut ausgefuehrt, 0 bereits vorhanden, 0 geaendert (Warnung), 0 markiert
```

Windows zeigt dieselbe Liste unter `==> Probelauf (nichts wird geändert)` und am Ende dieselbe Zeile mit Umlauten:
`Probelauf, nichts geändert. Geplant: SQL: 9 importiert, 0 erneut ausgeführt, 0 bereits vorhanden, 0 geändert (Warnung), 0 markiert`.
Mit `--mark-applied` bzw. `-MarkApplied` zählen ausstehende und geänderte Dateien unter `markiert`. Fehlende Dateien
stehen als `fehlt` mit dem Zusatz `(bereits importiert, Datei fehlt)` oder `(nicht importiert, Ressource installieren)`.

Fehlt eine noch nicht importierte Datei, zeigt der Trockenlauf trotzdem alle Dateien und die Zusammenfassung und
endet dann wie ein echter Lauf mit Exit 3 (`... Ein echter Lauf wuerde mit Exit-Code 3 abbrechen ...`), unter Linux
und Windows gleich.

Ist die Datenbank nicht erreichbar oder schlägt die Anmeldung fehl, erscheint `Datenbank nicht erreichbar, Status
unbekannt`, und die Dateien stehen als `unbekannt` bzw. `fehlt` da (Exit 2). Ist die MariaDB zu alt oder läuft dort
ein anderer Server, erscheint nur dessen Fehlermeldung mit derselben Liste (ebenfalls Exit 2). Fehlt der String in
`secrets.cfg` oder ist er ungültig, gibt es die Warnung auch, dann mit Exit 1.

### Exit-Codes

Gleich für `setup-database.sh` und `setup-database.ps1`:

| Code | Bedeutung                                                                                                  |
|------|------------------------------------------------------------------------------------------------------------|
| 0    | OK, auch wenn Warnungen zu geänderten Dateien ausgegeben wurden.                                          |
| 1    | Abbruch vor oder ohne DB-Arbeit: Optionen, `database.txt`, `secrets.cfg`, Client fehlt, winget, Namen, Voraussetzungen von `--create`. |
| 2    | Datenbank nicht erreichbar, Anmeldung fehlgeschlagen, kein MariaDB oder zu alt, db-Container nicht (rechtzeitig) bereit. Auch im Trockenlauf. |
| 3    | SQL-Fehler: Import oder Eintrag fehlgeschlagen, ausstehende Datei fehlt, CREATE/GRANT fehlgeschlagen.      |

Aufrufer: `setup-database.bat` meldet `[OK] Datenbank-Schritt abgeschlossen.`, bei 2
`[FEHLER] Datenbank nicht erreichbar, Anmeldung fehlgeschlagen oder MariaDB zu alt. ...`, bei 3
`[FEHLER] SQL-Import fehlgeschlagen. ...`. `install.bat` macht aus jedem Fehler des Datenbank-Schritts Exit 2,
`install.sh` Exit 1 (die übrigen Schritte laufen trotzdem), `deploy.sh` bricht vor dem Neustart ab.

## Datenbank schon per txAdmin-Rezept eingerichtet

Hast du Qbox früher über das txAdmin-Rezept aufgesetzt, sind die Tabellen schon da, aber `repo_sql_imports` fehlt.
Ein normaler Import würde `qbox.sql` und npwds `import.sql` ein zweites Mal ausführen, und die sind nicht
wiederholbar. So gehst du vor:

1. In `secrets.cfg` den `mysql_connection_string` auf diese Datenbank setzen.
2. Nur die beiden nicht wiederholbaren Dateien als erledigt eintragen:

   ```bash
   sudo -u fivem bash scripts/linux/setup-database.sh --mark-applied --only '[vendor]/.sources/qbox-recipe/qbox.sql' --only '[vendor]/[npwd]/npwd/import.sql'
   ```
   ```
   scripts\windows\setup-database.bat -MarkApplied -Only [vendor]/.sources/qbox-recipe/qbox.sql,[vendor]/[npwd]/npwd/import.sql
   ```

3. Danach normal importieren. Die `rerun`-Dateien laufen gefahrlos ein weiteres Mal und ergänzen dabei neue Spalten.

`--mark-applied` bzw. `-MarkApplied` **ohne** `--only` trägt **alle** ausstehenden Dateien ein, ohne sie
auszuführen (vorher zeigt es die Liste). Das nur auf einer Datenbank tun, die wirklich vollständig ist, sonst
fehlen später Tabellen oder Spalten, und das Skript merkt es nicht mehr.

## Eigene SQL-Dateien

Eigene Ressourcen mit Datenbank-Tabellen bekommen eine Zeile **am Ende** von `server-data/database.txt`, zum Beispiel:

```
# Eigene Ressource mein-script
[local]/mein-script/sql/mein-script.sql rerun
```

`rerun` nur, wenn die Datei wirklich mehrfach laufen darf, also z. B. nur
`CREATE TABLE IF NOT EXISTS ...` und `ALTER TABLE ... ADD COLUMN IF NOT EXISTS ...` enthält und keine festen
`INSERT`s. Ohne `rerun` läuft die Datei genau einmal; Änderungen daran spielst du von Hand ein und quittierst
sie mit `--mark-applied --only`. Die Ressource selbst braucht `dependency 'oxmysql'` in der `fxmanifest.lua`.

## Passwort neu setzen

```bash
sudo bash scripts/linux/setup-database.sh --create --reset-password
```
```
scripts\windows\setup-database.bat -Create -ResetPassword
```

Beide geben dem User ein neues 32-Hex-Passwort (für `@localhost` und `@127.0.0.1`), schreiben den String neu und
zeigen das Passwort einmal an, aber nur, wenn die Ausgabe ein Terminal ist (Linux: stderr). Sonst steht dort nur
ein Hinweis, dass es in `secrets.cfg` steht. Danach den Server neu starten, oxmysql liest den String nur beim Start. Nötig bei
`User existiert, Passwort unbekannt` und `Passwort in secrets.cfg passt nicht zum vorhandenen User`.

Docker: `MYSQL_PASSWORD` in der `.env` wirkt nur beim allerersten Start des Volumes. Später das Passwort im
Container ändern (`ALTER USER`), dann `.env` und `server-data/secrets.cfg` anpassen.

## Regeln für den mysql_connection_string

Die Skripte lesen den String genau so wie oxmysql 2.14.1, damit sie mit denselben Zugangsdaten arbeiten wie der
laufende Server:

- Gelesen wird nur `server-data/secrets.cfg` (oder `--secrets`/`-SecretsPath`). Zeilen, die mit `#` oder `//`
  beginnen, zählen nicht. Die **letzte** aktive Zeile `set mysql_connection_string ...` gewinnt.
- **Nur `set`.** `setr` und `sets` funktionieren in FXServer zwar auch, schicken das DB-Passwort aber an alle
  Spieler (`setr`) bzw. in die öffentliche Serverinfo (`sets`). Die Skripte werten solche Zeilen nicht aus und
  warnen.
- Zwei Schreibweisen:
  `mysql://fivem:PASSWORT@127.0.0.1:3306/fivem?charset=utf8mb4` oder
  `user=fivem;password=PASSWORT;host=127.0.0.1;port=3306;database=fivem`. Beide immer in Anführungszeichen:
  außerhalb davon trennt FXServer am `;` Befehle, auch in `#`-Kommentaren.
- **Passwort nur aus `A-Z a-z 0-9`.** oxmysql dekodiert keine `%XX`-Sequenzen (die Skripte warnen, das Passwort
  gilt wörtlich), und Zeichen wie `; , / ? : @ & = + $ #` zerlegen den String. Die erzeugten Passwörter sind hex.
- In der Schlüssel-Schreibweise sind die Namen nach dem Umschreiben der Aliase (`uid`, `pwd`, `db`, `server` usw.)
  groß-/kleinschreibungsabhängig: `Database=fivem` wird **nicht** als `database` erkannt. User und Datenbankname
  sind Pflicht (`Benutzer bzw. Datenbankname fehlt im mysql_connection_string`), Host ist sonst `localhost`, Port 3306.
- `127.0.0.1` statt `localhost`: Node.js löst `localhost` gern zu `::1` auf. Weil MariaDB eine Verbindung über
  `127.0.0.1` je nach `skip-name-resolve` dem Account `@localhost` oder `@127.0.0.1` zuordnet, legt `--create`
  beide Accounts mit demselben Passwort an.
- Optional `socketPath=/run/mysqld/mysqld.sock` (Schlüssel-Schreibweise oder `?socketPath=` in der URI). Unter
  Windows wird daraus eine Named-Pipe-Verbindung. Behält `--create` bzw. `-Create` einen String mit `socketPath`,
  prüft es die Anmeldung über diesen Socket bzw. diese Named Pipe.
- In der URI überschreiben die Query-Parameter `host`, `port`, `user`, `password`, `database` und `socketPath` wie
  bei oxmysql die Angaben davor, bei doppelten Parametern gewinnt der letzte:
  `mysql://fivem:pw@127.0.0.1/fivem?user=root&database=other` meldet sich als `root` an der Datenbank `other` an.
  Die Namen sind groß-/kleinschreibungsabhängig (`?Host=` zählt nicht), andere Parameter wie `charset` werten die
  Skripte nicht aus. Ein Parameter ohne Wert (`?user` oder `?user=`) ist leer; fehlen danach User oder
  Datenbankname, gilt die Meldung oben, und ein ungültiger `port` bricht mit Exit 1 ab.

## Backup und Wiederherstellung

Die Tabelle `repo_sql_imports` steckt im Dump, nach einer Wiederherstellung passt der Import-Stand also wieder.

Linux (als root, unix_socket):

```bash
mariadb-dump --single-transaction fivem | gzip > fivem-$(date +%F).sql.gz
gunzip -c fivem-2026-09-13.sql.gz | mariadb fivem                       # Wiederherstellen, Dienst vorher stoppen
```

Ein täglicher Cronjob steht in [linux-server.md](linux-server.md#backup).

Windows (Eingabeaufforderung, Versionsnummer im Pfad anpassen):

```
"C:\Program Files\MariaDB 12.3\bin\mariadb-dump.exe" -u root -p --single-transaction fivem > fivem.sql
"C:\Program Files\MariaDB 12.3\bin\mariadb.exe" -u root -p fivem < fivem.sql
```

In PowerShell funktioniert `<` nicht, dort `cmd /c "..."` nutzen.

Docker (Repo-Root):

```bash
docker compose --env-file .env -f docker/docker-compose.yml exec -T db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" exec mariadb-dump -uroot --single-transaction "$MARIADB_DATABASE"' > fivem.sql
docker compose --env-file .env -f docker/docker-compose.yml exec -T db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" exec mariadb -uroot "$MARIADB_DATABASE"' < fivem.sql
```

## Grafischer Client

HeidiSQL: `winget install --id HeidiSQL.HeidiSQL -e`. Lokal mit `127.0.0.1:3306` und dem User aus `secrets.cfg`
verbinden. Zum VPS per SSH-Tunnel (`ssh -L 3306:127.0.0.1:3306 root@<server-ip>`), MariaDB lauscht dort nur lokal.
Docker: die auskommentierten `ports`-Zeilen beim `db`-Service einkommentieren (`127.0.0.1:3306:3306`).

## Fehlerbilder

| Meldung                                                                       | Ursache und Lösung                                                                        |
|-------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------|
| `MariaDB nicht gefunden. Installieren: setup-database.bat -InstallMariaDB`     | Windows: MariaDB installieren, neues Terminal öffnen oder `-MariaDbBin` angeben.         |
| `Kein MariaDB-Client gefunden (mariadb oder mysql). Installieren: apt install mariadb-client` | Linux: Client installieren.                                               |
| `In ... fehlt ein aktives 'set mysql_connection_string ...'`                   | `--create` bzw. `-Create` ausführen oder den String von Hand eintragen.                  |
| `Datenbank nicht erreichbar oder Anmeldung fehlgeschlagen (...)`               | Dienst läuft nicht (`systemctl status mariadb`, Windows `net start MariaDB`), falscher Port oder Passwort. |
| `MariaDB ... ist zu alt. Qbox braucht mindestens 10.9`                        | Neuere MariaDB installieren, siehe [Welche Version](#welche-version).                    |
| `Der Server meldet '...', das ist kein MariaDB`                                | MySQL läuft auf dem Port. MariaDB installieren, MySQL beenden oder anderen Port nutzen.  |
| `<pfad> fehlt. Ist die Ressource installiert (install-resources)?`            | Ressourcen installieren (`install.bat` bzw. `install-resources.sh`), dann erneut.        |
| `FEHLER beim Import von ...`                                                  | Siehe [Wenn ein Import fehlschlägt](#wenn-ein-import-fehlschlägt).                        |
| `User existiert, Passwort unbekannt` / `Passwort in secrets.cfg passt nicht ...` | `--create --reset-password` bzw. `-Create -ResetPassword`.                              |
| `secrets.cfg zeigt auf einen anderen Datenbankserver`                          | `--create` richtet nur die lokale MariaDB ein. Für eine entfernte DB nur importieren.    |
| `secrets.cfg nutzt Port 3306, --db-port ist 3307` (Windows: `-Port ist 3307`)  | Der vorhandene String bliebe beim alten Port. Den Port aus `secrets.cfg` angeben (oder die Option weglassen) oder mit `--reset-password` bzw. `-ResetPassword` einen neuen String schreiben. |
| `Anmeldung als ... fehlgeschlagen` (am Ende von `--create`/`-Create`)          | Über TCP: `bind-address`, `port`, `skip-networking` und `skip-name-resolve` prüfen. Über einen Socket: `socketPath` passt nicht zum Server (Linux `SELECT @@socket;`, Windows `named-pipe` und `socket` in der `my.ini`). |
| `db-Container ist nach 120 s nicht bereit`                                    | `docker compose --env-file .env -f docker/docker-compose.yml logs db` lesen, erneut starten. |
| `-Create fragt das MariaDB-Root-Passwort ab und braucht dafür eine Konsole ...` | `setup-database.bat -Create` direkt in einem Fenster starten, nicht per Pipe.           |
| oxmysql meldet beim Serverstart Verbindungsfehler                             | `setup-database --dry-run` testet dieselben Zugangsdaten. Sonderzeichen im Passwort, `Database=` statt `database=`, MariaDB aus?          |
