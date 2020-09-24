#!/usr/bin/env python

import os
import json
import argparse
import pandas as pd

def generate_condlist(scenes, data, outpath):
    
    condlist = []
    
    # there are probe x n_trackers = 3 x 2 = 6 conditions
    for probe in range(2):
        for tracker in range(3):
            cond_trials = []
            for (i, scene) in enumerate(scenes):
                probe_trial = (probe + i) % 2
                tracker_trial = (tracker + i) % 3

                # mapping tracker_trial to the scene's trackers
                scene_data = data[data.scene == scene]
                tracker_trial = scene_data.tracker.unique()[tracker_trial]
                
                probe_str = "probe" if probe_trial == 1 else "noprobe"

                for epoch in range(1,6):
                    for query in ['trg', 'dis']:
                        trial = '%d_%d_t_%d_%s_%s.mp4' % (scene, tracker_trial, epoch, probe_str, query)
                        cond_trials.append(trial)
    
            condlist.append(cond_trials)

    with open(outpath, 'w') as f:
        json.dump(condlist, f, indent = 4)


def main():
    parser = argparse.ArgumentParser(
        description = 'Submits batch jobs to render stimuli.',
        formatter_class = argparse.ArgumentDefaultsHelpFormatter
    )
    data = pd.read_csv('output/attention_analysis/exp0_probe_map.csv')
    
    # splitting into two scene lists (every other)
    scenes = data.scene.unique()
    scenes_1 = scenes[0::2]
    scenes_2 = scenes[1::2]
    
    generate_condlist(scenes_1, data, os.path.join('/renders', 'condlist_1.json'))
    generate_condlist(scenes_2, data, os.path.join('/renders', 'condlist_2.json'))

    return

if __name__ == '__main__':
    main()
