-- fahrzeughilfe / config.lua
--
-- Einträge der Übersicht. Jeder Eintrag zeigt eine Taste und einen Text aus locales/de.json.
--   command    Name einer Tastenbelegung (RegisterKeyMapping). Bei lib.addKeybind aus ox_lib ist
--              das '+' vor dem Namen Pflicht, z. B. '+toggleseatbelt'.
--   control    ID eines GTA-Steuerbefehls (https://docs.fivem.net/docs/game-references/controls/).
--   fallback   Text, falls GTA die Taste nur als Symbol liefert (z. B. Leertaste).
--   driverOnly nur auf dem Fahrersitz anzeigen.
--
-- Stand der Tasten (13.09.2026): qbx_vehiclekeys, qbx_seatbelt, qbx_smallresources (Tempomat,
-- Sitzwechsel, Autoradio), ox_inventory, ox_fuel, ox_lib (Radialmenü), qbx_hud.

return {
    -- Taste zum Aus- und Einklappen. Spieler können sie unter Einstellungen > Tastenbelegung > FiveM ändern.
    toggleKey = 'F6',

    -- Bildschirmseite: 'left' oder 'right'. Rechts liegen die Hinweise von ox_lib (TextUI, Benachrichtigungen).
    side = 'left',

    -- Zustand für Spieler, die noch nie umgeschaltet haben. Danach merkt sich das Spiel ihre Wahl.
    startExpanded = true,

    groups = {
        {
            title = 'group_drive',
            entries = {
                { label = 'engine', command = '+toggleengine', driverOnly = true },
                { label = 'seatbelt', command = '+toggleseatbelt' },
                { label = 'cruise', command = '+toggle_cruise_control', driverOnly = true },
                { label = 'handbrake', control = 76, fallback = 'Leertaste', driverOnly = true },
                { label = 'headlights', control = 74, driverOnly = true },
                { label = 'horn', control = 86, driverOnly = true },
                { label = 'camera', control = 0 },
            },
        },
        {
            title = 'group_vehicle',
            entries = {
                { label = 'exit', control = 75 },
                { label = 'locks', command = '+togglelocks' },
                { label = 'searchkeys', command = '+searchkeys', driverOnly = true },
                { label = 'shuffle', command = '+shuffleSeat' },
                { label = 'trunk', command = '+inv2' },
                { label = 'fuel', command = 'startfueling' },
            },
        },
        {
            title = 'group_more',
            entries = {
                { label = 'radio_station', control = 85 },
                { label = 'vehradio', command = 'togglevehradio' },
                { label = 'radial', command = '+ox_lib-radial' },
                { label = 'hud', command = '+hud_menu' },
            },
        },
    },
}
