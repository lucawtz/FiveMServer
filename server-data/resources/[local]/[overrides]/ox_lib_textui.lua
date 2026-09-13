--[[
    https://github.com/overextended/ox_lib

    This file is licensed under LGPL-3.0 or higher <https://www.gnu.org/licenses/lgpl-3.0.en.html>

    Copyright © 2025 Linden <https://github.com/thelindat>
]]

-- Eigene Fassung von ox_lib/resource/interface/client/textui.lua (Weg B, docs/checkliste.md, Befund 6).
-- resources.txt kopiert diese Datei nach [vendor]/[ox]/ox_lib/resource/interface/client/textui.lua.
-- Grundlage: ox_lib v3.39.0. Nach einem Update von ox_lib die Original-Datei mit dieser vergleichen.
--
-- Abweichungen vom Original:
--   - Die Position ist immer 'bottom-center', auch wenn eine Ressource 'left-center' oder
--     'right-center' angibt. So stehen alle Interaktions-Hinweise an derselben, gut sichtbaren Stelle.
--   - Standard-Stil: größere, fette Schrift, farbiger Rand links, etwas über dem unteren Bildschirmrand.
--     Gibt eine Ressource eigene Stilwerte an, gewinnen diese.

---@class TextUIOptions
---@field position? 'right-center' | 'left-center' | 'top-center' | 'bottom-center';
---@field icon? string | {[1]: IconProp, [2]: string};
---@field iconColor? string;
---@field style? string | table;
---@field alignIcon? 'top' | 'center';

local POSITION = 'bottom-center'

-- CSS-Werte für das Kästchen (React-Schreibweise), siehe ox_lib web/src/features/textui
local DEFAULT_STYLE = {
    fontSize = '20px',
    fontWeight = 600,
    padding = '14px 22px',
    marginBottom = '12vh',
    borderLeft = '5px solid #4dabf7',
    boxShadow = '0 4px 16px rgba(0, 0, 0, 0.6)',
}

local isOpen = false
local currentText

---@param custom? string | table
---@return string | table
local function buildStyle(custom)
    if type(custom) == 'string' then return custom end

    local style = {}
    for key, value in pairs(DEFAULT_STYLE) do
        style[key] = value
    end
    if type(custom) == 'table' then
        for key, value in pairs(custom) do
            style[key] = value
        end
    end
    return style
end

---@param text string
---@param options? TextUIOptions
function lib.showTextUI(text, options)
    if currentText == text then return end

    -- Kopie, damit Konfigurationstabellen der aufrufenden Ressource unverändert bleiben
    local data = {}
    if options then
        for key, value in pairs(options) do
            data[key] = value
        end
    end

    data.text = text
    data.position = POSITION
    data.style = buildStyle(data.style)
    currentText = text

    SendNUIMessage({
        action = 'textUi',
        data = data
    })

    isOpen = true
end

function lib.hideTextUI()
    SendNUIMessage({
        action = 'textUiHide'
    })

    isOpen = false
    currentText = nil
end

---@return boolean, string | nil
function lib.isTextUIOpen()
    return isOpen, currentText
end
