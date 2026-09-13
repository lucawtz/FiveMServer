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
| M7          | Freizeit: Rennen, Verleih, Kino, Arcade, Paintball und weitere kostenlose Minispiele | 9 |

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
  Für qbx_core ist das seit 13.09.2026 umgesetzt (Befunde 10 und 11), `resources.txt` enthält die Zeile oben.
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
      `cleanPlayerGroups` bleibt an und räumt weiter auf. Die Datei liegt schon als
      `[local]/[overrides]/qbx_core_jobs.lua` bereit, dort neue Jobs ergänzen.
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
- [x] Key in `server-data\secrets.cfg` eintragen (13.09.2026, Anmeldung beim Start erfolgreich)
- [x] `start.bat`, txAdmin mit "Existing Server Data" einrichten (13.09.2026, alle Ressourcen starten, Datenbank verbunden)
- [ ] `connect localhost:30120`, Charakter anlegen, `/hallo` testen
- [ ] Dich zum Admin machen (`add_principal` in `server.cfg`, Abschnitt "Admin-Rechte"), `/admin` testen
- [ ] License Allowlist in txAdmin einschalten ([linux-server.md](linux-server.md#nur-freunde-zulassen-license-allowlist))
- [ ] Ein Freund verbindet sich, im LAN und über das Internet
- [ ] Fehlermeldungen und Abweichungen notieren, danach "Bekannte Grenzen" in [entscheidungen.md](entscheidungen.md) aktualisieren
- [x] CI-Lauf der letzten Pushes auf GitHub ansehen (Actions-Tab), 13.09.2026: alle 6 Läufe grün
- [x] Repo öffentlich gemacht (13.09.2026), Historie vorher auf Geheimnisse geprüft

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

### Befunde aus dem ersten Spieltest (13.09.2026)

Notiert von Luca beim ersten Einloggen, Ursachen noch nicht untersucht.

| # | Bereich | Beobachtung | Soll |
|---|---------|-------------|------|
| 1 | Einstieg | Nach dem Verbinden gibt es keine Anleitung. | Neue Spieler bekommen zuerst eine Einführung, in der alles verständlich erklärt ist (siehe Phase 3). |
| 2 | Charakter | Die Charakterauswahl funktioniert, wirkt aber unstrukturiert. | Übersichtlicher Ablauf bei Auswahl und Erstellung. |
| 3 | Apartment | Spawn-Ort und Apartment lassen sich auswählen, danach zeigt die Karte aber viele Apartments als eigenes Eigentum an. | Nur ein Apartment wählbar, und nur dieses gehört dem Spieler. |
| 4 | Apartment | Beim Verlassen des Gebäudes landet man im Aufzug und muss mehrmals rein und raus, bis man draußen ist. Im Aufzug gibt es keine Möglichkeit auszuwählen, wohin man fahren will. | Ein Ausgang, der direkt nach draußen führt. Wo ein Aufzug zu sehen ist, lässt sich das Ziel auswählen (z. B. Wohnung, Eingang, Garage). |
| 5 | Waffenladen | Im Ammu-Nation steht kein NPC, bei dem man eine Waffe kaufen kann. | Verkäufer bzw. Shop-Punkt vorhanden, Kauf möglich. |
| 6 | Bedienung | Beim Parken steht der Hinweis "E - Garage öffnen" klein am rechten Bildschirmrand und fällt nicht auf. | Bei allen Interaktionen ist der Hinweis sofort sichtbar, z. B. unten mittig und deutlicher hervorgehoben. |
| 7 | Fahrzeughändler | Nach der Probefahrt beim Premium Deluxe Motorsport liegt der Charakter tot vor dem Eingang. | Nach der Probefahrt steht man unverletzt am Händler, das Testfahrzeug ist weg. |
| 8 | Fahrzeug | Im Auto sieht man nicht, welche Tasten es gibt und was man machen kann. | Im Fahrzeug eine Übersicht der Tasten und Möglichkeiten, am besten ausklappbar. |
| 9 | Bedienung | Benachrichtigungen oben rechts (z. B. "Das Inventar wurde erfolgreich geladen") sind gut, aber zu klein und verschwinden zu schnell. | Größere Schrift und Box, länger sichtbar, sodass man sie in Ruhe lesen kann. |
| 10 | Geld | Bargeld und Kontostand sind nirgends zu sehen. | Geld jederzeit ablesbar, dauerhaft im HUD oder auf Tastendruck. |
| 11 | Geld | Alle 10 Minuten kommt Gehalt, obwohl man nichts macht und keinen Beruf gewählt hat. Unklar, wofür. | Klar erkennbar, wofür Geld kommt. **Entscheidung**, ob es ein Grundeinkommen ohne Job gibt. |
| 12 | Fahrzeughändler | Die Restzeit der Probefahrt steht nur in Sekunden da ("Verbleibende Zeit der Probefahrt:293"), ohne Leerzeichen, mitten über dem Auto. | Anzeige als Minuten und Sekunden (4:53), gut lesbar am Bildschirmrand. |
| 13 | Rettungsdienst | Am Boden steht nur "Du blutest aus in: 27 Sekunden", man kann nichts tun und keinen Notruf absetzen. | Am Boden lässt sich jederzeit ein Notruf absetzen, gut sichtbar mit Taste, und er erreicht auch jemanden. |
| 14 | Charakter | In der Charaktererstellung lässt sich unter "Ped" ein Tiermodell wählen (z. B. `a_c_cat_01`). Danach ist keine Figur im Bild, rechts steht weiter "mp_m_freemode_01", unter "Aussehen" gibt es nur noch "Haare", und fast alle Kleidungsteile zeigen "0 / -1" (bei "Ketten" sogar "-1 / -1"). | Andere Modelle, auch Tiere, funktionieren: Die Figur ist im Bild, die Anzeige stimmt, das Menü zeigt nur Kategorien mit echter Auswahl, und der Charakter lässt sich speichern und normal spielen. |

- [ ] Befunde 3 bis 5 untersuchen (Ursache in `qbx_properties`, `qbx_spawn` bzw. den Shops von `ox_inventory`)
  - Befund 3: In der Datenbank gehört dem Charakter nur ein Apartment. `qbx_properties`
    (`client/property.lua`) setzt aber für jede Apartment-Option ein grünes Haus-Symbol, bei allen Spielern.
    Änderung nur im Code möglich, das Repo hat keine Releases: Fork nötig (Weg C).
  - Befund 4: Apartment `4IntegrityWayApt30`, der Ausgang setzt den Spieler auf den Eingangspunkt
    `-47.52, -585.86, 37.95` aus `config/shared.lua`. Ob dieser Punkt im Aufzug liegt, im Spiel prüfen.
    `qbx_properties` hat **keine Aufzug-Steuerung**, die Knöpfe im Aufzug sind Deko aus GTA. Es gibt nur feste
    Punkte mit kleinem 3D-Text (`qbx.drawText3d`): draußen "[E] - Objekt anzeigen" im Umkreis von 1,6 m um den
    Eingang, drinnen "[E] - Verlassen | [G] - Verwalten" im Umkreis von 1,5 m um `exit` (bei Apt30
    `-17.41, -588.17, 90.11`). Wer daneben steht, sieht keine Auswahl. Beim Anlegen kopiert
    `server/apartmentselect.lua` Eingang (`enter`) und Innenpunkte als JSON in die Tabelle `properties`
    (`coords`, `interact_options`), und `exitProperty` liest den Eingang von dort. Eine geänderte Config gilt
    also nur für neue Apartments, bestehende brauchen eine SQL-Datei über `database.txt`.
    Mögliche Lösung: Eingangspunkt vor das Gebäude legen (Fork, Weg C) und bestehende Einträge per SQL
    nachziehen. Eine echte Zielauswahl im Aufzug (Wohnung, Eingang, Garage) wäre eine eigene Ressource mit
    `ox_target`-Zone und `lib.registerContext` (Weg D).
    - [ ] Im Spiel prüfen: In welchem Aufzug stehst du (nach dem Verlassen oder direkt nach dem Spawn),
          erscheint dort irgendein Text, und wie kommst du am Ende heraus? Koordinaten über das Admin-Menü (`/admin`) notieren.
  - [x] Befund 5: Der Ammunation hatte nur eine unsichtbare Zielzone an der Theke (linke Alt-Taste). Eigene
    `shops.lua` mit Verkäufern (Weg B), im Spiel testen. Pistole braucht den Waffenschein (`licences.weapon`).
- [ ] Logs vom 13.09.2026 auswerten (Server: `txData/default/logs/fxserver.log`, Client:
      `%LOCALAPPDATA%\FiveM\FiveM.app\logs\CitizenFX_log_*.log`). Nach Wichtigkeit:
  - **Handy (npwd):** Server meldet beim Anlegen des Charakters `Cannot read properties of null (reading
    'getIdentifier')` in `handleUnloadPlayerEvent`. Im Client bei jedem Öffnen `reading 'map'`,
    `Settings Schema was invalid, applying default settings` und für `npwd_qbx_mail` und `npwd_qbx_garages`
    `Cannot use import statement outside a module`, danach aber "Successfully loaded". Im Spiel prüfen, ob
    Mail- und Garagen-App funktionieren und Einstellungen gespeichert bleiben.
  - **Serverliste:** wiederholt `failed to store server`. Vermutlich erreicht die Serverliste den Server von außen
    nicht (Port 30120 nicht freigegeben oder CGNAT). Lokal harmlos, wichtig für "Ein Freund verbindet sich" in Phase 0.
  - **Probefahrt (Befund 7):** Etwa 14:28, kurz vor dem Verlassen, meldet der Client
    `[entity] GetNetworkObject: no object by ID 65534`. Zeitlich passend zum Ende der Probefahrt, Zusammenhang offen.
  - **Zonen:** `attempted to remove a zone that does not exist (id: nil)` (ox_lib), Ressource unbekannt, etwa
    10 Minuten nach dem Einloggen.
  - **Chat:** `Cannot read properties of undefined (reading 'replace')` in `chat/dist/chat.js` direkt nach dem
    Verbinden. Prüfen, ob Chat und `qbx_chat_theme` normal funktionieren.
  - **Deutsche Texte fehlen:** `could not load 'locales/de.json'` bei `xt-prison`, `npwd_qbx_garages` und
    `npwd_qbx_mail`, dort erscheint Englisch. Übersetzung per Override (Weg B/C), siehe Phase 2.
  - **Harmlos:** `ultra-voltlab` meldet `failed loading ... dlchei4_game.dat` (die Dateien liegen als `.dat151`
    bzw. `.dat54` vor, Sound im Hacking-Spiel prüfen). `server thread hitch warning` und langsame
    `CREATE INDEX`-Abfragen nur beim Start. Hinweise von `qbx_entitiesblacklist` und `qbx_staticemitters` sind
    gewollt. Den Qbox-Begrüßungstext blendet `set qbx:acknowledge "true"` in `server.cfg` aus.
  - **Schon behoben:** `No such command password=...` und `sv_endpointPrivacy` kamen nur beim ersten Start um
    13:31, beim Neustart um 13:41 nicht mehr.
- [x] Befund 6: Der Hinweis ist die TextUI von `ox_lib` (`lib.showTextUI`), Standardposition `right-center`, ohne
      Convar. Etwa 45 Ressourcen nutzen sie (Garagen, Jobs, Shops, Türen, Überfälle), viele geben selbst
      `left-center` an. `ox_lib` steht jetzt fest auf v3.39.0, `[local]/[overrides]/ox_lib_textui.lua` ersetzt die
      Datei (Weg B): immer unten mittig, größere fette Schrift, etwas über dem Bildschirmrand. Seit dem 13.09.2026
      im neuen Stil statt mit blauem Rand links ([Plan](#einheitlicher-stil-und-eigenes-hud), Schritt 3).
  - [ ] Im Spiel testen: Garage, Kleidungsladen (illenium-appearance), ein Job. Überdeckt der Hinweis im
        Fahrzeug den Tacho von `qbx_hud`? Dann `marginBottom` in der Datei anpassen.
  - [ ] Interaktionen über `ox_target` (linke Alt-Taste) sind eine andere Anzeige, getrennt bewerten.
- [x] Befund 9: Die Meldungen kommen von `lib.notify` (`ox_lib`). Die Anzeigedauer ist 3 Sekunden, wenn die
      aufrufende Ressource keine `duration` mitgibt (`web/build`, `n.duration||3e3`). Die Position ist eine
      Client-Einstellung (`resource/settings.lua`), `qbx_core` schickt aber bei jeder Meldung ausdrücklich
      `top-right` mit (`config/shared.lua`). Einen Convar für Dauer, Größe oder Position gibt es nicht.
      `[local]/[overrides]/ox_lib_notify.lua` ersetzt die Datei (Weg B): immer oben mittig, ohne Angabe 7 Sekunden,
      Angaben von 1,5 bis 5 Sekunden werden auf 5 Sekunden verlängert, kürzere bleiben. Dunkle Fläche im neuen Stil,
      Beschreibung größer und heller, die Symbolfarben nach Typ (Fehler, Erfolg, Warnung) bleiben.
  - [ ] Übernehmen und im Spiel testen: [Plan](#einheitlicher-stil-und-eigenes-hud), Schritt 3.
- [x] Befunde 10 und 11: Ursache war zweierlei. `qbx_hud` zeigt Geld nur 2 Sekunden bei einer Änderung oder
      3,5 Sekunden nach `/cash` und `/bank`. Und jeder Charakter startet im Job `unemployed` ("Civilian",
      "Freelancer", `payment = 10`, `defaultDuty = true`), qbx_core zahlt alle 10 Minuten aufs Konto und meldet nur
      "Du hast dein Gehalt ... erhalten". Entschieden am 13.09.2026: Grundsicherung bleibt, aber erkennbar.
  - `qbx_core` steht jetzt fest auf dem Release-Zip v1.24.0 (Weg C). `[local]/[overrides]/qbx_core_jobs.lua`
    benennt den Job in "Arbeitslos"/"Arbeitsuchend" um, `[local]/[overrides]/qbx_core_config_server.lua` meldet
    "Grundsicherung erhalten: 10 $ aufs Konto" bzw. "Gehalt als Taxi erhalten: ..." für 7 Sekunden.
  - Eigene Ressource `[local]/spielerinfo` (Weg D): Panel rechts mit Beruf, Dienst, Einkommen, Zeit bis zur
    nächsten Zahlung, Bargeld und Konto. `F7` klappt es aus und ein, das Spiel merkt sich die Wahl.
  - [ ] Umstellen am PC: Server stoppen, Ordner `server-data\resources\[vendor]\[qbx]\qbx_core` löschen,
        `scripts\windows\install.bat` ausführen (lädt das Zip und kopiert die beiden Dateien), Server starten.
  - [ ] Im Spiel testen: Panel sichtbar und lesbar neben Benachrichtigungen und Minimap, Beruf "Arbeitslos",
        nach spätestens 10 Minuten die neue Meldung, Zeit und Kontostand zählen richtig. Danach einen Job
        annehmen (z. B. Taxi) und prüfen, ob Beruf, Dienst und Gehalt wechseln.
  - Übrig: Die übrigen Jobs und Ränge sind noch englisch (Phase 5), die Befehle `/cash` und `/bank` ebenso.
- [ ] Befund 12 beheben: `qbx_vehicleshop` (`client/main.lua`, `startTestDriveTimer`) zeichnet jeden Frame
      `locale('general.testdrive_timer')..math.ceil(...)` per `qbx.drawText2d` an `vec2(1.0, 1.38)` mit Größe
      0.5. Der deutsche Text hat kein Leerzeichen am Ende, der englische schon. Eine eigene Anzeige in
      `[local]/probefahrt` (Befund 7) könnte `m:ss` zeigen, die alte Zeile lässt sich von außen aber nicht
      abschalten, man sähe beide. Sauber nur im Code (Weg C, Fork, das Repo hat keine Releases): Format `m:ss`,
      Anzeige am Rand oder als kleines Panel. Mit dem Fork für das Autohaus-Sortiment (Phase 4) zusammenlegen.
- [x] Befund 7: Nach 5 Minuten (`testDrive.limit`, `endBehavior = 'return'`) setzt `qbx_vehicleshop`
      (`server/main.lua`) den Spieler per `SetEntityCoords` auf `returnLocation` `-32.77, -1095.75, 26.42` und
      löscht danach das Fahrzeug, ohne ihn vorher aussteigen zu lassen. Die genaue Todesursache steht in keinem
      Log, vermutlich reißt der Teleport den Charakter mit Tempo aus dem Auto. Fix ohne Fork: eigene Ressource
      `[local]/probefahrt` (Weg D) hält das Fahrzeug 3 Sekunden vor dem Ende an, lässt den Spieler aussteigen und
      macht ihn 8 Sekunden unverwundbar (`config.lua`).
  - [ ] Im Spiel testen: Probefahrt bis zum Ende mit Tempo durchfahren, Spieler steht danach lebend am Händler.
- [ ] Befund 13 beheben: Den Notruf gibt es schon, er ist nur fast nie sichtbar. `qbx_ambulancejob`
      (`client/setdownedstate.lua`, `handleLastStand`) zeigt "Drücke [G] für eine hilfeanfrage" nur, wenn
      mindestens ein Spieler mit Job-Typ `ems` im Dienst ist, und erst ab 300 Sekunden Restzeit (`laststandTimer`
      in `config/client.lua`, die Blutungszeit ist 360 Sekunden, `laststandReviveInterval` in `qbx_medical`).
      Ohne Sanitäter im Dienst erscheint nur der Countdown, wie im Screenshot. Beim Hinfallen geht außerdem
      automatisch "Zivilist Down" an alle Sanitäter im Dienst (`qbx_medical:server:onPlayerLaststand`), auch das
      verpufft ohne Sanitäter. Der Chat bleibt am Boden bedienbar (`qbx_medical`, `client/dead.lua`), `/911e
      <Text>` (Rettungsdienst) und `/911p <Text>` (Polizei) funktionieren also schon, sind aber nirgends erklärt.
      Ob das Handy (npwd) am Boden aufgeht, ist offen, weder `npwd` noch `qbx_npwd` prüfen den Zustand.
      Bei 5 bis 15 Spielern ist selten jemand im Rettungsdienst. Lösung über die
      [Leitstelle mit NPC-Diensten](#leitstelle-und-npc-dienste): am Boden immer ein deutlicher Hinweis "G: Notruf",
      ohne Sanitäter im Dienst kommt der NPC-Rettungsdienst. Die Anzeige von `qbx_ambulancejob` läuft weiter, zwei
      Texte übereinander vermeiden (eigene Anzeige an anderer Stelle oder Weg C).
  - [ ] Im Spiel prüfen: Handy am Boden öffnen und anrufen, `/911e` am Boden absetzen.
- [x] Befund 8: eigene Ressource `[local]/fahrzeughilfe` (Weg D). Im Fahrzeug erscheint links ein Panel mit den
      Tasten für Fahren, Fahrzeug und Weiteres, `F6` klappt es aus und ein, das Spiel merkt sich die Wahl. Die
      Tasten werden live ausgelesen, geänderte Belegungen stimmen also. Im Spiel testen, vor allem Symbol-Tasten
      (Leertaste) und die Position neben HUD und Minimap.
  - Dabei gefunden: "Motor an/aus" (`qbx_vehiclekeys`) hat keine Standard-Taste, weil `config.keySearchBind` in
    dessen Config fehlt. Die Hilfe zeigt "nicht belegt". Taste festlegen (Weg C) oder Spielern den Weg über
    Einstellungen > Tastenbelegung > FiveM erklären.
- [ ] Befund 14 beheben. Stand der Untersuchung im Code von illenium-appearance (zip, `releases/latest`):
  - Die Auswahl "Ped" ist in der Erstellung für **alle** Spieler an (`Config.NewCharacterSections.Ped = true` in
    `shared/config.lua`), und `shared/peds.lua` hat keine Einschränkung (`jobs`, `gangs`, `aces`, `citizenids`):
    Jeder neue Spieler kann jedes der rund 800 Modelle wählen, Tiere und Story-Figuren eingeschlossen. Das
    Ped-Menü `/pedmenu` ist dagegen auf `group.admin` begrenzt (`Config.PedMenuGroup`).
  - "0 / -1" ist kein Anzeigefehler: Die Grenzen kommen direkt aus `GetNumberOfPedDrawableVariations(...) - 1`
    (`game/customization.lua`). Tiermodelle haben diese Kleidungsplätze nicht, das Menü blendet sie aber nur für
    Gesicht und Kopf aus (Prüfung auf `mp_m_freemode_01`/`mp_f_freemode_01` im Web-Code), Kleidung und Accessoires
    bleiben sichtbar.
  - Die Kamera nutzt feste Abstände für einen Menschen (`constants.CAMERAS` in `game/constants.lua`, z. B. 2,2 m
    vor und 0,2 m über dem Mittelpunkt der Figur). Bei kleinen Tieren passt der Bildausschnitt nicht, im Spiel
    prüfen, ob die Katze nur außerhalb des Bildes oder hinter dem Menü steht.
  - Woher die Anzeige "mp_m_freemode_01" rechts neben "Model" kommt, ist offen (Standardwert im Web-Code oder
    Wert vor dem Wechsel).
  - Außerhalb des Menüs im Spiel testen, bevor Tiere für Spieler freigegeben werden: Speichern und erneutes
    Einloggen, Laufen, Fahrzeuge, Inventar, `ox_target`, Emotes, Waffen, Tod und Wiederbelebung (`qbx_medical`).
    Viele dieser Funktionen erwarten ein menschliches Modell.
  - Umsetzung über Weg B (Override von `shared/config.lua`, `shared/peds.lua` bzw. `game/constants.lua` und
    `game/customization.lua`), das Menü selbst liegt nur als gebautes `web/dist` vor. Wer welche Modelle wählen
    darf: **Entscheidung** 15.
- [ ] Befunde 1 und 2 bei der Planung von Phase 3 berücksichtigen

## Phase 2: Entscheiden und aufräumen

- [ ] [Offene Entscheidungen](#offene-entscheidungen) beantworten
- [ ] Rezept-Fehler beheben: Item `markedbills` fehlt ([Phase 6](#fehler-und-lücken))
- [ ] **Regelverstoß beheben:** `scully_emotemenu` streamt Props einer echten Marke (Pizza Hut): `bzzz_pizzahut_cup_a`,
      `bzzz_pizzahut_menu_a` und `bzzz_pizzahut_box_a` samt `bzzz_package_pizzahut.ytyp` in `stream/[Props]/[BzZzi]`,
      genutzt von drei Emotes in `shared/data/emotes/prop_emotes.lua`, geladen über eine `data_file`-Zeile in
      `fxmanifest.lua`. Die Ressource kommt per git von `main`, deshalb Weg C: eigener Fork mit festem Stand, dort die
      drei Emotes, die Dateien und die `data_file`-Zeile entfernen ([inhalte-regeln.md](inhalte-regeln.md))
- [ ] **Sport- und Supersportwagen sind nicht kaufbar:** In `qbx_vehicleshop/config/shared.lua` ist der Beispiel-Händler
      `luxury` auskommentiert, unter `vehicles.models` sind aber viele Modelle an ihn gebunden (z. B. `banshee`,
      `comet2`, `elegy`). Beheben zusammen mit dem Luxus-Autohaus in [Phase 4](#phase-4-realismus-grundsystem)
- [ ] Ressourcen entfernen, die nach dem Test in Phase 1 nicht passen. Die kriminellen Ressourcen bleiben
      (Entscheidung vom 13.09.2026). Mögliche Kandidaten: `qbx_fireworks` und, falls in
      [Phase 9](#phase-9-freizeit-und-minispiele) `cw-racingapp` gewählt wird, `qbx_lapraces`. `qbx_diving`/`qbx_divegear`
      und `qbx_streetraces` sind dort als Freizeit eingeplant.
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
- [ ] Einführung für neue Spieler direkt nach dem ersten Einloggen: verständliche Anleitung zu Steuerung, Handy,
      Jobs, Geld und Regeln (Befund 1 aus dem ersten Spieltest)
- [ ] Regelwerk für Roleplay (kurz: Charakter spielen, kein Powergaming/Metagaming, Umgang bei Streit), als Seite in `docs/` oder im Discord
- [ ] **Entscheidung** Discord ja/nein: Link in `qbx:discordLink`, Freigabe-Anfragen der Allowlist dort abwickeln
- [ ] Festlegen, wer Allowlist-Anfragen freigibt und wer txAdmin-Admin ist

### Einheitlicher Stil und eigenes HUD

Entschieden am 13.09.2026: Alle Oberflächen folgen einem Stil, ox_lib bleibt ohne Fork, oben rechts stehen Beruf und
Geld, Benachrichtigungen oben mittig. Farben, Schrift, Abstände und Gründe:
[entscheidungen.md](entscheidungen.md) unter "Einheitlicher Stil ohne Fork von ox_lib" und "Eigenes HUD statt
qbx_hud". Die Schritte bauen aufeinander auf.

- [ ] **1. Ist-Zustand festhalten**, vor dem nächsten `install.bat` und solange qbx_hud läuft. Screenshots bei
      1920 × 1080 und in einem kleineren Fenster (1366 oder 1600 breit): Minimap zu Fuß und im Fahrzeug (sind unter
      der Minimap Lebens- und Rüstungsbalken zu sehen?), `/bank`, eine Benachrichtigung, das Kontextmenü einer Garage,
      Scoreboard, Emote-Menü (F5), Stress nach einem misslungenen Dietrich. Die Freunde nach ihrer Auflösung fragen
      (**Entscheidung** 18).
- [x] **2. `ox_target:drawSprite 24`** in `ox.cfg` (Weg A, vorher 1 aus dem Rezept).
  - [ ] Im Spiel testen: Mit gehaltener Alt-Taste haben alle Zonen in der Nähe einen Kreis, die angezielte wird blau.
        In belebten Ecken (Krankenhaus, Wache) bleiben die FPS stabil, sonst auf etwa 8 senken, aber nie wieder 1.
- [x] **3. Benachrichtigungen und Interaktions-Hinweise im neuen Stil** (Weg B, Befund 6 und 9):
      `[local]/[overrides]/ox_lib_notify.lua` (neu) und `ox_lib_textui.lua`. Beide warnen in der F8-Konsole, wenn
      ox_lib nicht mehr v3.39.0 ist.
  - [ ] Übernehmen am PC: `scripts\windows\install.bat` ausführen (die `copy`-Zeilen laufen bei jedem Aufruf, kein
        Force nötig), Server neu starten.
  - [ ] Im Spiel testen: Meldung beim Einloggen (Inventar geladen, von ox_inventory), Gehalt (von qbx_core, das
        immer `top-right` mitschickt), zwei oder drei Meldungen zugleich bei offenem Kontextmenü einer Garage,
        Lesbarkeit vor hellem Himmel, Ankündigung aus txAdmin, Hinweis "E - Garage öffnen", F8-Konsole ohne rote
        Warnung. Im Fahrzeug überdecken sich Meldungen oben mittig mit Kompass und Straßennamen von qbx_hud, bis
        Schritt 8 erledigt ist. Bis dahin keinen Spieltest mit Freunden.
- [ ] **4. Farbe der ox_lib-Menüs** (Weg A, eigener Commit): `setr ox:primaryColor dark` und
      `setr ox:primaryShade 3` statt `blue` und `8`. Der Name muss exakt stimmen, ein Tippfehler legt alle
      ox_lib-Oberflächen lahm. Übernehmen: `ox.cfg` ändern, Server neu starten, neu verbinden (nie `restart ox_lib`).
      Testen: Fortschrittsbalken (Füllstand gegen die Spur erkennbar), Eingabedialog mit Checkbox, Auswahl und
      Bestätigen, Radialmenü. Wirkt der Bestätigen-Button deaktiviert oder der Balken zu blass, zurück zu `blue`/`8`.
- [ ] **5. Bildschirm-Aufteilung** in `entscheidungen.md` festhalten, in vh, damit sich die getrennten Ressourcen nicht
      überlagern: oben rechts Beruf und Geld (auch ausgeklappt oberhalb von etwa 28vh, das Scoreboard beginnt bei
      30vh), oben mittig Benachrichtigungen, links die Fahrzeug-Hilfe (32vh), neben der Minimap Status, darüber die
      Straße, unten rechts das Fahrzeug (über der Sprachanzeige von pma-voice und dem Handy-Rand von npwd), unten
      mittig Text-Hinweis (12vh), Fortschritt, Item-Meldungen von ox_inventory (20vh) und Texte per `drawText2d`.
- [ ] **6. `spielerinfo` als Kacheln oben rechts, `fahrzeughilfe` im neuen Stil** (Weg D): eingeklappt Bargeld,
      Konto und Beruf mit "Im Dienst", mit F7 zusätzlich Einkommen und nächste Zahlung, Geldänderungen kurz als
      +/- Betrag. Ressourcenname, F7-Befehl und gespeicherter Zustand bleiben. Manrope als woff2 mit `OFL.txt` in
      beiden Ressourcen. Testen gegen Scoreboard, Emote-Menü, Admin-Menü, Mitgliederliste von mm_radio und Ausweis.
- [ ] **7. Eigene Ressource `[local]/hud`, Stufe A** (Weg D), gebaut, während qbx_hud noch läuft. Nur eine Sitzung
      arbeitet daran. `ensure hud` in `server.cfg` nach `ensure spielerinfo` eintragen.
  - Server-Events `hud:server:GainStress` und `hud:server:RelieveStress` unter genau diesen Namen: nur positive
    Beträge, Anstieg auf etwa 10 begrenzt, Wert 0 bis 100 über `SetMetadata`, Ausnahme für Polizei wie im Original,
    keine Meldung bei jedem Anstieg. Solange qbx_hud läuft (`GetResourceState('qbx_hud') == 'started'`), tun sie
    nichts, beim Start erscheint eine rote Warnung. Stress-Effekte wie in qbx_hud (**Entscheidung** 16).
  - Status neben der Minimap: Gesundheit, Hunger und Durst immer, Rüstung und Stress nur über 0 (**Entscheidung** 19).
  - Fahrzeug unten rechts: km/h, Tank (rot ab 20 %), Gurt-Warnung, Schloss. Straße über der Minimap.
  - Minimap: Lebens- und Rüstungsbalken des Spiels ausblenden (Scaleform `minimap`), Sichtbarkeit zu Fuß nach
    **Entscheidung** 17. Nur mit neu verbundenem Client ohne qbx_hud testen, dessen `minimap.gfx` lädt beim
    Verbinden.
  - Ausblenden im Pausemenü und vor dem Einloggen, das Fahrzeug-HUD auch bei offenem Inventar, aber nicht bei jedem
    NUI-Fokus (Handy und Listen-Menüs sind auch während der Fahrt offen).
  - Testen in der Serverkonsole: `stop qbx_hud`, Stress durch Dietrich, Abbau durch Essen, Effekte bei 50 und 100,
    danach `start qbx_hud` (die eigenen Events halten sich zurück, kein doppelter Stress).
- [ ] **8. qbx_hud entfernen:** Zeile in `resources.txt` löschen, `+hud_menu` aus `fahrzeughilfe/config.lua`
      entfernen, Doku anpassen (`/cash` und `/bank` entfallen). Am PC Server stoppen, Ordner
      `server-data\resources\[vendor]\[qbx]\qbx_hud` von Hand löschen, starten. Zurück: Zeile wieder eintragen,
      `install.bat`, `ensure hud` auskommentieren.
- [ ] **9. Stufe B**, je Funktion ein Commit: Sprachanzeige (dann `setr voice_enableUi 0` in `voice.cfg`), Tempomat,
      Himmelsrichtung, Gang, Luft unter Wasser, optional Stress beim Schießen.
- [ ] **10. Zweiter Spieltest** mit den Freunden bei ihrer echten Auflösung, Ergebnisse als neue Befunde.

Später, nur bei Bedarf: `spielerinfo` und `fahrzeughilfe` in `hud` zusammenlegen (gespeicherte Zustände und
Tastenbelegungen prüfen). Menüs von ox_lib über eine Anpassung von `resource/client.lua` weiter angleichen, als
zeitlich begrenzter Versuch. ox_target auf festen Stand setzen und eine eigene `web/style.css` kopieren.

## Phase 4: Realismus, Grundsystem

| Punkt | Umsetzung |
|-------|-----------|
| [ ] Tacho in km/h | kommt mit dem eigenen HUD, das `qbx_hud` ersetzt ([Plan](#einheitlicher-stil-und-eigenes-hud), Schritt 7). Ein Fork von `qbx_hud` (`useMPH = false` plus Einheit in `styles.css`) entfällt |
| [ ] Hunger und Durst | `qbx_core/config/server.lua`: `hungerRate` (4.2), `thirstRate` (3.8) (Weg C) |
| [ ] Startgeld | `qbx_core/config/server.lua`: `moneyTypes = { cash = 500, bank = 5000, crypto = 0 }`, **Entscheidung** Wirtschaft |
| [ ] Gehälter | Intervall `paycheckTimeout` (10 min) und `paycheckSociety` in `qbx_core/config/server.lua`, Beträge pro Rang in `shared/jobs.lua` |
| [ ] Preise | Shops in `ox_inventory/data/shops.lua` (Weg B), Fahrzeuge in `qbx_core/shared/vehicles.lua` (Weg C), Sprit in der Config von `ox_fuel` |
| [ ] Autohaus-Sortiment | nur GTA-Fahrzeuge, Kategorien und Händler-Standorte in `qbx_vehicleshop/config/shared.lua` (Weg C, Fork). Den Händler `luxury` aktivieren (Sport- und Supersportwagen, siehe Phase 2) und als Luxus-Autohaus in den Vinewood Car Club legen: `bob74_ipl` lädt den Showroom schon (`MercenariesClub`, 1202, -3251, -50, unter der Karte), Eingang per Teleport aus einer eigenen Ressource (Weg D). Die auskommentierte Vorlage ist `type = 'managed'` (Kauf nur mit einem Spieler im Job `cardealer`) und hat Koordinaten in Rockford Hills: auf `free-use` umstellen, `zone` und `showroomVehicles` in den Club legen, `vehicleSpawns` und `returnLocation` draußen an die Oberfläche. Showroom-Fahrzeuge unterstützt `qbx_vehicleshop` bereits |
| [ ] Fehlende Fahrzeuge | Die Autos aus "A Safehouse in the Hills" fehlen in `qbx_core/shared/vehicles.lua` (901 Einträge in v1.24.0), obwohl Build 3751 sie enthält. Nachtragen per Override `[local]/[overrides]/qbx_core_vehicles.lua` mit `copy`-Zeile wie bei `qbx_core_jobs.lua`, Modellnamen vorher im Spiel prüfen. Das LS Car Meet (-2000, 1113, -25, lädt `bob74_ipl`) eignet sich als Treffpunkt für Autotreffen |
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
- [ ] **NPC-Fahndung**, wenn niemand im Dienst ist: siehe [NPC-Polizei](#leitstelle-und-npc-dienste)

### Behörden und Gangs

- [ ] Polizei (`qbx_police`): Ränge, Ausrüstung, Fahrzeuge, Türen der Wache (`ox_doorlock`), Bußgeldkatalog
- [ ] Rettungsdienst (`qbx_ambulancejob`, `qbx_medical`, Innenraum `pillbox`): Wiederbelebung, Behandlung, Kosten
- [ ] Ersatz, wenn niemand im Dienst ist: siehe [Leitstelle und NPC-Dienste](#leitstelle-und-npc-dienste)
- [ ] Gefängnis (`xt-prison`), Texte sind nur englisch ([frameworks.md](frameworks.md#sprache))
- [ ] Gangs: Namen und Ränge in `qbx_core/shared/gangs.lua` (Weg C), eigene Gangs neben oder statt der GTA-Gangs;
      Anführer verwalten Mitglieder über `qbx_management`

### Leitstelle und NPC-Dienste

Entschieden am 13.09.2026: Der Server ist nur für Luca und Freunde. Jede Rolle, die sonst ein Mitspieler
übernehmen müsste, bekommt einen NPC-Ersatz, damit man auch allein oder zu zweit spielen kann
([entscheidungen.md](entscheidungen.md#qbox-als-framework)). Grundregel für alle Dienste: **Spieler im Dienst
haben Vorrang, der NPC springt nur ein, wenn niemand im Dienst ist** (`exports.qbx_core:GetDutyCountType(typ)`).
Spieler-Dienste bekommen umgekehrt NPC-Einsätze, damit sie auch ohne Mitspieler etwas zu tun haben.

Umsetzung als **eine eigene Ressource** `[local]/leitstelle` mit einem Modul pro Dienst (Weg D). Sie nimmt alle
Notrufe an (Taste am Boden, Befehl `/notruf`, später eine App bzw. die Nummer im Handy) und verteilt sie.

Stand im Rezept, geprüft am 13.09.2026:

| Dienst | Spieler-Job im Rezept | NPC heute |
|--------|-----------------------|-----------|
| Rettungsdienst | `qbx_ambulancejob` (`ambulance`) | Selbst-Einweisung im Krankenhaus für 2000 $ (`checkInCost`), nur solange weniger als 2 Sanitäter im Dienst sind (`minForCheckIn`); Wiederbelebung gegen Gebühr nach Ablauf der Zeit |
| Polizei | `qbx_police` (`police`, Typ `leo`) | keine: `qbx_disableservices` setzt `maxWantedLevel = 0` und schaltet alle GTA-Einsatzdienste aus, nur Straßensperren sind an |
| Feuerwehr | **fehlt** (kein Job in `qbx_core/shared/jobs.lua`) | keine, GTA-Feuerwehr ist aus |
| Militär | **fehlt** | keine, Fort Zancudo nur als Spielgebiet |
| Abschleppdienst | `qbx_towjob` (`tow`) | nur NPC-Aufträge für den Spieler-Job (`/npc`), niemand holt das Auto eines Spielers ab |
| Mechaniker | `qbx_mechanicjob` | keine NPC-Werkstatt, Reparatur nur durch Spieler |

- [ ] **Leitstelle:** Notruf mit Art (Rettung, Polizei, Feuer, Panne) und Ort. Ist jemand im passenden Dienst,
      geht der Alarm mit Blip an ihn (wie heute `hospital:client:ambulanceAlert`), sonst übernimmt der NPC.
      Rückmeldung an den Anrufer ("Rettungswagen ist unterwegs, ca. 60 Sekunden"). Abklingzeit gegen Spam, der
      Server prüft Zustand und Ort
- [ ] **NPC-Rettungsdienst** (Befund 13): Rettungswagen fährt mit Sirene an, Sanitäter-Ped läuft zum Spieler,
      Animation, Wiederbelebung, Rechnung an das Konto `ambulance`. Bei langer Anfahrt oder unerreichbarem Ort
      (Wasser, Dach) Transport ins nächste Krankenhaus. Die Wartezeit darf nicht länger sein als die Blutungszeit
      (360 Sekunden)
- [ ] **NPC-Polizei:** nach einem Alarm (Überfall, Schüsse, Autodiebstahl) bekommen die Täter ein Fahndungslevel,
      wenn niemand im Dienst ist. Weg 1: GTA-Fahndung wieder an (`maxWantedLevel` und die Dienste in
      `qbx_disableservices`, Weg C), einfach, aber GTA-Polizei reagiert auch auf Kleinigkeiten und verhaftet
      nicht im Qbox-Sinn. Weg 2: eigene Streifen-Peds mit Verfolgung, Festnahme führt zu `xt-prison` bzw.
      Bußgeld. **Entscheidung** 12. Außerdem ein NPC-Bußgeld für Raser bzw. Blitzer denkbar
- [ ] **Feuerwehr (neu):** Spieler-Job `fire` in `[local]/[overrides]/qbx_core_jobs.lua` (Weg C) mit Wache,
      Fahrzeugen und Ausrüstung. Einsätze: brennende Fahrzeuge nach Unfällen, Brände an festen Orten (Feuer per
      `StartScriptFire`, der Server verteilt die Einsätze), Löschen mit Schlauch bzw. Löschfahrzeug. Ohne Spieler
      im Dienst löscht ein NPC-Löschzug. Vorlagen mit passender Lizenz suchen, bevor alles selbst gebaut wird
- [ ] **Militär (neu):** Fort Zancudo als Lore-Militär (San Andreas National Guard bzw. Merryweather), keine
      echte Armee wie die Bundeswehr ([inhalte-regeln.md](inhalte-regeln.md)). NPC-Wachen am Tor und Sperrgebiet,
      wer eindringt, wird gewarnt und dann bekämpft. Spieler-Job optional später. **Entscheidung** 13: nur
      NPC-Sperrgebiet oder auch spielbar
- [ ] **NPC-Abschleppdienst:** Panne oder Totalschaden melden, ein Abschlepper-NPC holt das Fahrzeug, es landet
      gegen Gebühr in der Garage bzw. auf dem Abschlepphof (prüfen, was `qbx_garages` dafür anbietet). Ist ein
      Spieler im Job `tow` im Dienst, bekommt er den Auftrag stattdessen
- [ ] **NPC-Mechaniker:** Werkstätten mit NPC, Reparatur gegen Geld und Wartezeit, teurer als ein
      Spieler-Mechaniker. Kosten in `qbx_mechanicjob/config/shared.lua` (`repairCost`) als Anhaltspunkt
- [ ] **Weitere Rollen mit NPC-Ersatz** (später): Taxi rufen, Anwalt und Richter für kleine Verfahren, Kunden und
      Lieferaufträge für die Firmen ([Restaurants](#restaurants-lore-ketten)), Verkäufer in Autohaus und
      Immobilien. Neue Ideen hier eintragen
- [ ] **Spieler-Dienste mit NPC-Einsätzen:** Polizei, Rettung, Feuerwehr und Abschlepper im Dienst bekommen
      zufällige NPC-Einsätze (Verletzte, Unfälle, Ladendiebe), damit der Job auch allein trägt
- [ ] **Leistung:** Peds und Fahrzeuge nur bei Bedarf erzeugen und danach löschen, Anzahl begrenzen, mit `resmon`
      prüfen

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
- [ ] **Villen und Penthouses als Immobilien:** `bob74_ipl` lädt auf Build 3751 schon die drei Villen aus
      "A Safehouse in the Hills" (Vinewood Residence, Richman Villa, Tongva Estate), acht GTA-Online-Hanghäuser, die
      Penthouses im Eclipse Tower und Michaels Villa. Kostenlos, keine zusätzlichen Assets. Dafür Innenraum-Einträge in
      `qbx_properties/config/shared.lua` (Weg C, mit dem Fork aus Befund 3 zusammenlegen), danach legt der Makler
      (Job `realestate`) sie per `/createproperty` mit Preis, optionaler Miete und Garagenpunkt an. Grenze:
      `qbx_properties` kennt keine Instanz, deshalb pro Villa nur ein Besitzer
- [ ] Kostenloses Zusatz-Haus: Vinewood House MLO von Horizon Development (MIT, etwa 11 MB, aus
      https://github.com/Bazsi0513/vinewood_house_mlo, ersetzt das Haus bei -1531, 434, 109)
  - [x] Am 13.09.2026 als git-Zeile in `resources.txt` eingetragen (`[vendor]/[assets]/vinewood_house_mlo`, startet
        über `ensure [assets]`). Texturnamen geprüft: Spieltexturen und neutrale Materialien (z. B.
        `Bricks066_1K_Color`), keine Markennamen. Innenraum mit Garage, Bad und zwei Zimmern.
  - [ ] Installieren am PC: `scripts\windows\install.bat` holt die neue Zeile (vorhandene Ressourcen bleiben), Server
        neu starten.
  - [ ] Im Spiel testen: Haus außen und innen, Texturen auf Logos und Schriftzüge ansehen, Kollision (nicht durch
        Boden oder Wände fallen). Die MLO ersetzt die Kartendateien `apa_ch2_12b` und `ch2_12b` des Spiels und die
        Verdeckung `apa_ch2_occl_00` für die ganze Umgebung. Deshalb auch die Nachbarhäuser und die Richman Villa aus
        `bob74_ipl` (-1630, 470, 128, rund 100 m entfernt) ansehen: keine Löcher, keine flackernden oder unsichtbaren
        Gebäude.
  - [ ] Bei Problemen: Zeile in `resources.txt` auskommentieren, Ordner `[vendor]\[assets]\vinewood_house_mlo`
        löschen, Server neu starten.
- [ ] Eigene Kleidung (Firmen-Outfits mit eigenen Logos) über illenium-appearance
- [ ] **Weg E festlegen**, bevor die erste große Datei kommt. Git scheidet aus (GitHub blockt Dateien über
      100 MiB, LFS hat Kontingente). Optionen: von Hand bzw. per `rsync` nach `[vendor]` (gitignored, Liste der
      Pakete in einer committeten Datei), oder zip-Zeile auf einen eigenen Download-Speicher
- [ ] Bezahlte Ressourcen mit Asset Escrow sind an den Cfx.re-Account gebunden, dem der Lizenzschlüssel gehört;
      vor einem Kauf klären, welcher Account den Server-Key besitzt

## Phase 9: Freizeit und Minispiele

Entschieden am 13.09.2026: **Minispiele nur kostenlos.** Grundlage sind installierte Ressourcen, GTA-Orte und eigene
Ressourcen in `[local]` (Weg D). Fremden Code nur mit freier Lizenz übernehmen (z. B. GPL-3.0, MIT), Repos ohne Lizenz
nur als Ideenvorlage. Keine fremden Filme, Musik oder Spiele ([inhalte-regeln.md](inhalte-regeln.md)).

Reihenfolge: Rennen und Verleih, Kino und Arcade, Gym und Fallschirmsprung, Paintball und Derby, Casino.

- [ ] **Rennen:** `qbx_lapraces` ist installiert, Start und Beitritt laufen aber über Events einer Handy-Racing-App, die
      fehlt. Kleines `ox_lib`-Menü bauen (Weg D) und in `config.lua` den Platzhalter `PUTCID` unter `Config.WhitelistedCreators`
      ersetzen (git-Ressource von `main`, also Weg C: fester Stand bzw. Fork). Alternative: `cw-racingapp` (GPL-3.0, Qbox-Bridge, Zeitrennen und Ranglisten, braucht
      `cw-performance`), nur eins von beiden. `qbx_streetraces` (Bargeld-Einsatz) braucht mindestens zwei Spieler.
      Allein spielbar: Zeitrennen
- [ ] **Kart- und Jetski-Verleih:** eigene Ressource mit Station per `ox_target`, Fahrzeug gegen Gebühr spawnen (Karts
      `veto`/`veto2`, Jetskis `seashark`), nach Rückgabe oder Ablauf der Zeit löschen, Strecken über das Rennsystem.
      Allein spielbar
- [ ] **Kino:** eigene Ressource `[local]/kino`: Kinosaal `v_cinema` per `RequestIpl` laden, Eingang per `ox_target`, auf
      der Leinwand die Rockstar-Kinoplaylists (z. B. `PL_CINEMA_CARTOON`, `PL_CINEMA_ACTION`), für alle im Saal
      gleichzeitig starten. Vorlage zum Lesen: `davedumas0/fiveM-movies` (GPL-3.0, von 2020, nicht gepflegt). Keine
      YouTube- oder Link-Player. Allein spielbar
- [ ] **Arcade:** Diamond Arcade, lädt `bob74_ipl` schon (2732, -380, -50): Eingang per Teleport, `ox_target` auf die
      Automaten, Spiele über `lib.skillCheck` oder eigene HTML-Spiele, Tickets als Item gegen kleine Preise. Vorlage:
      `thommie-arcade` (GPL-3.0, QBCore mit ps-ui). Keine fremden Spiele wie DOOM oder Pac-Man, die in der
      Standardliste von `rcore_arcade` und `mtc-arcade` stehen. Allein spielbar
- [ ] **Gym:** Trainingsgeräte an Muscle Beach per `ox_target`, Animation mit `lib.progressBar`, Wirkung nach
      [Fähigkeiten](#fähigkeiten). Vorlage: `dynyx-gym` (GPL-3.0). Allein spielbar
- [ ] **Fallschirmsprung:** Start per Teleport in die Höhe oder im NPC-Flugzeug, Fallschirm ausgeben, Landezone mit
      Punkten nach Abstand zur Mitte. Allein spielbar
- [ ] **Paintball:** eigene Ressource `[local]/paintball`: Arena als Zone (`lib.zones`) oder Innenraum in eigenem
      Routing-Bucket, Lobby per `ox_target`, Leih-Ausrüstung statt des eigenen Inventars, wenig Schaden, Treffer und
      Punkte zählt der Server, danach zurück mit der alten Ausrüstung. Optional NPC-Gegner für kleine Runden. Keine
      nachgebauten Maps aus anderen Spielen
- [ ] **Demolition Derby:** Arena-War-Arena per `RequestIpl` (2800, -3750, 125, nicht in `bob74_ipl`), eigene Ressource
      mit Runden und Wertung. Spieler beim Laden kurz einfrieren, sonst fallen sie durch die Bahn. Braucht Mitspieler
- [ ] **Casino:** Diamond Casino, lädt `bob74_ipl` schon: einfache eigene Spiele wie Blackjack oder Roulette über
      `ox_lib`-Menüs, nur mit Spielgeld, nie gegen Echtgeld. Allein spielbar
- [ ] **Darts:** einfache eigene Version mit `lib.skillCheck` an der Dartscheibe im Yellow Jack. Vorlage: `rz-dart`
      (GPL-3.0). Allein spielbar
- [ ] **Musik im Club:** nur eigene oder frei lizenzierte Musikdateien, z. B. über `xsound` (MIT). DJ- und
      Karaoke-Skripte mit YouTube oder Links scheiden aus (PLA 2.4)
- [ ] **Tauchen** ist schon installiert (`qbx_diving`), Angeln und Jagen stehen unter [Solo-Aktivitäten](#solo-aktivitäten)
- [ ] Im Spiel prüfen, ob die GTA-eigenen Minispiele (Golf, Tennis, Darts) in FiveM laufen. Offiziell belegt ist es
      nicht, alles spricht dagegen

**Kostenlos nicht möglich:** Bowling, Billard, Tischtennis, Minigolf und Prop Hunt. Dafür gibt es keine brauchbaren
freien Skripte, ein Eigenbau wäre sehr aufwendig (Ballphysik, bei Prop Hunt Runden- und Versteck-Logik). Golf ginge nur
als großer Eigenbau, das kostenlose `alberttheprince/FiveM-Golf` hat keine Lizenz und taugt nur als Ideenvorlage.

---

## Offene Entscheidungen

| # | Frage | Warum wichtig | Vorschlag |
|---|-------|---------------|-----------|
| 1 | Wie viele Spieler sind realistisch gleichzeitig online, und wer spielt Polizei und Rettungsdienst? | Überfälle brauchen Gegenspieler, Schwellen in Phase 6 | Niedrige Polizei-Schwellen; fehlende Rollen übernehmen NPCs ([Leitstelle](#leitstelle-und-npc-dienste), Grundsatz entschieden 13.09.2026) |
| 2 | ~~Wie viel Kriminalität soll es geben?~~ | | **Entschieden 13.09.2026:** Berufe und Kriminalität von Anfang an, siehe Phase 6 |
| 3 | Wirtschaft locker oder hart? | Startgeld, Gehälter, Preise, Kosten für Autos und Wohnungen | Eher hart, damit Jobs Sinn haben; Werte nach 2 Wochen Spielzeit nachjustieren |
| 4 | Bezahlte Ressourcen (Tebex) ja oder nein, Budget? | Viele Innenräume und gute Jobs sind kostenpflichtig; Escrow bindet an einen Account | Zunächst nein, Lücken mit eigenen Ressourcen füllen. **Minispiele entschieden 13.09.2026:** nur kostenlos ([Phase 9](#phase-9-freizeit-und-minispiele)) |
| 5 | Wohin mit großen Assets (Weg E)? | Muss stehen, bevor Fahrzeuge oder Innenräume kommen | `rsync` nach `[vendor]` plus committete Paketliste |
| 6 | Handy bei npwd bleiben? | Wechsel später kostet Daten und Apps | Bleiben (aktiv gepflegt, letzter Push August 2026) |
| 7 | Projektname und Discord? | Pflicht-Hinweis, Logo, Allowlist-Ablauf | Name vor Phase 3 festlegen |
| 8 | Wann auf den VPS, welcher Anbieter? | Ohne erreichbaren PC kein gemeinsames Spielen | Sobald Phase 1 steht oder CGNAT den PC blockiert |
| 9 | Restaurants mit Innenraum-Mod oder ohne? | Größe, Lizenz, eventuell Kosten | Prototyp ohne Mod (Außenstelle/Food-Truck), später entscheiden |
| 10 | Wie stark wirken Fähigkeiten? | Neue Spieler dürfen nicht abgehängt werden | Nur schneller und mehr Ausbeute, nichts hinter einem Level sperren, kein Verfall |
| 11 | Angel- und Jagdschein Pflicht? | Realismus gegen Einstiegshürde | Ja, aber günstig; kontrolliert wird nur, wenn es Polizei gibt |
| 12 | NPC-Polizei über GTA-Fahndung oder eigene Streifen? | GTA-Fahndung ist schnell gebaut, passt aber schlecht zu Gefängnis und Bußgeld | Erst GTA-Fahndung nur nach Alarmen testen, eigene Streifen, wenn es stört |
| 13 | Militär nur als NPC-Sperrgebiet oder auch als Spieler-Job? | Aufwand, wenig Einsätze in kleiner Runde | Erst NPC-Sperrgebiet Fort Zancudo |
| 14 | Was kosten NPC-Dienste? | Zu billig macht Spieler-Jobs sinnlos, zu teuer frustriert | Deutlich teurer als ein Spieler im Dienst, Werte mit Entscheidung 3 |
| 15 | Wer darf Tier- und NPC-Modelle als Charakter wählen (Befund 14)? | Heute jeder bei der Erstellung; Tiere können vieles im Spiel nicht (Fahrzeuge, Inventar, Waffen) | In der Erstellung nur die beiden Freemode-Modelle, Tiere und NPC-Figuren über `/pedmenu` bzw. freigegebene Gruppen in `peds.lua`, sobald sie im Spiel funktionieren |
| 16 | Stress im Spiel behalten? | Überfälle und Dietrich erzeugen Druck (Unschärfe ab 50, Hinfallen bei 100); ohne Ersatz der Events von qbx_hud geht er still verloren | Behalten wie in qbx_hud, Abbau durch Essen und Heilen; später prüfen, ob er mit der Zeit sinken soll ([Plan](#einheitlicher-stil-und-eigenes-hud)) |
| 17 | Minimap zu Fuß immer sichtbar? | qbx_hud zeigt sie nur im Fahrzeug, die geplanten Status-Kacheln sitzen daneben | Immer sichtbar, sonst brauchen die Kacheln einen anderen Platz |
| 18 | Mit welcher Auflösung spielen die Freunde? | Unter etwa 1880 Pixeln Breite berühren gestapelte Meldungen oben mittig das Kontextmenü von ox_lib | Abfragen; bei kleinen Bildschirmen Meldungen schmaler oder kürzer |
| 19 | Gesundheit statt Energie im Status? | Qbox kennt keine Energie, qbx_core zieht bei Hunger oder Durst 0 Gesundheit ab | Gesundheit, Hunger, Durst immer; Rüstung und Stress nur über 0; Energie streichen |

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
- Einheitlicher Stil und eigenes HUD (13.09.2026): ox_lib v3.39.0 `resource/interface/client/notify.lua`, `textui.lua`,
  `resource/settings.lua`, `resource/client.lua` (nur `primaryColor`/`primaryShade`), `web/src/features/notifications/NotificationWrapper.tsx`
  und `textui/TextUI.tsx` (Stil, Klasse `description`, Standarddauer 3000), Releases von ox_lib; qbx_core
  `config/shared.lua` (`notifyPosition`) und `client/functions.lua`; qbx_hud auf `main` (`server/main.lua` mit
  `hud:server:GainStress`/`RelieveStress`, `client/main.lua`, `stream/minimap.gfx`) und die Aufrufer in
  `qbx_vehiclekeys`, `qbx_bankrobbery`, `qbx_storerobbery`, `qbx_medical`, `qbx_ambulancejob` und
  `qbx_smallresources/qbx_consumables`; `pma-voice` (State Bags `proximity`, `radioChannel`, `radioActive`);
  Positionen in `qbx_scoreboard`, `mm_radio` und `scully_emotemenu`; ox_target `client/utils.lua` (`drawSprite`)
- Freizeit, Villen und Autohäuser (13.09.2026): `bob74_ipl` `client.lua` (geladene Innenräume, Build-Sperren),
  `qbx_properties` `config/shared.lua`, `qbx_vehicleshop` `config/shared.lua` (`luxury` auskommentiert,
  `vehicles.models`), `qbx_core` v1.24.0 `shared/vehicles.lua` (901 Einträge), `qbx_lapraces` `config.lua` und
  Events, `scully_emotemenu` (`fxmanifest.lua`, `prop_emotes.lua`, `stream/[Props]/[BzZzi]`), Lizenzen und letzte
  Commits von `cw-racingapp`, `thommie-arcade`, `rz-dart`, `dynyx-gym`, `davedumas0/fiveM-movies`,
  `Xogy/rcore_arcade`, `morethancodenl/mtc-arcade`, `alberttheprince/FiveM-Golf` und dem Vinewood House MLO
