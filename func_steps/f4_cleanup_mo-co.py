#!/usr/bin/env python3
"""Clean up motion correction intermediate files."""

from __future__ import annotations

import sys
from pathlib import Path


def emit(message: str) -> None:
    print(message)


def discover_sequences(preproc_dir: Path, session: str) -> list[str]:
    sequences_found: dict[str, int] = {}
    # Detect sequences from current and legacy intermediate/final NIfTI naming.
    for nii_file in sorted(preproc_dir.glob(f"*{session}*.nii*")):
        if not nii_file.is_file():
            continue
        filename = nii_file.name
        if "_desc-dummyRemoval" not in filename:
            continue
        if "_acq-epi_" in filename:
            sequences_found["epi"] = 1
        elif "_acq-bssfp_" in filename:
            sequences_found["bssfp"] = 1
    return list(sequences_found.keys())


def cleanup_sequence(preproc_dir: Path, session: str, sequence: str) -> tuple[int, int]:
    emit("")
    emit(f"Processing sequence: {sequence}")

    cleanup_targets = [
        f"*{session}*{sequence}*.ps",
        f"rp_*{session}*{sequence}*_changedheader.txt",
        f"*{session}*{sequence}*_changedheader.mat",
        f"mean*{session}*{sequence}*_changedheader.nii",
        f"*{session}*{sequence}*changedheader*",
        f"*{session}*{sequence}*plotMotionParams.pdf",
        f"*{session}*{sequence}*motion-params-plot.pdf",
    ]
    has_targets = any(
        any(path.is_file() for path in preproc_dir.glob(pattern))
        for pattern in cleanup_targets
    )
    if not has_targets:
        emit(f"  Warning: No cleanup targets found for {sequence} - skipping cleanup")
        return 0, 0

    removed_count = 0
    renamed_count = 0

    for ps_file in sorted(preproc_dir.glob(f"*.ps")):
        if ps_file.is_file():
            ps_file.unlink()
            emit(f"  Removed: {ps_file.name} (.ps file)")
            removed_count += 1

    for rp_file in sorted(preproc_dir.glob(f"rp_*{session}*{sequence}*_changedheader.txt")):
        if rp_file.is_file():
            filename = rp_file.name
            new_filename = filename.removeprefix("rp_")
            if new_filename.endswith("_changedheader.txt"):
                new_filename = new_filename[: -len("_changedheader.txt")]
            new_filename = f"{new_filename}-motionParams.txt"
            rp_file.rename(preproc_dir / new_filename)
            emit(f"  Renamed: {filename} → {new_filename}")
            renamed_count += 1

    for mat_file in sorted(preproc_dir.glob(f"*{session}*{sequence}*_changedheader.mat")):
        if mat_file.is_file():
            filename = mat_file.name
            new_filename = filename
            if new_filename.endswith("_changedheader.mat"):
                new_filename = new_filename[: -len("_changedheader.mat")]
            new_filename = f"{new_filename}-motionCorr-transformationMatrix.mat"
            mat_file.rename(preproc_dir / new_filename)
            emit(f"  Renamed: {filename} → {new_filename}")
            renamed_count += 1

    for mean_file in sorted(preproc_dir.glob(f"mean*{session}*{sequence}*_changedheader.nii")):
        if mean_file.is_file():
            filename = mean_file.name
            new_filename = filename.removeprefix("mean")
            if new_filename.endswith("_changedheader.nii"):
                new_filename = new_filename[: -len("_changedheader.nii")]
            new_filename = f"{new_filename}-motionCorr-meanVol.nii"
            mean_file.rename(preproc_dir / new_filename)
            emit(f"  Renamed: {filename} → {new_filename}")
            renamed_count += 1

    for ch_file in sorted(preproc_dir.glob(f"*{session}*{sequence}*changedheader*")):
        if ch_file.is_file():
            ch_file.unlink()
            emit(f"  Removed: {ch_file.name} (*changedheader* file)")
            removed_count += 1

    return removed_count, renamed_count


def archive_interim_files(preproc_dir: Path) -> int:
    emit("====================================================================================")
    emit("  Archiving motion correction interim files")
    emit("====================================================================================")

    motion_interim_dir = preproc_dir / "motion-corr_interim"
    motion_interim_dir.mkdir(parents=True, exist_ok=True)

    archived_count = 0
    for ext in ("mat", "pdf", "txt"):
        for file in sorted(preproc_dir.glob(f"*.{ext}")):
            if file.is_file():
                file.rename(motion_interim_dir / file.name)
                archived_count += 1

    if archived_count > 0:
        emit(f"  Moved {archived_count} motion interim file(s) to: {motion_interim_dir}")
    else:
        emit("  No motion interim files found to archive")

    return archived_count


def cleanup_motion_correction(subject: str, session: str, preproc_dir: Path) -> int:
    if not subject or not session or not str(preproc_dir):
        emit("  Error: Missing required arguments")
        emit("  Usage: f4_cleanup_mo-co.py <subject> <session> <preproc_dir>")
        return 1

    emit("====================================================================================")
    emit("  Motion correction cleanup")
    emit("====================================================================================")

    sequences = discover_sequences(preproc_dir, session)

    total_removed = 0
    total_renamed = 0
    for sequence in sequences:
        removed, renamed = cleanup_sequence(preproc_dir, session, sequence)
        total_removed += removed
        total_renamed += renamed

    archive_interim_files(preproc_dir)

    emit("")
    emit("====================================================================================")
    emit("  Summary:")
    emit(f"    Total files removed: {total_removed}")
    emit(f"    Total files renamed: {total_renamed}")
    emit("====================================================================================")
    return 0


def main(argv: list[str]) -> int:
    subject = argv[1] if len(argv) > 1 else ""
    session = argv[2] if len(argv) > 2 else ""
    preproc_dir = Path(argv[3]).resolve() if len(argv) > 3 else Path("")
    return cleanup_motion_correction(subject, session, preproc_dir)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
