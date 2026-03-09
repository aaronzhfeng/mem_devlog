# Current State (2026-02-20)

This document is written to onboard a new session. Read this first, then the earlier devlog entries
for deeper context. The repo is `/root/arc/mem2`.

---

## What `mem2` is

A modular, domain-agnostic framework for memory-augmented LLM problem-solving. It is a clean-room
re-implementation of `arc_memo` (at `/root/arc/arc_memo/`) designed to apply the same concept-memory
approach to multiple benchmarks beyond ARC-AGI.

Pipeline architecture:
```
BenchmarkAdapter → TaskAdapter → InferenceEngine → Evaluator → FeedbackEngine
                                                        ↕
                                               MemoryBuilder + MemoryRetriever
```
All components are registered by name in `src/mem2/registry/` and wired at run time by
`src/mem2/orchestrator/wiring.py`. Configs live in `configs/experiments/`.

---

## Repo state as of this writing

### Git log (recent)
```
1d0d061  Refactor extraction to two-stage pipeline: solution→pseudocode then pseudocode→concepts with repo injection
74b412c  Add build and memory eval experiment configs for math and LCB
2014764  Add concept extraction pipeline: extraction.py core logic and extract_concepts.py CLI
09204a6  Add data directory
c29345a  Add baseline and recovery experiment configs
c493d32  Update model registry and env example
b9adf8a  Update benchmark adapters: arc_agi, competition_math_ps, livecodebench
8a09c41  Add 63 unit tests for concept core, concept builder/retriever, and LCB pipeline
2772a15  Add configs for concept_ps, concept_selector, LCB pipeline, and smoke experiments
9bf8345  Register concept_ps, concept_selector, and all LCB components in registries
...      (earlier: core framework, providers, ARC pipeline, math/LCB branch implementations)
```

### Uncommitted changes (need to commit)
- `scripts/extract_concepts.py` — updated default model to `qwen/qwen3.5-397b-a17b`, added
  `initial_analysis.json` save after Stage 1, summary stat improvements
- `third_party/llm_wrapper/llmplus/model_registry.py` — added `qwen/qwen3.5-397b-a17b` entry
- `data/competition_math_nt_cp_l5/concept_memory/` — untracked (concept extraction outputs)
- `data/livecodebench_v56/concept_memory/` — untracked (concept extraction outputs)

---

## Three supported benchmarks

### 1. ARC-AGI
- Data: `data/arc_agi/` (training + evaluation JSON, BARC seed programs)
- Concept memory: `data/arc_agi/concept_memory/compressed_v1.json` (~8790 lines, rich ARC concepts)
- Pipeline: `arc_agi` benchmark → `python_transform_retry` inference → `arc_exec` evaluator
- Status: stable, parity-validated against `arc_memo`

### 2. Math-PS (`competition_math` NT + C&P integer-answer subset)
- Data: `/root/workspace/data/hf/qwedsacf__competition_math` (loaded via `datasets.load_from_disk`)
- Subset: Number Theory + Counting & Probability, integer-boxed answers only (~2027 problems)
- Pipeline: `competition_math_ps` benchmark → `math_ps_solve` inference → `math_ps_exec` evaluator
- Evaluator: executes `solve()` function, compares return value to ground-truth integer

### 3. LiveCodeBench (LCB)
- Data: `data/livecodebench_v56/` (local HF dataset copy, release_v5 + v6)
- Pipeline: `livecodebench` benchmark → `lcb_solve` inference → `lcb_exec` evaluator
- Evaluator: subprocess execution with stdin piping, stdout comparison per test case

---

## Experiment results

### Build runs (concept extraction source data)

| Run | Dir | Problems | Solved | Solve rate |
|---|---|---|---|---|
| `build_math` | `outputs/_runs/build_math/151900440f88` | 200 | 123 | 61.5% |
| `build_lcb` | `outputs/_runs/build_lcb/5b254edab37a` | 200 | 63 | 31.5% |

Build runs use 2 passes (initial + 1 retry) with no memory, Qwen3-235B. Purpose: generate solved
problems to extract concepts from.

### Baseline evals (no memory)

| Run | Problems | Solved | Solve rate | Notes |
|---|---|---|---|---|
| `baseline_math_eval` | 1 | 1 | 100% | smoke only |
| `baseline_lcb_eval` | 100 | 25 | **25%** | full eval, test_pass_rate=20.2% |

The LCB baseline (25%) is notably lower than expected. The build run achieved 31.5% on 200 problems
with the same model — the difference may be problem set composition or the eval config.

### Memory evals (with `arcmemo_ps` + `lesson_topk` stub — NOT concept memory)

| Run | Problems | Solved | Solve rate | vs baseline |
|---|---|---|---|---|
| `memory_math_eval` | 100 | 57 | **57%** | (no clean math baseline to compare) |
| `memory_lcb_eval` | 100 | 24 | **24%** | −1 vs baseline 25% |

**Important:** These memory runs used the OLD stub memory system (`arcmemo_ps` builder seeding
from `build_math/memory/final.json` lessons, `lesson_topk` retriever), NOT the new `concept_ps` +
`concept_selector` system. The lesson_topk retriever injects hardcoded hints like "preserve
successful transformations" into every prompt regardless of relevance — this is the parity gap
documented in `13_ps_parity_gap_analysis.md`. The −1 on LCB is a direct consequence.

---

## Concept extraction pipeline

### What it is
An offline two-stage batch script (`scripts/extract_concepts.py`) that turns build run artifacts
into a `ConceptMemory` JSON file loadable by the `concept_ps` memory builder.

Stage 1 (parallel): solution code → pseudocode + summary (`<pseudocode>` and `<summary>` XML tags)  
Stage 2 (batched, sequential): pseudocode → typed concept annotations (YAML), with the growing
concept repository injected into each prompt so the model can reuse existing concept names

Core logic: `src/mem2/concepts/extraction.py`

### Extraction outputs produced so far

| File | Model | Problems | Concepts | Solutions | Notes |
|---|---|---|---|---|---|
| `data/competition_math_nt_cp_l5/concept_memory/extracted_v1.json` | qwen3-coder-30b | 5 | 13 | 5 | smoketest only |
| `data/competition_math_nt_cp_l5/concept_memory/extracted_v2.json` | **qwen3.5-397b-a17b** | 117 | **117** | 88 | **full run, use this** |
| `data/competition_math_nt_cp_l5/concept_memory/initial_analysis.json` | — | — | — | — | Stage 1 pseudocode/summary per problem |
| `data/livecodebench_v56/concept_memory/extracted_v1.json` | qwen3-coder-30b | 10 | 10 | 10 | smoketest only |

**Math extraction is done.** The full run (`extracted_v2.json`) has 117 concepts across 88 solved
problems. One known issue: kind names have inconsistent capitalisation (e.g. `technique` vs
`Technique`, `counting method` vs `Counting Method`) — worth a normalisation pass before use.

**LCB extraction is not yet done.** Only the 10-problem smoketest exists. Need to run:
```bash
python scripts/extract_concepts.py \
  --run-dir outputs/_runs/build_lcb/5b254edab37a \
  --domain code \
  --model qwen/qwen3.5-397b-a17b \
  --output data/livecodebench_v56/concept_memory/extracted_v2.json
```

---

## The concept memory system (Phase 1–2 from recovery)

### Data layer (`src/mem2/concepts/`)
- `data.py` — `Concept` dataclass (name, kind, description, cues, implementation, used_in, parameters)
- `memory.py` — `ConceptMemory` with `write_concept()`, `to_string()`, `save_to_file()`,
  `load_from_file()`, `to_payload()`/`from_payload()`
- `domain.py` — `DomainProfile` with `arc_profile()`, `math_profile()`, `code_profile()` factory methods
- `prompts/arc_select.py` — `SELECT_PROMPT_TEMPLATE` for LLM-based concept selection
- `prompts/arc_hints.py` — `HINT_TEMPLATE_OP3` for formatting selected concepts as hints
- `extraction.py` — `load_solved_problems()`, `build_pseudocode_prompt()`, `build_concept_prompt()`,
  `assemble_concept_memory()`, `render_concept_repo()`

### Pipeline components
- `branches/memory_builder/concept_ps.py` — `ConceptPsMemoryBuilder` (loads seed JSON, offline workflow)
- `branches/memory_retriever/concept_selector.py` — `ConceptSelectorRetriever` (LLM-based selection
  with graceful fallback chain)

### Key design: bypassing the ARC kind filter
`ConceptMemory.write_concept()` rejects kinds not in `{"structure", "routine"}` (hardcoded for ARC).
The extraction pipeline bypasses this by constructing `Concept` objects directly and inserting into
`mem.concepts` and `mem.categories` — enabling organic kind discovery (e.g. `technique`, `theorem`,
`number theory tool`, etc.).

---

## What needs to happen next

### Immediate (before next eval run)
1. **Normalise kind capitalisation** in `extracted_v2.json` — lowercase all kind names
2. **Run LCB extraction** — produce `data/livecodebench_v56/concept_memory/extracted_v2.json`
3. **Commit** the uncommitted files (`scripts/extract_concepts.py`,
   `third_party/llm_wrapper/llmplus/model_registry.py`, concept memory data files)

### Eval (next experiment)
4. **Wire `concept_ps` + `concept_selector` into math eval** — create a new experiment config that
   uses `concept_ps` builder seeded with `extracted_v2.json` and `concept_selector` retriever, then
   run on the same 100-problem test set as `memory_math_eval`. Compare 57% (stub) vs new result.
5. **Same for LCB** — after step 2 above, run `concept_ps` + `concept_selector` on LCB eval set

### Known failure mode to address
The `concept_selector` uses the same model as the solver (both Qwen3-235B in the current configs).
Pre-shutdown results showed this causes under-differentiation: 85% of LCB problems and 13.5% of Math
problems received effectively identical concept sets. Solution: use a stronger or different model
for the selector (e.g. `qwen/qwen3.5-397b-a17b` or `anthropic/claude-sonnet-4`), while keeping
a weaker model for the solver to create headroom for the memory to show lift.

---

## Key file locations

| Purpose | Path |
|---|---|
| Concept memory data (Math, full) | `data/competition_math_nt_cp_l5/concept_memory/extracted_v2.json` |
| Concept memory data (Math, Stage 1 analysis) | `data/competition_math_nt_cp_l5/concept_memory/initial_analysis.json` |
| Concept memory data (LCB, smoketest only) | `data/livecodebench_v56/concept_memory/extracted_v1.json` |
| ARC concept memory | `data/arc_agi/concept_memory/compressed_v1.json` |
| Build run (Math) | `outputs/_runs/build_math/151900440f88/` |
| Build run (LCB) | `outputs/_runs/build_lcb/5b254edab37a/` |
| Extraction script | `scripts/extract_concepts.py` |
| Core extraction logic | `src/mem2/concepts/extraction.py` |
| Experiment configs | `configs/experiments/` |
| Run outputs | `outputs/_runs/{run_name}/{run_id}/` |

## How to run an experiment

```bash
cd /root/arc/mem2
export OPENROUTER_API_KEY="..."
python -m mem2.cli.run configs/experiments/memory_math_eval.yaml
```

Check `configs/experiments/memory_math_eval.yaml` (and other yamls) for structure. Key fields:
`benchmark`, `task_adapter`, `inference_engine`, `evaluator`, `feedback_engine`,
`memory_builder`, `memory_retriever`, `trajectory_policy`, `provider`.
