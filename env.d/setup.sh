#!/bin/bash

#################################################################################
# Environment definition
#################################################################################
sconfig_dir=$(realpath "$0" | xargs dirname)
. "$sconfig_dir/load_config.sh"

#################################################################################
# Usage
#################################################################################
usage="$(basename "$0") [targets...] -- setup project according to [default|local].conf
supported targets:
    cont_[pull|build] : either pull the singularity container or build from ENV => build
    all : all non container blobs
    julia : build julia environment

examples:
    # pull container and setup all external blobs
    ./env.d/setup.sh cont_pull all
    # build and setup python speficially (if supported)
    ./env.d/setup.sh cont_build python
"
[ $# -eq 0 ] || [[ "${@}" =~ "help" ]] && echo "$usage"

#################################################################################
# Variable declarations
#################################################################################
cont_pull_url="https://yale.box.com/shared/static/2mu4c07x9ddtj38endxm6r81dm326mqg.sif"
SING="${SENV[sing]}"
BUILD="${SENV[envd]}/${SENV[def]}"
cont_dest="${SENV[envd]}/${SENV[cont]}"


#################################################################################
# Container setup
#################################################################################
[[ "${@}" =~ "cont_build" ]] || [[ "${@}" =~ "cont_pull" ]] || \
    echo "Not touching container"

[[ "${@}" =~ "cont_pull" ]] && [[ -z "${cont_pull_url}" ]] || \
    [[ "${cont_pull_url}" == " " ]] && \
    echo "Tried to pull but no link provided in \$cont_pull_url"
[[ "${@}" =~ "cont_pull" ]] && [[ -n "${cont_pull_url}" ]] && \
    [[ "${cont_pull_url}" != " " ]] && \
    echo "pulling container" && \
    wget "$cont_pull_url" -O "${cont_dest}"
[[ "${@}" =~ "cont_build" ]] && echo "building ${BUILD} -> ${cont_dest}" && \
    SINGULARITY_TMPDIR="${SPATHS[tmp]}" sudo -E $SING build \
    "$cont_dest" "$BUILD"


#################################################################################
# Python setup
#################################################################################
[[ "${@}" =~ "python" ]] || echo "Not touching python"
[[ "${@}" =~ "all" ]] || [[ "${@}" =~ "python" ]] && \
    echo "building python env at ${SENV[pyenv]}" && \
    $SING exec "${cont_dest}" bash -c "virtualenv ${SENV[pyenv]}" && \
    ./env.d/run.sh "python -m pip install --upgrade pip" && \
    ./env.d/run.sh "python -m pip install -r /project/requirements.txt"

#################################################################################
# Julia setup
#################################################################################
[[ "${@}" =~ "julia" ]] || echo "Not touching julia"
[[ "${@}" =~ "all" ]] || [[ "${@}" =~ "julia" ]] && \
    echo "building julia env" && \
    "${SENV[envd]}/run.sh" julia -e '"using Pkg; Pkg.instantiate();"'

#################################################################################
# Project data
# (ie datasets and checkpoints)
#################################################################################
[[ "${@}" =~ "datasets" ]] || [[ "${@}" =~ "datasets" ]] || \
    echo "Not touching datasets"
[[ "${@}" =~ "all" ]] || [[ "${@}" =~ "datasets" ]] && \
    [[ "${@}" =~ "all" ]] || [[ "${@}" =~ "datasets" ]] && \
    echo "pulling datasets" && \
    # wget "https://yale.box.com/shared/static/y064orseciieeada3jbsb73zrwr7qeqj.jld2" \
    # -O "${SPATHS[datasets]}/exp1_difficulty.jld2" && \
    wget "https://yale.box.com/shared/static/a8lnpspo2bt6fj6dcd006bl67ftzulsh.json" \
    -O "${SPATHS[datasets]}/exp1_difficulty.json" && \
    wget "https://yale.box.com/shared/static/cvk1wlh429kapdaclngrdel8z6ec6dip.json" \
    -O "${SPATHS[datasets]}/exp2_probes.json"

[[ "${@}" =~ "checkpoints" ]] || [[ "${@}" =~ "checkpoints" ]] || \
    echo "Not touching checkpoints"
[[ "${@}" =~ "all" ]] || [[ "${@}" =~ "checkpoints" ]] && echo "none yet"
# [[ "${@}" =~ "all" ]] || [[ "${@}" =~ "checkpoints" ]] && \
# echo "pulling checkpoints" && \
# # fill in here
