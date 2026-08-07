function disp_fa_maps(prf_dir, subject)

    addpath('../dr_samsrf');

    deriv_dir =     [prf_dir filesep 'derivatives'];
    samsrf_dir =    [deriv_dir filesep 'samsrf' filesep subject];
    fs_dir =        [deriv_dir filesep 'freesurfer' filesep subject];
    label_dir =     [fs_dir filesep 'label' filesep];

    hemis =         {'lh', 'rh'}; % has to be in that order, lh and then rh!
    sessions =      {'ses-01', 'ses-02', 'ses-03', 'ses-04', 'ses-05', 'ses-06', 'ses-07'}; %
    proj_fracs =    {'projFrac-0p5'};

    inputfolder =   [samsrf_dir filesep 'prf_fits']; 
    
    cd(inputfolder);

    
    CamViews = {    {[40 -22 3]       [-40 -22 3]  }, ... % sub-01 [14 -15 5.3]       [-10 -15 5.3]
                    {[11 -7 4]        [-10 -15 4]  }, ... % sub-02 needs adjustment!
                    {[12 -7 4]        [-10 -15 4]  }, ... % sub-03 needs adjustment!
                    {[12 -8 4]        [-7 -10 4]   }, ... % sub-04 needs adjustment!
                    {[15 -15 3.5]     [-9 -15 3.5] }, ... % sub-05 needs adjustment!
                    {[13 -20 4.5]     [-10 -25 4.5]}};    % sub-06 needs adjustment!
    
    s = char(subject);
    sub = str2double(s(end));
    Para.CamView =  CamViews{sub};
    
    PathColor = [1 1 1];
    Para.Transparency        = 0;
    %%% 0 = turn off transparency
    

    Para.Mesh                = 'inflated';
    Para.EccenRange          = [0 Inf];
    Para.NR2ThreshGen        = 0;  %%% Note that "Gen" refers to general.
   
    Para.FAThresh            = [0 100];
    

    for sess = 1:length(sessions)
        session = sessions{sess};
        for h = 1:length(hemis)
            hemi = hemis{h};
            CurrCamView = Para.CamView{h};


            for p = 1:length(proj_fracs)
                pf = proj_fracs{p};


                Labels = {[label_dir hemi '.bensonV1_ecc_thresh0.label'], [label_dir hemi '.bensonV1_ecc_thresh2.label'], [label_dir hemi '.bensonV1_ecc_thresh4.label']};

                input = [hemi '_' subject '_FAmap_desc-normalized_' pf]; %'lh_sub-01_task-prf_run-all_acq_bssfp_projFrac-0p5_fitted2DGaussian';
                % input = [hemi '_' subject '_' session '_FAmap_normalized']; % ghaba2 mo2akkat
                inputfile = fullfile(inputfolder, [input '.mat']);
                disp(['Processing ' input '...']);

                inputSrf = load(inputfile).Srf;
                outputfolder = [samsrf_dir filesep 'dispmaps/'];


                % fake high noise ceiling so you can plot everything!
                % this is necessary when visualizing the FA maps
                % inputSrf.Noise_Ceiling(isnan(inputSrf.Noise_Ceiling)) = 1;


                File.Srf = samsrf_expand_srf(inputSrf);
                

                Para.Threshold           = {...
                        [Para.NR2ThreshGen Para.FAThresh            Para.EccenRange Para.Transparency]; ...
                        };

                Para.MapType             = {...
                        'Volume #1' ...
                        };

                for i_mapt = 1:size(Para.MapType,2)

                    CurrThreshold = Para.Threshold{i_mapt};
                    CurrMapType   = Para.MapType{i_mapt};

                    
                    figure;
                    dr_samsrf_surf(File.Srf, Para.Mesh, CurrThreshold,...
                            [Labels, [NaN PathColor]], CurrCamView, CurrMapType);

                    % ONLY if zooming in...
                    if strcmp(hemi, 'lh')   
                        ax = gca;
                        axis(ax,'tight');
                        xl = xlim(ax);
                        xlim(ax, [-25, -10]);   % keep only left part 
                        yl = ylim(ax);
                        ylim(ax, [-100, 0]);   % move up in y
                        camzoom(ax, 3.5);

                    elseif strcmp(hemi, 'rh')
                        ax = gca;
                        axis(ax,'tight');
                        xl = xlim(ax);
                        xlim(ax, [13, 28]);   % keep only right part
                        yl = ylim(ax);
                        ylim(ax, [-100, 0]);   % move up in y
                        camzoom(ax, 3.5);
                    end

                    
                    % if output folder doesn't exist, create it
                    if ~exist(outputfolder, 'dir')
                        mkdir(outputfolder);
                    end
                    % save figure
                    cd(outputfolder);
                    saveas(gcf, sprintf('%s_FAmap.png', input));
                    % break
                end
            end
        end
    end
end