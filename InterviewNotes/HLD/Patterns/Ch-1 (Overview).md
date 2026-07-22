# Common Patterns — Overview

> Hello Interview · **System Design in a Hurry** · File `03`. **Series 3 = Patterns.** _(01x = Core Concepts · 02x = Key Technologies.)_ **Purpose:** patterns are the **recurring shapes** that solve most design problems. Spot the pattern → fall back to best practices, skip reinventing the wheel, and see the **known failure modes** instead of reverse-engineering them live. ▸ **The governing rule: PATTERN RECOGNITION IS THE SENIOR SIGNAL.** Saying _"this is a contention problem, I'd start with…"_ buys you three things at once: **language** (shared vocabulary), **compression** (skip the derivation), and **failure-mode foresight** (you already know where it breaks). This is what separates senior from junior in the room. ⚠ **Patterns are the assembly layer — they lean hard on 01x/02x.** Almost nothing here is new machinery; it's _when and how you combine_ the pieces you already have. Cross-references do the heavy lifting. ⚠ **Depth probed ∝ level.** For SDE2 at Indian unicorns you're expected to **proactively name** the pattern and defend one implementation — not just recognize it after the interviewer points at the bottleneck.

---

## Calibration — value per pattern for a backend SDE2 targeting Razorpay / Meesho / Swiggy / CRED

> ▸ **Use this to allocate depth.** Contention, Writes, and Multi-Step are where fintech interviews live; Blobs and Proximity are shallower or narrower for your targets.

|Pattern|Value|Why for _your_ targets|
|---|---|---|
|**Dealing with Contention** (`03c`)|⭐⭐⭐ **Critical**|The fintech pattern. No double-charge, no double-spend, wallet-balance safety, inventory decrement, idempotency. Razorpay/CRED-shaped prompts hit this immediately|
|**Scaling Writes** (`03e`)|⭐⭐⭐ **High + hard**|Ledgers, order writes, ad-click ingestion. The _hard_ side of scaling — interviewers probe it to test seniority. Write-hot keys (`02a`) show up here|
|**Multi-Step Processes** (`03g`)|⭐⭐⭐ **High**|Payment orchestration (auth → capture → settle), refunds, KYC onboarding. Sagas + audit trails = compliance. Very fintech|
|**Real-time Updates** (`03a`)|⭐⭐ **High**|Live order tracking (Swiggy/Zomato), payment status (Razorpay), price ticks (Groww/smallcase). Ubiquitous, easy to over-engineer|
|**Long-Running Tasks** (`03b`)|⭐⭐ **High**|Statement/report generation, settlement batches, bulk refunds, KYC processing. Common — and easy to get rejected on by over-queuing|
|**Scaling Reads** (`03d`)|⭐⭐ **High**|Catalog/feed reads, dashboards, portfolio views. Cheapest wins first; the "natural progression" is table stakes|
|**Handling Large Blobs** (`03f`)|⭐ **Medium**|KYC docs, invoices, product images. Mostly one idea (presigned URLs + CDN) — know the flow cold, don't over-invest|
|**Proximity-Based Services**|⭐ **Medium**|Swiggy/delivery only; **not** fintech. Mechanics already in Redis geo (`02a §5`). No dedicated `03x` file|

---

## 1. Real-time Updates → `03a`

▸ **CRUX** — push server→client **as things happen** (chat, notifications, live dashboards, order/payment status). A synchronous API just returns a response when done; realtime needs a **standing push channel**.

▸ **Two independent decisions:**

- **Client transport (protocol)** — **HTTP polling → SSE → WebSockets.** _(Protocol deep dive → `01a networking`.)_
- **Server-side fan-out** — **Pub/Sub** to decouple publisher/subscriber _(→ `02 §7`, `02a §7`)_, **or** stateful servers in a **consistent hash ring** _(→ `01g`)_ when per-connection processing is heavy.

⚠ **The pitfall: reaching for WebSockets first.** The infra (sticky sessions, reconnects, scaling stateful connections) is genuinely hard. **Start with polling until it stops serving you**, then justify the jump to SSE/WebSockets.

⚠ **Fintech/unicorn:** Swiggy/Zomato live-order tracking · Razorpay payment-status updates · Groww/smallcase live price ticks.

---

## 2. Managing Long-Running Tasks → `03b`

▸ **CRUX** — work too slow for a synchronous response (video encode, report gen, bulk ops, KYC). Split into **instant acknowledgment + background processing.** Web server validates → **enqueues a job → returns a job ID in ms**; a separate **worker pool** pulls and executes.

- **Buys:** fast user response · web servers and workers scale **independently** · fault isolation.
- **Coordination tech:** message queue _(→ `02 §6`)_ + worker pool. Need **job-status tracking, retries, DLQ** for poison messages _(→ `02 §6`)_.

⚠ **The pitfall (the reject trigger): reflexively queuing.** If jobs are **short**, returning status **synchronously** is dramatically simpler — clearer back-pressure, better UX. Candidates lose points by putting a queue behind everything. _(Queue back-pressure → `02 §6`.)_

⚠ **Fintech:** statement/report generation · nightly settlement batches · bulk refunds · async KYC verification.

---

## 3. Dealing with Contention → `03c` ⭐ highest fintech value

▸ **CRUX** — multiple users hit the **same resource at once** (last concert ticket, auction bid, wallet balance) → **race conditions.** You need to prevent them **and** keep data consistent.

▸ **Solutions ladder — start simple, escalate only when forced:**

- **DB-level atomicity / transactions** — the default. _(→ `01c`, `01d`.)_
- **Pessimistic locking** — `SELECT … FOR UPDATE` grabs the row before work.
- **Optimistic concurrency** — `UPDATE … WHERE version = X`; retry on conflict.
- **Distributed** — distributed lock _(→ `02 §8`, `02a §2`)_, two-phase commit, or queue-based serialization.

⚠ **The senior probe:** _databases are built to solve contention._ The moment you split data across multiple DBs, you **re-inherit every problem the DB already solved** for you. Interviewers dig here to see if you understand what you're giving up. **Don't shard prematurely.**

⚠ **Money invariants belong in the DB, not a Redis lock** — a Redis lock is an **efficiency tool, not a correctness guarantee** (async replication breaks it; no fencing token). Enforce the invariant where the data lives. _(Full argument → `02a §2`.)_

⚠ **Fintech:** no double-charge · no double-spend · idempotency keys on payments · inventory decrement · seat/ticket hold. This is the canonical Razorpay/CRED prompt.

---

## 4. Scaling Reads → `03d`

▸ **CRUX** — reads bottleneck **first** (read:write starts ~10:1, often 100:1+). Fix in a **natural progression, cheapest first:**

- **Inside the DB** — indexing _(→ `01d`)_ and denormalization _(→ `01c`)_.
- **Horizontal** — **read replicas** _(→ `01i`)_.
- **External layers** — Redis cache _(→ `01e`, `02a §1`)_ then CDN _(→ `01e`, `02 §10`)_.

⚠ **Three things interviewers make you own:**

- **Cache invalidation** _(→ `01e`)_.
- **Replication lag** on read replicas → read-your-own-writes anomalies _(→ `01h`)_.
- **Hot keys** — millions requesting the same popular content _(→ `02a` hot key, `01e`)_.

⚠ **Fintech/unicorn:** product catalog + feed reads · analytics dashboards · portfolio/holdings views.

#### ⚠ Confusion resolved — read replica FIRST or cache FIRST (once indexing / vertical scaling / denormalization are exhausted)?

> **My doubt:** _"Should i add read replica first or caching first when indexing and vertical scaling and denormalization all have exhausted?"_

▸ **There is no fixed order — it's decided by the SHAPE of your read load, not by the sequence.** HI lists replicas-before-cache as a reasonable **default**, but applying it mechanically is exactly what gets probed. The real discriminator is one question:

> **Is your read load repetitive (skewed) or diverse (spread)?**

▸ **Repetitive / high hit-ratio → cache first.** A small hot set served to everyone (product pages, top-N feed, config, session lookups, an expensive-but-stable join result). One Redis node absorbs load that would otherwise need many replicas, at µs latency, and it cuts **total DB work** instead of just redistributing it. _(→ `01e`, `02a §1`.)_

▸ **Diverse / low-repetition → replicas first.** Every user reads different rows, long-tail access, ad-hoc queries ("my order history," personalized data with little overlap). Caching a long tail gives a **low hit-ratio → you pay RAM for misses.** Replicas add raw read capacity that works **regardless of repetition** and keep full query flexibility. _(→ `01i`.)_

▸ **The mechanism difference IS the whole answer:**

||Read replicas|Cache (Redis)|
|---|---|---|
|What it does|**distributes** read load across copies|**eliminates** repeated reads|
|Wins when|reads are **spread** (diverse)|reads are **skewed** (hot set)|
|Per-query cost|same expensive query, other box|compute once, serve many|
|Query flexibility|full — it's a real DB|only what you cached|
|Staleness cost|bounded **replication lag** (→ `01h`)|**manual invalidation** (harder)|
|Hot key|read-hot only|the sharper tool (→ `02a`, `01e`)|

▹ **Why HI defaults to replicas → cache (and why it's fair):** replicas are the **more general** fix (no skew required) and **lower-risk on correctness** — bounded lag vs. front-loading **invalidation**, the hardest distributed-systems problem. When you don't yet know the access pattern, replicas are the safer next step. But they solve **different** problems, so in practice you **layer both**: cache the hot stable stuff, replicas for the diverse/analytical tail. The "progression" is **escalation, not either/or.**

⚠ **Two signals that override the default:**

- **Latency requirement (not just throughput)** → cache leans first; in-memory sub-ms beats network + disk on a replica.
- **Expensive query, stable result** → cache first; a replica just **re-runs the expensive join** per read.

▸ **Interview move — don't recite "replicas then cache."** Say: _"depends on whether reads are skewed — if there's a hot set I'd cache first for a high hit-ratio and a bigger multiplier; if reads are diverse I'd add replicas since a cache would just churn misses."_ That **diagnosis** is what rates you up.

---

## 5. Scaling Writes → `03e`

▸ **CRUX** — the **harder** side: every write must land in the **right place** and coordination gets complex fast. Strategies:

- **Horizontal sharding** by partition key _(→ `01f`, `01g`)_.
- **Vertical partitioning** — separate data by type/feature.
- **Burst handling** — write queues to buffer spikes _(→ `02 §6`)_; **load shedding** to prioritize important writes under overload.
- **Batching** — group writes to cut per-op overhead.

⚠ **Partition-key choice is the whole game:** distribute load evenly **while keeping related data together.** User ID (social feed) ✅ · geo region (ride-share) ✅ · **product category (e-commerce) ❌** — a few categories dominate → **hot shard** _(→ `02a` hot key, `01f` celebrity problem)_.

⚠ **Don't add a queue just because the WPS number looks big** — 5k WPS doesn't need one _(→ `02 §6`, `01i` mistake #3)_.

⚠ **Fintech:** ledger append writes · order writes · ad-click ingestion · **write-hot counters** → shard the counter + pre-aggregate per app server _(→ `02a` write-hot fixes)_.

#### ⚠ Confusion resolved — what is vertical partitioning ("separate data by type/feature")?

> **My doubt:** _"What is Vertical partitioning — separate data by type/feature. Explain this first?"_

▸ **Sharding splits by ROWS; vertical partitioning splits by COLUMNS/FEATURES.** That's the whole axis.

- **Sharding (horizontal)** — same schema, **rows** split across nodes; every shard has all columns, fewer rows _(→ `01f`)_.
- **Vertical** — **different columns/features** on different stores, for the same entity.

▸ **Two granularities:**

- **Column-split in one table** — cut a wide table into narrow ones sharing the PK: hot columns (`id, name, last_login`) apart from cold/bulky ones (`bio, avatar_blob, settings_json`).
- **Feature-split across databases** _(what HI means)_ — `users_db` · `orders_db` · `payments_db`, each its own store, often its own tech.

▸ **Why it helps writes:**

- Write-heavy features stop **contending** with write-light ones for the same disk/locks/buffer pool.
- Each partition **scales independently** on its own hardware.
- **Narrower rows → cheaper writes** (more rows/page, less index bloat); a login write touches only the small table, not the blob row.
- **Right tool per domain** — append-only events → LSM store; relational orders → Postgres.

⚠ **The costs (the senior probe — "you re-inherit contention"):**

- **No cross-partition JOINs** → becomes an app-level join (two queries + stitch).
- **No cross-partition transactions** → needs distributed txn / saga → straight into `03c` + `03g`.
- **No referential integrity** across separate stores.

⚠ **Fintech:** the natural fault line is **payments/ledger DB split from the rest** — but that's exactly where atomic "debit A, credit B **and** record the order" gets hard → you pay for it in `03c`/`03g`.

▸ **One-line hold:** _sharding = same table, fewer rows per node · vertical = different columns/features on different nodes → independent scaling + narrower hot writes, at the price of joins and cross-store transactions._

---

## 6. Handling Large Blobs → `03f`

▸ **CRUX** — videos/images/docs should **never route through your app servers.** Use **direct client↔storage transfers** via **presigned URLs** + CDN delivery. _(Full flow, chunking, cost → `02 §2`.)_

- App server mints a **temporary, scoped presigned URL** → client uploads **direct to S3**.
- Downloads come from a **CDN** with a signed URL for access control.
- **Buys:** your servers stop being the bandwidth bottleneck · resumable uploads · progress tracking · global distribution.

⚠ **The pitfall: state sync.** Your DB metadata and the blob store can drift — handle upload **failures** and lean on **storage event notifications** to keep app state consistent _(→ `02 §2` upload flow, step 4)_.

⚠ **Fintech/unicorn:** KYC documents · invoices/statements · product images.

---

## 7. Multi-Step Processes → `03g` ⭐ high fintech value

▸ **CRUX** — business workflows spanning **multiple services + long ops** that must **survive failures, retries, and external dependencies** (order fulfillment, onboarding, payment processing). _(This is Saga territory.)_

▸ **Solutions ladder:**

- **Single-server orchestration** — simplest; one coordinator drives the steps.
- **Event sourcing** — each step **emits an event** that triggers the next; replay reconstructs state _(→ `02 §7`, `02a §6`)_.
- **Workflow engines / durable execution** — **Temporal, AWS Step Functions** handle state, failure recovery, retries → **exactly-once** semantics + **complete audit trail.**

▸ **The key insight:** move from **scattered state + manual error handling** → **declarative workflow definitions** the system guarantees for you.

⚠ **Fintech:** payment orchestration (auth → capture → settle) · refund flows · KYC onboarding. The **audit trail is compliance**, not a nicety.

#### ⚠ Confusion resolved — Multi-Step Processes vs Managing Long-Running Tasks (feels overlapping)

> **My doubt:** _"Difference between Multi-Step Processes and Managing Long-Running Tasks pattern? I find it overlaping and confusing."_

▸ **One axis: "slow" vs "many steps that must not half-complete."**

- **Long-Running Task (`03b`)** solves a **latency** problem — _one_ unit of work too slow to do synchronously. Ack now, run it in the background. **One step, just slow.**
- **Multi-Step Process (`03g`)** solves a **coordination + reliability** problem — _several_ steps across services that must all-succeed or cleanly unwind. The hard question isn't "it's slow," it's **"step 3 of 5 failed after 1–2 already committed — now what?"**

▸ **They overlap** because both ride queues + background workers, and an MSP is often _also_ long-running. Five things pull them apart:

||Long-Running Task|Multi-Step Process|
|---|---|---|
|Core problem|don't block the user on slow work|complete a business transaction **or roll back**|
|Shape|1 logical operation|sequence across services|
|Failure model|job fails → **retry whole job** / DLQ|step fails mid-way → **compensate/undo** priors (saga)|
|State|a **status flag** (pending/running/done)|a **workflow state machine** (where am I, what to undo)|
|Tooling|queue + worker pool _(→ `02 §6`)_|workflow engine / durable exec (Temporal, Step Functions) · or event-sourcing chain _(→ `02 §7`)_|

▸ **The real tell is retry semantics.** An LRT is safe to re-run (idempotent → same result). An MSP is **not** — if you already charged the card, "retry from scratch" **double-charges**; you need **compensation** (refund, release inventory). That partial-failure unwind is the entire reason `03g` exists and `03b` doesn't need it.

▸ **They nest — that's why it feels overlapping.** An MSP can have steps that are _each_ long-running tasks.

> Video platform: **MSP** orchestrates upload → transcode → thumbnail → publish; the **transcode step is itself an LRT** (`03b` inside `03g`).

⚠ **Fintech:**

- **LRT** — generate a monthly statement PDF. One slow job, retry-safe.
- **MSP** — settlement: authorize → capture → update ledger → notify. Partial failure = money-integrity risk → **saga with compensation.** The fintech-critical one.

▸ **One-line hold:** _Long-Running = one slow job, retry it. Multi-Step = a coordinated sequence that must all-succeed-or-unwind, compensate it._

---

## Proximity-Based Services _(no dedicated `03x` file — see note)_

▸ **CRUX** — search entities **by location** (Uber, Gopuff, Swiggy). Use a **geospatial index**: PostGIS · Redis geo _(→ `02a §5`)_ · Elasticsearch geo-queries. Divide the area into **regions**, index within them → cheaply **exclude vast empty areas.**

⚠ **Only worth it at 100k–millions of items.** Under ~1k, **just scan** — the index overhead isn't paid back. ▹ Most proximity is **local, not global** — users want entities near _them_, so you rarely query the whole world. ▹ **Filing decision:** parked as a cross-reference, not a pattern file — Redis geo (`02a §5`) already carries the mechanics. Promote to `03h` if you want it standalone.

---

## Pattern Selection — they compose

▸ **Patterns are not mutually exclusive; real systems stack several.**

- **Video platform** = **Large Blobs** (upload) + **Long-Running Tasks** (transcode) + **Real-time Updates** (progress) + **Multi-Step Processes** (orchestrate the pipeline).

▸ **The interview move:** proactively **name the patterns you're applying** → signals architectural maturity and focuses time on what matters. **Start simple** (polling, single-server orchestration); add complexity **only when a specific requirement demands it.**

---

## Quick Recall (pass 3+)

|Pattern|One-line CRUX|The pitfall / probe|Leans on|
|---|---|---|---|
|**Real-time Updates**|push server→client as it happens|⚠ don't start at WebSockets — **poll until it hurts**|`01a`, `01g`, `02/02a §7`|
|**Long-Running Tasks**|instant ack + background workers|⚠ **don't reflexively queue** — short jobs go sync|`02 §6`|
|**Dealing with Contention** ⭐|same resource, many users → race|⚠ splitting DBs re-inherits contention · **money invariants in DB, not Redis lock**|`01c/01d`, `02 §8`, `02a §2`|
|**Scaling Reads**|index → denormalize → replicas → cache → CDN|⚠ invalidation · **replication lag** · hot keys|`01d/01c/01e/01h/01i`, `02a`|
|↳ replica **or** cache first?|**no fixed order — read-load shape decides**|**skewed → cache first** (hit-ratio) · **diverse → replicas first** (cache churns misses) · overrides: latency / expensive-stable query → cache. **Layer both**|`01e/01h/01i`, `02a`|
|**Scaling Writes** ⭐|shard · partition · buffer bursts · batch|⚠ **partition key**: even load + colocation · category = hot shard|`01f/01g`, `02 §6`, `02a`|
|↳ vertical partitioning?|**split by columns/features** (vs sharding = split by rows)|independent scaling + narrower hot writes · ⚠ loses **joins + cross-store txns** → `03c`/`03g`|`01f`|
|**Handling Large Blobs**|client↔S3 direct via **presigned URL** + CDN|⚠ **DB↔blob state sync** via storage events|`02 §2`|
|**Multi-Step Processes** ⭐|multi-service workflow that survives failure|prefer **declarative workflow** (Temporal/Step Functions) over scattered state|`02 §7`, `02a §6`|
|↳ vs Long-Running Task?|**LRT = one slow job (retry it)** · **MSP = coordinated sequence (all-succeed-or-compensate)**|tell = retry semantics: LRT re-runnable · MSP needs **compensation** (already-charged ≠ retry). They **nest**|`02 §6/§7`|
|**Proximity**|geospatial index, exclude empty regions|⚠ only worth it at 100k+ items; else scan|`02a §5`|
|**Governing rule**|—|**name the pattern** → language + compression + failure foresight. Compose freely; start simple|—|