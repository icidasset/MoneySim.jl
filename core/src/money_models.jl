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
function _paper_interest(remaining::Money, rate::Int64)::Money
    value = Float64(remaining.value) / 10000.0 * (Float64(rate) / 10000.0)
    return Money(round(Int64, value * 10000.0))
end

function _paper_loan(pool::Money, loan_rate::Int64)::Money
    pool <= MONEY_ZERO && return MONEY_ZERO
    rate = Float64(loan_rate) / 10000.0
    rate >= 1.0 && return MONEY_ZERO
    required = (Float64(pool.value) / 10000.0 / (1.0 - rate)) * rate
    required = round(required, digits = 2)
    required <= 0.0 && return MONEY_ZERO
    return Money(round(Int64, required * 10000.0))
end

function _paper_installment(principal::Money, maturity::Int)
    maturity = max(maturity, 1)
    q, r = divrem(principal.value, maturity)
    2r > maturity && return Money(q + 1)
    2r == maturity && return Money(iseven(q) ? q : q + 1)
    return Money(q)
end

function _resync_pro_rata!(state::SimState, old_total::Money, new_total::Money)
    old_total == new_total && return nothing
    n = alive_count(state)
    n == 0 && return nothing

    if new_total <= MONEY_ZERO
        for i in eachindex(state.wealth)
            state.wealth[i] = MONEY_ZERO
        end
        return nothing
    end

    if old_total <= MONEY_ZERO
        share, remainder = split_amount(new_total, n)
        given = 0
        for i in eachindex(state.wealth)
            is_alive(state, i) || continue
            state.wealth[i] = share
            if given < remainder.value
                state.wealth[i] += Money(1)
                given += 1
            end
        end
        return nothing
    end

    total = MONEY_ZERO
    for i in eachindex(state.wealth)
        is_alive(state, i) || continue
        scaled = Float64(state.wealth[i].value) * Float64(new_total.value) /
                 Float64(old_total.value)
        state.wealth[i] = Money(round(Int64, scaled))
        total += state.wealth[i]
    end

    remainder = new_total.value - total.value
    step = remainder > 0 ? Int64(1) : Int64(-1)
    index = 1
    while remainder != 0 && index <= state.n
        if is_alive(state, index)
            state.wealth[index] += Money(step)
            remainder -= step
        end
        index += 1
    end
    return nothing
end

"""
    loan_circuit_step!(state, money, loan, period)

Paper-1 loan circuit. In growth mode every balance accrues interest and debt;
in loan-rate mode the aggregate loan book is amortised and new loans are
created from the remaining pool.
"""
function loan_circuit_step!(state::SimState, money::MoneyConfig,
                            loan::LoanCircuitConfig, period::Int)
    loan.enabled || return nothing

    if loan.mode == 0
        if !state.loan_initialized
            for i in eachindex(state.wealth)
                is_alive(state, i) || continue
                state.debt[i] = max(state.wealth[i], MONEY_ZERO)
            end
            state.loan_initialized = true
        end

        if loan.profit_rate > 0
            for i in eachindex(state.wealth)
                (is_alive(state, i) && state.debt[i] > MONEY_ZERO) || continue
                converted = apply_rate(state.debt[i], loan.profit_rate)
                state.bank_reserve += converted
                state.debt[i] += converted
            end
        end

        if money.interest_rate > 0
            for i in eachindex(state.wealth)
                is_alive(state, i) || continue
                created = apply_rate(state.wealth[i], money.interest_rate)
                state.wealth[i] += created
                state.debt[i] += created
            end
        end
        return nothing
    end

    # Loan-rate mode: aggregate pool + amortisation book.
    maturity = max(loan.maturity, 1)
    pool = total_wealth(state)

    if !state.loan_initialized
        push!(state.loan_book_principal, pool)
        push!(state.loan_book_cycles, maturity)
        push!(state.loan_book_rate, loan.profit_rate)
        push!(state.loan_book_installment, _paper_installment(pool, maturity))
        state.loan_initialized = true
    end

    for l in eachindex(state.loan_book_principal)
        remaining = state.loan_book_principal[l]
        cycles = state.loan_book_cycles[l]
        payment = cycles <= 1 ? remaining : state.loan_book_installment[l]
        interest = _paper_interest(remaining, state.loan_book_rate[l])
        pool -= payment + interest
        state.loan_book_principal[l] = remaining - payment
        state.loan_book_cycles[l] = cycles - 1
    end

    while !isempty(state.loan_book_cycles) && state.loan_book_cycles[1] <= 0
        popfirst!(state.loan_book_principal)
        popfirst!(state.loan_book_cycles)
        popfirst!(state.loan_book_rate)
        popfirst!(state.loan_book_installment)
    end

    new_loan = _paper_loan(pool, money.interest_rate)
    if new_loan > MONEY_ZERO
        pool += new_loan
        push!(state.loan_book_principal, new_loan)
        push!(state.loan_book_cycles, maturity)
        push!(state.loan_book_rate, loan.profit_rate)
        push!(state.loan_book_installment, _paper_installment(new_loan, maturity))
    end

    book_debt = MONEY_ZERO
    for principal in state.loan_book_principal
        book_debt += principal
    end
    state.bank_reserve = book_debt - pool

    old_total = total_wealth(state)
    state.loan_pool = pool
    state.loan_collapsed = pool <= MONEY_ZERO
    _resync_pro_rata!(state, old_total, pool)
    return nothing
end

"""
    step_money!(state, cfg, bank, loan, period)

Dispatch to the configured money model.
"""
function step_money!(state::SimState, cfg::MoneyConfig, bank::BankConfig,
                     loan::LoanCircuitConfig, period::Int)
    if cfg.model === MoneyModel.SUMSY
        sumsy_step!(state, cfg, period)
    elseif cfg.model === MoneyModel.DEBT_BASED
        if bank.enabled
            bank_step!(state, cfg, bank)
        else
            debt_step!(state, cfg, period)
        end
    elseif cfg.model === MoneyModel.LOAN_CIRCUIT
        loan_circuit_step!(state, cfg, loan, period)
    end
    return nothing
end

export sumsy_step!, debt_step!, bank_step!, loan_circuit_step!, step_money!
