using MOT
using Random

function main()
    Random.seed!(0)

    exp = ExampleExperiment()
    run_inference(exp, "out")
end


main()
