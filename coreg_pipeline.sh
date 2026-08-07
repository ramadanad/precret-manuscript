#!/bin/bash

# coreg_pipeline.sh - BIDS boundary-based registration and surface projection
# Performs fine function-to-structure coregistration and projects to cortical surface
# Automatically detects and processes all available functional runs in BIDS format
# Processes both bssfp and epi sequences
# Automatically detects and processes all sessions if not specified
#
# Usage: $0 <BIDS root directory> <subject ID> [session ID]
# Example: ./coreg_pipeline.sh /data/bids sub-01              (processes all sessions)
# Example: ./coreg_pipeline.sh /data/bids sub-01 ses-01       (processes specific session)

# This sript is actually fairly slow... maybe it makes sense to parallelize 
# across runs and sessions in the future, but for now let's just get it working in a simple way first.


# Source common functions and variables
source "$(dirname "$0")/common_functions.sh"

ORIGINAL_ARGS=("$@")

# Check if required arguments are provided
if [[ -z "$1" || -z "$2" ]]; then
    echo "Error: At least two arguments are required."
    echo "Usage: $0 <BIDS root directory> <subject ID> [session ID]"
    echo "Example: $0 /data/bids sub-01              (processes all sessions)"
    echo "Example: $0 /data/bids sub-01 ses-01       (processes specific session)"
    exit 1
fi

BIDS_ROOT="$1"
SUBJECT="$2"
SESSION_INPUT="$3"  # Empty if not specified
TASK_NAME="prf"  # Always prf for this pipeline
SEQUENCES=("bssfp" "epi")  # Process both sequences

# Determine FreeSurfer subject directory
export SUBJECTS_DIR="$(realpath "$BIDS_ROOT/derivatives/freesurfer")"
FS_SUBJECT_DIR="$SUBJECT"
mri_folder="$SUBJECTS_DIR/$FS_SUBJECT_DIR/mri"
export APPTAINERENV_SUBJECTS_DIR="$SUBJECTS_DIR"
export APPTAINERENV_FS_SUBJECT_DIR="$FS_SUBJECT_DIR"

# Auto-detect sessions if not specified
if [[ -z "$SESSION_INPUT" ]]; then
    # Find all session directories for this subject
    declare -a SESSIONS_ARRAY
    for session_dir in "$BIDS_ROOT"/$SUBJECT/ses-*/; do
        if [[ -d "$session_dir" ]]; then
            session_name=$(basename "$session_dir")
            SESSIONS_ARRAY+=("$session_name")
        fi
    done
    
    if [[ ${#SESSIONS_ARRAY[@]} -eq 0 ]]; then
        # If no sessions found, try subject-level data (no session folder)
        if [[ -d "$BIDS_ROOT/$SUBJECT/func" ]]; then
            SESSIONS_ARRAY=("none")
        else
            echo "Error: No sessions found for $SUBJECT"
            exit 1
        fi
    else
        # Sort sessions
        SESSIONS_ARRAY=($(printf '%s\n' "${SESSIONS_ARRAY[@]}" | sort))
    fi
else
    # Use the specified session
    SESSIONS_ARRAY=("$SESSION_INPUT")
fi

# Define BIDS functional directory
# Will be set inside the session loop

############################################################################
############################     WHAT IS WHAT?    ##########################
############################################################################

# List of projection fractions to run (will iterate over these)
PROJFRACS=(0.5)
# Default projection fraction for status output
projfrac=${PROJFRACS[0]}


COMMAND_LINE="$(build_cmdline_string "$0" "${ORIGINAL_ARGS[@]}")"
SESSION_CONTEXT="${SESSION_INPUT:-all-sessions}"
init_pipeline_logging "$BIDS_ROOT" "$SUBJECT" "coreg_pipeline" "$SESSION_CONTEXT" "$COMMAND_LINE" || exit 1
log_pipeline_run_start

finalize_coreg_log() {
    local exit_code=$?
    if [[ $exit_code -eq 0 ]]; then
        log_pipeline_run_end "success"
    else
        log_pipeline_run_end "failure(exit_code=${exit_code})"
    fi
}
trap finalize_coreg_log EXIT

# Redirect all output (stdout and stderr) to the log file
exec > >(tee -a "$LOGFILE") 2>&1

set -e

# Validate FreeSurfer output exists (needed for all sessions)
if [[ ! -f "$mri_folder/T1.mgz" ]]; then
    echo "Error: FreeSurfer output T1.mgz not found in $mri_folder/"
    echo "Please run FreeSurfer recon-all first."
    exit 1
fi

vol2surf="$SUBJECTS_DIR/$FS_SUBJECT_DIR/vol2surf/"
mkdir -p "$vol2surf"

echo ""
echo "========================================"
echo "BBR and Surface Projection"
echo "========================================"
echo "BIDS Root: $BIDS_ROOT"
echo "Subject: $SUBJECT"
echo "Sessions to process: ${SESSIONS_ARRAY[@]}"
echo "Task: $TASK_NAME"
echo "Sequences: ${SEQUENCES[@]}"
echo "FreeSurfer Subject: $FS_SUBJECT_DIR"
echo "Projection Fraction: $projfrac"
echo ""

# Process each session
for SESSION in "${SESSIONS_ARRAY[@]}"; do
    # get the intermediate T1 file for this session
    INTERMEDIATE_FILE="$BIDS_ROOT/derivatives/preproc/$SUBJECT/$SESSION/anat/${SUBJECT}_${SESSION}_T1w_desc-biasCorrected-skullStripped.nii"

    # Define BIDS functional directory for this session
    DERIV_DIR="$BIDS_ROOT/derivatives/preproc/$SUBJECT/$SESSION/func"
        
    echo "========================================"
    echo "Processing session: $SESSION"
    echo "========================================"
    
    # Validate functional directory exists for this session
    if [[ ! -d "$DERIV_DIR" ]]; then
        echo "  Warning: No func directory found for session $SESSION, skipping."
        echo ""
        continue
    fi

    # Process each sequence
    for SEQUENCE in "${SEQUENCES[@]}"; do
        echo "  ========================================"
        echo "  Processing sequence: $SEQUENCE"
        echo "  ========================================"

        if [[ "$SEQUENCE" == "bssfp" ]]; then
            required_desc="desc-dummyRemoval-motionCorr"
            required_ext=".nii"
        elif [[ "$SEQUENCE" == "epi" ]]; then
            required_desc="desc-dummyRemoval-motionCorr-distortionCorr"
            required_ext=".nii.gz"
        else
            echo "    Warning: Unknown sequence $SEQUENCE, skipping."
            continue
        fi

        # Auto-detect all functional runs in BIDS format
        # bssfp: motionCorr .nii ; epi: motionCorr-distortionCorr .nii.gz
        unset RUNS  # Clear previous runs
        declare -a RUNS
        
        # Use find to get all matching nifti files (exclude .json sidecars)
        # Must match the exact sequence type in the filename
        while IFS= read -r run_file; do
            if [[ -n "$run_file" ]]; then
                # Extract run number from the filename
                basename_file=$(basename "$run_file")
                run_num=$(echo "$basename_file" | grep -oP 'run-\K[0-9]+' || echo "")
                
                if [[ -n "$run_num" ]]; then
                    echo "    Found run file: $basename_file (run number: $run_num)"
                    RUNS+=("$run_num")
                fi
            fi
        done < <(find "$DERIV_DIR" -maxdepth 1 -type f -name "${SUBJECT}_${SESSION}_task-${TASK_NAME}_run-*_acq-${SEQUENCE}_${required_desc}${required_ext}" 2>/dev/null | sort -u)

        # Remove duplicates and sort
        RUNS=($(printf '%s\n' "${RUNS[@]}" | sort -u))
        
       
        if [[ ${#RUNS[@]} -eq 0 ]]; then
            if [[ "$SEQUENCE" == "epi" ]]; then
                echo "    Error: No distortion-corrected EPI runs found for session $SESSION."
                echo "    Expected pattern: ${SUBJECT}_${SESSION}_task-${TASK_NAME}_run-*_acq-epi_desc-dummyRemoval-motionCorr-distortionCorr.nii.gz"
            fi
            echo "    No runs found for sequence $SEQUENCE, skipping."
        else
            echo "    Found ${#RUNS[@]} run(s): ${RUNS[@]}"
            echo ""

            # Function to find the functional run file
            find_run_file() {
                local run_id=$1
                local nifti_file="${DERIV_DIR}/${SUBJECT}_${SESSION}_task-${TASK_NAME}_run-${run_id}_acq-${SEQUENCE}_${required_desc}${required_ext}"
                if [[ ! -f "$nifti_file" ]]; then
                    nifti_file=""
                fi
                echo "$nifti_file"
            }

            # Process each run
            for run_id in "${RUNS[@]}"; do
                run_file=$(find_run_file "$run_id")
                
                if [[ -z "$run_file" ]]; then
                    echo "    Warning: Could not find functional file for run $run_id, skipping."
                    continue
                fi
                
                echo "    Processing run: $run_id ($SEQUENCE)"
                echo "      Input file: $(basename "$run_file")"
                               
                # BBR registration
                lta_file="${vol2surf}/${SUBJECT}_${SESSION}_task-${TASK_NAME}_run-${run_id}_acq-${SEQUENCE}_bbr.lta"
                
                if [[ -f "$lta_file" ]]; then
                    echo "      BBR registration file already exists, skipping bbregister."
                else
                    bash "$(dirname "$0")/coreg_steps/c0_bbr.sh" "$SUBJECTS_DIR" "$FREESURFER_CONTAINER" \
                        "$FS_SUBJECT_DIR" "$run_file" "$INTERMEDIATE_FILE" "$lta_file"

                fi

                # Move bbregister side outputs (.dat*/.log) to vol2surf/bbr_interim once LTA exists.
                bash "$(dirname "$0")/coreg_steps/c2_cleanup.sh" "$lta_file"
                
                # Surface projection for both hemispheres and multiple projection fractions
                for hemi in lh rh; do
                    for proj in "${PROJFRACS[@]}"; do
                        projfrac_local=$(echo "$proj" | sed 's/\./p/')
                        output_file="${vol2surf}/${hemi}_${SUBJECT}_${SESSION}_task-${TASK_NAME}_run-${run_id}_acq-${SEQUENCE}_projFrac-${projfrac_local}.mgh"

                        if [[ -f "$output_file" ]]; then
                            echo "      Surface projection for $hemi proj=$proj already exists, skipping."
                        else
                            echo "      Projecting to $hemi surface (proj=$proj)..."
                            bash "$(dirname "$0")/coreg_steps/c1_vol2surf.sh" "$SUBJECTS_DIR" "$FREESURFER_CONTAINER" \
                                "$run_file" "$lta_file" "$hemi" "$output_file" "$proj"
                        fi
                    done
                done
                
                echo "      Run $run_id completed."
                echo ""
            done
        fi

    done  # End sequence loop
done  # End session loop

echo "========================================"
echo "BBR and Surface Projection Complete"
echo "========================================"
echo "Output directory: $vol2surf/"
echo "Log file: $LOGFILE"
echo "========================================"

echo "Now creating projFrac folders and moving files into them..."
# Create projFrac folders and move files into them
for proj in "${PROJFRACS[@]}"; do
    projfrac_local=$(echo "$proj" | sed 's/\./p/')
    projfrac_dir="${vol2surf}/projFrac-${projfrac_local}/"
    mkdir -p "$projfrac_dir"
    mv "${vol2surf}/"*_projFrac-${projfrac_local}.mgh "$projfrac_dir"
done
echo "All done!"



