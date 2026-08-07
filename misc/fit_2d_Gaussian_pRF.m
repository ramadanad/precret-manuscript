function fit_2d_Gaussian_pRF(DataPath, SrfFiles, Roi, Output, Aperture, VolumeTR)
%
% Fits a standard 2D Gaussian pRF model
%
%	DataPath:	Path where the mapping data are
%   SrfFiles:   Cell array with SamSrf data files (without extension)
%   Roi:        ROI label to restrict analysis 
%

%% Mandatory parameters 
Model.Name = Output; % File name to indicate type of pRF model
Model.Prf_Function = @(P,ApWidth) prf_gaussian_rf(P(1), P(2), P(3), ApWidth); % Which pRF model function? 
Model.Param_Names = {'x0' 'y0' 'Sigma'}; % Names of parameters to be fitted
Model.Scaled_Param = [0 0 0]; % Which of these parameters are scaled 
Model.Only_Positive = [0 0 0]; % Which parameters must be positive? (refer to ModelHelp for issues with Nelder-Mead algorithm)
Model.Scaling_Factor = 4.6; % Scaling factor of the stimulus space (e.g. eccentricity) last updated on May 20th 2026
Model.TR = VolumeTR; %4.206 for bssfp and 4.2 for epi % Temporal resolution of stimulus Apertures (can be faster than scanner TR if downsampling predictions)
Model.Hrf = []; % HRF file or vector to use (0 = SPM canonical, [] = de Haas canonical), de Haas is used as it had a better fit
Model.Aperture_File = Aperture; % Aperture file must be defined!

%% Search grid for coarse fit 
% Some parameters are multiplied with scaling factor as this must be in stimulus space!
Model.Polar_Search_Space = true; % If true, parameter 1 & 2 are polar (in degrees) & eccentricity coordinates
Model.Param1 = 0 : 10 : 350; % Polar search grid
Model.Param2 = 2 .^ (-5 : 0.2 : 0.6) * Model.Scaling_Factor; % Eccentricity  search grid
Model.Param3 = 2 .^ (-5.6 : 0.2 : 1) * Model.Scaling_Factor; % Sigma search grid

%% Optional fine-fitting parameters
Model.Fine_Fit_Threshold = 1.0000e-100;
% Explanation from ss_samsrf_fit.m found here: https://github.com/Kriaese/manuscript-zoomprf/blob/main/toolboxes/ss_toolbox/ss_matlab/ss_samsrf/ss_samsrf_fit.m
%%% As for fine fit, optimization loop does not work when Pimg (parameters) are
%%% all NaN and corresponding Rimg is 0. This seems to happen when there are no 
%%% data points available for a certain vertex. This is why we need to have a 
%%% threshold but only for empirical data.
        
%% Go to data 
HomePath = pwd;
cd(DataPath);

%% Fit pRF model
MapFile = samsrf_fit_prf(Model, SrfFiles, Roi);

%% Return home
cd(HomePath); 
