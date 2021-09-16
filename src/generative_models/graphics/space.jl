"""
    Describes how objets get transformed to observation Space
"""

Space{T,N} = AbstractArray{T,N}

function render!(cg::CausalGraph, prev_cg::CausalGraph)::Vector{Space}
    graphics = get_graphics(cg)
    spaces = render!(cg, prev_cg, graphics)
end
function render!(cg::CausalGraph, prev_cg::CausalGraph,
                 graphics::Graphics, diff::Diff)::Vector{Space}
    vs = get_prop(cg, :graphics_vs)
    spaces = Vector{Space{Float64}}(undef, length(vs))
    @inbounds for i = 1:length(vs)
        sp = render_elem!(cg, prev_cg, vs[i],
                          get_prop(cg, vs[i], :object))
        set_prop!(cg, vs[i], :space, sp)
        @inbounds spaces[i] = sp
    end
    return spaces
end

function render!(cg::CausalGraph, prev_cg::CausalGraph,
                 graphics::Graphics)::Vector{Space}
    vs = get_prop(cg, :graphics_vs)
    spaces = Vector{Space{Float64}}(undef, length(vs))
    @inbounds for i = 1:length(vs)
        sp = render_elem!(cg, prev_cg, vs[i],
                          get_prop(cg, vs[i], :object))
        set_prop!(cg, vs[i], :space, sp)
        @inbounds spaces[i] = sp
    end
    return spaces
end

function render_elem!(cg::CausalGraph, prev_cg::CausalGraph,
                      src::Int64, dst::Int64, d::Dot)::Space

    @unpack img_dims, gauss_r_multiple, gauss_amp, gauss_std = (get_prop(cg, :graphics))
    @unpack area_width, area_height = (get_prop(cg, :gm))
    
    # going from area dims to img dims
    x, y = translate_area_to_img(d.pos[1:2]...,
                                 img_dims..., area_width, area_height)
    scaled_r = d.radius/area_width*img_dims[1]
    
    space = draw_gaussian_dot_mask([x,y], scaled_r, img_dims...,
                                   gauss_r_multiple,
                                   gauss_amp, gauss_std)

    if has_prop(prev_cg, src, :flow)
        flow = evolve(get_prop(prev_cg, src, :flow), space)
    else
        @unpack flow_decay_rate = (get_prop(cg, :graphics))
        flow = ExponentialFlow(decay_rate = flow_decay_rate, memory = space)
    end
    set_prop!(cg, dst, :flow, flow)
    
    return flow.memory
end

function render_elem!(cg::CausalGraph, prev_cg::CausalGraph,
                      src::Int64, dst::Int64, e::UniformEnsemble)::Space
    @unpack img_dims = (get_prop(cg, :graphics))
    space = Fill(e.pixel_prob, reverse(img_dims))
end

# # composes the spaces by subtracting occluded parts
# function compose!(spaces::Vector{Space}, cg::CausalGraph, depth_perm::Vector{Int64})
#     @unpack img_dims = (get_prop(cg, :graphics))
#     canvas = zeros(reverse(img_dims)) # reverse to (height, width)

#     for i in depth_perm
#         spaces[i] -= canvas
#         canvas += spaces[i]
#         clamp!(spaces[i], 1e-10, 1.0 - 1e-10)
#     end

#     return nothing
# end

# returns the permutation according to depth (smallest z values first)
function get_depth_perm(cg::CausalGraph, vs::Vector{Int64})
    @>> vs begin
        map(v -> get_pos(get_prop(cg, v, :object))[3])
        sortperm
    end
end
