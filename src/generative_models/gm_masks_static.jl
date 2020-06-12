export gm_masks_static

using LinearAlgebra

struct FullState
    trackers::Vector{Dot}
    pmbrfs_params::Union{PMBRFSParams, Nothing}
end


function get_masks_rvs_args(trackers, graphics_params::Dict)
    # sorted according to depth
    # (smallest values first, i.e. closest object first)
    
    # sorting trackers according to depth for rendering purposes
    depth_perm = sortperm(trackers[:, 3])
    trackers = trackers[depth_perm, :] 

    rvs_args = Vector{Tuple}(undef, length(trackers))
    
    # initially empty image
    img_so_far = zeros(graphics_params["img_height"], graphics_params["img_width"])

    for i=1:size(trackers, 1)
        mask = draw_gaussian_dot(trackers[i,1:2], graphics_params)
        mask = subtract_images(mask, img_so_far)
        img_so_far = add_images(img_so_far, mask)

        rvs_args[i] = (mask,)
    end
    
    # sorting arguments for MBRFS back so that tracker rvs_args[1] corresponds to tracker 1
    rvs_args = rvs_args[invperm(depth_perm)]

    return rvs_args, img_so_far
end


"""
    find_nearest_neighbour(distances::Matrix{Float64}, i::Int)
   
Returns the index of the nearest neighbour
"""
function find_nearest_neighbour(distances::Matrix{Float64}, i::Int)
    d = copy(distances[i,:])
    d[i] = Inf
    #d[d .== 0] .= Inf
    return argmin(d)

    """
    min_distance = Inf
    index = 0

    for j=1:size(distances,1)
        if j != i && min_distance > distances[i,j]
            min_distance = distances[i,j]
            index = j 
        end
    end

    return index
    """
end

"""
    get_masks_params(trackers, params::Params)

Returns the masks parameters (for PMBRFS) - ppp_params, mbrfs_params
i.e. parameters for the pmbrfs random variable describing the masks
"""
function get_masks_params(trackers, params::Dict)
    
    num_trackers = params["inference_params"]["num_trackers"]
    graphics_params = params["graphics_params"]

    # compiling list of x,y,z coordinates of all objects

    objects = [trackers[i].pos[j] for i=1:num_trackers, j=1:3]
    distances = [norm(objects[i,1:2] - objects[j,1:2])
                for i=1:num_trackers, j=1:num_trackers]
    
    """
    objects = Matrix{Float64}(undef, num_trackers , 3)
    for i=1:num_trackers
        objects[i,1] = trackers[i].x
        objects[i,2] = trackers[i].y
        objects[i,3] = trackers[i].z
    end
    distances = Matrix{Float64}(undef, num_trackers, num_trackers)
    for i=1:num_trackers
        for j=1:num_trackers
            a = [objects[i,1], objects[i,2]]
            b = [objects[j,1], objects[j,2]]
            distances[i,j] = dist(a, b)
        end
    end
    """

    # probability of existence of a particular tracker in MBRFS masks set
    rs = zeros(num_trackers)
    scaling = 5.0 # parameter to tweak how close objects have to be to occlude
    missed_detection = 1e-30 # parameter to tweak probability of missed detection

    if num_trackers == 1
       rs = [1.0 - missed_detection]
    else
        for i=1:num_trackers
            j = find_nearest_neighbour(distances, i)
            
            # comparing the depth
            if objects[i,3] > objects[j,3]
                rs[i] = 1.0 - missed_detection
            else
                r = 1.0 - exp(-distances[i,j] * scaling)
                r -= missed_detection
                rs[i] = max(r, 0.0) # lower bound 0.0
            end
        end
    end
    
    rvs = fill(mask, num_trackers)
    rvs_args, trackers_img = get_masks_rvs_args(objects, graphics_params)
    mbrfs_params = MBRFSParams(rs, rvs, rvs_args)

    # explaining distractor with one uniform mask with trackers cutout
    # probability of sampling true on individual pixel given that one distractor is present
    pixel_prob = (graphics_params["dot_radius"]*pi^2)/(graphics_params["img_width"]*graphics_params["img_height"])
    # getting this in the array with size of the image
    mask_prob = fill(pixel_prob, (graphics_params["img_height"], graphics_params["img_width"]))
    #mask_prob[trackers_img] .= 1e-6
    mask_prob = subtract_images(mask_prob, trackers_img)
    mask_params = (mask_prob,)

    ppp_params = PPPParams(params["inference_params"]["num_distractor_rate"], mask, mask_params)

    return ppp_params, mbrfs_params
end


##### INIT STATE ######
@gen function sample_init_tracker(params::Dict)

    init_pos = params["init_pos_spread"]
    x = @trace(uniform(-init_pos, init_pos), :x)
    y = @trace(uniform(-init_pos, init_pos), :y)
    # z (depth) drawn at beginning
    z = @trace(uniform(0, 1), :z)
    
    init_vel_spread = params["init_vel_spread"]
    vx = @trace(normal(0.0, init_vel_spread), :vx)
    vy = @trace(normal(0.0, init_vel_spread), :vy)

    return Dot([x,y,z], [vx,vy])
end
init_trackers_map = Gen.Map(sample_init_tracker)

@gen function sample_init_state(params)
    trackers_params = fill(params, params["inference_params"]["num_trackers"])
    init_trackers = @trace(init_trackers_map(trackers_params), :init_trackers)
    
    return FullState(init_trackers, nothing)
end
######################


##### UPDATE STATE #####
@gen function tracker_update_kernel(tracker::Dot, dynamics_model::DynamicsModel)
    @trace(update_individual(tracker, dynamics_model), :dynamics)
end
trackers_update_map = Gen.Map(tracker_update_kernel)
##################################


@gen (static) function kernel(t::Int,
                     prev_state::FullState,
                     dynamics_model::DynamicsModel,
                     params::Dict)

    prev_trackers = prev_state.trackers

    #trackers_params = fill(params, params.num_trackers)
    dms = fill(dynamics_model, params["inference_params"]["num_trackers"])
    new_trackers = @trace(trackers_update_map(prev_trackers, dms), :trackers)
    
    # get masks params returns parameters for the poisson multi bernoulli
    ppp_params, mbrfs_params = get_masks_params(new_trackers, params)

    # initializing the saved state for the target designation
    pmbrfs_stats = PMBRFSStats([],[],[])
    pmbrfs_params = PMBRFSParams(ppp_params, mbrfs_params, pmbrfs_stats)

    @trace(pmbrfs(pmbrfs_params), :masks)

    # returning this to get target designation and assignment
    # later (HACKY STUFF) saving as part of state
    new_state = FullState(new_trackers, pmbrfs_params)

    return new_state
end

chain = Gen.Unfold(kernel)

@gen (static) function gm_masks_static(T::Int, params::Dict)
    
    dynamics_params = params["dynamics_params"]
    dynamics_model = BrownianDynamicsModel(dynamics_params["inertia"],
                                           dynamics_params["spring"],
                                           dynamics_params["sigma_w"])
    
    init_state = @trace(sample_init_state(params), :init_state)
    states = @trace(chain(T, init_state, dynamics_model, params), :states)

    result = (init_state, states)

    return result
end
