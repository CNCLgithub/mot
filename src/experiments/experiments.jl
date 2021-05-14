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


function get_observations(graphics::AbstractGraphics, masks)
    k = length(masks)
    observations = Vector{Gen.ChoiceMap}(undef, k)
    receptive_fields = graphics.receptive_fields
    
    for t=1:k
        cm = Gen.choicemap()

        if receptive_fields isa NullReceptiveFields
            cm[:kernel => t => :masks] = masks[t]
        else
            for i=1:length(receptive_fields)
                cm[:kernel => t => :receptive_fields => i => :masks] = masks[t][i]
            end
        end

        observations[t] = cm
    end
    
    return observations
end


function get_init_constraints(cg::CausalGraph)
    cm = Gen.choicemap()
    init_dots = get_objects(cg, Dot)
    for i=1:length(init_dots)
        addr = :init_state => :trackers => i => :x
        cm[addr] = init_dots[i].pos[1]
        addr = :init_state => :trackers => i => :y
        cm[addr] = init_dots[i].pos[2]
    end

    return cm
end


function query_from_params(gt_causal_graphs,
                           masks,
                           generative_model,
                           gm_params::AbstractGMParams,
                           dm_params::AbstractDynamicsModel,
                           graphics_params::AbstractGraphics,
                           k::Int64)
    
    if graphics_params.receptive_fields isa NullReceptiveFields
        assignments_func = extract_assignments
    else
        assignments_func = extract_assignments_receptive_fields
    end

    _lm = Dict(:tracker_positions => extract_tracker_positions,
               :assignments => assignments_func,
               :causal_graph => extract_causal_graph,
               :trace => extract_trace)
               #:tracker_masks => extract_tracker_masks)
    latent_map = LatentMap(_lm)

    init_gt_cg = gt_causal_graphs[1]
    gt_cgs = gt_causal_graphs[2:end]

    init_constraints = get_init_constraints(init_gt_cg)
    observations = get_observations(graphics_params, masks)

    path = "testing_refactor"
    for t=1:k
        render_rf_masks(observations[t], t, gm_params, graphics_params,
                        joinpath(path, "obs_rf_masks"))
    end
    
    init_args = (0, gm_params, dm_params, graphics_params)
    args = [(t, gm_params, dm_params, graphics_params) for t in 1:k]

    query = Gen_Compose.SequentialQuery(latent_map,
                                        generative_model,
                                        init_args,
                                        init_constraints,
                                        args,
                                        observations)
    
    return query
end

export run_inference, query_from_params
