--[[
    https://github.com/overextended/ox_lib

    This file is licensed under LGPL-3.0 or higher <https://www.gnu.org/licenses/lgpl-3.0.en.html>

    Copyright © 2025 Linden <https://github.com/thelindat>
]]

-- Eigene Fassung von ox_lib/resource/interface/client/notify.lua (Weg B, docs/checkliste.md, Befund 9).
-- resources.txt kopiert diese Datei nach [vendor]/[ox]/ox_lib/resource/interface/client/notify.lua.
-- Grundlage: ox_lib v3.39.0. Nach einem Update von ox_lib die Original-Datei mit dieser vergleichen.
--
-- Abweichungen vom Original:
--   - Die Position ist immer 'top' (oben mittig), auch wenn eine Ressource eine andere angibt (qbx_core schickt
--     immer 'top-right') oder der Spieler sie unter /ox_lib ändert. Oben rechts bleibt frei für Beruf und Geld.
--   - Längere Anzeige: ohne Angabe 7 Sekunden (Original 3), Angaben von 1,5 bis 5 Sekunden werden auf 5 Sekunden
--     verlängert. Kürzere Angaben bleiben, damit schnell wechselnde Meldungen nicht stehen bleiben.
--   - Standard-Stil im Design des Servers (docs/entscheidungen.md, "Einheitlicher Stil"): dunkle, halbtransparente
--     Fläche mit feiner Linie, runde Ecken, fetter Titel, größere und hellere Beschreibung. Gibt eine Ressource
--     eigene Stilwerte an, gewinnen diese, auch einzelne Werte in verschachtelten Einträgen wie '& .description'.
--     Die Symbolfarben nach Typ (Fehler, Erfolg, Warnung) bleiben.
--   - Warnung in der F8-Konsole, wenn eine andere Version von ox_lib läuft als die Grundlage.
--
-- Zurück zum Verhalten des Originals ohne Force: FORCE_POSITION, DEFAULT_DURATION und MIN_DURATION auf nil setzen,
-- DEFAULT_STYLE leeren, install.bat bzw. install-resources.sh ausführen (kopiert die Datei nach [vendor]) und den
-- Server neu starten.

---@alias NotificationPosition 'top' | 'top-right' | 'top-left' | 'bottom' | 'bottom-right' | 'bottom-left' | 'center-right' | 'center-left'
---@alias NotificationType 'info' | 'warning' | 'success' | 'error'
---@alias IconAnimationType 'spin' | 'spinPulse' | 'spinReverse' | 'pulse' | 'beat' | 'fade' | 'beatFade' | 'bounce' | 'shake'

---@class NotifyProps
---@field id? string
---@field title? string
---@field description? string
---@field duration? number
---@field showDuration? boolean
---@field position? NotificationPosition
---@field type? NotificationType
---@field style? { [string]: any }
---@field icon? string | { [1]: IconProp, [2]: string }
---@field iconAnimation? IconAnimationType
---@field iconColor? string
---@field alignIcon? 'top' | 'center'
---@field sound? { bank?: string, set: string, name: string }

local settings = require 'resource.settings'

local EXPECTED_VERSION = '3.39.0'

---@type NotificationPosition?
local FORCE_POSITION = 'top'

-- Millisekunden. Ohne Angabe zeigt ox_lib 3000.
local DEFAULT_DURATION = 7000
local MIN_DURATION = 5000
-- Angaben unter diesem Wert bleiben unverändert
local SHORT_DURATION = 1500

-- Stilwerte für das Kästchen (Mantine sx, siehe ox_lib web/src/features/notifications/NotificationWrapper.tsx).
-- Zahlen gelten als Pixel. Die Breite bleibt bei 300 wie im Original, die Schrift bleibt Roboto.
local DEFAULT_STYLE = {
    color = '#f5f3ea',
    backgroundColor = 'rgba(26, 24, 7, 0.7)',
    border = '1px solid rgba(245, 243, 234, 0.1)',
    borderRadius = 14,
    padding = '12px 16px 12px 12px',
    boxShadow = '0 10px 30px rgba(0, 0, 0, 0.3)',
    -- Titel und Markdown-Überschriften in der Beschreibung. Die Farbe erbt der Titel vom Kästchen.
    ['& .mantine-Text-root'] = {
        fontWeight = 700,
    },
    -- Beschreibung ohne Titel (Original 14 px, grau)
    ['& .description'] = {
        fontSize = 16,
        color = '#f5f3ea',
    },
    -- Beschreibung unter einem Titel (Original 12 px, grau)
    ['& .mantine-Text-root + .description'] = {
        fontSize = 14,
        color = 'rgba(245, 243, 234, 0.8)',
    },
}

local loadedVersion = GetResourceMetadata(GetCurrentResourceName(), 'version', 0)
if loadedVersion ~= EXPECTED_VERSION then
    print(('^1[ox_lib_notify.lua] Eigene Benachrichtigungen passen zu ox_lib v%s, geladen ist v%s. Datei mit dem Original vergleichen (docs/ressourcen.md).^0')
        :format(EXPECTED_VERSION, tostring(loadedVersion)))
end

---@param duration? number
---@return number?
local function buildDuration(duration)
    -- 0 behandelt ox_lib wie keine Angabe
    if type(duration) ~= 'number' or duration <= 0 then
        return DEFAULT_DURATION or duration
    end
    if MIN_DURATION and duration >= SHORT_DURATION and duration < MIN_DURATION then
        return MIN_DURATION
    end
    return duration
end

---@param custom? { [string]: any }
---@return { [string]: any }?
local function buildStyle(custom)
    if custom ~= nil and type(custom) ~= 'table' then return custom end

    local style = {}
    for key, value in pairs(DEFAULT_STYLE) do
        style[key] = value
    end
    if custom then
        for key, value in pairs(custom) do
            local base = style[key]
            if type(base) == 'table' and type(value) == 'table' then
                -- Verschachtelte Einträge wie '& .description' Wert für Wert zusammenführen
                local merged = {}
                for innerKey, innerValue in pairs(base) do
                    merged[innerKey] = innerValue
                end
                for innerKey, innerValue in pairs(value) do
                    merged[innerKey] = innerValue
                end
                style[key] = merged
            else
                style[key] = value
            end
        end
    end
    return next(style) and style or nil
end

---`client`
---@param data NotifyProps
---@diagnostic disable-next-line: duplicate-set-field
function lib.notify(data)
    local sound = settings.notification_audio and data.sound
    local payload = table.clone(data)
    payload.sound = nil
    payload.position = FORCE_POSITION or payload.position or settings.notification_position
    payload.duration = buildDuration(payload.duration)
    payload.style = buildStyle(payload.style)

    SendNUIMessage({
        action = 'notify',
        data = payload
    })

    if not sound then return end

    if sound.bank then lib.requestAudioBank(sound.bank) end

    local soundId = GetSoundId()
    PlaySoundFrontend(soundId, sound.name, sound.set, true)
    ReleaseSoundId(soundId)

    if sound.bank then ReleaseNamedScriptAudioBank(sound.bank) end
end

---@class DefaultNotifyProps
---@field title? string
---@field description? string
---@field duration? number
---@field position? NotificationPosition
---@field status? 'info' | 'warning' | 'success' | 'error'
---@field id? number

---@param data DefaultNotifyProps
function lib.defaultNotify(data)
    -- Backwards compat for v3
    data.type = data.status
    if data.type == 'inform' then data.type = 'info' end
    return lib.notify(data --[[@as NotifyProps]])
end

RegisterNetEvent('ox_lib:notify', lib.notify)
RegisterNetEvent('ox_lib:defaultNotify', lib.defaultNotify)
