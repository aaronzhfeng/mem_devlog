# Research Direction

## Title
Better math performance through concept memory

## Questions
- RQ1: Can concept memory improve math problem-solving, given that technique-level hints have failed?
- RQ2: What alternative memory architectures (similar-problem retrieval, proof strategy hints, worked examples) could address the reasoning-depth failure mode?
- RQ3: Is there a concept representation that bridges the gap between "technique name" (too shallow) and "full solution" (too specific)?

## Context
Extensive experimentation (devlogs 28-34) has established that the current concept memory framework — technique-level hints extracted from solved problems — is structurally limited on math. At every tested baseline (6%, 57%, 80%, 98.5%), technique concepts are neutral or harmful on math, while providing +5pp on code (LCB). The failure mode mismatch is well-characterized:

- **Code:** failure = knowledge gap → concept fills it → +5pp
- **Math competition:** failure = already knows techniques → concepts redundant → 0pp
- **Math olympiad:** failure = reasoning depth → technique hints mislead → -5 to -17pp

The current concept type (technique hints like "use Vieta's formulas") doesn't match what math solvers need. The question is whether a *different* kind of memory can help.

## Anchor
- `mem_devlog/docs/34_headroom_search_2026_03_17.md` — Full headroom search establishing the structural cap
- `mem_devlog/docs/31_fast_iter_summary_2026_03_09.md` — Best configurations and domain sensitivity
- `mem_devlog/copilot_context.md` — Project overview and open questions

## Initial Hypotheses
- H1: Similar-problem retrieval (showing a solved problem with analogous structure) provides more useful context than abstract technique names for math
- H2: Proof strategy hints ("try an invariant argument", "construct a bijection") are more actionable than technique names for olympiad-level math
- H3: Worked examples (full solution paths of related problems) give the model reasoning scaffolding that technique names cannot
- H4: The concept extraction pipeline can be adapted to produce these richer memory types without fundamental architecture changes
