#!/usr/bin/env python3
"""Remove first 3 dummy volumes from functional files."""

from __future__ import annotations

import re
import stat
import subprocess
import sys
from collections import OrderedDict
from pathlib import Path


def emit(message: str) -> None:
    print(message)


def find_functional_files(func_dir: Path, fmap_dir: Path) -> list[Path]:
    func_files: list[Path] = []

    for nii_file in sorted(func_dir.rglob("*.nii.gz")):
        if re.search(r"run-[0-9]+", nii_file.name):
            func_files.append(nii_file)

    if fmap_dir.is_dir():
        rev_candidates = list(fmap_dir.rglob("*dir-PA_epi.nii.gz"))
        if rev_candidates:
            rev_pe_file = rev_candidates[0]
            func_files.append(rev_pe_file)
            emit(f"Found reversed phase encoded EPI: {rev_pe_file.name}")

    return func_files


def group_by_sequence(func_files: list[Path]) -> tuple[OrderedDict[str, list[Path]], OrderedDict[str, int], int]:
    sequence_files: OrderedDict[str, list[Path]] = OrderedDict()
    sequence_counts: OrderedDict[str, int] = OrderedDict()
    valid_files = 0

    for func_file in func_files:
        filename = func_file.name
        if "epi" in filename:
            sequence = "epi"
        elif "bssfp" in filename:
            sequence = "bssfp"
        else:
            emit(f"Warning: Could not determine sequence type from {filename}, skipping")
            continue

        if sequence not in sequence_files:
            sequence_files[sequence] = []
            sequence_counts[sequence] = 0

        sequence_files[sequence].append(func_file)
        sequence_counts[sequence] += 1
        valid_files += 1

    return sequence_files, sequence_counts, valid_files


def ensure_executable(script_path: Path) -> None:
    mode = script_path.stat().st_mode
    script_path.chmod(mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def process_files(
    subject: str,
    session: str,
    preproc_dir: Path,
    fsl_container: Path,
    sequence_files: OrderedDict[str, list[Path]],
    fslroi_script: Path,
) -> tuple[int, int]:
    processed_files = 0
    skipped_files = 0

    for sequence, files in sequence_files.items():
        emit(f"Processing {sequence} files for dummy removal...")

        for func_file in files:
            filename = func_file.name

            run_match = re.search(r"run-([0-9]+)", filename)
            if run_match:
                run_num = run_match.group(1)
            elif "dir-PA" in filename:
                run_num = "NA"
            else:
                emit(f"Warning: Could not extract run number from {filename}, skipping")
                continue

            if "dir-PA" in filename:
                output_file = preproc_dir / f"{subject}_{session}_dir-PA_{sequence}_desc-dummyRemoval.nii.gz"
            else:
                output_file = preproc_dir / f"{subject}_{session}_task-prf_run-{run_num}_acq-{sequence}_desc-dummyRemoval.nii.gz"

            if output_file.exists():
                emit(f"File exists, skipping: {output_file.name}")
                skipped_files += 1
                continue

            emit(f"Processing: {filename} -> {output_file.name}")
            subprocess.run(
                [str(fslroi_script), str(fsl_container), str(func_file), str(output_file)],
                check=True,
            )
            processed_files += 1

    return processed_files, skipped_files


def dummy_removal(subject: str, session: str, func_dir: Path, preproc_dir: Path, fsl_container: Path) -> None:
    if not fsl_container.is_file():
        emit(f"Error: FSL container not found: {fsl_container}")
        raise SystemExit(1)

    if not func_dir.is_dir():
        emit(f"Error: Functional directory not found: {func_dir}")
        raise SystemExit(1)

    preproc_dir.mkdir(parents=True, exist_ok=True)

    emit("====================================================================================")
    emit("  Removing dummy volumes ...")
    emit("====================================================================================")

    fmap_dir = func_dir.parent / "fmap"
    func_files = find_functional_files(func_dir, fmap_dir)

    if not func_files:
        emit(f"Error: No functional files found in {func_dir}")
        raise SystemExit(1)

    emit(f"Found {len(func_files)} functional files total")

    sequence_files, sequence_counts, valid_files = group_by_sequence(func_files)

    if not sequence_files:
        emit("Error: No valid functional files with recognizable sequence types found")
        raise SystemExit(1)

    emit("Detected sequence types and counts:")
    for seq, count in sequence_counts.items():
        emit(f"  - {seq}: {count} files")
    emit(f"Total valid files to process: {valid_files}")

    fslroi_script = Path(__file__).resolve().parent / "f2_fslroi_3.sh"
    if not fslroi_script.is_file():
        emit(f"Error: Missing helper script: {fslroi_script}")
        raise SystemExit(1)
    ensure_executable(fslroi_script)

    processed_files, skipped_files = process_files(
        subject=subject,
        session=session,
        preproc_dir=preproc_dir,
        fsl_container=fsl_container,
        sequence_files=sequence_files,
        fslroi_script=fslroi_script,
    )

    emit("")
    emit(f"Dummy volume removal completed: {processed_files} processed, {skipped_files} skipped")


def main(argv: list[str]) -> int:
    if len(argv) < 6:
        emit("Error: Insufficient parameters")
        emit(f"Usage: {argv[0]} <subject> <session> <FUNC_DIR> <PREPROC_DIR> <fsl_container>")
        return 1

    subject = argv[1]
    session = argv[2]
    func_dir = Path(argv[3]).resolve()
    preproc_dir = Path(argv[4]).resolve()
    fsl_container = Path(argv[5]).resolve()

    try:
        dummy_removal(subject, session, func_dir, preproc_dir, fsl_container)
    except subprocess.CalledProcessError:
        return 1
    except SystemExit as exc:
        code = int(exc.code) if isinstance(exc.code, int) else 1
        return code

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
