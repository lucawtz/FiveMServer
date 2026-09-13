# Marketplace-Assets: `[marketplace]`

In diesem Ordner liegen Ressourcen aus dem [Cfx Marketplace](https://marketplace.cfx.re/). Sie kommen über dein
Cfx.re-Konto, nicht über `resources.txt`, und bleiben aus Git draußen:

- Marketplace-Assets sind an den Cfx.re-Account gebunden, der sie gekauft oder kostenlos geholt hat (Datei `.fxap`
  im Asset). Sie laufen nur auf einem Server, dessen `sv_licenseKey` zu diesem Account gehört.
- Das Repo ist öffentlich. Ein Commit wäre eine Weitergabe an alle.

Git kennt aus diesem Ordner nur diese README und den Unterordner `.anpassungen/` mit eigenen Dateien, z. B.
Übersetzungen. FXServer überspringt Ordner, deren Name mit `.` beginnt.

`server.cfg` startet alles hier mit `ensure [marketplace]`, nach Qbox, den ox-Ressourcen und den übrigen
Kategorien. Ist der Ordner leer, startet der Befehl nichts und meldet auch nichts (FXServer geht bei einer Kategorie
nur die gefundenen Ressourcen durch).

## Installierte Assets

| Ordner                 | Asset                | Version | Kosten    | Quelle |
|------------------------|----------------------|---------|-----------|--------|
| `electus_black_market` | Electus Black Market | 1.0.1   | kostenlos | [Marketplace](https://marketplace.cfx.re/packages/7426640-electus-black-market), [Doku](https://docs.electus-scripts.com/docs/blackmarket/installation) |
| `codem-supreme-radialmenu` | CodeM Supreme Radial Menu | 1.1 | gekauft | [Cfx-Portal](https://portal.cfx.re/), Download vom 13.09.2026 |

## electus_black_market einrichten

Schwarzmarkt mit NPC-Händlern, Tagesbestand, Öffnungszeiten und Bezahlung mit Schwarzgeld. Braucht `oxmysql` und
`ox_lib`, erkennt Qbox und ox_inventory selbst. Auf jedem Rechner, auf dem der Server läuft, einmal:

1. Asset im [Cfx-Portal](https://portal.cfx.re/) bei deinen Assets herunterladen, mit dem Account, dem der
   Lizenzschlüssel gehört.
2. Entpacken nach `server-data/resources/[marketplace]/electus_black_market/`, die `fxmanifest.lua` liegt direkt
   darin.
3. Deutsche Texte: `.anpassungen/electus_black_market/config/locales/de.lua` nach
   `electus_black_market/config/locales/de.lua` kopieren.
4. In `electus_black_market/config/config.lua` ändern:

   | Einstellung                   | Standard        | Hier            | Grund |
   |-------------------------------|-----------------|-----------------|-------|
   | `Config.Locale`               | `"en"`          | `"de"`          | deutsche Texte, fehlende fallen auf Englisch zurück |
   | `Config.Debug`                | `true`          | `false`         | keine Debug-Ausgaben in der Serverkonsole |
   | `Config.BlackMoneyItem`       | `"markedbills"` | `"black_money"` | `markedbills` gibt es auf diesem Server nicht (siehe `docs/checkliste.md`), bezahlt wird mit Schwarzgeld wie im Ammunation |
   | `Config.ElectusGangs.Enabled` | `true`          | `false`         | Electus Gangs ist nicht installiert |
   | `Config.BlackMarkets`         | Beispielmarkt   | Block unten     | das Beispiel-Item `armor` heißt in Qbox `armour`, Beschriftungen deutsch |

   ```lua
   Config.BlackMarkets = {
   	{
   		id = "vespucci_drop",
   		label = "Umschlagplatz Vespucci",
   		npc = {
   			model = "g_m_m_chicold_01",
   			coords = vector4(-1172.57, -1572.11, 4.66, 124.0),
   			scenario = "WORLD_HUMAN_SMOKING",
   		},
   		access = {
   			type = "public",
   		},
   		items = {
   			{ id = "lockpick", item = "lockpick", label = "Dietrich", price = 450, maxStock24h = 25 },
   			{ id = "advancedlockpick", item = "advancedlockpick", label = "Verbesserter Dietrich", price = 1500, maxStock24h = 10 },
   			{ id = "electronickit", item = "electronickit", label = "Elektronik-Set", price = 2500, maxStock24h = 5 },
   			{ id = "thermite", item = "thermite", label = "Thermit", price = 6000, maxStock24h = 3 },
   			{ id = "armour", item = "armour", label = "Schutzweste", price = 3200, maxStock24h = 10 },
   			{ id = "radio", item = "radio", label = "Funkgerät", price = 900, maxStock24h = 15 },
   			{ id = "weapon_knife", item = "weapon_knife", label = "Messer", price = 1250, maxStock24h = 10 },
   		},
   	},
   }
   ```

   Die Preise sind Startwerte, bis die Wirtschaft entschieden ist.
5. Tabellen anlegen. Das Script legt sie nicht selbst an. Über `database.txt` geht es nicht, weil `setup-database`
   dann auf jedem Rechner ohne das Asset mit Exit 3 abbräche. Die Datei nutzt `CREATE TABLE IF NOT EXISTS`, ein
   zweiter Lauf schadet nicht.

   Windows, Eingabeaufforderung im Repo-Ordner (Versionsnummer im Pfad anpassen, das Passwort des Users `fivem`
   steht in `secrets.cfg`):

   ```
   "C:\Program Files\MariaDB 12.3\bin\mariadb.exe" -u fivem -p fivem < "server-data\resources\[marketplace]\electus_black_market\electus_black_market.sql"
   ```

   In PowerShell funktioniert `<` nicht, dort `cmd /c "..."` nutzen. Alternativ die Datei in HeidiSQL öffnen und
   ausführen ([datenbank.md](../../../docs/datenbank.md#grafischer-client)).

   Linux (als root):

   ```bash
   mariadb fivem < "server-data/resources/[marketplace]/electus_black_market/electus_black_market.sql"
   ```

6. Server neu starten, z. B. in txAdmin.

Im Spiel:

- Der Händler "Umschlagplatz Vespucci" steht am Strand von Vespucci (`-1172.57, -1572.11`) und ist von 20 bis 6 Uhr
  Spielzeit da (`Config.DefaultMarketSchedule`). Ansprechen per Interaktion (Taste `E`).
- Bezahlt wird mit dem Item `black_money`.
- Verwalten mit `/manage_black_market`. Das dürfen Admins: `permissions.cfg` gibt `group.admin` mit
  `add_ace group.admin command allow` alle Befehle.
- Käufe stehen in der Tabelle `electus_black_market_transactions`.

## codem-supreme-radialmenu einrichten

Radialmenü mit eigener Oberfläche auf F3. Es ersetzt `qbx_radialmenu`: Kofferraum, Fesseln und Abführen,
Kleidung ablegen, Fahrzeug (Türen, Sitze, Extras, Aufrichten), Kartenmarker, eigene Befehle und Job-Menüs. Braucht nur
`ox_lib` und erkennt Qbox selbst. Keine SQL-Datei, keine zusätzlichen Modelle (die Trage ist ein GTA-Objekt). Auf jedem
Rechner, auf dem der Server läuft, einmal:

1. Asset im [Cfx-Portal](https://portal.cfx.re/) bei deinen Assets herunterladen, mit dem Account, dem der
   Lizenzschlüssel gehört, und nach `server-data/resources/[marketplace]/codem-supreme-radialmenu/` entpacken. Die
   `fxmanifest.lua` liegt direkt darin.
2. Deutsche Texte: `.anpassungen/codem-supreme-radialmenu/locales/de.json` nach
   `codem-supreme-radialmenu/locales/de.json` kopieren. Die Datei ist vollständig, das muss so bleiben: Die Oberfläche
   bekommt sie ohne Rückfall auf Englisch. `settings.title` ist der Name oben in den Einstellungen, beim Festlegen des
   Projektnamens mit ändern.
3. In `codem-supreme-radialmenu/shared/config.lua` ändern:

   | Einstellung              | Standard                                           | Hier            | Grund |
   |--------------------------|----------------------------------------------------|-----------------|-------|
   | `Locale`                 | `"en"`                                             | `"de"`          | deutsche Texte |
   | `DefaultCommands`        | `/phone`, `/inventory`, `/wallet`, `/emotes`       | Block unten     | nur `/phone` gibt es auf diesem Server |

   ```lua
   DefaultCommands = {
       { labelKey = "game.menu.phone",     label = "Phone",     icon = "phone",      command = "/phone" },
       { labelKey = "game.menu.inventory", label = "Inventory", icon = "box",        command = "/+inv" },
       { labelKey = "game.menu.emotes",    label = "Emotes",    icon = "face-smile", command = "/emotemenu" },
   },
   ```

   `/phone` kommt aus npwd, `+inv` ist der Tastenbefehl von ox_inventory (wie Tab), `/emotemenu` kommt aus
   scully_emotemenu. Die Liste ist nur der Startwert, jeder Spieler kann sie in den Einstellungen ändern.
4. In `codem-supreme-radialmenu/shared/items.lua` die Einträge löschen, deren Event auf diesem Server niemand empfängt
   (ein Klick täte nichts). Geprüft am 13.09.2026 gegen die Qbox-Quellen:

   | Eintrag                     | Menü       | Event ohne Empfänger |
   |-----------------------------|------------|----------------------|
   | `givecontact`               | Bürger     | `qb-phone:client:GiveContactDetails` (npwd hat das nicht) |
   | `takedriverlicense`         | Polizei    | `police:client:SeizeDriverLicense` |
   | `repair` und `clean`        | Mechaniker | `mechanic:client:RepairVehicle`, `mechanic:client:CleanVehicle` |
   | ganzer Block `['hotdog']`   | Hotdog     | `qb-hotdogjob:client:ToggleSell` (keine Hotdog-Ressource installiert) |

   Lua erlaubt ein Komma nach dem letzten Eintrag, beim Löschen muss also kein Komma angepasst werden.
5. Server neu starten. `server.cfg` hält `qbx_radialmenu` direkt nach `ensure [marketplace]` per `stop` an. Fehlt das
   Asset auf einem Rechner, dort die Zeile `stop qbx_radialmenu` auskommentieren, sonst gibt es kein Radialmenü.

Im Spiel:

- F3 öffnet das Menü. Im Modus "Halten" schließt Loslassen es, im Modus "Drücken" ESC. Umstellen, Design, Größe und
  eigene Befehle unter `/radialsettings` oder im Menü unter Allgemein. Die Taste lässt sich in GTA unter Einstellungen,
  Tastenbelegung, FiveM ändern.
- Job-Menüs erscheinen nur im Dienst und nur für die Jobnamen `police`, `ambulance`, `mechanic`, `taxi` und `tow`
  (Schlüssel von `JobInteractions` in `items.lua`). `bcso` und `sasp` haben kein Menü. Bei Bedarf den Block
  `['police']` kopieren und Schlüssel und `id` umbenennen. "Abschleppen" wirkt nur im Abschleppwagen.
- `/getintrunk` und `/putintrunk` darf jeder Spieler nutzen. Der Server prüft beim Hineinlegen nur, ob der andere
  Spieler weniger als 2 Meter entfernt ist.
- Z öffnet weiterhin das Radialmenü von ox_lib, dort steht nur noch der Emote-Eintrag von scully_emotemenu. Wer nur
  ein Radialmenü will: `setr scully_emotemenu:enableRadialMenu "false"` (nicht umgesetzt).
- Gegenüber `qbx_radialmenu` fehlt das Öffnen und Schließen der Fenster.
- Eigene Ressourcen hängen Einträge über die Client-Exports `AddMenuItem` und `RemoveMenuItem` ein, nicht über
  `lib.addRadialItem`.

## Neues Asset hinzufügen

1. Vorher prüfen: kostenlos oder im Budget, keine echten Marken und keine Modelle aus anderen Spielen
   ([inhalte-regeln.md](../../../docs/inhalte-regeln.md)).
2. Nach `[marketplace]/<name>/` entpacken und die Abhängigkeiten aus der Doku des Assets prüfen. Die Position von
   `ensure [marketplace]` startet es nach Qbox und ox.
3. SQL-Dateien wie oben einmal von Hand importieren.
4. Zeile in der Tabelle "Installierte Assets" ergänzen, eigene Dateien unter `.anpassungen/<name>/` ablegen und die
   nötigen Config-Änderungen hier aufschreiben.
