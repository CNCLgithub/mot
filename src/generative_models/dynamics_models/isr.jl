export ISRDynamics

@with_kw struct ISRDynamics <: AbstractDynamicsModel
    repulsion::Bool = true
    dot_repulsion::Float64 = 80.0
    wall_repulsion::Float64 = 50.0
    distance::Float64 = 60.0
    vel::Float64 = 10.0 # base velocity
    rep_inertia::Float64 = 0.9

    brownian::Bool = true
    inertia::Float64 = 0.8
    spring::Float64 = 0.002
    sigma_x::Float64 = 1.0
    sigma_y::Float64 = 1.0
end

function load(::Type{ISRDynamics}, path::String)
    ISRDynamics(;read_json(path)...)
end

@gen function isr_brownian_step(model::ISRDynamics, dot::Dot)
    _x, _y, _z = dot.pos
    vx, vy = dot.vel
    
    if model.brownian
        vx = @trace(normal(model.inertia * vx - model.spring * _x,
                               model.sigma_x), :vx)
        vy = @trace(normal(model.inertia * vy - model.spring * _y,
                               model.sigma_y), :vy)
    end

    x = _x + vx
    y = _y + vy
    
    return Dot(pos=[x,y,_z], vel=[vx,vy],
               pylon_interaction=dot.pylon_interaction)
end

_isr_brownian_step = Map(isr_brownian_step)

function get_repulsion_from_wall(min_distance, wall_repulsion, pos, gm_params)
    # repulsion from walls
    walls = Matrix{Float64}(undef, 4, 3)
    walls[1,:] = [gm_params.area_width/2, pos[2], pos[3]]
    walls[2,:] = [pos[1], gm_params.area_height/2, pos[3]]
    walls[3,:] = [-gm_params.area_width/2, pos[2], pos[3]]
    walls[4,:] = [pos[1], -gm_params.area_height/2, pos[3]]

    force = zeros(3)
    for j = 1:4
        v = pos - walls[j,:]
        (norm(v) > min_distance) && continue
        force .+= wall_repulsion*exp(-(v[1]^2 + v[2]^2)/(min_distance^2)) * v / norm(v)
    end
    return force
end

function get_repulsion_object_to_object(distance, repulsion, pos, other_pos)
    force = zeros(3)
    for j = 1:length(other_pos)
        v = pos - other_pos[j]
        (norm(v) > distance) && continue
        force .+= repulsion*exp(-(v[1]^2 + v[2]^2)/(distance^2)) * v / norm(v)
    end
    return force
end

function get_repulsion_force(model, dots, gm_params)

    n = length(dots)
    rep_forces = Vector{Vector{Float64}}(undef, n)
    positions = map(d->d.pos, dots)

    for i = 1:n
        dot = dots[i]
        
        other_pos = positions[map(j -> i != j, 1:n)]
        dot_applied_force = get_repulsion_object_to_object(model.distance, model.dot_repulsion, dot.pos, other_pos)
        wall_applied_force = get_repulsion_from_wall(model.distance, model.wall_repulsion, dot.pos, gm_params)

        rep_forces[i] = dot_applied_force[1:2]+wall_applied_force[1:2]
    end
    
    rep_forces
end

function isr_repulsion_step(model, dots, gm_params)
    rep_forces = get_repulsion_force(model, dots, gm_params)
    n = length(dots)

    for i = 1:n
        vel = dots[i].vel
        if sum(vel) != 0
            vel *= model.vel/norm(vel)
        end
        vel *= model.rep_inertia
        vel += (1.0-model.rep_inertia)*(rep_forces[i])
        dots[i] = Dot(dots[i].pos, vel)
    end
    
    return dots
end


@gen function isr_update(model::ISRDynamics, cg::CausalGraph, gm_params) #gm_params::GMMaskParams)
    dots = cg.elements

    if model.repulsion
        dots = isr_repulsion_step(model, dots, gm_params)
    end

    dots = @trace(_isr_brownian_step(fill(model, length(dots)), dots), :brownian)

    dots = collect(Object, dots)
    cg = update(cg, dots)
    return cg
end
