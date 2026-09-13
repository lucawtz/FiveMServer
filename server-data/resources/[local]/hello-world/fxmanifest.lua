-- hello-world: kleine Beispiel-Ressource für den Einstieg.
-- Zeigt einen Server-Befehl (/hallo), ein Server-Event (playerJoining)
-- und eine Client-Begrüßung über das Chat-System. Braucht kein Framework.

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Luca Wirtz'
description 'Beispiel-Ressource: /hallo-Befehl, Join-Log und Begrüßung nach dem Spawn (mit und ohne Framework)'
version '1.1.0'

server_script 'server.lua'
client_script 'client.lua'
