using MOT
using JLD2
using CSV
using DataFrames
using Lazy: @>>
using GLM
using Plots; pyplot()
using Statistics

dataset_path = "output/datasets/exp3_polygons_v3.jld2"
file = jldopen(dataset_path, "r")
n_scenes = file["n_scenes"]
close(file)
#scenes = map(i -> MOT.load_scene(i, dataset_path, HGMParams(); generate_masks=false), 1:n_scenes)

get_polygon_structure(scene_data) = scene_data[:aux_data][:scene_structure]
get_targets(scene_data) = scene_data[:aux_data][:targets]

polygons = map(i -> get_polygon_structure(scenes[i]), 1:n_scenes)
targets = map(i -> get_targets(scenes[i]), 1:n_scenes)

# get number of dots and vertices represented
function get_num_d_v(polygons, targets)
    num_d = 0
    num_v = 0
    index = 1
    for pol in polygons
        # just a dot
        if pol == 1 && targets[index] == 1
            num_d += 1
            num_v += 1
        elseif any(targets[index:index+pol-1])
            # polygon with at least one target
            num_d += 1
            num_v += pol
        end
        index += pol
    end
    
    num_d, num_v
end

num_d_v = @>> zip(polygons, targets) map(x -> get_num_d_v(x...))

df = CSV.File("output/subject/exp3_polygons_v3_td.csv") |> DataFrame

df[!, "n_d"] = @>> num_d_v map(first)
df[!, "n_v"] = @>> num_d_v map(last)

display(mean(df.td))
ols = lm(@formula(td ~ n_d + n_v + 1), df)
display(ols)

scatter(predict(ols), df.td)
txts = []
for (i, scene) in enumerate(df.scene)
    annotate!([(predict(ols)[i], df.td[i], "$scene")])
end

#heatmap(df.n_d, df.n_v, df.td)

