# Load necessary libraries
import numpy as np
import nibabel as nib
from pathlib import Path

# Load FA map
def load_fa_map(fa_path: Path) -> nib.Nifti1Image:
    """Load the FA map from a NIfTI file."""
    if not fa_path.is_file():
        raise FileNotFoundError(f"FA map file not found: {fa_path}")
    
    try:
        fa_img = nib.load(fa_path)
    except Exception as exc:
        raise ValueError(f"Could not load FA map from {fa_path}: {exc}") from exc
    
    return fa_img

# Rescale FA map
def rescale_fa_map(fa_img: nib.Nifti1Image) -> nib.Nifti1Image:
    """Rescale the FA map to the range [0, 100] %."""
    fa_data = fa_img.get_fdata()
    
    if not np.isfinite(fa_data).all():
        raise ValueError("FA map contains NaN or infinite values.")
    
    # Rescaled data are in percent (divide by 10 and then by the FA, in this case it's 60 deg, and then multiply by 100 to get percentage) 
    rescaled_data = fa_data / 10 / 60 * 100
    
    rescaled_img = nib.Nifti1Image(rescaled_data, affine=fa_img.affine, header=fa_img.header)
    return rescaled_img

# Save rescaled FA map as nii
def save_rescaled_fa_map(rescaled_img: nib.Nifti1Image, output_path: Path) -> None:
    """Save the rescaled FA map to a NIfTI file."""
    try:
        nib.save(rescaled_img, output_path)
    except Exception as exc:
        raise ValueError(f"Could not save rescaled FA map to {output_path}: {exc}") from exc
    
def main():
    """ Run the FA map rescaling process for all sessions. """
    
    import argparse
    parser = argparse.ArgumentParser(description="Rescale FA map to [0, 100] %.")
    parser.add_argument("data_dir", help="Path to the input FA map NIfTI file.")
    parser.add_argument("subject", help="Subject to be processed.")
    args = parser.parse_args()
    
    # Define paths
    data_dir = Path(args.data_dir).expanduser() 
    subject_dir = data_dir / args.subject

    for session_path in subject_dir.expanduser().glob("ses-0*"):
        session = session_path.name

        fa_path = data_dir / args.subject / session / "fmap" / f"{args.subject}_{session}_TB1map.nii.gz"
        output_path = data_dir / "derivatives/preproc" / args.subject / session / "fmap"
        if not output_path.exists():
            output_path.mkdir(parents=True, exist_ok=True) 
        output_file = output_path / f"{args.subject}_{session}_FAmap_desc-normalized.nii.gz"
        
        # Load, rescale, and save FA map
        fa_img = load_fa_map(fa_path)
        rescaled_img = rescale_fa_map(fa_img)
        save_rescaled_fa_map(rescaled_img, output_file)
        print(f"Rescaled FA map saved to: {output_file}")

# Call this function as usual with path to data and subject
if __name__ == "__main__":
    main()