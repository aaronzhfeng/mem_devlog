# 20: LCB Concept Memory — Next Steps & Design Options (2026-02-23)

## Context

After porting the full concept memory pipeline to LiveCodeBench and fixing the
`exec()` evaluator bug, concepts are **neutral** on LCB (33% vs 34% baseline at
pass@2, within noise). Deep case study identified two failure mechanisms:

1. **Attention misdirection**: ~5K chars of algorithmic hints dilute the model's
   attention on retry, especially when the real failure is I/O format (not
   algorithm). The model focuses on algorithmic correctness instead of debugging
   execution issues.
2. **Overcomplication**: Generic concepts ("Frequency Map", "Dynamic Programming
   Running State") push the model toward premature optimizations that introduce
   bugs, when the simple brute-force approach works.

Three upstream levers can address this. Each maps to a modular extension point
in mem2's plugin architecture — implement as a new class, register by name,
swap via config.

---

## Option 1: Better Selection — Fewer, More Specific Concepts

### Problem

The concept selector floods prompts with generic concepts. `Linear Scan` is
selected for 78/100 problems, `Index Boundary Check` for 46/100. These provide
no discriminative signal but consume prompt space. The NEITHER group (61 unsolved
problems) receives the most concepts (5.2 avg) with the lowest specificity
(0.090).

### Approach

Improve the offline selection pipeline to produce fewer, more targeted concepts.

**A. Frequency-aware filtering**: After selection, drop concepts whose global
selection frequency exceeds a threshold (e.g., >30%). This removes near-universal
concepts that don't help distinguish problem types.

**B. Diversity-constrained selection**: Modify the selection prompt to request
a maximum of 3 concepts and explicitly instruct "only select concepts that are
specifically relevant — do not include general-purpose patterns."

**C. Specificity-weighted rendering**: Keep all selected concepts but render
high-frequency ones as just names (no cues/implementation), while rendering
rare/specific ones in full detail. This preserves signal while reducing token
count.

### Extension Point

**Offline**: Modify `scripts/select_concepts.py` — change the selection prompt
template, add post-processing filters, or adjust `to_string()` rendering flags.
The script already supports `--show-other-concepts` and custom `max_tokens`.

**Runtime**: Create a new retriever class (e.g., `FilteredConceptRetriever`) in
`src/mem2/branches/memory_retriever/`, register in
`src/mem2/registry/memory_retriever.py`, swap via config:

```yaml
pipeline:
  memory_retriever: filtered_concept_selector
components:
  memory_retriever:
    prompt_info_file: data/.../prompt_info.json
    max_frequency: 0.3        # Drop concepts selected >30% of the time
    max_concepts_per_problem: 3
```

### Expected Impact

Reduces average hint size from ~5K to ~2K chars. Removes the "noise floor" of
generic concepts. May improve the 2 overcomplication hurt cases (abc384_f,
abc396_c) where generic hints pushed toward wrong optimizations.

---

## Option 2: Shorter Hints — Leaner Rendering

### Problem

Concept hints average ~5K chars, adding +33% to retry prompts. The full
rendering includes cues, implementation patterns, and parameter descriptions
for every selected concept. Much of this is redundant for a strong model that
only needs a nudge, not a tutorial.

### Approach

Reduce hint verbosity while preserving the key signal.

**A. Name + description only**: Render only concept names and one-line
descriptions, omitting cues/implementation/parameters. Math eval showed this
was neutral (v8: 63% = baseline), but it was also not harmful — and it
drastically cuts token count (~700 chars avg vs ~4.4K).

**B. Cues only**: Render concept names + cues (the "when to use this" signal)
but omit implementation details. The model likely knows *how* to implement
standard algorithms — it just needs to know *which* to consider.

**C. Adaptive detail**: Full detail for rare/specific concepts (specificity >
threshold), name-only for common ones. Combines specificity filtering with
rendering control.

### Extension Point

**`ConceptMemory.to_string()`** already supports granular control via flags:
`skip_cues`, `skip_implementation`, `skip_parameters`,
`skip_parameter_description`, `include_description`. These can be set per-call.

**`DomainProfile`** in `src/mem2/concepts/domain.py` controls section ordering
and headers. A new profile variant could define leaner rendering.

**In the retriever**: The `_render_hint_text()` method in `concept_selector.py`
calls `to_string()` — override this in a subclass or add config flags:

```yaml
components:
  memory_retriever:
    render_mode: cues_only  # or: name_only, full, adaptive
```

### Expected Impact

Reduces hint overhead from +33% to +5-10%. Addresses the attention misdirection
issue by giving the model less to read. The math benchmark showed name-only was
neutral, so the risk of losing signal is low.

---

## Option 3: Router — Skip Concepts When Unhelpful

### Problem

Concepts are applied uniformly to all 100 problems. But the case study shows
they only genuinely help ~3 problems algorithmically while hurting ~2. For the
remaining 95, they're noise. A router could decide per-problem whether to
include hints, improving the hit rate.

### Constraint

The router must operate **pre-inference** using only information available before
seeing the model's output. It cannot use pass 1 results to inform pass 2
behavior — the 2-pass structure is for eval variance reduction only, not a
method mechanic.

### Approach

**A. Problem-feature router**: Use properties of the problem itself to decide.
Candidates:
- Problem length (short problems are often easy → skip concepts)
- Presence of starter code / class template (LeetCode-style → skip concepts,
  since the bottleneck is format not algorithm)
- Problem source (AtCoder vs LeetCode vs Codeforces — different formats)

**B. Selection-confidence router**: Use properties of the concept selection
output to decide. If the selector only found generic concepts (all with global
frequency >30%), skip hints entirely. If it found at least one specific concept
(frequency <10%), include hints.

**C. Hint-length router**: If the rendered hint exceeds a character budget
(e.g., 3K chars), truncate or skip. This is a soft version that limits
damage from long generic hints without fully removing concepts.

### Extension Point

Create a new retriever class (e.g., `RoutedConceptRetriever`) that wraps the
existing `ConceptSelectorRetriever` and adds a gating decision:

```python
class RoutedConceptRetriever:
    name = "routed_concept_selector"

    def __init__(self, routing_strategy="selection_confidence", **kwargs):
        self.inner = ConceptSelectorRetriever(**kwargs)
        self.routing_strategy = routing_strategy

    def retrieve(self, ctx, memory, problem, previous_attempts):
        bundle = self.inner.retrieve(ctx, memory, problem, previous_attempts)
        if self._should_skip(problem, bundle):
            return RetrievalBundle(
                problem_uid=problem.uid,
                hint_text=None,
                retrieved_items=[],
                metadata={"selector_mode": "routed_skip", **bundle.metadata},
            )
        return bundle
```

Register and swap via config:

```yaml
pipeline:
  memory_retriever: routed_concept_selector
components:
  memory_retriever:
    routing_strategy: selection_confidence
    min_specificity: 0.10
    prompt_info_file: data/.../prompt_info.json
```

### Expected Impact

Could eliminate the 3 I/O-format hurt cases (LeetCode-style problems would be
detected and skipped). The selection-confidence approach could also skip cases
where only generic concepts were found. But this requires validation — the
router's accuracy determines whether it helps or just adds another source of
error.

---

## Implementation Priority

| Option | Effort | Risk | Expected Lift | Dependencies |
|--------|--------|------|---------------|--------------|
| **2. Shorter hints** | Low | Low (name-only was neutral on math) | Small — reduces noise | None |
| **1. Better selection** | Medium | Low | Medium — removes generic flooding | Re-run selection script |
| **3. Router** | Medium | Medium (needs validation) | Highest ceiling | Needs feature engineering |

**Recommended order**: Start with **Option 2** (quick, low risk, validates
whether hint length is the bottleneck). Then **Option 1** (improves selection
quality). Then **Option 3** if the first two don't close the gap.

All three are composable — a router that uses lean-rendered, well-selected
concepts is the end state.

---

## Architecture Reference

All three options leverage mem2's modular plugin system:

| Extension Point | File | Swap Mechanism |
|----------------|------|---------------|
| New retriever class | `src/mem2/branches/memory_retriever/` | Register in `src/mem2/registry/memory_retriever.py`, set `pipeline.memory_retriever` in config |
| Rendering flags | `src/mem2/concepts/memory.py` (`to_string()`) | Pass flags from retriever config via `components.memory_retriever.*` |
| Domain profile | `src/mem2/concepts/domain.py` | Create new profile, use in retriever's `_build_profile()` |
| Selection prompt | `src/mem2/concepts/prompts/code_select.py` | Modify template, re-run `scripts/select_concepts.py` |
| Offline selection | `scripts/select_concepts.py` | Add post-processing filters, new `--strategy` flag |

No changes to the orchestrator, runner, or wiring logic are needed. Each option
is a leaf-node change that plugs into the existing pipeline.
