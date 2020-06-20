export perturb_state!

"""
	state_perturb(trace, probs)

Perturbs velocity based on probs of assignments to observations.
"""
@gen function state_perturb_proposal(trace, probs)
    t, motion, gm = Gen.get_args(trace)
    choices = Gen.get_choices(trace)

    # sample a tracker to perturb
    tracker_ps = softmax(probs)
    tracker = @trace(Gen.categorical(tracker_ps), :tracker)
    
    # perturb velocity
    addr_vx = :states => t => :dynamics => :brownian => tracker => :vx
    addr_vy = :states => t => :dynamics => :brownian => tracker => :vy
    prev_vx = choices[addr_vx]
    prev_vy = choices[addr_vy]

    @trace(normal(prev_vx, motion.sigma_x), :new_vx)
    @trace(normal(prev_vy, motion.sigma_y), :new_vy)

    return (tracker, [prev_vx, prev_vy])
end


"backward step for state perturbation"
function state_perturb_involution(trace, fwd_choices::ChoiceMap, fwd_ret,
                                   proposal_args::Tuple)
    choices = Gen.get_choices(trace)
    t, motion, gm = Gen.get_args(trace)
    (tracker, prev_v) = fwd_ret
    
    # recording attended tracker in involution
    # (not to count twice)
    # TODO
    # push!(gm["attended_trackers"][t], tracker)

    # constraints for update step
    constraints = choicemap()

    # decision over target state
    vx, vy = fwd_choices[:new_vx], fwd_choices[:new_vy]
    constraints[:states => t => :dynamics => :brownian => tracker => :vx] = vx
    constraints[:states => t => :dynamics => :brownian => tracker => :vy] = vy

    # backward stuffs
    bwd_choices = choicemap()
    bwd_choices[:tracker] = fwd_choices[:tracker]
    bwd_choices[:new_vx] = prev_v[1]
    bwd_choices[:new_vy] = prev_v[2]

    model_args = get_args(trace)
    (new_trace, weight, _, _) = Gen.update(trace, model_args, (NoChange(),), constraints)

    (new_trace, bwd_choices, weight)
end

state_move(trace, args) = Gen.mh(trace, state_perturb_proposal, args, state_perturb_involution)

rejuvenate_state!(state, probs) = rejuvenate!(state, probs, state_move)


"""
    rejuvenate_state!(state::Gen.ParticleFilterState, probs::Vector{Float64})

    Does one state rejuvenation step based on the probabilities of which object to perturb.
    probs are softmaxed in the process so no need to normalize.
"""
function perturb_state!(state::Gen.ParticleFilterState, probs::Vector{Float64})
    #timestep, motion, gm = Gen.get_args(first(state.traces))
    num_particles = length(state.traces)
    accepted = 0
    args = (probs,)
    for i=1:num_particles
        state.traces[i], a = state_move(state.traces[i], args)
        accepted += a
    end
    return accepted / num_particles
end
