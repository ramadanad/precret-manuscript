#!/bin/bash

# Usage: ./s1_run_fit_prf.sh <dataDir> <subject>
# Example:
# HARD-CODED PATH EXAMPLE: fixed local BIDS root shown in usage text.
#    nyx:            ./s1_run_fit_prf.sh /home/dramadan/data/prf_bids/ sub-01
#    sneezewort:     ./s1_run_fit_prf.sh /home/dramadan/prf_bids_nyx/ sub-01

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common_functions.sh"

dataDir="${1:-}"
subject="${2:-}"

if [[ -z "$dataDir" || -z "$subject" ]]; then
    echo "Usage: $0 <dataDir> <subject>"
    exit 1
fi

if [[ ! -d "$dataDir" ]]; then
    echo "Error: dataDir does not exist: $dataDir"
    exit 1
fi

# Run MATLAB fitting stage inside the configured container.
run_matlab_container "$dataDir" "$SCRIPT_DIR" "$SCRIPT_DIR" "s1_fit_prf('${dataDir}','${subject}')"