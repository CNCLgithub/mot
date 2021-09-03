export extract_tracker_positions,
        extract_tracker_velocities,
        extract_assignments,
        extract_tracker_masks,
        extract_pmbrfs_params,
        extract_chain

using JLD2
using DataFrames
using Gen_Compose:SeqPFChain
using Combinatorics:combinations

function digest_auxillary(c::SeqPFChain)
    deepcopy(c.auxillary)
end

function extract_digest(f::String)
    df = DataFrame()
    jldopen(f, "r") do data
        steps = data["current_idx"]
        steps === 0 && return df
        df = DataFrame(data["1"])
        steps === 1 && return df
        @inbounds for i = 2:steps
            push!(df, data["$i"])
        end
    end
    return df
end

function td_accuracy(td::Dict{Int64, Float64}; k::Int64 = 4)
    mass = -Inf
    for key = 1:k
        mass = logsumexp(mass, td[key])
    end
    exp(mass - log(k))
end
function td_accuracy(td::Dict{BitVector, Float64}; k::Int64 = 4)
    denom = log(k)
    mass = -Inf
    for (key, val) in td
        w = log(sum(key[1:k])) - denom + get(td, key, -Inf)
        mass = logsumexp(mass, w)
    end
    exp(mass - logsumexp(collect(values(td))))
end

function extract_td_accuracy(c::SeqPFChain)
    # particles at last frame of inference
    @unpack state = c
    traces = sample_unweighted_traces(state, length(state.traces))
    @>> traces begin
        map(target_designation_flat) # traces x rf
        map(first)  # assuming only a 1x1 receptive field
        map(td_accuracy)
        mean        # average across traces
    end
end

function extract_tracker_positions(trace::Gen.Trace)
    (init_state, states) = Gen.get_retval(trace)

    trackers = get_objects(states[end], Dot)

    tracker_positions = Array{Float64}(undef, length(trackers), 3)
    for i=1:length(trackers)
        tracker_positions[i,:] = trackers[i].pos
    end

    tracker_positions = reshape(tracker_positions, (1,1,size(tracker_positions)...))
    return tracker_positions
end

function extract_tracker_velocities(trace::Gen.Trace)
    (init_state, states) = Gen.get_retval(trace)

    trackers = states[end].graph.elements

    tracker_velocities = Array{Float64}(undef, length(trackers), 2)
    for i=1:length(trackers)
        tracker_velocities[i,:] = trackers[i].vel
    end

    tracker_velocities = reshape(tracker_velocities, (1,1,size(tracker_velocities)...))
    return tracker_velocities
end

function extract_assignments(trace::Gen.Trace)
    t, motion, gm = Gen.get_args(trace)
    ret = Gen.get_retval(trace)
    pmbrfs = ret[2][t].rfs
    record = AssociationRecord(5)
    xs = get_choices(trace)[:kernel => t => :masks]
    Gen.logpdf(rfs, xs, pmbrfs, record)
    (record.table, record.logscores)
end


function extract_tracker_masks(trace::Gen.Trace)
    t, motion, gm = Gen.get_args(trace)
    ret = Gen.get_retval(trace)
    pmbrfs = ret[2][t].rfs
    
    tracker_masks = Vector{Array{Float64,2}}(undef, gm.n_trackers)

    for i=1:gm.n_trackers
        tracker_masks[i] = first(GenRFS.args(pmbrfs[1+i]))
    end

    tracker_masks = reshape(tracker_masks, (1,1,size(tracker_masks)...))

    return tracker_masks
end

function extract_causal_graph(trace::Gen.Trace)
    @>> trace begin
        get_retval # (init_state, states)
        last # states
        last # CausalGraph
    end
end

function extract_trace(trace::Gen.Trace)
    reshape([trace], (1,1, size([trace])...))
end
