# 00: ArcMemo — Complete Implementation Reference

Cross-reference of the paper (2509.04439) with the codebase (`/root/arc/arc_memo/`).
Purpose: prevent missing components when porting to mem2.

---

## Pipeline Overview

ArcMemo operates as a **cyclical inference-time learning loop** (Algorithm 1 in paper):

```
For each problem i in dataset D:
  1. MemRead(M, x_i)          → s_i      (select relevant concepts)
  2. LLM_Generate(x_i, s_i)   → y_i_hat  (solve with selected concepts)
  3. Every k problems:
     - GetFeedback(y_i_hat, y_i)          (verify via test cases)
     - MemWrite(M, x_i, y_i_hat, f_i)    (extract concepts from solved)
```

The PS (Program Synthesis) pipeline — which is what we port — has these **offline** stages:

```
Stage 1: Pseudocode generation     (solution code → pseudocode + summary)
Stage 2: Concept abstraction       (pseudocode → concept annotations)
Stage 3: Memory compression        (deduplicate cues & implementation notes)
Stage 4: Concept selection         (concept memory + puzzle → selected concept names)
Stage 5: Hint rendering            (selected concepts → hint text in prompt_info.json)
Stage 6: Evaluation                (puzzle + hints → solver → score → retry)
```

---

## Stage 1: Pseudocode Generation

**Purpose:** Convert solution code into pseudocode to prioritize high-level operations
over low-level implementation details.

**Paper (Section 3.3, line 308):**
> "We find that directly converting solutions into routines often leads to minor
> implementation details being recorded as memories as opposed to our intended
> abstract concepts."

**File:** `concept_mem/memory/v4/pseudocode.py`

**Prompt template** (loaded from `data/abstract_anno/op3/pseudocode_instr.txt`):
```
# Introduction
Consider a class of "ARC" puzzles where each puzzle has a hidden transformation
rule that maps input grids to output grids...

We are trying to learn from previous puzzle solutions to improve our puzzle solving
capabilities. Your task is to analyze a puzzle solution, rewrite it as pseudocode
that can more easily be abstracted into concepts, and finally write a one-liner
summary of the transformation rule.

# Instructions
Pseudocode:
- write the pseudocode translation inside <pseudocode> and </pseudocode> tags
- be concise without compromising correctness
- reuse function names/operations from the examples
- focus on broader ideas compared to implementation details
- prefer explicit attributes like .color/.colors/.shape/.height/.width/.size/.position

Summary:
- write a one-liner summary inside <summary> and </summary> tags

# Examples
{examples}

# Concepts Examples
{concepts}

# Your Puzzle Solution
{solution}
```

**Input/Output:**
- Input: solution Python code
- Output: `<pseudocode>...</pseudocode>` + `<summary>...</summary>` (parsed via markup tags)
- Model: configured via Hydra (typically GPT-4 class)

**Key function:** `generate_pseudocode(problems, solutions, example_annotations, ...)`

---

## Stage 2: Concept Abstraction

**Purpose:** Extract reusable concepts from pseudocode. Aware of existing concepts —
encourages reuse and revision over creating duplicates.

**Paper (Section 3.3, lines 310-315):**
> "recording new concepts and revising existing concepts along with their various fields"
> "Aware of existing concepts with a compressed form of memory included in context"
> "Encourages the model to reuse and revise existing concepts"

**File:** `concept_mem/memory/v4/abstract.py`

**Prompt template** (loaded from `data/abstract_anno/op3/concept_instr.txt`):
- Introduces ARC domain
- Defines concept types: routine (grid manipulation or intermediate) and structure (visual entities)
- Explains parameterization and functional programming philosophy
- Provides few-shot examples with pseudocode → concept annotations
- Includes compressed form of existing concept memory for context

**Concept schema** (`concept_mem/memory/v4/concept.py`):
```python
@dataclass
class Concept:
    name: str
    kind: str                          # "structure" or "routine"
    routine_subtype: str | None        # "grid manipulation", "intermediate operation", etc.
    output_typing: str | None          # e.g. "grid", "list", "bool"
    parameters: list[ParameterSpec]    # typed parameter list
    description: str | None
    cues: list[str]                    # relevance cues
    implementation: list[str]          # implementation notes
    used_in: list[str]                 # problem IDs
```

**Update/merge logic** (`Concept.update()` in concept.py):
When a concept already exists, it **merges** rather than replaces:
- `description`: keeps first non-null
- `output_typing`: keeps first non-null
- `parameters`: merges by name (deduped)
- `cues`: appends new, deduplicates via `dict.fromkeys()` (preserves order)
- `implementation`: same append + dedup logic
- `used_in`: appends problem ID

This is why cues/implementation lists **grow unboundedly** across problems — the
extraction stage only appends and deduplicates exact matches, it does NOT compress
semantically similar entries. That's Stage 3's job.

**Key function:** `generate_concepts_batch(problems, solutions, examples, concept_mem, ...)`

**Categories in memory** (`concept_mem/memory/v4/memory.py`):
Concepts are organized into four sections for rendering:
1. `structure` — visual entities in grids
2. `types` — (from kind field)
3. `grid manipulation` — routines that directly affect output grid (routine_subtype)
4. `other_routines` — everything else

---

## Stage 3: Memory Compression

**Purpose:** Deduplicate and synthesize redundant cues and implementation notes
that accumulated across multiple problems in Stage 2.

**Paper (Section 3.3 / Appendix C.1):**
> "Parameterization allows similar concepts to be represented compactly with
> variations abstracted into parameters."
> "A subtle benefit of this more structured formulation is that memory
> representation can be simply compressed omitting certain fields."

**File:** `notebooks/memory_compression.ipynb`

**Process:**
1. Load raw memory from extraction output (`memory.json`)
2. Find concepts that need compression: `len(used_in) > 1` AND (`len(cues) > 1` OR `len(implementation) > 1`)
   - In their run: **93 out of 270 concepts** needed compression
3. Send each concept to LLM with compression prompt
4. Parse YAML response, write compressed cues/implementation back
5. Save as `compressed_v1.json`

**Compression prompt** (full text):
```
# Introduction
[ARC domain context + concept types explanation + functional programming philosophy]

# Task
We allowed multiple passes to add to the cues and implementation notes lists, and
now we are looking to remove redundancy. Make sure to keep separate ideas in separate
entries, but remove duplicate entries in a list or if they are very similar and only
subtly different, try to synthesize into a single entry.

We expect you to output a fenced yaml markdown block that contains a re-written
version of the cues and implementation notes lists:
```yaml
cues:
  - first cue
  - second cue
implementation:
  - first implementation note
  - second implementation note
```

# Your Concept Annotation
```
{concept}
```
```

**Model:** `gpt-4.1-2025-04-14`, temperature 0.1, max_tokens 1024

**Result:** ARC concepts after compression: mean **2.2 cues**, **1.4 implementation** per concept.
Without compression (our math concepts): mean ~8 cues, ~5 implementation per concept.

**Output:** `data/memory/compressed_v1.json`

---

## Stage 4: Concept Selection

**Purpose:** Given a new puzzle and the full concept memory, select the most relevant
concepts. Two approaches in the codebase.

### 4a. Batch Selection (v4/select.py) — used for offline precomputation

**Paper (Section 3.4, PS Selection, lines 340-349):**
> "PS Selection instructs a reasoning model to systematically explore the problem:
> first identify initial concepts using relevance cue annotations, then attempt to
> 'fill in the details' by determining values or routines to populate these initial
> concepts' parameters using type annotations."

**File:** `concept_mem/memory/v4/select.py`

**How concept memory string is loaded (lines 141-147):**
```python
# From a PRE-RENDERED TEXT FILE, not from to_string()
mem_str = mem_str_path.read_text()
```

**Selection prompt template** (SELECT_PROMPT_TEMPLATE, lines 28-67):
```
# Introduction
Consider a class of "ARC" puzzles...

Your task is to analyze a puzzle's reference examples, examine a set of concepts
recorded from previously solved puzzles, and determine which concepts are relevant.

# Concepts from Previously Solved Puzzles
[Explains concept annotations: cues, implementation, output typing, parameters]
[Recommendations on approach: start with grid manipulation, use parameters, etc.]

{concepts}

# Instructions
- Investigate "visible" concepts first (structures, grid manipulation)
- Then investigate logic/criteria/intermediate routines
- Write final selection as yaml list of concept names
- Use exact concept names
```yaml
- line drawing
- intersection of lines
...
```

# Your Given Puzzle
{puzzle}
```

**Hint rendering after selection (lines 190-195):**
```python
sel_mem_str = concept_mem.to_string(
    concept_names=selection,
    skip_parameter_description=False,
    usage_threshold=0,
    show_other_concepts=True,      # <-- includes non-selected as name-only lists
)
prompt_info[pzid] = {"op3f_sel": {"hint": sel_mem_str}}
```

**What gets saved:** RAW concept string (NOT wrapped in hint template).
The hint template wrapping happens at eval time in `make_prompt()`.

**Storage format in prompt_info.json:**
```json
{
  "puzzle_id": {
    "op3f_sel": {
      "hint": "## structure concepts\n- concept: ..."
    }
  }
}
```

**Key detail:** `show_other_concepts=True` means ALL concepts appear in the hint —
selected ones get full detail, non-selected ones appear as name-only lists per section.
This is intentional for ARC where the full memory is ~138K chars and the solver model
(o4-mini) can handle it. For weaker models, this overwhelms.

### 4b. Long Chain-of-Thought Selection (selection/long_cot.py) — used at runtime

**File:** `concept_mem/selection/long_cot.py`

**Template** (CONCEPT_SELECTION_PROMPT_TEMPLATE):
```
[ARC_INTRO]

### Puzzle Grids
{puzzle_grids}

### Concepts
[SPECIAL_CONCEPT_CLASS_NOTE about guide objects and criteria]
{concepts}

### Instructions
Please identify the concepts most relevant to this puzzle by thinking through
possible solution. Output your selected list of concepts along with notes
summarizing what you tried, the corresponding results, and your observations.
```yaml
concepts:
- concept 1
- concept 2
notes: notes about what you observe/tried/concluded
```
- Be sure to have top level keys `concepts` and `notes`
- The purpose is a first attempt in a collaborative effort to solve the puzzle
- Future attempts will have access to your notes
- It is vital that your notes do not contain misleading information
```

**Difference from v4/select.py:**
| Aspect | v4/select.py | long_cot.py |
|--------|---|---|
| Output | YAML list of names only | YAML with concepts + detailed notes |
| Reasoning | No notes required | Detailed thought process required |
| Usage | Offline batch precomputation | Runtime with chain-of-thought |
| Follow-up | Hints used directly | Notes reused in subsequent attempts |

---

## Stage 5: Hint Rendering & Injection

### 5a. Hint Templates

**File:** `concept_mem/evaluation/prompts.py`

The codebase has **10 hint templates** for different experiments. The one used
for the PS pipeline is `HINT_TEMPLATE_OP3`:

```
### Concepts from Previously Solved Puzzles
We recorded concepts about structures and routines we observed in previously
solved puzzles. These concepts may or may not be relevant to this puzzle, but
they provide useful context to show examples of what structures may appear in
the grids, what operations may be used, and how they might be composed.
Concepts are annotated with fields like:
- cues: what to look for that might indicate this concept is relevant
- implementation: how this concept was implemented in past solution programs
- output typing: what the output of this routine is
- parameters: a list of parameters that describe ways the concept may vary
Recommendations:
- Grid manipulation routines are easier to spot (along with structures)
- Try to first identify grid manipulation operations, then investigate parameters
- Non-grid manipulation routines describe ways to set parameters
- Think about variations, novel recombinations, and completely new concepts
- These are only suggestions, use them as you see fit

{hints}
```

**Other notable templates:**
- `HINT_TEMPLATE_MIN`: just `### Hints\n{hints}` — minimal framing
- `HINT_TEMPLATE_SELECTED`: one-sentence "lessons we selected that may be relevant"
- `HINT_TEMPLATE_ALL`: full description with situation-suggestion format
- `HINT_TEMPLATE_CHEATSHEET_MIN`: "cheatsheet containing relevant strategies"

### 5b. Prompt Assembly

**File:** `concept_mem/evaluation/prompts.py`, function `make_prompt()` (lines 363-427)

**Full solver prompt structure:**
```
[ARC_INTRO]                       — domain introduction
[ICL_DEMO_SECTION]                — optional in-context examples
[PUZZLE_GRIDS]                    — formatted input/output grids
[INSTRUCTIONS]                    — code generation instructions
[CONCEPTS_SECTION]                — optional raw concept list
[DESCRIPTION]                     — optional VLM description
[HINT_BLOCK]                      — hint template wrapping selected concepts
[COMMON_LIB]                      — optional shared library code
```

**Critical detail — hint wrapping happens here, at eval time:**
```python
if hint:
    formatted_hint = HINT_TEMPLATES[hint_template_key].format(hints=hint)
else:
    formatted_hint = None
```

The `hint` parameter comes from `prompt_info.json` which stores RAW concept strings.
The template wrapping is applied once, at eval time. **NOT at selection time.**

### 5c. Prompt Builder

**File:** `concept_mem/evaluation/prompt_builder.py`

`PromptBuilder` loads `prompt_info.json` and routes to `make_prompt()`:
```python
def build_initial_prompts(self, problem):
    # Load hint from prompt_info
    variant_data = problem_data.get(problem.uid, {}).get(variant_key, {})
    hint = variant_data.get("hint", None)

    # Build prompt (hint template applied inside make_prompt)
    return make_prompt(
        problem=problem,
        hint=hint,
        hint_template_key=self.prompt_options.hint_template_key,
        ...
    )
```

---

## Stage 6: Evaluation

### 6a. Evaluation Runner

**File:** `concept_mem/evaluation/driver.py`

**Loop structure:**
```python
async def run(self, problems):
    for i in range(1, retry.max_passes + 1):
        if i == 1:
            await self.initial_solve_step(problems, output_dir)
        else:
            await self.retry_solving_step(problems, output_dir)
        self.compute_and_report_scores(iteration, output_dir)
```

**Initial solve:**
1. Run long-cot concept selection (if enabled)
2. Build initial prompts via `PromptBuilder`
3. Batch LLM generation
4. Parse code from completions
5. Score: execute code on train/test pairs

**Retry solve:**
1. Identify puzzles needing retry (`needs_retry(step)` checks train/test correctness)
2. Optionally **reselect concepts** based on description + previous attempt
3. Build retry prompt:
   ```
   [initial_prompt]
   ### Your Previous Response(s) and Outcomes
   [formatted error feedback]
   ### New Instructions
   Please reflect on the above issues and revise...
   ### Reselected Lessons          (optional, if reselection enabled)
   [new_concepts]
   ```
4. Batch LLM generation
5. Score new attempts

### 6b. Retry Policy

**File:** `concept_mem/evaluation/retry_policy.py`

```python
@dataclass
class RetryPolicy:
    max_passes: int = 3              # total attempts including first
    criterion: RetryCriterion        # TRAIN or TEST
    error_feedback: str = "all"      # "all" or "first" error shown
    num_feedback_passes: int = 1     # how many past attempts to include
    include_past_outcomes: bool      # show outcomes of earlier attempts
    reselect_concepts: bool          # re-select concepts on retry
    reselect_with_description: bool  # use VLM description for reselection
    reselect_with_prev_attempt: bool # include previous attempt in reselection
```

### 6c. Scoring

**File:** `concept_mem/evaluation/score_tree.py`

**Process:**
1. Parse Python code block from LLM completion
2. Execute `transform(input_grid)` in sandboxed process (with timeout)
3. Compare output grid to expected
4. Track per-pair results (train + test)

**Metrics:**
- `official_score`: oracle@k (if ANY of k candidates passes ALL test cases, full credit)
- `strict_score`: requires all training pairs correct too

### 6d. Code Execution

**File:** `concept_mem/utils/code_execution/exec.py`

- Uses `ProcessPoolExecutor` for sandboxed execution
- Blocks dangerous imports: `os, sys, subprocess, multiprocessing, pathlib`
- Configurable timeout per execution
- Returns `ExecutionResult(status, output, error, stdout, stderr)`

---

## OE vs PS Pipeline

The paper describes two memory formats:
- **OE (Open-Ended):** situation-suggestion pairs, minimal structure
- **PS (Program Synthesis):** typed/parameterized concepts with cues and implementation

**In the codebase, these are NOT separate code paths.** The same code handles both.
The difference is in:
- **Memory format:** different concept schemas (lesson_memory.py for OE, memory/v4/ for PS)
- **Selection method:** description-based for OE, reasoning-based for PS
- **Configuration:** different Hydra configs select different components

---

## Continual Learning

**File:** `concept_mem/evaluation/continual_driver.py`

Implements the full loop: Solve → Abstract → Select → Repeat.
Processes problems in batches of `continual_batch_size` (default 10).

**Paper (Section 3.5):**
> "Memory updates introduce a dependency on problem order. If solving problem i
> induces a memory update that enables problem j to be solved, then the system
> will have different performance if the evaluation set is ordered differently."

---

## Key File Map

### Extraction Pipeline
| File | Purpose |
|---|---|
| `memory/v4/pseudocode.py` | Stage 1: solution → pseudocode + summary |
| `memory/v4/abstract.py` | Stage 2: pseudocode → concept annotations |
| `memory/v4/concept.py` | Concept dataclass with update/merge logic |
| `memory/v4/memory.py` | ConceptMemory: storage, to_string(), save/load |
| `notebooks/memory_compression.ipynb` | Stage 3: LLM-based cue/impl deduplication |

### Selection & Retrieval Pipeline
| File | Purpose |
|---|---|
| `memory/v4/select.py` | Stage 4: offline batch concept selection |
| `selection/long_cot.py` | Alternative: runtime chain-of-thought selection |
| `selection/description/generate.py` | VLM puzzle description generation |
| `selection/description/select.py` | Description-based concept reselection |

### Evaluation Pipeline
| File | Purpose |
|---|---|
| `evaluation/prompts.py` | All prompt templates + make_prompt() + make_retry_prompt() |
| `evaluation/prompt_builder.py` | Routes config → prompt generation, loads prompt_info.json |
| `evaluation/driver.py` | Main eval loop: initial solve → retry → score |
| `evaluation/retry_policy.py` | Retry logic configuration |
| `evaluation/score_tree.py` | Code execution + scoring |
| `evaluation/solution_tree.py` | Data structures for tracking attempts |
| `evaluation/continual_driver.py` | Continual learning loop |

### Data & Utils
| File | Purpose |
|---|---|
| `data/arc_agi.py` | Load ARC problems from files/datasets |
| `data/barc_seed_processing.py` | BARC seed solution extraction |
| `utils/common.py` | File I/O, YAML/code block extraction |
| `utils/llm_job.py` | Batch LLM generation with logging |
| `utils/code_execution/exec.py` | Sandboxed Python execution |

### Data Files
| File | Purpose |
|---|---|
| `data/memory/compressed_v1.json` | Final concept memory (270 concepts, compressed) |
| `data/abstract_anno/op3/concept_instr.txt` | Abstraction prompt instructions |
| `data/abstract_anno/op3/pseudocode_instr.txt` | Pseudocode prompt instructions |
| `data/abstract_anno/op3/cue_impl_compressed.json` | Compressed annotations cache |

### Configuration
| File | Purpose |
|---|---|
| `configs/default.yaml` | Main config (data, model, generation, retry, prompts) |
| `configs/selection/default.yaml` | Selection config (model, mem_str_path, ensemble) |
| `configs/generation/gen_default.yaml` | Default gen: temp=0.3, max_tokens=1024, seed=88 |
| `configs/model/*.yaml` | Model configs (gpt41, o4_mini, deepseek, qwen, etc.) |

---

## What We Missed When Porting to mem2

| Component | arc_memo | mem2 status | Impact |
|---|---|---|---|
| **Pseudocode preprocessing** | Stage 1 in pipeline | Ported in `extract_concepts.py` | OK |
| **Concept abstraction** | Stage 2, with existing memory context | Ported | OK |
| **Memory compression** | Stage 3, LLM-based dedup of cues/impl | **MISSING** | Bloated concepts (mean 998 chars vs 718 for ARC) |
| **show_other_concepts=True** | Intentional for strong solver (o4-mini) | Used blindly for weak solver (7B) | 95% of prompt was hints, hurt performance |
| **Hint wrapping timing** | Raw in prompt_info, wrapped at eval time | Was double-wrapped | Fixed (devlog 16) |
| **Concept reselection on retry** | Optional in retry_policy | Not implemented | Missing retry enhancement |
| **VLM description for selection** | Used for OE selection | Not applicable for math/code | N/A |
| **Solution tree (multi-branch)** | Multiple prompt variants per puzzle | Single path | Simpler but less flexible |

---

## Models Used in arc_memo

| Task | Model | Config |
|---|---|---|
| Pseudocode generation | GPT-4 class (via Hydra) | temp=0.3, max_tokens=1024 |
| Concept abstraction | GPT-4 class (via Hydra) | temp=0.3, max_tokens=1024 |
| Memory compression | gpt-4.1-2025-04-14 | temp=0.1, max_tokens=1024 |
| Concept selection | GPT-4.1 (via Hydra) | temp=0.3, max_tokens=1024 |
| Puzzle solving | o4-mini-2025-04-16 | max_tokens=32000, reasoning_effort=medium |
| VLM descriptions | GPT-4o (multimodal) | varies |
| Concept reselection | GPT-4 class | temp=0.3, max_tokens=1024 |

---

## Key Design Principles (from paper)

1. **Parameterization & composition:** Concepts are parameterized with typed interfaces
   to promote reusability. Higher-order functions (routines as parameters) are encouraged.

2. **Abstraction over instances:** Store modular concepts (A, B, C, D, E separately)
   rather than fully composed rules (A+B+C together), making them easier to recognize
   and reassemble in new contexts.

3. **Separation of situation and suggestion:** Relevance cues help match concepts to
   new problems; implementation notes help apply them. These serve different phases
   of problem solving.

4. **Feedback requirement:** Only extract concepts from CORRECT solutions to avoid
   propagating mistakes.

5. **Compression matters:** Raw extraction accumulates redundancy. A dedicated
   compression pass is needed to keep concepts compact and useful.
