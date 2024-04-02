# MOT - analysis

This folder contains several pre-processing scripts that generate covariates used in the `mot-analysis` repo. 


## aggregrate_chains.jl

This script aggregates the multiple inference chains (traces) generated by adaptive computation for each experiment into ".csv" files that can be used in R.

> NOTE: This script must be run before the other analysis scripts.

## nd_probes.jl

This script produces the nearest-distractor coviarates used for one of the heuristic models in the attention experiment. 

## nd_localization_error.jl

Computes the nearest distractor covariates used in the localization error experiment. It generates the distance of each target to its closest distractor for every time point. 