# Sharding — Deep Dive

> Hello Interview · Core Concepts (deep dive) · File `01f`. Overview in `01_core_concepts`. **Calibration:** **HIGH value / core** — comes up any time you discuss scaling. Must-knows: **shard key choice**, **hash-based as default**, and the three challenges (**hot spots / cross-shard queries / consistency**). You will _not_ implement sharding internals — modern DBs do it. **The #1 interview mistake is sharding before proving it's needed.**

---

## Why Shard

▸ **CRUX** — you scale a DB **vertically** (bigger instance: more CPU/memory/storage) until you hit the **ceiling of a single machine**. Then queries slow, writes bottleneck, storage caps out (even Aurora maxes ~**256 TiB**). At that point there is exactly **one real option: split the data across multiple machines.**

- Sharding solves scale but **introduces new problems** — shard key choice, query routing _(sending each query to the correct shard that actually holds the data)_, hot spots, rebalancing. Everything below manages those.

### Partitioning vs Sharding (the terminology)

▸ **CRUX** — people use the words interchangeably. The one distinction that matters: **is your data on one machine or many?**

||**Partitioning**|**Sharding**|
|---|---|---|
|Scope|splits a large table **inside a single DB instance**|splits data **across multiple machines**|
|Adds machines?|❌ no — just organizes data into logical pieces|✅ yes — each shard is a standalone DB|
|Purpose|smaller pieces the DB can manage separately (query scans only the relevant partition; indexes/vacuum/analyze stay manageable)|scale **storage capacity + read/write throughput**|

▹ **Why partitioning helps at all:** an `orders` table with 500M rows / 2TB → a query for last month scans the **whole table**; indexes get huge and slow to maintain; vacuum/analyze/reindex can **lock the whole table**. Partition it → the query scans only last month's partition.

▹ **Two types of partitioning:**

- **Horizontal** — split **rows** across partitions (e.g. one partition per year of orders). _Same columns, fewer rows each._
- **Vertical** — split **columns** across partitions (e.g. hot columns in one, large/rarely-used columns in another). _Same rows, fewer columns each._

▸ **Sharding = horizontal partitioning across multiple machines.** Each shard is a **standalone DB with its own CPU, memory, storage, connection pool.** No single machine holds all data or serves all traffic.

### ⚠ Confusion resolved — what "a user's shard" actually means

> **My doubt:** "If I have users, orders, posts in one DB and I shard by `user_id`, surely **every shard still has all three tables**? So why say _'the user's shard'_ — as if a shard only holds user data?" **You're right, and the phrase is sloppy shorthand.** Here's the precise version:

- Sharding by `user_id` does **NOT** mean "users table → shard 1, orders → shard 2." That's splitting by **table** (functional partitioning) — a **different thing entirely.**
- It means: **every table carrying `user_id` is sharded by that same key.** Each shard is a **full database** with users + orders + posts — just **fewer rows** of each.
- ▸ **The payoff is CO-LOCATION:** every row belonging to user 123 — their user row, their orders, their posts — lands on the **same** shard, because they all hash the same `user_id`.
- So **"Taylor Swift's shard"** = the shard holding _her user row + her posts + her orders_. **Not** a shard that only holds user data.
- **Master / reference tables** (small, read-mostly, no `user_id`) → just **replicate to every shard**.

---

## How to Shard — Two Decisions

▸ **CRUX** — sharding is always **two decisions that work together**:

- **What to shard by** → the **shard key** (which field groups the data).
- **How to distribute it** → the **strategy** (the rule assigning groups to machines).

### 1. Choosing the Shard Key

⚠ **A bad shard key gives you:** uneven data distribution · hot spots (one shard pounded, others idle) · queries forced to hit **every** shard.

▸ **Three properties of a good shard key:**

- **High cardinality** — many unique values. A boolean shard key = **2 shards max**, which defeats the purpose. Millions of user IDs = plenty of room to spread.
- **Even distribution** — values spread evenly. Sharding by **country** when 90% of users are US = one massive shard.
- **Aligns with queries** — your **most common query should hit exactly one shard.** Queries that span all shards are expensive.

**Examples — good vs bad shard keys:**

||Key|Verdict|Why|
|---|---|---|---|
|🟢|`user_id` (user-centric app)|**Good**|high cardinality · even · most queries are already scoped to one user → **perfect fit**|
|🟢|`order_id` (e-commerce orders)|**Good**|high cardinality · queries scoped to a specific order · orders distribute evenly over time|
|🔴|`is_premium` (boolean)|**Bad**|only 2 possible values → 2 shards; if most users are free, that shard is overloaded|
|🔴|`created_at` (growing table)|**Bad**|**all new writes land on the newest shard** → write hot spot; old shards idle|

### 2. Choosing the Distribution Strategy

|Strategy|How|Pro|Con|Verdict|
|---|---|---|---|---|
|**Range-based**|assign value ranges to shards (`shard1 = users 1–1M`, `shard2 = 1M–2M`…)|simplest; **efficient range scans** (users 500K–600K = one shard)|real access patterns rarely spread evenly across ranges|good for **multi-tenant** (each company owns a range)|
|**Hash-based** ⭐|`shard = hash(user_id) % N`|**even distribution** — the hash scrambles inputs|**resharding pain:** 4→5 shards changes `% 4`→`% 5` → almost every record moves|**the default.** Interviewer assumes this unless you say otherwise|
|**Directory-based**|a **lookup table/service** maps each record → shard|max **flexibility** (move a heavy user to a dedicated shard; rebalance by editing the map)|**every request needs a lookup** → added latency + the directory is a **single point of failure**|**rarely the interview answer**|

⚠ **Hash-based → resharding (Problem → Fix):**

- **Problem —** simple modulo means adding/removing a shard remaps nearly every record → massive data movement.
- **Fix —** **consistent hashing** — minimizes data movement when shards are added/removed. _(Own deep dive — cross-ref, not re-explained here.)_
- ▸ Net: **hash-based works great as long as you have a resharding plan.**

⚠ **Directory-based — why to avoid it in interviews:** valid for dynamic use cases, but it introduces a **SPOF** (directory down → whole system down even if every shard is healthy) and **latency on every request**. It invites follow-up questions that derail the conversation. Most systems start hash- or range-based and only add a directory for a specific requirement.

▹ **Range-based sweet spot — multi-tenant SaaS:** each client owns a range of IDs. Company A queries only A's range, Company B only B's → load naturally spreads. _(Directly relevant to TerrySage/LiftUP multi-tenancy.)_

---

## The Three Challenges

### 1. Hot Spots & Load Imbalance

- **Problem —** even with a good shard key, one shard takes far more traffic than the rest → it becomes the bottleneck, **negating the whole point of sharding.**
    - **The celebrity problem** — shard by `user_id`, and Taylor Swift's shard takes 1000x normal traffic (every profile view, like, message). **Hash distribution doesn't help** — the issue isn't the strategy, it's that **some keys are inherently more active.**
    - **Time-based hot spot** — shard by creation date → **all writes** hit the newest shard while old shards idle on reads.
- **Detect it —** monitor per-shard **query latency, CPU, request volume**. One shard consistently higher = hot spot.
- **Fix —**
    - **Isolate hot keys to dedicated shards** — move the celebrity account to its own shard. (This is where directory-based sharding earns its keep — though you wouldn't _start_ there.)
    - **Compound shard keys** — `hash(user_id + date)` instead of `user_id` alone → spreads one user's data across shards over time.
    - **Dynamic shard splitting** — some DBs split a shard automatically when it grows too large/hot. **MongoDB**'s balancer splits + migrates chunks automatically. **Vitess** supports online resharding but it's **operator-driven, not automatic.**

### 2. Cross-Shard Operations

- **Problem —** any query needing data from **more than one shard** gets expensive: query N shards, wait for all N, aggregate yourself.
    
    - Aligned query: "get user 12345's profile" → **one shard.** Fast.
    - Misaligned query: "top 10 most popular posts globally" → posts are scattered across all user shards → hit **all 64 shards**, wait for 64 responses, merge, return 10. **64x the network calls and latency.**
- **Fix —** you can't eliminate these, but you can minimize them. **First classify the query:**
    
    - **Scoped to an entity** (a user's feed, a user's orders) → **denormalize to co-locate** → fan-out **eliminated**.
    - **Global by nature** (top 10 worldwide, total users) → **no shard owns the answer** → denormalization can't help → **cache or precompute**.
    
    **The three tools:**
    
    - **Denormalize to co-locate** _(only helps scoped queries)_ — copy data **across shard boundaries** so a query never has to leave its shard.
        - _Feed example:_ shard by `user_id`; the people I follow live on **other shards**. Normalized → my feed query fans out to their shards. Denormalized → when someone I follow publishes, **write a copy of that post into my shard** → my feed query touches **one shard. Fan-out: zero.**
        - Duplicates data and complicates writes — often worth it.
    - **Cache the result** _(the fix for global queries)_ — first query is expensive, the next thousand hit the cache (see `01e_caching`). Perfect for leaderboards, trending content, aggregate stats — anything tolerating **eventual consistency**. Pair with **precompute via background job**.
    - **Accept the hit for rare queries** — an admin dashboard loaded a few times a day can afford to be slow.

⚠ **Two different meanings of "denormalize" — don't conflate them:**

||**Single-DB denormalization**|**Sharding denormalization** ⭐|
|---|---|---|
|Goal|**eliminate joins** (fold order details into the user row)|**eliminate fan-out** — put the data on the shard that will ask for it|
|Wins you|faster read _within_ one machine|query touches **1 shard instead of N**|
|Relevance to sharding|none — this is just normal schema tuning|**this is the sharding-specific reason**|

▸ **The trap (worth internalizing):** denormalizing makes each of the 64 shards _faster_, but for a **global** query **you still hit all 64.** Reducing per-shard time is **not** the same as reducing fan-out. That's exactly why the fix for global aggregates is **cache/precompute — not denormalization.**

- ⚠ **Interview signal:** if you hear yourself saying _"we'll query all shards and aggregate"_ for a **common** use case, **stop.** Interviewers expect you to **minimize** cross-shard queries, not accept them. Ask: can I **denormalize**? **cache**? **precompute with a background job**?

### 3. Maintaining Consistency

- **Problem —** on one DB, atomicity is a transaction (deduct inventory + create order → both or neither). **Sharding breaks this** — user on shard 1, transaction record on shard 2 = two independent DBs that don't know about each other.
- ⚠ **2PC (two-phase commit)** is the textbook answer: a coordinator asks all shards to _prepare_, waits for confirmation, then tells everyone to _commit_. **Guarantees consistency but is slow and fragile** — any shard or the coordinator failing mid-transaction can wedge the system. **Most production systems avoid it.**
- **Fix —**
    - **Design to avoid cross-shard transactions** ⭐ **— the best solution.** Shard by `user_id` and keep **all** of a user's data on their shard (balance, history, profile) → every transaction becomes a fast, reliable **single-shard** transaction.
    - **Sagas for genuine multi-shard operations** — break the operation into independent steps, each with a **compensating action**. Step 3 fails → run compensations for 2 and 1. Gives **eventual consistency without 2PC's fragility.**
        - _Money transfer across shards:_ deduct from A (shard 1) → add to B (shard 2) → if step 2 fails, **refund A** (compensating action).
    - **Accept eventual consistency** — a denormalized follower count showing different values across shards for a few seconds is fine; they converge.
- ▸ **TLDR:** most apps can be designed to **avoid cross-shard transactions entirely.** If you constantly need distributed transactions, **you picked the wrong shard key or the wrong shard boundaries.**

---

## Sharding in Modern Databases

▸ **CRUX** — **you won't implement sharding from scratch.** Modern distributed DBs handle it. Specify a partition key; they route + rebalance. **But the mechanics differ** — don't blanket-claim "consistent hashing."

|DB|Mechanism|
|---|---|
|**Cassandra**|partitioner (e.g. Murmur3) + **virtual nodes** → a form of **consistent hashing** mapping keys to token ranges|
|**DynamoDB**|**hashes the partition key** to route items to internal partitions; splits/merges as they grow. **Not** classic ring-based consistent hashing exposed to users|
|**MongoDB**|**range-based chunks** on the shard key (if hashed key → ranges over the _hash space_); a background **balancer** auto-splits and migrates chunks. **Not** classic consistent hashing|

▹ **SQL has matured too:**

- **Vitess** and **Citus** — open-source sharding layers in front of MySQL / PostgreSQL; handle routing, cross-shard ops, resharding.
- **AWS Aurora**, **Google Cloud Spanner** — distributed SQL with built-in sharding.

▸ **In interviews, this is enough:** _"We'll use DynamoDB with `user_id` as the partition key"_ or _"We'll shard using Vitess on `user_id` and plan for operator-driven online resharding."_ No internals unless asked.

---

## Interview Playbook

### When to bring it up

⚠ **The #1 sharding mistake: introducing it before proving it's necessary.** Slow down, **do the math**, confirm sharding is actually needed. A well-tuned single DB gets you surprisingly far.

▸ **Formula:** identify the bottleneck → explain why a single DB won't scale → propose sharding.

Trigger it during **capacity planning** when you hit one of these:

- **Storage** — "500M users × 5KB = 2.5TB. One Postgres can handle it, but at 10x growth we'll need to shard."
- **Write throughput** — "50K writes/sec at peak. A single DB will struggle with that write load."
- **Read throughput** — "Even with read replicas, 100M DAU × multiple queries each → we need to distribute reads across shards."

▹ **Use "Numbers to Know" for this** — that reference is what lets you say _"a single Postgres instance handles X TB / Y writes-per-sec before it struggles"_ with a concrete number instead of a vague gesture at "scale." Interviewers notice the difference between "eventually we'd need to shard" and "at 50K writes/sec we'd need to shard" — the second is the one that sounds like you've actually hit this limit before.

⚠ **Restating the discipline, because it's the #1 mistake:** don't start explaining _how_ you'd shard until you've done the math and shown _why_ a single DB can't take the load. **Slow down.** Prove the bottleneck first — sharding is the conclusion, not the opening move.

### What to say (4 steps — social media example)

1. **Propose a shard key from your access patterns**
    
    > _"Most queries here are user-centric — feed, posts, followers, likes are all scoped to a single user. So I'd shard by `user_id`."_
    
2. **Choose the distribution strategy**
    
    > _"Hash-based sharding with consistent hashing — hash the `user_id` to spread users evenly across shards."_
    
3. **Call out the trade-offs**
    
    > _"Global queries get expensive. 'Trending posts across all users' means querying every shard and aggregating. We'd cache trending content and precompute it with a background job rather than calculating per request."_
    
4. **Address growth / resharding**
    
    > _"Start with 64 shards for headroom. Consistent hashing lets us add shards later without resharding everything — only a fraction of the data moves."_
    

▹ The flow matters more than the facts: you're **walking through reasoning and trade-offs**, not listing terms.

---

## Quick Recall (pass 3+)

|Situation|Reach for|
|---|---|
|Partitioning vs sharding|one machine (logical split) vs **many machines** (standalone DBs)|
|Default strategy|**Hash-based** — interviewer assumes it|
|Good shard key|high cardinality · even distribution · **aligns with common queries**|
|Bad shard key|boolean (2 shards max) · `created_at` (all writes → newest shard)|
|Efficient range scans / multi-tenant|Range-based (each client owns an ID range)|
|Need to move one heavy user|Directory-based — but **SPOF + per-request lookup** → rarely the interview answer|
|Adding/removing shards|**Consistent hashing** (plain `% N` remaps almost everything)|
|Celebrity / hot key|isolate to dedicated shard · compound key `hash(user_id + date)` · dynamic splitting|
|"Query all shards and aggregate"|**red flag** → denormalize / cache / precompute|
|What's on one shard?|**all tables** (users+orders+posts), fewer rows each — **co-located by shard key**. Not "users on shard 1"|
|Denormalize — which kind?|**scoped** query → co-locate → kills fan-out · **global** query → denormalization won't help → **cache/precompute**|
|Cross-shard atomicity|**avoid it by design** (co-locate on one shard) · sagas + compensating actions · **not 2PC**|
|Constantly needing distributed txns|wrong shard key or wrong shard boundaries|
|DB mechanics|Cassandra = consistent hashing · DynamoDB = hashed partition key · MongoDB = range chunks + balancer|
|When NOT to shard|**before you've proven a single DB can't cope** — the #1 mistake|


QR => https://www.hellointerview.com/learn/system-design/core-concepts/sharding/quick-reference