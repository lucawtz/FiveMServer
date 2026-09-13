#!/bin/bash
#
# entrypoint.sh - Startskript des FXServer-Containers.
#
# 1. Erzeugt /server-data/secrets.cfg aus Umgebungsvariablen, falls die Datei fehlt
#    und FIVEM_LICENSE_KEY gesetzt ist (FIVEM_LICENSE_KEY, RCON_PASSWORD,
#    STEAM_WEBAPI_KEY, MYSQL_CONNECTION_STRING). OneSync steht bewusst in keiner
#    cfg-Datei (auch nicht hier): txAdmin kommentiert jeden 'onesync'-Setter in
#    geladenen cfgs aus und verwaltet OneSync selbst (Settings > FXServer, Standard an).
# 2. Startet run.sh im txAdmin-Modus (Port 40120, txData in /txData). Port und
#    txData-Pfad kommen als TXHOST_*-Umgebungsvariablen (wie systemd-Unit und
#    start.bat), die alten ConVars txDataPath/txAdminPort gelten als veraltet.
#    Zusaetzliche Argumente werden an run.sh durchgereicht. Direktmodus ohne txAdmin
#    (OneSync kommt dann als Argument vor +exec mit, nicht aus einer cfg):
#      docker compose --env-file .env -f docker/docker-compose.yml \
#        run --rm --service-ports fxserver +set onesync on +exec server.cfg

set -euo pipefail

FX_DIR="/opt/fxserver"
DATA_DIR="/server-data"
TXDATA_DIR="/txData"
SECRETS="$DATA_DIR/secrets.cfg"

log()  { printf '[entrypoint] %s\n' "$*" >&2; }
warn() { printf '[entrypoint] WARNUNG: %s\n' "$*" >&2; }

if [ ! -x "$FX_DIR/run.sh" ]; then
    log "FEHLER: $FX_DIR/run.sh fehlt. Das Image wurde nicht korrekt gebaut."
    exit 1
fi

if [ ! -d "$DATA_DIR" ]; then
    log "FEHLER: $DATA_DIR ist nicht eingebunden. Mounte ../server-data nach /server-data."
    exit 1
fi

if [ ! -f "$DATA_DIR/server.cfg" ]; then
    warn "$DATA_DIR/server.cfg fehlt. Ist server-data korrekt als Volume eingebunden?"
fi

if [ ! -w "$DATA_DIR" ]; then
    warn "$DATA_DIR ist fuer den Container-User (uid $(id -u)) nicht beschreibbar."
    warn "Auf dem Host ausfuehren: sudo chown -R 1000:1000 server-data"
fi

if [ ! -w "$TXDATA_DIR" ]; then
    warn "$TXDATA_DIR ist nicht beschreibbar. txAdmin kann sein Profil nicht speichern."
fi

if [ ! -f "$SECRETS" ]; then
    if [ -n "${FIVEM_LICENSE_KEY:-}" ] && [ -w "$DATA_DIR" ]; then
        # Werte landen in Anfuehrungszeichen in der cfg. Anfuehrungszeichen, Backslash oder
        # Zeilenumbruch im Wert wuerden die Zeile zerlegen (z. B. verkuerztes RCON-Passwort).
        for v in FIVEM_LICENSE_KEY RCON_PASSWORD STEAM_WEBAPI_KEY MYSQL_CONNECTION_STRING; do
            case "${!v:-}" in
                *\"*|*$'\n'*|*\\*)
                    log "FEHLER: $v enthaelt Anfuehrungszeichen, Backslash oder Zeilenumbruch. Das kann secrets.cfg nicht abbilden, bitte anderen Wert waehlen."
                    exit 1 ;;
            esac
        done
        log "Erzeuge $SECRETS aus Umgebungsvariablen."
        {
            printf '# Automatisch erzeugt von docker/entrypoint.sh aus den Umgebungsvariablen der .env.\n'
            printf '# Diese Datei ist per .gitignore ausgeschlossen. Loeschen = beim naechsten Start neu erzeugen.\n'
            printf 'sv_licenseKey "%s"\n' "$FIVEM_LICENSE_KEY"
            [ -z "${RCON_PASSWORD:-}" ] || printf 'set rcon_password "%s"\n' "$RCON_PASSWORD"
            [ -z "${STEAM_WEBAPI_KEY:-}" ] || printf 'set steam_webApiKey "%s"\n' "$STEAM_WEBAPI_KEY"
            [ -z "${MYSQL_CONNECTION_STRING:-}" ] || printf 'set mysql_connection_string "%s"\n' "$MYSQL_CONNECTION_STRING"
            # Kein 'set onesync on' hier: txAdmin wuerde die Zeile beim Laden auskommentieren.
            # txAdmin-Modus: txAdmin setzt OneSync selbst. Direktmodus: '+set onesync on' vor '+exec'.
        } > "$SECRETS"
        chmod 600 "$SECRETS" || true
        if [ "${FIVEM_LICENSE_KEY}" = "changeme" ]; then
            warn "FIVEM_LICENSE_KEY steht noch auf 'changeme'. Ohne gueltigen Key startet der Server nicht richtig."
            warn "Key erstellen: https://portal.cfx.re/servers/registration-keys"
        fi
    else
        warn "$SECRETS fehlt und FIVEM_LICENSE_KEY ist nicht gesetzt (oder /server-data nicht beschreibbar)."
        warn "Entweder .env befuellen oder server-data/secrets.cfg aus secrets.cfg.example anlegen."
    fi
elif grep -Eq '^[[:space:]]*(set[[:space:]]+)?sv_licenseKey[[:space:]]+"?changeme"?' "$SECRETS"; then
    warn "In $SECRETS steht noch sv_licenseKey \"changeme\". Bitte echten Key eintragen."
fi

if [ -f "$SECRETS" ] && [ -r "$SECRETS" ] \
    && ! grep -Eq '^[[:space:]]*set[[:space:]]+mysql_connection_string[[:space:]]+[^[:space:]]' "$SECRETS"; then
    warn "In secrets.cfg fehlt ein aktives 'set mysql_connection_string'. Qbox startet ohne Datenbank nicht."
fi

if [ -z "$(ls -A "$DATA_DIR/resources/[vendor]" 2>/dev/null)" ]; then
    warn "server-data/resources/[vendor] ist leer: auf dem Host scripts/linux/install-resources.sh ausfuehren."
fi

if [ -z "$(ls -A "$DATA_DIR/resources/[cfx-default]" 2>/dev/null)" ]; then
    warn "server-data/resources/[cfx-default] ist leer. Auf dem Host einmal ausfuehren: scripts/linux/install-resources.sh"
fi

cd "$DATA_DIR"
# txAdmin-Konfiguration per Umgebung (TXHOST_INTERFACE bleibt weg, Standard ist 0.0.0.0).
export TXHOST_DATA_PATH="$TXDATA_DIR"
export TXHOST_TXA_PORT=40120
log "Starte FXServer/txAdmin (txAdmin: Port $TXHOST_TXA_PORT, txData: $TXHOST_DATA_PATH)"
exec "$FX_DIR/run.sh" "$@"
