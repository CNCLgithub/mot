
# projects p onto the line defined by a and b
function _project(p::T, a::T, b::T) where {T <: Vector{Float64}}
    ap = p .- a
    ab = b .- a
    a .+ dot(ap, ab) / dot(ab, ab) * ab
end

function get_repulsion_from_wall(dm::ISRDynamics, pos::Vector{Float64},
                                 walls::Vector{Wall})::Vector{Float64}

    # idea is to project the point onto the walls
    pos_proj = @>> walls map(w -> _project(pos, w.p1, w.p2))

    force = zeros(2)
    for i = 1:4
        v = pos - pos_proj[i]
        absolute_force = dm.wall_repulsion*exp(-(v[1]^2 + v[2]^2)/(dm.distance^2))
        force .+= absolute_force * v/norm(v)
    end
    return force
end


function get_repulsion_object_to_object(dm::ISRDynamics, pos::T,
                                        other_pos::Vector{T})::T where {T <: Vector{Float64}}
    force = zeros(2)
    for j = 1:length(other_pos)
        v = pos - other_pos[j]
        absolute_force = dm.dot_repulsion*exp(-(v[1]^2 + v[2]^2)/(dm.distance^2))
        force .+= absolute_force * v/norm(v)
    end
    return force
end

function get_repulsion_force_dots(cg::CausalGraph)::Vector{Vector{Float64}}
    dm = get_dm(cg)
    dots = get_objects(cg, Dot)

    n = length(dots)
    rep_forces = fill(zeros(2), n)
    positions = map(d->d.pos[1:2], dots)

    for i = 1:n
        dot = dots[i]
        other_pos = positions[map(j -> i != j, 1:n)]

        dot_applied_force = get_repulsion_object_to_object(dm, dot.pos[1:2], other_pos)
        wall_applied_force = get_repulsion_from_wall(dm, dot.pos[1:2], get_walls(cg, dm))
        
        println("WALLLLLL!!!")
        println(wall_applied_force)
        println("DOT!!!!!!")
        println(dot_applied_force)
        println()

        rep_forces[i] = dot_applied_force + wall_applied_force
    end
    
    rep_forces
end

function isr_repulsion_step(cg::CausalGraph)::Vector{Dot}
    rep_forces = get_repulsion_force_dots(cg)

    dm = get_dm(cg)
    dots = get_objects(cg, Dot)

    for i=1:length(dots)
        vel = dots[i].vel
        if sum(vel) != 0
            vel *= dm.vel/norm(vel)
        end
        vel *= dm.rep_inertia
        vel += (1.0-dm.rep_inertia)*(rep_forces[i])
        dots[i] = Dot(pos=dots[i].pos, vel=vel)
    end
    
    return dots
end


function dynamics_init!(dm::ISRDynamics, gm::GMParams,
                        cg::CausalGraph, things)

    ws = init_walls(gm.area_width, gm.area_height)
    for w in walls_idx(dm)
        add_vertex!(cg)
        set_prop!(cg, w, :object, ws[w])
    end
    set_prop!(cg, :walls, walls_idx(dm))
    
    for thing in things
        add_vertex!(cg)
        v = MetaGraphs.nv(cg)
        set_prop!(cg, v, :object, thing)
    end
    
    #cg = dynamics_update!(dm, cg, things)
    return cg
end

function dynamics_update!(dm::ISRDynamics,
                          cg::CausalGraph,
                          things)
    vs = get_object_verts(cg, Dot)

    for (i, thing) in enumerate(things)
        set_prop!(cg, vs[i], :object, thing)
    end

    return cg
end

walls_idx(dm::ISRDynamics) = collect(1:4)

function get_walls(cg::CausalGraph, dm::ISRDynamics)
    @>> walls_idx(dm) begin
        map(v -> get_prop(cg, v, :object))
    end
end