# Distributed Cache — Problem Breakdown

> 📐 **Revision note (calc):** **1 TB of data · peak 100k req/s · <10 ms get/set.** 📐 **Throughput: 100,000 ÷ 20,000 req/s per host = 5 ⇒ ~8 with buffer. Storage: 32 GB instance, ~24 GB usable ⇒ 1,024 ÷ 24 ≈ 43 ⇒ ~50. Storage wins ⇒ 50 nodes.** 📐 ⊕ **My check: HI's final design gives each node 2 read replicas ⇒ 50 × 3 = 150 machines (1 TB stored 3× ≈ 3 TB; 150 × 32 GB ≈ 4.8 TB of instance RAM) — he never counts them.** 📐 **Hot read: 100k reads/s on one key ÷ 4 copies = 25k each. Hot write: 10,000 writes/s ÷ 10 sub-keys = 1,000 each.** 📐 ⊕ **Batching 10,000 writes/s into one op per 100 ms = 10 ops/s — a 1,000× cut, not HI's "order of magnitude".**

> Common Problems · **Evan King, published Jul 12, 2024** · ⭐⭐ **"medium"** · **Asked at: Google, Microsoft, Amazon +2** · ⭐⭐ **Pattern: `Scaling Reads` → `03d`** · Cross-refs: ⭐⭐⭐ **Rate Limiter (13) DD1/DD4 — shard by key, hot-key splitting; Redis Cluster slots** · ⭐⭐⭐ **Ad Click (25) DD1 — salt a hot key, owe a merge** · ⭐⭐ **Flash Sale (32) DD1 — sharded counter** · **`02a` Redis · `02e` Cassandra (consistent hashing) · `05g`.**
> 
> **Calibration:** ⭐⭐ **ONE pass plus a second look at §4.3 (LRU), vnodes and the hot-key dives (my call).** ⭐ **Order: §4.3 > DD3 > DD4/DD5 > DD1 > DD2 > DD6 > §4.2.** ⭐⭐ **This one doubles as LLD practice: a hash map plus a doubly linked list, with TTL and thread-safety questions.** ⚠ **HI: the question is asked very differently by different interviewers — some want LLD or even code, others architecture and scale. He takes the middle path.**
> 
> - ⭐⭐ **What actually scores:** **(a)** ⭐⭐⭐ **O(1) LRU: hash table + doubly linked list** · **(b)** ⭐⭐ **TTL: lazy check on read + a background janitor** · **(c)** ⭐⭐⭐ **replication mode, chosen with a reason (async, because a cache may lose data)** · **(d)** ⭐⭐⭐ **sizing from BOTH storage and throughput** · **(e)** ⭐⭐⭐ **consistent hashing vs modulo** · **(f)** ⭐⭐⭐ **hot READS and hot WRITES are different problems** · **(g)** ⭐ **pooling and batching for latency.**
> - ⭐ **Transferable primitives:**
>     - ⭐⭐⭐ **Combine two structures, each covering the other's weakness (map = lookup, list = order).**
>     - ⭐⭐⭐ **Consistent hashing: remap only one node's arc; virtual nodes make it even.**
>     - ⭐⭐⭐ **Pick the consistency mode from what a miss costs — a cache can lose data, so async replication fits.**
>     - ⭐⭐ **Split a hot key and you owe a merge: reads need synced copies, writes need a sum.**
>     - ⭐⭐ **Sample or expire lazily instead of scanning everything.**
>     - ⭐ **With no coordinator, the client library carries routing, batching and pooling.**
> - ⭐ **Re-run (cross-ref only):** **Redis and Redis Cluster slots (`02a`, Rate Limiter) · hot-key splitting (Rate Limiter DD4, Ad Click DD1) · sizing from ops/s (Rate Limiter DD1).** **Genuinely new:** ⭐⭐⭐ **the LRU data structure** · ⭐⭐⭐ **consistent hashing + vnodes** · ⭐⭐ **replication modes (sync, async, peer-to-peer)** · ⭐⭐ **TTL expiry** · ⭐⭐ **hot reads vs hot writes.**

---

## 0 · Understanding the problem

💬 **A distributed cache stores key-value pairs in memory across many machines. Unlike a one-node cache, it scales horizontally; the cluster partitions and replicates the data, so it stays available when a node fails.**

⭐⭐ **HI's path: balance low-level design with a high-level design that scales. Entities and API are trivial — skip or rush them.**

---

## 1 · Requirements

### 1.1 Functional

1. ⭐⭐ **Users can set, get and delete key-value pairs.**
2. ⭐⭐ **Users can configure the expiration time for key-value pairs.**
3. ⭐⭐⭐ **Data is evicted according to a Least Recently Used (LRU) policy.**

⚠ **Below the line:** **Configuring the cache size.** ▹ **Ask which eviction policy they want: LFU, FIFO or custom are alternatives.**

### 1.2 Non-functional

📐 ⭐ **Ask scale first. HI's interviewer answer: 1 TB of data, peak 100k req/s.**

1. ⭐⭐⭐ **Highly available. Eventual consistency is acceptable.**
2. ⭐⭐ **Low latency: < 10 ms for get and set.**
3. ⭐⭐ **Scalable to 1 TB of data and 100k req/s.**

⚠ **Below the line:** **Durability · Strong consistency · Complex querying · Transactions.** ▹ **HI: these are strong assumptions — confirm them; some interviewers care about durability.**

> ⚠ **Two things sit loose.** ⊕ **"Configure the cache size" is dropped, yet LRU needs a capacity (§4.3). And 1 TB of data is not 1 TB of memory to buy — a cache holds the hot subset, so ask the target hit ratio (DD2).**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 1.3 ⭐⭐⭐ The design driver — an in-memory store, fast on every operation, bigger than one machine, still up when a node dies, with lopsided traffic

|Constraint|What it breaks|Fixed by|
|---|---|---|
|⭐⭐⭐ **O(1) get/set and an eviction order**|**a bare hash table (no order) or a bare list (slow lookup)**|**hash table + doubly linked list (§4.3)**|
|⭐⭐ **stale entries, full memory**|**expired keys that nobody reads**|**lazy check + janitor (§4.2)**|
|⭐⭐⭐ **a node dies**|**the cache for its keys**|**async replication + failover (DD1)**|
|⭐⭐⭐ **1 TB, 100k req/s**|**one machine**|**shard by consistent hashing, ~50 nodes (DD2, DD3)**|
|⭐⭐⭐ **one key is hot**|**its shard**|**copies for reads; sub-keys or batching for writes (DD4, DD5)**|
|⭐⭐ **<10 ms over a network**|**hops and handshakes**|**pooling, client-side routing, batching (DD6)**|

### 1.4 Planning the approach

⭐ **MVP first, one FR at a time, then deep dives on the NFRs. Lead toward them, but expect the interviewer to jump in.**

---

## 2 · Core Entities

⭐ **Keys and their values — the only data we hold, in memory.**

> ⚠ ⊕ **Each stored entry also carries an expiry timestamp and, in §4.3, a list node (two pointers). That per-entry overhead is why 1 TB of data needs more than 1 TB of RAM when values are small.**
> 
> ■ **— end of insert · HI write-up resumes below —**

---

## 3 · API

```
POST   /:key   { "value": "..." }
GET    /:key   -> { value: "..." }
DELETE /:key
```

- ⭐ **Three operations from the FRs; HI breezes through them.**
- ⚠ **Gaps:** ⊕ **① FR2 needs a `ttl` in the set body (the pseudocode takes one; the API doesn't) · ② `PUT` is the idempotent verb for a set · ③ `GET` on a miss returns 404 · ④ real caches speak a binary protocol (Redis: RESP over TCP), not REST · ⑤ DD5 needs an atomic increment (`INCRBY`), which set/get/delete can't express.**

---

## 4 · High-Level Design

⭐ **An MVP that need not scale; each FR in turn.**

### 4.1) Users can set, get and delete key-value pairs

⭐ **A cache is a hash table (Python `dict`, Java `HashMap`, Go `map`): O(1) lookup and insert, collisions and resizing handled for you. Host it on one server: parse the request, call `get`/`set`/`delete` on the Cache instance, return the result.**

```
class Cache:  data = {}
    get(key):        return data[key]
    set(key, value): data[key] = value
    delete(key):     delete data[key]
```

▹ **HI: pseudocode needn't be syntactically perfect, and corner cases (key not found) don't matter — but confirm with the interviewer.** ⭐ **Not production-ready: it falls over on real traffic or too much data. It meets the core FR.**

> ⚠ **What HI leaves loose.**
> 
> - ⚠⚠ **A plain map is not thread-safe.** ⊕ **Concurrent `get`/`set` need a lock or sharded locks; Redis sidesteps the problem by running commands on one thread. HI mentions thread safety only in a closing note.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 4.2) Users can configure the expiration time

⭐ **Store `(value, expiry_timestamp)`. `set(key, value, ttl)` computes `expiry = now + ttl`; `get` checks the expiry first and, if expired, deletes the key and returns null.**

⭐⭐ **Problem: expired keys are only removed when read, so unread ones fill memory. Fix: a background "janitor" that every n minutes scans for expired entries and deletes them.** ⭐ **Trade-off: CPU spent checking vs memory freed promptly; run on a schedule or under memory pressure.**

> ⚠ **What HI leaves loose.**
> 
> - ⚠⚠ **The janitor scans EVERY key: at ~24 GB per node that is hundreds of millions of entries, and the scan holds the lock.** ⊕ **Redis samples a random batch of keys that have a TTL and repeats while many are expired (textbook), plus the lazy check on read.**
> - ⚠ **With replicas (DD1), expiry is clock-dependent: a replica with a skewed clock disagrees on whether a key is dead. Redis lets the primary expire and propagate a delete (textbook).**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 4.3) Data is evicted according to LRU

⭐ **When the cache is full, evict the entry unused for the longest time.** ▹ **Confirm LRU with the interviewer.**

⭐⭐⭐ **The challenge: find items fast AND know access order. A hash table alone finds fast but has no order; a list alone has order but a slow lookup. Combine them: a hash table (key → Node) for O(1) lookup, and a doubly linked list for access order — head is most recent, tail is least recent, with dummy head and tail nodes.**

- ⭐⭐ **A `Node` holds key, value and expiry.**
- ⭐⭐ **Add: create the Node, put it in the table, insert it at the front. Over capacity ⇒ remove the node before the dummy tail from both the list and the table. Example: capacity 2, add A, B, C ⇒ `[A]`, `[B→A]`, then evict A ⇒ `[C→B]`.**
- ⭐⭐ **Access: look the Node up (O(1)), unlink it from its place (O(1)), move it to the front (O(1)). Hot items stay near the head; cold ones drift to the tail.**
- ⭐ **`get` also handles TTL: expired ⇒ delete from table and list, return null. `set` on an existing key updates value and expiry and moves it to the front.**
- ⭐ **`cleanup()` (the janitor) walks from the tail and deletes expired nodes.**
- ✅ **All operations — get, set, even eviction — stay O(1).**

⚠ **HI: the code is simplified; production needs thread safety, error handling, monitoring and tuning.**

> ⚠⚠ **What HI leaves loose — the biggest cluster in the HLD.**
> 
> - ⚠⚠ **In an LRU, every read is a WRITE (move to front), so every `get` needs an exclusive lock on the list — the list becomes the bottleneck at 20k req/s per node.** ⊕ **Redis uses a single thread and an APPROXIMATE LRU (sample a few keys, evict the oldest); Memcached uses segmented LRU lists (textbook).** ▹ **A fair follow-up question.**
> - ⚠ **`size > capacity` counts items, but the NFR is bytes, and values vary in size: one big value can force several evictions.**
> - ⚠⚠ **LRU is per node; with read replicas (DD1) recency is not shared.** ⊕ **A key read only on replicas looks cold on the primary, gets evicted there, and the eviction is replicated — the hot key disappears.**
> - ⚠ **`cleanup()` walks from the LRU end, but expiry order is not LRU order, so the scan is still O(n).**
> 
> ■ **— end of insert · HI write-up resumes below —**

⭐ **HI: until here this was more low-level than system design. The deep dives turn one in-memory cache into a distributed system that meets the NFRs.**

---

## 5 · Deep Dives

⭐ **HI's usual six questions; a strong candidate raises them proactively.**

### 1) How do we ensure our cache is highly available and fault tolerant?

⭐⭐ **One node dies ⇒ its data is gone. The fix is replication, which raises four questions: how many copies, on which nodes, how to keep them in sync, and what happens when nodes fail or can't talk.** ⭐ **These patterns apply far beyond caches (databases, message queues).**

⚠ **HI: all three can be right depending on the case — options, not a strict ladder.**

#### Option A — synchronous replication

- ⭐ **A few replicas per shard; a write goes to ALL replicas and returns only when all acknowledge. Preferred when a cache needs strong consistency — ours doesn't.**
- ⚠⚠ **Writes wait for the slowest replica ⇒ latency; one replica down ⇒ writes stop ⇒ availability suffers; each extra replica makes both worse, so it scales badly. HI: not a fit — we put availability and performance over consistency.**

#### ⭐⭐⭐ Option B — asynchronous replication (primary + replicas)

- ⭐⭐ **Write to one primary, acknowledge, then propagate to replicas in the background. Fits the eventual-consistency NFR.**
- ✅ **Faster writes (no waiting), higher availability (writes proceed with replicas down), replicas don't add write latency, and some staleness is fine for a cache.**
- ⚠ **Challenges (HI): replicas can be briefly stale; one primary orders all writes, so no conflict resolution; recovery must track updates a replica missed; a dead primary needs a replica promoted — complexity and possible downtime.**

#### Option C — peer-to-peer (gossip)

- ⭐ **Every node is equal and accepts reads and writes; changes spread by gossip — nodes periodically exchange state with random peers. No single point of failure; a write is applied at once and propagated later.**
- ⚠ **Challenges (HI): more complex (many peer connections, conflict resolution); nodes may briefly disagree on a key; concurrent updates at different nodes need a resolution strategy.**

⭐⭐ **Real systems: Redis replicates asynchronously by default; its `WAIT` command lets a client wait for replica acks ("semi-synchronous"). Others let you configure the mode.** ⭐⭐ **HI: the interviewer cares more that you know the options and trade-offs than which you pick. He'd discuss async (balance of availability and simplicity) and peer-to-peer (maximum scalability) — "no single right answer".**

> ⚠⚠ **What HI leaves loose.**
> 
> - ⭐⭐⭐ ⊕ **The strongest argument for async is missing: a cache may LOSE writes. A promoted replica that lacks the last few writes just causes misses, refilled from the source database. Durability is out of scope precisely because of this.**
> - ⚠⚠ **None of his four questions gets an answer.** ⊕ **How many: 1 primary + 2 replicas (his final diagram). Where: different availability zones. Failure detection and promotion: Redis Sentinel, or Redis Cluster's own gossip with a majority vote (textbook).**
> - ⚠ **Sync is a strawman "write to ALL".** ⊕ **The middle ground is a quorum (W of N acks), which Dynamo-style stores use (textbook).**
> - ⚠ **Peer-to-peer conflates two things: "every node holds everything" and "a shard's replicas have no leader" (Dynamo, Cassandra).** ⊕ **With sharding (DD2) you mean the second. Conflicts are usually last-write-wins, which needs reasonably synced clocks.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 2) How do we ensure our cache is scalable?

⭐⭐ **1 TB and 100k req/s don't fit one node: shard the key-value pairs across nodes, so each holds a manageable portion and we scale by adding machines.** 💬 **Partitioning (within one system) vs sharding (across machines): technically different, used interchangeably.**

- 📐 ⭐⭐ **Throughput: benchmark a host at ~20,000 req/s ⇒ 100,000 ÷ 20,000 = 5 nodes; with spike and failure buffer, ~8.**
- 📐 ⭐⭐ **Storage: a 32 GB instance reliably uses ~24 GB for data ⇒ 1,024 GB ÷ 24 GB ≈ 43; with growth buffer, ~50.**
- ⭐⭐⭐ **Storage needs more nodes ⇒ provision 50; that leaves plenty of throughput headroom.** ▹ **HI: rough numbers; real ones depend on hardware, value sizes, read/write ratio, replication, growth — benchmark.**

> ⚠ **What HI leaves loose.**
> 
> - ⚠⚠ **50 counts primaries only.** ⊕ **With 2 read replicas each (the final design), it's ~150 machines: ~3 TB of data across ~4.8 TB of instance RAM.**
> - ⚠ **1 TB of data is not 1 TB of RAM: per-entry overhead (hash entry, list node, expiry) can rival small values.** ⊕ **And a cache needn't hold the whole dataset — size for the hit ratio you want.** ▹ **Judgment call.**
> - ⚠ **20k req/s per node is conservative for in-memory ops (Rate Limiter used ~100–200k ops/s for Redis); 50 nodes then carry ~1M req/s, 10× the need.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 3) How can we ensure an even distribution of keys across our nodes?

⭐⭐⭐ **Consistent hashing.**

- ⭐⭐ **Naive: `hash(key) % 4` picks a node. Fine for a fixed count — but going to `% 5` or `% 3` remaps most keys.**
- ⭐⭐⭐ **Instead place both nodes and keys on a circle: hash the key (e.g. MurmurHash) to a position, walk clockwise to the first node, store it there. Example: `hash(key) = 28` ⇒ find 28 on the ring ⇒ walk clockwise ⇒ that node stores it.**
- ⭐⭐⭐ **Why: adding or removing a node remaps only the keys in that node's range, not everything.** ▸ **More in the Cassandra deep dive (`02e`).**

> ⚠⚠ **What HI leaves loose — the title says "even", and plain consistent hashing isn't.**
> 
> - ⚠⚠ **With one point per node, arc sizes vary a lot, so some nodes own far more keys; and a dead node's whole arc lands on ONE neighbour.** ⊕ **Virtual nodes: each physical node takes many points (100–256) on the ring — load evens out and a failure spreads over many survivors (textbook). HI never mentions them.**
> - ⚠ **Redis Cluster doesn't use a ring at all: 16,384 hash slots assigned to nodes (Rate Limiter DD1).**
> - ⚠ **Who holds the ring? In DD6 the client does.** ⊕ **Clients must learn about joins and leaves (gossip, ZooKeeper, a config service); a stale ring sends requests to the wrong node.**
> - ⚠ **Keys remapped to a new node start as MISSES.** ⊕ **That, or a hot key expiring, can send a stampede to the database: coalesce concurrent misses (one fetch per key) and jitter TTLs (textbook).**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 4) What happens if you have a hot key that is being read from a lot?

⭐ **The classic follow-up. HI: usually a property of the client, not the cache — but be ready.** ⭐⭐ **Hot keys get far more traffic than others (a viral tweet, a flash-sale product's count) and overload the shard that holds them. Two kinds: hot READS (millions viewing one item) and hot WRITES (a live vote counter).**

> ⭐⭐ **Pattern: Scaling Reads (`03d`)** — **when millions request the same item at once, normal caching assumptions break.**
> 
> ■ **— end of insert · HI write-up resumes below —**

#### ⚠⚠ Bad — scale up every node

**What it is:**

- ⭐ **Upgrade the hardware of ALL nodes in the cluster — more CPU, memory and network — so every node can absorb a hot key.**
- **Simple: no new logic, every node treated the same, whatever its real load.**

**Challenges:**

- ⚠⚠ **Expensive and wasteful: you upgrade every node when only the few holding hot keys are under pressure.**
- ⚠ **Doesn't fix the cause — a key hot enough still overwhelms even a bigger node.**
- ⚠ **Cost grows linearly with node count, so it doesn't last on a large cluster.**

**Why climb:** ⭐ **put the extra capacity only where the hot keys are.**

#### Good — a dedicated hot-key cache

**What it is:**

- ⭐⭐ **A separate cache tier just for hot keys. Monitoring flags a key as hot; it is PROMOTED to this tier, which runs more powerful hardware tuned for high throughput.**
- ⭐ **Clients read hot keys from the hot tier and everything else from the main nodes. The tier can be spread geographically, closer to users.**

**Challenges:**

- ⚠⚠ **Keeping the hot tier consistent with the main cache adds complexity.**
- ⚠ **Needs good monitoring to spot hot keys, plus promote/demote logic — and tuning of WHEN to promote or demote.**
- ⚠ **A whole extra caching system to run and operate.**

**Why climb:** ⭐ **reuse something we already have instead of building a new tier.**

#### Good — read replicas

**What it is:**

- ⭐⭐ **Reuse the replication from DD1: each node has copies on other machines, and read requests are spread across them.**

**Challenges:**

- ⚠⚠ **It copies WHOLE nodes, so storage and network costs are high even if only one key is hot.**
- ⚠ **Replication lag and primary–replica consistency must be managed.**
- ⚠ **More operational work: more copies to monitor, failover to handle, sync to keep correct.**
- ⚠ **Overkill when only a small set of keys is hot.**

**Why climb:** ⭐ **copy only the hot keys, not whole nodes.**

#### ⭐⭐⭐ Great — copies of just the hot keys

**What it is:**

- ⭐⭐⭐ **Selective replication: only keys with heavy read traffic get extra copies, so it targets the hotspot directly.**
- ⭐⭐ **How it works: ① monitor access patterns to detect hot keys ② when `user:123` turns hot, store copies under suffixes — `user:123#1`, `user:123#2`, `user:123#3` ③ consistent hashing places each suffix on a different node ④ a READ picks a random suffix, spreading the load ⑤ a WRITE must update all copies.**
- 📐 **Example: `product:iphone` in a flash sale at 100,000 reads/s and 1 write/s. One copy ⇒ one node serves all 100k. Four copies ⇒ ~25,000 reads/s each, and each write updates 4 copies.**

**Challenges:**

- ⚠⚠ **Keeping copies in sync on writes. Atomic updates to all copies would be complex — but our cache is eventually consistent, so brief divergence is acceptable as long as copies converge.**
- ⚠ **Overhead of detecting hot keys and managing the copies' lifecycle: when to create them, when to remove them once the key cools.**
- ⚠⚠ **Read-heavy keys only. A key hot for reads AND writes gets worse: every write now fans out to all copies.**

⭐⭐ **HI's takeaway: show that hot keys are a real operational concern, and have concrete mitigations.**

> ⚠ **What HI leaves loose.**
> 
> - ⚠⚠ **The usual first answer is missing: a short-TTL local cache in each app server ("near cache") takes a hot read off the network entirely (textbook).**
> - ⚠ **For suffix copies, every CLIENT must know which keys are hot and how many copies exist — a detector plus a push to clients. Two suffixes can also hash to the same node.**
> - ⚠ **A flash-sale inventory count (HI's example) is not cache data — it's the source of truth (Flash Sale DD1).**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 5) What happens if you have a hot key that is being written to a lot?

⭐ **Like hot reads, but harder, with different trade-offs.**

#### Option A — write batching

- ⭐⭐ **The client buffers writes for a short window (50–100 ms) and sends one consolidated operation. Best for counters and metrics, where the final value matters more than each update.** 📐 **A viral video at 10,000 views/s: collect for 100 ms, then one operation adds 1,000 — HI says an order of magnitude less write pressure.**
- ⚠ **Challenges (HI): longer windows mean less load but later visibility; a crash inside the window loses buffered writes unless they can be replayed; reads always miss the pending buffer. Not for data that must be visible immediately.**

#### Option B — key sharding

- ⭐⭐⭐ **Split the hot key into sub-keys on different nodes: `views:video123:1` … `:10`. A write picks one at random; a read sums all ten. HI: the technique used in many of his breakdowns.** 📐 **10,000 writes/s over 10 shards ≈ 1,000/s each.** ⭐ **Works for any operation that decomposes and recombines, not only counters.**
- ⚠ **Challenges (HI): reads now aggregate several shards (more latency and work — writes traded for reads); consistency during failures or rebalancing; choosing the shard count (too few doesn't spread, too many makes reads heavy); unusable for operations needing strict order or atomicity across all updates.**

> ⚠⚠ **What HI leaves loose.**
> 
> - ⚠⚠ **Both options need an ATOMIC increment, and the API has only set/get/delete.** ⊕ **"Set the value 1,000 higher" as GET then SET loses concurrent updates — the Rate Limiter lesson. Add `INCRBY`.**
> - ⚠ **📐 HI's own numbers: one op per 100 ms is 10 ops/s against 10,000/s — a 1,000× cut, not "an order of magnitude".**
> - ⚠ **Sub-keys age independently: LRU can evict one shard of a counter, and the sum silently undercounts. Give all sub-keys the same TTL.**
> - ✅ **Same shape as Ad Click DD1 (salt, then merge) and Rate Limiter DD4: split a hot key and you owe a merge.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 6) How do we ensure our cache is performant?

⭐⭐ **One node was O(1) in memory. Spread over dozens of nodes, performance is about finding the right node fast, bundling requests, and avoiding network chatter: a microsecond lookup can become slow across several network hops and connection setups.**

- ⭐⭐ **Request batching (from DD5) cuts round trips.**
- ⭐⭐ **Consistent hashing in the client means no central routing service to ask — one round trip saved.**
- ⭐⭐⭐ **Connection pooling: keep persistent connections instead of a new one per request; removes handshakes and cuts tail latency (p95, p99).** ▸ **Rate Limiter DD3.**

> ⚠ **What HI leaves loose.**
> 
> - ⚠ **DD5's batching merges updates to ONE key; cutting round trips means sending many DIFFERENT keys at once.** ⊕ **Pipelining or multi-get per node (textbook).**
> - ⚠ **"No routing hop" holds only while the client's ring is current (DD3).**
> 
> ■ **— end of insert · HI write-up resumes below —**

---

## 6 · Final Design

⚠ **Layout is mine; components are HI's.** ⭐ **On each node: a hash table for the key-value pairs and a linked list for LRU. HI's choices: async replication (HA and hot reads) · consistent hashing (sharding and routing) · random suffixes (hot-key load) · write batching + connection pooling (latency).**

```
Client library  ⭐⭐ batch writes · connection pool · consistent hashing picks the node
                ⭐⭐ random suffix spreads a hot key · ⊕ atomic INCRBY · ⊕ near cache for hot reads
     │
     ├──► Node 1 (primary: hash table + LRU list) ──async──► Node 1 read replica ×2
     ├──► Node 2 (primary)                        ──async──► Node 2 read replica ×2
     └──► … Node N (≈50 primaries)                ──async──► …                       ⊕ ≈150 machines

⊕ missing from HI's picture: ring membership (gossip / config service) · failure detector + promotion
  (Sentinel-style) · hot-key detector feeding clients · virtual nodes on the ring
```

---

## 7 · Expected at Each Level

|Level|The bar for Distributed Cache|
|---|---|
|**Mid-level**|**More time on the high-level (really low-level) design, less on scale. Reason to the right data structures for the latency target, and problem-solve to basic answers on scalability and availability — e.g. see the need for replication and the ways to do it.**|
|**Senior**|**The low-level part goes quickly; most time is on scale. Weigh trade-offs and decide from the requirements. Know basic hot-read and hot-write strategies, and talk about consistent hashing as second nature.**|
|**Staff**|**HI usually doesn't ask staff engineers this — the concepts should come naturally, so it evaluates them poorly.**|

> ⭐ **For an SDE2 loop, the Mid → Senior bar is the one that matters: fast LRU, then replication, sharding and hot keys with trade-offs.**
> 
> ■ **— end of insert · HI write-up resumes below —**

---

## Quick Recall (pass 3+)

|Use / Question|Distributed Cache answer|
|---|---|
|Calibration|**Evan King · Jul 2024 · ⭐⭐ "medium" · Asked at Google, Microsoft, Amazon +2 · ⭐⭐ pattern `03d` Scaling Reads.** ⭐⭐ **ONE pass + a second look at LRU, vnodes, hot keys. Order §4.3 > DD3 > DD4/DD5 > DD1 > DD2 > DD6 > §4.2.** ⚠ **Asked very differently: some want LLD or code, others scale**|
|⭐⭐⭐ Design driver|⭐⭐⭐ **In memory, fast on every op, bigger than a machine, up when a node dies, lopsided traffic.** **O(1) + order ⇒ map + doubly linked list · stale/full ⇒ lazy expiry + janitor · node dies ⇒ async replication · 1 TB / 100k ⇒ consistent hashing, ~50 nodes · hot key ⇒ copies (reads), sub-keys or batching (writes) · <10 ms ⇒ pooling, client routing, batching**|
|📐 Numbers|**1 TB · 100k req/s · <10 ms.** **100k ÷ 20k = 5 ⇒ ~8 nodes; 1,024 GB ÷ 24 GB ≈ 43 ⇒ ~50 nodes; storage wins.** ⊕ **×3 with replicas ≈ 150 machines.** **Hot read 100k ÷ 4 copies = 25k each · hot write 10k ÷ 10 sub-keys = 1k each · batch 100 ms ⇒ +1,000 per op (⊕ a 1,000× cut)**|
|FRs / NFRs|**set/get/delete · configurable expiry · LRU eviction.** Below: configuring cache size. **NFRs: ⭐⭐⭐ highly available, eventual consistency OK · ⭐⭐ <10 ms · ⭐⭐ 1 TB and 100k req/s.** Below: durability, strong consistency, complex queries, transactions. ▹ **Confirm these; some interviewers want durability**|
|Entities + API|**Keys and values.** `POST /:key {value}` · `GET /:key` · `DELETE /:key`. ⚠ **No `ttl` in the set body; `PUT` is the idempotent verb; real caches use a binary protocol (RESP); DD5 needs `INCRBY`**|
|⭐⭐ §4.1 — hash table|**A cache is a hash table: O(1) get/set/delete on one server; pseudocode, corner cases skipped (confirm with the interviewer).** ⚠⚠ **Not thread-safe ⇒ locks, or Redis-style single thread**|
|⭐⭐ §4.2 — TTL|**Store (value, expiry); `get` checks and deletes expired keys (lazy); a janitor periodically deletes the rest — CPU vs memory.** ⚠⚠ **A full scan of ~24 GB holds the lock ⇒ ⊕ sample keys with a TTL (Redis). ⚠ Replica clocks ⇒ primary expires and propagates the delete**|
|⭐⭐⭐ §4.3 — LRU|⭐⭐⭐ **Hash table (key → Node) + doubly linked list (head = most recent, tail = least), dummy head/tail. Add ⇒ front; over capacity ⇒ evict `tail.prev` from both. Access ⇒ unlink, move to front. A, B, C at capacity 2 ⇒ `[C→B]`. Everything O(1)**|
|⚠⚠ §4.3 — loose ends|⚠⚠ **Every read is a write (move to front) ⇒ one lock on the list ⇒ ⊕ approximate LRU by sampling (Redis), segmented LRU (Memcached).** ⚠ **Capacity in items, NFR in bytes.** ⚠⚠ **Recency isn't shared with replicas: a key read only on replicas is evicted on the primary, and the delete replicates**|
|⭐⭐⭐ DD1 — replication|**Four questions: how many copies, where, how synced, what on failure.** ⚠ **Sync: write to all, wait for all ⇒ latency, availability drop, worse per replica; for strong consistency only.** ⭐⭐⭐ **Async: primary acks, replicas catch up ⇒ fast, available, no conflicts; ⚠ stale replicas, catch-up after downtime, promotion on primary failure.** ⭐ **Peer-to-peer gossip: any node writes, no SPOF; ⚠ complex, conflicts, divergence.** **Redis: async + `WAIT`. HI: show options; async or P2P; "no single right answer"**|
|⚠⚠ DD1 — loose ends|⭐⭐⭐ ⊕ **A cache may lose writes — the real reason async is right: a lost write is a miss.** ⚠⚠ **His four questions go unanswered ⇒ ⊕ 1 primary + 2 replicas, across AZs; Sentinel or Cluster gossip + majority to promote.** ⚠ **Sync is a strawman ⇒ quorum W of N.** ⚠ **P2P here means leaderless per-shard replicas; last-write-wins needs clocks**|
|⭐⭐⭐ DD2 — scale|**Shard 1 TB across nodes (partitioning ≈ sharding). 100k ÷ 20k = 5 ⇒ ~8; 1,024 ÷ 24 ≈ 43 ⇒ ~50; provision for storage, throughput headroom follows. Benchmark — numbers are rough.** ⚠⚠ **Primaries only ⇒ ~150 with replicas. ⚠ Per-entry overhead; a cache sizes for a hit ratio, not the whole dataset. ⚠ 20k/node is conservative**|
|⭐⭐⭐ DD3 — consistent hashing|**`hash % N` remaps most keys when N changes. Ring: hash the key (MurmurHash), walk clockwise to the first node. Adding/removing a node moves only its range.** ⚠⚠ **"Even" needs virtual nodes (100–256 points per node); otherwise uneven arcs and one neighbour absorbs a dead node.** ⚠ **Redis Cluster uses 16,384 slots. Clients need ring membership. Remapped keys start cold ⇒ stampede ⇒ coalesce misses, jitter TTLs**|
|⭐⭐⭐ DD4 — hot reads|**Hot reads ≠ hot writes; HI: often a client property.** **Scale up all nodes (wasteful) · dedicated hot-key tier (detection, promotion, consistency) · read replicas (whole-node copies, overkill) · ⭐⭐⭐ copies of just the hot key: `user:123#1..3` on different nodes, read a random one, write all; 100k reads/s ⇒ 25k per copy with 4. Read-heavy keys only.** ⚠⚠ **Missing: a near cache in app servers. ⚠ Clients must know which keys are hot**|
|⭐⭐⭐ DD5 — hot writes|**Batching: buffer 50–100 ms, send one op (10k views/s ⇒ +1,000 per 100 ms); ⚠ visibility delay, lost buffer on crash, reads miss pending writes; for counters and metrics.** **Key sharding: `views:video123:1..10`, write a random one, read sums all (10k ⇒ 1k per shard); ⚠ heavier reads, rebalancing, shard count, no strict order or atomicity.** ⚠⚠ **Both need atomic `INCRBY`; the API lacks it. ⚠ 1,000× not 10×. ⚠ Sub-keys evicted independently ⇒ undercount. ▸ Ad Click DD1, Rate Limiter DD4**|
|⭐⭐ DD6 — performance|**Across many nodes, latency is hops and handshakes. Batching cuts round trips; client-side consistent hashing removes a routing hop; ⭐⭐⭐ connection pooling removes handshakes and cuts p95/p99.** ⚠ **Batching one key ≠ pipelining many keys (multi-get). The routing win needs a current ring**|
|⭐⭐⭐ The meta-lesson|⭐⭐⭐ **Four ideas outlive this problem: (1) combine structures so each covers the other's weakness (map + list); (2) consistent hashing moves only one arc — vnodes make it even; (3) choose consistency from what a miss costs: a cache can lose data, so async; (4) split a hot key and you owe a merge (synced copies for reads, a sum for writes)**|
|Levels (one line)|**Mid:** more time on the data structures; basic scale and availability (replication options) · **Senior:** LLD quick, most time on scale, trade-offs, hot reads/writes, consistent hashing as second nature · **Staff:** usually not asked|

---

> 🔗 **HI source:** https://www.hellointerview.com/learn/system-design/problem-breakdowns/distributed-cache