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

## Neues Asset hinzufügen

1. Vorher prüfen: kostenlos oder im Budget, keine echten Marken und keine Modelle aus anderen Spielen
   ([inhalte-regeln.md](../../../docs/inhalte-regeln.md)).
2. Nach `[marketplace]/<name>/` entpacken und die Abhängigkeiten aus der Doku des Assets prüfen. Die Position von
   `ensure [marketplace]` startet es nach Qbox und ox.
3. SQL-Dateien wie oben einmal von Hand importieren.
4. Zeile in der Tabelle "Installierte Assets" ergänzen, eigene Dateien unter `.anpassungen/<name>/` ablegen und die
   nötigen Config-Änderungen hier aufschreiben.
