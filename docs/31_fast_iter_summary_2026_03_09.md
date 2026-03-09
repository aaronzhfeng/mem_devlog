# Devlog 31: Fast Iteration Summary & Next Steps (2026-03-09)

## Overview

This document consolidates findings from devlogs 28-30: the m3 three-mode
experiment, the fast iteration prompt work, and the selection specificity
investigation. It establishes the current best configuration per domain and
lays out four concrete next steps.

## Timeline

| Date | Devlog | What | Key outcome |
|------|--------|------|-------------|
| 03-04 | 28 | 3-mode experiment (200 math, 100 LCB, nano) | Hybrid best for retry; concepts hurt LCB with nano |
| 03-07 | 29 | Fast iteration: v3a/v3b extraction prompts | v3a eliminates 76% leakage → 0%; LCB +2.5 |
| 03-07 | 30 | Selection specificity: two-tier rendering + v3c | `selector_render_mode=cues_only` → math 20/20; v3c reverted |

## Current Best Configuration

### Extraction Prompt: v3a
- Anti-leakage instructions with BAD/GOOD examples
- Abstract implementation field ("general procedure, no specific values")
- Parameters optional
- Code-specific: anti-backtick rule
- **Tested and rejected:** v3b (drop implementation — hurts LCB), v3c (enforce
  parameterization — hurts both)

### Domain-Specific Pipeline Settings

| Setting | Math | LCB |
|---------|------|-----|
| Extraction prompt | v3a | v3a |
| `selector_render_mode` | `cues_only` | `full` |
| `render_mode` (solver) | `cues_only` or `full` | `full` |
| Retry mode | hybrid (concept on retry only) | concept (both passes) |

**Why domains differ:**
- **Math is name-driven.** "Vieta's Formulas" tells a solver exactly what to do.
  Hiding implementation from selector prevents over-matching on procedural keywords.
  Hiding it from solver is fine too — the name suffices.
- **Code is procedure-driven.** "Digit DP" alone is insufficient — the solver needs
  to know about tight-bound tracking, state representation, modulo handling.
  Hiding any detail from selector or solver causes regressions.

## Consolidated Results (20-problem fruit fly sets, qwen3.5-flash, 2 seeds)

### Math (20 eval problems, 2 passes)

| Config | Extraction | Selector | Solver | s42 | s43 | Mean |
|--------|-----------|----------|--------|-----|-----|------|
| Baseline | — | — | — | 18 | 20 | 19.0 |
| v3a full/full | v3a | full | full | 19 | 19 | 19.0 |
| **v3a cues/full** | **v3a** | **cues_only** | **full** | **20** | **20** | **20.0** |
| v3a cues/cues | v3a | cues_only | cues_only | 20 | 20 | 20.0 |
| v3a name/full | v3a | name_only | full | 19 | 19 | 19.0 |
| v3b full/full | v3b | full | full | 20 | 20 | 20.0 |
| v3c cues/full | v3c | cues_only | full | 19 | 19 | 19.0 |

### LCB (20 eval problems, 2 passes)

| Config | Extraction | Selector | Solver | s42 | s43 | Mean |
|--------|-----------|----------|--------|-----|-----|------|
| Baseline | — | — | — | 17 | 15 | 16.0 |
| **v3a full/full** | **v3a** | **full** | **full** | **20** | **17** | **18.5** |
| v3a cues/full | v3a | cues_only | full | 18 | 17 | 17.5 |
| v3a full/cues | v3a | full | cues_only | 15 | 14 | 14.5 |
| v3b full/full | v3b | full | full | 17 | 15 | 16.0 |
| v3c full/full | v3c | full | full | 15 | 19 | 17.0 |

### Key Numbers

| Metric | Math | LCB |
|--------|------|-----|
| Baseline | 19.0 | 16.0 |
| Best concept config | **20.0** (+1.0) | **18.5** (+2.5) |
| Worst concept config | 19.0 (0.0) | 14.5 (-1.5) |
| Leakage (v3a) | 0% | 0% |
| v3c vs v3a delta | -1.0 | -1.5 |

## What We Learned

### 1. Leakage was the #1 problem (devlog 29)
76% of m3 math concepts contained source-specific numbers. Fixing the extraction
prompt (v3a) turned concept damage from -7 hurts to 0. This single change made
concepts safe to use.

### 2. Information hiding is domain-specific (devlog 30)
- Hiding implementation from math selector: +1.0 (19.0 → 20.0)
- Hiding implementation from LCB selector: -1.0 (18.5 → 17.5)
- Hiding implementation from LCB solver: -4.0 (18.5 → 14.5)

The optimal information surface differs by domain. There is no universal setting.

### 3. Parameterization enforcement backfires (devlog 30)
Forcing all concepts to have parameters (v3c) strips useful specificity from cues
and pushes it into parameters that the selector can't see. The net effect is
worse matching, not better. Optional parameters (v3a) let the model decide what
merits parameterization.

### 4. Concepts help most on retry (devlog 28)
Hybrid mode (baseline p1 → concept retry) gives the best final score and strongest
retry recovery. Concept mode has best p1 but weakest retry (same hint twice has
diminishing returns). This was shown at scale (200 math, nano) but not yet tested
with the improved v3a extraction or flash model.

### 5. Math is at ceiling on fruit fly set
20/20 on both seeds means we can't differentiate further on these 20 problems with
flash. We need the full eval set or a weaker solver to see further gains.

## Next Steps

### Direction 1: Scale to Full Eval (HIGH PRIORITY)

Run the optimal domain configs on the full eval sets to validate fruit fly gains.

**Math (200 problems):**
- Extract v3a concepts from full 500-problem build set
- Select with `selector_render_mode=cues_only`
- Solve with `render_mode=full`, 2 passes, multiple seeds
- Compare to m3 baseline (174.5 p1, 186.0 best with nano)
- Use qwen3.5-flash as solver for fair comparison to fruit fly results

**LCB (100 problems):**
- Extract v3a concepts from full LCB build set
- Select with `selector_render_mode=full`
- Solve with `render_mode=full`, 2 passes, multiple seeds
- Compare to m3 LCB baseline (which had broken nano selection)

**Expected outcome:** If fruit fly gains hold at scale:
- Math: ~4-5% improvement over baseline (extrapolating from m3 concept +4.3)
- LCB: ~12% improvement over baseline (extrapolating from +2.5/20)

**Key risk:** Fruit fly sets are hand-picked mixes of helps/hurts/neutrals. Full
eval may have different distributions. Ceiling effects on easy problems may dilute
gains.

**Config files needed:**
- `configs/experiments/full_eval/math_v3a_cues_flash.yaml`
- `configs/experiments/full_eval/lcb_v3a_full_flash.yaml`
- Plus seed variants (s43, s44, s45)

### Direction 2: Hybrid + Two-Tier Rendering (HIGH PRIORITY)

Combine m3's best finding (hybrid retry mode) with v3a extraction and optimal
selector/solver configs. Never tested together.

**Hypothesis:** Hybrid mode benefits from better concepts. m3 hybrid used leaky
nano-extracted concepts (76% leakage). With v3a clean concepts + domain-specific
selector modes, hybrid should improve further.

**Test matrix (on fruit fly sets first, then scale):**

| Config | p1 | retry | Expected benefit |
|--------|-----|-------|------------------|
| Baseline | no hint | no hint | reference |
| Concept | hint | hint | best p1 |
| Hybrid | no hint | hint | best final |
| Hybrid + cues selector | no hint | cues_only selected hint | best final for math? |

**Implementation:** `hybrid_concept_mode: true` already exists in runner.py. Just
needs to be combined with v3a extraction and `selector_render_mode=cues_only` for
math.

**Config files needed:**
- `configs/experiments/fast_iter/hybrid_v3a_math_flash.yaml`
- `configs/experiments/fast_iter/hybrid_v3a_lcb_flash.yaml`

### Direction 3: Dev Set Concept Rejection (MEDIUM PRIORITY)

Build per-concept attribution to automatically filter out net-negative concepts.

**Approach:**
1. For each concept C in the library:
   - Identify problems where C was selected
   - Compare solve rate with C included vs excluded (leave-one-out)
   - Compute per-concept delta: mean(solve_with_C) - mean(solve_without_C)
2. Reject concepts with consistently negative delta across seeds
3. Iterate: re-run selection without rejected concepts, re-evaluate

**What exists:**
- 20-problem eval sets with per-problem results across seeds
- Selection outputs identifying which concepts each problem received
- Solve results per problem per seed

**What needs to be built:**
- Script to parse selection outputs → concept-problem mapping
- Leave-one-out evaluation (re-run solve with each concept excluded)
- Delta aggregation and rejection threshold
- Filtered concept memory output

**Estimated scope:** Medium — mainly scripting + a few solve runs per concept.
The bottleneck is that leave-one-out requires N additional solve runs (one per
concept being tested), which is expensive at scale. Could start with the fruit
fly set (20 problems × ~50 concepts = ~1000 solves) to find the worst offenders.

**Alternative (cheaper):** Instead of leave-one-out, use the existing multi-seed
results to estimate concept value. If a concept is selected for problems that
consistently fail across seeds, flag it for review. Less rigorous but much
cheaper.

### Direction 4: Harder Test Problems (LOW PRIORITY)

Math fruit fly set is at ceiling (20/20). Options:
- **Use full 200-problem eval** — natural difficulty distribution includes harder
  problems. This is subsumed by Direction 1.
- **Curate a harder 20-problem subset** — pick from the ~30 problems that fail
  across all seeds/modes in m3. Tests concept effectiveness on genuinely hard
  problems.
- **Use a weaker solver** — e.g., gpt-5-nano. But nano has selection problems
  (55% empty completions), so this conflates solver weakness with infrastructure
  issues.
- **Cross-domain difficulty** — LCB already has room (16.0 baseline). Focus
  iteration energy on LCB rather than math.

**Recommendation:** Defer. Direction 1 (full eval) naturally solves this for math.
LCB already has headroom for differentiation.

## Recommended Execution Order

1. **Hybrid + v3a on fruit fly** (Direction 2) — quick, validates combo
2. **Full eval with optimal configs** (Direction 1) — main validation
3. **Concept rejection on fruit fly** (Direction 3) — if full eval shows hurts
4. **Harder test set** (Direction 4) — only if math still at ceiling

Directions 1 and 2 can run in parallel since they use different configs. Direction
3 should wait for full eval results to identify which concepts are problematic at
scale.

## Files Reference

### Extraction & Selection Data
```
data/competition_math_all_l5/fast_iter/
├── build_20.txt                      # Math build problem IDs
├── eval_20.txt                       # Math eval problem IDs
├── eval_20_problems.json             # Math eval problem specs
├── extracted_v3a_flash.json          # v3a concepts (53, 0% leakage)
├── extracted_v3b_flash.json          # v3b concepts (no impl/params)
├── extracted_v3c_flash.json          # v3c concepts (forced params, reverted)
├── selection_v3a/                    # full selector selections
├── selection_v3a_cues_only/          # cues_only selector selections
├── selection_v3a_name_only/          # name_only selector selections
├── selection_v3c_cues_only/          # v3c cues_only selections
└── selection_v3b/                    # v3b selections

data/livecodebench_all/fast_iter/
├── build_20.txt                      # LCB build problem IDs
├── eval_20.txt                       # LCB eval problem IDs
├── eval_20_problems.json             # LCB eval problem specs
├── extracted_v3a_flash.json          # v3a concepts (42, clean)
├── extracted_v3c_flash.json          # v3c concepts (forced params, reverted)
├── selection_v3a/                    # full selector selections
├── selection_v3a_cues_only/          # cues_only selector selections
└── selection_v3c_flash/              # v3c full selections
```

### Configs
```
configs/experiments/fast_iter/
├── baseline_flash.yaml / _s43.yaml         # Math baseline
├── baseline_lcb_flash.yaml / _s43.yaml     # LCB baseline
├── concept_v3a_flash.yaml / _s43.yaml      # Math v3a full/full
├── concept_v3a_lcb_flash.yaml / _s43.yaml  # LCB v3a full/full
├── concept_v3b_flash.yaml / _s43.yaml      # Math v3b
├── concept_v3b_lcb_flash.yaml / _s43.yaml  # LCB v3b
├── concept_v3c_flash.yaml / _s43.yaml      # Math v3c (reverted)
├── concept_v3c_lcb_flash.yaml / _s43.yaml  # LCB v3c (reverted)
├── concept_cues_only_flash.yaml / _s43.yaml      # Math cues_only selector
├── concept_cues_only_lcb_flash.yaml / _s43.yaml  # LCB cues_only selector
├── concept_cues_cues_flash.yaml / _s43.yaml      # Math cues selector + cues solver
├── concept_full_cues_lcb_flash.yaml / _s43.yaml  # LCB full selector + cues solver
└── concept_name_only_flash.yaml / _s43.yaml      # Math name_only selector
```

### Code Changes (cumulative since devlog 28)
| File | Change |
|------|--------|
| `src/mem2/concepts/extraction.py` | v3a extraction prompt (anti-leakage, abstract impl) |
| `src/mem2/branches/memory_retriever/ps_selector.py` | `selector_render_mode` param |
| `scripts/extract_concepts.py` | `--include-ids`, `--include-ids-file` flags |
| `scripts/select_concepts.py` | `--selector-render-mode` flag |
| `third_party/.../model_registry.py` | qwen3.5-flash-02-23 registration |
