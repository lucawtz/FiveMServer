-- hello-world / client.lua
-- Läuft beim Spieler. Begrüßt ihn einmalig nach dem ersten Spawn und
-- trägt /hallo in die Befehlsvorschläge des Chats ein.

local greeted = false

-- 'playerSpawned' kommt vom spawnmanager (wird von basic-gamemode genutzt).
-- Nach jedem Respawn wird es erneut ausgelöst, wir begrüßen aber nur einmal.
AddEventHandler('playerSpawned', function()
    if greeted then
        return
    end
    greeted = true

    TriggerEvent('chat:addMessage', {
        color = { 0, 170, 255 },
        multiline = true,
        args = { 'Server', 'Willkommen! Tippe /hallo in den Chat, um die Beispiel-Ressource zu testen.' }
    })
end)

-- Beim Start dieser Ressource den Befehl im Chat als Vorschlag anzeigen.
AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end
    TriggerEvent('chat:addSuggestion', '/hallo', 'Lässt den Server dich mit deinem Namen begrüßen')
end)

-- Beim Stoppen der Ressource den Vorschlag wieder entfernen.
AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end
    TriggerEvent('chat:removeSuggestion', '/hallo')
end)
