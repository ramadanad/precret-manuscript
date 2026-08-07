#!/usr/bin/env python3
"""Create an all-subject motion summary with paired boxplots per subject.

This script only produces the boxplot summary. It scans the preprocessing
directories for one subject's motion-parameter files, pools translations and
rotations per session, and writes a single paired-box SVG to the
<data_root>/figures/motionfigures folder.

Usage:
    python plot_motion_params_allsubs.py ~/data/prf_bids sub-05
"""

from __future__ import annotations

import re
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np


FILE_PATTERN = "sub-*_ses-*_task-prf_run-*_acq-*_desc-dummyRemoval-motionParams.txt"


# find_preproc_root: resolve the preproc directory under the provided data root.
# It expects a folder named 'derivatives/preproc' under the given path and
# raises FileNotFoundError if that exact path does not exist.
def find_preproc_root(data_root: Path | None = None) -> Path:
    """Return the preprocessing root inside the provided `data_root`.

    The provided `data_root` should be the PRF data root (for example
    ``~/data/prf_bids``). This function returns the Path to
    ``<data_root>/derivatives/preproc`` if it exists.
    """

    if data_root is None:
        # HARD-CODED PATH: fixed local PRF data root used by default.
        data_root = Path.home() / "data" / "prf_bids"

    primary_root = data_root / "derivatives" / "preproc"
    if primary_root.is_dir():
        return primary_root
    raise FileNotFoundError(
        f"Could not find a preprocessing root under {data_root}/derivatives/preproc."
    )


# discover_motion_files: collect all motion-parameter text files for a subject.
# It searches each session folder for 'func/motion-corr_interim' and matches
# files against the expected filename pattern.
def discover_motion_files(subject_id: str, data_root: Path | None = None) -> dict[str, list[Path]]:
    """Return motion-parameter files grouped by session for one subject."""

    preproc_root = find_preproc_root(data_root) / subject_id
    if not preproc_root.is_dir():
        raise FileNotFoundError(f"Subject directory not found: {preproc_root}")

    motion_files: dict[str, list[Path]] = {}
    for session_dir in preproc_root.glob("ses-*"):
        session_name = session_dir.name
        session_files = sorted(set(session_dir.glob(f"func/motion-corr_interim/{FILE_PATTERN}")))
        if session_files:
            motion_files[session_name] = session_files
    return motion_files


# load_motion_params was inlined into the pooling step below; helper removed.


# plot_motion_boxplot: discover sessions for a single subject, split runs by
# acquisition type (bssfp / epi), and draw paired boxplots (translation and
# rotation) side-by-side for each session. Saves one SVG per acquisition and
# returns their paths.
def plot_motion_boxplot(subject_id: str, data_root: Path | None = None) -> list[Path]:
    """Create paired boxplots per session for bssfp and epi acquisitions.

    Returns the saved Paths.
    """

    def acq_group(f: Path) -> str | None:
        match = re.search(r"_acq-([^_]+)_", f.name, flags=re.IGNORECASE)
        if not match:
            return None
        acq = match.group(1).lower()
        if "bssfp" in acq:
            return "bssfp"
        if "epi" in acq:
            return "epi"
        return None

    session_files = discover_motion_files(subject_id, data_root)
    if not session_files:
        raise FileNotFoundError(f"No motion-parameter files were found for {subject_id}.")

    session_ids = sorted(
        session_files,
        key=lambda s: int(re.search(r"(\d+)$", s).group(1)) if re.search(r"(\d+)$", s) else 10**9,
    )

    plt.rcParams.update({
        "font.size": 20,
        "axes.titlesize": 20,
        "axes.labelsize": 20,
        "xtick.labelsize": 20,
        "ytick.labelsize": 20,
        "legend.fontsize": 20,
    })

    # HARD-CODED PATH: fixed local output root under the PRF data directory.
    out_dir = Path.home() / "data" / "prf_bids" / "figures" / "motionfigures" / subject_id
    out_dir.mkdir(parents=True, exist_ok=True)
    out_paths: list[Path] = []

    for acq in ("bssfp", "epi"):
        session_labels: list[str] = []
        session_translation: list[np.ndarray] = []
        session_rotation: list[np.ndarray] = []

        for session_id in session_ids:
            files = [f for f in session_files[session_id] if acq_group(f) == acq]
            if not files:
                continue

            tr_chunks: list[np.ndarray] = []
            rot_chunks: list[np.ndarray] = []
            for f in files:
                data = np.loadtxt(f)
                if data.ndim == 1:
                    if data.size != 6:
                        raise ValueError(f"Expected 6 columns in {f}, got {data.size}")
                    data = data[np.newaxis, :]
                if data.ndim != 2 or data.shape[1] != 6:
                    raise ValueError(f"Expected shape Nx6 in {f}, got {data.shape}")
                if not np.isfinite(data).all():
                    raise ValueError(f"Non-finite values in {f}")
                tr_chunks.append(data[:, (0, 1, 2)].reshape(-1))
                rot_chunks.append(np.degrees(data[:, (3, 4, 5)].reshape(-1)))

            session_labels.append(session_id)
            session_translation.append(np.concatenate(tr_chunks) if tr_chunks else np.array([], dtype=float))
            session_rotation.append(np.concatenate(rot_chunks) if rot_chunks else np.array([], dtype=float))

        if not session_labels:
            continue

        fig, ax = plt.subplots(figsize=(max(6, len(session_labels) * 0.9), 6), constrained_layout=True)

        ax.axhline(0, color="grey", linewidth=1.2, alpha=0.8)
        ax.axhline(0.4, color="grey", linestyle="dotted", linewidth=1.2, alpha=0.8)
        ax.axhline(0.8, color="grey", linestyle="dashed", linewidth=1.2, alpha=0.8)
        ax.axhline(-0.4, color="grey", linestyle="dotted", linewidth=1.2, alpha=0.8)
        ax.axhline(-0.8, color="grey", linestyle="dashed", linewidth=1.2, alpha=0.8)

        base = np.arange(1, len(session_labels) + 1)
        off = 0.18
        pos_tr = base - off
        pos_rot = base + off

        box_style = dict(
            medianprops=dict(color="black", linewidth=1.5),
            flierprops=dict(marker="o", markersize=4, markerfacecolor="black", markeredgecolor="none", alpha=0.7),
            patch_artist=True,
            showfliers=True,
        )

        b_tr = ax.boxplot(session_translation, positions=pos_tr, widths=0.28, **box_style)
        b_rot = ax.boxplot(session_rotation, positions=pos_rot, widths=0.28, **box_style)

        for p in b_tr["boxes"]:
            p.set_facecolor("#a8e6cf")
            p.set_alpha(0.8)
        for p in b_rot["boxes"]:
            p.set_facecolor("#ffb3c1")
            p.set_alpha(0.8)

        # Ensure line elements have higher visibility (alpha=0.8)
        for part in ("whiskers", "caps", "medians"):
            for l in b_tr.get(part, []):
                l.set_alpha(0.8)
            for l in b_rot.get(part, []):
                l.set_alpha(0.8)

        for l in b_tr.get("fliers", []):
            l.set_alpha(0.7)
        for l in b_rot.get("fliers", []):
            l.set_alpha(0.7)

        ax.legend([b_tr["boxes"][0], b_rot["boxes"][0]], ["Translation", "Rotation"], loc="best", frameon=True)

        ax.set_xticks(base)
        ax.set_xticklabels([str(i) for i in base], rotation=0, ha="center")
        ######################################
        # Start of changed part per subject
        ax.set_ylim(-.7, .7)
        ax.set_yticks(np.arange(-.6, .7, 0.2))
        # End of changed part per subject
        ######################################
        ax.set_xlim(0.5, len(session_labels) + 0.5)
        ax.set_ylabel("mm / deg")
        ax.set_xlabel("Session")
        fig.suptitle(f"Motion parameters for {subject_id} ({acq})", fontsize=20)

        out_path = out_dir / f"{subject_id}_task-prf_acq-{acq}_plotMotionParams_boxplot.svg"
        fig.savefig(out_path, format="svg", bbox_inches="tight")
        plt.close(fig)
        out_paths.append(out_path)

    if not out_paths:
        raise FileNotFoundError(f"No bssfp/epi motion files were found for {subject_id}.")

    return out_paths


def main() -> None:
    """Run the boxplot summary and print the saved path."""

    import argparse

    parser = argparse.ArgumentParser(
        description="Create a single-subject motion summary boxplot.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "data_root",
        help="Path to the prf data root (required). Example: ~/data/prf_bids",
    )
    parser.add_argument(
        "subject_id",
        help="Subject identifier to plot. Example: sub-05",
    )
    args = parser.parse_args()

    data_root = Path(args.data_root).expanduser()
    out_paths = plot_motion_boxplot(args.subject_id, data_root)
    for out in out_paths:
        print(f"Saved motion plot: {out}")


if __name__ == "__main__":
    main()
