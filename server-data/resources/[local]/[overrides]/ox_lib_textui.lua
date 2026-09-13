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
--   - Standard-Stil im Design des Servers (docs/entscheidungen.md, "Einheitlicher Stil"): dunkle,
--     halbtransparente Fläche mit feiner Linie, runde Ecken, größere fette Schrift, Symbole in der
--     Akzentfarbe, etwas über dem unteren Bildschirmrand. Gibt eine Ressource eigene Stil- oder
--     Farbwerte an, gewinnen diese.
--   - Warnung in der F8-Konsole, wenn eine andere Version von ox_lib läuft als die Grundlage.

---@class TextUIOptions
---@field position? 'right-center' | 'left-center' | 'top-center' | 'bottom-center';
---@field icon? string | {[1]: IconProp, [2]: string};
---@field iconColor? string;
---@field style? string | table;
---@field alignIcon? 'top' | 'center';

local POSITION = 'bottom-center'
local EXPECTED_VERSION = '3.39.0'

-- CSS-Werte für das Kästchen (React-Schreibweise), siehe ox_lib web/src/features/textui
local DEFAULT_STYLE = {
    fontSize = '20px',
    fontWeight = 600,
    padding = '14px 22px',
    marginBottom = '12vh',
    color = '#f5f3ea',
    backgroundColor = 'rgba(26, 24, 7, 0.7)',
    border = '1px solid rgba(245, 243, 234, 0.1)',
    borderRadius = '14px',
    boxShadow = '0 10px 30px rgba(0, 0, 0, 0.3)',
}

-- Farbe der Symbole, wenn die Ressource keine angibt (Akzent aus dem Ladebildschirm)
local ICON_COLOR = '#f1e542'

local loadedVersion = GetResourceMetadata(GetCurrentResourceName(), 'version', 0)
if loadedVersion ~= EXPECTED_VERSION then
    print(('^1[ox_lib_textui.lua] Eigene TextUI passt zu ox_lib v%s, geladen ist v%s. Datei mit dem Original vergleichen (docs/ressourcen.md).^0')
        :format(EXPECTED_VERSION, tostring(loadedVersion)))
end

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
    data.iconColor = data.iconColor or ICON_COLOR
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
