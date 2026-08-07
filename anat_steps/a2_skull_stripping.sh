#!/bin/bash

# a2_skull_stripping.sh - BIDS anatomical processing pipeline - Step 2: Skull Stripping
# Usage: a2_skull_stripping.sh <BIDS root directory> <subject ID> [session ID]
# If session ID is omitted, processes ALL sessions for the subject in parallel

# Source common functions and variables
source "$(dirname "$0")/../common_functions.sh"
source "$(dirname "$0")/a12_helpers.sh"

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

# If session is specified, process only that session
if [[ -n "$SESSION" ]]; then
    setup_pipeline "$@"
    set -e
    
    echo "========================================"
    echo "BIDS Anatomical Processing Pipeline"
    echo "Step 2: Skull Stripping (Single Session)"
    echo "========================================"

    process_session_skull "$SESSION" "$LOGFILE"

else
    # Process ALL sessions in parallel
    echo "========================================"
    echo "BIDS Anatomical Processing Pipeline"
    echo "Step 2: Skull Stripping (All Sessions in Parallel)"
    echo "========================================"
    echo "BIDS root: $BIDS_ROOT"
    echo "Subject: $SUBJECT"
    echo "Processing started: $(date)"
    echo "========================================"

    run_parallel_sessions "skull stripping" "skull" "process_session_skull" || exit 1
fi
