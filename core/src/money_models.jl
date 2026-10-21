# Money-model steps.
#
# Phase 2 implements SUMSY fully and the legacy homogeneous-interest debt model.
# The post-Keynesian bank and loan circuit follow in Phase 4.

"""
    sumsy_step!(state, cfg, period)

Apply demurrage and guaranteed income every `cfg.interval` steps. Demurrage is
charged on the opening balance above `demurrage_free`, then eligible actors
receive the guaranteed income.
"""
function sumsy_step!(state::SimState, cfg::MoneyConfig, period::Int)
    (cfg.interval > 0 && mod(period, cfg.interval) == 0) || return nothing

    sumsy = SuMSy(cfg.guaranteed_income, cfg.demurrage, cfg.demurrage_free)
    for i in eachindex(state.wealth)
        is_alive(state, i) || continue
        guaranteed_income, demurrage = calculate_adjustments(
            state.wealth[i], sumsy, state.gi_eligible[i] == UInt8(1),
            cfg.demurrage_free, cfg.interval, cfg.interval, false)
        state.wealth[i] += guaranteed_income - demurrage
    end
    return nothing
end

"""
    debt_step!(state, cfg, period)

Homogeneous interest model: with no designated bank, every balance grows by the
interest rate each interval. The bank/loan-circuit mechanics are Phase 4.
"""
function debt_step!(state::SimState, cfg::MoneyConfig, period::Int)
    (cfg.interval > 0 && mod(period, cfg.interval) == 0) || return nothing
    cfg.interest_rate == 0 && return nothing

    for i in eachindex(state.wealth)
        is_alive(state, i) || continue
        state.wealth[i] += apply_rate(state.wealth[i], cfg.interest_rate)
    end
    return nothing
end

"""
    step_money!(state, cfg, period)

Dispatch to the configured money model.
"""
function step_money!(state::SimState, cfg::MoneyConfig, period::Int)
    if cfg.model === MoneyModel.SUMSY
        sumsy_step!(state, cfg, period)
    elseif cfg.model === MoneyModel.DEBT_BASED
        debt_step!(state, cfg, period)
    end
    return nothing
end

export sumsy_step!, debt_step!, step_money!
