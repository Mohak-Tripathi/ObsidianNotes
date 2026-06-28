# Layer 3 Roadmap v2 — Execution & Tracking Layer

> Pair this with v1 (theory, architecture, failure modes). v1 = _what & why it's hard_. This = _what you build, how you measure it, what it becomes, and the one thing to read._
> 
> Rule: every pillar ends in a number you can report back. If you can't measure it, you haven't learned it — you've read about it.

---

## How to track (so you can share progress and move with confidence)

For each pillar/project, you produce a **Block Card**:

- **Built:** the artifact (repo/module link)
- **Metric hit:** the actual number vs the target
- **Proof:** the trace/eval-run/dashboard screenshot
- **Verdict:** PASS / PARTIAL / REDO
- **Feeds:** which big project this block plugs into

A pillar is _done_ when the metric target is hit **and** the block is reusable in a big project. Not when you "understand it." Template at the bottom — fill it and send it to me; I'll tell you if the metric is real or if you're fooling yourself (the most common failure).

---

# Part 1 — Pillar Execution Cards

Each card: **Build (what + why) · Tools (why this one) · Measurable outcome (metric + "you've got it when") · Building-block fit · Must-read.**

---

## P1 — Orchestration Patterns

**Build:** _The Pattern Lab._ One task implemented 4 ways (sequential / router / planner-executor / supervisor-worker) on a shared eval set. **Why:** You can't choose the right topology until you've _felt_ the cost of the wrong one. This is the experiment that kills your instinct to reach for multi-agent.

**Tools — why this one:**

- **LangGraph** — graph = explicit state machine; you _see_ and control every branch/retry/loop. Other frameworks hide control flow; you need it visible to learn. Time-travel debugging makes failures legible.
- (Fold-in: **state machines** multiplier lives here — LangGraph _is_ "make the implicit state machine explicit.")

**Measurable outcome:**

- Metric: a table of tokens / latency / success-rate / lines-to-debug across all 4 patterns on ≥30 eval cases.
- **You've got it when:** given a _new_ task, you pick the pattern on the first try and justify it in ≤3 numbers — and you default to the simplest that passes.

**Building-block fit:** the router becomes the front door of every big project; the graph scaffold is reused everywhere.

**Must-read:** Dex Horthy, **"12-Factor Agents"** (HumanLayer — GitHub repo + AI Engineer talk). The single best "agents are mostly software, own your control flow" piece. Non-negotiable, ~30 min.

---

## P2 — Context Engineering

**Build:** _Context Manager + Inspector._ A module that, given task + history + retrieved candidates + token budget, returns the optimal window — and logs exactly what went in. **Why:** Context is your RAM and your bill. This module is invisible infrastructure every later project leans on.

**Tools — why this one:**

- **tiktoken + your own budget enforcer** — there's no framework for this; it's code. That's the point.
- **A reranker** (Cohere Rerank or a cheap LLM-as-reranker) — lets you inject 3 great chunks instead of 30 mediocre ones.

**Measurable outcome:**

- Metric: **tokens-per-call reduced ≥40%** on a real task with **no accuracy drop** on your eval set; "lost-in-the-middle" failures eliminated on a probe set.
- **You've got it when:** tightening the window _raises_ accuracy and you can show the curve.

**Building-block fit:** powers memory retrieval (P3), every agent in every project, and your cost numbers (P6).

**Must-read:** Anthropic, **"Effective Context Engineering for AI Agents"** (Anthropic engineering blog, 2025). The clearest treatment of context-as-state and tool design.

---

## P3 — Memory Systems

**Build:** _Memory Service_ — `remember(fact, source, confidence)` / `recall(query, k)` / `resolve_conflict(...)`, with dedup, recency-weighted retrieval, decay, and **Postgres = truth, vector DB = index.** **Why:** This is _memory learning_ (your "second memory" — persistent, per-user). It's the dominant personalization pattern and the seed of your moat. Note: this is NOT model training — it's retrieval.

**Tools — why this one:**

- **PostgreSQL** — source of truth; you must be able to audit and correct memory, which a vector store alone can't do.
- **Qdrant or pgvector** — semantic index over memory. Start pgvector (smaller stack); move to Qdrant when scale hurts.
- **Redis** — working memory / "first memory" (ephemeral session). Cheap, fast.

**Measurable outcome:**

- Metric: **recall@k ≥ 0.8** on a held-out preference set; **zero contradictory outputs** across ≥20 designed conflict cases; dedup rate reported.
- **You've got it when:** the system gives consistent answers after you feed it contradictory facts over time (conflict resolution + decay actually work).

**Building-block fit:** becomes the memory core of the Personal OS; the same write/read pipeline serves the memory _graph_ later.

**Must-read:** the **MemGPT paper** (Packer et al. — "LLM as an OS managing its own memory"; productized as Letta). Read for the _mental model_ of self-managed memory tiers, not as a library to copy.

---

## P4 — Evals

**Build:** _Eval Harness._ ≥50 cases, structural scorers + a calibrated LLM-judge, wired into CI as a merge gate. **Why:** Without this every later "improvement" is a vibe. Evals are how you'll _prove_ the metrics in every other card. This is the highest-leverage pillar; build it early.

**Tools — why this one:**

- **Braintrust** — eval + trace in one, generous free tier, CI gates, one-click "production trace → test case." Lowest friction to the loop that matters.
- **DeepEval / Confident AI** — 50+ research-backed scorers (faithfulness, hallucination, tool-selection) if you want them off-the-shelf.
- **Promptfoo** — red-teaming / adversarial cases, local, YAML.

**Measurable outcome:**

- Metric: **LLM-judge ↔ your-labels agreement ≥ 80%** (calibrate before you trust the judge); CI gate catches an **injected regression 100%** of the time; track correctness/hallucination/latency/cost/tool-success as a _vector_.
- **You've got it when:** a "helpful" prompt change that secretly breaks 50 cases gets blocked automatically.

**Building-block fit:** the quality gate for every project; the dataset is fed by production failures forever (loops into P9).

**Must-read (non-negotiable, the whole set):** Hamel Husain — **"Your AI Product Needs Evals,"** **"Creating a LLM-as-a-Judge That Drives Business Results,"** **"A Field Guide to Improving AI Products"** (all on hamel.dev). If you do nothing else from this list, do these. The "Critique Shadowing" method for trustworthy judges is gold. (His AI Evals course with Shreya Shankar if you want the cohort version.)

---

## P5 — Failure Engineering

**Build:** _Resilient Workflow._ A 4–5 step workflow with real side effects (research → draft → persist → notify), with failure injected at every step, made idempotent + resumable, with a saga to undo partial work and a dead-letter queue. **Why:** Probabilistic systems fail constantly and partially. This is the pillar that compounds fastest — every failure you survive is a lesson no tutorial has.

**Tools — why this one:**

- **Temporal** — durable execution, retries, sagas as _first-class_; a crashed workflow resumes from the last good step. Heavyweight but this is the canonical answer to long-running reliability.
- **LangGraph checkpointing** — lighter durable-execution for the non-Temporal cases.
- **Pydantic** — schema-validate every model output before you act on it.

**Measurable outcome:**

- Metric: system reaches **correct-or-safe state 100%** of injected-failure runs; **zero duplicate side effects** across ≥50 retried runs (idempotency proven); resume-from-checkpoint demonstrated; dead-letter queue catches exhausted retries.
- **You've got it when:** you can kill the process mid-run and it recovers without corruption or double-charging.

**Building-block fit:** the reliability skeleton under every long-running workflow in all 3 big projects.

**Must-read:** Anthropic, **"Building Effective Agents"** (Anthropic, Dec 2024) — workflow-vs-agent distinction and the patterns that survive production. Pair with 12-Factor Agents (already cited).

---

## P6 — Cost Engineering

**Build:** _Model Router + Cache._ Cheap model for routing/extraction, capable model for reasoning, gated by your eval set so quality holds; add semantic + prompt caching. **Why:** Same architecture can cost 5–10×. Cost is a design constraint, not an afterthought — and routing is also a _reliability_ lever (small models are more predictable on narrow tasks).

**Tools — why this one:**

- **LiteLLM / Portkey / OpenRouter** (gateway) — one SDK for many providers, plus routing, caching, fallbacks, and **cost attribution** so you can actually measure per-task spend.
- (Fold-in: **model routing** multiplier lives here.)

**Measurable outcome:**

- Metric: **cost-per-successful-task down ≥40%** vs single-premium-model baseline, **with quality held** on the eval set; cache hit-rate reported.
- **You've got it when:** you can show the cost/quality Pareto frontier of your system and name your operating point.

**Building-block fit:** keeps every big project economically viable at scale; the per-task cost metric feeds the meta-review (P9).

**Must-read:** _(none mandatory — this is mostly your own measurement; the applied-llms piece below covers the strategy.)_

---

## P7 — Trust Systems

**Build:** _Trust Layer._ Add to the resilient workflow: a blast-radius classifier, an approval gate on the irreversible step **with a real preview (dry-run)**, and an immutable audit log recording decision + evidence + rationale + model version. **Why:** Autonomy without trust is liability. **This is where Layer 4 money lives** — in domains where mistakes are expensive, the trust layer _is_ the product.

**Tools — why this one:**

- **LangGraph interrupts** (interrupt-before-tool / resume) — native suspend/resume for human approval, no custom plumbing.
- **Postgres append-only tables** — immutable audit you can hand to a skeptical reviewer/regulator.
- (Fold-in: **human-override design** multiplier lives here — decide what must _never_ be automated.)

**Measurable outcome:**

- Metric: **100% of irreversible actions gated**; **any action's decision+evidence+rationale reconstructable from the audit log alone**; dry-run preview matches actual outcome on ≥20 cases.
- **You've got it when:** someone who's never seen the code can read one audit record and understand exactly why the system did what it did.

**Building-block fit:** the gate on every consequential action in all 3 projects; the thing that makes a Layer 4 pitch credible.

**Must-read:** _(covered by Building Effective Agents + your domain's regulatory docs later — no generic must-read.)_

---

## P8 — Observability

**Build:** _Trace Everything._ OTEL-based tracing across all prior modules; a dashboard where any user goal shows the full decision tree with cost + quality per step; "replay this trace" works. **Why:** You can't fix what you can't see. Traces are the most valuable data you generate, and the substrate for the entire learning loop (P9).

**Tools — why this one:**

- **OpenTelemetry** — vendor-neutral substrate so you're never locked in.
- **LangSmith** (deepest LangGraph integration, time-travel) **or Langfuse** (OSS, self-host, OTEL-native) **or Braintrust** (trace+eval together).
- **Latitude** — worth a look: agent-_session_-native, closes the loop production-failure → auto-generated eval.

**Measurable outcome:**

- Metric: **any user goal fully reconstructable from its trace alone** (no log spelunking); **online eval on ≥1% of traffic** with an **alert that fires on an injected quality drop**.
- **You've got it when:** a bug report becomes "open the trace, see the cause" instead of "try to reproduce."

**Building-block fit:** the nervous system every project runs on; the raw material the meta-orchestrator (P9) reasons over.

**Must-read:** **"What We Learned from a Year of Building with LLMs"** (applied-llms.org — Yan, Bischof, Frye, Husain, Liu, Shankar). The best operational/strategic field notes in the space; read once now, again in 3 months.

---

# P9 — System Learning, Self-Healing & Meta-Orchestration _(the new flagship pillar)_

This is the part you're most excited about, and it's correctly identified as the deep end of Layer 3. Read this carefully — it's where "the system learns" stops being a non-techie hand-wave and becomes engineering.

### The one distinction that fixes everyone's confusion

**The system learns ≠ the model learns.** RL / weight updates = what Anthropic/OpenAI do to _base models_. Expensive, slow, not yours. What you build is **externalized reinforcement: the _environment_ learns, not the model.** Three mechanisms, increasing depth:

- **Contextual learning** (your "first memory") — session-only preference injection. Ephemeral. Redis.
- **Memory learning** (your "second memory") — persistent, per-user. Postgres + vector DB. (Built in P3.)
- **Policy learning** (this pillar) — the _system's own behavior_ improves: prompts, flows, routing, state transitions change because outcomes told you to.

### Meta-orchestration: two layers

- **Layer A — Runtime intelligence:** handles user requests (refunds, scheduling, reviews).
- **Layer B — Meta intelligence:** _observes Layer A._ Where do retries spike? Where does latency rise? Where do users abandon? Where do hallucinations cluster? Where does trust break?

The compounding loop is **Layer B watching Layer A**: `Run → Observe → Detect patterns → Recommend fixes → Human validates → Improve`

### This is SRE — for cognition

Traditional SRE monitors CPU/memory/latency/downtime. **Layer 3 SRE** monitors **hallucination rate, tool-failure rate, retry rate, trust failures, abandonment points, cost spikes, semantic drift.** Same discipline, new signals. (This is why Layer 3 is _cognitive systems engineering_, not coding.) Your P8 observability is the instrumentation; this pillar is the on-call brain reading it.

### The self-healing ladder (target L3–L4)

- L0 static → L1 human observes+fixes → L2 system surfaces, human fixes → **L3 system suggests fix, human approves** → **L4 system proposes code change (PR), human reviews** → L5 self-patches (dangerous; not your target).

### Knowledge graph vs memory graph

- **Knowledge graph** = objective world facts (`Stripe → payments`). Generic, commoditized.
- **Memory graph** = the user-specific _evolving_ graph (`user → prefers mornings → strong in backend → building AI startup`). Personal, dynamic. **This is your moat** — "who the user is becoming," not just "what they did."

**Build:** _The Meta-Orchestrator (Monthly System Review Agent)_ — exactly your idea. A standing agent that, on a schedule (or on demand: "analyze how to improve the system"):

1. Ingests last month's traces/logs/eval-scores (from P8).
2. Synthesizes failure _mechanisms_, not just incidents (clusters: "refund requests spike after checkout timeout"; "auth bugs recur on middleware changes").
3. Produces a **ranked issue list** with proposed fixes (prompt/flow/routing changes, or code changes).
4. (L3) You approve → it applies config/prompt fixes. (L4) It opens **PRs**; you review and merge.
5. The fix's effect is measured against the eval set next cycle — closing the loop.

**Why:** This is the transition from _software_ to _living systems_ — systems that remember, observe, critique, adapt, improve. It's one of the strongest moats in AI systems and the capstone proof you're operating at Layer 3.

**Tools — why this one:**

- **Your P8 traces (LangSmith/Langfuse/Braintrust)** as the input corpus — the meta-agent reasons over _real_ production data, not vibes.
- **Latitude** specifically targets the production-failure → eval loop; study it even if you build your own.
- **GitHub API / Claude Agent SDK** for the L4 "propose a PR" step (the Claude Agent SDK loop is built for exactly this: hooks, tools, sub-agents, code edits with a human gate).
- **A queue/cron (Temporal or simple scheduler)** to run the review on a cadence.

**Measurable outcome:**

- Metric: the monthly review produces a ranked issue list where **≥60% of its top-5 suggestions are ones you'd actually action**; demonstrate **L2→L3** (system suggests, you approve, metric improves next cycle); ideally one **L4** PR merged; show a tracked metric (e.g., retry rate or abandonment) _fall_ after a meta-suggested fix.
- **You've got it when:** you can point to a graph where a problem the _system_ found and proposed fixing went down after you approved its fix. That graph is your Layer 3 diploma.

**Building-block fit:** sits atop _all_ projects; the Personal OS, Repo Intelligence, and Research Engine each get a Layer B. This is the thing that makes them improve without you.

**Must-read:** Hamel Husain, **"A Field Guide to Improving AI Products"** (hamel.dev) — it _is_ the policy-learning/improvement loop, written by someone who's done it for money. (The eval trilogy from P4 is the substrate.) Beyond this, the literature is thin and fast-moving — you'll be writing the blog posts others read.

---

# Part 2 — Projects (with success metrics + blocks assembled)

Each project = an assembly of the blocks above + one signature capability. Don't start a big project until its prerequisite blocks are PASS.

### Big Project 1 — Personal OS

**Assembles:** P1 router, P2 context mgr, P3 memory service, P4 evals, P5 resilient workflow, P7 trust gate, P8 tracing, **P9 Layer B.** **Signature:** the memory graph + the "what did my agents do while I slept" digest (a trace query). **Success metrics:** runs daily doing real work; ≥1 standing long-running monitor; trust gate on 100% of outbound actions; eval set curated _from your own corrections_; **one meta-suggested improvement shipped and measured.**

### Big Project 2 — Repo Intelligence

**Assembles:** P2 (subgraph retrieval), P3 (code _memory graph_), P4 (false-positive discipline), P7 (advisory + HITL merges), P8, **P9 (accept/reject → policy learning).** **Signature:** the code memory graph (files/symbols/tests/owners/deploys as nodes; calls/imports/modifies as edges), updated per commit. **Success metrics:** PR-review **precision ≥ X, false-positive rate ≤ Y** on labeled real PRs (false positives are what kill these tools); suggestion **acceptance rate** rising over time as the policy loop learns.

### Big Project 3 — Autonomous Research + Decision Engine

**Assembles:** P1 (planner-executor), P2, P4 (faithfulness/calibration), P7 (provenance + trust scoring), P8. **Signature:** contradiction detection (surface disagreement, never fake consensus) + per-claim trust scoring. **Success metrics:** **faithfulness ≥ X** (synthesis traces to sources), contradiction-detection **recall ≥ Y**, trust-score **calibration** within Z of ground truth; every conclusion auditable to evidence. **Why this is the Layer 4 bridge:** it's a _decision_ engine in a high-entropy domain — build it _inside_ the domain you intend to own (see analysis in chat).

---

# Part 3 — Consolidated Must-Read List (curated, no clutter)

**Read first (foundations):**

1. Chip Huyen — **"AI Engineering"** (O'Reilly, 2025). The one book; the map of the whole territory.
2. **"What We Learned from a Year of Building with LLMs"** — applied-llms.org. Field notes; reread quarterly.

**Per discipline (only the canonical ones):** 3. Anthropic — **"Building Effective Agents"** (Dec 2024) → orchestration/failure. 4. Dex Horthy — **"12-Factor Agents"** (HumanLayer) → control flow/state/reliability. 5. Anthropic — **"Effective Context Engineering for AI Agents"** (2025) → context. 6. Hamel Husain — **evals trilogy** ("Your AI Product Needs Evals" / "Creating a LLM-as-a-Judge That Drives Business Results" / "A Field Guide to Improving AI Products"), hamel.dev → evals + the improvement loop. **The highest-ROI reading on this list.** 7. **MemGPT paper** (Packer et al.) → memory mental model.

That's it. Seven sources. Anything beyond this is procrastination disguised as preparation.

---

# Part 4 — Block Card Template (fill + share back)

```
BLOCK: P_ — <name>
Built:        <repo / module link>
Target:       <the metric target from the card>
Metric hit:   <actual number>
Proof:        <trace link / eval run / dashboard shot>
Verdict:      PASS | PARTIAL | REDO
Feeds:        <which big project>
Notes:        <what surprised you / what broke>
```

Send me a filled card and I'll pressure-test whether the metric is real or whether the number is flattering you. That's the fastest way to move with confidence instead of false confidence.

---

_System learns ≠ model learns. Postgres is truth. The simplest pattern that passes evals wins. The graph where a system-found problem goes down after a system-proposed fix — that's the finish line._