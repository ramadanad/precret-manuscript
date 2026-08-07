#!/bin/bash

# f3_run_mo-co.sh
# Purpose: Run motion correction on functional data using SPM
# Script beign used: f3_realign_SPM.m
# Usage:
#   f3_run_mo-co.sh <bids_root> <subject> <session> <preproc_dir> <script_dir>

set -e

if [[ $# -ne 5 ]]; then
    echo "Error: Usage: $0 <bids_root> <subject> <session> <preproc_dir> <script_dir>"
    exit 1
fi

bids_root="$1"
subject="$2"
session="$3"
PREPROC_DIR="$4"
SCRIPT_DIR="$5"

source "${SCRIPT_DIR}/common_functions.sh"

echo "===================================================================================="
echo "  Motion correction"
echo "===================================================================================="

declare -a sequences
mapfile -t _found_dummy < <(find "${PREPROC_DIR}" -maxdepth 1 -type f -name "*${session}*_desc-dummyRemoval.nii.gz" | sort)
for dummy_file in "${_found_dummy[@]}"; do
    filename=$(basename "$dummy_file")
    if [[ "$filename" == *"_acq-epi_"* || "$filename" == *"_epi_"* ]]; then
        sequences+=("epi")
    elif [[ "$filename" == *"_acq-bssfp_"* || "$filename" == *"_bssfp_"* ]]; then
        sequences+=("bssfp")
    fi
done

if [[ ${#sequences[@]} -eq 0 ]]; then
    echo "  Warning: No sequences found for motion correction"
    exit 0
fi

declare -A _seen_sequences
declare -a _unique_sequences
for seq in "${sequences[@]}"; do
    [[ -z "$seq" ]] && continue
    if [[ -z "${_seen_sequences[$seq]}" ]]; then
        _seen_sequences["$seq"]=1
        _unique_sequences+=("$seq")
    fi
done
sequences=("${_unique_sequences[@]}")

declare -a dummy_inputs
mapfile -t dummy_inputs < <(find "${PREPROC_DIR}" -maxdepth 1 -type f -name "*${session}*_desc-dummyRemoval.nii.gz" | sort)

if [[ ${#dummy_inputs[@]} -eq 0 ]]; then
    echo "  Error: No dummy-removal outputs found for motion correction"
    exit 1
fi

require_files_exist_from_array dummy_inputs "dummy-removal input" || exit 1

declare -A SEQUENCE_FILES
for sequence in "${sequences[@]}"; do
    for f in "${dummy_inputs[@]}"; do
        filename=$(basename "$f")
        if [[ "$filename" == *"_acq-${sequence}_"* || "$filename" == *"_${sequence}_"* ]]; then
            SEQUENCE_FILES["$sequence"]+="$f "
        fi
    done
done

mc_processed=0
mc_skipped=0
motion_outputs=()

for sequence in "${!SEQUENCE_FILES[@]}"; do
    echo "    Motion correction for ${sequence} files..."

    rev_motion_output="${PREPROC_DIR}/${subject}_${session}_dir-PA_epi_desc-dummyRemoval-motionCorr.nii"
    
    # Check if motion correction output already exists
    if ls "${PREPROC_DIR}"/*${session}*${sequence}*_desc-dummyRemoval-motionCorr.nii 1> /dev/null 2>&1 || \
       ls "${PREPROC_DIR}"/*${session}*${sequence}*plotMotionParams.pdf 1> /dev/null 2>&1; then
        # For EPI, keep processing if reverse-PE motion output is still missing.
        if [[ "$sequence" != "epi" || -f "$rev_motion_output" ]]; then
            echo "      Motion correction output already exists for ${sequence}, skipping."
            mc_skipped=$((mc_skipped+1))
            while IFS= read -r existing_file; do
                motion_outputs+=("$existing_file")
            done < <(find "${PREPROC_DIR}" -maxdepth 1 -type f -name "*${session}*${sequence}*_desc-dummyRemoval-motionCorr.nii" | sort)
            continue
        else
            echo "      Forward EPI outputs exist but reverse-PE motion file is missing; rerunning EPI motion correction."
        fi
    fi

    # Create changedheader copies for SPM motion correction (SPM modifies headers)
    echo "      Creating changedheader copies for ${sequence}..."
    read -ra files <<< "${SEQUENCE_FILES[$sequence]}"
    for func_file in "${files[@]}"; do
        filename=$(basename "$func_file")
        
        if [[ "$filename" =~ run-([0-9]+) ]]; then
            run_num="${BASH_REMATCH[1]}"
        elif [[ "$filename" == *dir-PA* ]]; then
            run_num="NA"
        else
            continue
        fi
        
        dummy_file="$func_file"
        changedheader_file="${PREPROC_DIR}/$(basename "$dummy_file" .nii.gz)_changedheader.nii.gz"
        
        if [[ ! -f "$changedheader_file" && -f "$dummy_file" ]]; then
            cp "$dummy_file" "$changedheader_file"
            echo "        Created changedheader copy: $(basename $changedheader_file)"
        fi
    done

    # Decompress changedheader files for SPM processing (SPM works with .nii files)
    echo "      Decompressing changedheader files for ${sequence}..."
    decompressed_count=0
    for changedheader_file in "${PREPROC_DIR}"/*${sequence}*changedheader.nii.gz; do
        if [[ -f "$changedheader_file" ]]; then
            fname=$(basename "$changedheader_file")
            uncompressed_file="${PREPROC_DIR}/${fname%.gz}"
            
            if [[ ! -f "$uncompressed_file" ]]; then
                gunzip -c "$changedheader_file" > "$uncompressed_file"
                decompressed_count=$((decompressed_count+1))
            fi
        fi
    done
    echo "      Decompressed ${decompressed_count} changedheader file(s)"
    
    echo "      Running SPM motion correction for ${sequence} sequence..."
    
    # Run SPM motion correction on changedheader files in PREPROC_DIR
    run_matlab_container "$bids_root" "$SCRIPT_DIR" "$PREPROC_DIR" "f3_realign_SPM('${sequence}',${subject: -1},${session: -1})" || {
        echo "      ERROR: MATLAB motion correction failed or timed out"
        exit 1
    }
    
    # Verify motion correction completed successfully
    if ls "${PREPROC_DIR}"/rs_*${session}*${sequence}*changedheader*.nii* 1> /dev/null 2>&1; then
        echo "      Motion correction output files detected"
    else
        echo "      Warning: No motion correction output files (rs_*) found"
    fi
    
    # Rename motion corrected files to remove changedheader suffix
    # SPM creates rs_* prefixed files - rename them to *_motion-corr.nii
    for realigned_file in "${PREPROC_DIR}"/rs_*${session}*${sequence}*changedheader.nii; do
        if [[ -f "$realigned_file" ]]; then
            filename=$(basename "$realigned_file")
            
            # Extract run number from filename
            if [[ "$filename" =~ run-([0-9]+) ]]; then
                run_num="${BASH_REMATCH[1]}"
                output_filename="${subject}_${session}_task-prf_run-${run_num}_acq-${sequence}_desc-dummyRemoval-motionCorr.nii"
            elif [[ "$sequence" == "epi" && "$filename" == *"dir-PA_epi_desc-dummyRemoval_changedheader.nii" ]]; then
                output_filename="${subject}_${session}_dir-PA_epi_desc-dummyRemoval-motionCorr.nii"
            else
                echo "      Warning: Could not extract run number from $filename, skipping"
                continue
            fi

            output_file="${PREPROC_DIR}/${output_filename}"
            
            if [[ ! -f "$output_file" ]]; then
                mv "$realigned_file" "$output_file"
                echo "      Renamed motion-corrected file: ${output_filename}"
            fi
            motion_outputs+=("$output_file")
        fi
    done
    
    echo "      Motion correction completed for ${sequence}"
    mc_processed=$((mc_processed+1))
done

echo "  Motion correction completed: ${mc_processed} processed, ${mc_skipped} skipped"

if [[ -z "${motion_outputs[*]}" ]]; then
    while IFS= read -r existing_file; do
        motion_outputs+=("$existing_file")
    done < <(find "${PREPROC_DIR}" -maxdepth 1 -type f -name "*${session}*_desc-dummyRemoval-motionCorr.nii" | sort)
fi

exit 0
