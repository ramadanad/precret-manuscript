#!/usr/bin/env python3
"""
QA Metrics Calculator for MRI Data

This script calculates quality assurance metrics for MRI functional data including:
- tSNR (temporal Signal-to-Noise Ratio)
- Effective tSNR
- Effective Coefficient of Variation
- Mean, Standard Deviation
- Skewness, Kurtosis

The script can save results as NIfTI files or svg visualizations.

Usage:
    python f6_calculate_qa.py <input_path> <metric> [--output-type nifti|svg] [--output-dir <path>] [--zoom 0|1] [--file-pattern <glob> ...]

Examples:
    python f6_calculate_qa.py /path/to/data tsnr --output-type svg
    python f6_calculate_qa.py /path/to/data eff_tsnr --output-type nifti
    python f6_calculate_qa.py /path/to/data mean --output-type both
    python f6_calculate_qa.py /path/to/data tsnr --file-pattern "*_dummy-removal.nii.gz" "*_motion-corr.nii"
"""

import argparse
import numpy as np
import nibabel as nb
import math
import matplotlib
matplotlib.use('Agg')  # Set backend before importing pyplot (for headless operation)
import matplotlib.pyplot as plt
from pathlib import Path
import sys
import traceback

# Valid metrics that can be calculated
VALID_METRICS = ['mean', 'std', 'tsnr', 'eff_tsnr', 'eff_cv', 'skewness', 'kurtosis']

# Default ranges for visualization
METRIC_RANGES = {
    'mean': (0, 4000),
    'std': (0, 100),
    'tsnr': (0, 40),
    'eff_tsnr': (0, 20),
    'eff_cv': (0, 0.1),
    'skewness': (-0.5, 0.5),
    'kurtosis': (-1, 1)
}

# Colormaps for visualization
METRIC_COLORMAPS = {
    'mean': 'Greys_r',
    'std': 'Greys_r',
    'tsnr': 'viridis',
    'eff_tsnr': 'viridis',
    'eff_cv': 'viridis',
    'skewness': 'Greys_r',
    'kurtosis': 'Greys_r'
}
# you can also try a different colmap for skew and kurt like RdBu_r

def display_series(data, run_name, metric, TR, vox_size, n_vols, output_path, fcols=8, zoom=0):
    """
    Create a panel visualization of metric data across slices.
    
    Parameters:
    -----------
    data : numpy.ndarray
        3D metric data to visualize
    run_name : str
        Name of the run for title
    metric : str
        Name of the metric being visualized
    TR : float
        Repetition time in seconds
    vox_size : tuple
        Voxel dimensions
    n_vols : int
        Number of volumes in original data
    output_path : Path
        Output file path for saving svg
    fcols : int
        Number of columns in the panel (default: 8)
    zoom : int
        Whether to zoom in on visualization (1 to enable, default: 0)
    """
    plt.style.use('default')
    
    plt.figure(figsize=(8,5))
    
    if zoom == 1:
        fcols = 2
        print(f"  Generating visualization with {fcols} columns")

    # layout
    frows = data.shape[2]//fcols
        
    fig, sub = plt.subplots(nrows=frows, ncols=fcols)
    
    # Format title information
    tr_ms = int(round(TR * 1000)) if TR else "Unknown"
    rounded_vox_size = tuple(float(round(float(v), 2)) for v in vox_size)
    fig.suptitle(f'{metric} - {run_name}\nTR={tr_ms}ms, Voxel={rounded_vox_size}, Volumes={n_vols}', fontsize=12, y=0.93)
    
    idx=0

    # Get visualization parameters
    vmin, vmax = METRIC_RANGES.get(metric, (np.nanmin(data), np.nanmax(data)))
    colormap = METRIC_COLORMAPS.get(metric, 'viridis')
    
    # Adjust layout once before plotting
    plt.subplots_adjust(wspace=-0.02, hspace=-0.52)
    fig.subplots_adjust(right=0.8)
    
    # plot each slice
    for sub in sub.flat:
        if idx >= data.shape[2]:  # Stop if we've plotted all slices
            break
            
        sub.axis('off')
        im = sub.imshow(data[:,:,idx].T, vmin=vmin, vmax=vmax, cmap=colormap, origin='lower')
        idx += 1
    
    # Add colorbar once after all plots
    if zoom == 1:
        # Shorter colorbar for zoomed view
        cbar_ax = fig.add_axes([0.82, 0.3, 0.02, 0.33])  # half the height
    else:
        # Regular colorbar size
        cbar_ax = fig.add_axes([0.82, 0.2, 0.02, 0.55])
    
    # Create colorbar with exactly three ticks
    cbar = fig.colorbar(im, cax=cbar_ax)
    tick_locs = [vmin, (vmin + vmax)/2, vmax]
    cbar.set_ticks(tick_locs)
    cbar.set_ticklabels([f'{v:.1f}' for v in tick_locs])
    
    
    # Save figure
    plt.savefig(output_path, dpi=300, bbox_inches='tight', facecolor='white')
    plt.close()
    print(f"  Saved visualization: {output_path}")


def calculate_metrics(data, TR, metric):
    """
    Calculate the specified metric from 4D MRI data.
    
    Parameters:
    -----------
    data : numpy.ndarray
        4D input data (x, y, z, time)
    TR : float
        Repetition time in seconds
    metric : str
        Metric to calculate
        
    Returns:
    --------
    numpy.ndarray
        3D array with calculated metric
    """
    data = data[:,:,:,5:]  # Exclude first 5 volumes 
    # Calculate basic statistics
    mean_data = np.mean(data, axis=-1)
    
    if metric == 'mean':
        return mean_data
    
    std_data = np.std(data, axis=-1)#, ddof=1) this ddof changes the std calculation (N-1) instead of N
    
    if metric == 'std':
        return std_data
    
    # Avoid division by zero
    with np.errstate(divide='ignore', invalid='ignore'):
        if metric in ['tsnr', 'eff_tsnr', 'eff_cv']:
            # Calculate tSNR
            tsnr = np.divide(mean_data, std_data, 
                           out=np.zeros_like(mean_data), 
                           where=std_data!=0)
            
            if metric == 'tsnr':
                return tsnr
            
            # Calculate effective tSNR
            if TR is not None and TR > 0:
                eff_tsnr = tsnr / math.sqrt(TR)
            else:
                print("Warning: TR not available, using tSNR instead of effective tSNR")
                eff_tsnr = tsnr
            
            # Replace infinities with NaN
            eff_tsnr[np.isinf(eff_tsnr)] = np.nan
            
            if metric == 'eff_tsnr':
                return eff_tsnr
            
            # Calculate effective coefficient of variation
            if metric == 'eff_cv':
                eff_cv = np.divide(1, eff_tsnr, 
                                out=np.full_like(eff_tsnr, np.nan), 
                                where=eff_tsnr!=0)
                return eff_cv
        
        elif metric in ['skewness', 'kurtosis']:
            # Calculate higher-order moments
            n = data.shape[-1]
            
            # Expand dimensions for broadcasting
            mean_exp = np.expand_dims(mean_data, axis=-1)
            std_exp = np.expand_dims(std_data, axis=-1)
            
            # Standardized data
            standardized = np.divide(data - mean_exp, std_exp,
                                   out=np.zeros_like(data),
                                   where=std_exp!=0)
            
            if metric == 'skewness':
                skewness = np.mean(standardized**3, axis=-1)
                skewness[np.isinf(skewness)] = np.nan
                return skewness
            
            elif metric == 'kurtosis':
                # Excess kurtosis (subtract 3 for normal distribution reference)
                kurtosis = np.mean(standardized**4, axis=-1) - 3
                kurtosis[np.isinf(kurtosis)] = np.nan
                return kurtosis
    
    raise ValueError(f"Unknown metric: {metric}")


def process_nifti_files(input_path, metric, output_type='nifti', output_dir=None, zoom=0, file_patterns=None):
    """
    Process all NIfTI files in the input directory.
    
    Parameters:
    -----------
    input_path : Path
        Path to directory containing NIfTI files
    metric : str
        Metric to calculate
    output_type : str
        Output format: 'nifti', 'svg', or 'both'
    output_dir : Path or None
        Custom output directory (default: input_path/qametrics)
    zoom : int
        Whether to zoom in on visualization (1 to enable, default: 0)
    file_patterns : list of str or None
        Glob patterns to filter which NIfTI files to process (e.g. ['*_dummy-removal.nii.gz']).
        If None, all NIfTI files are processed.
    """
    input_path = Path(input_path)
    
    if not input_path.exists():
        raise FileNotFoundError(f"Input path does not exist: {input_path}")
    
    # Set up output directory
    if output_dir is None:
        if zoom == 1:
            output_dir = input_path / 'qametrics_middle'
        else:
            output_dir = input_path / 'qametrics'
    else:
        output_dir = Path(output_dir)
    
    output_dir.mkdir(parents=True, exist_ok=True)
    
    # Find NIfTI files
    if file_patterns:
        nifti_files = []
        for pattern in file_patterns:
            nifti_files.extend(input_path.glob(pattern))
    else:
        nifti_extensions = ['*.nii', '*.nii.gz']
        nifti_files = []
        for ext in nifti_extensions:
            nifti_files.extend(input_path.glob(ext))
    
    # Remove duplicates (a file could match multiple patterns)
    nifti_files = list(dict.fromkeys(nifti_files))
    
    if not nifti_files:
        print(f"No NIfTI files found in {input_path}")
        return
    
    print(f"Found {len(nifti_files)} NIfTI file(s)")
    print(f"Calculating {metric} metric")
    print(f"Output directory: {output_dir}")
    if zoom == 1:
        print(f"Zooming enabled for visualizations")
    print("-" * 50)
    
    for nifti_file in sorted(nifti_files):
        try:
            print(f"Processing: {nifti_file.name}")
            
            # Generate output filename base
            run_name = nifti_file.stem.replace('.nii', '')
            
            # Check if output files already exist
            nifti_output = output_dir / f'{run_name}_qa-{metric}.nii.gz'
            svg_output = output_dir / f'{run_name}_qa-{metric}.svg'
            
            skip_nifti = output_type not in ['nifti', 'both'] or nifti_output.exists()
            skip_svg = output_type not in ['svg', 'both'] or svg_output.exists()
            
            if skip_nifti and skip_svg:
                print(f"  Skipping {nifti_file.name}: All requested output files already exist")
                continue
            elif skip_nifti:
                print(f"  NIfTI output already exists, will only generate svg")
            elif skip_svg:
                print(f"  svg output already exists, will only generate NIfTI")
            
            # Load data only if processing is needed
            img = nb.load(nifti_file)
            data = img.get_fdata()
            
            if data.ndim != 4:
                print(f"  Skipping {nifti_file.name}: Expected 4D data, got {data.ndim}D")
                continue
            
            # Get metadata
            header = img.header
            TR = header.get_zooms()[3] if len(header.get_zooms()) > 3 else None
            vox_size = header.get_zooms()[:3]
            n_vols = data.shape[-1]
            
            print(f"  Shape: {data.shape}, TR: {TR:.3f}s" if TR else f"  Shape: {data.shape}, TR: Unknown")
            
            # Calculate metric only once if needed
            metric_data = calculate_metrics(data, TR, metric)
            
            # Generate output filename base (already done above)
            # run_name = nifti_file.stem.replace('.nii', '')
            
            # Save NIfTI output only if it doesn't exist
            if output_type in ['nifti', 'both'] and not nifti_output.exists():
                metric_img = nb.Nifti1Image(metric_data, affine=img.affine, header=img.header)
                nb.save(metric_img, nifti_output)
                print(f"  Saved NIfTI: {nifti_output}")
            
            # Save svg output only if it doesn't exist
            if output_type in ['svg', 'both'] and not svg_output.exists():
                # Select middle slices for visualization
                n_slices = metric_data.shape[2]
                vis_slices = 2 if zoom ==1 else 40
                start_slice = n_slices // 2 - vis_slices//2 #max(0, n_slices // 2 - 10)
                end_slice = n_slices // 2 + vis_slices//2 #min(n_slices, n_slices // 2 + 10)
                viz_data = metric_data[:, :, start_slice:end_slice]
                
                display_series(viz_data, run_name, metric, TR, vox_size, n_vols, svg_output, zoom=zoom)
        
        except Exception as e:
            tb = traceback.extract_tb(e.__traceback__)
            if tb:
                filename, lineno, func, text = tb[-1]
                print(f"  Error processing {nifti_file.name}: {e} (at {filename}, line {lineno})")
            else:
                print(f"  Error processing {nifti_file.name}: {e}")
            continue
    
    print("-" * 50)
    print(f"Processing complete! Results saved in: {output_dir}")


def main():
    """Main function for command-line interface."""
    parser = argparse.ArgumentParser(
        description='Calculate QA metrics for MRI functional data',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s /path/to/data tsnr
  %(prog)s /path/to/data eff_tsnr --output-type svg --zoom 1
  %(prog)s /path/to/data mean --output-type both --output-dir /custom/output
  
Valid metrics: """ + ', '.join(VALID_METRICS)
    )
    
    parser.add_argument('input_path', 
                       help='Path to directory containing NIfTI files')
    
    parser.add_argument('metric', 
                       choices=VALID_METRICS,
                       help='QA metric to calculate')
    
    parser.add_argument('--output-type', '-t',
                       choices=['nifti', 'svg', 'both'],
                       default='nifti',
                       help='Output format (default: nifti)')
    
    parser.add_argument('--output-dir', '-o',
                       help='Custom output directory (default: input_path/qametrics)')
    
    parser.add_argument('--zoom', '-z', type=int, choices=[0,1], default=0,
                        help='Zoom in on visualization (1 to enable, default: 0)')
    
    parser.add_argument('--file-pattern', '-p', nargs='+',
                        help='Glob pattern(s) for NIfTI files to include (e.g. "*_dummy-removal.nii.gz")')
    
    parser.add_argument('--version', action='version', version='%(prog)s 1.0')
    
    args = parser.parse_args()
    
    try:
        process_nifti_files(
            input_path=args.input_path,
            metric=args.metric,
            output_type=args.output_type,
            output_dir=args.output_dir,
            zoom=args.zoom,
            file_patterns=args.file_pattern
        )
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
