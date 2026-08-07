#!/bin/bash

# famap_steps/fa0_run_rescale.sh - Run the FA rescaling step for all subjects in a BIDS dataset
# Usage: fa0_run_rescale.sh <bids_root>
set -e

BIDS_ROOT="${1:-}"

# activate conda environment
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


# run fa0_rescale.py for each subject
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for subject_dir in "$BIDS_ROOT"/sub-*/; do
    [[ -d "$subject_dir" ]] || continue
    subject=$(basename "$subject_dir")
    echo "Processing subject: $subject"
    $PYTHON_CMD "$SCRIPT_DIR/fa0_rescale.py" "$BIDS_ROOT" "$subject"
done