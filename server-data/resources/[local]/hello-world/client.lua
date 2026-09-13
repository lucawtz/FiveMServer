-- hello-world / client.lua
-- Läuft beim Spieler. Begrüßt ihn einmalig, sobald er im Spiel ist, und
-- trägt /hallo in die Befehlsvorschläge des Chats ein.
--
-- Die Ressource hängt von keinem Framework ab. Je nach Spawn-Ablauf kommt ein
-- anderes Signal, deshalb hören wir auf mehrere und begrüßen nur einmal:
--   1. 'playerSpawned' vom spawnmanager (ohne Framework; bei Qbox nur, wenn
--      qbx_spawn nicht läuft).
--   2. 'QBCore:Client:OnPlayerLoaded' von Qbox (qbx_core, qbx_spawn) nach der
--      Charakterauswahl. Nur ein Eventname: ohne Qbox kommt es nie, es entsteht
--      keine Abhängigkeit.
--   3. Rückfall: zwei Minuten, nachdem der Spieler im Netzwerk aktiv ist.

local greeted = false

local function greetOnce()
    if greeted then
        return
    end
    greeted = true

    TriggerEvent('chat:addMessage', {
        color = { 0, 170, 255 },
        multiline = true,
        args = { 'Server', 'Willkommen! Tippe /hallo in den Chat, um die Beispiel-Ressource zu testen.' }
    })
end

AddEventHandler('playerSpawned', greetOnce)
AddEventHandler('QBCore:Client:OnPlayerLoaded', greetOnce)

CreateThread(function()
    while not NetworkIsPlayerActive(PlayerId()) do
        Wait(1000)
    end
    Wait(120000)
    greetOnce()
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
