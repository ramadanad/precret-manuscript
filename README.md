# precret-manuscript

This repository contains the custom code used for the manuscript describing the **9.4 Tesla Dataset for Precision Retinotopy in the Human Brain”**.

The dataset contains population receptive field (pRF) mapping data acquired at the 9.4 T MRI scanner at the Max Planck Institute for Biological Cybernetics in Tübingen, Germany. Six healthy volunteers viewed a moving-bar stimulus during five or seven scanning sessions. Data were acquired at 0.8 mm isotropic resolution using both 3D EPI and 3D bSSFP sequences.

For questions or to report an issue, please contact [Dana Ramadan](mailto:dana.ramadan@tuebingen.mpg.de).

## Paper

The preprint is available [here](INSERT_PREPRINT_URL).

## Data

The dataset is available on [OpenNeuro](INSERT_OPENNEURO_URL).

## Stimulus code

The code used to generate and present the experimental stimulus is available in the separate [`precret-stimulus`](INSERT_STIMULUS_REPOSITORY_URL) repository.

## Overview of the processing workflow

The main workflow is launched from the project root with:

```bash
bash main.sh <BIDS_ROOT> <SUBJECT>
```

where `<BIDS_ROOT>` is the path to the BIDS dataset root directory and `<SUBJECT>` is the subject ID (e.g., `sub-01`).


`main.sh` orchestrates four processing pipelines. Each pipeline has its own entry-point script, which calls the numbered processing scripts in the corresponding subdirectory in the intended order.

| Pipeline | Entry point | Processing-step directory |
|---|---|---|
| Functional preprocessing | `func_pipeline.sh` | `func_steps/` |
| Anatomical preprocessing | `anat_pipeline.sh` | `anat_steps/` |
| Coregistration | `coreg_pipeline.sh` | `coreg_steps/` |
| pRF modelling | `samsrf_pipeline.sh` | `samsrf_steps/` |

The FAmap pipeline is separate from the main workflow. It is not called by `main.sh` and must be run independently:

```bash
bash famap_pipeline.sh <BIDS_ROOT>
```

Its processing scripts are located in `famap_steps/`. This processes all subjects in the dataset, so no subject ID is required.

### Defacing
The documented workflow begins **after defacing**. Before running the pipeline, the MPRAGE image from each session must be defaced with [PyDeface](https://github.com/poldracklab/pydeface). In this workflow, PyDeface is applied only to the MPRAGE images.

### Common functions
The file `common_functions.sh` contains shell functions shared by multiple pipeline scripts. Within each pipeline directory, scripts are numbered according to their intended execution order. Individual steps can be run separately when needed, although running the corresponding pipeline script is recommended for the standard workflow. The container paths are defined here.

### Script naming
Some scripts have similar filename prefixes because one script calls another. These are separate scripts with different purposes; inspect the scripts themselves for the exact calling relationship.

### Other directories

- `misc/` contains miscellaneous scripts and files, including Python environment files and files required by the pRF workflow.
- `dr_samsrf/` contains the modified SamSrf code used in this project.
- `plotting/` contains scripts for plotting the results.

Some workflow steps are used for file discovery or cleanup and are not listed below. Refer to the scripts in each step directory for the complete implementation.

## Processing pipelines

### 1. Functional preprocessing

Run with:

```bash
bash func_pipeline.sh <BIDS_ROOT> <SUBJECT>
```

See `func_steps/` for the complete set of steps. The main processing stages include:

- Dummy-scan removal using FSL: `f2_dummy_removal.py`
- Motion correction using SPM25: `f3_run_mo-co.sh`
- Quality-assurance metric calculation using Python: `f6_run_qa.sh`
- Distortion correction using TOPUP: `f7_topup.sh`

### 2. Anatomical preprocessing

Run with:

```bash
bash anat_pipeline.sh <BIDS_ROOT> <SUBJECT>
```

Anatomical preprocessing can be run in parallel with functional preprocessing. The main processing stages include:

- Bias-field correction using SPM25: `a1_bias_correction.sh`
- Skull stripping using SynthStrip: `a2_skull_stripping.sh`
- Template creation using ANTs: `a3_template_creation.sh`
- Surface reconstruction using FreeSurfer: `a4_reconall.sh`
- Benson atlas creation using Python: `a5_benson14.sh`

The Benson atlas step requires the `fsaverage` template to be present in `derivatives/freesurfer/`. It also requires the appropriate Python environment; see [Python environments](#python-environments).

### 3. Co-registration

Run with:

```bash
bash coreg_pipeline.sh <BIDS_ROOT> <SUBJECT>
```

The main processing stages include:

- Boundary-based registration using FreeSurfer: `c0_bbr.sh`
- Surface projection using FreeSurfer: `c1_vol2surf.sh`

### 4. pRF modelling

Run with:

```bash
bash samsrf_pipeline.sh <BIDS_ROOT> <SUBJECT>
```

Before starting the pRF pipeline:

1. Copy `aperture.mat` and `aperture_vec.mat` from `misc/` to `derivatives/samsrf/aperture/`. If necessary, create `aperture_vec.mat` using `s_aperture_creation.m` in `samsrf_steps/`. The same aperture files are used for all subjects.
2. Copy `fit_2d_Gaussian_pRF.m` from `misc/` to `derivatives/samsrf/sub-0x/fit_2d_Gaussian_pRF.m` for each subject. The same fitting function is used for all subjects.

The main processing stages include:

- Conversion of MGH files to SamSrf files: `s0_run_occ_aprtr_mgh2srf.sh`
- pRF model fitting with SamSrf: `s1_run_fit_prf.sh`

### 5. Flip-angle-map processing

The FAMAP workflow is separate from `main.sh` and should be run after anatomical preprocessing:

```bash
bash famap_pipeline.sh
```

See `famap_steps/` for the complete set of steps. The main processing stages include:

- Flip-angle-map rescaling: `fa0_run_rescale.sh`
- Coregistration of flip-angle maps to the T1 image using FreeSurfer: `fa1_run_coreg.sh`
- Conversion of MGH files to SamSrf files: `fa2_run_mgh2srf.sh`

## Vessel reconstruction

Vessel probability map creation is not part of the processing pipelines described above. Vessel maps were generated separately using the following workflow:

1. Manual reconstruction of the ME-GRE data.
2. Coil combination.
3. Processing with [CLEARSWI](https://github.com/korbinian90/CLEARSWI.jl).
4. Generation of vessel-probability maps with [VesSynth](https://github.com/chiara-mauri/VesSynth).


## Software requirements

The following software versions were used for preprocessing and analysis:

| Software | Version |
|---|---|
| SPM | 25.01.02 |
| FreeSurfer | 8.1.0 |
| FSL | 6.0.7.16 |
| ANTs | 2.6.0 |
| PyDeface | 2.0.2 |
| MATLAB | R2024b |
| SamSrfX | 10.201 |

### Containers

The required containers are not included in this repository. Store them in a separate directory and update the container paths in `common_functions.sh` before running the pipeline.

The containers used for this project were obtained from [Neurodesk](https://github.com/neurodesk):

- [FreeSurfer 8.1.0](https://github.com/neurodesk/neurocontainers/pkgs/container/freesurfer_8.1.0), pulled on 2025-11-13.
- [ANTs 2.6.0](https://github.com/neurodesk/neurocontainers/pkgs/container/ants_2.6.0), build 20250424.
- [FSL 6.0.7.16](https://github.com/neurodesk/neurocontainers/pkgs/container/fsl_6.0.7.16), build 20250131.

### Other software

- [PyDeface 2.0.2](https://github.com/poldracklab/pydeface), obtained on 2026-04-04. DOI: [10.5281/zenodo.6856482](https://doi.org/10.5281/zenodo.6856482).
- [SamSrfX 10.201](https://github.com/samsrf/samsrf), commit `85e3609`.

The SamSrfX source was downloaded with:

```bash
curl -L -o samsrf-85e3609.zip \
  https://github.com/samsrf/samsrf/archive/85e36097b37c50a5b395a0eef9e62f08e69da468.zip
```

Minor modifications were made to SamSrfX. The modified code is included in `dr_samsrf/`.

## Python environments

The Conda environment files are provided in `misc/`.

Create the main environment from the project root with:

```bash
conda env create --file misc/prf_pipeline.yml
conda activate prf_pipeline
```

The Benson atlas step requires a separate environment:

```bash
conda env create --file misc/benson_atlas.yml
conda activate benson_atlas
```


## Running individual steps

To run a complete workflow, use the relevant pipeline entry point. To rerun or debug a single processing stage, enter the corresponding step directory and run the numbered script directly. Check the script first for required inputs, environment variables, and configuration paths.

For example:

```bash
cd func_steps
bash f7_topup.sh <BIDS_root> <SUBJECT> <SESSION> <FSL_CONTAINER_PATH>
```

The exact command may differ if a script is intended to be sourced rather than executed directly; consult the script header and its callers before running it independently.
