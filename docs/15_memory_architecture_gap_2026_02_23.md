# Devlog 21 — Memory Architecture Gap: Explicit Coupling & Composable Retrieval

**Date**: 2026-02-23

## Problem

The memory builder/retriever protocols look independent but are tightly coupled
through `MemoryState.payload` (untyped `dict[str, Any]`). Mismatched pairs (e.g.,
`arcmemo_ps` builder + `oe_topk` retriever) silently produce empty or nonsensical
results because the payload schemas are different:

- `arcmemo_oe` payload: `{"entries": [{hint, problem_uid, ...}]}`
- `arcmemo_ps` payload: `{"concepts": {...}, "solutions": {...}, "categories": {...}}`

The documentation warns about this in `components.md`, but nothing enforces it.

## Three Concerns Bundled in ps_selector

The `PsSelectorRetriever` bundles three distinct concerns:

1. **Deserialization** — reconstructing `ConceptMemory` from payload
2. **Selection** — choosing which concepts are relevant (precomputed or LLM)
3. **Rendering** — converting selected concepts to hint text via `to_string()`

This makes it impossible to vary one concern without touching the others. Devlog 20
identified three LCB concept improvements:

- **Option 1**: Better selection (frequency filtering, per-problem cap)
- **Option 2**: Shorter hints (cues-only or name-only rendering)
- **Option 3**: Per-problem routing (skip hints for "generic" problems)

All three target the retriever and need to compose independently.

## Dead `reflect()` Method

The `MemoryBuilder` protocol defines `reflect()`, but the runner never calls it.
All three implementations (`none`, `arcmemo_oe`, `arcmemo_ps`) have stub
implementations that are dead code. Removed in this refactoring.

## Sync `retrieve()` Bug

`PsSelectorRetriever.retrieve()` (sync) returns `hint_text=None` when no
`prompt_info_file` is set, even with `use_llm_selector=False`. The async path
correctly reconstructs `ConceptMemory` from payload and renders hints. This causes
three test failures. Fixed by making the sync path reconstruct and render, matching
the async path.

## Refactoring Approach

### Schema Validation (Step 3)

Add explicit schema coupling at wiring time:
- Builders declare `SCHEMA_NAME` (e.g., `"arcmemo_ps"`)
- Retrievers declare `COMPATIBLE_SCHEMAS` (e.g., `{"arcmemo_ps"}`)
- `wiring.py` validates compatibility at startup, raising `ConfigurationError`
  for mismatches

Uses `getattr()` so existing/external implementations without these constants
remain backward-compatible.

### Composable Retrieval (Step 5)

Decompose `ps_selector` into an internal pipeline:
```
select → filter → route → render
```

New constructor params (all with backward-compatible defaults):
- `render_mode`: `"full"` / `"cues_only"` / `"name_only"`
- `max_frequency`: drop concepts selected too often across the problem set
- `max_concepts_per_problem`: cap selected concepts
- `routing_strategy`: skip hints entirely for "generic" problems
- `concept_frequency_file`: JSON with per-concept selection frequencies

Each concern can be configured independently via YAML config, composing freely.

### Concept Frequency Script (Step 6)

New `scripts/compute_concept_frequencies.py` reads `selected_concepts.json`
(from `scripts/select_concepts.py`) and outputs per-concept selection fractions.
This feeds the `max_frequency` filter and `selection_confidence` routing.

## Known Gap: Precomputed Path Bypasses Pipeline

The composable pipeline (filter → route → render) only fires on the **inline
path** (no `prompt_info_file`). When `prompt_info_file` is set — which is how
all real experiment configs work — `_retrieve_precomputed()` returns the
pre-baked hint string directly and short-circuits past the new params.

This means `render_mode`, `max_frequency`, `routing_strategy`, etc. are
currently **inert** for precomputed configs. The 3 new experiment configs
(`concept_lcb_opt2_cues`, `concept_lcb_opt1_filtered`, `concept_lcb_opt123_composed`)
produce identical behavior to the baseline `concept_lcb_eval`.

Smoke tests confirmed: all 4 precomputed configs produced identical prompt
sizes (6,185 bytes). The render_mode difference only appeared on the inline
path (full=42K, cues_only=25K at -41%, name_only=11K at -73%).

**To activate Options 1/2/3 for real experiments**, the precomputed path needs
to store selected concept *names* (not pre-rendered text) in `prompt_info.json`,
then re-render at runtime through the pipeline. Alternatively, re-run
`scripts/select_concepts.py` with different rendering flags to produce separate
`prompt_info.json` files per option.
