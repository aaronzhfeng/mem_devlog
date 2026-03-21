# Case Study: Where Concepts Help vs Hurt (3-Mode Math Experiment)

**Date:** 2026-03-06
**Data:** 4 baseline runs x 4 concept runs, gpt-5-nano, 200 math problems, 2 passes

## Aggregate Summary

| Metric | Baseline (4 runs) | Concept (4 runs) | Delta |
|--------|-------------------|-------------------|-------|
| Total p1 correct | 698/800 | 715/800 | +17 |
| Total best correct | 744/800 | 745/800 | +1 |
| Oracle p1 | 190 | 192 | +2 |
| Oracle best | 193 | 193 | 0 |
| Concept-only p1 (never solved by baseline) | -- | 3 | |
| Baseline-only p1 (never solved by concept) | 1 | -- | |
| Problems with any run-level difference | 51/194 | | |

## Distribution of per-problem delta (concept - baseline wins out of 4)

### p1 delta distribution
```
-2:    1
-1:   18
 0:  147
+1:   21
+2:    5
+3:    2
```

### best delta distribution
```
-3:    1
-2:    2
-1:    5
 0:  175
+1:    9
+2:    2
```

The distribution is slightly right-shifted for p1 (28 helps vs 19 hurts), confirming the +17 aggregate uplift. Best-of-2 is nearly neutral (+1 total), with changes concentrated in few problems.

---

## Table 1: Top Problems Where Concepts Help

Ranked by combined uplift (p1 delta + best delta).

| # | problem_uid | BL p1 | CO p1 | BL best | CO best | p1 d | best d | Problem summary |
|---|-------------|-------|-------|---------|---------|------|--------|-----------------|
| 1 | cmath_10805 | 0/4 | 3/4 | 1/4 | 3/4 | +3 | +2 | Digit rearrangement: purchase + change from $10 |
| 2 | cmath_9932 | 0/4 | 3/4 | 3/4 | 4/4 | +3 | +1 | Factor x^8+98x^4+1 into monic polynomials, find p(1)+q(1) |
| 3 | cmath_2084 | 0/4 | 2/4 | 1/4 | 2/4 | +2 | +1 | Largest subset of {1..1989} with no two differing by 4 or 7 |
| 4 | cmath_3121 | 2/4 | 4/4 | 3/4 | 4/4 | +2 | +1 | Right triangle with medians on given lines |
| 5 | cmath_3177 | 1/4 | 3/4 | 2/4 | 3/4 | +2 | +1 | Visible area walking around a square |
| 6 | cmath_4161 | 2/4 | 3/4 | 2/4 | 4/4 | +1 | +2 | Functional equation f(x^2+yf(z))=xf(x)+zf(y), find n*s for f(5) |
| 7 | cmath_10098 | 2/4 | 4/4 | 4/4 | 4/4 | +2 | 0 | Polynomial p(x) with p(1)=210 and recurrence |
| 8 | cmath_3010 | 2/4 | 3/4 | 3/4 | 4/4 | +1 | +1 | Two circles, count external tangent lines |
| 9 | cmath_4051 | 3/4 | 4/4 | 3/4 | 4/4 | +1 | +1 | Iterated function f_n(x) = f_{n-1}(sqrt(1-x)), find domain |
| 10 | cmath_9421 | 2/4 | 4/4 | 4/4 | 4/4 | +2 | 0 | Line segments in unit square with length in [sqrt(2), sqrt(10)] |

## Table 2: Top Problems Where Concepts Hurt

Ranked by combined deficit (baseline advantage).

| # | problem_uid | BL p1 | CO p1 | BL best | CO best | p1 d | best d | Problem summary |
|---|-------------|-------|-------|---------|---------|------|--------|-----------------|
| 1 | cmath_5298 | 2/4 | 1/4 | 4/4 | 1/4 | -1 | -3 | Highway car spacing, max cars past photoelectric eye |
| 2 | cmath_2931 | 3/4 | 1/4 | 4/4 | 2/4 | -2 | -2 | Rectangle folded into tetrahedron, find volume |
| 3 | cmath_9959 | 2/4 | 1/4 | 4/4 | 2/4 | -1 | -2 | Polynomial f(x) with f(x)f(2x^2) = f(2x^3+x), find f(5) |
| 4 | cmath_7630 | 4/4 | 3/4 | 4/4 | 3/4 | -1 | -1 | (2a-3)(4b-6) for roots of 2x^2-10x+5=0 |
| 5 | cmath_5246 | 2/4 | 1/4 | 2/4 | 1/4 | -1 | -1 | Count elements of {9^k} with leading digit 9 |
| 6 | cmath_3719 | 1/4 | 0/4 | 1/4 | 0/4 | -1 | -1 | Min value of sqrt sums A-B with shifted arguments |
| 7 | cmath_3059 | 4/4 | 3/4 | 4/4 | 3/4 | -1 | -1 | Rectangle inscribed in triangle, find area |
| 8 | cmath_9599 | 4/4 | 3/4 | 4/4 | 4/4 | -1 | 0 | Two parallel chords in circle, find radius |
| 9 | cmath_5268 | 4/4 | 3/4 | 4/4 | 4/4 | -1 | 0 | Rectangular array numbering, find N |
| 10 | cmath_5243 | 3/4 | 2/4 | 4/4 | 4/4 | -1 | 0 | Largest n with unique k for n^2 = (k+1)^3 - k^3 |

---

## Failure Mode Analysis

### Pass 1 failure decomposition: Empty output vs Wrong answer

For the 6 largest-uplift problems:

| problem_uid | Mode | Empty | Wrong | Correct |
|-------------|------|-------|-------|---------|
| cmath_10805 | baseline | 4 | 0 | 0 |
| cmath_10805 | **concept** | **1** | **0** | **3** |
| cmath_9932 | baseline | 3 | 1 | 0 |
| cmath_9932 | **concept** | **0** | **1** | **3** |
| cmath_2084 | baseline | 4 | 0 | 0 |
| cmath_2084 | **concept** | **2** | **0** | **2** |
| cmath_3121 | baseline | 2 | 0 | 2 |
| cmath_3121 | **concept** | **0** | **0** | **4** |
| cmath_3177 | baseline | 1 | 2 | 1 |
| cmath_3177 | **concept** | **1** | **0** | **3** |
| cmath_4161 | baseline | 2 | 0 | 2 |
| cmath_4161 | **concept** | **1** | **0** | **3** |

For the 7 largest-deficit problems:

| problem_uid | Mode | Empty | Wrong | Correct |
|-------------|------|-------|-------|---------|
| cmath_5298 | **baseline** | **0** | **2** | **2** |
| cmath_5298 | concept | 0 | 3 | 1 |
| cmath_2931 | **baseline** | **1** | **0** | **3** |
| cmath_2931 | concept | 3 | 0 | 1 |
| cmath_9959 | **baseline** | **2** | **0** | **2** |
| cmath_9959 | concept | 3 | 0 | 1 |
| cmath_7630 | **baseline** | **0** | **0** | **4** |
| cmath_7630 | concept | 0 | 1 | 3 |
| cmath_5246 | **baseline** | **2** | **0** | **2** |
| cmath_5246 | concept | 3 | 0 | 1 |
| cmath_3719 | **baseline** | **3** | **0** | **1** |
| cmath_3719 | concept | 4 | 0 | 0 |
| cmath_3059 | **baseline** | **0** | **0** | **4** |
| cmath_3059 | concept | 0 | 1 | 3 |

### Key Finding: Concepts primarily affect empty output rate

For problems with |p1 delta| >= 2, the empty-output change explains most of the effect:

| problem_uid | p1 delta | empty delta (CO-BL) |
|-------------|----------|---------------------|
| cmath_10805 | +3 | -3 (4 -> 1) |
| cmath_9932 | +3 | -3 (3 -> 0) |
| cmath_2084 | +2 | -2 (4 -> 2) |
| cmath_3121 | +2 | -2 (2 -> 0) |
| cmath_2931 | -2 | +2 (1 -> 3) |
| cmath_10098 | +2 | 0 |
| cmath_9421 | +2 | 0 |
| cmath_3177 | +2 | 0 |

For the top 4 biggest helps, **every correct answer gained came from converting an empty output to a successful generation**. Concepts act as scaffolding that helps the reasoning model complete its output.

---

## Detailed Case Analysis

### cmath_10805 (biggest help, +5 combined)

**Problem:** Digit rearrangement puzzle -- how many valid change amounts from a $10 bill where purchase digits rearrange to make the change amount.

**Concepts retrieved:** Intersection of Solution Sets, Finite Case Enumeration, Modular Inverse Calculation

**Mechanism:** Baseline produces EMPTY output in all 4 runs on pass 1 (the model fails to complete reasoning). With concepts, "Finite Case Enumeration" provides scaffolding that guides the model to systematically enumerate cases. 3/4 concept runs complete successfully with the correct answer (8).

**Diagnosis:** Concepts help by **providing reasoning structure** for a combinatorial search problem where nano struggles to organize its approach.

### cmath_9932 (second biggest help, +4 combined)

**Problem:** Factor x^8 + 98x^4 + 1 into monic integer polynomials, find p(1)+q(1).

**Concepts retrieved:** Polynomial Intercepts, Monic Quadratic Factorization over Integers

**Mechanism:** The key concept "Monic Quadratic Factorization over Integers" directly tells the model the factoring trick: (y^2 + ay + 1)(y^2 - ay + 1). Baseline: 3/4 empty outputs on pass 1 (model can't find the factorization approach). Concept: 0/4 empty, 3/4 correct. All 4 concept runs generate complete output.

**Diagnosis:** Concepts provide the **critical mathematical technique** that the model can't reliably discover on its own.

### cmath_5298 (biggest hurt, -4 combined)

**Problem:** Highway car spacing problem. Cars are 4m long, safety gap = ceil(v/15) car lengths per car. Find floor(M/10) where M = max cars past a point in one hour.

**Concepts retrieved:** Speed Unit Interpretation, Interval Width, Floor-Ceiling Interval Bound for Integer Counting

**Mechanism:** The concepts are superficially relevant but **misleading**. The "Floor-Ceiling Interval Bound" concept includes implementation details from unrelated problems (e.g., "n = 1 + 23k", "four-digit negative interval [-9999, -1000]"). The concept model consistently gets M=3749 and answers 374. The baseline model correctly accounts for an edge case (the car at time t=0 adds one) to get M=3750 and answers 375.

**Diagnosis:** **Irrelevant implementation details** in concept cues steer the model toward a floor/ceil framework that misses the boundary counting nuance. The concept anchors the model on "floor(b) - ceil(a) + 1" which yields an off-by-one error for this specific problem.

### cmath_2931 (second biggest hurt, -4 combined)

**Problem:** Rectangle ABCD folded into a tetrahedron, find volume.

**Concepts retrieved:** Scalar Triple Product as Volume Measure, Triangle Area Formula

**Mechanism:** The concepts are actually relevant (the answer does involve triangle areas and volume computation). However, concept runs produce 3/4 EMPTY outputs vs baseline 1/4 empty. When the concept model does generate, it gets the correct answer (594).

**Diagnosis:** This is **not a content failure** -- the concepts are fine. The increased empty rate appears to be noise/variance. The extra tokens from concept hints may slightly increase the chance of generation failure for this long-reasoning problem, but the overall empty rates are similar across modes (6.5% concept vs 7.0% baseline).

### cmath_9959 (third biggest hurt, -3 combined)

**Problem:** Find f(5) where f(x)f(2x^2) = f(2x^3+x), f(0)=1, f(2)+f(3)=125.

**Concepts retrieved:** Polynomial Y-intercept (with c=8, from a different problem), Specialization of FE (with f(0) in {0,2}, from a different problem)

**Mechanism:** Both concept implementations contain **source value leakage**. The Y-intercept concept says "y-intercept is 8, c=8" but this problem has f(0)=1. The FE specialization says "f(0) in {0,2}" but the correct f(0)=1. The model produces 3/4 empty outputs with concepts vs 2/4 without. The leaked values may confuse the reasoning chain.

**Diagnosis:** Classic **source value leakage** -- concept implementations carry numeric values from the source problem that contradict the target problem's conditions.

---

## Failure Taxonomy Summary

| Category | Mechanism | Count in top hurts | Fix |
|----------|-----------|-------------------|-----|
| **Misleading implementation** | Concept cues contain approach details that anchor model on wrong framework | 1 (cmath_5298) | Strip source-specific implementation values |
| **Source value leakage** | Concept implementations carry numeric constants from source problem | 1 (cmath_9959) | Scrub all literal values from implementations |
| **Variance/noise** | Concept adds tokens, random generation failures shift | 3 (cmath_2931, cmath_5246, cmath_3719) | N/A -- inherent variance |
| **Mild noise** | Single-run flips on easy problems (4/4 -> 3/4) | 2 (cmath_7630, cmath_3059) | N/A |

| Category | Mechanism | Count in top helps | |
|----------|-----------|-------------------|---|
| **Reasoning scaffolding** | Concepts provide structure that prevents generation failure | 3 (cmath_10805, cmath_2084, cmath_3121) | Biggest effect |
| **Key technique hint** | Concept provides the critical mathematical method | 2 (cmath_9932, cmath_4161) | Direct technique transfer |
| **Wrong-answer correction** | Concept steers away from common wrong approach | 1 (cmath_3177) | Approach guidance |

---

## Conclusions

1. **Concepts help p1 more than best** (+17 p1, +1 best). The primary mechanism is reducing generation failures by providing reasoning scaffolding, not improving retry strategy.

2. **The biggest wins come from hard problems** where baseline nano consistently fails to generate any output. Concepts provide enough structure for the model to complete its reasoning chain.

3. **The biggest losses come from two distinct failure modes:**
   - Misleading implementation details that anchor the model on wrong frameworks (fixable)
   - Source value leakage in concept descriptions (fixable)
   - Random variance in generation failures (not fixable, small effect)

4. **Net effect is positive:** 28 problems helped vs 19 hurt on p1, with helps being larger magnitude (top help = +5, top hurt = -4).

5. **Fix priority:** Stripping source-specific values from concept implementations and cues would likely eliminate the two worst hurt cases while preserving all helps.
