#!/usr/bin/env bash
set -euo pipefail


SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"


while true; do
    echo "Start Bytefish..."
    

    mojo "$SCRIPT_DIR/uci.mojo"
    
    echo "Bytefish exited. Restarting in 2 seconds..."
    sleep 2
done

