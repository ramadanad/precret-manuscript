#!/bin/bash

# a123_parallel.sh - BIDS anatomical processing pipeline - Steps 1&2: Parallel Bias Field Correction and Skull Stripping
# Usage: a123_parallel.sh <BIDS root directory> <subject ID>
# This script processes ALL sessions for a subject in parallel for both bias field correction and skull stripping

# Source common functions and variables
source "$(dirname "$0")/../common_functions.sh"

# Source shared Step 1/2 helper functions
source "$(dirname "$0")/a12_helpers.sh"

# Script location for MATLAB path setup
SCRIPT_DIR="$(dirname "$(realpath "$0")")"

# Parse arguments
BIDS_ROOT="$1"
SUBJECT="$2"

# Check if required arguments are provided
if [[ -z "$1" || -z "$2" ]]; then
    echo "Error: Both BIDS root directory and subject ID are required."
    echo "Usage: $0 <BIDS root directory> <subject ID>"
    echo "Example: $0 /path/to/bids sub-01"
    exit 1
fi

# Validate MATLAB container setup once before processing
validate_matlab_container_setup "$BIDS_ROOT" || {
    echo "Error: MATLAB container setup validation failed."
    exit 1
}

# Main processing
echo "========================================"
echo "BIDS Anatomical Processing Pipeline"
echo "Steps 1&2: Parallel Bias Field Correction and Skull Stripping"
echo "========================================"
echo "BIDS root: $BIDS_ROOT"
echo "Subject: $SUBJECT"
echo "Processing started: $(date)"
echo "========================================"

run_parallel_sessions "bias field correction and skull stripping" "bfc_skull" "process_session_bfc_skull" || exit 1

if [[ ${PARALLEL_SESSION_COUNT:-0} -gt 0 ]]; then
    echo ""
    echo "All sessions are now ready for template creation and FreeSurfer recon-all processing."
    echo ""
    echo "Automatically starting template creation (Step 3)..."

    # Run template creation step
    TEMPLATE_SCRIPT="$(dirname "$0")/a3_template_creation.sh"
    if [[ -f "$TEMPLATE_SCRIPT" ]]; then
        if "$TEMPLATE_SCRIPT" "$BIDS_ROOT" "$SUBJECT"; then
            echo "Template creation completed successfully!"
        else
            echo "Warning: Template creation failed. Check logs for details."
            exit 1
        fi
    else
        echo "Warning: Template creation script not found at $TEMPLATE_SCRIPT"
        echo "Please run template creation manually if needed."
    fi

    echo ""
    echo "You can check the results using:"
    echo "  freeview <derivatives_dir>/<session>/sub-XX_ses-XX_T1w_desc-biasCorrected-skullStripped.nii <derivatives_dir>/<session>/sub-XX_ses-XX_T1w_desc-biasCorrected.nii"
    echo "  freeview <derivatives_dir>/sub-XX/ses-all/anat/sub-XX_ses-all_T1w_desc-biasCorrected-template-skullStripped.nii.gz"
    echo "========================================"
fi

echo ""
echo "Steps 1&2 (Bias Field Correction and Skull Stripping) completed successfully!"
echo "Processing finished: $(date)"
