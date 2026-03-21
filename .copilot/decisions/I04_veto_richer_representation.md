---
id: D-I04
title: "Veto I04: Richer concept representation"
date: 2026-03-18
dag_nodes: ["I04"]
links:
  - target: A06
    type: evidence_for
  - target: I05
    type: related_to
tags: ["veto"]
---

# Veto: Richer Concept Representation (I04)

## Decision

Veto I04 (richer concept representation — bridge shallow and specific).

## Rationale

1. **Negative precedent:** Devlog 30 tested v3c (forced parameterization, a richer representation variant) and it backfired (-1.0 math, -1.5 LCB vs v3a). Enriching the existing Concept schema does not change the fundamental type of memory being injected.

2. **Incremental, not structural:** The current schema (name, kind, cues, implementation, parameters, description) is already rich. Adding "proof sketches" or "key insight statements" is essentially I02 (proof strategy hints) embedded in a different schema field — same mechanism, different packaging.

3. **No new mechanism:** The established failure mode (A07) is that math failures are reasoning depth, not knowledge gaps. Richer technique-level concepts still encode technique-level knowledge. The representation fidelity is not the bottleneck — the *type* of memory is.

## What was considered

- Adding proof sketch fields to Concept dataclass
- Adding "common failure mode" and "prerequisite check" fields
- Restructuring extraction to produce multi-level concepts

## Why this is different from I05

I05 (episodic memory) changes the *type* of memory from semantic (abstracted technique) to episodic (full worked solution of a similar problem). I04 would have enriched the semantic representation without changing the fundamental type.
