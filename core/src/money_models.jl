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
function _lend_to_poorest!(state::SimState, bank::Int, targets::Int,
                           amount::Money)
    (targets > 0 && amount > MONEY_ZERO) || return nothing
    available = alive_count(state) - (is_alive(state, bank) ? 1 : 0)
    targets = min(targets, available)
    targets <= 0 && return nothing

    chosen = fill(false, state.n)
    share, remainder = split_amount(amount, targets)

    for k in 1:targets
        best = 0
        for i in eachindex(state.wealth)
            is_alive(state, i) || continue
            i == bank && continue
            chosen[i] && continue
            if best == 0 || state.wealth[i] < state.wealth[best]
                best = i
            end
        end
        best == 0 && break
        chosen[best] = true
        add = share + (k <= remainder.value ? Money(1) : MONEY_ZERO)
        state.wealth[best] += add
        state.debt[best] += add
    end
    return nothing
end

"""
    bank_step!(state, money, bank)

One post-Keynesian bank step: interest to the bank, principal repayment
(money destruction), then new lending to the poorest actors (money creation).
"""
function bank_step!(state::SimState, money::MoneyConfig, bank::BankConfig)
    bank.enabled || return nothing
    index = bank.actor_index
    (1 <= index <= state.n && is_alive(state, index)) || return nothing

    if money.interest_rate != 0
        for i in eachindex(state.wealth)
            (is_alive(state, i) && i != index && state.debt[i] > MONEY_ZERO) || continue
            interest = min(apply_rate(state.debt[i], money.interest_rate),
                           max(state.wealth[i], MONEY_ZERO))
            if interest > MONEY_ZERO
                state.wealth[i] -= interest
                state.wealth[index] += interest
            end
        end
    end

    if bank.repayment_rate > 0
        for i in eachindex(state.wealth)
            (is_alive(state, i) && i != index && state.debt[i] > MONEY_ZERO) || continue
            repayment = min(apply_rate(state.debt[i], bank.repayment_rate),
                            max(state.wealth[i], MONEY_ZERO))
            if repayment > MONEY_ZERO
                state.wealth[i] -= repayment
                state.debt[i] -= repayment
            end
        end
    end

    _lend_to_poorest!(state, index, bank.lending_targets, bank.lending_amount)
    return nothing
end

"""
    step_money!(state, cfg, period)

Dispatch to the configured money model.
"""
function step_money!(state::SimState, cfg::MoneyConfig, bank::BankConfig,
                     period::Int)
    if cfg.model === MoneyModel.SUMSY
        sumsy_step!(state, cfg, period)
    elseif cfg.model === MoneyModel.DEBT_BASED
        if bank.enabled
            bank_step!(state, cfg, bank)
        else
            debt_step!(state, cfg, period)
        end
    end
    return nothing
end

export sumsy_step!, debt_step!, bank_step!, step_money!
