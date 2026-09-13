# Ressourcen: resources.txt, [local], [vendor]

## Vier Ordner unter server-data/resources/

| Ordner           | Inhalt                                                 | In Git | Gefüllt von                                   |
|------------------|--------------------------------------------------------|--------|-----------------------------------------------|
| `[local]`        | Deine eigenen Ressourcen, z. B. `hello-world`          | ja     | dir                                           |
| `[cfx-default]`  | Standard-Ressourcen aus `citizenfx/cfx-server-data`    | nein   | `install-resources.ps1` / `install-resources.sh` |
| `[vendor]`       | Qbox und Fremd-Ressourcen aus `server-data/resources.txt` | nein | dieselben Skripte                              |
| `[marketplace]`  | Assets aus dem Cfx Marketplace (Asset Escrow, gekauft oder kostenlos) | nur `README.md` und `.anpassungen/` | dir, Ablauf in `server-data/resources/[marketplace]/README.md` |

So sieht `[vendor]` nach der Installation aus (Inhalt der Kategorien: [frameworks.md](frameworks.md#was-installiert-ist)):

```
server-data/resources/[vendor]/
  .sources/            qbox-recipe, qbx_invimages (keine Ressourcen, von FXServer ignoriert)
  [standalone]/        bob74_ipl, illenium-appearance, [MugShotBase64]/MugShotBase64, ...
  [voice]/             pma-voice, mm_radio
  [qbx]/               qbx_core, qbx_garages, ...
  [ox]/                ox_lib, oxmysql, ox_target, ox_inventory, ox_doorlock, ox_fuel
  [npwd]/              npwd, qbx_npwd
  [npwd-apps]/         npwd_qbx_garages, npwd_qbx_mail
  [assets]/            pillbox, vinewood_house_mlo
```

So findet FXServer Ressourcen:

- Ordner mit eckigen Klammern sind **Kategorien** und werden rekursiv durchsucht, auch verschachtelt
  (`[vendor]/[qbx]/qbx_core`). Eine Ressource ist ein Ordner mit `fxmanifest.lua`, ihr Name ist genau dieser
  Ordnername, nicht der Pfad.
- Ordner, deren Name mit `.` beginnt (z. B. `.sources`, `.git`), überspringt FXServer. Dort liegen Quell-Repos,
  aus denen `copy`-Zeilen Dateien holen.
- Dateien direkt in einem Klammer-Ordner (z. B. `[local]/[overrides]/items.lua`) sind keine Ressource und werden
  ignoriert.
- `ensure <name>` startet eine Ressource, `ensure [kategorie]` alle Ressourcen unter einem Ordner dieses Namens,
  egal wie tief er liegt: `ensure [qbx]` findet `[vendor]/[qbx]`. Die Reihenfolge der ensure-Zeilen in
  `server.cfg` ist die Startreihenfolge; zwei Ressourcen mit demselben Ordnernamen führen zu einem Konflikt.

## Das Manifest resources.txt

`server-data/resources.txt` beschreibt, welche Fremd-Ressourcen die Installer holen. Die committete Datei enthält
das Qbox-Rezept: 60 `git`-, 17 `zip`- und 3 `copy`-Zeilen. Einträge laufen in der Reihenfolge der Datei.

Format, eine Zeile pro Eintrag, Felder durch Leerzeichen getrennt:

```
# Kommentarzeilen und Leerzeilen werden ignoriert
git <ziel> <git-url> [ref]
zip <ziel> <url>
copy <quelle> <ziel>
```

### git

`git clone --depth 1 [--branch <ref>] <url> server-data/resources/<ziel>`. `<ref>` ist ein Branch- oder
Tag-Name, kein Commit-Hash (Clone schlägt sonst fehl, die Meldung sagt das). Ohne `<ref>` der Standard-Branch.

### zip

Archiv in einen Temp-Ordner laden und entpacken. Hat das Archiv genau **einen** Ordner auf oberster Ebene, wird
dessen **Inhalt** zu `<ziel>` (so sind die Release-Zips von ox_lib, oxmysql, ox_inventory usw. gebaut). Sonst
landet alles direkt in `<ziel>`. Ein leeres Archiv ist ein Fehler.

### copy

`copy <quelle> <ziel>` kopiert eine Datei oder einen Ordner innerhalb von `server-data/resources/`, typischerweise
aus einer weiter oben installierten Zeile über eine Datei einer anderen Ressource:

```
copy [vendor]/.sources/qbox-recipe/items.lua [vendor]/[ox]/ox_inventory/data/items.lua
copy [vendor]/.sources/qbx_invimages/images [vendor]/[ox]/ox_inventory/web/images
copy [vendor]/[npwd]/qbx_npwd/config.json [vendor]/[npwd]/npwd/config.json
```

- Läuft bei **jedem** Aufruf, unabhängig von `--update`/`-Update` und `--force`/`-Force`. So liegt die
  Überlagerung auch nach einem `git pull` oder Neuladen wieder richtig.
- **Quelle ist eine Datei:** Ist das Ziel byte-gleich (Linux `cmp -s`, Windows Größe und SHA256), wird
  übersprungen (`unveraendert, ueberspringe` bzw. `übersprungen`), sonst überschrieben (`Datei kopiert` bzw.
  `installiert`). Ist das Ziel ein Ordner: Fehler `Ziel ist ein Ordner, Quelle eine Datei`.
- **Quelle ist ein Ordner:** Der Inhalt wird erst in einen Temp-Ordner kopiert (ein `.git` auf oberster Ebene
  bleibt draußen), dann wird das Ziel **komplett ersetzt** (`Ordner ersetzt` bzw. `installiert`). Schlägt das
  Kopieren fehl, bleibt das alte Ziel stehen. Ist das Ziel eine Datei: Fehler `Ziel ist eine Datei, Quelle ein Ordner`.
- Fehler: `Quelle fehlt: <quelle> (steht die Zeile, die sie installiert, weiter oben?)`,
  `Zielordner fehlt: <ordner> (ist die Ressource installiert?)`. Quelle und Ziel dürfen sich nicht überschneiden
  (gleich oder eines liegt im anderen): `Quelle und Ziel ueberschneiden sich` (Windows vergleicht ohne
  Groß-/Kleinschreibung).
- Log-Präfix `[copy] <quelle> -> <ziel>: ...`. Eigene Änderungen am Ziel gehen bei jedem Lauf verloren.

### Regeln für alle Zeilen

- `<ziel>` und `<quelle>` sind relativ zu `server-data/resources/`, dürfen Klammer-Ordner und Unterordner
  enthalten, fehlende Elternordner legen `git` und `zip` an. Beide Parser prüfen dieselben Regeln: abgelehnt
  werden absolute Pfade, jedes `:` (Laufwerksbuchstaben), leere Segmente (`foo//bar`) und Segmente, die genau
  `.` oder `..` sind. `[vendor]/my..script` ist erlaubt, ein `/` am Ende wird entfernt (unter Windows sind `/`
  und `\` erlaubt). Meldungen: Linux
  `Zeile N: Ziel '...' ist unzulaessig (muss relativ zu server-data/resources liegen, ohne '.'- oder '..'-Segmente, leere Segmente oder ':')`,
  Windows `Unzulässiges Ziel '...' (...)` bzw. `Unzulässige Quelle '...' (...)`.
- URLs bei `git` und `zip` müssen mit `http://` oder `https://` beginnen (Windows prüft das explizit).
- Unbekannter Typ (`(erlaubt: git, zip, copy)`) oder zu wenige Felder
  (Linux `Zeile N: Format ist '<git|zip> <ziel> <url> [ref]' oder 'copy <quelle> <ziel>'.`, Windows
  `Erwartet: copy <quelle> <ziel>`): Eintrag zählt als fehlgeschlagen, die restlichen laufen weiter.
  Überzählige Felder (bei `git` ab dem fünften, bei `zip` und `copy` ab dem vierten) werden mit Warnung ignoriert.
- Kommentare: Zeilen, die mit `#` beginnen, und ` # Kommentar` am Zeilenende (mit Leerzeichen davor, damit URLs
  mit `#` heil bleiben). Ein UTF-8-BOM am Dateianfang stört nicht.
- Reihenfolge zählt für `copy`: die Zeile, die Quelle bzw. Zielordner installiert, muss weiter oben stehen.

### Manifest prüfen: --check / -Check

```
Linux:    bash scripts/linux/install-resources.sh --check [--manifest <pfad>]
Windows:  powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows\install-resources.ps1 -Check [-ManifestPath <datei>]
```

Prüft nur die Datei: kein Netzwerk, kein git, nichts wird installiert. Dieselben Zeilenregeln wie ein normaler
Lauf plus die **Reihenfolge-Regel**: Beginnt die Quelle einer `copy`-Zeile mit `[vendor]/` oder `[cfx-default]/`,
muss sie gleich einem Ziel einer **früheren** `git`/`zip`-Zeile sein oder darunter liegen; beginnt das Ziel damit,
gilt dasselbe für seinen Elternordner. Sonst:
`Zeile N: copy-Quelle/-Ziel wird von keiner frueheren git/zip-Zeile installiert`. Pfade anderswo (z. B. eine
committete Quelle unter `[local]/`) prüft die Regel nicht. Ergebnis Linux
`[OK] Manifest gueltig: 80 Eintraege (...)`, Windows `[+] Manifest ist gültig (80 Einträge, davon 3 copy).`
Exit 0 gültig, 1 bei Fehlern oder fehlendem Manifest. `--check` geht nur mit `--manifest` (sonst Exit 1),
Windows ignoriert `-Update`/`-Force` mit Warnung. Die CI führt die Prüfung bei jedem Push aus.

## Semantik von Update und Force

| Situation                              | Standard                  | `--update` / `-Update`                              | `--force` / `-Force`                       |
|----------------------------------------|---------------------------|-----------------------------------------------------|--------------------------------------------|
| `[cfx-default]` nicht leer             | übersprungen              | übersprungen                                        | Inhalt löschen, neu klonen                 |
| git-Ziel existiert, ist Git-Repo       | übersprungen              | `git pull --ff-only` (Fehler = Eintrag fehlgeschlagen) | Ziel löschen, neu klonen                |
| git-Ziel existiert, kein `.git`        | übersprungen              | übersprungen mit Warnung (`[WARN]` bzw. `[!]`)      | Ziel löschen, neu klonen                   |
| zip-Ziel existiert                     | übersprungen              | übersprungen (`update` gilt nicht für zip)          | Ziel löschen, neu laden                    |
| Ziel fehlt                             | installieren              | installieren                                        | installieren                               |
| `copy`                                 | kopieren (Datei nur bei Unterschied) | kopieren                                 | kopieren                                   |

- zip-Einträge mit `releases/latest/download/...` werden **nie** ohne `--force`/`-Force` aktualisiert. Mit Force
  holen sie das jeweils neueste Release.
- Alles unter `[vendor]` gehört den Installern. Eigene Änderungen dort gehen bei `--force`, beim nächsten
  `copy`-Lauf oder beim `git pull` (Konflikt, Eintrag schlägt fehl) verloren. Eigene Anpassungen gehören in
  committete Dateien, siehe unten.
- Auf ein Tag geklonte Ziele (detached HEAD) überspringt `install-resources.ps1` bei `-Update` mit Hinweis; unter
  Linux läuft `git pull --ff-only` durch, in der Regel ohne Änderung. Für ein neueres Tag: Ref im Manifest ändern
  und Force nutzen.
- Beide Flags dürfen kombiniert werden, `force` gewinnt.
- Ziele, die nicht mehr im Manifest stehen, entfernt kein Lauf. Wer eine Zeile löscht, löscht den Ordner von Hand,
  sonst startet FXServer die Ressource weiter.

Reihenfolge bei `force`: `install-resources.sh` klont bzw. lädt und entpackt zuerst in einen Temp-Ordner und
ersetzt den vorhandenen Zielordner erst danach; schlägt Download, Clone oder Entpacken fehl, bleibt der alte
Ordner stehen (Meldung z. B. `[git] <ziel>: git clone fehlgeschlagen, der vorhandene Ordner bleibt erhalten.`).
`install-resources.ps1` lädt zip-Ziele ebenfalls erst in einen Temp-Ordner und ersetzt danach; nur git-Ziele
löscht es vor dem Neuklonen (`Entferne '<ziel>' (-Force) ...`).

Aufrufe:

```
Windows:  scripts\windows\install.bat -UpdateResources
          scripts\windows\install.bat -ForceResources
          powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows\install-resources.ps1 [-Update] [-Force] [-ManifestPath <datei>]
Linux:    scripts/linux/install-resources.sh [--update] [--force] [--manifest <pfad>]
```

Exit-Codes: Windows 0 ok, 1 Abbruch, 2 mindestens ein Eintrag fehlgeschlagen. `install.bat` bzw. `install.ps1`
endet außerdem mit 2, wenn in `[cfx-default]` das `fxmanifest.lua` von `mapmanager`, `spawnmanager` oder
`baseevents` fehlt oder der Datenbank-Schritt fehlschlägt. Linux 0 ok, 1 Abbruch oder mindestens ein Eintrag
fehlgeschlagen. Auf beiden Plattformen gilt: Fehlt das Standard-Manifest, nur eine Warnung (Exit 0); ein mit
`-ManifestPath` / `--manifest` angegebenes, fehlendes Manifest bricht mit Exit 1 ab. `deploy.sh` ruft
`install-resources.sh --update` bei jedem Deploy auf.

Fehlgeschlagene Git-Clones räumen den halb angelegten Zielordner wieder weg. Private Repositories fragen
nicht nach Zugangsdaten (`GIT_TERMINAL_PROMPT=0`, unter Windows zusätzlich `GCM_INTERACTIVE=Never`), sondern
schlagen sofort fehl. Unter Windows müssen die Zugangsdaten deshalb vorher im Git Credential Manager
(Windows-Anmeldeinformationsverwaltung) liegen, z. B. durch einen einmaligen manuellen `git clone` desselben
Hosts; unter Linux per SSH-Key des Service-Users `fivem` oder Token in der URL.

## Fester Stand oder immer aktuell

Das Manifest übernimmt die Quellen des Qbox-Rezepts weitgehend: fast alle git-Zeilen stehen auf `main` bzw.
`master`, die meisten zip-Zeilen auf `releases/latest`. Fest stehen npwd (3.16.0, wie im Rezept), ox_lib (v3.39.0,
siehe [unten](#ox_lib-mit-eigenen-dateien-aktualisieren)) und qbx_core (v1.24.0). Folgen:

- Jedes `deploy.sh` bzw. `-UpdateResources` holt den neuesten Stand der git-Ressourcen. Das bringt Fehlerbehebungen,
  kann aber auch Änderungen bringen, die nicht zu den zip-Ressourcen passen.
- zip-Ressourcen bleiben stehen, bis du Force nutzt, und springen dann auf das neueste Release.

Stand festhalten:

```
# git: Tag statt Branch
git [vendor]/[qbx]/qbx_core https://github.com/qbox-project/qbx_core.git v1.24.0
# zip: feste Release-URL statt latest
zip [vendor]/[ox]/ox_lib https://github.com/overextended/ox_lib/releases/download/<version>/ox_lib.zip
```

Danach den Server stoppen, nur den Ordner des betroffenen Ziels unter `[vendor]` löschen und `install-resources`
ohne Force ausführen, dann lädt nur dieses Ziel neu. Force dagegen lädt alle Ziele neu und hebt jede
`releases/latest`-Ressource auf das neueste Release. Vorher auf der Release-Seite prüfen, dass es das Tag bzw. die
Datei gibt. Nach Updates immer die Serverkonsole und `setup-database --dry-run` prüfen.

### ox_lib mit eigenen Dateien aktualisieren

ox_lib steht fest auf v3.39.0, weil zwei eigene Dateien über das Release kopiert werden:
`[local]/[overrides]/ox_lib_textui.lua` und `[local]/[overrides]/ox_lib_notify.lua`. Beide schreiben eine rote
Warnung in die F8-Konsole, wenn eine andere Version von ox_lib läuft. Für ein Update:

1. Im Repo von ox_lib nachsehen, ob sich `resource/interface/client/textui.lua` oder `notify.lua` seit v3.39.0
   geändert haben, und Änderungen in die eigenen Dateien übernehmen. Die Abweichungen vom Original stehen jeweils
   im Kopf der Datei. Außerdem `web/src/features/notifications/NotificationWrapper.tsx` und
   `web/src/features/textui/TextUI.tsx` vergleichen: Die Stilwerte hängen an deren Aufbau und Klassennamen und
   greifen nach Änderungen dort ohne Fehlermeldung nicht mehr.
2. In beiden Dateien `EXPECTED_VERSION` und die Zeile "Grundlage" anpassen, in `resources.txt` die URL der
   zip-Zeile von ox_lib, außerdem die Versionsangaben in der Doku (`grep -rn "3.39.0" docs server-data`).
3. `install-resources --check`. Dann den Server stoppen, nur den Ordner `server-data/resources/[vendor]/[ox]/ox_lib`
   löschen und die Ressourcen ohne Force installieren (Windows `install.bat`, Linux `install-resources.sh` bzw.
   `deploy.sh`). Die zip-Zeile lädt dann nur ox_lib neu, die beiden `copy`-Zeilen darunter legen die eigenen
   Dateien gleich wieder darüber. Force nicht verwenden: Es lädt alle Ziele neu und hebt jede
   `releases/latest`-Ressource auf das neueste Release. Im Spiel eine Meldung und einen Hinweis "E - ..." prüfen.

Die `copy`-Zeile zu löschen stellt die Original-Datei nicht wieder her: `copy` schreibt nur, und die zip-Zeile lädt
nichts neu, solange der Ordner existiert. Zurück zum Original: `copy`-Zeile löschen, den Ordner
`[vendor]/[ox]/ox_lib` löschen und ohne Force installieren. In `ox_lib_notify.lua` lassen sich die Abweichungen
auch über die Konstanten am Anfang der Datei abschalten. Danach `install.bat` bzw. `install-resources.sh`
ausführen, damit die geänderte Datei nach `[vendor]` kopiert wird, und den Server neu starten.

## Eigene Item-Definitionen

`[vendor]/[ox]/ox_inventory/data/items.lua` wird bei jedem Lauf von der `copy`-Zeile aus dem Rezept überschrieben.
Eigene Items oder geänderte Beschriftungen deshalb so pflegen:

1. Die aktuelle Datei nach `server-data/resources/[local]/[overrides]/items.lua` kopieren und dort ändern. Die
   Datei liegt direkt in einem Klammer-Ordner, FXServer ignoriert sie also, sie wird aber committet.
2. In `resources.txt` die Quelle der `copy`-Zeile auf diese Datei umstellen (die alte Zeile ersetzen, nicht
   zusätzlich eintragen):

   ```
   copy [local]/[overrides]/items.lua [vendor]/[ox]/ox_inventory/data/items.lua
   ```

3. `install-resources --check`, dann `install-resources` ausführen.

Nach Qbox-Updates die Rezept-Fassung (`[vendor]/.sources/qbox-recipe/items.lua`) mit deiner vergleichen und neue
Items übernehmen. Dasselbe Muster funktioniert für andere Dateien, die eine Ressource per Konfiguration erwartet.

## Nach der Installation: ensure

Die Installer ändern `server.cfg` nicht. Neue Ressourcen in einer bestehenden Kategorie (`[vendor]/[standalone]/...`,
`[vendor]/[qbx]/...`) startet das vorhandene `ensure [standalone]` bzw. `ensure [qbx]` automatisch. Für eine neue
Kategorie oder eine Ressource außerhalb davon trägst du `ensure <name>` bzw. `ensure [kategorie]` im Abschnitt
"Ressourcen" der `server.cfg` hinter ihren Abhängigkeiten ein und startest die Ressource per `refresh` und
`ensure <name>` in der Konsole (txAdmin > Live Console) oder durch einen Neustart. Bringt eine Ressource
SQL-Dateien mit, gehört eine Zeile ans Ende von `server-data/database.txt` ([datenbank.md](datenbank.md#eigene-sql-dateien)).

## Eigene Ressourcen in [local]

Eigene Skripte gehören nach `server-data/resources/[local]/<name>/` und werden committet. Namen nur mit
Kleinbuchstaben, Ziffern, `-` und `_`. Jede Ressource braucht eine `fxmanifest.lua`:

```lua
fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Dein Name'
description 'Was das Script macht'
version '1.0.0'

server_script 'server.lua'
client_script 'client.lua'
-- shared_script 'config.lua'
-- dependency 'oxmysql'
-- shared_script '@ox_lib/init.lua'
```

Danach `ensure <name>` in `server.cfg` hinter den Abhängigkeiten eintragen (dort steht schon `ensure hello-world`
am Ende). Die mitgelieferte Ressource `hello-world` (Befehl `/hallo`, Join-Log, einmalige Begrüßung nach dem
Spawn, mit und ohne Qbox) ist ein lauffähiges Beispiel. Mehr dazu in `server-data/resources/[local]/README.md`.

Die CI prüft alle `.lua`-Dateien unter `[local]` mit `luac5.4 -p` auf Syntaxfehler. Lokal geht das mit
`luac5.4 -p datei.lua` (Ubuntu: `apt install lua5.4`).

## Fremd-Ressourcen, die nicht ins Manifest passen

Manche Ressourcen kommen als Zip ohne Oberordner, mit mehreren Ressourcen in einem Archiv oder nur per
Tebex-Download. Optionen:

- Zip mit mehreren Ressourcen: `zip [vendor]/[paketname] <url>` legt alles unter einer Kategorie ab; FXServer
  findet die Ressourcen darin rekursiv.
- Ressource liegt im Repo in einem Unterordner: in einen Klammer-Ordner klonen, wie
  `git [vendor]/[standalone]/[MugShotBase64] https://github.com/BaziForYou/MugShotBase64.git main`.
- Kein öffentlicher Download (Cfx Marketplace, gekauft oder kostenlos): nach `[marketplace]/<name>/` entpacken, nicht
  nach `[vendor]`. Der Ordner ist gitignored, eigene Dateien wie Übersetzungen liegen committet in
  `[marketplace]/.anpassungen/<name>/`, die nötigen Config-Änderungen stehen pro Asset in
  `server-data/resources/[marketplace]/README.md`. Ressourcen, die du selbst pflegst und deren Lizenz es erlaubt,
  gehören nach `[local]/<name>/` (wird committet).
- Eigene Forks: in ein eigenes Git-Repo legen und als `git`-Eintrag mit Tag referenzieren, dann ist der Stand
  reproduzierbar.

Vor dem Installieren neuer Fahrzeuge, Kleidung, Karten oder Sounds [inhalte-regeln.md](inhalte-regeln.md) lesen.
