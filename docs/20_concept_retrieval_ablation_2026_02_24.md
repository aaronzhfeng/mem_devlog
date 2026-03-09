# 25: Concept Retrieval Ablation — LCB & Math Results (2026-02-24)

## Context

Devlog 20 proposed three composable improvements to concept retrieval:
1. **Frequency filtering** — drop generic concepts selected >30% of the time, cap at 3 per problem
2. **Cues-only rendering** — render concept names + cues, omit implementation details
3. **Selection-confidence routing** — skip hints when only generic concepts were selected

Devlog 22–23 implemented these as config-driven features in `ps_selector`:
`max_frequency`, `max_concepts_per_problem`, `concept_frequency_file`,
`render_mode`, `routing_strategy`. Devlog 22 also added `selected_concepts_file`
so precomputed concept names flow through the filter/route/render pipeline at
runtime instead of using pre-rendered `prompt_info.json` hints.

This devlog reports ablation results across **both LCB and Math** benchmarks.

---

## Experiments Run

### LCB (100 problems, qwen3-coder-30b, 2 passes)

| Config | Score | vs Baseline | Helped | Hurt |
|--------|-------|-------------|--------|------|
| Baseline (no memory) | **33%** | — | — | — |
| Concept baseline (prompt_info.json) | **33%** | 0 | +5 | -5 |
| Composed (cues + filter + routing) | **34%** | +1 | +6 | -5 |
| Cues-only | **32%** | -1 | +7 | -8 |
| Filtered (max_freq=0.3, max_concepts=3) | **28%** | -5 | +5 | -10 |
| Relaxed filter (max_freq=0.5, max_concepts=5) | **32%** | -1 | +5 | -6 |

### Math (100 problems, qwen-2.5-7b, 2 passes)

| Config | Score | vs Baseline | Helped | Hurt |
|--------|-------|-------------|--------|------|
| Baseline (no memory) | **58%** | — | — | — |
| Cues-only (selected_concepts_file) | **58%** | 0 | +19 | -19 |
| Composed (cues + filter + routing) | **57%** | -1 | +17 | -18 |

Reference from prior session (Feb 21): concept baseline with prompt_info.json scored 65% vs baseline 63%.

---

## Key Findings

### 1. No concept config reliably beats baseline on either benchmark

Across 8 experimental configs (5 LCB + 3 Math), the best result is +1% (LCB
composed), the worst is -5% (LCB filtered). All are within noise given the
variance we observe.

### 2. High run-to-run variance dominates the signal

**Math cross-session variance**: Baseline scored 63% on Feb 19 and 58% on
Feb 24 — a 5-point swing. Of 100 problems, **35 changed outcome** between
the two baseline runs (20 regressed, 15 improved). This means any concept
config showing <5% delta cannot be distinguished from noise.

**LCB cross-session variance**: Baseline scored 34% (Feb 23 early run) and
33% (Feb 23 late run). 17/100 problems changed between runs.

### 3. Concept perturbation is symmetric — as many hurt as helped

Math cues-only perfectly illustrates this: +19 helped, -19 hurt, net zero.
The concepts are not providing a consistent directional signal — they're
randomly perturbating which problems the model solves. This suggests the
current concept content is not adding actionable information that the model
lacks.

### 4. Filtering makes things worse, not better

| Filter Setting | LCB Score |
|----------------|-----------|
| No filter | 33% (concept baseline) |
| Relaxed (max_freq=0.5, max_concepts=5) | 32% |
| Strict (max_freq=0.3, max_concepts=3) | 28% |

Stricter filtering monotonically decreases performance. This contradicts the
hypothesis from devlog 20 that generic concepts were the main problem.
Possible explanation: even generic concepts contribute some useful signal,
and removing them leaves too few concepts to provide any benefit.

### 5. Composed config (all three options) slightly outperforms individual options on LCB

| LCB Config | Score |
|------------|-------|
| Cues-only alone | 32% |
| Filtering alone | 28% |
| Composed (cues + filter + routing) | 34% |

The composed config is the only one that matches or beats baseline on LCB.
The routing gate may be saving some hurt cases by skipping hints when only
generic concepts are available. But at +1% vs baseline, this is not
statistically significant.

---

## Run-to-Run Variance Analysis

The high variance undermines confidence in *all* prior concept memory results,
including the +2% on math (65% vs 63%) reported in devlog 18. With 35/100
problems changing between baseline runs, a +2% signal is well within the
noise floor.

This is a structural problem with the evaluation methodology:
- **100 problems, 2 passes**: Small sample size with high per-problem variance
- **Non-deterministic model output**: Temperature > 0, different responses each run
- **Cache effects**: OpenRouter routing to different model instances

To get reliable signal, we would need either:
- **Many more evaluation runs** (e.g., 5+ baseline runs to estimate variance)
- **Much larger problem sets** (e.g., 500+ problems)
- **Per-problem paired testing** (same cache, same session, A/B per problem)

---

## Implications for Concept Memory

The ablation reveals a more fundamental issue than hint formatting: **the
concept content itself may not be adding information the model doesn't already
have.** The qwen models being evaluated are strong enough that concepts like
"Frequency Map" or "Modular Arithmetic" are already in their training data.
The concept memory system is essentially restating knowledge the model already
possesses.

For concept memory to provide genuine lift, concepts would need to be:
- **Novel to the model** — domain-specific patterns not in training data
- **Problem-specific** — mapping from problem features to solution strategy
  (not just listing relevant techniques)
- **Format-aware** — knowing that a problem needs I/O parsing vs algorithmic
  insight

---

## Bug Fix: Silent API Failures

During this session, discovered that `llmplus/client.py` silently swallowed
API errors (e.g., 403 rate limit) — `_request_completions` caught all
exceptions and returned `[]`, with only a `logger.error()` call going to a
NullHandler. This caused all experiments to complete with 0% accuracy (0
attempts) without any visible error message.

**Fix**: Added `warnings.warn(msg, stacklevel=2)` to both exception handlers
in `_request_completions`, ensuring API failures are always visible to the
user regardless of logging configuration.

---

## Files Changed

### New configs
- `configs/experiments/concept_lcb_opt1_relaxed.yaml` — Relaxed filtering (max_freq=0.5, max_concepts=5)
- `configs/experiments/concept_math_opt2_cues.yaml` — Math cues-only rendering
- `configs/experiments/concept_math_opt123_composed.yaml` — Math composed (all three options)

### Generated data
- `data/competition_math_nt_cp_l5/concept_memory/selection_v1/concept_frequencies.json` — Math concept frequency distribution (90 concepts)

### Bug fix
- `third_party/llm_wrapper/llmplus/client.py` — Added `warnings.warn()` for silent API errors

---

## Next Steps

1. **Assess variance properly**: Run 3-5 baseline runs on each benchmark to
   establish confidence intervals before further concept experiments.

2. **Reconsider concept granularity**: Current concepts are algorithm-level
   ("Dynamic Programming", "BFS"). These are too generic for strong models.
   Consider problem-archetype concepts that encode *when* to use which
   approach, not *what* the approach is.

3. **Focus on ARC where concepts may matter more**: ARC tasks require novel
   spatial reasoning that may not be in training data. The concept memory
   system might provide genuine lift there, unlike math/code where the model
   already knows standard techniques.
