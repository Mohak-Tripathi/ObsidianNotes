# Key Technologies — Overview

> Hello Interview · **System Design in a Hurry** · File `02`. _(New section — `01x` series = Core Concepts.)_ **Purpose:** the building blocks that solve **90% of system design problems.** You're free to pick _which_ technology per category — but you must have **at least one** you can actually use. ▸ **The governing rule: BREADTH BEFORE DEPTH.** Interviewers rarely care _which_ queue you pick, only that you have one. But if you know _no_ queueing solution, you can't design a system that needs one. ⚠ **Depth probed ∝ level.** Mid-level describing Elasticsearch as "a search index" = fine. **Senior who can't explain the inverted index or reason about its scaling = yellow flag.** _(You're targeting SDE2 → be ready for the follow-up, not just the name-drop.)_

---

> 📌 **Post-job project (parked):** build a DB from scratch to actually understand internals — **https://cstack.github.io/db_tutorial/** _(Let's Build a Simple Database — C, SQLite-style, walks B-tree/pager/cursor from zero.)_ ▹ Not interview prep — **do this after the offer.** But it maps directly onto `01d` (B-tree, pages, heap file), so the concepts will already be familiar.

---

## 1. Core Database

▸ **CRUX** — almost every problem needs storage. Two families: **relational (Postgres)** and **NoSQL (DynamoDB)**. **Pick one and know it well.**

▸ **Which to pick — by interview type:**

- **Product design interview** → **relational.** ⭐ _(This is you — SDE2 product/full-stack at Razorpay/Meesho/Swiggy. Pick **Postgres**.)_
- **Infrastructure design interview** → **NoSQL.**

### ⚠ The SQL-vs-NoSQL pothole — avoid it entirely

This is the **#1 self-inflicted wound** in this section. Candidates volunteer a comparison and reveal inexperience.

**Yellow-flag statements (never say these):**

- ❌ _"I need a relational DB because I have relationships in my data."_ → **NoSQL handles relationships fine.**
- ❌ _"I need NoSQL because I need scale and performance."_ → **Relational DBs, used correctly, scale and perform incredibly well** (→ `01i`).

▸ **What to do instead:** don't compare. **Talk about what the DB you chose gives you, and how it solves _this_ problem.**

> ✅ **Great opener:** _"I'm using Postgres here because its ACID properties let me maintain data integrity."_

▸ **If explicitly asked to compare:** stick to **differences between the databases you actually know** and how they'd impact **this design.** Don't philosophize about the categories.

### Relational — what to know

- **SQL Joins** — combine data across tables (users + posts). Powerful, but ⚠ **a major performance bottleneck — minimize where possible.**
- **Indexes** — the relational superpower is **(a)** arbitrarily many indexes and **(b)** multi-column + specialized types (geospatial, full-text). _(Full mechanics → `01d`.)_
- **Transactions** — group operations atomically. Create a user + their first post → **both succeed or both fail.** No orphan post from a nonexistent user.
- **Common:** **Postgres**, MySQL. _(No favorite? Take Postgres.)_

### NoSQL — what to know

- **Data models** — key-value · document · column-family · graph. Often **schema-less**.
- **Consistency models** — a **spectrum**, not two options: **strong → causal → read-your-own-writes → eventual** (→ `01h` for the full table). NoSQL DBs are often **configurable** along it.
- **Indexing** — also supported (B-tree, hash).
- **Scalability** — horizontal, via **consistent hashing and/or sharding** (→ `01g`, `01f`).
- **Common:** **DynamoDB** (broad features, widely accepted) · **Cassandra** (write-heavy, append-only storage — tradeoffs in functionality) · MongoDB.
- ⚠ **NoSQL's strengths are not relational's failures.** Postgres has **JSON columns** for flexible schemas and _can_ scale horizontally. **Discuss specific features, not broad categories.**

---

## 2. Blob Storage

▸ **CRUX** — large unstructured blobs (images, video, files) in a traditional DB are **expensive and inefficient.** Use **S3 / GCS / Azure Blob** instead. Upload a blob → get a **URL** back.

⚠ **The standard pattern — never use S3 as your primary DB:**

> **Core DB (Postgres/DynamoDB) holds the metadata + a pointer (URL) → S3 holds the blob.** You get low-latency query/index from the DB **and** cheap storage from S3.

- Design **YouTube** → videos in blob storage, metadata in DB.
- Design **Instagram** → images/videos in blob storage, metadata in DB.
- Design **Dropbox** → files in blob storage, metadata in DB.

▸ **The presigned-URL flow (know this — it's the commonly probed bit):**

- **Upload:**
    1. Client requests a **presigned URL** from the server.
    2. Server returns it, **recording it in the DB**.
    3. Client uploads **directly** to the presigned URL.
    4. Blob storage **notifies the server** on completion → status updated.
- **Download:**
    1. Client requests the file → server returns a **presigned URL**.
    2. Client downloads **via the CDN**, which proxies to the underlying blob storage.

▸ **What else to know:**

- **Durability** — replication + erasure coding; survives disk/server failure.
- **Scalability** — treat S3 as **infinitely scalable. Don't spend interview time on it — it's a given.**
- **Cost** — **S3 ≈ $0.023/GB/month** (first 50TB) vs **DynamoDB ≈ $1.25/GB/month** (first 10TB) → **~50x cheaper.**
- **Security** — encryption at rest + in transit, access control.
- **Upload & download directly from the client** ⭐ — blob storage lets the **client talk to S3 directly**, so large files **never pass through your server** (no bandwidth or memory cost to you). This is what makes it viable for images and video at scale.
    - The enabler is the **presigned URL** — a **temporary, scoped grant** of access to a blob, for **either upload or download**. **Familiarize yourself with these** — it's the commonly probed bit (flow above).
- **Chunking** — large files uploaded in pieces → **resumable** + **parallel.** S3 supports it via the **multipart upload API.**
- ▸ **Pairs with a CDN** — S3 is the **origin**; the CDN caches at the edge (→ `01e`).

---

## 3. Search-Optimized Database

▸ **CRUX** — full-text search. Without it you're stuck with `SELECT * FROM documents WHERE document_text LIKE '%term%'` → **can't use an index → full table scan → slow.** _(Why B-trees fail here → `01d`.)_

- **The mechanism: inverted index** — maps **word → documents containing it**, instead of document → words. _(Full mechanics, analysis pipeline → `01d`.)_
- **What to know — these are 3 different layers, not one thing:**
    - **① The data structure — inverted index.** Maps **word → documents**. This _is_ the search index. _(Full mechanics → `01d`.)_
    - **② Build-time pipeline (how the index gets made)** — runs over each document **before** it's indexed:
        - **Tokenization** — break text into individual words → gives you the words to map from.
        - **Stemming** — reduce words to their root ("running", "runs" → "run") → so different forms of a word match.
    - **③ Query-time feature (on top of the finished index)**:
        - **Fuzzy search** — find results _similar_ to the search term, tolerating misspellings. Works via **edit distance** (how many letters must change/add/remove to turn one word into another). Usually a config option out of the box.
    - **Scaling** _(separate concern)_ — like any DB: **add nodes to a cluster and shard across them** (→ `01f`).
- **The leader: Elasticsearch** (distributed, built on Apache Lucene). Used by Netflix, Uber, Yelp.
- ▹ **Alternative — use what you already have:**
    - **Postgres GIN indexes** — support full-text search. **Reduces the footprint of your design** (no new system to run) — worth knowing even if you don't pick it.
    - **Redis** — also has full-text search, but the author's view is that it's **immature and weak.** Know it exists; **don't reach for it.**
- **When:** Ticketmaster searching events · Twitter searching tweets.

---

## 4. API Gateway

▸ **CRUX** — sits **in front** of your system, routes requests to the right backend service (`GET /users/123` → users service). Also handles **cross-cutting concerns: authentication, rate limiting, logging.**

- ▸ **In nearly all product-design interviews, include one as the first point of contact for clients.**
- ▹ **Interviewers rarely probe deeper here** — they'd rather ask problem-specific questions. Draw it, name it, move on.
- **Common:** AWS API Gateway · Kong · Apigee · (nginx/Apache also serve this role).

---

## 5. Load Balancer

▸ **CRUX** — distributes traffic across multiple machines (**horizontal scaling**) to avoid overloading any one or creating a hotspot. **Treat it as a black box in interviews.**

⚠ **Drawing rule:** you technically need an LB wherever multiple machines serve the same request — but **drawing one in front of every service is redundant clutter.** Instead:

- **Omit them entirely** and just say "these services are horizontally scaled", **or**
- **Draw one at the front** as an abstraction.

▸ **The one real decision: L4 vs L7.** Rule of thumb:

- **Persistent connections (WebSockets)** → **L4.**
- **Otherwise** → **L7** — more routing flexibility, minimizes connection load downstream.
- **Common:** AWS ELB · NGINX · HAProxy.

---

## 6. Queues

▸ **CRUX** — a **buffer for bursty traffic** and a way to **distribute work.** Producer fires messages and forgets; a pool of workers consumes at its **own pace.**

- **Smooths load:** spike of 1,000 requests but you handle 200/sec → 800 **wait in the queue — not dropped.**
- **Decouples** producer and consumer → **scale them independently**; bring services down/up behind the queue with negligible impact.

⚠ **Do NOT put a queue in a synchronous workload with tight latency requirements** (e.g. <500ms) — **you're nearly guaranteeing you break the constraint.** ⚠ **And don't add one just because the write number looks big** — 5k WPS doesn't need a queue (→ `01i`, mistake #3).

**Use cases:**

- **Buffer bursty traffic** — Uber ride requests spiking at peak hours.
- **Distribute work** — photo-processing service; workers pull expensive image tasks off the queue.

**What to know:**

- **Message ordering** — most are **FIFO** (processed in receipt order); some (like **Kafka**) allow **more complex ordering**, e.g. based on a specified **priority** or **time**.
- **Retry mechanisms** — configurable attempts + delay before declaring failure.
- **Dead letter queues (DLQ)** — park unprocessable messages for **debugging/auditing.**
- **Scaling with partitions** — partition across servers; **needs a partition key** so related messages land together _(same idea as a shard key → `01f`)_.
- ⚠ **Backpressure — the biggest problem with queues.** If you handle 200 rps but receive 300 rps, **you'll never catch up — the queue is just hiding the fact that you lack capacity.** Fix: **slow the producer** — reject new messages or throttle acceptance, returning an error to the user/producer.
- **Common:** **Kafka** · **SQS** (AWS, fully managed).

---

## 7. Streams / Event Sourcing

▸ **CRUX** — like a queue, but **retains data for a configurable period** → consumers can **re-read** from the same position or from a point in the past. **That replay ability is the whole difference.**

▸ **Event sourcing** — store state changes as a **sequence of events**; replay them to reconstruct state at **any point in time.** → audit trails, reversing/replaying transactions.

**Use a stream when:**

- **Real-time processing at volume** — social platform ingesting likes/comments/shares globally; **Flink / Spark Streaming** updates a live analytics dashboard.
- **Event sourcing** — banking: every deposit/withdrawal/transfer is an event → **audit, rollback, or reconstruct any account's state by replaying.** _(⭐ Directly relevant to fintech targets — ledgers are the canonical event-sourcing case.)_
- **Multiple consumers reading the same stream** — chat room: message published once, **all participants receive it simultaneously** → **publish-subscribe.**

**What to know:**

- **Scaling with partitioning** — partition key, same as queues.
- **Multiple consumer groups** — different consumers read the same stream **independently** (one updates a dashboard, another archives to a DB).
- **Replication** — across servers for fault tolerance.
- **Windowing** — group events by **time or count** → "mean delivery time per region over the last 24h".
- **Common:** **Kafka** · Flink · Kinesis.

---

### ⚠ Confusion resolved — Queue vs Stream vs Stream Processor (Kafka vs Flink)

> **My doubt:** how is a stream different from a queue, what's so special, and how is Flink different from Kafka — when to use which? **The confusion hides a category error: Kafka and Flink are NOT two kinds of the same thing. They're not competing. They do different jobs and usually work _together_.**

**First: three roles, not three products.** The words "queue," "stream," and "stream processor" name three **roles**. Some products fill one role, some fill two. That overlap is exactly what's confusing.

- **Queue** — a buffer you put work into, and workers take work _out_ and it's **gone**.
- **Stream** — a log you append events to, that **remembers** them, and _many_ readers can read independently.
- **Stream processor** — a separate engine that _reads_ a stream and _computes_ things on it continuously.

Kafka is the middle one (a stream). Flink is the third one (a processor). SQS/Redis are the first one (a queue).

**Queue vs Stream — the one distinction that matters.** Forget everything else. The single difference:

> **A queue message is consumed and destroyed. A stream event is read and retained.**

- **Queue (SQS):** Uber has 1,000 ride requests. Each goes into the queue. A worker grabs request #47, assigns a driver, and request #47 is **deleted** from the queue. It's done its job. Nobody else will ever read #47. One message → one worker → gone.
- **Stream (Kafka):** A user likes a post. That "like" event is appended to a log. It **stays there** for days. And now _five different systems_ can each read that same like event, independently, for five different reasons:
    - the notification service (tell the author)
    - the analytics dashboard (increment a counter)
    - the ML pipeline (update recommendations)
    - the audit log (compliance)
    - the fraud detector (is this user botting likes?)

In a queue, once the notification worker grabbed the event, it'd be gone — the other four never see it. The stream's **retention + replay + multiple independent readers** is the whole point.

So the instinct _"Kafka is also a queue"_ is _almost_ right. Kafka _can_ act like a queue. But its real superpower is being a **replayable log that many consumers share**. That's why we call it a stream, not a queue.

> **The one-line test:** does exactly one worker need this message, after which it's done forever? → **queue.** Do multiple systems need it, possibly re-read it, possibly replay history? → **stream.**

**Now: where does Flink come in?** Here's the part that unlocks it. **Kafka stores events. Kafka does not compute anything.**

Kafka is a pipe with a memory. It holds "like happened at 10:03," "like happened at 10:03," "comment at 10:04." It will faithfully hand those to anyone who asks. But if you want to answer:

> _"How many likes per region, per minute, updated live?"_

— Kafka **cannot** do that. It has no idea how to count, group by region, or bucket by minute. It just stores and serves raw events.

**Something has to read the raw events and do the math.** That something is **Flink** (a stream processor).

```
users → [Kafka: stores raw like-events] → [Flink: reads them, counts per region per minute] → dashboard
          the LOG (storage/transport)         the COMPUTE (aggregation/logic)
```

Kafka = the **storage and transport**. Flink = the **computation** on top.

They're not alternatives. In that pipeline **you use both** — Kafka holds the firehose of events, Flink continuously chews through them and produces answers.

**So when do you actually need Flink?** Only when you need **continuous computation over the stream** — not just moving events, but _transforming/aggregating_ them in real time:

- Live analytics — "trending hashtags right now," "mean delivery time per region over the last 24h"
- Windowing — anything "per minute / per hour / rolling 5-minute average." Kafka has no concept of a time window; Flink's core feature _is_ time windows.
- Complex event patterns — "alert if a card is used in 3 countries within 10 minutes" (fraud). That's pattern detection across many events — pure Flink.

If all you're doing is **moving events from A to B** and each consumer does its own simple handling → **just Kafka, no Flink.** The moment you need **aggregation/windowing/pattern-matching across many events, live** → **add Flink on top of Kafka.**

**The scenario contrast.**

- **Scenario A — food delivery order events.** Order placed → notify restaurant, notify driver, save to DB. Three consumers, each does a simple thing with each event. → **Kafka alone.** (Stream, because 3 independent consumers. No Flink, because no cross-event math.)
- **Scenario B — live ops dashboard for that same company.** "Show average delivery time per city, updated every minute, over the last hour." → **Kafka + Flink.** Kafka carries the delivery-completed events; Flink windows them by city and by minute and computes the rolling average. Kafka _can't_ compute the average; that's why Flink exists.

Same event source. B needs computation, so B adds Flink. That's the entire decision.

**The mental hierarchy to keep.**

```
SQS / Redis  →  queue        →  consume once, then gone
Kafka        →  stream       →  retain + replay + many readers  (STORAGE/TRANSPORT)
Flink        →  processor    →  compute over the stream, live   (COMPUTE)
```

- Queue vs stream = **destroyed vs retained**.
- Stream vs processor = **storing events vs computing on them**.
- Kafka and Flink are **partners**, not competitors.

▹ Small correction to bank: Redis _can_ do queue-like things (Redis Streams, or `LPUSH`/`BRPOP` lists), so the "Redis is also a queue" instinct is right too.

---

## 8. Distributed Lock

▸ **CRUX** — DB transaction locks are for **short, in-transaction** consistency. They are **NOT designed for longer-term locking** (holding a concert ticket for ~10 minutes while a user checks out). **That's the gap distributed locks fill.**

- **Mechanism** — a distributed key-value store (**Redis**, ZooKeeper). Use the store's **atomicity**: set `ticket-123 = locked`; a second process trying the same **fails** because it's already set. Release → set to unlocked.
- ▸ **Lock expiry is the killer feature** — if the process **crashes while holding the lock**, the lock **auto-expires** (e.g. 10 min) instead of wedging the resource forever.

**Use cases:**

- **E-commerce checkout** — hold limited-edition sneakers in a cart for 10 min during payment.
- **Ride-sharing matchmaking** — lock a driver so they can't be matched to two riders at once.
- **Distributed cron** — ensure a scheduled job runs on **only one server**, not duplicated across the fleet.
- **Auction bidding** — lock the item in the final seconds while a bid is processed.

**What to know:**

- **Redlock** — the common Redis implementation; uses **multiple Redis instances** for safe acquire/release.
- **Lock expiry** — as above; prevents stuck locks.
- **Locking granularity** — one resource (a ticket) vs a group (a stadium section).
- ⚠ **Deadlocks** — process A holds lock 1 and wants 2; process B holds 2 and wants 1 → **both wait forever.** Be ready to discuss prevention. **Common mistake: pulling locks from far-flung parts of your infra/code — it makes deadlocks hard to see coming.**

---

## 9. Distributed Cache

> Full treatment → **`01e_caching`.** Only the **interview-specific** deltas are here.

▸ **CRUX** — a server/cluster storing data **in memory**; used to **scale** and **lower latency**.

**Use it to:**

- **Save aggregated metrics** — expensive dashboard metrics computed hourly by a background job, served from cache.
- **Reduce DB queries** — user sessions in cache instead of hitting the DB every request.
- **Speed up expensive queries** — Twitter's "posts from people I follow" joins several tables; run it once, cache the result.

**What to know:** eviction (**LRU / LFU / FIFO**) · **invalidation strategy** · **write strategy** (write-through / **write-around** / write-back) — all → `01e`.

- ▹ **Write-around** is the one `01e` doesn't cover: **write straight to the datastore, bypassing the cache.** Minimizes **cache pollution**, but the **next read is slower** (guaranteed miss).

⚠ **The missed opportunity most candidates hand over:**

> **"I'll store the events in a cache"** ← too vague; **invites follow-up questions.** **Be explicit about WHAT you're storing and in WHICH data structure.** Redis is **not** just key-value — it has **sorted sets, lists, hashes, sets, bitmaps, hyperloglogs.** Storing a leaderboard? **Say "sorted set"** so you can pull top-N cheaply.

- **Common:** **Redis** (rich data structures) · **Memcached** (simple strings/binary).

---

## 10. CDN

> Mechanics + latency numbers → **`01e_caching`.**

▸ **CRUX** — a **geographically distributed cache**. Routes each user to the **closest edge server**; miss → fetch from origin, cache, return.

- ▸ **Most common interview use: static media** (Instagram profile pictures, images, video).
- ▹ **But not only static** — CDNs can cache **dynamic content** and **API responses** too (great for frequently-accessed, infrequently-changed data, like a blog post updated daily).
- **Eviction:** TTL or explicit **cache invalidation** on change.
- **Common:** Cloudflare · Akamai · CloudFront. _(Also offer DDoS protection, WAF.)_

---

## Quick Recall (pass 3+)

|Category|Default pick|The one thing to remember|
|---|---|---|
|**Core DB**|**Postgres** (product design) · DynamoDB (infra)|⚠ **Never volunteer a SQL-vs-NoSQL comparison** — it's a yellow flag. Talk about _your_ DB's features|
|**Blob storage**|**S3**|metadata+URL in the DB, **blob in S3**. Never S3 as primary DB. **Presigned URLs** + chunking|
|**Search**|**Elasticsearch**|**inverted index** (→`01d`); `LIKE '%x%'` can't use an index. Postgres **GIN** as the lighter option|
|**API Gateway**|AWS API Gateway / Kong|routing + **auth, rate limiting, logging**. Include it; **rarely probed deeply**|
|**Load Balancer**|ALB / NGINX|**black box.** Don't draw one per service. **WebSockets → L4, else L7**|
|**Queue**|**Kafka** / **SQS**|buffer + decouple. ⚠ **Backpressure** — a queue hides missing capacity, it doesn't create it. **Not in tight-latency sync paths**|
|**Stream**|**Kafka**|queue + **retention/replay** → event sourcing, multiple consumer groups, windowing|
|Queue vs stream?|**destroyed vs retained.** one worker then gone → queue · many readers + replay → stream||
|Kafka vs Flink?|**partners, not competitors.** Kafka **stores/transports** events · Flink **computes** over them (windows, aggregates, patterns). Need live aggregation → add Flink on top of Kafka||
|**Distributed lock**|**Redis (Redlock)**|for **long-held** locks (10-min checkout) — DB txn locks can't. **Expiry** saves you on crash. Watch **deadlocks**|
|**Distributed cache**|**Redis**|⚠ **name the data structure** ("sorted set for the leaderboard"), not just "I'll cache it"|
|**CDN**|CloudFront / Cloudflare|static media at the edge; **also dynamic + API responses**|
|**Governing rule**|—|**breadth before depth.** Have _one_ option per category you can actually defend|