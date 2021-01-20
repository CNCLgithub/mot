export dgp

using Setfield

_dgp(k::Int, gm::GMParams, motion::AbstractDynamicsModel) = error("not implemented")
_dgp(k::Int, gm::GMParams, motion::BrownianDynamics) = gm_brownian(k, motion, gm)
_dgp(k::Int, gm::GMParams, motion::ISRDynamics) = gm_isr(k, motion, gm)

function dgp(k::Int, gm::GMParams,
             motion::AbstractDynamicsModel)

    # new params with all dots having state for data generation
    gm = deepcopy(gm)
    gm = @set gm.n_trackers = round(Int, gm.n_trackers + gm.distractor_rate)
    
    # running generative model on just positions (no need to go to masks)
    init_state, states = _dgp(k, gm, motion)
    
    gt_causal_graphs = Vector{CausalGraph}(undef, k+1)
    gt_causal_graphs[1] = init_state.graph
    gt_causal_graphs[2:end] = map(state->state.graph, states)
    
    scene_data = Dict([:gt_causal_graphs => gt_causal_graphs,
                       :motion => motion])
end
