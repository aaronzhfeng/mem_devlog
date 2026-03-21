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
<!-- _paginate: false -->

# Concept Memory: 3-Mode Experiment

Baseline vs Concept vs Hybrid
gpt-5-nano | 4 runs | 2 passes | Competition Math

2026-03-04

---

## Setup

**3 modes**, each with 2 passes (pass 1 = initial, pass 2 = retry on failures):

| Mode | Pass 1 | Pass 2 (retry) |
|------|--------|----------------|
| **Baseline** | No concepts | No concepts |
| **Concept** | With concepts | With concepts |
| **Hybrid** | No concepts | Concepts on retry only |

- 4 independent runs per mode, gpt-5-nano, `n=1`
- 200 Level-5 competition math problems
- 837 concepts extracted from 420 build solutions
- Selection coverage: 196/200 (98%)

---

## Results: Per-Run Scores

| Mode | Run 1 | Run 2 | Run 3 | Run 4 | Mean |
|------|-------|-------|-------|-------|------|
| **Baseline p1** | 178 | 176 | 173 | 171 | 174.5 |
| **Concept p1** | 182 | 175 | 183 | 175 | **178.8** |
| **Hybrid p1** | 174 | 171 | 173 | 171 | 172.2 |
| | | | | | |
| **Baseline best** | 184 | 187 | 188 | 185 | 186.0 |
| **Concept best** | 187 | 187 | 184 | 187 | 186.2 |
| **Hybrid best** | 188 | 190 | 187 | 189 | **188.5** |

---

## Results: Summary

| Metric | Baseline | Concept | Hybrid |
|--------|----------|---------|--------|
| Mean p1 | 174.5 | **178.8** (+4.3) | 172.2 |
| Mean best | 186.0 | 186.2 | **188.5** (+2.5) |
| Retry gain | +11.5 | +7.5 | **+16.2** |
| Oracle (4-run) | 193 | 193 | **194** |

- **Concept** boosts first-attempt accuracy by **+4.3**
- **Hybrid** has strongest retry: fresh attempt + concept hint = **+16.2** gain
- Concept retry gain is *lowest* (7.5) — same hint on both passes has diminishing returns
- Oracle union of all three modes: **195/200**

---

## Why Hybrid Wins on Retry

**Hybrid = best of both worlds:**

1. **Pass 1 without hints** avoids misleading concepts on easy problems
2. **Pass 2 adds concepts only to failures** — problems that genuinely need help
3. Error feedback + concept hint = strongest retry signal

**Concept mode** uses hints on both passes, so pass 2 repeats the same hint with diminishing returns (+7.5 vs hybrid's +16.2)

**Baseline** retries without any new information — only error feedback drives improvement (+11.5)

---

<!-- _class: section-divider -->

# Analysis

What do the concepts look like? When do they help vs hurt?

---

## Case: Concept Helps (cmath_2920)

**Problem**: Two intersecting chords in a circle, radius 5, BC=6, AD bisected by BC. Find sine of central angle of minor arc AB as $\frac{m}{n}$, compute $mn$.

**Hint given**:
```yaml
- concept: Center-based Relative Coordinate System
  description: Use coordinates relative to center to simplify symmetry.
  cues:
    - dx = i−4, dy = j−4
  implementation:
    - classify point by (|dx|,|dy|) to identify orbit under D4
- concept: Distance from a Point to a Line
  description: Perpendicular distance from point to line = triangle height.
  cues:
    - Line BC: x − 11y + 197 = 0
    - dist(A, BC) = height
  implementation:
    - distance = |p − 11q + 197| / √122
```

Useful geometric framing. Baseline fails; concept mode solves it.

---

## Case: Concept Hurts (cmath_5298)

**Problem**: Cars on a highway obey safety rule: distance = one car length per 15 km/h. Photoelectric eye counts cars per hour. Maximize $M/N$ where $N$=number of cars, $M$=speed in km/h.

**Baseline solves 4/4 runs. Concept solves 1/4.**

**Hint given**:
```yaml
- concept: Speed Unit Interpretation
  description: speed = distance/time; 160mi ÷ 5hr = 32mph
- concept: Interval Width
  description: width of [a,b] is b − a
- concept: Floor-Ceiling Interval Bound for Integer Counting
  description: count integers in [a,b] = ⌊b⌋ − ⌈a⌉ + 1
  implementation:
    - n = 1+23k, enforce -9999 ≤ n ≤ -1000
    - k_max = floor((-1001)/23), n = 1+23·k_max = -1011
```

*Leakage*: "160 miles / 5 hours = 32 mph" and "-9999 ≤ n ≤ -1000" are values from the **source** problem, not this one. Injects contradictory numbers that confuse the model.

---

## Case: Concept Hurts (cmath_2931)

**Problem**: Rectangle ABCD ($12\sqrt{3} \times 13\sqrt{3}$), cut triangle ABP, fold into pyramid. Find volume.

**Baseline 4/4, Concept 2/4.** Hints: *Scalar Triple Product*, *Triangle Area Formula*

```yaml
- concept: Triangle Area Formula
  implementation:
    - ACM: base CM = 2, height = 8 → area = 8
    - ACN: base CN = 4, height = 4 → area = 8
```

Again, **source-specific values** (CM=2, height=8, CN=4) leak into the hint. These numbers belong to a different problem entirely.

---

## Failure Taxonomy

| Failure Mode | Effect | Frequency |
|-------------|--------|-----------|
| **Misleading** | Suggests wrong approach | ~2-3 per run |
| **Too generic** | Obvious hint, wastes tokens | ~3-4 per run |
| **Leakage** | Source-specific values in hint | ~1-2 per run |

Net effect per run: **~4 wins, ~2 harms** from concepts
(+4.3 p1 mean = genuine positive signal despite noise)

### Key observation
Concepts help more than they hurt on math — the 837-concept pool with 98% coverage provides enough relevant matches. The remaining harms come from selection quality, not pool size.

---

<!-- _class: section-divider -->

# Takeaways

---

## Summary

- **Concept mode**: best for p1 accuracy (**+4.3**)
- **Hybrid mode**: best for final score (**+2.5 best**, +16.2 retry gain)
- **Baseline**: weakest retry (+11.5), but cleanest p1 signal
- Oracle across all modes: **195/200** (only 5 never solved)

Concepts provide genuine signal on competition math when:
- Large concept pool (837 from 420 solutions)
- High selection coverage (98%)
- Domain has transferable techniques (algebra, geometry, number theory)

