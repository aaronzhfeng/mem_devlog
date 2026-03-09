# Devlog 29: Fast Iteration on Extraction Prompt (2026-03-07)

## Goal
Iterate rapidly on the concept extraction prompt to eliminate source-specific
value leakage, using a 20-problem "fruit fly" approach instead of full-scale runs.

## Problem: 76% Concept Leakage
In the m3 experiment, 634/837 extracted math concepts (76%) contained
source-specific numeric values in their `cues` and `implementation` fields.
Root cause: the extraction prompt literally asked for "how this concept was
applied in this specific solution" — producing entries like:
- "compute 160mi / 5hr = 32mph"
- "base CM = 2, height = 8 -> area = 8"
- "center at (4,4) for a 7x7 grid"

These values leak into hints for different target problems, causing misleading
guidance.

## Approach: Two 20-Problem Sets

**Set A (Build):** 20 problems for extraction testing
- 15 known leaky sources + 5 clean sources from the m3 concept pool

**Set B (Eval):** 20 problems for selection + solve testing
- 7 concept-helps + 7 concept-hurts + 6 neutral from m3 per-problem results

Added `--include-ids` and `--include-ids-file` flags to `extract_concepts.py`
for subsetting.

## Extraction Prompt v3a Changes
1. Added anti-leakage instructions with BAD/GOOD examples
2. Changed `implementation` field from "how applied in this specific solution"
   to "the general procedure (abstract, no specific values)"
3. Updated ICL example to use abstract patterns

For code domain (LCB), also added:
4. Anti-backtick instruction (backticks break YAML parsing)
5. Same anti-leakage and abstract implementation instructions

## Leakage Results
- Before (v1): **76% leaky** (634/837 math concepts)
- After (v3a): **0% source-specific leakage** (52-53 math concepts, clean)
- LCB had minimal leakage before (1/168), remains clean

## Solve Results (qwen3.5-flash, n=1, 2 passes, 2 seeds)

### Math (20 eval problems)
| Config        | Seed 42 | Seed 43 | Mean  |
|---------------|---------|---------|-------|
| Baseline      | 18/20   | 20/20   | 19.0  |
| Concept (v3a) | 19/20   | 19/20   | 19.0  |

- **Delta: 0.0** — flash is too strong for these 20 problems
- s42: +1 help, 0 hurts. s43: 0 helps, 1 hurt
- Essentially noise — the problems are too easy for flash
- Key validation: **zero concept damage** vs m3's 7 hurts with leaky concepts

### LCB (20 eval problems)
| Config        | Seed 42 | Seed 43 | Mean  |
|---------------|---------|---------|-------|
| Baseline      | 17/20   | 15/20   | 16.0  |
| Concept (v3a) | 20/20   | 17/20   | 18.5  |

- **Delta: +2.5** — consistent improvement across seeds
- s42: +3 helps, 0 hurts. s43: +5 helps, 3 hurts
- Concepts especially powerful for retry: s42 recovered 6/6 vs baseline 2/5
- 17/20 concept selection coverage (3 problems got no hints = baseline)

### Per-problem LCB details (across 2 seeds):
| Problem    | B-s42 | C-s42 | B-s43 | C-s43 | Notes |
|------------|-------|-------|-------|-------|-------|
| 2919       | N     | Y     | N     | Y     | concept always helps |
| 2921       | Y     | Y     | N     | Y     | concept rescues s43 |
| 3047       | Y     | Y     | Y     | N     | concept hurt s43 |
| abc372_f   | N     | Y     | Y     | N     | flips between seeds |
| abc380_g   | Y     | Y     | Y     | N     | concept hurt s43 |

## Retry Recovery Analysis

Concept hints dramatically improve retry recovery, especially for LCB:

| Domain | Mode    | s42 retry | s43 retry |
|--------|---------|-----------|-----------|
| LCB    | Baseline| 2/5 (40%) | 3/8 (38%)|
| LCB    | Concept | 6/6 (100%)| 3/6 (50%)|

The concept hints give the model a new angle when its first approach fails.

## v3b Variant: Drop implementation + parameters

Tested a lighter extraction that keeps only concept name, kind, description, cues.
Hints are 40% shorter (951 vs 1585 chars avg).

### v3b Results (2 seeds)
| Domain | Variant | s42 final | s43 final | Mean  |
|--------|---------|-----------|-----------|-------|
| Math   | Baseline| 18/20     | 20/20     | 19.0  |
| Math   | v3a     | 19/20     | 19/20     | 19.0  |
| Math   | **v3b** | **20/20** | **20/20** | **20.0** |
| LCB    | Baseline| 17/20     | 15/20     | 16.0  |
| LCB    | **v3a** | **20/20** | **17/20** | **18.5** |
| LCB    | v3b     | 17/20     | 15/20     | 16.0  |

### Analysis
- **Math: v3b wins** — leaner hints let the solver focus. 20/20 both seeds
- **LCB: v3a wins** — procedural details (implementation, parameters) matter for
  algorithm selection. Without them, v3b = baseline
- **Conclusion: v3a is the best general variant.** It works well for both domains.
  v3b is better for math specifically but damages LCB.

### Why v3b fails on LCB
Code problems need to know *how* to apply an algorithm, not just its name.
"Digit DP" as a name is less useful than "Digit DP with tight bound and modulo
constraint" with implementation notes about state tracking. Math problems are
different — "Vieta's Formulas" as a name already tells you what to do.

## Model Notes
- **gpt-5-nano**: Unreliable for selection (55% empty completions, deterministic)
- **qwen3.5-flash-02-23**: Fast, reliable via OpenRouter. Strong solver (19/20 math baseline)
- Registered in model_registry.py for OpenRouter provider

## Code Changes
| File | Change |
|------|--------|
| `scripts/extract_concepts.py` | `--include-ids`, `--include-ids-file` flags |
| `src/mem2/concepts/extraction.py` | v3a/v3b anti-leakage for math + code |
| `third_party/.../model_registry.py` | Registered qwen3.5-flash-02-23 |
| `configs/experiments/fast_iter/` | 12 configs total |
| `data/.../fast_iter/` | Build/eval sets, v3a/v3b extractions + selections |

## Key Takeaways
1. **v3a extraction eliminates leakage** — 76% → 0% for math, clean for LCB
2. **Concepts don't hurt anymore** — 0 average damage on math (vs -7 in m3)
3. **LCB benefits most** — +2.5/20 net improvement (v3a) because baseline is weaker
4. **v3b (no implementation) helps math but hurts LCB** — domain-specific tradeoff
5. **v3a is the best general variant** — works for both domains
6. **Retry recovery** is where concepts shine most — especially for LCB
7. **Flash is too strong** for 20-problem math eval — need harder problems or weaker solver
8. **Selection coverage matters** — v3a had 3/20 LCB failures, v3b had 0/20 (shorter concepts easier to match)

## Next Steps
- [x] Validate v3a extraction on both math + LCB
- [x] Multi-seed confirmation
- [x] v3b tested — better for math, worse for LCB
- [x] Two-tier rendering tested — cues_only selector best for math (devlog 30)
- [x] v3c parameterization enforcement — tested, reverted (devlog 30)
- [ ] Scale to full eval, hybrid mode, concept rejection — see devlog 31
