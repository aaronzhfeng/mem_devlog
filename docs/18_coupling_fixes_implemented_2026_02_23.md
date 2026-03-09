# Devlog 23 — Coupling Fixes Implemented

**Date**: 2026-02-23
**Prerequisite**: Devlog 22 (coupling audit, 10 gaps identified)

## Summary

Devlog 22 identified 10 coupling points where pipeline components depended on each
other's internals. This devlog records the actual fixes implemented across two rounds.

**Guiding principle held throughout**: structure changes, logic doesn't. Every config
that worked before produces byte-identical prompts after. Parity verified at each step.

---

## Round 1: Memory System Independence (Points 1, 7, 8, 10)

### Problem

`ps_selector` was a 468-line monolith that imported `ConceptMemory` directly and
bundled 5 concerns (deserialization, selection, filtering, routing, rendering) as
internal methods. The precomputed path (`prompt_info_file`) bypassed the pipeline
entirely — `render_mode`, `max_frequency`, `routing_strategy` were all inert.

### What Was Done

**Extracted format-independent stages** into `src/mem2/retrieval/`:

| New Class | File | Purpose |
|-----------|------|---------|
| `ConceptFilter` | `retrieval/filters.py` | Frequency filter + count cap on concept name strings |
| `RetrievalRouter` | `retrieval/routers.py` | Per-problem gate (none / selection_confidence / hint_length) |

These know nothing about ConceptMemory, OE entries, or any specific format. Any
retriever can compose them.

**Refactored `ps_selector`** to compose these stages:

```python
# Before: internal methods trapped in the class
self._filter_concepts(names)        # can't reuse
self._should_include_hints(names, text)  # can't reuse

# After: composed standalone objects
self._filter = ConceptFilter(max_frequency=..., max_concepts=..., frequency_file=...)
self._router = RetrievalRouter(strategy=..., max_hint_chars=..., frequencies=...)
self._filter.filter(names)
self._router.should_include(names, text)
```

**Added `selected_concepts_file`** param to ps_selector. Loads concept NAMES from
`selected_concepts.json` and feeds them through the full pipeline (filter -> route ->
render). Selection mode priority:

```
1. selected_concepts_file  -> names -> filter -> route -> render  (preferred)
2. prompt_info_file        -> pre-baked hint text, bypasses pipeline  (legacy)
3. LLM selector            -> names -> filter -> route -> render
4. all concepts            -> names -> filter -> route -> render
```

Three experiment configs updated to use `selected_concepts_file`, activating the
pipeline. Baseline config unchanged (legacy path preserved).

### Files Changed (Round 1)

| File | Change |
|------|--------|
| `src/mem2/retrieval/__init__.py` | New package |
| `src/mem2/retrieval/filters.py` | New: ConceptFilter |
| `src/mem2/retrieval/routers.py` | New: RetrievalRouter |
| `src/mem2/branches/memory_retriever/ps_selector.py` | Compose Filter+Router, add selected_concepts_file, dispatch logic |
| `configs/experiments/concept_lcb_opt*.yaml` (3 files) | Add selected_concepts_file |
| `configs/options.yaml` | Document selected_concepts_file |
| `configs/components.md` | Document three selection modes, Filter, Router |
| `tests/unit/test_retrieval_stages.py` | New: 16 tests for ConceptFilter + RetrievalRouter |
| `tests/unit/test_concept_ps.py` | 5 new tests + 2 fixed for precomputed-names path |

### Verified (Round 1)

- 158 unit tests passed
- ARC parity: `offline parity reproducible: True`
- Differentiated prompt sizes confirmed (baseline 6,027B, cues_only 5,101B at -15%,
  filtered 5,509B at -9%)

---

## Round 2: Protocol Completeness & Domain Validation (Points 3, 4, 5, 6)

### Point 3 Fix: InferenceEngine Protocol Extended

**Problem**: Runner used `getattr`/`hasattr` for attributes that every IE implements
but the protocol didn't declare: `model`, `include_reselected_lessons`,
`set_retry_policy()`.

**Fix**: Added to `InferenceEngine` protocol in `contracts.py`:

```python
class InferenceEngine(Protocol):
    name: str
    model: str                              # was: getattr(..., "model", "")
    include_reselected_lessons: bool        # was: getattr(..., "include_reselected_lessons", False)
    def set_retry_policy(self, policy) -> None: ...  # was: hasattr check
```

Runner now uses direct access. All 3 inference engines already had these — no
implementation changes needed.

For `prompt_options` (ARC-specific, only `python_transform_retry` has it): replaced
`getattr` on the IE object with a config dict read. The runner already has
`self.config` — it reads `components.inference_engine.prompt_options` from the dict
instead of probing the object. No coupling to the IE class.

### Point 4 Fix: Unified async_retrieve

**Problem**: Runner had two code paths based on `hasattr(retriever, "async_retrieve")`.
The async path received `provider` and `selector_model` from the IE. The sync path
got neither. A new retriever implementer wouldn't know about this hidden branching.

**Fix**: Added `async_retrieve` to `MemoryRetriever` protocol:

```python
class MemoryRetriever(Protocol):
    def retrieve(self, ctx, memory, problem, previous_attempts) -> RetrievalBundle: ...
    async def async_retrieve(self, *, ctx, provider, memory, problem,
                             previous_attempts, selector_model="") -> RetrievalBundle: ...
```

All 4 retrievers implement it:
- `none`, `oe_topk`: thin wrapper calling `self.retrieve(...)`, ignores provider/model
- `oe_selector`, `ps_selector`: existing async implementation (LLM-based selection)

Runner always calls `await retriever.async_retrieve(...)`. The `hasattr` branch and
the fallback sync path in `_run_inference_job` are gone.

**Result**: `runner.py` has zero `getattr` and zero `hasattr` calls.

### Points 5+6 Fix: Domain Triple Validation

**Problem**: Nothing validated that benchmark, IE, evaluator, and feedback engine
belong to the same domain. `arc_agi` + `math_ps_solve` would silently produce garbage.
Feedback engine detail format mismatches (point 6) were a consequence of the same gap.

**Fix**: Added `DOMAIN_NAME` class attribute to all 12 domain-specific components:

| Domain | Benchmark | IE | Evaluator | Feedback |
|--------|-----------|-----|-----------|----------|
| `"arc"` | `arc_agi` | `python_transform_retry` | `arc_exec` | `gt_check` |
| `"math"` | `competition_math_ps` | `math_ps_solve` | `math_ps_exec` | `math_ps_gt` |
| `"code"` | `livecodebench` | `lcb_solve` | `lcb_exec` | `lcb_gt` |

New `_validate_domain_components()` in `wiring.py` checks all 4 share the same domain.
Uses `getattr(comp, "DOMAIN_NAME", None)` — components without the attribute are
silently accepted (backward compat). Mismatches raise `ConfigurationError` at startup.

This also prevents point 6: if `gt_check` (arc) can never be paired with
`math_ps_exec` (math), the eval detail format mismatch can never occur.

### Point 9: Accepted

`oe_topk`/`oe_selector` reading `memory.payload["entries"]` is the OE equivalent of
`ConceptMemory.from_payload()`. The format is simple (flat list of dicts) and
`SCHEMA_NAME`/`COMPATIBLE_SCHEMAS` validation prevents mispairing. Adding a
deserialization layer would add complexity for minimal gain.

### Point 2: Document Only

Retriever -> IE hint format coupling is low severity. `hint_text` is just a string,
prompt templates are generic (`"### Hints\n{hint_text}"`). No fix needed.

### Files Changed (Round 2)

| File | Change |
|------|--------|
| `src/mem2/core/contracts.py` | IE: +model, +include_reselected_lessons, +set_retry_policy. MR: +async_retrieve |
| `src/mem2/orchestrator/runner.py` | Removed all getattr/hasattr, unified async path |
| `src/mem2/orchestrator/wiring.py` | Added _validate_domain_components() |
| `src/mem2/branches/memory_retriever/none.py` | Added async_retrieve wrapper |
| `src/mem2/branches/memory_retriever/oe_topk.py` | Added async_retrieve wrapper |
| 12 component files | Added DOMAIN_NAME class attribute |
| `tests/unit/test_wiring_validation.py` | New: 12 domain + memory pairing tests |
| `tests/unit/test_async_retrieve.py` | New: 5 async_retrieve tests |

### Verified (Round 2)

- 175 unit tests passed (158 + 17 new)
- ARC parity: `offline parity reproducible: True`
- ARC smoke test end-to-end: pass via unified async path
- Domain mismatch: `arc_agi` + `math_ps_solve` -> `ConfigurationError`
- Prompt sizes: differentiated (baseline 6,344B, cues 5,923B, filtered 5,661B)

---

## Final Status: All 10 Coupling Points

| # | Coupling Point | Severity | Status |
|---|---------------|----------|--------|
| 1 | Builder <-> Retriever shared class | HIGH | **Fixed** (round 1: schema validation, ConceptFilter/Router extracted) |
| 2 | Retriever <-> IE hint format | LOW | Documented (generic template, low risk) |
| 3 | Runner <-> IE non-protocol methods | MEDIUM | **Fixed** (round 2: protocol extended, getattr removed) |
| 4 | Runner <-> Retriever async split | MEDIUM | **Fixed** (round 2: async_retrieve on protocol, hasattr removed) |
| 5 | Domain triples unvalidated | MEDIUM | **Fixed** (round 2: DOMAIN_NAME + wiring validation) |
| 6 | Evaluator <-> Feedback detail format | MEDIUM | **Fixed** (round 2: covered by domain validation) |
| 7 | ps_selector imports ConceptMemory | HIGH | **Fixed** (round 1: format-independent stages extracted) |
| 8 | ps_selector bundles 5 concerns | HIGH | **Fixed** (round 1: ConceptFilter + RetrievalRouter composed) |
| 9 | OE retrievers reach into payload | LOW | Accepted (schema validation, simple format) |
| 10 | Precomputed path bypasses pipeline | HIGH | **Fixed** (round 1: selected_concepts_file goes through pipeline) |

---

## What "Adding a New Component" Looks Like Now

### New benchmark domain (e.g. "geometry")

1. Create `src/mem2/branches/benchmark/geometry.py` with `DOMAIN_NAME = "geometry"`
2. Create matching IE, evaluator, feedback engine with `DOMAIN_NAME = "geometry"`
3. Register each in `src/mem2/registry/`
4. Create experiment config YAML

Wiring catches: memory schema mismatch, domain mismatch. Protocols tell you exactly
what methods to implement — no hidden `hasattr` branching in the runner.

### New memory retriever

1. Create `src/mem2/branches/memory_retriever/my_retriever.py`
2. Implement `retrieve()` and `async_retrieve()` per protocol
3. Set `COMPATIBLE_SCHEMAS = {"arcmemo_ps"}` (or whichever)
4. Optionally compose `ConceptFilter` and `RetrievalRouter` for filtering/routing
5. Register in `src/mem2/registry/memory_retriever.py`

### New routing strategy

1. Add the strategy name to `RetrievalRouter.should_include()` in
   `src/mem2/retrieval/routers.py`
2. Add it to `routing_strategy` options in `configs/options.yaml`
3. Use it in any retriever that composes `RetrievalRouter`

---

## Remaining Gap (see Devlog 24)

The `pipeline:` and `components:` config sections are not validated against each
other. `pipeline.X` selects a class; `components.X` provides kwargs. Nothing checks
that the kwargs are valid for the selected class. Wrong params are silently absorbed
or ignored.
