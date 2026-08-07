#!/bin/bash

# a6_convert_labels.sh - BIDS anatomical processing pipeline - Step 6: Convert Labels to NIfTI
# Usage: a6_convert_labels.sh <BIDS root directory> <subject ID> [session ID]

# Source common functions and variables
source "$(dirname "$0")/../common_functions.sh"

# Setup pipeline variables and paths
setup_pipeline "$@"

# Redirect all output (stdout and stderr) to the log file
exec > >(tee -a "$LOGFILE") 2>&1

set -e

echo "========================================"
echo "BIDS Anatomical Processing Pipeline"
echo "Step 6: Converting Labels to NIfTI"
echo "========================================"

export SUBJECTS_DIR="$DERIVATIVES_DIR"
cd "$SUBJECTS_DIR"

# Use FreeSurfer subject directory from freesurfer derivatives
FS_SUBJECTS_DIR="$BIDS_ROOT/derivatives/freesurfer"
FS_SUBJECT_DIR="$SUBJECT"

# Check if FreeSurfer subject directory exists and is complete
if [[ ! -d "$FS_SUBJECTS_DIR/$FS_SUBJECT_DIR" ]]; then
    echo "Error: FreeSurfer subject directory '$FS_SUBJECT_DIR' not found in $FS_SUBJECTS_DIR"
    echo "Please run FreeSurfer recon-all steps first."
    exit 1
fi

if [[ ! -f "$FS_SUBJECTS_DIR/$FS_SUBJECT_DIR/surf/lh.pial" || ! -f "$FS_SUBJECTS_DIR/$FS_SUBJECT_DIR/surf/rh.pial" ]]; then
    echo "Error: FreeSurfer processing appears incomplete (missing pial surfaces)"
    echo "Please complete FreeSurfer recon-all steps first."
    exit 1
fi

echo -e "Converting cortex labels to nifti for use in SamSrf...\n"

# BIDS-compliant naming for cortex labels
RH_CORTEX_OUTPUT="${BIDS_OUTPUT_PREFIX}_hemi-R_desc-cortex_dseg.nii"
LH_CORTEX_OUTPUT="${BIDS_OUTPUT_PREFIX}_hemi-L_desc-cortex_dseg.nii"

# Check if cortex labels already exist
if [[ -f "$SUBJECTS_DIR/$RH_CORTEX_OUTPUT" && -f "$SUBJECTS_DIR/$LH_CORTEX_OUTPUT" ]]; then
    echo "Cortex label files already exist:"
    echo "  - Right: $RH_CORTEX_OUTPUT"
    echo "  - Left: $LH_CORTEX_OUTPUT"
    echo -e "Do you want to regenerate cortex labels? (y/n): "
    read -r repeat_labels
    if [[ "$repeat_labels" != "y" && "$repeat_labels" != "Y" ]]; then
        echo "Skipping cortex label conversion."
        run_labels=false
    else
        run_labels=true
    fi
else
    run_labels=true
fi

if [[ "$run_labels" == "true" ]]; then
    for hemi in R L; do
        if [[ "$hemi" == "R" ]]; then
            hemi_lower="rh"
            output_file="$RH_CORTEX_OUTPUT"
            hemi_name="Right"
        else
            hemi_lower="lh"
            output_file="$LH_CORTEX_OUTPUT"
            hemi_name="Left"
        fi

        apptainer exec "$FREESURFER_CONTAINER" mri_label2vol --label "$FS_SUBJECTS_DIR/$FS_SUBJECT_DIR/label/${hemi_lower}.cortex.label" \
                      --temp "$FS_SUBJECTS_DIR/$FS_SUBJECT_DIR/mri/T1.mgz" \
                      --o "$SUBJECTS_DIR/$output_file" \
                      --identity

        cat > "$SUBJECTS_DIR/${BIDS_OUTPUT_PREFIX}_hemi-${hemi}_desc-cortex_dseg.json" << EOF
{
    "Description": "${hemi_name} hemisphere cortical segmentation mask",
    "Sources": ["fs_${OUTPUT_PREFIX}"],
    "Type": "Cortex",
    "Hemisphere": "${hemi}",
    "SpatialReference": "orig",
    "Resolution": "native",
    "Density": "native",
    "GeneratedBy": [
        {
            "Name": "FreeSurfer",
            "Version": "$FREESURFER_VERSION",
            "Description": "Cortical label conversion using FreeSurfer mri_label2vol"
        }
    ]
}
EOF
    done

    echo -e "Cortex label conversion completed."
else
    echo -e "Cortex label conversion step skipped."
    echo -e "Using existing label files."
fi

echo "========================================"
echo "Label conversion step completed"
echo "Right cortex: $RH_CORTEX_OUTPUT"
echo "Left cortex: $LH_CORTEX_OUTPUT"
echo "========================================"
