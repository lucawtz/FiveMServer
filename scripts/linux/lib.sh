#!/usr/bin/env bash
# shellcheck shell=bash
#
# lib.sh - gemeinsame Funktionen fuer die Linux-Skripte des FiveM-Servers.
#
# Diese Datei wird von den anderen Skripten per "source" eingebunden und
# fuehrt beim Einbinden selbst nichts aus. Sie laeuft mit bash 3.2+ (macOS)
# und bash 5 (Linux), BSD- und GNU-Tools.
#
# Wichtige Funktionen:
#   log_info / log_warn / log_error / log_step / log_ok / die
#   repo_root                      -> absoluter Pfad zum Projektordner (Test-Hook: FX_REPO_ROOT)
#   fetch_artifact_info <channel>  -> setzt ARTIFACT_URL und ARTIFACT_VERSION
#   fetch_artifact_url  <channel>  -> gibt nur die Download-URL aus
#   download_artifacts  <channel> <force 0|1> [update 0|1]
#   install_base_resources <force 0|1>
#   process_manifest <update 0|1> <force 0|1> [manifest-pfad]   (git, zip, copy)
#   manifest_check <manifest-pfad>  -> prueft resources.txt ohne Netz (inkl. copy-Reihenfolge)
#   check_license_key              -> warnt, wenn secrets.cfg fehlt oder "changeme" enthaelt
#   cfg_set_line <datei> <ERE> <zeile> -> Zeile in einer cfg ersetzen oder anhaengen
#   secrets_get_connection_string <secrets.cfg>, db_parse_connection_string <string>
#   sql_manifest_read <database.txt>, db_import_run <import|mark> <dry 0|1> <manifest> [only...]
#   fx_cleanup                     -> raeumt temporaere Ordner auf (per trap einhaengen)

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    echo "lib.sh wird nur von anderen Skripten eingebunden und nicht direkt gestartet." >&2
    exit 1
fi

FX_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
FX_CHANGELOG_API="${FX_CHANGELOG_API:-https://changelogs-live.fivem.net/api/changelog/versions/linux/server}"
FX_SERVER_DATA_REPO="${FX_SERVER_DATA_REPO:-https://github.com/citizenfx/cfx-server-data.git}"
FX_TMP=""
FX_TMP_LIST=""
ARTIFACT_URL=""
ARTIFACT_VERSION=""

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
if [ -t 2 ]; then
    FX_C_RESET=$'\033[0m'
    FX_C_INFO=$'\033[36m'
    FX_C_WARN=$'\033[33m'
    FX_C_ERR=$'\033[31m'
    FX_C_OK=$'\033[32m'
    FX_C_STEP=$'\033[1m'
else
    FX_C_RESET=""; FX_C_INFO=""; FX_C_WARN=""; FX_C_ERR=""; FX_C_OK=""; FX_C_STEP=""
fi

log_info()  { printf '%s[INFO]%s  %s\n' "$FX_C_INFO" "$FX_C_RESET" "$*" >&2; }
log_warn()  { printf '%s[WARN]%s  %s\n' "$FX_C_WARN" "$FX_C_RESET" "$*" >&2; }
log_error() { printf '%s[FEHLER]%s %s\n' "$FX_C_ERR" "$FX_C_RESET" "$*" >&2; }
log_ok()    { printf '%s[OK]%s    %s\n' "$FX_C_OK" "$FX_C_RESET" "$*" >&2; }
log_step()  { printf '\n%s==> %s%s\n' "$FX_C_STEP" "$*" "$FX_C_RESET" >&2; }
die()       { log_error "$*"; exit 1; }

# ---------------------------------------------------------------------------
# Allgemeine Helfer
# ---------------------------------------------------------------------------
repo_root() {
    # Test-Hook: FX_REPO_ROOT ersetzt den Projektordner (z. B. eine Kopie fuer Tests).
    if [ -n "${FX_REPO_ROOT:-}" ]; then
        (cd "$FX_REPO_ROOT" 2>/dev/null && pwd -P) || printf '%s\n' "$FX_REPO_ROOT"
    else
        (cd "$FX_LIB_DIR/../.." && pwd -P)
    fi
}

need_cmd() {
    # need_cmd <programm> [hinweis]
    if ! command -v "$1" >/dev/null 2>&1; then
        die "Das Programm '$1' fehlt. ${2:-Bitte installiere es und starte das Skript erneut.}"
    fi
}

is_root() {
    [ "$(id -u)" -eq 0 ]
}

require_root() {
    if ! is_root; then
        die "Dieses Skript muss als root laufen (z. B. mit sudo)."
    fi
}

dir_is_empty() {
    # dir_is_empty <ordner> -> 0 wenn leer oder nicht vorhanden
    [ ! -d "$1" ] || [ -z "$(ls -A "$1" 2>/dev/null)" ]
}

fx_strip_bom() {
    # fx_strip_bom <text>: entfernt ein UTF-8-BOM (EF BB BF) am Anfang (wie Get-Content unter Windows)
    printf '%s' "$1" | LC_ALL=C sed '1s/^\xEF\xBB\xBF//'
}

now_utc() {
    date -u +%Y-%m-%dT%H:%M:%SZ
}

random_hex() {
    # 32 Hex-Zeichen (16 Byte Zufall)
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -hex 16
    else
        head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n'
    fi
}

validate_channel() {
    case "$1" in
        recommended|latest|optional) return 0 ;;
        *) die "Unbekannter Channel '$1'. Erlaubt: recommended, latest, optional." ;;
    esac
}

# Temporaere Ordner: fx_mktemp_dir setzt FX_TMP (kein Subshell-Aufruf noetig)
fx_mktemp_dir() {
    local base="${FX_TMPDIR:-${TMPDIR:-/tmp}}"
    FX_TMP="$(mktemp -d "${base%/}/fxserver.XXXXXX")" || die "Konnte keinen temporaeren Ordner anlegen."
    FX_TMP_LIST="${FX_TMP_LIST}${FX_TMP}
"
}

fx_cleanup() {
    local d
    while IFS= read -r d; do
        if [ -n "$d" ] && [ -d "$d" ]; then
            case "$d" in
                */fxserver.*) rm -rf -- "$d" ;;
            esac
        fi
    done <<EOT
$FX_TMP_LIST
EOT
    FX_TMP_LIST=""
}

# rm -rf nur innerhalb des Projektordners und niemals auf leere Variablen
safe_rm_rf() {
    local target="$1" root
    root="$(repo_root)"
    case "$target" in
        ""|/|"$root"|"$root/")
            die "Sicherheitsstopp: rm -rf auf '$target' verweigert." ;;
        "$root"/*) ;;
        *)
            die "Sicherheitsstopp: '$target' liegt nicht im Projektordner '$root'." ;;
    esac
    rm -rf -- "$target"
}

# JSON-Wert auslesen: json_get <datei> <schluessel>. Nutzt jq falls vorhanden; der
# sed-Fallback versteht String-Werte ("key": "wert") und nackte Zahlen ("key": 12345).
json_get() {
    local file="$1" key="$2" val
    if command -v jq >/dev/null 2>&1; then
        jq -r --arg k "$key" '.[$k] // empty' "$file"
        return
    fi
    val="$(sed -n 's/.*"'"$key"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$file" | head -n 1)"
    if [ -z "$val" ]; then
        val="$(sed -n 's/.*"'"$key"'"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$file" | head -n 1)"
    fi
    printf '%s\n' "$val" | sed 's#\\/#/#g'
}

http_download() {
    # http_download <url> <zieldatei> [beschreibung]
    local url="$1" dest="$2" what="${3:-Datei}"
    need_cmd curl "Unter Ubuntu/Debian: apt install curl"
    log_info "Lade ${what}: ${url}"
    if [ -t 2 ]; then
        curl -fL --connect-timeout 20 --retry 3 --retry-delay 2 --progress-bar -o "$dest" "$url" || die "Download fehlgeschlagen: $url"
    else
        curl -fsSL --connect-timeout 20 --retry 3 --retry-delay 2 -o "$dest" "$url" || die "Download fehlgeschlagen: $url"
    fi
}

# ---------------------------------------------------------------------------
# Artifacts (FXServer-Binaries)
# ---------------------------------------------------------------------------
fetch_artifact_info() {
    # setzt ARTIFACT_URL und ARTIFACT_VERSION fuer den Channel
    local channel="${1:-recommended}" json
    validate_channel "$channel"
    need_cmd curl "Unter Ubuntu/Debian: apt install curl"
    fx_mktemp_dir
    json="$FX_TMP/versions.json"
    log_info "Frage Changelog-API ab (${channel}) ..."
    curl -fsSL --connect-timeout 20 --max-time 60 --retry 3 --retry-delay 2 -o "$json" "$FX_CHANGELOG_API" \
        || die "Changelog-API nicht erreichbar: $FX_CHANGELOG_API"
    ARTIFACT_URL="$(json_get "$json" "${channel}_download")"
    ARTIFACT_VERSION="$(json_get "$json" "$channel")"
    if [ -z "$ARTIFACT_URL" ]; then
        die "Die API lieferte keine Download-URL fuer '${channel}_download'. Antwort liegt in $json"
    fi
    if [ -z "$ARTIFACT_VERSION" ]; then
        ARTIFACT_VERSION="unbekannt"
    fi
    log_info "Channel '${channel}': Build ${ARTIFACT_VERSION}"
}

fetch_artifact_url() {
    fetch_artifact_info "$1"
    printf '%s\n' "$ARTIFACT_URL"
}

installed_artifact_version() {
    local file="$1/VERSION.txt"
    if [ -f "$file" ]; then
        sed -n 's/^version=//p' "$file" | head -n 1
    fi
}

write_version_file() {
    # write_version_file <ordner> <channel> <version> <url>
    {
        printf 'channel=%s\n' "$2"
        printf 'version=%s\n' "$3"
        printf 'url=%s\n' "$4"
        printf 'downloaded_at=%s\n' "$(now_utc)"
        printf 'platform=linux\n'
    } > "$1/VERSION.txt"
}

artifacts_complete() {
    # artifacts_complete <ordner>: true, wenn run.sh UND VERSION.txt vorhanden sind.
    # VERSION.txt wird erst nach dem vollstaendigen Entpacken geschrieben, ein abgebrochener
    # Lauf (Strg+C, getrennte SSH-Sitzung) hinterlaesst also einen Ordner ohne VERSION.txt.
    [ -f "$1/run.sh" ] && [ -f "$1/VERSION.txt" ]
}

download_artifacts() {
    # download_artifacts <channel> <force 0|1> [update 0|1]
    #   force=0, update=0 : nur laden, wenn artifacts/run.sh oder artifacts/VERSION.txt fehlt
    #   update=1          : laden, wenn die API eine andere Version meldet
    #   force=1           : immer neu laden
    local channel="${1:-recommended}" force="${2:-0}" update="${3:-0}"
    local root art bak installed tarball
    validate_channel "$channel"
    root="$(repo_root)"
    art="$root/artifacts"
    bak="$root/artifacts.bak"

    if [ -f "$art/run.sh" ] && [ ! -f "$art/VERSION.txt" ]; then
        log_warn "artifacts/run.sh ist vorhanden, aber artifacts/VERSION.txt fehlt. Die Artifacts gelten als unvollstaendig (abgebrochenes Entpacken?) und werden neu geladen."
    fi

    if artifacts_complete "$art" && [ "$force" != "1" ] && [ "$update" != "1" ]; then
        log_info "Artifacts sind bereits vorhanden ($(installed_artifact_version "$art" || true)). Ueberspringe Download."
        log_info "Zum Aktualisieren: scripts/linux/update-artifacts.sh [--channel ${channel}] [--force]"
        return 0
    fi

    fetch_artifact_info "$channel"

    if artifacts_complete "$art" && [ "$force" != "1" ]; then
        installed="$(installed_artifact_version "$art")"
        if [ -n "$installed" ] && [ "$installed" = "$ARTIFACT_VERSION" ]; then
            log_ok "Artifacts sind aktuell (Build ${installed}, Channel ${channel}). Nichts zu tun."
            return 0
        fi
        log_info "Installiert: ${installed:-unbekannt}, verfuegbar: ${ARTIFACT_VERSION}. Aktualisiere."
    fi

    need_cmd tar
    if [ "$(uname -s)" != "Darwin" ] && ! command -v xz >/dev/null 2>&1; then
        die "Zum Entpacken von fx.tar.xz wird 'xz' benoetigt. Unter Ubuntu/Debian: apt install xz-utils"
    fi
    case "$(uname -m)" in
        x86_64|amd64) ;;
        *) log_warn "FXServer fuer Linux laeuft nur auf x86_64. Diese Maschine meldet '$(uname -m)'. Download und Entpacken funktionieren, Starten nicht." ;;
    esac

    fx_mktemp_dir
    tarball="$FX_TMP/fx.tar.xz"
    http_download "$ARTIFACT_URL" "$tarball" "FXServer-Artifacts (Build ${ARTIFACT_VERSION})"

    log_info "Pruefe Archiv ..."
    tar -tJf "$tarball" >/dev/null 2>&1 || die "Das heruntergeladene Archiv ist beschaedigt oder kein tar.xz: $tarball"

    # Alte Artifacts sichern. Ein evtl. vorhandenes artifacts/txData (wenn jemand
    # run.sh direkt im artifacts-Ordner gestartet hat) wandert mit in artifacts.bak
    # und wird nach dem Entpacken wieder zurueckgeholt.
    # Ein kaputter artifacts-Ordner (run.sh oder VERSION.txt fehlt, z. B. abgebrochenes
    # Entpacken) ersetzt keine noch intakte Sicherung: er wird entfernt, artifacts.bak bleibt.
    if [ -d "$art" ]; then
        if artifacts_complete "$art"; then
            if [ -d "$bak" ]; then
                log_info "Entferne aeltere Sicherung artifacts.bak"
                safe_rm_rf "$bak"
            fi
            log_info "Verschiebe bisherige Artifacts nach artifacts.bak"
            mv "$art" "$bak"
        else
            log_warn "artifacts/ ist unvollstaendig (run.sh oder VERSION.txt fehlt) und wird entfernt. Eine vorhandene Sicherung artifacts.bak bleibt erhalten."
            if [ -d "$art/txData" ]; then
                mkdir -p "$bak"
                if [ -d "$bak/txData" ]; then
                    safe_rm_rf "$bak/txData"
                fi
                mv "$art/txData" "$bak/txData"
            fi
            safe_rm_rf "$art"
        fi
    fi

    mkdir -p "$art"
    log_info "Entpacke nach ${art} ..."
    if ! tar -xJf "$tarball" -C "$art" || [ ! -f "$art/run.sh" ]; then
        log_error "Entpacken fehlgeschlagen. Stelle vorherigen Zustand wieder her."
        safe_rm_rf "$art"
        if [ -d "$bak" ]; then
            mv "$bak" "$art"
        fi
        die "Artifacts konnten nicht installiert werden."
    fi
    chmod +x "$art/run.sh"

    if [ -d "$bak/txData" ]; then
        log_warn "Es lag ein txData-Ordner in artifacts/. Er wird beibehalten (artifacts/txData). Die Skripte nutzen aber <repo>/txData."
        mv "$bak/txData" "$art/txData"
        # artifacts.bak wurde evtl. nur fuer txData angelegt und ist jetzt leer
        rmdir "$bak" 2>/dev/null || true
    fi

    write_version_file "$art" "$channel" "$ARTIFACT_VERSION" "$ARTIFACT_URL"
    log_ok "Artifacts installiert: Build ${ARTIFACT_VERSION} (${channel}) in ${art}"
    if [ -d "$bak" ]; then
        log_info "Die vorherige Version liegt in artifacts.bak und wird beim naechsten Update ersetzt."
    fi
}

# ---------------------------------------------------------------------------
# Basis-Ressourcen (cfx-server-data)
# ---------------------------------------------------------------------------
install_base_resources() {
    # install_base_resources <force 0|1>
    local force="${1:-0}" root target src entry name
    root="$(repo_root)"
    target="$root/server-data/resources/[cfx-default]"

    if ! dir_is_empty "$target"; then
        if [ "$force" = "1" ]; then
            log_info "Basis-Ressourcen werden neu installiert (--force): $target"
        else
            log_info "Basis-Ressourcen sind bereits vorhanden ([cfx-default]). Ueberspringe (--force erzwingt Neuinstallation)."
            return 0
        fi
    fi

    need_cmd git "Unter Ubuntu/Debian: apt install git"
    fx_mktemp_dir
    src="$FX_TMP/cfx-server-data"
    log_info "Klone cfx-server-data ..."
    GIT_TERMINAL_PROMPT=0 git clone --depth 1 --quiet "$FX_SERVER_DATA_REPO" "$src" </dev/null \
        || die "git clone von $FX_SERVER_DATA_REPO fehlgeschlagen."
    [ -d "$src/resources" ] || die "Das Repository enthaelt keinen resources-Ordner."

    # Erst nach erfolgreichem Klonen den alten Stand entfernen, damit bei einem
    # Netzwerkfehler kein leeres [cfx-default] zurueckbleibt.
    if [ "$force" = "1" ] && [ -d "$target" ]; then
        log_info "Entferne vorhandene Basis-Ressourcen (--force): $target"
        safe_rm_rf "$target"
    fi
    mkdir -p "$target"
    for entry in "$src/resources"/*; do
        [ -e "$entry" ] || continue
        name="$(basename "$entry")"
        # [local] aus cfx-server-data ist leer, wir haben unser eigenes [local]
        if [ "$name" = "[local]" ]; then
            continue
        fi
        mv "$entry" "$target/"
    done
    rm -rf -- "$src"
    log_ok "Basis-Ressourcen installiert nach server-data/resources/[cfx-default]"
}

# ---------------------------------------------------------------------------
# resources.txt Manifest
# ---------------------------------------------------------------------------
FX_MANIFEST_OK=0
FX_MANIFEST_SKIPPED=0
FX_MANIFEST_FAILED=0
FX_M_KIND=""
FX_M_TARGET=""
FX_M_URL=""
FX_M_REF=""
FX_M_SOURCE=""
FX_M_ERROR=""
FX_M_WARN=""

manifest_git_entry() {
    # manifest_git_entry <target> <dest> <url> <ref> <update> <force>
    local target="$1" dest="$2" url="$3" ref="$4" update="$5" force="$6"
    local -a args
    local clone_dir replace=0

    if [ -d "$dest" ]; then
        if [ "$force" = "1" ]; then
            log_info "[git] ${target}: klone neu und ersetze den vorhandenen Ordner (--force)"
            replace=1
        elif [ "$update" = "1" ]; then
            if [ -d "$dest/.git" ]; then
                log_info "[git] ${target}: git pull --ff-only"
                if GIT_TERMINAL_PROMPT=0 git -C "$dest" pull --ff-only --quiet </dev/null; then
                    log_ok "[git] ${target}: aktualisiert"
                    FX_MANIFEST_OK=$((FX_MANIFEST_OK + 1))
                else
                    log_error "[git] ${target}: Update fehlgeschlagen (lokale Aenderungen? anderer Branch?)"
                    FX_MANIFEST_FAILED=$((FX_MANIFEST_FAILED + 1))
                fi
            else
                log_warn "[git] ${target}: vorhanden, aber kein Git-Repository. Ueberspringe (--force klont neu)."
                FX_MANIFEST_SKIPPED=$((FX_MANIFEST_SKIPPED + 1))
            fi
            return 0
        else
            log_info "[git] ${target}: bereits vorhanden, ueberspringe (--update aktualisiert, --force klont neu)"
            FX_MANIFEST_SKIPPED=$((FX_MANIFEST_SKIPPED + 1))
            return 0
        fi
    fi

    # Erst in einen temporaeren Ordner klonen, dann erst das alte Ziel ersetzen: schlaegt
    # der Clone fehl (Netz, falsche URL oder Ref), bleibt der vorhandene Ordner unangetastet
    # (gleiches Muster wie install_base_resources).
    need_cmd git "Unter Ubuntu/Debian: apt install git"
    fx_mktemp_dir
    clone_dir="$FX_TMP/clone"
    args=(git clone --depth 1 --quiet)
    if [ -n "$ref" ]; then
        args+=(--branch "$ref")
    fi
    args+=("$url" "$clone_dir")
    log_info "[git] ${target}: klone ${url}${ref:+ (ref: $ref)}"
    if ! GIT_TERMINAL_PROMPT=0 "${args[@]}" </dev/null; then
        if [ "$replace" = "1" ]; then
            log_error "[git] ${target}: git clone fehlgeschlagen, der vorhandene Ordner bleibt erhalten."
        else
            log_error "[git] ${target}: git clone fehlgeschlagen"
        fi
        FX_MANIFEST_FAILED=$((FX_MANIFEST_FAILED + 1))
        return 0
    fi
    mkdir -p "$(dirname "$dest")"
    if [ "$replace" = "1" ]; then
        log_info "[git] ${target}: entferne den alten Ordner und uebernehme den neuen Clone"
        safe_rm_rf "$dest"
    fi
    if ! mv "$clone_dir" "$dest"; then
        log_error "[git] ${target}: Clone konnte nicht nach ${dest} verschoben werden."
        FX_MANIFEST_FAILED=$((FX_MANIFEST_FAILED + 1))
        return 0
    fi
    log_ok "[git] ${target}: geklont${ref:+ (ref: $ref)}"
    FX_MANIFEST_OK=$((FX_MANIFEST_OK + 1))
}

manifest_zip_entry() {
    # manifest_zip_entry <target> <dest> <url> <force>
    local target="$1" dest="$2" url="$3" force="$4"
    local archive extract count single src replace=0

    if [ -d "$dest" ]; then
        if [ "$force" = "1" ]; then
            log_info "[zip] ${target}: lade neu und ersetze den vorhandenen Ordner (--force)"
            replace=1
        else
            log_info "[zip] ${target}: bereits vorhanden, ueberspringe (--force laedt neu)"
            FX_MANIFEST_SKIPPED=$((FX_MANIFEST_SKIPPED + 1))
            return 0
        fi
    fi

    need_cmd unzip "Unter Ubuntu/Debian: apt install unzip"
    fx_mktemp_dir
    archive="$FX_TMP/archive.zip"
    extract="$FX_TMP/extract"
    # Erst laden und entpacken, dann erst das alte Ziel ersetzen: schlaegt Download oder
    # Entpacken fehl, bleibt der vorhandene Ordner unangetastet.
    if ! curl -fsSL --connect-timeout 20 --retry 3 --retry-delay 2 -o "$archive" "$url"; then
        if [ "$replace" = "1" ]; then
            log_error "[zip] ${target}: Download fehlgeschlagen, der vorhandene Ordner bleibt erhalten: $url"
        else
            log_error "[zip] ${target}: Download fehlgeschlagen: $url"
        fi
        FX_MANIFEST_FAILED=$((FX_MANIFEST_FAILED + 1))
        return 0
    fi
    mkdir -p "$extract"
    if ! unzip -q "$archive" -d "$extract"; then
        if [ "$replace" = "1" ]; then
            log_error "[zip] ${target}: Archiv konnte nicht entpackt werden, der vorhandene Ordner bleibt erhalten: $url"
        else
            log_error "[zip] ${target}: Archiv konnte nicht entpackt werden: $url"
        fi
        FX_MANIFEST_FAILED=$((FX_MANIFEST_FAILED + 1))
        return 0
    fi
    rm -rf -- "$extract/__MACOSX"

    count="$(find "$extract" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')"
    src="$extract"
    if [ "$count" -eq 1 ]; then
        single="$(find "$extract" -mindepth 1 -maxdepth 1)"
        if [ -d "$single" ]; then
            # Genau ein Top-Level-Ordner: sein Inhalt wird zum Ziel
            src="$single"
        fi
    fi
    mkdir -p "$(dirname "$dest")"
    if [ "$replace" = "1" ]; then
        log_info "[zip] ${target}: entferne den alten Ordner und uebernehme das neue Archiv"
        safe_rm_rf "$dest"
    fi
    if ! mv "$src" "$dest"; then
        log_error "[zip] ${target}: entpacktes Archiv konnte nicht nach ${dest} verschoben werden."
        FX_MANIFEST_FAILED=$((FX_MANIFEST_FAILED + 1))
        return 0
    fi
    log_ok "[zip] ${target}: installiert aus ${url}"
    FX_MANIFEST_OK=$((FX_MANIFEST_OK + 1))
}

manifest_copy_entry() {
    # manifest_copy_entry <quelle> <ziel> <quellpfad> <zielpfad>
    # Datei: nur bei Unterschied schreiben (erst <ziel>.tmp.PID, dann mv -f).
    # Ordner: erst komplett in einen temporaeren Ordner kopieren (ohne .git auf oberster
    # Ebene), dann das alte Ziel entfernen und den neuen Ordner an seine Stelle setzen.
    local source="$1" target="$2" src="$3" dest="$4" parent tmp stage prefix
    prefix="[copy] ${source} -> ${target}"
    parent="$(dirname "$dest")"

    if [ ! -e "$src" ]; then
        log_error "${prefix}: Quelle fehlt: ${source} (steht die Zeile, die sie installiert, weiter oben?)"
        FX_MANIFEST_FAILED=$((FX_MANIFEST_FAILED + 1))
        return 0
    fi
    if [ ! -d "$parent" ]; then
        log_error "${prefix}: Zielordner fehlt: $(dirname "$target") (ist die Ressource installiert?)"
        FX_MANIFEST_FAILED=$((FX_MANIFEST_FAILED + 1))
        return 0
    fi

    if [ -f "$src" ]; then
        if [ -d "$dest" ]; then
            log_error "${prefix}: Ziel ist ein Ordner, Quelle eine Datei"
            FX_MANIFEST_FAILED=$((FX_MANIFEST_FAILED + 1))
            return 0
        fi
        if [ -f "$dest" ] && cmp -s "$src" "$dest"; then
            log_info "${prefix}: unveraendert, ueberspringe"
            FX_MANIFEST_SKIPPED=$((FX_MANIFEST_SKIPPED + 1))
            return 0
        fi
        tmp="${dest}.tmp.$$"
        if cp "$src" "$tmp" && mv -f "$tmp" "$dest"; then
            log_ok "${prefix}: Datei kopiert"
            FX_MANIFEST_OK=$((FX_MANIFEST_OK + 1))
        else
            rm -f -- "$tmp"
            log_error "${prefix}: Kopieren fehlgeschlagen"
            FX_MANIFEST_FAILED=$((FX_MANIFEST_FAILED + 1))
        fi
        return 0
    fi

    if [ -d "$src" ]; then
        if [ -e "$dest" ] && [ ! -d "$dest" ]; then
            log_error "${prefix}: Ziel ist eine Datei, Quelle ein Ordner"
            FX_MANIFEST_FAILED=$((FX_MANIFEST_FAILED + 1))
            return 0
        fi
        fx_mktemp_dir
        stage="$FX_TMP/copy"
        # '-exec ... {} +' statt '\;': nur so meldet find einen fehlgeschlagenen cp als Exit-Code.
        # shellcheck disable=SC2016
        if ! mkdir "$stage" \
            || ! find "$src" -mindepth 1 -maxdepth 1 ! -name .git -exec sh -c 'exec cp -R "$@" "$0"' "$stage" {} +; then
            log_error "${prefix}: Kopieren fehlgeschlagen, das Ziel bleibt unveraendert"
            FX_MANIFEST_FAILED=$((FX_MANIFEST_FAILED + 1))
            return 0
        fi
        if [ -d "$dest" ]; then
            safe_rm_rf "$dest"
        fi
        if ! mv "$stage" "$dest"; then
            log_error "${prefix}: Ordner konnte nicht nach ${dest} verschoben werden"
            FX_MANIFEST_FAILED=$((FX_MANIFEST_FAILED + 1))
            return 0
        fi
        log_ok "${prefix}: Ordner ersetzt"
        FX_MANIFEST_OK=$((FX_MANIFEST_OK + 1))
        return 0
    fi

    log_error "${prefix}: Quelle ist weder Datei noch Ordner"
    FX_MANIFEST_FAILED=$((FX_MANIFEST_FAILED + 1))
}

manifest_target_ok() {
    # manifest_target_ok <ziel> -> 0 wenn zulaessig. Gleiche Regeln wie ConvertTo-SafeTarget
    # in install-resources.ps1: relativ, ohne ':' (Laufwerk), ohne leere Segmente und ohne
    # ein Segment, das genau '.' oder '..' ist. '[vendor]/my..script' ist damit erlaubt,
    # 'foo/./bar', 'foo//bar', '../x' und '/abs' nicht. Endende '/' sind vorher entfernt.
    local rest="$1" seg
    case "$rest" in
        ""|/*|*:*) return 1 ;;
    esac
    while :; do
        seg="${rest%%/*}"
        case "$seg" in
            ""|.|..) return 1 ;;
        esac
        case "$rest" in
            */*) rest="${rest#*/}" ;;
            *) break ;;
        esac
    done
    return 0
}

manifest_parse_line() {
    # manifest_parse_line <zeile>
    # Zerlegt eine Manifest-Zeile und setzt:
    #   FX_M_KIND    git | zip | copy | <unbekannt>; leer bei Kommentar- oder Leerzeile
    #   FX_M_TARGET  Ziel (ohne endende '/')
    #   FX_M_URL     URL (git, zip)
    #   FX_M_REF     Branch oder Tag (git)
    #   FX_M_SOURCE  Quelle (copy, ohne endende '/')
    #   FX_M_ERROR   Fehlertext ohne "Zeile N: " (leer = gueltig)
    #   FX_M_WARN    Warnung ohne "Zeile N: " (z. B. zu viele Felder)
    local line="$1" kind f1 f2 f3 rest
    FX_M_KIND=""; FX_M_TARGET=""; FX_M_URL=""; FX_M_REF=""; FX_M_SOURCE=""; FX_M_ERROR=""; FX_M_WARN=""
    # Kommentare: ganze Zeile ab '#' am Anfang oder ' # ...' am Zeilenende. Vor dem '#'
    # muss Leerraum stehen, damit ein '#' innerhalb einer URL erhalten bleibt (wie
    # install-resources.ps1).
    line="$(printf '%s' "$line" | tr -d '\r' | sed -E 's/(^|[[:space:]]+)#.*$//')"
    kind=""; f1=""; f2=""; f3=""; rest=""
    read -r kind f1 f2 f3 rest <<EOT
$line
EOT
    [ -n "$kind" ] || return 0
    FX_M_KIND="$kind"

    case "$kind" in
        git)
            FX_M_TARGET="$f1"; FX_M_URL="$f2"; FX_M_REF="$f3"
            if [ -n "$rest" ]; then
                FX_M_WARN="zu viele Felder, ignoriere Rest '${rest}'"
            fi
            ;;
        zip)
            FX_M_TARGET="$f1"; FX_M_URL="$f2"
            # zip kennt kein viertes Feld; wie unter Windows nur warnen und ignorieren.
            if [ -n "$f3" ]; then
                FX_M_WARN="zu viele Felder, zip kennt kein viertes Feld, ignoriere Rest '${f3}${rest:+ $rest}'"
            fi
            ;;
        copy)
            FX_M_SOURCE="$f1"; FX_M_TARGET="$f2"
            if [ -n "$f3" ]; then
                FX_M_WARN="zu viele Felder, copy kennt kein drittes Feld, ignoriere Rest '${f3}${rest:+ $rest}'"
            fi
            ;;
        *)
            FX_M_ERROR="unbekannter Typ '${kind}' (erlaubt: git, zip, copy). Ueberspringe."
            return 0
            ;;
    esac

    if [ -z "$FX_M_TARGET" ] \
        || { [ "$kind" = "copy" ] && [ -z "$FX_M_SOURCE" ]; } \
        || { [ "$kind" != "copy" ] && [ -z "$FX_M_URL" ]; }; then
        FX_M_ERROR="Format ist '<git|zip> <ziel> <url> [ref]' oder 'copy <quelle> <ziel>'. Ueberspringe: ${line}"
        return 0
    fi

    # Endende '/' entfernen (wie TrimEnd in install-resources.ps1), dann pruefen
    while [ "${FX_M_TARGET%/}" != "$FX_M_TARGET" ]; do
        FX_M_TARGET="${FX_M_TARGET%/}"
    done
    if ! manifest_target_ok "$FX_M_TARGET"; then
        FX_M_ERROR="Ziel '${FX_M_TARGET}' ist unzulaessig (muss relativ zu server-data/resources liegen, ohne '.'- oder '..'-Segmente, leere Segmente oder ':'). Ueberspringe."
        return 0
    fi

    if [ "$kind" = "copy" ]; then
        while [ "${FX_M_SOURCE%/}" != "$FX_M_SOURCE" ]; do
            FX_M_SOURCE="${FX_M_SOURCE%/}"
        done
        if ! manifest_target_ok "$FX_M_SOURCE"; then
            FX_M_ERROR="Quelle '${FX_M_SOURCE}' ist unzulaessig (muss relativ zu server-data/resources liegen, ohne '.'- oder '..'-Segmente, leere Segmente oder ':'). Ueberspringe."
            return 0
        fi
        case "$FX_M_SOURCE" in
            "$FX_M_TARGET"|"$FX_M_TARGET"/*)
                FX_M_ERROR="Quelle und Ziel ueberschneiden sich ('${FX_M_SOURCE}', '${FX_M_TARGET}'). Ueberspringe."
                return 0 ;;
        esac
        case "$FX_M_TARGET" in
            "$FX_M_SOURCE"/*)
                FX_M_ERROR="Quelle und Ziel ueberschneiden sich ('${FX_M_SOURCE}', '${FX_M_TARGET}'). Ueberspringe."
                return 0 ;;
        esac
    fi
    return 0
}

manifest_path_under() {
    # manifest_path_under <pfad> <liste> -> 0, wenn <pfad> gleich einem Eintrag der
    # (zeilengetrennten) Liste ist oder darunter liegt.
    local path="$1" list="$2" t
    while IFS= read -r t; do
        [ -n "$t" ] || continue
        case "$path" in
            "$t"|"$t"/*) return 0 ;;
        esac
    done <<EOT
$list
EOT
    return 1
}

process_manifest() {
    # process_manifest <update 0|1> <force 0|1> [manifest-pfad]
    local update="${1:-0}" force="${2:-0}" manifest="${3:-}"
    local root resdir line lineno dest
    root="$(repo_root)"
    resdir="$root/server-data/resources"
    if [ -z "$manifest" ]; then
        manifest="$root/server-data/resources.txt"
    fi
    FX_MANIFEST_OK=0
    FX_MANIFEST_SKIPPED=0
    FX_MANIFEST_FAILED=0

    if [ ! -f "$manifest" ]; then
        log_warn "Kein Manifest gefunden: $manifest (uebersprungen)"
        return 0
    fi
    log_info "Verarbeite Manifest: $manifest"
    mkdir -p "$resdir"

    lineno=0
    # Das Manifest wird ueber fd 3 gelesen, damit git/curl nicht aus stdin lesen.
    while IFS= read -r line <&3 || [ -n "$line" ]; do
        lineno=$((lineno + 1))
        if [ "$lineno" = "1" ]; then
            line="$(fx_strip_bom "$line")"
        fi
        manifest_parse_line "$line"
        [ -n "$FX_M_KIND" ] || continue
        if [ -n "$FX_M_WARN" ]; then
            log_warn "Zeile ${lineno}: ${FX_M_WARN}"
        fi
        if [ -n "$FX_M_ERROR" ]; then
            log_error "Zeile ${lineno}: ${FX_M_ERROR}"
            FX_MANIFEST_FAILED=$((FX_MANIFEST_FAILED + 1))
            continue
        fi
        dest="$resdir/$FX_M_TARGET"
        case "$FX_M_KIND" in
            git) manifest_git_entry "$FX_M_TARGET" "$dest" "$FX_M_URL" "$FX_M_REF" "$update" "$force" ;;
            zip) manifest_zip_entry "$FX_M_TARGET" "$dest" "$FX_M_URL" "$force" ;;
            copy) manifest_copy_entry "$FX_M_SOURCE" "$FX_M_TARGET" "$resdir/$FX_M_SOURCE" "$dest" ;;
        esac
    done 3< "$manifest"

    log_info "Manifest fertig: ${FX_MANIFEST_OK} installiert/aktualisiert, ${FX_MANIFEST_SKIPPED} uebersprungen, ${FX_MANIFEST_FAILED} fehlgeschlagen"
    if [ "$FX_MANIFEST_FAILED" -gt 0 ]; then
        return 1
    fi
    return 0
}

manifest_check() {
    # manifest_check <manifest-pfad> -> 0 gueltig, 1 Fehler oder Manifest fehlt.
    # Prueft nur die Datei (kein Netz, kein git). Zusaetzlich zu den Zeilenregeln gilt die
    # Reihenfolge: liegt eine copy-Quelle bzw. ein copy-Ziel unter [vendor]/ oder
    # [cfx-default]/, muss die Quelle bzw. der Zielordner von einer FRUEHEREN git/zip-Zeile
    # installiert werden. Andere Pfade (z. B. [local]/...) sind committet und frei.
    local manifest="$1" line lineno=0 errors=0 entries=0 targets="" parent order_ok
    if [ ! -f "$manifest" ]; then
        log_error "Manifest fehlt: ${manifest}"
        return 1
    fi
    if [ ! -r "$manifest" ]; then
        log_error "Manifest ist nicht lesbar: ${manifest}"
        return 1
    fi
    log_info "Pruefe Manifest: ${manifest}"
    while IFS= read -r line || [ -n "$line" ]; do
        lineno=$((lineno + 1))
        if [ "$lineno" = "1" ]; then
            line="$(fx_strip_bom "$line")"
        fi
        manifest_parse_line "$line"
        [ -n "$FX_M_KIND" ] || continue
        if [ -n "$FX_M_WARN" ]; then
            log_warn "Zeile ${lineno}: ${FX_M_WARN}"
        fi
        if [ -n "$FX_M_ERROR" ]; then
            log_error "Zeile ${lineno}: ${FX_M_ERROR}"
            errors=$((errors + 1))
            continue
        fi
        entries=$((entries + 1))
        case "$FX_M_KIND" in
            git|zip)
                targets="${targets}${FX_M_TARGET}
"
                ;;
            copy)
                order_ok=1
                case "$FX_M_SOURCE" in
                    "[vendor]/"*|"[cfx-default]/"*)
                        manifest_path_under "$FX_M_SOURCE" "$targets" || order_ok=0 ;;
                esac
                case "$FX_M_TARGET" in
                    "[vendor]/"*|"[cfx-default]/"*)
                        parent="${FX_M_TARGET%/*}"
                        manifest_path_under "$parent" "$targets" || order_ok=0 ;;
                esac
                if [ "$order_ok" = "0" ]; then
                    log_error "Zeile ${lineno}: copy-Quelle/-Ziel wird von keiner frueheren git/zip-Zeile installiert"
                    errors=$((errors + 1))
                fi
                ;;
        esac
    done < "$manifest"

    if [ "$errors" -gt 0 ]; then
        log_error "Manifest ungueltig: ${errors} Fehler (${manifest})"
        return 1
    fi
    log_ok "Manifest gueltig: ${entries} Eintraege (${manifest})"
    return 0
}

# ---------------------------------------------------------------------------
# secrets.cfg pruefen
# ---------------------------------------------------------------------------
check_license_key() {
    # Rueckgabe 0 = Key sieht gesetzt aus, 1 = fehlt/Platzhalter
    local root secrets
    root="$(repo_root)"
    secrets="$root/server-data/secrets.cfg"
    if [ ! -f "$secrets" ]; then
        log_warn "server-data/secrets.cfg fehlt. Kopiere secrets.cfg.example nach secrets.cfg und trage deinen Key ein."
        return 1
    fi
    if grep -Eq '^[[:space:]]*(set[[:space:]]+)?sv_licenseKey[[:space:]]+"?changeme"?' "$secrets" \
        || ! grep -Eq '^[[:space:]]*(set[[:space:]]+)?sv_licenseKey[[:space:]]+' "$secrets"; then
        log_warn "In server-data/secrets.cfg ist noch kein Lizenz-Key eingetragen (sv_licenseKey = changeme)."
        log_warn "Key erstellen: https://portal.cfx.re/servers/registration-keys"
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# cfg-Dateien bearbeiten
# ---------------------------------------------------------------------------
cfg_set_line() {
    # cfg_set_line <datei> <ERE der alten Zeile> <neue Zeile>
    #   1. ersetzt die LETZTE aktive (nicht auskommentierte) passende Zeile,
    #   2. sonst die ERSTE auskommentierte passende Zeile ('#' oder '//'),
    #   3. sonst wird "\n<neue Zeile>" angehaengt.
    # Geschrieben wird nach <datei>.tmp.PID (umask 077), Rechte bleiben erhalten,
    # der Besitzer nur, wenn root das Skript ausfuehrt. Rueckgabe 0 oder 1.
    local file="$1" pattern="$2" newline="$3" tmp mode owner
    if [ ! -f "$file" ]; then
        log_error "Datei fehlt: ${file}"
        return 1
    fi
    tmp="${file}.tmp.$$"
    # Muster und neue Zeile ueber ENVIRON statt awk -v: -v wuerde Backslashes umdeuten.
    if ! (
        umask 077
        FX_CFG_PAT="$pattern" FX_CFG_NEW="$newline" awk '
            NR == FNR {
                if ($0 ~ ENVIRON["FX_CFG_PAT"]) {
                    if ($0 ~ /^[[:space:]]*(#|\/\/)/) {
                        if (!fc) fc = FNR
                    } else {
                        la = FNR
                    }
                }
                next
            }
            {
                if (la) {
                    if (FNR == la) { print ENVIRON["FX_CFG_NEW"]; next }
                } else if (fc && FNR == fc) {
                    print ENVIRON["FX_CFG_NEW"]; next
                }
                print
            }
            END {
                if (!la && !fc) { print ""; print ENVIRON["FX_CFG_NEW"] }
            }
        ' "$file" "$file" > "$tmp"
    ); then
        rm -f -- "$tmp"
        log_error "Konnte ${file} nicht bearbeiten."
        return 1
    fi
    mode="$(stat -c %a "$file" 2>/dev/null || stat -f %Lp "$file" 2>/dev/null || true)"
    if [ -n "$mode" ]; then
        chmod "$mode" "$tmp" 2>/dev/null || true
    fi
    if is_root; then
        owner="$(stat -c %u:%g "$file" 2>/dev/null || stat -f %u:%g "$file" 2>/dev/null || true)"
        if [ -n "$owner" ]; then
            chown "$owner" "$tmp" 2>/dev/null || true
        fi
    fi
    if ! mv -f "$tmp" "$file"; then
        rm -f -- "$tmp"
        log_error "Konnte ${file} nicht ersetzen."
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Datenbank (MariaDB) und SQL-Import
# ---------------------------------------------------------------------------
# FX_DB_MODE   local (Client mit --defaults-file), root (unix_socket als root),
#              docker (Client im db-Container)
# FX_DB_CLIENT Pfad/Name des Clients (mariadb oder mysql; Test-Hook FX_MARIADB_CLIENT)
# FX_DB_CNF    temporaere Defaults-Datei fuer den local-Modus
# FX_DB_SECRETS  secrets.cfg, aus der db_import_run den Verbindungs-String liest
FX_DB_MODE="local"
FX_DB_CLIENT=""
FX_DB_CNF=""
FX_DB_SECRETS=""
FX_DB_WORK=""
FX_DB_HOST=""
FX_DB_PORT=""
FX_DB_USER=""
FX_DB_PASSWORD=""
FX_DB_NAME=""
FX_DB_SOCKET=""
FX_DB_VERSION=""
FX_DB_CHECK=""

# Backticks sind hier SQL-Bezeichner, keine Befehlsersetzung.
# shellcheck disable=SC2016
FX_DB_TRACKING_DDL='CREATE TABLE IF NOT EXISTS `repo_sql_imports` (
  `file_path` VARCHAR(512) NOT NULL,
  `sha256` CHAR(64) NOT NULL,
  `imported_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `applied_by` VARCHAR(16) NOT NULL DEFAULT '"'"'import'"'"',
  PRIMARY KEY (`file_path`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;'

secrets_get_connection_string() {
    # secrets_get_connection_string <secrets.cfg>
    # Gibt den Wert der LETZTEN aktiven Zeile 'set mysql_connection_string ...' aus.
    # Rueckgabe: 0 gefunden, 1 keine aktive Zeile, 2 Datei fehlt, 3 nicht lesbar.
    local file="$1" line trimmed rest value="" found=0 lineno=0 re_set re_other
    [ -f "$file" ] || return 2
    [ -r "$file" ] || return 3
    re_set='^[[:space:]]*set[[:space:]]+mysql_connection_string[[:space:]]+(.*)$'
    re_other='^[[:space:]]*set[rs][[:space:]]+mysql_connection_string([[:space:]]|$)'
    while IFS= read -r line || [ -n "$line" ]; do
        lineno=$((lineno + 1))
        line="${line%$'\r'}"
        trimmed="${line#"${line%%[![:space:]]*}"}"
        case "$trimmed" in
            '#'*|'//'*) continue ;;
        esac
        if [[ "$line" =~ $re_set ]]; then
            rest="${BASH_REMATCH[1]}"
            rest="${rest#"${rest%%[![:space:]]*}"}"
            [ -n "$rest" ] || continue
            case "$rest" in
                \"*\"*)
                    rest="${rest#\"}"
                    value="${rest%%\"*}" ;;
                *)
                    value="${rest%%[[:space:]]*}" ;;
            esac
            found=1
        elif [[ "$line" =~ $re_other ]]; then
            log_warn "${file} Zeile ${lineno}: 'setr'/'sets' mysql_connection_string schickt das DB-Passwort an alle Spieler (setr) bzw. in die oeffentliche Serverinfo (sets). Nur 'set' verwenden. Die Skripte werten diese Zeile nicht aus."
        fi
    done < "$file"
    if [ "$found" = "1" ]; then
        printf '%s\n' "$value"
        return 0
    fi
    return 1
}

db_parse_connection_string() {
    # db_parse_connection_string <string>
    # Zerlegt den String genau wie oxmysql 2.14.1 (src/config.ts), ohne URL-Dekodierung.
    # Setzt FX_DB_HOST FX_DB_PORT FX_DB_USER FX_DB_PASSWORD FX_DB_NAME FX_DB_SOCKET.
    # Rueckgabe 0 oder 1 (Fehlermeldung schon ausgegeben).
    local s="$1" re userinfo path query rest part key val ktrim re_pct
    FX_DB_HOST=""; FX_DB_PORT=""; FX_DB_USER=""; FX_DB_PASSWORD=""; FX_DB_NAME=""; FX_DB_SOCKET=""
    case "$s" in
        *mysql://*)
            # Gruppen: 5 userinfo, 6 host, 8 port, 9 path, 11 query
            re='^(([^:/?#.]+):)?(//(([^/?#]*)@)?([A-Za-z0-9_.%-]*)(:([0-9]+))?)?([^?#]+)?(\?([^#]*))?$'
            if ! [[ "$s" =~ $re ]]; then
                log_error "mysql_connection_string hat ein ungueltiges Format"
                return 1
            fi
            userinfo="${BASH_REMATCH[5]}"
            FX_DB_HOST="${BASH_REMATCH[6]}"
            FX_DB_PORT="${BASH_REMATCH[8]}"
            path="${BASH_REMATCH[9]}"
            query="${BASH_REMATCH[11]}"
            case "$userinfo" in
                *:*)
                    FX_DB_USER="${userinfo%%:*}"
                    rest="${userinfo#*:}"
                    FX_DB_PASSWORD="${rest%%:*}" ;;
                *)
                    FX_DB_USER="$userinfo" ;;
            esac
            while [ "${path#/}" != "$path" ]; do
                path="${path#/}"
            done
            FX_DB_NAME="$path"
            if [ -n "$query" ]; then
                rest="$query"
                while :; do
                    part="${rest%%&*}"
                    key="${part%%=*}"
                    # Wie oxmysql: jeder Query-Parameter ueberschreibt den Wert davor, auch
                    # host, port, user, password und database aus dem URI-Teil.
                    case "$part" in
                        *=*) val="${part#*=}"; val="${val%%=*}" ;;
                        *) val="" ;;
                    esac
                    case "$key" in
                        socketPath) FX_DB_SOCKET="$val" ;;
                        host) FX_DB_HOST="$val" ;;
                        port) FX_DB_PORT="$val" ;;
                        user) FX_DB_USER="$val" ;;
                        password) FX_DB_PASSWORD="$val" ;;
                        database) FX_DB_NAME="$val" ;;
                    esac
                    case "$rest" in
                        *'&'*) rest="${rest#*&}" ;;
                        *) break ;;
                    esac
                done
            fi
            re_pct='%[0-9A-Fa-f]{2}'
            if [[ "$FX_DB_PASSWORD" =~ $re_pct ]]; then
                log_warn "oxmysql dekodiert %XX im Passwort NICHT; das Passwort wird woertlich verwendet. Besser nur A-Z a-z 0-9 verwenden."
            fi
            ;;
        *)
            rest="$(FX_CS="$s" awk 'BEGIN {
                s = ENVIRON["FX_CS"]
                gsub(/([Hh][Oo][Ss][Tt][Nn][Aa][Mm][Ee]|[Ii][Pp]|[Ss][Ee][Rr][Vv][Ee][Rr]|[Dd][Aa][Tt][Aa][[:space:]]?[Ss][Oo][Uu][Rr][Cc][Ee]|[Aa][Dd][Dd][Rr]([Ee][Ss][Ss])?)=/, "host=", s)
                gsub(/([Uu][Ss][Ee][Rr][[:space:]]?([Ii][Dd]|[Nn][Aa][Mm][Ee])?|[Uu][Ii][Dd])=/, "user=", s)
                gsub(/([Pp][Ww][Dd]|[Pp][Aa][Ss][Ss])=/, "password=", s)
                gsub(/[Dd][Bb]=/, "database=", s)
                printf "%s", s
            }')"
            while :; do
                part="${rest%%;*}"
                key="${part%%=*}"
                case "$part" in
                    *=*) val="${part#*=}"; val="${val%%=*}" ;;
                    *) val="" ;;
                esac
                if [ -n "$key" ]; then
                    ktrim="${key#"${key%%[![:space:]]*}"}"
                    ktrim="${ktrim%"${ktrim##*[![:space:]]}"}"
                    if [ "$ktrim" != "$key" ]; then
                        log_warn "mysql_connection_string: Schluessel '${key}' hat Leerzeichen am Rand und wird von oxmysql nicht als '${ktrim}' erkannt."
                    fi
                    case "$key" in
                        host) FX_DB_HOST="$val" ;;
                        port) FX_DB_PORT="$val" ;;
                        user) FX_DB_USER="$val" ;;
                        password) FX_DB_PASSWORD="$val" ;;
                        database) FX_DB_NAME="$val" ;;
                        socketPath) FX_DB_SOCKET="$val" ;;
                    esac
                fi
                case "$rest" in
                    *';'*) rest="${rest#*;}" ;;
                    *) break ;;
                esac
            done
            ;;
    esac
    [ -n "$FX_DB_HOST" ] || FX_DB_HOST="localhost"
    [ -n "$FX_DB_PORT" ] || FX_DB_PORT="3306"
    case "$FX_DB_PORT" in
        *[!0-9]*)
            log_error "mysql_connection_string: Port '${FX_DB_PORT}' ist keine Zahl"
            return 1 ;;
    esac
    if [ -z "$FX_DB_USER" ] || [ -z "$FX_DB_NAME" ]; then
        log_error "Benutzer bzw. Datenbankname fehlt im mysql_connection_string"
        return 1
    fi
    return 0
}

db_cnf_escape() {
    # Wert fuer eine MariaDB-Optionsdatei in "..." : \ -> \\ und " -> \"
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

db_write_defaults_file() {
    # db_write_defaults_file <pfad>: schreibt [client] aus den FX_DB_*-Variablen (0600).
    local file="$1"
    if ! (
        umask 077
        {
            printf '[client]\n'
            printf 'user="%s"\n' "$(db_cnf_escape "$FX_DB_USER")"
            printf 'password="%s"\n' "$(db_cnf_escape "$FX_DB_PASSWORD")"
            if [ -n "$FX_DB_NAME" ]; then
                printf 'database="%s"\n' "$(db_cnf_escape "$FX_DB_NAME")"
            fi
            printf 'default-character-set=utf8mb4\n'
            if [ -n "$FX_DB_SOCKET" ]; then
                printf 'socket="%s"\n' "$(db_cnf_escape "$FX_DB_SOCKET")"
                printf 'protocol=SOCKET\n'
            else
                printf 'host="%s"\n' "$(db_cnf_escape "$FX_DB_HOST")"
                printf 'port=%s\n' "$FX_DB_PORT"
                printf 'protocol=TCP\n'
            fi
        } > "$file"
    ); then
        log_error "Konnte die temporaere Zugangsdatei nicht schreiben: ${file}"
        return 1
    fi
    chmod 600 "$file" 2>/dev/null || true
    return 0
}

db_find_client() {
    # Setzt FX_DB_CLIENT: $FX_MARIADB_CLIENT (Test-Hook), sonst mariadb, sonst mysql.
    if [ -n "${FX_MARIADB_CLIENT:-}" ]; then
        if ! command -v "$FX_MARIADB_CLIENT" >/dev/null 2>&1; then
            log_error "FX_MARIADB_CLIENT zeigt auf kein ausfuehrbares Programm: ${FX_MARIADB_CLIENT}"
            return 1
        fi
        FX_DB_CLIENT="$FX_MARIADB_CLIENT"
    elif command -v mariadb >/dev/null 2>&1; then
        FX_DB_CLIENT="mariadb"
    elif command -v mysql >/dev/null 2>&1; then
        FX_DB_CLIENT="mysql"
    else
        log_error "Kein MariaDB-Client gefunden (mariadb oder mysql). Installieren: apt install mariadb-client"
        return 1
    fi
    return 0
}

db_client_run() {
    # db_client_run <eingabe-datei> <stdout-datei> <stderr-datei> -> Exit-Code des Clients.
    # SQL kommt immer per stdin, Passwoerter nie auf die Kommandozeile.
    local in="$1" out="$2" err="$3" root
    case "$FX_DB_MODE" in
        local)
            "$FX_DB_CLIENT" --defaults-file="$FX_DB_CNF" --batch --skip-column-names \
                --default-character-set=utf8mb4 <"$in" >"$out" 2>"$err"
            ;;
        root)
            "$FX_DB_CLIENT" --protocol=socket --user=root --batch --skip-column-names \
                --default-character-set=utf8mb4 <"$in" >"$out" 2>"$err"
            ;;
        docker)
            root="$(repo_root)"
            # Das Passwort kommt aus der Umgebung des Containers (MARIADB_PASSWORD) und
            # erscheint weder auf der Kommandozeile des Hosts noch in ps.
            # shellcheck disable=SC2016
            docker compose --env-file "$root/.env" -f "$root/docker/docker-compose.yml" exec -T db \
                sh -c 'MYSQL_PWD="$MARIADB_PASSWORD" exec mariadb --protocol=socket --user="$MARIADB_USER" --database="$MARIADB_DATABASE" --batch --skip-column-names --default-character-set=utf8mb4' \
                <"$in" >"$out" 2>"$err"
            ;;
        *)
            printf 'Unbekannter FX_DB_MODE: %s\n' "$FX_DB_MODE" >"$err"
            return 1
            ;;
    esac
}

db_work_init() {
    # Temporaerer Arbeitsordner (0700) fuer Abfragen, Ausgaben und Zugangsdateien.
    if [ -z "$FX_DB_WORK" ] || [ ! -d "$FX_DB_WORK" ]; then
        fx_mktemp_dir
        FX_DB_WORK="$FX_TMP"
    fi
}

db_query() {
    # db_query <sql>: SQL per stdin ausfuehren. Ausgabe in $FX_DB_WORK/out und /err.
    local q="$FX_DB_WORK/query.sql" rc=0
    (umask 077; printf '%s\n' "$1" > "$q") || return 1
    db_client_run "$q" "$FX_DB_WORK/out" "$FX_DB_WORK/err" || rc=$?
    rm -f -- "$q"
    return "$rc"
}

db_err_head() {
    # erste 5 Zeilen der letzten Client-Fehlerausgabe
    head -n 5 "$FX_DB_WORK/err" 2>/dev/null | tr -d '\r' || true
}

mariadb_version_ok() {
    # mariadb_version_ok <VERSION()-Ausgabe> -> 0 MariaDB >= 10.9, 1 zu alt oder kein MariaDB,
    # 2 Version nicht lesbar.
    local v="$1" re major minor
    re='^([0-9]{1,6})\.([0-9]{1,6})'
    if ! [[ "$v" =~ $re ]]; then
        return 2
    fi
    major=$((10#${BASH_REMATCH[1]}))
    minor=$((10#${BASH_REMATCH[2]}))
    case "$v" in
        *MariaDB*) ;;
        *) return 1 ;;
    esac
    if [ "$major" -gt 10 ] || { [ "$major" -eq 10 ] && [ "$minor" -ge 9 ]; }; then
        return 0
    fi
    return 1
}

db_check_server() {
    # db_check_server <beschreibung>: Verbindung + Versionspruefung. Rueckgabe 0 oder 2.
    # Setzt FX_DB_VERSION und FX_DB_CHECK (ok, unreachable, notmariadb, tooold).
    local label="$1" rc=0
    FX_DB_VERSION=""
    FX_DB_CHECK=""
    if ! db_query 'SELECT VERSION();'; then
        FX_DB_CHECK="unreachable"
        log_error "Datenbank nicht erreichbar oder Anmeldung fehlgeschlagen (${label}): $(db_err_head)"
        return 2
    fi
    FX_DB_VERSION="$(head -n 1 "$FX_DB_WORK/out" | tr -d '\r')"
    case "$FX_DB_VERSION" in
        *MariaDB*) ;;
        *)
            FX_DB_CHECK="notmariadb"
            log_error "Der Server meldet '${FX_DB_VERSION}', das ist kein MariaDB. Qbox unterstuetzt MySQL nicht."
            return 2 ;;
    esac
    mariadb_version_ok "$FX_DB_VERSION" || rc=$?
    if [ "$rc" -ne 0 ]; then
        FX_DB_CHECK="tooold"
        log_error "MariaDB ${FX_DB_VERSION} ist zu alt. Qbox braucht mindestens 10.9 (empfohlen: 12.3 LTS). Anleitung: docs/datenbank.md"
        return 2
    fi
    FX_DB_CHECK="ok"
    log_info "MariaDB ${FX_DB_VERSION}"
    return 0
}

db_docker_wait() {
    # db_docker_wait <repo-root> <sekunden>: wartet auf healthcheck.sh im db-Container.
    local root="$1" secs="${2:-120}" waited=0
    log_info "Warte, bis der db-Container bereit ist (bis ${secs} s) ..."
    while :; do
        if docker compose --env-file "$root/.env" -f "$root/docker/docker-compose.yml" exec -T db \
            healthcheck.sh --connect --innodb_initialized </dev/null >/dev/null 2>&1; then
            log_ok "db-Container ist bereit."
            return 0
        fi
        if [ "$waited" -ge "$secs" ]; then
            log_error "db-Container ist nach ${secs} s nicht bereit (erster Start oder Upgrade dauert laenger?). Logs: docker compose --env-file .env -f docker/docker-compose.yml logs db"
            return 2
        fi
        sleep 2
        waited=$((waited + 2))
    done
}

sha256_file() {
    # sha256_file <datei> -> sha256 in Kleinbuchstaben (ueber den rohen Dateiinhalt)
    local f="$1" out
    if command -v sha256sum >/dev/null 2>&1; then
        out="$(sha256sum < "$f")" || return 1
    elif command -v shasum >/dev/null 2>&1; then
        out="$(shasum -a 256 < "$f")" || return 1
    elif command -v openssl >/dev/null 2>&1; then
        out="$(openssl dgst -sha256 -r < "$f")" || return 1
    else
        log_error "Kein sha256-Programm gefunden (sha256sum, shasum oder openssl)."
        return 1
    fi
    printf '%s\n' "${out%% *}" | tr 'ABCDEF' 'abcdef'
}

sql_path_ok() {
    # sql_path_ok <pfad> -> 0 wenn zulaessig: nur A-Z a-z 0-9 . _ - [ ] /, Endung .sql,
    # relativ, ohne leere, '.'- oder '..'-Segmente. Damit enthaelt ein gueltiger Pfad
    # weder Anfuehrungszeichen noch Backslash und darf woertlich in SQL stehen.
    local p="$1" re
    re='^[][A-Za-z0-9._/-]+$'
    [[ "$p" =~ $re ]] || return 1
    case "$p" in
        *.[Ss][Qq][Ll]) ;;
        *) return 1 ;;
    esac
    manifest_target_ok "$p"
}

sql_manifest_read() {
    # sql_manifest_read <database.txt> -> gibt pro Eintrag "<pfad><TAB><0|1 rerun>" aus.
    # Rueckgabe 1 (ohne Ausgabe) bei jedem Fehler; alle Fehler werden gemeldet.
    local manifest="$1" line lineno=0 p lp opt rest errors=0 out="" rerun nl seen
    nl='
'
    seen="$nl"
    if [ ! -f "$manifest" ]; then
        log_error "SQL-Manifest fehlt: ${manifest}"
        return 1
    fi
    if [ ! -r "$manifest" ]; then
        log_error "SQL-Manifest ist nicht lesbar: ${manifest}"
        return 1
    fi
    while IFS= read -r line || [ -n "$line" ]; do
        lineno=$((lineno + 1))
        line="$(printf '%s' "$line" | tr -d '\r')"
        if [ "$lineno" = "1" ]; then
            line="$(fx_strip_bom "$line")"
        fi
        p=""; opt=""; rest=""
        read -r p opt rest <<EOT
$line
EOT
        [ -n "$p" ] || continue
        case "$p" in
            '#'*) continue ;;
        esac
        rerun=0
        if [ -n "$opt" ] && [ "$opt" != "rerun" ]; then
            log_error "Zeile ${lineno}: unbekannte Option '${opt}' (erlaubt: rerun)"
            errors=$((errors + 1))
            continue
        elif [ -n "$rest" ]; then
            log_error "Zeile ${lineno}: unbekannte Option '${rest}' (erlaubt: rerun)"
            errors=$((errors + 1))
            continue
        elif [ "$opt" = "rerun" ]; then
            rerun=1
        fi
        if ! sql_path_ok "$p"; then
            log_error "Zeile ${lineno}: ungueltiger SQL-Pfad '${p}' (erlaubt: A-Z a-z 0-9 . _ - [ ] /, keine Leerzeichen, Endung .sql, relativ, keine leeren, '.'- oder '..'-Segmente)"
            errors=$((errors + 1))
            continue
        fi
        # Doppelte ohne Gross-/Kleinschreibung erkennen: repo_sql_imports.file_path
        # (utf8mb4_unicode_ci) und Windows unterscheiden sie auch nicht.
        lp="$(printf '%s' "$p" | tr '[:upper:]' '[:lower:]')"
        case "$seen" in
            *"$nl$lp$nl"*)
                log_error "Zeile ${lineno}: SQL-Pfad '${p}' steht doppelt im Manifest"
                errors=$((errors + 1))
                continue ;;
        esac
        seen="$seen$lp$nl"
        out="${out}${p}	${rerun}${nl}"
    done < "$manifest"
    if [ "$errors" -gt 0 ]; then
        return 1
    fi
    printf '%s' "$out"
    return 0
}

sql_only_check() {
    # sql_only_check <eintraege aus sql_manifest_read> [pfad...] -> 1, wenn ein Pfad fehlt.
    local entries="$1" o paths nl bad=0
    shift
    nl='
'
    paths="$nl$(printf '%s' "$entries" | cut -f1)$nl"
    for o in "$@"; do
        case "$paths" in
            *"$nl$o$nl"*) ;;
            *)
                log_error "--only '${o}' steht nicht im SQL-Manifest (Pfad genau wie in database.txt, ohne 'rerun')."
                bad=1 ;;
        esac
    done
    return "$bad"
}

db_import_list_unknown() {
    # Dry-run ohne Datenbank: jede Datei als 'unbekannt' bzw. 'fehlt' auflisten.
    local entries="$1" only="$2" resdir="$3" p rerun nl
    nl='
'
    while IFS='	' read -r p rerun; do
        [ -n "$p" ] || continue
        if [ -n "$only" ]; then
            case "$only" in
                *"$nl$p$nl"*) ;;
                *) continue ;;
            esac
        fi
        if [ -f "$resdir/$p" ]; then
            printf '  %-10s  %s\n' "unbekannt" "$p"
        else
            printf '  %-10s  %s\n' "fehlt" "$p"
        fi
    done <<EOT
$entries
EOT
}

db_import_run() {
    # db_import_run <import|mark> <dry_run 0|1> <database.txt> [only...]
    # Rueckgabe: 0 ok, 1 Abbruch ohne DB-Arbeit, 2 DB nicht erreichbar/zu alt, 3 SQL-Fehler.
    local rc=0
    db_import_main "$@" || rc=$?
    if [ -n "$FX_DB_CNF" ]; then
        rm -f -- "$FX_DB_CNF"
        FX_DB_CNF=""
    fi
    return "$rc"
}

db_import_summary() {
    # db_import_summary <dry> <importiert> <erneut> <vorhanden> <geaendert> <markiert>
    if [ "$1" = "1" ]; then
        log_info "Trockenlauf, nichts geaendert. Geplant: SQL: $2 importiert, $3 erneut ausgefuehrt, $4 bereits vorhanden, $5 geaendert (Warnung), $6 markiert"
    else
        log_info "SQL: $2 importiert, $3 erneut ausgefuehrt, $4 bereits vorhanden, $5 geaendert (Warnung), $6 markiert"
    fi
}

db_record_sql() {
    # db_record_sql <pfad> <sha256> <import|mark-applied>
    db_query "INSERT INTO repo_sql_imports (file_path, sha256, applied_by) VALUES ('$1','$2','$3') ON DUPLICATE KEY UPDATE sha256=VALUES(sha256), applied_by=VALUES(applied_by), imported_at=CURRENT_TIMESTAMP;"
}

db_import_main() {
    local action="$1" dry="$2" manifest="$3"
    shift 3
    local root resdir entries nl only="" o cs rc label count p rerun full sha row rec_sha rec_at
    local status plan="" tab n_imp=0 n_re=0 n_have=0 n_chg=0 n_mark=0 missing=0 errfile
    nl='
'
    tab='	'
    root="$(repo_root)"
    resdir="$root/server-data/resources"
    case "$action" in
        import|mark) ;;
        *) log_error "db_import_run: unbekannte Aktion '${action}'"; return 1 ;;
    esac

    # 1. Manifest
    entries="$(sql_manifest_read "$manifest")" || return 1
    if [ -z "$entries" ]; then
        log_warn "Das SQL-Manifest enthaelt keine Dateien: ${manifest}"
    fi
    if [ $# -gt 0 ]; then
        sql_only_check "$entries" "$@" || return 1
        only="$nl"
        for o in "$@"; do
            only="$only$o$nl"
        done
    fi

    db_work_init

    # 2. Verbindung vorbereiten
    if [ "$FX_DB_MODE" = "docker" ]; then
        label="Docker-Service db"
    else
        FX_DB_MODE="local"
        if [ -z "$FX_DB_SECRETS" ]; then
            FX_DB_SECRETS="$root/server-data/secrets.cfg"
        fi
        rc=0
        cs="$(secrets_get_connection_string "$FX_DB_SECRETS")" || rc=$?
        if [ "$rc" -ne 0 ]; then
            case "$rc" in
                1) log_error "In ${FX_DB_SECRETS} fehlt ein aktives 'set mysql_connection_string \"...\"'. Lokale MariaDB einrichten: sudo bash scripts/linux/setup-database.sh --create" ;;
                2) log_error "secrets.cfg fehlt: ${FX_DB_SECRETS}" ;;
                *) log_error "secrets.cfg ist nicht lesbar: ${FX_DB_SECRETS} (als Service-User oder root ausfuehren)" ;;
            esac
            if [ "$dry" = "1" ]; then
                log_warn "Datenbank nicht erreichbar, Status unbekannt"
                db_import_list_unknown "$entries" "$only" "$resdir"
            fi
            return 1
        fi
        if ! db_parse_connection_string "$cs"; then
            if [ "$dry" = "1" ]; then
                log_warn "Datenbank nicht erreichbar, Status unbekannt"
                db_import_list_unknown "$entries" "$only" "$resdir"
            fi
            return 1
        fi
        db_find_client || return 1
        FX_DB_CNF="$FX_DB_WORK/client.cnf"
        db_write_defaults_file "$FX_DB_CNF" || return 1
        if [ -n "$FX_DB_SOCKET" ]; then
            label="${FX_DB_SOCKET}, User ${FX_DB_USER}"
        else
            label="${FX_DB_HOST}:${FX_DB_PORT}, User ${FX_DB_USER}"
        fi
    fi

    # 3. Verbinden + Version
    rc=0
    db_check_server "$label" || rc=$?
    if [ "$rc" -ne 0 ]; then
        if [ "$dry" = "1" ]; then
            if [ "$FX_DB_CHECK" = "unreachable" ]; then
                log_warn "Datenbank nicht erreichbar, Status unbekannt"
            fi
            db_import_list_unknown "$entries" "$only" "$resdir"
        fi
        return 2
    fi

    # 4./5. Tracking-Tabelle und Eintraege
    : > "$FX_DB_WORK/rows.tsv"
    count="1"
    if [ "$dry" = "1" ]; then
        if ! db_query "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='repo_sql_imports';"; then
            log_error "Tabelle repo_sql_imports konnte nicht geprueft werden: $(db_err_head)"
            return 3
        fi
        count="$(head -n 1 "$FX_DB_WORK/out" | tr -d '\r[:space:]')"
        [ -n "$count" ] || count="0"
    else
        if ! db_query "$FX_DB_TRACKING_DDL"; then
            log_error "Tabelle repo_sql_imports konnte nicht angelegt werden: $(db_err_head)"
            return 3
        fi
    fi
    if [ "$count" != "0" ]; then
        if ! db_query "SELECT file_path, sha256, imported_at FROM repo_sql_imports;"; then
            log_error "Eintraege aus repo_sql_imports konnten nicht gelesen werden: $(db_err_head)"
            return 3
        fi
        tr -d '\r' < "$FX_DB_WORK/out" > "$FX_DB_WORK/rows.tsv"
    fi

    # 6a. Status jeder Datei bestimmen (noch ohne Aenderungen)
    while IFS="$tab" read -r p rerun; do
        [ -n "$p" ] || continue
        if [ -n "$only" ]; then
            case "$only" in
                *"$nl$p$nl"*) ;;
                *) continue ;;
            esac
        fi
        full="$resdir/$p"
        row="$(FX_P="$p" awk -F '\t' 'tolower($1) == tolower(ENVIRON["FX_P"]) { r = $2 "\t" $3 } END { if (r != "") print r }' "$FX_DB_WORK/rows.tsv")"
        rec_sha="${row%%"$tab"*}"
        rec_at="${row#*"$tab"}"
        sha="-"
        if [ -f "$full" ]; then
            sha="$(sha256_file "$full")" || { log_error "sha256 von ${p} konnte nicht berechnet werden."; return 1; }
            if [ -z "$row" ]; then
                status="ausstehend"
            elif [ "$rec_sha" = "$sha" ]; then
                status="importiert"
            elif [ "$action" = "import" ] && [ "$rerun" = "1" ]; then
                status="erneut"
            else
                status="geaendert"
            fi
        elif [ -n "$row" ]; then
            status="fehlt-ok"
        else
            status="fehlt"
            missing=$((missing + 1))
        fi
        plan="${plan}${status}${tab}${p}${tab}${sha}${tab}${rec_sha:--}${tab}${rec_at:--}${nl}"
    done <<EOT
$entries
EOT

    # Dry-run: nur anzeigen
    if [ "$dry" = "1" ]; then
        while IFS="$tab" read -r status p sha rec_sha rec_at; do
            [ -n "$status" ] || continue
            case "$status" in
                importiert) n_have=$((n_have + 1)); printf '  %-10s  %s\n' "importiert" "$p" ;;
                fehlt-ok) n_have=$((n_have + 1)); printf '  %-10s  %s  (bereits importiert, Datei fehlt)\n' "fehlt" "$p" ;;
                fehlt) printf '  %-10s  %s  (nicht importiert, Ressource installieren)\n' "fehlt" "$p" ;;
                ausstehend)
                    if [ "$action" = "mark" ]; then n_mark=$((n_mark + 1)); else n_imp=$((n_imp + 1)); fi
                    printf '  %-10s  %s\n' "ausstehend" "$p" ;;
                erneut) n_re=$((n_re + 1)); printf '  %-10s  %s\n' "erneut" "$p" ;;
                geaendert)
                    if [ "$action" = "mark" ]; then n_mark=$((n_mark + 1)); else n_chg=$((n_chg + 1)); fi
                    printf '  %-10s  %s\n' "geaendert" "$p" ;;
            esac
        done <<EOT
$plan
EOT
        db_import_summary 1 "$n_imp" "$n_re" "$n_have" "$n_chg" "$n_mark"
        if [ "$missing" -gt 0 ]; then
            log_error "${missing} noch nicht importierte Datei(en) fehlen. Ein echter Lauf wuerde mit Exit-Code 3 abbrechen. Ressourcen installieren: scripts/linux/install-resources.sh"
            return 3
        fi
        return 0
    fi

    # Mark-applied: fehlende Dateien vorher abfangen, Liste ohne --only vorher zeigen
    if [ "$action" = "mark" ]; then
        if [ "$missing" -gt 0 ]; then
            while IFS="$tab" read -r status p sha rec_sha rec_at; do
                if [ "$status" = "fehlt" ]; then
                    log_error "${p} fehlt. Ist die Ressource installiert (install-resources)?"
                fi
            done <<EOT
$plan
EOT
            log_error "Nichts eingetragen."
            return 3
        fi
        if [ -z "$only" ]; then
            if printf '%s' "$plan" | grep -Eq '^(ausstehend|geaendert)	'; then
                log_info "Diese Dateien werden als importiert eingetragen, OHNE sie auszufuehren:"
                printf '%s' "$plan" | awk -F '\t' '$1 == "ausstehend" || $1 == "geaendert" { printf "  %-10s  %s\n", $1, $2 }' >&2
            fi
        fi
    fi

    # 6b. Ausfuehren
    errfile="$FX_DB_WORK/import.err"
    while IFS="$tab" read -r status p sha rec_sha rec_at; do
        [ -n "$status" ] || continue
        full="$resdir/$p"
        case "$status" in
            importiert)
                n_have=$((n_have + 1)) ;;
            fehlt-ok)
                log_info "${p}: bereits importiert, Datei fehlt"
                n_have=$((n_have + 1)) ;;
            fehlt)
                log_error "${p} fehlt. Ist die Ressource installiert (install-resources)?"
                db_import_summary 0 "$n_imp" "$n_re" "$n_have" "$n_chg" "$n_mark"
                return 3 ;;
            geaendert)
                if [ "$action" = "mark" ]; then
                    if ! db_record_sql "$p" "$sha" "mark-applied"; then
                        log_error "Eintrag fuer ${p} fehlgeschlagen: $(db_err_head)"
                        db_import_summary 0 "$n_imp" "$n_re" "$n_have" "$n_chg" "$n_mark"
                        return 3
                    fi
                    log_ok "${p}: als importiert eingetragen (nicht ausgefuehrt)"
                    n_mark=$((n_mark + 1))
                else
                    log_warn "${p} wurde am ${rec_at} importiert, die Datei hat sich seitdem geaendert (alt $(printf '%s' "$rec_sha" | cut -c1-8), neu $(printf '%s' "$sha" | cut -c1-8)). Sie wird NICHT erneut ausgefuehrt. Pruefe die Aenderung und spiele noetige Befehle von Hand ein. Warnung quittieren: setup-database --mark-applied --only '${p}'"
                    n_chg=$((n_chg + 1))
                fi
                ;;
            ausstehend|erneut)
                if [ "$action" = "mark" ]; then
                    if ! db_record_sql "$p" "$sha" "mark-applied"; then
                        log_error "Eintrag fuer ${p} fehlgeschlagen: $(db_err_head)"
                        db_import_summary 0 "$n_imp" "$n_re" "$n_have" "$n_chg" "$n_mark"
                        return 3
                    fi
                    log_ok "${p}: als importiert eingetragen (nicht ausgefuehrt)"
                    n_mark=$((n_mark + 1))
                    continue
                fi
                if [ "$status" = "erneut" ]; then
                    log_info "${p} hat sich geaendert und ist als rerun markiert, wird erneut ausgefuehrt"
                else
                    log_info "Importiere ${p} ..."
                fi
                rc=0
                db_client_run "$full" "$FX_DB_WORK/import.out" "$errfile" || rc=$?
                if [ "$rc" -ne 0 ]; then
                    log_error "FEHLER beim Import von ${p} (Exit-Code ${rc}): $(head -n 20 "$errfile" | tr -d '\r')"
                    log_error "Achtung: MariaDB fuehrt CREATE/ALTER TABLE ohne Transaktion aus. Befehle vor dem Fehler sind bereits angewendet. Die Datei ist NICHT als importiert eingetragen, folgende Dateien wurden nicht importiert. Ursache beheben und erneut starten, oder nach Handarbeit: --mark-applied --only '${p}'."
                    db_import_summary 0 "$n_imp" "$n_re" "$n_have" "$n_chg" "$n_mark"
                    return 3
                fi
                if ! db_record_sql "$p" "$sha" "import"; then
                    log_error "Import lief, Eintrag fehlgeschlagen; vor dem naechsten Lauf --mark-applied --only '${p}' ausfuehren ($(db_err_head))"
                    db_import_summary 0 "$n_imp" "$n_re" "$n_have" "$n_chg" "$n_mark"
                    return 3
                fi
                if [ "$status" = "erneut" ]; then
                    log_ok "${p}: erneut ausgefuehrt"
                    n_re=$((n_re + 1))
                else
                    log_ok "${p}: importiert"
                    n_imp=$((n_imp + 1))
                fi
                ;;
        esac
    done <<EOT
$plan
EOT
    db_import_summary 0 "$n_imp" "$n_re" "$n_have" "$n_chg" "$n_mark"
    return 0
}
