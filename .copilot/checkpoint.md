# Checkpoint

**Phase:** DO (Phase-1 scaffolding complete, runs pending GPU)
**Updated:** 2026-04-19
**Autonomy:** full

## Status
Phase-1 ablation scaffold complete. All 11 net-new files landed + registered. Six axes dry-run + mock-live-run cleanly. Strict-parity lock still passes. Live runs on Qwen blocked on GPU endpoint — `../gpu-request.md` written for `_runpod` agent.

## Start here (for new agent)
1. Read `mem2/docs/phase1_setup_complete.md` — full scaffold report
2. Read `../../raw_ideas/context/surveys/03_mem2/06_ablation_plan.md` — live plan
3. Read `../../raw_ideas/INBOX.md` — latest handoff (2026-04-19 Mem2 → Explorer)
4. Check `../gpu-request.md` — endpoint URL if fulfilled by _runpod
5. Resume by running the sweep driver once Qwen endpoint is live

## Key artifacts (absolute paths rooted at workstation_00_arc/)
- `mem2/src/mem2/concepts/graph.py` — `ConceptGraph`
- `mem2/src/mem2/scoring/mdl.py` — MDL scorer
- `mem2/src/mem2/branches/feedback_engine/plateau_trigger.py`
- `mem2/src/mem2/branches/memory_builder/{arcmemo_reorg,variant_formats,barc_ingest,alma_style_metaedit}.py`
- `mem2/src/mem2/branches/memory_retriever/{graph_traversal,rrmc_interactive}.py`
- `mem2/src/mem2/branches/task_adapter/arc3.py` — SDK stub (not wired)
- `mem2/scripts/sweeps/ablation_matrix.py` — sweep driver (all 6 axes)

## Immediate next steps
1. When `../gpu-request.md` shows `## Fulfilled`, extract proxy URL.
2. Create `configs/experiments/phase1_qwen3_4b_base.yaml` (strict-ARC shape + OpenAI-compatible Qwen provider pointing at proxy URL).
3. Smoketest 1 condition × 1 seed × 5 problems to estimate runtime.
4. Estimate full Phase-1 cost (6 axes × 3 seeds × ~100 problems × conditions).
5. Launch axes in parallel (A, D, E, F have no dependencies; B, C need PS builder which we ship).
6. Write `docs/phase1_axis_<A-F>_report.md` per axis as they complete.
7. Append INBOX summary per axis.

## Open structural blockers
- **ARC-3 SDK**: no installable package found. Falling back to ARC-1/2 (`--benchmark arc_agi`) per plan open-question #1. Adapter stub at `arc3.py` raises `NotImplementedError` on `.load()`.
- **Qwen endpoint**: requested 2026-04-19T17:00Z, not yet fulfilled.

## Gates the researcher still owns (surface before crossing)
- Phase 3 (full fusion grid) — after all 6 axes' Phase-1 + Phase-2 results.
- Phase 5 (ALMA external baseline) — compute cost estimate.
- Phase 6 (big-model validation) — budget + closed-model choice.

## Sanity checks that passed this session
- `python scripts/parity/run_arc_default_parity_lock.py` → offline parity reproducible = True
- All 6 axes × 1 condition × 1 seed × 2 problems with mock provider → status=ok

## Known deviations from plan (documented in phase1_setup_complete.md)
- Axis D: 1 parameterized file (`variant_formats.py`) + 5 registry names instead of 5 files. Same behavior.
- Axis C: RRMC is a faithful simplification — core Coverage-gated multi-round loop, not the full MI-estimator / SP machinery. Expand if Phase-1 shows signal.
- Axis F: LLM-proposed meta-edit is hookable via `ctx.config["_meta_edit_provider"]` but falls back to hand-coded reorg if no provider is wired. Keeps Phase-1 infra independent of orchestrator/runner LLM-wiring changes.
