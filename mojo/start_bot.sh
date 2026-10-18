#!/usr/bin/env bash
set -euo pipefail

# Ermittelt das Verzeichnis, in dem dieses Skript liegt
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Führt direkt die Mojo-Datei aus
exec mojo "$SCRIPT_DIR/uci.mojo"
