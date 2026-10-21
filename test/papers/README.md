# Paper-based regression suite

This directory holds the before/after test suite for the WASM-ready refactor.
The papers under `jupyter/` are the external oracle; a captured baseline is the
internal oracle.

The full design is in the
[`sim.wasm` plan](https://github.com/HapponomyOrg/sim.wasm/blob/main/docs/plans/2026-10-21-wasm-ready-core.md),
§9.

## Why

The refactor changes the money representation, the RNG, the config shape, and
possibly the rounding. Structural tests alone cannot tell us whether the
economics still behave. The papers give us concrete numbers:

- **Paper 1** (`jupyter/paper 1/`) — closed-form debt-ratio and growth-ratio
  values for the post-Keynesian loan circuit.
- **Paper 2** (`jupyter/paper 2/`) — SUMSY money-stock equilibria and bounds
  for equal/concentrated starts, injection/destruction, demurrage-free buffers,
  and tiered demurrage.
- **Paper 3** (`jupyter/paper 3/`) — full Belgium reference series, committed
  as CSV under `jupyter/paper 3/data/<scenario>/`.

## Workflow

### 1. Capture the baseline (before the refactor)

```bash
PAPER_TESTS=write julia --project=. test/papers/run.jl
```

This is the intended interface for capturing every scenario through the current
implementation into `fixtures/baseline.json`. The capture runner lands in
Phase 0 together with `adapter.jl`; until then the command runs the checks
below.

### 2. Check after the refactor

```bash
# Fast PR suite: paper 1 + paper 2 short scenarios + paper 3 fixture integrity
PAPER_TESTS=fast julia --project=. test/papers/run.jl

# Full nightly suite: all paper 2 equilibria + paper 3 at 10,000 actors
PAPER_TESTS=full julia --project=. test/papers/run.jl
```

The paper 3 simulation layer is currently a skipped placeholder; it is enabled
when the `PaperAdapter` core backend is wired in Phase 0.

### 3. Adapters

The same manifest is consumed by two adapters:

- `adapter.jl` with `backend = :legacy` — the current `MoneySim` API;
- `adapter.jl` with `backend = :core` — the refactored `MoneySimCore`.

That is what makes the comparison meaningful: the scenarios do not change,
only the implementation.

## Files

| File | Status | Purpose |
|---|---|---|
| `scenarios.jl` | implemented | Canonical, data-only scenario manifest for papers 1–3 |
| `paper1.jl` | implemented | Exact closed-form assertions from the paper 1 notebook |
| `paper2.jl` | implemented | SUMSY scenarios, bounds, and consumer–supplier balances |
| `paper3.jl` | partial | Fixture integrity (238 checks); simulation comparison planned |
| `run.jl` | implemented | Entry point; honours `PAPER_TESTS` |
| `adapter.jl` | planned | Stable interface for `:legacy` and `:core` backends |
| `compare.jl` | planned | Tolerance-aware comparators and report formatting |
| `capture_baseline.jl` | planned | Writes `fixtures/baseline.json` |
| `fixtures/` | planned | Captured baseline snapshots |

## Current status (2026-10-21)

Run against Julia 1.12.6 via `distrobox enter happy`:

```
Paper 1 — post-Keynesian endogenous money | 41 pass
Paper 2 — SUMSY equilibria                | 30 pass (full); 4 scenarios + r1/r2 in fast mode
Paper 3 — fixture integrity               | 238 pass
Paper 3 — simulation comparison           | 1 broken (placeholder)
```

`PAPER_TESTS=full` takes about 7 minutes, dominated by the paper 2
750-period scenarios. `PAPER_TESTS=fast` runs the four short scenarios
(`a1`, `a2`, `b1`, `b2`) plus the consumer–supplier cases and finishes in about
two minutes after compilation.

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

## Tolerances

| Comparison | Rule |
|---|---|
| Native vs wasm, same config/seed | exact (bit-identical) |
| Paper 1 ratios | ±0.1 percentage points (older notebook rounding) |
| Paper 2 analytic bounds | 1% relative |
| Paper 2 r1/r2 balances | 0.1% relative |
| Paper 3 Gini | ±0.01 absolute |
| Paper 3 money stock | ±0.5% relative |
| Paper 3 public debt / tax collected | ±1% relative |
| Paper 3 tax scale | ±0.05 absolute |
| Paper 3 percentile shares | ±1.5 percentage points |

If the refactor intentionally changes the RNG stream, year-by-year paper 3
traces may exceed these tolerances. The runner reports trace and distribution
results separately; only the distribution checks are release-blocking.

## Adding a scenario

1. Add an entry to `scenarios.jl` with `kind`, `params`, `expected`, and
   `fixture` (if it has a committed CSV).
2. Add any scenario-specific assertion to the matching `paperN.jl`.
3. Re-run `PAPER_TESTS=write` to refresh the baseline.

Keep the manifest declarative: no simulation calls, no imports from `MoneySim`
or `MoneySimCore`.
