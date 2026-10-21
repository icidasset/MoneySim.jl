# Yard-sale transactions.
#
# Two non-broke actors exchange a fraction of the poorer balance. The direction
# is a weighted coin flip; the winner books income (the loser books expenses).
# The transfer conserves money.

const BROKE_THRESHOLD = Money(100) # 0.01 currency in scaled units

function _rand_non_broke(state::SimState, rng::Rng)
    state.n > 0 || return 0
    for _ in 1:64
        idx = rand_index(rng, state.n)
        if is_alive(state, idx) && state.wealth[idx] >= BROKE_THRESHOLD
            return idx
        end
    end
    return 0
end

function coinflip_prob(asset_value_1::Float64, asset_value_2::Float64,
                       wealth_advantage::Float64,
                       average_wealth::Float64)::Float64
    average = average_wealth > 0.0 ? average_wealth : 1.0
    raw_bias = wealth_advantage * (asset_value_1 - asset_value_2) / average
    bias = min(max(raw_bias, -1.0), 1.0)
    return (1.0 + bias) / 2.0
end

"""
    yardsale_transfer!(state, cfg, rng, average_wealth) -> Money

Execute one yard-sale transfer. Returns the amount moved (zero if the draw was
invalid or the transfer was blocked by the minimum balance).
"""
function yardsale_transfer!(state::SimState, cfg::TransactionConfig,
                            rng::Rng, average_wealth::Float64)
    i = _rand_non_broke(state, rng)
    j = _rand_non_broke(state, rng)
    (i == j || i == 0 || j == 0) && return MONEY_ZERO

    av1 = max(Int64(0), state.wealth[i].value)
    av2 = max(Int64(0), state.wealth[j].value)
    min_balance = min(av1, av2)

    rate_amount = apply_rate(Money(min_balance), cfg.transfer_rate)
    amount = max(min(min_balance, cfg.minimal_transfer.value), rate_amount.value)
    amount <= 0 && return MONEY_ZERO

    probability_first = coinflip_prob(Float64(av1) / SCALE,
                                      Float64(av2) / SCALE,
                                      cfg.wealth_advantage, average_wealth)
    moved = Money(amount)

    if rand_unit(rng) < probability_first
        if cfg.allow_negative || state.wealth[j] >= moved
            state.wealth[i] += moved
            state.income[i] += moved
            state.wealth[j] -= moved
            state.expenses[j] += moved
        end
    else
        if cfg.allow_negative || state.wealth[i] >= moved
            state.wealth[j] += moved
            state.income[j] += moved
            state.wealth[i] -= moved
            state.expenses[i] += moved
        end
    end

    return moved
end

"""
    transactions_step!(state, cfg, rng)

Run the configured number of yard-sale transfers for one simulation step.
"""
function transactions_step!(state::SimState, cfg::TransactionConfig, rng::Rng)
    (cfg.enabled && cfg.transactions_per_step > 0) || return nothing
    average = mean_wealth(state)
    for _ in 1:cfg.transactions_per_step
        yardsale_transfer!(state, cfg, rng, average)
    end
    return nothing
end

"""
    gdp_transactions_step!(state, cfg, gdp, rng)

Run yard-sale transfers until the period's volume target is met.
"""
function gdp_transactions_step!(state::SimState, cfg::TransactionConfig,
                                gdp::GdpConfig, rng::Rng)
    n = alive_count(state)
    n > 0 || return nothing

    if gdp.growth_permyriad != 0
        state.gdp_factor *= 1.0 + Float64(gdp.growth_permyriad) / 120_000.0
    end

    target = Int64(round(Float64(gdp.per_capita.value) * Float64(n) * state.gdp_factor))
    target <= 0 && return nothing

    average = mean_wealth(state)
    volume = Int64(0)
    guard = n * 50
    while volume < target && guard > 0
        amount = yardsale_transfer!(state, cfg, rng, average)
        volume += amount.value
        guard -= 1
    end
    return nothing
end

function transactions_step!(state::SimState, cfg::TransactionConfig,
                            gdp::GdpConfig, rng::Rng)
    if gdp.enabled
        return gdp_transactions_step!(state, cfg, gdp, rng)
    end
    return transactions_step!(state, cfg, rng)
end

export BROKE_THRESHOLD, coinflip_prob, yardsale_transfer!, transactions_step!
export gdp_transactions_step!
