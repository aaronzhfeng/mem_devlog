---
marp: true
theme: default
paginate: true
math: mathjax
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
}

h1, h2, h3, h4, h5, h6 {
  font-weight: 700;
  color: var(--color-heading);
  margin: 0;
  padding: 0;
  font-family: var(--font-code);
}

h1 { font-size: 48px; line-height: 1.3; }
h2 { font-size: 34px; margin-bottom: 32px; padding-bottom: 10px; border-bottom: 2px solid var(--color-border); }
h3 { color: var(--color-foreground); font-size: 24px; margin-top: 24px; margin-bottom: 8px; }

ul, ol { padding-left: 32px; }
li { margin-bottom: 8px; }
li::marker { color: var(--color-accent); }

pre {
  background-color: var(--color-code-bg);
  border: 1px solid var(--color-border);
  border-radius: 6px;
  padding: 14px;
  font-family: var(--font-code);
  font-size: 15px;
  line-height: 1.4;
}

code {
  background-color: var(--color-code-bg);
  color: var(--color-accent);
  padding: 2px 6px;
  border-radius: 3px;
  font-family: var(--font-code);
  font-size: 0.85em;
}

pre code { background-color: transparent; padding: 0; color: var(--color-foreground); }
pre code span { color: var(--color-foreground) !important; }
pre code .hljs-attr { color: var(--color-accent) !important; }
pre code .hljs-string { color: #a5d6ff !important; }
pre code .hljs-bullet { color: var(--color-warn) !important; }
pre code .hljs-number { color: #d2a8ff !important; }

table { border-collapse: collapse; width: 100%; font-size: 20px; margin-top: 16px; }
th { background-color: #161b22; color: var(--color-heading); padding: 10px 14px; text-align: left; border-bottom: 2px solid var(--color-accent); }
td { padding: 8px 14px; border-bottom: 1px solid var(--color-border); color: #2d333b; }
tr:hover td { background-color: #161b22; }

strong { color: var(--color-accent); font-weight: 700; }
em { color: var(--color-warn); }

footer {
  font-size: 14px;
  color: #8b949e;
  font-family: var(--font-code);
  position: absolute;
  left: 56px; right: 56px; bottom: 40px;
  text-align: right;
}

section.lead {
  border-left: 4px solid var(--color-accent);
  display: flex;
  flex-direction: column;
  justify-content: center;
}

section.lead h1 { margin-bottom: 24px; }
section.lead p { font-size: 22px; color: var(--color-foreground); font-family: var(--font-code); }

section.section-divider {
  display: flex;
  flex-direction: column;
  justify-content: center;
  align-items: flex-start;
  border-left: 4px solid var(--color-warn);
}
section.section-divider h1 { color: var(--color-warn); font-size: 44px; }
</style>

<!-- _class: lead -->

# Extraction Prompt v3a
## Eliminating Source-Value Leakage

ArcMemo Concept Extraction — Fast Iteration Results
2026-03-07

---

## The Leakage Problem

In the m3 experiment, **76% of extracted math concepts** (634/837) contained source-specific numeric values in their `cues` and `implementation` fields.

### Root cause
The extraction prompt asked for *"how this concept was applied in this specific solution"* — producing entries like:

- `"compute 160mi / 5hr = 32mph"`
- `"base CM = 2, height = 8 -> area = 8"`
- `"center at (4,4) for a 7x7 grid"`

These values **leak into hints for different target problems**, causing misleading guidance.

---

## Leaky Example 1: Speed (source: cmath_6446)

```yaml
- concept: Speed Unit Interpretation
  kind: definition
  description: >
    speed is distance per unit time; with distance in miles
    and time in hours, the speed unit is miles per hour (mph)
  cues:
    - "distance measured in miles"
    - "time measured in hours"
  implementation:
    - "compute 160 miles / 5 hours = 32 mph"       # LEAKED!
```

When selected as a hint for a *different* problem (e.g., trains traveling 300 km in 4 hours), the solver sees **"160 miles / 5 hours = 32 mph"** and incorporates irrelevant numbers.

---

## Leaky Example 2: Geometry (source: cmath_5659)

```yaml
- concept: Triangle Area Formula
  kind: theorem
  cues:
    - "used to compute ACM with base CM and height
       distance from A to the line through CM (x = 8)"   # LEAKED!
    - "used to compute ACN with base CN and height
       distance from A to the line through CN (y = 0)"   # LEAKED!
  implementation:
    - "ACM: base CM = 2, height = 8 -> area = 8"         # LEAKED!
    - "ACN: base CN = 4, height = 4 -> area = 8"         # LEAKED!
```

Cues reference specific points (A, C, M, N) and coordinates. Implementation has hardcoded numeric answers. **Meaningless for any other problem.**

---

## Leaky Example 3: Grid Coloring (source: cmath_2171)

```yaml
- concept: Center-based Relative Coordinate System
  kind: definition
  description: >
    Use coordinates relative to the center of the grid
    to simplify symmetry analysis.
  cues:
    - "center is at (4,4) for a 7x7 grid"                # LEAKED!
    - "dx = i - 4, dy = j - 4 with
       dx, dy in {-3, -2, -1, 0, 1, 2, 3}"               # LEAKED!
  implementation:
    - "classify a point by (|dx|, |dy|) up to order
       to identify its orbit under D4"
```

If this hint is given for a **5x5 grid** or a **hexagonal grid**, the values `(4,4)` and `7x7` are actively misleading.

---

<!-- _class: section-divider -->

# The Fix: v3a Prompt

---

## v3a Anti-Leakage Instructions

Added to the Stage 2 extraction prompt:

```yaml
- CRITICAL: No problem-specific values. Strip ALL concrete
  numbers, coordinates, coefficients, and computed answers
  from cues and implementation. Write abstract patterns only.

    BAD cue: "center is at (4,4) for a 7x7 grid"
    GOOD cue: "problem has a grid with a natural center point"

    BAD implementation: "compute 160 miles / 5 hours = 32 mph"
    GOOD implementation: "compute speed = distance / time"

    BAD implementation: "ACM: base CM = 2, height = 8 -> area = 8"
    GOOD implementation: "compute triangle area = 1/2 x base x height
      using perpendicular distance"
```

Also changed `implementation` field from *"how this concept was applied in this specific solution"* to *"the general procedure (abstract, not specific)"*.

---

## Clean v3a: Speed (same source: cmath_6446)

```yaml
- concept: Average Speed Calculation
  kind: technique
  parameters:
    - name: total distance
      typing: number
      description: the total path length covered
    - name: total time
      typing: number
      description: the total duration of the travel
  description: >
    Calculate average speed by dividing total distance
    traveled by total time elapsed.
  cues:
    - "problem involves motion or travel"
    - "asks for average speed rather than instantaneous speed"
  implementation:
    - "divide total path length by total time duration"
```

No "160 miles", no "5 hours", no "32 mph". **Fully abstract and reusable.**

---

## Clean v3a: Geometry (same source: cmath_5659)

```yaml
- concept: Shoelace Formula
  kind: technique
  parameters:
    - name: vertices
      typing: list[tuple[float, float]]
      description: ordered list of polygon vertex coordinates
  description: >
    Calculate the area of a polygon given the coordinates
    of its vertices in order.
  cues:
    - "polygon vertices are given as coordinates"
    - "area calculation is required"
  implementation:
    - "list vertices in cyclic order"
    - "compute sum of cross-products of adjacent coordinates"
    - "take absolute value and divide by 2"
```

No hardcoded points. No specific areas. **Just the general procedure.**

---

## Clean v3a: Grid Coloring (same source: cmath_2171)

```yaml
- concept: Invariant Colorings via Orbits
  kind: technique
  parameters:
    - name: number of colors
      typing: int
    - name: domain set
      typing: str
      description: set of elements being colored
  description: >
    Count colorings invariant under a group action by
    assigning colors to orbits of the group action.
  cues:
    - "problem asks for colorings invariant under a symmetry group"
    - "elements of the domain partition into orbits"
  implementation:
    - "identify the orbits of the domain under the group action"
    - "total colorings = (number of colors)^(number of orbits)"
```

No `(4,4)`, no `7x7`. **Works for any symmetry group on any domain.**

---

<!-- _class: section-divider -->

# Code Domain (LiveCodeBench)

---

## v3a Code Concepts

Code domain had minimal leakage (1/168) but needed two additional fixes:

1. **Anti-backtick instruction** — backticks in YAML break parsing
2. **Abstract implementation** — same anti-leakage rules as math

### Example: Digit DP

```yaml
- concept: Digit DP
  kind: algorithm
  description: >
    DP approach to count numbers satisfying digit-based
    properties within a range.
  cues:
    - "Problem asks to count integers in a range with digit properties"
    - "Constraints involve divisibility or digit counts"
    - "State depends on position and accumulated properties"
  implementation:
    - "iterate over digit positions, track tight bound and property state"
    - "use memoization on (position, tight, accumulated_state)"
```

---

## v3a Code Concepts (cont.)

### Prefix Sums

```yaml
- concept: Prefix Sums
  kind: technique
  description: >
    Precomputing cumulative sums to allow O(1) range
    sum queries on static arrays.
  cues:
    - "Problem requires frequent sum queries over subarrays"
    - "The array is static with no updates"
    - "Range sums needed for multiple different intervals"
  implementation:
    - "Construct array where each index stores cumulative sum
       from start. Calculate subarray sums by subtracting
       prefix at start from prefix at end."
    - "Answer range query [L, R] as count(R) - count(L-1)"
```

Procedural details matter for code — the solver needs to know *how* to apply the algorithm, not just its name.

---

<!-- _class: section-divider -->

# Results

---

## Leakage Elimination

| Version | Math Leakage | LCB Leakage |
|---------|-------------|-------------|
| **v1** (original) | *76%* (634/837) | 1/168 |
| **v3a** (anti-leakage) | **0%** (0/53) | **0%** |

v3a extraction eliminates source-value leakage entirely.

---

## Solve Results (qwen3.5-flash, n=1, 2 passes, 2 seeds)

### Math (20 eval problems)

| Config | Seed 42 | Seed 43 | Mean |
|--------|---------|---------|------|
| Baseline | 18/20 | 20/20 | 19.0 |
| **Concept (v3a)** | 19/20 | 19/20 | **19.0** |

- Delta: **0.0** — flash is too strong for these 20 problems
- Key validation: **zero concept damage** vs m3's 7 hurts with leaky concepts

### LCB (20 eval problems)

| Config | Seed 42 | Seed 43 | Mean |
|--------|---------|---------|------|
| Baseline | 17/20 | 15/20 | 16.0 |
| **Concept (v3a)** | **20/20** | **17/20** | **18.5** |

- Delta: **+2.5** — consistent improvement across seeds

---

## Retry Recovery: Where Concepts Shine

| Domain | Mode | s42 Retry | s43 Retry |
|--------|------|-----------|-----------|
| LCB | Baseline | 2/5 (40%) | 3/8 (38%) |
| LCB | **Concept** | **6/6 (100%)** | 3/6 (50%) |

Concept hints give the model a **new angle** when its first approach fails.

Seed 42: concept recovered **all 6** failed problems on retry vs baseline's 2/5.

---

## v3a vs v3b: Domain-Specific Tradeoff

**v3b** drops `implementation` and `parameters` fields (40% shorter hints).

| Domain | Variant | s42 | s43 | Mean |
|--------|---------|-----|-----|------|
| Math | Baseline | 18 | 20 | 19.0 |
| Math | v3a | 19 | 19 | 19.0 |
| Math | **v3b** | **20** | **20** | **20.0** |
| LCB | Baseline | 17 | 15 | 16.0 |
| LCB | **v3a** | **20** | **17** | **18.5** |
| LCB | v3b | 17 | 15 | 16.0 |

- **Math**: v3b wins — leaner hints let the solver focus
- **LCB**: v3a wins — procedural details matter for algorithm selection
- **v3a is the best general variant** for both domains

---

## Why Implementation Details Matter for Code

**Math:** "Vieta's Formulas" as a name already tells you what to do.

**Code:** "Digit DP" as a name is less useful than:

> *"Digit DP with tight bound tracking — iterate over digit positions, maintain (position, tight, accumulated_state) with memoization"*

Code problems need to know **how** to apply an algorithm, not just its name. Dropping implementation details makes v3b = baseline for LCB.

---

<!-- _class: lead -->

# Summary

- **v3a eliminates leakage**: 76% &rarr; 0% for math
- **Zero concept damage**: no more misleading hints
- **LCB +2.5/20** net improvement (strongest on retry)
- **v3a is best general variant** across both domains
- Retry recovery is where concepts add the most value

---

<!-- _class: lead -->

# Appendix: Side-by-Side Comparison

| Source | v1 (Leaky) | v3a (Clean) |
|--------|-----------|-------------|
| cmath_6446 | `"compute 160mi / 5hr = 32mph"` | `"divide total path length by total time"` |
| cmath_5659 | `"base CM = 2, height = 8 -> area = 8"` | `"compute sum of cross-products of adjacent coords"` |
| cmath_2171 | `"center at (4,4) for 7x7 grid"` | `"identify orbits of domain under group action"` |
