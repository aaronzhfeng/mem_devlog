# Devlog 29 — Clean Oracle Analysis (12 Runs, Fixed Feedback)

**Date:** 2026-02-26

## Summary

Completed comprehensive oracle analysis across 12 experiment runs:
- 2 benchmarks (Math, LCB) × 3 configs (baseline, concepts, concept-retry) × 2 seeds (42, 43)
- All runs use **fixed feedback engine** (no ground-truth leakage)
- Oracle analysis uses proper `metadata.pass_idx` filtering (script bug fixed)
- 2-seed design enables **variance-controlled** genuine signal measurement

## Run Matrix

All runs use Qwen models (Qwen-2.5-7B for math, Qwen3-Coder-30B-A3B for LCB).

| Config | Math s42 | Math s43 | LCB s42 | LCB s43 |
|--------|----------|----------|---------|---------|
| Baseline (p1→p1+2) | 55→67 | 41→57 | 26→32 | 25→35 |
| Concepts (p1→p1+2) | 51→63 | 39→53 | 23→32 | 27→35 |
| Concept-retry (p1→p1+2) | 46→54 | 49→61 | 25→33 | 23→30 |

Run IDs:
- Baseline math: e47a68550a31 (s42), cc995e36926b (s43)
- Baseline LCB: ee8aefd8ca5a (s42), e2e77deadd11 (s43)
- Concepts math: 88c4414888d0 (s42), ae889bbb7549 (s43)
- Concepts LCB: 4142b8923310 (s42), 6cbb14c3bce8 (s43)
- Concept-retry math: 46a751e4717e (s42), 7f5b1d30c7f5 (s43)
- Concept-retry LCB: 8b4589770d21 (s42), 68c761057d1b (s43)

## Oracle Analysis — Key Numbers

### Math (Pass 1 only)

| Metric | Concepts | Concept-retry |
|--------|----------|---------------|
| Baseline oracle (2 seeds) | 64 | 64 |
| Method oracle (2 seeds) | 56 | 63 |
| Combined oracle | 74 | 75 |
| Gain over baseline oracle | +10 | +11 |
| **Genuine wins** | **10** | **11** |
| **Genuine harms** | **18** | **12** |
| **Net signal** | **-8** | **-1** |

### Math (Pass 1+2)

| Metric | Concepts | Concept-retry |
|--------|----------|---------------|
| Baseline oracle (2 seeds) | 77 | 77 |
| Method oracle (2 seeds) | 68 | 73 |
| Combined oracle | 81 | 86 |
| Gain over baseline oracle | +4 | +9 |
| **Genuine wins** | **4** | **9** |
| **Genuine harms** | **13** | **13** |
| **Net signal** | **-9** | **-4** |

### LCB (Pass 1 only)

| Metric | Concepts | Concept-retry |
|--------|----------|---------------|
| Baseline oracle (2 seeds) | 29 | 29 |
| Method oracle (2 seeds) | 31 | 31 |
| Combined oracle | 36 | 36 |
| Gain over baseline oracle | +7 | +7 |
| **Genuine wins** | **7** | **7** |
| **Genuine harms** | **5** | **5** |
| **Net signal** | **+2** | **+2** |

### LCB (Pass 1+2)

| Metric | Concepts | Concept-retry |
|--------|----------|---------------|
| Baseline oracle (2 seeds) | 41 | 41 |
| Method oracle (2 seeds) | 39 | 40 |
| Combined oracle | 43 | 47 |
| Gain over baseline oracle | +2 | +6 |
| **Genuine wins** | **2** | **6** |
| **Genuine harms** | **4** | **7** |
| **Net signal** | **-2** | **-1** |

## Interpretation

### 1. Concepts are net-negative on Math

Always-on concepts show **-8 net signal** on pass 1 (10 genuine wins, 18 genuine harms). The concept hints actively mislead the model on nearly twice as many problems as they help. With retry, this improves to -1 — suggesting that when the model already failed once, concepts are less harmful (or the retry mechanism absorbs some of the damage).

### 2. Concepts are approximately neutral on LCB

On pass 1, both concept variants show **+2 net signal** (7 wins, 5 harms). This is within noise for 100 problems, but the direction is mildly positive. On pass 1+2 this flattens to -1/-2, again noise range.

### 3. Concept-retry is strictly better than always-on concepts

On math pass 1: concept-retry=-1 vs concepts=-8. On math pass 1+2: concept-retry=-4 vs concepts=-9. The "withhold concepts on first try, inject on retry" strategy consistently reduces harm while preserving most of the genuine wins.

### 4. Sampling variance is large

Math baseline oracle (2 seeds) = 64, but individual seeds are 55 and 41. That's a 14-point spread from the same config. LCB is tighter (26 vs 25, 1-point spread). This means any single-run comparison on math is unreliable — you need multi-seed oracle to distinguish signal from noise.

### 5. Oracle headroom exists but is bidirectional

The combined oracle (baseline + concepts) reaches 74-75 on math pass 1, vs 64 for baseline alone. This means concepts DO solve 10-11 problems that baseline never solves across seeds. But they also miss 12-18 that baseline catches. The oracle gain is real but misleading if cited without the harm count.

## Next Steps

1. **Investigate the 10 genuine math wins** — what do these problems have in common? Are the concepts actually helpful or is the model getting lucky with different prompts?
2. **Investigate the 18 genuine math harms** — can we identify patterns to route these away from concept injection?
3. **Try concept routing** — use an LLM/NLI router to gate concept injection per-problem. The pipeline router infrastructure is built (devlog 26).
4. **Consider SkillRL-style lean hints** — current concepts may be too verbose. SkillRL uses (title, principle, when_to_apply) format which is much leaner.
5. **Expand to more seeds** — 2 seeds gives marginal variance control. 3-5 seeds would narrow confidence intervals.
