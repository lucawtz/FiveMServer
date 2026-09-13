#!/usr/bin/env bash
#
# deploy.sh - holt den neuesten Stand aus Git, aktualisiert die Ressourcen, importiert
# neue SQL-Dateien (server-data/database.txt) und startet den fxserver-Dienst neu. Wird von GitHub Actions (deploy.yml) per SSH
# aufgerufen, kann aber auch von Hand laufen.
#
# Aufruf: bash scripts/linux/deploy.sh [--no-restart] [--no-sql] [--update-artifacts [--channel X]]
#
# Laeuft als Service-User (Standard) oder als root. Als root werden git und die
# Ressourcen-Skripte per runuser an den Service-User delegiert, damit der
# Ordner nicht root gehoert.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/linux/lib.sh
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib.sh"

usage() {
    cat <<USAGE
Verwendung: $(basename "$0") [OPTIONEN]

Schritte: git pull --ff-only -> install-resources.sh --update -> setup-database.sh --import -> [update-artifacts.sh] -> systemctl restart fxserver

Optionen:
  --no-restart         Dienst nach dem Update nicht neu starten
  --no-sql             SQL-Import (setup-database.sh --import) ueberspringen
  --update-artifacts   Zusaetzlich die FXServer-Artifacts aktualisieren
  --channel <name>     Channel fuer --update-artifacts (recommended, latest, optional)
  -h, --help           Diese Hilfe anzeigen

Exit-Code ungleich 0, sobald ein Schritt fehlschlaegt.
USAGE
}

NO_RESTART=0
NO_SQL=0
UPDATE_ARTIFACTS=0
CHANNEL="recommended"

while [ $# -gt 0 ]; do
    case "$1" in
        --no-restart) NO_RESTART=1; shift ;;
        --no-sql) NO_SQL=1; shift ;;
        --update-artifacts) UPDATE_ARTIFACTS=1; shift ;;
        --channel)
            [ $# -ge 2 ] || die "--channel braucht einen Wert."
            CHANNEL="$2"; shift 2 ;;
        --channel=*) CHANNEL="${1#--channel=}"; shift ;;
        -h|--help) usage; exit 0 ;;
        *)
            usage >&2
            die "Unbekannte Option: $1" ;;
    esac
done
validate_channel "$CHANNEL"

# main() wird komplett geparst, bevor es laeuft; das abschliessende exit ganz unten
# verhindert, dass bash nach einem git pull weitere Bytes aus der (dann neuen) Datei liest.
main() {
    local root unit service_user user_home done_steps="" start_ts cs_rc sql_rc
    root="$(repo_root)"
    unit="/etc/systemd/system/fxserver.service"
    start_ts="$(date +%s)"
    trap fx_cleanup EXIT

    # Service-User bestimmen: aus der Unit, sonst Besitzer des Projektordners
    service_user=""
    if [ -f "$unit" ]; then
        service_user="$(sed -n 's/^User=//p' "$unit" | head -n 1)"
    fi
    if [ -z "$service_user" ]; then
        service_user="$(stat -c %U "$root" 2>/dev/null || stat -f %Su "$root" 2>/dev/null || true)"
    fi
    [ -n "$service_user" ] || service_user="$(id -un)"

    if is_root; then
        # '|| true' in der Pipeline: fehlt der User, soll die die()-Meldung erscheinen und
        # nicht set -e/pipefail das Skript wortlos beenden.
        user_home="$( (getent passwd "$service_user" 2>/dev/null || true) | cut -d: -f6)"
        [ -n "$user_home" ] || die "Service-User '${service_user}' existiert nicht. Erst install.sh ausfuehren."
        run_as() {
            if command -v runuser >/dev/null 2>&1; then
                runuser -u "$service_user" -- env HOME="$user_home" GIT_TERMINAL_PROMPT=0 "$@"
            else
                sudo -u "$service_user" -H env GIT_TERMINAL_PROMPT=0 "$@"
            fi
        }
        log_info "Laufe als root, delegiere git und Ressourcen an '${service_user}'."
    else
        if [ "$(id -un)" != "$service_user" ]; then
            log_warn "Du bist '$(id -un)', der Dienst laeuft als '${service_user}'. Dateirechte koennten nicht passen."
        fi
        run_as() { GIT_TERMINAL_PROMPT=0 "$@"; }
    fi

    log_step "Deploy: ${root}"

    # 1. Git
    if [ -d "$root/.git" ]; then
        log_info "git pull --ff-only --autostash"
        local before after
        before="$(run_as git -C "$root" rev-parse --short HEAD 2>/dev/null || echo '?')"
        # --autostash legt lokale Aenderungen an versionierten Dateien beiseite und wendet
        # sie nach dem Pull wieder an (Git >= 2.27, auf allen Zielsystemen vorhanden).
        if ! run_as git -C "$root" pull --ff-only --autostash; then
            die "git pull --ff-only fehlgeschlagen (Konflikt mit lokalen Aenderungen oder abweichender Branch?)."
        fi
        # git meldet Exit 0, auch wenn der Autostash danach nicht sauber angewendet werden konnte
        # ("Applying autostash resulted in conflicts"). Dann stehen Konfliktmarker in den Dateien
        # (typisch server.cfg) und der Server darf so nicht neu gestartet werden.
        if [ -n "$(run_as git -C "$root" ls-files --unmerged)" ]; then
            die "git pull hat Konflikte hinterlassen (lokale Aenderungen kollidieren mit dem Upstream). Pruefen: git -C '${root}' status. Lokale Aenderungen verwerfen: git -C '${root}' reset --hard && git -C '${root}' stash drop"
        fi
        after="$(run_as git -C "$root" rev-parse --short HEAD 2>/dev/null || echo '?')"
        if [ "$before" = "$after" ]; then
            log_ok "Git: bereits aktuell (${after})"
            done_steps="${done_steps}  - Git: keine Aenderungen (${after})
"
        else
            log_ok "Git: ${before} -> ${after}"
            done_steps="${done_steps}  - Git: ${before} -> ${after}
"
        fi
        chmod +x "$SCRIPT_DIR"/*.sh 2>/dev/null || true
    else
        log_warn "Kein Git-Repository in ${root}, ueberspringe git pull."
        done_steps="${done_steps}  - Git: uebersprungen (kein Repository)
"
    fi

    # 2. Ressourcen
    log_info "install-resources.sh --update"
    if ! run_as bash "$SCRIPT_DIR/install-resources.sh" --update; then
        die "Ressourcen-Update fehlgeschlagen."
    fi
    done_steps="${done_steps}  - Ressourcen aktualisiert
"

    # 3. SQL-Import
    if [ "$NO_SQL" = "1" ]; then
        log_info "SQL-Import uebersprungen (--no-sql)."
        done_steps="${done_steps}  - SQL-Import: uebersprungen (--no-sql)
"
    else
        # Als Service-User pruefen (frisch eingebundene lib.sh aus dem gerade gezogenen Stand),
        # damit root-Deploys dieselben Dateirechte sehen wie der Dienst.
        cs_rc=0
        # shellcheck disable=SC2016
        run_as bash -c '. "$1/lib.sh" && secrets_get_connection_string "$2" >/dev/null' _ \
            "$SCRIPT_DIR" "$root/server-data/secrets.cfg" || cs_rc=$?
        case "$cs_rc" in
            0)
                log_info "setup-database.sh --import"
                sql_rc=0
                run_as bash "$SCRIPT_DIR/setup-database.sh" --import || sql_rc=$?
                if [ "$sql_rc" -ne 0 ]; then
                    die "SQL-Import fehlgeschlagen (Exit-Code ${sql_rc}), Dienst wird NICHT neu gestartet."
                fi
                done_steps="${done_steps}  - SQL-Import: ausgefuehrt
"
                ;;
            1|2)
                log_warn "Kein mysql_connection_string in secrets.cfg, SQL-Import uebersprungen (Qbox braucht die Datenbank)."
                done_steps="${done_steps}  - SQL-Import: uebersprungen (kein mysql_connection_string)
"
                ;;
            *)
                die "secrets.cfg nicht lesbar"
                ;;
        esac
    fi

    # 4. Artifacts (optional)
    if [ "$UPDATE_ARTIFACTS" = "1" ]; then
        log_info "update-artifacts.sh --channel ${CHANNEL}"
        if ! run_as bash "$SCRIPT_DIR/update-artifacts.sh" --channel "$CHANNEL"; then
            die "Artifact-Update fehlgeschlagen."
        fi
        done_steps="${done_steps}  - Artifacts geprueft/aktualisiert (${CHANNEL})
"
    fi

    check_license_key || true

    # 5. Neustart
    if [ "$NO_RESTART" = "1" ]; then
        log_info "Neustart uebersprungen (--no-restart)."
        done_steps="${done_steps}  - Neustart: uebersprungen
"
    elif ! command -v systemctl >/dev/null 2>&1; then
        log_warn "systemctl nicht gefunden, kein Neustart moeglich (kein systemd?)."
        done_steps="${done_steps}  - Neustart: nicht moeglich (kein systemctl)
"
    else
        log_info "systemctl restart fxserver"
        if is_root; then
            systemctl restart fxserver || die "systemctl restart fxserver fehlgeschlagen."
        else
            if ! sudo -n systemctl restart fxserver; then
                die "sudo systemctl restart fxserver fehlgeschlagen. Fehlt /etc/sudoers.d/fivem-deploy (install.sh)?"
            fi
        fi
        sleep 2
        if systemctl is-active --quiet fxserver; then
            log_ok "fxserver laeuft."
            done_steps="${done_steps}  - Dienst fxserver neu gestartet (aktiv)
"
        else
            log_error "fxserver ist nach dem Neustart nicht aktiv. Logs: journalctl -u fxserver -n 50"
            exit 1
        fi
    fi

    log_step "Deploy abgeschlossen in $(( $(date +%s) - start_ts )) s"
    printf '%s' "$done_steps" >&2
}

main "$@"; exit $?
