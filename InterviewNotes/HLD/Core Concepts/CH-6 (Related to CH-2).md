# Caching — Deep Dive

> Hello Interview · Core Concepts (deep dive) · File `01e`. Overview in `01_core_concepts`. **Calibration:** **HIGH value / core** — comes up in nearly every design, and directly relevant to your read-heavy + fintech targets. Must-knows: **cache-aside**, **invalidation**, and the three failure modes (**stampede / consistency / hot keys**). Write-behind & read-through are situational → know the one-liner, don't over-invest.

---
### You need to know when and why to introduce it, So Number to Know chapter of Hello interview is important.
## Why Cache

▸ **CRUX** — DB read ≈ **50ms** (disk access every query); in-memory cache (Redis) ≈ **1ms** → **~50x latency win** _and_ offloads the DB. Memory sits close to the CPU, skips disk entirely.

- The whole tension in one line: caches make reads fast + cut DB load, but **create new problems around invalidation + failure handling.** Everything below is managing that trade-off.
- ▹ Quantify it in interviews using `01_core_concepts` capacity numbers (DB vs cache latency) — that's what justifies reaching for a cache.

---

## Where to Cache (the layers)

▸ **CRUX** — caching isn't just Redis. It shows up at **every layer**: browser → CDN → app process → external cache → DB's own cache. Pick the layer that matches the problem.

|Layer|What it is|Reach for it when|Interview note|
|---|---|---|---|
|**External** ⭐ (Redis/Memcached)|standalone cache over the network; every app server shares it|**default** for any high-traffic read path|the expected answer — start here|
|**CDN** (Cloudflare/Fastly/Akamai)|geo-distributed edge servers cache content near users|serving **static media at scale** (can also do API/HTML/edge logic)|introduce when static media is the bottleneck, then expand|
|**Client-side** (browser HTTP cache, localStorage, mobile on-device, client-lib metadata)|data cached on the requester|avoid network calls entirely; offline (Strava run data synced later)|limited backend control → staleness + invalidation harder|
|**In-process** (local memory inside the app)|cache _inside_ the service, no network hop|small, hot, rarely-changing data|**optimization layer only — after** external cache|

### External Cache — why it's the default

▸ **CRUX** — shared across **all** app servers (so it scales horizontally), and supports **eviction (LRU) + TTL** so the memory footprint stays bounded.

### CDN — mechanics

▹ Request → **nearest edge server** → hit: returned immediately · miss: edge **fetches from origin, stores it, returns it** → future users in that region get it instantly. ▹ **The latency case:** origin in Virginia, user in India → **250–300ms per request** without a CDN, vs **20–40ms** from a nearby edge.

### In-Process Cache — the overlooked one

▸ **CRUX** — servers run on machines with **a lot of memory** (and more every hardware generation). Use it: cache data **directly inside the application process** instead of calling out to Redis or the DB. Reads from local memory beat Redis because they **avoid the network hop entirely.**

▹ **The idea:** if your service requests the same small pieces of data over and over, keep a local cache in-process. It's a lightweight form of caching for **small, frequently-requested, rarely-changing** values:

- Configuration values
- Feature flags
- Small reference datasets
- Hot keys
- Rate-limiting counters
- Precomputed values

⚠ **The catch (Problem → Fix):**

- **Problem —** each application instance has **its own** cache → cached data is **not shared across servers**. If one instance updates or invalidates a value, **the others never find out** → they keep serving stale data.
- **Fix —** don't use it as your primary cache. Restrict it to values where staleness is tolerable (config, flags, precomputed), and keep **Redis as the shared source of truth**.

▸ **Interview rule:** blazing fast, but **not a Redis replacement.** Mention it **only as an optimization layer _after_ you've already introduced an external cache** — typically to relieve a hot key.

---

## Cache Architectures (read/write patterns)

▸ **CRUX** — how you read/write changes performance, consistency, complexity. Four patterns; **default to cache-aside.**

|Pattern|How it works|Trade-off|Use when|Interview freq|
|---|---|---|---|---|
|**Cache-aside** ⭐ (lazy load)|app checks cache → hit: return · miss: read DB, populate cache, return|cache miss = extra latency; cache stays lean (only what's needed)|**almost always**|**the one to know**|
|**Write-through**|app writes to cache → cache **synchronously** writes DB before ack|slower writes; can pollute cache with never-read data|reads must always be fresh, writes can be slower|less common|
|**Write-behind** (write-back)|app writes to cache → cache **batches + writes DB async**|very fast writes, but **crash before flush = data loss**|high write throughput + eventual consistency OK (analytics, metrics)|situational|
|**Read-through**|cache is a proxy; on miss the **cache itself** fetches DB, stores, returns|centralizes logic but needs specialized cache lib|rarely at app level|mostly just CDNs|

⚠ **Write-through — dual-write problem (Problem → Fix):**

- **Problem —** cache update succeeds but DB write fails (or vice-versa) → systems diverge.
- **Fix —** retry logic + error handling, or accept that perfect consistency is hard without distributed transactions.
- ▹ Redis has **no native** write-through → needs app code or a framework/plugin to implement it.

▹ **Read-through ≈ CDN:** a CDN _is_ a read-through cache (miss → fetch origin → store → return). For app-level Redis, cache-aside wins — few reasons to propose read-through unless discussing CDN-style infra. ▹ Read-through/write-through are mirror images (cache as intermediary for reads vs writes); systems often run both together.

---

### ⚠ Confusion resolved — Write-Behind vs LSM Tree

> **My doubt:** "Write-behind sounds exactly like an LSM tree / write-heavy DB. Am I wrong somewhere?" **Answer: the resemblance is real** — both **buffer writes in memory now, flush to durable storage later**. Same core move. But they diverge on three axes, and an interviewer can poke at exactly this.

|Axis|**LSM Tree** (`01d`)|**Write-Behind Cache**|
|---|---|---|
|**Where it sits**|the **storage engine of the DB itself** — the source of truth. Nothing sits "behind" it.|a **cache in front of a separate DB**. Two systems; the cache is **not** the source of truth.|
|**Durability** ⭐|**WAL-backed.** Every write is appended to an on-disk log **before ack** → memtable crash → **replay the WAL, nothing lost.** Memtable = performance buffer, not a gamble.|**No WAL.** Redis acks, holds in memory, flushes later → **crash before flush = the write is gone.**|
|**Problem being solved**|dodging **random disk seeks** — turns scattered B-tree leaf updates into sequential appends.|dodging the **synchronous network round-trip to the DB** + batching many writes into fewer DB calls.|

▸ **The one-line hold:** **LSM = durable write buffering (WAL-backed). Write-behind = lossy write buffering (unbacked).**

- Same buffering _shape_, **opposite durability guarantees.** LSM is fast **and** durable; write-behind buys speed by **giving up** durability.
- ▹ That's exactly why write-behind is confined to analytics/metrics (losing a few seconds is survivable), while LSM happily backs **Cassandra as a primary store**.

---

## Eviction Policies

▸ **CRUX** — cache memory is finite → need a rule for what to drop when full. **LRU is the safe default; TTL is essential for freshness.**

|Policy|Evicts|Good for|Note|
|---|---|---|---|
|**LRU** ⭐ (least recently used)|item unused longest|most workloads (recent = likely reused)|default; O(1) via linked list / ring buffer|
|**LFU** (least frequently used)|lowest access count|consistently popular keys (trending videos, top playlists)|approximate LFU avoids exact-count cost|
|**FIFO** (first in first out)|oldest by insertion|rarely — ignores usage patterns|may evict still-hot items|
|**TTL** (time to live)|expired entries|data that must refresh (API responses, session tokens)|**not an eviction policy alone** — pairs with LRU/LFU|

▹ LRU is exactly the `LRU Cache` you're building in LLD (hashmap + doubly-linked list = O(1) get/put). Same structure, applied here as the cache's own eviction.

---

## Common Problems (the failure modes interviewers probe)

> Bringing up caching means owning these — benefits alone don't score.

### Cache Stampede (Thundering Herd)

- **Problem —** a hot entry expires → **many requests miss simultaneously** and all hit the DB in the same window → one query becomes hundreds/thousands → DB overload + cascading failure. (e.g. homepage feed TTL=60s expires at 12:01:00 → every in-flight request stampedes.)
- **Fix —**
    - **Request coalescing / single-flight** — only one request rebuilds the entry, others wait for that result. _Most effective._
    - **Cache warming** — proactively refresh popular keys before they expire. ⚠ **Only helps with TTL-based expiry** — useless if you invalidate on writes instead.

### Cache Consistency (staleness)

- **Problem —** system reads from cache but **writes to DB first** → window where cache holds stale data (update profile pic → old one served until cache refreshes). No perfect solution — choose by how fresh data must be.
- **Fix —**
    - **Invalidate on write** — delete the cache entry after the DB update → next read repopulates it fresh.
    - **Short TTL** — let data be slightly stale, but bound how stale.
    - **Accept eventual consistency** — feeds, metrics, analytics tolerate a short delay.

### Hot Keys

- **Problem —** one key takes disproportionate traffic → overloads a **single Redis node/shard** even at high hit-rate (Twitter: `user:taylorswift` = millions req/s on one node, "working correctly" but bottlenecked).
- **Fix —**
    - **Replicate the hot key** — store it on multiple cache nodes, load-balance reads across them.
    - **Local in-process fallback** — keep the hottest values in-process so you stop pounding Redis.
    - **Rate-limit** — throttle abusive traffic patterns on specific keys.
- ▹ Generalizes to "scaling reads" — same breakdown when millions request identical viral content.

⚠ **Cache failure (raise this in the downsides step):** if Redis goes down, all traffic falls through to the DB at once. **Fix —** fallback to DB + **circuit breaker** (see `01a_networking` fault-tolerance trio) so the DB isn't crushed; optional small in-process last-resort layer.

---

## Interview Playbook

### When to bring it up

▸ **Don't jump to caching — establish the _why_ first.** Trigger it when you identify one of:

- **Read-heavy workload** — 10M DAU × 20 req = 200M reads; even indexed, 20–50ms/query → cache drops to <2ms + offloads DB.
- **Expensive queries** — personalized feed joins posts/followers/likes = 200ms → cache computed feed 60s, serve in 1ms.
- **High DB CPU** — same reads repeated, CPU 80% at peak → caching hot queries cuts load 70–80%.
- **Latency requirement** — need sub-10ms, DB is 30–50ms → must cache.
- Pattern: **name the bottleneck → quantify with rough numbers → show how cache solves it.**

### How to introduce it (5 steps)

1. **Identify the bottleneck** — be specific about what's slow and why ("profile queries: 500/s at peak, 30ms each").
2. **Decide what to cache** — read-often, changes-rarely, expensive to compute. Name the **cache keys** (`user:123:profile`, `trending:posts:global`). _Not everything gets cached._
3. **Choose the architecture** — "cache-aside: check Redis → hit return / miss → DB, store, return." CDN for static media; in-process for extreme hot keys.
4. **Set eviction** — "LRU + TTL 10min on profiles; invalidate immediately on profile update." LRU = safe default, TTL = anti-stale.
5. **Address the downsides** — caching adds complexity; show you've thought about the trade-offs. **Pick one or two that are actually relevant to your system — do not list every possible problem.**
    - **Cache invalidation** — how do you keep cached data fresh? Invalidate on writes, rely on TTL, or accept eventual consistency?
        
        > _"When a user updates their profile, we delete the cache entry so the next read fetches fresh data from the DB."_
        
    - **Cache failure** — what happens if Redis goes down? Does the DB get crushed by the sudden traffic spike?
        
        > _"Requests fall back to the DB. We add circuit breakers so we don't overwhelm it with a stampede, and can keep a small in-process cache as a last-resort layer."_
        
    - **Thundering herd** — what happens when a popular key expires and 1000 requests refetch it at once?
        
        > _"For extremely popular keys, we use request coalescing (or probabilistic early expiration) so only one request hits the DB while the others wait on that result."_
        
    - ▹ **Staff-level calibration:** focus on the **important but non-obvious** scenarios. Don't burn time on things the interviewer already assumes you know.

▹ Core principle for the wrap-up: **don't cache everything.** Show you know when caching is worth the complexity vs when a **well-indexed DB** (`01d`) is enough.

---

## Quick Recall (pass 3+)

|Situation|Reach for|
|---|---|
|Default cache|**External / Redis**, **cache-aside**, **LRU + TTL**|
|Static media, global users|CDN (edge, read-through)|
|Tiny hot rarely-changing data|In-process (optimization layer only, not shared)|
|Reads must always be fresh|Write-through (slower writes; dual-write risk)|
|High write throughput, loss-tolerant|Write-behind (async flush; crash = data loss)|
|Write-behind vs LSM?|same buffering shape — **LSM = durable (WAL-backed)** · **write-behind = lossy (no WAL)**|
|Popular key expires → DB spike|**Stampede** → request coalescing (single-flight) + cache warming|
|Cache vs DB diverge|**Consistency** → invalidate on write / short TTL / accept eventual|
|One key hammering one node|**Hot key** → replicate + local fallback + rate-limit|
|Redis down → DB crush|fallback + **circuit breaker** (`01a`)|
|Which eviction?|LRU default · LFU for steady-popular · TTL for must-refresh · FIFO rarely|
|When to introduce caching|after naming a **quantified** bottleneck (read-heavy / expensive query / DB CPU / latency)|
|Don't cache when|well-indexed DB already suffices|
qr => https://www.hellointerview.com/learn/system-design/core-concepts/caching/quick-reference