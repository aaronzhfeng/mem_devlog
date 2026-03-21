# Research Log

---

<a id="LOG-2026-03-18-1"></a>
### 2026-03-18 — Copilot attached to mem2 (math performance direction)

Attached research-copilot to mem2 project via mem_devlog.

**What exists:** Full concept memory pipeline across 3 benchmarks. LCB shows +5pp benefit. Math is structurally capped — technique-level concepts are neutral at ceiling (98.5%), harmful on olympiad (-5.1pp overall, -17pp at d7-8). The failure mode mismatch is well-characterized: concepts fill knowledge gaps (code) but not reasoning depth gaps (math).

**New direction:** Explore alternative memory architectures that could help on math. The technique-name concept type is the wrong tool for math's failure mode. Candidates: similar-problem retrieval, proof strategy hints, worked examples, richer concept representations.

Initial DAG: 7 Assumed nodes (pipeline, extraction, rendering, LCB benefit, math cap, failure taxonomy), 4 exploring nodes (similar-problem, proof strategies, worked examples, richer representations).

-> DAG: A01, A02, A03, A04, A05, A06, A07, I01, I02, I03, I04
-> Evidence: (none yet — grounded in devlogs 28-34)
-> Decision: (initialization)

---

<a id="LOG-2026-03-18-2"></a>
### 2026-03-18 — Narrow IDEATION: merge I01+I03→I05, veto I04, park I02

Research-reflect evaluated all 4 exploring nodes (medium-high confidence). Key findings:

**Merge I01+I03→I05 (Episodic memory: similar-problem retrieval with worked solutions):** I01 (similar-problem retrieval) and I03 (worked examples) are the same approach — both inject solved-problem content rather than abstracted concepts. The only design choice is selection method and how much solution to show. Merged into I05 as the primary exploring direction. Strongest mechanistic case: episodic memory (full worked solutions) addresses reasoning depth failure mode fundamentally differently than semantic memory (technique names). MemP paper finding (trajectories > scripts) supports this.

**Veto I04 (richer concept representation):** Negative precedent — v3c (forced parameterization) backfired in devlog 30. Incremental enrichment of the Concept schema does not change the fundamental type of memory. Adding "proof sketches" to the schema is I02 wearing a different hat. No new mechanism for addressing reasoning depth.

**Park I02 (proof strategy hints, rank 2):** Weak mechanistic story — "try an invariant argument" is still technique-level. But cheap to test as a negative control: if strategy hints also fail, strengthens the case that only full worked examples can help.

**Next step:** Retrieval quality audit — embed ~50 Omni-MATH problems, retrieve top-3 from solved set, inspect whether "nearest" means "structurally similar." This validates or kills I05 before any pipeline changes.

-> DAG: I01 (vetoed/merged), I03 (vetoed/merged), I04 (vetoed), I02 (parked), I05 (new, exploring)
-> Evidence: (research-reflect analysis, MemP literature finding)
-> Decision: D-I04

---

<a id="LOG-2026-03-18-3"></a>
### 2026-03-18 — Retrieval quality audit: TF-IDF viable for formulaic problem types

Ran TF-IDF retrieval audit on 20 Omni-MATH problems (d3-d7). Two banks: Math L5 (cross-corpus) and Omni-MATH self (leave-one-out).

**Key numbers:**
- Math L5 cross-corpus: mean top-1 sim 0.330, mostly topically related but not structurally similar
- Omni self-retrieval: mean top-1 sim 0.485, substantially better — self-retrieval works

**Problem type sensitivity:** Retrieval works well (sim > 0.5) for recurrences, functional equations, series, probability. Works poorly (sim < 0.3) for geometry, constructive proofs, optimization. The well-retrieved types are ~50% of the problem distribution and are also the types where seeing a worked solution is most useful.

**Gate verdict: PROCEED to smoketest.** Retrieval is viable for a meaningful fraction of problems. Expect heterogeneous effects — positive on formulaic types, neutral on geometric/constructive. Net effect depends on distribution.

New assumed node: A08 (TF-IDF retrieval viable for formulaic math).

-> DAG: A08 (new, Assumed), I05 (exploring, continues)
-> Evidence: devlog 35, retrieval_audit_results.json
-> Decision: (analysis)

---

<a id="LOG-2026-03-18-4"></a>
### 2026-03-18 — Phase transition IDEATION→DO; design decisions for smoketest

Transitioning to DO after retrieval audit gate passed. research-reflect approved (high confidence) with two caveats, resolved here:

**D1: Retrieval bank = Omni-MATH leave-one-out.** Self-retrieval (sim 0.485 mean) is much stronger than cross-corpus Math L5 (sim 0.330). Yes, this is oracle-flavored — the bank IS the eval corpus. But the smoketest tests the *mechanism* (does seeing a worked solution help?), not the bank quality. A real system would use a curated library. Self-retrieval gives the upper bound.

**D2: No similarity threshold — inject for all, segment in analysis.** We want to see both benefit on high-sim problems AND cost on low-sim problems. A threshold gate would hide the failure modes. Track per-problem TF-IDF similarity score alongside results. Segment analysis by similarity bucket (>0.5, 0.3-0.5, <0.3) in TEST phase.

**Smoketest plan:** 20 Omni-MATH problems (from existing stratified set, d3-d5 range). Standalone script — bypasses full pipeline for speed. TF-IDF retrieval, inject top-1 worked solution as context preamble, run math_reason inference with Flash, evaluate with olympiad_eval.

-> DAG: I05 (exploring, continues to DO)
-> Evidence: research-reflect approval (LOG-2026-03-18-3)
-> Decision: (phase transition + design decisions D1, D2)

---

<a id="LOG-2026-03-18-5"></a>
### 2026-03-18 — Episodic memory smoketest: +5pp, zero regressions

Ran episodic memory smoketest on 20 Omni-MATH problems (d3-d5, seed=42).

**Results:**
| Condition | Score | Rate |
|---|---|---|
| Baseline | 16/20 | 80.0% |
| Episodic | 17/20 | 85.0% |
| **Delta** | **+1** | **+5.0pp** |

**Per-problem overlap:** 16 both correct, 0 only baseline, 1 only episodic, 3 neither.

**By similarity segment:**
- High (>0.5): 7 problems, 6/7 both conditions, delta=0
- Mid (0.3-0.5): 8 problems, +1 gain (omath_0877 d=5.0 sim=0.306)
- Low (<0.3): 5 problems, 5/5 both conditions, delta=0

**Critical finding: zero regressions.** Technique concepts caused -5 to -17pp damage on the same benchmark. Episodic memory never hurt. Even if +5pp is noise, the safety profile is fundamentally different from technique concepts.

**Comparison to established results:**
- Technique concepts on Omni-MATH d1-4 (baseline ~80%): 0pp
- Episodic memory on Omni-MATH d3-d5 (baseline 80%): +5pp
- (Both same model, same baseline range, different memory type)

**Caveats:** n=20 too small for significance. Single seed. Self-retrieval (oracle bank). +1 could be noise.

-> DAG: I05 (exploring — positive signal, needs validation)
-> Evidence: episodic_smoketest baseline_results.json, episodic_results.json
-> Decision: (smoketest result — INCOMPLETE, see LOG-2026-03-18-6)

---

<a id="LOG-2026-03-18-6"></a>
### 2026-03-18 — Random control kills the episodic relevance hypothesis

**Critical update to LOG-2026-03-18-5.** Added random-example control condition per experiment-designer recommendation (inject a random solved problem, not the most similar).

**Full 3-condition results:**
| Condition | Score | vs Baseline |
|---|---|---|
| Baseline | 16/20 (80%) | — |
| Random example | 17/20 (85%) | +5pp |
| Episodic (relevant) | 17/20 (85%) | +5pp |
| **Episodic - Random** | **0** | **No relevance effect** |

**Interpretation:** The +5pp comes from injecting ANY worked math solution as context (a math warm-up / chain-of-thought scaffolding effect), NOT from retrieval relevance. Both random and episodic gain +1 problem over baseline, but gain DIFFERENT problems (random gained omath_2313, episodic gained omath_0877).

**What this means for I05:** The episodic memory hypothesis — that structurally similar problems provide more useful reasoning scaffolding — is NOT supported at n=20. The benefit is a domain-general context effect, not a retrieval-specific effect.

**What this means for the project:** The "context warm-up" finding is itself interesting but is NOT what we set out to test. Injecting any solved math problem helps equally, which is much simpler than building a retrieval pipeline.

**Zero answer leakage confirmed:** 0/20 retrieved problems share an answer with the target.

**Also note:** Experiment-designer raised \boxed{} pollution risk. Added stripping of \boxed{} from injected solutions to avoid parser confusion.

-> DAG: I05 (exploring — relevance hypothesis not supported, context effect found)
-> Evidence: episodic_smoketest baseline_results.json, episodic_results.json, random_results.json
-> Decision: (branching trigger — surprising result, see LOG-2026-03-18-7)

---

<a id="LOG-2026-03-18-7"></a>
### 2026-03-18 — Reframe: I05 negative, I06 (context warm-up) exploring

research-reflect assessed the random-control result (medium-high confidence). Recommends hybrid path: validate the warm-up effect at scale while investigating what properties of injected solutions matter.

**I05 marked negative.** Retrieval relevance does not contribute beyond random context. The +5pp is a domain-general warm-up effect.

**I06 created (exploring).** "Context warm-up: any worked math solution improves math performance." Reframed from I05. The finding is mechanistically distinct from technique concepts (zero regressions vs -17pp), simpler to implement (no retrieval needed), and needs validation at scale.

**Next experiment plan (n=100, 3 seeds):**
1. Baseline (no context)
2. Random worked math solution (the warm-up treatment)
3. Non-math text control (e.g., random code solution from LCB)
   - If warm-up holds and is math-specific → publishable finding
   - If warm-up holds but non-math equally good → generic context effect (less interesting)
   - If warm-up doesn't hold at n=100 → noise, close direction

-> DAG: I05 (negative), I06 (new, exploring)
-> Evidence: episodic_smoketest results (baseline, random, episodic)
-> Decision: D-I05

---

<a id="LOG-2026-03-19-1"></a>
### 2026-03-19 — I06 negative: warm-up effect was noise at n=108

Ran powered experiment on 108 Omni-MATH problems (12 per d1-d9, seed=42). Three conditions: baseline, math-warmup (random problem + solution), problem-only (random problem, no solution).

**Results:**
| Condition | Score | Rate | vs Baseline |
|---|---|---|---|
| Baseline | 73/108 | 67.6% | — |
| Math-warmup | 71/108 | 65.7% | -1.9pp |
| Problem-only | 72/108 | 66.7% | -0.9pp |

All conditions are statistically equivalent. The smoketest's +5pp (n=20) was pure noise. Per-problem overlap shows random churn (6 lost/4 gained for warmup, 8 lost/7 gained for problem-only), not directional effect.

**Per-difficulty:** No consistent advantage at any difficulty level. Random variation dominates.

**Comparison to technique concepts:** Technique concepts caused -5.1pp on the same benchmark (devlog 34). Context injection is ~0pp — neutral but not helpful. The safety profile is better (no -17pp damage) but the positive signal is absent.

**Lesson confirmed:** Do not conclude from fewer than 50 samples. The n=20 smoketest was misleading.

**Direction status:** All explored nodes are now negative or vetoed:
- I05 (episodic relevance): negative
- I06 (context warm-up): negative
- I04 (richer representation): vetoed
- I01, I03: merged then negative via I05
- I02 (proof strategy hints): parked, weak mechanistic story

-> DAG: I06 (negative)
-> Evidence: warmup_experiment baseline/math-warmup/problem-only results
-> Decision: (powered experiment confirms null)

---

<a id="LOG-2026-03-19-2"></a>
### 2026-03-19 — Pivot: math direction closed, exploring GPQA Diamond + BFCL-V4

Math direction exhausted — all approaches negative (technique concepts -5pp, episodic retrieval 0pp, context warm-up 0pp). The failure mode (reasoning depth) is not addressable by memory augmentation.

Pivoting to two new domains where the failure mode matches what concepts address (knowledge gaps):

**I07: GPQA Diamond (science QA)**
- Flash baseline ~84%, graduate-level science
- Failure mode: missing domain knowledge in physics/chemistry/biology
- Needs: MCQ evaluator adapter, science concept extraction pipeline

**I08: BFCL-V4 (function calling)**
- Flash baseline ~67%, API/tool use tasks
- Failure mode: not knowing the right API pattern — same as LCB where concepts gave +5pp
- Needs: function-call evaluator, tool-use concept extraction

Both parent from A05 (LCB concept benefit) — extending the validated positive to new knowledge-gap domains.

-> DAG: I07 (new, exploring), I08 (new, exploring)
-> Evidence: math direction negative (I05, I06), LCB positive (A05)
-> Decision: (pivot — user approved)

---

<a id="LOG-2026-03-20-1"></a>
### 2026-03-20 — BFCL exec baseline at ceiling (91%); GPQA blocked on HF auth

Ran BFCL-V4 baseline on exec splits (only splits with ground truth):
- exec_simple: 93/100 (93%)
- exec_multiple: 44/50 (88%)
- **Overall: 137/150 (91.3%)**

This is a ceiling problem identical to Math L5 (98.5%). The reported 67% Flash score applies to the full BFCL benchmark including harder multi-turn and live splits, which don't have ground truth in the HuggingFace dataset download. Evaluating those requires the full BFCL evaluation pipeline from their GitHub repo.

GPQA Diamond download blocked on HuggingFace authentication (gated dataset, user accepted license but machine not authenticated).

**Assessment:** BFCL exec splits have insufficient headroom for concept memory. Need either (a) full BFCL eval pipeline for harder splits, or (b) focus on GPQA instead. GPQA has better headroom (~84%) and simpler evaluation (letter match).

-> DAG: I08 (exploring — headroom concern on available splits)
-> Evidence: bfcl_pilot baseline_results.json
-> Decision: (baseline assessment)

---

<a id="LOG-2026-03-21-1"></a>
### 2026-03-21 — GPQA Diamond baseline: 80.8% with strong domain variation

Ran GPQA Diamond baseline on all 198 questions (Flash, seed=42):
- **Overall: 160/198 (80.8%)**
- Physics: 83/86 (97%) — ceiling, no headroom
- **Chemistry: 64/93 (69%)** — 31% headroom, knowledge-gap failure mode
- **Biology: 13/19 (68%)** — 32% headroom, small sample

**Assessment:** Physics is saturated (like Math L5). Chemistry and Biology have the headroom and the right failure mode (domain knowledge gaps — "doesn't know the reaction mechanism" or "doesn't know the pathway"). This exactly matches the concept memory sweet spot seen on LCB.

Next: extract science concepts from the GPQA explanation fields and test concept-augmented condition on Chemistry/Biology questions.

-> DAG: I07 (exploring — baseline established, good headroom in chem/bio)
-> Evidence: gpqa_pilot baseline_s42_results.json
-> Decision: (baseline assessment — proceed to concept extraction)

---

<a id="LOG-2026-03-21-2"></a>
### 2026-03-21 — GPQA concept experiment: +3pp overall, +5pp Chemistry with relevance effect

Ran 3-condition experiment on GPQA Diamond eval split (100 questions, seed=42):

| Condition | Overall | Chemistry (n=47) | Biology (n=10) | Physics (n=43) |
|---|---|---|---|---|
| Baseline | 81% | 74% | 60% | 93% |
| Random-hint | 82% (+1) | 70% (-4) | 70% (+10) | 98% (+5) |
| Relevant-hint | 84% (+3) | **79% (+5)** | 60% (0) | 95% (+2) |

**Key findings:**
1. **Relevance matters on Chemistry:** relevant +5pp, random -4pp. Opposite of math where random = relevant.
2. **Random hints hurt Chemistry:** irrelevant science explanations confuse the model (-4pp). This is a DIFFERENT failure mode from math.
3. **Per-problem overlap:** relevant-hint gained 6, lost 3 vs baseline (net +3).
4. **Physics at ceiling** (93-98%) — contributes minimal signal.

**Comparison to prior results:**
- LCB concepts: +5pp at 80% baseline (knowledge gaps, validated)
- Math concepts: 0 to -5pp (reasoning depth, all negative)
- **GPQA Chemistry concepts: +5pp at 74% baseline** (knowledge gaps, preliminary)

**Caveats:** n=47 Chemistry is small. Single seed. Math smoketest also showed +5pp which was noise. Need validation.

-> DAG: I07 (exploring — promising preliminary signal, needs validation)
-> Evidence: gpqa_concept baseline/relevant-hint/random-hint results
-> Decision: (preliminary positive — do not declare victory, validate harder)

---

<a id="LOG-2026-03-21-3"></a>
### 2026-03-21 — Seed 43 reverses GPQA signal; cross-seed average is null

Seed 43 results flip the direction: baseline 85% > relevant-hint 83%. Cross-seed average:

| Condition | s42 | s43 | Mean |
|---|---|---|---|
| Baseline | 81% | 85% | 83.0% |
| Random-hint | 82% | 83% | 82.5% |
| Relevant-hint | 84% | 83% | 83.5% |

**All conditions within 1pp of each other across seeds.** The seed 42 "relevance effect" was noise from option shuffling (baseline fluctuated 4pp between seeds).

Chemistry cross-seed: relevant-hint 77.7% vs baseline 76.6% = +1.1pp (not significant). Random-hint 72.3% = -4.3pp (consistent regression across seeds — injecting random science explanations may confuse the model on chemistry, but this is n=47×2 seeds).

**Verdict:** Like math, the GPQA concept memory effect is null at the aggregate level. The +5pp from seed 42 was noise. However, the random-hint regression on Chemistry is an interesting negative finding worth noting.

-> DAG: I07 (exploring → likely negative, needs larger sample to confirm)
-> Evidence: gpqa_concept s42 + s43 results
-> Decision: (second seed confirms null)
