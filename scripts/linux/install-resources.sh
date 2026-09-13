#!/usr/bin/env bash
#
# install-resources.sh - installiert die Basis-Ressourcen (cfx-server-data) und
# verarbeitet server-data/resources.txt (git-, zip- und copy-Eintraege).
#
# Aufruf: scripts/linux/install-resources.sh [--update] [--force] [--manifest <pfad>]
#         scripts/linux/install-resources.sh --check [--manifest <pfad>]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/linux/lib.sh
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib.sh"

usage() {
    cat <<USAGE
Verwendung: $(basename "$0") [OPTIONEN]

1. Klont cfx-server-data nach server-data/resources/[cfx-default] (falls leer).
2. Verarbeitet server-data/resources.txt:
     git <ziel> <url> [ref]   -> git clone --depth 1 nach server-data/resources/<ziel>
     zip <ziel> <url>         -> Archiv laden und nach server-data/resources/<ziel> entpacken
     copy <quelle> <ziel>     -> Datei/Ordner aus einer frueheren Zeile ueber <ziel> kopieren
                                 (laeuft bei jedem Aufruf, auch ohne --update/--force)

Optionen:
  --update           Vorhandene git-Eintraege per 'git pull --ff-only' aktualisieren
  --force            Alles neu holen: [cfx-default] neu klonen, Manifest-Ziele loeschen und neu laden
  --manifest <pfad>  Anderes Manifest statt server-data/resources.txt verwenden (muss existieren)
  --check            Nur das Manifest pruefen (Format, Pfade, copy-Reihenfolge). Kein Netz,
                     kein git, nichts wird installiert. Nur mit --manifest kombinierbar
  -h, --help         Diese Hilfe anzeigen

Exit-Code 1, wenn mindestens ein Manifest-Eintrag fehlgeschlagen ist oder das mit
--manifest angegebene Manifest fehlt (fehlt nur das Standard-Manifest: Warnung, Exit 0).
Mit --check: Exit 0 bei gueltigem Manifest, Exit 1 bei Fehlern oder fehlendem Manifest.
USAGE
}

UPDATE=0
FORCE=0
MANIFEST=""
CHECK=0

while [ $# -gt 0 ]; do
    case "$1" in
        --update) UPDATE=1; shift ;;
        --force) FORCE=1; shift ;;
        --check) CHECK=1; shift ;;
        --manifest)
            [ $# -ge 2 ] || die "--manifest braucht einen Pfad."
            MANIFEST="$2"; shift 2 ;;
        --manifest=*)
            MANIFEST="${1#--manifest=}"; shift ;;
        -h|--help) usage; exit 0 ;;
        *)
            usage >&2
            die "Unbekannte Option: $1" ;;
    esac
done

if [ "$CHECK" = "1" ]; then
    if [ "$UPDATE" = "1" ] || [ "$FORCE" = "1" ]; then
        die "--check laesst sich nur mit --manifest kombinieren."
    fi
    if [ -z "$MANIFEST" ]; then
        MANIFEST="$(repo_root)/server-data/resources.txt"
    fi
    if manifest_check "$MANIFEST"; then
        exit 0
    fi
    exit 1
fi

# Ein explizit angegebenes Manifest muss existieren (wie -ManifestPath unter Windows). Fehlt nur das
# Standard-Manifest server-data/resources.txt, gibt process_manifest eine Warnung aus und macht weiter.
if [ -n "$MANIFEST" ] && [ ! -f "$MANIFEST" ]; then
    die "Das angegebene Manifest wurde nicht gefunden: $MANIFEST"
fi

trap fx_cleanup EXIT

log_step "Basis-Ressourcen (cfx-server-data)"
install_base_resources "$FORCE"

log_step "Ressourcen aus resources.txt"
if process_manifest "$UPDATE" "$FORCE" "$MANIFEST"; then
    log_ok "Ressourcen sind auf Stand."
else
    die "Mindestens ein Eintrag aus dem Manifest konnte nicht installiert werden (siehe oben)."
fi
