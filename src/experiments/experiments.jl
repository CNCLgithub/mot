function run_inference(query::SequentialQuery,
                       proc::Gen_Compose.AbstractParticleFilter)

    results = sequential_monte_carlo(proc, query,
                                     buffer_size = length(query))
end
function run_inference(query::SequentialQuery,
                       proc::Gen_Compose.AbstractParticleFilter,
                       path::String)

    results = sequential_monte_carlo(proc, query,
                                     buffer_size = length(query),
                                     path = path)
end

function query_from_params(gm_params_path::T, dataset::T, scene::K, k::K;
                           gm = gm_brownian_mask, motion = nothing) where {T<:String, K<:Int}

    _lm = Dict(:tracker_positions => extract_tracker_positions,
               :assignments => extract_assignments,
               :causal_graph => extract_causal_graph)
               # :tracker_masks => extract_tracker_masks)
               # :trace => extract_trace)

    latent_map = LatentMap(_lm)

    gm_params = load(GMMaskParams, gm_params_path)

    scene_data = load_scene(scene, dataset, gm_params;
                            generate_masks=true)

    motion = isnothing(motion) ? scene_data[:motion] : motion
    masks = scene_data[:masks]
    gt_causal_graphs = scene_data[:gt_causal_graphs]

    # initial observations based on init_positions
    # model knows where trackers start off
    constraints = Gen.choicemap()
    init_dots = gt_causal_graphs[1].elements

    for i=1:gm_params.n_trackers
        addr = :init_state => :trackers => i => :x
        constraints[addr] = init_dots[i].pos[1]
        addr = :init_state => :trackers => i => :y
        constraints[addr] = init_dots[i].pos[2]
    end

    # compiling further observations for the model
    args = [(t, motion, gm_params) for t in 1:k]
    observations = Vector{Gen.ChoiceMap}(undef, k)
    for t = 1:k
        cm = Gen.choicemap()
        cm[:kernel => t => :masks] = masks[t]
        observations[t] = cm
    end

    query = Gen_Compose.SequentialQuery(latent_map,
                                        gm,
                                        (0, motion, gm_params),
                                        constraints,
                                        args,
                                        observations)

    return query, gt_causal_graphs, gm_params
end

export run_inference, query_from_params
