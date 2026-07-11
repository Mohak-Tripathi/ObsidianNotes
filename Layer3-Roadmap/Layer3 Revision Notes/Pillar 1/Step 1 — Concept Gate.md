# P1 — Orchestration Patterns (Revision Notes)

> Layer 3 · Pillar 1 · **concept layer only** (from the 2026-07-11 session + Socratic gate). Build-layer TODO (add after S1): cost/latency/reliability tradeoff numbers · LangGraph code skeletons. Revise cadence: full pass ~40 min · pass 3–4 = **CRUX + Quick Recall only** (~15 min).

---

## Current Stand
## P1 — Orchestration Patterns · Completion Map

**Steps to complete this pillar:**
1. **Concept gate** — six patterns + workflow/agent + selection axis (known-upfront vs
   runtime) + per-pattern failure modes; validated via novel scenario tests.
   ✅ DONE (2026-07-11)
2. **Required reading** — Building Effective Agents ✅ · 12-Factor Agents ⏳ pending
3. **S1 — Pattern Lab build** — one task × 4 patterns (sequential / router /
   planner-executor / supervisor-worker) + shared eval harness; metric table
   (tokens / latency / success / debuggability) over ≥30 cases → **PASS Block Card**.
   ⛔ not started

**These notes cover → Step 1 (concept gate) only.**
Reading residue (Step 2) and build-layer content — tradeoff numbers, LangGraph
skeletons (Step 3) — get added as later passes.

## 0. Pillar-level (read once, then it's ambient)

**▸ Mental model:** An agent is a control loop wrapped around a probabilistic function. **The model supplies reasoning; the topology supplies guarantees.** Orchestration = choosing that topology = deciding how much authority the model has over "what happens next."

**▸ Governing question for every pattern:** _how much do I trust the model to decide the next step?_ → **The model's authority shrinks as the action's blast radius grows.**

**▸ Prime directive:** default to the **least powerful pattern that passes evals.** Most "multi-agent" systems should be a single agent + router + good tools.

### 0b. Workflow vs Agent (the autonomy spectrum)

|Dimension|Workflow|Agent|
|---|---|---|
|Control flow|predefined code paths — **you** own it|model decides next step at runtime|
|Predictability|high|lower|
|Use when|path is knowable / decomposable upfront|can't decompose upfront, but can verify progress|
|Cost / latency|lower|higher — each autonomous turn adds latency, tokens, and error-compounding risk|

> ▹ WHY: it's a spectrum, not a binary. Agentic systems use workflow patterns _internally_ (a supervisor is workflow scaffolding around agent workers). Anthropic's line: simplest solution first — maybe don't build an agent at all.

### 0c. Selection guide (the whiteboard cheat)

Primary axis = **known-upfront decomposition vs runtime decomposition.**

|Situation|Pattern|
|---|---|
|decomposable upfront, one linear path|**Sequential**|
|decomposable upfront, closed-set branch|**Routing**|
|decomposable upfront, independent subtasks|**Parallelization**|
|decompose dynamically at runtime, delegate|**Orchestrator-workers**|
|output needs iterative critique|**Evaluator-optimizer**|
|plan first, then execute typed steps|**Planner-executor**|
|can't decompose at all, verify-as-you-go|**Autonomous agent**|

Then: pick the least powerful that clears the bar.

---

## Patterns

### 1. Sequential (prompt chaining)

- **▸ Trigger:** "step A then B then C," fixed pipeline, each step feeds the next, no branching.
- **▸ Say-it-out-loud:** "Fixed chain of LLM calls — each node's output is the next node's input. Use when the path is known and linear: highest reliability, lowest flexibility."
- **▸ Use / refuse:** use when the path is deterministic; refuse the moment you need branching (→ routing) or the plan isn't knowable (→ agent).
- **Fails when —** a mid-chain step emits malformed output → every downstream step compounds it. **Mitigate —** validate each step's output against a schema before passing on (Pydantic — see P5); gate-check between steps.
- _Analogy:_ pizza — base → sauce → toppings → bake.

### 2. Routing

- **▸ Trigger:** "classify, then handle differently," distinct input categories.
- **▸ Say-it-out-loud:** "A cheap classifier picks one of N branches; each branch gets a focused prompt. Converts an open-ended input into a closed-set decision — highest-ROI pattern."
- **▸ Use / refuse:** use when inputs fall into distinct categories needing different handling; refuse if there's really only one path (just do the task).
- **Fails when —** misclassification routes to the wrong branch → confidently wrong downstream. **Mitigate —** a fallback/"general" branch; log routing decisions and eval the router itself (routing accuracy is a metric).
- _Correct framing (from gate):_ the reason isn't "attention" hand-waving — it's that each branch gets a **focused prompt** instead of one overloaded catch-all.

### 3. Parallelization (sectioning / voting)

- **▸ Trigger:** "independent subtasks," "run these at once," "run N times and vote."
- **▸ Say-it-out-loud:** "Split into independent subtasks run concurrently (sectioning), or run the same task N times and aggregate (voting). Key property: subtasks **don't depend on each other's output**, and the decomposition is **known upfront**."
- **▸ Use / refuse:** use when subtasks are independent AND known in advance; refuse when a subtask needs another's output (→ sequential) or the subtasks can't be predetermined (→ orchestrator-workers).
- **Fails when —** you use it on tasks that actually have dependencies → incoherent merge / ordering bugs. **Mitigate —** dependency-check before parallelizing; if dependent, it's not this pattern.
- _Analogy:_ two engineers, independent features, merge at the end.

### 4. Orchestrator-workers (= supervisor-worker)

- **▸ Trigger:** "can't predict the subtasks upfront," "break it down at runtime and delegate."
- **▸ Say-it-out-loud:** "An orchestrator decomposes the task **at runtime** and delegates to workers (often sub-agents with isolated context windows), then merges results. Use when the decomposition itself is dynamic."
- **▸ Use / refuse:** use when decomposition is runtime-dynamic; refuse when subtasks are knowable upfront (that's parallelization). **Separating axis: known-upfront vs runtime.**
- **Fails when —** a worker gets insufficient context, returns wrong output, and the orchestrator builds the final answer on that bad piece → error propagates through the aggregation step. **Mitigate —** scope enough context to each worker; validate worker outputs before merge. (Isolated windows are a _benefit_ — clean context — AND the _failure vector_ — missing context. Same property, two faces.)
- **Numbers to drop:** multi-agent ≈ **~18% token overhead** + opaque debugging, for often-marginal quality. `[FLAG: from roadmap — verify exact figure/source before quoting live.]`
- _Example (correct, from gate):_ Cursor plan-mode agent deciding which modules to explore at runtime = orchestrator-workers.

### 5. Evaluator-optimizer (= reflection loop)

- **▸ Trigger:** "generate, critique, revise," "iterate until good enough," clear eval criteria.
- **▸ Say-it-out-loud:** "One LLM generates, a second critiques against criteria, loop until 'good enough' or max iterations. Reserve for **high-value, low-volume** tasks where refinement measurably helps and you can articulate the criteria."
- **▸ Use / refuse:** use when critique is cheap to articulate and improves output; refuse for high-volume/low-value (too expensive) or when "good" can't be specified.
- **Fails when — (a)** no stopping condition → loop runs forever, burns tokens. **Mitigate —** hard max-iteration bound (counter in state + conditional edge to END).
- **Fails when — (b)** the evaluator itself is miscalibrated → **self-reinforcing incorrect reasoning**: the critic launders its own error into "refined" output. **Mitigate —** calibrate the judge against human labels (see P4 LLM-as-judge); a bad critic _amplifies_ error.
- _Personal-gold:_ failure (b) was **your** gate insight — deeper than the textbook "no bound." Hold **both**.

### 6. Planner-executor

- **▸ Trigger:** "write a full plan first, then execute it," "plan as inspectable data."
- **▸ Say-it-out-loud:** "One model writes a typed, inspectable plan upfront; a separate loop executes each step with validation between. The point: the plan is **data you can log / inspect / gate** before any expensive execution."
- **▸ Use / refuse:** use when you want to review/gate the plan before acting, or planning and doing benefit from separation; refuse when the plan can't be known until mid-task (→ orchestrator-workers / agent).
- **Fails when —** a plausible-but-impossible plan → the executor is dumb-by-design and faithfully executes the flaw off a cliff. **Mitigate —** inspect/gate the plan before execution (this is _why_ plan-as-data matters); bounded re-plan on dead ends.
- _vs orchestrator-workers:_ planner-executor = one fixed plan, no sub-agents, executor trusts the plan. OW = dynamic delegation to sub-agents.

### 7. Autonomous agent (the full loop)

- **▸ Trigger:** "can't decompose upfront but can verify progress," open-ended.
- **▸ Say-it-out-loud:** "Input (human or trigger) → LLM at the center with tools + memory → loop: decide next action, act, observe ground truth, repeat until done or blocked. Reserve for tasks you genuinely can't hardcode, where the environment gives verifiable feedback each step."
- **▸ Use / refuse:** use when the path is unknowable AND each step yields verifiable feedback (tool results, tests, screenshots); refuse when a workflow would do — agents trade predictability for flexibility and each turn compounds cost + error risk.
- **Fails when —** no ground-truth signal each step → drifts, can't tell if it's progressing. **Mitigate —** ensure verifiable feedback per step; HITL checkpoint at blockers / irreversible actions.
- _Note:_ HITL is a **requirement, not a pattern** — mandatory for any irreversible action (see P7). Agent capabilities (memory types, tools/MCP, RAG) belong to **P2 / P3 / P8** — cite by name, don't re-explain here.

---

## 8. Vocab bridge (roadmap ↔ Anthropic)

|Roadmap term|Anthropic term|
|---|---|
|sequential|prompt chaining|
|router|routing|
|reflection loop|evaluator-optimizer|
|supervisor-worker|orchestrator-workers|
|planner-executor|_(no exact name — workflow cousin of orchestrator-workers)_|
|parallelization|parallelization (sectioning / voting)|

---

## 9. My Learnings (Personal — from the gate) — _highest-signal section_

**1. Missed prompt chaining in the taxonomy.**

- Scenario: "explain the patterns." Listed routing / parallelization / OW / evaluator-optimizer — dropped **sequential**.
- **Rule:** sequential is the _foundation_ pattern and one of the four S1 lab patterns. Six-pattern checklist, never skip: `seq · route · parallel · OW · eval-opt · planner-exec` (+ agent).

**2. Confused parallelization vs orchestrator-workers.**

- Scenario: CareerOps example (batch 20 **known** job sites to sub-agents) — I called it orchestrator-workers.
- Correction: 20 sites known upfront = **parallelization/sectioning**, not OW.
- **Rule (separates half of all pattern selection):** _known-upfront decomposition → parallelization; runtime decomposition → orchestrator-workers._

**3. Forgot the stopping condition on a revise-loop.**

- Scenario: ad-copy Q — described the generate→check→revise loop, walked past the bound.
- **Rule:** any loop (evaluator-optimizer, agent) needs a **max-iteration bound** or it runs forever + burns tokens. LangGraph won't add it for you — counter in state + conditional edge to END.
- Got right: the deeper evaluator-optimizer failure = a miscalibrated critic self-reinforcing its own error.

**4. Calibration note to self.** Blended knowledge hid which parts were load-bearing — the axis in #2 I "knew" but couldn't _deploy_ on a new frame (the PDF-vs-research question). **Recall ≠ selection.** Drill novel framings, not definitions.

---

## 10. Quick Recall (scan in 5 min — doubles as system-design cheat sheet)

|Scenario / interview prompt|Reach for|One-line justification|
|---|---|---|
|classify ticket, then handle by type|Routing|closed-set decision → focused branch prompt|
|step A→B→C, each feeds next, no branches|Sequential|known linear path, max reliability|
|independent subtasks, known upfront|Parallelization|no inter-dependency + known decomposition|
|same task N times, want confidence|Parallelization (voting)|aggregate to cut variance|
|can't predict subtasks, break down at runtime|Orchestrator-workers|dynamic decomposition + delegate|
|generate → critique → refine until good|Evaluator-optimizer|iterative gain + articulable criteria (**bound it!**)|
|review the plan before acting|Planner-executor|plan-as-data, gate before execution|
|can't hardcode path, but can verify each step|Autonomous agent|unknowable path + ground-truth feedback|
|irreversible action anywhere|HITL gate (not a pattern)|requirement — see P7|
|tempted to reach for multi-agent|**Stop → router + good tools first**|multi-agent only for genuinely parallel/independent subtasks or genuinely different prompts/tools/models|

---

_Prime directive, restated: least powerful pattern that passes evals. Authority shrinks as blast radius grows._