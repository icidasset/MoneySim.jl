# Taxes, redistribution, and the government deficit.
#
# Phase 4 adds the progressive income tax with optional target-revenue scaling
# and monthly slice collection. The wealth levy remains the flat path.

function _add_remainder!(state::SimState, amount::Money)
    remaining = amount.value
    remaining <= 0 && return
    for i in eachindex(state.wealth)
        is_alive(state, i) || continue
        state.wealth[i] += Money(1)
        remaining -= 1
        remaining <= 0 && break
    end
    return
end

"""
    redistribute!(state, amount, recipient, recipient_actor)

Redistribute collected tax. `DESTROY` extinguishes it; `ONE_ACTOR` sends it to
one actor; `FIRST_N` splits it among the first N alive actors; `EVERYONE`
splits it equally among all alive actors.
"""
function redistribute!(state::SimState, amount::Money,
                       recipient::TaxRecipient.Kind, recipient_actor::Int)
    amount <= MONEY_ZERO && return nothing
    recipient === TaxRecipient.DESTROY && return nothing

    if recipient === TaxRecipient.ONE_ACTOR
        if recipient_actor >= 1 && recipient_actor <= state.n &&
           is_alive(state, recipient_actor)
            state.wealth[recipient_actor] += amount
        end
        return nothing
    end

    if recipient === TaxRecipient.FIRST_N
        targets = min(max(recipient_actor, 0), alive_count(state))
        targets <= 0 && return nothing
        share, remainder = split_amount(amount, targets)
        seen = 0
        for i in eachindex(state.wealth)
            is_alive(state, i) || continue
            seen += 1
            seen > targets && break
            state.wealth[i] += share
        end
        _add_remainder!(state, remainder)
        return nothing
    end

    targets = alive_count(state)
    targets <= 0 && return nothing
    share, remainder = split_amount(amount, targets)
    for i in eachindex(state.wealth)
        is_alive(state, i) || continue
        state.wealth[i] += share
    end
    _add_remainder!(state, remainder)
    return nothing
end

"""
    bracket_tax(taxable, brackets, rates) -> Money

Progressive marginal tax. `brackets[i]` is the cumulative upper bound of band
`i`; the last band is unbounded. `rates[i]` is its permyriad rate.
"""
function bracket_tax(taxable::Money, brackets::Vector{Money},
                     rates::Vector{Int64})::Money
    bands = min(length(brackets), length(rates))
    bands == 0 && return MONEY_ZERO

    remaining = taxable
    tax = MONEY_ZERO
    previous = MONEY_ZERO
    for band in 1:bands
        upper = band == bands ? typemax(Money) : brackets[band]
        width = upper - previous
        in_band = min(max(remaining, MONEY_ZERO), width)
        tax += apply_rate(in_band, rates[band])
        remaining -= in_band
        previous = upper
    end
    return max(tax, MONEY_ZERO)
end

function _scaled_rates(rates::Vector{Int64}, scale::Float64)
    applied = copy(rates)
    for i in eachindex(applied)
        rate_value = Float64(applied[i]) / Float64(PERMYRIAD)
        if rate_value > 0.001 && rate_value < 0.95
            scaled = max(0.001, min(0.95, round(rate_value * scale, digits = 2)))
            applied[i] = round(Int64, scaled * PERMYRIAD)
        end
    end
    return applied
end

"""
    tax_step_wealth!(state, cfg, period) -> Money
"""
function tax_step_wealth!(state::SimState, cfg::TaxConfig, period::Int)
    (cfg.interval > 0 && cfg.rate > 0) || return MONEY_ZERO
    mod(period, cfg.interval) == 0 || return MONEY_ZERO

    collected = MONEY_ZERO
    for i in eachindex(state.wealth)
        is_alive(state, i) || continue
        state.wealth[i] > MONEY_ZERO || continue
        levy = min(apply_rate(state.wealth[i], cfg.rate), state.wealth[i])
        state.wealth[i] -= levy
        collected += levy
    end
    state.tax_scale = 1.0
    redistribute!(state, collected, cfg.recipient, cfg.recipient_actor)
    return collected
end

"""
    tax_step_income!(state, cfg, period) -> Money

Assess at the start of every tax window, then collect one slice per period.
The assessed base is the window's accumulated market income. If
`scale_to_target` is set, the bracket rates are scaled (and clamped to
[0.1%, 95%]) so the assessed total meets `target_revenue`; the recorded scale
is the raw target/projected ratio.
"""
function tax_step_income!(state::SimState, cfg::TaxConfig, period::Int)
    (cfg.interval > 0 && !isempty(cfg.bracket_rates)) || return MONEY_ZERO

    if mod(period - 1, cfg.interval) == 0
        projected = MONEY_ZERO
        for i in eachindex(state.wealth)
            is_alive(state, i) || continue
            base = state.income[i]
            if base > MONEY_ZERO
                projected += bracket_tax(base, cfg.brackets, cfg.bracket_rates)
            end
        end

        applied = cfg.bracket_rates
        if cfg.scale_to_target && cfg.target_revenue > MONEY_ZERO &&
           projected > MONEY_ZERO
            scale = Float64(cfg.target_revenue.value) / Float64(projected.value)
            state.tax_scale = scale
            applied = _scaled_rates(cfg.bracket_rates, scale)
        else
            state.tax_scale = 1.0
        end

        for i in eachindex(state.wealth)
            is_alive(state, i) || continue
            base = state.income[i]
            state.tax_owed[i] = base > MONEY_ZERO ?
                bracket_tax(base, cfg.brackets, applied) : MONEY_ZERO
            state.income[i] = MONEY_ZERO
        end
        state.tax_slices = cfg.interval
    end

    state.tax_slices > 0 || return MONEY_ZERO

    collected = MONEY_ZERO
    for i in eachindex(state.wealth)
        is_alive(state, i) || continue
        owed = state.tax_owed[i]
        owed > MONEY_ZERO || continue
        slice = div(owed, state.tax_slices)
        slice > MONEY_ZERO || continue
        levy = min(slice, max(state.wealth[i], MONEY_ZERO))
        if levy > MONEY_ZERO
            state.wealth[i] -= levy
            state.tax_owed[i] -= levy
            collected += levy
        end
    end
    state.tax_slices -= 1

    redistribute!(state, collected, cfg.recipient, cfg.recipient_actor)
    return collected
end

"""
    tax_step!(state, cfg, period) -> Money
"""
function tax_step!(state::SimState, cfg::TaxConfig, period::Int)
    if cfg.kind === TaxKind.WEALTH
        return tax_step_wealth!(state, cfg, period)
    elseif cfg.kind === TaxKind.INCOME
        return tax_step_income!(state, cfg, period)
    end
    state.tax_scale = 1.0
    return MONEY_ZERO
end

"""
    government_step!(state, government, tax, collected)

Create the deficit when spending exceeds collected tax, add it to public debt,
and distribute it to the tax recipients.
"""
function government_step!(state::SimState, government::GovernmentConfig,
                          tax::TaxConfig, collected::Money)
    government.enabled || return nothing
    government.deficit_spending || return nothing
    government.expenses > collected || return nothing

    deficit = government.expenses - collected
    state.government_debt += deficit
    redistribute!(state, deficit, tax.recipient, tax.recipient_actor)
    return nothing
end

export redistribute!, bracket_tax, tax_step_wealth!, tax_step_income!, tax_step!
export government_step!
