# 19: LiveCodeBench Concept Memory Pipeline — Case Study (2026-02-23)

## Summary

Ported the full concept memory pipeline to LiveCodeBench (LCB). After fixing
infrastructure issues (max_tokens for thinking models, code-domain prompt
templates), the pipeline runs end-to-end but yields **-1% vs baseline** (24% vs
25% at pass@2). Deep case study reveals the performance loss is entirely caused
by **evaluator `exec()` scoping failures**, not by algorithmic degradation from
concepts. Fixing the infra issues would flip the result to **+2% lift**.

---

## What Was Done

### 1. Bug fixes

**Problem text extraction for code domain** — Two locations used
`metadata.get("problem_text")` for LCB problems, but LCB stores the problem
statement in `metadata["question_content"]`. Without the fix, selection prompts
received `str(metadata)` (the entire dict), making concept selection garbage.

- `scripts/select_concepts.py` — `format_problem_text()`
- `src/mem2/branches/memory_retriever/concept_selector.py` — `_format_problem_for_selection()`

### 2. Code-domain prompt templates

Created `src/mem2/concepts/prompts/code_select.py` and `code_hints.py`. The code
domain was previously reusing math templates. New templates reference algorithms,
data structures, and competitive programming patterns instead of theorems and
number theory. Wired into `DOMAIN_PROMPT_MAP["code"]` in `__init__.py`.

### 3. Compression (v2)

Ran `scripts/compress_concepts.py` on `extracted_v2.json` (60 concepts from 47
solved problems, extracted 2026-02-20 with `qwen/qwen3.5-397b-a17b`).

**v1 attempt** (max_tokens=1024): 54% failure rate — thinking model's reasoning
tokens exceeded the budget, leaving zero tokens for content.

**v2** (max_tokens=16384): 98% success (58/59 compressed).

| Metric | Before | After |
|---|---|---|
| Cues mean | 5.5 | 2.6 |
| Impl mean | 4.6 | 2.3 |
| Total size reduction | — | 51% |

Output: `data/livecodebench_v56/concept_memory/compressed_v2.json`

### 4. Offline concept selection (v2)

Ran `scripts/select_concepts.py` on the 100-problem eval set.

**v1** (max_tokens=4096): 44% failure rate (same thinking-token issue).

**v2** (max_tokens=16384): 96% success (96/100), mean 5.0 concepts per problem.

Output: `data/livecodebench_v56/concept_memory/selection_v2/`

### 5. Eval config

Created `configs/experiments/concept_lcb_eval.yaml` — same 100 problem IDs
and solver model (`qwen/qwen3-coder-30b-a3b-instruct`) as `baseline_lcb_eval.yaml`,
with concept memory builder + retriever wired in.

---

## Results

### Before `exec()` fix

| Run | Pass 1 | Pass 2 | Delta vs Baseline |
|---|---|---|---|
| baseline_lcb_eval | 21% | 25% | — |
| concept_lcb_eval (v2) | 20% | 24% | **-1%** |

Per-problem breakdown (pre-fix):

| Category | Count | Problems |
|---|---|---|
| Genuinely helped | 2 | abc384_f, abc386_c |
| Genuinely hurt | 3 | abc375_d, abc397_g, arc185_c |
| Variance (zero concepts) | 2 | arc194_d (helped), arc196_b (hurt) |
| Both solved | 21 | — |
| Neither solved | 72 | — |

### After `exec()` fix

Fixed `exec(code, {"__builtins__": __builtins__}, {})` (separate globals/locals)
→ `exec(code, {"__builtins__": __builtins__, "__name__": "__main__"})` (single
namespace + `__name__` set). This fixed two classes of silent failures:
1. List comprehensions at top level couldn't see variables (separate scope dicts)
2. `if __name__ == "__main__"` guards never fired

| Run | Pass 1 | Pass 2 | Delta vs Baseline |
|---|---|---|---|
| baseline_lcb_eval | **24%** | **34%** | — |
| concept_lcb_eval (v2) | **25%** | **33%** | **-1%** |

The fix gave **+9% on pass 2** for both runs. Many correct solutions were
silently failing under `exec()` before. But the concept vs baseline delta
remains -1%.

Post-fix per-problem breakdown:

| Category | Count |
|---|---|
| Helped by concepts | 5 |
| Hurt by concepts | 6 |
| Both pass | 28 |
| Neither passes | 61 |

The hurt/helped lists completely reshuffled due to LLM sampling variance.
The original 3 `exec()` hurt cases are no longer systematically failing,
but new variance-driven differences appeared. **Concepts are neutral on LCB.**

---

## Deep Case Study: How Concepts Changed Outcomes

### Helped cases (concept solved, baseline failed)

**abc384_f** — Baseline over-engineered a grouping approach with a nested `f(x)`
function that failed under the evaluator's code extraction. Concepts ("Pair
Counting from Frequencies", "Conditional Summation") steered toward a clean
14-line brute-force double loop. The simpler code ran correctly.

**abc386_c** — Baseline had a missing boundary condition: when the difference
occurs at the very end of the string, the post-loop check was wrong. The "Index
Boundary Check" concept directly addressed this — the concept version added
explicit end-of-loop validation that the baseline lacked.

### Hurt cases (baseline solved, concept failed)

**All 3 failures were execution/infrastructure failures, not algorithmic
failures.** The concept versions produced correct or reasonable algorithms
that failed due to code packaging issues under `exec()`.

| Problem | Algorithm OK? | Failure Mode |
|---|---|---|
| abc375_d | Yes (same prefix/suffix approach) | Top-level code: `[0]*n for _ in range(26)` can't see `n` under `exec()` scoping |
| abc397_g | Partially (correct approach) | Model redefined `main()` 11+ times without calling any — analysis paralysis from 4 concept hints |
| arc185_c | Yes (same 3-sum hash approach) | `if __name__ == "__main__"` guard fails under `exec()` — `__name__` not set to `"__main__"` |

The baseline versions of these same algorithms succeeded because they used
`def solve(): ...` wrappers with direct calls, avoiding the `exec()` scoping
issues.

### Concept selector statistics

| Group | Count | Avg Concepts | Avg Specificity | Avg Generic Ratio |
|---|---|---|---|---|
| Helped | 2 | 3.7 | 0.152 | 0.47 |
| Hurt | 3 | 4.0 | 0.180 | 0.16 |
| Both solved | 21 | 3.7 | 0.126 | 0.35 |
| Neither solved | 72 | 5.2 | 0.094 | 0.33 |

- Top concept: `Linear Scan` selected for 78/100 problems — essentially noise.
- NEITHER group gets the most concepts (5.2 avg) with the lowest specificity
  (0.094), suggesting the selector defaults to generic concepts on hard problems.

---

## Thinking Model max_tokens Lesson

Qwen3.5-397b-a17b (thinking model) uses reasoning tokens that count against
`max_tokens`. Average reasoning token usage was ~4800-6800 tokens. With
`max_tokens=1024` (compression) or `max_tokens=4096` (selection), the reasoning
consumed the entire budget, leaving zero tokens for content output.

The LLM client logged `content is None` warnings and returned empty strings.
This manifested as `empty_completion` parse errors.

**Fix:** Set `max_tokens=16384` for all thinking model calls. This resolved:
- Compression: 54% → 1.7% failure rate
- Selection: 44% → 4% failure rate

This applies to any thinking/reasoning model — always budget for reasoning
tokens on top of expected content length.

---

## Key Takeaways

1. **The `exec()` fix was critical infrastructure.** Changing from separate
   globals/locals dicts to a single namespace + `__name__` gave +9% on pass 2
   for both baseline and concept runs. Many correct solutions were silently
   failing.

2. **Concepts are neutral on LCB after the fix.** The pre-fix analysis showed
   concepts causing `exec()` failures (3 hurt cases). After fixing, those
   specific failures went away — but the concept delta is still -1%, now driven
   by LLM sampling variance rather than systematic `exec()` failures.

3. **The pre-fix case study was misleading.** It attributed concept failures to
   `exec()` scoping and predicted +2% lift after fixing. In reality, the fix
   helped baseline equally (+9%) because baseline solutions also had scoping
   issues. The concept advantage was an artifact of the broken evaluator.

4. **Generic concept flooding is a concern.** `Linear Scan` at 78% selection
   rate provides no discriminative signal. The selector needs better calibration
   or a minimum specificity threshold.

5. **Thinking models need large max_tokens budgets.** The default 1024 is
   completely insufficient. Use 16384+ for any call to a reasoning model.

6. **Run-to-run variance is ~5-6%.** With temperature=0.3 and ignore_cache=true,
   the helped/hurt lists completely reshuffle between runs. The -1% delta is
   well within noise.

---

## Next Steps

1. **Concept router** (future) — Dynamic adaptor to decide per-problem whether
   to include concept hints, based on problem features and selection quality.
   May help if concepts can be targeted to problems where they add value.
2. **Better concept selection** — Reduce generic concept flooding (Linear Scan
   at 78%). Consider minimum specificity thresholds or diversity-aware selection.
3. **Larger concept memory** — Current LCB memory has only 60 concepts from 47
   problems. Math had 117 concepts from 123 problems. More diverse concepts
   might improve coverage on hard problems (61 unsolved by either run).

---

## File Locations

| Artifact | Path |
|---|---|
| Compressed concepts (v2) | `data/livecodebench_v56/concept_memory/compressed_v2.json` |
| Selection (v2) | `data/livecodebench_v56/concept_memory/selection_v2/` |
| Eval config | `configs/experiments/concept_lcb_eval.yaml` |
| Baseline run | `outputs/_runs/baseline_lcb_eval/381f50cc86b3/` |
| Concept eval run (v2) | `outputs/_runs/concept_lcb_eval/5b45ec1b8b4c/` |
| Code-domain prompts | `src/mem2/concepts/prompts/code_select.py`, `code_hints.py` |
