# P1 — Orchestration Patterns · Completion Map

**Steps to complete this pillar:**

1. **Concept gate** — six patterns + workflow/agent + selection axis (known-upfront vs runtime) + per-pattern failure modes; validated via novel scenario tests. ✅ DONE (2026-07-11)
2. **Required reading** — Building Effective Agents ✅ · 12-Factor Agents ✅ DONE (2026-07-11)
3. **S1 — Pattern Lab build** — one task × 4 patterns (sequential / router / planner-executor / supervisor-worker) + shared eval harness; metric table (tokens / latency / success / debuggability) over ≥30 cases → **PASS Block Card**. ⛔ not started

**These notes cover → Step 2 (required reading: 12-Factor Agents) only.**

---

# Step 2 — Required Reading: 12-Factor Agents

**▸ Mental model (one line):** Agents = **prompt + switch + context + loop**, and _you_ own every piece of that — not a framework, not the model's improving capability. A better model raises per-step reliability; it doesn't dissolve the compounding math, cost, or debuggability reasons to keep control.

**▹ WHY this doc exists in your revision system:** it's not a new architecture — it's reinforcement of P1's prime directive (least powerful pattern, authority shrinks with blast radius) plus a handful of _specific, load-bearing_ factors. Read it as "how do I actually implement 'own the control flow'" — not as a competing philosophy to Anthropic's.

---

## The load-bearing factors (the ones that changed something)

### Factor 3 — Own your context window

- **▸ Say-it-out-loud:** "Context is the LLM's RAM — small, expensive, shared by system prompt, tools, history, retrieved docs. My job as the engineer is deciding what goes in, what gets compacted, and when to discard — not letting it fill passively."
- **Numbers to drop:** Horthy's **"dumb zone"** — signal-to-noise degrades once the window fills past **~40%**; recall and reasoning both suffer in the middle of a large window (ties to "lost-in-the-middle," P2). `[FLAG: verify exact % before quoting live — single-source stat.]`
- **Fails when —** you let history/tool-results accumulate unbounded → dumb zone, agent loses focus. **Mitigate —** structured (not prose) compaction of older turns; discard aggressively; start a fresh session/window rather than let one grow indefinitely.

### Factor 5 — Unify execution state and business state

- **▸ Say-it-out-loud:** "Serialize _where the agent is in the flow_ (execution state — current step, retry count, pending approval) and _the actual domain data_ (business state — what happened) into **one object**. That's what makes the agent pause, resume, and replay cleanly."
- **▹ Personal correction:** this is NOT a memory-type question (episodic vs procedural). It's a **state-serialization** question — one axis, not the memory taxonomy from P3. Don't reach for P3 vocabulary here.
- **Fails when —** the two states live separately / implicitly → you can't reconstruct or resume a mid-flight agent from a single checkpoint. **Mitigate —** one serializable state object; this is exactly what LangGraph's `State` + checkpointing gives you for free.

### Factor 6 / 8 — Launch/pause/resume + Own your control flow

- **▸ Say-it-out-loud:** "The agent must be launchable, pausable, and resumable via a simple API — which only works if I own the control flow myself (explicit state/nodes/edges) rather than hiding it inside a framework's abstraction."
- **When to use / when to refuse:** LangGraph gives you these control primitives (state, nodes, conditional edges) without hand-rolling checkpointing/HITL/streaming. Raw Anthropic SDK gives _maximum_ control but you rebuild all of that infra yourself.
- **Numbers/decision to drop:** _raw SDK → to learn the guts; LangGraph → for the orchestration/durability/HITL you'd otherwise hand-roll._ This is literally the S1 stack decision.
- **Fails when —** you adopt a heavy framework (CrewAI-style) that generates/hides your prompts and branching → you lose the ability to debug or tune precisely. **Mitigate —** prefer low-abstraction tools (LangGraph, raw SDK) when you're past prototyping and building for years, not weeks.

### Factor 9 — Compact errors into the context

- **▸ Say-it-out-loud:** "Errors go back into context so the model can self-correct — but a long back-and-forth debugging a single bug shouldn't cost the whole window. Summarize/compact the resolved error trail before moving on."
- **Personal-gold:** you derived this correctly, unprompted, before I confirmed it — good instinct, keep it.
- **Fails when —** raw multi-turn error-solving sits in context uncompacted → burns window on a resolved problem. **Mitigate —** after resolution, collapse the debugging detour into a one-line summary; don't carry the full trace forward.

### Factor 10 — Small, focused agents

- **▸ Say-it-out-loud:** "An agent should do 3–10 steps, not everything — small in **scope**, so context stays tight and reliability holds. This is _not_ the small-model-vs-big-model debate (that's P9/routing) — it's about agent _scope_, a completely different axis."
- **▹ Personal correction:** you conflated this with "use a small specialized model" (legal-trained-LLM tangent). Different axis — same two-axes-confusion reflex as parallelization-vs-orchestrator-workers. Watch for it.
- **Fails when —** one giant agent tries to do everything → same failure surface as reaching for supervisor-worker when router+sequential would do (P1 prime directive). **Mitigate —** router/parallelization/workflow patterns over one monolith — this is _why_ the P1 patterns exist.

### Factor 12 — Stateless reducer

- **▸ Say-it-out-loud:** "Model the agent as a pure function: `(current_state, new_event) → new_state`. No hidden internal state — everything passed in, everything returned out. Redux-reducer pattern applied to agents."
- **Why it's load-bearing:** makes the agent testable (feed state, assert output), resumable (serialize state, reload later — ties to Factor 5), replayable, and horizontally scalable (any worker can pick up any state).
- **Fails when —** the agent keeps state in memory/closures instead of the returned object → can't resume on a different process, can't test in isolation. **Mitigate —** every state transition is an explicit, serializable return value.

---

## Factors that just reinforced what you already hold (compressed, not re-explained)

- **F1 (NL→tool calls)**, **F2 (own your prompts)**, **F4 (tools = structured outputs)**, **F7 (contact humans as a tool call = HITL, gated by stakes)**, **F11 (trigger from anywhere: human/cron/outer-loop)** — all confirmed correct on first read, no correction needed. Don't re-derive these on revision; just confirm recognition.

---

## My Learnings (Personal) — where this session actually corrected something

**1. Inverted the central thesis.**

- I argued "modern models + good harness (Cursor) prove full autonomy works, so the deterministic-workflow advice is dated."
- **Correction:** the thesis was never "make it deterministic." It's **"own your control flow"** — decide _where_ the model has authority. Cursor is the exemplar of 12-Factor (tight control flow, aggressive compaction, small focused sub-agents, plan-mode HITL gate), not a counterexample.
- **Rule:** a stronger model raises per-step reliability; it does not remove compounding-error math, cost, or debuggability reasons to keep control. This is the P1 prime directive resurfacing — don't loosen on "least powerful pattern, authority shrinks with blast radius" just because the model got better.

**2. Misread Factor 5 (execution/business state) as a memory-type question.**

- Mapped it to episodic/procedural memory (P3 vocabulary). Wrong axis — it's state-serialization for pause/resume, not memory typing.

**3. Conflated Factor 10 (small agent _scope_) with small-model-vs-big-model.**

- Same shape of error as the parallelization-vs-OW confusion from the concept gate: two genuinely different axes pattern-matched into one because they both contain the word "small." **Recurring failure shape — flag it explicitly whenever "small/large" comes up.**

---

## Quick Recall

|Prompt / scenario|Reach for|One-liner|
|---|---|---|
|"why not let the agent figure out the whole flow now that models are better?"|Own your control flow (F8)|better model ≠ dissolved compounding/cost/debug argument — Cursor proves the discipline, not its absence|
|"how do I make an agent resumable?"|F5 (unify state) + F12 (stateless reducer) + F6 (pause/resume API)|one serializable state object, pure-function transitions|
|"context window keeps growing / agent loses focus"|F3 (own context)|compact structurally past ~40% fill; discard aggressively|
|"should I use a small model or one agent that does everything?"|Two different questions|small **model** = P9/routing; small **agent scope** = F10, don't merge them|
|"framework (CrewAI-style) is hiding my prompts/branching"|F2 + F8|own your prompt, own your control flow — prefer low-abstraction (LangGraph/raw SDK) once past prototyping|
|"LangGraph vs raw Anthropic SDK?"|Depends on control need|raw SDK = max control, rebuild infra yourself; LangGraph = control primitives without hand-rolling checkpointing/HITL|

---

_Read residue only — no build content here. Next: S1 Pattern Lab (Step 3)._