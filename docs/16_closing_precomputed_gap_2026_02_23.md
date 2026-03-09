# Devlog 22 — Closing the Precomputed-Path Gap

**Date**: 2026-02-23

## Background

Devlog 21 identified five structural problems in the memory architecture and
implemented fixes for all of them:

1. **Hidden payload coupling** — Fixed with `SCHEMA_NAME`/`COMPATIBLE_SCHEMAS`
   validation at wiring time (`wiring.py:_validate_memory_pairing()`).
2. **Three concerns bundled in ps_selector** — Decomposed into internal pipeline
   methods: `_filter_concepts()`, `_should_include_hints()`, `_render_hint_text()`.
3. **Dead `reflect()` method** — Removed from protocol and all implementations.
4. **Sync `retrieve()` bug** — Fixed to reconstruct ConceptMemory from payload.
5. **Composable retrieval** — Added `render_mode`, `max_frequency`,
   `max_concepts_per_problem`, `routing_strategy`, `concept_frequency_file` params.

All 137 tests pass. ARC parity holds.

## The Gap Discovered

Smoke testing all four LCB concept configs against real API revealed that **all four
configs produce identical 6,185-byte prompts**. The three "improved" configs
(`concept_lcb_opt2_cues`, `concept_lcb_opt1_filtered`, `concept_lcb_opt123_composed`)
are functionally identical to the baseline `concept_lcb_eval`.

### Root Cause

The precomputed path (`_retrieve_precomputed()`) returns the pre-baked hint string
from `prompt_info.json` directly:

```python
def _retrieve_precomputed(self, problem):
    entry = self._prompt_info.get(problem.uid)
    if entry and entry.get("hint"):
        return RetrievalBundle(hint_text=entry["hint"], ...)  # <-- bypasses everything
```

This short-circuits past the entire filter/route/render pipeline. The pipeline params
(`render_mode`, `max_frequency`, `routing_strategy`, etc.) only fire on the **inline
path** (no `prompt_info_file`), which no real experiment config uses.

### Why `prompt_info.json` Stores Pre-Rendered Text

The offline pipeline (`scripts/select_concepts.py`) produces two files:

| File | Format | Content |
|------|--------|---------|
| `selected_concepts.json` | `{uid: ["name", ...]}` | Concept names per problem |
| `prompt_info.json` | `{uid: {hint: "markdown"}}` | Pre-rendered hint text |

The retriever currently only consumes `prompt_info.json` (pre-rendered text), ignoring
`selected_concepts.json` (names). This was a reasonable design when rendering was fixed
— but now that we have composable render_mode/filtering/routing, we need the names to
re-render at runtime.

### Inline Path Confirmation

On the inline path (no `prompt_info_file`), the pipeline works correctly:

| Render Mode | Hint Size | Reduction |
|-------------|-----------|-----------|
| full | 42K bytes | baseline |
| cues_only | 25K bytes | -41% |
| name_only | 11K bytes | -73% |

The pipeline is correctly implemented — it just never fires for real configs.

## Data Inventory

All files exist in `mem2/data/livecodebench_v56/concept_memory/`:

```
compressed_v2.json           ← ConceptMemory (seed for builder)
selection_v2/
  selected_concepts.json     ← {uid: [concept_name, ...]}  (96 problems, 49 unique concepts)
  prompt_info.json           ← {uid: {hint: "rendered text"}}
  concept_frequencies.json   ← {concept_name: fraction}  (from compute_concept_frequencies.py)
  completions.json           ← raw LLM selection outputs
  parse_errors.json          ← failed selections
```

`selected_concepts.json` is the key input — it has exactly what the pipeline needs
(concept names) without pre-baking the rendering.

## Current Architecture (After Devlog 21)

```
ps_selector.__init__():
  prompt_info_file  → self._prompt_info: {uid: {hint: str}} | None
  concept_frequency_file → self._concept_frequencies: {name: float}

retrieve() / async_retrieve():
  if self._prompt_info is not None:
      return _retrieve_precomputed(problem)   ← BYPASSES PIPELINE
  concept_mem = _reconstruct_memory(memory)
  if use_llm_selector:
      selected = LLM_select(concept_mem, problem)
      return _apply_pipeline(selected)
  else:
      return _apply_pipeline(None)            ← None = all concepts

_apply_pipeline(selected_names):
  _filter_concepts(selected_names)            ← max_frequency, max_concepts_per_problem
  _render_hint_text(concept_mem, filtered)    ← render_mode: full/cues_only/name_only
  _should_include_hints(filtered, hint_text)  ← routing_strategy
  → RetrievalBundle
```

## Proposed Fix

### Add `selected_concepts_file` Param

New constructor param that loads `{uid: [concept_name, ...]}` — the same format as
`selected_concepts.json`. When set, the retriever looks up concept names per problem
and feeds them through `_apply_pipeline()`.

### Selection Mode Priority

```
1. selected_concepts_file  → "precomputed"          (names → filter → route → render)
2. prompt_info_file        → "precomputed_rendered"  (legacy, bypasses pipeline)
3. use_llm_selector=True   → "llm"                  (runtime LLM → filter → route → render)
4. use_llm_selector=False  → "all"                  (all concepts → filter → route → render)
```

When `selected_concepts_file` is set, it takes priority over `prompt_info_file`.
This means:

- **New configs** (opt2, opt1, opt123): set `selected_concepts_file` → pipeline active
- **Baseline config** (`concept_lcb_eval`): only `prompt_info_file` → legacy path preserved
- **No config breaks**: existing configs without `selected_concepts_file` work as before

### New Internal Method

```python
def _retrieve_precomputed_names(self, concept_mem, problem):
    names = self._selected_concepts.get(problem.uid)
    if not names:
        return RetrievalBundle(hint_text=None, metadata={"selector_mode": "precomputed_miss"})
    return self._apply_pipeline(
        concept_mem=concept_mem, selected_names=names,
        problem=problem, selector_mode="precomputed",
    )
```

This is the missing link — takes precomputed concept names and routes them through the
filter/route/render pipeline that already exists and works.

### Updated Retrieve Flow

```python
def retrieve(self, ctx, memory, problem, previous_attempts):
    # Legacy precomputed rendered (bypasses pipeline)
    if self._selected_concepts is None and self._prompt_info is not None:
        return self._retrieve_precomputed(problem)

    # All other modes need ConceptMemory
    concept_mem = self._reconstruct_memory(memory)
    if not concept_mem.concepts:
        return RetrievalBundle(hint_text=None, metadata={"selector_mode": "empty"})

    # Precomputed names → through pipeline
    if self._selected_concepts is not None:
        return self._retrieve_precomputed_names(concept_mem, problem)

    # All concepts fallback
    return self._apply_pipeline(concept_mem=concept_mem, selected_names=None, ...)
```

## Expected Outcomes After Fix

### Differentiated Prompt Sizes

| Config | Selection | Pipeline Params | Expected Prompt Size |
|--------|-----------|-----------------|---------------------|
| `concept_lcb_eval` | prompt_info.json (rendered) | none (bypassed) | ~6,185 bytes |
| `concept_lcb_opt2_cues` | selected_concepts.json (names) | render_mode=cues_only | ~3,700 bytes (-40%) |
| `concept_lcb_opt1_filtered` | selected_concepts.json (names) | max_freq=0.3, max_concepts=3 | ~4,000 bytes (-35%) |
| `concept_lcb_opt123_composed` | selected_concepts.json (names) | cues_only + filtered + routing | ~2,500 bytes (-60%) |

### Three Improvement Options Now Active

- **Option 1** (better selection): `max_frequency` drops over-selected concepts,
  `max_concepts_per_problem` caps per-problem count
- **Option 2** (shorter hints): `render_mode=cues_only` strips implementation/params,
  keeping only concept names + cues
- **Option 3** (per-problem routing): `routing_strategy=selection_confidence` skips
  hints entirely when all selected concepts are high-frequency (generic)

All three compose independently via YAML config.

## Experiment Config Updates

Three configs switch from `prompt_info_file`-only to `selected_concepts_file` + pipeline:

```yaml
# concept_lcb_opt2_cues.yaml — Option 2: shorter hints
memory_retriever:
  selected_concepts_file: .../selection_v2/selected_concepts.json
  prompt_info_file: .../selection_v2/prompt_info.json  # fallback
  render_mode: cues_only

# concept_lcb_opt1_filtered.yaml — Option 1: better selection
memory_retriever:
  selected_concepts_file: .../selection_v2/selected_concepts.json
  prompt_info_file: .../selection_v2/prompt_info.json
  max_frequency: 0.3
  max_concepts_per_problem: 3
  concept_frequency_file: .../selection_v2/concept_frequencies.json

# concept_lcb_opt123_composed.yaml — All three composed
memory_retriever:
  selected_concepts_file: .../selection_v2/selected_concepts.json
  prompt_info_file: .../selection_v2/prompt_info.json
  render_mode: cues_only
  max_frequency: 0.3
  max_concepts_per_problem: 3
  concept_frequency_file: .../selection_v2/concept_frequencies.json
  routing_strategy: selection_confidence
```

Baseline `concept_lcb_eval.yaml` stays unchanged (prompt_info_file only, legacy path).

## Files to Change

| File | Change |
|------|--------|
| `src/mem2/branches/memory_retriever/ps_selector.py` | Add `selected_concepts_file` param, `_retrieve_precomputed_names()`, dispatch logic |
| `configs/experiments/concept_lcb_opt2_cues.yaml` | Add `selected_concepts_file` |
| `configs/experiments/concept_lcb_opt1_filtered.yaml` | Add `selected_concepts_file` |
| `configs/experiments/concept_lcb_opt123_composed.yaml` | Add `selected_concepts_file` |
| `configs/options.yaml` | Document `selected_concepts_file` param |
| `configs/components.md` | Update ps_selector docs with three modes |
| `arcmemo_devlog/21_*.md` | Add resolution note |
| `tests/unit/test_concept_ps.py` | 5 new tests for precomputed-names path |

## Verification Plan

1. `python -m pytest tests/unit/ -v` — all tests pass
2. Instantiate ps_selector with different configs, call `retrieve()`, compare prompt
   sizes — confirm differentiation
3. Optional: smoke test opt2_cues against real API, compare prompt size to baseline
