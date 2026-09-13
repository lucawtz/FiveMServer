-- probefahrt: schützt den Spieler am Ende einer Probefahrt von qbx_vehicleshop.
-- Hintergrund: Befund 7 in docs/checkliste.md.

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Luca Wirtz'
description 'Hält das Testfahrzeug kurz vor Ende der Probefahrt an und schützt den Spieler beim Teleport'
version '1.0.0'

dependencies {
    'ox_lib',
    'qbx_vehicleshop',
}

shared_script '@ox_lib/init.lua'
client_script 'client.lua'

files {
    'config.lua',
}
