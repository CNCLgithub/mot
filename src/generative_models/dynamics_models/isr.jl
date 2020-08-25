export ISRDynamics

@with_kw struct ISRDynamics <: AbstractDynamicsModel
    repulsion::Bool = true
    dot_repulsion::Float64 = 100.4
    wall_repulsion::Float64 = 110.9
    distance::Float64 = 40.0
    vel::Float64 = 10.0 # base velocity
    rep_inertia::Float64 = 0.9

    brownian::Bool = false
    inertia::Float64 = 0.8
    spring::Float64 = 0.002
    sigma_x::Float64 = 1.0
    sigma_y::Float64 = 1.0
end

function load(::Type{ISRDynamics}, path::String)
    ISRDynamics(;read_json(path)...)
end

@gen function isr_step(model::ISRDynamics, dot::Dot)
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

    return Dot([x,y,_z], [vx,vy])
end

_isr_step = Map(isr_step)

function isr_repulsion_step(model, dots, gm_params)
    n = length(dots)

    for i = 1:n
        force = zeros(3)
        for j = 1:n
            i == j && continue
            v = dots[i].pos - dots[j].pos
            (norm(v) > model.distance) && continue
            force .+= model.dot_repulsion*exp(-(v[1]^2 + v[2]^2)/(2*model.dot_repulsion^2)) * v / norm(v)
        end
        dot_applied_force = force
                
        # repulsion from walls
        walls = Matrix{Float64}(undef, 4, 3)
        walls[1,:] = [gm_params.area_width/2, dots[i].pos[2], dots[i].pos[3]]
        walls[2,:] = [dots[i].pos[1], gm_params.area_height/2, dots[i].pos[3]]
        walls[3,:] = [-gm_params.area_width/2, dots[i].pos[2], dots[i].pos[3]]
        walls[4,:] = [dots[i].pos[1], -gm_params.area_height/2, dots[i].pos[3]]

        force = zeros(3)
        for j = 1:4
            v = dots[i].pos - walls[j,:]
            (norm(v) > model.distance) && continue
            force .+= model.wall_repulsion*exp(-(v[1]^2 + v[2]^2)/(2*model.wall_repulsion^2)) * v / norm(v)
        end
        wall_applied_force = force

        if sum(dots[i].vel) != 0
            dots[i].vel = model.vel*dots[i].vel/norm(dots[i].vel)
        end
        dots[i].vel = model.rep_inertia*dots[i].vel + (1.0-model.rep_inertia)*(dot_applied_force[1:2]+wall_applied_force[1:2])
    end
    
    return dots
end


@gen function isr_update(model::ISRDynamics, cg::CausalGraph, gm_params) #gm_params::GMMaskParams)
    dots = cg.elements

    if model.repulsion
        dots = isr_repulsion_step(model, dots, gm_params)
    end

    dots = @trace(_isr_step(fill(model, length(dots)), dots), :brownian)

    dots = collect(Dot, dots)
    cg = update(cg, dots)
    return cg
end
