using EconoSim
using MoneySim

include("test_utils.jl")
include("test_data_analysis.jl")
include("test_transaction_sim.jl")
include("test_plotting.jl")

# Paper-based before/after regression suite. Opt-in so the normal test run stays
# fast: PAPER_TESTS=fast|full julia --project=. test/runtests.jl
if haskey(ENV, "PAPER_TESTS")
    include(joinpath(@__DIR__, "papers", "run.jl"))
end