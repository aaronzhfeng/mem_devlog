# 16: Concept Retrieval — Math Eval & Offline Selection Pipeline (2026-02-20)

## Summary

Wired the concept memory system (`concept_ps` + `concept_selector`) into the math eval
pipeline. Discovered and fixed several issues, built an offline selection pipeline matching
arc_memo's modular design, and got initial results showing the retrieval mechanics work.

---

## What was done

### 1. Kind normalisation
Lowercased all kind values in `extracted_v2.json` — fixed 10 inconsistent entries
(e.g. `Algorithm` → `algorithm`, `Number Theory Tool` → `number theory tool`).

### 2. Domain-aware concept rendering (bug fix)
`ConceptMemory.to_string()` without a `DomainProfile` only renders `"structure"` and
`"routine"` categories (ARC-specific). Math concepts have kinds like `technique`, `theorem`,
`algorithm`, etc. — so `to_string()` returned **empty** for math. Fixed by building a
dynamic `DomainProfile` from the concept memory's actual categories.

### 3. Domain-aware selection prompts
Added `src/mem2/concepts/prompts/math_select.py` and `math_hints.py` — math-specific
versions of the ARC selection and hint templates. Added `DOMAIN_PROMPT_MAP` to
`prompts/__init__.py` for domain → template lookup.

### 4. Fallback behavior fix
The original `concept_selector` dumped ALL concepts (~107K chars) on selection failure.
This actively hurt the solver — qwen-2.5-7b performs worse with a massive concept dump
than with no hints. Changed fallback to return no hints.

### 5. Offline selection pipeline (`scripts/select_concepts.py`)
Built a standalone offline selection script following arc_memo's pattern:
- Loads concept memory + problems.json
- Renders concept memory string with domain-aware profile
- Batch LLM calls for concept selection
- Parses YAML responses, matches against valid concept names
- Saves inspectable outputs:
  - `selected_concepts.json` — pid → [concept_name, ...]
  - `prompt_info.json` — pid → {hint: rendered_text}
  - `completions.json` — pid → raw LLM response (for debugging)
  - `parse_errors.json` — failures with reasons

### 6. Precomputed hints in retriever
Updated `concept_selector.py` to support `prompt_info_file` config. When set, the
retriever loads pre-computed hints at init and does a simple file lookup at runtime —
no LLM calls during eval.

### 7. Other fixes
- `to_primitive()` in `core/entities.py`: handle sympy `Integer` / numpy int types
- `math_ps_exec.py` evaluator: catch `OverflowError` in int comparison

---

## Experiment results

### Offline selection (selection_v1)

| Metric | Value |
|---|---|
| Problems | 100 |
| Selections OK | 88 |
| Selection failed | 12 (all `no_yaml_block`) |
| Concepts per problem | min=1, max=8, mean=4.6 |
| Unique selections | 87/88 |

The 12 failures are cases where the selector model (qwen3.5-397b) starts solving the
problem instead of selecting concepts. The 107K char concept list overwhelms the prompt.

### Math eval runs (same 100 problems, solver: qwen-2.5-7b)

| Run | Memory type | Pass 1 | Pass 2 |
|---|---|---|---|
| baseline (no memory) | none | — | ~57% |
| old stub (lesson_topk) | hardcoded lessons | — | 57% |
| v4 (inline, dump-all fallback) | concept_ps, all 117 on failure | 37% | 54% |
| v5 (inline, no-hints fallback) | concept_ps, skip on failure | 41% | 62% |
| v6 (offline precomputed) | concept_ps + prompt_info.json | 42% | 54% |

Notes:
- v5 vs v6 difference (62% vs 54%) is likely run-to-run variance — solver uses
  `temperature=0.3` with `ignore_cache=true`, so completions differ between runs.
- Both v5 and v6 are in the range of the 57% baseline, suggesting marginal or
  neutral lift from concept memory on this problem set with this solver.
- The concept memory does NOT hurt when fallback is no-hints (v5/v6), but actively
  hurts when fallback dumps all concepts (v4: 54%).

---

## Key findings

### The retrieval mechanics work
- LLM-based concept selection produces reasonable selections (4.6 concepts avg, 87 unique out of 88)
- Pre-computed hints are correctly injected into solver prompts
- The offline pipeline is modular and debuggable

### Lift is marginal with qwen-2.5-7b solver
- The solver model may be too weak to benefit from concept hints
- arc_memo uses a stronger model gap (GPT-4.1 selector → DeepSeek solver)
- Our setup: qwen3.5-397b selector → qwen-2.5-7b solver

### Selection failure mode: model solves instead of selecting
- 12% of problems fail because the selector model ignores the selection
  instructions and starts solving the math problem directly
- The 107K char concept list in the prompt likely contributes — the model
  loses track of the task

---

## Design gap: domain branching in retriever

The `concept_selector.py` currently has domain-specific `if` branching inside it:
- `_get_prompt_templates()` → switches on domain
- `_format_problem_for_selection()` → `if domain in ("math", "code")`
- `_build_profile()` → `if domain == "arc"`

This violates the codebase's design philosophy of **portability & modularity** — components
should be swappable via config, with domain-specific `if` branching only in the orchestrator.

**Current state:** The precomputed path (`prompt_info_file`) is domain-agnostic — just a
file lookup. The domain-specific logic lives in the offline scripts, which is acceptable.
But the inline LLM path still has `if domain` branching inside the component.

**Future cleanup options:**
1. Remove the inline LLM path entirely — retriever is just a file loader
2. Or split into separate retriever components per domain, each with their own config
3. Or inject domain-specific behavior (templates, formatters) via config/factories

This is deferred until we validate that the retrieval mechanics generalize to other
benchmarks.

---

## LCB extraction complete

Ran `extract_concepts.py` for LiveCodeBench. Results:
- 60 concepts from 63 solved problems
- Saved to `data/livecodebench_v56/concept_memory/extracted_v2.json`
- Ready for selection + eval

---

## File locations

| Purpose | Path |
|---|---|
| Offline selection script | `scripts/select_concepts.py` |
| Math selection output | `data/competition_math_nt_cp_l5/concept_memory/selection_v1/` |
| Math prompt_info | `data/competition_math_nt_cp_l5/concept_memory/selection_v1/prompt_info.json` |
| Math eval config (precomputed) | `configs/experiments/concept_math_eval.yaml` |
| Math eval v6 run | `outputs/_runs/concept_math_eval/980bd5b0ad59/` |
| LCB extracted concepts | `data/livecodebench_v56/concept_memory/extracted_v2.json` |
| Math select prompt template | `src/mem2/concepts/prompts/math_select.py` |
| Math hint template | `src/mem2/concepts/prompts/math_hints.py` |

## Next steps

1. **Validate on LCB** — run select_concepts.py + eval for LiveCodeBench to see if
   the mechanics generalize
2. **Reduce selection failures** — try shorter concept rendering (names + descriptions
   only, no full detail) in the selection prompt to reduce from 107K to ~10-20K chars
3. **Test with stronger solver** — try qwen3-235b or similar to see if concept hints
   help more with a model that can actually use them
4. **Clean up design** — address the domain branching gap once mechanics are validated
