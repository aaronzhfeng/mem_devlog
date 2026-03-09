# 18: Math Benchmark — Full Performance Progress

## Benchmark Setup

- **Dataset:** competition_math (Number Theory + Counting & Probability, Level 5)
- **Eval set:** 100 fixed problems, same IDs across all runs
- **Solver:** qwen/qwen-2.5-7b-instruct (temperature=0.3, max_tokens=4096)
- **Retry:** 2 passes, retry on test failure
- **Cache:** `ignore_cache=true` — fresh completions each run (introduces variance)
- **Platform:** OpenRouter

---

## Phase 1: Recovery Validation (2026-02-19)

First runs after server migration. Mixed difficulty levels (not Level 5 only).
Used to validate the pipeline works, not for memory comparison.

| Run | Model | Problems | Difficulty | Pass 1 | Pass 2 |
|---|---|---|---|---|---|
| recovery_math_10 | gemini-2.5-flash | 10 | Mixed | 100% | 100% |
| recovery_math_100_qwen | qwen3-coder-30b | 100 | Mixed | 84% | 88% |
| recovery_math_100_qwen25_7b | qwen-2.5-7b | 100 | Mixed | 71% | 78% |
| recovery_math_100_qwen3_8b | qwen3-8b | 100 | Mixed | 88% | (killed) |

**Finding:** qwen3-8b matched qwen3-coder-30b (88%) on mixed difficulty — too strong
for a weak-solver experiment. Selected qwen-2.5-7b as the solver for concept memory
experiments (weakest model with reasonable performance).

---

## Phase 2: Baseline Establishment (2026-02-19)

Switched to Level 5 only problems to create more room for memory lift.

| Run | Memory | Problem Set | Pass 1 | Pass 2 | Notes |
|---|---|---|---|---|---|
| baseline_math_l5_100 | none | 100 from HF (L5) | 34% | 46% | Different 100 problems |
| **baseline_math_eval** | **none** | **100 eval set (L5)** | **49%** | **63%** | **Canonical baseline** |

The eval set was curated from the HF dataset to have 100 specific L5 problems. All
subsequent memory experiments use this same set.

---

## Phase 3: Build Run + Concept Extraction (2026-02-19)

| Run | Purpose | Problems | Pass 2 | Output |
|---|---|---|---|---|
| build_math | Solve problems for concept extraction | 200 (L5) | 61.5% (123 solved) | 123 solved → 117 concepts |

The 200 build problems are separate from the 100 eval problems. Solved problems went
through the two-stage concept extraction pipeline (solution → pseudocode → typed
concept annotations).

---

## Phase 4: Memory Eval — All on Same 100 Eval Problems (2026-02-19 to 2026-02-21)

All runs below use **qwen-2.5-7b** solver on the **same 100 Level 5 eval problems**.

### Verified runs (from summary.json + driver.log)

| Run | Memory Type | Pass 1 | Pass 2 | Delta vs Baseline |
|---|---|---|---|---|
| baseline_math_eval | none | 49% | 63% | — |
| memory_math_eval | stub lessons (lesson_topk) | 47% | 57% | **-6%** |
| concept_math_eval (inline) | concept (inline LLM select) | 41% | 62% | **-1%** |
| **concept_math_eval (compressed)** | **concept (precomputed, compressed)** | **51%** | **65%** | **+2%** |

### Additional variants (from devlog, not all have separate run dirs)

These were tested by regenerating prompt_info.json and re-running under the same
config. Results from conversation logs:

| Variant | Hint Details | Avg Hint Chars | Pass 1 | Pass 2 | Delta |
|---|---|---|---|---|---|
| v4 (dump-all fallback) | All 117 concepts on selection failure | ~107,000 | 37% | 54% | **-9%** |
| v5 (no-hints fallback) | Skip hints on selection failure | varies | 41% | 62% | **-1%** |
| v6 (precomputed, double-wrapped) | Uncompressed, double hint template | ~13,000 | 42% | 54% | **-9%** |
| v7 (uncompressed full + other list) | Full detail + all concept names | ~13,000 | 36% | 48% | **-15%** |
| v8 (lean: name + desc only) | Name + description only | ~700 | 49% | 63% | **0%** |
| **v9 (compressed full detail)** | **Compressed cues + impl, no other list** | **~4,400** | **51%** | **65%** | **+2%** |

---

## Performance Trajectory (Pass 2 — Same 100 Problems)

```
65% ──────────────────────────────────────── v9 compressed concepts (+2%)
63% ──────────────────────────────────────── BASELINE (no memory) / v8 lean
62% ──────────────────────────────────────── v5 inline (no-hints fallback)
57% ──────────────────────────────────────── stub lessons (lesson_topk)
54% ──────────────────────────────────────── v4 dump-all / v6 double-wrapped
48% ──────────────────────────────────────── v7 uncompressed full + other list
```

---

## Concept Memory Pipeline Stages & Their Impact

| Stage | What it does | Impact on performance |
|---|---|---|
| Extraction (2-stage LLM) | solution → pseudocode → typed concepts | Foundation — 117 concepts from 123 solved problems |
| Compression (LLM dedup) | Deduplicate cues/impl entries | Critical — without it, hints are too long and hurt perf |
| Selection (offline LLM) | Pick 4-5 relevant concepts per problem | Important — dumping all concepts causes -15% |
| Rendering (to_string) | Format selected concepts as text | show_other_concepts=False saves ~8K chars per hint |
| Hint wrapping | Single template wrap at eval time | Double-wrapping caused bugs, must wrap exactly once |

### Concept stats before/after compression

| Metric | Before compression | After compression | arc_memo reference |
|---|---|---|---|
| Cues mean | 6.2 | 2.3 | 2.2 |
| Cues max | 46 | 8 | — |
| Impl mean | 4.3 | 1.7 | 1.4 |
| Impl max | 32 | 6 | — |
| Concept size mean | 998 chars | 726 chars | 718 chars |

---

## Hint Size vs Performance

```
Pass 2 %
  65 |                                                    * v9 (4.4K)
  63 |              * baseline (0)         * v8 (0.7K)
  62 |                                 * v5
  57 |          * stub
  54 |                                         * v6 (13K)
  48 |                                              * v7 (13K)
     +----+----+----+----+----+----+----+----+----+----+----
     0   1K   2K   3K   4K   5K   6K   8K  10K  12K  14K
                        Avg hint size (chars)
```

Sweet spot: ~4K chars of compressed, full-detail concept hints.

---

## Key Takeaways

1. **Concept memory provides +2% lift** (65% vs 63%) over no-memory baseline with the
   complete pipeline (extraction + compression + selection + lean rendering).

2. **Uncompressed concepts hurt performance** (-9% to -15%) — the solver cannot parse
   13K+ chars of hints and produces worse solutions.

3. **Compression is not optional** — it's the difference between -9% and +2%. Without
   compression, concept memory is counterproductive.

4. **The "57% baseline" in earlier devlogs is the stub-lesson run**, not the clean
   no-memory baseline (which is 63%). This overstated the apparent lift of concept
   memory by 6 percentage points.

5. **Run-to-run variance is ~3-5%** with temperature=0.3 and ignore_cache=true.
   The +2% lift is within noise. Multiple runs needed to confirm statistical significance.

---

## Caveats

- All results are single runs (no averaging). With temp=0.3, expect ~3-5% variance.
- The solver model (qwen-2.5-7b) may be too weak to fully exploit concept hints.
  arc_memo uses a stronger model gap (GPT-4.1 selector → DeepSeek solver).
- The 100-problem eval set is fixed but relatively small for detecting small effects.
- Concept memory was extracted from a different 200-problem build set — no data leakage
  between build and eval sets.

---

## File Locations

| Run | Path |
|---|---|
| baseline_math_eval | `outputs/_runs/baseline_math_eval/d6436faba6c1/` |
| memory_math_eval (stub) | `outputs/_runs/memory_math_eval/98f73164c213/` |
| concept_math_eval (inline) | `outputs/_runs/concept_math_eval/c72796785b5b/` |
| concept_math_eval (compressed) | `outputs/_runs/concept_math_eval/980bd5b0ad59/` |
| Compressed concepts | `data/competition_math_nt_cp_l5/concept_memory/compressed_v1.json` |
| Prompt info (v9) | `data/competition_math_nt_cp_l5/concept_memory/selection_v1/prompt_info.json` |
