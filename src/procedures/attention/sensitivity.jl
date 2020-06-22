import PhysicalConstants.CODATA2018: k_B

export PairwiseSensitivity

@with_kw struct PairwiseSensitivity <: AbstractAttentionModel
    objective::Function = target_designation
    latents::Function = t -> extract_tracker_positions(t)[1, 1, :, :]
    sweeps::Int = 5
    eps::Float64 = 0.01
end

function load(::Type{PairwiseSensitivity}, path; kwargs...)
    PairwiseSensitivity(;read_json(path)..., kwargs...)
end


function get_stats(att::PairwiseSensitivity, state::Gen.ParticleFilterState)
    num_particles = length(state.traces)
    # using weighted traces
    indices = index_pairs(num_particles)
    n_pairs = size(indices, 1)
    n_latents = get_dims(att.latents, state.traces[1])
    gradients = zeros(n_pairs, n_latents)
    weights = zeros(n_pairs)
    for i = 1:n_pairs
        idxs = indices[i, :]
        weights[i] = sum(state.log_weights[idxs])
        traces = state.traces[idxs]
        entropies = map(entropy ∘ att.objective, traces)
        a_l, b_l = map(att.latents, traces)
        ẟs = diff(entropies)
        ẟh = max.(map(norm, eachrow(a_l - b_l)), 1E-10)
        gradients[i, :] = ẟs./ẟh
    end
    gs = vec(sum(abs.(gradients) .* weights ./ logsumexp(weights), dims = 1))
end

function get_sweeps(att::PairwiseSensitivity, stats)
    norm(stats) >= att.eps ? att.sweeps : 0
end

function early_stopping(att::PairwiseSensitivity, new_stats, prev_stats)
    # norm(new_stats) <= att.eps
    false
end

# Objectives

function target_designation(tr::Gen.Trace; w::Int = 3)
    k = first(Gen.get_args(tr))
    ret = Gen.get_retval(tr)[2]
    ll = pmbrfs_stats = ret[end].pmbrfs_params.pmbrfs_stats.ll
    lls = zeros(min(k, w), length(ll))
    lls[end, :] = ll
    for t = max(1, k-w):(size(lls, 1) -1)
        lls[t, :] = ret[t].pmbrfs_params.pmbrfs_stats.ll
    end
    lls = mean(lls, dims = 1)
    exp.(lls) .+ 1E-5
end


# Helpers

"""
Computes the entropy of a discrete distribution
"""
function entropy(ps::AbstractArray{Float64})
    # -k_B * sum(map(p -> p * log(p), ps))
    -1 * sum(map(p -> p * log(p), ps))
end

function index_pairs(n::Int)
    if !iseven(n)
        n -= 1
    end
    indices = shuffle(collect(1:n))
    reshape(indices, Int(n/2), 2)
end

function get_dims(latents::Function, trace::Gen.Trace)
    results = latents(trace)
    size(results, 2)
end


# """
# Returns a weighted vector of approximated
# elbo derivatives per object
# """
# function elbo(s, ss, logs)
#     weights = logsumexp(logs)
#     ss .* weights - s
# end

# function first_order(state::Gen.ParticleFilterState, objective, args, cm)
#     map_tr = get_map(state)
#     current_s = (entropy ∘ objective)(map_tr)
#     prediction, p_ls = Gen.update(map_tr, args, (UnknownChange,), cm)
#     base_h = (entropy ∘ target_designation)(prediction)
#     perturbations = map(i -> perturb_state(prediction, i), 1:N)
#     trs, lgs = zip(perturbations...)
#     entropies = map(entropy ∘ target_designation, trs)
#     elbo(base_h, entropies, lgs)
# end