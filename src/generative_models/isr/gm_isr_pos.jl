
@gen function isr_pos_kernel(t::Int,
                             prev_cg::CausalGraph)
    # advancing causal graph according to dynamics
    # (there is a deepcopy here)
    cg = @trace(isr_update(prev_cg), :dynamics) 
    return cg
end


@gen function gm_isr_pos(k::Int, gm, dm)
    cg = get_init_cg(gm, dm)
    init_state = @trace(sample_init_state_pos(cg), :init_state)
    states = @trace(Gen.Unfold(isr_pos_kernel)(k, init_state), :kernel)
    result = (init_state, states)
    return result
end

export gm_isr_pos