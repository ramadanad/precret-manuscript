#!/bin/bash

# func_pipeline.sh - BIDS-compatible functional processing pipeline
# Usage: ./func_pipeline.sh <BIDS_root> <subject> [options]
# Examples:
# ./func_pipeline.sh /path/to/bids sub-01 --session ses-02    # Process specific session with realign only
# ./func_pipeline.sh /path/to/bids sub-01                     # Process all sessions with realign only

# Function to display help
show_help() {
    cat << EOF
BIDS Functional Processing Pipeline

USAGE:
    $0 <BIDS_root> <subject> [options]

REQUIRED ARGUMENTS:
    BIDS_root       Path to BIDS dataset root directory
    subject         Subject ID (must start with 'sub-', e.g., sub-01)

OPTIONS:
    --session, -s           Session ID (e.g., ses-02). If not provided, all sessions will be processed
    --help, -h             Show this help message

FEATURES:
    * Automatic sequence type detection (EPI/bSSFP) from filenames
    * Automatic EPI distortion correction when EPI files are detected
    * Flexible session processing (single session or all sessions)
    * BIDS-compliant output structure

EXAMPLES:
    # Process all sessions
    $0 /path/to/bids sub-01

    # Process specific session
    $0 /path/to/bids sub-01 --session ses-02

EOF
}

############################################################################
############################     FUNCTIONS     ###########################
############################################################################

# Run a Python script in the prf_pipeline conda environment.
run_prf_python() {
    local py_script="$1"
    shift

    local conda_exe="${HOME}/miniforge3/bin/conda"
    if [[ -x "$conda_exe" ]]; then
        "$conda_exe" run -n prf_pipeline python "$py_script" "$@"
    elif command -v conda >/dev/null 2>&1; then
        conda run -n prf_pipeline python "$py_script" "$@"
    else
        return 127
    fi
}

print_section() {
    local title="$1"
    echo "===================================================================================="
    echo "  ${title}"
    echo "===================================================================================="
}

# Main processing function for a single session
process_session() {
    local bids_root="$1"
    local subject="$2"
    local session="$3"

    # Run each session in a subshell so logging redirection, shell options,
    # and any internal exit only affect the current session.
    (

    echo "  Starting processing for session: ${session}"
    
    ############################################################################
    ############################     SETUP PATHS     #########################
    ############################################################################

    # Define paths
    local SUBJECT_DIR="${bids_root}/${subject}"
    local SESSION_DIR="${SUBJECT_DIR}/${session}"
    local FUNC_DIR="${SESSION_DIR}/func"
    local DERIV_DIR="${bids_root}/derivatives"
    local DERIV_FUNC="${DERIV_DIR}/preproc/${subject}/${session}/func"
    local PREPROC_DIR="${DERIV_FUNC}"
    local FMAP_DIR="${SESSION_DIR}/fmap"

    # Create necessary directories
    mkdir -p "${DERIV_FUNC}"

    set -e

    echo "  Session directory: ${SESSION_DIR}"
    echo "  Output directory: ${DERIV_FUNC}"

    ############################################################################
    ################     VALIDATE SETUP AND ENVIRONMENT     ####################
    ############################################################################
    print_section "Validating setup..."

    if ! DISTCORR=$(run_prf_python "${SCRIPT_DIR}/func_steps/f0_validate_setup.py" "$bids_root" "$subject" "$session" "$SCRIPT_DIR"); then
        echo "  Error: Setup validation failed"
        exit 1
    fi

    ############################################################################
    ###########     DISCOVER AND PROCESS FUNCTIONAL FILES     ################
    ############################################################################
    local DISCOVER_STATE
    DISCOVER_STATE=$(mktemp)
    if ! run_prf_python "${SCRIPT_DIR}/func_steps/f1_find_func_files.py" "$FUNC_DIR" "$FMAP_DIR" "$DISCOVER_STATE"; then
        echo "  Error: Functional file discovery failed"
        rm -f "$DISCOVER_STATE"
        exit 1
    fi
    # Load discovered arrays/flags: FUNC_FILES, SEQUENCE_FILES, SEQUENCE_COUNTS, valid_files, REV_PE_EXISTS
    source "$DISCOVER_STATE"
    rm -f "$DISCOVER_STATE"

    # Show distortion correction status
    if [[ " ${!SEQUENCE_FILES[*]} " =~ " epi " ]]; then
        if [[ -n "$DISTCORR" && -x "$DISTCORR" && "$REV_PE_EXISTS" == true ]]; then
            echo "  EPI distortion correction will be applied"
        else
            echo "  EPI distortion correction will be SKIPPED"
            if [[ -z "$DISTCORR" || ! -x "$DISTCORR" ]]; then
                echo "    - Reason: Distortion correction script not available"
            fi
            if [[ "$REV_PE_EXISTS" == false ]]; then
                echo "    - Reason: Reversed phase encoded EPI file not found"
            fi
        fi
    fi

    # Count forward EPI runs (task run-*) separately from reverse-PE files.
    # Distortion correction should only be required when forward EPI runs exist.
    local forward_epi_runs=0
    if [[ -n "${SEQUENCE_FILES[epi]}" ]]; then
        local _epi_src _epi_name
        read -ra _epi_sources <<< "${SEQUENCE_FILES[epi]}"
        for _epi_src in "${_epi_sources[@]}"; do
            _epi_name=$(basename "$_epi_src")
            if [[ "$_epi_name" == *run-* && "$_epi_name" == *epi* ]]; then
                forward_epi_runs=$((forward_epi_runs + 1))
            fi
        done
    fi


    ############################################################################
    ###########     DUMMY VOLUME REMOVAL     #################################
    ############################################################################
    if ! run_prf_python "${SCRIPT_DIR}/func_steps/f2_dummy_removal.py" "$subject" "$session" "$FUNC_DIR" "$DERIV_FUNC" "$FSL_CONTAINER"; then
        echo "  Error: Dummy volume removal failed"
        exit 1
    fi

    # Set PREPROC_DIR for subsequent processing steps
    local PREPROC_DIR="${DERIV_FUNC}"

    ############################################################################
    #########################     MOTION CORRECTION      #######################
    ############################################################################
    bash "${SCRIPT_DIR}/func_steps/f3_run_mo-co.sh" "$bids_root" "$subject" "$session" "$PREPROC_DIR" "$SCRIPT_DIR" || {
        echo "  Error: Motion correction failed"
        exit 1
    }

    # Hard-fail if forward EPI runs exist but no/insufficient EPI motion-corrected outputs were produced.
    if [[ $forward_epi_runs -gt 0 ]]; then
        local epi_motion_count
        epi_motion_count=$(find "${PREPROC_DIR}" -maxdepth 1 -type f \
            -name "${subject}_${session}_task-prf_run-*_acq-epi_desc-dummyRemoval-motionCorr.nii" | wc -l)
        if [[ "$epi_motion_count" -lt "$forward_epi_runs" ]]; then
            echo "  Error: EPI motion correction did not complete."
            echo "    Expected at least ${forward_epi_runs} forward EPI motion-corrected file(s), found ${epi_motion_count}."
        fi
    fi

    ############################################################################
    ################     MOTION CORRECTION CLEANUP     #########################
    ############################################################################
    if ! run_prf_python "${SCRIPT_DIR}/func_steps/f4_cleanup_mo-co.py" "$subject" "$session" "$PREPROC_DIR"; then
        echo "  Warning: Motion correction cleanup failed"
    fi

    ############################################################################
    #########     JSON SIDECARS FOR FINAL bSSFP OUTPUTS     ###################
    ############################################################################
    print_section "Creating JSON sidecars for final bSSFP runs"

    if [[ -n "${SEQUENCE_FILES[bssfp]}" ]]; then
        read -ra bssfp_src_files <<< "${SEQUENCE_FILES[bssfp]}"

        bash "${SCRIPT_DIR}/func_steps/f5_create_bssfp_json.sh" \
            "$PREPROC_DIR" \
            "$subject" \
            "$session" \
            "$FSL_CONTAINER" \
            "$MATLAB_CONTAINER" \
            "$MATLAB_SPM_HOST" \
            "${bssfp_src_files[@]}" || {
                echo "  Warning: JSON sidecar creation failed"
            }
    else
        echo "  No bSSFP files detected, skipping JSON sidecar creation"
    fi

    ############################################################################
    #########################     QA metrics        #######################
    ############################################################################
    print_section "QA metrics (tSNR, kurtosis, skewness)"

    # Make QA_DIR
    QA_DIR="${DERIV_DIR}/qametrics/${subject}/${session}/func"
    mkdir -p "$QA_DIR"

    bash "${SCRIPT_DIR}/func_steps/f6_run_qa.sh" "$PREPROC_DIR" "$QA_DIR" || {
        echo "  Warning: QA metrics calculation failed"
    }

    
    
    ############################################################################
    #######################     DISTORTION CORRECTION      #####################
    ############################################################################
    print_section "Distortion Correction of EPI data"

    # Distortion correction is mandatory when forward EPI runs exist.
    if [[ $forward_epi_runs -gt 0 ]]; then
        if [[ -z "$DISTCORR" || ! -x "$DISTCORR" ]]; then
            echo "  Error: Distortion correction script not available, but forward EPI runs were found."

        fi
        if [[ "$REV_PE_EXISTS" != true ]]; then
            echo "  Error: Reversed phase encoded EPI file not found, but forward EPI runs were found."

        fi

        echo "  Performing distortion correction for EPI data..."

        # Call BIDS-compatible distortion correction script (hard fail on error)
        "${DISTCORR}" "${bids_root}" "${subject}" "${session}" "${FSL_CONTAINER}" || {
            echo "  Error: Distortion correction failed for ${session}."

        }

        # Hard-fail if expected distortion-corrected outputs are missing.
        local epi_distcorr_count
        epi_distcorr_count=$(find "${PREPROC_DIR}" -maxdepth 1 -type f \
            -name "${subject}_${session}_task-prf_run-*_acq-epi_desc-dummyRemoval-motionCorr-distortionCorr.nii.gz" | wc -l)
        if [[ "$epi_distcorr_count" -lt "$forward_epi_runs" ]]; then
            echo "  Error: Distortion correction did not complete."
            echo "    Expected at least ${forward_epi_runs} distortion-corrected EPI file(s), found ${epi_distcorr_count}."

        fi

        echo "  Distortion correction completed!"
    else
        echo "  No forward EPI runs found. Skipping distortion correction."
    fi

}

# Initialize variables with defaults
BIDS_ROOT=""
SUBJECT=""
SESSION=""
ORIGINAL_ARGS=("$@")

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            show_help
            exit 0
            ;;
        --session|-s)
            SESSION="$2"
            shift 2
            ;;
        -*)
            echo "Error: Unknown option $1"
            echo "Use --help for usage information"
            exit 1
            ;;
        *)
            # Positional arguments
            if [[ -z "$BIDS_ROOT" ]]; then
                BIDS_ROOT="$1"
            elif [[ -z "$SUBJECT" ]]; then
                SUBJECT="$1"
            else
                echo "Error: Too many positional arguments"
                echo "Use --help for usage information"
                exit 1
            fi
            shift
            ;;
    esac
done

# Check if minimum required arguments are provided
if [[ -z "$BIDS_ROOT" || -z "$SUBJECT" ]]; then
    echo "Error: BIDS_root and subject are required."
    echo "Use --help for usage information"
    exit 1
fi

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common_functions.sh"

COMMAND_LINE="$(build_cmdline_string "$0" "${ORIGINAL_ARGS[@]}")"
SESSION_CONTEXT="${SESSION:-all-sessions}"
init_pipeline_logging "$BIDS_ROOT" "$SUBJECT" "func_pipeline" "$SESSION_CONTEXT" "$COMMAND_LINE" || exit 1
log_pipeline_run_start

finalize_func_log() {
    local exit_code=$?
    if [[ $exit_code -eq 0 ]]; then
        log_pipeline_run_end "success"
    else
        log_pipeline_run_end "failure(exit_code=${exit_code})"
    fi
}
trap finalize_func_log EXIT

exec > >(tee -a "$LOGFILE") 2>&1

echo "=========================================="
echo "BIDS Functional Processing Pipeline"
echo "=========================================="
echo "BIDS Root: ${BIDS_ROOT}"
echo "Subject: ${SUBJECT}"
echo "Session: ${SESSION:-"All available sessions"}"
echo "Log file: ${LOGFILE}"
echo "=========================================="

############################################################################
############################     VALIDATION     ##########################
############################################################################

echo "Validating inputs and discovering data..."

# Validate subject format
if [[ ! "$SUBJECT" =~ ^sub- ]]; then
    echo "Error: Subject must start with 'sub-' (e.g., sub-01)"
    exit 1
fi

# Validate session format if provided
if [[ -n "$SESSION" && ! "$SESSION" =~ ^ses- ]]; then
    echo "Error: Session must start with 'ses-' (e.g., ses-02)"
    exit 1
fi


# Check if subject directory exists
SUBJECT_DIR="${BIDS_ROOT}/${SUBJECT}"
if [[ ! -d "$SUBJECT_DIR" ]]; then
    echo "Error: Subject directory ${SUBJECT_DIR} does not exist."
    exit 1
fi

echo "Subject directory found: ${SUBJECT_DIR}"

# Discover sessions to process
if [[ -n "$SESSION" ]]; then
    # Process specific session
    SESSIONS=("$SESSION")
    echo "Processing specific session: ${SESSION}"
else
    # Discover all sessions
    SESSIONS=($(find "$SUBJECT_DIR" -maxdepth 1 -name "ses-*" -type d | xargs -n 1 basename | sort))
    if [[ ${#SESSIONS[@]} -eq 0 ]]; then
        echo "Error: No sessions found in ${SUBJECT_DIR}"
        exit 1
    fi
    echo "Found ${#SESSIONS[@]} sessions to process: ${SESSIONS[*]}"
fi

echo "=========================================="

############################################################################
############################     PROCESSING     ##########################
############################################################################

# Process each session
session_count=0
total_sessions=${#SESSIONS[@]}
failed_sessions=()
successful_sessions=0

for session in "${SESSIONS[@]}"; do
    session_count=$((session_count+1))
    echo ""
    echo "Processing session ${session_count}/${total_sessions}: ${session}"
    echo "----------------------------------------"
    
    if process_session "$BIDS_ROOT" "$SUBJECT" "$session"; then
        echo "Successfully completed processing for ${session}"
        successful_sessions=$((successful_sessions+1))
    else
        echo "Error occurred while processing ${session}; continuing to next session"
        failed_sessions+=("$session")
    fi
done

echo ""
echo "=========================================="
if [[ ${#failed_sessions[@]} -eq 0 ]]; then
    echo "ALL PROCESSING COMPLETED SUCCESSFULLY!"
else
    echo "PROCESSING COMPLETED WITH WARNINGS"
fi
echo "=========================================="
echo "Processed ${total_sessions} session(s) for subject ${SUBJECT}"
echo "Successful sessions: ${successful_sessions}"
echo "Failed sessions: ${#failed_sessions[@]}"
if [[ ${#failed_sessions[@]} -gt 0 ]]; then
    echo "Failed session IDs: ${failed_sessions[*]}"
fi

echo "Results saved in: ${BIDS_ROOT}/derivatives/preproc/${SUBJECT}/"
echo "=========================================="

if [[ ${#failed_sessions[@]} -gt 0 ]]; then
    exit 1
fi

exit 0