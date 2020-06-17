export get_masks,
        draw_masked_dot,
        draw_gaussian_dot

# translates coordinate from euclidean to image space
function translate_area_to_img(x, y, img_height, img_width,
                               area_height, area_width;
                               whole_number=true)
    x *= img_width/area_width
    x += img_width/2
    if whole_number
        x = round(Int, x)
    end

    # inverting y
    y *= -1 * img_height/area_height
    y += img_height/2
    if whole_number
        y = round(Int, y)
    end
    
    return x, y
end


# draws a dot and subtracts image so far
function draw_masked_dot(pos, img_so_far, r, h, w, ah, aw)
    img_height, img_width = size(img_so_far)
    x, y = translate_area_to_img(pos[1], pos[2], h, w, ah, aw)
    
    mask = BitArray{2}(undef, h, w)
    mask .= false

    radius = r * w / aw
    draw_circle!(mask, [x,y], radius, true)
    
    # getting rid of the intersection
    mask[img_so_far] .= false

    return mask
end

# 2d gaussian function
function two_dimensional_gaussian(x, y, x_0, y_0, A, sigma_x, sigma_y)
    return A * exp(-( (x-x_0)^2/(2*sigma_x^2) + (y-y_0)^2/(2*sigma_y^2)))
end

# drawing a gaussian dot
function draw_gaussian_dot(center::Vector{Float64}, r::Real, h::Int, w::Int)
    
    # standard deviation based on the volume of the Gaussian
    spread_1 = 1.0 # parameter for how spread out the mask is
    spread_2 = 5.0
    A = 0.4999999999
    std_1 = sqrt(spread_1 * r)
    std_2 = sqrt(spread_2 * r)

    img = zeros(h, w)
    for i=1:h
        for j=1:w
            img[j,i] = two_dimensional_gaussian(i, j, center[1], center[2], A, std_1, std_1)
            img[j,i] += two_dimensional_gaussian(i, j, center[1], center[2], A, std_2, std_2)
        end
    end

    return img
end



"""
    get_masks(positions::Array{Float64})

    returns an array of masks
"""
function get_masks(positions::Array{Float64}, r, h, w, ah, aw)
    k, num_dots = size(positions)
    masks = Vector{Vector{BitArray{2}}}(undef, k)
    
    for t=1:k
        pos = positions[t,:,:]

        # sorting according to depth
        depth_perm = sortperm(pos[:, 3])
        pos = pos[depth_perm, :]

        # initially empty image
        img_so_far = BitArray{2}(undef, h, w)
        img_so_far .= false
        
        masks_t = []
        for i=1:num_dots
            mask = draw_masked_dot(pos[i,:], img_so_far, r, h, w, ah, aw)
            push!(masks_t, mask)
            img_so_far = mask .| img_so_far
        end
        masks[t] = masks_t
    end

    return masks
end

