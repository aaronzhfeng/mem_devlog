# Devlog 24 — Config Validation: pipeline vs components

**Date**: 2026-02-23
**Prerequisite**: Devlog 22 (audit), Devlog 23 (coupling fixes)

## The Gap

The config has two sections that must agree but were not validated against each other:

```yaml
pipeline:
  inference_engine: python_transform_retry    # selects the CLASS

components:
  inference_engine:                           # provides CONSTRUCTOR ARGS
    model: qwen/qwen3-30b
    gen_cfg: {n: 1, temperature: 0.0}
    prompt_options:                            # only valid for python_transform_retry
      include_hint: true
```

`wiring.py` did:
```python
cls = INFERENCE_ENGINES[pipe["inference_engine"]]   # lookup class by name
kwargs = comp_cfg.get("inference_engine", {})        # grab kwargs dict
return cls(**kwargs)                                 # pray they match
```

No check that `kwargs` are valid for `cls`.

---

## How This Failed

### Silent absorption — wrong params ignored

```yaml
pipeline:
  inference_engine: math_ps_solve

components:
  inference_engine:
    model: qwen/qwen3-30b
    prompt_options:            # <-- math_ps_solve doesn't have this
      include_hint: true       #     but accepts **kwargs, so it vanishes
```

`MathPsSolveInferenceEngine.__init__` had `**kwargs` to absorb unknown keys.
The user thinks `include_hint` is active. It's not. No error, no warning.

### Stale params after pipeline swap

User changes `pipeline.inference_engine` from `python_transform_retry` to
`math_ps_solve` but forgets to update `components.inference_engine`. The old
`prompt_options`, `system_prompt_key`, etc. are silently absorbed.

### Config inheritance bleed-through

`base.yaml` defaults to ARC (`python_transform_retry` + `arc_exec`). Its
`components.inference_engine` includes `prompt_options: {...}` and
`components.evaluator` includes `require_all_tests: true`. When a math or LCB
config inherits via `_base_: ../base.yaml`, the `deep_merge` in the config
loader carries these ARC-specific keys into the domain config. The math/lcb
constructors silently absorbed them via `**kwargs`.

---

## Scope of the Problem

6 classes used `**kwargs`:

| Class | Component | Absorbed Keys |
|-------|-----------|---------------|
| `MathPsSolveInferenceEngine` | inference_engine | `prompt_options` from base |
| `LcbSolveInferenceEngine` | inference_engine | `prompt_options` from base |
| `MathPsExecutionEvaluator` | evaluator | `require_all_tests` from base |
| `LcbExecutionEvaluator` | evaluator | `require_all_tests` from base |
| `PsSelectorRetriever` | memory_retriever | various from inheritance |
| `ArcMemoPsMemoryBuilder` | memory_builder | `max_entries` from OE configs |

---

## Fix Implemented: Option A + C

### 1. `_build_component` validates kwargs via `inspect.signature`

```python
import inspect

def _build_component(registry, key, cfg):
    if key not in registry:
        known = ", ".join(sorted(registry.keys()))
        raise ConfigurationError(f"Unknown component '{key}'. Known: [{known}]")
    cls = registry[key]
    # Strip None values — YAML null means "unset this inherited key"
    kwargs = {k: v for k, v in cfg.items() if v is not None}
    # Validate kwargs against constructor signature
    sig = inspect.signature(cls.__init__)
    has_var_keyword = any(
        p.kind == inspect.Parameter.VAR_KEYWORD
        for p in sig.parameters.values()
    )
    if not has_var_keyword:
        accepted = {
            name for name, p in sig.parameters.items()
            if name != "self" and p.kind in (
                inspect.Parameter.POSITIONAL_OR_KEYWORD,
                inspect.Parameter.KEYWORD_ONLY,
            )
        }
        unknown = set(kwargs.keys()) - accepted
        if unknown:
            raise ConfigurationError(
                f"Unknown config params for '{key}': {sorted(unknown)}. "
                f"Accepted: {sorted(accepted)}"
            )
    return cls(**kwargs)
```

### 2. Removed `**kwargs` from all 6 constructors

Each class now explicitly lists every param it accepts. The constructor IS the
schema — single source of truth. No manual schema maintenance.

### 3. YAML `null` stripping handles config inheritance

`base.yaml` is the ARC default config. Math/LCB configs inherit via `_base_:`
and `deep_merge`. ARC-specific keys (`prompt_options`, `require_all_tests`)
bleed into the merged dict.

The fix: `_build_component` strips keys with `None` values before validation.
Domain configs neutralize inherited keys with `null`:

```yaml
# In a math config that inherits from base.yaml:
components:
  inference_engine:
    model: qwen/qwen-2.5-7b-instruct
    prompt_options: null        # <-- neutralize inherited ARC key
  evaluator:
    timeout_s: 10.0
    require_all_tests: null     # <-- neutralize inherited ARC key
```

- `prompt_options: null` → stripped → not passed to `math_ps_solve` → no error
- `prompt_options: {include_hint: true}` → NOT stripped → passed to `math_ps_solve` → `ConfigurationError` (correct!)

---

## Config Fixes

16 configs inherited ARC-specific keys from `base.yaml` without neutralizing
them. Added `prompt_options: null` and/or `require_all_tests: null`:

| Config | Added |
|--------|-------|
| `smoke_lcb.yaml` | `prompt_options: null`, `require_all_tests: null` |
| `baseline_lcb_eval.yaml` | `prompt_options: null`, `require_all_tests: null` |
| `baseline_lcb_v56_342_qwen.yaml` | `prompt_options: null`, `require_all_tests: null` |
| `baseline_math_eval.yaml` | `prompt_options: null`, `require_all_tests: null` |
| `build_lcb.yaml` | `prompt_options: null`, `require_all_tests: null` |
| `build_math.yaml` | `prompt_options: null`, `require_all_tests: null` |
| `concept_lcb_eval.yaml` | `prompt_options: null`, `require_all_tests: null` |
| `concept_math_eval.yaml` | `prompt_options: null`, `require_all_tests: null` |
| `memory_lcb_eval.yaml` | `prompt_options: null`, `require_all_tests: null` |
| `memory_math_eval.yaml` | `prompt_options: null`, `require_all_tests: null` |
| `recovery_lcb_10.yaml` | `prompt_options: null`, `require_all_tests: null` |
| `recovery_lcb_100_qwen.yaml` | `prompt_options: null`, `require_all_tests: null` |
| `recovery_lcb_v1_100_qwen.yaml` | `prompt_options: null`, `require_all_tests: null` |

3 more configs (`concept_lcb_opt*.yaml`) inherit from `concept_lcb_eval.yaml`
and were fixed transitively.

Configs that already had the nullifiers (`smoke_math_ps`, `recovery_math_*`,
`baseline_math_l5_*`) needed no changes.

---

## Pre-Existing Config Issues (Also Fixed)

The validation sweep surfaced pre-existing bugs in legacy configs:

**`arcmemo_arc_logic_parity_openrouter_mem_retry.yaml`** — `pipeline` had
`memory_retriever: oe_selector` but didn't set `memory_builder`, inheriting
`none` from base. `components.memory_builder` had OE params (`max_entries`,
`seed_lessons_file`, `seed_lessons_per_problem`). `NoneMemoryBuilder` has no
`__init__`, so construction would always fail.

**Fix**: Added `memory_builder: arcmemo_oe` to the pipeline section. This
cascades to 7 dependent configs (lockstep_replay, mem_retry_desc, 5x tmp_live*)
via `_base_:` inheritance.

**`arcmemo_arc_parity_baseline.yaml`** — `_base_` pointed to
`../arcmemo_arc_strict.yaml` but the file is in the same `configs/experiments/`
directory.

**Fix**: Changed to `./arcmemo_arc_strict.yaml`.

---

## Files Changed

| File | Change |
|------|--------|
| `src/mem2/orchestrator/wiring.py` | `_build_component`: null-strip + `inspect.signature` validation |
| `src/mem2/branches/inference_engine/math_ps_solve.py` | Removed `**kwargs` |
| `src/mem2/branches/inference_engine/lcb_solve.py` | Removed `**kwargs` |
| `src/mem2/branches/evaluator/math_ps_exec.py` | Removed `**kwargs` |
| `src/mem2/branches/evaluator/lcb_exec.py` | Removed `**kwargs` |
| `src/mem2/branches/memory_retriever/ps_selector.py` | Removed `**kwargs` |
| `src/mem2/branches/memory_builder/arcmemo_ps.py` | Removed `**kwargs` |
| `tests/unit/test_wiring_validation.py` | 12 new tests for param validation |
| 13 experiment configs | Added `prompt_options: null` and/or `require_all_tests: null` |
| `arcmemo_arc_logic_parity_openrouter_mem_retry.yaml` | Added `memory_builder: arcmemo_oe` to pipeline |
| `arcmemo_arc_parity_baseline.yaml` | Fixed `_base_` path |

---

## Verification

- **187 unit tests passed** (175 existing + 12 new config validation tests)
- **ARC parity: `offline parity reproducible: True`**
- **ARC smoke test**: passed
- **Config sweep**: 30/36 configs wire successfully. 6 remaining failures are
  all `API_KEY` (need OpenRouter credentials, not config bugs)
- **All 3 domains wired**: ARC, Math, LCB — each with baseline and concept configs
- **Validation catches real errors**:
  - `math_ps_solve` + `prompt_options: {include_hint: true}` → `ConfigurationError`
  - `arc_exec` + `nonexistent_param: true` → `ConfigurationError`
  - `lcb_exec` + `require_all_tests: null` → stripped, uses defaults (OK)

---

## What This Means Going Forward

### Adding a new component

The constructor IS the config schema. If a new inference engine accepts
`model`, `gen_cfg`, and `custom_param`:

```python
class MyNewIE:
    def __init__(self, model="", gen_cfg=None, custom_param=False):
        ...
```

The wiring automatically validates that only `model`, `gen_cfg`, `custom_param`
are passed. No `ACCEPTED_PARAMS` to maintain, no schema file to update.

### Swapping pipeline components

Changing `pipeline.inference_engine` from `python_transform_retry` to
`math_ps_solve` will now fail immediately if `components.inference_engine`
still has `prompt_options` — instead of silently absorbing it and producing
a run where the user thinks hints are active but they're not.

### Config inheritance

Use `null` to neutralize inherited keys that don't apply to the new class:

```yaml
_base_: ../base.yaml
pipeline:
  inference_engine: math_ps_solve    # <-- changed from ARC default
components:
  inference_engine:
    prompt_options: null              # <-- neutralize inherited ARC key
```
