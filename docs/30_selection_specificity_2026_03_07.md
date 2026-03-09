# Devlog 30: Selection Over-Specificity Feedback (2026-03-07)

## Problem Statement

Concepts with over-specific detail (numerical or conceptual) get **over-selected**
— they match too aggressively and negatively impact downstream solve performance.
v3a fixed numeric leakage in extraction (76% → 0%), but conceptual over-specificity
in selection remains.

Example failure mode: a concept with cues like "problem involves modular arithmetic
with prime modulus" gets selected for any problem mentioning modular arithmetic,
even when the actual technique (e.g., Hensel lifting) is irrelevant.

## Proposed Solutions (from channel feedback)

### 1. Dev Set Concept Rejection

Use a dev set of problems to test whether new concepts are over-selected or
negatively impact downstream performance. Reject concepts that consistently hurt.

**Status:** Partially implemented via fruit fly approach (20-problem eval sets).
The gap is systematic per-concept impact measurement and automated rejection.

**What we have:**
- 20-problem build/eval sets for math and LCB
- Per-problem solve results across seeds
- Can identify which concepts were selected for which problems

**What's missing:**
- Automated loop: extract → select → solve → measure per-concept delta → reject
- Per-concept attribution (which concept caused a hurt vs a help)
- Rejection threshold and filtering mechanism

### 2. Parameterization for Generalization

Contain over-specific detail as parameters rather than in cues/implementation.
This is core to ArcMemo's design philosophy — parameters are the generalization
mechanism that makes concepts reusable across problems.

**Two sub-directions:**
- **Numerical detail → parameters:** Instead of "grid has even dimensions",
  use `parameter: grid_dimensions, typing: int, description: side length`.
  The parameter exists as a slot to be filled, not a constraint.
- **Conceptual detail → functional parameters:** Instead of "modular arithmetic
  with prime modulus", use `parameter: modulus_type, typing: str, description:
  properties of the modulus (prime, composite, prime power)`.

**Status:** The `parameters` field exists in the Concept schema and is extracted,
but the extraction prompt doesn't systematically push specifics into parameters.
Parameter descriptions are already hidden from both selector and solver
(`skip_parameter_description=True`), so they're a natural containment zone.

### 3. Two-Tier Rendering (Hide Detail from Selector)

Show different concept fields to the selector vs the solver. The selector should
match on abstract features (name, description, cues), while the solver gets full
procedural detail (implementation, parameters).

**Current architecture:**
- Selector always sees full concept (hardcoded in `async_retrieve()` and
  `select_concepts.py`)
- Solver view is configurable via `render_mode` (full/cues_only/name_only)
- No `selector_render_mode` exists

**Field visibility matrix:**

| Field | Selector (current) | Selector (proposed) | Solver (full) |
|---|---|---|---|
| name | Y | Y | Y |
| description | Y | Y | Y |
| cues | Y | Y | Y |
| implementation | Y | **N** | Y |
| parameters | Y | **N** | Y |
| kind | N | N | N |

**Rationale:** Implementation and parameters may contain over-specific conceptual
detail that causes the selector to over-match. If the selector only sees
name + description + cues, it matches on abstract problem features. The solver
still gets full detail for actually applying the concept.

**Implementation plan:**
1. Add `selector_render_mode` config field to ps_selector
2. Apply render profile in selection code path (same mechanism as solver)
3. Default to `full` (backward compatible)
4. Test with `cues_only` on the 20-problem eval sets

## Implementation: `selector_render_mode`

Added `selector_render_mode` config to `ps_selector.py` and `--selector-render-mode`
CLI flag to `select_concepts.py`. Same render profiles as solver (`full`/`cues_only`/
`name_only`), default `full` (backward compatible).

### Code Changes
| File | Change |
|------|--------|
| `src/mem2/branches/memory_retriever/ps_selector.py` | `selector_render_mode` param, applied in `async_retrieve()` |
| `scripts/select_concepts.py` | `--selector-render-mode` flag, applied to `mem.to_string()` |
| `configs/experiments/fast_iter/concept_cues_only_*.yaml` | 4 configs (math/lcb x s42/s43) |

### Selection Comparison: full vs cues_only

Math: 17/20 coverage for cues_only (vs 20/20 full) — 3 timeouts.
LCB: 17/20 coverage for both modes.

Selections differ significantly — cues_only tends to select different concepts
because it can't see implementation details. Fewer "Undetermined Coefficients
Method" selections (which over-matched on "polynomial" keywords in implementation).

### Solve Results (qwen3.5-flash, n=1, 2 passes, 2 seeds)

#### Math — Full Selector/Solver Matrix
| Selector | Solver | s42 | s43 | Mean |
|----------|--------|-----|-----|------|
| — | — (baseline) | 18 | 20 | 19.0 |
| full | full (v3a) | 19 | 19 | 19.0 |
| **cues_only** | **full** | **20** | **20** | **20.0** |
| name_only | full | 19 | 19 | 19.0 |
| **cues_only** | **cues_only** | **20** | **20** | **20.0** |

- `cues_only` selector is the sweet spot — cues provide abstract matching
- `name_only` drops too much signal (no cues = worse matching)
- Solver doesn't need implementation/parameters for math (cues_only = full)
- Both 20/20 configs required zero retries on s43

#### LCB — Full Selector/Solver Matrix
| Selector | Solver | s42 | s43 | Mean |
|----------|--------|-----|-----|------|
| — | — (baseline) | 17 | 15 | 16.0 |
| **full** | **full** (v3a) | **20** | **17** | **18.5** |
| cues_only | full | 18 | 17 | 17.5 |
| full | cues_only | 15 | 14 | *14.5* |

- `full/full` is the clear winner (+2.5 over baseline)
- `cues_only` selector loses 1.0 — misses algorithm-specific concepts
- `cues_only` solver **actively hurts** (-1.5 vs baseline) — LCB solver needs
  implementation details
- Code domain needs full information at every stage

Per-problem LCB differences (full vs cues_only selector):
- abc380_g: full wins s42 — "Fenwick Tree Range Maximum Query" not selected by cues_only
- abc385_d: full wins s43 — "Sweep Line Algorithm" not selected by cues_only
- abc372_f: cues_only wins — different selections happened to work better

### Analysis

**Math: cues_only is best** — 20/20 perfect on both seeds. Matches v3b finding
(devlog 29) but achieved differently: v3b dropped implementation from the
*solver hint*, while cues_only drops it from the *selector input*. Both work
because math concept names are self-explanatory ("Vieta's Formulas").

**LCB: full is best** — 18.5 vs 17.5. The selector needs implementation details
to distinguish similar algorithm concepts (e.g., "Digit DP" vs "1D DP State
Compression"). cues_only misses algorithm-specific concepts like "Fenwick Tree"
and "Sweep Line" because their cues are too generic. But cues_only still beats
baseline (17.5 vs 16.0).

**Domain-specific optimal config:**
- Math: `selector_render_mode=cues_only`, `render_mode=cues_only` (or `full`)
- LCB: `selector_render_mode=full`, `render_mode=full`

This matches the v3a/v3b finding: math is name-driven, code is procedure-driven.

**Math ceiling reached:** 20/20 on both seeds with qwen3.5-flash. Need harder
problems or weaker solver to see further differentiation.

### Run Outputs
- `outputs/_runs/fastiter_concept_cues_only_flash/` — math s42: 20/20
- `outputs/_runs/fastiter_concept_cues_only_flash_s43/` — math s43: 20/20
- `outputs/_runs/fastiter_concept_cues_only_lcb_flash/` — lcb s42: 18/20
- `outputs/_runs/fastiter_concept_cues_only_lcb_flash_s43/` — lcb s43: 17/20

## Parameterization Enforcement (v3c)

Made `parameters` required in extraction prompt and added "Parameterization over
specificity" instructions pushing variable aspects into parameters instead of cues.

### v3c Extraction Stats
- Math: 49 concepts, **0 without parameters** (vs 8/53 in v3a)
- LCB: 41 concepts, **0 without parameters**

### v3c Solve Results
| Domain | Variant | Selector | Solver | s42 | s43 | Mean |
|--------|---------|----------|--------|-----|-----|------|
| Math | v3a | cues_only | full | 20 | 20 | **20.0** |
| Math | v3c | cues_only | full | 19 | 19 | 19.0 |
| LCB | v3a | full | full | 20 | 17 | **18.5** |
| LCB | v3c | full | full | 15 | 19 | 17.0 |

### v3c Verdict: **Worse on both domains. Reverted.**

Enforced parameterization adds bulk and makes cues overly abstract. The model
pushes too much information into parameters, making cues generic enough to
over-match (the opposite of what we want). The original v3a prompt with optional
parameters produces better-calibrated concepts.

**Root cause:** When forced to parameterize everything, the model strips useful
specificity from cues to move it into parameters. But parameters are hidden from
the selector (via `skip_parameters=True` in cues_only mode), so the selector
sees only the now-too-generic cues. Ironically, enforcing parameterization makes
the over-specificity problem worse by making cues under-specific.

### Extraction prompt reverted to v3a (parameters optional, no parameterization section).

## Implementation Priority

1. ~~**Two-tier rendering**~~ — **DONE** (`selector_render_mode`)
2. ~~**Parameterization enforcement**~~ — **TESTED, REVERTED** (v3c worse on both domains)
3. **Dev set concept rejection** — largest project, needs attribution pipeline

## Relationship to Existing Work

- v3a anti-leakage (devlog 29): Fixed numeric specificity in extraction
- v3b experiment (devlog 29): Showed implementation matters for LCB solver
  but may not matter for selection
- `render_mode` (existing): Already controls solver view, just need selector parity
- `max_frequency` filtering (existing): Removes over-generic concepts, complementary
  to this work which targets over-specific ones

## Key Takeaways

1. **Two-tier rendering works for math** — hiding impl from selector: 19.0 → 20.0
2. **LCB needs full info everywhere** — dropping any field hurts (14.5 with cues solver)
3. **Domain-specific configs are essential:**
   - Math: `selector=cues_only`, `solver=cues_only` or `full` → 20/20
   - LCB: `selector=full`, `solver=full` → 18.5/20
4. **Math is name-driven**, code is procedure-driven (consistent across experiments)
5. **name_only selector too aggressive** — drops useful cue-matching signal (19.0)
6. **Math at ceiling** on 20-problem set — need harder problems for further iteration

## Next Steps

- [x] Try parameterization enforcement (v3c) — tested, reverted (worse on both domains)
- [ ] Scale to full eval set — see devlog 31
- [ ] Hybrid + two-tier rendering — see devlog 31
- [ ] Concept rejection pipeline — see devlog 31
