#!/bin/bash

# fa1_run_coreg.sh - Run FA-map coregistration for all subjects/sessions

set -e

BIDS_ROOT="${1:-}"

export SUBJECTS_DIR="$(realpath "$BIDS_ROOT/derivatives/freesurfer")"
FREESURFER_CONTAINER=/ptmp/dramadan/containers/freesurfer_8.1.0_latest.sif
PROJFRAC=0.5
PROJFRAC_LABEL="projFrac-0p5"

export APPTAINERENV_SUBJECTS_DIR="$SUBJECTS_DIR"

for SUBJECT_DIR in "$BIDS_ROOT"/sub-*/; do
    [[ -d "$SUBJECT_DIR" ]] || continue

    SUBJECT="$(basename "$SUBJECT_DIR")"
    SUBJECT_FS_DIR="$SUBJECTS_DIR/$SUBJECT"
    mkdir -p "$SUBJECT_FS_DIR/vol2surf"

    for SESSION_DIR in "$SUBJECT_DIR"/ses-*/; do
        [[ -d "$SESSION_DIR" ]] || continue

        SESSION="$(basename "$SESSION_DIR")"
        B1_FILE="$BIDS_ROOT/derivatives/preproc/$SUBJECT/$SESSION/fmap/${SUBJECT}_${SESSION}_FAmap_desc-normalized.nii.gz"
        MPRAGE_FILE="$BIDS_ROOT/derivatives/preproc/$SUBJECT/$SESSION/anat/${SUBJECT}_${SESSION}_T1w_desc-biasCorrected-skullStripped.nii"
        LTA_FILE="$SUBJECT_FS_DIR/vol2surf/${SUBJECT}_${SESSION}_FAmap.lta"

        if [[ ! -f "$B1_FILE" ]]; then
            echo "Skipping $SUBJECT $SESSION: missing FA map $B1_FILE"
            continue
        fi

        if [[ ! -f "$MPRAGE_FILE" ]]; then
            echo "Skipping $SUBJECT $SESSION: missing MPRAGE file $MPRAGE_FILE"
            continue
        fi

        for HEMI in lh rh; do
            OUTPUT_FILE="$SUBJECT_FS_DIR/vol2surf/${PROJFRAC_LABEL}/${HEMI}_${SUBJECT}_${SESSION}_FAmap_desc-normalized.mgh"

            if [[ -f "$OUTPUT_FILE" ]]; then
                echo "Skipping $SUBJECT $SESSION $HEMI: output already exists"
                continue
            fi

            bash "$(dirname "$0")/fa1_coreg.sh" \
                "$SUBJECTS_DIR" \
                "$FREESURFER_CONTAINER" \
                "$SUBJECT" \
                "$MPRAGE_FILE" \
                "$B1_FILE" \
                "$LTA_FILE" \
                "$HEMI" \
                "$OUTPUT_FILE" \
                "$PROJFRAC"
        done
    done
done

for SUBJECT_DIR in "$BIDS_ROOT"/sub-*/; do
    [[ -d "$SUBJECT_DIR" ]] || continue

    SUBJECT="$(basename "$SUBJECT_DIR")"
    SUBJECT_VOL2SURF_DIR="$SUBJECTS_DIR/$SUBJECT/vol2surf"
    TARGET_DIR="$SUBJECT_VOL2SURF_DIR/famap_$PROJFRAC_LABEL"
    BBR_INTERIM="$SUBJECT_VOL2SURF_DIR/famap_bbr_interim"

    mkdir -p "$TARGET_DIR"
    mkdir -p "$BBR_INTERIM"

    shopt -s nullglob
    for fmap_file in "$SUBJECT_VOL2SURF_DIR"/*FAmap*.mgh; do
        mv "$fmap_file" "$TARGET_DIR/"
    done

    for bbr_interim_files in "$SUBJECT_VOL2SURF_DIR"/*FAmap*.dat*; do
        mv "$bbr_interim_files" "$BBR_INTERIM/"
    done

    for bbr_interim_files in "$SUBJECT_VOL2SURF_DIR"/*FAmap*.log; do
        mv "$bbr_interim_files" "$BBR_INTERIM/"
    done
    shopt -u nullglob
done