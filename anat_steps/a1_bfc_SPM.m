% MATLAB Script for Bias Field Correction using SPM12 (BIDS format)
% Usage: an_BFCorrection(<input_nii_or_nii_gz>, <output_nii>)
% Ensure SPM12 is installed and added to your MATLAB path

function an_BFCorrection(input_nifti, output_nifti)
    try
        fprintf('Starting bias field correction (BIDS version)...\n');

        if nargin ~= 2
            error('an_BFCorrection requires 2 arguments: input_nifti and output_nifti.');
        end

        input_nifti = char(input_nifti);
        output_nifti = char(output_nifti);

        if ~exist(input_nifti, 'file')
            error('Input NIfTI not found: %s', input_nifti);
        end

        [output_dir, ~, ~] = fileparts(output_nifti);
        if ~isempty(output_dir) && ~exist(output_dir, 'dir')
            mkdir(output_dir);
        end
        
        % Check if SPM is available
        fprintf('Checking for SPM...\n');
        spm_path = which('spm');
        if isempty(spm_path)
            error('SPM12 is not found. Please add it to your MATLAB path.');
        else
            fprintf('SPM found at: %s\n', spm_path);
        end

        % Process in an isolated temporary workspace so only final output
        % is written to output_nifti.
        temp_dir = tempname;
        mkdir(temp_dir);
        cleanup_obj = onCleanup(@() rmdir(temp_dir, 's'));

        local_input = fullfile(temp_dir, 'input_T1w.nii');
        if endsWith(input_nifti, '.nii.gz')
            gunzip(input_nifti, temp_dir);
            [~, base_name, ~] = fileparts(input_nifti);
            movefile(fullfile(temp_dir, base_name), local_input, 'f');
        elseif endsWith(input_nifti, '.nii')
            copyfile(input_nifti, local_input, 'f');
        else
            error('Input must end with .nii or .nii.gz: %s', input_nifti);
        end

        % Initialize SPM
        fprintf('Initializing SPM...\n');
        spm('defaults', 'FMRI');
        spm_jobman('initcfg');
        fprintf('SPM initialized successfully.\n');

        % SPM batch for bias field correction
        fprintf('Setting up SPM batch job...\n');
        matlabbatch = [];
        matlabbatch{1}.spm.spatial.preproc.channel.vols = {local_input};
        matlabbatch{1}.spm.spatial.preproc.channel.biasreg = 0.001; % Medium regularization
        matlabbatch{1}.spm.spatial.preproc.channel.biasfwhm = 40;   % FWHM 40 mm
        matlabbatch{1}.spm.spatial.preproc.channel.write = [0 1];  % Save bias-corrected image only
        
        % Run the job
        fprintf('Running SPM job...\n');
        spm_jobman('run', matlabbatch);

        local_output = fullfile(temp_dir, 'minput_T1w.nii');
        if ~exist(local_output, 'file')
            error('Expected SPM output not found: %s', local_output);
        end

        copyfile(local_output, output_nifti, 'f');
        fprintf('Bias field corrected image written to: %s\n', output_nifti);

        clear cleanup_obj;
        
    catch ME
        fprintf('Error in an_BFCorrection: %s\n', ME.message);
        fprintf('Error occurred in: %s at line %d\n', ME.stack(1).name, ME.stack(1).line);
        rethrow(ME);
    end
end
