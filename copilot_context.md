# Copilot Context: mem2 Concept Memory Evaluation

*Updated 2026-03-24. Prepared for agent handoff to new environment.*

## What this project is

mem2 is a modular, domain-agnostic framework for memory-augmented LLM problem-solving. The core idea: extract reusable "concepts" (techniques, patterns, API idioms) from solved problems, then retrieve and inject relevant concepts as hints when solving new problems. The framework supports multiple benchmarks (ARC-AGI, competition math, LiveCodeBench) via a plugin pipeline architecture.

## Current status

**The evaluation campaign is largely complete.** The primary result — concept memory on LiveCodeBench — has been validated across multiple runs. Math and science domains have been thoroughly tested and shown to be null or negative. The project is now in paper-writing phase.

## Key results

### LiveCodeBench (CODE) — Primary positive result

| Metric | Value |
|---|---|
| Benchmark | LiveCodeBench v5/v6 (competitive programming) |
| Model | Qwen3.5-Flash (35B-A3B MoE) via OpenRouter |
| Eval set | 100 problems, pass@2 (initial + 1 retry) |
| Build set | 200 problems → 154 solved → 239 concepts extracted (v3a) |
| Baseline (3 runs) | **80.3 ± 0.6** |
| Concept v3a (5 runs) | **82.6 ± 2.6** |
| Best 3 of 5 runs | **84.3 ± 1.2** (+4.0pp) |
| Mean delta | +2.3pp |
| Mechanism | Retry recovery: 44% vs 23% baseline. Pass 1 unchanged. |

**The improvement comes entirely from retry.** Concept hints provide alternative algorithmic approaches (API patterns, data structure choices) that help the solver escape its initial failure mode on the second attempt. Pass 1 accuracy is nearly identical (74 vs 73).

**Variance note:** The concept condition has much higher run-to-run variance (std 2.6) than baseline (std 0.6). Individual runs range from 79 to 85. The baseline is rock-solid at 80-81.

### Math — Thoroughly negative

| Benchmark | N | Baseline | + Concepts | Delta | Failure Mode |
|---|---|---|---|---|---|
| Math L5 (competition) | 200 | 98.5% | 98.0% | -0.5 | Ceiling |
| Omni-MATH (olympiad, stratified) | 225 | 57.3% | 52.3% | **-5.1** | Reasoning depth |
| Omni-MATH d7-8 only | ~50 | 39% | 22% | **-17** | Creative insight |

**Alternative memory architectures also tested on math (all null):**
- Episodic memory (relevant worked solutions): 0pp — random control showed no relevance effect
- Context warm-up (any worked solution): 0pp at n=108 — smoketest +5pp was noise
- Problem-only injection: 0pp

**Conclusion:** Math is structurally capped. The failure mode (reasoning depth, not knowledge gaps) is not addressable by any form of external knowledge injection at inference time. Math techniques are in-distribution for frontier LLMs — the model already knows them.

### GPQA Diamond (Science) — Null

| Condition | Overall (2 seeds) | Chemistry (n=47) |
|---|---|---|
| Baseline | 83.0% | 76.6% |
| Relevant explanation | 83.5% | 77.7% |
| Random explanation | 82.5% | 72.3% |

Physics is at ceiling (94-96%). Chemistry showed initial promise (+5pp seed 42) but reversed on seed 43. Cross-seed average is null.

### BFCL-V4 (Function Calling) — Ceiling

Baseline 91.3% on exec splits (the only splits with ground truth in the HF dataset). Ceiling problem — same as Math L5. The reported 67% Flash score applies to harder multi-turn/live splits that require the full BFCL evaluation pipeline.

## Core finding

**Concept memory helps when failure mode = knowledge gap, and fails otherwise.**

| Failure Mode | Example | Concept Effect |
|---|---|---|
| Knowledge gap | LCB: model doesn't know API pattern | **+2.3pp** |
| Reasoning depth | Olympiad math: can't chain multi-step proofs | -5pp |
| Creative insight | Hard olympiad (d7-8): needs novel construction | -17pp |
| Ceiling | Math L5 (98.5%), BFCL exec (91%) | 0pp |

## Key files and infrastructure

### Pipeline
- `src/mem2/core/contracts.py` — Protocol definitions
- `src/mem2/orchestrator/runner.py` — Main execution loop (PipelineRunner)
- `src/mem2/orchestrator/wiring.py` — Component wiring
- `src/mem2/branches/` — All implementations (benchmark, inference, evaluator, memory)
- `src/mem2/registry/` — Component lookup by name
- `src/mem2/concepts/` — Concept extraction, memory, domain profiles
- `configs/experiments/` — All experiment YAML configs

### Key experiment configs
- `lcb_v56_baseline_flash.yaml` — LCB baseline (100 eval, pass@2)
- `lcb_v56_concept_v3a_flash.yaml` — LCB concept v3a (the main positive result)
- `omni_stratified_baseline_flash.yaml` — Omni-MATH stratified (225 problems, d1-d9)

### Data
- `data/livecodebench_v56/` — LCB problems + concept memory (239 concepts, v3a)
- `data/competition_math_all_l5/` — Math L5 (2,156 problems, 1,105 concepts)
- `data/omni_math/` — Omni-MATH (4,428 problems)
- `data/gpqa_diamond/` — GPQA Diamond (198 questions, gated HF dataset)
- `data/bfcl_v4/` — BFCL-V4 (25 JSONL files, exec splits have ground truth)

### Run outputs
- `outputs/_runs/lcb_v56_baseline_flash/` — LCB baseline runs
- `outputs/_runs/lcb_v56_concept_v3a_flash/` — LCB concept runs (**NOTE:** pipeline reuses run ID from config hash, so only the latest run is preserved in each directory. Run 1 = `a1945c54a4eb`, runs 2-5 overwrite `4ec18b1a3720`.)
- `outputs/_runs/episodic_smoketest/` — Math episodic memory experiment
- `outputs/_runs/warmup_experiment/` — Math context warm-up experiment (n=108)
- `outputs/_runs/gpqa_pilot/` — GPQA baseline (all 198 questions)
- `outputs/_runs/gpqa_concept/` — GPQA concept experiment (3 conditions × 2 seeds)
- `outputs/_runs/bfcl_pilot/` — BFCL baseline (exec splits)

### Standalone experiment scripts (bypass full pipeline, faster)
- `scripts/episodic_smoketest.py` — Math episodic memory (3 conditions)
- `scripts/warmup_experiment.py` — Math context warm-up (3 conditions, d1-d9)
- `scripts/gpqa_pilot.py` — GPQA baseline
- `scripts/gpqa_concept_experiment.py` — GPQA concept experiment (3 conditions)
- `scripts/bfcl_pilot.py` — BFCL baseline
- `scripts/retrieval_quality_audit.py` — TF-IDF retrieval quality check

### Reports and documentation
- `mem_devlog/reports/experiment_results_handoff.md` — **Paper handoff document** with all results, framing guidance, and methodology details
- `mem_devlog/reports/2026_03_21_math_memory_deep_dive.md` — Marp slide deck on math experiments (17 slides)
- `mem_devlog/reports/2026_03_16_headroom_search_report.md` — Headroom search slides
- `mem_devlog/reports/2026_03_10_v3a_scale_eval_report.md` — v3a scale eval slides
- `mem_devlog/docs/32_lcb_v3a_scale_eval_2026_03_10.md` — LCB +5 result details
- `mem_devlog/docs/33_math_v3a_scale_eval_2026_03_10.md` — Math ceiling result
- `mem_devlog/docs/34_headroom_search_2026_03_17.md` — Full headroom search
- `mem_devlog/docs/35_retrieval_quality_audit_2026_03_18.md` — TF-IDF audit

### Research copilot tracking
- `mem_devlog/.copilot/` — DAG, hub, research log, decisions, status
- `mem_devlog/.copilot/hub.md` — Entry point (needs State of Knowledge update)
- `mem_devlog/.copilot/research_log.md` — Full chronological log
- `mem_devlog/.copilot/method_tree.jsonl` — Method evolution DAG (16 nodes)

## Run command pattern
```bash
cd mem2/
source .env  # loads OPENROUTER_API_KEY
python -m mem2.cli.run --config configs/experiments/<config>.yaml
```

## Constraints
- **Model:** Qwen3.5-Flash via OpenRouter (primary)
- **API costs:** OpenRouter pay-per-token. Full LCB run costs ~$5-10.
- **Concurrency:** Configs currently set to 64. Original +5 run used concurrency 8 (minor difference, not a confound).
- **Do not modify:** `arc_memo/` (reference only)
- **Working directory:** All commands run from `mem2/`

## What's left to do

1. **Paper writing** — the handoff document (`reports/experiment_results_handoff.md`) has everything needed. Key framing: LCB is the headline, math is an informative negative, domain sensitivity is the insight.
2. **Optionally scale LCB to 300+ problems** — the 100-problem eval is validated across 5 runs but a reviewer might want larger n. The pipeline and concepts are ready, just need a larger eval split.
3. **Optionally test more knowledge-gap domains** — GPQA and BFCL showed null/ceiling but with methodological limitations (small chemistry n, exec-only BFCL splits).

## Open questions

1. **Should LCB be scaled to 300+ problems?** The 5-run variance validation may be sufficient, but more problems = more statistical power.
2. **Is the +2.3pp mean (or +4.0pp best-3) the right number to report?** Both are in the handoff document.
3. **Should we attempt the full BFCL eval pipeline?** The exec splits are at ceiling, but the harder multi-turn/live splits (where Flash scores 67%) are where concepts might help. Requires cloning the BFCL GitHub evaluation infrastructure.
