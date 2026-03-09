# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Layout

This repo contains two projects:

- **`mem2/`** — Active codebase. A modular, domain-agnostic framework for memory-augmented LLM problem-solving. Clean-room re-implementation of `arc_memo` supporting multiple benchmarks.
- **`arc_memo/`** — Original ArcMemo framework (reference only, not actively developed).
- **`mem_devlog/`** — Development logs. `docs/09_current_state_2026_02_20.md` is the best onboarding document. `docs/00_schema_alignment.tsv` tracks parity between mem2 and arcmemo — **read it before any pipeline change, update it after**.

## Common Commands

All commands run from `/root/arc/mem2/`.

```bash
# Install
pip install -e .

# Run all unit tests (130 tests)
python -m pytest tests/unit/

# Run a single test file
python -m pytest tests/unit/test_scoring.py

# Run a single test
python -m pytest tests/unit/test_scoring.py::test_name -v

# Smoke test (integration, requires API key)
python -m pytest tests/smoke/test_smoke_arc.py

# Run an experiment
python -m mem2.cli.run --config configs/experiments/smoke_arc.yaml

# Offline parity validation
python scripts/parity/run_arc_default_parity_lock.py
```

API keys are loaded from environment. Use `source .env` (see `.env.example` for `OPENROUTER_API_KEY`, `OPENAI_API_KEY`, `XAI_API_KEY`).

## Architecture

### Plugin-based Pipeline

All pipeline components are **Protocols** defined in `src/mem2/core/contracts.py`:

```
BenchmarkAdapter → TaskAdapter → InferenceEngine → Evaluator → FeedbackEngine
                                                        ↕
                                               MemoryBuilder + MemoryRetriever
```

Additional protocols: `TrajectoryPolicy`, `ProviderClient`, `ArtifactSink`.

Components are registered by name in `src/mem2/registry/` and wired at runtime by `src/mem2/orchestrator/wiring.py`. Memory builder/retriever pairs are validated for schema compatibility at wiring time (builders declare `SCHEMA_NAME`, retrievers declare `COMPATIBLE_SCHEMAS`). The main execution loop is `PipelineRunner` in `src/mem2/orchestrator/runner.py`.

### Branch Implementations

Each protocol has concrete implementations in `src/mem2/branches/`:

| Branch | Implementations | Purpose |
|--------|----------------|---------|
| `benchmark/` | `arc_agi`, `competition_math_ps`, `livecodebench` | Data loaders |
| `task_adapter/` | `arc_grid` | Problem format adapters |
| `memory_builder/` | `none`, `arcmemo_oe` (OE), `arcmemo_ps` (PS) | Memory construction |
| `memory_retriever/` | `none`, `oe_topk`, `oe_selector`, `ps_selector` | Memory retrieval |
| `inference_engine/` | `python_transform_retry`, `math_ps_solve`, `lcb_solve` | LLM inference |
| `evaluator/` | `arc_exec`, `math_ps_exec`, `lcb_exec` | Solution evaluation |
| `feedback_engine/` | `gt_check` | Ground-truth feedback |
| `trajectory_policy/` | `single_path` | Retry strategy |
| `artifact_sink/` | `json_local` | Output serialization |

### Concept Memory System

Offline two-stage extraction pipeline (`scripts/extract_concepts.py`, core logic in `src/mem2/concepts/extraction.py`):
1. Solution code → pseudocode + summary
2. Pseudocode → typed concept annotations (YAML)

Data layer in `src/mem2/concepts/`: `data.py` (Concept dataclass), `memory.py` (ConceptMemory), `domain.py` (DomainProfile factory), `extraction.py` (batch extraction).

Note: `ConceptMemory.write_concept()` has a hardcoded ARC kind filter (`{"structure", "routine"}`). The extraction pipeline bypasses this by inserting directly into `mem.concepts` and `mem.categories`.

The `ps_selector` retriever supports composable configuration: `render_mode` (full/cues_only/name_only), `max_frequency` + `concept_frequency_file` (frequency-based filtering), `max_concepts_per_problem` (cap), and `routing_strategy` (per-problem hint gating). See `configs/components.md` for details.

### Configuration

YAML configs with hierarchical composition. Base config: `configs/base.yaml`. Experiment configs: `configs/experiments/*.yaml`. Key config fields: `pipeline.*` (component names), `run.*` (execution settings), `components.*` (component-specific params).

### Three Supported Benchmarks

1. **ARC-AGI** — Grid transformation tasks, Python code execution. Stable, parity-validated.
2. **Math-PS** — Competition math (Number Theory + Counting & Probability), integer answers. `solve()` function execution.
3. **LiveCodeBench** — Code generation, subprocess execution with stdin/stdout test cases.

### Data Entities

Core data classes in `src/mem2/core/entities.py`: `RunContext`, `ProblemSpec`, `MemoryState`, `AttemptRecord`, `EvalRecord`, `FeedbackRecord`, `RetrievalBundle`, `TrajectoryPlan`, `TaskSpec`.

## Output Structure

Experiment outputs go to `mem2/outputs/_runs/{run_name}/{run_id}/` containing iteration data, prompts, model outputs, token counts, solution trees, and memory state.

## Python Version

Requires Python >=3.10.
