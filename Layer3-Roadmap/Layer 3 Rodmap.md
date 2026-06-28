# Layer 3 Roadmap — Engineering Predictable Behavior from Probabilistic Intelligence

> Definition you're building toward: **reliable, autonomous, long-running systems under uncertainty.** Operating principle: you don't _learn_ Layer 3, you _survive_ it. Optimize for production scars, not chapters read.

---

# Part 1 — Pillar-by-Pillar Deep Dive

For each pillar: theory → mental model → production architecture → common mistakes → failure cases → beginner vs advanced → tools → what to build.

---

## Pillar 1 — Orchestration Patterns

**Theory.** An agent is a control loop wrapped around a probabilistic function. Orchestration is deciding the _topology_ of that loop: who calls whom, in what order, with what authority to branch, retry, or stop. The model supplies reasoning; the topology supplies guarantees.

**Mental model.** The LLM is an unreliable contractor with good instincts. Orchestration is the project manager that breaks work into verifiable units, checks each one, and refuses to let one bad decision cascade. Every pattern is a different answer to: _how much do I trust the model to decide what happens next?_

**Production architecture.**

- **Sequential** — deterministic pipeline, model fills steps. Use when the path is known. Highest reliability, lowest flexibility.
- **Router** — a cheap classifier model picks one of N downstream branches. The single highest-ROI pattern: it converts an open-ended problem into a closed-set decision.
- **Planner-executor** — one model writes a plan (a typed list of steps), a separate loop executes each step with validation between. The plan is _data you can inspect, log, and gate_, which is the whole point.
- **Reflection loop** — generate → critique → revise, bounded by max iterations + a "good enough" check. Expensive; reserve for high-value, low-volume tasks.
- **Supervisor-worker** — a supervisor decomposes and delegates to specialized sub-agents, merges results. Powerful and the most failure-prone (see below).
- **Human-in-the-loop (HITL)** — execution suspends at a checkpoint, waits for approval, resumes. This is not a pattern, it's a _requirement_ for any irreversible action.

The non-obvious truth: **most "multi-agent" systems should be a single well-designed agent with a router and good tools.** Multi-agent earns its complexity only when subtasks are genuinely parallel and independent, or need genuinely different system prompts/tools/models.

**Common mistakes.**

- Reaching for supervisor-worker when a router + sequential chain would do. Multi-agent multiplies failure surface (~18% token overhead and opaque debugging for marginal quality).
- Letting the model decide control flow that should be hard-coded. If the next step is deterministic, _make it deterministic._
- No max-iteration bound on loops → infinite reflection / runaway token spend.

**Failure cases.** Loops that never terminate; sub-agents that silently disagree and the supervisor picks the wrong one; context loss across handoffs; a planner that produces a plausible-but-impossible plan the executor blindly attempts.

**Beginner vs advanced.** Beginner knows the patterns and uses them. Advanced knows _when not to_ — and defaults to the least powerful pattern that works. Advanced designs the graph so that the model's authority shrinks as the action's blast radius grows.

**Tools.** LangGraph (directed graph, conditional edges, cycles, subgraphs, checkpointing, durable execution, HITL — the production default in 2026). Claude Agent SDK (the loop that powers Claude Code; hooks, MCP, skills, subagents — strongest for Anthropic-native production). For TypeScript: Mastra. Avoid CrewAI for anything you'll have to debug at 2am.

**What to build.** Take ONE task and implement it four ways — sequential, router, planner-executor, supervisor-worker. Measure tokens, latency, success rate, and _debuggability_ on the same eval set. You'll feel in your bones why the simplest one usually wins.

---

## Pillar 2 — Context Engineering

**Theory.** The model only knows what's in the window right now. Context engineering is the discipline of deciding, on every single call, what goes in, what stays out, what gets compressed, and what gets retrieved. This is the highest-leverage and least-taught pillar.

**Mental model.** Context is RAM, not disk. It's small, expensive, and shared by everything: system prompt, tools, history, retrieved docs, scratchpad. Every token you spend on noise is a token of attention stolen from signal. Treat the window like a budget you actively allocate, not a bucket you fill.

**Production architecture.**

- **Layered context**: static (system prompt, tool defs) → semi-static (user profile, task spec) → dynamic (retrieved chunks) → volatile (recent turns, scratchpad). Assemble per-call from these layers; never just append.
- **Compaction**: when history grows, summarize older turns into a running state object. Keep the summary structured (JSON), not prose — structured summaries don't drift.
- **Retrieval injection**: retrieve _just-in-time_ and _just-enough_. Rerank, then inject the top-k, not the top-50.
- **Isolation**: give sub-agents their own clean windows. Don't let one agent's mess pollute another's context.

**Common mistakes.** Dumping entire documents in. Keeping full chat history forever. Retrieving by similarity alone without reranking. Putting tool _results_ back verbatim when a one-line summary would do.

**Failure cases.**

- **Context poisoning** — a hallucinated fact enters context, gets summarized as truth, and now contaminates every downstream decision.
- **Context drift** — over a long session the running summary slowly diverges from reality.
- **Lost-in-the-middle** — critical info buried in the middle of a huge window gets ignored by the model.
- **Distraction** — irrelevant retrieved chunks pull the model off-task.

**Beginner vs advanced.** Beginner asks "how do I fit more in?" Advanced asks "what can I _remove_?" Advanced treats context assembly as a function with its own tests, measures the marginal value of each token category, and knows that a tighter window often _raises_ accuracy.

**Tools.** Your own assembly layer (this is mostly code, not a library). Reranking: Cohere Rerank, or a cheap LLM-as-reranker. Token accounting: tiktoken + your own budget enforcer.

**What to build.** A context manager module: given a task + history + retrieved candidates + token budget, it returns the optimal window. Add a "context inspector" that logs exactly what went into each call. You will use this in every future project.

---

## Pillar 3 — Memory Systems

**Theory.** Memory is what makes a system persistent rather than amnesiac. Four types, mapped to human memory: **working** (current session), **episodic** (past interactions/events), **semantic** (facts the system knows), **procedural** (learned how-to behaviors). Each has different storage, retrieval, decay, and correction needs.

**Mental model.** Memory is not "save everything to a vector DB." Memory is a _curated, ranked, decaying, correctable_ representation of what's worth remembering. The hard problems are not storage — they're **retrieval relevance, ranking, conflict resolution, and forgetting.**

**Production architecture.**

- **Working** → in-process state / Redis. Cheap, fast, ephemeral.
- **Episodic** → append-only event log (Postgres) + embeddings for semantic recall (vector DB).
- **Semantic** → structured facts in Postgres + optional knowledge graph for relationships.
- **Procedural** → learned policies/preferences stored as structured records, retrieved and injected into context.
- **Write path**: extract → deduplicate against existing → resolve conflicts → store with timestamp + source + confidence.
- **Read path**: query → retrieve candidates → rerank by relevance _and recency_ → inject top-k.

**Common mistakes.** Storing raw transcripts as "memory." No deduplication (the same fact 40 times). No conflict resolution (user said X Monday, ¬X Friday — which wins?). No decay (stale preferences treated as current). Treating the vector DB as the source of truth instead of as an index over the source of truth (Postgres).

**Failure cases.** Memory conflicts producing contradictory behavior; stale memories overriding fresh reality; retrieval surfacing the wrong "similar" memory; unbounded memory growth degrading retrieval quality and cost over time.

**Beginner vs advanced.** Beginner = RAG over a doc store and calls it memory. Advanced = explicit memory types, a write pipeline with conflict resolution, recency-weighted retrieval, decay/correction, and the discipline that **Postgres is truth, the vector DB is a derived index.**

**Tools.** Postgres (truth) + pgvector or Qdrant (semantic index) + Redis (working). Mastra ships a 4-tier memory model if you're in TS. LangGraph's Store API for cross-session memory. Look at how Letta/MemGPT-style systems do memory management for ideas, but build your own.

**What to build.** A memory service with a clean interface: `remember(fact, source, confidence)`, `recall(query, k)`, `resolve_conflict(...)`. Include decay and a dedup step. This becomes the backbone of your Personal OS.

---

## Pillar 4 — Evals

**Theory.** Without evals you are flying blind: you cannot tell whether a prompt change, model swap, or new tool made the system better or worse. Evals turn "it feels better" into a number with a confidence interval. This is the single discipline that separates engineering from vibes.

**Mental model.** An eval is a regression test for a non-deterministic function. Because output varies, you test _distributions of behavior over a dataset_, not single outputs. Your eval set is your spec made executable.

**Production architecture.**

- **Datasets**: curated input → expected-output (or expected-property) pairs. Grow them from real production failures — every incident becomes a test case.
- **Scorers**: exact-match/structural checks where possible (cheapest, most reliable); LLM-as-judge for subjective quality (calibrate the judge against human labels); task-specific metrics (tool-selection accuracy, retrieval faithfulness, plan validity).
- **Offline evals**: run on every prompt/model/code change in CI. Gate merges on score thresholds.
- **Online evals**: score a sample of production traffic continuously; alert on score _drops_, not just latency spikes.
- **The loop**: production failure → annotate → add to dataset → it now guards against regression forever.

**Common mistakes.** No eval set at all (most common). Tiny eval set (10 cases) that overfits. LLM-judge that's never calibrated against humans. Measuring only accuracy and ignoring cost/latency/hallucination. Treating evals as a one-time exercise instead of a living asset.

**Failure cases.** Silent quality regression after a model provider updates their model under you; a prompt "improvement" that helps 5 cases and breaks 50; judge drift where the judge model itself changes behavior.

**Beginner vs advanced.** Beginner ships and watches for complaints. Advanced has a CI gate: no merge if the eval score drops. Advanced curates datasets from production, calibrates judges, and tracks correctness/hallucination/latency/cost/tool-success as a _vector_, not a scalar.

**Tools.** Braintrust (eval-first, generous free tier, CI gates, production-trace→test-case in one click). DeepEval / Confident AI (50+ research-backed metrics, OTEL-native). Promptfoo (red-teaming, YAML-driven, local). Langfuse if you want open-source self-hosted. Latitude is interesting for the closed loop: production failure → auto-generated eval.

**What to build.** Wrap your router-vs-pattern project from Pillar 1 in a real eval harness. 50+ cases, structural + LLM-judge scorers, a CI gate. Then deliberately regress a prompt and watch the gate catch it.

---

## Pillar 5 — Failure Engineering

**Theory.** Probabilistic systems fail constantly and partially. Failure engineering is designing for failure as the _default state_, not the exception. This is the fastest-compounding pillar because every failure you survive teaches a lesson no tutorial contains.

**Mental model.** Assume every external call fails, every model output is malformed, every tool returns garbage sometimes, and every long-running job gets interrupted halfway. Now design a system that still ends in a correct or _safely incomplete_ state. Aim for **idempotency and recoverability**, not for never failing.

**Production architecture.**

- **Validate every model output** against a schema (structured outputs / function calling / Pydantic) before acting on it. Reject-and-retry on parse failure.
- **Retries with backoff + jitter** on transient errors; a _retry budget_ so you don't loop forever.
- **Idempotency keys** on every side-effecting action so a retry can't double-charge / double-send.
- **Durable execution**: checkpoint state so an interrupted long-running workflow resumes from the last good step, not from zero.
- **Compensation / sagas**: for multi-step workflows with side effects, define how to _undo_ completed steps when a later step fails.
- **Circuit breakers**: when a dependency is failing, stop hammering it and degrade gracefully.
- **Dead-letter queues**: failures that exhaust retries go somewhere a human can inspect, not into the void.

**Common mistakes.** Trusting model output without validation. No idempotency → retries cause duplicate side effects. No partial-failure handling in multi-step flows → system left in a corrupt half-state. Treating timeouts as rare.

**Failure cases.** Partial execution (step 3 of 5 fails, steps 1–2 already touched the world); prompt injection via tool output; malformed JSON breaking the executor; a tool that succeeds but returns semantically wrong data.

**Beginner vs advanced.** Beginner handles the happy path and patches failures reactively. Advanced designs the failure taxonomy _first_, makes every action idempotent and every workflow resumable, and treats the dead-letter queue as a primary product surface.

**Tools.** Temporal (durable execution / sagas / retries as first-class — the heavyweight answer to long-running reliability). LangGraph's built-in checkpointing + durable execution for the lighter cases. Pydantic for output validation. Your queue (SQS/Kafka) for dead-letter handling.

**What to build.** Take a 4-step workflow with side effects (e.g., research → draft → save → notify). Inject failures at each step. Make it fully resumable and idempotent. Add a saga that undoes partial work. This single exercise is worth a month of reading.

---

## Pillar 6 — Cost Engineering

**Theory.** Tokens are money and latency. At scale, an architecturally identical system can cost 5–10× more than a tuned one. Cost engineering is treating spend as a first-class design constraint, not an afterthought.

**Mental model.** Every token has a price and a cheaper substitute almost always exists. The question on every call is: _what is the cheapest configuration that still passes the eval?_

**Production architecture.**

- **Model tiering**: cheap/small models for routing, classification, extraction; expensive/large models only for genuine reasoning. Mixing tiers typically cuts cost 40–60% with no quality loss on the cheap tasks.
- **Semantic caching**: cache by meaning, not exact string, so near-duplicate requests hit cache.
- **Prompt caching**: cache the static prefix (system prompt, tool defs, long context) across calls — major savings on repeated large prefixes.
- **Selective retrieval**: retrieve less; reranking lets you inject 3 great chunks instead of 30 mediocre ones.
- **Output bounding**: cap max tokens; structured outputs are shorter than prose.
- **Batch** where latency allows.

**Common mistakes.** One premium model for everything. No caching. Retrieving 50 chunks "to be safe." Unbounded output length. Not measuring cost-per-task until the bill arrives.

**Failure cases.** A reflection loop quietly 10×-ing spend; a retry storm during an outage; cost scaling super-linearly with users because context grows per session.

**Beginner vs advanced.** Beginner picks the best model and moves on. Advanced routes per-task, caches aggressively, measures cost-per-successful-task as a core metric, and knows the cost/quality Pareto frontier of their system.

**Tools.** LLM gateways for routing/caching/cost-attribution: LiteLLM, Portkey, Helicone, OpenRouter, or Braintrust Gateway. Per-request cost attribution in your observability layer.

**What to build.** Add a model router that sends easy cases to a small model and hard cases to a large one, gated by your eval set so quality holds. Report cost-per-successful-task before and after. Add semantic caching and measure hit rate.

---

## Pillar 7 — Trust Systems

**Theory.** Autonomy without trust is a liability. Trust systems are the controls that let a human (or auditor, or regulator) believe the system's actions are safe, reversible, and explainable. This is the gate between a demo and anything that touches money, health, law, or infrastructure.

**Mental model.** The more autonomous and irreversible an action, the more trust scaffolding it requires. Trust is engineered, not assumed: approvals, rollback, audit, simulation, explainability. **This is where Layer 4 money actually lives** — in domains where mistakes are expensive, the trust layer _is_ the product.

**Production architecture.**

- **Approval gates (HITL)**: irreversible/high-value actions suspend for human sign-off.
- **Rollback / reversibility**: prefer reversible actions; for irreversible ones, require stronger gates.
- **Audit trails**: immutable log of _what the system did, why, on what evidence, with what model/version/prompt._ Reconstructable after the fact.
- **Simulation / dry-run**: show what _would_ happen before it happens (preview the refund, the deploy, the email).
- **Explainability**: every consequential decision carries a human-readable rationale and the evidence it used.
- **Permissioning**: agents act with least privilege; destructive scopes are gated separately.

**Common mistakes.** Logging inputs/outputs but not _decisions and rationale_. No dry-run. Treating "the model said so" as justification. One permission level for all actions. Approvals that are rubber-stamps (no real preview).

**Failure cases.** An autonomous action causes harm and there's no audit trail to explain why; a destructive action with no rollback; an approval UI that humans click through blindly because it shows nothing useful.

**Beginner vs advanced.** Beginner adds approvals as an afterthought. Advanced designs the _blast-radius map_ first — classifying every action by reversibility and value — and matches trust scaffolding to each tier. Advanced makes the audit trail rich enough to satisfy a skeptical regulator.

**Tools.** LangGraph interrupts (interrupt-before-tool, resume) for HITL. Postgres append-only audit tables. Your own dry-run layer. Semantic Kernel / policy layers for enterprise governance if you go that route.

**What to build.** Add to your failure-engineering workflow: a blast-radius classifier, an approval gate on the irreversible step with a real preview, and an immutable audit log that records decision + rationale + evidence + model version. Then write the "explain this action" endpoint.

---

## Pillar 8 — Observability

**Theory.** You can't fix what you can't see. Observability is end-to-end visibility into every step an agent takes — LLM calls, tool invocations, retrieval, planning decisions, and the causal links between them. Unlike traditional APM (latency, errors), agent observability tracks _output quality, faithfulness, and behavioral drift._

**Mental model.** Observability is the nervous system. A trace is the unit: one user goal → the full tree of decisions, calls, costs, and outcomes that served it. If you can't reconstruct exactly what happened from the trace alone, you're blind.

**Production architecture.**

- **Tracing**: instrument every LLM call, tool call, retrieval, and decision as spans in a tree, with inputs/outputs/tokens/latency/cost.
- **Session-level view**: group spans by user goal, not just by request, so you reason about _outcomes_.
- **Quality monitoring**: run online evals on sampled traffic; alert on quality drops.
- **Drift detection**: watch for behavioral change over time (model updates, data shift).
- **Standardize on OpenTelemetry** so you're not locked to one vendor.

**Common mistakes.** Logging text but not structured spans. No cost/token per span. No way to replay a trace. Quality issues invisible because you only alert on latency/errors. Vendor lock-in via a non-OTEL tracer.

**Failure cases.** A quality regression that goes unnoticed for weeks; an incident you can't reproduce because the trace lacks the model version / prompt / retrieved context; cost blowup you can't attribute to a cause.

**Beginner vs advanced.** Beginner adds logging after something breaks. Advanced instruments from line one, treats traces as the most valuable data the system generates, and closes the loop: trace → annotated failure → eval case → regression guard.

**Tools.** LangSmith (deepest LangChain/LangGraph integration, time-travel debugging). Langfuse (open-source, self-hostable, OTEL-native; note: acquired by ClickHouse Jan 2026). Braintrust (trace + eval in one, fast). Arize Phoenix (OSS, drift/clustering). Latitude (agent-session-native, issue lifecycle). OpenTelemetry as the substrate. Datadog if you want LLM spans next to the rest of your APM.

**What to build.** Instrument _everything_ you've built so far with OTEL-based tracing. Build a dashboard that, for any user goal, shows the full decision tree with cost and quality per step. Make "replay this trace" work.

---

# Hidden Multipliers

## Multiplier 1 — Model Routing

Not "best model" but "best model per task." A cheap model routes and extracts; an expensive model reasons; a tiny model classifies. This is simultaneously a cost lever (40–60%), a latency lever, and a reliability lever (smaller models are more predictable on narrow tasks). Build a router whose decisions are themselves logged and eval'd. Gateways: LiteLLM/Portkey/OpenRouter.

## Multiplier 2 — State Machines

Agents are still state machines. The LLM _thinks_; the state machine _controls_. Predictability comes from constraining the model inside explicit states with explicit allowed transitions. When you feel a system getting unpredictable, the fix is almost always "make the implicit state machine explicit." LangGraph is literally this idea as a framework.

## Multiplier 3 — Human Override Design

The core question: _what must NOT be automated?_ Finance, legal, deploys, destructive/irreversible actions. Designing the override is a product and trust decision, not a technical afterthought. The art is making overrides rare enough to be worth automating around, but present wherever blast radius is high. Good override design is what lets you ship autonomy in regulated domains at all.

## Multiplier 4 — Learning Loops (Meta-Orchestration / Policy Learning)

The system improving itself _without_ retraining the model. Loop: observe → infer → store → retrieve → adapt → evaluate → correct → repeat. Three levels:

- **Contextual** (short-term, session) — temporary, not persistent.
- **Memory** (persistent, user-specific) — preferences and patterns in Postgres/Redis/vector DB. Most practical, biggest near-term moat.
- **Policy** (system-level) — find bottlenecks, suggest fixes, improve the workflow. This is _operational intelligence_ and the real long game.

Map this onto the **self-healing ladder** (target Level 3–4): system surfaces issues → suggests fixes → human approves → proposes code changes → (rarely) self-patches. Self-patching (L5) is dangerous; don't aim there yet.

---

# Part 2 — Layer 3 Project Roadmap

Build small, break things, then build big. Each big project is designed to force you through pillars you'd otherwise skip.

## Small Foundational Projects (1–3 weeks each)

**S1 — The Pattern Lab.** One task, four orchestration patterns (sequential / router / planner-executor / supervisor-worker), one shared eval harness. Deliverable: a table of tokens/latency/success/debuggability per pattern. _Strengthens:_ Orchestration, Evals, Cost.

**S2 — The Resilient Workflow.** A 4–5 step workflow with real side effects (research → draft → persist → notify). Inject failure at every step. Make it idempotent, resumable (checkpointed), with a saga to undo partial work and a dead-letter queue. _Strengthens:_ Failure Engineering, State Machines, Trust (approval on the irreversible step).

**S3 — The Memory Service.** A standalone memory microservice: `remember/recall/resolve_conflict`, with dedup, recency-weighted retrieval, decay, and Postgres-as-truth / vector-DB-as-index. Full tracing. _Strengthens:_ Memory, Context Engineering, Observability.

> After S1–S3 you have reusable modules (eval harness, resilient-workflow scaffold, memory service, context manager, tracing) that every big project reuses. **Do not skip these.** They are your standard library.

---

## Big Project 1 — Personal OS

An autonomous personal operating system: it ingests your inputs (email, notes, tasks, calendar), maintains a model of who you are and what you're doing, and runs long-running workflows on your behalf — answering "what did my agents do while I slept?"

**Architecture.**

- **Ingestion layer**: connectors (email, calendar, notes) → normalized event stream (Kafka or a queue) → extraction agents.
- **Memory core** (reuse S3, expanded): episodic (events), semantic (facts about you), procedural (your preferences/patterns), working (current session). The memory graph is the heart.
- **Orchestration layer** (LangGraph): a supervisor routes incoming events to specialized workers (triage, draft, schedule, summarize).
- **Long-running workflows** (Temporal or LangGraph durable execution): "monitor X and act when Y," running for days.
- **Trust layer**: every outbound action (send email, book event) goes through an approval gate with preview + audit log.
- **Observability**: full tracing; a morning digest = a query over last night's traces.

**Agents.** Triage (router, cheap model), Extractor (small model), Drafter (capable model), Scheduler (tool-heavy), Summarizer (capable model), Supervisor (orchestrates).

**Memory.** This is where the "memory graph" (who you're becoming) lives — a structured, evolving graph of context, distinct from raw workflow logs.

**Evals.** Did triage route correctly? Did extraction capture the right entities? Did drafts match your voice (LLM-judge calibrated against your edits)? Curate the eval set from your own corrections — _those corrections are your proprietary data moat in miniature._

**Trust.** Nothing leaves the system or hits the calendar without a gated preview. Audit log records decision + evidence + rationale.

**Observability.** "What did my agents do while I slept" is literally a trace query. Cost-per-task tracked.

**Long-running workflows.** Standing monitors ("watch for emails from investors," "if a meeting is double-booked, propose a fix").

**Learning loops.** Every time you correct a draft or reject an action, store it as procedural memory; future drafts adapt. This is contextual + memory learning made real.

_Strengthens:_ ALL eight pillars + memory/learning multipliers. This is your Layer 3 capstone.

---

## Big Project 2 — Repo Intelligence System

An agent that understands a codebase as a living system: reviews PRs, suggests refactors, understands architecture, knows the deployment surface, and improves its own suggestions over time.

**Architecture.**

- **Code memory graph**: parse the repo into a graph — files, modules, functions, call edges, ownership, change history (from git). Store structure in Postgres + graph relations; embeddings for semantic code search. This graph _is_ the system's understanding; RAG-over-files alone is not enough.
- **PR review agent**: on a PR, retrieve the relevant subgraph (changed files + their callers/callees + related tests), assess correctness/risk/style, produce a review with rationale and evidence (cited lines).
- **Refactoring intelligence**: detect smells across the graph (duplicated logic, high-fan-in modules), propose changes with blast-radius analysis from the call graph.
- **Architecture understanding**: answer "what depends on this?" and "what breaks if I change this?" from the graph, not from vibes.
- **Deployment awareness**: ingest CI/CD config + recent deploy history so risk assessment knows what's actually shipped and how.
- **Self-improving suggestions**: track which suggestions humans accept/reject; store as procedural memory; rank future suggestions by learned acceptance.

**Code memory graph (detail).** Nodes: file, symbol, test, owner, deploy-target. Edges: imports, calls, tests, modifies (from git), deploys. Update incrementally on each commit. Retrieval for any task = "fetch the relevant subgraph," which is far higher-signal than top-k chunks.

**Evals.** Precision/recall of review comments against a labeled set of real PRs; false-positive rate (the metric that kills code-review tools); refactor-suggestion acceptance rate.

**Trust.** Reviews are advisory by default; any _applied_ change is a PR a human merges (HITL by construction). Every suggestion cites evidence (graph paths, lines).

**Observability + learning.** Trace every review; the accept/reject signal feeds the policy-learning loop (self-healing ladder L3–L4: suggests fixes / proposes code changes, human approves).

_Strengthens:_ Memory (graph), Context Engineering (subgraph retrieval), Trust, Evals (false-positive discipline), Learning loops, Observability. Directly relevant to where coding-agent value is concentrating in 2026.

---

## Big Project 3 — Autonomous Research + Decision Engine

Give it a question; it plans research, retrieves across sources, detects contradictions, synthesizes, and produces a _trust-scored_ recommendation — not just a summary.

**Architecture.**

- **Planner**: decomposes the question into sub-questions + a research plan (typed, inspectable). Planner-executor pattern.
- **Retrieval**: multi-source (web, internal docs, APIs), reranked, with source metadata (recency, authority).
- **Contradiction detection**: cluster claims; flag where sources disagree; surface the disagreement instead of silently averaging it. This is the feature that makes it trustworthy.
- **Synthesis**: produce an answer that explicitly separates consensus, contested points, and gaps.
- **Recommendation engine**: turn synthesis into a decision with reasoning, alternatives, and confidence.
- **Trust scoring**: every claim carries source provenance + a confidence score; the final recommendation carries an overall trust score and the evidence behind it.

**Planner (detail).** Output a structured plan you can inspect and gate before any expensive retrieval runs. Re-plan on dead ends (bounded).

**Contradiction detection (detail).** Extract atomic claims with sources → embed/cluster → within clusters, detect semantic opposition → present "Source A says X (recent, authoritative); Source B says ¬X (older)." Never collapse a real disagreement into false consensus.

**Trust scoring.** Per-claim: source authority × recency × corroboration. Per-recommendation: aggregate + explicit uncertainty. The output is auditable: every conclusion traces to evidence.

**Evals.** Faithfulness (does the synthesis reflect the sources?), contradiction-detection recall, hallucination rate, calibration of trust scores against ground truth.

**Trust + observability.** Full provenance chain; the entire reasoning path is a replayable trace. High-stakes recommendations gated for human review.

_Strengthens:_ Orchestration (planner-executor), Context Engineering, Evals (faithfulness/calibration), Trust (provenance + scoring), Observability. This is the bridge project into Layer 4 — it's a _decision_ engine in a high-entropy domain, which is exactly the Layer 4 shape.

---

# Part 3 — Production Layer 3 Stack (2026)

What each tool solves. Choose the _least_ infrastructure that meets your reliability bar; add heavyweight pieces only when you feel the specific pain they solve.

|Need|Tool(s)|What it solves|
|---|---|---|
|Orchestration|**LangGraph** (default), **Claude Agent SDK** (Anthropic-native), Mastra (TS)|Graph-based control flow, conditional branching, cycles, sub-agents, checkpointing, HITL. The "execution nervous system."|
|Long-running / durable workflows|**Temporal** (heavyweight), LangGraph durable execution (lighter)|Workflows that run for hours/days, survive crashes, resume from last good step, with retries + sagas as first-class.|
|Memory (truth)|**PostgreSQL**|Source of truth for facts, events, audit. Everything else is derived from here.|
|Memory (semantic index)|**Qdrant** (or pgvector for simplicity, Weaviate as alt)|Vector search over episodic/semantic memory and documents. An _index_, not the truth.|
|Working memory / cache|**Redis**|Fast ephemeral session state, semantic cache, rate limiting.|
|Vector DB|Qdrant / pgvector|Embeddings storage + ANN retrieval. pgvector keeps your stack smaller; Qdrant scales harder.|
|Observability / tracing|**LangSmith** (LangChain-native) or **Langfuse** (OSS, self-host) or **Braintrust** (trace+eval)|Step-by-step traces, replay, cost/latency per span, quality monitoring.|
|Tracing substrate|**OpenTelemetry**|Vendor-neutral instrumentation so you're not locked in.|
|Evals|**Braintrust**, **DeepEval/Confident AI**, Promptfoo (red-team), Latitude (closed loop)|Datasets, scorers, LLM-judge, CI gates, production-trace→test-case.|
|Queues / event-driven|**Kafka** (high-throughput event streams) or SQS/Redis Streams (simpler)|Decoupling, buffering, async fan-out, dead-letter queues. Use the simplest that handles your volume.|
|Retries / backoff|Temporal (built-in) or app-level (tenacity etc.)|Transient-failure recovery with budgets + jitter.|
|Human approvals|LangGraph interrupts + your own approval UI|Suspend/resume on irreversible actions; previews.|
|Audit logs|Postgres append-only tables|Immutable record of decision + evidence + rationale + model version.|
|Output validation|**Pydantic** / structured outputs / function calling|Schema-enforce every model output before acting.|
|Model routing / gateway|**LiteLLM**, Portkey, OpenRouter, Braintrust Gateway|Per-task model selection, fallbacks, caching, cost attribution, one SDK for many providers.|
|Tool connection|**MCP (Model Context Protocol)**|Standard way for agents to discover/call external tools and data (verify per-framework support).|
|Cost optimization|Gateway caching + model tiering + your eval gate|Semantic/prompt caching, cheap-vs-expensive routing, cost-per-successful-task metric.|
|Security|Least-privilege tool scopes, secrets manager, input sanitization, OWASP-GenAI guardrails|Prompt-injection defense, scoped permissions, no secrets in context.|

**Sensible starting stack:** LangGraph + Postgres + pgvector + Redis + Langfuse (or LangSmith) + Braintrust + Pydantic + LiteLLM. Add **Temporal** and **Kafka** when long-running durability and event volume demand them — not before.

---

# Part 4 — Layer 3 Production Maturity Model

**Level 0 — Toy.** Works in a notebook on the happy path. No evals, no tracing, no failure handling. _You learn the API._ Everyone starts here; don't stay.

**Level 1 — Usable.** A real user can use it for a real task. Basic error handling, structured outputs, some logging. _Requires:_ output validation, retries on transient errors, a handful of manual test cases.

**Level 2 — Production.** Real users, real traffic, you'd be paged if it broke. _Requires:_ full tracing/observability, an eval suite gating changes in CI, idempotent side effects, cost tracking, approval gates on irreversible actions, audit logs. **This is the floor for "I do Layer 3 professionally."**

**Level 3 — Resilient.** Survives failure gracefully: durable/resumable long-running workflows, sagas/compensation, circuit breakers, dead-letter queues, drift detection, online quality monitoring with alerts. Recovers from partial failure without corruption. _This is where production scars compound fastest._

**Level 4 — Self-improving.** The system improves without retraining the model: policy/memory learning loops, production failures auto-curate into evals, self-healing ladder L3–L4 (surfaces issues → suggests/proposes fixes → human approves). Operational intelligence. _Few systems are genuinely here; this is the frontier._

**How you know you crossed Layer 3:** you can take a brand-new agentic task and ship it to **Level 2–3 reliably and quickly**, because you have a reusable standard library (eval harness, tracing, memory service, resilient-workflow scaffold, trust layer) and the judgment to choose the _least_ complex architecture that meets the bar. The tell is not knowledge — it's that **production stops surprising you.**

---

# Part 5 — Learning Sequence (Fastest Realistic Route)

Bias: build first, read just-in-time. Every week ends in shipped, traced, eval'd code. Estimated 5–6 months at serious part-time; ~3 months full-time.

### Month 1 — Foundations + first scars

- **Wk 1:** LangGraph deeply. Build S1 (Pattern Lab), sequential + router first. Instrument with Langfuse/LangSmith from day one — observability is not a later chapter.
- **Wk 2:** Finish S1 (planner-executor, supervisor-worker). Build a real eval harness in Braintrust. Add a CI gate. Deliberately regress a prompt; watch it catch.
- **Wk 3:** Context engineering. Build the context-manager module + inspector. Structured outputs + Pydantic validation everywhere.
- **Wk 4:** Start S2 (Resilient Workflow). Idempotency, retries, checkpointing, dead-letter queue.

### Month 2 — Reliability + memory

- **Wk 5:** Finish S2. Add a saga (undo partial work) and an approval gate on the irreversible step. First real failure-engineering scars.
- **Wk 6:** Memory theory + S3 (Memory Service). Postgres-as-truth, pgvector index, dedup, recency-weighted retrieval, decay.
- **Wk 7:** Finish S3 with conflict resolution + full tracing. Add semantic + prompt caching; measure cost-per-task.
- **Wk 8:** Model routing. Build a gated router (cheap vs capable), prove quality holds on your eval set, report 40–60% cost cut.

### Months 3–4 — Big Project 1 (Personal OS)

- Reuse S1–S3 modules. Build ingestion → memory core → supervisor + workers → long-running monitors → trust gates → digest-as-trace-query.
- Drive every pillar to **Level 2–3**. Curate evals from your own corrections (your first proprietary data moat). Add the learning loop (corrections → procedural memory).
- _Milestone:_ you run it daily and it does real work overnight.

### Month 5 — Big Project 2 OR 3 (pick by destination)

- **Repo Intelligence** if you're aiming at developer-tools / coding-agent space.
- **Research/Decision Engine** if you're aiming at a high-entropy decision domain (the Layer 4 on-ramp).
- Go deep on the project's signature pillar (code memory graph; or contradiction detection + trust scoring). Push toward **Level 3–4** with policy learning.

### Month 6 — Hardening + Layer 4 radar

- Take whichever big project is closest to real and harden it to Level 3 (durable workflows, drift detection, online evals, dead-letter triage).
- Begin Layer 4 radar in parallel (see critique): immerse in ONE high-entropy domain, find painful workflows where mistakes are expensive and trust is critical, and start shipping the project to _real outside users_ — distribution scars matter as much as production scars.

**Anti-over-theorizing rules:**

1. No week without shipped, traced, eval'd code.
2. Read the doc you need _the moment you hit the wall_, not before.
3. Every production failure becomes an eval case the same day.
4. Default to the least powerful pattern that passes evals.
5. If you've spent two days without breaking something in production-like conditions, you're reading too much.

---

_Logs are textbooks. Pain teaches. Patterns compound. Ship, break, fix, observe — repeat._