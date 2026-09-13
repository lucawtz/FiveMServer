-- spielerinfo: Panel mit Beruf, Einkommen, Bargeld und Kontostand des eigenen Charakters.
-- Beruf, Rang, Dienst und Geld kommen aus den Spielerdaten von qbx_core, Betrag und Zeit bis zur
-- nächsten Zahlung liefert der Server-Teil.

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Luca Wirtz'
description 'Panel mit Beruf, Einkommen, Bargeld und Kontostand'
version '1.0.0'

dependencies {
    'ox_lib',
    'qbx_core',
}

shared_script '@ox_lib/init.lua'
client_script 'client.lua'
server_script 'server.lua'

ui_page 'html/index.html'

files {
    'config.lua',
    'locales/*.json',
    'html/index.html',
    'html/style.css',
    'html/script.js',
}
