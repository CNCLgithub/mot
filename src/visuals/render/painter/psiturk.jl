export PsiturkPainter

@with_kw struct PsiturkPainter <: Painter
    dot_color = "#b4b4b4"
    # highlight = "#ea3433"
    probe_color = "#a0a0a0"
    wall_color = "black"
end

function paint(p::PsiturkPainter, cg::CausalGraph, v::Int64, dot::Dot)
    _draw_circle(dot.pos[1:2], dot.radius, p.dot_color)
    return nothing
end

function paint(p::PsiturkPainter, cg::CausalGraph, v::Int64, w::Wall)
    _draw_arrow(w.p1, w.p2, p.wall_color, arrowheadlength=0.0)
    return nothing
end