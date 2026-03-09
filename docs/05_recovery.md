# Recovery: Concept Core + LiveCodeBench Pipeline (2026-02-19)

## Background

`mem2` is a modular, domain-agnostic migration of `arc_memo`. The goal is to lift the memory-augmented solving approach that was validated on ARC-AGI and apply it to additional benchmarks without rewriting per-domain logic. The architecture is a pluggable pipeline of `BenchmarkAdapter → TaskAdapter → InferenceEngine → Evaluator → FeedbackEngine → MemoryBuilder → MemoryRetriever`, all wired by a registry-based `Orchestrator`.

Prior to the server shutdown, the codebase had been extended with:
1. A rich **concept memory system** (ported from `arc_memo`'s `concept_mem/`) usable across domains
2. A **Math-PS pipeline** (competition_math Number Theory + Counting & Probability subset)
3. A **LiveCodeBench pipeline** (competitive code generation with stdin/stdout execution)
4. Full-scale experiment results across all three domains

All of this was lost. This entry documents the recovery pass.

## What was lost (pre-shutdown state)

From the mentor progress report sent before the shutdown:

> Small-scale pilot: 30 hard Math-PS problems (Level 4–5). Baseline: 20/30 (67%). After extracting 36 reusable concepts from solved problems (two-stage: solution → pseudocode → typed annotations) and running retrieval on the 10 unsolved problems: 25/30 (83%). Retry with concepts added 3 solves; baseline retry added 0.
>
> Full-scale results (LLM-based concept selection, Qwen3-30B): 86.5% on Math (vs 90.6% baseline), 76% on LCB (vs 77% baseline). Small negative due to the baseline being too strong — the full test set was much easier than the hard-problem pilot. Selector failure mode identified: on LCB 85% of problems received one of two nearly identical concept sets; on Math 13.5% received an identical generic fallback prompt that actively hurt performance. The selector (same model as the solver) failed to differentiate per-problem.
>
> Next step: pair a stronger selector model with a weaker solver to better surface the retrieval signal. Overall pipeline architecture is finalized and domain-agnostic, validated across ARC, Math, and LCB.

## What was recovered in this session

### Phase 1 — Concept Core (`src/mem2/concepts/`)

Ported the concept data model from `arc_memo/concept_mem/memory/v4/` into `mem2` as a standalone package.

**`concepts/data.py`** — `Concept` and `ParameterSpec` dataclasses.

A `Concept` stores structured cross-problem knowledge:
- `name`, `kind` (string validated by builders; e.g. `"structure"`, `"routine"`, `"theorem"`, `"algorithm"`)
- `routine_subtype`, `output_typing`, `parameters: list[ParameterSpec]`
- `description`, `cues` (when to apply), `implementation` (how to apply), `used_in` (problem IDs)

Key methods:
- `update(problem_id, annotation)` — merges a new annotation into the concept; never duplicates `used_in`, `cues`, or `implementation` entries
- `_merge_lines(curr, new_lines)` — deduplication-preserving list merge that tolerates single-key dict items (arc_memo YAML artifact)
- `to_string(**skip_flags)` — renders to indented YAML-ish markdown with per-field skip controls for prompt budget management

**`concepts/memory.py`** — `ConceptMemory`, the central concept store.

- `write_concept(problem_id, annotation)` — upserts a concept by name; creates or merges
- `write_solution(problem_id, code, summary, pseudocode)` — records a solved solution
- `initialize_from_annotations(annotations)` — batch-loads a dict of `{problem_id: [concept_annotation, ...]}` (matches arc_memo's offline annotation format)
- `to_string(concept_names, usage_threshold, show_other_concepts, skip_*)` — rich filtered rendering: shows selected concepts in full detail, optionally appends a compact list of remaining concept names; supports `usage_threshold` to hide low-frequency concepts
- `save_to_file(path)` / `load_from_file(path)` — JSON persistence
- `to_payload()` / `from_payload(payload)` — serialization into/from `MemoryState.payload` for pipeline integration

**`concepts/domain.py`** — `DomainProfile` dataclass.

Controls how `ConceptMemory.to_string()` renders sections per domain:

| Profile | `valid_kinds` | `section_order` |
|---|---|---|
| `arc_profile()` | structure, routine | structure → types → routine |
| `math_profile()` | theorem, technique, definition | theorem → technique → definition |
| `code_profile()` | algorithm, pattern, data_structure | algorithm → pattern → data_structure |

**`concepts/prompts/`** — Ported prompt templates:
- `arc_select.py` — `SELECT_PROMPT_TEMPLATE`: instructs the LLM to select relevant concepts from the full memory for a given problem, outputting a YAML list
- `arc_hints.py` — `HINT_TEMPLATE_OP3`: wraps rendered concepts into the hint block injected into the solver prompt

### Phase 2 — Concept Builder + Retriever

**`branches/memory_builder/concept_ps.py`** — `ConceptPsMemoryBuilder`

Implements the `MemoryBuilder` protocol. Loads a seed `ConceptMemory` from either:
- A pre-serialized JSON file (`seed_memory_file`)
- A raw annotations file (`seed_annotations_file`) in arc_memo format

Serializes it into `MemoryState.payload` on `initialize()`. On `update()`, records correct solutions into `payload["solutions"]`. Concept extraction is intentionally offline (matching arc_memo's actual workflow — concepts are distilled in batch, not online per-solve).

**`branches/memory_retriever/concept_selector.py`** — `ConceptSelectorRetriever`

LLM-based concept selection with graceful fallback:

1. Reconstruct `ConceptMemory` from `MemoryState.payload`
2. Render full concept list via `to_string(usage_threshold=0)`
3. Build selection prompt from `SELECT_PROMPT_TEMPLATE` with the current problem
4. LLM call → parse YAML list of concept names
5. Re-render selected concepts in full detail with `show_other_concepts=True`
6. Format through `HINT_TEMPLATE_OP3` → `RetrievalBundle.hint_text`

Fallback at every failure point (empty memory, no model configured, LLM error, YAML parse error) returns all concepts rather than nothing. Fallback reason is recorded in `metadata["selector_mode"]`.

Identified failure mode from the pre-shutdown full-scale run: when the selector model is the same as the solver (Qwen3-30B), it under-differentiates — 85% of LCB problems and 13.5% of Math problems received effectively identical concept sets, eliminating the per-problem retrieval signal.

### Phase 3 — LiveCodeBench Pipeline

**`branches/benchmark/livecodebench.py`** — `LiveCodeBenchAdapter`

Loads from a local HF dataset copy (`datasets.load_from_disk`). Handles dataset-with-splits and split-less formats. Filters by `difficulty`. Robustly parses test cases from multiple LCB field formats:
- `{"input": ..., "expected_output": ...}` dicts
- `{"stdin": ..., "stdout": ...}` dicts
- JSON-encoded strings
- `(input, output)` tuples
- `None` / empty → `[]`

**`branches/task_adapter/livecodebench.py`** — `LiveCodeBenchTaskAdapter`

Formats problem statements for the solver prompt. Task description instructs the model to write Python reading from stdin and writing to stdout.

**`branches/inference_engine/lcb_solve.py`** — `LcbSolveInferenceEngine`

Builds structured prompts:
- Initial: problem statement + public test cases as "Example Test Cases" + optional concept hints block
- Retry: "Previous Response" block containing prior attempt + feedback, then re-states the problem

**`branches/evaluator/lcb_exec.py`** — `LcbExecutionEvaluator`

Executes extracted Python code in an isolated subprocess per test case using `multiprocessing.Process`:
- `extract_python_block()` → code + parsing error
- `execute_with_stdin(code, stdin_data, timeout_s)` → spawns worker, pipes stdin via `io.StringIO`, captures stdout; kills process on timeout
- Runs all public + private test cases; records `pair_idx`, `correct`, `output`, `expected`, `error` per case
- `is_correct = all test cases pass`
- `aggregate()` reports `total_puzzles`, `strict_solved_puzzles`, `solve_rate`, `test_pass_rate`

**`branches/feedback_engine/lcb_gt.py`** — `LcbGroundTruthFeedbackEngine`

Per-test-case feedback:
- Parsing error → surfaces the error message directly
- All pass → `"All test cases passed"`
- Some fail → `"Failed Test Cases"` section with `output` vs `expected` per failing case

**`scripts/download_lcb.py`** — Dataset download utility supporting `--dataset` and `--version` (HF config name) args.

## Files created

| File | Description |
|---|---|
| `src/mem2/concepts/__init__.py` | Package exports |
| `src/mem2/concepts/data.py` | `Concept`, `ParameterSpec` |
| `src/mem2/concepts/memory.py` | `ConceptMemory`, `ProblemSolution` |
| `src/mem2/concepts/domain.py` | `DomainProfile` factory methods |
| `src/mem2/concepts/prompts/__init__.py` | Template exports |
| `src/mem2/concepts/prompts/arc_select.py` | `SELECT_PROMPT_TEMPLATE` |
| `src/mem2/concepts/prompts/arc_hints.py` | `HINT_TEMPLATE_OP3` |
| `src/mem2/branches/memory_builder/concept_ps.py` | `ConceptPsMemoryBuilder` |
| `src/mem2/branches/memory_retriever/concept_selector.py` | `ConceptSelectorRetriever` |
| `src/mem2/branches/benchmark/livecodebench.py` | `LiveCodeBenchAdapter` |
| `src/mem2/branches/task_adapter/livecodebench.py` | `LiveCodeBenchTaskAdapter` |
| `src/mem2/branches/inference_engine/lcb_solve.py` | `LcbSolveInferenceEngine` |
| `src/mem2/branches/evaluator/lcb_exec.py` | `LcbExecutionEvaluator` |
| `src/mem2/branches/feedback_engine/lcb_gt.py` | `LcbGroundTruthFeedbackEngine` |
| `scripts/download_lcb.py` | LCB dataset download script |
| `configs/memory_builder/concept_ps.yaml` | Builder config |
| `configs/memory_retriever/concept_selector.yaml` | Retriever config |
| `configs/benchmark/livecodebench.yaml` | Benchmark config |
| `configs/task_adapter/livecodebench.yaml` | Task adapter config |
| `configs/inference_engine/lcb_solve.yaml` | Inference engine config |
| `configs/evaluator/lcb_exec.yaml` | Evaluator config |
| `configs/feedback_engine/lcb_gt.yaml` | Feedback engine config |
| `configs/experiments/smoke_arc_concept.yaml` | Smoke test: ARC + concept memory |
| `configs/experiments/smoke_lcb.yaml` | Smoke test: LCB pipeline |

## Files modified

| File | Change |
|---|---|
| `src/mem2/registry/memory_builder.py` | Added `"concept_ps"` entry |
| `src/mem2/registry/memory_retriever.py` | Added `"concept_selector"` entry |
| `src/mem2/registry/benchmark.py` | Added `"livecodebench"` entry |
| `src/mem2/registry/task_adapter.py` | Added `"livecodebench"` entry |
| `src/mem2/registry/inference_engine.py` | Added `"lcb_solve"` entry |
| `src/mem2/registry/evaluator.py` | Added `"lcb_exec"` entry |
| `src/mem2/registry/feedback_engine.py` | Added `"lcb_gt"` entry |
| `src/mem2/prompting/render.py` | Added `HINT_TEMPLATE_OP3` to `HINT_TEMPLATES` dict |

## Tests added

| File | Count | Coverage |
|---|---|---|
| `tests/unit/test_concept_data.py` | 31 | `Concept`, `ParameterSpec`, `ConceptMemory`, `DomainProfile` |
| `tests/unit/test_concept_ps.py` | 10 | `ConceptPsMemoryBuilder`, `ConceptSelectorRetriever` |
| `tests/unit/test_lcb.py` | 22 | Evaluator, feedback engine, inference engine prompts, task adapter, benchmark parser |

**Result:** 63 new tests pass. 0 regressions in existing tests. 3 pre-existing failures (`test_math_ps.py`) remain — they require the `datasets` library which is not installed in this environment and are unrelated to these changes.

## What is not yet recovered

The following were lost and are not recovered in this session:

- **Math-PS pipeline** (`branches/benchmark/competition_math_ps.py`, `branches/evaluator/math_ps_exec.py`, `branches/feedback_engine/math_ps_gt.py`, `branches/inference_engine/math_ps_solve.py`) — partially reconstructed skeleton exists in `test_math_ps.py` but the source modules need to be rebuilt
- **Experiment results and run artifacts** — the full-scale run outputs (Math 86.5%, LCB 76%) are not reproducible without re-running
- **Offline concept extraction pipeline** — the two-stage `solution → pseudocode → typed concept annotations` batch workflow and its configs
- **Seed concept memory files** — the 36 extracted Math-PS concepts and any LCB concept files

## Next steps

1. Rebuild Math-PS pipeline source modules
2. Re-run full-scale experiments with stronger selector model (separate from the solver) to address the under-differentiation failure mode identified in the pre-shutdown results
3. Add offline concept extraction pipeline configs and scripts
