#!/bin/bash

set -e

if [[ $# -ne 13 ]]; then
    echo "Usage: $0 <json_file> <tmp_json_file> <work_dir> <input_file> <fsl_version> <fsl_container_name> <matlab_spm_host> <matlab_container_name> <topup_fout> <topup_out> <run_index> <tro> <run_label>"
    exit 1
fi

json_file="$1"
tmp_json_file="$2"
work_dir="$3"
input_file="$4"
fsl_version="$5"
fsl_container_name="$6"
matlab_spm_host="$7"
matlab_container_name="$8"
topup_fout="$9"
topup_out="${10}"
run_index="${11}"
tro="${12}"
run_label="${13}"

if [[ -f "$json_file" ]]; then
    echo "JSON sidecar already exists, skipping: $(basename "$json_file")"
    exit 0
fi

if cat > "$tmp_json_file" << EOF
{
    "Sources": ["${work_dir}/${input_file}"],
    "Description": "EPI run after dummy volume removal, motion correction, and topup distortion correction. This is the final preprocessed EPI output.",
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
            "SoftwarePath": "${matlab_spm_host}",
            "MATLABVersion": "R2024b",
            "ContainerImage": "${matlab_container_name}",
            "Function": "f3_realign_SPM"
        },
        {
            "Name": "DistortionCorrection",
            "Description": "Susceptibility-induced geometric distortion correction using FSL topup field estimation and applytopup. Phase-encoding direction: A-P (runs) and P-A (reversed PE).",
            "Software": "FSL",
            "SoftwareVersion": "${fsl_version}",
            "ContainerImage": "${fsl_container_name}",
            "TopupCommand": "topup",
            "TopupConfig": "b02b0.cnf",
            "TopupFieldmap": "${topup_fout}.nii.gz",
            "TopupFieldcoef": "${topup_out}_fieldcoef.nii.gz",
            "ApplytopupCommand": "applytopup",
            "ApplytopupMethod": "jac",
            "RunIndex": ${run_index},
            "ReadoutTime": ${tro},
            "PhaseEncodingDirection": "A-P"
        }
    ],
    "GeneratedBy": {
        "Name": "func_pipeline / fu_topup",
        "Version": "1.0.0",
        "Description": "BIDS-compatible functional processing pipeline"
    }
}
EOF
then
    if [[ -s "$tmp_json_file" ]]; then
        mv "$tmp_json_file" "$json_file"
        echo "    Created: $(basename "$json_file")"
    else
        echo "    Warning: JSON sidecar file is empty for run ${run_label}; skipping"
        rm -f "$tmp_json_file"
    fi
else
    echo "    Warning: Failed to write JSON sidecar for run ${run_label}; continuing"
    rm -f "$tmp_json_file"
fi
