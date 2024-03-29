export AttentionGaussianPainter


@with_kw struct AttentionGaussianPainter <: Painter
    area_dims::Tuple{Int64, Int64} = (500, 500)
    dims::Tuple{Int64, Int64} = (500, 500)
    attention_color::String = "red"
    opacity::Float64 = 0.7
end

function paint(p::AttentionGaussianPainter, cg::CausalGraph, attention_weights::Vector{Float64})
    points = @>> get_objects(cg, Dot) begin
        map(x -> x.pos[1:2])
        x -> (hcat(x...)')
        x -> Matrix{Float64}(x)
    end

    attention_weights = attention_weights .+ 0.01
    norm_weights = attention_weights /sum(attention_weights)
    weighted_mean = vec(sum(points .* norm_weights, dims=1))
    weighted_cov = cov(points .* norm_weights, dims=1)

    n = 50
    values = Array{Float64, 2}(undef, n, 2)
    for i = 1:n
        values[i, :]  = mvnormal(weighted_mean, weighted_cov)
    end
    p = FixationsPainter(fixations_color = "red")
    MOT.paint(p, values)
end

# function paint(p::AttentionGaussianPainter, cg::CausalGraph, attention_weights::Vector{Float64})
#     points = @>> get_objects(cg, Dot) begin
#         map(x -> x.pos[1:2])
#         x -> (hcat(x...)')
#         x -> Matrix{Float64}(x)
#     end

#     norm_weights = attention_weights/sum(attention_weights)
#     weighted_mean = vec(sum(points .* norm_weights, dims=1))
#     weighted_cov = cov(points .* norm_weights, dims=1)

#     values = Matrix{Float64}(undef, p.dims[1], p.dims[2])

#     for i=1:p.dims[1], j=1:p.dims[2]
#         x = i - p.dims[1]/2
#         y = j - p.dims[2]/2
#         values[i,j] = exp(Gen.logpdf(mvnormal, [x, y], weighted_mean, weighted_cov))
#     end

#     values /= maximum(values)
#     values = reverse(values, dims=2)'

#     _draw_array(values, p.area_dims... , p.dims..., p.attention_color, opacity=p.opacity)
# end
