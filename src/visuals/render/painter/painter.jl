export Painter, paint, InitPainter

abstract type Painter end

function paint_series(cgs::Vector{CausalGraph}, painters::Vector{Vector{Painter}})
    for (cg, tp) in zip(cgs, painters)
        foreach(p -> paint(p, cg), tp)
        finish()
    end
    return nothing
end

function paint_series(cgs::Vector{Vector{CausalGraph}},
                      painters::Vector{Vector{Painter}})

    for (cg, tp) in zip(cgs, painters)
        foreach(p -> paint(p, cg), tp)
        finish()
    end
    return nothing
end

function paint(p::Painter, cg::CausalGraph)
    @>> cg edges map(e -> paint(p, cg, e))
    @>> cg vertices map(v -> paint(p, cg, v))
    return nothing
end

function paint(p::Painter, cg::CausalGraph, e::Edge)
    return nothing
end

function paint(p::Painter, cg::CausalGraph, v::Int64)
    paint(p, cg, v, get_prop(cg, v, :object))
    return nothing
end

function paint(p::Painter, cg::CausalGraph, v::Int64, o::Object)
    return nothing
end

@with_kw struct InitPainter <: Painter
    path::String
    dimensions::Tuple{Int64, Int64}
    background::String = "#e7e7e7"
end

function paint(p::InitPainter, cg::CausalGraph)
    height, width = p.dimensions
    Drawing(width, height, p.path)
    origin()
    background(p.background)
end


include("psiturk.jl")
include("id.jl")
include("internal_force.jl")
include("kinematics.jl")
include("poly.jl")
include("subset.jl")
include("target.jl")
include("poiss_dot.jl")
include("rf.jl")