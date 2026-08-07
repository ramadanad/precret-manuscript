#!/bin/bash

# c0_bbr.sh - Run FreeSurfer bbregister for one functional run
# Usage: c0_bbr.sh <subjects_dir> <freesurfer_container> <fs_subject_dir> <run_file> <intermediate_file> <lta_file>

set -e

if [[ $# -ne 6 ]]; then
    echo "Error: Usage: $0 <subjects_dir> <freesurfer_container> <fs_subject_dir> <run_file> <intermediate_file> <lta_file>"
    exit 1
fi

SUBJECTS_DIR="$1"
FREESURFER_CONTAINER="$2"
FS_SUBJECT_DIR="$3"
RUN_FILE="$4"
INTERMEDIATE_FILE="$5"
LTA_FILE="$6"

if [[ ! -f "$RUN_FILE" ]]; then
    echo "Error: Run file not found: $RUN_FILE"
    exit 1
fi

if [[ ! -f "$INTERMEDIATE_FILE" ]]; then
    echo "Error: Intermediate file not found: $INTERMEDIATE_FILE"
    exit 1
fi

if [[ ! -f "$FREESURFER_CONTAINER" ]]; then
    echo "Error: FreeSurfer container not found: $FREESURFER_CONTAINER"
    exit 1
fi

echo "      SUBJECTS_DIR = $SUBJECTS_DIR"
echo "      Running bbregister..."

apptainer exec \
    --bind "$SUBJECTS_DIR":"$SUBJECTS_DIR" \
    "$FREESURFER_CONTAINER" \
    bbregister \
        --s "$FS_SUBJECT_DIR" \
        --mov "$RUN_FILE" \
        --int "$INTERMEDIATE_FILE" \
        --bold \
        --nearest \
        --reg "$LTA_FILE"
