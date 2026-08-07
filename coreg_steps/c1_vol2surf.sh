#!/bin/bash

# c1_vol2surf.sh - Run FreeSurfer mri_vol2surf for one hemisphere/projection
# Usage: c1_vol2surf.sh <subjects_dir> <freesurfer_container> <run_file> <lta_file> <hemi> <output_file> <projfrac>

set -e

if [[ $# -ne 7 ]]; then
    echo "Error: Usage: $0 <subjects_dir> <freesurfer_container> <run_file> <lta_file> <hemi> <output_file> <projfrac>"
    exit 1
fi

SUBJECTS_DIR="$1"
FREESURFER_CONTAINER="$2"
RUN_FILE="$3"
LTA_FILE="$4"
HEMI="$5"
OUTPUT_FILE="$6"
PROJFRAC="$7"

if [[ ! -f "$RUN_FILE" ]]; then
    echo "Error: Run file not found: $RUN_FILE"
    exit 1
fi

if [[ ! -f "$LTA_FILE" ]]; then
    echo "Error: Registration file not found: $LTA_FILE"
    exit 1
fi

if [[ ! -f "$FREESURFER_CONTAINER" ]]; then
    echo "Error: FreeSurfer container not found: $FREESURFER_CONTAINER"
    exit 1
fi

if [[ "$HEMI" != "lh" && "$HEMI" != "rh" ]]; then
    echo "Error: Hemisphere must be 'lh' or 'rh' (got: $HEMI)"
    exit 1
fi

apptainer exec \
    --bind "$SUBJECTS_DIR":"$SUBJECTS_DIR" \
    "$FREESURFER_CONTAINER" \
    mri_vol2surf \
        --mov "$RUN_FILE" \
        --reg "$LTA_FILE" \
        --hemi "$HEMI" \
        --o "$OUTPUT_FILE" \
        --projfrac "$PROJFRAC"
