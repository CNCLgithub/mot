using MOT

function plot_exp_trial(path::String)
        extracted = extract_chain(path)
        tracker_positions = extracted["unweighted"][:tracker_positions]
        # tracker_masks = extracted["unweighted"][:tracker_masks]
        aux_state = extracted["aux_state"]
        k = size(tracker_positions, 1)
        attention_weights = [aux_state[t].stats for t = 1:k]
        attention_weights = collect(hcat(attention_weights...)')

        out = dirname(path)
        println(out)

        plot_compute_weights(attention_weights, out)

        attempts = Vector{Int}(undef, k)
        attended = Vector{Vector{Float64}}(undef, k)
        for t=1:k
            attempts[t] = aux_state[t].attempts
            attended[t] = aux_state[t].attended_trackers
        end

        # plot_attention(attended, 15, out)
        plot_rejuvenation(attempts, out)
        # visualizing inference on stimuli
        #MOT.render(positions, q, gm_params;
        #    pf_xy=tracker_positions,
        #    attended = attended / attention.sweeps,
        #    tracker_masks=tracker_masks,
        #    dir = joinpath(path, "render"))
    return nothing
end

