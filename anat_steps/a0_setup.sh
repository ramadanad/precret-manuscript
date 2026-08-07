#!/bin/bash

# a0_setup.sh - BIDS anatomical processing pipeline - Step 0: Data Setup
# Usage: a0_setup.sh <BIDS root directory> <subject ID> [session ID]

# Source common functions and variables
source "$(dirname "$0")/../common_functions.sh"

# Setup pipeline variables and paths
setup_pipeline "$@"

# Redirect all output (stdout and stderr) to the log file
exec > >(tee -a "$LOGFILE") 2>&1

set -e

echo "========================================"
echo "BIDS Anatomical Processing Pipeline"
echo "Step 0: Data Setup"
echo "========================================"
echo "BIDS root: $BIDS_ROOT"
echo "Subject: $SUBJECT"
if [[ -n "$SESSION" ]]; then
    echo "Session: $SESSION"
fi
echo "Processing started: $(date)"
echo "========================================"

# Validate and discover input data (no copy/staging)
discover_t1w_input

# Verify T1w sidecar JSON indicates defacing was done
if [[ -n "$T1W_INPUT" ]]; then
    T1W_JSON="${T1W_INPUT%.nii.gz}.json"
    [[ "$T1W_JSON" == "$T1W_INPUT" ]] && T1W_JSON="${T1W_INPUT%.nii}.json"

    if [[ ! -f "$T1W_JSON" ]]; then
        echo "ERROR: Missing JSON sidecar: $T1W_JSON"
        echo "Please deface the anatomical data of this session first."
        exit 1
    fi

    if command -v jq >/dev/null 2>&1; then
        DEFACED_VAL="$(jq -r 'if has("defaced") then .defaced elif has("Defaced") then .Defaced else empty end' "$T1W_JSON")"
    else
        DEFACED_VAL="$(python3 - <<'PY' "$T1W_JSON"
import json, sys
with open(sys.argv[1], "r") as f:
    d = json.load(f)
v = d.get("defaced", d.get("Defaced", ""))
print(str(v).lower() if v != "" else "")
PY
)"
    fi

    if [[ "$DEFACED_VAL" != "true" ]]; then
        echo "ERROR: $T1W_JSON must contain \"defaced\": true"
        echo "Please deface the anatomical data of this session first."
        exit 1
    else
        echo "$T1W_INPUT is defaced."
    fi
fi

echo "========================================"
echo "Data setup completed successfully"
if [[ -n "$T1W_INPUT" ]]; then
    echo "T1w input: $T1W_INPUT"
else
    echo "T1w input: validation-only (no subject-level copy)"
fi
echo "Working directory: $DERIVATIVES_DIR"
echo "Output prefix: $BIDS_OUTPUT_PREFIX"
echo "========================================"
