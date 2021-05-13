export AbstractGMParams

abstract type AbstractGMParams end

include("gm_params.jl")
include("utils/utils.jl")
include("dynamics_models/dynamics_models.jl")
include("graphics/graphics.jl")
include("state/state.jl")

include("inertia/gm_inertia.jl")
#include("isr/gm_isr.jl")
#include("squishy/gm_squishy.jl")

#include("receptive_fields/gm_receptive_fields.jl")

include("data_generating_procedures/data_generating_procedures.jl")

