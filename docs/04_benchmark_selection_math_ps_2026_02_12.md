# Benchmark Selection: Math-PS via competition_math (2026-02-12)

## Decision

Use the **Number Theory + Counting & Probability** integer-answer subset of `competition_math` (HuggingFace: `qwedsacf/competition_math`) as the first PS-format math benchmark for `mem2`.

## Rationale

### Why math-PS matters

ARC is a grid-transformation benchmark. To show the memory system generalizes, we need a second domain. The key constraint is **PS compatibility**: solutions must be executable code verified against ground-truth outputs, not open-ended answers or proofs.

### Benchmarks evaluated

| Benchmark | PS compatible? | Reason |
|---|---|---|
| LiveCodeBench | Yes (code) | Strong PS fit, but it's a *code* bench, not *math* |
| Karel | No | No pre-generated dataset; solutions in Karel DSL, not Python |
| competition_math | **Partially** | NT + C&P subsets are code-solvable; Geometry/Precalculus are not |
| MATH-500 | No | Same as competition_math but only 500 problems |
| miniF2F | No | Formal proof benchmark (Lean); no I/O pairs; 22% prove-style |
| IMOBench | No | IMO-level; answers are characterizations/functions; no code verifier |

### Feasibility pilot

Sampled 30 problems from NT + C&P integer-answer subset. **29/30 were cleanly code-solvable** via Python enumeration, modular arithmetic, combinatorial computation, or brute-force search. Zero required proof-style reasoning.

### Dataset numbers

| Subset | Count | Answer type | Verifier |
|---|---|---|---|
| Number Theory, integer answer | 1,254 | `int` | `solve() == answer` |
| Counting & Probability, integer answer | 773 | `int` | `solve() == answer` |
| **Total PS-math pilot pool** | **2,027** | `int` | Integer equality |

Fraction-answer C&P problems (472) can be added later with a fraction-aware verifier.

### Levels available

- Level 1–5 per subject, providing natural difficulty stratification
- Level 1–3: mostly direct computation/enumeration
- Level 4–5: requires insight but still code-solvable

## PS format mapping

| mem2 concept | Math-PS implementation |
|---|---|
| Problem | Math problem statement (LaTeX) |
| Solution code | Python function `solve()` returning an integer |
| Train pairs | Not applicable (no I/O examples) — problem statement serves as sole input |
| Test verification | Execute `solve()`, compare return value to ground-truth integer |
| Feedback | Execution error details or "returned X, expected Y" |
| PS lessons | "When you see modular arithmetic, try iterating over residues", "for divisibility, enumerate and filter", etc. |

### Key difference from ARC

ARC provides train I/O pairs within each problem. Math-PS does not — each problem is standalone with only the statement. This means:
- Initial prompt includes only the problem statement (no example grids)
- Feedback is "your code returned X but the answer is Y" (similar to ARC's output mismatch)
- Cross-problem memory transfer is the primary learning signal (lesson from problem A helps solve problem B)

## Implementation plan

New branch implementations (all additive, no existing code modified):

1. `branches/task_adapter/math_ps.py` — prompt template for `solve()` format
2. `branches/benchmark/competition_math_ps.py` — load NT+CP integer subset from HF dataset
3. `branches/evaluator/math_ps_exec.py` — execute `solve()`, integer comparison
4. `branches/feedback_engine/math_ps_gt.py` — execution error / wrong answer feedback

Reused from ARC:
- `trajectory_policy/single_path.py`
- `memory_builder/arcmemo_ps.py`
- `memory_retriever/lesson_topk.py` (or `arcmemo_selector.py`)
- `providers/*` (same LLM backend)
- `artifact_sink/json_local.py`

## Data source

- Local path: `/root/workspace/data/hf/qwedsacf__competition_math`
- Load with: `datasets.load_from_disk(...)`
- Filter: `type in ("Number Theory", "Counting & Probability")` and integer boxed answer
