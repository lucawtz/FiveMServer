#!/usr/bin/env bash
#
# install.sh - richtet den FiveM-Server auf einem Linux-VPS ein (Ubuntu 24.04 / 22.04, Debian 12).
#
# Voraussetzung: Das Repository ist bereits geklont (z. B. nach /opt/fivem) und du bist root.
#
# Aufruf: sudo bash scripts/linux/install.sh [--user fivem] [--channel recommended] [--with-mariadb]
#                                            [--enable-firewall] [--txadmin-public] [--no-firewall]
#
# Schritte:
#   1. apt-Pakete (git curl xz-utils unzip ca-certificates sudo)
#   2. Service-User anlegen und Repository ihm uebergeben
#   3. FXServer-Artifacts laden, Basis- und Manifest-Ressourcen installieren (als Service-User)
#   4. server-data/secrets.cfg aus der Vorlage mit zufaelligem rcon_password anlegen
#   5. Optional MariaDB samt Datenbank "fivem" einrichten (--with-mariadb)
#   6. systemd-Unit fxserver.service anlegen und aktivieren (nicht starten: Key fehlt noch).
#      txAdmin lauscht auf 0.0.0.0:40120, der Port bleibt per Firewall zu (SSH-Tunnel nutzen)
#   7. sudoers-Regel, damit der Service-User fxserver steuern darf (start|stop|restart; deploy.sh, CI)
#   8. ufw-Regeln (30120/tcp+udp), wenn ufw aktiv ist. Ist ufw installiert, aber aus
#      (Ubuntu-Standard), wird nur laut gewarnt (40120 haengt dann offen im Netz) und nichts
#      eingeschaltet. Mit --enable-firewall werden die erkannten SSH-Ports und 30120 freigegeben
#      und ufw eingeschaltet
#
# Das Skript ist idempotent und kann gefahrlos erneut ausgefuehrt werden.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/linux/lib.sh
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib.sh"

usage() {
    cat <<USAGE
Verwendung: sudo bash $(basename "$0") [OPTIONEN]

Optionen:
  --user <name>      Service-User (Standard: fivem), wird bei Bedarf angelegt
  --channel <name>   Artifact-Channel: recommended (Standard), latest, optional
  --with-mariadb     MariaDB installieren, DB "fivem" + User "fivem"@"localhost" anlegen
  --enable-firewall  Ein installiertes, aber inaktives ufw einschalten (vorher SSH-Port(s) und
                     30120/tcp+udp freigeben). Ohne diese Option wird nur gewarnt
  --txadmin-public   40120/tcp in ufw oeffnen, txAdmin damit oeffentlich (nicht empfohlen)
  --no-firewall      Keine ufw-Regeln anlegen und ufw nicht einschalten
  -h, --help         Diese Hilfe anzeigen
USAGE
}

USER_NAME="fivem"
CHANNEL="recommended"
WITH_MARIADB=0
TXADMIN_PUBLIC=0
NO_FIREWALL=0
ENABLE_FIREWALL=0

while [ $# -gt 0 ]; do
    case "$1" in
        --user)
            [ $# -ge 2 ] || die "--user braucht einen Namen."
            USER_NAME="$2"; shift 2 ;;
        --user=*) USER_NAME="${1#--user=}"; shift ;;
        --channel)
            [ $# -ge 2 ] || die "--channel braucht einen Wert."
            CHANNEL="$2"; shift 2 ;;
        --channel=*) CHANNEL="${1#--channel=}"; shift ;;
        --with-mariadb) WITH_MARIADB=1; shift ;;
        --txadmin-public) TXADMIN_PUBLIC=1; shift ;;
        --enable-firewall) ENABLE_FIREWALL=1; shift ;;
        --no-firewall) NO_FIREWALL=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *)
            usage >&2
            die "Unbekannte Option: $1" ;;
    esac
done

require_root
validate_channel "$CHANNEL"
case "$USER_NAME" in
    ""|*[!a-z0-9_-]*) die "Ungueltiger User-Name '$USER_NAME' (erlaubt: a-z 0-9 _ -)." ;;
esac
if [ "$(uname -s)" != "Linux" ]; then
    die "install.sh ist nur fuer Linux gedacht."
fi
need_cmd systemctl "install.sh setzt systemd voraus."

trap fx_cleanup EXIT

ROOT="$(repo_root)"
if printf '%s' "$ROOT" | LC_ALL=C grep -q '[^A-Za-z0-9/._+:-]'; then
    die "Der Projektpfad '$ROOT' enthaelt Leerzeichen oder Sonderzeichen. Bitte nach einem einfachen Pfad wie /opt/fivem klonen (txAdmin verlangt ohnehin reine ASCII-Pfade)."
fi
SERVER_DATA="$ROOT/server-data"
SECRETS="$SERVER_DATA/secrets.cfg"
SECRETS_EXAMPLE="$SERVER_DATA/secrets.cfg.example"
UNIT_TEMPLATE="$SCRIPT_DIR/fxserver.service.template"
UNIT_FILE="/etc/systemd/system/fxserver.service"
SUDOERS_FILE="/etc/sudoers.d/fivem-deploy"
MARIADB_PASSWORD=""
SUMMARY=""
NEXT_EXTRA=""

note() { SUMMARY="${SUMMARY}  - $*
"; }

# Befehle als Service-User ausfuehren (mit passendem HOME)
USER_HOME=""
run_as_user() {
    if command -v runuser >/dev/null 2>&1; then
        runuser -u "$USER_NAME" -- env HOME="$USER_HOME" GIT_TERMINAL_PROMPT=0 "$@"
    else
        sudo -u "$USER_NAME" -H env GIT_TERMINAL_PROMPT=0 "$@"
    fi
}

# Zeile in einer cfg ersetzen oder anhaengen: set_cfg_line <datei> <regex-der-alten-zeile> <neue-zeile>
set_cfg_line() {
    local file="$1" pattern="$2" newline="$3" tmp
    tmp="${file}.tmp.$$"
    if grep -Eq "$pattern" "$file"; then
        awk -v pat="$pattern" -v repl="$newline" 'BEGIN{done=0} { if (!done && $0 ~ pat) { print repl; done=1 } else print }' "$file" > "$tmp"
        # Besitzer und Rechte der Originaldatei uebernehmen, sonst wuerde mv eine
        # root-eigene 0644-Datei an die Stelle der 0600-Datei des Service-Users setzen.
        chown --reference="$file" "$tmp"
        chmod --reference="$file" "$tmp"
        mv "$tmp" "$file"
    else
        printf '\n%s\n' "$newline" >> "$file"
    fi
}

log_step "1/8 Systempakete"
export DEBIAN_FRONTEND=noninteractive
if command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq
    apt-get install -y -qq git curl xz-utils unzip ca-certificates sudo >/dev/null
    log_ok "git curl xz-utils unzip ca-certificates sudo installiert"
else
    log_warn "apt-get nicht gefunden. Stelle sicher, dass git, curl, xz, unzip und sudo installiert sind."
fi
note "Systempakete geprueft"

log_step "2/8 Service-User '${USER_NAME}' und Rechte"
if id -u "$USER_NAME" >/dev/null 2>&1; then
    log_info "User '${USER_NAME}' existiert bereits."
else
    useradd -m -s /bin/bash "$USER_NAME"
    log_ok "User '${USER_NAME}' angelegt."
fi
USER_HOME="$( (getent passwd "$USER_NAME" 2>/dev/null || true) | cut -d: -f6)"
[ -n "$USER_HOME" ] || die "Konnte das Home-Verzeichnis von '${USER_NAME}' nicht ermitteln."
mkdir -p "$ROOT/txData"
# "user:" ohne Gruppenname = primaere Gruppe des Users (muss nicht wie der User heissen)
chown -R "$USER_NAME:" "$ROOT"
chmod +x "$SCRIPT_DIR"/*.sh 2>/dev/null || true
if [ -f "$ROOT/docker/entrypoint.sh" ]; then
    chmod +x "$ROOT/docker/entrypoint.sh" || true
fi
if [ -d "$ROOT/.git" ]; then
    # Git akzeptiert Repos fremder Besitzer nur, wenn sie als safe.directory markiert sind.
    if ! git config --global --get-all safe.directory 2>/dev/null | grep -qxF "$ROOT"; then
        git config --global --add safe.directory "$ROOT"
    fi
    if ! run_as_user git config --global --get-all safe.directory 2>/dev/null | grep -qxF "$ROOT"; then
        run_as_user git config --global --add safe.directory "$ROOT"
    fi
fi
log_ok "Repository gehoert jetzt '${USER_NAME}': ${ROOT}"
# Der Service-User muss den Pfad auch betreten koennen (z. B. nicht unter /root mit 0700),
# sonst scheitert systemd spaeter mit status=200/CHDIR.
if ! run_as_user test -r "$SERVER_DATA/server.cfg"; then
    die "Der User '${USER_NAME}' kann ${ROOT} nicht lesen (liegt das Repo z. B. unter /root?). Bitte nach /opt/fivem klonen oder die Elternordner mit 'chmod o+x' betretbar machen."
fi
note "Service-User: ${USER_NAME} (Home: ${USER_HOME})"

log_step "3/8 Artifacts und Ressourcen (als ${USER_NAME})"
run_as_user bash "$SCRIPT_DIR/update-artifacts.sh" --channel "$CHANNEL" --if-missing
if ! run_as_user bash "$SCRIPT_DIR/install-resources.sh"; then
    log_warn "Nicht alle Ressourcen konnten installiert werden. Spaeter erneut: scripts/linux/install-resources.sh"
fi
note "Artifacts: $(sed -n 's/^version=//p' "$ROOT/artifacts/VERSION.txt" 2>/dev/null | head -n 1 || echo '?') (${CHANNEL})"

log_step "4/8 secrets.cfg"
if [ -f "$SECRETS" ]; then
    log_info "server-data/secrets.cfg existiert bereits, bleibt unveraendert."
else
    [ -f "$SECRETS_EXAMPLE" ] || die "Vorlage fehlt: $SECRETS_EXAMPLE"
    cp "$SECRETS_EXAMPLE" "$SECRETS"
    RCON_PW="$(random_hex)"
    set_cfg_line "$SECRETS" '^[[:space:]]*#?[[:space:]]*(set[[:space:]]+)?rcon_password' "set rcon_password \"${RCON_PW}\""
    log_ok "secrets.cfg aus Vorlage erstellt, rcon_password zufaellig gesetzt."
fi
chown "$USER_NAME:" "$SECRETS"
chmod 600 "$SECRETS"
check_license_key || true
note "secrets.cfg: ${SECRETS}"

log_step "5/8 MariaDB"
if [ "$WITH_MARIADB" = "1" ]; then
    need_cmd apt-get "MariaDB-Installation braucht apt."
    # Auf das Server-Paket pruefen, nicht auf den Client: ein reiner mariadb-client
    # (z. B. fuer eine fruehere Remote-DB) hat keinen Dienst zum Starten.
    if ! dpkg -s mariadb-server >/dev/null 2>&1; then
        apt-get install -y -qq mariadb-server >/dev/null
        log_ok "mariadb-server installiert."
    else
        log_info "mariadb-server ist bereits installiert."
    fi
    systemctl enable --now mariadb >/dev/null 2>&1 || systemctl enable --now mysql >/dev/null 2>&1 || die "MariaDB-Dienst konnte nicht gestartet werden."
    DB_CLIENT="mariadb"
    command -v mariadb >/dev/null 2>&1 || DB_CLIENT="mysql"
    DB_USER_COUNT="$("$DB_CLIENT" -N -B -e "SELECT COUNT(*) FROM mysql.user WHERE user='fivem' AND host='localhost';")" || die "Keine Verbindung zu MariaDB als root (unix_socket). Laeuft der Dienst?"
    if [ "${DB_USER_COUNT:-0}" -gt 0 ]; then
        log_info "DB-User 'fivem'@'localhost' existiert bereits. Passwort bleibt unveraendert."
        "$DB_CLIENT" -e "CREATE DATABASE IF NOT EXISTS fivem CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
        note "MariaDB: Datenbank fivem vorhanden, User fivem unveraendert"
    else
        MARIADB_PASSWORD="$(random_hex)"
        # SQL per stdin, damit das Passwort nicht als Prozessargument (ps) sichtbar ist
        "$DB_CLIENT" <<SQL
CREATE DATABASE IF NOT EXISTS fivem CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'fivem'@'localhost' IDENTIFIED BY '${MARIADB_PASSWORD}';
GRANT ALL PRIVILEGES ON fivem.* TO 'fivem'@'localhost';
FLUSH PRIVILEGES;
SQL
        set_cfg_line "$SECRETS" '^[[:space:]]*#?[[:space:]]*(set[[:space:]]+)?mysql_connection_string' \
            "set mysql_connection_string \"mysql://fivem:${MARIADB_PASSWORD}@localhost/fivem?charset=utf8mb4\""
        log_ok "Datenbank 'fivem' und User 'fivem'@'localhost' angelegt, Verbindungs-String in secrets.cfg eingetragen."
        note "MariaDB: DB fivem, User fivem angelegt (Passwort steht in secrets.cfg und wird unten einmal ausgegeben)"
    fi
    # secrets.cfg enthaelt jetzt auch das DB-Passwort: Besitzer und 0600 sicherheitshalber erneut setzen
    chown "$USER_NAME:" "$SECRETS"
    chmod 600 "$SECRETS"
else
    log_info "Uebersprungen (--with-mariadb nicht gesetzt)."
fi

log_step "6/8 systemd-Unit"
[ -f "$UNIT_TEMPLATE" ] || die "Vorlage fehlt: $UNIT_TEMPLATE"
sed -e "s|__ROOT__|${ROOT}|g" -e "s|__USER__|${USER_NAME}|g" "$UNIT_TEMPLATE" > "$UNIT_FILE"
chmod 644 "$UNIT_FILE"
systemctl daemon-reload || die "systemctl daemon-reload fehlgeschlagen."
systemctl enable fxserver >/dev/null 2>&1 || die "systemctl enable fxserver fehlgeschlagen."
if systemctl is-active --quiet fxserver; then
    log_info "fxserver laeuft bereits. Neue Unit greift beim naechsten Neustart (systemctl restart fxserver)."
else
    log_ok "fxserver.service angelegt und aktiviert (noch nicht gestartet)."
fi
note "systemd: ${UNIT_FILE} (txAdmin lauscht auf 0.0.0.0:40120, nur per Firewall/SSH-Tunnel erreichbar)"

log_step "7/8 sudoers fuer deploy.sh"
need_cmd visudo "Unter Ubuntu/Debian: apt install sudo"
SYSTEMCTL_PATHS=""
for p in /usr/bin/systemctl /bin/systemctl; do
    if [ -x "$p" ]; then
        SYSTEMCTL_PATHS="${SYSTEMCTL_PATHS} ${p}"
    fi
done
[ -n "$SYSTEMCTL_PATHS" ] || SYSTEMCTL_PATHS="$(command -v systemctl)"
fx_mktemp_dir
SUDOERS_TMP="$FX_TMP/fivem-deploy"
{
    echo "# Erlaubt dem Service-User, den FiveM-Dienst ohne Passwort zu steuern (deploy.sh, GitHub Actions)."
    echo "# Erzeugt von scripts/linux/install.sh"
    for p in $SYSTEMCTL_PATHS; do
        for action in start stop restart; do
            echo "${USER_NAME} ALL=(root) NOPASSWD: ${p} ${action} fxserver, ${p} ${action} fxserver.service"
        done
    done
} > "$SUDOERS_TMP"
if visudo -cf "$SUDOERS_TMP" >/dev/null; then
    install -m 0440 -o root -g root "$SUDOERS_TMP" "$SUDOERS_FILE"
    log_ok "sudoers-Regel geschrieben: ${SUDOERS_FILE}"
else
    die "Die erzeugte sudoers-Datei ist ungueltig (visudo -cf). Nichts installiert."
fi
note "sudoers: ${SUDOERS_FILE}"

log_step "8/8 Firewall (ufw)"
if [ "$NO_FIREWALL" = "1" ]; then
    log_info "Uebersprungen (--no-firewall)."
elif ! command -v ufw >/dev/null 2>&1; then
    log_info "ufw ist nicht installiert, keine Regeln angelegt. Gib 30120/tcp und 30120/udp in deiner Firewall frei."
    log_warn "ACHTUNG: txAdmin (40120/tcp) ist ohne aktive Firewall aus dem Internet erreichbar!"
    log_warn "Empfehlung: apt install ufw && ufw allow OpenSSH && ufw allow 30120/tcp && ufw allow 30120/udp && ufw enable"
elif ! LC_ALL=C ufw status 2>/dev/null | grep -q '^Status: active'; then
    # ufw ist da, aber aus (Ubuntu-Standard). Ohne Firewall ist txAdmin (0.0.0.0:40120) aus
    # dem Internet erreichbar. Eingeschaltet wird trotzdem nur mit --enable-firewall: ufw
    # sperrt sonst als Nebenwirkung alle anderen Dienste auf dem Server, und ein falsch
    # erkannter SSH-Port sperrt dich aus.
    #
    # SSH-Port(s) erkennen: sshd -T (Fehler wie fehlendes sshd duerfen das Skript nicht
    # abbrechen, deshalb '|| true' in der Pipeline) plus ssh.socket, denn Ubuntu 24.04 startet
    # ssh per Socket-Aktivierung und der Port steht dann nur in der Unit.
    SSHD_BIN="$(command -v sshd || true)"
    [ -n "$SSHD_BIN" ] || SSHD_BIN="/usr/sbin/sshd"
    SSH_PORTS="$( ("$SSHD_BIN" -T 2>/dev/null || true) | awk '$1=="port"{print $2}' | tr '\n' ' ')"
    SOCKET_PORTS="$( (systemctl show ssh.socket -p Listen --value 2>/dev/null || true) | sed -n 's/^\(.*:\)\{0,1\}\([0-9][0-9]*\) (Stream).*/\2/p' | tr '\n' ' ')"
    SSH_PORTS="$(printf '%s %s' "$SSH_PORTS" "$SOCKET_PORTS" | tr ' ' '\n' | { grep -E '^[0-9]+$' || true; } | sort -u | tr '\n' ' ')"
    [ -n "$SSH_PORTS" ] || SSH_PORTS="22 "
    if [ "$ENABLE_FIREWALL" != "1" ]; then
        MANUAL_UFW=""
        for p in $SSH_PORTS; do
            MANUAL_UFW="${MANUAL_UFW}ufw allow ${p}/tcp && "
        done
        MANUAL_UFW="${MANUAL_UFW}ufw allow 30120/tcp && ufw allow 30120/udp && ufw enable"
        RERUN_CMD="sudo bash ${SCRIPT_DIR}/install.sh --enable-firewall"
        if [ "$USER_NAME" != "fivem" ]; then
            RERUN_CMD="${RERUN_CMD} --user ${USER_NAME}"
        fi
        if [ "$WITH_MARIADB" = "1" ]; then
            RERUN_CMD="${RERUN_CMD} --with-mariadb"
        fi
        if [ "$TXADMIN_PUBLIC" = "1" ]; then
            RERUN_CMD="${RERUN_CMD} --txadmin-public"
        fi
        log_warn "ACHTUNG: ufw ist installiert, aber AUS. Ohne aktive Firewall ist txAdmin (0.0.0.0:40120) aus dem Internet erreichbar!"
        log_warn "ufw wird nicht automatisch eingeschaltet, weil das alle anderen Dienste auf diesem Server sperren koennte."
        log_warn "Erkannte SSH-Port(s): ${SSH_PORTS% }. Entweder dieses Skript erneut ausfuehren:"
        log_warn "    ${RERUN_CMD}"
        log_warn "Oder von Hand (erst SSH freigeben, sonst sperrst du dich aus):"
        log_warn "    ${MANUAL_UFW}"
        note "ufw: installiert, aber AUS und nicht eingeschaltet. txAdmin 40120 ist offen! (--enable-firewall)"
        NEXT_EXTRA="${NEXT_EXTRA}  6. Firewall einschalten, damit txAdmin (40120) nicht offen im Netz haengt:
       ${RERUN_CMD}
     oder von Hand: ${MANUAL_UFW}
"
    else
        log_info "Schalte ufw ein (--enable-firewall). Standard: eingehend alles zu ausser SSH (${SSH_PORTS% }) und 30120."
        for p in $SSH_PORTS; do
            ufw allow "${p}/tcp" comment 'SSH' >/dev/null
        done
        ufw allow 30120/tcp comment 'FXServer' >/dev/null
        ufw allow 30120/udp comment 'FXServer' >/dev/null
        if [ "$TXADMIN_PUBLIC" = "1" ]; then
            ufw allow 40120/tcp comment 'txAdmin' >/dev/null
        fi
        ufw --force enable >/dev/null
        if [ "$TXADMIN_PUBLIC" = "1" ]; then
            log_ok "ufw eingeschaltet: SSH (${SSH_PORTS% }), 30120/tcp+udp und 40120/tcp offen."
            log_warn "ufw: 40120/tcp (txAdmin) ist oeffentlich erreichbar. txAdmin spricht nur HTTP, sichere es zusaetzlich ab!"
            note "ufw eingeschaltet (SSH ${SSH_PORTS% }, 30120, 40120 offen)"
        else
            log_ok "ufw eingeschaltet: SSH (${SSH_PORTS% }) und 30120/tcp+udp offen, 40120/tcp bleibt zu (SSH-Tunnel)."
            note "ufw eingeschaltet (SSH ${SSH_PORTS% }, 30120), 40120 zu"
        fi
        log_warn "Andere Dienste auf diesem Server (Webserver, Panel, Datenbank von aussen) sind jetzt gesperrt. Bei Bedarf: ufw allow <port>/tcp"
    fi
else
    ufw allow 30120/tcp comment 'FXServer' >/dev/null
    ufw allow 30120/udp comment 'FXServer' >/dev/null
    log_ok "ufw: 30120/tcp und 30120/udp freigegeben."
    if [ "$TXADMIN_PUBLIC" = "1" ]; then
        ufw allow 40120/tcp comment 'txAdmin' >/dev/null
        log_warn "ufw: 40120/tcp (txAdmin) ist oeffentlich erreichbar. txAdmin spricht nur HTTP, sichere es zusaetzlich ab!"
    else
        log_ok "ufw: 40120/tcp (txAdmin) bleibt zu, Zugriff nur per SSH-Tunnel."
    fi
    note "ufw-Regeln gesetzt"
fi

log_step "Fertig"
printf '\nZusammenfassung:\n%s\n' "$SUMMARY" >&2
cat >&2 <<NEXT
Naechste Schritte:
  1. Lizenz-Key eintragen (https://portal.cfx.re/servers/registration-keys):
       nano ${SECRETS}
  2. Server starten:
       systemctl start fxserver
  3. txAdmin-PIN aus dem Log holen:
       journalctl -fu fxserver
  4. txAdmin im Browser oeffnen (per SSH-Tunnel von deinem PC aus):
       ssh -L 40120:127.0.0.1:40120 root@<server-ip>   (jeder SSH-faehige User geht)
       dann http://localhost:40120 oeffnen, PIN eingeben, Cfx.re-Account verknuepfen.
     In txAdmin "Existing Server Data" waehlen: Ordner ${SERVER_DATA}, CFG server.cfg
  5. Spaetere Updates: bash ${SCRIPT_DIR}/deploy.sh
NEXT
printf '%s' "$NEXT_EXTRA" >&2
if [ -n "$MARIADB_PASSWORD" ]; then
    printf '\nMariaDB-Passwort fuer fivem@localhost (steht auch in secrets.cfg): %s\n' "$MARIADB_PASSWORD" >&2
fi
