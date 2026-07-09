# Delivery Framework — The Spine of Every Design

> Hello Interview · System Design in a Hurry · Reference file — **learned once, never repeated in case studies.** When a case study says _"→ framework: deep dives"_, it means this file.

---

## The One-Line Principle

> You fail these interviews by **not delivering a working system**, not by knowing too little. "Time management" is the usual post-mortem. The fix is focusing on the right things in the right order — that is what this framework enforces.

---

## The Sequence (memorize this table)

|#|Step|Time|Output on the board|
|---|---|---|---|
|1|Requirements|~5 min|Functional (top 3) + Non-functional (quantified, 3–5)|
|2|Core Entities|~2 min|Bulleted noun list — first draft only|
|3|API / Interface|~5 min|Endpoint contract (usually REST)|
|—|_[Optional]_ Data Flow|~5 min|Ordered list of processing steps|
|4|High-Level Design|~10–15 min|Boxes + arrows satisfying the API|
|5|Deep Dives|~10 min|Harden against non-functional reqs + probes|

▸ **Total ≈ 45 min.** Fall back to this order whenever you get lost. Linear build = you never freeze.

---

## Step 1 — Requirements (~5 min)

### Functional — "Users should be able to…"

▸ **CRUX**

- Core features, phrased as user capabilities. First thing you discuss.
- It's a **back-and-forth** — ask like a PM: _"Does it need X?" "What happens on Y?"_
- **Prioritize the top 3.** Ruthlessly. A long list hurts you. ▹ WHY: these systems have hundreds of features. Top FAANGs _directly evaluate_ your ability to identify what matters. The rest of the interview exists to satisfy this list — so a bloated list dilutes everything downstream.

_Twitter example:_ post tweets · follow users · see feed from followed users.

### Non-Functional — "The system should be…"

▸ **CRUX**

- Statements about system _qualities_. Must be **quantified** and **contextual**.
- Pick the **top 3–5** that actually drive design.
- ❌ "should be low latency" (meaningless — everything should be)
- ✅ "render feeds in < 200ms" · "scale to 100M+ DAU" · "available over consistent" ▹ WHY: an unquantified NFR gives the interviewer no target and you no design constraint. The number is what forces an architectural decision later.

**Checklist to surface NFRs** (scan, pick the relevant few):

- **CAP** — consistency _or_ availability? (Partition tolerance is a given.)
- **Environment** — mobile battery / limited memory / low bandwidth (3G video)?
- **Scalability** — bursty traffic? holiday spikes? **read:write ratio** — scaling reads or writes more?
- **Latency** — which specific operation needs to be fast? (e.g. search on Yelp)
- **Durability** — how bad is data loss? (social post ≠ bank balance)
- **Security** — data protection, access control, compliance.
- **Fault tolerance** — redundancy, failover, recovery.
- **Compliance** — legal/regulatory (data-protection laws, industry standards).

### Capacity Estimation

▸ **CRUX**

- **Skip upfront math.** Tell the interviewer you'll compute _when a number changes a decision._
- Do the math only when it forks the design. ▹ WHY: "calculate DAU/QPS/storage → conclude 'it's a lot' " signals nothing except that you can multiply. The interviewer gains nothing. ▹ WHEN it _does_ matter — TopK trending topics: you must estimate the topic count, because it decides **single min-heap vs. sharded** across instances. That's a real design fork, so the number earns its place.

⚠ **Rejection trap:** burning 5 minutes on vanity back-of-envelope math that touches nothing downstream.

---

## Step 2 — Core Entities (~2 min)

▸ **CRUX**

- Jot a **bulleted noun list**. Announce it's a first draft. Move on.
- Do **not** build the full data model yet — no columns/fields. ▹ WHY: you don't know what you don't know. Entities and relationships emerge during HLD. Starting small lets you iterate; columns get added later, next to the DB box, once you know what state each request mutates.

**Prompts to find entities:** Who are the actors (do they overlap)? What nouns/resources do the functional reqs require?

_Twitter:_ User · Tweet · Follow.

▹ Naming matters — some interviewers use it to probe the "hardest problem in CS." Don't use `foo`/`bar`.

---

## Step 3 — API / Interface (~5 min)

▸ **CRUX**

- Define the **contract** before HLD. Usually maps 1:1 to functional reqs (not always).
- **Default to REST.** Resources = **plural nouns**.
- Derive the current user from the **auth token**, never from request body/path.

**Protocol pick:**

|Protocol|Use when|
|---|---|
|**REST**|Default. CRUD over HTTP verbs.|
|**GraphQL**|Diverse clients, different data needs — avoids over/under-fetching.|
|**RPC (gRPC)**|Internal service-to-service where performance is critical.|

▹ Real-time features also need **WebSockets / SSE** — but design the core API first.

```
POST /v1/tweets            body: { "text": string }
GET  /v1/tweets/{tweetId}  -> Tweet
POST /v1/follows           body: { "followee_id": string }
GET  /v1/feed              -> Tweet[]
```

⚠ **Rejection trap:** taking `user_id` from the request body — a security hole. Always authenticate and derive identity from the token.

---

## Step — [Optional] Data Flow (~5 min)

▸ **CRUX**

- Only for **data-processing / sequential** systems. If there's no pipeline of actions, **skip entirely.**
- Express as a simple ordered list; it feeds the HLD.

_Web crawler:_ fetch seed URLs → parse HTML → extract URLs → store data → repeat.

---

## Step 4 — High-Level Design (~10–15 min)

▸ **CRUX**

- Boxes + arrows (Excalidraw / whiteboard). Components = servers, DBs, caches, queues.
- **Goal: satisfy the API you just wrote.** Walk your endpoints one-by-one, build the design to serve each.
- Keep it **simple**. Meet core _functional_ reqs here; push complexity to deep dives.
- Spot a cache/queue opportunity? **Verbal callout + written note, then move on** — don't build it yet.
- Talk as you draw: trace data flow, name the **state that changes** per request (DB/cache/queue).
- Document only the **design-relevant** columns, next to the DB box. Skip the obvious (`User.name`, `email`, `password_hash`). ▹ WHY over-building early: the #1 reason candidates never reach a complete solution is layering complexity too soon. A simple correct system beats an elaborate unfinished one.

⚠ **Rejection trap:** premature complexity → running out of time with no working end-to-end system.

---

## Step 5 — Deep Dives (~10 min)

▸ **CRUX**

- Harden the design by: meeting **non-functional reqs**, handling **edge cases**, killing **bottlenecks**, responding to **interviewer probes**.
- **Seniority sets who leads:** juniors → interviewer points at weak spots; seniors → you identify and drive them proactively.
- **Do not talk over the interviewer.** Leave room for probes. ▹ WHY: they have specific signals to extract. Monologuing makes you miss them _and_ tanks your communication/collaboration score.

_Twitter deep dives that fall out of the NFRs:_ scale to 100M DAU → horizontal scaling + caches + DB sharding. Low-latency feed → **fanout-on-read vs fanout-on-write** + caching. (This feed problem is the actually-interesting part of Twitter.)

⚠ **Rejection trap:** treating deep dives as a lecture. It's a dialogue — balance proactivity with listening.

---

## Revision Speed-Card (read this on pass 3+)

```
[0:00] Requirements  → functional top 3 · non-functional quantified 3–5 · defer math
[5:00] Entities      → noun bullets, first draft, no columns
[7:00] API           → REST, plural nouns, user from auth token
       [Data Flow]   → only if sequential/processing system
[12:00] HLD          → boxes satisfy API, endpoint by endpoint, defer complexity
[27:00] Deep Dives   → attack non-functional reqs, follow interviewer, don't monologue
[37:00] buffer
```

**Four traps that reject you:** bloated requirements list · vanity capacity math · premature complexity in HLD · monologuing over the interviewer.