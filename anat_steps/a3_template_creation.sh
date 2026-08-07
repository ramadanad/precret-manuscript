#!/bin/bash

# a3_template_creation.sh - BIDS anatomical processing pipeline - Step 3: Template Creation
# Usage: a3_template_creation.sh <BIDS root directory> <subject ID>
# This script creates anatomical templates across sessions.
# Adapted from
# https://github.com/Kriaese/manuscript-zoomprf/blob/main/toolboxes/falkluesebrink/pRF/pRF_pipeline_nonlinear_BBR_01.sh

set -euo pipefail

# Source common functions and variables
source "$(dirname "$0")/../common_functions.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

build_sources_json() {
    local file_array_name="$1"
    local -n file_array_ref="$file_array_name"

    local sources_json
    sources_json=$(printf '"bids::%s/%s/anat/%s",' "$SUBJECT" "${SESSION_IDS[0]}" "$(basename "${file_array_ref[0]}")")
    local i
    for i in "${!SESSION_IDS[@]}"; do
        if [[ "$i" -eq 0 ]]; then
            continue
        fi
        sources_json+=$(printf '"bids::%s/%s/anat/%s",' "$SUBJECT" "${SESSION_IDS[$i]}" "$(basename "${file_array_ref[$i]}")")
    done

    echo "${sources_json%,}"
}

# Parse arguments
BIDS_ROOT="$1"
SUBJECT="$2"
ARGS=("$@")

# Check if required arguments are provided
if [[ -z "${BIDS_ROOT:-}" || -z "${SUBJECT:-}" ]]; then
    echo "Error: Both BIDS root directory and subject ID are required."
    echo "Usage: $0 <BIDS root directory> <subject ID>"
    echo "Example: $0 /path/to/bids sub-01"
    exit 1
fi

if [[ -z "${LOGFILE:-}" ]]; then
    COMMAND_LINE="$(build_cmdline_string "$0" "${ARGS[@]}")"
    init_pipeline_logging "$BIDS_ROOT" "$SUBJECT" "anat_pipeline" "all-sessions" "$COMMAND_LINE" || exit 1
fi

exec > >(tee -a "$LOGFILE") 2>&1

# ANTs processing parameters
ANTS_THREADS=64

# Check required containers
if [[ ! -f "$ANTS_CONTAINER" ]]; then
    echo "Error: ANTs container not found at $ANTS_CONTAINER"
    exit 1
fi
if [[ ! -f "$FREESURFER_CONTAINER" ]]; then
    echo "Error: FreeSurfer container not found at $FREESURFER_CONTAINER"
    exit 1
fi

echo "========================================"
echo "BIDS Anatomical Processing Pipeline"
echo "Step 3: Template Creation"
echo "========================================"
echo "BIDS root: $BIDS_ROOT"
echo "Subject: $SUBJECT"
echo "Processing started: $(date)"
echo "ANTs threads: $ANTS_THREADS"
echo "========================================"

# Set up template output directory and canonical final outputs.
TEMPLATE_DIR="$BIDS_ROOT/derivatives/preproc/$SUBJECT/ses-all/anat"
mkdir -p "$TEMPLATE_DIR"

FINAL_MASKED_TEMPLATE="$TEMPLATE_DIR/${SUBJECT}_ses-all_T1w_desc-biasCorrected-template-skullStripped.nii.gz"
final_template_json="${FINAL_MASKED_TEMPLATE%.nii.gz}.json"

# If canonical final output and sidecar already exist, skip this entire step.
if [[ -f "$FINAL_MASKED_TEMPLATE" && -f "$final_template_json" ]]; then
    echo "Final canonical template and JSON already exist. Skipping Step 3 entirely."
    echo "  - $(basename "$FINAL_MASKED_TEMPLATE")"
    echo "  - $(basename "$final_template_json")"
    exit 0
fi

# Find all sessions for this subject
SUBJECT_DIR="$BIDS_ROOT/$SUBJECT"
if [[ ! -d "$SUBJECT_DIR" ]]; then
    echo "Error: Subject directory '$SUBJECT_DIR' does not exist."
    exit 1
fi

# Find session directories
mapfile -t SESSIONS < <(find "$SUBJECT_DIR" -maxdepth 1 -type d -name "ses-*" | sort)

if [[ ${#SESSIONS[@]} -eq 0 ]]; then
    echo "Error: No session directories found for $SUBJECT"
    echo "Template creation requires multiple sessions."
    exit 1
fi

if [[ ${#SESSIONS[@]} -lt 2 ]]; then
    echo "Warning: Only ${#SESSIONS[@]} session found for $SUBJECT"
    echo "Template creation works best with multiple sessions, but continuing..."
fi

echo "Found ${#SESSIONS[@]} session(s) for $SUBJECT:"
for session_dir in "${SESSIONS[@]}"; do
    echo "  - $(basename "$session_dir")"
done
echo ""

# Check if required input files exist for all sessions
# Keep arrays index-aligned across session/masked/unmasked/transform/warped stages.
echo "Checking input files for all sessions..."
SESSION_IDS=()
MASKED_FILES=()
UNMASKED_FILES=()
TRANSFORM_FILES=()
WARPED_FILES=()
missing_files=false

for session_dir in "${SESSIONS[@]}"; do
    session_id=$(basename "$session_dir")
    session_derivatives_dir="$BIDS_ROOT/derivatives/preproc/$SUBJECT/$session_id/anat"
    bids_output_prefix="${SUBJECT}_${session_id}"

    masked_file="$session_derivatives_dir/${bids_output_prefix}_T1w_desc-biasCorrected-skullStripped.nii"
    unmasked_file="$session_derivatives_dir/${bids_output_prefix}_T1w_desc-biasCorrected.nii"

    if [[ ! -f "$masked_file" ]]; then
        echo "Error: Missing masked file for $session_id: $masked_file"
        missing_files=true
    else
        echo "Found masked file for $session_id: $(basename "$masked_file")"
    fi

    if [[ ! -f "$unmasked_file" ]]; then
        echo "Error: Missing unmasked file for $session_id: $unmasked_file"
        missing_files=true
    else
        echo "Found unmasked file for $session_id: $(basename "$unmasked_file")"
    fi

    SESSION_IDS+=("$session_id")
    MASKED_FILES+=("$masked_file")
    UNMASKED_FILES+=("$unmasked_file")
    TRANSFORM_FILES+=("$TEMPLATE_DIR/${SUBJECT}_${session_id}_from-biasCorrected-skullStripped_to-biasCorrected-skullStripped-template_xfm.mat")
    WARPED_FILES+=("$TEMPLATE_DIR/${SUBJECT}_${session_id}_T1w_space-template_desc-biasCorrected.nii.gz")
done

if [[ "$missing_files" == "true" ]]; then
    echo "Error: Missing required input files. Please run bias field correction and skull stripping steps first."
    exit 1
fi

echo ""
echo "All required input files found. Proceeding with template creation..."

# Define output files
MASKED_SKULL_TEMPLATE="$TEMPLATE_DIR/${SUBJECT}_ses-all_T1w_desc-biasCorrected-skullStripped-template.nii.gz"
UNMASKED_TEMPLATE="$TEMPLATE_DIR/${SUBJECT}_ses-all_T1w_desc-biasCorrected-template.nii.gz"
# Canonical template consumed downstream by recon-all
WARPED_LIST="$TEMPLATE_DIR/${SUBJECT}_ses-all_desc-biasCorrected-warped_paths.txt"

# Step 3.0: Create unbiased template of all masked structural data across sessions
# This stage yields affines from each skull-stripped session image to masked template space.
echo ""
echo "***************************************"
echo "* Step 3.0: Create masked skull-stripped template across sessions"
echo "***************************************"

TEMP_PREFIX="temp_"
missing_transforms=()
for t in "${TRANSFORM_FILES[@]}"; do
    if [[ ! -f "$t" ]]; then
        missing_transforms+=("$t")
    fi
done

if [[ -f "$MASKED_SKULL_TEMPLATE" && ${#missing_transforms[@]} -eq 0 ]]; then
    echo "Masked skull-stripped template and all per-session transforms already exist. Skipping ANTs average stage."
else
    if [[ -f "$MASKED_SKULL_TEMPLATE" && ${#missing_transforms[@]} -gt 0 ]]; then
        echo "Masked skull-stripped template exists but transform set is incomplete for current sessions."
        echo "Missing transforms:"
        for t in "${missing_transforms[@]}"; do
            echo "  - $(basename "$t")"
        done
        echo "Removing stale ses-all template artifacts and rebuilding Step 3 from current session set..."

        rm -f "$MASKED_SKULL_TEMPLATE" "${MASKED_SKULL_TEMPLATE%.nii.gz}.json"
        rm -f "$UNMASKED_TEMPLATE" "${UNMASKED_TEMPLATE%.nii.gz}.json"
        rm -f "$FINAL_MASKED_TEMPLATE" "${FINAL_MASKED_TEMPLATE%.nii.gz}.json"
        rm -f "$WARPED_LIST"
        rm -f "${TRANSFORM_FILES[@]}"
        rm -f "${WARPED_FILES[@]}"
        rm -f "$TEMPLATE_DIR"/temp_*
    fi

    echo "Creating masked skull-stripped template using ANTs..."
    echo "Copying masked files to template directory..."
    cp "${MASKED_FILES[@]}" "$TEMPLATE_DIR/"

    cd "$TEMPLATE_DIR" || { echo "ERROR: Failed to change directory to $TEMPLATE_DIR"; exit 1; }

    masked_input_names=()
    for file in "${MASKED_FILES[@]}"; do
        masked_input_names+=("$(basename "$file")")
    done

    apptainer exec --bind "$SCRIPT_DIR:$SCRIPT_DIR" "$ANTS_CONTAINER" \
        "$SCRIPT_DIR/fluesebrink/antsIntrasubjectAverage_NearestNeighbor.sh" \
        -d 3 \
        -i 4 \
        -c 2 \
        -g 0.1 \
        -e 1 \
        -k 1 \
        -a 2 \
        -b 0 \
        -n 0 \
        -r 1 \
        -j "$ANTS_THREADS" \
        -f 8x4x2x1 \
        -s 4x2x1x0 \
        -q 1000x1000x500x250 \
        -t Rigid \
        -o "$TEMP_PREFIX" \
        "${masked_input_names[@]}"

    raw_template="$TEMPLATE_DIR/${TEMP_PREFIX}template0.nii.gz"
    if [[ -f "$raw_template" ]]; then
        mv "$raw_template" "$MASKED_SKULL_TEMPLATE"
        echo "Masked skull-stripped template created: $(basename "$MASKED_SKULL_TEMPLATE")"
    else
        echo "Error: Expected ANTs output not found: $raw_template"
        exit 1
    fi

    # Remove copied inputs from the template folder after ANTs finishes.
    for file in "${MASKED_FILES[@]}"; do
        rm -f "$TEMPLATE_DIR/$(basename "$file")"
    done
fi

# Ensure per-session transform files are available with stable names.
for i in "${!SESSION_IDS[@]}"; do
    session_id="${SESSION_IDS[$i]}"
    src_basename="$(basename "${MASKED_FILES[$i]}")"
    target_transform="${TRANSFORM_FILES[$i]}"

    if [[ -f "$target_transform" ]]; then
        continue
    fi

    candidate=$(find "$TEMPLATE_DIR" -maxdepth 1 -type f -name "${TEMP_PREFIX}${src_basename}*GenericAffine.mat" | head -n 1)
    if [[ -n "$candidate" ]]; then
        mv "$candidate" "$target_transform"
        echo "Mapped transform for $session_id: $(basename "$target_transform")"
    else
        echo "Error: Missing transform for $session_id after masked template creation"
        echo "Expected either $target_transform or ANTs-native ${TEMP_PREFIX}${src_basename}*GenericAffine.mat"
        exit 1
    fi
done

# Step 3.1: Apply transformations from masked template stage to UNMASKED structural data
# This yields per-session unmasked images in masked template space.
echo ""
echo "***************************************"
echo "* Step 3.1: Warp unmasked T1w images to masked-template space"
echo "***************************************"
for i in "${!SESSION_IDS[@]}"; do
    session_id="${SESSION_IDS[$i]}"
    unmasked_input="${UNMASKED_FILES[$i]}"
    transform_file="${TRANSFORM_FILES[$i]}"
    warped_output="${WARPED_FILES[$i]}"

    if [[ -f "$warped_output" ]]; then
        echo "Warped unmasked image for $session_id already exists. Skipping."
        continue
    fi

    echo "Applying transform for $session_id..."
    apptainer exec "$ANTS_CONTAINER" antsApplyTransforms \
        -d 3 \
        -e 0 \
        -v 1 \
        -n NearestNeighbor \
        --float \
        -r "$MASKED_SKULL_TEMPLATE" \
        -t "$transform_file" \
        -i "$unmasked_input" \
        -o "$warped_output"

done

# Step 3.2: Create unbiased template of all warped UNMASKED structural data across sessions
echo ""
echo "***************************************"
echo "* Step 3.2: Create unmasked structural template across sessions"
echo "***************************************"
if [[ -f "$UNMASKED_TEMPLATE" ]]; then
    echo "Unmasked template already exists. Skipping average stage."
else
    printf '%s\n' "${WARPED_FILES[@]}" > "$WARPED_LIST"

    # Calculate a voxel-wise mean image from all warped images, in the template space
    apptainer exec "$ANTS_CONTAINER" ImageSetStatistics 3 \
        "$WARPED_LIST" \
        "$UNMASKED_TEMPLATE" \
        0

    echo "Unmasked template created: $(basename "$UNMASKED_TEMPLATE")"
fi

# Step 3.3: Mask unmasked structural template (canonical final output)
echo ""
echo "***************************************"
echo "* Step 3.3: Mask unmasked structural template"
echo "***************************************"
if [[ -f "$FINAL_MASKED_TEMPLATE" ]]; then
    echo "Final masked template already exists. Skipping masking stage."
else
    # b is 0 for sub-01, sub-03, sub-05, sub-06, and b is 1 for sub-02, sub-04
    apptainer exec "$FREESURFER_CONTAINER" mri_synthstrip \
        -i "$UNMASKED_TEMPLATE" \
        -b 0 \
        -o "$FINAL_MASKED_TEMPLATE" \
        --no-csf

    echo "Final masked template created: $(basename "$FINAL_MASKED_TEMPLATE")"
fi

# Create JSON sidecars
echo ""
echo "Creating BIDS-compliant JSON sidecars..."

source_masked_json=$(build_sources_json MASKED_FILES)
source_unmasked_json=$(build_sources_json UNMASKED_FILES)

masked_template_json="${MASKED_SKULL_TEMPLATE%.nii.gz}.json"
unmasked_template_json="${UNMASKED_TEMPLATE%.nii.gz}.json"

if [[ -f "$masked_template_json" ]]; then
    echo "Masked template JSON already exists. Skipping."
else
cat > "$masked_template_json" << EOF
{
    "Description": "Unbiased template created from skull-stripped T1-weighted images across sessions",
    "Sources": [${source_masked_json}],
    "SpatialReference": "orig",
    "SkullStripped": true,
    "Resolution": "native",
    "Density": "native",
    "TemplateType": "MaskedSkullstrip",
    "GeneratedBy": [
        {
            "Name": "ANTs",
            "Version": "2.6.0",
            "Description": "Template creation using ANTs antsIntrasubjectAverage_NearestNeighbor.sh"
        }
    ]
}
EOF
fi

if [[ -f "$unmasked_template_json" ]]; then
    echo "Unmasked template JSON already exists. Skipping."
else
cat > "$unmasked_template_json" << EOF
{
    "Description": "Unbiased template created from warped bias-field-corrected unmasked T1-weighted images across sessions",
    "Sources": [${source_unmasked_json}],
    "SpatialReference": "${SUBJECT}_ses-all_T1w_desc-biasCorrected-skullStripped-template",
    "SkullStripped": false,
    "Resolution": "native",
    "Density": "native",
    "TemplateType": "Unmasked",
    "GeneratedBy": [
        {
            "Name": "ANTs",
            "Version": "2.6.0",
            "Description": "Warping with antsApplyTransforms and averaging with ImageSetStatistics"
        }
    ]
}
EOF
fi

if [[ -f "$final_template_json" ]]; then
    echo "Final canonical template JSON already exists. Skipping."
else
cat > "$final_template_json" << EOF
{
    "Description": "Final canonical structural template obtained by masking the unmasked structural session-average template",
    "Sources": ["$(basename "$UNMASKED_TEMPLATE")"],
    "SpatialReference": "orig",
    "SkullStripped": true,
    "Resolution": "native",
    "Density": "native",
    "TemplateType": "CanonicalMasked",
    "GeneratedBy": [
        {
            "Name": "FreeSurfer",
            "Version": "$FREESURFER_VERSION",
            "Description": "Template masking using mri_synthstrip"
        }
    ]
}
EOF
fi

# Archive interim template files once the final ses-all template and sidecar exist.
if [[ -f "$FINAL_MASKED_TEMPLATE" && -f "$final_template_json" ]]; then
    interim_dir="$TEMPLATE_DIR/template_interim"
    mkdir -p "$interim_dir"

    shopt -s nullglob

    temp_template_files=("$TEMPLATE_DIR"/temp_template0*)
    if [[ ${#temp_template_files[@]} -gt 0 ]]; then
        mv "${temp_template_files[@]}" "$interim_dir"/
    fi

    per_session_files=("$TEMPLATE_DIR"/${SUBJECT}_ses-0*)
    if [[ ${#per_session_files[@]} -gt 0 ]]; then
        mv "${per_session_files[@]}" "$interim_dir"/
    fi

    txt_files=("$TEMPLATE_DIR"/*.txt)
    if [[ ${#txt_files[@]} -gt 0 ]]; then
        mv "${txt_files[@]}" "$interim_dir"/
    fi

    shopt -u nullglob
fi

echo ""
echo "========================================"
echo "TEMPLATE CREATION COMPLETED SUCCESSFULLY"
echo "========================================"
echo "Processing completed: $(date)"
echo "Template directory: $TEMPLATE_DIR"
echo ""
echo "BIDS-compliant output files:"
echo "  - Masked skull-stripped template: $(basename "$MASKED_SKULL_TEMPLATE")"
echo "  - Unmasked template: $(basename "$UNMASKED_TEMPLATE")"
echo "  - Final canonical masked template: $(basename "$FINAL_MASKED_TEMPLATE")"
echo "========================================"


