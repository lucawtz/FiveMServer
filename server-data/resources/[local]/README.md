# Eigene Ressourcen: `[local]`

In diesem Ordner liegen deine eigenen Ressourcen. Er ist der einzige Ordner unter
`server-data/resources/`, dessen Ressourcen in Git eingecheckt werden:

| Ordner           | Inhalt                                             | In Git? |
|------------------|----------------------------------------------------|---------|
| `[local]`        | Deine eigenen Skripte (dieser Ordner)              | ja      |
| `[cfx-default]`  | Standard-Ressourcen aus cfx-server-data            | nein, Installer |
| `[vendor]`       | Fremd-Ressourcen aus `server-data/resources.txt`   | nein, Installer |
| `[marketplace]`  | Assets aus dem Cfx Marketplace, von Hand entpackt  | nur `README.md` und `.anpassungen/` |

FXServer durchsucht alle Ordner in eckigen Klammern rekursiv. Der Name einer
Ressource ist immer der Name ihres Ordners, nicht der Pfad.

## Eine neue Ressource anlegen

1. Ordner anlegen, z. B. `server-data/resources/[local]/mein-script/`.
   Nur Kleinbuchstaben, Ziffern, `-` und `_` verwenden, keine Leerzeichen.
2. Eine `fxmanifest.lua` hineinlegen (Minimalbeispiel):

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
   ```

3. Die Skripte schreiben (`server.lua`, `client.lua`). Die Ressource `hello-world`
   in diesem Ordner ist ein lauffähiges Beispiel mit Befehl, Event und Chat-Ausgabe.
4. Die Ressource in `server-data/server.cfg` im Abschnitt "Ressourcen" starten:

   ```
   ensure mein-script
   ```

   `ensure` startet die Ressource beim Serverstart und startet sie neu, falls sie
   bereits läuft. Die Reihenfolge der `ensure`-Zeilen ist die Startreihenfolge:
   Abhängigkeiten (z. B. `oxmysql`, `ox_lib`, ein Framework) müssen vor deinem
   Script stehen.

5. Server neu starten oder in der Serverkonsole (bzw. txAdmin > Live Console)
   `refresh` und danach `ensure mein-script` eingeben. Für Änderungen an einer
   laufenden Ressource reicht `restart mein-script`.

## Tipps

- Nutzt dein Script die Datenbank, trage `dependency 'oxmysql'` in die
  `fxmanifest.lua` ein (oxmysql startet über `ensure [ox]` vor `[local]`). Eigene
  SQL-Dateien bekommen eine Zeile am Ende von `server-data/database.txt`, damit
  `setup-database` sie importiert. `rerun` nur für Dateien anhängen, die gefahrlos
  mehrfach laufen können (siehe `docs/datenbank.md`).
- Mit Qbox (qbx_spawn aktiv) kommt `playerSpawned` in keinem Spawn-Ablauf, weder bei
  neuen Charakteren noch bei der Spawn-Auswahl. `hello-world/client.lua` zeigt das robuste
  Muster: mehrere Signale abhören und die Aktion nur einmal ausführen.
- Nutzt du `ox_lib`, gehört `shared_script '@ox_lib/init.lua'` in die Manifest-Datei.
- Konfigurierbare Werte gehören in eine `config.lua` (als `shared_script`) oder in
  Convars (`GetConvar('name', 'standard')`), nicht fest in den Code.
- Die Lua-Syntax aller Dateien in diesem Ordner wird von der CI geprüft
  (`luac -p`). Lokal geht das mit `luac5.4 -p datei.lua`.
- Client-Ausgaben für Spieler laufen über `chat:addMessage`, Server-Logs über
  `print()`. Beide siehst du in `hello-world/` im Einsatz.
