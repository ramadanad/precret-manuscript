#!/bin/bash

# f7_topup.sh - BIDS-compatible distortion correction script
# Usage: ./f7_topup.sh <BIDS_root> <subject> <session> <fsl_container>

############################################################################
############################     WHAT IS WHAT?    ##########################
############################################################################

BIDS_ROOT="$1"
SUBJECT="$2"
SESSION="$3"
FSL_CONTAINER="$4"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Validate inputs
if [[ -z "$1" || -z "$2" || -z "$3" || -z "$4" ]]; then
    echo "Error: Four arguments are required."
    echo "Usage: $0 <BIDS_root> <subject> <session> <fsl_container>"
    exit 1
fi

if [[ ! -f "$FSL_CONTAINER" ]]; then
    echo "Error: FSL container not found: $FSL_CONTAINER"
    exit 1
fi

# Define paths
DERIV_DIR="${BIDS_ROOT}/derivatives/preproc/${SUBJECT}/${SESSION}/func"
FMAP_DIR="${BIDS_ROOT}/${SUBJECT}/${SESSION}/fmap"
WORK_DIR="${DERIV_DIR}"

echo "=========================================="
echo "BIDS Distortion Correction"
echo "=========================================="
echo "Working directory: ${WORK_DIR}"
echo "=========================================="

cd "${WORK_DIR}"

# Skip entire distortion-correction workflow if run-02 final output already exists.
# This run acts as the sentinel indicating the session has already been corrected.
DISTCORR_SENTINEL="${SUBJECT}_${SESSION}_task-prf_run-02_acq-epi_desc-dummyRemoval-motionCorr-distortionCorr.nii.gz"

if [[ -f "${DISTCORR_SENTINEL}" ]]; then
    echo "Detected existing distortion-corrected run-02 output: ${DISTCORR_SENTINEL}"
    echo "Skipping distortion correction for this session."
    exit 0
fi

# Count number of EPI runs (motion-corrected files)
EPI_FILES=($(ls ${SUBJECT}_${SESSION}_task-prf_run-*_acq-epi_desc-dummyRemoval-motionCorr.nii 2>/dev/null || true))
NUM_RUNS=${#EPI_FILES[@]}

if [ $NUM_RUNS -eq 0 ]; then
    echo "Error: No motion-corrected EPI files found in ${WORK_DIR}"
    exit 1
fi

# Build BIDS prefix from detected EPI filename (drop run index)
FIRST_EPI_FILE=$(basename "${EPI_FILES[0]}")
if [[ "$FIRST_EPI_FILE" =~ ^(.+)_run-[0-9]+_([^_]+)_desc-dummyRemoval-motionCorr\.nii$ ]]; then
    BIDS_PREFIX="${BASH_REMATCH[1]}_${BASH_REMATCH[2]}_TopUp"
else
    # Fallback to a stable prefix if filename format is unexpected
    BIDS_PREFIX="${SUBJECT}_${SESSION}_TopUp"
fi

echo "Found ${NUM_RUNS} EPI runs for distortion correction"
echo "Using BIDS prefix: ${BIDS_PREFIX}"

# Define a timestamp function
timestamp() {
    date +"%T"
}

set -e

############################################################################
############################     acq_par.txt      ##########################
############################################################################

echo "Creating acquisition parameters file..."

ACQ_PAR="${BIDS_PREFIX}_acq-params.txt"

# Remove existing acq_par file
if [ -f "$ACQ_PAR" ]; then
    rm "$ACQ_PAR"
fi

# Set readout time for EPI
TRO=0.032056

# Phase encoding directions
I="0 1 0 $TRO"    # A-->P
J="0 -1 0 $TRO"   # P-->A

# Create acquisition parameters file
for ((i = 1; i <= NUM_RUNS; i++)); do
    echo "$I"
done >> "$ACQ_PAR"
for ((i = 1; i <= NUM_RUNS; i++)); do
    echo "$J"
done >> "$ACQ_PAR"

# Middle volume index for EPI
MID=93

############################################################################
#########################     MIDDLE VOLUMES      ##########################
############################################################################

echo "Creating middle volumes..."

# Extract middle volumes from each run
for ((i = 1; i <= NUM_RUNS; i++)); do
    printf -v padded_i "%02d" $i
    input_file="${SUBJECT}_${SESSION}_task-prf_run-${padded_i}_acq-epi_desc-dummyRemoval-motionCorr.nii"
    output_file="midvols_${SUBJECT}_${SESSION}_task-prf_run-${padded_i}_acq-epi_desc-dummyRemoval-motionCorr"
    
    if [ -f "$input_file" ]; then
        if [ -f "${output_file}.nii.gz" ]; then
            echo "Middle volume already exists, skipping: ${output_file}.nii.gz"
        else
            echo "Creating middle volume from $input_file"
            apptainer exec "$FSL_CONTAINER" fslroi "$input_file" "$output_file" $MID 1
            echo "Created middle volume: ${output_file}.nii.gz"
        fi
    else
        echo "Warning: $input_file not found"
    fi
done

# Find reverse phase encoding file
REV_PE_FILE=$(find ${WORK_DIR} -name "${SUBJECT}_${SESSION}_dir-PA_epi_desc-dummyRemoval-motionCorr.nii*" | head -1)

if [ -n "$REV_PE_FILE" ]; then
    rev_pe_output="midvols_${SUBJECT}_${SESSION}_dir-PA_epi_desc-dummyRemoval-motionCorr"
    if [ -f "${rev_pe_output}.nii.gz" ]; then
        echo "Reverse PE middle volume already exists, skipping: ${rev_pe_output}.nii.gz"
    else
        echo "Found reverse PE file: $REV_PE_FILE"
        echo "Creating reverse PE middle volume..."
        apptainer exec "$FSL_CONTAINER" fslroi "$REV_PE_FILE" "$rev_pe_output" 0 2
        echo "Created reverse PE middle volume: ${rev_pe_output}.nii.gz"
    fi
else
    echo "Warning: No reverse PE file found"
fi

echo "Merging middle volumes..."

# Collect input files for merging
INPUT_FILES=""
for ((i = 1; i <= NUM_RUNS; i++)); do
    printf -v padded_i "%02d" $i
    midvol_file="midvols_${SUBJECT}_${SESSION}_task-prf_run-${padded_i}_acq-epi_desc-dummyRemoval-motionCorr.nii.gz"
    if [ -f "$midvol_file" ]; then
        INPUT_FILES="$INPUT_FILES $midvol_file"
    fi
done


# Add reverse PE middle volume if it exists
rev_pe_midvol="midvols_${SUBJECT}_${SESSION}_dir-PA_epi_desc-dummyRemoval-motionCorr.nii.gz"
if [ -f "$rev_pe_midvol" ]; then
    INPUT_FILES="$INPUT_FILES $rev_pe_midvol"
fi

echo "Input files for merging: $INPUT_FILES"

# BIDS-named intermediate files for topup
MERGED="${BIDS_PREFIX}_merged-midvols"
TOPUP_OUT="${BIDS_PREFIX}_config"
TOPUP_FOUT="${BIDS_PREFIX}_fieldmap"
TOPUP_IOUT="${BIDS_PREFIX}_corrected"

# Merge volumes for topup
apptainer exec "$FSL_CONTAINER" fslmerge -t "$MERGED" $INPUT_FILES


############################################################################
##############################     TOPUP      ##############################
############################################################################

echo "Running topup on ${MERGED}.nii.gz. Topup started at $(timestamp)"

# Check if topup has already been run
if [ -f "${TOPUP_OUT}_fieldcoef.nii.gz" ] && [ -f "${TOPUP_OUT}_movpar.txt" ]; then
    echo "Topup output already exists, skipping topup calculation"
else
    echo "Running topup calculation..."
    apptainer exec \
        --bind $SCRIPT_DIR/../misc:/configs \
        "$FSL_CONTAINER" topup --imain="${MERGED}.nii.gz" \
        --datain="$ACQ_PAR" \
        --config=/configs/b02b0_1mm.cnf \
        --out="$TOPUP_OUT" \
        --fout="$TOPUP_FOUT" \
        --iout="$TOPUP_IOUT"
    
    echo "Topup completed at $(timestamp)"
fi

############################################################################
#############################     APPLYTOPUP      ##########################
############################################################################

echo "Running applytopup on all runs!"

# Derive version/name strings from container filenames (used in JSON sidecars)
_fsl_container_name=$(basename "$FSL_CONTAINER")
_fsl_version=$(echo "$_fsl_container_name" | grep -oP '(?<=fsl_)[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?(?=_)' || true)
[[ -z "$_fsl_version" ]] && _fsl_version="unknown"
_matlab_container_name=$(basename "${MATLAB_CONTAINER:-}")


for ((i = 1; i <= NUM_RUNS; i++)); do
    printf -v padded_i "%02d" $i
    input_file="${SUBJECT}_${SESSION}_task-prf_run-${padded_i}_acq-epi_desc-dummyRemoval-motionCorr.nii"
    output_file="${SUBJECT}_${SESSION}_task-prf_run-${padded_i}_acq-epi_desc-dummyRemoval-motionCorr-distortionCorr.nii.gz"

    if [ -f "$input_file" ]; then
        if [ -f "$output_file" ]; then
            echo "Output file $output_file already exists, skipping applytopup for run ${padded_i}"
        else
            echo "Running applytopup for run ${padded_i}..."
            apptainer exec "$FSL_CONTAINER" applytopup --imain="$input_file" \
                       --inindex=$i \
                       --method=jac \
                       --datain="$ACQ_PAR" \
                       --topup="$TOPUP_OUT" \
                       --out="$output_file"
            
            echo "Applytopup completed for run ${padded_i}"
        fi
        
        # Create detailed JSON sidecar for distortion-corrected file
        json_file="${output_file%.nii.gz}.json"
        tmp_json_file="${json_file}.tmp"
        bash "${SCRIPT_DIR}/f7_create_epi_json.sh" \
            "$json_file" \
            "$tmp_json_file" \
            "$WORK_DIR" \
            "$input_file" \
            "${_fsl_version}" \
            "${_fsl_container_name}" \
            "${MATLAB_SPM_HOST:-}" \
            "${_matlab_container_name}" \
            "$TOPUP_FOUT" \
            "$TOPUP_OUT" \
            "$i" \
            "$TRO" \
            "$padded_i"
    else
        echo "Warning: Input file $input_file not found"
    fi
done

# Clean up temporary files
echo "Cleaning up temporary files..."

# Remove temporary middle-volume files
rm -f midvols_${SUBJECT}_${SESSION}_*.nii.gz

# Archive TOPUP interim files
INTERIM_DIR="${WORK_DIR}/distortion-corr_interim"
mkdir -p "$INTERIM_DIR"

# Move files corresponding to the TOPUP interim naming table
INTERIM_PATTERNS=(
    "$ACQ_PAR"
    "${MERGED}.nii.gz"
    "${MERGED}.topup_log"
    "${TOPUP_OUT}*"
    "${TOPUP_FOUT}*"
    "${TOPUP_IOUT}*"
)

for pattern in "${INTERIM_PATTERNS[@]}"; do
    for file in $pattern; do
        if [[ -e "$file" ]]; then
            mv "$file" "$INTERIM_DIR/"
        fi
    done
done

echo "Distortion correction completed successfully!"
echo "TOPUP interim files moved to: ${INTERIM_DIR}"
echo "Results saved in: ${WORK_DIR}"
