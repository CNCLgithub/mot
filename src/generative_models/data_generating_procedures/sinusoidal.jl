export dgp

function dgp(k::Int, params::GMMaskParams,
             period::Float64)
    # assumes two trackers, one distractor

    positions = zeros(k+10, 3, 3)
    # distractor is fixed at origin
    # one target is fixed at +x
    amp = params.area_width * 0.1
    positions[:, 2, 1] .= -amp
    positions[:, 1, :] .= amp
    for t = 10:k+10
        positions[t, 1, 2] = amp - sin(period * (t-10) * pi / 180) * 2.0 * amp
    end
    # positions[:, 1, 1] .+= params.dot_radius * 0.5
    positions[:, :, 3] = rand(k+10, 3)
    init_pos = positions[1,:,:]
    masks = get_masks(positions[2:end, : ,:], params.dot_radius, params.img_height,
                      params.img_width, params.area_height, params.area_width)
    return init_pos, masks
end
