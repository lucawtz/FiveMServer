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
| 4 | Apartment | Beim Verlassen des Gebäudes landet man im Aufzug und muss mehrmals rein und raus, bis man draußen ist. | Ein Ausgang, der direkt nach draußen führt. |
| 5 | Waffenladen | Im Ammu-Nation steht kein NPC, bei dem man eine Waffe kaufen kann. | Verkäufer bzw. Shop-Punkt vorhanden, Kauf möglich. |
| 6 | Bedienung | Beim Parken steht der Hinweis "E - Garage öffnen" klein am rechten Bildschirmrand und fällt nicht auf. | Bei allen Interaktionen ist der Hinweis sofort sichtbar, z. B. unten mittig und deutlicher hervorgehoben. |
| 7 | Fahrzeughändler | Nach der Probefahrt beim Premium Deluxe Motorsport liegt der Charakter tot vor dem Eingang. | Nach der Probefahrt steht man unverletzt am Händler, das Testfahrzeug ist weg. |
| 8 | Fahrzeug | Im Auto sieht man nicht, welche Tasten es gibt und was man machen kann. | Im Fahrzeug eine Übersicht der Tasten und Möglichkeiten, am besten ausklappbar. |
| 9 | Bedienung | Benachrichtigungen oben rechts (z. B. "Das Inventar wurde erfolgreich geladen") sind gut, aber zu klein und verschwinden zu schnell. | Größere Schrift und Box, länger sichtbar, sodass man sie in Ruhe lesen kann. |
| 10 | Geld | Bargeld und Kontostand sind nirgends zu sehen. | Geld jederzeit ablesbar, dauerhaft im HUD oder auf Tastendruck. |
| 11 | Geld | Alle 10 Minuten kommt Gehalt, obwohl man nichts macht und keinen Beruf gewählt hat. Unklar, wofür. | Klar erkennbar, wofür Geld kommt. **Entscheidung**, ob es ein Grundeinkommen ohne Job gibt. |
| 12 | Fahrzeughändler | Die Restzeit der Probefahrt steht nur in Sekunden da ("Verbleibende Zeit der Probefahrt:293"), ohne Leerzeichen, mitten über dem Auto. | Anzeige als Minuten und Sekunden (4:53), gut lesbar am Bildschirmrand. |
| 13 | Rettungsdienst | Am Boden steht nur "Du blutest aus in: 27 Sekunden", man kann nichts tun und keinen Notruf absetzen. | Am Boden lässt sich jederzeit ein Notruf absetzen, gut sichtbar mit Taste, und er erreicht auch jemanden. |

- [ ] Befunde 3 bis 5 untersuchen (Ursache in `qbx_properties`, `qbx_spawn` bzw. den Shops von `ox_inventory`)
  - Befund 3: In der Datenbank gehört dem Charakter nur ein Apartment. `qbx_properties`
    (`client/property.lua`) setzt aber für jede Apartment-Option ein grünes Haus-Symbol, bei allen Spielern.
    Änderung nur im Code möglich, das Repo hat keine Releases: Fork nötig (Weg C).
  - Befund 4: Apartment `4IntegrityWayApt30`, der Ausgang setzt den Spieler auf den Eingangspunkt
    `-47.52, -585.86, 37.95` aus `config/shared.lua`. Ob dieser Punkt im Aufzug liegt, im Spiel prüfen.
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
      Datei (Weg B): immer unten mittig, größere fette Schrift, blauer Rand links, etwas über dem Bildschirmrand.
  - [ ] Im Spiel testen: Garage, Kleidungsladen (illenium-appearance), ein Job. Überdeckt der Hinweis im
        Fahrzeug den Tacho von `qbx_hud`? Dann `marginBottom` in der Datei anpassen.
  - [ ] Interaktionen über `ox_target` (linke Alt-Taste) sind eine andere Anzeige, getrennt bewerten.
- [ ] Befund 9 beheben: Die Meldungen kommen von `lib.notify` (`ox_lib`). Die Anzeigedauer ist 3 Sekunden, wenn die
      aufrufende Ressource keine `duration` mitgibt (`web/build`, `n.duration||3e3`), die Position `top-right` ist
      eine Client-Einstellung (`resource/settings.lua`). Einen Convar für Dauer oder Größe gibt es nicht. Zentral
      lösbar zusammen mit Befund 6 über einen Override von `resource/interface/client/notify.lua` (Weg B): ohne
      angegebene Dauer z. B. 6 bis 8 Sekunden setzen und über das Feld `style` Schriftgröße und Breite erhöhen.
      Ressourcen mit eigener kurzer `duration` bleiben davon unberührt, bei Bedarf eine Mindestdauer erzwingen.
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
- [ ] Befunde 1 und 2 bei der Planung von Phase 3 berücksichtigen

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
- [ ] Einführung für neue Spieler direkt nach dem ersten Einloggen: verständliche Anleitung zu Steuerung, Handy,
      Jobs, Geld und Regeln (Befund 1 aus dem ersten Spieltest)
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
| 1 | Wie viele Spieler sind realistisch gleichzeitig online, und wer spielt Polizei und Rettungsdienst? | Überfälle brauchen Gegenspieler, Schwellen in Phase 6 | Niedrige Polizei-Schwellen; fehlende Rollen übernehmen NPCs ([Leitstelle](#leitstelle-und-npc-dienste), Grundsatz entschieden 13.09.2026) |
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
| 12 | NPC-Polizei über GTA-Fahndung oder eigene Streifen? | GTA-Fahndung ist schnell gebaut, passt aber schlecht zu Gefängnis und Bußgeld | Erst GTA-Fahndung nur nach Alarmen testen, eigene Streifen, wenn es stört |
| 13 | Militär nur als NPC-Sperrgebiet oder auch als Spieler-Job? | Aufwand, wenig Einsätze in kleiner Runde | Erst NPC-Sperrgebiet Fort Zancudo |
| 14 | Was kosten NPC-Dienste? | Zu billig macht Spieler-Jobs sinnlos, zu teuer frustriert | Deutlich teurer als ein Spieler im Dienst, Werte mit Entscheidung 3 |

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
