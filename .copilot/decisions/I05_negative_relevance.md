---
id: D-I05
title: "I05 relevance hypothesis not supported — reframe to context warm-up"
date: 2026-03-18
dag_nodes: ["I05", "I06"]
links:
  - target: A08
    type: related_to
tags: ["negative", "reframe"]
---

# I05 Relevance Hypothesis Not Supported

## Decision

Mark I05 (episodic memory: similar-problem retrieval with worked solutions) as `negative`. The retrieval relevance hypothesis is not supported. Reframe into I06 (context warm-up) to investigate the domain-general priming effect.

## Evidence

Smoketest on 20 Omni-MATH problems (d3-d5):

| Condition | Score | vs Baseline |
|---|---|---|
| Baseline | 16/20 (80%) | — |
| Random example | 17/20 (85%) | +5pp |
| Episodic (TF-IDF relevant) | 17/20 (85%) | +5pp |
| **Episodic - Random** | **0** | **No relevance effect** |

Both random and episodic gained +1 problem over baseline, but gained DIFFERENT problems (random: omath_2313, episodic: omath_0877). Zero answer leakage confirmed (0/20 retrieved problems share target answer).

## Why this matters

The original hypothesis (H1): structurally similar problems provide more useful reasoning scaffolding. The data says: any worked math solution provides equal scaffolding. This means:

1. No retrieval infrastructure needed — simpler is equally effective
2. The benefit is a domain-general context warm-up, not episodic transfer
3. The safety profile (zero regressions) is preserved regardless of relevance

## What remains

The warm-up effect itself is interesting and distinct from technique concepts (which cause -5 to -17pp on math). Needs validation:
- n=100 with multiple seeds to confirm +5pp is real
- Non-math text control to distinguish "any text helps" from "mathematical reasoning helps"
- If math-specific, this is a publishable finding with practical implications

## Caveats

- n=20 is underpowered — relevance might separate at n=100
- Single seed — no variance estimate
- The null (any context equally good) is the simpler explanation with equal support
