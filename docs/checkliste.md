# Checkliste: Was auf den Server kommt und wie

Plan für den privaten Roleplay-Server: Qbox, nur Freunde, Fokus Realismus mit GTA-Lore-Marken und eigenen
Designs ([inhalte-regeln.md](inhalte-regeln.md)). Stand: 13.09.2026.

Erledigtes mit `[x]` abhaken. Punkte mit **Entscheidung** brauchen zuerst eine Antwort aus
[Offene Entscheidungen](#offene-entscheidungen).

## Überblick

| Meilenstein | Ziel                                                                  | Phasen |
|-------------|-----------------------------------------------------------------------|--------|
| M1          | Server läuft auf dem Windows-PC, ein Freund kommt drauf               | 0      |
| M2          | Rezept im Spiel getestet, Fehler behoben, Stände festgehalten         | 1, 2   |
| M3          | Eigene Identität und Grund-Realismus (km/h, Wirtschaft, Fahrzeuge)    | 3, 4   |
| M4          | Erstes eigenes Restaurant spielbar (Prototyp: Burger Shot)            | 5      |
| M5          | Umzug auf den Linux-VPS, regelmäßig spielen                           | 7      |
| M6          | Kriminalität ausbauen (Geldwäsche, Labore, Waffenhandel), weitere Firmen, Inhalte | 5, 6, 8 |

M5 lässt sich vorziehen, wenn Freunde über das Internet nicht auf den PC kommen (DS-Lite/CGNAT, siehe
[windows-lokal.md](windows-lokal.md#freunde-verbinden)). Entwickeln geht weiter lokal.

## So werden Änderungen umgesetzt

Fast jeder Punkt unten läuft über einen dieser fünf Wege. Sie folgen aus dem Aufbau des Repos: `[vendor]` gehört
den Installern, eigene Arbeit liegt in committeten Dateien.

| Weg | Wann                                   | Wo                                                        |
|-----|----------------------------------------|-----------------------------------------------------------|
| A   | Ressource bietet einen Convar an       | `server.cfg`, `ox.cfg`, `voice.cfg`, `misc.cfg`           |
| B   | Datei in einer **zip**-Ressource ändern | Kopie unter `[local]/[overrides]/`, `copy`-Zeile in `resources.txt` |
| C   | Datei in einer **git**-Ressource ändern | erst auf festen Stand umstellen, dann wie B oder im Fork  |
| D   | eigene Spiellogik                      | eigene Ressource unter `[local]/<name>/`                  |
| E   | große Assets (Fahrzeuge, Innenräume, Kleidung) | nicht in Git, **Entscheidung** Speicherort         |

**Weg A** zuerst prüfen, er übersteht jedes Update.

**Weg B** ist schon dokumentiert: [ressourcen.md, Eigene Item-Definitionen](ressourcen.md#eigene-item-definitionen).
Passt für `ox_inventory` (`data/items.lua`, `data/shops.lua`, `data/crafting.lua`, `data/stashes.lua`) und `npwd`.
zip-Ziele ändern sich nur mit Force, danach legt die `copy`-Zeile die eigene Fassung wieder drüber. Nach einem
Update die Original-Datei mit der eigenen vergleichen.

**Weg C** betrifft zum Beispiel `qbx_core/config/server.lua`, `qbx_core/shared/jobs.lua`,
`qbx_core/shared/vehicles.lua`, `qbx_hud/config/client.lua` und `qbx_vehicleshop/config/shared.lua`. Eine
`copy`-Zeile allein reicht dort nicht: Die Datei gilt im Git-Klon als lokal geändert, und
`install-resources --update` (auch in `deploy.sh`) scheitert an `git pull --ff-only`, sobald Qbox dieselbe Datei
ändert. Deshalb vor der ersten Anpassung umstellen:

- **Release-Zip**, wenn es eins gibt und es nicht älter als `main` ist. Beispiel qbx_core (Release v1.24.0 vom
  22.08.2026 mit `qbx_core.zip`, ein Oberordner, `qbx_core.sql` liegt an derselben Stelle wie im Klon):

  ```
  zip [vendor]/[qbx]/qbx_core https://github.com/Qbox-project/qbx_core/releases/download/v1.24.0/qbx_core.zip
  ```

  Server stoppen, alten Ordner `[vendor]/[qbx]/qbx_core` löschen, `install-resources` ausführen. Vorsicht:
  `qbx_hud` (v0.1.0) und `qbx_garages` (v1.1.4) haben nur Releases von 2024, `qbx_vehicleshop` gar keins.
- **Eigener Fork** auf GitHub, sonst. Änderungen direkt im Fork committen, im Manifest mit Tag referenzieren
  (`git <ziel> <fork-url> <tag>`). Updates von Qbox holst du bewusst per Merge in den Fork.

**Weg D:** Aufbau und Beispiel in [server-data/resources/[local]/README.md](../server-data/resources/%5Blocal%5D/README.md).
Auf `ox_lib`, `ox_target` und `ox_inventory` aufbauen, wie die Qbox-Ressourcen. Geld, Items und Jobs immer auf dem
Server prüfen und ändern, nie dem Client vertrauen.

### Stolperfalle: eigene Jobs und cleanPlayerGroups

qbx_core kann Jobs zur Laufzeit anlegen (`exports.qbx_core:CreateJobs(jobs)`). Das klingt nach dem saubersten Weg
für eigene Firmen, beißt sich aber mit `set qbx:cleanPlayerGroups "true"` in `server.cfg`: qbx_core löscht beim
eigenen Start alle Einträge aus `player_groups`, deren Job es nicht kennt. Das passiert, bevor eine eigene
Ressource ihre Jobs registriert, und jeder Serverneustart würde die Mitarbeiter eigener Firmen entlassen.

Deshalb eine der beiden Varianten:

- [ ] **Empfehlung:** Jobs in `qbx_core/shared/jobs.lua` eintragen (Weg C). Eine Quelle für alle Jobs,
      `cleanPlayerGroups` bleibt an und räumt weiter auf.
- [ ] Alternative: `CreateJobs` aus der eigenen Ressource, dann `qbx:cleanPlayerGroups` auf `"false"` und die
      Jobs auch nach einem Neustart von `qbx_core` erneut registrieren (`onResourceStart`).

---

## Phase 0: Server lokal zum Laufen bringen

- [x] Grundgerüst, Skripte, Doku (`977fab0`, `aa24ff3`)
- [x] Qbox und MariaDB eingebaut (`c3ccd53`)
- [x] Lizenzschlüssel erstellen: <https://portal.cfx.re/> > Servers > Registration Keys
- [x] Am Windows-PC klonen (kurzer Pfad, z. B. `C:\FiveMServer`), `scripts\windows\install.bat`
      (13.09.2026 unter `C:\Code\FiveMServer`: Artifacts 35245, 80 von 80 Manifest-Einträgen installiert)
- [x] `setup-database.bat -InstallMariaDB`, danach `setup-database.bat -Create -Import`
      (13.09.2026: MariaDB 12.3.3, 9 SQL-Dateien importiert)
- [ ] Key in `server-data\secrets.cfg` eintragen
- [x] `start.bat`, txAdmin mit "Existing Server Data" einrichten (13.09.2026, alle Ressourcen starten, Datenbank verbunden)
- [ ] `connect localhost:30120`, Charakter anlegen, `/hallo` testen
- [ ] Dich zum Admin machen (`add_principal` in `server.cfg`, Abschnitt "Admin-Rechte"), `/admin` testen
- [ ] License Allowlist in txAdmin einschalten ([linux-server.md](linux-server.md#nur-freunde-zulassen-license-allowlist))
- [ ] Ein Freund verbindet sich, im LAN und über das Internet
- [ ] Fehlermeldungen und Abweichungen notieren, danach "Bekannte Grenzen" in [entscheidungen.md](entscheidungen.md) aktualisieren
- [ ] CI-Lauf der letzten Pushes auf GitHub ansehen (Actions-Tab)

## Phase 1: Vorhandenes im Spiel testen

Das Qbox-Rezept bringt schon eine komplette Grundlage mit ([frameworks.md](frameworks.md#was-installiert-ist)).
Ziel dieser Phase: wissen, was funktioniert, bevor etwas geändert wird.

- [ ] **Charakter:** Erstellung und Kleidung (illenium-appearance), Spawn-Auswahl (qbx_spawn), Apartment (qbx_properties)
- [ ] **Inventar:** Items haben Bilder und deutsche Namen, Shops verkaufen, Kofferraum und Handschuhfach
- [ ] **Geld:** Bank und Geldautomaten (Renewed-Banking), Gehalt kommt (Standard alle 10 Minuten)
- [ ] **Fahrzeuge:** Händler, Garage, Schlüssel, Tanken, Schaden, Gurt, Tuning
- [ ] **Handy:** npwd öffnet, Anrufe zwischen zwei Spielern, Garagen- und Mail-App
- [ ] **Sprache:** pma-voice Reichweiten, Funk (mm_radio), Doppelbelegung der linken Alt-Taste
      ([frameworks.md](frameworks.md#prüfen-und-fehlersuche))
- [ ] **Jobs:** je einmal anstempeln und arbeiten: Taxi, Bus, Trucker, Müll, Abschlepper, Mechaniker
- [ ] **Solo-Tätigkeiten:** Recycling (`qbx_recyclejob`), Weinberg (`qbx_vineyard`), Tauchen (`qbx_diving`): Macht
      das allein Spaß? Grundlage für [Solo-Aktivitäten](#solo-aktivitäten)
- [ ] **Behörden:** Polizei (Handschellen, Gefängnis per xt-prison), Rettungsdienst (Wiederbelebung, Krankenhaus)
- [ ] **Kriminalität:** Ladenüberfall (Kasse und Tresor), Weed anpflanzen und ernten, Straßenverkauf, Dealer per
      `/newdealer` anlegen und eine Lieferung fahren, Auto mit Dietrich öffnen, Hehler, Alarm kommt bei der Polizei an
- [ ] **Admin:** qbx_adminmenu, txAdmin (Kick, Bann, Teleport, Spawn von Fahrzeugen)
- [ ] **Leistung:** `resmon` im Client (F8), Server-Auslastung im txAdmin-Dashboard; Ressourcen mit dauerhaft hoher Last notieren
- [ ] **Beschriftungen mit echten Produktnamen** notieren (Items, Shops, Handy), siehe [inhalte-regeln.md](inhalte-regeln.md#fremd-ressourcen-prüfen)

## Phase 2: Entscheiden und aufräumen

- [ ] [Offene Entscheidungen](#offene-entscheidungen) beantworten
- [ ] Rezept-Fehler beheben: Item `markedbills` fehlt ([Phase 6](#fehler-und-lücken))
- [ ] Ressourcen entfernen, die nach dem Test in Phase 1 nicht passen. Die kriminellen Ressourcen bleiben
      (Entscheidung vom 13.09.2026). Mögliche Kandidaten: `qbx_fireworks`, `qbx_diving`/`qbx_divegear`, eine der
      beiden Renn-Ressourcen `qbx_lapraces` und `qbx_streetraces`.
      So geht's: Zeile in `resources.txt` löschen, Ordner unter `[vendor]` von Hand löschen (kein Lauf entfernt
      ihn), bei SQL-Dateien vorher `setup-database --dry-run` prüfen. Die Tabellen bleiben in der Datenbank.
- [ ] Stand festhalten, bevor Anpassungen beginnen: Tags bzw. feste Release-URLs statt `main` und
      `releases/latest` ([ressourcen.md](ressourcen.md#fester-stand-oder-immer-aktuell)), zuerst für alles, was
      über Weg B oder C angepasst wird
- [ ] Sichtbare echte Produktnamen über Sprachdateien oder `label` ersetzen (Weg B/C, interne Item-Schlüssel bleiben)
- [ ] `hello-world` und den `/hallo`-Hinweis in `qbx:motd` entfernen, wenn Phase 0 abgeschlossen ist

## Phase 3: Identität und Community

- [ ] Projektname festlegen (keine Rockstar-, FiveM- oder Lore-Marken im Namen): `sv_projectName`, `sv_hostname`
- [ ] Pflicht-Hinweis mit dem neuen Namen in `sv_projectDesc` (`server.cfg`), Betreiber und Kontakt-E-Mail per
      `sets sv_projectDesc` in `secrets.cfg` ([inhalte-regeln.md](inhalte-regeln.md#erlaubt-lore-marken-und-eigene-designs))
- [ ] Eigenes Logo: Server-Icon 96x96 PNG (`load_server_icon`), Ladebildschirm-Logo (Weg B für `loadscreen`) und Farben (`loadscreen:*`-Convars)
- [ ] Begrüßung `qbx:motd` und Chat-Meldungen
- [ ] Regelwerk für Roleplay (kurz: Charakter spielen, kein Powergaming/Metagaming, Umgang bei Streit), als Seite in `docs/` oder im Discord
- [ ] **Entscheidung** Discord ja/nein: Link in `qbx:discordLink`, Freigabe-Anfragen der Allowlist dort abwickeln
- [ ] Festlegen, wer Allowlist-Anfragen freigibt und wer txAdmin-Admin ist

## Phase 4: Realismus, Grundsystem

| Punkt | Umsetzung |
|-------|-----------|
| [ ] Tacho in km/h | `qbx_hud/config/client.lua`: `useMPH = false`, laut Kommentar zusätzlich die Einheit in `styles.css` ändern (Weg C, Fork); entfällt, falls ein eigenes HUD `qbx_hud` ersetzt |
| [ ] Hunger und Durst | `qbx_core/config/server.lua`: `hungerRate` (4.2), `thirstRate` (3.8) (Weg C) |
| [ ] Startgeld | `qbx_core/config/server.lua`: `moneyTypes = { cash = 500, bank = 5000, crypto = 0 }`, **Entscheidung** Wirtschaft |
| [ ] Gehälter | Intervall `paycheckTimeout` (10 min) und `paycheckSociety` in `qbx_core/config/server.lua`, Beträge pro Rang in `shared/jobs.lua` |
| [ ] Preise | Shops in `ox_inventory/data/shops.lua` (Weg B), Fahrzeuge in `qbx_core/shared/vehicles.lua` (Weg C), Sprit in der Config von `ox_fuel` |
| [ ] Autohaus-Sortiment | nur GTA-Fahrzeuge, Kategorien und Händler-Standorte in `qbx_vehicleshop/config/shared.lua` (Weg C, Fork) |
| [ ] Fahrverhalten | eigene Ressource `[local]/handling` mit angepasster `handling.meta` (`data_file 'HANDLING_FILE'`), klein genug für Git (Weg D) |
| [ ] Schaden, Gurt | Configs von `vehiclehandler` und `qbx_seatbelt` testen und abstimmen |
| [ ] Wetter und Uhrzeit | Tageslänge und Wetterwechsel in `Renewed-Weathersync` |
| [ ] Verkehr und Passanten | Dichte über `qbx_density` |
| [ ] Sprachreichweite | `voice.cfg` |
| [ ] Ausweis, Führerschein | `qbx_cityhall` und `qbx_idcard` testen; Fahrschule gibt es im Rezept nicht, später eigene Ressource |
| [ ] Rechnungen, Bußgelder | Bußgelder: `qbx_police` bucht vom Bankkonto auf das Konto `police`. Rechnungen von Firmen (Restaurant, Werkstatt): prüfen, ob `Renewed-Banking` das kann, sonst eigene Ressource |
| [ ] Später: Versicherung, Kfz-Steuer, Hauptuntersuchung | eigene Ressource(n), Abbuchung über Renewed-Banking, Stand in eigener Tabelle (Zeile in `database.txt`) |

## Phase 5: Arbeitswelt und Firmen

### Vorhandene Jobs anpassen

- [ ] Gehälter, Ränge und deutsche Rangnamen in `qbx_core/shared/jobs.lua` (Weg C)
- [ ] Chef-Menü und Firmenkonten testen (`qbx_management`, Renewed-Banking)

### Restaurants (Lore-Ketten)

Kandidaten aus dem GTA-Universum: Burger Shot, Cluckin' Bell, Bean Machine, Pizza This, Up-n-Atom. Prototyp ist
**Burger Shot**, die anderen folgen demselben Aufbau mit eigener Config.

Umsetzung als **eine eigene Ressource** `[local]/restaurants` mit einer Config pro Laden (Weg D). Vorlage zum
Lesen: [y_burgershot](https://github.com/TonybynMp4/y_burgershot) (Qbox, ox_lib, ox_target, ox_inventory; letzter
Push Mai 2024, Lizenz GPL-3.0: übernommener Code macht die eigene Ressource ebenfalls GPL-3.0).

- [ ] **Standort:** Viele Restaurants haben im Basisspiel keinen begehbaren Innenraum. **Entscheidung** zwischen
      Außenstellen/Food-Trucks, einem bestehenden Innenraum oder einem Innenraum-Mod (Lizenz, Größe, Weg E)
- [ ] **Job:** `burgershot` mit Rängen (Aushilfe, Koch, Schichtleitung, Chef mit `isboss`) in `shared/jobs.lua`,
      siehe [Stolperfalle](#stolperfalle-eigene-jobs-und-cleanplayergroups)
- [ ] **Items:** Zutaten, Gerichte, Getränke, Menü-Tüte in der eigenen `items.lua` (Weg B), eigene Bilder als
      einzelne `copy`-Zeilen hinter der `qbx_invimages`-Zeile (die Ordner-Zeile ersetzt den Bilder-Ordner komplett)
- [ ] **Zutaten-Einkauf:** Lieferanten-Shop in `ox_inventory/data/shops.lua`, nur für den Job (`groups`)
- [ ] **Stationen:** `ox_target`-Zonen an Grill, Fritteuse, Getränke; `lib.progressBar` mit Animation; der Server
      prüft Job, Dienststatus, Zutaten und Entfernung und tauscht dann die Items.
      Einfachere Alternative: Werkbänke über `ox_inventory/data/crafting.lua`
- [ ] **Lager:** Kühlraum und Ausgabe-Tablett als Stash (`exports.ox_inventory:RegisterStash`)
- [ ] **Verkauf an Spieler:** Kasse mit Rechnung, Einnahmen auf das Firmenkonto (Renewed-Banking)
- [ ] **Verkauf ohne Spieler:** NPC-Bestellungen oder Lieferfahrten, damit die Firma auch in kleiner Runde Geld
      verdient
- [ ] **Drumherum:** Stempeluhr (Dienst an/aus), Blip auf der Karte, Türen (`ox_doorlock`), Arbeitskleidung
      (illenium-appearance), Wirkung der Gerichte auf Hunger/Durst
- [ ] **Texte** in `locales/de.json` der eigenen Ressource (`ox_lib`-Locale)

### Solo-Aktivitäten

Für Abende mit wenigen Spielern: Tätigkeiten, die ohne Mitspieler funktionieren und Rohstoffe für die Firmen liefern.
Umsetzung als **eine eigene Ressource** `[local]/aktivitaeten` mit einer Config pro Tätigkeit (Weg D), Aufbau wie bei
den Restaurants. Besser werden durch Übung: [Fähigkeiten](#fähigkeiten).

- [ ] **Vorhandenes zuerst:** Ergebnis der Solo-Tätigkeiten aus Phase 1 auswerten, nur die Lücken selbst bauen
- [ ] **Angeln:** Angelplätze (z. B. Del Perro Pier, Alamo Sea), Angel und Köder als Items, Biss als
      `lib.skillCheck`, Fische mit Seltenheit, Verkauf beim Fischhändler
- [ ] **Jagen:** Jagdgebiet (z. B. Paleto Forest, Mount Chiliad), Jagdgewehr als Waffe in `ox_inventory`, Wild aus
      dem Spiel, erlegtes Tier per `ox_target` ausnehmen, Fleisch und Felle verkaufen. Vorher testen, ob
      `qbx_density` auch die Tiere ausdünnt
- [ ] **Bergbau:** Steinbruch Davis Quartz, Spitzhacke, Gestein zu Metall schmelzen
- [ ] **Holz:** Sägewerk im Paleto Forest, Axt, Stämme zu Brettern verarbeiten
- [ ] **Scheine:** Angel- und Jagdschein als zusätzliche Einträge in `metadata.licences` (qbx_core legt dort `id`,
      `driver` und `weapon` an), setzen per `exports.qbx_core:SetMetadata(source, 'licences.hunting', true)`.
      Ausgabe über `qbx_cityhall` prüfen, sonst eigener Schalter. **Entscheidung** Pflicht ja/nein
- [ ] **Kreislauf:** Fisch und Fleisch als Zutaten für die Restaurants, Holz und Metall für Werkbänke
      (`ox_inventory/data/crafting.lua`). So hängen Solo-Spiel und Firmen zusammen
- [ ] **Server prüft:** Zone bzw. Entfernung, Werkzeug im Inventar, Abklingzeit pro Aktion. Items gibt nur der Server
      aus (`exports.ox_inventory:AddItem`), Preise stehen nur in der Server-Config. Das Minispiel läuft auf dem
      Client, deshalb begrenzen Abklingzeit und Zone die Ausbeute
- [ ] **Preise** nach **Entscheidung** Wirtschaft, Tageslimit gegen Dauerfarmen erwägen
- [ ] Freie Vorlagen nur mit passender Lizenz nutzen und vorher lesen: keine verschleierten Dateien, kein `load` mit
      Code aus `PerformHttpRequest`

### Fähigkeiten

Wer eine Tätigkeit oft macht, wird darin besser. Eine eigene Ressource `[local]/faehigkeiten` (Weg D) verwaltet die
Werte, Aktivitäten und Restaurants rufen sie über Exports auf. Die Restaurants funktionieren auch ohne sie und
bekommen die Anbindung später.

- [ ] **Liste:** Kochen, Angeln, Jagen, Bergbau, Holz, Handwerk. qbx_core führt schon `metadata.jobrep` (`tow`,
      `trucker`, `taxi`, `hotdog`) und `craftingrep`: vorher prüfen, welche Ressourcen diese Werte nutzen, damit
      nichts doppelt zählt
- [ ] **Speicher:** am Charakter in den Metadaten von qbx_core, keine eigene Tabelle. Einmal
      `SetMetadata(source, 'faehigkeiten', {})` anlegen, danach `SetMetadata(source, 'faehigkeiten.angeln', xp)`.
      Verschachteln geht nur eine Ebene tief und nur, wenn `faehigkeiten` schon eine Tabelle ist
- [ ] **Schnittstelle:** Server-Exports `AddXP(source, faehigkeit, menge)` und `GetLevel(source, faehigkeit)`
- [ ] **XP vergibt nur der Server**, nach denselben Prüfungen wie beim Item-Tausch. Kein Event, über das der Client
      selbst XP meldet
- [ ] **Stufen:** Level-Kurve mit steigendem XP-Bedarf und Obergrenze (z. B. Level 10) in der Config
- [ ] **Wirkung** nach **Entscheidung** Fähigkeiten: kürzere Fortschrittsbalken, leichtere `lib.skillCheck`, seltener
      Fehlschlag, mehr Ausbeute
- [ ] **Anzeige:** Eintrag im Radialmenü (`qbx_radialmenu`) oder Befehl öffnet ein `lib.registerContext`-Menü mit
      Fortschrittsbalken pro Fähigkeit, Hinweis beim Aufstieg per `lib.notify`
- [ ] **Admin-Befehl** zum Setzen und Zurücksetzen für Tests: `lib.addCommand` mit `restricted = 'group.admin'`
- [ ] **Texte** in `locales/de.json`

### Weitere Firmen (später, nach Bedarf)

- [ ] Werkstatt als Spielerfirma (Basis `qbx_mechanicjob`, `qbx_customs`)
- [ ] Autohaus mit Verkäufern statt reinem NPC-Händler
- [ ] Immobilienmakler (Basis `qbx_properties`)
- [ ] Lieferdienst/Spedition (Basis `qbx_truckerjob`)

## Phase 6: Behörden und Kriminalität

Entschieden am 13.09.2026: Kriminalität gehört wie die Berufe von Anfang an dazu.

### Was das Rezept mitbringt

Standardwerte, geprüft im Quellcode am 13.09.2026:

| Bereich | Ressource | Standard | Anmerkung |
|---------|-----------|----------|-----------|
| Ladenüberfall | `qbx_storerobbery` | 0 Polizisten nötig, Alarm mit 70 % Wahrscheinlichkeit (nachts 40 %) | Kasse 80–200 bar; Tresor: `markedbills` (**Item fehlt**, siehe unten), Uhren, Goldbarren |
| Juwelier | `qbx_jewelery` | 0 Polizisten, braucht `electronickit` | |
| Banken (Fleeca, Paleto, Pacific) | `qbx_bankrobbery` | 0 Polizisten | Beute `black_money` |
| Einbruch | `qbx_houserobbery` | **2 Polizisten im Dienst** | ohne Polizei nicht startbar |
| Geldtransporter | `qbx_truckrobbery` | **2 Polizisten im Dienst**, Startgebühr vom Konto, braucht Haftbombe | Beute `black_money` |
| Drogen-Anbau | `qbx_weed` | mehrere Weed-Sorten zum Anpflanzen | Ernte liefert die `weed_*`-Items |
| Drogen-Verkauf | `qbx_drugs` | Straßenverkauf (Weed, Koks, Crack, Meth), Lieferaufträge von Dealern | Dealer-Liste ist leer, Admins legen sie mit `/newdealer` an; mit Polizei im Dienst zahlen Lieferungen mehr |
| Hehler | `qbx_pawnshop` | kauft Schmuck, Uhren, Elektronik, schmilzt Gold zu Barren | |
| Autodiebstahl | `qbx_vehiclekeys` | Dietrich, verbesserter Dietrich, Carjacking mit Waffe | |
| Schrottplatz | `qbx_scrapyard` | Fahrzeuge verschrotten, Liste in der Config | |
| Gangs | `qbx_core` (`shared/gangs.lua`), `qbx_management` | 6 GTA-Gangs (Lost MC, Ballas, Vagos, Families, Triads, Cartel), Menü für Anführer | |
| Polizei | `qbx_police` | Alarme der Überfälle, Bußgeld vom Bankkonto auf das Konto `police`, Gefängnis per `xt-prison`, Spuren, Kennzeichen-Scanner, Kameras, Nagelbänder, Waffenschein ab Rang 2 | |
| NPC-Polizei | `qbx_smallresources` (`qbx_disableservices`) | Fahndungslevel 0, Einsatzdienste der NPCs aus | ohne Spieler-Polizei verfolgt niemand die Täter |

### Fehler und Lücken

- [ ] **Fehler im Rezept: Item `markedbills` fehlt.** `qbx_storerobbery` (Tresor) und `qbx_drugs` (bei
      `useMarkedBills = true`) vergeben es, aber weder die Rezept-Items noch qbx_core oder ox_inventory definieren
      es. Wie beim `cola`-Item ([frameworks.md](frameworks.md#abweichungen-vom-rezept)) legt ox_inventory dann
      nichts ab. Umsetzung: `markedbills` mit dem ersten Item-Override in die eigene `items.lua` aufnehmen (Weg B)
- [ ] **Geldwäsche fehlt:** `black_money` hat im Rezept keine Verwendung. Eigene Ressource `[local]/geldwaesche`
      (Weg D): Ort, Gebühr (z. B. 20–40 %), Tageslimit, Wartezeit; nimmt `black_money` und `markedbills` (Wert aus
      den Metadaten `worth`); der Server prüft alles und schreibt ein Log für Admins. Später auch über eigene Firmen
      (Umsatz im Restaurant)
- [ ] **Herstellung von Koks, Crack und Meth fehlt:** Der Straßenverkauf nimmt sie an, aber nichts im Rezept
      stellt sie her. Eigene Ressource mit Laboren, Zutaten und Arbeitsschritten (`ox_target`,
      `lib.progressBar`, Weg D) oder eine Fremd-Ressource
- [ ] **Illegaler Waffenhandel fehlt:** legal gibt es den Waffenladen (Ammunation aus den ox_inventory-Shops) und
      den Waffenschein über die Polizei. Schwarzmarkt als Shop mit Zugriffsbeschränkung (`groups`, Weg B) oder
      Händler an wechselnden Orten (Weg D)
- [ ] **Später:** Gang-Gebiete, Dispatch-Liste für die Polizei (heute nur Meldung und Blip), Anwälte
      (`qbx_police` kennt `lawyerJobs` und `lawyerPay`)

### Überfälle in kleiner Runde

Mit 0 Pflicht-Polizisten laufen Überfälle ohne Gegenspieler ab (schnelles Geld, wenig Spannung). Mit 2 sind
Einbruch und Geldtransporter die meiste Zeit gesperrt. Die Werte hängen an **Entscheidung** 1.

- [ ] Schwellen setzen (alles git-Ressourcen, Weg C):
  - `qbx_storerobbery/config/shared.lua`: `minimumCops`
  - `qbx_jewelery/config/server.lua`: `minimumPolice`
  - `qbx_bankrobbery/config/client.lua`: `minFleecaPolice`, `minPaletoPolice`, `minPacificPolice`, `minThermitePolice`
  - `qbx_houserobbery/config/server.lua`: `minimumPolice`
  - `qbx_truckrobbery/config/server.lua`: `numRequiredPolice`
- [ ] Vorschlag: kleine Überfälle (Laden, Einbruch) ab 0–1 Polizisten, große (Juwelier, Bank, Geldtransporter)
      ab 2; Beute und Abklingzeiten an die Wirtschaft anpassen
- [ ] Idee: **NPC-Fahndung**, wenn niemand im Dienst ist. Eine eigene Ressource gibt den Tätern nach einem Alarm
      ein GTA-Fahndungslevel, wenn `GetDutyCountType('leo')` 0 liefert. Dafür müssten `maxWantedLevel` und die
      Polizei-Dienste in `qbx_disableservices` wieder an (Weg C). Aufwand und Nebenwirkungen erst testen

### Behörden und Gangs

- [ ] Polizei (`qbx_police`): Ränge, Ausrüstung, Fahrzeuge, Türen der Wache (`ox_doorlock`), Bußgeldkatalog
- [ ] Rettungsdienst (`qbx_ambulancejob`, `qbx_medical`, Innenraum `pillbox`): Wiederbelebung, Behandlung, Kosten
- [ ] Ersatz, wenn niemand im Dienst ist: Selbst-Einweisung im Krankenhaus testen, sonst eigene Lösung
- [ ] Gefängnis (`xt-prison`), Texte sind nur englisch ([frameworks.md](frameworks.md#sprache))
- [ ] Gangs: Namen und Ränge in `qbx_core/shared/gangs.lua` (Weg C), eigene Gangs neben oder statt der GTA-Gangs;
      Anführer verwalten Mitglieder über `qbx_management`

## Phase 7: Umzug auf den Linux-VPS

- [ ] **Entscheidung** Anbieter und Budget. README: mindestens 2 vCPU und 4 GB RAM, mit Qbox, Datenbank und
      zusätzlichen Assets eher mehr; Ubuntu 24.04 x86_64
- [ ] `sudo bash scripts/linux/install.sh --enable-firewall`, Key in `secrets.cfg`, `systemctl start fxserver`
- [ ] txAdmin per SSH-Tunnel einrichten, Admins und Allowlist neu anlegen: sie liegen in `txData/` und kommen
      nicht über Git mit
- [ ] **Entscheidung** Datenbank: frisch starten (empfohlen, Testdaten bleiben lokal) oder Dump vom PC übernehmen
- [ ] Große Assets (Weg E) auf den Server bringen
- [ ] Deploy per GitHub Actions ([linux-server.md](linux-server.md#deploy-per-github-actions))
- [ ] Backups: Datenbank-Dump regelmäßig ([linux-server.md](linux-server.md#backup),
      [datenbank.md](datenbank.md#backup-und-wiederherstellung)), `txData/` mitsichern, **Wiederherstellung einmal testen**
- [ ] Geplante Neustarts im txAdmin-Scheduler (z. B. täglich morgens)
- [ ] Update-Routine: Backup, Stand im Manifest anheben, lokal testen, erst dann deployen

## Phase 8: Inhalte (Fahrzeuge, Kleidung, Karten)

Nur Lore-Marken und eigene Designs, keine echten Fahrzeuge oder Marken, auch nicht entbadged
([inhalte-regeln.md](inhalte-regeln.md)).

- [ ] Erst die Spielfahrzeuge ausschöpfen: Sortiment pro Händler kuratieren, Handling anpassen (Phase 4)
- [ ] Zusätzliche lore-freundliche Fahrzeuge nur mit Erlaubnis zur Nutzung, Größe und Texturen prüfen
- [ ] Zusätzliche Innenräume (Restaurants, Wache, Werkstatt) nach Bedarf aus Phase 5 und 6
- [ ] Eigene Kleidung (Firmen-Outfits mit eigenen Logos) über illenium-appearance
- [ ] **Weg E festlegen**, bevor die erste große Datei kommt. Git scheidet aus (GitHub blockt Dateien über
      100 MiB, LFS hat Kontingente). Optionen: von Hand bzw. per `rsync` nach `[vendor]` (gitignored, Liste der
      Pakete in einer committeten Datei), oder zip-Zeile auf einen eigenen Download-Speicher
- [ ] Bezahlte Ressourcen mit Asset Escrow sind an den Cfx.re-Account gebunden, dem der Lizenzschlüssel gehört;
      vor einem Kauf klären, welcher Account den Server-Key besitzt

---

## Offene Entscheidungen

| # | Frage | Warum wichtig | Vorschlag |
|---|-------|---------------|-----------|
| 1 | Wie viele Spieler sind realistisch gleichzeitig online, und wer spielt Polizei und Rettungsdienst? | Überfälle brauchen Gegenspieler, Schwellen in Phase 6 | Unter ca. 8: niedrige Polizei-Schwellen, Rollen abwechselnd besetzen, NPC-Fahndung prüfen |
| 2 | ~~Wie viel Kriminalität soll es geben?~~ | | **Entschieden 13.09.2026:** Berufe und Kriminalität von Anfang an, siehe Phase 6 |
| 3 | Wirtschaft locker oder hart? | Startgeld, Gehälter, Preise, Kosten für Autos und Wohnungen | Eher hart, damit Jobs Sinn haben; Werte nach 2 Wochen Spielzeit nachjustieren |
| 4 | Bezahlte Ressourcen (Tebex) ja oder nein, Budget? | Viele Innenräume und gute Jobs sind kostenpflichtig; Escrow bindet an einen Account | Zunächst nein, Lücken mit eigenen Ressourcen füllen |
| 5 | Wohin mit großen Assets (Weg E)? | Muss stehen, bevor Fahrzeuge oder Innenräume kommen | `rsync` nach `[vendor]` plus committete Paketliste |
| 6 | Handy bei npwd bleiben? | Wechsel später kostet Daten und Apps | Bleiben (aktiv gepflegt, letzter Push August 2026) |
| 7 | Projektname und Discord? | Pflicht-Hinweis, Logo, Allowlist-Ablauf | Name vor Phase 3 festlegen |
| 8 | Wann auf den VPS, welcher Anbieter? | Ohne erreichbaren PC kein gemeinsames Spielen | Sobald Phase 1 steht oder CGNAT den PC blockiert |
| 9 | Restaurants mit Innenraum-Mod oder ohne? | Größe, Lizenz, eventuell Kosten | Prototyp ohne Mod (Außenstelle/Food-Truck), später entscheiden |
| 10 | Wie stark wirken Fähigkeiten? | Neue Spieler dürfen nicht abgehängt werden | Nur schneller und mehr Ausbeute, nichts hinter einem Level sperren, kein Verfall |
| 11 | Angel- und Jagdschein Pflicht? | Realismus gegen Einstiegshürde | Ja, aber günstig; kontrolliert wird nur, wenn es Polizei gibt |

## Quellen der technischen Angaben

Geprüft am 13.09.2026 im Quellcode bzw. über die GitHub-API:

- qbx_core v1.24.0: `server/groups.lua` (`CreateJob`, `CreateJobs`, `UpsertJobData`),
  `server/storage/players.lua` (`cleanPlayerGroups` beim Start), `config/server.lua` (Geld, Gehalt, Hunger/Durst),
  Release-Asset `qbx_core.zip`
- qbx_hud `config/client.lua` (`useMPH`), Releases von qbx_hud, qbx_garages, qbx_vehicleshop
- `scripts/linux/lib.sh` und `scripts/windows/install-resources.ps1` (`git pull --ff-only` bei `--update`)
- project-error/npwd (nicht archiviert, letzter Push 05.08.2026), TonybynMp4/y_burgershot (GPL-3.0, letzter Push 11.05.2024)
- qbx_core `server/player.lua` auf `main`: `SetMetadata`/`GetMetadata` (eine Ebene verschachtelt, speichert sofort),
  Standard-Metadaten `licences` (`id`, `driver`, `weapon`), `jobrep`, `craftingrep`
- Kriminalität (Stand `main` vom 09.07. bzw. 07.09.2026): Configs und Server-Code von `qbx_storerobbery`,
  `qbx_bankrobbery`, `qbx_jewelery`, `qbx_houserobbery`, `qbx_truckrobbery`, `qbx_drugs`, `qbx_weed`,
  `qbx_pawnshop`, `qbx_police`, `qbx_vehiclekeys`, `qbx_management` (README), `qbx_smallresources`
  (`qbx_disableservices`); `markedbills` gesucht in Rezept-`items.lua`, qbx_core v1.24.0 und dem aktuellen
  ox_inventory-Release
