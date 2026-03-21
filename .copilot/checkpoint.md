# Checkpoint

**Phase:** TEST
**Updated:** 2026-03-21

## Current task
GPQA concept experiment shows promising signal: relevant-hint +5pp on Chemistry (74→79%), random-hint -4pp. Need validation with more seeds and larger n.

## Key numbers
- GPQA baseline: 81/100 (81%) — Chemistry 74%, Biology 60%, Physics 93%
- Relevant-hint: 84/100 (84%) — Chemistry **79%** (+5pp)
- Random-hint: 82/100 (82%) — Chemistry 70% (-4pp)
- Relevance effect on Chemistry: +9pp (relevant 79% vs random 70%)
- BFCL exec baseline: 91% (ceiling, deprioritized)

## DAG state
- I07: exploring (GPQA — promising signal, needs validation)
- I08: exploring (BFCL — ceiling on available splits)

## Next steps
1. Run seed 43 on all 3 GPQA conditions to check if signal holds
2. If confirmed: use full GPQA main set (448 questions) for powered test
3. Consider extracting proper science concepts (vs raw explanation injection)
4. BFCL: need full eval pipeline for harder splits, deprioritize for now
