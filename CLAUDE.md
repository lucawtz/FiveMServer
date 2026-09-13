# CLAUDE.md

Kontext und Regeln für Claude-Code-Sitzungen in diesem Repo. Gilt auf jedem Rechner (Mac, Windows-PC, VPS).

## Projekt

- Privater FiveM-Roleplay-Server für Luca und Freunde (etwa 5 bis 15 Spieler), kein Geld, kein öffentlicher Betrieb.
- Framework **Qbox** mit **MariaDB**, übersetzt aus dem offiziellen txAdmin-Rezept (Commit `a4be9fc`).
- Ziel ist Realismus über GTA-Lore-Marken und eigene Designs, **keine echten Marken** (siehe Regeln unten).
- Repo: **öffentliches** GitHub-Repo `lucawtz/FiveMServer` (seit 13.09.2026), Branch `main`. Alles Committete
  und die Logs der Actions sind für jeden sichtbar.
- Kommunikation mit Luca auf Deutsch in du-Form, kurze Zwischenstände. Doku und Skriptausgaben ebenfalls Deutsch.

## Wo was steht

- **Plan, Fortschritt, offene Entscheidungen:** [docs/checkliste.md](docs/checkliste.md). Erledigtes dort abhaken,
  neue Entscheidungen dort eintragen.
- **Warum etwas so gebaut ist:** [docs/entscheidungen.md](docs/entscheidungen.md), inklusive "Bekannte Grenzen".
- **Anleitungen:** README.md, `docs/windows-lokal.md`, `docs/linux-server.md`, `docs/docker.md`,
  `docs/datenbank.md`, `docs/ressourcen.md`, `docs/frameworks.md` (inkl. Abweichungen vom Rezept),
  `docs/inhalte-regeln.md`.

## Rechner und Teststand

- **Mac:** Entwicklung und Linux-Skripttests. FXServer läuft dort nicht (arm64, kein Docker), GTA ist nicht installiert.
- **Windows-PC:** lokaler Testserver mit GTA V und FiveM, Repo z. B. unter `C:\FiveMServer` (kurzer ASCII-Pfad).
- **Später:** Ubuntu-24.04-VPS mit systemd und txAdmin, Deploy per `scripts/linux/deploy.sh` bzw. GitHub Actions.
- **Stand 13.09.2026:** Auf dem Windows-PC (Windows 11, PowerShell 5.1, Repo unter `C:\Code\FiveMServer`) liefen
  `install.ps1`, `setup-database` (`-InstallMariaDB`, `-Create -Import`, `-DryRun`) gegen MariaDB 12.3.3 und
  `start.bat` mit txAdmin 8.1.1 erfolgreich, Qbox startet. Im Spiel ist noch nichts getestet. Die Linux-Skripte
  und Docker liefen noch nie auf einem echten Ubuntu. Meldet Luca Fehler, zuerst die **komplette**
  Konsolenausgabe erbitten.

## Aufbau

| Pfad | Inhalt |
|------|--------|
| `server-data/server.cfg` | gemeinsame Konfiguration, lädt per `exec` der Reihe nach `permissions.cfg`, `voice.cfg`, `ox.cfg`, `misc.cfg`, `secrets.cfg` |
| `server-data/secrets.cfg` | Lizenzschlüssel, `mysql_connection_string`, RCON, Tokens; gitignored, Vorlage `secrets.cfg.example` |
| `server-data/resources.txt` | Ressourcen-Manifest: `git <ziel> <url> [ref]`, `zip <ziel> <url>`, `copy <quelle> <ziel>` |
| `server-data/database.txt` | SQL-Manifest in Import-Reihenfolge, Option `rerun` nur für idempotente Dateien |
| `server-data/resources/[local]/` | eigene Ressourcen (committet) |
| `server-data/resources/[cfx-default]/`, `[vendor]/` | von den Installern befüllt, gitignored; `[vendor]/.sources` sind Quell-Repos, keine Ressourcen |
| `server-data/resources/[marketplace]/` | Assets aus dem Cfx Marketplace (Asset Escrow, gekauft oder kostenlos), von Hand entpackt und gitignored; committet sind nur `README.md` (Einrichtung pro Asset) und `.anpassungen/` (z. B. Übersetzungen) |
| `scripts/windows/` | `install.bat`/`.ps1`, `install-resources.ps1`, `setup-database.bat`/`.ps1`, `start.bat`, `start-direct.bat` |
| `scripts/linux/` | `lib.sh` (gemeinsame Funktionen), `install.sh`, `deploy.sh`, `install-resources.sh`, `update-artifacts.sh`, `setup-database.sh`, systemd-Vorlage |
| `docker/` | Dockerfile, `docker-compose.yml` (fxserver + db), `entrypoint.sh` |
| `artifacts/`, `txData/`, `tools/` | FXServer-Binaries, txAdmin-Daten, Hilfsprogramme; gitignored, `txData` nie löschen |

## Befehle

Windows, im Repo-Ordner (Befehle ohne Kommentar auf derselben Zeile ausführen):

| Befehl | Zweck |
|--------|-------|
| `scripts\windows\install.bat` | Artifacts, Ressourcen, `secrets.cfg`; Optionen `-UpdateResources`, `-ForceResources`, `-UpdateArtifacts`, `-SetupDatabase` |
| `scripts\windows\setup-database.bat -InstallMariaDB` | MariaDB per winget installieren |
| `scripts\windows\setup-database.bat -Create -Import` | Datenbank und User anlegen, SQL importieren |
| `scripts\windows\setup-database.bat -DryRun` | ausstehende SQL-Dateien anzeigen |
| `scripts\windows\start.bat` | txAdmin-Modus, <http://localhost:40120> |
| `scripts\windows\start-direct.bat` | ohne txAdmin, startet `+set onesync on +exec server.cfg` |

Linux:

| Befehl | Zweck |
|--------|-------|
| `sudo bash scripts/linux/install.sh --enable-firewall` | Erstinstallation, MariaDB ist Standard (`--no-mariadb` für externe DB) |
| `bash scripts/linux/deploy.sh` | `git pull`, Ressourcen, SQL-Import, Neustart; Optionen `--no-sql`, `--no-restart`, `--update-artifacts` |
| `bash scripts/linux/install-resources.sh --update` | git-Ressourcen aktualisieren, `--force` lädt alles neu |
| `bash scripts/linux/setup-database.sh --dry-run` | SQL-Status; außerdem `--import`, `--create`, `--mark-applied --only <pfad>` |

Docker: immer `docker compose --env-file .env -f docker/docker-compose.yml ...`, SQL-Import vom Host mit
`bash scripts/linux/setup-database.sh --docker`.

Exit-Codes von `setup-database`: 0 ok, 1 Abbruch, 2 Datenbank nicht erreichbar/Anmeldung/Version, 3 SQL-Fehler.

## Prüfen vor dem Commit

Die CI (`.github/workflows/ci.yml`) prüft Shell, PowerShell, Lua und die Manifeste. Lokal auf Mac oder Linux:

```bash
shellcheck scripts/linux/*.sh docker/entrypoint.sh
bash scripts/linux/install-resources.sh --check
bash scripts/linux/setup-database.sh --check
```

Auf Windows mindestens die geänderten `.ps1` parsen, z. B.
`powershell -NoProfile -Command "$t=$null; $e=$null; [void][System.Management.Automation.Language.Parser]::ParseFile('scripts\windows\install.ps1',[ref]$t,[ref]$e); $e"`
(keine Ausgabe heißt keine Syntaxfehler).

## Harte Regeln

1. **Keine Geheimnisse in Git.** Werte gehören in `secrets.cfg` bzw. `.env`. Skripte geben Passwörter nie auf
   einer Kommandozeile weiter.
2. **OneSync in keiner cfg-Datei.** txAdmin kommentiert `onesync`-Zeilen aus und verwaltet OneSync selbst. Der
   Direktmodus übergibt `+set onesync on` vor `+exec server.cfg`. Die CI prüft das.
3. **txAdmin über Umgebungsvariablen** `TXHOST_DATA_PATH` und `TXHOST_TXA_PORT`, nicht über `+set txAdminPort` usw.
   Nie `txAdminInterface 127.0.0.1` setzen: txAdmin lehnt dann die Endpoints `0.0.0.0:30120` ab.
4. **Fremd-Ressourcen nur über `resources.txt`.** Nie Dateien in `[vendor]` direkt ändern, das geht beim Update
   verloren oder bricht `git pull --ff-only`. Anpassungen über die Wege A bis E in `docs/checkliste.md`
   (Convar, Override per `copy`, fester Stand/Fork, eigene Ressource in `[local]`). Vor dem ersten Anpassen einer
   git-Ressource auf festen Stand umstellen.
5. **SQL nur über `database.txt`.** Neue Datei als Zeile eintragen, Import per `setup-database`. Die Tabelle
   `repo_sql_imports` nie von Hand ändern, stattdessen `--mark-applied`/`-MarkApplied` mit `--only`/`-Only`.
6. **Inhalte:** keine echten Marken, Logos, Produktnamen, Automodelle (auch nicht entbadged), realen Orte und keine
   Assets aus anderen Spielen (Rockstar Mod Guidelines, Creator PLA, gilt auch für private Server). Stattdessen
   GTA-Lore-Marken (z. B. Burger Shot, Sprunk, Pfister) oder eigene Designs. Kein Rockstar-, FiveM- oder
   Lore-Name im Servernamen; der Hinweis in `sv_projectDesc` muss zu `sv_projectName` passen. Details:
   `docs/inhalte-regeln.md`.
7. **Große Assets nicht in Git** (GitHub blockt Dateien über 100 MiB). Speicherort ist noch offen (Weg E).
8. **Encodings:** `.ps1` UTF-8 mit BOM und CRLF, `.bat` reines ASCII und CRLF, alles andere UTF-8 ohne BOM und LF.
9. **PowerShell** muss mit Windows PowerShell 5.1 laufen: kein `?:`, kein `??`, `Join-Path` mit einem Kind,
   `-LiteralPath` bei Pfaden mit `[`/`]`, `$LASTEXITCODE` nach externen Programmen prüfen.
10. **Bash:** `set -euo pipefail`, alles quoten, shellcheck-sauber, nicht-root-Teile bash-3.2-kompatibel (Tests auf
    macOS). Ausgaben der Linux-Skripte ohne Umlaute (`ae`, `oe`, `ue`), PowerShell-Ausgaben mit Umlauten.
11. **Doku:** Deutsch, du-Form, keine Gedankenstriche. Doku und Code im selben Commit synchron halten. Neue
    Designentscheidungen in `docs/entscheidungen.md`, Fortschritt in `docs/checkliste.md`.
12. **Git:** An diesem Repo arbeiten mehrere Sitzungen, auch auf verschiedenen Rechnern. Vor Änderungen `git pull`,
    vor einem Commit `git status` und `git log` prüfen. Committen und pushen nur, wenn Luca es sagt.
    Commit-Nachrichten auf Deutsch.

## Bekannte Stolperfallen

- `basic-gamemode` wird per `stop` angehalten (kollidiert mit der Qbox-Charakterauswahl). `mapmanager`,
  `spawnmanager` und `baseevents` kommen aus `[cfx-default]`. `hardcap` und `sessionmanager` gibt es nicht mehr.
- Rezept-Fehler: `cola` in der Fahrzeug-Beute (`ox.cfg`) und in den Shops (`[local]/[overrides]/shops.lua`) ist
  durch `sprunk` ersetzt; das Item `markedbills` fehlt noch
  (`docs/checkliste.md`, Phase 6).
- `server.cfg` stoppt `qbx_radialmenu`, das Radialmenü kommt aus `[marketplace]/codem-supreme-radialmenu`. Auf einem
  Rechner ohne das Asset die `stop`-Zeile auskommentieren. Gekaufte Dateien nie committen, das Repo ist öffentlich.
- `set qbx:cleanPlayerGroups "true"` entfernt beim Start Jobs, die `qbx_core` nicht kennt. Eigene Jobs deshalb in
  `qbx_core/shared/jobs.lua` (siehe Checkliste).
- Qbox-Quellen stehen wie im Rezept auf `main` bzw. `releases/latest` und können sich bei jedem Update ändern.
- `sv_master1 ""` nimmt den Server nicht aus der Serverliste. Zugang nur für Freunde über die txAdmin
  License Allowlist.
- In cfg-Dateien trennt `;` außerhalb von Anführungszeichen Befehle, auch in `#`-Kommentaren (Log:
  `No such command ...`). Die CI prüft das. Zweimal `Argument count mismatch (passed 1, wanted 2)` beim Start
  kommt von txAdmin (`sets sv_allowlistInstructions ""` bei ausgeschalteter Allowlist) und ist harmlos.
- Windows: Klick ins Konsolenfenster (QuickEdit) hält den Server an, `Esc` löst es. Pfade mit Umlauten brechen txAdmin.
- Admins und Allowlist liegen in `txData/` und wandern nicht über Git mit.
