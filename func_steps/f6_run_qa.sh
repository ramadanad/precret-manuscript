#!/bin/bash

# f6_run_qa.sh - Compute QA metrics (tSNR, kurtosis, skewness) for functional data
# Usage:
#   f6_run_qa.sh <preproc_dir> <qa_output_dir>

set -e

PREPROC_DIR="$1"
QA_OUTPUT_DIR="$2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QA_SCRIPT="${SCRIPT_DIR}/f6_calculate_qa.py"

if [[ -z "$PREPROC_DIR" || -z "$QA_OUTPUT_DIR" ]]; then
    echo "  Error: Missing required arguments"
    echo "  Usage: $0 <preproc_dir> <qa_output_dir>"
    exit 1
fi

# Create output subdirectories
TSNR_DIR="${QA_OUTPUT_DIR}/tsnr"
KURT_DIR="${QA_OUTPUT_DIR}/kurtosis"
SKEW_DIR="${QA_OUTPUT_DIR}/skewness"
mkdir -p "$TSNR_DIR" "$KURT_DIR" "$SKEW_DIR"

echo "    Computing QA metrics..."

CONDA_ENV_NAME="prf_pipeline"
CONDA_EXE="$HOME/miniforge3/bin/conda"
if [[ -x "$CONDA_EXE" ]]; then
    echo "    Using conda environment: ${CONDA_ENV_NAME}"
    PYTHON_CMD="$CONDA_EXE run -n ${CONDA_ENV_NAME} python"
elif command -v conda > /dev/null 2>&1; then
    echo "    Using conda environment: ${CONDA_ENV_NAME}"
    PYTHON_CMD="conda run -n ${CONDA_ENV_NAME} python"
else
    echo "    Warning: conda not found, using system Python"
    PYTHON_CMD="python3"
fi

export MPLBACKEND=Agg

if [[ ! -f "$QA_SCRIPT" ]]; then
    echo "    Warning: QA metrics script not found at $QA_SCRIPT"
    echo "    Skipping QA metrics"
    exit 0
fi

QA_PATTERNS=("*_desc-dummyRemoval.nii.gz" "*_desc-dummyRemoval-motionCorr.nii")
QA_PATTERN_ARGS=()
for p in "${QA_PATTERNS[@]}"; do
    QA_PATTERN_ARGS+=("--file-pattern" "$p")
done

echo "    Computing tSNR..."
$PYTHON_CMD "$QA_SCRIPT" "$PREPROC_DIR" tsnr --output-type nifti --output-dir "$TSNR_DIR" "${QA_PATTERN_ARGS[@]}" || echo "    Warning: tSNR calculation failed, continuing..."

echo "    Computing kurtosis..."
$PYTHON_CMD "$QA_SCRIPT" "$PREPROC_DIR" kurtosis --output-type nifti --output-dir "$KURT_DIR" "${QA_PATTERN_ARGS[@]}" || echo "    Warning: Kurtosis calculation failed, continuing..."

echo "    Computing skewness..."
$PYTHON_CMD "$QA_SCRIPT" "$PREPROC_DIR" skewness --output-type nifti --output-dir "$SKEW_DIR" "${QA_PATTERN_ARGS[@]}" || echo "    Warning: Skewness calculation failed, continuing..."

echo "    QA metrics calculations completed"

exit 0