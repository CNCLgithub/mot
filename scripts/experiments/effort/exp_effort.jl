using CSV
using MOT
using Gen_Compose
using ArgParse
using Accessors


experiment_name = "exp_effort"

plan_objectives = Dict(
    # key => (plan object, args)
    :td => (td_flat, (1.025,)),
    :na_perf => ((_...) -> 1.0, ()),
    :na_load => ((_...) -> 1.0, ()),
    # :id => (id_flat, (3.0,)),
)

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

        "--plan"
        help = "which decision objective to use"
        arg_type = Symbol
        default = :td

        "--dataset"
        help = "jld2 dataset path"
        arg_type = String
        default = "/spaths/datasets/$(experiment_name).json"

        "--time", "-t"
        help = "How many frames"
        arg_type = Int64
        default = 240

        "--step_size", "-s"
        help = "How many steps before saving"
        arg_type = Int64
        default = 60

        "--restart", "-r"
        help = "Whether to resume inference"
        action = :store_true

        "--viz", "-v"
        help = "Whether to render masks"
        action = :store_true

        "--scene"
        help = "Which scene to run"
        arg_type = Int
        default = 23

        "--chain"
        help = "The number of chains to run"
        arg_type = Int
        default = 1
    end

    return parse_args(s)
end

function main()
    args = parse_commandline()
    # args["restart"] = true
    # args["viz"] = true

    att_mode = args["plan"]
    att_params = "$(@__DIR__)/$(att_mode).json"
    plan, plan_args = plan_objectives[att_mode]

    # loading scene data
    gm = MOT.load(InertiaGM, args["gm"])
    dgp_gm = gm
    scene_data = MOT.load_scene(dgp_gm,
                                args["dataset"],
                                args["scene"])
    # gt_states = scene_data[:gt_states][1:args["time"]]
    init_gt_state = scene_data[:gt_states][1]
    gt_states = scene_data[:gt_states][2:(args["time"] + 1)]
    aux_data = scene_data[:aux_data]

    gm = setproperties(gm, (
        n_dots = gm.n_targets + aux_data["n_distractors"],
        vel = aux_data["vel"] * 0.55,
        ))

    query = query_from_params(gm, init_gt_state, gt_states)

    att = MOT.load(PopSensitivity,
                   att_params,
                   plan = plan,
                   plan_args = plan_args,
                   percept_update = tracker_kernel,
                   percept_args = (3,) # look back steps
                   )

    proc = MOT.load(PopParticleFilter,
                    args["proc"];
                    attention = att)

    path = "/spaths/experiments/$(experiment_name)_ac_$(att_mode)/$(args["scene"])"
    try
        isdir(path) || mkpath(path)
    catch e
        println("could not make dir $(path)")
    end

    c = chain = args["chain"]
    nsteps = length(gt_states) + 1
    logger = MemLogger(nsteps)
    chain_perf_path = joinpath(path, "$(chain)_perf.csv")
    chain_att_path = joinpath(path, "$(chain)_att.csv")

    println("running chain $(chain)")
    if isfile(chain_perf_path) && args["restart"]
        rm(chain_perf_path)
        rm(chain_att_path)
    end
    smc_chain = run_chain(proc, query, nsteps, logger)

    dg = extract_digest(logger)
    perf_df = MOT.chain_performance(dg)
    perf_df[!, :scene] .= args["scene"]
    perf_df[!, :chain] .= chain
    CSV.write(chain_perf_path, perf_df)
    att_df = MOT.chain_attention(dg, gm.n_targets)
    att_df[!, :scene] .= args["scene"]
    att_df[!, :chain] .= chain
    CSV.write(chain_att_path, att_df)

    args["viz"] && visualize_inference(smc_chain, dg, gt_states, gm,
                                          joinpath(path, "$(chain)_scene"))

    return nothing
end

main();
