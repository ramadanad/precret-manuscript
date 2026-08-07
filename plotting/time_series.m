function time_series(prf_dir, subject)

    % This is how you compare the predicted and observed time course 
    % of the same voxel


    addpath('../dr_samsrf');

    cd([prf_dir filesep 'derivatives/samsrf' filesep subject filesep 'prf_fits']);
    timeseries_dir = [prf_dir filesep 'derivatives/samsrf' filesep subject filesep 'timeseries'];
    label_dir = [prf_dir filesep 'derivatives/freesurfer' filesep subject filesep 'label'];

    if ~exist(timeseries_dir, 'dir')
        mkdir(timeseries_dir);
    end
    
    hemis = {'lh', 'rh'}; 
    sequences = {'epi', 'bssfp'};

    for s = 1:length(sequences)
        seq = sequences{s};
        for h = 1:length(hemis)
            hemi = hemis{h};

            file = sprintf('%s_%s_task-prf_run-all_acq-%s_projFrac-0p5_fitted2DGaussian', hemi, subject, seq);
            load(file);
            Label = [label_dir filesep hemi '.bensonV1_ecc_thresh4'];

            [vtx_best, vtx_worst] = vertices_for_time_series(file, Label);


            for v = 1:length(vtx_best)
                vtx = vtx_best(v);
                dr_samsrf_fitvsobs(Srf, Model, vtx);
                ylim([-2, 2.5]);
                yticks([-1, 0, 1, 2]);
                xticks([200, 400, 600]);
                [~, name, ~] = fileparts(file);
                filename = sprintf('%s/%s_good_vtx%d.svg', timeseries_dir, name, vtx);
                disp('Saving figure..');
                saveas(gcf, filename, 'svg');
                close(gcf);
                disp('Done');
            end

            for v = 1:length(vtx_worst)
                vtx = vtx_worst(v);
                dr_samsrf_fitvsobs(Srf, Model, vtx);
                ylim([-2, 2.5]);
                yticks([-1, 0, 1, 2]);
                xticks([200, 400, 600]);
                [~, name, ~] = fileparts(file);
                filename = sprintf('%s/%s_bad_vtx%d.svg', timeseries_dir, name, vtx);
                disp('Saving figure..');
                saveas(gcf, filename, 'svg');
                close(gcf);
                disp('Done');
            end
        end
    end
end




function [vtx_best, vtx_worst] = vertices_for_time_series(Srf_File, Label)
    load(Srf_File);
    Srf = samsrf_expand_srf(Srf);
    R2_values = Srf.Data(8,:);
    v1_4dva = samsrf_loadlabel(Label);
    R2_values_v1_4dva = R2_values(v1_4dva);

    % find all vertices in R2_values_v1_4dva that are greater than 0.6 and store their indices given in v1_4dva
    vertices_good = v1_4dva(R2_values_v1_4dva > 0.55);
    disp('Vertices with R2 > 0.55 in V1 (ecc < 4 dva):');
    disp(length(vertices_good));
    sorted_vertices_good = sort(vertices_good);
    num_vtx_g = min(5, length(sorted_vertices_good));
    vtx_best = sorted_vertices_good(end-(num_vtx_g-1):end);  % I know this is redundant, but it's a good sanity check to make sure that the vertices are sorted in ascending order
    % disp('Vertices with best R2 in V1 (ecc < 4 dva):');
    % disp(vtx_best); 
    disp('R2 values for best vertices:');
    disp(R2_values(vtx_best));

    % find all vertices between 0.25 and 0.3 and store their indices given in v1_4dva
    vertices_bad = v1_4dva(R2_values_v1_4dva > 0.25 & R2_values_v1_4dva <= 0.3);
    disp('Vertices with 0.25 < R2 <= 0.3 in V1 (ecc < 4 dva):');
    disp(length(vertices_bad));
    sorted_vertices_bad = sort(vertices_bad);
    num_vtx_b = min(5, length(sorted_vertices_bad));
    vtx_worst = sorted_vertices_bad(1:num_vtx_b);
    % disp('Worst vertices with 0.25 < R2 <= 0.3 in V1 (ecc < 4 dva):');
    % disp(vtx_worst);
    disp('R2 values for worst vertices:');
    disp(R2_values(vtx_worst));
end