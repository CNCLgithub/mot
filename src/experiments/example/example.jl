export ExampleExperiment


@with_kw struct ExampleExperiment <: AbstractExperiment
    proc::String = "$(@__DIR__)/proc.json"
    gm::String = "$(@__DIR__)/gm.json"
    motion::String = "$(@__DIR__)/motion.json"
    attention::String = "$(@__DIR__)/attention.json"
    k::Int = 120
end

get_name(::ExampleExperiment) = "example"

function run_inference(q::ExampleExperiment, path::String)

    gm_params = load(GMMaskParams, q.gm)
    motion = load(BrownianDynamicsModel, q.motion)
    
    # generating initial positions and masks (observations)
    init_positions, init_vels, masks, positions = dgp(q.k, gm_params, motion)

    latent_map = LatentMap(Dict(
                                :tracker_positions => extract_tracker_positions,
                                :tracker_masks => extract_tracker_masks
                               ))

    
    # initial observations based on init_positions
    # model knows where trackers start off
    constraints = Gen.choicemap()
    for i=1:size(init_positions, 1)
        addr = :init_state => :trackers => i => :x
        constraints[addr] = init_positions[i,1]
        addr = :init_state => :trackers => i => :y
        constraints[addr] = init_positions[i,2]
    end
    
    # compiling further observations for the model
    args = [(t, motion, gm_params) for t in 1:q.k]
    observations = Vector{Gen.ChoiceMap}(undef, q.k)
    for t = 1:q.k
        cm = Gen.choicemap()
        cm[:states => t => :masks] = masks[t]
        observations[t] = cm
    end
    
    query = Gen_Compose.SequentialQuery(latent_map,
                                        gm_masks_static,
                                        (0, motion, gm_params),
                                        constraints,
                                        args,
                                        observations)

    
    attention = load(TDEntropyAttentionModel, q.attention;
                     perturb_function = perturb_state!)

    proc = load(PopParticleFilter, q.proc;
                rejuvenation = rejuvenate_attention!,
                rejuv_args = (attention,))
    

    results = sequential_monte_carlo(proc, query,
                                     buffer_size = q.k,
                                     path = nothing)

    extracted = extract_chain(results)
    tracker_positions = extracted["unweighted"][:tracker_positions]
    tracker_masks = extracted["unweighted"][:tracker_masks]
    
    aux_state = extracted["aux_state"]
    attempts = Vector{Int}(undef, q.k)
    attended = Vector{Vector{Float64}}(undef, q.k)

    for t=1:q.k
        attempts[t] = aux_state[t].attempts
        attended[t] = aux_state[t].attended_trackers
    end
    
    plot_attention(attended, attention)

    # visualizing inference on stimuli
    render(positions, gm_params;
           pf_xy=tracker_positions[:,:,:,1:2],
           attended=attended/attention.max_sweeps,
           tracker_masks=tracker_masks)

    #full_imgs = get_full_imgs(masks)
    #visualize(tracker_positions, full_imgs, gm_params)

    return results
end


