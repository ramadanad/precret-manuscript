#!/bin/bash

# samsrf_pipeline.sh - Run SamSrf steps in sequence
# Usage: ./samsrf_pipeline.sh <dataDir> <subject>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common_functions.sh"

ORIGINAL_ARGS=("$@")

dataDir="${1:-}"
subject="${2:-}"

if [[ -z "$dataDir" || -z "$subject" ]]; then
	echo "Usage: $0 <dataDir> <subject>"
	exit 1
fi

COMMAND_LINE="$(build_cmdline_string "$0" "${ORIGINAL_ARGS[@]}")"
init_pipeline_logging "$dataDir" "$subject" "samsrf_pipeline" "all-sessions" "$COMMAND_LINE" || exit 1
log_pipeline_run_start

finalize_samsrf_log() {
	local exit_code=$?
	if [[ $exit_code -eq 0 ]]; then
		log_pipeline_run_end "success"
	else
		log_pipeline_run_end "failure(exit_code=${exit_code})"
	fi
}
trap finalize_samsrf_log EXIT

exec > >(tee -a "$LOGFILE") 2>&1

echo "========================================"
echo "SamSrf Pipeline"
echo "========================================"
echo "Data dir: $dataDir"
echo "Subject: $subject"
echo "Log file: $LOGFILE"

echo ""
echo "Making sure everything exists where it should be..."

SAMSRF_ROOT="$dataDir/derivatives/samsrf"
SAMSRF_SUBJ_DIR="$SAMSRF_ROOT/$subject"
SAMSRF_APERTURE_DIR="$SAMSRF_ROOT/aperture"
MISC_DIR="$SCRIPT_DIR/misc"

# Step 0 preflight: create the SamSrf directories and copy shared MATLAB assets
# only when they are missing. This keeps the pipeline idempotent and avoids
# overwriting files that may already have been prepared manually.
mkdir -p "$SAMSRF_SUBJ_DIR"
mkdir -p "$SAMSRF_APERTURE_DIR"

if [[ ! -f "$SAMSRF_SUBJ_DIR/fit_2d_Gaussian_pRF.m" ]]; then
	echo "Copying fit_2d_Gaussian_pRF.m into $SAMSRF_SUBJ_DIR"
	cp "$MISC_DIR/fit_2d_Gaussian_pRF.m" "$SAMSRF_SUBJ_DIR/"
fi

if [[ ! -f "$SAMSRF_APERTURE_DIR/aperture.mat" ]]; then
	echo "Copying aperture.mat into $SAMSRF_APERTURE_DIR"
	cp "$MISC_DIR/aperture.mat" "$SAMSRF_APERTURE_DIR/"
fi


echo ""
echo "Step s0: run_occ_aprtr_mgh2srf"
bash "$SCRIPT_DIR/samsrf_steps/s0_run_occ_mgh2srf.sh" "$dataDir" "$subject"

echo ""
echo "Step s1: run_fit_prf"
bash "$SCRIPT_DIR/samsrf_steps/s1_run_fit_prf.sh" "$dataDir" "$subject"

echo ""
echo "SamSrf pipeline completed successfully."
