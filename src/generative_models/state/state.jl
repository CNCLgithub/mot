@gen function sample_init_tracker(cg::CausalGraph)::Dot
    @unpack area_width, area_height, dot_radius = (get_gm(cg))

    x = @trace(uniform(-area_width/2 + dot_radius, area_width/2 - dot_radius), :x)
    y = @trace(uniform(-area_height/2 + dot_radius, area_height/2 - dot_radius), :y)

    vx = @trace(normal(0.0, 0.1), :vx)
    vy = @trace(normal(0.0, 0.1), :vy)

    # z (depth) drawn at beginning
    z = @trace(uniform(0, 1), :z)

    return Dot(pos=[x,y,z], vel=[vx, vy], radius=dot_radius)
end

@gen function sample_init_state(cg::CausalGraph)
    cg = deepcopy(cg)

    @unpack n_trackers = (get_gm(cg))
    cgs = fill(cg, n_trackers)
    init_trackers = @trace(Gen.Map(sample_init_tracker)(cgs), :trackers)
    ensemble = UniformEnsemble(cg)
    
    dynamics_init!(cg, [ensemble; init_trackers])
    graphics_init!(cg)

    return cg
end
