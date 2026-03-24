# Checkpoint

**Phase:** Paper writing / handoff
**Updated:** 2026-03-24

## Status
Evaluation campaign complete. All documentation updated for environment migration.

## Start here (for new agent)
1. Read `copilot_context.md` — full project status, all results, file locations
2. Read `reports/experiment_results_handoff.md` — paper-ready results with framing guidance
3. Read `.copilot/hub.md` — State of Knowledge, DAG summary
4. Read `.copilot/research_log.md` — full chronological decision history

## Key numbers
- **LCB baseline:** 80.3 ± 0.6 (3 runs, pass@2)
- **LCB concept v3a:** 82.6 ± 2.6 (5 runs, pass@2), best 3: 84.3 ± 1.2
- **Math (Omni-MATH):** -5.1pp with concepts (n=225, technique concepts hurt)
- **Math (all alt architectures):** 0pp (episodic, warm-up, problem-only — all null at n=108)
- **GPQA Diamond:** null across 2 seeds (83% ± 1pp all conditions)
- **BFCL exec:** 91% baseline (ceiling)

## Important notes for new environment
- Pipeline configs currently use concurrency 64 / batch_size 64 (changed from original 8)
- GPQA Diamond requires HF token (gated dataset): set `HF_TOKEN` in `.env`
- API key needed: `OPENROUTER_API_KEY` in `.env`
- Run outputs: pipeline reuses run ID from config hash — only latest run preserved per config
- All standalone scripts in `scripts/` bypass the full pipeline (faster for experiments)
