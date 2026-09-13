-- spielerinfo / server.lua
-- Liefert dem Client Betrag, Zahlungsstatus und die Zeit bis zur nächsten Zahlung.
-- qbx_core zahlt in einer eigenen Schleife alle paycheckTimeout Minuten, gezählt ab dem eigenen Start.
-- Den genauen Takt gibt qbx_core nicht heraus. Diese Ressource merkt sich deshalb die letzte Zahlung
-- (Event qbx_core:server:onPaycheck) und rechnet von dort weiter. Bis zur ersten Zahlung nach einem
-- Neustart gilt der Start von qbx_core bzw. dieser Ressource als Ausgangspunkt, die Zeit ist dann ungefähr.

local config = require 'config'

local interval = config.paycheckMinutes * 60
local lastPaycheck = os.time()
local exact = false

AddEventHandler('onResourceStart', function(resource)
    if resource ~= 'qbx_core' then return end
    lastPaycheck = os.time()
    exact = false
end)

-- Kommt einmal pro bezahltem Spieler, alle im selben Durchlauf
AddEventHandler('qbx_core:server:onPaycheck', function()
    lastPaycheck = os.time()
    exact = true
end)

local function secondsUntilPaycheck()
    return interval - (os.time() - lastPaycheck) % interval
end

lib.callback.register('spielerinfo:server:einkommen', function(source)
    local player = exports.qbx_core:GetPlayer(source)
    if not player then return nil end

    -- Gleiche Regeln wie pay() in qbx_core/server/loops.lua
    local job = player.PlayerData.job
    local jobData = exports.qbx_core:GetJob(job.name)
    local grade = jobData and jobData.grades[job.grade.level]
    local payment = grade and (grade.payment or job.payment) or 0
    local offDutyPay = jobData and jobData.offDutyPay or false

    return {
        payment = payment,
        paid = payment > 0 and (offDutyPay or job.onduty) and true or false,
        minutes = config.paycheckMinutes,
        secondsLeft = secondsUntilPaycheck(),
        exact = exact,
    }
end)
