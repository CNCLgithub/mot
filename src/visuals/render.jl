export render

using Luxor, ImageMagick

"""
    initialize the drawing file according to the frame number,
    position at (0,0) and set background color
"""
function _init_drawing(frame, path, gm;
                       background_color="ghostwhite")
    fname = "$(lpad(frame, 3, "0")).png"
    Drawing(gm.area_width, gm.area_height,
            joinpath(path, fname))
    origin()
    background(background_color)
end

"""
    helper to draw text
"""
function _draw_text(text, position; opacity=1.0, color="black", size=30)
    setopacity(opacity)
    sethue(color)
    Luxor.fontsize(size)
    point = Luxor.Point(position[1], -position[2])
    Luxor.text(text, point, halign=:right, valign=:bottom)
end

"""
    helper to draw circle
"""
function _draw_circle(position, radius, color;
                      opacity=1.0, style=:fill,
                      pattern="solid")
    if style==:stroke
        setline(5)
        setdash(pattern)
    end
    setopacity(opacity)
    sethue(color)
    point = Luxor.Point(position[1], -position[2])
    Luxor.circle(point, radius, style)
end

"""
    helper to draw array (used to draw the predicted tracker masks)
"""
function _draw_array(array, gm, color; opacity=1.0)
    sethue(color)

    tiles = Tiler(gm.area_width, gm.area_height, gm.img_width, gm.img_height, margin=0)

    for (pos, n) in tiles
        # reading value from the array
        row = tiles.currentrow
        col = tiles.currentcol
        value = array[row, col]
        
        # scaling opacity according to the value
        setopacity(opacity*value)

        box(pos, tiles.tilewidth, tiles.tileheight, :fill)
    end
end

"""
    helper to draw arrow
"""
function _draw_arrow(startpoint, endpoint, color;
                     opacity=1.0, style=:fill,
                     linewidth=5.0, arrowheadlength=15.0)
    setopacity(opacity)
    sethue(color)
    p1 = Luxor.Point(startpoint[1], -startpoint[2])
    p2 = Luxor.Point(endpoint[1], -endpoint[2])
    Luxor.arrow(p1, p2, linewidth=linewidth, arrowheadlength=arrowheadlength)
end

function render_object(object::Object)
    error("not defined")
end

function render_object(dot::Dot;
                       leading_edges=true,
                       dot_color="#e0b388",
                       leading_edge_color="#ee70f2",
                       probe_color="#c99665")
    color = dot.probe ? probe_color : dot_color
    _draw_circle(dot.pos[1:2], dot.radius, color)
    if leading_edges
        _draw_circle(dot.pos[1:2], dot.radius, leading_edge_color, style=:stroke)
    end
end

"""
    renders the causal graph
"""
function render_cg(cg::CausalGraph, gm;
                   show_label=true,
                   highlighted::Vector{Int}=Int[],
                   highlighted_color="blue",
                   render_edges=false)
    
    objects = cg.elements

    # furthest (highest z) comes first in depth_perm
    depth_perm = sortperm(map(x -> x.pos[3], objects), rev=true)
    
    for i in depth_perm
        render_object(objects[i])
        if show_label
            _draw_text("$i", objects[i].pos[1:2] .+ [objects[i].width/2, objects[i].height/2])
        end
        if i in highlighted
            _draw_circle(objects[i].pos[1:2], objects[i].width, highlighted_color;
                         style=:stroke, pattern="dash")
        end
    end

    # TODO render edges potentially
end


"""
    helper function to determine opacity based on number of particles
"""

function _get_opacity(particle, n_particles)
    bg_visibility = 1.0 - particle*(1.0/n_particles)
    prev_bg_visibility = 1.0 - (particle-1)*(1.0/n_particles)
    opacity = 1.0 - bg_visibility/prev_bg_visibility
end

"""
    helper function to draw the tracker masks on top of the image
"""
function _render_tracker_masks(tracker_masks, gm;
                               tracker_masks_colors=["indigo", "green", "blue", "yellow"])

    n_particles, n_trackers = size(tracker_masks)

    for p=1:n_particles
        for i=1:n_trackers
            opacity = 0.5 * _get_opacity(p,n_particles)
            _draw_array(tracker_masks[p,i], gm, tracker_masks_colors[i], opacity=opacity)
        end
    end
end

"""
    renders particle filter inferred positions (and velocities) of the tracked objects
    from the causal graph
"""
function render_pf(causal_graph, gm;
                   attended=nothing,
                   pf_color="darkslateblue",
                   show_label=true,
                   render_pos=true,
                   render_vel=false)
    
    n_particles = length(causal_graph)

    for p=1:n_particles
        objects = causal_graph[p].elements

        for i=1:length(objects)
            # drawing the predicted position of this tracker in particle
            if render_pos
                pred_pos = objects[i].pos
                _draw_circle(pred_pos, gm.dot_radius/3, pf_color, opacity=1.0)
            end
            
            if render_vel
                pred_vel = objects[i].vel
                _draw_arrow(pred_pos, pred_pos[1:2] + pred_vel*5, pf_color,
                            opacity=1.0)
            end
            
            if show_label
                _draw_text("$i", pred_pos)
            end
            
            # visualizing attention
            if !isnothing(attended)
                att_opacity = attended[i] * _get_opacity(p, n_particles)
                _draw_circle(pred_pos, 2.5*gm.dot_radius, "red", opacity=att_opacity, style=:stroke)
            end
        end
    end
end


"""
    renders detailed information about inference on top of stimuli

    gm - generative model parameters

    optional:
    dot_positions - (k, n_dots, 3) array with positions of the dots
    probes - (k, n_dots) boolean array describing timesteps to put the probes on
    stimuli - true if we want to render without timestep and inference information
    freeze_time - time before and after movement (for highlighting targets and querying)
    highlighted - array 
"""
function render(gm, k;
                gt_causal_graphs=nothing,
                dot_positions=nothing,
                probes=nothing,
                stimuli=false,
                freeze_time=0,
                highlighted=Int[],
                causal_graphs=nothing,
                attended=nothing,
                array=false,
                tracker_masks=nothing,
                background_color="#7079f2",
                path="render")
    
    # if returning array of images as matrices, then make vector
    array ? imgs = [] : mkpath(path)

    # stopped at beginning
    for t=1:freeze_time
        _init_drawing(t, path, gm, background_color = background_color)
        
        if !isnothing(gt_causal_graphs)
            render_cg(gt_causal_graphs[1], gm;
                      highlighted=collect(1:gm.n_trackers),
                      show_label=!stimuli)
        end
        finish()
    end
    
    # tracking while dots are moving
    # TODO change with good init causal graphs
    for t=1:k
        print("render timestep: $t \r")
        _init_drawing(t+freeze_time, path, gm,
                      background_color = background_color)

        if !stimuli
            _draw_text("$t", [gm.area_width/2 - 100, gm.area_height/2 - 100], size=50)
        end
        
        if !isnothing(gt_causal_graphs)
            render_cg(gt_causal_graphs[t+1], gm;
                      show_label=!stimuli)
        end

        if !isnothing(causal_graphs)
            render_pf(causal_graphs[t,:], gm;
                      attended = isnothing(attended) ? nothing : attended[t])
        end

        if !isnothing(tracker_masks)
            _render_tracker_masks(tracker_masks[t,:,:], gm)
        end

        array ? push!(imgs, image_as_matrix()) : finish()
    end
    # final freeze showing the query
    for t=1:freeze_time
        _init_drawing(t+k+freeze_time, path, gm,
                      background_color = background_color)
        if !isnothing(gt_causal_graphs)
            render_cg(gt_causal_graphs[k+1], gm;
                       highlighted=highlighted,
                       highlighted_color="#d2f72a",
                       show_label=!stimuli)
        end

        finish()
    end
    array && return imgs
end
