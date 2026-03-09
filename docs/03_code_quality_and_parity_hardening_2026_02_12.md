# Code Quality and Parity Hardening (2026-02-12)

## Scope

Post-migration audit of `mem2` codebase focused on two concerns:
1. Design quality issues that create maintenance risk or mask bugs.
2. Parity reliability gaps that could allow silent behavioral drift from `arc_memo`.

All changes are strictly non-behavioral: no prompt construction, code extraction, evaluation logic, feedback formatting, or retry semantics were modified.

## Audit findings and actions taken

### 1) extract_python_block regex — VERIFIED, no fix needed

**Risk level:** HIGH (would silently change which completions produce valid code)

**Finding:** Compared `mem2/utils/code_execution.py` against `arc_memo/concept_mem/utils/common.py`.

Both use identical regexes:
- `r"```python\n(.*?)\n```"` with `re.DOTALL`
- `r"```\n(.*?)\n```"` fallback with `re.DOTALL`
- `.strip()` on the extracted group

The only difference is the return type (`(code, error)` tuple vs `code | None`), which is functionally equivalent for the evaluation path.

**Action:** No code change. Added unit tests that assert parity-specific edge cases (case sensitivity, fence format requirements).

### 2) PipelineComponents typed with Protocol classes

**Risk level:** None (type annotations only, no runtime enforcement)

**Finding:** `PipelineComponents` dataclass had all 10 fields typed as `Any`, defeating the purpose of the Protocol-based contract system in `core/contracts.py`.

**Action:** Changed field types from `Any` to their respective Protocol types (`TaskAdapter`, `BenchmarkAdapter`, `MemoryBuilder`, etc.). This enables static type checking at the wiring boundary without any runtime behavior change.

### 3) Deduplicated _run_pass_sequential / _run_pass_arc_batch

**Risk level:** None (methods were byte-identical except for a log string)

**Finding:** `runner.py` contained two copy-pasted ~70-line methods that differed only in their error log message (`"sequential mode"` vs `"arc_batch mode"`).

**Action:** Merged into a single `_run_pass` method. The execution mode is logged dynamically via `self.execution_mode`, producing the exact same strings. The `__init__` validation gate for supported execution modes is preserved.

### 4) Comparison script fixed to join by problem_uid

**Risk level:** MEDIUM (false parity reports if problem ordering differs)

**Finding:** `scripts/parity/compare_arc_memo_mem2_runs.py` compared prompts by positional index (`step_rows[i]`). If the two systems iterate problems in different orders, the script would compare prompts for different puzzles and produce false negatives.

**Action:** Rewrote to extract `problem_uid` from arc_memo's `metadata.json` entries and join prompts by UID. The report now includes `uid_match_rate`, `arc_only_uids`, and `mem2_only_uids` fields.

### 5) Cleaned up duplicate v1 files

**Risk level:** None (deleted files were unused shims)

**Finding:** Every branch had both a canonical file (`arc_agi.py`) and a 3-line re-export shim (`arc_agi_v1.py`). Similarly, 14 `_v1.yaml` config files duplicated their non-v1 counterparts. The registries already import from the canonical modules and provide `_v1` key aliases pointing to the same class.

**Action:** Removed 9 shim source files and 14 duplicate config files. Registry `_v1` aliases remain for backward compatibility with any configs using v1 names.

### 6) Added 53 unit tests for parity-critical path

**Risk level:** N/A (new test files only, no production code changed)

**Finding:** The test suite had only 1 smoke test. No regression coverage for the components that directly determine parity: code extraction, scoring, prompt building, feedback formatting, and retry policy.

**Action:** Added 4 test modules:
- `test_code_extraction.py` (10 tests) — regex behavior, edge cases, parity-specific assertions
- `test_scoring.py` (10 tests) — official and strict score calculations
- `test_prompt_building.py` (18 tests) — initial/retry prompt structure, hint handling, feedback embedding, `num_feedback_passes`, `error_feedback` modes
- `test_feedback.py` (4 tests) — correct/incorrect feedback, metadata structure consumed by retry prompts
- `test_retry_policy.py` (11 tests) — train/test/all criterion, validation, config parsing

### 7) Extracted LockstepReplayArtifacts to its own module

**Risk level:** None (pure code move, zero logic change)

**Finding:** `runner.py` was a 1089-line god-object containing the run loop, lockstep replay infrastructure (~280 lines including helpers), artifact writing, solution tree building, and driver logging.

**Action:** Moved `LockstepReplayArtifacts` and its 5 helper functions to `orchestrator/lockstep_replay.py`. Runner.py dropped to ~729 lines. Removed the now-unused `import json` from runner.

## Parity impact assessment

**None of these changes can affect parity.** The reasoning for each:

| Change | Why safe |
|---|---|
| Protocol types on PipelineComponents | Type annotations; not enforced at runtime |
| _run_pass dedup | Byte-identical methods merged; log string produced dynamically |
| Comparison script rewrite | Offline tooling; never imported by pipeline |
| v1 file removal | Shim re-exports deleted; registry aliases preserved |
| Unit tests | New files only |
| Lockstep extraction | Pure code move; zero logic change |

## Remaining known gaps (not addressed in this round)

- **No data-source fingerprinting** in frozen config (data_root recorded, file hashes not).
- **`MemoryBuilder.update` produces placeholder hints** ("preserve successful transformations" / "inspect failure mode") rather than distilled content. Safe for parity (seed lessons are used), but blocks online memory learning experiments.
- **Module-level `_PROBLEM_DATA_CACHE`** in `render.py` could cause subtle issues in multi-run scenarios.
- **`lesson_topk.py` line 25** uses `"\\n"` (escaped newline literal) instead of `"\n"` in hint_text join — worth verifying against arc_memo's equivalent if this retriever is used in parity runs.
