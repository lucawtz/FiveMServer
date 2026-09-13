# Framework: Qbox

Auf diesem Server läuft **Qbox** mit MariaDB. Die Ressourcen sind eine Übersetzung des offiziellen
txAdmin-Rezepts von Qbox (<https://github.com/Qbox-project/txAdminRecipe>, `qbox.yaml`, Commit `a4be9fc` vom
09.07.2026) in die Manifeste dieses Repos: `server-data/resources.txt` (Ressourcen), `server-data/database.txt`
(SQL-Dateien) und `server-data/server.cfg` mit `permissions.cfg`, `ox.cfg`, `voice.cfg` und `misc.cfg`.

Warum Qbox (Stand September 2026, Details in [entscheidungen.md](entscheidungen.md#qbox-als-framework)):

- aktiv gepflegt mit regelmäßigen Releases (`qbx_core` v1.24.0 vom August 2026),
- modernes ox-Paket (ox_lib, ox_inventory, ox_target, oxmysql) statt eigener Inventar- und Menüsysteme,
- deutsche Sprachdateien für Kern und ox-Ressourcen,
- `qbx_core` stellt `qb-core` bereit (`provide 'qb-core'` plus Brücke): die meisten QBCore-Skripte laufen weiter,
  solange sie `qb-core` auf dokumentierte Weise nutzen (nicht z. B. direkt auf dessen Tabellen zugreifen),
- das Rezept bringt eine komplette Roleplay-Grundlage mit: Jobs, Garagen, Händler, Immobilien, Handy.

## Was installiert ist

`install.bat` bzw. `install-resources.sh` legen alles unter `server-data/resources/[vendor]/` ab. Die
Kategorie-Ordner startet `server.cfg` mit `ensure [kategorie]`.

| Ordner in `[vendor]` | Inhalt                                                                                                   |
|----------------------|----------------------------------------------------------------------------------------------------------|
| `.sources/`          | Keine Ressourcen, von FXServer ignoriert: `qbox-recipe` (Rezept-Repository, liefert `items.lua` und `qbox.sql`) und `qbx_invimages` (Item-Bilder). |
| `[ox]`               | `ox_lib` (Bibliothek, Menüs, Hinweise), `oxmysql` (Datenbank-Anbindung), `ox_target` (Zielsystem), `ox_inventory` (Inventar, Shops, Lager), `ox_doorlock` (Türschlösser), `ox_fuel` (Tanken). |
| `[qbx]`              | `qbx_core` (Spieler, Charaktere, Jobs, Gangs) und 47 weitere Qbox-Ressourcen: Spawn, HUD, Radialmenü, Garagen, Fahrzeughändler, Fahrzeugschlüssel, Immobilien, Rathaus, Polizei, Rettungsdienst, Mechaniker, Taxi, Bus, Müllabfuhr, Abschleppdienst, Überfälle, Rennen, Tuning, Admin-Menü und mehr. |
| `[standalone]`       | Framework-unabhängige Ressourcen: `bob74_ipl` (Innenräume), `illenium-appearance` (Aussehen, Kleidung), `Renewed-Banking` (Bank), `Renewed-Weathersync` (Wetter und Uhrzeit), `scully_emotemenu` (Emotes), `xt-prison` (Gefängnis), `vehiclehandler` (Fahrzeugschaden), `loadscreen` (Ladebildschirm), `screencapture` (Bildschirmfotos), `[MugShotBase64]` (Fahndungsfotos), `safecracker`, `mhacking`, `ultra-voltlab` (Minispiele), `mana_audio` (Audio). |
| `[voice]`            | `pma-voice` (Sprachchat), `mm_radio` (Funkgerät).                                                        |
| `[npwd]`             | `npwd` (Handy, fest auf Version 3.16.0), `qbx_npwd` (Qbox-Anbindung).                                    |
| `[npwd-apps]`        | `npwd_qbx_garages`, `npwd_qbx_mail` (Handy-Apps).                                                        |
| `[assets]`           | `pillbox` (Krankenhaus-Innenraum).                                                                        |

Aus `[cfx-default]` laufen `mapmanager`, `spawnmanager` und `baseevents`, `chat` kommt aus dem Artifact.
Drei `copy`-Zeilen im Manifest legen Dateien über andere Ressourcen: die Qbox-Items nach
`ox_inventory/data/items.lua`, die Qbox-Item-Bilder nach `ox_inventory/web/images` und die Qbox-Konfiguration
von `qbx_npwd` nach `npwd/config.json` (Format: [ressourcen.md](ressourcen.md#copy)).

## Voraussetzungen

- **OneSync** an. Steht in keiner cfg-Datei: txAdmin setzt es selbst (Settings > FXServer, Standard "on"),
  der Direktmodus übergibt `+set onesync on` vor `+exec server.cfg`.
- **FXServer-Artifact >= 10731** (`qbx_core` verlangt das). Der Kanal `recommended` (35245) passt; der Kanal
  `optional` (Build 7290) ist zu alt für Qbox.
- **MariaDB >= 10.9**, empfohlen 12.3 LTS. Einrichten und SQL-Import: [datenbank.md](datenbank.md).
- `server.cfg` setzt `sv_enforceGameBuild 3751`.

## Abweichungen vom Rezept

Das Rezept deployt in einen leeren Ordner und schreibt eine eigene `server.cfg`. Hier läuft stattdessen die
committete Konfiguration, deshalb unterscheidet sich Folgendes:

- **Kein Deploy über txAdmin.** Die Download-, Kopier- und SQL-Schritte des Rezepts stehen bis auf die hier
  genannten Ausnahmen 1:1 in `resources.txt` und `database.txt`, txAdmin wird mit "Existing Server Data"
  eingerichtet.
- **Logo entfällt.** Das Rezept kopiert sein Logo über `loadscreen/html/assets/logo.png` und setzt es als
  Server-Icon. Hier bleibt das Logo von `loadscreen`, `load_server_icon` ist auskommentiert.
- **`config.json` wird kopiert, nicht verschoben.** Das Rezept verschiebt `qbx_npwd/config.json` nach `npwd/`.
  Das Verschieben würde eine versionierte Datei im Git-Klon von `qbx_npwd` löschen und späteres
  `git pull --ff-only` stören.
- **MugShotBase64 liegt in einem Klammer-Ordner.** Das Repo hat die Ressource im Unterordner `MugShotBase64/`,
  deshalb wird es nach `[vendor]/[standalone]/[MugShotBase64]` geklont. README und LICENSE bleiben eine Ebene
  darüber liegen, FXServer findet die Ressource darunter.
- **`sessionmanager` und `hardcap` werden nicht gestartet.** Beide gibt es in `cfx-server-data` nicht mehr, das
  Rezept-`ensure` würde nur `Couldn't find resource` melden.
- **`remove_path` für `[cfx-default]/[gameplay]/chat` entfällt.** `cfx-server-data` enthält `chat` nicht mehr,
  `ensure chat` startet den Systemchat aus dem Artifact.
- **`stop basic-gamemode`** wie im Rezept: `basic-gamemode` schaltet den automatischen Spawn ein und kollidiert
  mit der Charakterauswahl.
- **Spielversion 3751 statt 3258.** Qbox nennt keinen Pflicht-Build, jeder Build enthält die Inhalte der
  früheren. Bei Problemen mit einzelnen Innenräumen testweise `sv_enforceGameBuild 3258` setzen.
- **Deutsche Sprache** über Convars (`ox:locale`, `illenium-appearance:locale`, `qb_locale`) und deutsche
  Texte für Chat-Meldungen und MOTD.
- **Keine automatischen Admin-Rechte.** Das Rezept trägt den txAdmin-Master-Account per
  `{{addPrincipalsMaster}}` als Admin ein. Hier machst du das von Hand in `server.cfg`, Abschnitt "Admin-Rechte"
  (`add_principal identifier.license:... group.admin`).
- **`quit` für Admins gesperrt.** `permissions.cfg` ergänzt `add_ace group.admin command.quit deny` (wie die
  cfx-Standard-server.cfg), damit ein Admin im Spiel den Server nicht per `quit` beendet.
- **Geheimnisse in `secrets.cfg`.** Lizenzschlüssel, `mysql_connection_string`, RCON, `steam_webApiKey` und die
  npwd-Tokens stehen nicht in `server.cfg`, sondern in der gitignorierten `secrets.cfg`.
- **`steam_webApiKey` bleibt ungesetzt.** Das Rezept setzt ihn auf `"none"`, hier steht er nur als auskommentierte
  Vorlage in `secrets.cfg.example`.
- **`qbx:discordLink`** ist ein deutscher Hinweistext ("Frag einen Admin") statt des Qbox-Einladungslinks.
- **Reihenfolge der cfg-Dateien.** `permissions.cfg` und `misc.cfg` werden vor `secrets.cfg` und dem ensure-Block
  geladen (Rezept: nach dem ensure-Block). Das ändert nichts, weil ACE-Rechte erst zur Laufzeit geprüft werden und
  `misc.cfg` nur einen Convar setzt.
- **Kein Warteschritt.** Der `waste_time`-Schritt des Rezepts entfällt.
- **SQL mit Buchführung.** Jede SQL-Datei läuft genau einmal; idempotente Dateien sind mit `rerun` markiert und
  laufen nach Änderungen erneut ([datenbank.md](datenbank.md#so-funktioniert-der-import)).
- **Zeichensatz der Datenbank.** Das Rezept legt die Datenbank mit utf8/utf8_general_ci an,
  `setup-database --create` bzw. `-Create` mit utf8mb4/utf8mb4_unicode_ci (wie die Qbox-Tabellen). Unter Docker
  legt der `db`-Container die Datenbank mit dem Server-Standard an; Tabellen ohne eigenen Zeichensatz
  (npwd `import.sql`) erben ihn.
- **`sprunk` statt `cola` in der Fahrzeug-Beute.** Das Rezept trägt in `inventory:vehicleloot` das Item `cola`
  ein, das weder die Qbox-Items noch ox_inventory definieren. ox_inventory meldet dann `item does not exist`
  und legt nichts ab. `ox.cfg` nutzt stattdessen das GTA-Getränk `sprunk`, das in den Qbox-Items existiert.
- **ox_lib fest auf v3.39.0 mit eigener `textui.lua`.** `[local]/[overrides]/ox_lib_textui.lua` ersetzt per
  `copy`-Zeile die TextUI von ox_lib: Interaktions-Hinweise ("E - Garage öffnen" usw.) stehen immer unten mittig,
  größer und mit farbigem Rand, auch wenn eine Ressource `left-center` oder `right-center` angibt. Im Original
  stehen sie klein am Bildschirmrand und fallen kaum auf.
- **Eigene Ressource `probefahrt`.** `qbx_vehicleshop` setzt am Ende der Probefahrt den Spieler per Teleport vor
  den Händler, ohne ihn vorher aussteigen zu lassen; wer fährt, kann dabei sterben. `[local]/probefahrt` hält das
  Fahrzeug 3 Sekunden vor dem Ende an, lässt den Spieler aussteigen und macht ihn 8 Sekunden unverwundbar.
  `qbx_vehicleshop` selbst bleibt unverändert.

## Qbox aktualisieren

- `deploy.sh` (Linux) bzw. `install.bat -UpdateResources` (Windows) machen `git pull --ff-only` in allen
  git-Zielen. Die Qbox-Repos stehen wie im Rezept auf `main`, jedes Deploy holt also den neuesten Stand.
- zip-Einträge mit `releases/latest/download/...` (oxmysql, ox_inventory, illenium-appearance usw.)
  ändern sich mit `--update`/`-Update` **nicht**. Neue Releases holt nur `--force`/`-Force`, das alle Ziele neu lädt.
  ox_lib steht fest auf v3.39.0 (eigene `textui.lua`).
- Wer einen Stand festhalten will, setzt im Manifest bei git-Zeilen ein Tag als `[ref]` bzw. bei zip-Zeilen eine
  Release-URL mit fester Version (wie bei npwd `.../releases/download/3.16.0/npwd.zip`), siehe
  [ressourcen.md](ressourcen.md#fester-stand-oder-immer-aktuell).
- Neue SQL-Dateien und geänderte `rerun`-Dateien importiert `setup-database` automatisch (auch in `deploy.sh`).
  Andere geänderte Dateien erzeugen nur eine Warnung.
- Vor größeren Updates Datenbank sichern ([datenbank.md](datenbank.md#backup-und-wiederherstellung)) und nach dem
  Update die Serverkonsole auf Fehler prüfen.

## Sprache

- `setr ox:locale "de"` in `ox.cfg` gilt für ox_lib und alle Ressourcen mit `locales/*.json`, also Qbox und die
  ox-Ressourcen.
- `setr illenium-appearance:locale "de"` in `server.cfg` für Aussehen und Kleidung.
- `setr qb_locale "de"` wirkt nur für zusätzliche QBCore-Skripte über die Brücke, keine Rezept-Ressource liest es.
- Das Handy (npwd) stellt die Sprache in den Einstellungen des Handys um.
- Ohne deutsche Übersetzung (fallen auf Englisch zurück oder haben feste englische Texte): `xt-prison`,
  `npwd_qbx_garages`, `npwd_qbx_mail`, `qbx_idcard`, `qbx_streetraces`, `qbx_scoreboard`.
- Spieler dürfen die Sprache nicht selbst wählen (`setr ox:userLocales 0`).

## Zu ESX Legacy oder QBCore wechseln (kurz)

Frameworks lassen sich nicht mischen, `qbx_core` stellt selbst `qb-core` bereit. Für einen Wechsel:

1. In `resources.txt` alle Zeilen unterhalb des Kopfes durch die Ressourcen des neuen Frameworks ersetzen, in
   `database.txt` die SQL-Zeilen, in `server.cfg` den ensure-Block und die Qbox-Convars. `ox.cfg`,
   `permissions.cfg` und `voice.cfg` an das neue Framework anpassen.
2. Eine **neue, leere Datenbank** verwenden, z. B.
   `sudo bash scripts/linux/setup-database.sh --create --db esx --db-user esx --reset-password` bzw.
   `setup-database.bat -Create -DbName esx -DbUser esx -ResetPassword`. `repo_sql_imports` beginnt dort leer.
3. Server stoppen und den kompletten Ordner `server-data/resources/[vendor]` löschen (oder umbenennen), damit keine
   Qbox-Ressourcen mit gleichen Namen übrig bleiben (`--force` lädt nur Ziele neu, die im aktuellen Manifest
   stehen). `[cfx-default]` und `[local]` bleiben.
4. `install-resources --force`, `setup-database --import`, Server starten.

Vorlage sind die offiziellen Rezepte:
ESX Legacy <https://raw.githubusercontent.com/esx-framework/ESX-recipes/legacy/recipe.yaml>,
QBCore <https://raw.githubusercontent.com/qbcore-framework/txAdminRecipe/main/qbcore.yaml>.
Jeder `download_github`/`download_file`-Schritt wird zu einer `git`- bzw. `zip`-Zeile, jeder `move_path`/`copy_path`
zu einer `copy`-Zeile, jeder `query_database`-Schritt zu einer Zeile in `database.txt`.

## Prüfen und Fehlersuche

- **Datenbank:** `setup-database --dry-run` zeigt, ob die Verbindung klappt und alle SQL-Dateien importiert sind.
  Verbindungsfehler von oxmysql beim Start: Sonderzeichen im Passwort, `Database=` statt `database=`, MariaDB aus?
  Siehe [datenbank.md](datenbank.md#fehlerbilder).
- **`Table 'fivem....' doesn't exist`:** SQL nicht importiert, `setup-database` ausführen.
- **`Couldn't find resource ...`:** Ressource nicht installiert (Ausgabe von `install-resources` prüfen) oder
  Tippfehler im ensure. Betrifft es `mapmanager`, `spawnmanager` oder `baseevents`, fehlt `[cfx-default]`:
  Windows `install.bat` ohne `-SkipResources`, Linux `scripts/linux/install-resources.sh` (bei kaputtem Ordner
  mit `-ForceResources` bzw. `--force`).
- **Items fehlen oder heißen falsch, keine Item-Bilder:** Die `copy`-Zeilen sind nicht gelaufen. In der Ausgabe
  von `install-resources` nach `[copy]` suchen; `install-resources --check` prüft die Reihenfolge.
- **Keine Charakterauswahl, Spieler spawnt sofort:** `basic-gamemode` läuft. In `server.cfg` muss
  `stop basic-gamemode` stehen, kein `ensure basic-gamemode`.
- **ox_lib oder qbx_core starten nicht, Meldung zu OneSync:** txAdmin Settings > FXServer > OneSync "on"; im
  Direktmodus `start-direct.bat` bzw. `+set onesync on` vor `+exec server.cfg`. Kein `set onesync on` in eine
  cfg-Datei schreiben, txAdmin kommentiert es aus.
- **Linke Alt-Taste doppelt belegt:** Funk (`voice_defaultRadio` in `voice.cfg`) und Zielsystem
  (`ox_target:defaultHotkey` in `ox.cfg`) nutzen beide `LMENU`. Spieler können die Tasten in GTA unter
  Einstellungen > Tastenbelegung > FiveM ändern; für alle ändern: einen der beiden Werte in der cfg-Datei.
- **Innenräume fehlen oder flackern:** testweise `sv_enforceGameBuild 3258` in `server.cfg`.
- **`/admin` geht nicht:** `add_principal` für deine ID in `server.cfg` eintragen (Abschnitt "Admin-Rechte"),
  Server neu starten.
- **Englische Texte:** siehe [Sprache](#sprache).
