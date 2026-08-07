#!/usr/bin/env bash
# ================================================================
# Script: a5_benson14.sh
# Purpose: Run Neuropythy Benson14 retinotopy mapping on FreeSurfer output
# Usage: ./a5_benson14.sh <BIDS root> <subject>
# Example: ./a5_benson14.sh /path/to/bids sub-01
#
# Outputs: Benson14 retinotopy maps in subject's surf/ directory
# ================================================================

# Check if required arguments are provided
if [[ -z "$1" || -z "$2" ]]; then
    echo "Error: BIDS root and subject ID are required."
    echo "Usage: $0 <BIDS root> <subject>"
    exit 1
fi

BIDS_ROOT="$1"
SUBJECT="$2"

# Derived variables
SUBJECTS_DIR="${BIDS_ROOT}/derivatives/freesurfer"
CONDA_BIN="${CONDA_EXE:-$HOME/miniforge3/bin/conda}"
PYTHON_ENV_NAME="benson_atlas"
VERBOSE=1

# --------------------------
# 1) Ensure fsaverage exists
# --------------------------
FSAVERAGE_DIR="${SUBJECTS_DIR}/fsaverage"
if [ ! -d "${FSAVERAGE_DIR}" ]; then
    echo "Error: fsaverage not found in ${SUBJECTS_DIR}"
    echo "Please ensure FreeSurfer is properly installed and fsaverage is set up."
    exit 1
fi

# --------------------------
# 2) Determine subject directory path
# --------------------------
SUBJECT_DIR="${SUBJECTS_DIR}/${SUBJECT}"

# --------------------------
# 3) Check that subject FreeSurfer output exists
# --------------------------
if [ ! -d "${SUBJECT_DIR}" ]; then
    echo "Error: FreeSurfer subject directory not found: ${SUBJECT_DIR}"
    echo "Please run recon-all first."
    exit 1
fi

if [ ! -f "${SUBJECT_DIR}/surf/lh.pial" ] || [ ! -f "${SUBJECT_DIR}/surf/rh.pial" ]; then
    echo "Error: FreeSurfer surfaces not found. Recon-all may not have completed successfully."
    exit 1
fi

# --------------------------
# 4) Validate Python environment
# --------------------------
if [[ ! -x "${CONDA_BIN}" ]]; then
    echo "Error: Conda executable not found at ${CONDA_BIN}"
    echo "Set CONDA_EXE or install Miniforge/Conda at ~/miniforge3/bin/conda"
    exit 1
fi

if ! "${CONDA_BIN}" run -n "${PYTHON_ENV_NAME}" python -c "import neuropythy" >/dev/null 2>&1; then
    echo "Error: Neuropythy is not available in conda environment '${PYTHON_ENV_NAME}'."
    echo "Please install it in that environment."
    exit 1
fi

# --------------------------
# 5) Run Neuropythy Benson14
# --------------------------
echo "========================================"
echo "Running Benson14 Retinotopy Mapping"
echo "========================================"
echo "Subject directory: ${SUBJECT_DIR}"
echo ""

export SUBJECTS_DIR="${SUBJECTS_DIR}"

# Run neuropythy directly on the subject directory
if "${CONDA_BIN}" run -n "${PYTHON_ENV_NAME}" python -m neuropythy benson14_retinotopy "${SUBJECT_DIR}" ${VERBOSE:+-v}; then
    echo ""
    echo "========================================"
    echo "Benson14 Mapping Completed Successfully"
    echo "========================================"
    echo "Outputs saved in: ${SUBJECT_DIR}/surf/"
    echo ""
    
    # --------------------------
    # 6) Convert Benson14 to ROI using benson2roi function
    # --------------------------
    echo "========================================"
    echo "Converting Benson14 to ROI"
    echo "========================================"
    
    BENSON2ROI="$(dirname "$0")/a5_benson2roi.py"
    
    if [[ ! -f "$BENSON2ROI" ]]; then
        echo "Warning: a5_benson2roi.py not found at ${BENSON2ROI}"
        echo "Skipping ROI conversion but Benson14 maps are available."
        exit 0
    fi
    
    # Run benson2roi with subject parameters
    "${CONDA_BIN}" run -n "${PYTHON_ENV_NAME}" python "$BENSON2ROI" "${BIDS_ROOT}" "${SUBJECT}"
    
    if [[ $? -eq 0 ]]; then
        echo ""
        echo "========================================"
        echo "All Benson14 processing completed"
        echo "========================================"
        exit 0
    else
        echo ""
        echo "Warning: Benson14 mapping succeeded but ROI conversion failed."
        echo "Benson14 maps are still available in: ${SUBJECT_DIR}/surf/"
        exit 0
    fi
else
    echo ""
    echo "Error: Benson14 mapping failed."
    echo "Check the output above for details."
    exit 1
fi