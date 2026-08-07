#!/bin/bash

# Shared helpers for anatomical pipeline Step 1/2 processing.
# This file is sourced by orchestration scripts and expects these globals:
# - BIDS_ROOT
# - SUBJECT
# - SCRIPT_DIR

process_session_bfc() {
    local session_id="$1"
    local session_logfile="$2"

    setup_pipeline "$BIDS_ROOT" "$SUBJECT" "$session_id"
    exec > >(tee -a "$session_logfile") 2>&1

    echo "========================================"
    echo "Processing Bias Field Correction"
    echo "Subject: $SUBJECT, Session: $session_id"
    echo "Started: $(date)"
    echo "========================================"

    discover_t1w_input
    stage_t1w_for_bfc
    cd "$DERIVATIVES_DIR"

    local bfc_output
    bfc_output="${BIDS_OUTPUT_PREFIX}_T1w_desc-biasCorrected.nii"

    if [[ -f "$bfc_output" ]]; then
        echo "Bias field corrected image '$bfc_output' already exists for $session_id."
        echo "Skipping bias field correction for $session_id."
        return 0
    fi

    echo "Running bias field correction for $session_id..."

    local clean_session_id
    clean_session_id="${session_id//-/_}"

    cat > "temp_bias_correction_${clean_session_id}.m" << EOF
addpath(genpath(pwd));
try
    a1_bfc_SPM('${T1W_INPUT}', '${DERIVATIVES_DIR}/${bfc_output}');
    fprintf('Bias field correction completed successfully for ${session_id}.\n');
    exit(0);
catch ME
    fprintf('MATLAB Error for ${session_id}: %s\n', ME.message);
    fprintf('Error in: %s at line %d\n', ME.stack(1).name, ME.stack(1).line);
    exit(1);
end
EOF

    run_matlab_container "$BIDS_ROOT" "$SCRIPT_DIR" "$DERIVATIVES_DIR" "run('temp_bias_correction_${clean_session_id}.m')" || {
        echo "Error: MATLAB bias correction failed for ${session_id}."
        rm -f "temp_bias_correction_${clean_session_id}.m"
        return 1
    }

    rm -f "temp_bias_correction_${clean_session_id}.m"

    cat > "${BIDS_OUTPUT_PREFIX}_T1w_desc-biasCorrected.json" << EOF
{
    "Description": "Bias field corrected T1-weighted image",
    "Sources": ["$(basename "$T1W_INPUT")"],
    "SpatialReference": "orig",
    "SkullStripped": false,
    "Resolution": "native",
    "Density": "native",
    "GeneratedBy": [
        {
            "Name": "SPM12",
            "Version": "$SPM_VERSION",
            "Description": "Bias field correction using SPM12 unified segmentation"
        },
        {
            "Name": "MATLAB",
            "Version": "$MATLAB_VERSION",
            "Description": "MATLAB runtime environment"
        }
    ]
}
EOF

    echo "Bias field correction completed for $session_id: $bfc_output"
    echo "Completed: $(date)"
}

process_session_skull() {
    local session_id="$1"
    local session_logfile="$2"

    setup_pipeline "$BIDS_ROOT" "$SUBJECT" "$session_id"
    exec > >(tee -a "$session_logfile") 2>&1

    echo "========================================"
    echo "Processing Skull Stripping"
    echo "Subject: $SUBJECT, Session: $session_id"
    echo "Started: $(date)"
    echo "========================================"

    local bfc_output
    bfc_output="${BIDS_OUTPUT_PREFIX}_T1w_desc-biasCorrected.nii"

    if [[ ! -f "$DERIVATIVES_DIR/$bfc_output" ]]; then
        echo "Error: Bias field corrected image '$bfc_output' not found in $DERIVATIVES_DIR"
        echo "Please run bias field correction step first for $session_id."
        return 1
    fi

    cd "$DERIVATIVES_DIR"

    local skullstripped_output mask_output
    skullstripped_output="${BIDS_OUTPUT_PREFIX}_T1w_desc-biasCorrected-skullStripped.nii"
    mask_output="${BIDS_OUTPUT_PREFIX}_T1w_desc-brainMask.nii"

    if [[ -f "$skullstripped_output" && -f "$mask_output" ]]; then
        echo "Skull-stripped image '$skullstripped_output' and mask '$mask_output' already exist for $session_id."
        echo "Skipping skull stripping for $session_id."
        return 0
    fi

    echo "Running skull stripping for $session_id..."

    apptainer exec "$FREESURFER_CONTAINER" mri_synthstrip -i "$bfc_output" \
                   -o "$skullstripped_output" \
                   -m "$mask_output" \
                   --no-csf

    cat > "${BIDS_OUTPUT_PREFIX}_T1w_desc-biasCorrected-skullStripped.json" << EOF
{
    "Description": "Skull-stripped and bias field corrected T1-weighted image",
    "Sources": ["$bfc_output"],
    "SpatialReference": "orig",
    "SkullStripped": true,
    "Resolution": "native",
    "Density": "native",
    "GeneratedBy": [
        {
            "Name": "FreeSurfer",
            "Version": "$FREESURFER_VERSION",
            "Description": "Skull stripping using FreeSurfer SynthStrip"
        }
    ]
}
EOF

    cat > "${BIDS_OUTPUT_PREFIX}_T1w_desc-brainMask.json" << EOF
{
    "Description": "Brain extraction mask derived from T1-weighted image",
    "Sources": ["$bfc_output"],
    "Type": "Brain",
    "SpatialReference": "orig",
    "Resolution": "native",
    "Density": "native",
    "GeneratedBy": [
        {
            "Name": "FreeSurfer",
            "Version": "$FREESURFER_VERSION",
            "Description": "Brain mask generation using FreeSurfer SynthStrip"
        }
    ]
}
EOF

    echo "Skull stripping completed for $session_id:"
    echo "  Output: $skullstripped_output"
    echo "  Mask: $mask_output"
    echo "Completed: $(date)"
}

process_session_bfc_skull() {
    local session_id="$1"
    local session_logfile="$2"

    process_session_bfc "$session_id" "$session_logfile" || return 1
    process_session_skull "$session_id" "$session_logfile" || return 1

    echo "========================================"
    echo "Both bias field correction and skull stripping completed for $session_id"
    echo "Completed: $(date)"
    echo "========================================"
}

run_parallel_sessions() {
    local task_label="$1"
    local log_prefix="$2"
    local worker_fn="$3"

    local subject_dir
    subject_dir="$BIDS_ROOT/$SUBJECT"

    if [[ -z "${LOGFILE:-}" ]]; then
        init_pipeline_logging "$BIDS_ROOT" "$SUBJECT" "anat_pipeline" "all-sessions" "${PIPELINE_CMDLINE:-$0}" || return 1
    fi

    if [[ ! -d "$subject_dir" ]]; then
        echo "Error: Subject directory '$subject_dir' does not exist."
        return 1
    fi

    local -a sessions
    mapfile -t sessions < <(find "$subject_dir" -maxdepth 1 -type d -name "ses-*" | sort)
    PARALLEL_SESSION_COUNT=${#sessions[@]}

    if [[ $PARALLEL_SESSION_COUNT -eq 0 ]]; then
        echo "No session directories found. Processing subject-level data..."
        "$worker_fn" "" "$LOGFILE"
        return $?
    fi

    echo "Found $PARALLEL_SESSION_COUNT session(s) for $SUBJECT:"
    local -a session_ids
    for session_dir in "${sessions[@]}"; do
        local session_id
        session_id=$(basename "$session_dir")
        session_ids+=("$session_id")
        echo "  - $session_id"
    done
    echo ""
    echo "Starting parallel processing of all sessions..."

    local -a pids
    for session_id in "${session_ids[@]}"; do
        echo "Starting ${task_label} for $session_id in background..."
        ("$worker_fn" "$session_id" "$LOGFILE") &
        pids+=("$!")
    done

    echo "Waiting for all sessions to complete ${task_label}..."
    local -a failed_sessions
    local i
    for i in "${!pids[@]}"; do
        local session_id
        session_id="${session_ids[$i]}"
        if ! wait "${pids[$i]}"; then
            failed_sessions+=("$session_id")
            echo "ERROR: ${task_label^} failed for $session_id"
        else
            echo "${task_label^} completed successfully for $session_id"
        fi
    done

    if [[ ${#failed_sessions[@]} -gt 0 ]]; then
        echo ""
        echo "========================================"
        echo "ERROR: ${task_label^} failed for the following sessions:"
        local failed_session
        for failed_session in "${failed_sessions[@]}"; do
            echo "  - $failed_session"
        done
        echo "========================================"
        return 1
    fi

    echo ""
    echo "========================================"
    echo "${task_label^} completed successfully for all sessions"
    echo "Processed sessions:"
    local session_id
    for session_id in "${session_ids[@]}"; do
        echo "  - $session_id"
    done
    echo "========================================"

    return 0
}
