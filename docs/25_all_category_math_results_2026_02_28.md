# Devlog 30 — All-Category Math L5 Results

**Date:** 2026-02-28

## Motivation

Previous experiments used a biased subset: only Number Theory + Counting & Probability (2 of 7 MATH categories). This devlog covers re-running on all 7 categories to get a representative evaluation.

## Dataset: competition_math_all_l5

- Source: qwedsacf/competition_math (HuggingFace), Level 5 only, integer-answer filter
- Total eligible: 2,156 problems across all 7 categories
- Split: 500 build / 200 eval / 1,456 held_out (random, seed=42)
- Eval category distribution: Algebra 44, Number Theory 41, Intermediate Algebra 41, Geometry 24, C&P 22, Prealgebra 20, Precalculus 9
- Path: data/competition_math_all_l5/

## Concept Pipeline

- Build run: 500 problems, Qwen-2.5-7B, 250 solved (50%)
- Extraction: 112 concepts from 247 solved problems (3 parse failures)
- Compression (v1, 1024 max_tokens): failed on 6 bloated concepts — `algorithm` kept 99 cues, `system of equations` kept 92 cues
- Compression (v2, 8192 max_tokens): 0 failures, but only 32% reduction. Bloated concepts are genuinely over-generic, not just truncated
- Filtered version: dropped 22 concepts with >10 cues. 90 concepts remain

## Root Cause: Bloated Concepts

Old NT+CP dataset produced specific concepts (max 8 cues, max 6 impl) like "Valuation Analysis", "Direct Enumeration". New all-category dataset produces generic catch-alls:

| Concept | Cues | Impl |
|---|---|---|
| algorithm | 99 | 163 |
| system of equations | 92 | 134 |
| algebraic manipulation | 82 | 142 |
| constraint satisfaction | 82 | 116 |

Compression can't fix this — the LLM treats 99 slightly-different cues as distinct. The extraction prompt needs to discourage generic names on broad datasets.

## Run Matrix

All runs: Qwen-2.5-7B, 200 eval problems, 2 passes, fixed feedback engine.

| Config | s42 | s43 | s44 | s45 |
|---|---|---|---|---|
| Baseline | 117 | 120 | 110 | 108 |
| CR unfiltered | 114 | 113 | — | — |
| CR filtered (<=10 cues) | 107 | 108 | — | — |

Run IDs:
- Baseline: 797378910963 (s42), 1423111ddaa1 (s43), b36f890392fc (s44), 85c79028341b (s45)
- CR unfiltered: 9957fada8650 (s42), 8d952d6f7689 (s43)
- CR filtered: 2b6e0b3bfdae (s42), 5d0942ff7ac4 (s43)

## Ensemble Oracle (pass 1+2)

| Ensemble | Oracle | vs 4B |
|---|---|---|
| 4 baseline | 144 | — |
| 2B + 2CR unfiltered | 146 | +2 |
| 2B + 2CR filtered | 149 | +5 |
| 4B + 2CR unfiltered | 149 | +5 |
| 4B + 2CR filtered | 150 | +6 |

## Case Study: "Harms" Are Seed Variance

All 18 "genuine harms" (4B solves, CR never) show False on BOTH CR passes. The model fails pass 1 (no concepts) AND pass 2 (with concepts). Concepts don't cause the harm — these problems are solved sporadically across baseline seeds.

## Unique Concept Pass 2 Solves

Isolating problems solved ONLY by concept-injected pass 2, never by any baseline or any concept-free pass 1:

- Unfiltered CR: 1 problem (cmath_4005 — complex number optimization, solved on both seeds' pass 2)
- Filtered CR: 1 problem (cmath_10620 — different problem unlocked by different concept set)

## Decomposing the +5 Oracle Uplift

The headline result: 2B + 2CR_filtered = 149 vs 4B = 144, a **+5 oracle uplift** at the same compute budget.

But where does the +5 come from?

- **1 of 5** is directly attributable to concept content — solved ONLY on concept-injected pass 2, never by any baseline or concept-free pass 1 across all runs
- **4 of 5** come from the different prompt trajectory — concept-retry runs use a different pipeline path (memory builder/retriever loaded, different wiring), producing different sampling outcomes even on pass 1 where no concepts are injected

Evidence: pass 1 prompt fingerprints are identical between baseline and CR on the same seed, but results differ by 22-24 problems per seed. The LLM sampling (via OpenRouter) is non-deterministic even with the same seed, and the different pipeline path may affect request batching/ordering.

This means the +5 is real and reproducible for ensembling purposes — mixing CR runs into a baseline ensemble consistently adds diversity. But only ~20% of that diversity is from concept content. The rest is equivalent to running more baseline seeds with different random trajectories.

## Key Findings

1. **+5 oracle uplift** from mixing filtered CR into baseline ensemble (149 vs 144 at K=4)
2. Of that +5, **~1 is concept signal** (pass 2 unique solve), **~4 is trajectory diversity** (different sampling outcomes)
3. Filtering bloated concepts hurts individual scores (107-108 vs 113-114) but improves oracle diversity (+5 vs +2)
4. The "harms" are seed variance, not concept damage — all 18 genuine harms show False on both CR passes
5. Concept extraction produces over-generic concepts on broad datasets (99 cues for "algorithm")
6. The broader dataset confirms the NT+CP-only findings: concepts add marginal content signal

## Implications

- **Router/gating is wrong framing** — pass 1 is concept-free, concepts can't cause harm
- **Verifier/ensembler is right framing** — run baseline + CR, pick best answer. Oracle ceiling is 149-150/200
- **Concept content matters less than diversity** — the +5 mostly comes from different trajectories, not concept knowledge
- **Extraction quality is the bottleneck** — generic concepts dominate on broad datasets. SkillRL-style lean format (title, principle, when_to_apply) may produce more targeted hints
- **Next step**: either improve concept extraction quality to increase the content signal fraction, or build a verifier to harvest the diversity signal regardless of source
