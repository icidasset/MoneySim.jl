# Money injection and destruction adaptations.
#
# A constant total amount is created or destroyed every interval and split
# equally among alive actors. Injection is booked as income; destruction never
# takes a balance below zero.

function _sweep_inject!(state::SimState, amount::Money)
    targets = alive_count(state)
    targets <= 0 && return nothing
    share, remainder = split_amount(amount, targets)
    given = 0
    for i in eachindex(state.wealth)
        is_alive(state, i) || continue
        state.wealth[i] += share
        state.income[i] += share
        if given < remainder.value
            state.wealth[i] += Money(1)
            state.income[i] += Money(1)
            given += 1
        end
    end
    return nothing
end

function _sweep_destroy!(state::SimState, amount::Money)
    targets = alive_count(state)
    targets <= 0 && return nothing
    share, remainder = split_amount(amount, targets)
    given = 0
    for i in eachindex(state.wealth)
        is_alive(state, i) || continue
        take = min(share, max(state.wealth[i], MONEY_ZERO))
        state.wealth[i] -= take
        if given < remainder.value && state.wealth[i] > MONEY_ZERO
            extra = min(Money(1), state.wealth[i])
            state.wealth[i] -= extra
            given += 1
        end
    end
    return nothing
end

"""
    adaptations_step!(state, cfg, period)
"""
function adaptations_step!(state::SimState, cfg::AdaptationConfig, period::Int)
    if cfg.inject_enabled && cfg.inject_amount > MONEY_ZERO &&
       cfg.inject_interval > 0 && mod(period, cfg.inject_interval) == 0
        _sweep_inject!(state, cfg.inject_amount)
    end

    if cfg.destroy_enabled && cfg.destroy_amount > MONEY_ZERO &&
       cfg.destroy_interval > 0 && mod(period, cfg.destroy_interval) == 0
        _sweep_destroy!(state, cfg.destroy_amount)
    end
    return nothing
end

export adaptations_step!
