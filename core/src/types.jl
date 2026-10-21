# Configuration and result types for MoneySimCore.
#
# Values are named and grouped by concern. No bare integer codes are used at
# call sites; enums live in small modules so they are always qualified.

module MoneyModel
    const Kind = Int32
    const SUMSY = Int32(1)
    const DEBT_BASED = Int32(2)
    const LOAN_CIRCUIT = Int32(3)
end

module TaxKind
    const Kind = Int32
    const NONE = Int32(0)
    const WEALTH = Int32(1)
    const INCOME = Int32(2)
    const DEMURRAGE = Int32(3)
end

module TaxRecipient
    const Kind = Int32
    const EVERYONE = Int32(0)
    const ONE_ACTOR = Int32(1)
    const DESTROY = Int32(2)
    const FIRST_N = Int32(3)
end

module WealthDistribution
    const Kind = Int32
    const EQUAL = Int32(0)
    const CUSTOM = Int32(1)
    const CONCENTRATED = Int32(2)
end

"""
    MoneyConfig

The money model and its parameters. `interval` is the number of simulation
steps between adjustments; guaranteed income and demurrage are applied once per
interval.
"""
struct MoneyConfig
    model::MoneyModel.Kind
    guaranteed_income::Money
    demurrage::DemTiers
    demurrage_free::Money
    interval::Int
    interest_rate::Int64
end

function MoneyConfig(; model::MoneyModel.Kind = MoneyModel.SUMSY,
                     guaranteed_income::Money = MONEY_ZERO,
                     demurrage::DemTiers = NO_DEM_TIERS,
                     demurrage_free::Money = MONEY_ZERO,
                     interval::Integer = 1,
                     interest_rate::Integer = 0)
    return MoneyConfig(model, guaranteed_income, demurrage, demurrage_free,
                       Int(interval), Int64(interest_rate))
end

"""
    TransactionConfig

Yard-sale transaction settings. `transfer_rate` is permyriad.
"""
struct TransactionConfig
    enabled::Bool
    transactions_per_step::Int
    transfer_rate::Int64
    minimal_transfer::Money
    wealth_advantage::Float64
    allow_negative::Bool
end

function TransactionConfig(; enabled::Bool = false,
                           transactions_per_step::Integer = 0,
                           transfer_rate::Real = 0.2,
                           minimal_transfer::Money = MONEY_ZERO,
                           wealth_advantage::Real = 0.0,
                           allow_negative::Bool = false)
    return TransactionConfig(enabled, Int(transactions_per_step),
                             permyriad(transfer_rate), minimal_transfer,
                             Float64(wealth_advantage), allow_negative)
end

"""
    TaxConfig

Wealth-tax settings for the minimal path. Income and demurrage taxes are added
in Phase 4.
"""
struct TaxConfig
    kind::TaxKind.Kind
    rate::Int64
    interval::Int
    recipient::TaxRecipient.Kind
    recipient_actor::Int
end

function TaxConfig(; kind::TaxKind.Kind = TaxKind.NONE,
                   rate::Real = 0.0,
                   interval::Integer = 0,
                   recipient::TaxRecipient.Kind = TaxRecipient.EVERYONE,
                   recipient_actor::Integer = 0)
    return TaxConfig(kind, permyriad(rate), Int(interval), recipient,
                     Int(recipient_actor))
end

"""
    WealthConfig

Initial wealth distribution. For `CUSTOM`, `custom[i]` is actor `i`'s starting
wealth; missing entries are zero.
"""
struct WealthConfig
    distribution::WealthDistribution.Kind
    equal_amount::Money
    custom::Vector{Money}
end

function WealthConfig(; distribution::WealthDistribution.Kind = WealthDistribution.EQUAL,
                      equal_amount::Money = MONEY_ZERO,
                      custom::Vector{Money} = Money[])
    return WealthConfig(distribution, equal_amount, custom)
end

"""
    PopulationConfig

Fixed population for the minimal path. `gi_eligible` is empty for "everyone is
eligible", otherwise a 1/0 vector of length `count`.
"""
struct PopulationConfig
    count::Int
    gi_eligible::Vector{UInt8}
end

function PopulationConfig(; count::Integer = 100,
                          gi_eligible::Vector{UInt8} = UInt8[])
    return PopulationConfig(Int(count), gi_eligible)
end

"""
    SimConfig

The full simulation configuration. `periods` counts simulation steps;
`record_interval` controls how often aggregates are recorded.
"""
struct SimConfig
    periods::Int
    seed::UInt64
    record_interval::Int
    money::MoneyConfig
    wealth::WealthConfig
    transactions::TransactionConfig
    tax::TaxConfig
    population::PopulationConfig
end

function SimConfig(; periods::Integer = 100,
                   seed::Integer = 42,
                   record_interval::Integer = 1,
                   money::MoneyConfig = MoneyConfig(),
                   wealth::WealthConfig = WealthConfig(),
                   transactions::TransactionConfig = TransactionConfig(),
                   tax::TaxConfig = TaxConfig(),
                   population::PopulationConfig = PopulationConfig())
    return SimConfig(Int(periods), UInt64(seed), Int(record_interval), money,
                     wealth, transactions, tax, population)
end

const CONFIG_OK = Int32(0)
const CONFIG_BAD_PERIODS = Int32(1)
const CONFIG_BAD_RECORD_INTERVAL = Int32(2)
const CONFIG_BAD_POPULATION = Int32(3)
const CONFIG_BAD_MONEY_INTERVAL = Int32(4)
const CONFIG_BAD_TAX_INTERVAL = Int32(5)
const CONFIG_BAD_WEALTH = Int32(6)
const CONFIG_BAD_TRANSFERS = Int32(7)

"""
    validate_config(cfg) -> Int32

Numeric validation code for the wasm ABI. Returns `CONFIG_OK` on success.
"""
function validate_config(cfg::SimConfig)::Int32
    cfg.periods > 0 || return CONFIG_BAD_PERIODS
    cfg.record_interval > 0 || return CONFIG_BAD_RECORD_INTERVAL
    mod(cfg.periods, cfg.record_interval) == 0 || return CONFIG_BAD_RECORD_INTERVAL
    cfg.population.count > 0 || return CONFIG_BAD_POPULATION
    cfg.money.interval > 0 || return CONFIG_BAD_MONEY_INTERVAL
    cfg.tax.interval >= 0 || return CONFIG_BAD_TAX_INTERVAL
    if cfg.wealth.distribution === WealthDistribution.CUSTOM &&
       length(cfg.wealth.custom) < cfg.population.count
        return CONFIG_BAD_WEALTH
    end
    if cfg.transactions.enabled && cfg.transactions.transactions_per_step < 0
        return CONFIG_BAD_TRANSFERS
    end
    if !isempty(cfg.population.gi_eligible) &&
       length(cfg.population.gi_eligible) != cfg.population.count
        return CONFIG_BAD_POPULATION
    end
    return CONFIG_OK
end

export MoneyModel, TaxKind, TaxRecipient, WealthDistribution
export MoneyConfig, TransactionConfig, TaxConfig, WealthConfig, PopulationConfig, SimConfig
export CONFIG_OK, CONFIG_BAD_PERIODS, CONFIG_BAD_RECORD_INTERVAL
export CONFIG_BAD_POPULATION, CONFIG_BAD_MONEY_INTERVAL, CONFIG_BAD_TAX_INTERVAL
export CONFIG_BAD_WEALTH, CONFIG_BAD_TRANSFERS, validate_config
