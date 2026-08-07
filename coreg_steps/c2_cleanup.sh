#!/bin/bash

# c2_cleanup.sh - Archive bbregister side outputs for one .lta registration
# Usage: c2_cleanup.sh <lta_file>

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Error: Usage: $0 <lta_file>"
    exit 1
fi

LTA_FILE="$1"

if [[ ! -f "$LTA_FILE" ]]; then
    echo "Info: LTA file not found, skipping cleanup: $LTA_FILE"
    exit 0
fi

VOL2SURF_DIR="$(dirname "$LTA_FILE")"
BASENAME_NO_EXT="$(basename "${LTA_FILE%.lta}")"
INTERIM_DIR="${VOL2SURF_DIR}/bbr_interim"

mkdir -p "$INTERIM_DIR"

moved=0

shopt -s nullglob

for f in "${VOL2SURF_DIR}/${BASENAME_NO_EXT}"*.dat*; do
    if [[ -f "$f" ]]; then
        mv "$f" "$INTERIM_DIR"/
        moved=$((moved + 1))
    fi
done

for f in "${VOL2SURF_DIR}/${BASENAME_NO_EXT}"*.log; do
    if [[ -f "$f" ]]; then
        mv "$f" "$INTERIM_DIR"/
        moved=$((moved + 1))
    fi
done

shopt -u nullglob

if [[ "$moved" -gt 0 ]]; then
    echo "Moved ${moved} bbregister interim file(s) to: $INTERIM_DIR"
else
    echo "No matching .dat*/.log files found for: ${BASENAME_NO_EXT}"
fi
