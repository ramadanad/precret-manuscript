function s1_fit_prf(prf_dir, subject)
% Fit the pRF model using the samsrf toolbox.

% Example:
% prf_dir = '/home/dramadan/prf_bids_nyx/'      % on sneezewort
% prf_dir = '/home/dramadan/data/prf_bids/'     % on nyx
% subject = 'sub-03'

% Set up parameters

deriv_dir = [prf_dir filesep 'derivatives'];
samsrf_dir = [deriv_dir filesep 'samsrf'];
samsrf_subj_dir = [samsrf_dir filesep subject];
cd(samsrf_subj_dir);


% Define processing parameters
% proj_frac_tokens = {'projFrac-0p5', 'projFrac-0', 'projFrac-0p25', 'projFrac-0p75', 'projFrac-1'};
proj_frac_tokens = {'projFrac-0p5'};
hemis = {'lh', 'rh'};
sequences = {'bssfp', 'epi'};


aperture = [samsrf_dir filesep 'aperture' filesep 'aperture'];
% aperture = '~/data/prf_bids/derivatives/samsrf/aperture/aperture.mat';

for h = 1:length(hemis)
    hemi = hemis{h};
    roi = ['../' hemi '_occ'];
    % Loop over projection fractions
    for p = 1:length(proj_frac_tokens)
        pf = proj_frac_tokens{p};
        
        % Process both bSSFP and EPI
        for s = 1:length(sequences)
            seq = sequences{s};
            % volumeTR depends on the sequence, and is 4.206 for bssfp and 4.2 for epi
            if strcmp(seq, 'bssfp')
                volumeTR = 4.206;
            elseif strcmp(seq, 'epi')
                volumeTR = 4.2;
            else
                error('Unknown sequence type: %s', seq);
            end

            input_pattern = sprintf('%s_%s_task-prf_run-all_acq-%s_%s.mat', hemi, subject, seq, pf);
            matches = dir(fullfile('prf_fits', input_pattern));

            if isempty(matches)
                error('No input file found for pattern: %s', input_pattern);
                continue;
            else
                [~, input_name, ~] = fileparts(matches(1).name);
            end
            output_name = sprintf('%s_task-prf_run-all_acq-%s_%s_fitted2DGaussian', subject, seq, pf);
            results_file = ['prf_fits' filesep hemi '_' output_name '.mat'];

            % Check if output already exists, skip if it does
            if isfile(results_file)
                disp(['Skipping ' input_name ' Output file ' results_file ' already exists!']);
            else
                % Ensure fitting function is available before running.
                if ~exist('fit_2d_Gaussian_pRF', 'file')
                    error(['fit_2d_Gaussian_pRF function not found in ' samsrf_subj_dir '. Copy it from misc folder...']);
                end
                % example input_name: lh_sub-03_ses-01_task-prf_run-all_acq-bssfp_projFrac-0p5
                fit_2d_Gaussian_pRF('prf_fits', input_name, roi, output_name, aperture, volumeTR);
            end
        end
    end
end

end