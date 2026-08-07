def benson2roi(prfDIR, subject):

    import nibabel as nb
    import numpy as np
    from pathlib import Path

    prfDIR = Path(prfDIR)
    path2data = prfDIR / 'derivatives/freesurfer' / subject

    path2surf = path2data / 'surf'
    path2label = path2data / 'label'


    for hemi in ['lh', 'rh']:

        ecc = path2surf / f'{hemi}.benson14_eccen'
        varea = path2surf / f'{hemi}.benson14_varea'

        # first check if files exist
        if not ecc.exists():
            print(f'File {ecc} does not exist. Skipping {hemi}.')
            continue

        if not varea.exists():
            print(f'File {varea} does not exist. Skipping {hemi}.')
            continue

        # Load eccentricity
        eccen = nb.freesurfer.read_morph_data(str(ecc))

        # Load visual areas
        visarea = nb.freesurfer.read_morph_data(str(varea))

        # Load surface coordinates
        surf = path2surf / f'{hemi}.white'
        coords, faces = nb.freesurfer.read_geometry(str(surf))

        # first get vertices in V1 (where visarea == 1)
        label = np.where(visarea == 1)[0]

        # Mask: vertices in label AND 0.001 < ecc < 4
        for ecc_max in np.arange(0,5):
            if ecc_max == 0:
                roi_verts = label
            else:
                roi_verts = label[(eccen[label] > 0.001) & (eccen[label] < ecc_max)] 

            output = path2label / f'{hemi}.bensonV1_ecc_thresh{ecc_max}.label'

            # Save new label
            with open(output, 'w') as f:
                f.write('#!ascii label , from subject  \n')
                f.write(f'{len(roi_verts)}\n')

                for vertex in roi_verts:
                    x, y, z = coords[vertex]
                    f.write(
                        f'{vertex} '
                        f'{x:.6f} '
                        f'{y:.6f} '
                        f'{z:.6f} '
                        f'0.000000\n'
                    )
            
            print(f'Created {output} with {len(roi_verts)} vertices')


if __name__ == '__main__':
    import sys
    
    if len(sys.argv) != 3:
        print('Usage: python benson2roi.py <BIDS_root> <subject>')
        sys.exit(1)
    
    bids_root = sys.argv[1]
    subject = sys.argv[2]
    
    try:
        benson2roi(bids_root, subject)
        print(f'Successfully created ROI labels for {subject}')
    except Exception as e:
        print(f'Error: {e}', file=sys.stderr)
        sys.exit(1)
