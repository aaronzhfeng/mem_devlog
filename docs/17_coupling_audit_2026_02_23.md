# Devlog 22 — Pipeline Coupling Audit & Memory System Independence Plan

**Date**: 2026-02-23

## Why This Document Exists

This repo was designed so that "new attempt on different component of a lifelong
improving agent can be swapped without too much changes." Every pipeline component
should be independent from the rest — swap one via config, others stay untouched.

In practice, the components are intertwined. This document:
1. Lists every pipeline component and its role
2. Audits every coupling point where one component depends on another's internals
3. Plans the structural fix for the memory system (the most entangled subsystem)

---

## Guiding Principle: Structure Changes, Logic Doesn't

`mem2` is a migration from `/root/arc/arc_memo`. The purpose of the migration is to
make the architecture friendly to future changes — not to make those changes yet.

**The invariant**: no matter how many intermediate steps get restructured, **the prompt
stays the same and what gets sent to the API stays the same**. If a baseline config
produced a specific prompt string before the refactor, it must produce the exact same
prompt string after. If a specific set of concepts was selected for a problem, the
same concepts must be selected. If hint text was rendered with certain formatting, the
same formatting must appear.

This means:
- **Refactoring only** — move logic between classes, extract reusable stages, change
  internal wiring. Never alter the computation itself.
- **Parity is the test** — `scripts/parity/run_arc_default_parity_lock.py` must pass
  before and after every change. Any prompt diff is a bug in the refactor.
- **New capabilities are inert by default** — new config params (like `render_mode`,
  `selected_concepts_file`) must default to the existing behavior. Only explicit
  config changes activate new behavior.
- **No "improvements" during migration** — don't fix prompt wording, don't change
  selection logic, don't optimize rendering. Those are separate experiments that
  happen AFTER the structure is clean.

Every step in this document and the fix plan below follows this principle.

---

## All Pipeline Components

10 protocol interfaces defined in `src/mem2/core/contracts.py`. Each has concrete
implementations registered in `src/mem2/registry/` and wired at runtime by
`src/mem2/orchestrator/wiring.py`. Config YAML selects which class to instantiate
(`pipeline.*`) and passes constructor args (`components.*`).

### Component Map

```
BenchmarkAdapter → ProblemSpec[] → TaskAdapter
                                        ↓
                                   InferenceEngine ←→ ProviderClient
                                        ↓
                                   AttemptRecord[]
                                        ↓
                                   Evaluator → EvalRecord[]
                                        ↓
                                   FeedbackEngine → FeedbackRecord[]
                                        ↓
                            MemoryBuilder.update(attempts, evals, feedback)
                                        ↓
                                   MemoryState
                                        ↓
                            MemoryRetriever.retrieve(memory, problem)
                                        ↓
                                   RetrievalBundle(hint_text)
                                        ↓
                                   InferenceEngine (next pass)

TrajectoryPolicy — plans initial/retry paths (parallel to above)
ArtifactSink — serializes all outputs to disk
```

### Component Implementations

| # | Protocol | Implementations | Data Produced |
|---|----------|----------------|---------------|
| 1 | **BenchmarkAdapter** | `arc_agi`, `competition_math_ps`, `livecodebench` | `dict[str, ProblemSpec]` |
| 2 | **TaskAdapter** | `arc_grid`, `math_ps` | `TaskSpec` |
| 3 | **MemoryBuilder** | `none`, `arcmemo_oe`, `arcmemo_ps` | `MemoryState` |
| 4 | **MemoryRetriever** | `none`, `oe_topk`, `oe_selector`, `ps_selector` | `RetrievalBundle` |
| 5 | **TrajectoryPolicy** | `single_path` | `TrajectoryPlan` |
| 6 | **ProviderClient** | `mock`, `llmplus_openrouter`, `llmplus_openai`, ... | `list[str]` (completions) |
| 7 | **InferenceEngine** | `python_transform_retry`, `math_ps_solve`, `lcb_solve` | `list[AttemptRecord]` |
| 8 | **FeedbackEngine** | `gt_check`, `math_ps_gt`, `lcb_gt` | `list[FeedbackRecord]` |
| 9 | **Evaluator** | `arc_exec`, `math_ps_exec`, `lcb_exec` | `list[EvalRecord]` |
| 10 | **ArtifactSink** | `json_local` | file paths |

### Data Entities (the protocol boundaries)

Defined in `src/mem2/core/entities.py`:

| Entity | Fields | Flows Between |
|--------|--------|---------------|
| `ProblemSpec` | uid, train_pairs, test_pairs, metadata | Benchmark → everything |
| `MemoryState` | schema_name, schema_version, payload (`dict[str, Any]`), metadata | Builder → Retriever |
| `RetrievalBundle` | problem_uid, hint_text, retrieved_items, metadata | Retriever → InferenceEngine |
| `AttemptRecord` | problem_uid, pass_idx, branch_id, completion, prompt, metadata | InferenceEngine → Evaluator |
| `EvalRecord` | problem_uid, attempt_idx, is_correct, train_details, test_details, metadata | Evaluator → FeedbackEngine |
| `FeedbackRecord` | problem_uid, attempt_idx, feedback_type, content, metadata | FeedbackEngine → Builder.update() |
| `TrajectoryPlan` | num_paths, strategy, metadata | Policy → InferenceEngine |
| `RunContext` | run_id, seed, config, output_dir | Everywhere |

---

## Coupling Audit: 10 Points Where Components Are Intertwined

### Point 1: MemoryBuilder ↔ MemoryRetriever — Shared Internal Class

**Where**: `arcmemo_ps` builder (line 3-6) imports `ConceptMemory`, calls
`concept_mem.to_payload()` to serialize into `MemoryState.payload`.
`ps_selector` retriever (line 129-130) imports `ConceptMemory`, calls
`ConceptMemory.from_payload(memory.payload)` to deserialize.

**Problem**: Both sides share the `ConceptMemory` class as a hidden contract.
The protocol boundary is `MemoryState.payload` (untyped `dict[str, Any]`), but
the actual contract is "this dict must be a serialized ConceptMemory." If you
change ConceptMemory's serialization format, both builder and retriever break.

**Same pattern in OE**: `arcmemo_oe` writes `payload["entries"]` as flat dicts.
`oe_topk` reads `memory.payload.get("entries", [])`. `oe_selector` reads the
same, or loads from external file.

**Mitigation added in devlog 21**: `SCHEMA_NAME`/`COMPATIBLE_SCHEMAS` validation
at wiring time catches mismatched pairs (e.g., `arcmemo_ps` + `oe_topk`). But
this only checks a string label — doesn't validate payload structure or version.

**Files**:
- `src/mem2/branches/memory_builder/arcmemo_ps.py` (lines 3-6, 30-40)
- `src/mem2/branches/memory_retriever/ps_selector.py` (lines 22, 129-130)
- `src/mem2/branches/memory_retriever/oe_topk.py` (line 20)
- `src/mem2/concepts/memory.py` (to_payload at line 537, from_payload at line 546)

---

### Point 2: MemoryRetriever ↔ InferenceEngine — Hint Format Assumption

**Where**: Retriever produces `RetrievalBundle.hint_text` (a string). InferenceEngine
wraps it in a prompt template.

**Problem**: No contract on what `hint_text` contains. Different retrievers produce
different formats:
- `oe_topk`: plain text concatenation of lesson entries
- `oe_selector`: situation/suggestion bullets
- `ps_selector`: markdown with `## structure concepts`, `## grid manipulation routines`,
  concept names, cues, implementation patterns

The inference engine's prompt template implicitly expects a specific format.
`python_transform_retry` uses `HINT_TEMPLATE_OP3` which wraps hint_text in
`"### Hints\n{hint_text}"`. Works for both formats because the template is generic.
But if a retriever produced structured JSON or a different markdown format, the
prompt would be wrong.

**Current risk**: Low — `hint_text` is just text and templates are generic. But
there's no validation or documentation of expected format.

**Files**:
- `src/mem2/prompting/render.py` (hint templates)
- `src/mem2/branches/inference_engine/python_transform_retry.py` (make_initial_prompt)

---

### Point 3: Runner ↔ InferenceEngine — Non-Protocol Methods

**Where**: `runner.py` uses `getattr()` and `hasattr()` to access methods/attributes
not defined on the `InferenceEngine` protocol:

```python
# runner.py:45 — checks non-protocol attribute
self._reselect_hint_enabled = bool(
    getattr(self.components.inference_engine, "include_reselected_lessons", False)
)

# runner.py:328 — reads non-protocol attribute
prompt_options = getattr(self.components.inference_engine, "prompt_options", None)

# runner.py:618 (in _sync_retry_policy) — calls non-protocol method
if hasattr(self.components.inference_engine, "set_retry_policy"):
    self.components.inference_engine.set_retry_policy(self.retry_policy)
```

**Problem**: The runner knows about implementation details of specific inference
engines. If you write a new InferenceEngine that doesn't have `prompt_options` or
`set_retry_policy`, the runner silently skips those features. Some behaviors become
invisible and hard to debug.

**Files**:
- `src/mem2/orchestrator/runner.py` (lines 45, 328, 618)
- `src/mem2/core/contracts.py` (InferenceEngine protocol — missing these methods)

---

### Point 4: Runner ↔ MemoryRetriever — Async Split

**Where**: `runner.py` checks `hasattr(retriever, "async_retrieve")` to decide
between two code paths:

```python
# runner.py:338 — sync path
if hasattr(retriever, "async_retrieve"):
    retrieval = None  # deferred to _run_inference_job
else:
    retrieval = retriever.retrieve(ctx, memory, problem, history)

# runner.py:375 — async path (later)
if hasattr(retriever, "async_retrieve"):
    retrieval = await retriever.async_retrieve(
        ctx=ctx,
        provider=self.components.provider,   # <-- extra dependency
        memory=...,
        problem=...,
        previous_attempts=...,
        selector_model=str(getattr(self.components.inference_engine, "model", "")),  # <-- from IE
    )
```

**Problem**: The `MemoryRetriever` protocol only defines sync `retrieve()`. The async
path is an informal extension that receives extra dependencies (`provider`,
`selector_model` from the inference engine). This means:
- The retriever informally depends on the provider (for LLM selection)
- The retriever informally depends on the inference engine (for model name)
- Two completely different code paths in the runner based on `hasattr()`

**Files**:
- `src/mem2/orchestrator/runner.py` (lines 338, 373-390)
- `src/mem2/core/contracts.py` (MemoryRetriever protocol — only has sync retrieve)
- `src/mem2/branches/memory_retriever/ps_selector.py` (async_retrieve method)
- `src/mem2/branches/memory_retriever/oe_selector.py` (async_retrieve method)

---

### Point 5: Benchmark ↔ InferenceEngine ↔ Evaluator — Domain Triples

**Where**: Three domain-specific triples must match but nothing validates compatibility:

| Domain | Benchmark | InferenceEngine | Evaluator | FeedbackEngine |
|--------|-----------|----------------|-----------|----------------|
| ARC | `arc_agi` | `python_transform_retry` | `arc_exec` | `gt_check` |
| Math | `competition_math_ps` | `math_ps_solve` | `math_ps_exec` | `math_ps_gt` |
| LCB | `livecodebench` | `lcb_solve` | `lcb_exec` | `lcb_gt` |

**Problem**: If you configure `arc_agi` benchmark + `math_ps_solve` inference engine,
the run silently produces garbage:
- `math_ps_solve` expects `problem.metadata["problem_text"]` (ARC problems don't have it)
- `arc_exec` expects Python code with `transform()` function (`math_ps_solve` produces
  `solve()` function)

No wiring-time validation catches this. The `SCHEMA_NAME`/`COMPATIBLE_SCHEMAS` pattern
from devlog 21 could be extended to these triples but isn't.

**Files**:
- `src/mem2/orchestrator/wiring.py` (no cross-component validation beyond memory)

---

### Point 6: Evaluator ↔ FeedbackEngine — Detail Field Names

**Where**: `gt_check.py:22-35` reads specific field names from
`EvalRecord.train_details`:

```python
for detail in eval_record.train_details:
    pair_idx = int(detail.get("pair_idx", -1)) + 1
    err = detail.get("error")
    if not detail.get("correct", False):
        mismatches.append({
            "example_idx": pair_idx,
            "output": detail.get("output"),
            "expected": detail.get("expected"),
        })
```

**Problem**: The detail dict structure (`pair_idx`, `error`, `correct`, `output`,
`expected`) is an implicit contract between `arc_exec` evaluator and `gt_check`
feedback engine. Not versioned, not documented in the protocol. Each domain triple
has its own detail format:
- ARC: `{pair_idx, is_train, parsed, correct, error, output, expected}`
- Math: `{error, output, expected, correct}`
- LCB: `{test_idx, stdin, expected_stdout, actual_stdout, correct, error}`

**Files**:
- `src/mem2/branches/feedback_engine/gt_check.py` (lines 22-35)
- `src/mem2/branches/evaluator/arc_exec.py` (train_details structure)

---

### Point 7: ps_selector Imports ConceptMemory Directly

**Where**: `ps_selector.py` imports 4 classes from the concept system:

```python
from mem2.concepts.domain import DomainProfile
from mem2.concepts.memory import ConceptMemory
from mem2.concepts.prompts import DOMAIN_PROMPT_MAP
from mem2.prompting.render import format_problem_for_prompt
```

**Problem**: The retriever implementation is hard-wired to the concept memory system.
It calls:
- `ConceptMemory.from_payload()` — deserialization
- `concept_mem.to_string()` with 6+ flags — rendering
- `concept_mem.concepts` — direct attribute access
- `DomainProfile()` — domain-specific rendering profiles
- `DOMAIN_PROMPT_MAP` — domain-specific prompt templates

If you wanted to use a different memory representation (e.g., embeddings, knowledge
graph, flat key-value pairs), you'd need to write an entirely new retriever from
scratch. The filtering and routing logic — which is format-independent — can't be
reused.

**Files**:
- `src/mem2/branches/memory_retriever/ps_selector.py` (lines 21-31)
- `src/mem2/concepts/memory.py` (ConceptMemory class)
- `src/mem2/concepts/domain.py` (DomainProfile)
- `src/mem2/concepts/prompts/` (DOMAIN_PROMPT_MAP)

---

### Point 8: ps_selector Bundles 5 Concerns

**Where**: One class handles everything between `MemoryState` and `RetrievalBundle`:

| Concern | Method | Format-Dependent? |
|---------|--------|--------------------|
| Deserialization | `_reconstruct_memory()` → `ConceptMemory.from_payload()` | Yes (ConceptMemory) |
| Selection | precomputed / LLM / all concepts | Yes (concept names, domain prompts) |
| Filtering | `_filter_concepts()` — frequency filter + count cap | **No** (works on string names) |
| Routing | `_should_include_hints()` — confidence/length gate | **No** (works on names + text) |
| Rendering | `_render_hint_text()` → `ConceptMemory.to_string()` | Yes (ConceptMemory) |

**Problem**: Filtering and routing are generic operations on concept names and metadata.
They don't depend on ConceptMemory at all. But they're trapped as internal methods of
`ps_selector` — `oe_selector` can't reuse them, and neither can any future retriever.

You can't swap rendering mode without understanding the whole class. You can't add a
new routing strategy without touching ps_selector. Each concern should be independently
configurable and reusable.

**Files**:
- `src/mem2/branches/memory_retriever/ps_selector.py` (lines 157-237)

---

### Point 9: oe_topk / oe_selector Reach Into Payload

**Where**: Same structural problem as points 7-8, but simpler:

```python
# oe_topk.py:20
entries = list(memory.payload.get("entries", []))

# oe_selector.py (multiple locations)
# Falls back to memory.payload["entries"], expects {situation, suggestion} dicts
```

**Problem**: Both OE retrievers directly access `payload["entries"]` and expect
specific dict fields (`problem_uid`, `hint`, `situation`, `suggestion`). The format
is an implicit contract with `arcmemo_oe` builder.

**Severity**: Lower than PS because the OE format is simpler (flat list of dicts).
But the structural issue is the same — retriever knows builder internals.

**Files**:
- `src/mem2/branches/memory_retriever/oe_topk.py` (line 20)
- `src/mem2/branches/memory_retriever/oe_selector.py` (multiple locations)

---

### Point 10: Precomputed Path Bypasses Pipeline

**Where**: `ps_selector._retrieve_precomputed()` returns pre-baked hint text from
`prompt_info.json`, short-circuiting filter/route/render:

```python
def _retrieve_precomputed(self, problem):
    entry = self._prompt_info.get(problem.uid)
    if entry and entry.get("hint"):
        return RetrievalBundle(hint_text=entry["hint"], ...)  # bypasses everything
```

**Problem**: All real experiment configs use `prompt_info_file` (precomputed mode).
The pipeline params added in devlog 21 (`render_mode`, `max_frequency`,
`routing_strategy`, etc.) only fire on the inline path (no `prompt_info_file`).

Smoke test confirmed: all 4 precomputed configs produce identical 6,185-byte prompts.
On the inline path, differentiation works correctly (full=42K, cues_only=25K at -41%,
name_only=11K at -73%).

**Root cause**: `prompt_info.json` stores pre-rendered hint TEXT. But
`selected_concepts.json` stores concept NAMES and already exists (produced by the same
`scripts/select_concepts.py`). The retriever only consumes the rendered version,
ignoring the names.

**Fix**: Add `selected_concepts_file` param that loads concept names and feeds them
through the pipeline (filter → route → render) at runtime.

**Files**:
- `src/mem2/branches/memory_retriever/ps_selector.py` (lines 274-290)
- `data/livecodebench_v56/concept_memory/selection_v2/selected_concepts.json`
- `data/livecodebench_v56/concept_memory/selection_v2/prompt_info.json`

---

## Coupling Severity Summary

| # | Coupling Point | Severity | Status |
|---|---------------|----------|--------|
| 1 | Builder ↔ Retriever shared class | HIGH | **Fixed** (round 1) |
| 2 | Retriever ↔ InferenceEngine hint format | LOW | Document only |
| 3 | Runner ↔ InferenceEngine non-protocol | MEDIUM | **Fixed** (round 2) |
| 4 | Runner ↔ Retriever async split | MEDIUM | **Fixed** (round 2) |
| 5 | Domain triples unvalidated | MEDIUM | **Fixed** (round 2) |
| 6 | Evaluator ↔ FeedbackEngine detail format | MEDIUM | **Fixed** (round 2, via point 5) |
| 7 | ps_selector imports ConceptMemory | HIGH | **Fixed** (round 1) |
| 8 | ps_selector bundles 5 concerns | HIGH | **Fixed** (round 1) |
| 9 | oe_topk/oe_selector reach into payload | LOW | Accepted (schema validation) |
| 10 | Precomputed path bypasses pipeline | HIGH | **Fixed** (round 1) |

---

## Fix Plan: Memory System Independence

### Problem Summary

`ps_selector` is a monolith that handles deserialization, selection, filtering,
routing, and rendering — all in one 468-line class. It directly imports
`ConceptMemory`, `DomainProfile`, and `DOMAIN_PROMPT_MAP`. The format-independent
stages (filtering, routing) are trapped as internal methods and can't be reused by
other retrievers.

### Target Architecture

```
ps_selector (thin coordinator, format-specific)
  ├── Deserialization: ConceptMemory.from_payload()    [stays, format-specific]
  ├── Selection: precomputed names / LLM / all         [stays, format-specific]
  ├── ConceptFilter                                    [EXTRACTED, format-independent]
  ├── RetrievalRouter                                  [EXTRACTED, format-independent]
  └── Rendering: ConceptMemory.to_string()             [stays, format-specific]
```

**Key change**: `ConceptFilter` and `RetrievalRouter` become standalone classes in a
new `src/mem2/retrieval/` package. They work on concept names (strings) and frequency
metadata. They know nothing about ConceptMemory, OE entries, or any specific memory
format. Any retriever — current or future — can compose them.

### Step 1: Create `src/mem2/retrieval/filters.py`

Extract `_filter_concepts()` from ps_selector into standalone `ConceptFilter`:

```python
class ConceptFilter:
    """Format-independent concept filtering. Reusable across retrievers."""

    def __init__(self, max_frequency=0.0, max_concepts=0, frequency_file=""):
        self.max_frequency = float(max_frequency)
        self.max_concepts = int(max_concepts)
        self._frequencies: dict[str, float] = {}
        if frequency_file:
            path = Path(frequency_file)
            if path.exists():
                self._frequencies = json.loads(path.read_text())

    @property
    def frequencies(self) -> dict[str, float]:
        return self._frequencies

    def filter(self, names: list[str]) -> list[str]:
        result = names
        if self.max_frequency > 0.0 and self._frequencies:
            result = [n for n in result
                      if self._frequencies.get(n, 0.0) <= self.max_frequency]
        if self.max_concepts > 0:
            result = result[:self.max_concepts]
        return result
```

### Step 2: Create `src/mem2/retrieval/routers.py`

Extract `_should_include_hints()` from ps_selector into standalone `RetrievalRouter`:

```python
class RetrievalRouter:
    """Format-independent routing gate. Reusable across retrievers."""

    def __init__(self, strategy="none", frequency_threshold=0.5,
                 max_hint_chars=0, frequencies=None):
        self.strategy = strategy
        self.frequency_threshold = float(frequency_threshold)
        self.max_hint_chars = int(max_hint_chars)
        self._frequencies = frequencies or {}

    def should_include(self, names: list[str] | None, hint_text: str | None) -> bool:
        if self.strategy == "none":
            return True
        if self.strategy == "selection_confidence":
            if not names or not self._frequencies:
                return True
            all_generic = all(
                self._frequencies.get(n, 0.0) > self.frequency_threshold
                for n in names)
            return not all_generic
        if self.strategy == "hint_length":
            if not hint_text or self.max_hint_chars <= 0:
                return True
            return len(hint_text) <= self.max_hint_chars
        return True
```

### Step 3: Add `selected_concepts_file` to ps_selector

New constructor param. Loads `{uid: [concept_name, ...]}` from
`selected_concepts.json`. When set, takes priority over `prompt_info_file`.

Selection mode priority:
```
1. selected_concepts_file  → "precomputed"          (names → filter → route → render)
2. prompt_info_file        → "precomputed_rendered"  (legacy, bypasses pipeline)
3. use_llm_selector=True   → "llm"                  (LLM → filter → route → render)
4. use_llm_selector=False  → "all"                  (all concepts → filter → route → render)
```

New `_retrieve_precomputed_names()`:
```python
def _retrieve_precomputed_names(self, concept_mem, problem):
    names = self._selected_concepts.get(problem.uid)
    if not names:
        return RetrievalBundle(hint_text=None,
            metadata={"selector_mode": "precomputed_miss"})
    return self._apply_pipeline(
        concept_mem=concept_mem, selected_names=names,
        problem=problem, selector_mode="precomputed")
```

### Step 4: Refactor ps_selector to compose stages

Replace internal methods with composed objects:

```python
class PsSelectorRetriever:
    def __init__(self, ..., max_frequency=0.0, max_concepts_per_problem=0,
                 concept_frequency_file="", routing_strategy="none",
                 routing_max_hint_chars=0, ...):
        # Compose format-independent stages
        self._filter = ConceptFilter(
            max_frequency=max_frequency,
            max_concepts=max_concepts_per_problem,
            frequency_file=concept_frequency_file,
        )
        self._router = RetrievalRouter(
            strategy=routing_strategy,
            max_hint_chars=routing_max_hint_chars,
            frequencies=self._filter.frequencies,
        )
```

Then in `_apply_pipeline()`:
```python
# Before: self._filter_concepts(selected_names)
# After:  self._filter.filter(selected_names)

# Before: self._should_include_hints(filtered, hint_text)
# After:  self._router.should_include(filtered, hint_text)
```

Constructor signature stays the same (flat params) — backward compatible. But
internally, generic logic lives in reusable classes.

### Step 5: Update experiment configs

Three configs add `selected_concepts_file` so pipeline params are active:

```yaml
# concept_lcb_opt2_cues.yaml
memory_retriever:
  selected_concepts_file: data/.../selected_concepts.json
  render_mode: cues_only

# concept_lcb_opt1_filtered.yaml
memory_retriever:
  selected_concepts_file: data/.../selected_concepts.json
  max_frequency: 0.3
  max_concepts_per_problem: 3
  concept_frequency_file: data/.../concept_frequencies.json

# concept_lcb_opt123_composed.yaml
memory_retriever:
  selected_concepts_file: data/.../selected_concepts.json
  render_mode: cues_only
  max_frequency: 0.3
  max_concepts_per_problem: 3
  concept_frequency_file: data/.../concept_frequencies.json
  routing_strategy: selection_confidence
```

Baseline `concept_lcb_eval.yaml` unchanged (legacy rendered path).

### Step 6: Tests

New `tests/unit/test_retrieval_stages.py`:
- `test_concept_filter_frequency` — drops high-frequency names
- `test_concept_filter_max_count` — caps at N
- `test_concept_filter_noop` — pass-through when disabled
- `test_router_none` — always includes
- `test_router_confidence_all_generic` — skips when all high-frequency
- `test_router_hint_length` — skips when too long

New tests in `tests/unit/test_concept_ps.py`:
- `test_precomputed_names_through_pipeline` — pipeline active with selected_concepts_file
- `test_precomputed_names_with_filtering` — frequency filter applied
- `test_precomputed_names_priority` — names beats rendered
- `test_precomputed_names_miss` — unknown uid returns None
- `test_legacy_rendered_preserved` — existing behavior unchanged

### Verified Outcomes (API smoke tests, problem 3502)

| Config | Pipeline Active? | Prompt Size | Change |
|--------|-----------------|-------------|--------|
| `concept_lcb_eval` (baseline) | No (legacy rendered) | 6,027 bytes | — |
| `concept_lcb_opt2_cues` | Yes (cues_only) | 5,101 bytes | **-15.4%** |
| `concept_lcb_opt1_filtered` | Yes (freq+cap filter) | 5,509 bytes | **-8.6%** |

Baseline prompt contains the verbatim hint text from `prompt_info.json` — legacy
path is preserved exactly.

### Round 1 Verification (all passed)

1. `python -m pytest tests/unit/ -v` — 158 passed (137 original + 21 new)
2. `python scripts/parity/run_arc_default_parity_lock.py` — ARC parity holds
3. API smoke tests — differentiated prompt sizes confirmed (above)
4. Baseline parity — `prompt_info.json` hint appears verbatim in baseline prompt

### Files to Change

| File | Change |
|------|--------|
| `src/mem2/retrieval/__init__.py` | New package |
| `src/mem2/retrieval/filters.py` | New: ConceptFilter |
| `src/mem2/retrieval/routers.py` | New: RetrievalRouter |
| `src/mem2/branches/memory_retriever/ps_selector.py` | Compose Filter+Router, add selected_concepts_file |
| `configs/experiments/concept_lcb_opt*.yaml` | Add selected_concepts_file |
| `configs/options.yaml` | Add selected_concepts_file param |
| `configs/components.md` | Document selection modes, Filter, Router |
| `tests/unit/test_retrieval_stages.py` | New: ConceptFilter + RetrievalRouter tests |
| `tests/unit/test_concept_ps.py` | New: precomputed-names path tests |

---

## Round 2 Fixes: Protocol Completeness & Domain Validation

### Fix for Point 3: InferenceEngine Protocol Extended

**Before**: Runner used `getattr`/`hasattr` for `model`, `include_reselected_lessons`,
`set_retry_policy`, `prompt_options` — none on the protocol.

**After**: Added to `InferenceEngine` protocol in `contracts.py`:
```python
class InferenceEngine(Protocol):
    name: str
    model: str                              # NEW
    include_reselected_lessons: bool        # NEW
    def set_retry_policy(self, policy: Any) -> None: ...  # NEW
```

Runner now uses direct attribute access:
```python
# Before: getattr(self.components.inference_engine, "include_reselected_lessons", False)
# After:  self.components.inference_engine.include_reselected_lessons

# Before: getattr(self.components.inference_engine, "model", "")
# After:  self.components.inference_engine.model

# Before: if hasattr(ie, "set_retry_policy"): ie.set_retry_policy(...)
# After:  ie.set_retry_policy(...)
```

For `prompt_options` (ARC-specific, not on all IEs): replaced `getattr` on the
inference engine object with a config dict read — the config is already available
in `self.config`. No probing of implementation internals.

**Files changed**: `src/mem2/core/contracts.py`, `src/mem2/orchestrator/runner.py`

---

### Fix for Point 4: Unified async_retrieve

**Before**: Runner checked `hasattr(retriever, "async_retrieve")` for two code paths.
Sync path called `retriever.retrieve()`. Async path called `retriever.async_retrieve()`
with extra `provider` and `selector_model` args. `none` and `oe_topk` had no
`async_retrieve` and always went through the sync path.

**After**: Added `async_retrieve` to `MemoryRetriever` protocol:
```python
class MemoryRetriever(Protocol):
    name: str
    def retrieve(...) -> RetrievalBundle: ...
    async def async_retrieve(                     # NEW
        self, *, ctx, provider, memory, problem,
        previous_attempts, selector_model="",
    ) -> RetrievalBundle: ...
```

All 4 retrievers now implement `async_retrieve`:
- `none`: wraps `self.retrieve(...)`, ignores provider/selector_model
- `oe_topk`: wraps `self.retrieve(...)`, ignores provider/selector_model
- `oe_selector`: existing implementation (LLM-based selection)
- `ps_selector`: existing implementation (precomputed/LLM selection)

Runner always defers to `async_retrieve` — **zero `hasattr` checks remaining**:
```python
# Before: if hasattr(retriever, "async_retrieve"): ... else: ...
# After:  retrieval = await retriever.async_retrieve(ctx=..., provider=..., ...)
```

**Result**: `runner.py` has zero `getattr` and zero `hasattr` calls.

**Files changed**: `src/mem2/core/contracts.py`, `src/mem2/orchestrator/runner.py`,
`src/mem2/branches/memory_retriever/none.py`,
`src/mem2/branches/memory_retriever/oe_topk.py`

---

### Fix for Points 5 & 6: Domain Triple Validation

**Before**: No validation that benchmark, IE, evaluator, and feedback engine belong
to the same domain. Configuring `arc_agi` + `math_ps_solve` silently produced garbage.

**After**: Added `DOMAIN_NAME` class attribute to all 12 domain-specific components:

| Domain | Benchmark | InferenceEngine | Evaluator | FeedbackEngine |
|--------|-----------|----------------|-----------|----------------|
| `"arc"` | `arc_agi` | `python_transform_retry` | `arc_exec` | `gt_check` |
| `"math"` | `competition_math_ps` | `math_ps_solve` | `math_ps_exec` | `math_ps_gt` |
| `"code"` | `livecodebench` | `lcb_solve` | `lcb_exec` | `lcb_gt` |

New `_validate_domain_components()` in `wiring.py` checks all 4 share the same
`DOMAIN_NAME`. Uses `getattr(comp, "DOMAIN_NAME", None)` for backward compat —
components without the attribute are silently accepted. Mismatches raise
`ConfigurationError` at wiring time, before any data processing.

This also covers Point 6 (evaluator ↔ feedback engine detail format mismatch):
if `gt_check` (ARC) can never be paired with `math_ps_exec` (math), the detail
format incompatibility can never occur at runtime.

**Files changed**: 12 component files (DOMAIN_NAME added),
`src/mem2/orchestrator/wiring.py` (validation function)

---

### Point 9: Accepted

`oe_topk`/`oe_selector` reading `memory.payload["entries"]` is the OE equivalent
of `ConceptMemory.from_payload()`. The format is simple (flat list of dicts) and
the `SCHEMA_NAME`/`COMPATIBLE_SCHEMAS` validation already prevents mispairing.
Adding a deserialization layer would add complexity for minimal gain.

---

### Round 2 Verification (all passed)

1. `python -m pytest tests/unit/ -v` — **175 passed** (158 from round 1 + 17 new)
2. `python scripts/parity/run_arc_default_parity_lock.py` — ARC parity holds
3. `python -m mem2.cli.run --config configs/experiments/smoke_arc.yaml` — end-to-end pass
4. API smoke tests via `async_retrieve` — differentiated prompt sizes confirmed:

| Config | Mode | Hint Size | Prompt Size |
|--------|------|-----------|-------------|
| baseline | precomputed (legacy) | 4,121 | 6,344 bytes |
| opt2_cues | precomputed (pipeline) | 3,700 | 5,923 bytes |
| opt1_filtered | precomputed (pipeline) | 3,438 | 5,661 bytes |

5. Domain mismatch detection verified:
   `arc_agi` + `math_ps_solve` → `ConfigurationError: Domain mismatch`

### Round 2 Files Changed

| File | Change |
|------|--------|
| `src/mem2/core/contracts.py` | Added `model`, `include_reselected_lessons`, `set_retry_policy` to IE protocol; added `async_retrieve` to MR protocol |
| `src/mem2/orchestrator/runner.py` | Removed all `getattr`/`hasattr`; unified async path |
| `src/mem2/orchestrator/wiring.py` | Added `_validate_domain_components()` |
| `src/mem2/branches/memory_retriever/none.py` | Added `async_retrieve` |
| `src/mem2/branches/memory_retriever/oe_topk.py` | Added `async_retrieve` |
| `src/mem2/branches/benchmark/arc_agi.py` | Added `DOMAIN_NAME = "arc"` |
| `src/mem2/branches/benchmark/competition_math_ps.py` | Added `DOMAIN_NAME = "math"` |
| `src/mem2/branches/benchmark/livecodebench.py` | Added `DOMAIN_NAME = "code"` |
| `src/mem2/branches/inference_engine/python_transform_retry.py` | Added `DOMAIN_NAME = "arc"` |
| `src/mem2/branches/inference_engine/math_ps_solve.py` | Added `DOMAIN_NAME = "math"` |
| `src/mem2/branches/inference_engine/lcb_solve.py` | Added `DOMAIN_NAME = "code"` |
| `src/mem2/branches/evaluator/arc_exec.py` | Added `DOMAIN_NAME = "arc"` |
| `src/mem2/branches/evaluator/math_ps_exec.py` | Added `DOMAIN_NAME = "math"` |
| `src/mem2/branches/evaluator/lcb_exec.py` | Added `DOMAIN_NAME = "code"` |
| `src/mem2/branches/feedback_engine/gt_check.py` | Added `DOMAIN_NAME = "arc"` |
| `src/mem2/branches/feedback_engine/math_ps_gt.py` | Added `DOMAIN_NAME = "math"` |
| `src/mem2/branches/feedback_engine/lcb_gt.py` | Added `DOMAIN_NAME = "code"` |
| `tests/unit/test_wiring_validation.py` | New: 12 domain validation tests |
| `tests/unit/test_async_retrieve.py` | New: 5 async_retrieve tests |
