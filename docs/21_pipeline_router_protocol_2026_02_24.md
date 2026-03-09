# 26: Pipeline-Level Router Protocol (2026-02-24)

## Context

Devlog 25's ablation showed concept hints help and hurt problems in roughly
equal measure. The mechanism of harm is **semantic** — hints push the model
toward wrong algorithms or verbose error-prone code. Numeric thresholds
(concept count, hint length) correlate with harm but overlap too much for clean
separation (devlog 25, finding #4: stricter filtering monotonically decreases
performance).

The existing routing logic lives inside `ps_selector` as component-level params
(`routing_strategy`, `routing_max_hint_chars`, etc.). This couples routing
decisions to a single retriever implementation and limits experimentation.

This devlog documents the **Router protocol** — a first-class pipeline
component that sits between retrieval and inference, deciding *which* retrieved
hints to keep.

---

## Design

### Data Flow

```
MemoryRetriever.async_retrieve()  →  RetrievalBundle (always has hint_text)
                                          ↓
Router.route()                    →  RetrievalBundle (filtered)
                                          ↓
InferenceEngine.initial_attempt() ←  receives final RetrievalBundle
```

The router call is inserted in `runner.py::_run_inference_job()`, after
retrieval completes and before the retry/initial branching logic. It runs on
every job — initial and retry — regardless of how the retrieval was obtained.

### Protocol

```python
class Router(Protocol):
    name: str

    async def route(
        self,
        *,
        ctx: RunContext,
        provider: ProviderClient,
        problem: ProblemSpec,
        retrieval: RetrievalBundle,
    ) -> RetrievalBundle: ...
```

Returns a `RetrievalBundle` — either passed through, partially filtered, or
with `hint_text=None`. The `provider` param enables LLM-based routing; other
implementations ignore it.

### Per-Item Filtering

Both the LLM and NLI routers operate at the **individual hint level**, not
as a binary keep/discard gate on the entire bundle. This is the key design
difference from the component-level routing in `ps_selector`.

Per-item text extraction handles both retriever formats:
- **oe_selector items**: each item has a `hint` field — used directly.
- **ps_selector items**: items are `{"concept": name}` — the rendered
  `hint_text` is split on `- concept: {name}` boundaries to recover
  per-concept text blocks.

Shared logic lives in `src/mem2/branches/router/_items.py`:
- `extract_problem_text(problem, domain)` — domain-aware text extraction
- `split_concepts_from_hint(hint_text, names)` — splits rendered hint_text
  into per-concept blocks
- `extract_item_texts(items, retrieval)` — unified extraction for both formats

---

## Implementations

### `none` — Pass-through (default)

Returns the input `RetrievalBundle` unchanged. Default when `pipeline.router`
is absent from config. No constructor params.

### `threshold` — Rule-based composite gating

Wraps the existing `RetrievalRouter` from `src/mem2/retrieval/routers.py`.
Operates on the whole bundle (not per-item). Reads `selected_names` and
`pre_filter_count` from `retrieval.metadata` and delegates to
`RetrievalRouter.should_include()`.

Params: `strategy`, `frequency_threshold`, `max_hint_chars`,
`max_concept_count`, `max_pre_filter_count`, `concept_frequency_file`.

### `llm` — LLM-based per-item filtering

One LLM call per problem. Presents all items as a numbered list:

```
Problem: {problem_text}

Proposed hints:
1. [dp] - concept: dp\n  description: dynamic programming...
2. [greedy] - concept: greedy\n  description: greedy algorithm...

Which of the above hints are directly relevant to solving this problem?
Return ONLY the numbers of the relevant hints as a comma-separated list, e.g. "1, 3, 5".
If none are relevant, return "NONE".
```

Parses comma-separated numbers from the response. "NONE" drops all hints.
Unparseable responses keep all (fail-open).

Params: `model`, `gen_cfg` (default `{n:1, temperature:0, max_tokens:256}`),
`domain`.

Metadata: `routing_model`, `routing_prompt`, `routing_completion`,
`routing_included`, `routing_included_items`, `routing_excluded_items`.
On parse failure: `routing_parse_failure: true`.

### `nli` — Cross-encoder NLI per-item filtering

Scores entailment between problem text and each item's text using a
cross-encoder. Items below the entailment threshold are dropped.

Cross-encoder is loaded lazily on first call (avoids import cost when not
used). Uses softmax over 3-class logits (contradiction/neutral/entailment),
checks index 2 against the threshold.

Params: `model_name` (default `cross-encoder/nli-deberta-v3-base`),
`entailment_threshold` (default 0.5), `domain`, `device`.

Metadata: `routing_nli_scores` (per-item dict), `routing_included_items`,
`routing_excluded_items`, `routing_included`.

---

## Integration

### Wiring

Follows the standard Protocol → Registry → Wiring pattern:

| Layer | File | Change |
|-------|------|--------|
| Protocol | `src/mem2/core/contracts.py` | Added `Router` protocol |
| Implementations | `src/mem2/branches/router/` | `none.py`, `threshold.py`, `llm.py`, `nli.py`, `_items.py` |
| Registry | `src/mem2/registry/router.py` | `ROUTERS` dict mapping names to classes |
| Wiring | `src/mem2/orchestrator/wiring.py` | `router` field on `PipelineComponents`, `pipe.get("router", "none")` default |
| Runner | `src/mem2/orchestrator/runner.py` | Router call after retrieval, before inference |
| Config | `configs/base.yaml` | `router: none` in pipeline section |

### Backward Compatibility

- `pipeline.router` defaults to `"none"` via `pipe.get("router", "none")`
- All existing configs work unchanged — no `router:` key needed
- `ps_selector`'s internal routing params remain functional as an "inner gate"
- When using a pipeline router, set `routing_strategy: none` in `ps_selector`
  to avoid double-gating

### Config Example

```yaml
pipeline:
  router: nli
components:
  router:
    model_name: cross-encoder/nli-deberta-v3-base
    entailment_threshold: 0.4
    domain: code
```

---

## Files Changed

| File | Action |
|------|--------|
| `src/mem2/core/contracts.py` | Modified — added `Router` protocol |
| `src/mem2/branches/router/__init__.py` | Created |
| `src/mem2/branches/router/_items.py` | Created — shared per-item extraction helpers |
| `src/mem2/branches/router/none.py` | Created |
| `src/mem2/branches/router/threshold.py` | Created |
| `src/mem2/branches/router/llm.py` | Created |
| `src/mem2/branches/router/nli.py` | Created |
| `src/mem2/registry/router.py` | Created |
| `src/mem2/orchestrator/wiring.py` | Modified — router field + wiring |
| `src/mem2/orchestrator/runner.py` | Modified — router call insertion |
| `configs/base.yaml` | Modified — `router: none` default |
| `configs/components.md` | Modified — Router section added |
| `tests/unit/test_router.py` | Created — 44 tests |
| `tests/unit/test_wiring_validation.py` | Modified — router default test |
| `scripts/route_concepts.py` | Created — offline routing script |

---

## Test Coverage

253 unit tests passing (44 new + 209 existing, zero regressions).

New test classes:
- `TestNoneRouter` — pass-through, metadata unchanged
- `TestThresholdRouter` — delegated gating, metadata propagation, concept count
  skip, hint length skip
- `TestLlmRouter` — ps/oe item filtering, NONE response, parse failure
  fallback, metadata, edge cases
- `TestNliRouter` — ps/oe per-item scoring, threshold gating, lazy loading,
  score metadata, edge cases
- `TestParseSelection` — LLM response parsing (numbers, NONE, out-of-range,
  parse failures)
- `TestSplitConceptsFromHint` — concept block extraction, missing concepts,
  section header boundaries
- `TestExtractItemTexts` — oe items, ps items, empty items
- `TestRouterWiring` — registry, default when key absent, explicit config

---

## Relationship to ps_selector Internal Routing

The pipeline Router is the **outer gate**; `ps_selector`'s `routing_strategy`
is the **inner gate**. They serve different roles:

| | ps_selector routing | Pipeline Router |
|---|---|---|
| Scope | Inside one retriever | Between retrieval and inference |
| Operates on | Concept names + metadata | Full RetrievalBundle |
| Granularity | Binary (whole bundle) | Per-item filtering |
| Swappable | Config params only | Different implementations |
| Access to | Concept frequencies, names | Problem text, provider |

When using a pipeline Router, disable the inner gate:
```yaml
components:
  memory_retriever:
    routing_strategy: none   # disable inner gate
  router:
    entailment_threshold: 0.4  # outer gate handles filtering
```

---

## Offline Routing Script

### `scripts/route_concepts.py`

Stage 3 in the modular pipeline:
```
extract_concepts.py → select_concepts.py → route_concepts.py → eval
```

Takes the output of `select_concepts.py` (selected_concepts.json) and runs a
Router (NLI or LLM) over each problem's rendered hints to filter which concepts
to keep. Produces a new selection directory usable directly by `ps_selector`.

### Usage

```bash
# NLI routing
python scripts/route_concepts.py \
    --concept-memory data/livecodebench_v56/concept_memory/extracted_v2.json \
    --selected-concepts data/livecodebench_v56/concept_memory/selection_v2/selected_concepts.json \
    --problems outputs/_runs/build_lcb/5b254edab37a/problems.json \
    --domain code \
    --router nli \
    --entailment-threshold 0.4
# → data/livecodebench_v56/concept_memory/routed_nli_nli-deberta-v3-base/

# LLM routing
python scripts/route_concepts.py \
    --concept-memory data/livecodebench_v56/concept_memory/extracted_v2.json \
    --selected-concepts data/livecodebench_v56/concept_memory/selection_v2/selected_concepts.json \
    --problems outputs/_runs/build_lcb/5b254edab37a/problems.json \
    --domain code \
    --router llm \
    --model qwen/qwen3-coder-30b-a3b-instruct
# → data/livecodebench_v56/concept_memory/routed_llm_qwen3-coder-30b-a3b-instruct/
```

Output dir is auto-generated as `routed_<type>_<model>/` alongside the source
selection directory. Override with `--output-dir` if needed.

### Directory Layout

```
data/livecodebench_v56/concept_memory/
├── extracted_v2.json                          ← extract_concepts.py
├── selection_v2/                              ← select_concepts.py
│   ├── selected_concepts.json
│   └── prompt_info.json
├── routed_nli_nli-deberta-v3-base/            ← route_concepts.py (NLI)
│   ├── selected_concepts.json
│   ├── prompt_info.json
│   ├── routing_scores.json
│   ├── routing_summary.json
│   └── concept_frequencies.json
└── routed_llm_qwen3-coder-30b-a3b-instruct/  ← route_concepts.py (LLM)
    └── ...
```

### Process

1. Loads concept memory + precomputed selections + problems
2. Renders each problem's hints (same logic as `ps_selector`)
3. Builds `RetrievalBundle` objects mimicking `ps_selector` output
4. Runs the Router (NLI or LLM) over each bundle
5. Extracts surviving concept names, re-renders filtered hints
6. Saves all outputs to disk

### Output Files

| File | Content |
|------|---------|
| `selected_concepts.json` | pid → [filtered concept names] |
| `prompt_info.json` | pid → {hint: re-rendered text} |
| `routing_scores.json` | pid → per-item NLI scores or LLM completions |
| `routing_summary.json` | Aggregate statistics |
| `concept_frequencies.json` | concept → frequency in filtered set |

### Integration with `ps_selector`

The filtered output plugs directly into the evaluation pipeline:
```yaml
components:
  memory_retriever:
    selected_concepts_file: data/livecodebench_v56/concept_memory/routed_nli_nli-deberta-v3-base/selected_concepts.json
    routing_strategy: none  # disable inner gate — filtering already done
```

Or use the pre-rendered hints:
```yaml
components:
  memory_retriever:
    prompt_info_file: data/livecodebench_v56/concept_memory/routed_nli_nli-deberta-v3-base/prompt_info.json
```

### Validation Run

NLI routing on 30 LCB problems (CPU, threshold=0.4):
- 91% include rate (141 items kept, 14 dropped)
- Concepts per problem: 5.2 → 4.7
- 29/30 problems retained at least one hint
- Clear score separation: relevant concepts score 0.9+ entailment,
  irrelevant concepts score <0.2

---

## Next Steps

### 1. Evaluate NLI router on LCB

Run the NLI router with varying thresholds (0.3, 0.4, 0.5) on the full LCB
problem set. Compare per-problem outcomes against devlog 25 baselines. The
per-item scores from `routing_scores.json` will show whether entailment
separates helpful from harmful hints better than frequency-based filtering.

### 2. Evaluate LLM router on LCB

Same evaluation with the LLM router. Compare cost (one lightweight LLM call
per problem) against quality of filtering. The `routing_prompt` and
`routing_completion` in `routing_scores.json` enable post-hoc analysis of
why the LLM kept or dropped each hint.
