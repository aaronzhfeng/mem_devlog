# PS Parity Gap Analysis: Math & Code Benchmarks (2026-02-19)

## Summary

The current math/code pipelines do not use PS-format memory. They use a degraded stub (`arcmemo_ps` + `lesson_topk`) that produces hardcoded hint strings and selects by recency, not by relevance. This entry documents exactly what PS format is, what the current pipelines actually do, and the concrete gaps that must be closed.

## What PS format is

PS (Problem Solving) format is the concept memory system from the ArcMemo paper. It stores **typed, structured concepts** extracted from solved problems and uses **LLM-based per-problem selection** to retrieve relevant concepts at inference time.

### PS concept schema

Each concept is a structured record (defined in `src/mem2/concepts/data.py`):

```
Concept:
  name: str                    # e.g. "extract objects", "modular inverse"
  kind: str                    # category tag (ARC uses "structure"/"routine")
  routine_subtype: str | None  # optional sub-category
  output_typing: str | None    # what the concept produces
  parameters: list[ParameterSpec]  # typed parameters describing variation
  description: str | None      # what this concept does
  cues: list[str]              # relevance cues — when to apply this concept
  implementation: list[str]    # notes on how it was implemented in past solutions
  used_in: list[str]           # problem IDs where this concept appeared
```

### PS memory container

`ConceptMemory` (defined in `src/mem2/concepts/memory.py`) holds:
- `concepts: dict[str, Concept]` — the concept bank, keyed by name
- `solutions: dict[str, ProblemSolution]` — solved problem solutions (code, summary, pseudocode)
- `custom_types: dict[str, str]` — domain-specific type definitions
- `categories: dict[str, list[str]]` — concepts grouped by kind

Concepts are rendered to text via `ConceptMemory.to_string()`, which produces sectioned output grouped by kind with full detail (cues, parameters, implementation notes).

### PS retrieval pipeline

The `concept_selector` retriever (`src/mem2/branches/memory_retriever/concept_selector.py`) performs per-problem LLM-based selection:

1. Reconstruct `ConceptMemory` from `MemoryState.payload`
2. Render all concepts to text via `to_string(usage_threshold=0)`
3. Build selection prompt using `SELECT_PROMPT_TEMPLATE` (concept list + problem)
4. LLM call → model selects relevant concept **names** as a YAML list
5. Re-render only selected concepts in full detail, with `show_other_concepts=True`
6. Format through `HINT_TEMPLATE_OP3` → inject into solver prompt as `### Concepts from Previously Solved Puzzles`

Fallback at every failure point (empty memory, no model, LLM error, parse error) returns all concepts rather than nothing.

### PS memory builder

The `concept_ps` builder (`src/mem2/branches/memory_builder/concept_ps.py`):

- `initialize()`: Loads pre-built `ConceptMemory` from a seed file (JSON)
- `update()`: Records correct solutions into `payload["solutions"]` — concepts themselves are static (extracted offline)
- Concept extraction is an **offline batch process**, not online per-solve

### Reference implementation (ARC)

For ARC-AGI, the PS pipeline uses:
- **Seed data**: `data/arc_agi/concept_memory/compressed_v1.json` — 270 typed concepts extracted from 164 BARC seed solutions
- **Builder**: `concept_ps` with `seed_memory_file` pointing to compressed_v1.json
- **Retriever**: `concept_selector` with LLM-based selection
- **Extraction method**: Two-stage offline pipeline (solution → pseudocode → typed concept annotations)

## What the current math/code pipelines actually do

### Builder: `arcmemo_ps`

`src/mem2/branches/memory_builder/arcmemo_ps.py`, line 183:

```python
"hint": "preserve successful transformations" if is_correct else "inspect failure mode"
```

The `update()` method appends one entry per attempt with:
- `problem_uid`, `pass_idx`, `is_correct`, `feedback` (real content)
- `hint`: one of exactly two hardcoded strings (not PS concepts)

There is no concept extraction. No situation analysis. No structured knowledge.

### Retriever: `lesson_topk`

`src/mem2/branches/memory_retriever/lesson_topk.py`:

```python
items = source_entries[-self.top_k :]
```

Selects the last `top_k=2` entries by recency. No LLM involvement. No per-problem relevance matching. When build and eval splits are disjoint (always), every eval problem receives the same two entries.

### Actual prompt injected

Every eval problem, regardless of content, receives:

```
### Hints
Here are some lessons from previously solved math problems that may be relevant:
preserve successful transformations
inspect failure mode
```

### Measured impact

| Benchmark | Baseline (no memory) | With arcmemo_ps memory | Delta |
|-----------|---------------------|----------------------|-------|
| Math (Qwen2.5-7B, 100 eval) | 63/100 (63%) | 57/100 (57%) | **-6** |
| LCB (Qwen3-Coder-30B-A3B, 100 eval) | 25/100 (25%) | 24/100 (24%) | **-1** |

Memory injection **hurts** performance because it injects irrelevant noise into every prompt.

## The gaps

### Gap 1: No concept extraction pipeline

The critical missing piece. For ARC, concepts were extracted offline from BARC seed solutions via a two-stage LLM pipeline:
1. Solution code → pseudocode + summary
2. Pseudocode → typed concept annotations (name, kind, parameters, cues, implementation)

This pipeline does not exist for math or code. We have 123 solved math problems and 63 solved code problems from the build phase, with full solution code and feedback — but no mechanism to extract PS-format concepts from them.

**What needs to be built**: An offline concept extraction script that:
- Reads build run artifacts (`attempts.jsonl`, `eval_records.jsonl`)
- Filters to correct solutions
- Calls an LLM to extract typed concepts per solution (name, kind, parameters, cues, implementation)
- Merges across problems (same concept appearing in multiple solutions gets `used_in` updated, cues/implementation merged)
- Outputs a `ConceptMemory`-compatible JSON file

**Open question**: What `kind` categories to use for math and code. `domain.py` pre-defines `{theorem, technique, definition}` for math and `{algorithm, pattern, data_structure}` for code, but these may not be the right categories. The extraction LLM should discover kinds organically from the solutions rather than being constrained to predefined categories. The `Concept` dataclass accepts any string for `kind`; the constraint is only in `DomainProfile.valid_kinds`, which filters during rendering. We can either extend the profiles or bypass them.

### Gap 2: Wrong builder

Current configs use `arcmemo_ps` (flat entries with hardcoded hints). Need to switch to `concept_ps` (loads `ConceptMemory` from extracted concept file).

Config change:
```yaml
pipeline:
  memory_builder: concept_ps    # was: arcmemo_ps

components:
  memory_builder:
    seed_memory_file: <path to extracted concept memory JSON>
```

### Gap 3: Wrong retriever

Current configs use `lesson_topk` (recency-based, no LLM). Need to switch to `concept_selector` (LLM-based per-problem selection).

Config change:
```yaml
pipeline:
  memory_retriever: concept_selector    # was: lesson_topk

components:
  memory_retriever:
    top_k: 10
    use_llm_selector: true
    selector_model: <model for selection, ideally different from solver>
    selector_gen_cfg:
      n: 1
      temperature: 0.0
      max_tokens: 1024
```

### Gap 4: Prompt templates are ARC-specific

`SELECT_PROMPT_TEMPLATE` (in `src/mem2/concepts/prompts/arc_select.py`) references "ARC puzzles", "input grids to output grids", "2D numpy integer arrays with integers representing colors". This prompt won't work for math or code problems.

Need domain-appropriate selection prompt templates:
- **Math**: references math problem statements, solution patterns, mathematical techniques
- **Code**: references competitive programming problems, algorithmic approaches, data structures

Similarly, `HINT_TEMPLATE_OP3` (in `src/mem2/concepts/prompts/arc_hints.py`) references "structures and routines we observed in previously solved puzzles" and "grid manipulation routines". Need math/code equivalents.

### Gap 5: Concept extraction prompt templates

The two-stage extraction pipeline (solution → pseudocode → annotations) needs prompt templates for math and code domains. These don't exist.

For ARC, the annotations were structured as:
```yaml
concepts:
  - concept: extract objects
    kind: routine
    routine_subtype: grid manipulation
    parameters:
      - name: connectivity
        typing: str
        description: "4-way or 8-way"
    cues:
      - "multiple distinct colored regions"
    implementation:
      - "flood-fill from each non-background cell"
solution:
  summary: "recolor objects matching guide shape"
  pseudocode: "objects = extract_objects(...)\n..."
```

Need equivalent annotation schemas for math (e.g., what does a "technique" concept look like?) and code (e.g., what does an "algorithm" concept look like?). The extraction LLM should be guided by examples but allowed to discover kinds organically.

### Gap 6: Selector model separation

From the pre-shutdown results documented in devlog entry 11:

> Identified failure mode: when the selector model is the same as the solver (Qwen3-30B), it under-differentiates — 85% of LCB problems received one of two nearly identical concept sets.

The selector model should be different from (ideally stronger than) the solver model. This is a config concern, not a code gap, but it's critical for PS to actually work.

## Existing infrastructure that's ready

| Component | Status | Location |
|-----------|--------|----------|
| `Concept` dataclass | Ready | `src/mem2/concepts/data.py` |
| `ConceptMemory` container | Ready | `src/mem2/concepts/memory.py` |
| `ConceptPsMemoryBuilder` | Ready | `src/mem2/branches/memory_builder/concept_ps.py` |
| `ConceptSelectorRetriever` | Ready | `src/mem2/branches/memory_retriever/concept_selector.py` |
| `DomainProfile` (rendering) | Exists but may need revision | `src/mem2/concepts/domain.py` |
| ARC concept seed data | Ready | `data/arc_agi/concept_memory/compressed_v1.json` |
| Build run artifacts (Math) | Ready | `outputs/_runs/build_math/151900440f88/` (123/200 solved) |
| Build run artifacts (LCB) | Ready | `outputs/_runs/build_lcb/5b254edab37a/` (63/200 solved) |
| Math/LCB inference engines | Ready | `src/mem2/branches/inference_engine/{math_ps_solve,lcb_solve}.py` |
| Math/LCB evaluators | Ready | `src/mem2/branches/evaluator/{math_ps_exec,lcb_exec}.py` |
| Math/LCB feedback engines | Ready | `src/mem2/branches/feedback_engine/{math_ps_gt,lcb_gt}.py` |

## What needs to be built

| Priority | Component | Description |
|----------|-----------|-------------|
| **P0** | Concept extraction script | Offline: build artifacts → LLM extraction → ConceptMemory JSON |
| **P0** | Extraction prompt templates | Math/code domain annotation schemas + few-shot examples |
| **P1** | Domain selection prompts | Math/code versions of `SELECT_PROMPT_TEMPLATE` |
| **P1** | Domain hint templates | Math/code versions of `HINT_TEMPLATE_OP3` |
| **P2** | DomainProfile revision | Let kinds emerge from extraction rather than hardcoding |
| **P2** | Eval configs | Wire `concept_ps` + `concept_selector` + extracted concepts |

## Build run data available for extraction

### Math build (`outputs/_runs/build_math/151900440f88/`)

- 200 problems, 304 attempts across 2 passes
- **123 solved** (61.5%), 77 unsolved
- Model: Qwen2.5-7B-Instruct
- Available: `attempts.jsonl` (full solution code), `eval_records.jsonl`, `feedback_records.jsonl`

### LCB build (`outputs/_runs/build_lcb/5b254edab37a/`)

- 200 problems, 345 attempts across 2 passes
- **63 solved** (31.5%), 137 unsolved
- Model: Qwen3-Coder-30B-A3B-Instruct
- Available: `attempts.jsonl` (full solution code), `eval_records.jsonl`, `feedback_records.jsonl`

## Baseline results for comparison

| Benchmark | Model | Eval Split | Baseline | Target |
|-----------|-------|-----------|----------|--------|
| Math | Qwen2.5-7B | 100 problems | 63% | > 63% with PS concepts |
| LCB | Qwen3-Coder-30B-A3B | 100 problems | 25% | > 25% with PS concepts |
