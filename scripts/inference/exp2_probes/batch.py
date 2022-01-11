#!/usr/bin/env python

""" Submits sbatch array for rendering stimuli """
import os
import argparse
from slurmpy import sbatch

# script = 'bash {0!s}/run.sh julia -J "/project/mot.so" -C generic' + \
script = 'bash {0!s}/env.d/run.sh julia ' + \
         '/project/scripts/inference/exp2_probes/exp2_probes.jl'

def att_tasks(args):
    tasks = [(t,c) for c in range(1, args.chains + 1)
             for t in range(1, args.scenes+1)]
    return (tasks, [], [])
    
def main():
    parser = argparse.ArgumentParser(
        description = 'Submits batch jobs for Exp1 (Difficulty)',
        formatter_class = argparse.ArgumentDefaultsHelpFormatter
    )

    parser.add_argument('--scenes', type = int, default = 40,
                        help = 'number of scenes')
    parser.add_argument('--chains', type = int, default = 30,
                        help = 'number of chains')
    parser.add_argument('--duration', type = int, default = 45,
                        help = 'job duration (min)')

    args = parser.parse_args()

    n = args.scenes * args.chains
    tasks, kwargs, extras = att_tasks(args)

    interpreter = '#!/bin/bash'
    resources = {
        'cpus-per-task' : '1',
        'mem-per-cpu' : '2GB',
        'time' : '{0:d}'.format(args.duration),
        'partition' : 'scavenge',
        'requeue' : None,
        'job-name' : 'mot',
        'output' : os.path.join(os.getcwd(), 'env.d/spaths/slurm/%A_%a.out')
    }
    func = script.format(os.getcwd())
    batch = sbatch.Batch(interpreter, func, tasks,
                         kwargs, extras, resources)
    print("Template Job:")
    print('\n'.join(batch.job_file(chunk=n)))
    batch.run(n = n, check_submission = False)

if __name__ == '__main__':
    main()
