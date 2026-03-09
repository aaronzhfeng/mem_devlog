# Devlog 27 — GPT-5-Nano Full Concept Pipeline: Results & Failure Analysis

**Date:** 2026-03-03

## Overview

Full concept memory pipeline using gpt-5-nano for build/extract/select, evaluated
with both gpt-5-nano (self-help) and gpt-5-mini (cross-model transfer). This devlog
covers the complete results, a parser bug discovery, oracle analysis, and a detailed
failure taxonomy of every problem where concepts changed the outcome.

## Pipeline

```
Build:    gpt-5-nano → 500 problems → 420 p1, 467 best
Extract:  gpt-5-nano → 467 solved   → 837 concepts
Select:   gpt-5-nano → 200 eval     → 194/200 coverage, mean 1.6 concepts/problem
Eval:     gpt-5-nano or gpt-5-mini  → 200 eval → see results
```

Build run: `dd0166da5d1a`. Selection required chunked processing (chunk-size=1,
chunk-delay=5s) due to 200k TPM rate limit — each selection prompt is ~100k tokens.

## Parser Bug: `\boxed{}` vs `boxed{}`

The math_reason evaluator's regex required `\boxed{N}` with the backslash. GPT-5-nano
sometimes writes `boxed{N}` without it — stochastic, ~7-8% of completions. This
inflated both the apparent baseline and concept scores and, critically, created fake
wins/harms in the oracle analysis.

**Fix:** Changed `_BOXED_RE` in `math_reason_eval.py` from `\\boxed\{...\}` to
`\\?boxed\{...\}` (optional backslash).

## Results (Corrected)

### GPT-5-Nano (self-help)

| Run | p1 (old→fixed) | best (old→fixed) |
|-----|-----------------|-------------------|
| Baseline | 166→**175** | 181→**189** |
| Concept | 161→**173** | 184→**187** |
| **Δ** | -5→**-2** | +3→**-2** |

The apparent +3 best uplift was entirely parsing noise. After the fix, concepts are
net -2 on both p1 and best.

### GPT-5-Mini (cross-model transfer)

| Run | p1 | best |
|-----|-----|------|
| Baseline | 194 | 198 |
| Concept (qwen-extracted) | 194 | 197 |
| Concept (nano-extracted) | 195 | 199 |

Mini results use the code-based pipeline (`math_ps_solve`) which wasn't affected by
the `\boxed` bug. Nano-extracted concepts provide +1/+1 for mini — still the best
result.

### Cross-Model Comparison

| Model | Type | BL best | Con best | Oracle | Con-only | BL-only | Net |
|-------|------|---------|----------|--------|----------|---------|-----|
| Qwen-2.5-7B | non-thinking | 144* | 131* | 150* | 6 | 21 | **-15** |
| gpt-5-nano | thinking | 189 | 187 | 192 | 3 | 5 | **-2** |
| gpt-5-mini | thinking | 198 | 199 | 200 | 2 | 1 | **+1** |

*multi-run oracle

Thinking models are much less harmed by concepts (-2 vs -15), but nano is still
net-negative. The hypothesis that reasoning models can evaluate/ignore bad hints
is partially confirmed — they're better at it, but not good enough to overcome
low-quality concept selection.

## Oracle Analysis (Corrected)

### p1

| Metric | Count |
|--------|-------|
| Baseline p1 | 175 |
| Concept p1 | 173 |
| Overlap | 164 |
| Baseline-only p1 | 11 |
| Concept-only p1 | 9 |
| **Oracle p1** | **184** |

### Best

| Metric | Count |
|--------|-------|
| Baseline best | 189 |
| Concept best | 187 |
| Overlap | 184 |
| Baseline-only best | 5 |
| Concept-only best | 3 |
| **Oracle best** | **192** |

### Hybrid Experiment (no-concept p1 → concept retry on 34 failures)

Ran the 34 baseline p1 failures through concept config: 14/34 solved.
Combined: p1=175, best=175+14=189 — identical to baseline best. The hybrid
doesn't beat either pure strategy because concept diversity operates across
the full problem set, not just retries.

## Detailed Failure Taxonomy

### 5 Concept Harms (baseline solves, concept doesn't)

#### cmath_4786 — MISLEADING (consistent, both iters)
- **Problem:** Smallest n where 1/n terminates and n contains digit 9
- **Answer:** 4096 (= 2^12)
- **Concept:** "2^a 5^b Under N Counting" — frames as a counting problem
- **What happened:** Concept pushed model toward enumerate-and-count strategy.
  Model listed powers of 2 but stated "2^12 = 4096 has no 9" — a careless
  computational error it didn't make in baseline. Baseline carefully checked
  each power and found 4096 correctly.
- **Root cause:** Concept reframed the problem type (finding→counting), causing
  the model to use a less careful enumeration strategy.

#### cmath_5246 — IRRELEVANT NOISE (consistent, both iters)
- **Problem:** Count elements of {9^k : 0≤k≤4000} with leftmost digit 9
- **Answer:** 184
- **Concepts:** "Base-b Digit Count Bounds", "Interval Width" — completely off-topic
- **What happened:** i1: empty completion. i2: correct answer 184 but formatted
  as "boxed: 184" instead of `\boxed{184}` (still fails even with the relaxed
  parser since it's "boxed:" not "boxed{").
- **Root cause:** Off-topic concepts (base-b digit counting vs leading digit
  analysis via logarithms) disrupted generation.

#### cmath_9955 — MISLEADING (consistent, both iters)
- **Problem:** Ordered pairs (a,b) where both are roots of x²+ax+b=0
- **Answer:** 3
- **Concept:** "Viete's Formulas" — pushed model to equate {a,b} = {root1, root2}
- **What happened:** With Viete's, model assumed a and b ARE the two roots,
  getting a+b=-a, ab=b → only 2 solutions. Missed (−½,−½) where a=b=same root.
  Baseline used direct substitution and found all 3.
- **Root cause:** Concept actively reframed the approach. Viete's requires
  {a,b} to be THE root pair, but the problem only says each is A root.

#### cmath_3022 — MISLEADING (baseline i2 only)
- **Problem:** Paper folding/cutting tray, find m+n for height = n-th root of m
- **Answer:** 871
- **Concepts:** 4 irrelevant geometry concepts with leaked coordinates from other
  problems (e.g., "Set B=(0,0), A=(5,0), C=(0,-8), D=(20,-8)")
- **What happened:** Concept run i1: produced "53" with no reasoning. i2: empty.
  Baseline i2 worked through the geometry correctly.
- **Root cause:** Context flooded with irrelevant geometric scaffolding from other
  problems. Concept **leakage** of specific coordinates.

#### cmath_9959 — MISLEADING + LEAKAGE (baseline i2 only)
- **Problem:** f(x)f(2x²) = f(2x³+x), f(0)=1, f(2)+f(3)=125. Find f(5).
- **Answer:** 676
- **Concepts:** "Polynomial Y-intercept" (says c=8), "Specialization of Functional
  Equation" (says f(0)∈{0,2}, f(t)=t)
- **What happened:** All concept completions empty. Concepts contain values that
  directly contradict the problem (f(0)=1 ≠ {0,2}). Model couldn't reconcile.
- **Root cause:** **Concept leakage** — source-problem-specific values leaked into
  concept descriptions and contradicted the target problem. Most severe failure mode.

### 3 Concept Wins (concept solves, baseline doesn't)

#### cmath_9987 — STOCHASTIC (consistent, both iters)
- **Problem:** Minimize 4a+3b+c³/((a-b)b) with a+b+c=4, a>b
- **Answer:** 12
- **Concept:** "Center-based Relative Coordinate System" — about 7×7 grid symmetry,
  completely irrelevant
- **What happened:** Baseline: all completions empty (4 attempts). Concept: all
  completions correct and detailed.
- **Root cause:** Pure sampling variance. The irrelevant concept may have served as
  context padding that shifted sampling, but there's no causal mechanism from the
  concept content.

#### cmath_3177 — STOCHASTIC (concept i2 only)
- **Problem:** Area visible while walking around 5km square, seeing 1km in all directions
- **Answer:** 39
- **Concepts:** "Circle Circumference Formula", "Rectangle Area Formula" — elementary
- **What happened:** Baseline i2 used Steiner's formula incorrectly → 43. Concept i1
  got 46 (wrong). Concept i2 got the correct geometric decomposition → 39.
- **Root cause:** Largely stochastic — both runs needed multiple attempts. Elementary
  geometry concepts may have slightly biased toward decomposition over formula approach.

#### cmath_5298 — GENUINE CONCEPT WIN (concept i2 only)
- **Problem:** Highway cars with spacing rule, find max flow rate
- **Answer:** 375 (M=3750)
- **Concept:** "Floor-Ceiling Interval Bound for Integer Counting"
- **What happened:** Baseline consistently used floor() reasoning → M=3749 → 374.
  Concept run i2 applied ceil() to the flow formula → M=3750 → 375 (correct).
- **Root cause:** The floor/ceiling concept primed the model to consider ceil()
  operations for integer counting, which is the key insight for the boundary case.
  **Only genuine concept win in the dataset.**

## Summary of Failure Modes

| Category | Harms | Wins | Net |
|----------|-------|------|-----|
| Misleading (wrong approach) | 3 | 0 | -3 |
| Irrelevant noise | 1 | 0 | -1 |
| Leakage (contradictory values) | 1 | 0 | -1 |
| Stochastic | 0 | 2 | +2 |
| Genuine concept benefit | 0 | 1 | +1 |
| **Total** | **5** | **3** | **-2** |

Genuine concept signal: 1 win, 0 harms = **+1 net**.
Concept-caused damage: 5 harms from bad selection/extraction.

## Root Cause Analysis

### 1. Concept Leakage (most dangerous)
Source-problem-specific values leak into concept descriptions:
- "f(0) ∈ {0,2}" from a different functional equation → contradicts f(0)=1
- "Set B=(0,0), A=(5,0), C=(0,-8), D=(20,-8)" from a different geometry problem
- "The y-intercept is 8" from a different polynomial problem

These are implementation details that should have been stripped during extraction.
The extraction prompt should enforce: **no specific numerical values from the source
problem in concept descriptions.**

### 2. Problem Type Reframing (subtle)
Concepts that reframe the mathematical approach can be actively harmful:
- "2^a 5^b Under N Counting" turned a find-minimum into a counting problem
- "Viete's Formulas" turned direct substitution into a root-pair decomposition

The concept is mathematically related but pushes toward the wrong framing. Selection
needs to consider not just topic relevance but approach compatibility.

### 3. Irrelevant Selection (wasteful → harmful)
"Center-based Relative Coordinate System" (7×7 grid D4 symmetry) was selected for:
- An optimization problem (cmath_9987)
- A paper-folding geometry problem (cmath_3022)

At best this wastes tokens; at worst it confuses the model (cmath_3022 where
the model produced "53" with no reasoning).

## Actionable Improvements

### Extraction
1. **Strip source-specific values:** Post-process extracted concepts to remove
   specific numerical values, coordinates, and computed results. Keep the technique
   description, remove the instantiation.
2. **Validate concept generality:** A concept should make sense without knowing
   the source problem. If removing the source problem makes the concept meaningless,
   it's too specific.

### Selection
3. **Approach compatibility check:** Don't just match topic (both involve "terminating
   decimals") — check if the concept's approach aligns with what the target problem
   actually needs.
4. **Reduce max concepts per problem:** With 1.6 mean and 3+ harms from irrelevant
   concepts, reducing to max 1 concept per problem might help by limiting noise.
5. **Confidence threshold:** Skip concept injection when the selector's confidence
   is low or the match is weak. An empty hint is better than a misleading one.

### Evaluation
6. **Parser robustness:** Fixed (`\boxed` → `\?boxed`). Should also handle
   "boxed:" and other formatting variants. Consider a more flexible extraction
   that finds any answer-presentation pattern.

## Run IDs and Configs

| Run | Config | Output Dir |
|-----|--------|------------|
| Nano build | `build_math_reason_gpt5nano.yaml` | `build_math_reason_gpt5nano/dd0166da5d1a` |
| Nano baseline eval | `eval_math_reason_gpt5nano_s42.yaml` | `eval_math_reason_gpt5nano/4885376b58f8` |
| Nano concept eval | `concept_math_reason_gpt5nano_s42.yaml` | `concept_math_reason_gpt5nano/9c2923098b76` |
| Nano concept retry (34 failures) | `concept_math_reason_gpt5nano_retry34_s42.yaml` | `concept_math_reason_gpt5nano_retry34/9acb88b78c7c` |
| Mini concept eval (nano-extracted) | `concept_math_all_l5_gpt5mini_nano_s42.yaml` | `concept_math_all_l5_gpt5mini_nano/5bc46058e2d1` |

## Key Takeaway

The thinking model (gpt-5-nano) is much more robust to bad concepts than the
non-thinking model (Qwen, net -15 → nano net -2). But robustness ≠ benefit.
The current concept pipeline produces 5 harms and only 1 genuine win on the
margin. The bottleneck is concept quality (leakage, irrelevant selection,
approach mismatch), not the injection mechanism. Fix extraction and selection
first, then re-evaluate.
