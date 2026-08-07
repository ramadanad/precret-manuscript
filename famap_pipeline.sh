#!/bin/bash

# famap_pipeline.sh - Run the full FAMAP pipeline for all subjects in a BIDS dataset

# Usage: famap_pipeline.sh <bids_root>

# this should only be run, if the anatomical pipeline completed successfully for all subjects

set -e

BIDS_ROOT="${1:-}"

if [[ -z "$BIDS_ROOT" ]]; then
    echo "Usage: $0 <bids_root>"
    exit 1
fi

# Step 0: Run FA rescaling for all subjects
bash "$(dirname "$0")/famap_steps/fa0_run_rescale.sh" "$BIDS_ROOT"

# Step 1: Run coregistration for all subjects/sessions
bash "$(dirname "$0")/famap_steps/fa1_run_coreg.sh" "$BIDS_ROOT"

# Step 2: Run MGH to surface conversion for all subjects/sessions
bash "$(dirname "$0")/famap_steps/fa2_run_mgh2srf.sh" "$BIDS_ROOT"
