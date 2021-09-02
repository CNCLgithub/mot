using CSV
using GenRFS
using MOT
using Gen_Compose
using ArgParse
using Setfield

# using Profile
# using StatProfilerHTML

experiment_name = "exp1_difficulty"

function parse_commandline()
    s = ArgParseSettings()

    @add_arg_table! s begin
        "--gm"
        help = "Generative Model params"
        arg_type = String
        default = "$(@__DIR__)/gm.json"

        "--proc"
        help = "Inference procedure params"
        arg_type = String
        default = "$(@__DIR__)/proc.json"

        "--graphics"
        help = "Graphics params"
        arg_type = String
        default = "$(@__DIR__)/graphics.json"

        "--dm"
        help = "Motion parameters for Inertia model"
        arg_type = String
        default = "$(@__DIR__)/dm.json"

        "--dataset"
        help = "jld2 dataset path"
        arg_type = String
        default = joinpath("/datasets", "$(experiment_name).jld2")

        "--time", "-t"
        help = "How many frames"
        arg_type = Int64
        default = 240

        "--step_size", "-s"
        help = "How many steps before saving"
        arg_type = Int64
        default = 30

        "--restart", "-r"
        help = "Whether to resume inference"
        action = :store_true

        "--viz", "-v"
        help = "Whether to render masks"
        action = :store_true

        "scene"
        help = "Which scene to run"
        arg_type = Int
        required = true

        "chain"
        help = "The number of chains to run"
        arg_type = Int
        required = true

        "target_designation", "T"
        help = "Using target designation"
        action = :command

        "data_correspondence", "D"
        help = "Using data correspondence"
        action = :command

        "scene_avg", "A"
        help = "Using scene avg"
        action = :command

    end

    @add_arg_table! s["target_designation"] begin
        "--params"
        help = "Attention params"
        arg_type = String
        default = "$(@__DIR__)/td.json"

    end
    @add_arg_table! s["data_correspondence"] begin
        "--params"
        help = "Attention params"
        arg_type = String
        default = "$(@__DIR__)/dc.json"
    end
    @add_arg_table! s["scene_avg"] begin
        "model_path"
        help = "path containing compute allocations"
        arg_type = String
        required = true

    end

    return parse_args(s)
end

function default_args()
    args = Dict(["target_designation" => Dict(["params" => "$(@__DIR__)/td.json"]),
                "dm" => "$(@__DIR__)/dm.json",
                "gm" => "$(@__DIR__)/gm.json",
                "proc" => "$(@__DIR__)/proc.json",
                "graphics" => "$(@__DIR__)/graphics.json",
                "dataset" => "/datasets/exp1_difficulty.jld2",
                "scene" => 63,
                "chain" => 1,
                "time" => 100,
                "step_size" => 60,
                "restart" => false,
                "viz" => true])
end

function main()
    args = parse_commandline()
    # args = default_args()

    # increase the size of GenRFS memoization table
    modify_partition_ctx!(10)

    # loading scene data
    scene_data = MOT.load_scene(args["scene"], args["dataset"])
    gt_cgs = scene_data[:gt_causal_graphs][1:args["time"]]
    aux_data = scene_data[:aux_data]

    n_trackers = sum(aux_data.targets)
    gm = MOT.load(GMParams, args["gm"])
    gm = @set gm.n_trackers = n_trackers # always 4 targets but whatever
    gm = @set gm.distractor_rate = sum(aux_data.n_distractors)

    dgp = deepcopy(gm)
    dgp = @set dgp.n_trackers = length(aux_data.targets)
    dgp = @set dgp.distractor_rate = 0.
    @show dgp


    dm = MOT.load(InertiaModel, args["dm"])
    dm = @set dm.vel = aux_data[:vel]

    @show aux_data
    @show dm
    @show gm

    graphics = MOT.load(Graphics, args["graphics"])

    query = query_from_params(gt_cgs,
                              dgp,
                              gm_inertia_mask,
                              gm,
                              dm,
                              graphics,
                              length(gt_cgs))

    att_mode = "target_designation"
    att = MOT.load(MapSensitivity, args[att_mode]["params"],
                   objective = MOT.target_designation_receptive_fields,
                   )

    proc = MOT.load(PopParticleFilter, args["proc"];
                    rejuvenation = rejuvenate_attention!,
                    rejuv_args = (att,),
                    latents = collect(1:n_trackers))

    path = "/experiments/$(experiment_name)_$(att_mode)/$(args["scene"])"
    try
        isdir(path) || mkpath(path)
    catch e
        println("could not make dir $(path)")
    end

    c = args["chain"]
    chain_path = joinpath(path, "$(c).jld2")

    println("running chain $c")

    # Profile.init(delay = 1E-3,
    #              n = 10^8)
    # Profile.clear()
    # @profilehtml begin
    if isfile(chain_path)
        chain  = resume_chain(chain_path, args["step_size"])
    else
        chain = sequential_monte_carlo(proc, query, chain_path,
                                    args["step_size"])
    end
    # end

    df = MOT.analyze_chain_receptive_fields(chain, chain_path,
                                            n_trackers = gm.n_trackers,
                                            n_dots = gm.n_trackers + gm.distractor_rate,
                                            gt_cg_end = gt_cgs[end])
    df[!, :scene] .= args["scene"]
    df[!, :chain] .= c
    CSV.write(joinpath(path, "$(c).csv"), df)

    if (args["viz"])
        visualize_inference(chain, chain_path, gt_cgs, gm,
                            graphics, att, path)
    end

    return nothing
end

main();
