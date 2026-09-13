-- fahrzeughilfe: ausklappbare Tastenübersicht, solange der Spieler in einem Fahrzeug sitzt.
-- Liest die aktuellen Tastenbelegungen der anderen Ressourcen aus, geänderte Tasten
-- erscheinen deshalb richtig. Reine Anzeige, kein Server-Teil.

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Luca Wirtz'
description 'Ausklappbare Tastenübersicht im Fahrzeug'
version '1.0.0'

dependency 'ox_lib'

shared_script '@ox_lib/init.lua'
client_script 'client.lua'

ui_page 'html/index.html'

files {
    'config.lua',
    'locales/*.json',
    'html/index.html',
    'html/style.css',
    'html/script.js',
}
