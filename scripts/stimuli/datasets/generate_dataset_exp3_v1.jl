using MOT
using Gen


"""
    k - num timesteps
    gm - generative model params
    pis - pylon interactions n_scenes x [ 2 x [ n_dots{Int} ] ]
"""
function get_choicemaps(k, gm,
                        pis::Vector{Vector{Vector{Int}}})
    cms = Vector{Gen.ChoiceMap}(undef, n_scenes)

    for i=1:n_scenes
        cm = choicemap()

        for j=1:Int(gm.n_trackers+gm.distractor_rate)
            cm[:init_state => :trackers => j => :pylon_interaction] = pis[i][1][j]+2
            cm[:kernel => floor(Int, k/2) => :dynamics => :pylon => j => :stay] = false
            cm[:kernel => floor(Int, k/2) => :dynamics => :pylon => j => :pylon_interaction] = pis[i][2][j]+2
        end

        cms[i] = cm
    end
    
    return cms
end



# fastest just to spell it out
pi_22 = [-1, -1, 1, 1, -1, -1, 1, 1]
pi_13 = [-1, -1, -1, 1, -1, -1, -1, 1]
pi_31 = [-1, 1, 1, 1, -1, 1, 1, 1]
pi_04 = fill(-1, 8)
pi_40 = fill(1, 8)

possible_pis = [pi_22, pi_13, pi_31, pi_04, pi_40]
#perms = collect(permutations(possible_pis))

# generating not changing scenes
pis = map(p -> [p, p], possible_pis)

# repeating to generate more scenes
pis = repeat(pis, 4)

println(pis)
#pis = Vector{Vector{Vector{Int}}}(undef, n_scenes)

# pis = [
        # [
         # het_pi,
         # hom_att_pi
        # ],
        # [
         # hom_att_pi,
         # hom_rep_pi
        # ]
      # ]

n_scenes = length(pis)

pylon_strength = 30
vel = 12

dataset_path = joinpath("/datasets", "exp3_v1.jld2")
k = 240
motion = ISRPylonsDynamics(vel = vel,
                           pylon_strength = pylon_strength,
                           pylon_radius = 100.0,
                           pylon_x = 150.0,
                           pylon_y = 150.0)
    
cms = get_choicemaps(k, default_gm, pis)

MOT.generate_dataset(dataset_path, n_scenes, k, default_gm, motion;
                     min_distance = 80.0,
                     cms=cms)

