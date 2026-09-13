#!/usr/bin/env bash
#
# install.sh - richtet den FiveM-Server auf einem Linux-VPS ein (Ubuntu 24.04 / 22.04, Debian 12).
#
# Voraussetzung: Das Repository ist bereits geklont (z. B. nach /opt/fivem) und du bist root.
#
# Aufruf: sudo bash scripts/linux/install.sh [--user fivem] [--channel recommended] [--no-mariadb]
#                                            [--enable-firewall] [--txadmin-public] [--no-firewall]
#
# Schritte:
#   1. apt-Pakete (git curl xz-utils unzip ca-certificates sudo)
#   2. Service-User anlegen und Repository ihm uebergeben
#   3. FXServer-Artifacts laden, Basis- und Manifest-Ressourcen installieren (als Service-User)
#   4. server-data/secrets.cfg aus der Vorlage mit zufaelligem rcon_password anlegen
#   5. MariaDB-Server installieren, starten und Version pruefen (mindestens 10.9, Qbox).
#      Mit --no-mariadb nur den Client (fuer eine Datenbank auf einem anderen Server)
#   6. Datenbank und User anlegen (setup-database.sh --create, schreibt mysql_connection_string)
#      und die SQL-Dateien aus server-data/database.txt importieren (setup-database.sh --import)
#   7. systemd-Unit fxserver.service anlegen und aktivieren (nicht starten: Key fehlt noch).
#      txAdmin lauscht auf 0.0.0.0:40120, der Port bleibt per Firewall zu (SSH-Tunnel nutzen)
#   8. sudoers-Regel, damit der Service-User fxserver steuern darf (start|stop|restart; deploy.sh, CI)
#   9. ufw-Regeln (30120/tcp+udp), wenn ufw aktiv ist. Ist ufw installiert, aber aus
#      (Ubuntu-Standard), wird nur laut gewarnt (40120 haengt dann offen im Netz) und nichts
#      eingeschaltet. Mit --enable-firewall werden die erkannten SSH-Ports und 30120 freigegeben
#      und ufw eingeschaltet
#
# Schlaegt der Datenbank-Teil fehl (Schritte 5 und 6), laufen die Schritte 7 bis 9 trotzdem,
# das Skript endet dann mit Exit-Code 1.
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
  --no-mariadb       Keinen MariaDB-Server installieren und keine lokale DB anlegen (Datenbank
                     auf einem anderen Server). Nur der Client wird bei Bedarf installiert
  --with-mariadb     Veraltet und ohne Wirkung: MariaDB ist jetzt Standard
  --enable-firewall  Ein installiertes, aber inaktives ufw einschalten (vorher SSH-Port(s) und
                     30120/tcp+udp freigeben). Ohne diese Option wird nur gewarnt
  --txadmin-public   40120/tcp in ufw oeffnen, txAdmin damit oeffentlich (nicht empfohlen)
  --no-firewall      Keine ufw-Regeln anlegen und ufw nicht einschalten
  -h, --help         Diese Hilfe anzeigen
USAGE
}

USER_NAME="fivem"
CHANNEL="recommended"
NO_MARIADB=0
WITH_MARIADB_FLAG=0
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
        --no-mariadb) NO_MARIADB=1; shift ;;
        --with-mariadb) WITH_MARIADB_FLAG=1; shift ;;
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
if [ "$WITH_MARIADB_FLAG" = "1" ]; then
    log_info "MariaDB ist jetzt Standard, --with-mariadb ist nicht mehr noetig."
    if [ "$NO_MARIADB" = "1" ]; then
        die "--with-mariadb und --no-mariadb widersprechen sich."
    fi
fi
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
DB_FAILED=0
DB_STATE=""
SUMMARY=""
NEXT_EXTRA=""

print_mariadb_upgrade_help() {
    # print_mariadb_upgrade_help [backup]: Anleitung fuer MariaDB aus dem offiziellen
    # Repository. Mit "backup" steht zuerst die Sicherung (Server hat schon Daten).
    printf '\nMariaDB aus dem offiziellen MariaDB-Repository installieren (Beispiel 12.3 LTS):\n' >&2
    if [ "${1:-}" = "backup" ]; then
        printf '  Backup: sudo mariadb-dump --all-databases > /root/mariadb-vor-upgrade.sql\n' >&2
    fi
    cat >&2 <<'UPGRADE'
  curl -LsSO https://r.mariadb.com/downloads/mariadb_repo_setup
  Pruefsumme aus https://mariadb.com/docs/server/server-management/install-and-upgrade-mariadb/mariadb-package-repository-setup-and-usage (Abschnitt "mariadb_repo_setup Versions") einsetzen:
    echo "<pruefsumme> mariadb_repo_setup" | sha256sum -c -
  sudo bash mariadb_repo_setup --mariadb-server-version="mariadb-12.3"
  sudo apt-get update && sudo apt-get install -y mariadb-server mariadb-client
  danach install.sh erneut ausfuehren
Alternative Anleitung: https://mariadb.org/download/?t=repo-config

UPGRADE
}

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

log_step "1/9 Systempakete"
export DEBIAN_FRONTEND=noninteractive
if command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq
    apt-get install -y -qq git curl xz-utils unzip ca-certificates sudo >/dev/null
    log_ok "git curl xz-utils unzip ca-certificates sudo installiert"
else
    log_warn "apt-get nicht gefunden. Stelle sicher, dass git, curl, xz, unzip und sudo installiert sind."
fi
note "Systempakete geprueft"

log_step "2/9 Service-User '${USER_NAME}' und Rechte"
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

log_step "3/9 Artifacts und Ressourcen (als ${USER_NAME})"
run_as_user bash "$SCRIPT_DIR/update-artifacts.sh" --channel "$CHANNEL" --if-missing
if ! run_as_user bash "$SCRIPT_DIR/install-resources.sh"; then
    log_warn "Nicht alle Ressourcen konnten installiert werden. Spaeter erneut: scripts/linux/install-resources.sh"
fi
note "Artifacts: $(sed -n 's/^version=//p' "$ROOT/artifacts/VERSION.txt" 2>/dev/null | head -n 1 || echo '?') (${CHANNEL})"

log_step "4/9 secrets.cfg"
if [ -f "$SECRETS" ]; then
    log_info "server-data/secrets.cfg existiert bereits, bleibt unveraendert."
else
    [ -f "$SECRETS_EXAMPLE" ] || die "Vorlage fehlt: $SECRETS_EXAMPLE"
    cp "$SECRETS_EXAMPLE" "$SECRETS"
    RCON_PW="$(random_hex)"
    cfg_set_line "$SECRETS" '^[[:space:]]*#?[[:space:]]*(set[[:space:]]+)?rcon_password([[:space:]]|$)' "set rcon_password \"${RCON_PW}\"" \
        || die "rcon_password konnte nicht in secrets.cfg geschrieben werden."
    log_ok "secrets.cfg aus Vorlage erstellt, rcon_password zufaellig gesetzt."
fi
chown "$USER_NAME:" "$SECRETS"
chmod 600 "$SECRETS"
check_license_key || true
note "secrets.cfg: ${SECRETS}"

log_step "5/9 MariaDB"
export DEBIAN_FRONTEND=noninteractive
if [ "$NO_MARIADB" = "1" ]; then
    log_info "Kein MariaDB-Server (--no-mariadb)."
    if ! command -v mariadb >/dev/null 2>&1 && ! command -v mysql >/dev/null 2>&1; then
        if command -v apt-get >/dev/null 2>&1 && apt-get install -y -qq mariadb-client >/dev/null; then
            log_ok "mariadb-client installiert (fuer den SQL-Import gegen eine entfernte Datenbank)."
        else
            log_warn "mariadb-client konnte nicht installiert werden. Der SQL-Import braucht ihn: apt install mariadb-client"
        fi
    fi
    note "MariaDB: kein lokaler Server (--no-mariadb)"
elif ! command -v apt-get >/dev/null 2>&1; then
    log_error "apt-get nicht gefunden, MariaDB kann nicht installiert werden. Installiere MariaDB >= 10.9 selbst und fuehre install.sh erneut aus (oder --no-mariadb)."
    DB_FAILED=1
else
    # Auf das Server-Paket pruefen, nicht auf den Client: ein reiner mariadb-client
    # (z. B. fuer eine fruehere Remote-DB) hat keinen Dienst zum Starten.
    # Nur Status "installed" zaehlt: 'dpkg -s' meldet auch entfernte Pakete mit
    # uebrig gebliebenen Konfigurationsdateien (config-files) als vorhanden.
    # shellcheck disable=SC2016
    mariadb_state="$(dpkg-query -W -f='${db:Status-Status}' mariadb-server 2>/dev/null || true)"
    MARIADB_UPGRADE_HELP=""
    if [ "$mariadb_state" != "installed" ]; then
        # Erst die apt-Kandidatenversion pruefen: ist sie zu alt (z. B. 10.6 unter
        # Ubuntu 22.04), wird nichts installiert, sonst waere spaeter ein Upgrade
        # ueber mehrere Hauptversionen noetig.
        mariadb_cand="$(LC_ALL=C apt-cache policy mariadb-server 2>/dev/null | awk '$1 == "Candidate:" { print $2; exit }')"
        mariadb_cand="${mariadb_cand#*:}"
        mariadb_cand="${mariadb_cand%%[-+~]*}"
        case "$mariadb_cand" in [0-9]*.[0-9]*) ;; *) mariadb_cand="" ;; esac
        mariadb_cand_rc=0
        if [ -n "$mariadb_cand" ]; then
            mariadb_version_ok "${mariadb_cand}-MariaDB" || mariadb_cand_rc=$?
        fi
        # apt wuerde einen installierten MySQL-Server beim Installieren von MariaDB
        # still entfernen (Paketkonflikt). Ausgabe erst sammeln: dpkg-query endet mit
        # Exit 1, sobald ein Muster nichts findet.
        # shellcheck disable=SC2016
        mysql_pkgs="$(dpkg-query -W -f='${binary:Package} ${db:Status-Status}\n' 'mysql-server*' 'percona-server-server*' 2>/dev/null || true)"
        if printf '%s\n' "$mysql_pkgs" | grep -q ' installed$'; then
            log_error "Ein MySQL-Server ist installiert ($(printf '%s\n' "$mysql_pkgs" | awk '$2 == "installed" { printf "%s%s", s, $1; s = " " }')). apt wuerde ihn beim Installieren von MariaDB entfernen. MySQL sichern und entfernen oder install.sh --no-mariadb verwenden (Qbox braucht MariaDB >= 10.9)."
            DB_FAILED=1
        elif [ "$mariadb_cand_rc" = "1" ]; then
            log_error "Die apt-Quellen bieten nur MariaDB ${mariadb_cand} an, Qbox braucht mindestens 10.9. Es wird nichts installiert."
            FX_DB_CHECK="tooold"
            MARIADB_UPGRADE_HELP="neu"
            DB_FAILED=1
        elif apt-get install -y -qq mariadb-server mariadb-client >/dev/null; then
            log_ok "mariadb-server und mariadb-client installiert."
        else
            log_error "apt-get install mariadb-server mariadb-client ist fehlgeschlagen."
            DB_FAILED=1
        fi
    else
        log_info "mariadb-server ist bereits installiert."
    fi
    if [ "$DB_FAILED" = "0" ]; then
        if ! systemctl enable --now mariadb >/dev/null 2>&1 && ! systemctl enable --now mysql >/dev/null 2>&1; then
            log_error "MariaDB-Dienst konnte nicht gestartet werden (systemctl status mariadb)."
            DB_FAILED=1
        fi
    fi
    if [ "$DB_FAILED" = "0" ]; then
        FX_DB_MODE="root"
        DB_RC=0
        if db_find_client; then
            db_work_init
            db_check_server "root ueber unix_socket" || DB_RC=$?
        else
            DB_RC=1
        fi
        if [ "$DB_RC" -ne 0 ]; then
            DB_FAILED=1
            [ "$FX_DB_CHECK" != "tooold" ] || MARIADB_UPGRADE_HELP="backup"
        else
            note "MariaDB: ${FX_DB_VERSION}"
        fi
    fi
    case "$MARIADB_UPGRADE_HELP" in
        backup) print_mariadb_upgrade_help backup ;;
        neu) print_mariadb_upgrade_help ;;
    esac
fi

log_step "6/9 Datenbank und SQL-Import"
if [ "$NO_MARIADB" = "0" ] && [ "$DB_FAILED" = "0" ]; then
    if ! bash "$SCRIPT_DIR/setup-database.sh" --create; then
        log_error "setup-database.sh --create ist fehlgeschlagen (siehe oben)."
        DB_FAILED=1
    fi
fi
if [ "$DB_FAILED" = "0" ]; then
    CS_RC=0
    secrets_get_connection_string "$SECRETS" >/dev/null || CS_RC=$?
    if [ "$CS_RC" = "0" ]; then
        if run_as_user bash "$SCRIPT_DIR/setup-database.sh" --import; then
            DB_STATE="eingerichtet"
        else
            log_error "setup-database.sh --import ist fehlgeschlagen (siehe oben)."
            DB_FAILED=1
        fi
    elif [ "$NO_MARIADB" = "1" ]; then
        log_warn "Qbox braucht eine Datenbank, in secrets.cfg steht aber noch kein mysql_connection_string."
        log_warn "Naechste Schritte: String in ${SECRETS} eintragen, dann: sudo -u ${USER_NAME} bash ${SCRIPT_DIR}/setup-database.sh --import"
        DB_STATE="uebersprungen (--no-mariadb)"
    else
        log_error "Nach --create steht kein aktiver mysql_connection_string in secrets.cfg."
        DB_FAILED=1
    fi
fi
if [ "$DB_FAILED" = "1" ]; then
    DB_STATE="FEHLGESCHLAGEN (siehe oben)"
fi
# secrets.cfg kann jetzt das DB-Passwort enthalten: Besitzer und 0600 sicherheitshalber erneut setzen
if [ -f "$SECRETS" ]; then
    chown "$USER_NAME:" "$SECRETS"
    chmod 600 "$SECRETS"
fi
note "Datenbank: ${DB_STATE}"

log_step "7/9 systemd-Unit"
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

log_step "8/9 sudoers fuer deploy.sh"
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

log_step "9/9 Firewall (ufw)"
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
        if [ "$NO_MARIADB" = "1" ]; then
            RERUN_CMD="${RERUN_CMD} --no-mariadb"
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
        NEXT_EXTRA="${NEXT_EXTRA}  8. Firewall einschalten, damit txAdmin (40120) nicht offen im Netz haengt:
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
  5. Nur Freunde zulassen: License Allowlist in txAdmin, siehe docs/linux-server.md,
     Abschnitt "Nur Freunde zulassen (License Allowlist)"
  6. Status der SQL-Dateien pruefen:
       sudo -u ${USER_NAME} bash ${SCRIPT_DIR}/setup-database.sh --dry-run
  7. Spaetere Updates (inkl. SQL-Import): bash ${SCRIPT_DIR}/deploy.sh
NEXT
printf '%s' "$NEXT_EXTRA" >&2
printf '\nDatenbank: %s\n' "$DB_STATE" >&2
if [ "$DB_FAILED" = "1" ]; then
    log_error "Die Einrichtung der Datenbank ist fehlgeschlagen (siehe oben). Nach dem Beheben install.sh erneut ausfuehren."
    exit 1
fi
exit 0
