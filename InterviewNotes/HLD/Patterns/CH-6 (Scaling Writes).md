# Scaling Writes

> Hello Interview · **Patterns** · File `03e`. Overview → `03 §5`. Sharding → `01f`; consistent hashing / virtual nodes → `01g`; Cassandra/LSM/B-tree → `01d`; queues + backpressure → `02 §6`; Kafka → `02 §7`; Redis Cluster slots + **write-hot keys** → `02a`; numbers → `01i`. **Calibration:** ⭐⭐⭐ **High + hard.** The _harder_ side of scaling — interviewers probe it to test seniority. For your targets: **ledger append writes, order writes, ad-click ingestion, write-hot counters** (likes/views/balances). A runaway-success "how does it scale?" almost always lands here. ▸ **The one governing insight:** every strategy below is the **same move — reduce throughput per component.** Spread 10k writes across 10 shards, smooth bursts through a queue, or batch 100 writes into 1 — all of it makes each individual component handle **manageable** load. ⚠ **Don't scale writes prematurely.** Each strategy has a real cost (queues → eventual consistency; sharding → compromised reads; batching → latency). **Do the back-of-envelope math first** — the worst move is inventing a bottleneck that doesn't exist.

---

## The Problem

▸ **CRUX** — reads have easy tools (replicas, cache → `03d`); **writes are the bigger challenge.** Bursty, high-throughput writes with contention are a nightmare, and every write hits **disk I/O, CPU, or network** hard limits. Interviewers love _"how does it scale when the product 4×'s?"_

### Where it shows up (HI breakdowns)

- Ad Click Aggregator · Metrics Monitoring · YouTube Top-K · Strava · Rate Limiter · FB Post Search.
- ⭐ **Fintech/unicorn:** payment ledger writes, order ingestion, ad-click/event pipelines, write-hot counters.

---

## The four strategies (climb in order)

> ▸ The four strategies, in order:
> 
> 1. **Vertical Scaling and Database Choices**
> 2. **Sharding and Partitioning**
> 3. **Handling Bursts with Queues and Load Shedding**
> 4. **Batching and Hierarchical Aggregation**
> 
> ▸ Exhaust the cheap single-box wins (1) before going distributed (2), then handle **bursts** (3) and raw **volume** (4).

---

## 1. Vertical Scaling & Database Choices _(exhaust the single box first)_

### 1.1 Vertical scaling (hardware)

▸ Writes bottleneck on **disk I/O · CPU · network** — **confirm you're actually hitting a wall** with quick back-of-envelope math (what's your true WPS, does it fit the hardware?).

- ⚠ **Hardware goes further than people think** — **200-core, 10 Gbit** boxes exist _(→ `01i`)_. Many candidates picture a 4-core spinning-disk instance and re-architect too early.
- ▹ Make the case that modern hardware solves part of it (staff+ signal) — but **don't fight** an interviewer who's built the question around horizontal scaling; they'll move the goalposts.

### 1.2 Database choices — pick a write-optimized store

▸ **CRUX — most DBs handle _mixed_ workloads but aren't tuned for extremes.** When you _know_ you're write-heavy, strip read-only features and pick an append-oriented store.

- ⭐ **Cassandra** — **append-only commit log**: writes go **sequentially to disk** (no expensive in-place seeks) → **~10k+ WPS** vs ~1k for a relational DB doing the same _(LSM vs B-tree → `01d`)_. ⚠ **Trade-off: worse reads** (must check + merge multiple files). That's the deal you _want_ when writes dominate. ▸ **Other stores make the same write-for-read trade in their own ways:**
- **Time-series databases** (InfluxDB, TimescaleDB) — purpose-built for **high-volume sequential writes stamped with time**, and they use **built-in delta encoding** (store only the _change_ between consecutive points) to pack the storage far tighter. ⭐ The natural fit for metrics.
- **Log-structured databases** (LevelDB) — **append new data rather than updating in place**, so writes stay sequential (same core idea as Cassandra's commit log).
- **Column stores** (ClickHouse) — lay data out by column so they can **batch writes efficiently**, ideal for analytics workloads that scan few columns over many rows.

⚠ **The write-vs-read tension (the fundamental trade):** optimizing writes usually **degrades reads**, and vice-versa. **Identify which is your bottleneck and optimize _that_** — different parts of the system may need different stores.

▸ **Other per-DB write tweaks:**

- **Disable expensive read-features** during high-write periods — FK constraints, complex triggers, full-text indexing.
- **Tune write-ahead logging** — e.g. Postgres batches multiple txns before flushing to disk.
- **Reduce index overhead** — fewer indexes = faster writes (you pay on reads).
- ▸ **Interview move:** don't say "use a faster DB." Say _why_ — "Cassandra's append-only writes beat MySQL's B-tree updates," or "a time-series DB for metrics."

---

## 2. Sharding & Partitioning _(the go-to; interviewers expect it)_

### 2.1 Horizontal sharding — split ROWS across servers

▸ **CRUX** — if one server does 1k WPS, 10 servers _should_ do 10k. Distribute write volume so each shard handles a slice; the many shards look like **one logical DB** to the app. _(Full mechanics → `01f`.)_

- **Routing options (how a key maps to a node):**
    - **Slot-based (Redis Cluster):** key → **CRC16 hash → slot number (0–16383)** → slot assigned to a node; client hashes the key, finds the node, writes there _(→ `02a`)_.
    - **Consistent hashing** _(→ `01g`)_ — ⭐ **also fully viable and often preferred at scale.** Keys and nodes both hash onto a ring; a key goes to the next node clockwise. **Why it wins:** adding/removing a node only remaps the keys in _one_ segment (≈ `1/N` of data) instead of rehashing everything, and **virtual nodes** smooth out skew. This is the go-to when your node count changes over time (resharding → DD1).

> ⚠ **Confusion resolved — "What is the CRC function, and is the Redis 'client' the Next.js browser client?"** **Doubt (verbatim):** _"Explain in 1-2 line what is CRC function. Also redis client is nothing but SDK right so it means application server not Nextjs client right?"_ **(a) CRC** = _Cyclic Redundancy Check_ — a **fast, non-cryptographic hash** that turns any input (your key) into a fixed-size number. Redis Cluster uses **CRC16(key) mod 16384** to pick one of its **16,384 slots**. Purpose here is purely **even distribution**, not security — it's cheap and spreads keys flatly. **(b) The "Redis client" = the SDK/driver running inside your BACKEND** (Node app server: `ioredis` / `node-redis`). It is **NOT** the Next.js browser client. The driver is what hashes the key, locates the node, and issues the write.
> 
> ```
> Browser (Next.js client)
>         │  HTTP request
>         ▼
> App server (Node)  ──►  ioredis SDK  ──►  hashes key → finds node → writes
>                                          (THIS is the "Redis client")
>         ▼
>    Redis Cluster node
> ```
> 
> ⚠ The browser must **never** hold Redis credentials or talk to Redis directly (that exposes the datastore to the public internet). So whenever HI says _"the client hashes the key,"_ read it as **your backend's Redis driver**, not the frontend.

- **Example — Redis Cluster (slot flow):** key → CRC16 hash → slot number → slot assigned to a node; the backend's Redis driver hashes the key, finds the node, writes there _(→ `02a`)_.

⚠ **2.1a — Selecting a good partition key (the detail interviewers actually want):**

- **Goal: minimize variance in writes-per-shard — "flat is good."** Hash a **primary identifier** (userId, postId) → even spread → you realize the full 10× gain.
- **Bad key example:** shard by **country** → China shard overloaded, New Zealand shard idle → skew kills you.
- ▹ Be ready to go deeper: **consistent hashing, virtual nodes, slot-assignment** _(→ `01g`)_ if probed.
- ⚠ **Also consider the READ path:** if writes spread evenly but each _read_ must gather from **every shard** (scatter-gather), you've traded a write bottleneck for read overhead. For your "fastest" (most read+written) data, ask: **"how many shards does this request hit?"** and **"how often?"** → spread evenly **while grouping commonly-accessed data together.**

> ⚠ **Confusion resolved — "Is the shard key the same as the partition key?"** **Doubt (verbatim):** _"whether sharding key and partitioning key, they are using in the same manner, because they are two different things. Partitioning happening within the same single shard, single database, and sharding happens when multiple databases involved. So here like a sharding key and partitioning key the same thing?"_ **Short answer: shard key ≈ _horizontal_ partition key — same _kind_ of thing (a routing key), differing only in SCOPE. But "partitioning" is overloaded, which is what's tripping you up.**
> 
> - **Horizontal partitioning** splits **rows** by a key. **Sharding = horizontal partitioning taken across separate machines.** The key that decides _which bucket a row lands in_ plays the **identical role** whether the bucket is a partition inside one Postgres instance or a whole separate shard-node. → **shard key and horizontal partition key are the same concept.**
> - Your working heuristic (**partition = within one DB · shard = across DBs**) is a fine mental model for _scope_. Just don't conclude the _key_ is a different animal — it isn't; it's the same routing decision at a bigger radius.
> - ⚠ **The overload:** **vertical partitioning** (§2.2 below) splits **COLUMNS by access pattern** — there is **no key at all** there. So "partitioning" covers _two_ different operations; only the **horizontal** one uses a key comparable to the shard key.
> 
> |Term|Splits|Uses a routing key?|Scope|
> |---|---|---|---|
> |Horizontal partitioning|rows|✅ yes (= shard key)|one DB _or_ many|
> |**Sharding**|rows|✅ yes (**the shard key**)|across machines|
> |Vertical partitioning|columns|❌ no (by access pattern)|one DB _or_ many|

### 2.2 Vertical partitioning — split COLUMNS by access pattern

▸ **CRUX** — horizontal splits **rows**; vertical splits **columns/tables** by how data is _used_. _(Full confusion block → overview `03 §5`.)_

- A monolithic `posts` table gets hammered from all sides (content writes, constant metric updates, analytics scans) — each operation **interferes** with the others. Split it:
    - **`post_content`** — write-once/read-many → B-tree indexes, read-optimized.
    - **`post_metrics`** — high-frequency counter updates → in-memory / specialized counters.
    - **`post_analytics`** — append-only time-series → column-oriented / TS storage.
- ▸ Then move each table to a **different DB instance** tuned for its workload. ▸ **The real challenge is _logical_ data modeling** (how you think about the data), not just where it physically lives.

---

## 3. Handling Bursts — Queues & Load Shedding

> ▸ Sharding gets ~80% of the way, but **real write traffic is bursty** ("Black Friday 4× orders", "New Year 3× drivers"). To 4× at peak you'd otherwise run at **25% utilization** the rest of the time — nobody sizes like that. ⚠ **Autoscaling isn't a panacea** — scaling up **takes time**, and for DBs often means **downtime / reduced throughput** _during_ the scale-up — the opposite of what you want mid-spike. So you either **(a) buffer** the writes or **(b) drop** some acceptably.

### 3.1 Write queues (buffer the burst)

▸ Put a **queue (Kafka / SQS)** between accept and process → **decouples write acceptance from write processing** → DB drains at a **steady rate** while the queue absorbs the spike. _(→ `02 §6`.)_

- ⚠ **Async → the app only knows the write is _queued_, not _durably written_** → clients often need a **callback / status check** to confirm it landed.
- ⚠ **A queue is a _temporary_ buffer, not a capacity fix.** If you enqueue **faster than the DB drains**, the queue grows **unboundedly** → writes take longer and longer → **backpressure** _(→ `02 §6`)_. **Use queues for short-lived bursts, NOT to patch a DB that can't handle steady-state load.**
- ▸ Decide at **requirements** time: what's your tolerance for **delayed writes / inconsistent reads**? If some delay is fine (esp. for rare peaks), a queue fits — but don't let it break a key functional/NFR.

### 3.2 Load shedding (drop the least-important writes)

▸ **CRUX** — when overwhelmed, **decide which writes to reject** rather than letting everything fail. Rank writes by business importance; drop the low-value ones to keep the system alive.

- ⭐ **Uber/Strava location pings:** users re-send location **every few seconds** → **dropping one is fine, a fresher one arrives shortly.** Shedding location updates within seconds of a prior one beats blowing out a queue.
- Analytics: drop **impressions** for a while to protect the more valuable **clicks**.
- ▸ **A release valve keeps "too much load" from becoming "system failure"** — a suboptimal experience for some beats an outage for all.

---

## 4. Batching & Hierarchical Aggregation _(change the shape of the writes)_

> ▸ Previous strategies accept the writes as given; these **restructure** them. Each individual write carries overhead (network round-trip, txn setup, index update), and DBs process **batches** far more efficiently than singles.

### 4.1 Batching — amortize per-write overhead

▸ Group many writes into one. Three layers:

- **Application layer** — client batches before sending. ⭐ Safe when the app **isn't the source of truth** (e.g. reading a Kafka topic → on crash, just re-read). ⚠ If the app **is** the source of truth, a crash mid-batch **loses confirmed writes** — not all apps can accept that.
- **Intermediate processing** — a dedicated batcher. ⭐ **Like Batcher:** read many `Like` events, tally per-post, forward the totals → **100 likes/min → 1 write.** ⚠ **Staff-level caveat:** if most posts get 1 like/hour, a 1-min batch window saves **nothing** — verify batching actually helps your distribution.
- **Database layer** — tune flush-to-disk interval (Redis flushes every ~100ms → 1000 writes in that window = fewer disk hits). ⚠ The **"big hammer"** — reserve for extreme cases.

> ⚠ **Confusion resolved — "How do queues (§3.1) and app-batching (§4.1) compose to beat bursty traffic?"** **Doubt (verbatim, condensed):** _"application batching can work very well if we are using a queue… queue is acting as acceptance layer, and application server becomes a processing layer. So we can use batching to avoid the meltdown. Database will have just one query instead of hundred… high probability will save us from meltdown and tackle bursty traffic."_ ✅ **Correct — and it's the intended composition, not two rival options.** Queue and batching solve **different sub-problems and stack:**
> 
> - **Queue (§3.1)** absorbs the **burst** — decouples acceptance from processing; DB drains at a steady rate.
> - **Batching (§4.1)** kills the **per-write overhead** — worker collapses 100 events → 1 DB write.
> - ▸ Once a **durable queue (Kafka) fronts the write path, the QUEUE is the source of truth — not the app server.** The worker consuming it is now a pure _processing layer_, so app-layer batching becomes **safe** (crash mid-batch → events still in the queue → just re-read). This is exactly _why_ HI says app-batching works "when the app isn't the source of truth."
> - ▸ **Net effect:** queue smooths the spike → worker batches → DB sees a **trickle (1 write, not 100)** → meltdown avoided. ✅
> 
> ⚠ **The one caveat to append — offset-commit ordering + idempotency (the part that makes "just re-read" actually safe):**
> 
> ```
> WRONG:  read batch → commit offset → write to DB   ✗ crash after commit = data LOST
> RIGHT:  read batch → write to DB → commit offset   ✓ crash before commit = re-read, safe
> ```
> 
> - Commit the queue **offset LAST** (after the DB write succeeds), never before — otherwise a crash between commit and write silently drops the batch.
> - ⚠ "RIGHT" gives **at-least-once** delivery → on crash-and-replay the same batch can be written **twice** → writes **must be idempotent** (upsert on a dedup key / event ID), or you double-count. The queue's log gives you durability; you pay for it with **dedup discipline on the write side.**

### 4.2 Hierarchical aggregation — reduce volume in stages _(extreme scale)_

▸ **CRUX** — for high-volume data (analytics, live comments) you often need **aggregated views, not individual events** — and those views build **incrementally.** Process in **stages, shrinking volume at each hop.**

- ⭐ **Live comments (millions of viewers all liking/commenting):** naive = **all-to-all** (every write fan-out to every viewer) → intractable.
    - **Fan-OUT fix — broadcast nodes:** assign viewers to **M broadcast nodes** (consistent hashing → `01g`); write to the **M nodes**, each forwards to its viewers → write to **M**, not **N** viewers.
    - **Fan-IN fix — write processors:** the root can't take every incoming event either → route each event to a **write processor by comment ID**; processors **aggregate likes over a window** and forward a **batch** to the root, which just **merges.**
- ▸ **Net:** aggregate on the way in (write processors) + dis-aggregate on the way out (broadcast nodes) → each component handles a fraction of the writes, at the cost of **some latency.** _(This is the celebrity fan-out referenced from `03a`.)_

> **▸ Plain-language walkthrough** _(read once, then the CRUX above is enough)_ **The problem — two explosions at once.** Millions watch a live stream, all liking/commenting. (1) Too many events come **IN** (millions of likes/sec hit the server). (2) Each event must go **OUT** to millions of screens (everyone's counter ticks up). Naive = every like sent to every viewer = **all-to-all = N × N = N²** → impossible for one machine. **The fix — layers that shrink the work at each step** (the "hierarchy"). Like a company: the CEO doesn't read every employee's email — **managers summarize upward**, and **announcements flow downward through managers.** Two directions → two different fixes.
> 
> **Fan-IN (incoming) — write processors.** The root counter can't take a million writes/sec, so put a layer of processors in between. Each processor collects likes for a few seconds, sums them, sends **one number** up:
> 
> ```
> 1,000,000 likes/sec
>       │  split across ~100 processors → each sees 10,000/sec
>       ▼  each waits 1 sec, sums its chunk → sends "10,000" up
>   root receives ~100 numbers/sec (not 1,000,000) → adds them
> ```
> 
> Root went **1,000,000 → 100 writes/sec.** Volume shrank as it climbed. _(= "aggregate on the way in.")_
> 
> **Fan-OUT (outgoing) — broadcast nodes.** One server can't hold a million live connections _(WebSockets → `03a`)_, so put a layer of broadcast nodes in between. Each node owns a share of viewers:
> 
> ```
> root has the new count
>       │  sends it to ~100 broadcast nodes (not to viewers directly)
>       ▼  each node forwards to its ~10,000 viewers
>   1,000,000 viewers updated — but root only sent 100 messages
> ```
> 
> Root sent **100 messages instead of 1,000,000.** One message fans out as it goes down. _(= "dis-aggregate on the way out.")_
> 
> **Both together:**
> 
> ```
>     millions of likes IN
>            ▼
>    [write processors]   ← squeeze many → few   (fan-IN)
>            ▼
>         [ root ]        ← handles a tiny trickle
>            ▼
>    [broadcast nodes]    ← expand few → many    (fan-OUT)
>            ▼
>    millions of screens OUT
> ```
> 
> Nobody in the middle is overwhelmed — each layer handles only a **fraction.** ⚠ Cost = **latency** (a like takes a second or two to appear, since processors batch over a window) — totally fine for a live counter. **▸ One-line takeaway:** instead of one machine doing a million-to-million job, **stack layers that combine on the way up and split on the way down** — every machine only ever does a small slice.

---

## In interviews

▸ **Proactively identify → validate with math → propose as a deep dive.** _"Millions posting content → we'll hit write bottlenecks. Let me check the throughput… significant — I'll deep-dive it."_ Then: _"partition posts by userId to spread load; handle a single power-user with a queue + rate limits."_

▸ **Scenario cheat-sheet:**

- **Instagram / social** — shard by userId; **vertical partition** by data type (profile / post / analytics); tiered storage for old posts.
- **News feed** — tension between **write** volume (celebrity → millions of followers) and **read** volume (fan-in at consume time).
- **Search** — write-heavy with heavy preprocessing → partitioning + batching.
- **Live comments** — the poster child for **hierarchical aggregation** (avoids all-to-all).

⚠ **When NOT to:** don't apply these when scale isn't needed — **math-check the suspected bottleneck first.** Each strategy has a cost (queue → eventual consistency + delay · partition → compromised read path · batch → latency + moving parts). **Creating a problem where none exists is the worst outcome.**

---

## Common Deep Dives

▸ **DD1 — "How do you reshard (8 → 16 shards) without downtime?"**

- ⚠ Naive = take offline, rehash everything, move → **hours of downtime.**
- ✅ **Gradual migration with dual-write:** during migration **write to BOTH** old and new shards, **read with preference for the new** shard. No data lost, availability maintained; once the new shard is caught up, cut over and drop the old. _(Consistent hashing minimizes what moves → `01g`.)_

▸ **DD2 — Hot write-key: too popular for even a single shard** _(→ `02a` write-hot)_

- **▸ PROBLEM** — a viral tweet takes **100k likes/sec**; even a dedicated shard can't hold that single key.
- **✅ SOLUTION — split the key into sub-keys** (the write-hot analog of `03d`'s read-hot fanout). Two ways to split:
    - **Option A — fixed split (all keys × _k_)** — store `post1Likes-0 … post1Likes-(k-1)` → each shard gets **1/k** of that post's write volume. ⚠ Cost: dataset ×k, **read volume ×k** (must sum all k sub-keys). Fine if a small k brings you back in line.
    - **Option B — dynamic split (hot keys only)** — split **only** keys detected hot (viral tweet → 100 sub-keys × 1k/sec each); aggregate on read. More surgical, less waste.
- **⚠ CAUTION 1 — aggregatable data only** — works for **likes, views, counts, balances**; **not atomic data** (user profiles). Luckily atomic data rarely sees this write pressure. _(Atomic-under-contention → `03b`.)_
- **⚠ CAUTION 2 — readers & writers must agree which keys are split.** Two ways to coordinate:
    - ⭐ **Readers always check all sub-keys** — simplest; same read amplification as fixed-split, but easy → **what most production systems do.**
    - **Writers announce the split to readers** — more efficient, but all readers must get the announcement first → complex. Avoid over-engineering in the interview.

---

## Quick Recall (pass 3+)

|Question|Answer|
|---|---|
|The one principle|every strategy **reduces throughput per component**|
|The 4 strategies|**1) vertical + DB choice · 2) shard/partition · 3) queues + load shedding · 4) batching + hierarchical aggregation**|
|First move|**exhaust hardware + math-check** the real WPS; don't re-architect early (`01i`)|
|Write-optimized DB|**Cassandra** append-only log → ~10k WPS (⚠ worse reads); time-series / log-structured / column stores (`01d`)|
|Write-vs-read tension|optimizing writes **degrades reads** & vice-versa → optimize your actual bottleneck|
|Horizontal sharding|split **rows**; **partition key = flat variance** (hash userId/postId); ⚠ bad key (country) = skew (`01f`, `01g`)|
|Routing options|**slot-based** (Redis Cluster: CRC16 mod 16384 → 1 of 16,384 slots) **or consistent hashing** (ring + vnodes; only ≈1/N remaps on node change → preferred when node count changes) (`01g`)|
|CRC function|**Cyclic Redundancy Check** — fast non-crypto hash for **even distribution**, not security; Redis uses CRC16 mod 16384|
|"Redis client"|the **SDK/driver in your BACKEND** (`ioredis`), **NOT** the Next.js browser; browser never talks to Redis directly|
|shard key vs partition key|**shard key ≈ _horizontal_ partition key** (same routing key, differs in scope); ⚠ **vertical** partitioning uses **no key** (splits columns by access pattern)|
|⚠ partition key + reads|even writes but **scatter-gather reads** = new bottleneck → "how many shards / how often?"|
|Vertical partitioning|split **columns** by access pattern (content / metrics / analytics) → per-workload DBs (overview `03 §5`)|
|Queues|**buffer short bursts** (Kafka/SQS); async → needs callback; ⚠ **unbounded growth / backpressure** if used to patch steady-state deficit (`02 §6`)|
|Autoscaling caveat|slow + DB scale-up = downtime mid-spike → not a burst fix|
|Load shedding|**drop least-important writes** (Uber location — fresher one coming); keeps system alive|
|Batching|app / intermediate (**Like Batcher** 100→1) / DB-flush; ⚠ useless if volume-per-key is low; ⚠ app-as-source-of-truth = data-loss risk|
|Queue + batching compose|queue absorbs **burst** + makes queue (not app) the **source of truth** → batching becomes safe (re-read on crash) → DB sees **1 write not 100** → meltdown avoided|
|⚠ batch-worker safety|commit **offset LAST** (after DB write) → at-least-once → writes must be **idempotent** (upsert on event ID) or double-count|
|Hierarchical aggregation|**stages shrink volume**: write processors aggregate fan-IN, broadcast nodes handle fan-OUT → avoids all-to-all (live comments); costs latency|
|Resharding|**dual-write** to old+new, **read-prefer-new**, then cut over — no downtime|
|Hot key (write)|**split into k sub-keys** (`:0…:k-1`, sum on read); fixed or **dynamic**; ⚠ **aggregatable only**, not atomic (`03b`); readers check all sub-keys (`02a`)|
|read-hot vs write-hot|**read-hot → duplicate copies** (`03d` fanout) · **write-hot → partition into summable pieces** (`02a`)|
|When NOT|**math-check first**; each strategy has a cost — don't invent bottlenecks|

---

> 🔗 **HI quick reference:** https://www.hellointerview.com/learn/system-design/patterns/scaling-writes/quick-reference