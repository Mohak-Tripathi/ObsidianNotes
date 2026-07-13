# Numbers to Know — Deep Divee

> Hello Interview · Core Concepts (deep dive) · File `01i`. Referenced from `01f_sharding` (capacity planning) and `01e_caching` (when to cache). **Calibration:** **HIGH value / core — and it's a _credibility_ file, not a theory file.** These numbers are what let you say _"at 50K writes/sec we'd shard"_ instead of _"eventually we'd need to shard."_ ⚠ **The tell it prevents:** quoting 2015-era hardware limits is the #1 giveaway of **book knowledge without hands-on experience.** Outdated numbers → **over-engineered designs** → rejection. This file is about **not over-building.**

---

## The Core Thesis

▸ **CRUX** — modern hardware is **far** more capable than textbooks assume. Many systems that once _required_ distributed architecture now **run on a single machine.**

- Single DBs handle **terabytes**.
- Caches hold **entire datasets** in memory.
- Message queues are fast enough for **synchronous** flows.
- App servers have enough memory for **significant local optimization**.

▸ **The point is NOT "vertical scaling always wins."** It's **knowing where the real limits are** — so you don't optimize prematurely and can build the **simpler** system that still grows.

---

## Modern Hardware Limits (context)

- **Memory** — AWS `M6i.32xlarge`: **512 GiB + 128 vCPUs**. Memory-optimized: `X1e.32xlarge` = **4 TB RAM**; `U-24tb1.metal` = **24 TB RAM**.
- **Storage** — `i3en.24xlarge` = **60 TB local SSD**; `D3en.12xlarge` = **336 TB HDD**. **S3 = effectively unlimited** (petabyte scale is routine).
- **Network** — **25 Gbps** standard in-datacenter; **50–100 Gbps** on high-perf instances.
- **Latency** — **sub-1ms** within an AZ · **1–2ms** across AZs in a region · **50–150ms** cross-region.

▹ Storage being a _primary constraint_ is largely over. Advice like "split the DB at 100GB" or "avoid large objects in memory" is working from **dead constraints.**

---

## The Four Components

### Caching

▸ **CRUX** — the 32–64GB Redis era is over. Modern caches handle **terabyte-scale** datasets at **single-digit ms**, hundreds of thousands of ops/sec per instance.

**Numbers:**

- **Memory** — up to **1TB** on memory-optimized instances.
- **Latency** — reads **<1ms** same region · writes **<1ms** same-AZ, **1–2ms** cross-AZ.
- **Throughput** — **100k–200k+ ops/sec** per instance (ElastiCache Redis on Graviton). Reads ≈ writes for simple ops.

**Scale triggers:**

- Dataset approaching **1TB**
- Sustained **100k+ ops/sec**
- Read latency requirement consistently **below 0.5ms**

▸ **What this changes:** you can often **cache the entire dataset** and skip complex partial-caching schemes. "Cache everything" looks brute-force but usually **costs less than the engineering time** spent on selective caching logic. ▹ **Counterintuitive:** when you _do_ need to scale a cache, the bottleneck is usually **ops/sec or network bandwidth — not memory size.**

### Databases

▸ **CRUX** — single Postgres/MySQL instances routinely handle **dozens of TB** at millisecond latency, and **tens of thousands of TPS** on one primary. The bottleneck is often **operational**, not performance.

**Numbers:**

- **Storage** — up to **64 TiB** for most engines; **Aurora up to 256 TiB**.
- **Latency** — reads **1–5ms** cached, **5–30ms** from disk · writes **5–15ms** commit latency.
- **Throughput** — reads up to **50k TPS** single-node · **writes 10–20k TPS** single-node (Aurora/RDS).
- **Connections** — **5–20k** concurrent.

**When to consider sharding (→ `01f`):**

- Dataset approaching/exceeding **50 TiB**
- Write throughput consistently above **10k TPS**
- Read latency requirement **below 5ms** for _uncached_ data
- **Geographic distribution** needs (cross-region replication)
- **Backup/recovery windows** stretching into hours → operationally impractical

⚠ **"Single instance" ≠ single point of failure.** You'd still run a **primary + read replicas** (e.g. Aurora multi-AZ failover). **Replication for HA is a SEPARATE concern from horizontal partitioning for scale.** Don't shard just to get redundancy.

### ⚠ Confusion resolved — reading these DB numbers correctly

**1. What is a "transaction" in TPS?**

- The unit is a **query / statement** — **not a row, not a column.**
- Reading one column vs the whole row = **the same one transaction.** Reading 100 rows in a single `SELECT ... WHERE` = **still one.** The cost lives in the round-trip + parse + plan + index traversal, **not** in how many columns you asked for.
- ⚠ **These numbers assume SIMPLE, INDEXED operations.** A `SELECT` with three joins, a sort, and an aggregate over a million rows is _one_ transaction but **nothing like 50k/sec.** _(Same caveat as the SSD-latency mistake below — the headline numbers describe cheap work.)_

**2. "Single-node" — do read replicas break it?** _(The subtle one — "node" means different things per metric.)_

||Primary + read replicas|
|---|---|
|**Writes** (10–20k TPS)|"single-node" = **one primary accepting writes.** All writes still funnel through it → **replicas add ZERO write capacity** → the only escape is **sharding** (`01f`)|
|**Reads** (50k TPS)|that's **one machine's** read capacity → replicas scale you **past** it (3 replicas ≈ 3x reads) → **no sharding needed**|

- ▸ **This is why the DB sharding trigger is stated on WRITE throughput, not read.** Reads have an easy escape hatch (replication); **writes don't.**
- ▸ And it's why **"replication for HA ≠ partitioning for scale"** — replicas buy you availability + read scale, but **never** write scale.

**3. Concurrent connections — the hidden cost.**

- Connections are **cheap to exhaust and expensive to hold.** In Postgres, each one is a **real backend process with its own memory.**
- ⚠ So at scale you **never** let app servers open connections directly to the DB — you put a **connection pooler (PgBouncer)** in front. 5,000 app-side connections **multiplex** onto a few hundred real DB connections.
- ▸ **Expect the follow-up:** _"You have 100k concurrent users — how do they not blow through your 5–20k connection limit?"_ → **Answer: pooling.**

### Application Servers

▸ **CRUX** — **CPU is almost always your first bottleneck — not memory, not connections.**

**Numbers:**

- **Connections** — **100k+** concurrent per instance. ⚠ **This is the `client → app server` hop** (inbound sockets), **not** `app server → DB` — see below.
- **CPU** — 8–64 cores.
- **Memory** — 64–512GB standard, up to **2TB**.
- **Network** — 25 Gbps standard, 50–100 Gbps high-perf.
- **Startup** — **30–60 seconds** for containerized apps.

**Scale triggers:**

- CPU consistently **above 70–80%**
- Response latency exceeding SLA
- Memory trending **above 70–80%**
- Network approaching instance limits

▸ **What this changes:** stateless services are good for scaling — but **don't forget each server has serious memory.** Local caching (`01e` in-process), in-memory computation, session handling can all use it. **Don't shy away from memory-intensive optimizations.** ▹ 30–60s startup makes **aggressive auto-scaling** a real alternative to over-provisioning.

#### ⚠ Confusion resolved — the 100k vs 5–20k connection numbers are DIFFERENT HOPS

> **My doubt:** "Is the 100k connections client→app-server, or app-server→DB? And if PgBouncer handles it, what is 100k?"

```
   client  ──────────►  app server  ──────────►  database
            HOP 1                     HOP 2
           100k+                     5–20k
    (inbound sockets)          (Postgres backends)
```

- **HOP 1 — `client → app server`: 100k+.** Inbound sockets one app server can hold. Cheap — mostly just an open socket.
- **HOP 2 — `app server → DB`: 5–20k.** Each Postgres connection is a **real backend process with its own memory** → **expensive**, hence the far lower ceiling.

▸ **This mismatch is exactly WHY a connection pooler exists.** 100k inbound **cannot** map 1:1 onto 5–20k DB connections. **PgBouncer sits on HOP 2** and multiplexes thousands of app-side connections onto a few hundred real DB connections.

▸ **So which number do you check?** Whichever hop you're reasoning about:

- Sizing app servers / worrying about inbound load → **100k+** (but remember: **CPU usually bottlenecks first**, not connections).
- Sizing the DB / worrying about connection exhaustion → **5–20k** → **pool it.**

### Message Queues

▸ **CRUX** — Kafka-class systems do **millions of msgs/sec at single-digit ms**, retaining weeks/months of data.

**Numbers:**

- **Throughput** — up to **1M messages/sec per broker**.
- **Latency** — **1–5ms** end-to-end in-region.
- **Message size** — **1KB–10MB** handled efficiently.
- **Storage** — up to **50TB per broker**.
- **Retention** — **weeks to months**.

**Scale triggers:**

- Nearing **800k msgs/sec** per broker
- Partition count approaching **200k** per cluster
- **Consumer lag** consistently growing
- Cross-region replication needs

▸ **What this changes:** at consistent **sub-5ms**, you can put a queue **inside a synchronous request flow** — reliable delivery + decoupling **without forcing the API to be async.** _(As long as there's no backlog.)_

---

## ⚠ The Four Interview Mistakes

> This is the real content of the file. Everything above exists to prevent these.

### 1. Premature Sharding — **the single biggest mistake**

- Candidates introduce a data model and **immediately** name a shard column.
- **Design Yelp:** 10M businesses × ~1KB = **10 GB**. Add 10x for reviews → **100 GB**. **Why would you shard?**
- **Same for caches — LeetCode leaderboard:** 100k competitions × 100k users × (36B ID + 4B rating) = **400 GB** → **fits on a single large cache.** No sharding.
- ▸ **Do the math first.** Sharding is the **conclusion**, not the opening move.

### 2. Overestimating Latency (especially SSDs)

- Candidates wildly overestimate the cost of an **indexed** SSD/DB lookup. Reality: **sub-millisecond to a few ms.** It's fast.
- → They then add a **caching layer to fix latency that isn't a problem** — extra infrastructure for nothing.
- ⚠ **Caveat:** this holds for **simple indexed row lookups only.** **Expensive queries are still worth caching** (`01e`).

### 3. Over-engineering for "High" Write Throughput

- 5k writes/sec feels big → candidates reach for a **message queue to buffer**. **They don't need one.**
- **A well-tuned Postgres handles 20k+ simple writes/sec.**
- **What actually limits write capacity:**
    - Complex transactions spanning multiple tables
    - **Write amplification from excessive indexes** (→ `01d`)
    - Writes triggering expensive cascading updates
    - Heavy concurrent reads competing with writes
- **Before reaching for a queue, try:** batch writes · schema + index optimization · connection pooling · async commits for non-critical writes.
- ▸ **Queues earn their place when:** you need **guaranteed delivery** on downstream failure · **event sourcing** · **write spikes beyond DB capacity** (>20k WPS on single Postgres) · **decoupling producers from consumers.** Not merely "the number looks large."

### 4. Obsessing Over Cost

- Real systems care about TCO. **Interviews mostly don't.**
- Nobody wants to memorize pricing tables, and SD estimates are **order-of-magnitude**, not dollar-exact.
- ⚠ **But abstract cost-sense still counts:** 100 machines where 1 suffices, or a bank of in-memory caches when users only need hundreds-of-ms — **that flags.**
- ▸ **Don't memorize AWS pricing. Spend the time elsewhere.**

---

## Cheat Sheet (2026)

> Typical values for well-tuned systems. **Starting points for capacity planning — not hard limits.**

|Component|Key Metrics|Scale Triggers|
|---|---|---|
|**Caching**|~1ms latency · **100k+ ops/sec** · memory-bound (**up to 1TB**)|hit rate <80% · latency >1ms · memory >80% · cache churn/thrashing|
|**Databases**|up to **50k TPS** · sub-5ms cached reads · **64 TiB+** storage|**write throughput >10k TPS** · read latency >5ms uncached · geo-distribution needs|
|**App Servers**|**100k+** concurrent connections · 8–64 cores · 64–512GB RAM (up to 2TB)|**CPU >70%** · latency > SLA · connections near 100k · memory >80%|
|**Message Queues**|up to **1M msgs/sec/broker** · sub-5ms e2e · up to 50TB storage|throughput near **800k msgs/sec** · ~200k partitions/cluster · growing consumer lag|

---

## Quick Recall (pass 3+)

|Question|Answer|
|---|---|
|Single Postgres — simple writes?|**20k+ WPS.** 5k WPS does **not** need a queue|
|Single DB — read TPS?|up to **50k TPS**; writes **10–20k TPS**|
|Single DB — storage ceiling?|**64 TiB** most engines · **Aurora 256 TiB** → shard nearing **50 TiB**|
|When to shard?|**>10k TPS writes** · nearing 50 TiB · geo-distribution · impractical backups|
|Cache size ceiling?|**~1TB** · **100k–200k ops/sec** per instance|
|Cache bottleneck is usually…|**ops/sec or network — NOT memory**|
|Indexed SSD/DB row lookup latency|**sub-ms to a few ms** — don't add a cache to "fix" this|
|App server first bottleneck|**CPU** (>70%), not memory, not connections|
|Kafka broker throughput|up to **1M msgs/sec**, **1–5ms** → usable **inside a sync flow**|
|Latency: AZ / region / cross-region|**<1ms** / **1–2ms** / **50–150ms**|
|#1 interview mistake|**premature sharding** — 10M × 1KB = 10GB. **Do the math.**|
|"Single instance" means SPOF?|**No** — primary + read replicas. **HA replication ≠ sharding**|
|What's a "transaction" in TPS?|a **query/statement** — not a row/column. 100 rows in one `SELECT` = **one**. Assumes **simple indexed** ops|
|Do read replicas raise write TPS?|**No.** Writes funnel through **one primary** → replicas add zero write capacity → **shard.** Reads _do_ scale with replicas|
|100k+ vs 5–20k connections?|**different hops.** 100k+ = `client→app server` (cheap sockets) · 5–20k = `app server→DB` (real Postgres processes) → **pool HOP 2**|
|100k users vs 5–20k connection limit?|**connection pooler (PgBouncer)** — multiplex many app connections onto few DB connections|
|Should I memorize AWS pricing?|**No.** Order-of-magnitude sense is enough|