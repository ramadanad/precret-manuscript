#!/usr/bin/env python3
"""Discover functional files and persist the same shell-sourceable state as f1_find_func_files.sh."""

from __future__ import annotations

import shlex
import sys
from collections import OrderedDict
from pathlib import Path


def emit(message: str) -> None:
    print(message)


def bash_quote(value: str) -> str:
    return shlex.quote(value)


def format_indexed_array(name: str, values: list[str]) -> str:
    entries = " ".join(f"[{index}]={bash_quote(value)}" for index, value in enumerate(values))
    return f"declare -a {name}=({entries})\n"


def format_associative_array(name: str, values: dict[str, str]) -> str:
    entries = " ".join(f"[{bash_quote(key)}]={bash_quote(value)}" for key, value in values.items())
    return f"declare -A {name}=({entries})\n"


def validate_inputs(func_dir: Path, fmap_dir: Path, state_file: Path) -> None:
    if not state_file:
        raise ValueError("state_file is required")
    if state_file.exists() and state_file.is_dir():
        raise IsADirectoryError(f"State file path is a directory: {state_file}")


def discover_functional_files(func_dir: Path, fmap_dir: Path) -> tuple[list[str], bool]:
    func_files: list[str] = []

    for path in sorted(func_dir.rglob("*.nii.gz")):
        if "run-" in path.name:
            func_files.append(str(path))

    rev_pe_exists = False
    if fmap_dir.is_dir():
        rev_pe_files = sorted(fmap_dir.rglob("*dir-PA_epi.nii.gz"))
        if rev_pe_files:
            rev_pe = str(rev_pe_files[0])
            func_files.append(rev_pe)
            rev_pe_exists = True
            emit(f"  Found reversed phase encoded EPI: {Path(rev_pe).name}")

    return func_files, rev_pe_exists


def group_by_sequence(func_files: list[str]) -> tuple[OrderedDict[str, str], OrderedDict[str, int], int]:
    sequence_files: OrderedDict[str, str] = OrderedDict()
    sequence_counts: OrderedDict[str, int] = OrderedDict()
    valid_files = 0

    for func_file in func_files:
        filename = Path(func_file).name
        if "epi" in filename:
            sequence = "epi"
        elif "bssfp" in filename:
            sequence = "bssfp"
        else:
            emit(f"  Warning: Could not determine sequence type from {filename}, skipping")
            continue

        sequence_files[sequence] = sequence_files.get(sequence, "") + f"{func_file} "
        sequence_counts[sequence] = sequence_counts.get(sequence, 0) + 1
        valid_files += 1

    return sequence_files, sequence_counts, valid_files


def write_state_file(
    state_file: Path,
    func_files: list[str],
    sequence_files: OrderedDict[str, str],
    sequence_counts: OrderedDict[str, int],
    valid_files: int,
    rev_pe_exists: bool,
) -> None:
    content = []
    content.append(format_indexed_array("FUNC_FILES", func_files))
    content.append(format_associative_array("SEQUENCE_FILES", dict(sequence_files)))
    content.append(format_associative_array("SEQUENCE_COUNTS", {k: str(v) for k, v in sequence_counts.items()}))
    content.append(f"valid_files={bash_quote(str(valid_files))}\n")
    content.append(f"REV_PE_EXISTS={bash_quote(str(rev_pe_exists).lower())}\n")

    state_file.parent.mkdir(parents=True, exist_ok=True)
    state_file.write_text("".join(content), encoding="utf-8")


def discover_and_persist(func_dir: str, fmap_dir: str, state_file: str) -> int:
    func_dir_path = Path(func_dir)
    fmap_dir_path = Path(fmap_dir)
    state_file_path = Path(state_file)

    validate_inputs(func_dir_path, fmap_dir_path, state_file_path)

    emit("====================================================================================")
    emit("  Discovering functional files...")
    emit("====================================================================================")

    func_files, rev_pe_exists = discover_functional_files(func_dir_path, fmap_dir_path)
    if not func_files:
        emit(f"  Error: No functional files found in {func_dir_path}")
        raise SystemExit(1)

    emit(f"  Found {len(func_files)} functional files total")

    sequence_files, sequence_counts, valid_files = group_by_sequence(func_files)
    if not sequence_files:
        emit("  Error: No valid functional files with recognizable sequence types found")
        raise SystemExit(1)

    emit("  Detected sequence types and counts:")
    for sequence, count in sequence_counts.items():
        emit(f"    - {sequence}: {count} files")
    emit(f"  Total valid files to process: {valid_files}")

    write_state_file(state_file_path, func_files, sequence_files, sequence_counts, valid_files, rev_pe_exists)
    return 0


def main(argv: list[str]) -> int:
    if len(argv) < 4:
        emit(f"  Error: Usage: {Path(argv[0]).name} <func_dir> <fmap_dir> <state_output_file>")
        return 1

    _, func_dir, fmap_dir, state_file = argv[:4]
    try:
        return discover_and_persist(func_dir, fmap_dir, state_file)
    except (FileNotFoundError, IsADirectoryError, ValueError) as exc:
        emit(f"  Error: {exc}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))