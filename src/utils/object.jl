export Object,
        Dot,
        BDot

# objects are things that dynamics models and generative processes
# work over (e.g. Dot)
abstract type Object end

@with_kw mutable struct Dot <: Object
    pos::Vector{Float64} = zeros(3)
    vel::Vector{Float64} = zeros(3)
    probe::Bool = false
end


# dot with bearing
mutable struct BDot <: Object
    pos::Vector{Float64}
    bearing::Float64
    vel::Float64
end
