import IfElse
using SparseArrays: getcolptr

export mask

"""
Random variable describing a mask prediction.
A matrix of bernoullis parametrized by ps::Matrix{Float64}.
Samples a BitMatrix.
"""
struct Mask <: Gen.Distribution{Matrix{Bool}} end

const mask = Mask()


function Gen.random(::Mask, ps::SubArray)
    Gen.random(mask, sparse(ps))
end
function Gen.random(::Mask, ps::AbstractSparseMatrix{Float64})
    xs, ys, vs = findnz(ps)
    result = falses(size(ps))
    @inbounds for i = eachindex(vs)
        result[xs[i], ys[i]] = bernoulli(vs[i])
    end
    return result
end

my_bern(w) = rand() < w

function Gen.random(::Mask, ps::Union{Matrix{Float64},
                                      Fill{Float64}})
    result = Matrix{Bool}(undef, size(ps))
    @inbounds for i in eachindex(ps)
        result[i] = bernoulli(ps[i])
    end
    return result
end

const min_mask_ls = log(1E-4)


function Gen.logpdf(::Mask,
                    image::Matrix{Bool},
                    ps::SparseMatrixCSC{Float64})
    # PDF regions:
    #  a - the intersection between `image` and `ps`
    #  b - the non-zero region of `ps`
    #  c - the non-zero region of `image`
    # @assert size(image) == size(ps) "weights have size $(size(ps)) but mask has size $(size(image))"
    rows = rowvals(ps)
    vs = nonzeros(ps)
    m, n = size(ps)
    ab = 0.
    c = 0
    @inbounds @views @fastmath for j in 1:n
        for i in nzrange(ps, j)
            x = image[rows[i], j]
            v = vs[i]
            ab += x ? log(v) : log(1.0-v)
            c += x
        end
    end
    ni = sum(image)
    nz = length(vs)
    lc = abs(ni - c) * min_mask_ls
    lpdf = ab + lc
    return lpdf
end

function Gen.logpdf(::Mask,
                    image::Matrix{Bool},
                    ps::Matrix{Float64})
    # vmapreduce(bern_vectorized, +, ps, image)
    lpdf = 0.
    @inbounds @views @fastmath for i in indices((ps, image))
        # lpdf += bern_vectorized(ps[i], image[i])
        lpdf += IfElse.ifelse(image[i], log(ps[i]), log(1 - ps[i]))
    end
    return lpdf
end
function Gen.logpdf(::Mask,
                    image::Matrix{Bool},
                    ps::Fill{Float64})
    p = first(ps)
    s = sum(image)
    (s * log(p)) + ((length(image) - s) * log(1.0 - p))
    # (s * p) + ((length(image) - s) * log1mexp(p))
end


(::Mask)(ps) = Gen.random(Mask(), ps)

Gen.has_output_grad(::Mask) = false
Gen.logpdf_grad(::Mask, value::Set, args...) = (nothing,)
