function fa2_mgh2srf(workingDir, projFrac, outputDir)
    % was once called mghAnalysis2

    % Process all MGH files in a folder and convert them to surface files
    % Create the mean of all sessions for each hemisphere
    %
    % Inputs:
    %   workingDir: Full path to folder containing MGH files (e.g., /path/to/vol2surf)
    %   projFrac: (optional) projFrac folder to process (default: 'projFrac-0p5')
    %   outputDir: (optional) destination folder for output .mat files
    %              (default: workingDir)
    %

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
    disp(workingDir);

    anatDir = ['..' filesep 'anatomy' filesep]
    
    % Change to working directory
    original_dir = pwd;
    cd(workingDir);

    hemispheres = {'lh', 'rh'};
       
    try
        % Find all MGH files in the projFrac subfolder
        mgh_path = fullfile('vol2surf', projFrac);
        if ~isfolder(mgh_path)
            error('Projection folder not found: %s', mgh_path);
        end
        fa_mgh_files = dir(fullfile(mgh_path, '*FAmap_desc-normalized.mgh'));
        activeProjFolder = erase(mgh_path, [filesep 'vol2surf' filesep]);
        
        if isempty(fa_mgh_files)
            error('No FAmap MGH files found in %s', mgh_path);
        end
        
        fprintf('Found %d FA map MGH files in %s\n\n', length(fa_mgh_files), mgh_path);
        


        all_fa_files = cell(2, 1);  % column cell array: all_fa_files{1} for lh, all_fa_files{2} for rh
        for h = 1:2
            hemi = hemispheres{h};
            mask = false(length(fa_mgh_files), 1);
            for i = 1:length(fa_mgh_files)
                mask(i) = strncmp(fa_mgh_files(i).name, hemi, 2);
            end
            hemi_files = fa_mgh_files(mask);
            
            mgh_files = cell(1, length(hemi_files));
            for i = 1:length(hemi_files)
                [~, fileName, ~] = fileparts(hemi_files(i).name);
                mgh_files{i} = fileName;
                disp(fileName);
            end
       

            % Convert MGH to surface format
            mgh2srf(pwd, mgh_files, activeProjFolder, 0, 1, anatDir); 
            % avrg 0 = separate
            % avrg 1 = average
            % avrg 2 = concatenate
            

            % Create output filename with projFrac
            output_file = sprintf('%s_%s_FAmap_projFrac-%s.mat', hemi, subject, projFracBody);
        
            % Move and rename the first file to the output directory
            src_file = [mgh_files{1}, '.mat'];
            dst_file = fullfile(outputDir, output_file);
            % movefile(src_file, dst_file);
            fprintf('  Saved: %s\n', dst_file);
        
        
            fprintf('======================================\n');
            fprintf('Processing complete!\n');
            fprintf('======================================\n');
        end

    catch ME
        % Return to original directory and re-throw error
        cd(original_dir);
        rethrow(ME);
    end
    
    % Return to original directory
    cd(original_dir);





% Function used here to convert mgh2srf 

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