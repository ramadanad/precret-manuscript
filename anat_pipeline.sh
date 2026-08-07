#!/bin/bash

# anat_pipeline.sh - Master script for BIDS anatomical processing pipeline
# Usage: anat_pipeline.sh <BIDS root directory> <subject ID> [session ID]
# 
# This script runs the anatomical processing pipeline by executing individual step scripts in order:
# 0. Data setup and validation
# 1. Bias field correction
# 2. Skull stripping
# 3. Template creation
# 4. FreeSurfer recon-all (autorecon1, autorecon2, autorecon3)
# 5. Benson14 retinotopy mapping (optional)
# 6. Convert cortex labels to NIfTI (disabled for now)
# 7. Convert T1.mgz to NIfTI
#
# Get the directory where this script is located
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
STEP_DIR="${SCRIPT_DIR}/anat_steps"
source "${SCRIPT_DIR}/common_functions.sh"

# Parse arguments
ARGS=("$@")
COMMAND_LINE="$(build_cmdline_string "$0" "${ARGS[@]}")"

# Check if required arguments are provided
if [[ ${#ARGS[@]} -lt 2 ]]; then
    echo "Error: Both BIDS root directory and subject ID are required."
    echo "Usage: $0 <BIDS root directory> <subject ID> [session ID]"
    echo "Example: $0 /path/to/bids sub-01"
    echo "Example: $0 /path/to/bids sub-01 ses-01"
    exit 1
fi

# Parse arguments
BIDS_ROOT="${ARGS[0]}"
SUBJECT="${ARGS[1]}"
SESSION="${ARGS[2]}"

# Resolve processing mode into exactly two cases:
# 1) MULTI_SESSION: multiple sessions discovered and no explicit session requested.
# 2) SINGLE_SESSION: explicit session requested OR exactly one session discovered.
PROCESSING_MODE=""
EFFECTIVE_SESSION=""
SUBJECT_DIR="$BIDS_ROOT/$SUBJECT"

if [[ -n "$SESSION" ]]; then
    PROCESSING_MODE="SINGLE_SESSION"
    EFFECTIVE_SESSION="$SESSION"
else
    mapfile -t FOUND_SESSIONS < <(find "$SUBJECT_DIR" -maxdepth 1 -type d -name "ses-*" | sort)

    if [[ ${#FOUND_SESSIONS[@]} -eq 1 ]]; then
        PROCESSING_MODE="SINGLE_SESSION"
        EFFECTIVE_SESSION="$(basename "${FOUND_SESSIONS[0]}")"
    elif [[ ${#FOUND_SESSIONS[@]} -gt 1 ]]; then
        PROCESSING_MODE="MULTI_SESSION"
    else
        echo "Error: No session directories found in $SUBJECT_DIR"
        echo "Expected at least one directory matching ses-*"
        exit 1
    fi
fi

# Keep backward-compatible flag naming for existing step selection logic.
SKIP_TEMPLATE_CREATION=false
if [[ "$PROCESSING_MODE" == "SINGLE_SESSION" ]]; then
    SKIP_TEMPLATE_CREATION=true
fi

SESSION_CONTEXT="${EFFECTIVE_SESSION:-all-sessions}"
init_pipeline_logging "$BIDS_ROOT" "$SUBJECT" "anat_pipeline" "$SESSION_CONTEXT" "$COMMAND_LINE" || exit 1
log_pipeline_run_start

finalize_anat_log() {
    local exit_code=$?
    if [[ $exit_code -eq 0 ]]; then
        log_pipeline_run_end "success"
    else
        log_pipeline_run_end "failure(exit_code=${exit_code})"
    fi
}
trap finalize_anat_log EXIT

echo "========================================"
echo "BIDS Anatomical Processing Pipeline"
echo "Master Script - Running All Steps"
echo "========================================"
echo "BIDS root: $BIDS_ROOT"
echo "Subject: $SUBJECT"
echo "Processing mode: $PROCESSING_MODE"
if [[ "$PROCESSING_MODE" == "SINGLE_SESSION" ]]; then
    echo "Session: $EFFECTIVE_SESSION"
    echo "Execution mode: Sequential single-session processing"
else
    echo "Execution mode: Parallel multi-session processing"
fi
echo "Log file: $LOGFILE"
echo "Started: $(date)"
echo "========================================"

# Define steps based on exactly two processing modes.
if [[ "$PROCESSING_MODE" == "MULTI_SESSION" ]]; then
    STEPS=(
        # "a0_setup.sh"
        # "a123_parallel.sh"
        "a4_reconall.sh"
        "a5_benson14.sh"
        # # "a6_convert_labels.sh"  # Disabled for testing pipeline without Step 6 ... everything works without it, so optional..
        # "a7_convert_t1mgz.sh"
    )

    STEP_DESCRIPTIONS=(
        # "Data setup and validation"
        # "Bias field correction, skull stripping, and template creation (all sessions in parallel)"
        "FreeSurfer recon-all (autorecon1, autorecon2, autorecon3)"
        "Benson14 retinotopy mapping (if recon-all successful)"
        # # "Convert cortex labels to NIfTI"  # Disabled for testing pipeline without Step 6 ... everything works without it, so optional..
        # "Convert T1.mgz to NIfTI"
    )
else
    STEPS=(
        "a0_setup.sh"
        "a1_bias_correction.sh"
        "a2_skull_stripping.sh"
        "a4_reconall.sh"
        "a5_benson14.sh"
        # "a6_convert_labels.sh"  # Disabled for testing pipeline without Step 6 ... everything works without it, so optional..
        "a7_convert_t1mgz.sh"
    )

    STEP_DESCRIPTIONS=(
        "Data setup and validation"
        "Bias field correction using SPM12"
        "Skull stripping using FreeSurfer SynthStrip"
        "FreeSurfer recon-all (autorecon1, autorecon2, autorecon3)"
        "Benson14 retinotopy mapping (if recon-all successful)"
        # "Convert cortex labels to NIfTI"  # Disabled for testing pipeline without Step 6... everything works without it, so optional..
        "Convert T1.mgz to NIfTI"
    )
fi

# Function to run a step
run_step() {
    local step_num=$1
    local step_script=$2
    local step_desc=$3
    local conda_bin
    local benson_env="benson_atlas"
    
    echo ""
    echo "========================================"
    echo "Running Step $step_num: $step_desc"
    echo "Script: $step_script"
    echo "========================================"
    
    # Check if script exists
    if [[ ! -f "$STEP_DIR/$step_script" ]]; then
        echo "Error: Step script '$step_script' not found in $STEP_DIR"
        exit 1
    fi
    
    # Special handling for Benson14: skip if neuropythy not available or check if optional
    if [[ "$step_script" == "a5_benson14.sh" ]]; then
        # Check if neuropythy is available in the configured conda environment.
        conda_bin="${CONDA_EXE:-$HOME/miniforge3/bin/conda}"
        if [[ ! -x "$conda_bin" ]] || ! "$conda_bin" run -n "$benson_env" python -c "import neuropythy" >/dev/null 2>&1; then
            echo "Note: Neuropythy not available, skipping Benson14 retinotopy mapping."
            echo "Expected conda environment: $benson_env"
            echo "Step $step_num skipped"
            return 0
        fi
    fi
    
    # Run the step script with appropriate arguments
    if [[ "$step_script" == "a123_parallel.sh" ]]; then
        # Parallel script only takes BIDS_ROOT and SUBJECT
        "$STEP_DIR/$step_script" "$BIDS_ROOT" "$SUBJECT"
    elif [[ "$step_script" == "a0_setup.sh" && "$PROCESSING_MODE" == "MULTI_SESSION" ]]; then
        # In multi-session mode setup performs validation only (no subject-level T1w copy).
        echo "Note: Setup step will validate all sessions without copying T1w data at subject level"
        "$STEP_DIR/$step_script" "$BIDS_ROOT" "$SUBJECT"
    else
        # Regular step script execution
        if [[ "$PROCESSING_MODE" == "SINGLE_SESSION" ]]; then
            "$STEP_DIR/$step_script" "$BIDS_ROOT" "$SUBJECT" "$EFFECTIVE_SESSION"
        else
            "$STEP_DIR/$step_script" "$BIDS_ROOT" "$SUBJECT"
        fi
    fi
    
    # Check if step completed successfully
    if [[ $? -ne 0 ]]; then
        echo "Error: Step $step_num ($step_script) failed"
        echo "Pipeline stopped at step $step_num"
        exit 1
    fi
    
    echo "Step $step_num completed successfully"
}

# Run all steps
for i in "${!STEPS[@]}"; do
    step_num=$i
    step_script="${STEPS[$i]}"
    step_desc="${STEP_DESCRIPTIONS[$i]}"
    
    run_step "$step_num" "$step_script" "$step_desc"
done

echo ""
echo "========================================"
echo "BIDS ANATOMICAL PIPELINE COMPLETED"
echo "All Steps Executed Successfully"
echo "========================================"
echo "Completed: $(date)"
echo "BIDS root: $BIDS_ROOT"
echo "Subject: $SUBJECT"
if [[ "$PROCESSING_MODE" == "SINGLE_SESSION" ]]; then
    echo "Session: $EFFECTIVE_SESSION"
fi
echo ""
echo "The following processing steps were completed:"
for i in "${!STEP_DESCRIPTIONS[@]}"; do
    step_num=$i
    echo "  $step_num. ${STEP_DESCRIPTIONS[$i]}"
done
echo ""
echo "All outputs are saved in:"
if [[ -n "$SESSION" ]]; then
    echo "  $BIDS_ROOT/derivatives/preproc/$SUBJECT/$EFFECTIVE_SESSION (anatomical preprocessing)"
    echo "  $BIDS_ROOT/derivatives/freesurfer/$SUBJECT (FreeSurfer recon-all outputs)"
else
    if [[ "$PROCESSING_MODE" == "SINGLE_SESSION" ]]; then
        echo "  $BIDS_ROOT/derivatives/preproc/$SUBJECT/$EFFECTIVE_SESSION (anatomical preprocessing)"
    else
        echo "  $BIDS_ROOT/derivatives/preproc/$SUBJECT (anatomical preprocessing)"
    fi
    echo "  $BIDS_ROOT/derivatives/freesurfer/$SUBJECT (FreeSurfer recon-all outputs)"
fi
echo "========================================"
