# Copilot Context: mem2 Concept Memory Evaluation

*Prepared for research-copilot attach mode handoff.*

## What this project is

mem2 is a modular, domain-agnostic framework for memory-augmented LLM problem-solving. The core idea: extract reusable "concepts" (techniques, patterns, API idioms) from solved problems, then retrieve and inject relevant concepts as hints when solving new problems. The framework supports multiple benchmarks (ARC-AGI, competition math, LiveCodeBench) via a plugin pipeline architecture.

## Current objective

**Validate and extend the concept memory benefit across benchmarks.** The immediate tasks:

1. **Scale up LCB evaluation** — We proved +5pp (80→85%) on 100 LiveCodeBench problems. Run 300-400 problems to confirm the signal is robust and not noise. This is the highest priority.
2. **GPQA Diamond pilot** — Test if concept memory helps on graduate-level science QA (Flash baseline ~84%). Requires: MCQ evaluator adapter, science concept extraction.
3. **BFCL-V4 Tool Use pilot** — Test if concepts help on API/function calling tasks (Flash baseline ~67%). Requires: function-call evaluator, tool-use concept extraction.

## Background

### What works
- **LCB (code):** +5pp at 80% baseline. Concepts fill knowledge gaps (API patterns, algorithmic tricks). This is the one validated positive result.

### What doesn't work (math, thoroughly tested)
- **Math L5 (competition):** 0pp at 98.5% baseline — ceiling, no headroom.
- **Math L5 (Qwen3.5-9B):** -2.5pp at 6% baseline — model too weak.
- **Omni-MATH (olympiad, stratified 225 problems):** -5.1pp at 57% baseline. Even at difficulty 1-4 where baseline is ~80%, concepts are neutral. At d7-8, concepts cause -17pp damage.
- **Conclusion:** Math is structurally capped for technique-level concept memory. The failure mode (reasoning depth) doesn't match what concepts encode (technique names). No subset optimization can fix this.

### Key insight: domain sensitivity
Concepts help when **failure mode = knowledge gap** (code). They don't help when **failure mode = reasoning depth** (math). Same framework, same baseline range, opposite outcomes. This is the central finding.

### Infrastructure already built
- **Pipeline:** Full plugin architecture in `src/mem2/`. Benchmark adapters, inference engines, evaluators, memory builder/retriever, all registry-driven.
- **Concept extraction:** Two-stage pipeline (solution→pseudocode→concepts). 1,105 math concepts, ~239 LCB concepts extracted.
- **Concept selection:** Chunked selection script for large concept libraries. Splits into ~220-concept chunks, runs selection per chunk, merges results.
- **Olympiad evaluator:** `olympiad_eval` — LLM judge (Flash) for open-ended answer equivalence. Handles algebraic, tuple, and expression answers.
- **vLLM integration:** VLLM provider in model_registry for local model deployment.
- **Benchmarks loaded:** Math L5 (200 eval), AIME 1983-2025 (961), Omni-MATH (4,428), LCB v5/v6 (existing).

### Key files
- Pipeline core: `src/mem2/core/contracts.py`, `src/mem2/orchestrator/runner.py`, `src/mem2/orchestrator/wiring.py`
- Concept system: `src/mem2/concepts/` (extraction, memory, domain profiles)
- Branches: `src/mem2/branches/` (all implementations)
- Registry: `src/mem2/registry/` (component lookup)
- Configs: `configs/experiments/` (all experiment YAML files)
- Selection script: `scripts/select_concepts_chunked.py`
- Extraction script: `scripts/extract_concepts.py`

### Run command pattern
```bash
source .env  # loads OPENROUTER_API_KEY
python -m mem2.cli.run --config configs/experiments/<config>.yaml
```

## Relevant prior work

- `mem_devlog/docs/09_current_state_2026_02_20.md` — Best onboarding document for the codebase
- `mem_devlog/docs/32_lcb_v3a_scale_eval_2026_03_10.md` — LCB +5 result details
- `mem_devlog/docs/33_math_v3a_scale_eval_2026_03_10.md` — Math ceiling result
- `mem_devlog/docs/34_headroom_search_2026_03_17.md` — Full headroom search (this session)
- `mem_devlog/reports/2026_03_10_v3a_scale_eval_report.md` — v3a scale eval Marp report
- `mem_devlog/reports/2026_03_16_headroom_search_report.md` — Headroom search Marp report
- `mem_devlog/docs/00_schema_alignment.tsv` — Parity tracker between mem2 and arcmemo

## Constraints

- **Model:** Qwen3.5-Flash via OpenRouter (primary). Local vLLM available but slow.
- **API costs:** OpenRouter pay-per-token. Full LCB run (400 problems × 2 passes) costs ~$5-10.
- **Evaluation:** LLM judge calls double the API cost. Use integer comparison when possible, Flash judge only for open-ended answers.
- **Do not modify:** `arc_memo/` (reference only). `mem_devlog/docs/00_schema_alignment.tsv` — read before pipeline changes, update after.
- **Working directory:** All commands run from `mem2/`.

## Open questions

1. **Does the LCB +5 hold at scale?** 100 problems is small. 300-400 would be convincing. If it doesn't hold, the entire concept memory benefit narrative is in question.
2. **Does concept memory work on science (GPQA)?** The failure mode (knowledge gaps in physics/chemistry/biology) seems concept-addressable. But MCQ format is different from our open-ended pipeline.
3. **Does concept memory work on tool use (BFCL)?** API knowledge gaps are very similar to LCB code patterns. This might be the second positive domain.
4. **Can concepts be extracted from science/tool-use domains?** The extraction pipeline is tuned for code and math. New domains may need prompt adjustments.
