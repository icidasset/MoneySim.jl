# Simulation orchestration.

struct ConfigError <: Exception
    code::Int32
end

Base.showerror(io::IO, error::ConfigError) =
    print(io, "invalid SimConfig (code ", error.code, ")")

function _resize_results!(results::ResultBuffers, count::Int)
    length(results.gini) == count && return results
    resize!(results.gini, count)
    resize!(results.mean, count)
    resize!(results.total, count)
    resize!(results.min, count)
    resize!(results.max, count)
    resize!(results.income_gini, count)
    resize!(results.shares, count * 6)
    resize!(results.income_shares, count * 6)
    resize!(results.tax_collected, count)
    return results
end

"""
    run_simulation!(cfg, state, results) -> SimResult

Run the configured periods over an existing state and result buffer.
"""
function run_simulation!(cfg::SimConfig, state::SimState, results::ResultBuffers)
    records = div(cfg.periods, cfg.record_interval)
    _resize_results!(results, records)

    reset_state!(state, cfg)
    rng = Rng(cfg.seed)
    index = 0

    for period in 1:cfg.periods
        population_step!(state, cfg.population, period)
        step_money!(state, cfg.money, period)
        transactions_step!(state, cfg.transactions, rng)
        collected = tax_step!(state, cfg.tax, period)

        if mod(period, cfg.record_interval) == 0
            index += 1
            record_period!(results, state, index, collected)
        end
    end

    return SimResult(results, index)
end

"""
    run_simulation(cfg) -> SimResult

Allocate state and result buffers, validate the configuration, and run.
"""
function run_simulation(cfg::SimConfig)
    code = validate_config(cfg)
    code == CONFIG_OK || throw(ConfigError(code))

    state = SimState(cfg.population.count)
    records = div(cfg.periods, cfg.record_interval)
    results = ResultBuffers(records)
    return run_simulation!(cfg, state, results)
end

simulate(cfg::SimConfig) = run_simulation(cfg)

export ConfigError, run_simulation, run_simulation!, simulate
