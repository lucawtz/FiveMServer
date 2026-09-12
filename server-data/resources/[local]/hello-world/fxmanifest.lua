-- hello-world: kleine Beispiel-Ressource für den Einstieg.
-- Zeigt einen Server-Befehl (/hallo), ein Server-Event (playerJoining)
-- und eine Client-Begrüßung über das Chat-System.

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Luca Wirtz'
description 'Beispiel-Ressource: /hallo-Befehl, Join-Log und Begrüßung beim Spawn'
version '1.0.0'

server_script 'server.lua'
client_script 'client.lua'
