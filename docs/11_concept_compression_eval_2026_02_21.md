# 17: Concept Compression & Eval — Matching arc_memo's Pipeline (2026-02-21)

## Summary

Completed the missing compression stage of arc_memo's pipeline, fixed hint rendering,
and achieved **+8% lift over baseline** (65% vs 57%) with compressed full-detail concepts.

---

## What was done

### 1. Double-wrapping bug fix
`select_concepts.py` wrapped hints with `MATH_HINT_TEMPLATE`, then `math_ps_solve.py`
wrapped again with `MATH_PS_HINT_TEMPLATE` at eval time — two stacked headers in the
solver prompt. Fixed by storing raw concept text in `prompt_info.json` and wrapping
once at eval time (matching arc_memo's pattern).

### 2. Selection failure recovery (12/100 → 100/100)
All 12 failures were `no_yaml_block` — selector model spent all tokens solving math
instead of selecting concepts. Root cause: `max_tokens=1024` too low. arc_memo's concept
memory (138K chars) is actually larger than ours (106K), but uses GPT-4.1 (better
instruction following). Fixed by bumping to `max_tokens=4096` and retrying.

### 3. Memory compression script (`scripts/compress_concepts.py`)
Built LLM-based compression following arc_memo's `memory_compression.ipynb`:
- Finds concepts with redundant cues/implementation entries
- Sends to LLM for deduplication/synthesis
- Domain-agnostic prompt (works for math, ARC, code)
- Multiple retry passes to handle transient API failures

### 4. Compression results (5 passes)

| Metric | Before | After |
|---|---|---|
| Cues mean | 6.2 | 2.3 |
| Cues max | 46 | 8 |
| Impl mean | 4.3 | 1.7 |
| Impl max | 32 | 6 |
| Concept size mean | 998 | 726 |
| Concept size max | 5,412 | 1,846 |
| Total entries | 1,225 | 473 |

Compare with arc_memo's post-compression: 2.2 cues mean, 1.4 impl mean, 718 chars mean.
Our compressed math concepts are now comparable.

### 5. Hint rendering fix
Changed `select_concepts.py` to default `show_other_concepts=False` (was True, dumping
all 117 concept names). Added `--show-other-concepts` flag for explicit opt-in.

### 6. Eval with compressed concepts

| Run | Hint type | Avg hint chars | Pass 1 | Pass 2 |
|---|---|---|---|---|
| baseline (no memory) | none | 0 | — | ~57% |
| v7 (uncompressed full + other list) | bloated | ~13,000 | 36% | 48% |
| v8 (lean: name + desc only) | minimal | ~700 | 49% | 63% |
| **v9 (compressed full detail)** | **balanced** | **~4,400** | **51%** | **65%** |

---

## Key findings

### Compression is essential
Without compression, full-detail concepts (13K chars avg) actively hurt performance (-9%
vs baseline). With compression (4.4K chars avg), full-detail concepts provide the best
results (+8% vs baseline).

### Full detail > name-only after compression
Compressed cues + implementation notes (+65%) outperform name + description only (+63%).
The solver can use the implementation notes when they're concise.

### Arc_memo's pipeline stages matter
The compression stage wasn't optional — it's critical for keeping concepts usable.
Skipping it (our earlier eval) made the concept hints counterproductive.

---

## Files modified/created

| Purpose | Path |
|---|---|
| Compression script (NEW) | `scripts/compress_concepts.py` |
| Selection script (MODIFIED) | `scripts/select_concepts.py` — show_other_concepts default, max_tokens |
| Concept selector (MODIFIED) | `src/mem2/branches/memory_retriever/concept_selector.py` — removed hint wrapping |
| Compressed concepts | `data/competition_math_nt_cp_l5/concept_memory/compressed_v1.json` |
| Regenerated prompt_info | `data/competition_math_nt_cp_l5/concept_memory/selection_v1/prompt_info.json` |
| Eval v9 output | `outputs/_runs/concept_math_eval/980bd5b0ad59/` |
| arcmemo reference doc | `arcmemo_devlog/00_arcmemo_reference.md` |

## Next steps

1. **Validate on LiveCodeBench** — run compression + selection + eval for LCB
2. **Try stronger solver** — qwen3-235b or similar to see if concept hints help more
3. **Test with fully compressed concepts** — 9 concepts still have uncompressed entries
   due to API failures; retry or accept partial compression
4. **Multiple eval runs** — current results use `ignore_cache=true` with `temperature=0.3`,
   so there's run-to-run variance. Average over 3+ runs for reliable numbers.
