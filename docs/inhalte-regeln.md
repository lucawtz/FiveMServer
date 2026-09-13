# Inhalte: was auf dem Server erlaubt ist

Kurzfassung der Regeln von Cfx.re und Rockstar Games für Inhalte auf FiveM-Servern, bezogen auf dieses Projekt.
Stand der Quellen: 12.09.2026. **Keine Rechtsberatung.** Maßgeblich sind immer die verlinkten Originaltexte.

## Gilt auch für private Server

- Die Regeln gelten für jeden "Custom Server". In der Creator Platform License Agreement (PLA), den Rockstar Mod
  Guidelines, dem Rockstar-Artikel zu Roleplay-Servern und den Rockstar Terms of Service wurde **keine Ausnahme**
  für private, nicht gelistete oder reine Freundes-Server gefunden (Stichwortsuche in der PLA, Lesen der
  einschlägigen Abschnitte der übrigen Texte).
- Nicht kommerziell zu sein hebt die Regeln zu fremdem geistigem Eigentum nicht auf.
- Wer einen Server betreibt oder administriert, ist für **alle** Inhalte darauf verantwortlich, auch für die, die
  andere erstellt oder hochgeladen haben (PLA §4). Dazu zählen auch installierte Fremd-Ressourcen aus `[vendor]`.

## Verboten

- **Echte Marken und Logos** und Designs, die echten Produkten nachgebaut sind. Abgewandelte Schreibweisen sind
  ebenfalls riskant (Tebex verbietet sie ausdrücklich für verkaufte Inhalte).
- **Echte Fahrzeuge und ihre Designs.** Logos entfernen ("De-badging") reicht nicht, echte Fahrzeuge müssen
  komplett runter vom Server. Cfx.re nennt auch einzigartige Fahrzeugdesigns schutzfähig, ein originalgetreuer
  Nachbau ist deshalb ebenfalls riskant.
- **Aussehen, Stimme oder Abbild echter Personen** ohne deren schriftliche Erlaubnis.
- **Lizenzierte Musik** und Ausschnitte davon, außerdem veränderte Sprachaufnahmen aus Rockstar-Spielen.
- **Karten, Modelle und andere Inhalte aus anderen Spielen**, ausdrücklich auch aus anderen Rockstar-Spielen.
- **Werbung, Produktplatzierung und Sponsoring** für Dritte (Mod Guidelines, PLA §3.1). Ebenso verboten: einen
  Server durch, im Auftrag oder in fortlaufender kommerzieller Verbindung mit einer fremden Marke zu betreiben
  (PLA §3.1).
- Echte Orte als geschützte Elemente fremder Rechteinhaber.

## Erlaubt: Lore-Marken und eigene Designs

- **Marken aus dem GTA-Universum**, also die Fantasie-Marken und -Fahrzeuge, die das Spiel selbst mitbringt
  (zum Beispiel Burger Shot, Cluckin' Bell, Pfister, Grotti, Vapid). Die PLA lizenziert veränderte Versionen der
  Spiele und ihrer Assets.
- **Eigene, lore-freundliche Designs**: eigene Firmen, Logos, Fahrzeuge und Kleidung, die ins GTA-Universum
  passen. Cfx.re empfiehlt ausdrücklich, eigene Fahrzeuge und Marken zu entwerfen.
- Grenze: Lore-Marken sind Marken von Rockstar. Sie dürfen **nicht Teil des Servernamens oder des
  Server-Brandings** sein (PLA §2.3) und nicht als Herkunftszeichen für Waren oder Dienste im Handel dienen
  (PLA §2.2). Dasselbe gilt für Namen und Logos von Rockstar und FiveM: die PLA zählt FiveM in §1.1 zu den
  Plattformen von Rockstar. Ein offizielles Verzeichnis "erlaubter" Lore-Marken wurde nicht gefunden (Tebex
  erwähnt eine "CFX Lore-Friendly Vehicle List", die aber nirgends auffindbar war). Die Einordnung folgt aus der
  PLA-Lizenz für Spiel-Assets und der Empfehlung von Cfx.re.
- Alle Webseiten, Listings, Shops und sonstigen Informationen, die Spieler zum Server sehen (PLA §2.3:
  "user-facing information"), müssen Betreiber, eine gültige Kontakt-E-Mail und einen deutlichen Hinweis wie
  "<SERVERNAME> IS NOT APPROVED, SPONSORED, OR ENDORSED BY ROCKSTAR GAMES." enthalten, auch bei privaten Servern.
- Für den Eintrag in der Serverliste bringt `server-data/server.cfg` den Hinweis schon in `sv_projectDesc` mit:
  "MEIN RP-PROJEKT IS NOT APPROVED, SPONSORED, OR ENDORSED BY ROCKSTAR GAMES.", passend zu
  `sets sv_projectName "Mein RP-Projekt"`. Benennst du das Projekt um, änderst du den Namen im Hinweis in
  `server.cfg` und `secrets.cfg` mit.
- Echten Betreiber und Kontakt-E-Mail trägst du in `secrets.cfg` per `sets sv_projectDesc "..."` ein (mit dem
  Hinweis im selben Text, eine auskommentierte Vorlage steht in `secrets.cfg.example`), dann stehen sie nicht in
  Git. `secrets.cfg` wird nach diesen Einstellungen geladen und überschreibt den Wert.

## Fremd-Ressourcen prüfen

Die Ressourcen aus `server-data/resources.txt` stammen von Dritten. Prüfe nach der Installation und nach Updates:

- **Item-Schlüssel und Beschriftungen**, vor allem `[vendor]/[ox]/ox_inventory/data/items.lua` (kommt aus dem
  Qbox-Rezept) und Shop- oder Job-Konfigurationen,
- **Item-Bilder** (`[vendor]/[ox]/ox_inventory/web/images`, aus `qbx_invimages`),
- **App-Namen und Texte** im Handy (npwd und seine Apps),
- **Bilder, Logos und Musik** in Ladebildschirm, HUD und Audio-Ressourcen,
- **Fahrzeuglisten** in Händler- und Garagen-Konfigurationen (nur Spielfahrzeuge oder eigene Designs).

Einige installierte Qbox- und Handy-Ressourcen enthalten in internen Schlüsseln oder Oberflächentexten Namen
echter Produkte oder Dienste. Diese Doku nennt sie bewusst nicht. So gehst du damit um:

- Interne Schlüssel (z. B. der Item-Name, auf den Skripte zugreifen) sieht kein Spieler. Sie umzubenennen bricht
  meist andere Ressourcen, also nicht ohne Not ändern.
- Sichtbare Beschriftungen nur dort ändern, wo die Ressource es vorsieht: Sprachdateien (`locales/*.json`),
  Konfigurationsdateien oder das `label` in `items.lua`. Eigene Fassungen gehören in eine committete Datei, die
  eine `copy`-Zeile über das Original legt, siehe [ressourcen.md](ressourcen.md#eigene-item-definitionen).
  Direkte Änderungen in `[vendor]` gehen beim nächsten Update verloren.
- Neue Fahrzeuge, Kleidung, Karten oder Sounds nur installieren, wenn sie selbst gemacht oder lore-freundlich
  sind und keine echten Vorbilder nachbilden.

Beispiele für Spielinhalte in diesem Repo (Doku, Kommentare, Konfiguration) nutzen deshalb nur Lore-Namen und
eigene Namen. Technische Werkzeuge (z. B. GitHub, Docker, MariaDB) werden beim Namen genannt.

## Folgen bei Verstößen

Rockstar kann nach der PLA (§7.2) gemäß den Rockstar Terms of Service "Adverse Action" gegen Nutzer, Accounts,
Inhalte und Custom Server ergreifen: Zugang sperren oder beenden, neue Accounts verbieten, rechtliche Schritte.
Rechteinhaber können Hinweise nach dem DMCA-Verfahren einreichen (TOS §8.1), bei wiederholten Verstößen drohen
weitere Maßnahmen (TOS §8.2). Die Mod Guidelines behalten sich vor, Inhalte jederzeit zu entfernen. Unabhängig
davon können Marken- oder Designinhaber ihre Rechte direkt geltend machen.

## Quellen

| Quelle                                                                                         | Stand                  |
|------------------------------------------------------------------------------------------------|------------------------|
| Creator Platform License Agreement: <https://fivem.net/terms>                                  | 10.09.2026             |
| Rockstar Games Mod Guidelines: <https://www.rockstargames.com/community-resources/mod-guidelines> | 10.09.2026          |
| Rockstar Games Terms of Service: <https://www.rockstargames.com/legal>                         | 28.02.2025             |
| Rockstar Support, Roleplay (RP) Servers: <https://support.rockstargames.com/articles/5I66kExWgligszgMCU3XC1/roleplay-rp-servers> | 07.01.2025 |
| Cfx.re Community Pulse, Oktober 2023 (Fahrzeuge, Inhalte aus anderen Spielen): <https://forum.cfx.re/t/community-pulse-october-2023-edition/5176467> | 13.10.2023 |
| Cfx.re Releases Rules and FAQ: <https://forum.cfx.re/t/releases-rules-and-faq/240725>          | 04.11.2024             |
| Tebex, What is Intellectual Property?: <https://docs.tebex.io/creators/initial-setup-guide/what-is-intellectual-property> | abgerufen 12.09.2026 |

Alle Quellen wurden am 12.09.2026 abgerufen.
