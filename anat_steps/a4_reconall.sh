#!/bin/bash

# a4_reconall.sh - BIDS anatomical processing pipeline - Step 4: FreeSurfer Recon-all Parts 1, 2 & 3
# Usage: a4_reconall.sh <BIDS root directory> <subject ID> [session ID]
# This script runs the complete FreeSurfer recon-all pipeline (autorecon1, autorecon2, and autorecon3)

# Source common functions and variables
source "$(dirname "$0")/../common_functions.sh"

# Setup pipeline variables and paths
setup_pipeline "$@"

# Redirect all output (stdout and stderr) to the log file
exec > >(tee -a "$LOGFILE") 2>&1

set -e

# Keep FreeSurfer subject naming session-agnostic for downstream compatibility.
FS_SUBJECT_NAME="$SUBJECT"


echo "========================================"
echo "BIDS Anatomical Processing Pipeline"
echo "Step 4: FreeSurfer Recon-all (autorecon1, autorecon2, autorecon3)"
echo "========================================"

# Select recon-all input based on session mode.
# - Single session: use that session's skull-stripped anatomical file directly.
# - Multiple sessions: use ses-all canonical masked template.
if [[ -n "$SESSION" ]]; then
    INPUT_SESSION="$SESSION"
    TEMPLATE_DIR="$BIDS_ROOT/derivatives/preproc/$SUBJECT/$INPUT_SESSION/anat"
    SKULLSTRIPPED_OUTPUT="${SUBJECT}_${INPUT_SESSION}_T1w_desc-biasCorrected-skullStripped.nii"
else
    mapfile -t FOUND_SESSIONS < <(find "$BIDS_ROOT/$SUBJECT" -maxdepth 1 -type d -name "ses-*" | sort)

    if [[ ${#FOUND_SESSIONS[@]} -eq 1 ]]; then
        INPUT_SESSION="$(basename "${FOUND_SESSIONS[0]}")"
        TEMPLATE_DIR="$BIDS_ROOT/derivatives/preproc/$SUBJECT/$INPUT_SESSION/anat"
        SKULLSTRIPPED_OUTPUT="${SUBJECT}_${INPUT_SESSION}_T1w_desc-biasCorrected-skullStripped.nii"
    else
        INPUT_SESSION="ses-all"
        TEMPLATE_DIR="$BIDS_ROOT/derivatives/preproc/$SUBJECT/ses-all/anat"
        SKULLSTRIPPED_OUTPUT="${SUBJECT}_ses-all_T1w_desc-biasCorrected-template-skullStripped-manualEdits.nii.gz"
    fi
fi

echo "========================================"
echo "Input mode: $INPUT_SESSION"
echo "Using anatomical input image: $SKULLSTRIPPED_OUTPUT"
echo "========================================"

SKULLSTRIPPED_INPUT_PATH="$TEMPLATE_DIR/$SKULLSTRIPPED_OUTPUT"

# Check if skull-stripped image exists
if [[ ! -f "$SKULLSTRIPPED_INPUT_PATH" ]]; then
    echo "Error: Skull-stripped image '$SKULLSTRIPPED_INPUT_PATH' not found"
    echo "Please run required upstream anatomical steps first."
    exit 1
fi

#### Starting recon-all autorecon1 ####
echo ""
echo "========================================"
echo "Step 4.0: FreeSurfer Recon-all Autorecon1"
echo "========================================"

# Use new FreeSurfer derivatives directory
export SUBJECTS_DIR="$BIDS_ROOT/derivatives/freesurfer"
mkdir -p "$SUBJECTS_DIR"
cd "$SUBJECTS_DIR"

# Check if FreeSurfer subject directory already exists
FS_SUBJECT_DIR="$FS_SUBJECT_NAME"
if [[ -d "$FS_SUBJECT_DIR" && -f "$FS_SUBJECT_DIR/mri/T1.mgz" ]]; then
    echo "FreeSurfer subject directory '$FS_SUBJECT_DIR' already exists with T1.mgz. Skipping autorecon1."
    run_recon1=false
else
    run_recon1=true
fi


if [[ "$run_recon1" == "true" ]]; then
    echo "Running autorecon1. This will take about half an hour..."
    apptainer exec "$FREESURFER_CONTAINER" recon-all -autorecon1 -noskullstrip \
              -i "$SKULLSTRIPPED_INPUT_PATH" \
              -s "$FS_SUBJECT_NAME" \
              -sd "$SUBJECTS_DIR" \
              -parallel -hires

    echo -e "\e[36mAutorecon1 completed. Making symbolic links. If you want, check T1.mgz\e[0m"
    cd "$FS_SUBJECT_NAME/mri/"

    # Symbolic links
    ln -sf T1.mgz brainmask.auto.mgz
    ln -sf brainmask.auto.mgz brainmask.mgz
    cd "$SUBJECTS_DIR"
else
    echo -e "Recon-all autorecon1 step skipped."
    echo -e "Using existing FreeSurfer subject: $FS_SUBJECT_DIR"
fi

echo "========================================"
echo "Autorecon1 phase completed"
echo "========================================"

#### Starting recon-all autorecon2 & autorecon3 ####
echo ""
echo "========================================"
echo "Step 4.1: FreeSurfer Recon-all Autorecon2 & Autorecon3"
echo "========================================"


export SUBJECTS_DIR="$BIDS_ROOT/derivatives/freesurfer"
mkdir -p "$SUBJECTS_DIR"
cd "$SUBJECTS_DIR"

mkdir -p $HOME/fstmp

# Check if FreeSurfer subject directory exists
FS_SUBJECT_DIR="$FS_SUBJECT_NAME"
if [[ ! -d "$FS_SUBJECT_DIR" ]]; then
    echo "Error: FreeSurfer subject directory '$FS_SUBJECT_DIR' not found in $SUBJECTS_DIR"
    echo "Please run autorecon1 first."
    exit 1
fi

# Check if recon-all parts 2 & 3 have been completed
if [[ -f "$SUBJECTS_DIR/$FS_SUBJECT_NAME/surf/lh.pial" && -f "$SUBJECTS_DIR/$FS_SUBJECT_NAME/surf/rh.pial" ]]; then
    echo "FreeSurfer recon-all parts 2 & 3 appear to be completed (pial surfaces exist). Skipping autorecon2 & autorecon3."
    run_recon23=false
else
    run_recon23=true
fi

if [[ "$run_recon23" == "true" ]]; then
    echo "Starting autorecon2 & autorecon3. This will take a few hours. Check back later..."
    apptainer exec \
        --bind $HOME/fstmp:/scratch \
        # HARD-CODED PATH: fixed FreeSurfer license path for this environment.
        --env FS_LICENSE=/opt/freesurfer-8.1.0/license.txt \
        $FREESURFER_CONTAINER recon-all -autorecon2 -autorecon3 \
        -s "$FS_SUBJECT_NAME" \
        -sd "$SUBJECTS_DIR" \
        -hires -parallel
else
    # NOTE: sub-03, sub-04, sub-05 and sub-06 had some segmentation issues around the calcarine sulcus
    # This was fixed by manually segmenting the wm.mgz file and then re-running autorecon2 & autorecon3.
    # Insert code from above here, just temprarily   
    # echo -e "Recon-all make all! Running all steps from wherever you changed files, most probably white matter (wm.mgz)."
    # END OF NOTE
    echo -e "Recon-all autorecon2 & autorecon3 steps skipped."
    echo -e "Using existing FreeSurfer processing results."
fi

echo "========================================"
echo "Autorecon2 & Autorecon3 phases completed"
echo "========================================"

echo ""
echo "=========================================="
echo "FREESURFER RECON-ALL PIPELINE COMPLETED"
echo "=========================================="
echo "FreeSurfer subject: $SUBJECT"
echo "Location: $BIDS_ROOT/derivatives/freesurfer/$SUBJECT"
echo "Full surface reconstruction completed"
echo "=========================================="
