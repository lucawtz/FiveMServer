-- spielerinfo / config.lua

return {
    -- Taste zum Aus- und Einklappen. Spieler können sie unter Einstellungen > Tastenbelegung > FiveM ändern.
    toggleKey = 'F7',

    -- Bildschirmseite: 'left' oder 'right'. Links sitzt im Fahrzeug die Fahrzeug-Hilfe. Die Benachrichtigungen
    -- von ox_lib stehen oben mittig ([local]/[overrides]/ox_lib_notify.lua).
    side = 'right',

    -- Abstand vom oberen Bildschirmrand (CSS-Wert)
    top = '38vh',

    -- Zustand für Spieler, die noch nie umgeschaltet haben. Danach merkt sich das Spiel ihre Wahl.
    startExpanded = true,

    -- Minuten zwischen zwei Zahlungen. Muss zu paycheckTimeout in
    -- [local]/[overrides]/qbx_core_config_server.lua passen, qbx_core gibt den Wert nicht heraus.
    paycheckMinutes = 10,

    -- Jobs, deren Zahlung als Grundsicherung statt als Gehalt erscheint. Für sie fehlt die Zeile "Dienst".
    basicIncomeJobs = {
        unemployed = true,
    },
}
