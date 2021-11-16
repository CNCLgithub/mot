export render_rf_masks

#using PaddedViews
using ImageTransformations

# this takes masks within one receptive field and superimposes them
aggregate_masks(masks::Vector{Matrix{Float64}}) = sum(masks)
_or = (x, y) -> x .| y
aggregate_masks(masks::Vector{BitMatrix}) = reduce(_or, rf_masks)

# takes already aggregated_masks for each receptive_field and
# also a vector of receptive_fields and returns the full composed
# img to save
function get_img(aggregated_masks::Vector{Matrix{Float64}})::Matrix{Float64}
    # we take the last receptive_field and take the second point
    # to find the full dimensions of the image
    (dim2, dim1) = receptive_fields[end].p2
    img = zeros(dim1, dim2)
    
    for (i, rf) in enumerate(receptive_fields)
        img[rf.p1[2], rf.p1[1]:rf.p2[1]] .= 0.5
        img[rf.p2[2], rf.p1[1]:rf.p2[1]] .= 0.5
        img[rf.p1[2]:rf.p2[2], rf.p1[1]] .= 0.5
        img[rf.p1[2]:rf.p2[2], rf.p2[1]] .= 0.5
    end

    for (i, rf) in enumerate(receptive_fields)
        img[rf.p1[2]:rf.p2[2], rf.p1[1]:rf.p2[1]] += aggregated_masks[i]
    end
    
    clamp!(img, 0.0, 1.0)

    return img
end

function get_masks(cgs::Vector{CausalGraph}, t::Int64)::Vector{Matrix{Float64}}
    vs = get_prop(cgs[t], :graphics_vs)
    rf_masks = @>> vs begin
        map(v -> get_prop(cgs[t], v, :space))
        cropfilter(receptive_fields[rf])
    end
    # println("predicted masks")
    # for v in vs
    #     display(get_prop(cgs[t], v, :space))
    # end
    return rf_masks
end

function get_rf_masks(choices::ChoiceMap, t::Int64,
                      receptive_fields::Vector{RectangleReceptiveField})::Vector{BitArray}
    masks = choices[:kernel => t => :masks]
    if isempty(masks)
        @unpack p1, p2 = receptive_fields[rf]
        masks = [falses((p2[1] - p1[1] + 1, p2[2] - p1[2] + 1))]
    end
    # println("gt masks")
    # @show length(masks)
    # for m in masks
    #     display(sparse(m))
    # end
    masks
end

function render_rf_masks(data::Union{Vector{CausalGraph}, ChoiceMap}, t::Int64,
                         gm::AbstractGMParams,
                         graphics::AbstractGraphics)
    masks = get_masks(data, t)
    aggregated = aggregate_masks(masks)
    img = get_img(aggregated)
    imresize(img, ratio=gm.area_width/size(img, 1))
end
function render_rf_masks(data::Union{Vector{CausalGraph}, ChoiceMap}, t::Int64,
                         gm::AbstractGMParams,
                         graphics::AbstractGraphics,
                         out_dir::String)
    img = render_rf_masks(data, t, gm, graphics)
    path = joinpath(out_dir, "$t.png")
    save(path, img)
end
