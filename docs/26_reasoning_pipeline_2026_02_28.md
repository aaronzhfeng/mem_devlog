# Devlog 26 — Reasoning-Based Math Pipeline & GPT-4.1/5-mini Setup

**Date:** 2026-02-28

## Motivation

Devlog 25 showed concept hints add marginal content signal on math (+1/5 oracle uplift from concepts, rest from trajectory diversity). Two root causes identified:

1. **Extraction quality** — generic concepts ("algorithm" with 99 cues) on broad datasets
2. **Code-as-intermediate-step** — forcing math solutions through `solve() -> int` is unnatural. Math reasoning is sequences of theorem applications, not Python programs

This devlog covers the pipeline changes to address both: switching to reasoning-based output for math, upgrading to GPT-4.1 (extraction/selection) + GPT-5-mini (inference), and the design philosophy behind these choices.

## Design Philosophy: Why PS Must Be Faithful to ArcMemo

The paper's main contribution is PS (concept memory with offline extraction → selection → hint injection). OE is the backup. ARC validated PS — the original arcmemo pipeline works there.

For PS to credibly generalize to math, the pipeline must be faithful to arcmemo's design:
- **Schema parity**: same Concept dataclass fields, same merge logic, same rendering
- **Pipeline shape**: same two-stage extraction (solution → pseudocode → concepts), same batched Stage 2 with growing concept repo, same selection → hint injection flow
- **Model tier**: GPT-4.1 for extraction/selection (matching arcmemo), strong reasoning model for inference

If we deviate from the original design and get a bad result, reviewers can blame implementation drift rather than PS's actual limitations. Schema alignment is the control variable.

## What Changed: Code → Reasoning

**Problem**: Math solutions aren't naturally code. The previous pipeline forced:
1. Model writes `def solve() -> int:` (unnatural translation)
2. Evaluator executes `solve()` and checks return value
3. Extraction takes model's code output through Stage 1 (code → pseudocode)

This means the model's actual mathematical reasoning is hidden inside code comments or lost entirely. The extraction pipeline can only see the code, not the reasoning.

**Solution**: New `math_reason` pipeline where the model reasons mathematically:
1. Model writes mathematical reasoning + `\boxed{N}` answer
2. Evaluator parses `\boxed{}` from text (no code execution)
3. Extraction can use the model's reasoning directly as input (`--stage1-mode passthrough`)

The PS architecture stays identical — only the inference format changes.

## New Components

### Inference Engine: `math_reason`
- File: `src/mem2/branches/inference_engine/math_reason.py`
- System prompt: "expert competition math solver ... clear mathematical reasoning"
- Asks for step-by-step reasoning with named theorems/techniques
- Final answer in `\boxed{N}` format
- Retry prompt: shows previous reasoning + "Incorrect" / "Answer Parsing Issue"
- Same constructor interface as `math_ps_solve` (model, gen_cfg, hints, retry params)

### Evaluator: `math_reason_eval`
- File: `src/mem2/branches/evaluator/math_reason_eval.py`
- Extracts last `\boxed{}` from model output via regex
- Parses integer (handles commas, negatives, whitespace)
- Three failure modes: no `\boxed{}` found, non-integer in box, wrong integer
- Same aggregate interface as `math_ps_exec`

### Feedback Engine: `math_reason_gt`
- File: `src/mem2/branches/feedback_engine/math_reason_gt.py`
- No execution errors possible — only "Answer Parsing Issue" or "Incorrect"
- No ground-truth leak (doesn't show expected answer)
- Parsing issue feedback tells model to use `\boxed{}` format

### Extraction Updates
- File: `src/mem2/concepts/extraction.py`
- New `_MATH_REASONING_PSEUDOCODE_PROMPT` for `--stage1-mode reasoning`
- `build_pseudocode_prompt()` accepts `stage1_mode` parameter
- `--stage1-mode passthrough`: model's reasoning goes directly as pseudocode to Stage 2 (no LLM call)
- `--stage1-mode reasoning`: lighter Stage 1 that summarizes mathematical reasoning into pseudocode
- `--stage1-mode code`: original behavior (translate Python code to pseudocode)

### Registry
- `math_reason` added to `INFERENCE_ENGINES`
- `math_reason_eval` added to `EVALUATORS`
- `math_reason_gt` added to `FEEDBACK_ENGINES`

## Experiment Configs

### `smoke_math_reason.yaml`
- Mock provider, 5 problems, for testing pipeline wiring

### `concept_math_reason_gpt5mini.yaml`
- Provider: `llmplus_openai` (direct OpenAI API)
- Inference model: `gpt-5-mini` (reasoning model, no temperature/top_p)
- Concept memory: `concept_memory_gpt41/extracted_v1.json` (to be built)
- Selection: `ps_selector` with default settings
- 2 passes with retry

## Model Setup

| Role | Model | Notes |
|------|-------|-------|
| Extraction (Stage 1+2) | gpt-4.1-2025-04-14 | Matching arcmemo |
| Selection | gpt-4.1-2025-04-14 | Matching arcmemo |
| Inference | gpt-5-mini | Reasoning model, replaces o4-mini |

GPT-5-mini registered in `model_registry.py` as reasoning model:
- `param_renaming`: `max_tokens` → `max_completion_tokens`
- `unsupported_kw`: `temperature`, `top_p` stripped before API call

## Prompt Improvements (v2, this session)

### Extraction Stage 1 (math)
- Added ICL example (inclusion-exclusion problem)
- Instructions emphasize naming theorems/techniques over describing Python operations

### Extraction Stage 2 (math + code)
- Anti-bloat "Concept Naming Rules" section with bad/good examples
- Fixed kind taxonomy: `theorem | technique | strategy | definition`
- ICL example (lattice path counting with full parameters)
- Cue quality guidelines (concrete & observable, not tautological)
- 2-4 concepts per problem cap
- `parameters` field explicitly requested

### Selection
- Actionability focus: "select only concepts that would genuinely help"
- Reasoning step: read problem → scan cues → ask "would this help?" → select 1-5
- Negative guidance: "do NOT select concepts just because they share a topic area"

### Hint Template
- Shorter framing, more actionable
- "adapt, combine, or ignore them as you see fit"

## Tests

24 new unit tests in `tests/unit/test_math_reason.py`:
- Evaluator: correct/wrong/missing/non-integer boxed, multiple boxed (takes last), negative, comma-separated, aggregate
- Feedback: correct, wrong (no leak), parsing issue
- Inference: prompt content, hints, retry, hints disabled
- Answer parsing: extract_boxed, parse_integer edge cases

Full suite: **278/278 passed** (24 new + 254 existing)

## Updated Tracking

`00_schema_alignment.tsv` updated with new INFERENCE MODE section tracking the reasoning pipeline components alongside the original code-based ones.

## Next Steps

1. **Build run with GPT-4.1**: Run 500 build problems with `math_reason` engine + GPT-4.1 to produce solved reasoning traces
2. **Extract concepts**: `--stage1-mode passthrough` with GPT-4.1, output to `concept_memory_gpt41/`
3. **Eval run with GPT-5-mini**: `concept_math_reason_gpt5mini.yaml` on 200 eval problems
4. **Baseline comparison**: same 200 eval problems, GPT-5-mini, no concepts
5. **Compare with Qwen-2.5-7B baselines** from devlog 25
