# Checkpoint

**Phase:** TEST
**Updated:** 2026-03-22

## Current task
Running LCB variance validation — 2 additional runs (run 2 and 3) of baseline + concept v3a on the same 100-problem eval set with same seed 42. API non-determinism provides natural variance.

## Run status
- Run 1 (devlog 32): baseline 80, concept 85 = +5
- Run 2: RUNNING (baseline b8et7397u, concept b0gyqsnfc)
- Run 3: pending (after run 2 completes)

## Key context
- The handoff document is written: `mem_devlog/reports/experiment_results_handoff.md`
- The Marp report is rendered: `mem_devlog/reports/2026_03_21_math_memory_deep_dive.pdf`
- Need 3 total runs to report mean ± std for both baseline and concept

## What we expect
- If +5 is robust: baseline ~78-82, concept ~83-87 across runs
- If +5 is noise: concept could drop to 80-82 range
- Even if the gap narrows, a consistent positive delta across 3 runs is publishable
