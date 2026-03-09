# 27: Oracle Best-Of Analysis & Feedback Engine Fix (2026-02-25)

## Ground-Truth Leakage Bug

Discovered that both the math and LCB feedback engines were leaking ground-truth
information to the solver on retry, inflating all pass 2 scores.

**Math (`math_ps_gt.py`)**: On wrong answer, the feedback said
`"Your code returned X, but the expected answer is Y"` — literally giving the
model the answer. The model could hardcode it on retry.

**LCB (`lcb_gt.py`)**: Feedback included private test case results (expected vs
actual output). Only public test cases (part of the problem statement) should be
exposed. Private test results are ground truth.

**ARC (`gt_check.py`)**: Correct — only uses train example results, which are
part of the problem definition. Matches arc_memo's behavior.

### Fix

**Math**: Wrong answers now return just `"Incorrect"`. Parsing errors and
execution errors are still shown (they come from the model's own code, not GT).
Removed `expected` field and `mismatches` from metadata entirely.

**LCB**: `_extract_outcomes()` now filters on `is_train` flag — only public test
failures are exposed. When public tests pass but private fail, feedback says
`"Example tests passed (N/N), but some hidden tests failed"`.

### Impact

All pass 2 scores for math and LCB are inflated. Pass 1 scores are unaffected
(no feedback involved). Need to re-run baselines and concept evals with the
fixed feedback engine to get clean pass 2 numbers.

### Files Changed

| File | Change |
|------|--------|
| `src/mem2/branches/feedback_engine/math_ps_gt.py` | Removed GT leak |
| `src/mem2/branches/feedback_engine/lcb_gt.py` | Filter to public tests only |
| `tests/unit/test_math_ps.py` | Updated assertions (no answer in content) |
| `tests/unit/test_lcb.py` | Added `is_train` flags, added private-only test |

254 unit tests passing, 0 regressions.

---

## Oracle Best-Of Analysis

### Motivation

Concept hints help some problems and hurt others in roughly equal measure
(devlog 25). Matthew Ho suggested checking whether ensembling (oracle best-of,
then model-driven answer selection) can extract only the improvements. The
oracle gives the ceiling: if we could perfectly predict which problems benefit
from concepts, how much would we gain?

### Method

Script: `scripts/oracle_analysis.py`

For each problem, check if it was solved in the baseline run OR the concept run.
Oracle = union of solved problems. Uses `eval_records.jsonl` per-problem results.
Pass 1 only (clean, unaffected by feedback bug).

### Results

#### Math (100 Level 5 problems, qwen-2.5-7b)

**Pairing 1: baseline 63% (d6436faba6c1) vs concepts 65% (980bd5b0ad59)**

| Metric | Count |
|--------|-------|
| Baseline solved | 63 |
| Concept solved | 65 |
| **Oracle solved** | **78** |
| Both solved | 50 |
| Concept-only wins | 15 |
| Baseline-only wins | 13 |
| Neither | 22 |
| **Oracle gain over baseline** | **+15** |

**Pairing 2: baseline 58% (f43eb6749d27) vs concepts 65% (980bd5b0ad59)**

| Metric | Count |
|--------|-------|
| Baseline solved | 58 |
| Concept solved | 65 |
| **Oracle solved** | **77** |
| Both solved | 46 |
| Concept-only wins | 19 |
| Baseline-only wins | 12 |
| Neither | 23 |
| **Oracle gain over baseline** | **+19** |

Concept-only wins consistent across both pairings:
`cmath_10994`, `cmath_11021`, `cmath_2305`, `cmath_2460`, `cmath_5322`, `cmath_5354`
(6 stable concept-only wins appearing in both pairings).

Baseline-only wins consistent across both pairings:
`cmath_10984`, `cmath_1803`, `cmath_5024`, `cmath_5071`, `cmath_5307`, `cmath_8695`
(6 stable baseline-only wins appearing in both pairings).

#### LCB (100 problems, qwen3-coder-30b)

**Baseline 34% (381f50cc86b3) vs concepts 25% (3a65ba81ebad)**

| Metric | Count |
|--------|-------|
| Baseline solved | 34 |
| Concept solved | 25 |
| **Oracle solved** | **37** |
| Both solved | 22 |
| Concept-only wins | 3 |
| Baseline-only wins | 12 |
| Neither | 63 |
| **Oracle gain over baseline** | **+3** |

### Interpretation (CORRECTED — see devlog 28)

**⚠️ The original interpretation below was wrong. See devlog 28 for the
corrected analysis with variance control.**

**Math**: The oracle ceiling is 77-78%, a +15 point gain over baseline. However,
oracle(baseline1, baseline2) = **also 78** — the same gain from just running
baseline twice with different seeds. The 15-point oracle gain is entirely
explained by sampling variance (~35/100 problems flip between identical runs).

Cross-referencing concept-only wins against both baselines:
- 6 problems solved by concepts but neither baseline (genuine concept wins)
- 6 problems solved by both baselines but not concepts (genuine concept harm)
- Net genuine effect: **0**

The remaining 9 "concept-only wins" overlap with baseline variance.

**LCB**: The oracle ceiling is only 37%, just +3 over baseline. Concepts are net
harmful — 12 problems lost, only 3 gained. Even perfect routing barely helps.
The concept content for code may need fundamental revision, or LCB may simply not
benefit from algorithm-level concept memory with this model.

### Implications for Resubmission

The oracle analysis, properly controlled, shows concepts have a real but
symmetric effect: 6 genuine wins and 6 genuine harms cancel to net zero.
The maximum recoverable gain from perfect routing is +6%, not +15%.

Viable approaches to test (see devlog 28 for full plan):
1. **Concepts on retry only**: pass 1 no concepts, pass 2 with concepts for
   failures. Tests if concepts help specifically when the model is stuck.
2. **Oracle ensembling with LLM judge**: run both configs, use LLM to pick
   better answer. Ceiling is +6% (the 6 genuine wins).
3. **Re-run with fixed feedback**: get clean pass 2 numbers first.

---

## Next Steps

1. **Re-run baselines with fixed feedback** — get clean pass 2 numbers for math
   and LCB. All prior pass 2 scores are invalid.
2. **Oracle ensembling with LLM judge** — run baseline + concept configs on same
   problems, use model to select better answer. Measures how much of the oracle
   ceiling is recoverable.
3. **Concepts on retry** — pass 1 no concepts, pass 2 add concepts for failures.
   Minimal method change, tests the self-correction hypothesis.
4. **Cross-reference concept-only wins with problem features** — what makes the
   15 concept-helped math problems different from the 13 concept-hurt ones?

---

## Files Created

| File | Description |
|------|-------------|
| `scripts/oracle_analysis.py` | Oracle best-of analysis script |
| `arcmemo_devlog/27_oracle_analysis_feedback_fix_2026_02_25.md` | This devlog |
