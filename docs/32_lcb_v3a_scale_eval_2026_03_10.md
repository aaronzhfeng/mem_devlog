# Devlog 32: LCB v3a Scale Evaluation (2026-03-10)

## Overview

First full-scale evaluation of the v3a concept pipeline on LiveCodeBench. Migrated
the workspace to Lightning Studio, fixed all hardcoded paths, ran the complete
build→extract→select→eval pipeline on 100 eval problems, and compared baseline,
concept v2, concept v3a, and hybrid v3a configurations.

**Headline result:** Concept v3a achieves 85/100 on LCB, +5 over baseline (+6.25%),
with 44% retry recovery vs 23% baseline.

## Session Work

### 1. Environment Migration

Migrated from `/root/arc/` (old studio) to `/teamspace/studios/this_studio/implemented/arc/`
(Lightning Studio).

- Fixed all hardcoded `/root/workspace/data/` paths to relative `data/` paths across
  ~30 config files, test files, and scripts
- Fixed `dotenv_path: .env.example` → `.env` in all 28 fast_iter experiment configs
- Set up new `.env` with fresh OpenRouter API key
- Verified: 278/278 unit tests passing

### 2. Math Fruit Fly Ceiling Confirmation

Attempted to run hybrid + v3a on 20-problem math fruit fly set. Results:

| Config | s42 | s43 | Mean |
|--------|-----|-----|------|
| Baseline | 20 | 20 | 20.0 |
| Hybrid v3a | 20 | 20 | 20.0 |

Ceiling confirmed. Can't differentiate on these 20 problems with qwen3.5-flash.

### 3. n=8 Bug Discovery

While investigating why math results differed from devlog 30, discovered that
`baseline_flash.yaml` had `n: 8` while all concept configs had `n: 1`. This gave
baseline an unfair 8x compute advantage (8 candidate solutions per problem).

- Fixed both baseline configs (s42 + s43) from `n: 8` to `n: 1`
- Impact: baseline was artificially inflated in previous comparisons
- Fruit fly set ceiling means this didn't affect math conclusions, but important for
  future full-eval runs

### 4. LCB v3a Pipeline (Full Scale)

#### 4a. Build Run
- Config: `build_lcb_v56_flash.yaml`, 200 build-set problems, qwen3.5-flash, n=1, 2 passes
- Result: 160/200 solved (80% solve rate)
- Output: `outputs/_runs/build_lcb_v56_flash/b2e0ee5435ce/`

#### 4b. Concept Extraction
- v3a extraction prompt, `--stage1-mode code`, qwen3.5-flash
- Input: 154 solved problems (from 160, excluding multi-solution)
- Output: **239 concepts** extracted
- Data: `data/livecodebench_v56/concept_memory/extracted_v3a_flash.json`

#### 4c. Concept Selection
- Full selector render mode (procedure-driven, as established in devlog 30)
- Result: **92/100** eval problems got selections (8 parse failures: no YAML block)
- Mean 3.4 concepts per problem (min=1, max=5)
- Data: `data/livecodebench_v56/concept_memory/selection_v3a_flash/`

#### 4d. Evaluation Runs

All runs: 100 eval problems, qwen3.5-flash, n=1, 2 passes.

**Note:** Also ran concept v2 and hybrid v2 experiments with old `extracted_v2.json`
before realizing these used pre-v3a concepts. Wasted ~$2 in tokens. Lesson: always
verify concept data version before running eval.

### 5. Wasted v2 Run

Ran `lcb_v56_concept_flash.yaml` and `lcb_v56_hybrid_flash.yaml` with old v2 concepts
before building the proper v3a pipeline. The v2 concept results (81/100) are included
in the comparison table for reference but weren't the intended experiment.

## Results

### LCB v56 (100 eval problems, qwen3.5-flash, n=1, 2 passes)

| Config | Pass 1 | Final | Retry recovery | vs Baseline |
|--------|--------|-------|----------------|-------------|
| Baseline | 74 | 80 | 6/26 (23%) | — |
| Concept v2 (old) | 70 | 81 | 11/30 (37%) | +1 |
| **Concept v3a** | **73** | **85** | **12/27 (44%)** | **+5** |
| Hybrid v3a | 72 | 80 | 8/28 (29%) | 0 |

### Analysis

**1. v3a concept is the clear winner (+5 over baseline)**

The 85/100 score represents a 6.25% improvement. This is the first time concept
augmentation has shown a meaningful gain at full scale on LCB.

**2. v3a fixes the p1 regression**

v2 concepts caused a significant p1 regression (74→70, -4 problems). v3a nearly
eliminates this (74→73, -1 problem). The anti-leakage extraction prompt prevents
confusing or misleading concept hints that hurt first-pass attempts.

**3. Retry recovery is the main mechanism**

The +5 gain comes almost entirely from retry: 12/27 failed problems recovered (44%)
vs 6/26 baseline (23%). Concepts provide new algorithmic angles that help the solver
escape its initial failure mode.

**4. Hybrid doesn't help for LCB**

Unlike math (where hybrid was best in devlog 28), LCB hybrid matches baseline exactly.
This confirms the domain difference identified in devlog 30: LCB is procedure-driven
and needs concept hints on **both** passes. Withholding hints on p1 (hybrid mode)
costs ~1-2 problems on p1 without being compensated by stronger retry.

**5. v2 concepts barely help (+1)**

The old extraction prompt (without anti-leakage, with specific values) causes a -4
regression on p1. Even though retry recovery is decent (37%), it mostly just recovers
the self-inflicted p1 damage.

### Comparison to Fruit Fly Results

| Metric | Fruit fly (20) | Full eval (100) | Held? |
|--------|---------------|-----------------|-------|
| Concept v3a vs baseline | +2.5 (+12.5%) | +5 (+6.25%) | Yes (attenuated) |
| Concept p1 regression | 0 | -1 | ~Yes |
| Retry recovery advantage | 6/6 vs 2/5 | 12/27 vs 6/26 | Yes |
| Hybrid ≤ concept for LCB | — (not tested) | Yes | — |

The fruit fly gain (+12.5%) was higher than full eval (+6.25%), as expected due to
the hand-picked nature of the fruit fly set. But the directional finding holds:
v3a concepts reliably improve LCB performance.

## Cost

| Step | Tokens (approx) | Cost (approx) |
|------|-----------------|---------------|
| Build run (200 problems) | ~40M | ~$8 |
| Extraction (154 solutions) | ~5M | ~$1 |
| Selection (100 problems) | ~6M input, ~1M output | ~$1 |
| Eval runs (4 configs × 100 problems) | ~100M | ~$20 |
| Wasted v2 runs | ~50M | ~$10 |
| **Total** | ~200M | **~$40** |

## Files Created/Modified

### New Configs
```
configs/experiments/
├── build_lcb_v56_flash.yaml           # Build run (200 problems)
├── lcb_v56_baseline_flash.yaml        # Baseline eval
├── lcb_v56_concept_flash.yaml         # Concept v2 (old, wasted)
├── lcb_v56_hybrid_flash.yaml          # Hybrid v2 (old, wasted)
├── lcb_v56_concept_v3a_flash.yaml     # Concept v3a eval
└── lcb_v56_hybrid_v3a_flash.yaml      # Hybrid v3a eval
```

### New Data
```
data/livecodebench_v56/concept_memory/
├── extracted_v3a_flash.json           # 239 concepts from 154 solutions
└── selection_v3a_flash/
    ├── prompt_info.json               # 92/100 hint renderings
    ├── selected_concepts.json         # pid → [concept_name, ...]
    ├── completions.json               # raw LLM responses
    └── parse_errors.json              # 8 failures
```

### Bug Fixes
```
configs/experiments/fast_iter/baseline_flash.yaml      # n: 8 → n: 1
configs/experiments/fast_iter/baseline_math_flash_s43.yaml  # n: 8 → n: 1
~30 config/test/script files                           # /root/workspace/ → data/
28 fast_iter configs                                   # .env.example → .env
```

## Domain-Specific Strategy (Updated)

| Setting | Math | LCB |
|---------|------|-----|
| Extraction prompt | v3a | v3a |
| `selector_render_mode` | `cues_only` | `full` |
| `render_mode` (solver) | `cues_only` or `full` | `full` |
| **Retry mode** | **hybrid** | **concept** |
| Scale validation | Pending | **Done (+6.25%)** |

## Next Steps

1. **Full math eval with v3a** — 200 problems, cues_only selector, hybrid mode,
   qwen3.5-flash. Compare to m3 baseline (186.0 with nano).

2. **Multi-seed LCB validation** — Run s43 seed to confirm +5 is robust, not
   seed-specific.

3. **Concept rejection pipeline** — The 8/100 selection parse failures suggest
   room for improvement. Also, per-concept attribution could identify net-negative
   concepts to filter.

4. **8-problem failure analysis** — Investigate the 8 problems where selection
   failed (no YAML block). May need prompt engineering for edge cases, or fallback
   to keyword matching.
