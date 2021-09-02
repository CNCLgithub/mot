export perturb_state!


"""
	state_perturb(trace, probs)

Perturbs velocity based on probs of assignments to observations.
"""


function _state_proposal(trace::Gen.Trace, tracker::Int64,
                         att::MapSensitivity)
    t, gm, dm, gr = Gen.get_args(trace)
    choices = Gen.get_choices(trace)

    @unpack ancestral_steps = att
    i = max(1, t - ancestral_steps)
    addr = :kernel => i => :dynamics => :trackers => tracker => :ang
    ang = choices[addr]

    inertia = choices[:kernel => i => :dynamics => :trackers => tracker => :inertia]
    @unpack k_min, k_max = dm
    k = inertia ? k_max : k_min
    (addr, ang, k)
end

@gen  function state_proposal(trace::Gen.Trace, tracker::Int64,
                              att:MapSensitivity)
    (addr, ang, k) = _state_proposal(trace, tracker, att)
    {addr} ~ von_mises(ang, k)
    return nothing
end

function apply_random_walk(trace::Gen.Trace, proposal, proposal_args)
    model_args = get_args(trace)
    argdiffs = map((_) -> NoChange(), model_args)
    proposal_args_forward = (trace, proposal_args...,)
    (fwd_choices, fwd_weight, _) = propose(proposal, proposal_args_forward)
    (new_trace, weight, _, discard) = Gen.update(trace,
        model_args, argdiffs, fwd_choices)
    proposal_args_backward = (new_trace, proposal_args...,)
    (bwd_weight, _) = Gen.assess(proposal, proposal_args_backward, discard)
    alpha = weight - fwd_weight + bwd_weight
    if isnan(alpha)
        @show fwd_weight
        @show weight
        @show bwd_weight
        error("nan in proposal")
    end
    (new_trace, alpha)
end

function tracker_kernel(trace::Gen.Trace, tracker::Int64,
                        att::MapSensitivity)
    new_tr, w1 = apply_random_walk(trace, state_proposal,
                                   (tracker, att))
    # @show w1
    new_tr, w2 = ancestral_tracker_move(new_tr, tracker, att)
    # @show w2
    (new_tr, w1 + w2)
end

# rejuvenate_state!(state, probs) = rejuvenate!(state, probs, state_move)

function ancestral_tracker_move(trace::Gen.Trace, tracker::Int64, att::MapSensitivity)
    args = Gen.get_args(trace)
    t = first(args)
    addrs = []
    t === 1 && return (trace, 0.)

    for i = max(2, t-att.ancestral_steps):t
        addr = :kernel => i => :dynamics => :trackers => tracker
        push!(addrs, addr)
    end
    (new_tr, ll) = take(regenerate(trace, Gen.select(addrs...)), 2)
end

"""
    rejuvenate_state!(state::Gen.ParticleFilterState, probs::Vector{Float64})

    Does one state rejuvenation step based on the probabilities of which object to perturb.
    probs are softmaxed in the process so no need to normalize.
"""
function perturb_state!(chain::SeqPFChain,
                        att::AbstractAttentionModel)
    @unpack state, auxillary = chain
    @unpack weights, cycles, allocated = auxillary
    allocated = zeros(size(allocated))
    num_particles = length(state.traces)
    @inbounds for i=1:num_particles, _ = 1:cycles
        tracker = Gen.categorical(weights)
        allocated[tracker] += 1
        new_tr, ls = att.jitter(state.traces[i], tracker, att)
        if log(rand()) < ls
            state.traces[i] = new_tr
        end
    end
    @pack! auxillary = allocated
    @pack! chain = state
    return nothing
end
