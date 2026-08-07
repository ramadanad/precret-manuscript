#!/bin/bash

# fa1_coreg.sh - Run FreeSurfer bbregister and mri_vol2surf for one functional run
# Usage: fa1_coreg.sh <subjects_dir> <freesurfer_container> <fs_subject_dir> <MPRAGE_FILE> <intermediate_file> <lta_file> <hemi> <output_file> <projfrac>

set -e

if [[ $# -ne 9 ]]; then
    echo "Error: Usage: $0 <subjects_dir> <freesurfer_container> <fs_subject_dir> <MPRAGE_FILE> <intermediate_file> <lta_file> <hemi> <output_file> <projfrac>"
    exit 1
fi

SUBJECTS_DIR="$1"
FREESURFER_CONTAINER="$2"
FS_SUBJECT_DIR="$3"
MPRAGE_FILE="$4"
B1_FILE="$5"
LTA_FILE="$6"
HEMI="$7"
OUTPUT_FILE="$8"
PROJFRAC="$9"

if [[ "$HEMI" != "lh" && "$HEMI" != "rh" ]]; then
    echo "Error: Hemisphere must be 'lh' or 'rh', got: $HEMI"
    exit 1
fi


if [[ ! -f "$FREESURFER_CONTAINER" ]]; then
    echo "Error: FreeSurfer container not found: $FREESURFER_CONTAINER"
    exit 1
fi

echo "      SUBJECTS_DIR = $SUBJECTS_DIR"
echo "      Running bbregister..."

export APPTAINERENV_SUBJECTS_DIR="$SUBJECTS_DIR"
export APPTAINERENV_FS_SUBJECT_DIR="$FS_SUBJECT_DIR"


# check if LTA_FILE exists, if not run bbregister to create it
if [[ ! -f "$LTA_FILE" ]]; then
    # co-register FA map to template using the session anatomy as an intermediate target
    # using trilinear interpolation (default)
    apptainer exec \
        --bind "$SUBJECTS_DIR":"$SUBJECTS_DIR" \
        "$FREESURFER_CONTAINER" \
        bbregister \
            --s "$FS_SUBJECT_DIR" \
            --mov "$B1_FILE" \
            --t1 \
            --int "$MPRAGE_FILE" \
            --reg "$LTA_FILE"

else
    echo "LTA file already exists: $LTA_FILE, skipping bbregister"
fi

# surface registration
apptainer exec \
    --bind "$SUBJECTS_DIR":"$SUBJECTS_DIR" \
    "$FREESURFER_CONTAINER" \
    mri_vol2surf \
        --mov "$B1_FILE" \
        --reg "$LTA_FILE" \
        --hemi "$HEMI" \
        --o "$OUTPUT_FILE" \
        --projfrac "$PROJFRAC"
