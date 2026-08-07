function s0_occ_mgh2srf(prf_dir, subject)

% Prepare the data for pRF modeling using the samsrf toolbox.
% It performs the following steps:
%       1. Sets up the file paths and parameters
%       2. Creates the occipital ROI for each hemisphere
%       3. Runs s0_mgh2srf_all which converts the mgh files in vol2surf to samsrf Srf mat files

% Example:
% prf_dir = '/home/dramadan/prf_bids_nyx/'      % on sneezewort
% prf_dir = '/home/dramadan/data/prf_bids/'     % on nyx
% subject = 'sub-03'

fs_dir = [prf_dir filesep 'derivatives' filesep 'freesurfer' filesep subject];

% first check the existence of vol2surf folder in fs_dir
if ~isfolder([fs_dir filesep 'vol2surf'])
    error('vol2surf folder does not exist in %s. Please run bbr_vol2surf first.', fs_dir);
end

samsrf_dir = [prf_dir filesep 'derivatives' filesep 'samsrf' filesep subject];
if ~isfolder(samsrf_dir)
    mkdir(samsrf_dir);
end

cd(samsrf_dir);

%% Create the occipital ROI
% so that calculation doesn't take forever
% get the occ_roi for each hemisphere
disp('Creating occipital ROI for each hemisphere...');
MakeOccRoi([fs_dir filesep 'surf']);

%% Convert mgh files to samsrf Srf mat files

outputDir = [samsrf_dir filesep 'prf_fits' filesep];
mkdir(outputDir);

% and now get the runs you want from the vol2surf folder
disp('Converting mgh files to samsrf Srf mat files');
s0_mgh2srf_all(fs_dir, 'projFrac-0p5', outputDir);


end

