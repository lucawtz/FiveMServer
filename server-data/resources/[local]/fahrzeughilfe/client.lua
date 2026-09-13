-- fahrzeughilfe / client.lua
-- Blendet die Übersicht ein, sobald der Spieler in einem Fahrzeug sitzt, und aus, wenn er
-- aussteigt, das Pausemenü offen ist oder ein Fenster mit Mauszeiger (z. B. Inventar) den Fokus hat.
-- Die Tasten werden bei jeder Aktualisierung neu ausgelesen.

lib.locale()

local config = require 'config'

-- Gespeicherter Zustand pro Spieler: 0 = nie umgeschaltet, 1 = eingeklappt, 2 = ausgeklappt
local KVP_EXPANDED = 'ausgeklappt'
local TOGGLE_COMMAND = '+fahrzeughilfe'

local expanded = config.startExpanded
local storedState = GetResourceKvpInt(KVP_EXPANDED)
if storedState ~= 0 then
    expanded = storedState == 2
end

local visible = false
local watching = false

---Liefert den Text der aktuell belegten Taste.
---@param entry table Eintrag aus config.lua (command oder control, optional fallback)
---@return string
local function keyLabel(entry)
    local hash = entry.control
    if entry.command then
        -- Wie ox_lib (keybind:getCurrentKey): Hash der Belegung mit gesetztem oberstem Bit
        hash = joaat(entry.command) | 0x80000000
    end

    local button = GetControlInstructionalButton(0, hash, true) or ''
    local prefix, text = button:sub(1, 2), button:sub(3)

    if prefix == 't_' and text ~= '' then
        return text
    end
    if prefix == 'b_' then
        -- Sondertasten liefert GTA nur als Symbol-Nummer
        return entry.fallback or locale('special_key')
    end
    return locale('unbound')
end

local function buildGroups()
    local isDriver = cache.seat == -1
    local groups = {}

    for i = 1, #config.groups do
        local group = config.groups[i]
        local entries = {}

        for j = 1, #group.entries do
            local entry = group.entries[j]
            if not entry.driverOnly or isDriver then
                entries[#entries + 1] = { key = keyLabel(entry), label = locale(entry.label) }
            end
        end

        if #entries > 0 then
            groups[#groups + 1] = { title = locale(group.title), entries = entries }
        end
    end

    return groups
end

local function update()
    SendNUIMessage({
        action = 'update',
        visible = visible,
        expanded = expanded,
        side = config.side,
        title = locale('title'),
        toggleKey = keyLabel({ command = TOGGLE_COMMAND, fallback = config.toggleKey }),
        hint = locale(expanded and 'hint_collapse' or 'hint_expand'),
        footer = locale('footer'),
        unboundText = locale('unbound'),
        groups = (visible and expanded) and buildGroups() or {},
    })
end

local function setVisible(state)
    if visible == state then return end
    visible = state
    update()
end

local function watchVehicle()
    if watching then return end
    watching = true

    CreateThread(function()
        -- lib.onCache ruft vor dem Setzen von cache.vehicle auf, deshalb einen Frame warten
        Wait(0)
        while cache.vehicle do
            setVisible(not IsPauseMenuActive() and not IsNuiFocused() and not IsHudHidden())
            Wait(250)
        end
        setVisible(false)
        watching = false
    end)
end

lib.onCache('vehicle', function(vehicle)
    if vehicle then
        watchVehicle()
    end
end)

-- Fahrer- und Beifahrersitz zeigen unterschiedliche Einträge
lib.onCache('seat', function()
    if visible then
        SetTimeout(0, update)
    end
end)

lib.addKeybind({
    name = 'fahrzeughilfe',
    description = locale('keybind'),
    defaultKey = config.toggleKey,
    onPressed = function()
        if not cache.vehicle then return end
        expanded = not expanded
        SetResourceKvpInt(KVP_EXPANDED, expanded and 2 or 1)
        update()
    end,
})

-- Ressource startet neu, während der Spieler schon im Fahrzeug sitzt
if cache.vehicle then
    watchVehicle()
end
