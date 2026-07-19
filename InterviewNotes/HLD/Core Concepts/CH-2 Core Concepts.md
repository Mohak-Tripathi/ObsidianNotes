# Core Concepts — The Building Blocks

> Hello Interview · System Design in a Hurry · Reference file — **the vocabulary. Case studies name-drop these; they don't re-explain them.** Technology-agnostic. Interviewers assume you know these and probe when you propose them.

---

## 1. Networking

▸ **CRUX**

- **Default to HTTP over TCP.** Handles ~90% of cases; interviewer expects it unless you justify otherwise.
- **SSE = unidirectional** (server pushes over one client-opened HTTP connection; client can't send more). Live scores, notifications.
- **WebSockets = bidirectional** (both sides send freely). Chat, live collaboration.
- Both are **stateful** → **can't sit behind a standard L7 load balancer.** Need connection persistence + a plan for server death dropping thousands of connections.
- **gRPC** for internal service-to-service when perf is critical (binary + HTTP/2, faster than JSON/HTTP). **Not public-facing** (browsers don't support it natively). Common pattern: REST external, gRPC internal.
- **Load balancers:** **L7** routes on HTTP content (API → service A, web → service B). **L4** works at TCP level — faster, dumber. **WebSockets need L4** (persistent TCP connection).
- **Geography sets a floor on latency:** NY↔London ≈ **80ms** minimum, speed-of-light through fiber, before any processing. Global low-latency → regional deployments + geo replication/partitioning. This is why **CDNs** exist (static content from edge).

⚠ **Rejection trap:** proposing WebSockets just because the word "real-time" appears. They add stateful-connection complexity at scale. Use only for genuine **bidirectional** needs; SSE / long-polling often suffice.

---

## 2. API Design

▸ **CRUX**

- **Default REST.** Resources → URLs, HTTP verbs manipulate them (`GET /users/{id}`, `POST /events/{id}/bookings`).
- Sketch **4–5 key endpoints in ~2 minutes, then move on.** API design is not where the signal is.
- **Pagination** (large result sets): **cursor-based** for real-time/frequently-appended data; **offset-based** fine otherwise.
- **Auth:** **JWT** for user sessions, **API keys** for service-to-service.
- **Rate limiting:** mention if abuse/bots are plausible. ▹ Don't go deep on pagination/auth/rate-limiting unless the interviewer pulls you there.

⚠ **Rejection trap:** still designing API details 10 min in → you've gone too deep, signals inexperience by omission of the real work.

---

## 3. Data Modeling

▸ **CRUX**

- **Relational (Postgres):** structured data, clear relationships, strong consistency, complex SQL, transactions, FK constraints.
- **NoSQL (DynamoDB/Mongo):** flexible/changing schema, or horizontal scale without complex joins.
- **Interview default: start normalized relational, denormalize specific hot paths only when you spot a read problem.** Don't denormalize upfront without a reason.
- **NoSQL forces access-pattern-first design:** choose **partition key + sort key** around your queries. Get the query right → fast single-partition lookup; query you didn't design for → full-table scan.
  
  **NoSQL forces access-pattern-first design**  => After Dynamo DB if still not clear then do research

**Normalize vs denormalize:**

||Normalize|Denormalize|
|---|---|---|
|What|split across tables, reference by ID|duplicate data to avoid joins|
|Win|consistency (update once)|fast reads (no joins)|
|Cost|joins get expensive at scale|update fan-out (change name → touch every copy)|
|Use|default|read-heavy, rarely-changing data|

⚠ **Rejection trap:** blindly applying denormalization to show you know it. They want the _tradeoff reasoning_, not the technique.

---

## 4. Database Indexing

▸ **CRUX**

- Index = skip full-table scan. 10M-row email lookup → milliseconds.
- **B-tree = default.** => because Exact lookups **and** range queries (dates A→B). Most RDBMS use it automatically.
- **Hash index:** faster exact match, **no range** → rarer.
- **Specialized:** full-text (search), geospatial (location).
- **Propose indexes on frequently-queried fields.** Auth by email → index email. Fetch user's orders → index `user_id`. "Events in SF on Dec 25" → **compound index** (city, date).
- **Beyond primary DB:** **Elasticsearch** for full-text; **PostGIS** for geo in Postgres. These sync from the primary via **CDC** → **the index lags (stale reads)**, which is fine for search.

▹ CDC + stale search index is a recurring pattern — see `pattern_bank` when it appears in case studies.

---

## 5. Caching

▸ **CRUX**

- **When:** DB is **read-hammered**. Redis hit ≈ **1ms** vs **20–50ms** DB → 20–50× speedup + offloads DB.
- **Default pattern: cache-aside + Redis.** Read → check cache → hit returns; miss → query DB, store with **TTL**, return.

**Three failure modes to know:**

- **Invalidation** (the hardest one)
    
    - **Problem —** after a write, the cached copy is stale until you act on it.
    - **Fix —** 1.  invalidate-on-write (delete/update the copy) ·
    - 2. short TTL (accept some staleness) · both. Choose by how fresh the data must be.
- **Cache stampede / thundering herd**
    
    - **Problem —** a popular entry expires → many concurrent requests miss at once → all pile onto the DB → can topple the system.
    - **Fix —** 1.  **lock** (one request regenerates, rest wait) ·
    - 2. **early recomputation** (refresh before expiry) · 
    - 3. **staggered TTLs** (entries don't all expire together). ▹ WHY staggered helps: shared TTLs expire in lockstep → synchronized misses; jittering expiry spreads regeneration over time.
- **Full cache outage**
    
    - **Problem —** Redis down → every read falls through to the DB → DB overload.
    - **Fix —** 1. In-process fallback cache 
    - 2. circuit breakers (shed load)
    - 3. Graceful degradation until Redis recovers.
- **Cache tiers (where each lives):** CDN → static assets at edge · in-process → tiny rarely-changing values (feature flags, config) · external Redis → core app data (default).
    

⚠ **Rejection trap:** caching everything. Cache only frequently-read + rarely-changing data. Caching per-request-changing data just adds latency. Profile first, cache hot paths.

---

## 6. Sharding

▸ **CRUX**

- Split data across independent servers when you outgrow one DB: **storage** (single Postgres maxes in low TB), **write throughput** (tens of thousands/sec), or **reads replicas can't absorb**.
- **Shard key is the decision.** Shard Instagram by `user_id` → all a user's data on one shard → user-scoped queries fast; **global queries ("trending across all users") get expensive** (hit every shard + aggregate). That's the tradeoff.
- **Strategies:** **hash-based** (hash key % N) → even distribution, default. **Range-based** → works if access naturally partitions (multi-tenant SaaS), but easy hot spots. **Directory-based** → lookup table, flexible but adds latency/dependency → rarely worth it in interviews.

**Sharding creates new problems:**

- **Cross-shard transactions**
    - **Problem —** a transaction spanning shards is ≈ impossible.
    - **Fix —** design shard boundaries so it never happens. If truly unavoidable (bank transfer across shards) → distributed transactions / **sagas** (complex, slow).
- **Hot spots**
    - **Problem —** one shard gets disproportionate traffic (Taylor Swift's shard) while others sit idle. _(No clean fix — mitigate via shard-key choice / further splitting the hot key.)_
- **Resharding**
    - **Problem —** can't add a shard without moving massive amounts of data → painful migration. _(Consistent hashing reduces how much moves — see §7.)_

⚠ **Rejection trap:** sharding too early. A tuned single DB + read replicas goes further than candidates think. **Do the capacity math first.** 10K writes/sec + 100GB → no sharding yet. Bring it up _after_ justifying why one DB fails; state the shard key + the fast-X / slow-Y tradeoff.

---

## 7. Consistent Hashing

▸ **CRUX**

- **Problem —** plain `hash(key) % N`: add/remove a server changes N → ~all keys remap → move ~everything.
- **Fix —** put servers + keys on a **virtual ring**; a key belongs to the next server clockwise. Add a server → only keys between it and the previous server move. Remove → only its keys relocate.
- **Impact:** add 1 server to a 10-server cluster — modulo moves ~**90%** of data; consistent hashing moves ~**10%**. Makes elastic scaling practical.
- **Used by:** distributed caches (Memcached, Redis Cluster), distributed DBs (Cassandra, DynamoDB) for sharding, some load balancers, CDNs.

▸ **In interviews:** you rarely explain the mechanism unless asked. Just say _"consistent hashing to distribute across cache nodes / for the shard key."_ **Main cue to raise it: elastic scaling** — adding/removing nodes based on load without massive data movement.

---

## 8. CAP Theorem

▸ **CRUX**

- Pick 2 of 3: **C**onsistency (all nodes same data) · **A**vailability (every request answered) · **P**artition tolerance (works despite network failure between nodes).
- Partitions are unavoidable → **you're really choosing C vs A** during a partition.
    - **Choose C:** nodes refuse to serve rather than return stale → might go down, but data always correct.
    - **Choose A:** every node keeps serving → users always get a response, nodes may temporarily disagree until partition heals.
- **Availability is the right default.** Users tolerate 2-second-stale feeds, not downtime. Social feeds, recommendations, analytics → **eventual consistency** (all nodes converge given time + no new updates; distinct from **weak consistency**, which promises no convergence).
- **Strong consistency where stale data costs money:** inventory (overselling), banking (fraud/balances), booking (double-booked seat).
- **Mix per subsystem:** e-commerce — product descriptions/reviews eventually consistent; inventory/orders strongly consistent.
- **PACELC:** during **P**artition → **A** or **C**; **E**lse → **L**atency or **C**. Even on a healthy network, strong consistency **adds latency** (nodes coordinate before responding). CAP only covers partition behavior; the everyday tradeoff is C vs latency.

▸ **In interviews:** when you mention replication/distributed data, the safe answer is **eventual consistency** — unless the problem involves **money, inventory, or limited-resource booking.**

---

## 9. Numbers to Know

▸ **CRUX**

- **Don't do upfront math.** Compute when a _decision_ needs it (shard? single Redis enough? how many servers?).
- **Modern hardware is powerful** — 2010-era numbers make you over-shard and over-cache. A tuned DB does tens of thousands QPS; a single Redis does hundreds of thousands ops/sec.
- **Latency ladder** (drives most decisions): memory = **ns** · SSD = **µs** · in-datacenter network = **1–10ms** · cross-continent = **tens–hundreds ms**.
- **Storage for sharding:** single Postgres handles a few TB comfortably; don't shard until **tens–hundreds of TB**. Sharding at 500GB = complexity for nothing.
- **Show the walk, not memorized facts:** _"50K req/s, ~5K per server, so ~10 servers + headroom."_

**Component reference table:**

|Component|Key metrics|Scale triggers|
|---|---|---|
|**Caching**|~1ms latency · 100k+ ops/s · memory-bound (up to 1TB)|hit rate <80% · latency >1ms · memory >80% · thrashing|
|**Databases**|up to 50k TPS · sub-5ms cached read · 64 TiB+ storage|writes >10k TPS · uncached read >5ms · geo-distribution needs|
|**App Servers**|100k+ concurrent conns · 8–64 cores @2–4GHz · 64–512GB RAM (up to 2TB)|CPU >70% · latency > SLA · conns near 100k/instance · mem >80%|
|**Message Queues**|up to 1M msgs/s per broker · sub-5ms end-to-end · up to 50TB|throughput near 800k msgs/s · ~200k partitions/cluster · growing consumer lag|

---

## 9b. Capacity Planning — Fast & Rough _(my add — not Hello Interview)_

> Goal: say a number that's _directionally correct_ in 30 seconds, then move on. Precision doesn't matter; the _decision_ it drives does.

▸ **The one trick that makes mental math easy**

- **Seconds in a day ≈ 100,000** (really 86,400, round to **10⁵**). This single approximation removes almost all the pain.

▸ **The only formula you need — DAU → QPS**

```
avg QPS  ≈  (DAU × actions per user per day) / 100,000
peak QPS ≈  avg × 2 to 3          ← always plan for peak, not average
```

- **Worked example:** 100M DAU, ~10 actions/day → 10⁹ / 10⁵ = **10K avg QPS** → **~20–30K peak**.
    - Then decide: one app server does ~tens of thousands QPS, so this is **a handful of servers**, not a fleet. No panic-sharding.

▸ **Storage — same shape**

```
storage/day ≈ writes per day × bytes per record
total       ≈ storage/day × retention (days)
```

- **Worked example:** 1M new posts/day × 1KB = **1GB/day** → ~**365GB/year**. Well under a single Postgres's few-TB comfort zone → **no sharding needed**. If it were 1M × 1MB (images) = **1TB/day**, that flips the answer → object store (S3) + CDN, not the DB.

▸ **Anchor numbers to hold in your head** (round, modern, generous)

|Thing|Rough capacity|Mental shortcut|
|---|---|---|
|App server|~10K QPS|"tens of thousands"|
|Postgres (well-tuned)|~10K writes/s · few TB|shard only past **tens of TB**|
|Redis|~100K+ ops/s · up to ~1TB|"hundreds of thousands"|
|Kafka broker|~1M msgs/s|"a million"|
|1 row of structured data|~1KB|text is cheap|
|Reference sizes|image ~1MB · minute of video ~10–50MB|media is 1000× text|

▸ **How to phrase it in the room** (the part they actually score)

- State assumption → do the divide → land the decision. Out loud:
    
    > _"~10K peak QPS, an app server handles ~10K, so 2–3 behind a load balancer with headroom. Storage is ~1GB/day, trivial for one Postgres — so I won't shard yet."_
    
- **The move that scores:** end every estimate with the **decision it unlocks** (shard / don't shard, cache / don't, one server / many). A number with no decision attached is the vanity math interviewers dislike.

⚠ **Rejection trap:** computing to fake precision (86,400 × 1,024…) and freezing. Round hard, say the ballpark, attach the decision, move on.

---

## Quick Recall (pass 3+)

|Situation|Reach for|
|---|---|
|Real-time, server→client only|SSE|
|Real-time, both directions|WebSocket (needs L4 LB)|
|Fast internal service calls|gRPC|
|Read-hammered DB|cache-aside + Redis|
|Popular key expiry storm|lock / early recompute / staggered TTL|
|Full-text / geo search|Elasticsearch / PostGIS via CDC (stale ok)|
|Outgrew one DB|shard — pick key, state tradeoff, _after_ math|
|Add/remove nodes without data churn|consistent hashing|
|Distributed data, freshness question|eventual consistency (unless money/inventory/booking)|
|"Do we need to shard / how many servers?"|pull the numbers, walk the math|