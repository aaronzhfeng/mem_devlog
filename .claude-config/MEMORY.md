# Memory Index

## Project State
- Working dir: `/root/arc/mem2/`
- Devlog repo: `/root/arc/mem_devlog/` (github: aaronzhfeng/mem_devlog)
- Active benchmark: competition_math_all_l5 (200 eval, 500 build)
- Current solver model: qwen3.5-flash-02-23 (via OpenRouter)
- Extraction/selection model: qwen3.5-flash-02-23
- API keys: in `/root/arc/mem2/.env` (gitignored); `.env.example` has placeholders

## Fast Iteration Experiment (2026-03-07) — devlog 29

### Setup
- 20-problem "fruit fly" subsets (Build + Eval) for rapid prompt iteration
- `--include-ids` and `--include-ids-file` flags added to extract_concepts.py
- Extraction prompt v3a: anti-leakage instructions, abstract implementation
- Code prompt: anti-backtick + anti-leakage

### Leakage Fix
- Math: 76% → 0% source-specific leakage
- LCB: was clean, remains clean

### Results (qwen3.5-flash, n=1, 2 passes, 2 seeds)
| Domain | Baseline | v3a Concept | v3b Concept | Best |
|--------|----------|------------|------------|------|
| Math   | 19.0/20  | 19.0/20    | **20.0/20**| v3b  |
| LCB    | 16.0/20  | **18.5/20**| 16.0/20    | v3a  |

- v3a: best general variant (works for both domains)
- v3b (no implementation/parameters): better for math, equal to baseline for LCB
- LCB needs procedural details; math names alone are sufficient
- Zero average concept damage (was -7 hurts in m3 with leaky concepts)
- Retry recovery: concept 6/6 (s42) vs baseline 2/5 for LCB
- v3a prompt reverted as default (best general)

### Key files
- `data/competition_math_all_l5/fast_iter/` — math build/eval sets, extracted/selected
- `data/livecodebench_all/fast_iter/` — LCB build/eval sets
- `configs/experiments/fast_iter/` — ~20 configs (various selector/solver combos)

## Two-Tier Rendering (2026-03-08) — devlog 30

### `selector_render_mode` implementation
- Added to `ps_selector.py` and `select_concepts.py` (`--selector-render-mode`)
- Controls what fields selector sees (full/cues_only/name_only)
- `render_mode` controls solver hint (unchanged)
- Default: `full` (backward compatible)

### Optimal domain configs
| Domain | Selector | Solver | Mean |
|--------|----------|--------|------|
| Math | cues_only | cues_only or full | **20.0/20** |
| LCB | full | full | **18.5/20** |

### Full math matrix
| Selector | Solver | Mean |
|----------|--------|------|
| baseline | baseline | 19.0 |
| full | full | 19.0 |
| **cues_only** | **full** | **20.0** |
| name_only | full | 19.0 |
| **cues_only** | **cues_only** | **20.0** |

### Full LCB matrix
| Selector | Solver | Mean |
|----------|--------|------|
| baseline | baseline | 16.0 |
| **full** | **full** | **18.5** |
| cues_only | full | 17.5 |
| full | cues_only | *14.5* (hurts!) |

### v3c Parameterization Enforcement — REVERTED
- Made `parameters` required, added "parameterization over specificity" instructions
- Math v3c: 19.0 (down from v3a cues_only 20.0)
- LCB v3c: 17.0 (down from v3a full 18.5)
- Root cause: forced parameterization strips useful specificity from cues
- Extraction prompt reverted to v3a

### Key insight
- Math is name-driven: concept names alone sufficient for solver
- Code is procedure-driven: needs full implementation details everywhere
- Removing info from LCB solver actively damages performance below baseline
- Forced parameterization makes cues under-specific → worse matching

## 3-Mode Experiment (2026-03-04) — devlog 28

### Math (200 problems, gpt-5-nano, 4 runs each, 2 passes)
| Mode | mean p1 | mean best | retry gain | oracle |
|------|---------|-----------|------------|--------|
| Baseline | 174.5 | 186.0 | +11.5 | 193 |
| Concept | **178.8** | 186.2 | +7.5 | 193 |
| Hybrid | 172.2 | **188.5** | **+16.2** | **194** |

### LCB (100 problems, gpt-5-nano) — concepts hurt
- Baseline best; selection broken (55% nano empty completions)
- Runs in `outputs/_runs/m3_{baseline,concept,hybrid}_{math,lcb}_nano/`

## Key Findings
- **Hybrid should be default** for multi-pass: fresh attempt + concept hint on retry
- **v3a extraction eliminates leakage** — validated on both domains
- **Concepts help most during retries**, providing new approach angles
- **gpt-5-nano unreliable for selection** (55% empty completions)
- **qwen3.5-flash reliable** for extraction + selection + solve via OpenRouter

## Concept Failure Taxonomy (devlog 27)
- **Leakage**: source-specific values → FIXED by v3a prompt
- **Misleading**: concept suggests wrong approach
- **Irrelevant noise**: off-topic concepts waste tokens

## Pipeline Architecture
- Math: `math_reason` + `math_reason_eval` + `math_reason_gt` (no-leak feedback)
- LCB: `lcb_solve` + `lcb_exec` + `lcb_gt`
- Extraction: 2-stage (solution→pseudocode→concepts), `--stage1-mode passthrough` for math
- Selection: per-problem concept matching via LLM
- Hints: rendered concept library subset injected into solver prompt

## Model Registry
- gpt-5-mini, gpt-5-nano: OpenAI reasoning models
- qwen3.5-flash-02-23: OpenRouter (registered in model_registry.py)
- gpt-4.1: registered

## Script Fixes Applied
- `select_concepts.py`: `--chunk-size`, `--chunk-delay`, `batch_size` from `--concurrency`
- `memory.py`: `_stringify_keys` for orjson YAML integer key crash
- `math_reason_eval.py`: `_BOXED_RE` regex fix (`\\?boxed`)
- `extract_concepts.py`: `--include-ids`, `--include-ids-file`

## Next Steps (devlog 31)
1. **Hybrid + v3a on fruit fly** — combine hybrid retry mode with optimal selector configs
2. **Scale to full eval** (200 math, 100 LCB) with domain-specific configs
3. **Concept rejection pipeline** — per-concept attribution + automated filtering
4. **Harder test set** — deferred, subsumed by full eval

## Repo Structure
- `mem_devlog/docs/` — devlogs 00-31 (moved from root)
- `mem_devlog/.claude-config/` — portable CLAUDE.md, settings.json, MEMORY.md + setup.sh
- `mem_devlog/literature_reference/` — arxiv papers as markdown (SkillRL etc.)
- Devlog paths: `docs/09_current_state_2026_02_20.md` (onboarding), `docs/00_schema_alignment.tsv` (parity)

## User Preferences
- Slack messages: plain text, no markdown
- Prefers concise reports with tables
- Wants arcmemo schema parity maintained
- Commits under user identity (no Co-Authored-By)
