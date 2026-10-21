# Taxes and redistribution.
#
# The minimal path implements the flat wealth levy. Income and demurrage taxes
# are added in Phase 4.

function _add_remainder!(state::SimState, amount::Money, offset::Int = 0)
    # `amount.value` is a count of scaled units (each 1/10,000 currency).
    remaining = amount.value
    remaining <= 0 && return
    count = 0
    for i in eachindex(state.wealth)
        is_alive(state, i) || continue
        count += 1
        count <= offset && continue
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

    # EVERYONE
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
    tax_step!(state, cfg, period) -> Money

Collect and redistribute the configured tax for this period.
"""
function tax_step!(state::SimState, cfg::TaxConfig, period::Int)
    cfg.kind === TaxKind.WEALTH || return MONEY_ZERO
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

    redistribute!(state, collected, cfg.recipient, cfg.recipient_actor)
    return collected
end

export redistribute!, tax_step!
