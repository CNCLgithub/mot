# include("mask.jl")
include("gpp.jl")
include("von_mises.jl")
include("id.jl")
include("log_bern_element.jl")

const gpp_mrfs = MRFS{GaussObs{2}}()
# const mask_rfs = RFS{BitMatrix}()
# const mask_mrfs = MRFS{Matrix{Bool}}()
