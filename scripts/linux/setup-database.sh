#!/usr/bin/env bash
#
# setup-database.sh - richtet die MariaDB fuer Qbox ein und importiert die SQL-Dateien
# aus server-data/database.txt. Die Tabelle repo_sql_imports merkt sich, welche Datei
# mit welchem sha256 schon importiert wurde (Details: docs/datenbank.md).
#
# Beispiele:
#   sudo bash scripts/linux/setup-database.sh --create              # DB + User anlegen, secrets.cfg schreiben
#   bash scripts/linux/setup-database.sh                            # ausstehende SQL-Dateien importieren
#   bash scripts/linux/setup-database.sh --dry-run                  # nur anzeigen
#   bash scripts/linux/setup-database.sh --docker                   # Import in den db-Container (Docker Compose)
#   bash scripts/linux/setup-database.sh --mark-applied --only '<pfad>'
#
# Exit-Codes:
#   0  OK (auch mit Warnungen zu geaenderten Dateien)
#   1  Abbruch vor oder ohne DB-Arbeit (Optionen, Manifest, secrets.cfg, Client fehlt, --create-Voraussetzungen)
#   2  Datenbank nicht erreichbar, Anmeldung fehlgeschlagen, kein MariaDB oder zu alt, db-Container nicht bereit
#   3  SQL-Fehler (Import oder Eintrag fehlgeschlagen, ausstehende Datei fehlt, CREATE/GRANT fehlgeschlagen)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/linux/lib.sh
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib.sh"

usage() {
    cat <<USAGE
Verwendung: $(basename "$0") [OPTIONEN]

Ohne Aktion wird --import ausgefuehrt. Reihenfolge: --create, dann --import.

Optionen:
  --create             DB und User anlegen (root, unix_socket), mysql_connection_string schreiben
  --reset-password     nur mit --create: vorhandenem User ein neues Passwort geben
  --db <name>          Standard fivem (nur --create)
  --db-user <name>     Standard fivem (nur --create)
  --db-port <n>        Standard 3306 (nur --create)
  --import             ausstehende SQL-Dateien importieren (Standard ohne andere Aktion)
  --mark-applied       ausstehende/geaenderte Dateien als importiert eintragen, ohne Ausfuehrung
  --only <pfad>        wiederholbar, beschraenkt import/mark-applied/dry-run
  --dry-run            nur anzeigen
  --check              nur database.txt pruefen, keine Datenbank
  --docker             Client im db-Container (docker compose ... exec -T db)
  --manifest <datei>   anderes SQL-Manifest (Standard server-data/database.txt)
  --secrets <datei>    andere secrets.cfg (Standard server-data/secrets.cfg)
  -h, --help           Diese Hilfe anzeigen

Werte gehen als '--db fivem' oder '--db=fivem'.

Exit-Codes: 0 OK, 1 Abbruch ohne DB-Arbeit, 2 Datenbank nicht erreichbar/Anmeldung/Version,
            3 SQL-Fehler
USAGE
}

CREATE=0
RESET_PASSWORD=0
DB_NAME="fivem"
DB_USER="fivem"
DB_PORT="3306"
IMPORT=0
MARK=0
DRY_RUN=0
CHECK=0
DOCKER=0
MANIFEST=""
SECRETS=""
SET_DB=0
SET_DB_USER=0
SET_DB_PORT=0
SET_SECRETS=0
ONLY=()

while [ $# -gt 0 ]; do
    opt="$1"
    val=""
    inline=0
    case "$opt" in
        --*=*)
            val="${opt#*=}"
            opt="${opt%%=*}"
            inline=1 ;;
    esac
    case "$opt" in
        --db|--db-user|--db-port|--only|--manifest|--secrets)
            if [ "$inline" = "0" ]; then
                if [ $# -lt 2 ]; then
                    usage >&2
                    die "${opt} braucht einen Wert."
                fi
                val="$2"
                shift
            fi
            [ -n "$val" ] || die "${opt} braucht einen Wert."
            ;;
        *)
            if [ "$inline" = "1" ]; then
                usage >&2
                die "${opt} erwartet keinen Wert."
            fi
            ;;
    esac
    shift
    case "$opt" in
        --create) CREATE=1 ;;
        --reset-password) RESET_PASSWORD=1 ;;
        --db) DB_NAME="$val"; SET_DB=1 ;;
        --db-user) DB_USER="$val"; SET_DB_USER=1 ;;
        --db-port) DB_PORT="$val"; SET_DB_PORT=1 ;;
        --import) IMPORT=1 ;;
        --mark-applied) MARK=1 ;;
        --only) ONLY+=("$val") ;;
        --dry-run) DRY_RUN=1 ;;
        --check) CHECK=1 ;;
        --docker) DOCKER=1 ;;
        --manifest) MANIFEST="$val" ;;
        --secrets) SECRETS="$val"; SET_SECRETS=1 ;;
        -h|--help) usage; exit 0 ;;
        *)
            usage >&2
            die "Unbekannte Option: ${opt}" ;;
    esac
done

# ---------------------------------------------------------------------------
# Unzulaessige Kombinationen (Exit 1)
# ---------------------------------------------------------------------------
if [ "$CHECK" = "1" ]; then
    if [ "$CREATE" = "1" ] || [ "$RESET_PASSWORD" = "1" ] || [ "$SET_DB" = "1" ] || [ "$SET_DB_USER" = "1" ] \
        || [ "$SET_DB_PORT" = "1" ] || [ "$IMPORT" = "1" ] || [ "$MARK" = "1" ] || [ "${#ONLY[@]}" -gt 0 ] \
        || [ "$DRY_RUN" = "1" ] || [ "$DOCKER" = "1" ] || [ "$SET_SECRETS" = "1" ]; then
        die "--check laesst sich nur mit --manifest kombinieren."
    fi
fi
if [ "$CREATE" = "1" ]; then
    [ "$DOCKER" = "0" ] || die "--create geht nicht mit --docker (der db-Container legt Datenbank und User selbst an)."
    [ "$MARK" = "0" ] || die "--create geht nicht mit --mark-applied."
    [ "$DRY_RUN" = "0" ] || die "--create geht nicht mit --dry-run."
fi
if [ "$IMPORT" = "1" ] && [ "$MARK" = "1" ]; then
    die "--import und --mark-applied schliessen sich aus."
fi
if [ "$CREATE" = "0" ]; then
    if [ "$RESET_PASSWORD" = "1" ] || [ "$SET_DB" = "1" ] || [ "$SET_DB_USER" = "1" ] || [ "$SET_DB_PORT" = "1" ]; then
        die "--reset-password, --db, --db-user und --db-port gehen nur zusammen mit --create."
    fi
fi
if [ "${#ONLY[@]}" -gt 0 ] && [ "$CREATE" = "1" ] && [ "$IMPORT" = "0" ]; then
    die "--only geht nicht mit --create allein (nur mit --import, --mark-applied oder --dry-run)."
fi
if [ "$SET_SECRETS" = "1" ] && [ "$DOCKER" = "1" ]; then
    die "--secrets geht nicht mit --docker (die Zugangsdaten kommen aus dem db-Container)."
fi

# Ohne Aktion: --import
if [ "$CREATE" = "0" ] && [ "$MARK" = "0" ] && [ "$CHECK" = "0" ]; then
    IMPORT=1
fi

ROOT="$(repo_root)"
if [ -z "$MANIFEST" ]; then
    MANIFEST="$ROOT/server-data/database.txt"
fi
FX_DB_SECRETS="${SECRETS:-$ROOT/server-data/secrets.cfg}"

trap fx_cleanup EXIT
trap 'exit 130' INT TERM

# ---------------------------------------------------------------------------
# --check
# ---------------------------------------------------------------------------
if [ "$CHECK" = "1" ]; then
    if entries="$(sql_manifest_read "$MANIFEST")"; then
        count="$(printf '%s' "$entries" | grep -c . || true)"
        log_ok "SQL-Manifest gueltig: ${count} Datei(en) (${MANIFEST})"
        exit 0
    fi
    log_error "SQL-Manifest ungueltig: ${MANIFEST}"
    exit 1
fi

# Manifest und --only immer VOR jeder Datenbank-Arbeit pruefen
if [ "$IMPORT" = "1" ] || [ "$MARK" = "1" ]; then
    entries="$(sql_manifest_read "$MANIFEST")" || exit 1
    if [ "${#ONLY[@]}" -gt 0 ]; then
        sql_only_check "$entries" "${ONLY[@]}" || exit 1
    fi
fi

# ---------------------------------------------------------------------------
# --create
# ---------------------------------------------------------------------------
sql_escape() {
    # Wert fuer ein SQL-Literal in '...': \ -> \\ und ' -> \'
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e "s/'/\\\\'/g"
}

do_create() {
    local re_name re_port example owner cs rc s_present=0 s_for_u=0
    local s_host="" s_user="" s_pass="" s_db="" s_socket="" s_port=""
    local has_acc=0 pass="" pass_new=0 sock row grant_db p_sql sql h cnf via

    # 1. Namen, Port und secrets.cfg
    re_name='^[A-Za-z0-9_]{1,32}$'
    re_port='^[0-9]{1,5}$'
    if ! [[ "$DB_NAME" =~ $re_name ]]; then
        log_error "Ungueltiger Datenbankname '${DB_NAME}' (erlaubt: A-Z a-z 0-9 _, 1 bis 32 Zeichen)."
        return 1
    fi
    if ! [[ "$DB_USER" =~ $re_name ]]; then
        log_error "Ungueltiger User-Name '${DB_USER}' (erlaubt: A-Z a-z 0-9 _, 1 bis 32 Zeichen)."
        return 1
    fi
    if ! [[ "$DB_PORT" =~ $re_port ]] || [ "$((10#$DB_PORT))" -lt 1 ] || [ "$((10#$DB_PORT))" -gt 65535 ]; then
        log_error "Ungueltiger Port '${DB_PORT}' (1 bis 65535)."
        return 1
    fi
    DB_PORT="$((10#$DB_PORT))"
    if [ ! -f "$FX_DB_SECRETS" ]; then
        example="$ROOT/server-data/secrets.cfg.example"
        if [ ! -f "$example" ]; then
            log_error "secrets.cfg fehlt und die Vorlage auch: ${example}"
            return 1
        fi
        if ! (umask 077; cp "$example" "$FX_DB_SECRETS"); then
            log_error "Konnte ${FX_DB_SECRETS} nicht aus der Vorlage anlegen."
            return 1
        fi
        chmod 600 "$FX_DB_SECRETS" || true
        owner="$(stat -c %u:%g "$ROOT/server-data/server.cfg" 2>/dev/null || stat -f %u:%g "$ROOT/server-data/server.cfg" 2>/dev/null || true)"
        if [ -n "$owner" ]; then
            chown "$owner" "$FX_DB_SECRETS" 2>/dev/null || log_warn "Konnte den Besitzer von ${FX_DB_SECRETS} nicht auf ${owner} setzen."
        fi
        log_ok "secrets.cfg aus secrets.cfg.example angelegt: ${FX_DB_SECRETS}"
    fi

    # 3. Vorhandenen Verbindungs-String pruefen (vor der Root-Verbindung: ein Abbruch
    #    mit Exit 1 darf noch nichts in der Datenbank angelegt haben)
    rc=0
    cs="$(secrets_get_connection_string "$FX_DB_SECRETS")" || rc=$?
    case "$rc" in
        0)
            if db_parse_connection_string "$cs"; then
                s_present=1
                s_host="$FX_DB_HOST"; s_user="$FX_DB_USER"; s_pass="$FX_DB_PASSWORD"
                s_db="$FX_DB_NAME"; s_socket="$FX_DB_SOCKET"; s_port="$FX_DB_PORT"
            elif [ "$RESET_PASSWORD" = "1" ]; then
                log_warn "Der vorhandene mysql_connection_string ist ungueltig und wird ersetzt (--reset-password)."
            else
                log_error "Der vorhandene mysql_connection_string in ${FX_DB_SECRETS} ist ungueltig. Korrigieren, auskommentieren oder --reset-password verwenden."
                return 1
            fi
            ;;
        1|2) ;;
        *)
            log_error "secrets.cfg ist nicht lesbar: ${FX_DB_SECRETS}"
            return 1 ;;
    esac
    if [ "$s_present" = "1" ]; then
        if [ -z "$s_socket" ]; then
            case "$s_host" in
                localhost|127.0.0.1|::1) ;;
                *)
                    log_error "secrets.cfg zeigt auf einen anderen Datenbankserver (${s_host}); --create richtet nur die lokale MariaDB ein"
                    return 1 ;;
            esac
        fi
        if [ "$s_user" != "$DB_USER" ] || [ "$s_db" != "$DB_NAME" ]; then
            if [ "$RESET_PASSWORD" = "0" ]; then
                log_error "secrets.cfg nutzt User '${s_user}' und Datenbank '${s_db}', --create soll User '${DB_USER}' und Datenbank '${DB_NAME}' einrichten. Entweder '--db-user ${s_user} --db ${s_db}' angeben oder mit --reset-password einen neuen String fuer ${DB_USER}/${DB_NAME} schreiben."
                return 1
            fi
        else
            s_for_u=1
        fi
    fi
    if [ "$s_present" = "1" ] && [ -z "$s_socket" ] && [ "$SET_DB_PORT" = "0" ] && [ "$s_port" != "$DB_PORT" ]; then
        log_info "Uebernehme Port ${s_port} aus dem vorhandenen mysql_connection_string (--db-port ueberschreibt das)."
        DB_PORT="$((10#$s_port))"
    fi
    # Ein behaltener String behielte seinen Port, oxmysql verbaende sich also weiter dorthin.
    if [ "$s_present" = "1" ] && [ -z "$s_socket" ] && [ "$SET_DB_PORT" = "1" ] && [ "$RESET_PASSWORD" = "0" ] \
        && [ "$((10#$s_port))" != "$DB_PORT" ]; then
        log_error "secrets.cfg nutzt Port ${s_port}, --db-port ist ${DB_PORT}. Entweder --db-port ${s_port} angeben oder mit --reset-password einen neuen String schreiben."
        return 1
    fi

    # 2. Root-Verbindung, Version, Datenbank
    db_find_client || return 1
    db_work_init
    FX_DB_MODE="root"
    db_check_server "root ueber unix_socket; laeuft der Dienst? systemctl status mariadb" || return 2
    if ! db_query "SELECT DEFAULT_CHARACTER_SET_NAME, DEFAULT_COLLATION_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='${DB_NAME}';"; then
        log_error "Abfrage der vorhandenen Datenbanken fehlgeschlagen: $(db_err_head)"
        return 3
    fi
    row="$(head -n 1 "$FX_DB_WORK/out" | tr -d '\r')"
    if [ -n "$row" ] && [ "$row" != "utf8mb4	utf8mb4_unicode_ci" ]; then
        log_warn "Datenbank '${DB_NAME}' existiert bereits mit Zeichensatz/Kollation '$(printf '%s' "$row" | tr '\t' '/')' statt utf8mb4/utf8mb4_unicode_ci. Sie bleibt so; bei Fehlern wegen gemischter Kollationen die Datenbank umstellen."
    fi
    if ! db_query "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"; then
        log_error "CREATE DATABASE fehlgeschlagen: $(db_err_head)"
        return 3
    fi
    log_ok "Datenbank '${DB_NAME}' vorhanden."

    # 4. Vorhandene Accounts
    if ! db_query "SELECT host FROM mysql.user WHERE user='${DB_USER}' AND host IN ('localhost','127.0.0.1');"; then
        log_error "Abfrage von mysql.user fehlgeschlagen: $(db_err_head)"
        return 3
    fi
    if grep -q . "$FX_DB_WORK/out"; then
        has_acc=1
    fi

    # 5. Passwort waehlen
    if [ "$has_acc" = "0" ]; then
        if [ "$s_for_u" = "1" ] && [ "$RESET_PASSWORD" = "0" ] && [ -n "$s_pass" ]; then
            pass="$s_pass"
        else
            pass="$(random_hex)"; pass_new=1
        fi
    elif [ "$RESET_PASSWORD" = "1" ]; then
        pass="$(random_hex)"; pass_new=1
    elif [ "$s_for_u" = "1" ]; then
        if ! db_query "SELECT @@socket;"; then
            log_error "Abfrage von @@socket fehlgeschlagen: $(db_err_head)"
            return 3
        fi
        sock="$(head -n 1 "$FX_DB_WORK/out" | tr -d '\r')"
        FX_DB_USER="$DB_USER"; FX_DB_PASSWORD="$s_pass"; FX_DB_NAME=""
        FX_DB_HOST="127.0.0.1"; FX_DB_PORT="$DB_PORT"; FX_DB_SOCKET="$sock"
        cnf="$FX_DB_WORK/login-test.cnf"
        db_write_defaults_file "$cnf" || return 1
        FX_DB_CNF="$cnf"
        FX_DB_MODE="local"
        rc=0
        db_query "SELECT 1;" || rc=$?
        rm -f -- "$cnf"
        FX_DB_CNF=""
        FX_DB_MODE="root"
        if [ "$rc" -ne 0 ]; then
            log_error "Passwort in secrets.cfg passt nicht zum vorhandenen User; --reset-password setzt ein neues"
            return 1
        fi
        pass="$s_pass"
    else
        log_error "User existiert, Passwort unbekannt; --reset-password setzt ein neues"
        return 1
    fi

    # 6. User anlegen und Rechte vergeben (per stdin, Passwort nie auf der Kommandozeile)
    p_sql="$(sql_escape "$pass")"
    grant_db="$(printf '%s' "$DB_NAME" | sed 's/_/\\_/g')"
    # Die Literale sind mit Backslashes maskiert; NO_BACKSLASH_ESCAPES wuerde das aushebeln.
    sql="SET SESSION sql_mode=REPLACE(@@SESSION.sql_mode,'NO_BACKSLASH_ESCAPES','');
"
    for h in localhost 127.0.0.1; do
        sql="${sql}CREATE USER IF NOT EXISTS '${DB_USER}'@'${h}' IDENTIFIED BY '${p_sql}';
ALTER USER '${DB_USER}'@'${h}' IDENTIFIED BY '${p_sql}';
GRANT ALL PRIVILEGES ON \`${grant_db}\`.* TO '${DB_USER}'@'${h}';
"
    done
    sql="${sql}FLUSH PRIVILEGES;"
    if ! db_query "$sql"; then
        log_error "User oder Rechte konnten nicht angelegt werden: $(db_err_head)"
        return 3
    fi
    log_ok "User '${DB_USER}'@'localhost' und '${DB_USER}'@'127.0.0.1' mit allen Rechten auf '${DB_NAME}' eingerichtet."

    # 7. Verbindungs-String schreiben (nur bei neuem Passwort oder fehlendem String)
    if [ "$pass_new" = "1" ] || [ "$s_present" = "0" ]; then
        if ! cfg_set_line "$FX_DB_SECRETS" '^[[:space:]]*#?[[:space:]]*(set[[:space:]]+)?mysql_connection_string([[:space:]]|$)' \
            "set mysql_connection_string \"mysql://${DB_USER}:${pass}@127.0.0.1:${DB_PORT}/${DB_NAME}?charset=utf8mb4\""; then
            log_error "mysql_connection_string konnte nicht in ${FX_DB_SECRETS} geschrieben werden."
            return 1
        fi
        chmod 600 "$FX_DB_SECRETS" || true
        log_ok "mysql_connection_string in secrets.cfg eingetragen (127.0.0.1:${DB_PORT})."
    else
        log_info "mysql_connection_string in secrets.cfg passt und bleibt unveraendert."
    fi

    # 8. Anmeldung als User pruefen, so wie oxmysql verbindet: ueber socketPath, wenn der
    #    behaltene String einen hat, sonst ueber TCP 127.0.0.1
    FX_DB_USER="$DB_USER"; FX_DB_PASSWORD="$pass"; FX_DB_NAME="$DB_NAME"
    FX_DB_HOST="127.0.0.1"; FX_DB_PORT="$DB_PORT"; FX_DB_SOCKET=""
    if [ "$pass_new" = "0" ] && [ "$s_present" = "1" ] && [ -n "$s_socket" ]; then
        FX_DB_SOCKET="$s_socket"
    fi
    via="TCP 127.0.0.1:${DB_PORT}"
    [ -z "$FX_DB_SOCKET" ] || via="Socket ${FX_DB_SOCKET}"
    cnf="$FX_DB_WORK/verify.cnf"
    db_write_defaults_file "$cnf" || return 1
    FX_DB_CNF="$cnf"
    FX_DB_MODE="local"
    rc=0
    db_query "SELECT 1;" || rc=$?
    rm -f -- "$cnf"
    FX_DB_CNF=""
    if [ "$rc" -ne 0 ]; then
        log_error "Anmeldung als '${DB_USER}' ueber ${via} fehlgeschlagen: $(db_err_head)"
        if [ -n "$FX_DB_SOCKET" ]; then
            log_error "Pruefe, ob socketPath im mysql_connection_string zum Socket des Servers passt (SELECT @@socket;). Ueber den Socket gilt der Account '${DB_USER}'@'localhost'."
        else
            log_error "Pruefe in /etc/mysql/mariadb.conf.d/ die Einstellungen bind-address (127.0.0.1 muss erreichbar sein), port und skip-networking. Mit skip-name-resolve gilt nur der Account '${DB_USER}'@'127.0.0.1'."
        fi
        return 2
    fi
    log_ok "Anmeldung als '${DB_USER}' ueber ${via} funktioniert."

    # 9. Neues Passwort einmal anzeigen, aber nur im Terminal (nicht in Logdateien)
    if [ "$pass_new" = "1" ]; then
        if [ -t 2 ]; then
            printf 'MariaDB-Passwort fuer %s (steht in secrets.cfg, wird nicht erneut angezeigt): %s\n' "$DB_USER" "$pass" >&2
        else
            log_info "Neues MariaDB-Passwort fuer ${DB_USER} steht in ${FX_DB_SECRETS} (keine Terminal-Ausgabe, daher nicht angezeigt)."
        fi
    fi
    return 0
}

# Nur ein schreibender Lauf gleichzeitig (deploy.sh, install.sh, Handaufruf): zwei
# ueberlappende Importe saehen dieselbe Datei als ausstehend. Sperre auf dem Ordner
# server-data (lesbar fuer root und Service-User, Inode bleibt bei git pull gleich).
# Der Trockenlauf aendert nichts und wartet nicht.
if [ "$DRY_RUN" = "0" ] && command -v flock >/dev/null 2>&1; then
    exec 9<"$ROOT/server-data"
    if ! flock -n 9; then
        log_info "Ein anderer setup-database-Lauf laeuft noch, warte bis zu 5 Minuten ..."
        flock -w 300 9 || die "Ein anderer setup-database-Lauf laeuft noch (5 Minuten gewartet)."
    fi
fi

if [ "$CREATE" = "1" ]; then
    is_root || die "--create als root ausfuehren (sudo)"
    log_step "Datenbank und User anlegen (--create)"
    rc=0
    do_create || rc=$?
    if [ "$rc" -ne 0 ]; then
        exit "$rc"
    fi
fi

# ---------------------------------------------------------------------------
# --docker: Container pruefen und warten
# ---------------------------------------------------------------------------
if [ "$DOCKER" = "1" ]; then
    FX_DB_MODE="docker"
    if ! command -v docker >/dev/null 2>&1 || ! docker compose version >/dev/null 2>&1; then
        die "docker compose fehlt (Docker Engine mit Compose-Plugin installieren)."
    fi
    [ -f "$ROOT/.env" ] || die ".env fehlt im Projektordner. Zuerst: cp .env.example .env (und Werte eintragen)"
    # Der Import landet in MARIADB_USER/MARIADB_DATABASE des Containers, FXServer liest
    # den mysql_connection_string (secrets.cfg, beim ersten Start aus .env erzeugt).
    # Weichen sie ab, meldet der Import OK, aber Qbox findet seine Tabellen nicht.
    env_val() { sed -n "s/^$1=//p" "$ROOT/.env" | tail -n 1 | tr -d '\r'; }
    env_db="$(env_val MYSQL_DATABASE)"; env_db="${env_db:-fivem}"
    env_user="$(env_val MYSQL_USER)"; env_user="${env_user:-fivem}"
    cs_src="server-data/secrets.cfg"
    cs="$(secrets_get_connection_string "$ROOT/server-data/secrets.cfg" 2>/dev/null)" || cs=""
    if [ -z "$cs" ]; then
        cs_src="MYSQL_CONNECTION_STRING in .env"
        cs="$(env_val MYSQL_CONNECTION_STRING)"
    fi
    if [ -n "$cs" ]; then
        # In einer Subshell parsen, damit die FX_DB_*-Globals unberuehrt bleiben.
        cs_fields="$(db_parse_connection_string "$cs" >/dev/null 2>&1 && printf '%s\t%s' "$FX_DB_USER" "$FX_DB_NAME")" || cs_fields=""
        if [ -n "$cs_fields" ]; then
            cs_user="${cs_fields%%	*}"; cs_db="${cs_fields#*	}"
            if [ "$cs_user" != "$env_user" ] || [ "$cs_db" != "$env_db" ]; then
                log_warn "${cs_src} nutzt User '${cs_user}' und Datenbank '${cs_db}', der db-Container MYSQL_USER '${env_user}' und MYSQL_DATABASE '${env_db}'. Der Import landet in '${env_db}', FXServer liest '${cs_db}'. MYSQL_* wirken ausserdem nur beim ersten Anlegen des Volumes dbdata."
            fi
        fi
    fi
    fx_mktemp_dir
    ps_err="$FX_TMP/compose-ps.err"
    ps_rc=0
    running="$(docker compose --env-file "$ROOT/.env" -f "$ROOT/docker/docker-compose.yml" ps --status running --services 2>"$ps_err")" || ps_rc=$?
    if [ "$ps_rc" -ne 0 ]; then
        log_error "docker compose ps ist fehlgeschlagen (Exit-Code ${ps_rc}): $(head -n 5 "$ps_err" | tr '\n' ' ')"
        log_error "Typische Ursachen: Pflichtwert fehlt in .env (MYSQL_ROOT_PASSWORD, MYSQL_PASSWORD) oder kein Zugriff auf Docker (sudo oder Gruppe docker)."
        exit 2
    fi
    if ! printf '%s\n' "$running" | grep -qx 'db'; then
        log_error "Der db-Container laeuft nicht. Starten: docker compose --env-file .env -f docker/docker-compose.yml up -d --wait db"
        exit 2
    fi
    rc=0
    db_docker_wait "$ROOT" "${FX_DOCKER_WAIT_SECONDS:-120}" || rc=$?
    if [ "$rc" -ne 0 ]; then
        exit "$rc"
    fi
fi

# ---------------------------------------------------------------------------
# --import / --mark-applied / --dry-run
# ---------------------------------------------------------------------------
if [ "$IMPORT" = "1" ] || [ "$MARK" = "1" ]; then
    action="import"
    if [ "$MARK" = "1" ]; then
        action="mark"
        log_step "SQL-Dateien als importiert eintragen (--mark-applied)${ONLY[0]+ (nur Auswahl)}"
    else
        log_step "SQL-Import aus $(basename "$MANIFEST")"
    fi
    [ "$DRY_RUN" = "0" ] || log_info "Trockenlauf (--dry-run): es wird nichts geaendert."
    rc=0
    db_import_run "$action" "$DRY_RUN" "$MANIFEST" ${ONLY[@]+"${ONLY[@]}"} || rc=$?
    exit "$rc"
fi

exit 0
