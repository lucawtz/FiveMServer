-- spielerinfo / client.lua
-- Zeigt ein Panel mit Beruf, Einkommen und Geld des eigenen Charakters, eingeklappt nur die Kopfzeile.
-- Beruf, Rang, Dienst und Geld kommen aus den Spielerdaten von qbx_core, Betrag und Zeit bis zur
-- nächsten Zahlung fragt der Client beim Server ab: nach dem Einloggen, bei Wechsel von Beruf, Rang
-- oder Dienst und wenn die Zahlung fällig war. Ausgeblendet im Pausemenü, bei offenem Inventar
-- (Mauszeiger) und vor der Charakterauswahl.

lib.locale()

local config = require 'config'

-- Gespeicherter Zustand pro Spieler: 0 = nie umgeschaltet, 1 = eingeklappt, 2 = ausgeklappt
local KVP_EXPANDED = 'ausgeklappt'
local TOGGLE_COMMAND = '+spielerinfo'
-- Mindestabstand zwischen zwei Anfragen an den Server in Millisekunden
local REQUEST_PAUSE = 5000

local expanded = config.startExpanded
local storedState = GetResourceKvpInt(KVP_EXPANDED)
if storedState ~= 0 then
    expanded = storedState == 2
end

local playerData = exports.qbx_core:GetPlayerData() or {}
local income           -- letzte Antwort des Servers
local incomeReceived = 0
local incomeKey        -- Beruf, Rang und Dienst, für die income gilt
local requesting = false
local lastRequest
local lastPayload

RegisterNetEvent('QBCore:Player:SetPlayerData', function(value)
    playerData = value
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    playerData = {}
    income = nil
    incomeKey = nil
end)

---Text der aktuell belegten Taste zum Aus- und Einklappen.
---@return string
local function keyLabel()
    -- Wie ox_lib (keybind:getCurrentKey): Hash der Belegung mit gesetztem oberstem Bit
    local button = GetControlInstructionalButton(0, joaat(TOGGLE_COMMAND) | 0x80000000, true) or ''
    local prefix, text = button:sub(1, 2), button:sub(3)

    if prefix == 't_' and text ~= '' then
        return text
    end
    if prefix == 'b_' then
        return locale('special_key')
    end
    return locale('unbound')
end

---Betrag mit Tausenderpunkten, z. B. 12.500 $
---@param amount number?
---@return string
local function formatMoney(amount)
    local text = tostring(math.floor(tonumber(amount) or 0))
    local sign = ''
    if text:sub(1, 1) == '-' then
        sign, text = '-', text:sub(2)
    end
    text = text:reverse():gsub('(%d%d%d)', '%1.'):reverse()
    if text:sub(1, 1) == '.' then
        text = text:sub(2)
    end
    return ('%s%s $'):format(sign, text)
end

---Sekunden als m:ss
---@param seconds number
---@return string
local function formatDuration(seconds)
    seconds = math.max(0, math.floor(seconds))
    return ('%d:%02d'):format(seconds // 60, seconds % 60)
end

local function requestIncome(key)
    local now = GetGameTimer()
    if requesting or (lastRequest and now - lastRequest < REQUEST_PAUSE) then return end
    requesting = true
    lastRequest = now

    CreateThread(function()
        income = lib.callback.await('spielerinfo:server:einkommen', false)
        incomeReceived = GetGameTimer()
        incomeKey = key
        requesting = false
    end)
end

local function addIncomeRows(job, rows)
    local basic = config.basicIncomeJobs[job.name] == true

    if not basic then
        rows[#rows + 1] = { label = locale('duty'), value = locale(job.onduty and 'duty_on' or 'duty_off') }
    end

    if not income then
        rows[#rows + 1] = { label = locale('income'), value = locale('loading') }
        return
    end

    if income.payment <= 0 then
        rows[#rows + 1] = { label = locale('income'), value = locale('income_none') }
        return
    end

    local label = locale(basic and 'basic_income' or 'salary')
    if not income.paid then
        rows[#rows + 1] = { label = label, value = locale('income_off_duty', formatMoney(income.payment)) }
        return
    end

    rows[#rows + 1] = { label = label, value = locale('income_value', formatMoney(income.payment), income.minutes) }

    local left = income.secondsLeft - (GetGameTimer() - incomeReceived) / 1000
    if left <= 0 then
        -- Zahlung war fällig: neuen Zeitpunkt beim Server holen
        requestIncome(incomeKey)
    end
    rows[#rows + 1] = {
        label = locale('next_payment'),
        value = locale(income.exact and 'next_in' or 'next_in_approx', formatDuration(left)),
    }
end

local function buildPayload()
    local job = playerData.job
    local visible = LocalPlayer.state.isLoggedIn and job ~= nil
        and not IsPauseMenuActive() and not IsNuiFocused() and not IsHudHidden()

    local payload = {
        action = 'update',
        visible = visible and true or false,
        expanded = expanded,
        side = config.side,
        top = config.top,
        title = locale('title'),
        toggleKey = keyLabel(),
        hint = locale(expanded and 'hint_collapse' or 'hint_expand'),
        footer = locale('footer'),
        rows = {},
    }
    if not visible then return payload end

    local key = ('%s:%s:%s'):format(job.name, job.grade and job.grade.level or 0, tostring(job.onduty))
    if key ~= incomeKey then
        requestIncome(key)
    end

    if not expanded then return payload end

    local rows = payload.rows
    local jobText = job.label
    if not config.basicIncomeJobs[job.name] and job.grade and job.grade.name then
        jobText = ('%s, %s'):format(job.label, job.grade.name)
    end
    rows[#rows + 1] = { label = locale('job'), value = jobText }

    addIncomeRows(job, rows)

    local money = playerData.money or {}
    rows[#rows + 1] = { label = locale('cash'), value = formatMoney(money.cash), money = true }
    rows[#rows + 1] = { label = locale('bank'), value = formatMoney(money.bank), money = true }

    return payload
end

CreateThread(function()
    while true do
        local payload = buildPayload()
        local encoded = json.encode(payload)
        if encoded ~= lastPayload then
            lastPayload = encoded
            SendNUIMessage(payload)
        end
        Wait(250)
    end
end)

lib.addKeybind({
    name = 'spielerinfo',
    description = locale('keybind'),
    defaultKey = config.toggleKey,
    onPressed = function()
        if not LocalPlayer.state.isLoggedIn then return end
        expanded = not expanded
        SetResourceKvpInt(KVP_EXPANDED, expanded and 2 or 1)
    end,
})
