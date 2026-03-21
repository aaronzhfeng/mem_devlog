# Devlog 33: Math v3a Scale Evaluation (2026-03-10)

## Overview

Full-scale evaluation of the v3a concept pipeline on competition_math_all_l5 (200 eval
problems, Level 5, all 7 categories). Ran the complete build→extract→select→eval pipeline
with qwen3.5-flash and compared baseline, concept v3a, and hybrid v3a configurations.

**Headline result:** Baseline is at 197/200 (98.5%) — near ceiling. Concepts hurt:
concept v3a scores 196 (-1), hybrid v3a scores 194 (-3). At this performance level,
concept hints introduce noise that confuses the solver.

## Session Work

### 1. Build Run

- Config: `build_math_l5_flash.yaml`, 500 build-set problems, qwen3.5-flash, n=1, 1 pass
- Concurrency: 32
- Result: **485/500 solved** (97% solve rate)
- Output: `outputs/_runs/build_math_l5_flash/a3d763b86ea6/`
- Time: ~26 minutes

### 2. Concept Extraction

- v3a extraction prompt, `--stage1-mode passthrough` (math reasoning output used directly)
- Input: 485 solved problems
- Output: **1105 concepts** extracted (vs 239 for LCB from 154 solutions)
- 49 batches × ~10 problems each, ~18 minutes total
- Data: `data/competition_math_all_l5/concept_memory/extracted_v3a_flash.json`
- Some YAML parse failures in stage 2 (e.g., LaTeX `$` in cues causing YAML errors)

### 3. Concept Selection

#### 3a. cues_only mode (optimal for math per devlog 30)
- First run: concurrency 32, **124/200 parse failures** (115 "None" + 8 empty + 1 other)
- Root cause: 1105 concepts in cues_only mode → model can't match concepts, returns "None"
- Retry with concurrency 16: improved to **131/200 valid selections** (69 "None" remaining)
- Mean 3.6 concepts/problem (min=1, max=5)

#### 3b. full mode (for comparison)
- Concurrency 16: **79/200 valid selections** (118 "None" + 3 other)
- full mode is *worse* than cues_only — longer prompts cause more "None" responses
- The 1105-concept library is too large for effective selection in either mode

**Key insight:** cues_only selector scaling breaks at ~1000+ concepts. The fruit fly
experiments (devlog 30) used small concept libraries where cues_only worked well. At full
scale, the model is overwhelmed by the concept catalog.

### 4. Evaluation Runs

All runs: 200 eval problems, qwen3.5-flash, n=1, 2 passes, concurrency 32.

## Results

### Math L5 (200 eval problems, qwen3.5-flash, n=1, 2 passes)

| Config | Pass 1 | Final | Retry recovery | vs Baseline |
|--------|--------|-------|----------------|-------------|
| **Baseline** | **196** | **197** | 1/4 (25%) | — |
| Concept v3a | 195 | 196 | 1/5 (20%) | **-1** |
| Hybrid v3a | 193 | 194 | 1/7 (14%) | **-3** |

### Analysis

**1. Math is at ceiling (98.5%) — no room for concepts to help**

The baseline already solves 197/200. Only 3 problems are available for improvement.
Meanwhile, concept hints cause regressions on 1-4 problems that baseline solves correctly.
The net effect is always negative.

**2. Concepts cause p1 regression**

- Concept v3a: -1 on p1 (196→195)
- Hybrid v3a: -3 on p1 (196→193)

This is the opposite of LCB, where v3a nearly eliminated p1 regression. On math, the
model is so strong that any additional context is more likely to confuse than help.

**3. Hybrid is worse than concept on math**

This contradicts the fruit fly finding (devlog 28: hybrid best for math) but makes sense:
- In fruit fly (20 problems, nano model), there was room for improvement
- At 98.5% baseline with flash, hybrid's p1 without hints still loses ~3 problems,
  and hints on retry can't recover them all

**4. Retry recovery is ineffective at ceiling**

With only 4-7 problems to retry, sample sizes are tiny. The 25% baseline recovery
(1/4) vs 14-20% concept recovery (1/5, 1/7) is not statistically meaningful.

**5. Selection coverage is poor (131/200)**

Only 66% of eval problems got concept selections. 69 problems got "None" — the model
couldn't match any of 1105 concepts to those problems. This could mean:
- The concept library is too large and unfocused
- cues_only format doesn't provide enough matching signal at scale
- Some eval problems genuinely have no relevant concepts in the library

### Comparison: Math vs LCB

| Metric | LCB (devlog 32) | Math (this devlog) |
|--------|------------------|--------------------|
| Baseline | 80/100 (80%) | 197/200 (98.5%) |
| Concept v3a | **85/100 (+5)** | **196/200 (-1)** |
| Hybrid v3a | 80/100 (0) | 194/200 (-3) |
| Concept library size | 239 | 1105 |
| Selection coverage | 92/100 (92%) | 131/200 (66%) |
| p1 regression | -1 | -1 to -3 |
| Retry recovery boost | 44% vs 23% | Not meaningful |

**The critical difference is baseline performance.** LCB baseline is 80% — 20 problems
available for improvement. Math baseline is 98.5% — only 3 problems available. Concepts
are helpful when there's room to improve and harmful when the model is already near-perfect.

## Cost

| Step | Tokens (approx) | Cost (approx) |
|------|-----------------|---------------|
| Build run (500 problems) | ~30M | ~$6 |
| Extraction (485 solutions) | ~15M | ~$3 |
| Selection (2 modes, 200 problems each) | ~20M | ~$4 |
| Eval runs (3 configs × 200 problems) | ~60M | ~$12 |
| **Total** | ~125M | **~$25** |

## Files Created/Modified

### New Configs
```
configs/experiments/
├── build_math_l5_flash.yaml            # Build run (500 problems)
├── math_l5_baseline_flash.yaml         # Baseline eval
├── math_l5_concept_v3a_flash.yaml      # Concept v3a eval
└── math_l5_hybrid_v3a_flash.yaml       # Hybrid v3a eval
```

### New Data
```
data/competition_math_all_l5/concept_memory/
├── extracted_v3a_flash.json            # 1105 concepts from 485 solutions
├── selection_v3a_cues_only/
│   ├── prompt_info.json                # 131/200 hint renderings
│   ├── selected_concepts.json          # pid → [concept_name, ...]
│   ├── completions.json                # raw LLM responses
│   └── parse_errors.json               # 69 failures
└── selection_v3a_full/
    ├── prompt_info.json                # 79/200 hint renderings
    ├── selected_concepts.json
    ├── completions.json
    └── parse_errors.json               # 121 failures
```

### Run Outputs
```
outputs/_runs/
├── build_math_l5_flash/a3d763b86ea6/          # Build (485/500)
├── math_l5_baseline_flash/e3439890ac56/       # Baseline (197/200)
├── math_l5_concept_v3a_flash/b80e84653644/    # Concept v3a (196/200)
└── math_l5_hybrid_v3a_flash/3fd63ec6ad43/     # Hybrid v3a (194/200)
```

## Domain-Specific Strategy (Updated)

| Setting | Math | LCB |
|---------|------|-----|
| Extraction prompt | v3a | v3a |
| `selector_render_mode` | `cues_only` | `full` |
| `render_mode` (solver) | `cues_only` or `full` | `full` |
| Retry mode | hybrid | concept |
| Scale validation | **Done (-1 to -3, at ceiling)** | **Done (+5, +6.25%)** |
| **Effective?** | **No (baseline too strong)** | **Yes** |

## Conclusions

1. **Concept memory is domain-dependent in a new way**: it's not just about render modes
   and retry strategy — it's about headroom. If the model already performs near-perfectly,
   concepts can only hurt.

2. **The math benchmark needs a harder model/problem combination** to test concept
   effectiveness. Options:
   - Use a weaker model (nano instead of flash) where baseline is ~93%
   - Use harder problems (AMC/AIME instead of competition_math L5)
   - Use problems the flash model actually struggles with

3. **Selection scaling is a real problem**: 1105 concepts overwhelm the selector at
   cues_only mode (only 66% coverage). Need either:
   - Concept library pruning/clustering
   - Hierarchical selection (category → concept)
   - Smaller, more focused libraries

## Next Steps

1. **Harder math benchmark** — Find/create a math eval where flash baseline is ~80-85%
   to provide headroom for concept improvement

2. **Concept library pruning** — Reduce from 1105 to ~200-300 high-quality concepts
   using deduplication and quality filtering

3. **Multi-seed LCB validation** — Run s43 on LCB to confirm the +5 finding is robust

4. **Weaker model math eval** — Try nano or a smaller model where baseline is lower
