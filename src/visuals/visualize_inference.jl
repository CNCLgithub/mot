export visualize,
        get_full_imgs,
        draw_image

function visualize(xy, full_imgs, params, T, num_particles, folder="inference_render")
    # just some non file magic kind of thing
    
    for t=1:length(full_imgs)
        img = full_imgs[t]

        for p=1:num_particles
            for i=1:size(xy,3)
                x = xy[t,p,i,1]
                y = xy[t,p,i,2]
                x, y = translate_area_to_img(x, y, params)

                draw_circle!(img, [x,y], 5.0, false)
                draw_circle!(img, [x,y], 3.0, true)
                draw_circle!(img, [x,y], 1.0, false)
            end
        end

        mkpath(folder)
        filename = "$(lpad(t, 3, "0")).png"
        save(joinpath(folder, filename), img)
    end

end

function get_full_imgs(T, choices, params, folder="masks")
    full_imgs = []
    for t=1:T
        masks = choices[:states => t => :masks]
        for m=1:length(masks)
            filename = "$(lpad(t, 3, "0"))_$(lpad(m, 3,"0")).png"
            mkpath(folder)
            save(joinpath(folder, filename), masks[m]) 
        end
        img = draw_image(masks, params)
        push!(full_imgs, img)
    end
    return full_imgs
end

function draw_image(masks, params)
    img = BitArray{2}(undef, params.img_height, params.img_width)
    img .= false

    for mask in collect(masks)
        img = img .|= mask
    end

    return img
end
