function s_aperture_creation(prf_dir)

% This step should be performed before running the samsrf pipeline
% The aperture file for each subject is the same
% This converts the aperture files to the format needed for samsrf fitting

% where is the samsrf deriv directory?
samsrf_dir = [prf_dir filesep 'derivatives' filesep 'samsrf' filesep];
if ~isfolder(samsrf_dir)
    mkdir(samsrf_dir);
end
% get the aperture
apertureDir = [samsrf_dir filesep 'aperture'];

aperture_files = dir(fullfile(apertureDir, '*.mat'));
if isempty(aperture_files)
    error('No aperture .mat file found in %s. Please place the aperture file there. You can find it in the misc folder', apertureDir);
else 
    disp('Aperture .mat file found:');
    disp({aperture_files.name}');
end

cd(apertureDir);

% Get the .mat file in apertureDir (should be only one)
aperture = {aperture_files(1).name};  % Get as cell array with just filename (already in apertureDir)

% display the aperture file being used
disp('********************************************************')
disp('********************************************************')
disp('********************************************************')
disp(['Using aperture file: ' aperture{1}]);
disp('********************************************************')
disp('********************************************************')
disp('********************************************************')

disp('Creating aperture files for samsrf');
getAperture(aperture, apertureDir);


function ApName = getAperture(files, outPath)
    % Create apertures from result files without GUI

    if isempty(files)
        error('No files provided!');
    end

    ApFrm = [];
    nvols = 0;
    for i = 1:length(files)
        Res = load(fullfile(pwd, files{i}));
        if ~isfield(Res, 'ApFrm')
            error('File %s contains no apertures!', files{i});
        end
        ApFrm(:,:,nvols+1:nvols+size(Res.ApFrm,3)) = Res.ApFrm;
        nvols = nvols + size(Res.ApFrm,3);
    end

    fprintf("The number of volumes is %d \n", nvols)

    ApName = 'aperture.mat';

    if nargin < 2 || isempty(outPath)
        outPath = pwd;
    end
    save(fullfile(outPath, ApName), 'ApFrm');
end

end