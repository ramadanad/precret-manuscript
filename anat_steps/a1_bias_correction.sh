#!/bin/bash

# a1_bias_correction.sh - BIDS anatomical processing pipeline - Step 1: Bias Field Correction
# Usage: a1_bias_correction.sh <BIDS root directory> <subject ID> [session ID]
# If session ID is omitted, processes ALL sessions for the subject in parallel

# Source common functions and variables
source "$(dirname "$0")/../common_functions.sh"
source "$(dirname "$0")/a12_helpers.sh"

# Script location for MATLAB path setup
SCRIPT_DIR="$(dirname "$(realpath "$0")")"

# Parse arguments
BIDS_ROOT="$1"
SUBJECT="$2"
SESSION="$3"

# Check if required arguments are provided
if [[ -z "$1" || -z "$2" ]]; then
    echo "Error: Both BIDS root directory and subject ID are required."
    echo "Usage: $0 <BIDS root directory> <subject ID> [session ID]"
    echo "Example: $0 /path/to/bids sub-01"
    echo "Example: $0 /path/to/bids sub-01 ses-01"
    exit 1
fi

# Validate MATLAB container setup once before processing
validate_matlab_container_setup "$BIDS_ROOT" || {
    echo "Error: MATLAB container setup validation failed."
    exit 1
}

# If session is specified, process only that session
if [[ -n "$SESSION" ]]; then
    setup_pipeline "$@"
    set -e
    
    echo "========================================"
    echo "BIDS Anatomical Processing Pipeline"
    echo "Step 1: Bias Field Correction (Single Session)"
    echo "========================================"

    process_session_bfc "$SESSION" "$LOGFILE"

else
    # Process ALL sessions in parallel
    echo "========================================"
    echo "BIDS Anatomical Processing Pipeline"
    echo "Step 1: Bias Field Correction (All Sessions in Parallel)"
    echo "========================================"
    echo "BIDS root: $BIDS_ROOT"
    echo "Subject: $SUBJECT"
    echo "Processing started: $(date)"
    echo "========================================"

    run_parallel_sessions "bias field correction" "bfc" "process_session_bfc" || exit 1
fi