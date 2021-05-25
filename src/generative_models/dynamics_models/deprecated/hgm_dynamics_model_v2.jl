export HGMDynamicsModel
using LightGraphs, MetaGraphs



@with_kw struct HGMDynamicsModel <: AbstractDynamicsModel
    inertia::Float64 = 0.8
    spring::Float64 = 0.002
    sigma_x::Float64 = 0.005
    sigma_y::Float64 = 0.005
    
    # # brownian motion on a spring with regards to polygon positions
    # pol_inertia::Float64 = 0.00001
    # pol_spring::Float64 = 0.01
    # pol_sigma_x::Float64 = 0.001
    # pol_sigma_y::Float64 = 0.001
    # pol_ang_vel_sigma::Float64 = 0.005

    # repulsion
    dot_repulsion::Float64 = 10.0
    wall_repulsion::Float64 = 10.0
    distance::Float64 = 100.0
    vel::Float64 = 10.0 # base velocity
    rep_inertia::Float64 = 0.9
    pol_pol_repulsion::Float64 = 0.0
    pol_wall_repulsion::Float64 = 0.0
    pol_pol_distance::Float64 = 100.0
    pol_wall_distance::Float64 = 150.0
end

function load(::Type{HGMDynamicsModel}, path::String)
    HGMDynamicsModel(;read_json(path)...)
end

@gen function hgm_brownian_step(model::HGMDynamicsModel, object::Object)

    _x, _y, _z = object.pos
    _vx, _vy = object.vel

    vx = @trace(normal(model.inertia * _vx - model.spring * _x,
                               model.sigma_x), :vx)
    vy = @trace(normal(model.inertia * _vy - model.spring * _y,
                               model.sigma_y), :vy)
    x = _x + vx
    y = _y + vy

    #z = @trace(uniform(0, 1), :z)
    z = _z

    if isa(object, Dot)
        return Dot([x,y,z], [vx,vy])

    elseif isa(object, Polygon)
        dots = Vector{Dot}(undef, length(object.dots))

        ang_vel = @trace(normal(0.95*object.ang_vel, model.pol_ang_vel_sigma), :ang_vel)
        rot = object.rot + ang_vel

        for i=1:length(dots)
            _dot_x, _dot_y = object.dots[i].pos
            _dot_vx, _dot_vy = object.dots[i].vel
    
            println("inside here")
            println(_dot_vx, _dot_vy)
            
            # finding the center position defined by the polygon
            r = object.radius
            c_dot_x = x + r * cos(2*pi*i/length(dots) + rot)
            c_dot_y = y + r * sin(2*pi*i/length(dots) + rot)

            dot_vx = @trace(normal(model.pol_inertia * _dot_vx - model.pol_spring * (_dot_x - c_dot_x),
                                       model.pol_sigma_x), i => :vx)
            dot_vy = @trace(normal(model.pol_inertia * _dot_vy - model.pol_spring * (_dot_y - c_dot_y),
                                       model.pol_sigma_y), i => :vy)
            dot_x = _dot_x + dot_vx + vx
            dot_y = _dot_y + dot_vy + vy

            dots[i] = Dot([dot_x, dot_y, z], [dot_vx, dot_vy])
        end

        return Polygon([x,y,z], [vx,vy],
                       rot, ang_vel,
                       object.radius, dots)
    end
end

_hgm_brownian_step = Map(hgm_brownian_step)


function get_new_dot(index, model, rep_forces, dot)
    vel = model.rep_inertia*dot.vel + (1.0 - model.rep_inertia) * rep_forces[index]
    if sum(vel) != 0
        vel *= model.vel/norm(vel)
    end
    index += 1
    return Dot(dot.pos, vel), index
end


function get_new_polygon(index, model, pol_rep_forces, polygon)
    pos = polygon.pos
    vel = polygon.vel
    rot = polygon.rot
    ang_vel = polygon.ang_vel
    radius = polygon.radius
    dots = polygon.dots

    vel = model.rep_inertia*vel + (1.0-model.rep_inertia)*pol_rep_forces[index]
    if sum(vel) != 0
        vel *= model.vel/norm(vel)
    end
    return Polygon(pos, vel, rot, ang_vel, radius, dots), index+1
end


# gets forces on dots from polygon-wall repulsion
function get_pol_rep_forces(model, objects, hgm, n_dots::Int)
    pol_rep_forces = []

    positions = map(x -> x.pos, objects)
    polygons = map(x -> x isa Polygon, objects)
    
    for i=1:length(objects)
        # if objects[i] isa Dot
            # push!(pol_rep_forces, zeros(2))
        # elseif objects[i] isa Polygon
        if objects[i] isa Polygon
            wall_force = get_repulsion_from_wall(model.pol_wall_distance,
                                                 model.pol_wall_repulsion,
                                                 objects[i].pos,
                                                 hgm)

            #println("wall_force $wall_force")

            others = map(j -> i != j, 1:length(objects))
            other_pos = positions[polygons .& others]
            
            pol_force = get_repulsion_object_to_object(model.pol_pol_distance,
                                                       model.pol_pol_repulsion,
                                                       objects[i].pos,
                                                        other_pos)

            #println("pol_force $pol_force")

            force = wall_force + pol_force
            #append!(pol_rep_forces, fill(force[1:2], length(objects[i].dots)))
            push!(pol_rep_forces, force[1:2])
        end
    end
    
    println("pol_rep_forces $pol_rep_forces")
    return pol_rep_forces
end


function hgm_repulsion_step(model, objects, hgm)

    dots = []
    for object in objects
        if isa(object, Polygon)
            dots = [dots; object.dots]
        elseif isa(object, Dot)
            push!(dots, object)
        end
    end
    
    n_dots = length(dots)

    # polygon-wall repulsion
    pol_rep_forces = get_pol_rep_forces(model, objects, hgm, n_dots)

    # individual dot-dot and dot-wall repulsion
    dot_rep_forces = get_repulsion_force_dots(model, dots, hgm)
    
    println()
    println("pol_rep_forces $pol_rep_forces")
    println("dot_rep_forces $dot_rep_forces")
    println()

    #rep_forces = pol_rep_forces + dot_rep_forces
    
    # keeping track to index into the correct forces
    pol_index = 1
    dot_index = 1
    for i=1:length(objects)
        if objects[i] isa Polygon
            objects[i], pol_index = get_new_polygon(pol_index, model, pol_rep_forces, objects[i])
            
            for j=1:length(objects[i].dots)
                objects[i].dots[j], dot_index = get_new_dot(dot_index, model, dot_rep_forces, objects[i].dots[j])
            end

        elseif objects[i] isa Dot
            objects[i], dot_index = get_new_dot(dot_index, model, dot_rep_forces, objects[i])
        end
    end
    return objects
end

get_n_dots(object) = object isa Dot ? 1 : length(object.dots)

function create_hgm_graph(objects)
    n_polygons = @>> objects map(x -> x isa Polygon) sum
    n_dots = @>> objects map(get_n_dots) sum
    g = MetaGraph(n_polygons + n_dots)

    @>> 1:n_polygons foreach(i -> set_prop!(g, i, :type, :centroid))
    @>> n_polygons+1:n_polygons+n_dots foreach(i -> set_prop!(g, i, :type, :dot))
    @>> 1:nv(g) foreach(i -> display(get_prop(g, i, :type)))
end

@gen function hgm_update(model::HGMDynamicsModel, cg::CausalGraph, hgm)
    objects = cg.elements
    hgm_graph = create_hgm_graph(objects)
    error()
    repulsion_forces = calculate_repulsion_forces(hgm_graph) 

    objects = hgm_repulsion_step(model, objects, hgm)
    objects = @trace(_hgm_brownian_step(fill(model, length(objects)), objects), :brownian)
    objects = collect(Object, objects)
    cg = update(cg, objects)
    return cg
end



