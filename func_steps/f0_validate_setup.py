#!/usr/bin/env python3
"""Validate functional pipeline setup and return the distortion-correction script path.

This is a Python implementation of the existing f0_validate_setup.sh contract.
It prints the same status lines and returns the DISTCORR path (or an empty line)
as the final line on stdout.
"""

from __future__ import annotations

import os
import stat
import sys
from pathlib import Path

CONTAINERS_PATH = Path("/ptmp/dramadan/containers")
MATLAB_CONTAINER = CONTAINERS_PATH / "matlab-r2024b-2024-11-24-bfbf29ea5350.sif"
MATLAB_SPM_HOST = Path.home() / "matlab" / "spm"


def eprint(message: str) -> None:
    print(message, file=sys.stderr)


def validate_matlab_container_setup(bids_root: Path) -> None:
    """Mirror the shell helper's validation of the MATLAB runtime prerequisites."""
    if not MATLAB_CONTAINER.is_file():
        raise FileNotFoundError(f"MATLAB container not found: {MATLAB_CONTAINER}")
    if not MATLAB_SPM_HOST.is_dir():
        raise FileNotFoundError(f"SPM path not found: {MATLAB_SPM_HOST}")
    if not bids_root.is_dir():
        raise FileNotFoundError(f"BIDS root for binding not found: {bids_root}")


def validate_setup(bids_root: str, subject: str, session: str, script_dir: str) -> str:
    """Validate session inputs and return the distortion-correction script path."""
    bids_root_path = Path(bids_root)
    subject_dir = bids_root_path / subject / session
    func_dir = subject_dir / "func"
    fmap_dir = subject_dir / "fmap"
    distcorr = Path(script_dir) / "func_steps" / "f7_topup.sh"

    eprint("====================================================================================")
    eprint("  Checking required directories...")
    eprint("====================================================================================")

    if not subject_dir.is_dir():
        eprint(f"  Error: Session directory {subject_dir} does not exist.")
        raise SystemExit(1)
    eprint("  Session directory found")

    if not func_dir.is_dir():
        eprint(f"  Error: Functional directory {func_dir} does not exist.")
        raise SystemExit(1)
    eprint("  Functional directory found")

    if not fmap_dir.is_dir():
        eprint(
            f"  Warning: Field map directory {fmap_dir} does not exist. You need the reversed phase encoded data!"
        )
    eprint("  Fmap directory found")

    if not distcorr.is_file():
        eprint("  Warning: Distortion correction script not found. EPI distortion correction will be skipped.")
        distcorr_output = ""
    elif not os.access(distcorr, os.X_OK):
        eprint("  Making distortion correction script executable...")
        distcorr.chmod(distcorr.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
        eprint("  Distortion correction script ready")
        distcorr_output = str(distcorr)
    else:
        eprint("  Distortion correction script found and executable")
        distcorr_output = str(distcorr)

    eprint("====================================================================================")
    eprint("  Validating MATLAB container setup...")
    eprint("====================================================================================")
    try:
        validate_matlab_container_setup(bids_root_path)
    except FileNotFoundError as exc:
        eprint(f"  Error: {exc}")
        raise SystemExit(1)

    eprint("  Validation successful")
    print(distcorr_output)
    return distcorr_output


def main(argv: list[str]) -> int:
    if len(argv) < 5:
        print(
            "Error: Usage: f0_validate_setup.py <bids_root> <subject> <session> <script_dir>",
            file=sys.stderr,
        )
        return 1

    _, bids_root, subject, session, script_dir = argv[:5]
    try:
        validate_setup(bids_root, subject, session, script_dir)
    except SystemExit as exc:
        return int(exc.code) if isinstance(exc.code, int) else 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
