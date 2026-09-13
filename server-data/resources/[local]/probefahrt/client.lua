-- probefahrt / client.lua
-- qbx_vehicleshop beendet die Probefahrt serverseitig: Nach Ablauf der Zeit setzt es den Spieler per
-- SetEntityCoords vor den Händler und löscht das Testfahrzeug, ohne dass der Spieler vorher aussteigt.
-- Wer in dem Moment fährt, wird mit Tempo aus dem Auto gerissen und kann sterben (Befund 7).
-- Diese Ressource ändert qbx_vehicleshop nicht. Sie startet mit der Probefahrt einen eigenen Timer,
-- hält kurz vor dem Ende das Fahrzeug an, lässt den Spieler aussteigen und macht ihn für die Dauer
-- des Teleports unverwundbar.

local config = require 'config'

-- Zählt Beginn und Ende von Probefahrten, damit ein alter Timer keine neue Probefahrt beendet
local run = 0
local protecting = false

local function protectPlayer()
    if protecting then return end
    protecting = true

    local playerId = PlayerId()
    local wasInvincible = GetPlayerInvincible(playerId)
    SetEntityInvincible(cache.ped, true)

    local vehicle = cache.vehicle
    if vehicle and DoesEntityExist(vehicle) then
        SetEntityVelocity(vehicle, 0.0, 0.0, 0.0)
        -- Flag 16: sofort aussteigen, der Spieler steht direkt neben dem Fahrzeug
        TaskLeaveVehicle(cache.ped, vehicle, 16)
    end

    SetTimeout(config.protectionTime, function()
        -- Unverwundbarkeit von anderer Stelle (z. B. Admin-Menü) nicht aufheben
        if not wasInvincible then
            SetEntityInvincible(cache.ped, false)
        end
        protecting = false
    end)
end

AddStateBagChangeHandler('isInTestDrive', ('player:%s'):format(cache.serverId), function(_, _, value)
    run = run + 1
    local thisRun = run

    if not value then
        -- Ende ohne eigenen Timer, z. B. Neustart von qbx_vehicleshop: trotzdem kurz schützen
        protectPlayer()
        return
    end

    -- value ist die Dauer der Probefahrt in Minuten (testDrive.limit)
    local delay = math.max(math.floor(value * 60000) - config.leadTime, 0)
    SetTimeout(delay, function()
        if thisRun ~= run or not LocalPlayer.state.isInTestDrive then return end
        protectPlayer()
    end)
end)
