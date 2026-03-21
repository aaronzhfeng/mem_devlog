# Devlog 34: Headroom Search — Model & Benchmark Sweep (2026-03-11 → 2026-03-17)

## Overview

Follow-up to devlogs 32-33. The v3a scale eval showed concepts help on LCB (+5 at 80% baseline) but are neutral on Math L5 (0 at 98.5%). This session searched for a model-benchmark pairing where concepts could help on math. Tested 3 strategies, 6 experiments. Found that **concept memory is structurally limited to domains where the failure mode is knowledge gaps** — math fails at every tested baseline.

**Headline result:** On Omni-MATH (olympiad, stratified 225 problems), concepts scored -5.1pp overall. Even at difficulty 1-4 where baseline is ~80% (the LCB sweet spot), concepts were neutral on math. At difficulty 7-8, concepts caused -17pp damage. The technique-level concept design is fundamentally mismatched with math failure modes.

## Experiments Run

### Strategy 1: Weaker Model (Qwen3.5-9B on Math L5)

**Infra:** Deployed Qwen3.5-9B on RunPod A40 via vLLM. Added VLLM provider to model_registry.py, profiles.py, provider.py. Tested at 4K and 16K context.

| Config | Score | Notes |
|---|---|---|
| 9B baseline (4K ctx) | 12/200 (6%) | All attempted |
| 9B + concepts (4K ctx) | 7/200 (3.5%) | 94/200 fit in context |
| 9B baseline (16K ctx) | 12/200 (6%) | Proxy timeouts |

**Conclusion:** 9B too weak. 4K context cripples concept injection (106 overflow). 16K didn't help due to CloudFlare proxy timeouts on RunPod.

### Strategy 2: Harder Benchmarks

**New data loaded:**
- AIME 1983-2025: 961 problems from `TianHongZXY/aime-1983-2025` HuggingFace dataset → `data/aime_1983_2025/problems.jsonl`
- Omni-MATH: 4,428 olympiad problems from `KbsdJames/Omni-MATH` (ICLR 2025) → `data/omni_math/problems.jsonl`

**New evaluator built:** `olympiad_eval` — LLM-based answer equivalence checking via Flash judge. Handles non-integer answers (algebraic, tuple, expression). Registered in evaluator registry.

| Benchmark | Flash Score | Pipeline |
|---|---|---|
| AIME (first 100) | 97/100 (97%) | Existing integer eval |
| Omni-MATH d4-5 (50) | 26/50 (52%) | olympiad_eval |
| Omni-MATH d7-8 (50) | 11/50 (22%) | olympiad_eval |

**Conclusion:** Flash is either too strong (competition math) or too weak (olympiad). No natural sweet spot.

### Strategy 3: Omni-MATH Stratified (the main experiment)

**Design:** 25 problems per difficulty level (1-9), 225 total, seed=42. Uniform sampling avoids cherry-picking a specific difficulty band.

**Concept selection:** Chunked selection (6 chunks × ~220 concepts) against existing 1,105 math concepts. 152/225 (67.6%) got selections, 73 failed (mostly chunk 6 timeouts).

**Results by difficulty level:**

| Diff | Baseline | Concept | Delta |
|---|---|---|---|
| 1 | 80% | 80% | 0 |
| 2 | 76% | 72% | -4 |
| 3 | 84% | 88% | +4 |
| 4 | 79% | 70% | -10 |
| 5 | 54% | 56% | +2 |
| 6 | 40% | 38% | -3 |
| 7 | 46% | 28% | -18 |
| 8 | 33% | 17% | -17 |
| 9 | 18% | 21% | +3 |
| **All** | **57.3%** | **52.3%** | **-5.1** |

Per-problem overlap: 108 both, 17 only baseline, 7 only concept. Net: -10.

## Analysis: Why Math Is Structurally Capped

The failure mode mismatch:
- **Code (LCB):** Model fails because it doesn't know an API pattern or algorithmic trick → concept fills the gap → +5
- **Math (competition):** Model already knows all techniques → concepts redundant → 0
- **Math (olympiad d1-4, ~80%):** Model knows techniques, fails on execution errors → concepts don't help → 0
- **Math (olympiad d7-8):** Model needs creative insight, not technique names → concepts mislead → -17

Subset optimization could recover -5 → ~0 (stop harmful concepts), but cannot achieve positive delta. The concept *type* (technique hints) doesn't match the math *failure mode* (reasoning depth). Would need a different memory architecture: similar-problem retrieval, proof strategy hints, or worked examples.

## Infrastructure Created

- **Files modified:** `model_registry.py` (VLLM provider), `profiles.py` (vllm profile), `provider.py` (registry), `competition_math_ps.py` (require_integer_answer gate in validate), `evaluator.py` (olympiad_eval registry)
- **Files created:** `olympiad_eval.py`, 8 experiment configs (`math_l5_baseline_9b`, `math_l5_concept_v3a_chunked_9b`, `aime_baseline_flash`, `omni_baseline_flash`, `omni_mid_baseline_flash`, `omni_stratified_baseline_flash`, `omni_stratified_concept_flash`)
- **Data:** `data/aime_1983_2025/` (961 problems), `data/omni_math/` (4,428 problems + concept selections)

## Candidate Benchmarks for Next Phase

Ranked by expected value for concept testing:

1. **Scale LCB to full set (300-400 problems)** — validate the +5 signal with statistical power. Zero pipeline work.
2. **GPQA Diamond** (Flash 84%) — graduate-level science. Knowledge-gap failure mode plausible. Needs MCQ evaluator, science concept extraction.
3. **BFCL-V4 Tool Use** (Flash 67%) — API/function calling. Knowledge-gap failure mode likely. Needs function-call evaluator, tool-use concept extraction.
4. **SWE-bench** (Flash 69%) — repo-level context. Major pipeline change.

## Run Outputs

| Run | Dir |
|---|---|
| math_l5_baseline_9b (4K) | `outputs/_runs/math_l5_baseline_9b/` (deleted, recreated for 16K) |
| math_l5_concept_v3a_chunked_9b (4K) | `outputs/_runs/math_l5_concept_v3a_chunked_9b/a9ce2862aea3/` |
| math_l5_baseline_9b (16K) | `outputs/_runs/math_l5_baseline_9b/a5e79894e7f0/` |
| aime_baseline_flash | `outputs/_runs/aime_baseline_flash/1d0c2977b1c9/` |
| omni_baseline_flash (d7-8) | `outputs/_runs/omni_baseline_flash/6f2557336bf8/` |
| omni_mid_baseline_flash (d4-5) | `outputs/_runs/omni_mid_baseline_flash/4dc3a8ea6ae0/` |
| omni_stratified_baseline_flash | `outputs/_runs/omni_stratified_baseline_flash/12fa5a417161/` |
| omni_stratified_concept_flash | `outputs/_runs/omni_stratified_concept_flash/0c01bda13852/` |

## Marp Report

Full slide deck: `mem_devlog/reports/2026_03_16_headroom_search_report.md` (20+ slides)
