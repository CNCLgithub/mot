using MOT
using CSV
using Statistics
using LinearAlgebra:norm
using Base.Iterators:take
using DataFrames
using Gadfly
Gadfly.push_theme(Theme(background_color = colorant"white"))
using Compose
import Cairo
# using ImageFiltering
# using ImageTransformations:imresize, imfilter
using StatsBase
using FileIO

function attention_map(c::Dict, bin::Int64)
    aux_state = c["aux_state"]
    k = length(aux_state)
    n = length(first(aux_state).attended_trackers)
    attended = Matrix{Float64}(undef, k, n)
    for t=1:k
        attended[t, :] = aux_state[t].attended_trackers
    end
    println(size(attended))
    return attended
    # smoothed = Matrix{Float64}(undef, k-2*bin, n)
    # for (i,t) in enumerate(bin+1:k-bin)
       # smoothed[i,:] = mean(attended[t-bin:t+bin, :], dims = 1)
    # end
    # smoothed
end

function load_attmap(trial_path::String; bin::Int64 = 2)
    chain_paths = filter(x -> occursin("jld", x), readdir(trial_path))
    chain_paths = map(x -> joinpath(trial_path, x), chain_paths)
    chains = map(extract_chain, chain_paths)
    atts = map(attention_map, chains, fill(bin, length(chains)))
    sum(atts) ./ length(chain_paths)
end


"""
    z scored attention maps from an experiment results folder
"""
function load_attmaps(exp_path::String; bin::Int64 = 2)
    trials = filter(isdir, readdir(exp_path; join = true))
    attmap = load_attmap(first(trials), bin=bin)
    attmaps = Array{Float64}(undef, length(trials), size(attmap)...)
    ts = 1:size(attmap, 1)
    results = []
    for trial in trials
        i = parse(Int64, basename(trial))
        print("getting attmap for trial $i \r")
        attmaps[i,:,:] = load_attmap(trial)
        df = DataFrame(t = ts,
                       tracker_1 = attmaps[i, :, 1],
                       tracker_2 = attmaps[i, :, 2],
                       tracker_3 = attmaps[i, :, 3],
                       tracker_4 = attmaps[i, :, 4])
        df[!, :trial] .= i
        push!(results, df)
    end
    print("done                               \n")
    mu = mean(attmaps)
    std = Statistics.std(attmaps)
    attmaps = (attmaps .- mu)/std
    results = vcat(results...)
    CSV.write(joinpath("output", "attention_analysis", "$(basename(exp_path))_attention.csv"), results)
    return attmaps
end

"""
    returns boolean attention maps for probe placement
    n - number of difficulty levels (quantiles)
"""
function bool_attmaps(attmaps::Array{Float64}, n_quantiles::Int)
    n_trials = size(attmaps, 1)
    quantiles = nquantile(collect(Iterators.flatten(attmaps)), n_quantiles)
    println(quantiles)
    b_ams = Array{Array{Bool}}(undef, n_trials, n_quantiles)
    for i=1:n_trials
        for j=1:n_quantiles
            println("$i $j")
            println(quantiles[j], " ", quantiles[j+1])
            b_ams[i,j] = (quantiles[j] .< attmaps[i,:,:]) .& (attmaps[i,:,:] .< quantiles[j+1])
            # b_ams[i,j][1:2,:] .= false
            # b_ams[i,j][end-1:end,:] .= false
        end
    end
    b_ams
end


# function csv_attmaps(exp_path::String, out_path::String, z_scored::Bool)
function csv_attmaps(exp_path::String, out_path::String)
    mkpath(out_path)
    # attmaps = load_attmaps(exp_path, z_scored=z_scored)
    attmaps = load_attmaps(exp_path)
    results = []
    for i = 1:size(attmaps,1)
        df = DataFrame(trial=fill(i,size(attmaps,2)),
                       t=1:size(attmaps,2),
                       tracker_1=attmaps[i,:,1],
                       tracker_2=attmaps[i,:,2],
                       tracker_3=attmaps[i,:,3],
                       tracker_4=attmaps[i,:,4])
        push!(results, df)
    end
    results = vcat(results...)
    display(results)
    CSV.write(joinpath(out_path, "attention.csv"), results)
end

function add_nearest_distractor(att_tps::String, att_tps_out::String;
                                dataset_path::String="/datasets/exp0.jld2",
                                min_distance::Float64=0.0)

    df = DataFrame(CSV.File(att_tps))

    # adding new cols
    df[!,:nd] .= 0
    df[!,:dist_to_nd] .= 0.0
    df[!,:tracker_to_origin] .= 0.0 # perhaps to control for eccentricity?
    df[!,:tracker_to_tracker_mean] .= 0.0 # perhaps to control for eccentricity?
    df[!,:tracker_to_dot_mean] .= 0.0 # another control for eccentricity
    df[!,:cumulative_dist] .= 0.0 # distance to all other objects

    for (i, trial_row) in enumerate(eachrow(df))
        scene = trial_row.scene
        scene_data = MOT.load_scene(scene, dataset_path, default_gm;
                                    generate_masks=false)
        # getting the corresponding causal graph elements
        #
        # (+1 because the first causal graph is for the init state)
        # dots = scene_data[:gt_causal_graphs][trial_row.frame+1].elements
        # actually, not sure if needed
        dots = scene_data[:gt_causal_graphs][trial_row.frame].elements
        pos = collect(map(x->x.pos[1:2], dots))

        tracker_pos = pos[trial_row.tracker]
        
        tracker_mean = Statistics.mean(pos[1:4])
        dot_mean = Statistics.mean(pos)
        df[i, :tracker_to_origin] = norm(tracker_pos - zeros(2))
        df[i, :tracker_to_tracker_mean] = norm(tracker_pos - tracker_mean)
        df[i, :tracker_to_dot_mean] = norm(tracker_pos - dot_mean)
        
        tracker_distances = map(x->norm(tracker_pos - x), pos[setdiff(1:4, trial_row.tracker)])
        distractor_distances = map(distr_pos->norm(tracker_pos - distr_pos), pos[5:8])
        
        df[i, :cumulative_dist] = sum(tracker_distances) + sum(distractor_distances)

        distractor_distances = map(x-> x < min_distance ? Inf : x, distractor_distances)

        df[i, :nd] = argmin(distractor_distances)+4
        df[i, :dist_to_nd] = minimum(distractor_distances)
    end

    display(df)
    CSV.write(att_tps_out, df)
end

