# 28: Oracle Control & Experiment Plan (2026-02-25)

## Bug: oracle_analysis.py pass filter was broken

The `--max-pass 0` filter in `oracle_analysis.py` checked `attempt_idx`, which
is always 0 in eval_records. The actual pass index is in `metadata.pass_idx`.
All oracle numbers in devlog 27 silently included corrupted pass 2 data.

**Fix**: `oracle_analysis.py` now reads `metadata.pass_idx` with fallback to
`attempt_idx`.

## Corrected Oracle Analysis (pass 1 only, clean)

| Run | Pass 1 Accuracy |
|-----|----------------|
| Baseline1 (d6436faba6c1) | **49%** (was reported as 63% with corrupted pass 2) |
| Baseline2 (f43eb6749d27) | **47%** (was reported as 58%) |
| Concepts (980bd5b0ad59) | **51%** (was reported as 65%) |

### Variance Control

| Oracle Pairing | Solved | Gain over Baseline1 |
|----------------|--------|---------------------|
| Oracle(b1, b2) — two baselines | **66** | +17 |
| Oracle(b1, concepts) | **67** | +18 |
| Oracle(b2, concepts) | **68** | +21 |

Oracle(b1, concepts) ≈ Oracle(b1, b2). The concept oracle doesn't meaningfully
exceed the variance oracle.

### Genuine Signal (cross-referenced against both baselines)

| Category | Count | Problems |
|----------|-------|----------|
| Genuine concept wins (neither baseline solves) | 9 | cmath_10546, cmath_10994, cmath_11021, cmath_2305, cmath_2460, cmath_5170, cmath_5322, cmath_5335, cmath_5345 |
| Genuine concept harm (both baselines solve, concept doesn't) | 9 | cmath_10571, cmath_10677, cmath_10984, cmath_1803, cmath_5024, cmath_5071, cmath_5193, cmath_5289, cmath_8695 |
| Variance-explained (overlap with b2-only wins) | 9 | cmath_10620, cmath_11038, cmath_2124, cmath_2129, cmath_2144, cmath_2180, cmath_2183, cmath_4749, cmath_5310 |
| **Net genuine effect** | **0** | |

Of the 18 "concept-only wins" vs baseline1, 9 are also solved by baseline2
(variance). The remaining 9 are genuine concept wins, balanced by 9 genuine
harms.

### What This Means

Concepts have a real but symmetric effect: 9 genuine wins + 9 genuine harms,
net zero. The maximum recoverable gain from perfect routing is +9% (if we
could capture all genuine wins and avoid all harms). Oracle ensembling ceiling
is similarly bounded.

---

## Experiment Plan

Three categories: (A) clean up existing data, (B) concepts-on-retry, (C) ensembling.

### A. Re-run with Fixed Feedback (clean pass 2 data)

**Why**: The feedback engine bug (devlog 27) invalidated all pass 2 scores. We
need clean multi-pass data before testing any retry-based approach.

**Runs needed** (all on same 100 math problems, qwen-2.5-7b):

| Run | Config | Passes | Concepts | Purpose |
|-----|--------|--------|----------|---------|
| A1 | baseline_math_eval | 2 | No | Clean baseline pass 1+2 |
| A2 | baseline_math_eval (seed=43) | 2 | No | Second baseline for variance control |
| A3 | concept_math_eval | 2 | Yes (all passes) | Clean concept pass 1+2 |

This gives us clean pass 2 numbers AND a second baseline for variance control
on pass 2 scores.

**Config changes**: None needed — feedback engine already fixed. Just re-run
existing configs. Change seed on A2 to get independent sample.

### B. Concepts on Retry Only

**What**: Pass 1 runs without concepts. Pass 2 injects concepts only for
problems that failed pass 1. Tests whether concepts help specifically when the
model is stuck, rather than as uniform guidance.

**Why** (from slack discussion): Self-reflection works for ARC because train
examples give unambiguous signal. For math/code, the model already knows it
failed (feedback says "Incorrect"). The question is whether adding concepts
on retry gives the model a different angle of attack it wouldn't find from
just the error feedback alone.

**Implementation**: The pipeline already supports this via existing config flags:

```yaml
inference_engine:
  prompt_options:
    include_hint: false           # No concepts on pass 1 (initial)
  include_reselected_lessons: true  # Yes concepts on pass 2+ (retry)
```

- `include_hint: false` → `make_initial_prompt()` skips hint_text
- `include_reselected_lessons: true` → `retry_attempt()` includes hint_text,
  runner triggers concept reselection on pass 2+

**Runs needed**:

| Run | Config | Passes | Pass 1 | Pass 2 | Purpose |
|-----|--------|--------|--------|--------|---------|
| B1 | concept_retry_math_eval (new) | 2 | No concepts | With concepts | Concepts on retry |

**New config**: `configs/experiments/concept_retry_math_eval.yaml`
- Clone concept_math_eval.yaml
- Set `prompt_options: {include_hint: false}`
- Set `include_reselected_lessons: true`
- Keep same memory_builder/retriever (concepts are loaded but only used on retry)

**What to compare**:
- B1 pass 1 should match A1 pass 1 (no concepts, same setup) — sanity check
- B1 pass 2 vs A1 pass 2: does adding concepts on retry beat just retrying
  with error feedback alone?
- B1 pass 2 vs A3 pass 2: does concepts-on-retry beat concepts-always?

### C. Ensembling / LLM Judge

**What**: Run both baseline and concept configs on same problems, use an LLM
to pick the better answer per problem. Approximates oracle best-of but with
a realizable answer selector.

**Why** (Matthew's suggestion): If concepts help some problems and hurt others,
ensembling extracts only the improvements without needing to predict which
problems benefit in advance.

**Prerequisite**: Needs runs A1 and A3 completed first (or can reuse existing
pass 1 data from before the feedback fix, since pass 1 was unaffected).

**Implementation**: New script `scripts/ensemble_judge.py`:
1. Load per-problem solutions from baseline and concept runs
2. For each problem where they disagree, present both solutions to an LLM judge
3. Judge picks which solution is more likely correct
4. Score = baseline answers on judge-picks-baseline + concept answers on
   judge-picks-concept

**Ceiling from oracle control**: The maximum possible gain from ensembling is
+6% (the 6 genuine concept wins). A perfect judge would recover all 6 wins
and avoid all 6 harms. A realistic judge will do worse.

**What to compare**:
- Ensemble score vs baseline score vs concept score
- Per-problem: does the judge correctly pick concept on the 6 genuine-win
  problems and baseline on the 6 genuine-harm problems?

### D. (Later) Hard-Only Subsets

Lower baseline = more headroom. If concepts help when the model genuinely
struggles, filtering to hard problems should show a bigger effect. Deferred
until A/B/C results are in — if concepts-on-retry works, hard-only amplifies
it. If it doesn't, hard-only won't save it.

---

## Execution Order

1. **Immediate** (no new runs): Update devlog 27 with corrected oracle
   interpretation
2. **A1, A2, A3**: Re-run with fixed feedback (clean pass 2 baseline + concept)
3. **B1**: Concepts on retry (after A1 confirms clean baseline)
4. **C**: Ensembling with LLM judge (can use existing pass 1 data)
5. **Cross-reference**: Compare the 6 genuine-win and 6 genuine-harm problems
   across all experiments — what makes them different?

## Key Metrics

For each experiment, report:
- Pass 1 accuracy, Pass 2 accuracy
- Oracle(baseline, X) vs Oracle(baseline1, baseline2) — always include the
  variance control
- Genuine wins/harms (problems solved by experiment but neither baseline,
  and vice versa)
- Net effect after variance correction

---

## Files to Create

| File | Description |
|------|-------------|
| `configs/experiments/concept_retry_math_eval.yaml` | Concepts on retry config |
| `scripts/ensemble_judge.py` | LLM judge ensembling script |
| Updated `arcmemo_devlog/27_...` | Corrected oracle interpretation |
