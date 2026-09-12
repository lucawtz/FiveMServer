# Ressourcen: resources.txt, [local], [vendor]

## Drei Ordner unter server-data/resources/

| Ordner           | Inhalt                                                 | In Git | Gefüllt von                                   |
|------------------|--------------------------------------------------------|--------|-----------------------------------------------|
| `[local]`        | Deine eigenen Ressourcen, z. B. `hello-world`          | ja     | dir                                           |
| `[cfx-default]`  | Standard-Ressourcen aus `citizenfx/cfx-server-data`    | nein   | `install-resources.ps1` / `install-resources.sh` |
| `[vendor]`       | Fremd-Ressourcen aus `server-data/resources.txt`       | nein   | dieselben Skripte                              |

FXServer durchsucht Ordner mit eckigen Klammern rekursiv. Ein Klammer-Ordner ist selbst keine Ressource,
sondern eine Kategorie; die Ressource ist der Ordner mit der `fxmanifest.lua` darin, und ihr Name ist
genau dieser Ordnername (nicht der Pfad). `[vendor]/[esx]/[core]/es_extended` ist also die Ressource
`es_extended`. Ordner ohne Klammern und ohne `fxmanifest.lua` (z. B. `.github/`, `[SQL]/`) ignoriert FXServer.

`ensure <name>` startet eine Ressource beim Serverstart. `ensure [core]` startet alle Ressourcen der Kategorie
`[core]`. Die Reihenfolge der `ensure`-Zeilen in `server.cfg` ist die Startreihenfolge: Abhängigkeiten
(`oxmysql`, `ox_lib`, das Framework) müssen vor den Ressourcen stehen, die sie nutzen. Zwei Ressourcen mit
demselben Ordnernamen an verschiedenen Orten führen zu einem Konflikt.

## Das Manifest resources.txt

Die Datei `server-data/resources.txt` beschreibt, welche Fremd-Ressourcen die Installer holen. Die
committete Datei enthält nur auskommentierte, vorbereitete Blöcke (oxmysql, ox_lib, pma-voice, ESX, QBCore,
Qbox). Ein frischer Lauf installiert also nur `[cfx-default]`. Zum Aktivieren das führende `#` entfernen.

Format, eine Zeile pro Eintrag, Felder durch Leerzeichen getrennt:

```
# Kommentarzeilen und Leerzeilen werden ignoriert
git <ziel> <git-url> [ref]
zip <ziel> <url>
```

- `git`: `git clone --depth 1 [--branch <ref>] <url> server-data/resources/<ziel>`. `<ref>` ist ein
  Branch- oder Tag-Name, kein Commit-Hash (Clone schlägt sonst fehl, die Meldung sagt das).
- `zip`: Archiv in einen Temp-Ordner laden und entpacken. Hat das Archiv genau **einen** Ordner auf oberster
  Ebene, wird dessen **Inhalt** zu `<ziel>` (so sind die Release-Zips von oxmysql, ox_lib, ox_target und
  ox_inventory gebaut: `oxmysql.zip` enthält `oxmysql/fxmanifest.lua ...`). Sonst landet alles direkt in `<ziel>`.
  Ein leeres Archiv ist ein Fehler.
- `<ziel>` ist relativ zu `server-data/resources/`, darf Klammer-Ordner und Unterordner enthalten
  (`[vendor]/oxmysql`, `[vendor]/[qb]/qb-core`), fehlende Elternordner werden angelegt. Beide Parser prüfen
  dieselben Regeln: abgelehnt werden absolute Pfade, jedes `:` im Ziel (Laufwerksbuchstaben), leere Segmente
  (`foo//bar`) und Segmente, die genau `.` oder `..` sind (`foo/./bar`, `../x`, `[vendor]/..`). Ein Name wie
  `[vendor]/my..script` ist erlaubt. Ein `/` am Ende wird entfernt; unter Windows sind `/` und `\` beide
  erlaubt und ein `\` am Ende wird ebenfalls entfernt. Meldungen: Linux
  `Zeile N: Ziel '...' ist unzulaessig (muss relativ zu server-data/resources liegen, ohne '.'- oder '..'-Segmente, leere Segmente oder ':')`,
  Windows `Unzulässiges Ziel '...' (muss relativ sein, ohne '..' und ohne Laufwerk)`.
- URLs müssen mit `http://` oder `https://` beginnen (Windows prüft das explizit).
- Unbekannter Typ oder zu wenige Felder: Eintrag wird als fehlgeschlagen gezählt (mit Zeilennummer), die
  restlichen Einträge laufen weiter. Überzählige Felder (bei `git` ab dem fünften, bei `zip` ab dem vierten)
  ignorieren beide Plattformen mit einer Warnung, die die Zeilennummer nennt.
- Kommentare: Beide Plattformen ignorieren Zeilen, die mit `#` beginnen, und schneiden ` # Kommentar` am
  Zeilenende ab. Vor dem `#` muss ein Leerzeichen stehen, damit URLs mit `#` darin heil bleiben. Am
  übersichtlichsten bleiben Kommentare trotzdem in eigenen Zeilen.

Beispiele:

```
# Release-Zip mit einem Oberordner -> Inhalt wird zu [vendor]/oxmysql
zip [vendor]/oxmysql https://github.com/overextended/oxmysql/releases/latest/download/oxmysql.zip

# Git-Repo, Standardbranch
git [vendor]/pma-voice https://github.com/AvarianKnight/pma-voice.git

# Git-Repo mit Branch oder Tag
git [vendor]/[qb]/qb-core https://github.com/qbcore-fivem/qb-core.git main
git [vendor]/mein-script https://github.com/<account>/mein-script.git v1.2.0

# Ganzes Repo mit Klammer-Ordnern darin (ESX): Ressourcen liegen dann unter [vendor]/[esx]/[core]/
git [vendor]/[esx] https://github.com/esx-framework/esx_core.git main
```

## Semantik von Update und Force

| Situation                              | Standard                  | `--update` / `-Update`                              | `--force` / `-Force`                       |
|----------------------------------------|---------------------------|-----------------------------------------------------|--------------------------------------------|
| `[cfx-default]` nicht leer             | übersprungen              | übersprungen                                        | Inhalt löschen, neu klonen                 |
| git-Ziel existiert, ist Git-Repo       | übersprungen              | `git pull --ff-only` (Fehler = Eintrag fehlgeschlagen) | Ziel löschen, neu klonen                |
| git-Ziel existiert, kein `.git`        | übersprungen              | übersprungen mit Warnung (`[WARN]` bzw. `[!]`)      | Ziel löschen, neu klonen                   |
| zip-Ziel existiert                     | übersprungen              | übersprungen (`update` gilt nicht für zip)          | Ziel löschen, neu laden                    |
| Ziel fehlt                             | installieren              | installieren                                        | installieren                               |

Auf ein Tag geklonte Ziele (detached HEAD, z. B. `v1.2.0` oben) überspringt `install-resources.ps1` bei
`-Update` mit Hinweis; unter Linux läuft dort `git pull --ff-only` durch, in der Regel ohne Änderung. Für ein
neueres Tag: Ref im Manifest ändern und `-Force` / `--force` nutzen.

Beide Flags dürfen kombiniert werden; `force` gewinnt. `--force` ist also der Weg, um ein Release-Zip
(z. B. oxmysql) auf die neueste Version zu bringen, weil `releases/latest/download/...` immer auf das aktuelle
Release zeigt.

Reihenfolge bei `force`: `install-resources.sh` klont bzw. lädt und entpackt zuerst in einen Temp-Ordner und
ersetzt den vorhandenen Zielordner erst danach; schlägt Download, Clone oder Entpacken fehl, bleibt der alte
Ordner stehen (Meldung z. B. `[git] <ziel>: git clone fehlgeschlagen, der vorhandene Ordner bleibt erhalten.`).
`install-resources.ps1` lädt zip-Ziele ebenfalls erst in einen Temp-Ordner und ersetzt danach; nur git-Ziele
löscht es vor dem Neuklonen (`Entferne '<ziel>' (-Force) ...`).

Aufrufe:

```
Windows:  scripts\windows\install.bat -UpdateResources
          scripts\windows\install.bat -ForceResources
          powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows\install-resources.ps1 -Update [-Force] [-ManifestPath <datei>]
Linux:    scripts/linux/install-resources.sh [--update] [--force] [--manifest <pfad>]
```

Exit-Codes: Windows 0 ok, 1 Abbruch, 2 mindestens ein Eintrag fehlgeschlagen. `install.bat` bzw. `install.ps1`
endet außerdem mit 2, wenn in `[cfx-default]` das `fxmanifest.lua` von `mapmanager`, `spawnmanager` oder
`basic-gamemode` fehlt. Linux 0 ok, 1 Abbruch oder mindestens ein Eintrag fehlgeschlagen. Auf beiden Plattformen gilt: Fehlt das Standard-Manifest, nur eine Warnung
(Exit 0); ein mit `-ManifestPath` / `--manifest` angegebenes, fehlendes Manifest bricht mit Exit 1 ab.
`deploy.sh` ruft `install-resources.sh --update` bei jedem Deploy auf.

Fehlgeschlagene Git-Clones räumen den halb angelegten Zielordner wieder weg. Private Repositories fragen
nicht nach Zugangsdaten (`GIT_TERMINAL_PROMPT=0`, unter Windows zusätzlich `GCM_INTERACTIVE=Never`), sondern
schlagen sofort fehl. Unter Windows müssen die Zugangsdaten deshalb vorher im Git Credential Manager
(Windows-Anmeldeinformationsverwaltung) liegen, z. B. durch einen einmaligen manuellen `git clone` desselben
Hosts; unter Linux per SSH-Key des Service-Users `fivem` oder Token in der URL.

## Nach der Installation: ensure

Die Installer ändern `server.cfg` nicht. Nach dem Aktivieren eines Manifest-Blocks musst du die passenden
Zeilen im Abschnitt "Ressourcen" der `server.cfg` einkommentieren, z. B.

```
ensure oxmysql
ensure ox_lib
```

und die Ressource dann per `refresh` und `ensure <name>` in der Konsole (txAdmin > Live Console) starten oder
den Server neu starten. Alles Weitere zu Frameworks in [frameworks.md](frameworks.md).

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

Danach `ensure <name>` in `server.cfg` hinter den Abhängigkeiten eintragen. Die mitgelieferte Ressource
`hello-world` (Befehl `/hallo`, Join-Log, Begrüßung beim Spawn) ist ein lauffähiges Beispiel. Mehr dazu in
`server-data/resources/[local]/README.md`.

Die CI prüft alle `.lua`-Dateien unter `[local]` mit `luac5.4 -p` auf Syntaxfehler. Lokal geht das mit
`luac5.4 -p datei.lua` (Ubuntu: `apt install lua5.4`).

## Fremd-Ressourcen, die nicht ins Manifest passen

Manche Ressourcen kommen als Zip ohne Oberordner, mit mehreren Ressourcen in einem Archiv oder nur per
Tebex-Download. Optionen:

- Zip mit mehreren Ressourcen: `zip [vendor]/[paketname] <url>` legt alles unter einer Kategorie ab; FXServer
  findet die Ressourcen darin rekursiv.
- Kein öffentlicher Download: Ressource manuell nach `[vendor]/<name>/` legen (bleibt gitignored) oder,
  wenn du sie selbst pflegst, nach `[local]/<name>/` (wird committet, Lizenz beachten).
- Eigene Forks: in ein eigenes Git-Repo legen und als `git`-Eintrag mit Tag referenzieren, dann ist der Stand
  reproduzierbar.
