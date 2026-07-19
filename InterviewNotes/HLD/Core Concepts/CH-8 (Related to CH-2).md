# Consistent Hashing — Deep Dive

> Hello Interview · Core Concepts (deep dive) · File `01g`. Referenced from `01f_sharding` (hash-based resharding). **⚠ Calibration — read this first:** for **your targets (full-stack / product SDE2)**, this is mostly a **name-drop topic**. Modern DBs (DynamoDB, Cassandra) do it for you — "they use consistent hashing under the hood to handle scaling" is usually the whole answer. **Go deep only for infra-flavored prompts:** _design a distributed cache · distributed database · distributed message broker._ Depth below exceeds what a product-role interview will probe. **Know the CRUX lines; treat the rest as ▹.**

---

## The Problem — Simple Modulo Hashing

▸ **CRUX** — you've decided to shard (`01f`). The obvious routing rule is **modulo hashing**:

```
database_id = hash(event_id) % number_of_databases
```

- 3 DBs: `hash(1234) % 3 = 1` → DB1 · `hash(5678) % 3 = 0` → DB0. **Works fine — until the node count changes.**

⚠ **Two failures, same root cause (Problem → Fix):**

- **Problem 1 — adding a node.** Go 3 → 4 DBs, so `% 3` becomes `% 4`. This **doesn't just affect data destined for the new node — it remaps almost every key.** Event 1234 was on DB1; now `hash(1234) % 4 = 0` → must move to DB0.
    - Result: **massive redistribution across all instances**, huge load spikes, users seeing slow responses or unavailable data.
- **Problem 2 — removing a node.** A DB dies (hardware, bug) → `% 3` becomes `% 2` → **exactly the same mass-redistribution problem.**
- **Fix —** **consistent hashing.**

▸ **The one-line framing:** the shard count is baked into the routing formula, so **changing the count changes the answer for every key.** Consistent hashing removes the count from the formula.

---

## The Solution — The Hash Ring

▸ **CRUX** — arrange **both the data and the nodes in a circular space** (the "hash ring"). To find a key's node: **hash the key onto the ring, then walk clockwise until you hit a node.** That's it.

**How it's built:**

- Create a ring with a fixed number of points. Toy example: 100 points; place 4 DBs at **0, 25, 50, 75**.
- Hash the event ID → land somewhere on the ring → **move clockwise** → first node you meet owns the key.
- ▹ Real rings use a hash space of **0 to 2³² − 1**, not 0–100. Same concept.

▸ **Why this fixes it — only the neighborhood moves:**

- **Adding DB5 at position 90** → only keys hashing to **75–90** move (they used to walk clockwise to DB1 at 0). **Everything else stays exactly where it is.** ≈15% of keys instead of nearly all of them.
- **Removing DB2 (at 25)** → only DB2's keys move; they now walk clockwise to **DB3 (at 50)**. **Everything else stays put.**

---

## Virtual Nodes

- **Problem —** when DB2 fails, **all** of its keys land on its single clockwise neighbor DB3 → **DB3 now carries 2x the load** of DB1 and DB4. The load moved, but it moved _unevenly_.
- **Fix — virtual nodes.** Place each DB at **many points on the ring**, not one, by hashing **variations of its name**:
    - Instead of hashing `"DB1"` → position 0, hash `"DB1-vn1"`, `"DB1-vn2"`, `"DB1-vn3"` → positions 20, 35, 65…
    - Do this for every DB → the virtual nodes are **naturally intermixed** around the ring.
- ▸ **Result on failure:** DB2's keys no longer dump on one neighbor. `DB2-vn1`'s keys → DB1 · `DB2-vn2`'s → DB3 · `DB2-vn3`'s → DB4 → **the failed node's load spreads evenly across all survivors.** More virtual nodes = more even distribution.
- ▹ **Also helps when _adding_ a node:** without vnodes, a new node only relieves its **single clockwise neighbor**. With vnodes, its positions are scattered around the ring → it **absorbs a small chunk from many existing nodes** → balanced cluster from the start.

---

## Hot Spots — What Consistent Hashing Does _Not_ Solve

⚠ **The critical distinction.** Consistent hashing distributes **keys** evenly — **not traffic.** A Taylor Swift concert generating 100x the reads of any other event still hammers one node, vnodes or not.

- **Fix —**
    - **Read replicas** — replicate popular keys across multiple nodes, load-balance reads among them. **Most common approach.**
    - **Key-space salting** — append a random suffix to hot keys (`taylor-swift-{0..9}`) so they hash to **different nodes**; reads scatter, then aggregate.
    - **Adaptive rebalancing** — monitor traffic live and move key ranges off overloaded nodes. Operationally complex; **DynamoDB does it automatically.**

▸ **The line to say in an interview:**

> **"Virtual nodes prevent _structural_ imbalance (uneven key distribution). Replication and key salting prevent _workload_ imbalance (uneven traffic)."**

▹ Same celebrity problem as `01f` hot spots and `01e` hot keys — three files, one underlying phenomenon: **some keys are inherently more active, and no distribution scheme fixes that.**

---

## Data Movement in Practice

▸ **CRUX** — consistent hashing tells you **where data should live**; it does **not** teleport terabytes when a node dies. In practice, distributed DBs pair it with **replication** so failures move **no data at all.**

- **DynamoDB** — replicates each partition across **3 availability zones**. Primary fails → a replica is **promoted via consensus (Raft)** → **nothing moves.**
- **Cassandra** — replicates data to **N consecutive nodes on the ring** → reads served from surviving replicas.
- ▸ **When does data actually move?** Only on **planned membership changes** — adding capacity, or permanently replacing a node to restore the replication factor. Even then, consistent hashing bounds it to **a fraction of keys, not the whole dataset.**

### ⚠ Confusion resolved — "N consecutive nodes" & how replicas sit on the ring

**Worked example — 10 nodes, RF = 3.** Ring positions 0–99:

```
N1(0)  N2(10)  N3(20)  N4(30)  N5(40)
N6(50) N7(60)  N8(70)  N9(80)  N10(90)
```

Key `event-abc` hashes to **17** → walk **clockwise** → the **first three nodes you meet** each store an identical copy:

- **N3 (20)** — first replica
- **N4 (30)** — second replica
- **N5 (40)** — third replica

Any of the three can serve the read.

⚠ **Trap 1 — you never walk backwards.** N1/N2 sit _behind_ position 17, so they hold nothing for this key. Always clockwise, always the **next** three.

⚠ **Trap 2 — the ring is NOT carved into fixed groups of three.** The replica set **slides by one node for every key**:

|Key hashes to|Replica set|
|---|---|
|17|**N3, N4, N5**|
|25|**N4, N5, N6**|
|33|**N5, N6, N7**|

▸ **The unlock:** watch **N5** — it's in all three sets. Every node is **simultaneously**:

- the **primary** for its own token range, **and**
- a **backup replica** for the two ranges behind it.

There is no "group of three" and no dedicated replica machine. There are **10 overlapping windows of three**, one starting at every node. **Everybody does both jobs at once.**

▸ **Why failure costs nothing:** N4 dies → every key it held (as primary _or_ backup) still lives on **two other healthy nodes**, because the windows overlap. Reads route to a survivor. **Nothing promoted, nothing copied, nothing moved.**

### ⚠ Confusion resolved — DynamoDB (leader-based) vs Cassandra (leaderless)

> **My doubt:** "Doesn't Cassandra cost 3x storage per node, while DynamoDB's leader stores only its own keys and replicates elsewhere?" **No — the storage cost is identical.** The mistake is imagining DynamoDB's replica-holders as _spare machines_.

- **RF=3 = three physical copies of every byte — in BOTH systems.** 1TB dataset → 3TB cluster-wide, either way. That's just what RF=3 costs, everywhere.
- In DynamoDB, the nodes holding follower copies are **ordinary nodes that are leaders for other partitions.** A node is leader for partition A **while** holding follower copies of B and C → it carries ~3x its own primary share. **Exactly like Cassandra.**

▸ **The real difference is: who may accept a write?**

||**DynamoDB** (leader-based)|**Cassandra** (leaderless)|
|---|---|---|
|Storage at RF=3|**3x**|**3x — identical**|
|Write path|must reach **that partition's leader**; followers copy it|**any of the 3 replicas** can accept it directly|
|Node failure|brief unavailability during **leader election** (Raft)|**none** — a survivor just answers|
|Consistency|**easier** — one node orders all writes|**harder** — concurrent conflicting writes possible → need resolution (last-write-wins, etc.)|
|Ring visibility|ring is **internal/hidden**; replication sits _below_ the partitioning abstraction|**replicas ARE ring members** — all peers, no master/slave|

▸ **The one line to keep:** RF=3 costs 3x storage in both. What differs is whether writes **funnel through a leader** (DynamoDB) or can **hit any replica** (Cassandra) — that's **availability vs consistency simplicity**, not storage.

▹ **Depth ceiling:** stop here. Raft internals, hinted handoff, and tunable consistency levels belong to the Cassandra / DynamoDB deep dives — pick them up there, not from this file.

---

## Where It's Used

▸ **CRUX** — applies to **any cluster you distribute data across** — not just databases. Caches, message brokers, even plain application servers.

|System|Usage|
|---|---|
|**Cassandra**|consistent hashing to distribute data across the ring|
|**DynamoDB**|consistent hashing under the hood for partition placement|
|**CDNs**|which edge server caches which content|
|**Redis Cluster** ⚠|**does NOT use it** — uses **fixed hash slots**: `CRC16(key) mod 16384`, slot ranges assigned to nodes. Simpler to reason about, but **more coordination when rebalancing**|

▹ **The Redis contrast is a real interview trade-off** — consistent hashing vs fixed hash slots is a legitimate design discussion, not a gotcha.

⚠ **Terminology caveat (Kleppmann, DDIA):** "consistent hashing" is used **loosely**. Several systems claiming it actually use variations like **hash partitioning with fixed slot ranges**. **What matters is the principle — minimizing data movement during rebalancing — not the textbook ring.** _(This is why `01f` deliberately distinguishes Cassandra / DynamoDB / MongoDB mechanics rather than blanket-claiming consistent hashing.)_

---

## Interview Playbook

### When to name-drop vs go deep

- **Most interviews (your targets)** → **name-drop.** "We'll use DynamoDB/Cassandra, which uses consistent hashing under the hood to handle scaling." **Then move on.** Existing solutions handle the complexity for you.
- **Infra-focused prompts** → **go deep.** Triggers:
    - Design a **distributed cache**
    - Design a **distributed database**
    - Design a **distributed message broker**

▸ **The real skill is recognizing which one you're in.** **Most system design interviews are the first category.** Going deep unprompted burns time you needed elsewhere.

### If you do go deep, be ready to explain

- Why consistent hashing **beats simple modulo** sharding.
- How **virtual nodes** improve load balancing.
- How you handle **node failures and additions**.
- How **hot spots** arise and how to mitigate them (**replication, key salting**).
- The relationship between **consistent hashing and replication** for fault tolerance.

---

## Quick Recall (pass 3+)

|Situation|Reach for|
|---|---|
|Why not plain `% N`?|node count is **in the formula** → changing it **remaps almost every key** (add _and_ remove)|
|Core mechanic|**hash ring** — hash the key, **walk clockwise** to the first node|
|What moves on add/remove?|only the **neighborhood** (keys between the new node and its predecessor) — not the whole dataset|
|One node's keys dumped on its neighbor|**virtual nodes** — one DB at many ring points (`DB1-vn1`, `DB1-vn2`…)|
|Vnodes on _adding_ a node|new node absorbs a little from **many** nodes, not all from one neighbor|
|Celebrity key still hammering a node|**consistent hashing distributes keys, not traffic** → read replicas · key salting · adaptive rebalancing|
|The one-liner to say|**vnodes = structural imbalance · replication/salting = workload imbalance**|
|Does a node failure move data?|**No** — replication (DynamoDB: 3 AZs + Raft promotion; Cassandra: N consecutive nodes). Data moves only on **planned** membership changes|
|"N consecutive nodes" means|walk **clockwise**, first N nodes each store a copy. Replica set **slides by one per key** — overlapping windows, **not** fixed groups|
|Every Cassandra node is…|**primary** for its own range **+ backup** for the two ranges behind it (no master/slave — replicas _are_ ring members)|
|DynamoDB vs Cassandra|**same 3x storage.** Difference = **write path**: leader-only (election on failure, easier consistency) vs **any replica** (no election, conflict resolution needed)|
|Redis Cluster|⚠ **not** consistent hashing — **fixed hash slots** (`CRC16 mod 16384`)|
|Interview default|**name-drop only.** Go deep only for distributed cache/DB/message-broker prompts|
qr => https://www.hellointerview.com/learn/system-design/core-concepts/consistent-hashing/quick-reference