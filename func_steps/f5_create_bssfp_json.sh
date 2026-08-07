#!/bin/bash

# f5_create_bssfp_json.sh
# Usage:
#   f5_create_bssfp_json.sh <PREPROC_DIR> <SUBJECT> <SESSION> <FSL_CONTAINER> <MATLAB_CONTAINER> <MATLAB_SPM_HOST> <src_file_1> [src_file_2 ...]

PREPROC_DIR="$1"
SUBJECT="$2"
SESSION="$3"
FSL_CONTAINER="$4"
MATLAB_CONTAINER="$5"
MATLAB_SPM_HOST="$6"
shift 6

if [[ $# -eq 0 ]]; then
    echo "  No bSSFP source files provided, skipping JSON sidecar creation"
    exit 0
fi

# Derive version/name strings from container filenames
fsl_container_name=$(basename "$FSL_CONTAINER")
# grep can return non-zero if pattern is not present; do not fail JSON creation for that
fsl_version=$(echo "$fsl_container_name" | grep -oP '(?<=fsl_)[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?(?=_)' || true)
[[ -z "$fsl_version" ]] && fsl_version="unknown"

matlab_container_name=$(basename "$MATLAB_CONTAINER")

json_created=0
for src_file in "$@"; do
    src_basename=$(basename "$src_file")

    if [[ "$src_basename" =~ run-([0-9]+) ]]; then
        run_num="${BASH_REMATCH[1]}"
    else
        echo "    Warning: Could not extract run number from ${src_basename}, skipping"
        continue
    fi

    # Point to the final output file: motion-corr
    final_file="${PREPROC_DIR}/${SUBJECT}_${SESSION}_task-prf_run-${run_num}_acq-bssfp_desc-dummyRemoval-motionCorr.nii"
    json_file="${PREPROC_DIR}/${SUBJECT}_${SESSION}_task-prf_run-${run_num}_acq-bssfp_desc-dummyRemoval-motionCorr.json"

    if [[ ! -f "$final_file" ]]; then
        echo "    Warning: Expected final file not found: $(basename "$final_file"), skipping JSON"
        continue
    fi

    if [[ -f "$json_file" ]]; then
        echo "    JSON sidecar already exists, skipping: $(basename "$json_file")"
        continue
    fi

    cat > "$json_file" << JSONEOF
{
    "Sources": ["bids::${SUBJECT}/${SESSION}/func/${src_basename}"],
    "Description": "bSSFP run after dummy volume removal and motion correction. No further preprocessing was applied to this sequence.",
    "SkullStripped": false,
    "ProcessingDate": "$(date -Iseconds)",
    "ProcessingSteps": [
        {
            "Name": "DummyVolumeRemoval",
            "Description": "Removal of the first 3 dummy volumes to allow magnetization to reach steady state",
            "Software": "FSL",
            "SoftwareVersion": "${fsl_version}",
            "ContainerImage": "${fsl_container_name}",
            "Command": "fslroi",
            "VolumesRemoved": 3,
            "VolumesRemovedPosition": "beginning"
        },
        {
            "Name": "MotionCorrection",
            "Description": "SPM12 rigid-body realignment to correct for head motion. Each run realigned independently to its own mean volume.",
            "Software": "SPM12",
            "SoftwarePath": "${MATLAB_SPM_HOST}",
            "MATLABVersion": "R2024b",
            "ContainerImage": "${matlab_container_name}",
            "Function": "f3_realign_SPM"
        }
    ],
    "GeneratedBy": {
        "Name": "func_pipeline",
        "Version": "1.0.0",
        "Description": "BIDS-compatible functional processing pipeline"
    }
}
JSONEOF

    echo "    Created: $(basename "$json_file")"
    json_created=$((json_created+1))
done

echo "  Created ${json_created} bSSFP JSON sidecar(s)"
