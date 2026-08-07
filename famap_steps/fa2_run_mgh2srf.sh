#!/bin/bash

# Usage: ./fa2_run_mgh2srf.sh <dataDir> 
# Example:
#    nyx:            ./fa2_run_mgh2srf.sh /home/dramadan/data/prf_bids/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common_functions.sh"

dataDir="${1:-}"
projFrac="projFrac-0p5"

for subject in "$dataDir"/derivatives/freesurfer/sub-0*/; do
    [[ -d "$subject" ]] || continue
    subject=$(basename "$subject")
    echo "Processing subject: $subject"
    workingDir="${dataDir}/derivatives/freesurfer/${subject}"
    outputDir="${dataDir}/derivatives/samsrf/${subject}/prf_fits"

   

    if [[ -z "$dataDir" || -z "$subject" ]]; then
        echo "Usage: $0 <dataDir> <subject>"
        exit 1
    fi

    if [[ ! -d "$dataDir" ]]; then
        echo "Error: dataDir does not exist: $dataDir"
        exit 1
    fi

    # Run MATLAB fitting stage inside the configured container.
    run_matlab_container "$dataDir" "$SCRIPT_DIR" "$SCRIPT_DIR" "fa2_mgh2srf('${workingDir}','${projFrac}','${outputDir}')"

done