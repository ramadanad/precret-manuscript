function s0_mgh2srf_all(workingDir, projFrac, outputDir)
    % was once called mghAnalysis2

    % Process all MGH files in a folder and convert them to surface files
    % Groups files by hemisphere and sequence only (4 groups total)
    % Combines all runs from all sessionsfor each group into a single output file

    %
    % Inputs:
    %   workingDir: Full path to folder containing MGH files (e.g., /path/to/vol2surf)
    %   projFrac: (optional) projFrac folder to process (default: 'projFrac-0p5')
    %   outputDir: (optional) destination folder for output .mat files
    %              (default: workingDir)
    %
    % Example usage:
    %   s0_mgh2srf_all('/path/to/freesurfer/sub-01')
    %   s0_mgh2srf_all('/path/to/freesurfer/sub-01', 'projFrac-0p5')
    %   s0_mgh2srf_all('/path/to/freesurfer/sub-01', 'projFrac-1')
    %   s0_mgh2srf_all('/path/to/freesurfer/sub-01', 'projFrac-1', '/path/to/samsrf/sub-01')
    %
    % File naming convention expected:
    %   {lh,rh}_sub-XX_task-prf_run-ZZ_acq-{bssfp,epi}_projFrac-0p5.mgh
    %
    % Output groups (e.g., for projFrac-0p5):
    %   lh_sub-XX_task-prf_run-all_acq-bssfp_projFrac-0p5.mat
    %   lh_sub-XX_task-prf_run-all_acq-epi_projFrac-0p5.mat
    %   rh_sub-XX_task-prf_run-all_acq-bssfp_projFrac-0p5.mat
    %   rh_sub-XX_task-prf_run-all_acq-epi_projFrac-0p5.mat

    % Validate input
    if ~ischar(workingDir) && ~isstring(workingDir)
        error('workingDir must be a string or character array');
    end
    if ~isfolder(workingDir)
        error('Working directory does not exist: %s', workingDir);
    end
    
    % Set default projFrac if not provided
    if nargin < 2 || isempty(projFrac)
        projFrac = 'projFrac-0p5';
    end
    if ~ischar(projFrac) && ~isstring(projFrac)
        error('projFrac must be a string or character array');
    end
    projFrac = char(projFrac);
    if ~startsWith(projFrac, 'projFrac-')
        error('projFrac must start with ''projFrac-'' (e.g., projFrac-0p5)');
    end
    projFracBody = regexprep(projFrac, '^projFrac-', '');

    % Set default outputDir if not provided
    if nargin < 3 || isempty(outputDir)
        outputDir = workingDir;
    end
    if ~ischar(outputDir) && ~isstring(outputDir)
        error('outputDir must be a string or character array');
    end
    if ~isfolder(outputDir)
        mkdir(outputDir);
    end

    [~, subject] = fileparts(workingDir);

    anatDir = [outputDir '..' filesep 'anatomy' filesep]
    
    % Change to working directory
    original_dir = pwd;
    cd(workingDir);
       
    try
        % Find all MGH files in the projFrac subfolder
        mgh_path = fullfile('vol2surf', projFrac);
        if ~isfolder(mgh_path)
            error('Projection folder not found: %s', mgh_path);
        end
        mgh_files = dir(fullfile(mgh_path, '*.mgh'));
        activeProjFolder = erase(mgh_path, [filesep 'vol2surf' filesep]);
        
        if isempty(mgh_files)
            error('No MGH files found in %s', mgh_path);
        end
        
        fprintf('Found %d MGH files in %s\n\n', length(mgh_files), mgh_path);
        
        % Initialize 4 groups: lh_bssfp, lh_epi, rh_bssfp, rh_epi
        groups = struct();
        groups.lh_bssfp = {};
        groups.lh_epi = {};
        groups.rh_bssfp = {};
        groups.rh_epi = {};
        
        % Parse filenames and assign to groups
        for i = 1:length(mgh_files)
            filename = mgh_files(i).name;
            
            % Parse filename: {lh,rh}_sub-XX_ses-YY_task-prf_run-ZZ_acq-{bssfp,epi}_projFrac-0p5.mgh
            pattern = '^(lh|rh)_(sub-[^_]+)_(ses-[^_]+)_task-prf_run-[^_]+_acq-(bssfp|epi)_projFrac-([^.]+)\.mgh$';
            tokens = regexp(filename, pattern, 'tokens');
            
            if isempty(tokens)
                warning('Could not parse filename: %s (skipping)', filename);
                continue;
            end
            
            tokens = tokens{1};
            hemi = tokens{1};      % lh or rh
            seq = tokens{4};       % bssfp or epi
            
            % Create group key
            group_key = sprintf('%s_%s', hemi, seq);
            
            % Add filename to appropriate group
            groups.(group_key) = [groups.(group_key); {filename}];
            
            fprintf('  %s → %s\n', filename, group_key);
        end
        
        fprintf('\n======================================\n');
        fprintf('Processing 4 groups:\n');
        fprintf('======================================\n\n');
        
        % Process each group
        group_names = {'lh_bssfp', 'lh_epi', 'rh_bssfp', 'rh_epi'};
        
        for g = 1:length(group_names)
            group_name = group_names{g};
            filenames = groups.(group_name);
            
            if isempty(filenames)
                fprintf('%s: No files found\n\n', group_name);
                continue;
            end
            
            fprintf('Group: %s\n', group_name);
            fprintf('  Files (%d):\n', length(filenames));
            for f = 1:length(filenames)
                fprintf('    %s\n', filenames{f});
            end
            
            % Remove .mgh extension for mgh2srf
            mgh_files_noext = cellfun(@(x) x(1:end-4), filenames, 'UniformOutput', false);

            
            % Convert MGH to surface format
            mgh2srf(pwd, mgh_files_noext, activeProjFolder, 1, 1, anatDir); 

            % avrg 0 = separate
            % avrg 1 = average
            % avrg 2 = concatenate
            % separate group_name by hemi and seq again
            hemi = group_name(1:2);
            seq = group_name(4:end);
            
            % Create output filename with projFrac
            output_file = sprintf('%s_%s_task-prf_run-all_acq-%s_projFrac-%s.mat', hemi, subject, seq, projFracBody);
        
            % Move and rename the first file to the output directory
            src_file = [mgh_files_noext{1}, '.mat'];
            dst_file = fullfile(outputDir, output_file);
            movefile(src_file, dst_file);
            fprintf('  Saved: %s\n', dst_file);
            
        end
        
        fprintf('======================================\n');
        fprintf('Processing complete!\n');
        fprintf('======================================\n');
        
    catch ME
        % Return to original directory and re-throw error
        cd(original_dir);
        rethrow(ME);
    end
    
    % Return to original directory
    cd(original_dir);


% function being used here

function mgh2srf(subjFSpath, mghFileList, projFrac, nrmls, avrg, anatpath)

%%%%%%%%%%%%%%%%%%%%%%
% Inputs
%%%%%%%%%%%%%%%%%%%%%%
%   SubjPath (string) - Subject directory path
%   fileList (cell array) - List of 4D-NIfTI/MGH/GII files with full paths
%%%%%%%%%%%%%%%%%%%%%%
% Normalization:
%%%%%%%%%%%%%%%%%%%%%%
% nrmls = 1; % z-score
% nrmls = -1; % Detrend only
% nrmls = 0; % No normalization
%%%%%%%%%%%%%%%%%%%%%%
% Averaging:
%%%%%%%%%%%%%%%%%%%%%%
% avrg = 0; % 'Separate'
% avrg = 1; % 'Average'
% avrg = 2; % 'Concatenate'
%%%%%%%%%%%%%%%%%%%%%%
% EXAMPLE 
%%%%%%%%%%%%%%%%%%%%%%
% mghFiles = {'rh_mask_coreg_realign_bssfp_run01_surf', 'rh_mask_coreg_realign_bssfp_run02_surf'};
% mgh2srf(pwd, mghFiles, 1, 1)
%%%%%%%%%%%%%%%%%%%%%%
% if it is just one run
% mghFiles = {'rh_mask_coreg_realign_bssfp_run01_surf'};
% mgh2srf(pwd, mghFiles, 1)
%%%%%%%%%%%%%%%%%%%%%%
% make sure the mghFiles are in pwd/func !!!!!



% Validate inputs
if nargin < 2
    error('All three input arguments (CurrPath, subjFSpath, mghFileList) are required.');
end

% Define surface folder path
hemfolder = [subjFSpath filesep 'surf' filesep];
fprintf('Surface folder: %s\n', hemfolder);

% Check if files were provided
if isempty(mghFileList)
    error('No functional scans provided.');
end

% Prepare functional file list without extensions
ef = cell(1, length(mghFileList));
for i = 1:length(mghFileList)
    % Add path & drop extension
    [~, fileName, ~] = fileparts(mghFileList{i});
    ef{i} = [pwd filesep projFrac filesep fileName];
end


%% How to handle multiple runs?
if length(ef) > 1
    if nargin < 4
        error('When multiple files are loaded, varargin must have a length of 4.');
    end
else
    avrg = 0;
end

if avrg == 0% Project each run separately
    for i = 1:length(ef)
        [~,fn] = fileparts(ef{i});
        hemsurf = fn(1:2); % Use hemisphere as indicated by -this- file name!
        samsrf_mgh2srf(ef{i}, [hemfolder hemsurf], nrmls); % MGH files
    end
elseif avrg == 1% Average all the runs after projection
    [~,fn] = fileparts(ef{1});
    hemsurf = fn(1:2); % Use hemisphere as indicated by -first- file name!
    samsrf_mgh2srf(ef, [hemfolder hemsurf], nrmls, true, true, anatpath); % MGH files
elseif avrg == 2% Concatenate all the runs after projection
    [~,fn] = fileparts(ef{1});
    hemsurf = fn(1:2); % Use hemisphere as indicated by -first- file name!
    samsrf_mgh2srf(ef, [hemfolder hemsurf], nrmls, false, true, anatpath); % MGH files
end
end

end
