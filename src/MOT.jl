module MOT

using Gen
using Gen_Compose
using GenRFS
using LinearAlgebra
using FillArrays
using SparseArrays
using StaticArrays
using Lazy: @>, @>> # TODO: remove
using Accessors: setproperties, @set
using Parameters: @with_kw, @unpack, @pack!

include("utils/utils.jl")
include("gms/gms.jl")
include("inference/inference.jl")

include("visuals/visuals.jl")


end
