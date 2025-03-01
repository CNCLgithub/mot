using CSV
using Gen
using MOT
using ArgParse
using Accessors
using DataFrames
using Gen_Compose

################################################################################
# Global variables
################################################################################

experiment_name = "exp_staircase"
nobjects = 16
plan = :td

exp_params = (;
              gm = "$(@__DIR__)/gm_staircase.json",
              proc = "$(@__DIR__)/proc.json",
              att = "$(@__DIR__)/$(plan)_staircase.json",
              dur = 120, # number of frames (24 fps)
              stairsteps = 20,
              velstep = 1.0,
              basevel = 4.0,
              model = "ac",
              # SET FALSE for full experiment
              restart = false,
              viz = false,
              # restart = true,
              # viz = true,
              )

plan_objectives = Dict(
    :td => (td_flat, (1.25,)),
)

plan_obj, plan_args = plan_objectives[plan]


default_gm = ISRGM(;
                   dot_repulsion = 40.0,
                   wall_repulsion = 50.0,
                   distance_factor = 100.0,
                   rep_inertia = 0.20,
                   max_distance = 100.0,
                   dot_radius = 20.0,
                   area_width = 960.0,
                   area_height = 960.0)

################################################################################
# Helper functions
################################################################################

function trial_constraints(gm::ISRGM)
    cm = choicemap()
    for i = 1:gm.n_dots
        cm[:init_state => :init_kernel => i => :target] =
            (i <= gm.n_targets)
    end
    return cm
end

function trial_data(dgp_gm::ISRGM, dur::Int64)

    cm = trial_constraints(dgp_gm)
    tr, _ = generate(gm_isr, (dur + 5, dgp_gm), cm)
    init_state, states = get_retval(tr)
    positions = []
    for t in 5:(dur+5)
        objects = states[t].objects
        push!(positions, map(get_pos, objects))
    end
    trial = Dict(
        "positions" => positions,
        "aux_data" => Dict("targets" => Bool.([i <= dgp_gm.n_targets for i = 1:dgp_gm.n_dots]),
                           "vel" => dgp_gm.vel,
                           "n_distractors" => dgp_gm.n_dots - dgp_gm.n_targets)
    )
end

function generate_trial(inference_gm, ntargets::Int64, vel::Float64)
    # configure dgp parameters
    dgp_gm = setproperties(default_gm,
                           (n_dots = nobjects,
                            n_targets = ntargets,
                            vel = vel))
    println("scene sampled")
    data = trial_data(dgp_gm, exp_params.dur)

    # configure inference generative model
    inference_gm = setproperties(inference_gm,
                                 (n_dots = nobjects,
                                  n_targets = ntargets,
                                  target_p = ntargets / nobjects,
                                  # adjustment for different gms
                                  vel = vel * 0.55,
                                  ))
    scene_data = MOT.load_scene(inference_gm, data)
    println("converted to json format")
    init_gt_state = scene_data[:gt_states][1]
    gt_states = scene_data[:gt_states][2:end]
    aux_data = scene_data[:aux_data]


    println("creating query...")
    # create query
    inference_gm, gt_states, query_from_params(inference_gm, init_gt_state, gt_states)
end

function load_perf(path::String)
    perf_df = DataFrame(CSV.File(path))
    sum(perf_df.td_acc)
end

################################################################################
# Main call
################################################################################

function run_model(ntargets::Int, chain::Int)
    gm = MOT.load(InertiaGM, exp_params.gm)

    # attention module and particle filter
    att = MOT.load(PopSensitivity,
                   exp_params.att,
                   plan = plan_obj,
                   plan_args = plan_args,
                   percept_update = tracker_kernel,
                   percept_args = (3,), # look back steps
                   latents = ntargets
                   )
    proc = MOT.load(PopParticleFilter,
                    exp_params.proc;
                    attention = att)

    path = "/spaths/experiments/$(experiment_name)_$(exp_params.model)_$(plan)/$(ntargets)"
    try
        isdir(path) || mkpath(path)
    catch e
        println("could not make dir $(path)")
    end

    chance_performance = ntargets / nobjects
    for step = 1:exp_params.stairsteps
        println("on step $step")
        vel = exp_params.basevel + exp_params.velstep*(step-1)
        println("generating query with vel=$(vel)")
        gm, gt_states, query = generate_trial(gm, ntargets, vel)

        # determine if inference should be reset
        # if previous checkpoint is found
        perf_path = joinpath(path, "$(chain)_$(step)_perf.csv")
        att_path = joinpath(path, "$(chain)_$(step)_att.csv")
        if isfile(perf_path)
            if exp_params.restart
                # restartng will remove previous
                # checkpoints
                rm(perf_path)
                rm(att_path)
            else
                # should retreive checkpoint performance
                # to determine if staircase should proceed
                # determine if performance is above chance
                step_perf = load_perf(perf_path)
                step_perf < ntargets && break
                # otherwise continue to next step
                continue
            end
        end

        # run the inference chain across all observations
        nsteps = length(query)
        logger = MemLogger(nsteps)
        println("running for $(nsteps) steps")
        smc_chain = run_chain(proc, query, nsteps, logger)

        # process results
        dg = extract_digest(logger)
        perf_df = MOT.chain_performance(dg)
        att_df = MOT.chain_attention(dg, ntargets)
        # append step data
        perf_df[!, :chain] .= chain
        perf_df[!, :ntargets] .= ntargets
        perf_df[!, :vel] .= vel
        att_df[!, :chain] .= chain
        att_df[!, :ntargets] .= ntargets
        att_df[!, :vel] .= vel


        # store results
        CSV.write(perf_path, perf_df)
        CSV.write(att_path, att_df)

        # determine if performance is above chance
        step_perf = sum(perf_df.td_acc) / ntargets
        if step_perf < 0.95 || step == exp_params.stairsteps
            exp_params.viz &&
                visualize_inference(smc_chain, dg, gt_states, gm,
                                    joinpath(path, "$(chain)_$(step)"))
            break
        end
    end

    return nothing
end

function pargs()
    s = ArgParseSettings()

    @add_arg_table! s begin
        "ntargets"
        help = "How many targets to track"
        arg_type = Int64
        default = 4

        "chain"
        help = "chain id"
        arg_type = Int64
        default = 1
    end

    return parse_args(s)
end

function main()
    args = pargs()
    i = args["ntargets"]
    c = args["chain"]
    run_model(i, c);
end


main();
