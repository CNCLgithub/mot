export PopSensitivity

@with_kw struct PopSensitivity <: AbstractAttentionModel
    # number of unique latents to attend to
    latents::Int = 4
    plan::Function
    plan_args::Tuple
    percept_update::Function
    percept_args::Tuple
    # importance
    importance_tau::Float64 = 1.003
    # arrousal
    init_samples::Int = 15
    min_samples::Int = 5
    max_arrousal::Int = 30
    div_scale::Float64 = 1.0
    x0::Float64 = 5.0
    m::Float64 = 1.0
end

# function load(::Type{PopSensitivity}, path; kwargs...)
#     PopSensitivity(;read_json(path)..., kwargs...)
# end

function AdaptiveComputation(att::PopSensitivity)
    n = att.latents
    base_arrousal = n * att.init_samples
    base_importance = fill(1 / n, n)
    AdaptiveComputation(sensitivities = zeros(n),
                        importance = base_importance,
                        arrousal = base_arrousal)
end

# returns the sensitivity of each latent variable
function hypothesis_testing!(chain::PFChain, att::PopSensitivity)

    @unpack proc, state, auxillary = chain
    @unpack sensitivities, importance, arrousal = auxillary

    cycles_per_latent = round.(Int64, importance .* arrousal)
    @show cycles_per_latent

    # number of particles
    np = length(state.traces)
    # number of latents (usually 4)
    nl = att.latents
    log_particles = log(np)
    # counter for acceptance ratio
    c = 0
    accepted = 0
    for l = 1:nl # for each latent
        # println("on latent $l")
        samples = cycles_per_latent[l] + att.min_samples
        log_steps = log(samples)
        # matrix storing estimates of dPdS
        dPdS = zeros((np, samples))
        for i = 1:np # for each particle
            # initialize objective of S -> P
            s = state.traces[i]
            p = att.plan(s, att.plan_args...)
            for j = 1:samples
                # perceptual update:: S -> (S', dS)
                s_prime, ls = att.percept_update(s, l , att.percept_args...)
                # New objective from planning:: S' -> P'
                p_prime = att.plan(s_prime, att.plan_args...)
                # dP
                dPdS[i, j] = sinkhorn_div(p, p_prime;
                                              scale = att.div_scale)
                # dP/dS
                # dS = log(abs(1.0 - exp(max(0., ls))))
                dS = max(ls, 0.0)
                dPdS[i, j] += dS
                # accepted a proposal and update references
                c +=1
                if log(rand()) < ls
                    accepted += 1
                    s = s_prime
                    p = p_prime
                    # mh reweighting
                    state.log_weights[i] += ls
                end
            end
            state.traces[i] = s
        end
        # @show dPdS
        # normalize dPdS across particles and steps
        sensitivities[l] = logsumexp(dPdS) - log_particles - log_steps
    end
    @show sensitivities
    # update adaptive computation state
    @pack! auxillary = sensitivities
    acceptance = accepted / c
    @pack! auxillary = acceptance
    println("acceptance ratio $(acceptance)")
    return nothing
end

# makes sensitivity weights smoother and softmaxes for categorical sampling
function update_importance!(chain::PFChain, att::PopSensitivity)
    @unpack auxillary = chain
    @unpack sensitivities = auxillary
    importance = softmax(sensitivities; t = att.importance_tau)
    println("importance: $(importance)")
    @pack! auxillary = importance
    return nothing
end

# returns number of sweeps (MH moves) to make determined
# by the sensitivity weights using an exponential function
function update_arrousal!(chain::PFChain, att::PopSensitivity)
    @unpack auxillary = chain
    @unpack sensitivities = auxillary
    @unpack m, max_arrousal, x0 = att
    logsumsens = logsumexp(sensitivities)
    amp = m * (logsumsens + x0)
    arrousal = floor(Int64, clamp(amp, 0., max_arrousal))
    println("arrousal: $(logsumsens) -> $(arrousal)")
    @pack! auxillary = arrousal
    return nothing
end
