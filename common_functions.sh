#!/bin/bash

# common_functions.sh - Common variables and functions for BIDS anatomical processing pipeline

# Define container paths
CONTAINERS_PATH="/ptmp/dramadan/containers"
FREESURFER_CONTAINER="$CONTAINERS_PATH/freesurfer_8.1.0_latest.sif" # did not use 8.0.0 because it was not working "ERROR: cannot use ML routines"
ANTS_CONTAINER="$CONTAINERS_PATH/ants_2.6.0_20250424.sif"
FSL_CONTAINER="$CONTAINERS_PATH/fsl_6.0.7.16_20250131.sif"

# MATLAB container/toolbox setup
MATLAB_CONTAINER="$CONTAINERS_PATH/matlab-r2024b-2024-11-24-bfbf29ea5350.sif"
MATLAB_SPM_HOST="$HOME/matlab/spm"

# instead of the ants default scripts use fluesebrink's scripts
# set the analysis dir to the path where commen_functions is located
ANALYSIS_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"

# Software version fallbacks (known versions for this pipeline)
SPM_VERSION="${SPM_VERSION:-SPM25}"
MATLAB_VERSION="${MATLAB_VERSION:-R2024b}"
FREESURFER_VERSION="${FREESURFER_VERSION:-8.1.0}"

# Build a shell-escaped command line string from argv parts.
build_cmdline_string() {
    local cmdline=""
    local arg
    for arg in "$@"; do
        cmdline+="$(printf '%q' "$arg") "
    done
    echo "${cmdline% }"
}

# Initialize canonical pipeline logging for one subject/pipeline.
# Canonical path: <bids_root>/derivatives/logs/<subject>/<subject>_<pipeline>.log
init_pipeline_logging() {
    local bids_root="$1"
    local subject="$2"
    local pipeline_name="$3"
    local session_context="$4"
    local cmdline="$5"

    if [[ -z "$bids_root" || -z "$subject" || -z "$pipeline_name" ]]; then
        echo "Error: init_pipeline_logging requires bids_root, subject, and pipeline_name"
        return 1
    fi

    local logs_dir
    logs_dir="$bids_root/derivatives/logs/$subject"
    mkdir -p "$logs_dir"

    LOGFILE="$logs_dir/${subject}_${pipeline_name}.log"
    PIPELINE_NAME="$pipeline_name"
    PIPELINE_SESSION_CONTEXT="$session_context"
    PIPELINE_CMDLINE="$cmdline"
    export LOGFILE PIPELINE_NAME PIPELINE_SESSION_CONTEXT PIPELINE_CMDLINE

    return 0
}

# Append a START boundary marker for one pipeline invocation.
log_pipeline_run_start() {
    local ts
    ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

    {
        echo ""
        echo "===================================================================================="
        echo "RUN START | pipeline=${PIPELINE_NAME:-unknown} | timestamp_utc=${ts}"
        echo "command: ${PIPELINE_CMDLINE:-unknown}"
        echo "subject: ${SUBJECT:-unknown}"
        echo "session: ${PIPELINE_SESSION_CONTEXT:-unknown}"
        echo "===================================================================================="
    } >> "$LOGFILE"
}

# Append an END boundary marker for one pipeline invocation.
log_pipeline_run_end() {
    local status="$1"
    local ts
    ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

    {
        echo "===================================================================================="
        echo "RUN END   | pipeline=${PIPELINE_NAME:-unknown} | timestamp_utc=${ts} | status=${status}"
        echo "subject: ${SUBJECT:-unknown}"
        echo "session: ${PIPELINE_SESSION_CONTEXT:-unknown}"
        echo "===================================================================================="
        echo ""
    } >> "$LOGFILE"
}


# Function to validate arguments and set up paths
setup_pipeline() {
    # Check if required arguments are provided
    if [[ -z "$1" || -z "$2" ]]; then
        echo "Error: Both BIDS root directory and subject ID are required."
        echo "Usage: <script> <BIDS root directory> <subject ID> [session ID]"
        echo "Example: <script> /path/to/bids sub-01"
        echo "Example: <script> /path/to/bids sub-01 ses-01"
        exit 1
    fi

    # Parse arguments
    BIDS_ROOT="$1"
    SUBJECT="$2"
    SESSION="$3"

    # Validate BIDS root directory exists
    if [[ ! -d "$BIDS_ROOT" ]]; then
        echo "Error: BIDS root directory '$BIDS_ROOT' does not exist."
        exit 1
    fi

    # Set up BIDS paths
    if [[ -n "$SESSION" ]]; then
        SUBJECT_DIR="$BIDS_ROOT/$SUBJECT/$SESSION"
        ANAT_DIR="$SUBJECT_DIR/anat"
        DERIVATIVES_DIR="$BIDS_ROOT/derivatives/preproc/$SUBJECT/$SESSION/anat"
        OUTPUT_PREFIX="${SUBJECT}_${SESSION}"
    else
        SUBJECT_DIR="$BIDS_ROOT/$SUBJECT"
        # Find all anat directories in all session folders
        ANAT_DIRS=( $(find "$SUBJECT_DIR" -maxdepth 2 -type d -name anat) )
        DERIVATIVES_DIR="$BIDS_ROOT/derivatives/preproc/$SUBJECT"
        OUTPUT_PREFIX="$SUBJECT"
    fi

    # Validate subject directory exists
    if [[ ! -d "$SUBJECT_DIR" ]]; then
        echo "Error: Subject directory '$SUBJECT_DIR' does not exist."
        exit 1
    fi

    # Validate anatomical directory exists (only if session is given)
    if [[ -n "$SESSION" ]]; then
        if [[ ! -d "$ANAT_DIR" ]]; then
            echo "Error: Anatomical directory '$ANAT_DIR' does not exist."
            exit 1
        fi
    fi

    # Create derivatives directory
    mkdir -p "$DERIVATIVES_DIR"

    # Keep LOGFILE stable if already initialized by a top-level pipeline.
    if [[ -z "${LOGFILE:-}" ]]; then
        local pipeline_name
        pipeline_name="${PIPELINE_NAME:-anat_pipeline}"
        init_pipeline_logging "$BIDS_ROOT" "$SUBJECT" "$pipeline_name" "${SESSION:-all-sessions}" "${PIPELINE_CMDLINE:-$0}"
    fi

    # Create BIDS-compliant output prefix including session if present
    if [[ -n "$SESSION" ]]; then
        BIDS_OUTPUT_PREFIX="${SUBJECT}_${SESSION}"
    else
        BIDS_OUTPUT_PREFIX="$SUBJECT"
    fi

    # Export variables for use in other scripts
    export BIDS_ROOT SUBJECT SESSION SUBJECT_DIR ANAT_DIR DERIVATIVES_DIR OUTPUT_PREFIX
    export LOGFILE BIDS_OUTPUT_PREFIX CONTAINERS_PATH FREESURFER_CONTAINER ANTS_CONTAINER FSL_CONTAINER
    export MATLAB_CONTAINER MATLAB_SPM_HOST ANALYSIS_DIR
}

# Validate MATLAB container prerequisites for containerized execution
validate_matlab_container_setup() {
    local bids_root="$1"

    if [[ ! -f "$MATLAB_CONTAINER" ]]; then
        echo "Error: MATLAB container not found: $MATLAB_CONTAINER"
        return 1
    fi

    if [[ ! -d "$MATLAB_SPM_HOST" ]]; then
        echo "Error: SPM path not found: $MATLAB_SPM_HOST"
        return 1
    fi

    if [[ ! -d "$bids_root" ]]; then
        echo "Error: BIDS root for binding not found: $bids_root"
        return 1
    fi

    return 0
}

# Run MATLAB commands in the configured MATLAB container
run_matlab_container() {
    local bids_root="$1"
    local script_dir="$2"
    local work_dir="$3"
    local matlab_cmd="$4"

    validate_matlab_container_setup "$bids_root" || return 1

    local bind_paths
    bind_paths="${ANALYSIS_DIR}:${ANALYSIS_DIR},${bids_root}:${bids_root},${MATLAB_SPM_HOST}:${MATLAB_SPM_HOST}"

    apptainer exec --bind "$bind_paths" "$MATLAB_CONTAINER" matlab -nodisplay -nosplash -nodesktop -r \
        "try; addpath(genpath('${script_dir}')); addpath(genpath('${MATLAB_SPM_HOST}')); cd('${work_dir}'); ${matlab_cmd}; catch ME; fprintf(2, 'MATLAB Error: %s\\n', getReport(ME, 'extended')); exit(1); end; exit(0);"
}

# Validate that every file in a named array exists on disk.
require_files_exist_from_array() {
    local array_name="$1"
    local label="${2:-file}"
    local -n files_ref="$array_name"

    if [[ ${#files_ref[@]} -eq 0 ]]; then
        echo "Error: No ${label}s found"
        return 1
    fi

    local missing=0
    for file in "${files_ref[@]}"; do
        if [[ ! -f "$file" ]]; then
            echo "Error: Missing ${label}: $file"
            missing=1
        fi
    done

    return "$missing"
}

# Discover T1w input paths without copying/staging into derivatives.
discover_t1w_input() {
    echo "Discovering anatomical input data"

    # Find T1w images in BIDS format
    if [[ -n "$SESSION" ]]; then
        T1W_FILES=( $(find "$ANAT_DIR" -name "*T1w.nii.gz" -o -name "*T1w.nii") )
    else
        T1W_FILES=()
        for anat_dir in "${ANAT_DIRS[@]}"; do
            found=( $(find "$anat_dir" -name "*T1w.nii.gz" -o -name "*T1w.nii") )
            T1W_FILES+=("${found[@]}")
        done
    fi

    if [[ ${#T1W_FILES[@]} -eq 0 ]]; then
        echo "Error: No T1w images found in any anat directory"
        exit 1
    fi

    echo "Found ${#T1W_FILES[@]} T1w image(s):"
    for file in "${T1W_FILES[@]}"; do
        echo "  $(basename "$file")"
    done

    # Use the first T1w image if multiple exist
    T1W_INPUT="${T1W_FILES[0]}"
    echo "Using: $(basename "$T1W_INPUT")"

    # Export selected input path for downstream processing.
    export T1W_INPUT
}

# Stage discovered T1w input into DERIVATIVES_DIR as an uncompressed .nii file.
# This preserves a local session T1w for downstream BBR while BFC runs.
stage_t1w_for_bfc() {
    if [[ -z "$T1W_INPUT" ]]; then
        echo "Error: T1W_INPUT is not set. Call discover_t1w_input first."
        return 1
    fi

    if [[ -z "$DERIVATIVES_DIR" ]]; then
        echo "Error: DERIVATIVES_DIR is not set."
        return 1
    fi

    mkdir -p "$DERIVATIVES_DIR"

    local src staged_name staged_path
    src="$T1W_INPUT"

    if [[ "$src" == *.gz ]]; then
        staged_name="$(basename "$src" .gz)"
        cp -f "$src" "$DERIVATIVES_DIR/"
        gunzip -f "$DERIVATIVES_DIR/$(basename "$src")"
    else
        staged_name="$(basename "$src")"
        cp -f "$src" "$DERIVATIVES_DIR/"
    fi

    staged_path="$DERIVATIVES_DIR/$staged_name"
    T1W_INPUT="$staged_path"
    export T1W_INPUT

    echo "Staged T1w input for BFC: $T1W_INPUT"
}
