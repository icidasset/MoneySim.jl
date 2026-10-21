# Concrete simulation state and result buffers.
#
# State is structure-of-arrays: one vector per actor-level quantity. This is
# the layout the wasm ABI will read and write through scalar accessors.

mutable struct SimState
    n::Int
    wealth::Vector{Money}
    income::Vector{Money}
    expenses::Vector{Money}
    gi_eligible::Vector{UInt8}
    alive::Vector{UInt8}
    age_type::Vector{UInt8}
    scratch::Vector{Float64}
    income_scratch::Vector{Float64}
end

function SimState(n::Integer = 0)
    count = Int(n)
    gi_eligible = Vector{UInt8}(undef, count)
    alive = Vector{UInt8}(undef, count)
    age_type = Vector{UInt8}(undef, count)
    for i in 1:count
        gi_eligible[i] = UInt8(1)
        alive[i] = UInt8(1)
        age_type[i] = UInt8(0)
    end
    return SimState(count,
                    fill(MONEY_ZERO, count),
                    fill(MONEY_ZERO, count),
                    fill(MONEY_ZERO, count),
                    gi_eligible,
                    alive,
                    age_type,
                    Vector{Float64}(undef, count),
                    Vector{Float64}(undef, count))
end

@inline is_alive(state::SimState, i::Int) = state.alive[i] == UInt8(1)

function alive_count(state::SimState)
    count = 0
    for i in eachindex(state.alive)
        state.alive[i] == UInt8(1) && (count += 1)
    end
    return count
end

function reset_state!(state::SimState, cfg::SimConfig)
    n = cfg.population.count

    if state.n != n
        resize!(state.wealth, n)
        resize!(state.income, n)
        resize!(state.expenses, n)
        resize!(state.gi_eligible, n)
        resize!(state.alive, n)
        resize!(state.age_type, n)
        resize!(state.scratch, n)
        resize!(state.income_scratch, n)
        state.n = n
    end

    fill!(state.income, MONEY_ZERO)
    fill!(state.expenses, MONEY_ZERO)
    for i in 1:n
        state.alive[i] = UInt8(1)
        state.age_type[i] = UInt8(0)
    end

    if isempty(cfg.population.gi_eligible)
        for i in 1:n
            state.gi_eligible[i] = UInt8(1)
        end
    else
        copyto!(state.gi_eligible, cfg.population.gi_eligible)
    end

    if cfg.wealth.distribution === WealthDistribution.EQUAL
        for i in 1:n
            state.wealth[i] = cfg.wealth.equal_amount
        end
    elseif cfg.wealth.distribution === WealthDistribution.CUSTOM
        fill!(state.wealth, MONEY_ZERO)
        for i in 1:min(n, length(cfg.wealth.custom))
            state.wealth[i] = cfg.wealth.custom[i]
        end
    else # CONCENTRATED
        fill!(state.wealth, MONEY_ZERO)
        state.wealth[1] = cfg.wealth.equal_amount * n
    end

    return state
end

mutable struct ResultBuffers
    gini::Vector{Float64}
    mean::Vector{Float64}
    total::Vector{Float64}
    min::Vector{Float64}
    max::Vector{Float64}
    income_gini::Vector{Float64}
    shares::Vector{Float64}
    income_shares::Vector{Float64}
    tax_collected::Vector{Float64}
end

function ResultBuffers(count::Integer)
    n = Int(count)
    return ResultBuffers(fill(0.0, n), fill(0.0, n), fill(0.0, n),
                         fill(0.0, n), fill(0.0, n), fill(0.0, n),
                         fill(0.0, n * 6), fill(0.0, n * 6), fill(0.0, n))
end

"""
    SimResult

Per-record aggregate series. `periods` is the number of recorded rows; each
vector has that length, and `shares` has `periods * 6` entries.
"""
struct SimResult
    periods::Int
    gini::Vector{Float64}
    mean::Vector{Float64}
    total::Vector{Float64}
    min::Vector{Float64}
    max::Vector{Float64}
    income_gini::Vector{Float64}
    shares::Vector{Float64}
    income_shares::Vector{Float64}
    tax_collected::Vector{Float64}
end

function SimResult(buffers::ResultBuffers, periods::Int)
    return SimResult(periods, buffers.gini, buffers.mean, buffers.total,
                     buffers.min, buffers.max, buffers.income_gini,
                     buffers.shares, buffers.income_shares,
                     buffers.tax_collected)
end

export SimState, ResultBuffers, SimResult, reset_state!, is_alive, alive_count
