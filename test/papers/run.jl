# Entry point for the paper regression suite.
#
# Usage:
#   PAPER_TESTS=fast julia --project=. test/papers/run.jl
#   PAPER_TESTS=full julia --project=. test/papers/run.jl
#
# `fast` runs the closed-form and analytic checks plus the fixture integrity
# checks. `full` additionally runs the paper 3 country simulations once the
# PaperAdapter core backend is wired (Phase 0).
#
# Baseline capture (`PAPER_TESTS=write`) is specified in
# docs/plans/2026-10-21-wasm-ready-core.md §9.2 and lands with the adapter.

using Test

const PAPER_TESTS = get(ENV, "PAPER_TESTS", "fast")

@info "Paper regression suite" mode = PAPER_TESTS

include("scenarios.jl")
include("paper1.jl")
include("paper2.jl")
include("paper3.jl")
