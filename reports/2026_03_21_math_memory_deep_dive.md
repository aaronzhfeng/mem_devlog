---
marp: true
theme: default
paginate: true
math: mathjax
size: 16:9
---

<style>
@import url('https://fonts.googleapis.com/css2?family=Noto+Sans+JP:wght@400;700&family=Fira+Code:wght@400;500;700&display=swap');

:root {
  --color-background: #0d1117;
  --color-foreground: #c9d1d9;
  --color-heading: #58a6ff;
  --color-accent: #7ee787;
  --color-warn: #f0883e;
  --color-error: #f85149;
  --color-code-bg: #161b22;
  --color-border: #30363d;
  --font-default: 'Noto Sans JP', 'Hiragino Kaku Gothic ProN', sans-serif;
  --font-code: 'Fira Code', 'Consolas', monospace;
}

section {
  background-color: var(--color-background);
  color: var(--color-foreground);
  font-family: var(--font-default);
  font-weight: 400;
  border-left: 4px solid var(--color-accent);
  line-height: 1.6;
  font-size: 22px;
  padding: 56px;
  width: 100%;
  height: 100%;
}

section::after {
  background: var(--color-background);
}

h1, h2, h3, h4, h5, h6 {
  font-weight: 700;
  color: var(--color-heading);
  margin: 0;
  padding: 0;
  font-family: var(--font-code);
}

h1 { font-size: 44px; line-height: 1.3; }
h2 { font-size: 32px; margin-bottom: 24px; padding-bottom: 10px; border-bottom: 2px solid var(--color-border); }
h3 { color: var(--color-foreground); font-size: 24px; margin-top: 16px; margin-bottom: 8px; }

ul, ol { padding-left: 32px; }
li { margin-bottom: 6px; }
li::marker { color: var(--color-accent); }

table { border-collapse: collapse; width: 100%; font-size: 19px; margin-top: 12px; }
th { background-color: #161b22; color: var(--color-heading); padding: 8px 12px; text-align: left; border-bottom: 2px solid var(--color-accent); }
td { padding: 7px 12px; border-bottom: 1px solid var(--color-border); color: #6e7681; }
tr:hover td { background-color: #161b22; }

code {
  background-color: var(--color-code-bg);
  color: var(--color-accent);
  padding: 2px 6px;
  border-radius: 3px;
  font-family: var(--font-code);
  font-size: 0.85em;
}

pre {
  background-color: var(--color-code-bg) !important;
  border: 1px solid var(--color-border);
  border-radius: 6px;
  padding: 16px;
}

pre code {
  background-color: transparent !important;
  padding: 0;
}

.green { color: var(--color-accent); }
.orange { color: var(--color-warn); }
.red { color: var(--color-error); }
.blue { color: var(--color-heading); }
.dim { color: #8b949e; }
</style>

# Beyond Technique Hints
### Can Alternative Memory Architectures Help on Math?

<br>

**Date:** 2026-03-21
**Context:** Follow-up to Headroom Search (2026-03-16)
**Question:** If technique-level concepts fail on math, does a fundamentally different memory type work?

---

## Recap: Where We Left Off

The headroom search (2026-03-16) established:

| Domain | Baseline | + Technique Concepts | Delta |
|---|---|---|---|
| **LiveCodeBench** | 80% | **85%** | <span class="green">+5</span> |
| Math L5 | 98.5% | 98.5% | <span class="dim">0</span> |
| **Omni-MATH** | **57.3%** | **52.3%** | <span class="red">-5.1</span> |
| Omni d7-8 | 39% | 22% | <span class="red">-17</span> |

**Diagnosis:** Concepts encode technique names ("use Vieta's formulas"). Math failures are reasoning depth, not knowledge gaps. The concept *type* is mismatched with the *failure mode*.

**Open question:** Would a fundamentally different memory architecture work?

---

## Three Alternative Architectures Tested

Starting from the failure mode analysis, we evaluated four approaches:

| ID | Approach | Mechanism | Status |
|---|---|---|---|
| I01+I03 → **I05** | Episodic memory (worked solutions) | Show full solution to similar problem | Tested |
| **I06** | Context warm-up (any solution) | Inject any math solution as priming | Tested |
| I04 | Richer concept representation | More fields in concept schema | Vetoed (v3c precedent) |
| I02 | Proof strategy hints | Higher-level hints | Parked (weak case) |

**Selection rationale:** I05 had the strongest mechanistic case — episodic memory (full worked solutions) addresses reasoning depth differently than semantic memory (technique names). Supported by MemP finding that trajectories outperform scripts.

---

## Phase 1: Retrieval Quality Audit

**Question:** Can embedding-based retrieval find structurally similar math problems?

Method: TF-IDF with bigrams over 4,428 Omni-MATH problems. 20 queries (d3-d7), two banks.

| Retrieval Bank | Mean Top-1 Similarity |
|---|---|
| Math L5 → Omni query | 0.330 |
| Omni self (leave-one-out) | **0.485** |

### Retrieval quality depends on problem type

| Problem Type | Typical Sim | Quality |
|---|---|---|
| Recurrences/sequences | 0.7–0.8 | <span class="green">Excellent</span> |
| Functional equations | 0.6–0.7 | <span class="green">Good</span> |
| Probability | 0.5–0.9 | <span class="green">Good</span> |
| Infinite series | 0.5–0.6 | <span class="green">Good</span> |
| Combinatorics | 0.3–0.5 | <span class="orange">Mediocre</span> |
| Geometry | 0.2–0.4 | <span class="red">Poor</span> |
| Constructive/proof | 0.1–0.2 | <span class="red">Poor</span> |

**Gate verdict:** Retrieval viable for ~50% of problem types. Proceed to smoketest.

---

## Phase 2: Episodic Memory Smoketest (n=20)

### Initial 2-condition result (looked promising)

| Condition | Score | Delta |
|---|---|---|
| Baseline | 16/20 (80%) | — |
| Episodic (TF-IDF relevant) | 17/20 (85%) | <span class="green">+5pp</span> |

Zero regressions. Gained 1 problem (omath_0877, d=5.0).

At this point the signal looked identical to LCB (+5pp, zero regressions, 80% baseline).

---

## The Random Control Changes Everything

The experiment-designer insisted on a 3rd condition: inject a **random** solved problem (not the most similar). This is the critical ablation — it tests whether the benefit comes from retrieval *relevance* or just extra *context*.

| Condition | Score | Delta |
|---|---|---|
| Baseline | 16/20 (80%) | — |
| **Random example** | **17/20 (85%)** | <span class="orange">+5pp</span> |
| Episodic (relevant) | 17/20 (85%) | <span class="orange">+5pp</span> |

**Episodic = Random.** Both gained +1 problem, but *different* problems:
- Random gained omath_2313, episodic gained omath_0877.
- The benefit was from extra context, not relevance.

---

## Interpretation: Context Effect, Not Episodic Transfer

```
                   Retrieval relevance
                   does NOT matter
                        │
  Baseline ──(+5pp)──> Random ──(0pp)──> Episodic
    80%                  85%                85%
                        │
                   Any worked solution
                   provides equal benefit
```

The +5pp was a **domain-general context warm-up** — seeing any mathematical reasoning primes the model. But this was n=20. Was the warm-up effect itself real?

---

## Phase 3: Powered Warm-Up Experiment (n=108)

Scaled to 108 problems (12 per difficulty d1-d9). Added a **problem-only** control (random problem statement without solution — tests if the reasoning chain matters).

| Condition | Score | Rate | vs Baseline |
|---|---|---|---|
| **Baseline** | **73/108** | **67.6%** | — |
| Math-warmup | 71/108 | 65.7% | <span class="red">-1.9pp</span> |
| Problem-only | 72/108 | 66.7% | <span class="dim">-0.9pp</span> |

**The warm-up effect was noise.** All three conditions within 2pp. Both treatment conditions scored *below* baseline.

---

## Per-Difficulty Breakdown (n=108)

| Diff | Baseline | Math-warmup | Problem-only |
|---|---|---|---|
| d1 | 83% | 75% | 75% |
| d2 | 92% | 92% | 100% |
| d3 | 83% | 83% | 75% |
| d4 | 67% | 67% | 67% |
| d5 | 58% | <span class="red">42%</span> | 58% |
| d6 | 67% | 58% | 58% |
| d7 | 50% | 58% | <span class="red">42%</span> |
| d8 | 50% | 58% | 58% |
| d9 | 58% | 58% | 67% |

No consistent advantage at any difficulty level. Random variation dominates.

---

## The Smoketest Trap

The n=20 smoketest showed +5pp (80% → 85%). This looked identical to the validated LCB result. But:

| Stage | n | Apparent Effect | Real Effect |
|---|---|---|---|
| Smoketest (2 conditions) | 20 | <span class="green">+5pp</span> | Unknown |
| Smoketest + random control | 20 | +5pp (both) | Context effect? |
| Powered experiment | 108 | <span class="dim">0pp</span> | **Null** |

**Lesson:** A single +1/20 flip is a coin toss (p=0.50 by McNemar's test). The experiment guardrail "do not conclude from fewer than 50 samples" exists for exactly this reason.

**The random control was essential.** Without it, we would have scaled the episodic pipeline to n=225 before discovering the null. The control saved ~$10 and several hours by collapsing the hypothesis at n=20.

---

## Why Math Is Structurally Immune

Every tested memory architecture fails on math. The pattern:

| Architecture | What It Provides | What Math Needs | Result |
|---|---|---|---|
| Technique concepts | "Use Vieta's formulas" | Multi-step reasoning | <span class="red">-5pp</span> |
| Relevant worked solution | Full solution to similar problem | Creative insight | <span class="dim">0pp</span> |
| Random worked solution | Any math reasoning chain | Novel approach path | <span class="dim">0pp</span> |
| Problem statement only | Priming with math problem | Deep combinatorial search | <span class="dim">0pp</span> |

The model already has technique knowledge and can follow worked solutions. Its failures on olympiad math are:
1. **Execution errors** (d1-d4): arithmetic mistakes, missed edge cases — not addressable by hints
2. **Reasoning depth** (d5-d7): needs 4-5 step chains without error — no external hint fixes this
3. **Creative insight** (d8-d9): needs non-obvious constructions — hints push wrong paths

---

## Cross-Domain Comparison

These math experiments complete the picture across all tested domains:

| Domain | Benchmark | Baseline | Memory Type | Effect | N |
|---|---|---|---|---|---|
| **Code** | LCB | 80% | Technique concepts | <span class="green">**+5pp**</span> | 100 |
| Math (competition) | Math L5 | 98.5% | Technique concepts | <span class="dim">0</span> | 200 |
| Math (olympiad) | Omni-MATH | 57% | Technique concepts | <span class="red">-5.1</span> | 225 |
| Math (olympiad) | Omni-MATH | 68% | Episodic (relevant) | <span class="dim">0</span> | 108 |
| Math (olympiad) | Omni-MATH | 68% | Context warm-up | <span class="dim">0</span> | 108 |
| Science | GPQA Diamond | 83% | Explanation injection | <span class="dim">+0.5</span> | 200 |
| Tool use | BFCL-V4 (exec) | 91% | — | <span class="dim">ceiling</span> | 150 |

---

## The Failure Mode Taxonomy

The key insight: **memory augmentation is not universally helpful.** It helps if and only if the failure mode is a knowledge gap.

```
  Failure Mode          Memory Helps?     Example

  Knowledge gap         YES               LCB: model doesn't know
  (model lacks info)                       itertools.accumulate pattern

  Reasoning depth       NO                Omni-MATH: model knows
  (model can't chain)                     techniques but can't chain
                                          4 steps without error

  Ceiling               NO                Math L5 (98.5%),
  (model already wins)                    BFCL exec (91%)

  Creative insight      HARMFUL           Omni d7-8: hints push
  (needs novel idea)                      plausible but wrong paths
```

---

## What Worked in the Process

### 1. The random control saved the project

At n=20, episodic memory looked like a breakthrough (+5pp, zero regressions). The random-example control — suggested by the experiment-designer agent — immediately showed the effect was domain-general context, not retrieval-specific. This prevented weeks of wasted pipeline work.

### 2. Retrieval quality audit as a gate

Before building any pipeline, we tested whether TF-IDF could find structurally similar math problems. This cheap check (zero API cost) validated the retrieval mechanism before committing to implementation.

### 3. Progressive sample sizes

Each stage increased commitment only after passing the previous gate:

| Stage | Cost | What It Tested | Gate Passed? |
|---|---|---|---|
| Retrieval audit | $0 | Can we find similar problems? | Yes (50% of types) |
| 2-condition smoketest | ~$1 | Does it work at all? | Yes (misleadingly) |
| 3-condition smoketest | ~$0.50 | Is it relevance or context? | No (context only) |
| Powered experiment | ~$3 | Is the context effect real? | No (null) |

Total cost to fully explore and close the math direction: **~$5**

---

## What Failed in the Process

### 1. Trusting n=20

The +5pp smoketest result triggered excitement before it was validated. The research principles state "positive results are a trigger to validate harder" — but the natural reaction to +5pp with zero regressions is to celebrate, not to add more controls.

### 2. Initial design missing the random control

The first smoketest had only baseline and episodic conditions. The experiment-designer agent caught this gap. Without mandatory experiment-designer dispatch, the random control would not have been run at the smoketest stage.

### 3. Option shuffling variance

On GPQA, baseline accuracy varied 4pp between seeds (81% → 85%) purely from shuffling answer option positions. This is a known MCQ evaluation issue — answer position affects model behavior. Single-seed MCQ results are unreliable.

---

## Recommendations

### For math: direction is closed

Every tested memory architecture fails. Further math gains require a fundamentally different approach:
- **Process-level improvements** (retry strategies, self-correction)
- **Different problem decomposition** (break into subproblems, verify steps)
- **Training-time interventions** (not inference-time memory augmentation)

### For the broader concept memory project

The validated finding remains: **concept memory helps when failure mode = knowledge gap (LCB +5pp)**. This is narrow but real. The path forward:

1. **Scale the LCB result** to 300+ problems for statistical confidence
2. **Test more knowledge-gap domains** (GPQA showed null but n was small; BFCL needs harder splits)
3. **Frame honestly**: concept memory is a domain-specific tool for knowledge-gap failure modes, not a universal augmentation

### For experimental methodology

- Always include a random-example control when testing retrieval/selection
- Never conclude from n<50 (make this a hard gate, not advisory)
- Run 2+ seeds before reporting MCQ results
- Use progressive sample sizes: cheap gate → smoketest → powered experiment

---

## Method Evolution DAG

```
A01 Pipeline architecture (Assumed)
├── A05 LCB concept benefit +5pp (Assumed)
│   ├── I07 GPQA Diamond (exploring → null at 2 seeds)
│   └── I08 BFCL-V4 (exploring → ceiling on available splits)
├── A06 Technique concepts neutral/harmful on math (Assumed)
│   └── A07 Failure mode taxonomy (Assumed)
│       ├── I05 Episodic memory (NEGATIVE — relevance = random)
│       │   ├── A08 TF-IDF retrieval viable for formulaic types (Assumed)
│       │   └── I06 Context warm-up (NEGATIVE — null at n=108)
│       ├── I02 Proof strategy hints (Parked — weak case)
│       └── I04 Richer representation (Vetoed — v3c precedent)
└── A02 Two-stage concept extraction (Assumed)
```

16 nodes: 8 Assumed, 2 exploring, 2 negative, 1 parked, 3 vetoed.

---

## Summary

**Question:** Can alternative memory architectures help on math?

**Answer: No.** We tested three fundamentally different approaches beyond technique concepts:

1. **Episodic memory** (relevant worked solutions): 0pp — relevance doesn't matter
2. **Context warm-up** (any worked solution): 0pp — smoketest noise
3. **Explanation injection on GPQA**: +0.5pp — null across seeds

Math failures are reasoning depth, not knowledge gaps. No form of external knowledge injection at inference time addresses this. The concept memory framework is validated for knowledge-gap domains (LCB +5pp) and only knowledge-gap domains.

**Cost of this investigation:** ~$8 in API calls, 3 sessions of work.

**Key methodological contribution:** The random-example control pattern. Should be mandatory for all retrieval/selection experiments.
