# MoneySimCore

Dependency-free simulation core for MoneySim. It depends only on
`EconoSimCore`; there are no Agents.jl, DataFrames, plotting, or wasm tooling
dependencies.

This is Phase 2 of the wasm-ready core plan. The canonical plan lives in
`sim.wasm/docs/plans/2026-10-21-wasm-ready-core.md`.

## What is here

| File | Contents |
|---|---|
| `src/types.jl` | `SimConfig`, `MoneyConfig`, `TransactionConfig`, `TaxConfig`, `WealthConfig`, `PopulationConfig`; named config values |
| `src/state.jl` | `SimState` (structure-of-arrays), `ResultBuffers`, `SimResult` |
| `src/metrics.jl` | Gini, mean/total/min/max, cumulative percentile shares, income Gini |
| `src/transactions.jl` | Yard-sale transactions with an explicit `Rng` |
| `src/taxes.jl` | Wealth levy and all four recipient modes |
| `src/money_models.jl` | SUMSY (GI + demurrage) and homogeneous debt-based interest |
| `src/population.jl` | Fixed population and GI eligibility |
| `src/run.jl` | `run_simulation` / `run_simulation!` |

## Test

```bash
julia --project=core -e 'using Pkg; Pkg.test()'
```

## Status

- 41 native tests pass.
- The full SUMSY + yard-sale + wealth-tax path runs under WasmTarget through
  `sim.wasm/wasm/`; the final Gini is bit-identical to native
  (`0.32961367869746727`).

## Configuration style

Config values are grouped by concern and use named values, for example:

```julia
SimConfig(
    periods = 30_000,
    record_interval = 30,
    population = PopulationConfig(count = 100),
    wealth = WealthConfig(distribution = WealthDistribution.EQUAL,
                          equal_amount = money(0)),
    money = MoneyConfig(model = MoneyModel.SUMSY, interval = 30,
                        guaranteed_income = money(2_000),
                        demurrage = make_tiers(0.01)),
    transactions = TransactionConfig(enabled = false),
    tax = TaxConfig(kind = TaxKind.NONE))
```

WasmTarget 0.5.3 cannot lower `@enum` equality, so the named values are
`const Int32` constants in small modules. Call sites and the future schema are
unaffected.

## Not here yet (Phase 4)

- Income tax / brackets / target revenue; demurrage tax; VAT.
- Demographics (births, deaths, aging, typed GI eligibility).
- Government / deficit spending and public debt.
- GDP volume target and growth.
- Money injection/destruction adaptations.
- The post-Keynesian bank and loan circuit.
- Tax-scale reporting.
