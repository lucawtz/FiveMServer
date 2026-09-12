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
#   repo_root                      -> absoluter Pfad zum Projektordner
#   fetch_artifact_info <channel>  -> setzt ARTIFACT_URL und ARTIFACT_VERSION
#   fetch_artifact_url  <channel>  -> gibt nur die Download-URL aus
#   download_artifacts  <channel> <force 0|1> [update 0|1]
#   install_base_resources <force 0|1>
#   process_manifest <update 0|1> <force 0|1> [manifest-pfad]
#   check_license_key              -> warnt, wenn secrets.cfg fehlt oder "changeme" enthaelt
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
    (cd "$FX_LIB_DIR/../.." && pwd -P)
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

process_manifest() {
    # process_manifest <update 0|1> <force 0|1> [manifest-pfad]
    local update="${1:-0}" force="${2:-0}" manifest="${3:-}"
    local root resdir line lineno kind target url ref rest dest
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
        # Kommentare: ganze Zeile ab '#' am Anfang oder ' # ...' am Zeilenende. Vor dem '#'
        # muss Leerraum stehen, damit ein '#' innerhalb einer URL erhalten bleibt (wie
        # install-resources.ps1).
        line="$(printf '%s' "$line" | tr -d '\r' | sed -E 's/(^|[[:space:]]+)#.*$//')"
        kind=""; target=""; url=""; ref=""; rest=""
        read -r kind target url ref rest <<EOT
$line
EOT
        [ -n "$kind" ] || continue
        # zip kennt kein viertes Feld; wie unter Windows nur warnen und ignorieren.
        if [ "$kind" = "zip" ] && [ -n "$ref" ]; then
            log_warn "Zeile ${lineno}: zu viele Felder, zip kennt kein viertes Feld, ignoriere Rest '${ref}${rest:+ $rest}'"
            ref=""
        elif [ -n "$rest" ]; then
            log_warn "Zeile ${lineno}: zu viele Felder, ignoriere Rest '${rest}'"
        fi
        if [ -z "$target" ] || [ -z "$url" ]; then
            log_error "Zeile ${lineno}: Format ist '<git|zip> <ziel> <url> [ref]'. Ueberspringe: $line"
            FX_MANIFEST_FAILED=$((FX_MANIFEST_FAILED + 1))
            continue
        fi
        # Endende '/' entfernen (wie TrimEnd in install-resources.ps1), dann pruefen
        while [ "${target%/}" != "$target" ]; do
            target="${target%/}"
        done
        if ! manifest_target_ok "$target"; then
            log_error "Zeile ${lineno}: Ziel '${target}' ist unzulaessig (muss relativ zu server-data/resources liegen, ohne '.'- oder '..'-Segmente, leere Segmente oder ':'). Ueberspringe."
            FX_MANIFEST_FAILED=$((FX_MANIFEST_FAILED + 1))
            continue
        fi
        dest="$resdir/$target"
        case "$kind" in
            git) manifest_git_entry "$target" "$dest" "$url" "$ref" "$update" "$force" ;;
            zip) manifest_zip_entry "$target" "$dest" "$url" "$force" ;;
            *)
                log_error "Zeile ${lineno}: unbekannter Typ '${kind}' (erlaubt: git, zip). Ueberspringe."
                FX_MANIFEST_FAILED=$((FX_MANIFEST_FAILED + 1)) ;;
        esac
    done 3< "$manifest"

    log_info "Manifest fertig: ${FX_MANIFEST_OK} installiert/aktualisiert, ${FX_MANIFEST_SKIPPED} uebersprungen, ${FX_MANIFEST_FAILED} fehlgeschlagen"
    if [ "$FX_MANIFEST_FAILED" -gt 0 ]; then
        return 1
    fi
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
