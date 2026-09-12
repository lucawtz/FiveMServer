-- hello-world / server.lua
-- Läuft auf dem Server. Registriert den Befehl /hallo und protokolliert,
-- wenn Spieler beitreten oder den Server verlassen.

local PREFIX = '^5[hello-world]^7 '

-- Schickt eine Chat-Nachricht an einen Spieler (oder an alle mit target = -1).
local function sendChat(target, message)
    TriggerClientEvent('chat:addMessage', target, {
        color = { 0, 170, 255 },
        multiline = false,
        args = { 'Server', message }
    })
end

-- /hallo : Der Server begrüßt den Spieler mit seinem Namen.
-- Letzter Parameter false = kein ACE-Recht nötig, jeder darf den Befehl nutzen.
RegisterCommand('hallo', function(source, args, rawCommand)
    -- source 0 bedeutet: Befehl kam aus der Serverkonsole, nicht von einem Spieler.
    if source == 0 then
        print(PREFIX .. 'Hallo Konsole! Der Server läuft und hello-world ist aktiv.')
        return
    end

    local playerName = GetPlayerName(source) or 'Unbekannt'
    sendChat(source, ('Hallo %s! Der Server läuft und die Ressource hello-world ist aktiv.'):format(playerName))
    print(PREFIX .. ('%s (ID %d) hat /hallo benutzt.'):format(playerName, source))
end, false)

-- Wird ausgelöst, sobald ein Spieler die Verbindung fertig aufgebaut hat.
-- 'source' ist dabei die endgültige Server-ID des Spielers.
AddEventHandler('playerJoining', function(oldId)
    local src = source
    local playerName = GetPlayerName(src) or 'Unbekannt'
    print(PREFIX .. ('%s ist beigetreten (ID %s, vorher %s).'):format(playerName, tostring(src), tostring(oldId)))
end)

-- Wird ausgelöst, wenn ein Spieler den Server verlässt.
AddEventHandler('playerDropped', function(reason)
    local src = source
    local playerName = GetPlayerName(src) or 'Unbekannt'
    print(PREFIX .. ('%s hat den Server verlassen (ID %s): %s'):format(playerName, tostring(src), tostring(reason)))
end)

print(PREFIX .. 'Server-Teil geladen. Befehl /hallo ist verfügbar.')
