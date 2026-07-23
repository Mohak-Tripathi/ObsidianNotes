# Redis — Deep Dive

> Hello Interview · Key Technologies (deep dive) · File `02a`. Overview in `02_key_technologies §9` (cache) + `§10`. Caching patterns → `01e`. **Calibration:** **HIGH value — learn this one deeply.** Redis is the single most **versatile** interview tool: one technology that stands in for cache, lock, leaderboard, rate limiter, geo search, queue, and pub/sub. Learn it well and you cover a dozen problems. ▸ **Why it's interview-friendly:** capabilities are just **data structures** → you can reason about scaling out loud **without knowing deep internals.** That's the whole selling point. ⚠ **Fintech relevance:** rate limiting, distributed locks, idempotency — all Redis, all directly relevant to Razorpay/CRED-style prompts.

---

## The Basics

▸ **CRUX** — Redis is a **"data structure store"** written in C. **In-memory**, executes commands **one at a time on a single thread.**

- **Single-threaded is deliberate:** no locks needed (commands can't interleave), and for operations this simple one core is rarely the bottleneck. → **every command is atomic.**
- ▹ Newer versions offload **I/O and background work** to other threads, but keep the mental model: **one command at a time, in order.**
- **Underneath it's a key-value store:** every value lives at a **string key.** Create a sorted set → it's stored as the value at your chosen key.

⚠ **The durability caveat — the #1 reason NOT to use Redis:**

- **RDB** — periodic snapshots → crash loses **everything since the last snapshot.**
- **AOF** — logs every write but **fsyncs once/sec by default** → crash loses **up to 1 second** of acknowledged writes.
- You _can_ fsync-every-write, but **few do** — it costs the speed they came for.
- ▸ **This is intentional. You do NOT get the "commit is on disk" guarantee a relational DB gives you.** _(AWS MemoryDB trades some speed for real disk durability if you need it.)_

#### ⚠ Confusion resolved — why persistence exists at all (if the DB is the source of truth)

> **My doubt:** "Redis is just an in-memory server. If I use cache-aside with Postgres as the truth, the cache rebuilds itself on a miss. So why do RDB/AOF exist? Why isn't it a rare feature? And if request coalescing already stops the thundering herd, why is warm-up even needed?"

▸ **Persistence is NOT about correctness. It's about surviving a restart without going ice-cold.**

- Zero persistence → Redis crashes → restarts **completely empty** → every key is now a miss → your **entire dataset's** reads fall through to the DB **at once.**
- That's not a hot-key problem — it's a **total thundering herd at the scale of everything you cached.** Your DB was sized assuming the cache absorbs ~95% of reads; now it absorbs 0%.
- ▸ **So RDB/AOF exist (even for a pure cache) so a restart comes back _mostly warm_ instead of _completely empty_.** It's not correctness (cache-aside self-heals — a miss just re-fetches + repopulates). It's an **operational kindness to your backing DB on restart.**

▸ **Is it on by default?** Yes — most deployments ship with **RDB snapshotting on** (e.g. "save every 60s if 10k+ keys changed"). Nobody reasons about it; it's just there, quietly softening restarts. **So it's not rare — it's already running under a normal cache-aside setup.** You only _tune_ it (AOF, fsync frequency) when you have a reason to care more.

⚠ **The key correction — "doesn't coalescing already fix this?" NO. They defend different-shaped problems:**

- **Coalescing protects ONE key** — when a single key is missing, one request rebuilds while others wait. Fixes **depth on one key.**
- **A cold restart breaks ALL keys at once** — say 10M distinct keys, each requested by different users. Coalescing dedupes _within_ a key, but **10M different keys = 10M unique DB queries** that all must actually run — they're **not duplicates**, so coalescing can't merge them.
- ▸ **Coalescing = depth (one hot key). Warm-up = breadth (millions of cold keys).** They don't overlap. Coalescing turns "50M requests → 10M unique queries," which is **still** a flood the DB was never sized for.

▹ **"Isn't a fresh launch also a cold cache?"** Yes — it's called a **cold start**, and it's a real concern. But it's manageable in a way a mid-life crash isn't:

- A **launch is planned** → you can **pre-warm** (load hot keys before taking traffic) or ramp traffic gradually. A **3 a.m. crash gives none of that** — traffic is already at peak when Redis comes back empty.
- Load **grows into** a fresh system (DB load ramps with the user base); a crash **slams** full peak traffic into an empty cache instantly.

▸ **The honest bottom line (your instinct was right):**

- **Pure cache-aside** → RDB warm-up is a **nice-to-have, not a necessity.** The DB is the truth; the cache rebuilds itself. Many teams run cache-aside with persistence **off** and accept the re-warm risk (fine if the DB can take the burst, or they pre-warm / ramp). It's **insurance, not a requirement** — it's on by default, cheap, and removes the crash-at-peak risk, so most just leave it on.
- **Redis holding something with NO other copy** (stream/queue jobs, session-only data, in-flight rate-limit counters, lock state) → persistence stops being optional. Losing that isn't "slow re-warm," it's **"data gone forever"** → _this_ is when you deliberately configure **AOF-everysec** or pay for **MemoryDB.**
- ▸ **The line to hold:** cache-aside data → persistence = **restart behavior** (not correctness). Irreplaceable state → persistence = **how much you're willing to lose** (a real per-feature decision).

▸ **Core data structures:** strings · hashes · lists · sets · **sorted sets** (priority queues) · **streams** (append-only logs) · geospatial indexes.

- ▹ Redis 8 ships **Bloom filters, JSON, time-series** in core (were Stack modules before).
- Also does **Pub/Sub** and **Streams** → partially stands in for Kafka / SNS / SQS.

#### ▸ Why the value's DATA STRUCTURE matters in Redis (not just "it's fast memory")

> **The reframe:** _"Redis is just fast RAM — why do I care what shape the value is?"_

- In a **dumb cache** (Memcached, or Redis used lazily) the value is an **opaque blob.** To change one thing inside it: fetch the whole blob → deserialize → edit → reserialize → send it all back. **Two round trips + you rewrite everything + read-modify-write race.**
- Redis's real superpower: the value is a **live server-side object Redis understands.** You send _"increment field X"_ or _"add this to the ranking"_ → Redis mutates it **in place, on its own thread, atomically.** **One round trip, no refetch, no race.**
- ▸ **So the structure decides what Redis can do FOR YOU server-side:**
    - **String blob** → nothing smart; you fetch + rewrite _(fine for "cache this JSON")_
    - **Hash** → update **one field** _(bump cart quantity without refetching the cart)_
    - **Set** → _"is X a member?"_, intersect/diff two groups
    - **Sorted set** → keeps things **ranked** → "top 10" is instant
- ▸ **The question to always ask:** _do I just store-and-fetch (blob), or do I need Redis to compute/mutate something for me?_ If compute/mutate → pick the structure that makes that operation **one fast command.** That's the entire reason these types exist instead of "just store a string."

**Value type → cache use-case (quick map):**

|Need|Type|
|---|---|
|Serialized blob / atomic counter (`INCR`)|**String**|
|Object with independently-updated fields|**Hash**|
|Ordered list, push/pop at ends, simple queue|**List**|
|Uniqueness, membership, intersect/diff groups|**Set**|
|Ranked by score — leaderboard, priority, sliding window, scheduler|**Sorted Set**|
|Event log with consumer groups + ack|**Stream**|
|"Near me" radius search|**Geospatial**|
|Nested document, path-level updates|**JSON** (Redis 8)|
|Huge-scale "probably seen / definitely not", memory-cheap|**Bloom filter** (Redis 8) _(same structure as LSM → `01d`)_|
|Timestamped metrics with rollups|**Time series** (Redis 8)|

---

## Infrastructure & Scaling

▸ **CRUX** — three modes: **single node** · **HA (primary + replica)** · **cluster.**

### Cluster = sharding via hash slots

- Every key hashes to one of **16,384 hash slots**; each slot is assigned to a node. **Each node owns a share of slots → a share of keys.** _(This is the fixed-slot approach from `01g` — NOT ring consistent hashing.)_
- **Clients cache the slot→node map** → compute the slot from the key, connect **directly** to the right node.
- ▹ **MOVED protocol:** ask the wrong node → it replies **`MOVED`** pointing at the right node (it **won't forward** for you). Client refreshes its map (`CLUSTER SHARDS`). Nodes share the full slot map via **gossip.**

⚠ **Replication is ASYNCHRONOUS** — the primary acks your write **before** the replica sees it. Primary dies → promoted replica **may never have seen the last few writes → they vanish.**

- ▸ **This is the deepest reason Redis isn't a system of record** — and it's the same failure that makes Redis locks unsafe (below).

⚠ **Redis clusters are deliberately basic** — they hand you **primitives**, not solutions. **Redis expects all data for one request on a single node.**

- **Key structure IS how you scale Redis.** _(Same lesson as shard keys → `01f`.)_
- **Hash tags** — only the part in **`{braces}`** is hashed → `{user:123}:posts` and `{user:123}:likes` land in the **same slot** → can run a `MULTI` transaction across both.

### Performance

- **~100k writes/sec** per node; commands execute in **microseconds**; **sub-ms** reads over the network.
- ▹ **N+1 is survivable here** (unlike SQL) — each command is microseconds, and you can **pipeline** or **`MGET`** to pay **one round trip instead of 100.** Still better to avoid, but it won't sink you.
- All of this speed is **purely a function of being in-memory.**

---

## The Seven Capabilities

> This is the real value of the file — the seven jobs Redis does in interviews.

### 1. Cache ⭐ (most common)

- Cache keys = Redis keys, cached values = Redis values. Scale by **adding nodes.**
- Store a product at `product:123` as a JSON blob or a **Hash** (`name`, `price`, `inventoryCount`).
- **TTL** — Redis guarantees you never read a key after its TTL expires. ⚠ **TTL handles staleness, NOT memory pressure** — out of the box Redis **rejects writes when memory is full.** For a cache, set an eviction policy: **`allkeys-lru`.**
- ▹ Redis approximates LRU by **sampling** keys, not tracking exact order — plenty for a cache.
- ⚠ Doesn't solve the **hot key** problem (see remediations below). _(Caching patterns → `01e`.)_

### 2. Distributed Lock

> Full lock concept → `02 §8`. Here's the Redis-specific implementation.

- **Acquire:** `SET lock:concert:343 my-token NX EX 30`
    - **`NX`** — succeed only if the key doesn't exist → if it worked, you own the lock.
    - **`EX 30`** — 30s expiry → a crashed holder can't lock forever.
    - **`my-token`** — a random value unique to you (matters on release).
- ⚠ **Release is NOT a blind `DEL`.** Your lock may have expired and been re-acquired by someone else → blind delete removes _their_ lock. **Check the token still matches, then delete — as one atomic Lua script:**
    
    ```
    if redis.call("GET", KEYS[1]) == ARGV[1] then return redis.call("DEL", KEYS[1]) end
    ```
    
- ▹ This is **pessimistic** locking (grab lock _before_ work). Redis also does **optimistic** — `WATCH` a key, `MULTI`/`EXEC`, aborts if the watched key changed.

⚠ **The critical warning — a Redis lock is NOT a correctness guarantee:**

- Async replication (above) → primary dies after granting → promoted replica grants the **same lock to someone else.**
- **Redlock** (acquire on a **majority** of independent nodes) tries to fix this — but it's **controversial** (Kleppmann's critique: a paused/slow client can act after its lock expired).
- The standard defense is a **fencing token** (increasing number; storage rejects stale ones) — **Redis has nothing built in for this.**
- ▸ **Treat a Redis lock as an efficiency tool that occasionally fails, not a correctness guarantee.** If a stale holder would **corrupt data**, enforce the invariant **where the data lives** — `SELECT ... FOR UPDATE` or `UPDATE ... WHERE version = X` in your DB — or use **ZooKeeper / etcd.** _(⭐ For fintech: money invariants belong in the DB, not a Redis lock.)_

### 3. Leaderboard — sorted sets

> ⭐ **The one structure worth understanding deeply** — it powers 4 different capabilities in this file (leaderboard, sliding-window rate limiter, priority queue, scheduler).

▸ **What a sorted set is:** a set of unique **members**, each with a **score** (a number). Redis keeps them **permanently ordered by score** — automatically, on every insert. **You never sort.** Ranking is **free at read time because Redis paid for it at write time.**

⚠ **Why a plain Set is NOT enough:**

- A **Set** answers _"is X a member?"_ — membership, yes/no. **No scores, no order.**
- 100k players in a Set + "top 10 by points" → Redis must pull all 100k and **sort them every read** → O(n log n) per read → useless for a live board.
- ▸ **Set = membership. Sorted set = membership + ranking.** The score is the entire difference.

▸ **How LeetCode uses it in a live contest** (100k participants, rank updating in real time):

- One sorted set per contest: `leaderboard:contest:456` · member = user ID · score = points.
- **You solve a problem → score changes:**
    
    ```
    ZADD leaderboard:contest:456 1500 "user:789"
    ```
    
    `ZADD` on an existing member **updates the score and re-slots them to the correct rank instantly** — part of the write, no re-sort.
- **Render the top 10:**
    
    ```
    ZREVRANGE leaderboard:contest:456 0 9 WITHSCORES
    ```
    
    Instant — it's already ordered.
- **Show a user their own rank** ("#4,213 of 100k") — ⭐ **the feature that makes a Set hopeless:**
    
    ```
    ZREVRANK leaderboard:contest:456 "user:789"
    ```
    
    Rank among 100k in **O(log n).** A Set can't answer this at all; a SQL `COUNT(*) WHERE score > mine` would hammer the DB on every refresh for every user.

▸ **The intuition to keep:** a sorted set is a **live ranking that maintains itself.** Pay a tiny `O(log n)` on each write to slot the member correctly → **every ranking question is cheap forever** (top-N, my-rank, everyone-between-two-scores). That **"pay at write, free at read"** trade wins whenever ranking is **read far more often than it changes** — which is every leaderboard.

▹ **Post-search example** ("tiger" posts by likes):

```
ZADD tiger_posts 500 "SomeId1"      # add/update a post's score
ZREMRANGEBYRANK tiger_posts 0 -6    # keep only the top 5
```

`ZADD` replaces the score if the member exists → re-adding just **moves its rank.** `ZREMRANGEBYRANK 0 -6` removes lowest up to 6th-from-top → leaves the **top 5.**

▸ **Same structure, 3 other jobs** (all "attach a number, let Redis keep it ordered, ask range/rank cheaply"):

- **Sliding-window rate limiter** — score = **timestamp** → "requests in last 60s" is a range query (capability #4).
- **Priority queue** — score = **priority** → pop the highest.
- **Delayed-job scheduler** — score = **"run at" epoch** → poll for scores ≤ now.

### 4. Rate Limiting

▸ **Goal:** each user makes at most **N requests per W seconds** (e.g. **5 per 60s**).

▸ **Fixed window — the core idea:** keep a **counter** of requests in the current window; let it **auto-delete after W** so the next window starts fresh at 0.

- `INCR key` — add 1, return the new value (fresh key → returns 1).
- `EXPIRE key 60` — auto-delete the key in 60s.

```
count = INCR user:123:requests      # count this request
if count > 5: reject (429 + Retry-After)
else: allow
```

When the key expires, it vanishes → next `INCR` starts from 1 → fresh window. _(`429` = HTTP "too many requests"; `Retry-After` tells the client how long to wait.)_

⚠ **Gotcha 1 — set the expiry ONLY on the first request of the window.**

- `EXPIRE` means "expire 60s **from now**", not "60s from key creation." Call it every request → every request **pushes the deadline forward.**
- Steady 1-req-every-10s traffic: 0:00 expire@1:00 · 0:10 expire@**1:10** · 0:20 expire@**1:20**… → **the reset runs away, the counter never resets** → user climbs 6, 7, 8 → **permanent lockout despite being under the limit.**
- **Fix:** set expiry only when the key was just created. `INCR` returns **1** exactly when the key was fresh → gate on it:

```
count = INCR user:123:requests
if count == 1:                      # created the key → brand-new window
    EXPIRE user:123:requests 60     # start the 60s clock ONCE
if count > 5: reject
else: allow
```

⚠ **Gotcha 2 — run `INCR` + `EXPIRE` as ONE Lua script.**

- Two commands must both happen. Crash **between** them → `INCR` ran (key exists) but `EXPIRE` didn't → **key exists with no expiry → never auto-deletes → counter stuck forever → permanent lockout.**
- **Fix:** bundle both in a **single Lua script** — Redis runs it **atomically on its single thread** (all or nothing, no in-between). _(Same atomicity trick as the lock-release `GET`-then-`DEL`.)_

▸ **Both gotchas are the same fear — a counter that never resets and locks the user out** — reached two ways: resetting the clock too often (call `EXPIRE` every time) vs never setting it at all (crash before `EXPIRE`).

▸ **Sliding window** — one sorted set per user, **timestamp as score:** `ZREMRANGEBYSCORE` (drop entries older than the window) → `ZCARD` (count what's left) → `ZADD` the new request if under N. **As one Lua script.**

- ▸ ⭐ Directly relevant to fintech API rate limits.

### 5. Proximity Search — geospatial

- `GEOADD key lon lat member` · `GEOSEARCH key FROMLONLAT lon lat BYRADIUS r unit`.
- Runs in **O(N + log M)** — N = candidates in the bounding box, M = items within the exact radius.
- ▹ **Why two terms:** Redis uses **geohashes** under the hood (lat/lng → one sortable value in a sorted set — the `log` is the seek). Geohash boxes are **grid-aligned squares → imprecise** → first pass grabs N candidates in the boxes, second pass filters to the M within the true radius. _(Geohash mechanics → `01d`.)_

▸ **Worked example — Swiggy "drivers near me":**

**Setup — one sorted set per city.** `drivers:bangalore`, `drivers:mumbai`… Inside `drivers:bangalore`: **all 50,000 drivers**, no ranking.

- member = driver ID · **score = geohash** (their lat+lng squashed into one sortable value).
- ▸ **Not used for top-N** — used purely because the set stays **sorted**, so you can **jump into the middle at the right spot.**

**Why drivers "club together" — the key trick.** A geohash is engineered so **physically-near places produce alphabetically-near strings:**

```
tdr1y8   ← driver:42  MG Road   ┐
tdr1y9   ← driver:99  MG Road   ├─ neighbors land adjacent
tdr4k2   ← driver:7   Airport (30km) → sits far down the list
```

Sort by geohash → the set is **automatically laid out geographically**, each neighborhood a **contiguous block:**

```
drivers:bangalore (sorted by geohash)
tdpx… ┐ Whitefield
tdpz… ┘
tdr1y8 ┐ MG Road
tdr1y9 ┘
tdr4k2 ┐ Airport
tdr4k5 ┘
```

Nobody arranges this — it falls out of geohash + sorted order.

**Write side — drivers keep moving.** Each GPS ping (~every 4s) = **one command:**

```
GEOADD drivers:bangalore <newLng> <newLat> driver:42
```

`GEOADD` on an existing driver **updates the score and re-slots them** — same re-score mechanic as `ZADD` on a leaderboard, just scored by _location_ instead of _points_. 50k drivers × ping/4s ≈ 12.5k writes/sec → trivial (100k/sec/node).

**Read side — the calculation (NO full-city scan):** rider at MG Road wants drivers within 3km:

```
GEOSEARCH drivers:bangalore FROMLONLAT <riderLng> <riderLat> BYRADIUS 3 km
```

- **① Circle → string range.** Redis computes the geohash prefix for the rider's spot → "near me" becomes "members whose geohash starts with `tdr1`."
- **② Binary-search to that prefix** — the set is sorted, so Redis **jumps** to where `tdr1…` begins. **~16 comparisons** (log₂ 50,000), _not_ 50,000. Skips Whitefield, airport, everyone else — never looks at them. ← the **`log`** term.
- **③ Read straight down** until the prefix ends → your neighborhood block, **~400 drivers**, not 50,000. ← these are the **N** candidates.
- **④ Square→circle cleanup** — the boxes are square and over-grab past the 3km circle, so Redis computes each candidate's **real distance** and drops those beyond 3km. What survives = **M** (truly within radius).

▸ **The tally:** ~16 (seek) + ~400 (read block) + filter-400-to-circle → **you compared ~416 things, not 50,000.** The reduction is entirely because **geohash string order = geographic order**, so your area is one jump-to-able block.

- ▹ **Honest caveat:** a circle can spill into a few _adjacent_ boxes → Redis seeks a handful of prefix-ranges, not always one. Same mechanic, repeated. `GEOSEARCH` handles it for you.
- ▸ **The one-line hold:** a geo index is **a leaderboard scored by location.** Moving = re-scoring · "who's near here" = read a score-range · N-vs-M = squares can't perfectly tile a circle.

### 6. Event Sourcing — streams

- **Streams** = append-only logs like Kafka topics; the building block for event sourcing. Producers `XADD`; consumer groups (`XREADGROUP`, `XCLAIM`) coordinate who processes what.
- **Work queue pattern:** `XADD` items → one consumer group → worker reads via `XREADGROUP`, processes, acknowledges. Pending entries track **idle time**; a dead worker's entry climbs in idle time until another worker `XCLAIM`s it.
- ⚠ That reclaim means an item can be **processed twice** (Redis can't tell slow from dead) → **make processing idempotent.**
- ⚠ Stream entries are **only as durable as your persistence settings** (the durability caveat again).
- ▸ **Redis streams vs Kafka:** Redis streams fit when you **already have Redis** and the queue is **modest** (background jobs, notification fan-out). **Kafka** earns its complexity for **long retention, replay for many independent consumers, or durable ordered throughput** where losing a message is unacceptable. _(Kafka vs everything → `02 §7` confusion block.)_

### 7. Pub/Sub

- **Broadcast to whoever's listening right now.** `PUBLISH channel message` / `SUBSCRIBE channel`. Great for chat, real-time notifications.
- ⚠ **Not durable — "at most once."** Subscriber offline when a message is published → **misses it entirely.** No persistence, no replay.
- ▸ **Streams vs Pub/Sub:** Streams = consumers **catch up on what they missed.** Pub/Sub = deliver to **current** listeners only.
- ▹ **Outdated criticism to NOT repeat:** classic cluster Pub/Sub broadcast every message to every node (adding nodes didn't add capacity). **Since Redis 7, sharded Pub/Sub (`SPUBLISH`/`SSUBSCRIBE`)** routes each channel to its slot's shard → **capacity scales with the cluster.**
- ▹ **Connection overhead is per node, not per channel** — one connection carries all subscribed channels → millions of channels ≠ millions of connections.
- **Need offline delivery / durable fan-out?** → Redis **Streams**, or pair Pub/Sub with a queue (SNS→SQS, Kafka) or the **outbox pattern** (write messages to a DB).

▹ **"Can I roll my own Pub/Sub?"** — candidates propose "store subscriber addresses in a key, publishers look up and send directly." **Don't.** It adds a **third network hop** (the expensive one — no pre-established TCP connection), and needs **heartbeats/TTLs** to detect dead servers → lots of chatter. **If it looks like Pub/Sub, use Pub/Sub.**

---

## Hot Key Problem & Remediations

⚠ **The setup:** 100 nodes, items evenly spread. One item suddenly gets traffic equal to _all the rest combined_ → **one server's load spikes → it fails.** _(Same phenomenon as `01e` hot keys, `01f` celebrity problem, `01g`.)_

### ⚠ Prerequisite — "how do you even know which key is hot?"

All three remediations assume you know the hot key. Two ways you find out:

- **Known in advance (static)** — the business tells you. Ticketmaster knows the Taylor Swift concert is hot the moment it's listed; Swiggy knows a promoted restaurant during an IPL match will spike. Hard-code these.
- **Detected at runtime (dynamic)** — you **measure.** Redis reports per-key frequency (`OBJECT FREQ`, or track counts yourself); a background monitor promotes any key crossing a threshold onto a **"hot-list"** that app servers can read.
- ▸ So you **don't** need to hand-know every hot key: the app server can **programmatically maintain its hot-set** from Redis's frequency data. Since hot keys are only ~**0.5% of all keys**, reserving a small slice of RAM for them is cheap — and worth it.

**Remediations (all with tradeoffs):**

### 1. App-server-side cache

⚠ **Terminology fix: this is the APP SERVER's cache, NOT "client-side."** It lives in the **RAM of your app server** (the EC2 instance between user and Redis) — **not** the user's browser, not cookies.

```
user → app server (tiny local cache in its own RAM) → Redis → DB
```

- Request for the hot item → app server checks **its own memory first** → hit → answers immediately, **the request never travels to Redis.**
- ▸ **You don't have to pre-name the hot key:** cache whatever you fetch with a **short TTL** (e.g. 5s). The hot item is requested constantly → stays resident; cold items fall out → it **self-selects.** Better still, drive it from the hot-list above so you **skip the Redis hop entirely** for known-hot keys.
- **Cost:** a second cache to keep coherent → you serve data **stale by up to the TTL** (you're not re-checking Redis in that window) → best with **short TTLs on a small set of keys.**

### 2. Key copies

- Hot key `product:123` lives on **one node** (one slot) → all its traffic hammers that node. Fix: store the value under **several key names** — `product:123:1` … `product:123:10`. Different **names** → **different slots → different nodes** → 10 nodes share the load.
- On read, pick a **random suffix** (`product:123:` + random 1–10) → reads spread across all 10 nodes.
- ▸ **Where this logic runs: the APP SERVER / business logic**, not the user's browser. The app server checks the hot-list, appends the suffix, hashes it, routes to the slot. Redis just receives a normal request for a normal key name.
- **Cost:**
    - the app server must **know which keys are duplicated** (the hot-list again).
    - **every write fans out** to all 10 copies, or they'd disagree.
- ▹ Works regardless of Redis using **fixed hash slots** (not the ring, → `01g`) — all that matters is _different names hash to different places._

### 3. Read replicas

- A replica of the **Redis instance itself** — a read-only **copy** of the primary. Adds read capacity: 1 primary + 2 replicas ≈ **3x reads** for that key.
- ⚠ **Two caveats interviewers probe:**
    - cluster clients read from the **primary by default** → replicas only help if clients are **configured for replica reads.**
    - ▸ **Replicas do NOTHING for a WRITE-hot key.** Every write still goes to the **one primary** (replicas only _copy_ it, can't accept writes) → a constantly-**written** key still hammers that single primary. Replicas help **read**-hot keys only.
- ▹ Same asymmetry as `01i` and `01g`: **replication copies data for reading; it never distributes write load.**

### ⚠ Read-hot vs WRITE-hot — where write-hot even comes from, and how to fix it

> **The realization:** a write-hot key is **NOT** the rare "write-through cache" pattern. It's what happens when **Redis IS the store for that data** (no DB behind it) — and then writing to Redis _is_ the workload.

▸ **When the constant write comes** — you're not storing once and reading; you're **updating the same key every time.** All the non-cache capabilities in this file are write-heavy by nature:

- **Rate limiter** — every request does `INCR` → hot endpoint = write-hot key.
- **Leaderboard** — every score change is `ZADD` → live contest = constant writes.
- **Driver locations** — every GPS ping is `GEOADD` → 12.5k writes/sec, all writes.
- **Distributed lock** — every acquire is a `SET`.
- ▸ **So:** _writes-to-a-cache_ are rare (cache-aside sends writes to the **DB**) — but **write-hot Redis keys are common**, because most of Redis's jobs aren't caching.

⚠ **Why write-hot is harder than read-hot:** read-hot has a free fix (more copies to read from). Write-hot doesn't — all writes must converge somewhere consistent, so you can't just "add more places to write." Every fix is either **split the key** or **touch the primary less often:**

- **① Shard the key (split the counter)** ⭐ **— the dominant fix.** Instead of one `counter:post:123`, keep N sub-counters `counter:post:123:0…:9` on different nodes. Each write → a **random** shard → write load splits across N nodes. Read the total = **sum the N.**
    - ▹ Mirror of "key copies," but opposite: read-hot **duplicates the same value**; write-hot **partitions the value into pieces that sum.**
- **② Pre-aggregate in the app server** — don't send every increment. Each app server keeps a **local running count in RAM** and flushes once/sec with one `INCRBY 250`. 1000 requests → 1 Redis write. Trade up-to-1s accuracy for a huge write drop. Ideal for metrics, view counts, analytics.
- **③ Batch / pipeline** — group many writes into one round trip (`pipeline`, `MSET`). Cuts network overhead; partial measure, usually combined with the above.
- **④ Rethink the store** — a durable, constantly-written value may belong in a **write-optimized store** (Cassandra / Kafka stream aggregated downstream — LSM append-only, `01d`), not Redis.

▸ **The interview move:** say the split out loud — _"replicas won't help here, it's write-hot; I'd shard the counter across N keys and pre-aggregate per app server."_ That's the depth that separates memorized-fixes from understanding the **read/write asymmetry.**

▸ **The prerequisite under all three read-side remediations:** you know the hot key because the **business tells you** (concert, sale) **or** you **monitor access counts** and promote it to a hot-list. ▸ **Interview move:** _recognizing_ the hot key issue is good (+); **proactively designing a remediation is better (++).**

---

## ⚠ When NOT to Use Redis

> State this boundary plainly — knowing when _not_ to reach for your favorite tool is a senior signal.

- **Not your system of record** — async replication + persistence-loss windows → **acknowledged writes can vanish.**
- **Not when the working set can't economically fit in RAM** — memory is the most expensive place to store data.
- **Not for query flexibility** — **no joins, no cross-key queries**; in a cluster, multi-key ops only work **within one slot** (hash tags aside).
- **Not for durable, replayable, long-retention streams with many independent consumers** — that's **Kafka's** job.

---

## Quick Recall (pass 3+)

|Use / Question|Redis answer|
|---|---|
|What is Redis?|in-memory **data structure store**, **single-threaded** → every command **atomic**|
|#1 reason to avoid|**durability** — RDB loses since last snapshot · AOF loses ~1s · async replication loses last writes|
|Why persistence exists (even for a cache)|**restart warm-up**, not correctness — empty restart = whole-dataset thundering herd on the DB. RDB is **on by default**|
|Coalescing vs warm-up|**coalescing = depth (1 hot key)** · **warm-up = breadth (millions of cold keys)** — they don't overlap; coalescing can't merge 10M _unique_ misses|
|When persistence is mandatory (not optional)|Redis holds data with **no other copy** — stream/queue jobs, session-only data, in-flight counters → configure **AOF / MemoryDB**|
|Cluster sharding|**16,384 hash slots** (fixed slots, not ring consistent hashing → `01g`); client caches slot→node, `MOVED` on miss|
|Co-locate two keys|**hash tags** — `{user:123}:posts` + `{user:123}:likes` → same slot → `MULTI`|
|Throughput|~**100k writes/sec**/node, **µs** commands, **sub-ms** reads|
|Cache eviction|`allkeys-lru` (TTL handles staleness, **not** memory — Redis rejects writes when full)|
|Lock acquire|`SET key token NX EX 30` · release = **Lua check-token-then-DEL**|
|Lock is…|⚠ **efficiency tool, not correctness.** Async repl breaks it; Redlock controversial; **no fencing token.** Money invariants → enforce in DB|
|Leaderboard|**sorted sets** — `ZADD` / `ZREVRANGE` / `ZREVRANK`|
|Why sorted set over Set?|Set = membership only · sorted set = **membership + ranking** (score). "My rank of 100k" in **O(log n)** — a Set can't do it|
|Sorted set intuition|**pay O(log n) at write, ranking free at read** → wins when ranking is read ≫ changed|
|Why the value's structure matters|Redis mutates the **live object server-side** (one atomic command, no refetch) vs opaque blob (fetch→edit→rewrite)|
|Rate limiter|fixed: `INCR` + `EXPIRE`-**on-first-only** (Lua) · sliding: sorted set of timestamps (Lua)|
|Rate limiter — 2 gotchas|both = **counter never resets → lockout**: (1) `EXPIRE` every request pushes reset forward → set only when `INCR==1` · (2) crash between `INCR`/`EXPIRE` → no expiry → one Lua script|
|Proximity|`GEOADD`/`GEOSEARCH`, **O(N+log M)**, geohash under the hood|
|Proximity mechanic|**one sorted set per city**, score = geohash → geohash string order = **geographic order** → binary-search to your prefix-block (~16 hops in 50k), read ~400, filter to circle. **Geo index = leaderboard scored by location**|
|Streams vs Pub/Sub|streams = **catch up on missed** (durable-ish) · Pub/Sub = **current listeners only**, at-most-once|
|Redis streams vs Kafka|Redis = already-have-it + modest queue · Kafka = long retention, replay, durable scale|
|Hot key fixes|**app-server** RAM cache (not "client-side") · key copies (suffix → diff slots) · read replicas (⚠ **read**-hot only)|
|Where write-hot keys come from|Redis used as **store not cache** — `INCR` rate limiter, `ZADD` leaderboard, `GEOADD` locations → writing IS the workload|
|Write-hot fixes (replicas useless)|**shard the counter** (`:0…:9`, sum to read) · **pre-aggregate** in app server (flush once/sec) · batch/pipeline · or write-optimized store|
|How to know a key is hot|business tells you (concert/sale) **or** monitor frequency (`OBJECT FREQ`) → **hot-list**. ~0.5% of keys → cheap to track|
|Where suffix/routing logic runs|**app server / business logic**, not the browser|
|Roll-your-own Pub/Sub?|**No** — extra hop + heartbeat chatter. Use Pub/Sub|