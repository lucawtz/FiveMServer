#!/usr/bin/env bash
#
# update-artifacts.sh - laedt die FXServer-Artifacts (Linux) herunter oder aktualisiert sie.
#
# Aufruf: scripts/linux/update-artifacts.sh [--channel recommended|latest|optional] [--force] [--if-missing]
#
# Ohne Optionen: fragt die Changelog-API ab und laedt neu, wenn noch keine Artifacts
# vorhanden sind oder die API eine andere Build-Nummer meldet. Die bisherige Version
# wandert nach artifacts.bak. txData wird nie angefasst.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/linux/lib.sh
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib.sh"

usage() {
    cat <<USAGE
Verwendung: $(basename "$0") [OPTIONEN]

Laedt die FXServer-Artifacts fuer Linux in <repo>/artifacts/.

Optionen:
  --channel <name>   recommended (Standard), latest oder optional
  --force            Immer neu herunterladen, auch wenn die Version schon installiert ist
  --if-missing       Nur herunterladen, wenn artifacts/run.sh noch fehlt (fuer install.sh)
  -h, --help         Diese Hilfe anzeigen

Beispiele:
  $(basename "$0")                        # auf den aktuellen recommended-Build aktualisieren
  $(basename "$0") --channel latest       # neuesten Build holen
  $(basename "$0") --force                # Neuinstallation erzwingen
USAGE
}

CHANNEL="recommended"
FORCE=0
IF_MISSING=0

while [ $# -gt 0 ]; do
    case "$1" in
        --channel)
            [ $# -ge 2 ] || die "--channel braucht einen Wert (recommended|latest|optional)."
            CHANNEL="$2"; shift 2 ;;
        --channel=*)
            CHANNEL="${1#--channel=}"; shift ;;
        --force)
            FORCE=1; shift ;;
        --if-missing)
            IF_MISSING=1; shift ;;
        -h|--help)
            usage; exit 0 ;;
        *)
            usage >&2
            die "Unbekannte Option: $1" ;;
    esac
done

validate_channel "$CHANNEL"
trap fx_cleanup EXIT

ROOT="$(repo_root)"
log_step "FXServer-Artifacts (Channel: ${CHANNEL})"

if [ "$IF_MISSING" = "1" ] && [ "$FORCE" != "1" ]; then
    download_artifacts "$CHANNEL" 0 0
else
    download_artifacts "$CHANNEL" "$FORCE" 1
fi

if [ -f "$ROOT/artifacts/VERSION.txt" ]; then
    log_info "Stand laut artifacts/VERSION.txt: $(sed -n 's/^version=//p' "$ROOT/artifacts/VERSION.txt" | head -n 1) (Channel: $(sed -n 's/^channel=//p' "$ROOT/artifacts/VERSION.txt" | head -n 1))"
fi
