# Concept Extraction Pipeline for Math & LCB

## Context

The mem2 framework's math/code pipelines currently use a broken memory system (arcmemo_ps +
lesson_topk) that injects hardcoded hints like "preserve successful transformations" into every
prompt, hurting performance (-6 on math, -1 on LCB). The core gap is: there is no concept extraction
pipeline for math or code — the offline process that turns solved problems into PS-format typed
concepts (ConceptMemory JSON). This plan builds that extraction pipeline and produces concept files
for both domains.

## What We're Building

A standalone script that:
1. Reads build run artifacts (solved problems + correct solutions)
2. Calls an LLM to extract typed PS-format concepts from each solution
3. Merges concepts across problems (dedup by name, merge cues/implementation/used_in)
4. Outputs a ConceptMemory-compatible JSON file that concept_ps builder can load directly

## Files to Create

### 1. `scripts/extract_concepts.py` — CLI entry point

Simple CLI that orchestrates the extraction. Arguments:
- `--run-dir` — path to build run directory (e.g. `outputs/_runs/build_math/151900440f88/`)
- `--domain` — `math` or `code`
- `--model` — LLM model for extraction (e.g. `qwen/qwen3-coder-30b-a3b-instruct`)
- `--output` — output JSON path (default: `data/{domain}_concepts/extracted_v1.json`)
- `--max-tokens` — max tokens for extraction LLM (default: 4096)
- `--concurrency` — max concurrent LLM calls (default: 16)
- `--dry-run` — print prompts without calling LLM

Steps:
1. Load solved problems via `load_solved_problems()` from extraction module
2. Initialize `LLMPlusProviderClient` with `llmplus_openrouter` profile
3. Build extraction prompts per solved problem
4. Call LLM via `async_batch_generate()`
5. Parse YAML responses into concept annotations
6. Assemble `ConceptMemory` directly (bypassing `write_concept()` which rejects non-ARC kinds)
7. Save to JSON via `ConceptMemory.save_to_file()`
8. Print summary stats

### 2. `src/mem2/concepts/extraction.py` — Core extraction logic

Functions:

**`load_solved_problems(run_dir: Path) -> list[SolvedProblem]`**

- Reads `problems.json`, `attempts.jsonl`, `eval_records.jsonl`
- Joins on `problem_uid + attempt_idx` to find correct attempts
- For each correctly solved problem, returns `SolvedProblem(uid, problem_text, solution_code)`
- Math: `problem_text` from `problems[uid].metadata.problem_text`
- Code: `problem_text` from `problems[uid].metadata.question_content`

**`build_extraction_prompt(problem: SolvedProblem, domain: str) -> str`**

- Builds domain-specific prompt asking the LLM to analyze a solved problem and extract typed concepts
- Two domain templates: `MATH_EXTRACTION_PROMPT` and `CODE_EXTRACTION_PROMPT`
- Prompt structure:
  - Context: you're analyzing a solved {math/code} problem
  - The problem statement
  - The correct solution code
  - Instructions to produce YAML with:
    - `summary`: one-line summary of the solution approach
    - `pseudocode`: step-by-step pseudocode
    - `concepts`: list of concepts, each with `concept` (name), `kind` (organic — whatever fits),
      `description`, `parameters` (list of `{name, typing, description}`), `cues` (when to apply),
      `implementation` (how it was done here)
  - Few-shot example showing the expected YAML format
  - Explicit instruction: discover concept kinds organically (do NOT constrain to predefined categories)

**`parse_extraction_response(response: str) -> dict | None`**

- Extracts YAML block from LLM response (reuse `_YAML_BLOCK_RE` pattern from `concept_selector`)
- Parses YAML, validates structure
- Returns dict with `summary`, `pseudocode`, `concepts` list
- Returns `None` on parse failure (logged)

**`assemble_concept_memory(extractions: list[tuple[str, dict]]) -> ConceptMemory`**

- Takes list of `(problem_uid, parsed_extraction)` tuples
- For each extraction:
  - Records `ProblemSolution` with `summary` + `pseudocode`
  - For each concept annotation: either creates new `Concept` or merges into existing one via `Concept.update()`
- Bypasses `ConceptMemory.write_concept()` which has the hardcoded ARC kind filter (line 62: `kind not in {"structure", "routine"}`)
- Instead, directly constructs `Concept` objects and adds to `mem.concepts` dict and `mem.categories`
- Returns the assembled `ConceptMemory`

## Extraction Prompt Design

### Math domain template (`MATH_EXTRACTION_PROMPT`)

```
You are analyzing a correctly solved competition math problem to extract reusable problem-solving
concepts.

## Problem
{problem_text}

## Correct Solution
{solution_code}

## Task
Analyze this solution and extract the key mathematical concepts, techniques, and patterns used. For
each concept, provide structured annotations.

Output a YAML block with this structure:
```yaml
summary: <one-line summary of the solution approach>
pseudocode: |
  <step-by-step pseudocode of the solution logic>
concepts:
  - concept: <concept name - a short descriptive name>
    kind: <category - discover organically, e.g. "technique", "theorem", "identity", "counting
method", "algebraic manipulation", "number theory tool", etc.>
    description: <what this concept does or represents>
    parameters:
      - name: <parameter name>
        typing: <parameter type>
        description: <what this parameter controls>
    cues:
      - <when to consider using this concept - what problem features suggest it>
    implementation:
      - <how this concept was applied in this specific solution>

Guidelines:
- Extract 1-5 concepts per problem (only meaningful ones)
- Name concepts clearly and concisely (e.g. "modular arithmetic", "pigeonhole principle", "generating
  function")
- Discover concept kinds organically - use whatever category naturally fits
- Cues should describe problem features that suggest this concept is relevant
- Implementation notes should be specific to this solution
```

### Code domain template (`CODE_EXTRACTION_PROMPT`)

Similar structure but references competitive programming, algorithmic approaches, data structures,
implementation patterns.

## Key Design Decisions

### Bypass `write_concept()` kind filter
`ConceptMemory.write_concept()` at line 62 rejects kinds not in `{"structure", "routine"}`. Since we
want organic kind discovery, we bypass this entirely by directly constructing `Concept` objects:
```python
concept = Concept(name=name, kind=kind, ...)
concept.update(problem_uid, annotation)
mem.concepts[name] = concept
mem.categories[kind].append(name)
```

### Single-call extraction (not two-stage)

The ARC pipeline used two separate stages (solution → pseudocode, then pseudocode → concepts). For
simplicity, we do both in one LLM call — the prompt asks for summary, pseudocode, AND concepts
together. This reduces API calls by half and keeps context together. We can revisit if quality is
poor.

### No dedup pass initially

Skip LLM-assisted dedup for v1. Instead, rely on `Concept.update()` merge logic — if two problems
produce a concept with the exact same name, they'll be merged. Near-duplicates with different names
will remain separate. We can add dedup later if the concept list is too noisy.

### Model choice

Use the same models available via OpenRouter. Good default: `qwen/qwen3-coder-30b-a3b-instruct`
(already proven to work for code). For math extraction, could also use this model since it's stronger
than qwen2.5-7b.

## Existing Code to Reuse

| Component | Location | Usage |
|---|---|---|
| `Concept` dataclass | `src/mem2/concepts/data.py` | Direct construction + `.update()` for merging |
| `ParameterSpec` dataclass | `src/mem2/concepts/data.py` | Parameter construction |
| `ConceptMemory` | `src/mem2/concepts/memory.py` | Container; use `.save_to_file()` for output |
| `ProblemSolution` | `src/mem2/concepts/memory.py` | Store solution summaries |
| `LLMPlusProviderClient` | `src/mem2/providers/llmplus_client.py` | LLM calls via `.async_batch_generate()` |
| `_YAML_BLOCK_RE` pattern | `src/mem2/branches/memory_retriever/concept_selector.py` | YAML extraction regex |

## Data Flow

```
Build run dir
  ├── problems.json          → problem_text for each uid
  ├── attempts.jsonl         → solution code (completion field)
  └── eval_records.jsonl     → is_correct flag
         │
         ▼
  load_solved_problems() → list[SolvedProblem]
         │
         ▼
  build_extraction_prompt() × N → list[str] prompts
         │
         ▼
  async_batch_generate() → list[str] LLM responses
         │
         ▼
  parse_extraction_response() × N → list[dict] parsed YAML
         │
         ▼
  assemble_concept_memory() → ConceptMemory
         │
         ▼
  save_to_file() → data/{domain}_concepts/extracted_v1.json
```

## Output Format

The output JSON matches `ConceptMemory.save_to_file()` format, identical to
`data/arc_agi/concept_memory/compressed_v1.json`:

```json
{
  "concepts": {
    "concept name": {
      "name": "concept name",
      "kind": "technique",
      "routine_subtype": null,
      "output_typing": null,
      "parameters": [...],
      "description": "...",
      "cues": ["..."],
      "implementation": ["..."],
      "used_in": ["problem_uid_1", "problem_uid_2"]
    }
  },
  "solutions": {
    "problem_uid": {
      "problem_id": "problem_uid",
      "solution": "...",
      "summary": "...",
      "pseudocode": "..."
    }
  },
  "custom_types": {}
}
```

## Verification

1. Run extraction for math:
```bash
python scripts/extract_concepts.py \
  --run-dir outputs/_runs/build_math/151900440f88 \
  --domain math \
  --model qwen/qwen3-coder-30b-a3b-instruct \
  --output data/math_concepts/extracted_v1.json
```

2. Run extraction for code:
```bash
python scripts/extract_concepts.py \
  --run-dir outputs/_runs/build_lcb/5b254edab37a \
  --domain code \
  --model qwen/qwen3-coder-30b-a3b-instruct \
  --output data/lcb_concepts/extracted_v1.json
```

3. Validate output: Load the JSON and verify it can be read by `ConceptMemory.load_from_file()`:
```python
from mem2.concepts.memory import ConceptMemory
mem = ConceptMemory()
mem.load_from_file("data/math_concepts/extracted_v1.json")
print(f"Concepts: {len(mem.concepts)}, Solutions: {len(mem.solutions)}")
print(f"Kinds: {dict(mem.categories)}")
```

4. Spot-check: Print a few concepts to verify they look reasonable (have meaningful names, cues,
   implementation notes)

5. (Future) Wire into eval configs with `concept_ps` builder + `concept_selector` retriever and
   measure lift vs baseline
