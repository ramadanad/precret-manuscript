#!/bin/bash

set -e

if [[ $# -ne 3 ]]; then
    echo "Usage: $0 <fsl_container> <input_file> <output_file>"
    exit 1
fi

FSL_CONTAINER="$1"
INPUT_FILE="$2"
OUTPUT_FILE="$3"

apptainer exec "$FSL_CONTAINER" fslroi "$INPUT_FILE" "$OUTPUT_FILE" 3 -1
