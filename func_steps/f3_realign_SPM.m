function f3_realign_SPM(sequence, subj_num, ses_num)
    %A function that does the motion correction for you
    %Here the functional data are realigned to the mean volume of each run

    %Example inputs:
    %sequence = 'bssfp'
    %subj_num = 1 (integer)
    %ses_num = 1 (integer)
    %This will realign each run to the mean of that run
    %Files should be named: sub-01_ses-01_task-prf_run-01_acq-bssfp_desc-dummyRemoval.nii

    data_path = pwd;

    % Create BIDS-compliant filename pattern
    subj_str = sprintf('sub-%02d', subj_num);
    ses_str = sprintf('ses-%02d', ses_num);

    func_img_pattern = sprintf('%s_%s_task-prf_run-%%02d_acq-%s_desc-dummyRemoval_changedheader', subj_str, ses_str, sequence);

    disp(['Processing files with pattern: ' func_img_pattern]);

    % For EPI sequences, also check for reverse phase encoding file
    rev_pe_pattern = '';
    if strcmp(sequence, 'epi')
        rev_pe_pattern = sprintf('%s_%s_dir-PA_%s_desc-dummyRemoval_changedheader', subj_str, ses_str, sequence);
        disp(['Also processing reverse PE file pattern: ' rev_pe_pattern]);
    end
    

    %Just start by opening up the Graphics window, because you will def need it  
    fg = spm_figure('GetWin','Graphics');
    
    %create vol which is the fourth dimension of the functional image, and
    %frankly how many volumes you have.. The more the merrier ;) and of
    %course the longer it will take!
    first_run_file = sprintf(func_img_pattern, 1);
    first_run_file = [first_run_file '.nii'];
    vol = niftiinfo(first_run_file).ImageSize(4);

    % Perform realignment on each run separately
    disp('Realigning each run separately...');
    run_idx = 1;
    while true
        run_file = sprintf(func_img_pattern, run_idx);
        run_file = [run_file '.nii'];
        output_file = sprintf('rs_%s_%s_task-prf_run-%02d_acq-%s_desc-dummyRemoval.nii', subj_str, ses_str, run_idx, sequence);
        if ~isfile(run_file)
        break;
        end
        if isfile(output_file)
        fprintf('Output for run %02d already exists. Skipping realignment.\n', run_idx);
        else
        % Select images for the current run
        P = spm_select('ExtList', data_path, run_file, 1:vol);

        % Realign the current run
        flags = struct('quality', 1, 'fwhm', 0, 'sep', 0.8, 'rtm', 1, 'interp', 2);
        spm_realign(P, flags);

        % Reslice the current run
        resl_flags = struct('prefix', 'rs_');
        spm_reslice(P, resl_flags);

        % Export diagrams for the current run
        pdf_name = sprintf('%s_%s_task-prf_run-%02d_acq-%s_desc-dummyRemoval-plotMotionParams.pdf', subj_str, ses_str, run_idx, sequence);
        saveas(fg, pdf_name);
        fprintf('Realignment and reslicing completed for run %02d.\n', run_idx);
        end
        run_idx = run_idx + 1;
    end
        
    % For EPI sequences, also process the reverse PE file separately
    if strcmp(sequence, 'epi') && ~isempty(rev_pe_pattern)
        rev_pe_file = [rev_pe_pattern '.nii'];
        rev_pe_output = sprintf('rs_%s.nii', rev_pe_pattern);
        
        if isfile(rev_pe_file)
            if isfile(rev_pe_output)
                fprintf('Reverse PE output already exists. Skipping realignment.\n');
            else
                disp('Processing reverse phase encoding EPI file...');
                % Get volume count for reverse PE file
                rev_pe_vol = niftiinfo(rev_pe_file).ImageSize(4);
                
                % Select images for reverse PE file
                P_rev = spm_select('ExtList', data_path, rev_pe_file, 1:rev_pe_vol);
                
                % Realign the reverse PE file
                flags = struct('quality', 1, 'fwhm', 0, 'sep', 0.8, 'rtm', 1, 'interp', 2);
                spm_realign(P_rev, flags);
                
                % Reslice the reverse PE file
                resl_flags = struct('prefix', 'rs_');
                spm_reslice(P_rev, resl_flags);
                
                fprintf('Reverse PE file realignment completed.\n');
            end
        else
            fprintf('Warning: Reverse PE file %s not found.\n', rev_pe_file);
        end
    end
  
end