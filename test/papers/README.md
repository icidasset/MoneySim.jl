# Paper-based regression suite

This directory holds the before/after test suite for the WASM-ready refactor.
The papers under `jupyter/` are the external oracle; a captured legacy baseline
is the internal oracle.

The full design is in the
[`sim.wasm` plan](https://github.com/HapponomyOrg/sim.wasm/blob/main/docs/plans/2026-10-21-wasm-ready-core.md),
§9.

## Why

The refactor changes the money representation, the RNG, the config shape, and
possibly the rounding. Structural tests alone cannot tell us whether the
economics still behave. The suite compares the same scenario manifest through
two backends:

- `backend = :legacy` — the pre-refactor `MoneySim` implementation;
- `backend = :core` — `MoneySimCore`.

Paper 1 and paper 2 are captured at their paper parameters. Paper 3 is captured
at a reduced scale (default 1,000 actors × 10 years) so the live legacy capture
stays practical; the scale is recorded in the baseline metadata.

## Workflow

```bash
# 1. Capture the legacy baseline (before the refactor / after a manifest change)
PAPER_TESTS=write julia --project=. test/papers/run.jl

# 2. PR suite: legacy paper checks + core-vs-baseline comparison
PAPER_TESTS=fast julia --project=. test/papers/run.jl

# 3. Full suite: also runs every legacy paper-2 equilibrium
PAPER_TESTS=full julia --project=. test/papers/run.jl
```

`write` takes roughly 4–6 minutes (paper 2 dominates). Paper 3 can be captured
at the paper scale for a nightly run:

```bash
PAPER3_BASELINE_ACTORS=10000 PAPER3_BASELINE_YEARS=100 \
  PAPER_TESTS=write julia --project=. test/papers/run.jl
```

The core comparison reads the actor/year scale back from
`fixtures/baseline.toml`, so it always uses the same scale as the captured
legacy run.

## Files

| File | Purpose |
|---|---|
| `scenarios.jl` | Canonical, data-only scenario manifest for papers 1–3 |
| `adapter.jl` | `run_paper1/2/3(...; backend = :legacy/:core)` |
| `compare.jl` | Tolerance-aware before/after comparison |
| `capture_baseline.jl` | Writes `fixtures/baseline.toml` from the legacy backend |
| `fixtures/baseline.toml` | Captured legacy numbers + metadata |
| `paper1.jl` | Exact closed-form assertions from the paper 1 notebook |
| `paper2.jl` | SUMSY scenarios, bounds, consumer–supplier balances |
| `paper3.jl` | Fixture integrity (238 checks) |
| `run.jl` | Entry point; honours `PAPER_TESTS` |

## Paper 1 note

The paper runs `M0 = 1,000,000`. The core comparison uses `M0 = 10,000` because
the ratios are scale-invariant and scaled Int64 cannot represent the paper's
`loan_rate_stable_m30` trajectory (it reaches ~10²⁶ currency). Every
representable scenario is compared on debt ratio, growth ratio, and length;
`loan_rate_stable_m30` is reported as skipped. The same Int64 limit is why the
paper-1 random-growth series saturate instead of growing indefinitely.

## Paper 3 tolerances

The legacy and core RNG streams differ, so paper-3 levels are distribution
checks, not trace checks:

| Comparison | SUMSY scenarios | Fixed-money scenarios |
|---|---|---|
| Gini wealth / income | ±0.06 | ±0.15 |
| Tax scale | ±0.35 | ±0.40 |
| Percentile shares | ±7 pp | ±8 pp |
| Money stock | ±2% | ±2% |
| Public debt | ±2% | ±2% |
| Tax collected | ±2% (5% demurrage tax) | ±2% |

Money, debt, and collected tax are the strict invariants. Direction checks
(`a2 < a1`, `a3 < a1`, `b1 > a1`, `c3.scale > c2.scale`) are release-blocking.
At the paper scale (10,000 actors × 100 years) the SUMSY distributions converge
close to the committed fixtures; the fixed-money c-series is chaotic across RNG
streams.

## Dependencies

`MoneySimCore` and `EconoSimCore` are workspace sources in `Project.toml`:

```toml
[sources]
EconoSimCore = {path = "../EconoSim.jl/core"}
MoneySimCore = {path = "core"}
```

This is a workspace-only source; published packages will use git URLs or
registry versions.

## Paper 3 fixtures

Use only the aggregate CSVs:

```
jupyter/paper 3/data/<scenario>/gini_wealth.csv
jupyter/paper 3/data/<scenario>/gini_income.csv
jupyter/paper 3/data/<scenario>/money_stock.csv
jupyter/paper 3/data/<scenario>/percentile_wealth_data.csv
jupyter/paper 3/data/<scenario>/percentile_income_data.csv
jupyter/paper 3/data/<scenario>/model_data.csv
```

**Do not load `actor_data.csv`.** For `b1` and `c1` it is 64–86 MB and is not
needed for the aggregate checks.

## Adding a scenario

1. Add an entry to `scenarios.jl` with `kind`, `params`, `expected`, and
   `fixture` (if it has a committed CSV).
2. Add any scenario-specific assertion to the matching `paperN.jl`.
3. Re-run `PAPER_TESTS=write` to refresh the baseline.

Keep the manifest declarative: no simulation calls, no imports from `MoneySim`
or `MoneySimCore`.
