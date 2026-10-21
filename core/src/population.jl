# Population hooks.
#
# The minimal path uses a fixed population initialized by `reset_state!`.
# Births, deaths, aging, and typed GI eligibility follow in Phase 4.

"""
    population_step!(state, cfg, period)

Population dynamics hook. Fixed-population runs are a no-op.
"""
function population_step!(state::SimState, cfg::PopulationConfig, period::Int)
    return nothing
end

"""
    set_gi_eligible!(state, i, eligible)

Set one actor's guaranteed-income eligibility.
"""
function set_gi_eligible!(state::SimState, i::Int, eligible::Bool)
    (1 <= i <= state.n) || return false
    state.gi_eligible[i] = eligible ? UInt8(1) : UInt8(0)
    return true
end

export population_step!, set_gi_eligible!
