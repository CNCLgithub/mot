export generate_dataset, is_min_distance_satisfied, are_dots_inside


_n_dots(x::MOT.Dot) = 1
_n_dots(x::MOT.Polygon) = length(x.dots)

function are_dots_inside(scene_data, gm)
    xmin, xmax = -gm.area_width/2 + gm.dot_radius, gm.area_width/2 - gm.dot_radius
    ymin, ymax = -gm.area_height/2 + gm.dot_radius, gm.area_width/2 - gm.dot_radius
    
    cg = first(scene_data[:gt_causal_graphs])
    n_dots = sum(map(x -> _n_dots(x), cg.elements))
    positions = get_hgm_positions(cg, fill(true, n_dots))

    satisfied = map(i ->
                    positions[i][1] > xmin &&
                    positions[i][1] < xmax &&
                    positions[i][2] > ymin &&
                    positions[i][2] < ymax,
                    1:n_dots)

    all(satisfied)    
end

function is_min_distance_satisfied(scene_data, min_distance;
                                   polygon_min_distance = 2.5 * min_distance)
    cg = first(scene_data[:gt_causal_graphs])
    n_dots = @>> cg.elements map(x -> _n_dots(x)) sum
    positions = get_hgm_positions(cg, fill(true, n_dots))
    
    # checking whether polygons are at the right distance if there are any
    if @>> cg.elements map(x -> x isa Polygon) any
        pos_pols = @>> cg.elements filter(x -> x isa Polygon) map(x->x.pos)
        n_pols = length(pos_pols)
        distances_idxs = Iterators.product(1:n_pols, 1:n_pols)
        distances = @>> distances_idxs map(xy -> MOT.dist(pos_pols[xy[1]][1:2], pos_pols[xy[2]][1:2]))
        satisfied = @>> distances map(distance -> distance == 0.0 || distance > polygon_min_distance)
        if !all(satisfied)
            return false
        end
    end
    
    distances_idxs = Iterators.product(1:n_dots, 1:n_dots)
    distances = @>> distances_idxs map(xy -> MOT.dist(positions[xy[1]][1:2], positions[xy[2]][1:2]))
    satisfied = @>> distances map(distance -> distance == 0.0 || distance > min_distance)
    all(satisfied)
end

function generate_dataset(dataset_path, n_scenes, k, gms, motion;
                          min_distance = 50.0,
                          cms::Union{Nothing, Vector{ChoiceMap}} = nothing,
                          aux_data::Union{Nothing, Vector{Any}} = nothing)
    
    jldopen(dataset_path, "w") do file 
        file["n_scenes"] = n_scenes
        for i=1:n_scenes
            println("generating scene $i/$n_scenes")
            scene_data = nothing

            # if no choicemaps, then create an empty one
            cm = isnothing(cms) ? choicemap() : cms[i]
            
            tries = 0
            while true
                tries += 1
                println("$tries \r")
                scene_data = dgp(k, gms[i], motion;
                                 generate_masks=false,
                                 cm=cm)
                if are_dots_inside(scene_data, gms[i]) && is_min_distance_satisfied(scene_data, min_distance)
                    break
                end
            end

            scene = JLD2.Group(file, "$i")
            scene["gm"] = gms[i]
            scene["motion"] = motion
            scene["aux_data"] = isnothing(aux_data) ? nothing : aux_data[i]

            gt_cgs = scene_data[:gt_causal_graphs]
            # fixing z according to the time 0
            z = map(x->x.pos[3], gt_cgs[1].elements)
            map(cg -> map(i -> cg.elements[i].pos[3] = z[i],
                          collect(1:length(cg.elements))),
                          gt_cgs)
            scene["gt_causal_graphs"] = gt_cgs
        end
    end
end
