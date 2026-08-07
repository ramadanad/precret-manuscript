#!/bin/bash

# a7_convert_t1mgz.sh - BIDS anatomical processing pipeline - Step 7: Convert T1.mgz to NIfTI
# Usage: a7_convert_t1mgz.sh <BIDS root directory> <subject ID> [session ID]

# Source common functions and variables
source "$(dirname "$0")/../common_functions.sh"

# Setup pipeline variables and paths
setup_pipeline "$@"

# Redirect all output (stdout and stderr) to the log file
exec > >(tee -a "$LOGFILE") 2>&1

set -e

echo "========================================"
echo "BIDS Anatomical Processing Pipeline"
echo "Step 7: Converting T1.mgz to NIfTI"
echo "========================================"

export SUBJECTS_DIR="$DERIVATIVES_DIR"
cd "$SUBJECTS_DIR"

# Use FreeSurfer subject directory from freesurfer derivatives
FS_SUBJECTS_DIR="$BIDS_ROOT/derivatives/freesurfer"

# Check if FreeSurfer subject directory exists
if [[ ! -d "$FS_SUBJECTS_DIR/$SUBJECT" ]]; then
    echo "Error: FreeSurfer subject directory '$SUBJECT' not found in $FS_SUBJECTS_DIR"
    echo "Please run FreeSurfer recon-all steps first."
    exit 1
fi

# BIDS-compliant naming for FreeSurfer T1
FS_T1_OUTPUT="T1.nii"
mri_folder="$FS_SUBJECTS_DIR/$SUBJECT/mri"

# Check if T1.mgz exists
if [[ ! -f "$mri_folder/T1.mgz" ]]; then
    echo "Error: T1.mgz not found in $mri_folder"
    echo "Please complete FreeSurfer recon-all steps first."
    exit 1
fi

# Convert mgz to nii only if the output file doesn't exist
if [ ! -f "$SUBJECTS_DIR/$FS_T1_OUTPUT" ]; then
    apptainer exec "$FREESURFER_CONTAINER" mri_convert -it mgz -ot nii "$mri_folder/T1.mgz" "$mri_folder/$FS_T1_OUTPUT"
    echo "Converted T1.mgz to $FS_T1_OUTPUT in $mri_folder"
    

else
    echo "$FS_T1_OUTPUT already exists. Skipping conversion."
fi

echo "========================================"
echo "T1.mgz conversion step completed"
echo "FreeSurfer T1: $FS_T1_OUTPUT"
echo "========================================"
