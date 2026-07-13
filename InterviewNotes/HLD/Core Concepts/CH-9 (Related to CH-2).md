# CAP Theorem — Deep Dive

> Hello Interview · Core Concepts (deep dive) · File `01h`. Overview in `01_core_concepts`. **Calibration:** **HIGH value / core — and it lands EARLY.** This belongs in the **non-functional requirements phase**, right after functional requirements. It shapes every downstream decision (DB choice, replication, caching). **Getting it right in minute 5 is worth more than any deep dive in minute 35.** ⚠ **Fintech note:** Razorpay/CRED-style prompts skew toward **consistency** (payments, balances, ledgers). Know _why_, and know which parts of even those systems can still choose availability.

---

## What It Is

▸ **CRUX** — in a distributed system you can only have **two of three**:

- **Consistency** — all nodes see the same data at the same time. Write to one node → **every subsequent read from any node returns that value.**
- **Availability** — every request to a **non-failing** node gets a response — **with no guarantee it's the latest version.**
- **Partition Tolerance** — the system keeps operating despite **message loss or network partitions** between nodes.

⚠ **CAP "consistency" ≠ ACID "consistency."** Different concepts, same word. Don't conflate them.

▸ **The insight that makes CAP simple: partition tolerance is NOT optional.** Networks fail. Your system must handle it. So the "pick two" framing collapses into **one real question:**

> ### **When a network partition occurs, do you choose consistency or availability?**

That's the entire theorem, for interview purposes.

---

## The Example (build intuition here)

Two servers: **USA** and **Europe**. User A (USA) updates their display name → replicates to Europe → User B (Europe) sees the new name. Fine.

**Then the link between USA and Europe goes down.** User B tries to view User A's profile:

- **Option A — choose consistency:** return an **error**, because we can't guarantee the data is current.
- **Option B — choose availability:** show **potentially stale** data.

▸ **Here the answer is obvious:** show the old name. **A stale name beats no name at all.** But that's this case — the whole skill is knowing when it flips.

---

## Which Do You Choose?

▸ **The one question to ask:**

> **"Would it be catastrophic if users briefly saw inconsistent data?"** Yes → **consistency.** No → **availability.**

### Choose Consistency when…

- **Ticket booking** — User A books seat 6A; during a partition User B sees it as free and books it too → **two people, one seat.**
- **E-commerce inventory** — one toothbrush left, shown as available to several users during a partition → **oversell.**
- **Financial systems** — stock platforms need accurate order books; **stale data → trades at wrong prices.**

### Choose Availability when… _(this is the majority of systems)_

- **Social media** — User B seeing an old profile picture for a few minutes is fine.
- **Content platforms (Netflix)** — a temporarily stale movie description isn't catastrophic.
- **Review sites (Yelp)** — slightly outdated restaurant hours **beats showing nothing at all.**

▹ Choosing availability **typically leads to** eventual consistency — the system converges, but it may take seconds or minutes. _(⚠ "leads to," not "equals" — see below.)_

### ⚠ Confusion resolved — Availability ≠ Eventual Consistency

> **My doubt:** "Isn't choosing availability the same as choosing eventual consistency?" **No — but AP systems are _typically_ eventually consistent.** They're different questions.

▸ **They answer two different questions:**

- **Availability** → _"Will the system **respond** to my request?"_ — about **service behavior.**
- **Consistency model** → _"What **guarantee** does that response carry?"_ (strong / causal / read-your-writes / eventual) — about **data correctness over time.**

▸ **Why they get conflated — the causal chain:**

```
Choose Availability during a partition
      ↓
Replicas keep accepting reads/writes independently
      ↓
Replicas DIVERGE (temporary inconsistency)
      ↓
Partition heals → replicas reconcile
      ↓
Eventual consistency
```

That last step is a **consequence** of the availability choice, not a synonym for it.

▸ **The two branches, concretely:**

- **CP (chose consistency)** — bank balance, replicas can't talk → _"Sorry, I can't answer right now."_
    - ✅ every read sees the latest committed write · ❌ **some requests fail or wait** → availability sacrificed.
- **AP (chose availability)** — replicas partitioned → the replica **answers anyway**, even if stale.
    - ✅ every request gets a response · ❌ **replicas may disagree temporarily** → they sync after the partition heals.

⚠ **Say this in an interview:**

> ✅ _"Prioritizing availability in CAP usually leads to eventual consistency, because replicas continue serving requests independently and reconcile after the partition heals."_ ❌ **Never:** _"Availability and eventual consistency are the same thing."_

---

## What Each Choice Means for Your Design

> This is the payoff — CAP isn't trivia, it **dictates your architecture.**

### If you prioritize CONSISTENCY

- **Distributed transactions** — keep multiple stores (cache + DB) in sync via **two-phase commit**. Guarantees consistency, but adds complexity and **higher latency** while nodes agree. _(2PC's fragility → `01f_sharding`.)_
- **Single-node solutions** — one DB instance sidesteps propagation entirely. **Limits scalability**, but gives one source of truth.
- **Technology choices:**
    - Traditional RDBMS — **PostgreSQL, MySQL**
    - **Google Spanner**
    - **DynamoDB** _(in strong consistency mode)_

### If you prioritize AVAILABILITY

- **Multiple replicas** — read replicas with **asynchronous replication**; reads served from any replica even if slightly behind. Better read performance + availability, at the cost of **staleness**.
- **Change Data Capture (CDC)** — track changes in the primary and propagate them **asynchronously** to replicas, caches, and downstream systems. The primary stays available while updates flow through eventually.
- **Technology choices:**
    - **Cassandra**
    - **DynamoDB** _(multi-AZ configuration)_
    - **Redis clusters**

▸ **Most modern distributed DBs let you configure either.** The skill isn't naming a database — it's **knowing which mode your use case needs.** _(Note DynamoDB appears on both lists — that's the point.)_

---

## Advanced — for senior/staff discussions

> ▹ **Calibration:** everything above is sufficient for **most mid-level interviews (that's you at 3.5 YOE).** This section is upside, not a requirement. But the **per-feature framing below is genuinely worth having** — it's a cheap way to sound senior.

### The choice is per-FEATURE, not per-system

▸ **CRUX** — real systems need **both** — just for different features. Saying so is a strong signal.

- **Ticketmaster:**
    - **Booking a seat** → **strong consistency** (prevent double-booking).
    - **Viewing event details** → **availability** (a stale description is fine).
    - > _"I'll prioritize consistency for booking transactions but optimize for availability when users are browsing and viewing events."_
        
- **Tinder:**
    - **Matching** → **consistency** (both swipe right ≈ simultaneously → both should see the match immediately).
    - **Viewing a profile** → **availability** (a slightly outdated picture is fine).
    - > _"I'll prioritize consistency for matching but optimize for availability when users are viewing profiles."_
        

▹ **Apply this to your fintech targets:** a payments system needs **strong consistency** for the ledger/balance, but **transaction history browsing** or **merchant dashboards** can happily be eventually consistent. Naming that split is exactly the nuance a Razorpay interviewer is listening for.

### The Consistency Spectrum

▸ When people say "consistency" in CAP they usually mean **strong**. But it's a spectrum:

|Model|Guarantee|Typical use|
|---|---|---|
|**Strong**|every read reflects the **most recent write**|bank balances — **most expensive** in performance|
|**Causal**|**related** events appear in the same order to everyone|comments must appear **after** the post they're on|
|**Read-your-own-writes**|**you** always see **your** updates immediately; others may see older versions|social media — you expect your own profile edit to show instantly|
|**Eventual**|converges over time; temporary inconsistency allowed|DNS. **The default for most distributed DBs** — and what you implicitly choose when you pick availability|

---

## Interview Playbook

▸ **When:** during **non-functional requirements** — right after you've aligned on functional requirements. **This is one of the first things you discuss.**

▸ **The question to ask out loud:**

> _"Does this system need to prioritize consistency or availability?"_

▸ **The self-check that resolves it:**

> **"Does every read need to read the most recent write?"** Yes → **consistency.** No → **availability.**

▸ **The senior move:** don't answer system-wide if the system has genuinely mixed needs — **split it by feature** (booking vs browsing; matching vs profile viewing; ledger vs dashboard).

⚠ **Don't overcomplicate it.** CAP is foundational, not hard. Ask the one question, state the answer, justify it in a sentence, and **carry the consequence into your DB and replication choices.** That's the whole job.

---

## Quick Recall (pass 3+)

|Situation|Reach for|
|---|---|
|The three properties|**C** — all nodes see same data · **A** — every non-failing node responds (maybe stale) · **P** — survives network partitions|
|Why "pick 2" is misleading|**P is mandatory** (networks fail) → the real choice is **C vs A during a partition**|
|CAP-C vs ACID-C|**different concepts, same word** — don't conflate|
|The one question|**"Would it be catastrophic if users briefly saw inconsistent data?"**|
|The self-check|**"Does every read need the most recent write?"** yes → C · no → A|
|Choose **C**|booking/seats · inventory · financial ledgers, balances, order books|
|Choose **A**|social media · content platforms · review sites — **most systems**|
|C design|2PC distributed txns · single-node · **Postgres/MySQL, Spanner, DynamoDB (strong mode)**|
|A design|async read replicas · **CDC** · **Cassandra, DynamoDB (multi-AZ), Redis cluster**|
|Senior signal|**choose per FEATURE, not per system** (Ticketmaster: booking=C, browsing=A)|
|Consistency spectrum|**strong** → **causal** → **read-your-own-writes** → **eventual**|
|Availability = eventual consistency?|**NO.** Availability = _will it respond?_ · Consistency model = _what guarantee?_ AP **leads to** eventual consistency (replicas diverge, then reconcile) — it isn't the same thing|
|Where it belongs in the interview|**non-functional requirements — minute 5, not minute 35**|