# Ad Click Aggregator — Problem Breakdown

> 📐 **Revision note (calc):** **10M ads · peak 10k clicks/s · average ≈ 1k/s (peak ≈ 10×) · ≈ 100M clicks/day (⊕ 1k × 86,400 = 86.4M, rounded up).** 📐 **Batch: 10k/s × 5 min = 3M events × 100 B = 300 MB.** 📐 ⊕ **Kinesis 1000 records/s per shard ⇒ ≥ 10 shards (HI never says).** 📐 **Dedupe cache 100M × 16 B = 1.6 GB raw; ⚠ ⊕ ~10 GB with real Redis overhead.** 📐 ⊕ **100M ÷ 10M ads ≈ 10 clicks per ad per day ⇒ most (ad, minute) buckets hold 0–1 clicks.**

> Common Problems · **Evan King, updated Feb 15, 2026** · ⭐⭐ **"hard"** · **Asked at: Rippling, W +4** (⭐ **Rippling is on your target list**) · ⭐⭐ **`Scaling Writes` → `03e`** · Cross-refs: **`02c` Kafka · `02h` Flink · `02e` Cassandra · `02a` Redis · `04d` TSDB · `04b` HyperLogLog · Rate Limiter (13) DD4 · Payment System DD1.**
> 
> **Calibration:** ⭐⭐ **TWO passes (my call). HI rates it "hard" and the ladders are long.** ⭐ **Order: HLD ladder (batch vs stream) > DD3 (idempotency) > DD2 (no lost clicks) > DD1 (scale) > DD4 (query latency).**
> 
> - ⭐⭐ **What scores:** **(a)** ⭐⭐⭐ **why raw + GROUP BY dies, pre-aggregation** · **(b)** ⭐⭐⭐ **batch vs stream, honestly** · **(c)** ⭐⭐⭐ **redirect through our server (302)** · **(d)** ⭐⭐⭐ **idempotency ladder: user+ad ⇒ signed impression ID ⇒ cache before the stream** · **(e)** ⭐⭐ **no lost clicks: retention, S3, reconciliation (Lambda)** · **(f)** ⭐⭐ **hot shards: salt the key** · **(g)** ⭐ **OLAP vs TSDB, rollups.**
> - ⭐ **Transferable primitives:**
>     - ⭐⭐⭐ **Mint the dedupe identity at the source, sign it, verify it at the sink.**
>     - ⭐⭐⭐ **The raw log is the truth; aggregates are derived and periodically recomputed.**
>     - ⭐⭐⭐ **A check-then-act dedupe store must be atomic (`SET NX`).**
>     - ⭐⭐ **Salt a hot key and you owe a merge.**
>     - ⭐⭐ **Event time ≠ processing time; watermarks say when a window may close.**
>     - ⭐ **Don't add machinery the problem size doesn't need — but know what guarantee it was buying.**
> - ⭐ **Re-run (cross-ref only):** **stream partitions and retention (`02c`) · Redis (`02a`) · hot-key splitting (Rate Limiter DD4) · HMAC + `SET NX` + TTL (Payment System DD1).** **New:** ⭐⭐⭐ **windows and watermarks · Lambda architecture** · ⭐⭐ **OLAP vs TSDB · event time** · ⭐ **rollups.**

---

## 0 · Understanding the problem

💬 **An Ad Click Aggregator collects clicks on ads and aggregates them so advertisers can track performance and tune campaigns.** ⭐ **Assume ads shown on a website or app, like Facebook.**

⭐⭐ **Scale first.** **HI: "the scale will have a large impact on the database design and the overall architecture".** ⭐ **Ask before drawing anything.**

⭐ **HI's path: this is a data-processing problem, not a product API. Define the system interface and the data flow, then build the HLD one FR at a time.**

---

## 1 · Requirements

### 1.1 Functional

1. ⭐⭐⭐ **Users can click on an ad and be redirected to the advertiser's website.**
2. ⭐⭐⭐ **Advertisers can query ad click metrics over time with a minimum granularity of 1 minute.**

⚠ **Below the line:** **Ad targeting · Ad serving · Cross device tracking · Integration with offline marketing channels.**

### 1.2 Non-functional

📐 ⭐ **Scale: 10M active ads, peak 10k clicks/s (peak ≈ 10× average ⇒ ~1k/s ⇒ ~100M/day).**

1. ⭐⭐ **Scalable to support a peak of 10k clicks per second.**
2. ⭐⭐ **Low latency analytics queries for advertisers (sub-second response time).**
3. ⭐⭐⭐ **Fault tolerant and accurate data collection. We should not lose any click data.**
4. ⭐⭐ **As realtime as possible. Advertisers should be able to query data as soon as possible after the click.**
5. ⭐⭐⭐ **Idempotent click tracking. We should not count the same click multiple times.**

⚠ **Below the line:** **Fraud or spam detection · Demographic and geo profiling of users · Conversion tracking.**

> ⚠ **Tension.** ⊕ **"Never lose a click" (at-least-once) and "never count twice" (at-most-once) together mean exactly-once, which nothing gives for free — DD2 and DD3 each buy one half.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 1.3 ⭐⭐⭐ The design driver — a write-heavy firehose that must be queryable within a minute, counted exactly once, and never lost

|Constraint|What it breaks|Fixed by|
|---|---|---|
|⭐⭐⭐ **10k clicks/s**|**a direct write to the query DB + GROUP BY**|**stream + pre-aggregation (§4.2)**|
|⭐⭐ **sub-second reads**|**aggregating at query time**|**OLAP + pre-aggregation (§4.2, DD4)**|
|⭐⭐ **minute-level freshness**|**batch every N minutes**|**Flink windows + a flush interval (§4.2)**|
|⭐⭐⭐ **no lost click**|**a single store, a consumer crash**|**replicated stream + retention + S3 + reconciliation (DD2)**|
|⭐⭐⭐ **count once**|**user+ad dedupe, in-window dedupe**|**signed impression ID + pre-stream cache (DD3)**|
|⭐⭐ **one ad can dominate**|**partition by AdId**|**salted key + a merge (DD1)**|

### 1.4 Planning the approach

⭐ **Interface and data flow first (no API section); then one HLD per FR; then the deep dives on the NFRs.**

---

## 2 · Core Entities

⭐ **HI lists no entities section for this problem — the entities are the schemas that appear in the HLD.**

- **Advertisement** — ⭐ **`AdId`, `RedirectUrl`, metadata, held in the Ad DB.**
- **Ad Click Event** — ⭐ **raw, one per click: `eventId`, `adId`, `userId`, `timestamp`.**
- **Aggregated Data** — ⭐ **one row per ad per minute: `AdId`, `Minute`, `Click Count`.**

> ⚠⚠ **The impression ID appears only in DD3 and is never added to the event.** ⊕ **The raw event must carry `impressionId`; reconciliation (DD2) and batch dedupe depend on it.**
> 
> ■ **— end of insert · HI write-up resumes below —**

---

## 3 · System Interface + Data Flow

⭐ **HI uses a system interface instead of an API, because this is a data-processing system.**

- ⭐ **Input: ad click data from users.** · ⭐ **Output: ad click metrics for advertisers.**

⭐⭐ **Data flow (HI says "start simple and build up"):**

1. ⭐ **A user clicks an ad on a website.**
2. ⭐ **The click is tracked and stored.**
3. ⭐ **The user is redirected to the advertiser's website.**
4. ⭐ **Advertisers query the system for aggregated click metrics.**

⚠ **Step order is a design choice. If step 2 must finish before step 3, then "never lose a click" costs redirect latency (see §4.1).**

---

## 4 · High-Level Design

### 4.1) Users can click on ads and be redirected to the target

⭐ **An Ad Placement Service decides which ad to show and delivers the creative plus metadata (redirect URL). It is a black box here: targeting and serving are out of scope.** ⭐ **The Ad DB holds `Advertisement`.**

⚠ **HI labels these two approaches without Bad/Good/Great; the first is plainly weaker.**

#### ⚠ Approach A — browser redirects by itself; a parallel POST to `/click` tracks it

- ⭐ **Ship the redirect URL with each ad. The click navigates directly; in parallel the browser POSTs `/click`. Simple, no server-side redirect logic.**
- ⚠⚠ **Tracking can be bypassed: a user can copy the URL, or someone builds a browser extension to skip the POST. The click data then undercounts, and advertisers can't trust it.** ⊕ **It also loses the POST if the tab closes on navigation.**

**Why climb:** ⭐ **we must see every click.**

#### ⭐⭐⭐ Approach B — click goes to OUR server, which tracks it and answers 302 (HI's pick)

- ⭐ **The click hits `/click` on our Click Processor; it records the click, then responds with a 302 to the advertiser's site.** ✅ **Every click passes through us; we can append tracking parameters (out of scope).**
- ⚠ **Added complexity and latency on the user's path; the service must be fast and scalable.**

> ⚠ **What HI leaves loose.**
> 
> - ⚠⚠ **If the stream write fails, do we still redirect?** ⊕ **"No lost click" needs a replicated ack from the stream BEFORE the 302, which costs latency. Or redirect anyway and accept a lost click. HI never says.** ▹ **Judgment call; at least name the choice.**
> - ⚠ **A navigation is a GET: the signed ID rides in the query string; bot GETs count as clicks.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 4.2) Advertisers can query ad click metrics over time at 1-minute intervals

⭐⭐ **Expand the Click Processor path: what happens after `/click` receives a request?**

#### ⚠⚠ Bad — store the raw event and GROUP BY at query time

- **Insert each click into one database: `EventId · Ad Id · User Id · Timestamp`. An advertiser's query is `SELECT COUNT(*), COUNT(DISTINCT UserId) … WHERE AdId = 123 AND Timestamp BETWEEN …` .**
- ⚠⚠ **HI: "at our scale, this solution sucks". 10k writes/s overloads the DB; the GROUP BY is slow, so the sub-second NFR breaks.**

**Why climb:** ⭐ **separate the write path from the read path, and do the aggregation in advance.**

#### Good — Cassandra raw events + Spark batch into an OLAP database

⭐⭐ **The flow (HI's):** **① the ad click is sent to the Click Processor ② it writes the event to the event store ③ every N minutes a cron job kicks off a Spark job that reads the events from the event store and aggregates them ④ the aggregated data is stored in an OLAP database ⑤ advertisers query the OLAP database for metrics on their ads.**

- ⭐ **Raw events go to Cassandra (LSM tree: commit log, memtable, SSTables). Every N minutes a cron starts a Spark job: read raw events, aggregate by (AdId, minute) with map-reduce, write to an OLAP database. Schema: `Ad Id · Minute Timestamp · Unique Clicks`.**
- 📐 **10k/s × 5 min = 3M events × 100 B = 300 MB per batch. HI admits one machine could do it; Spark is for growth and "a well-understood MapReduce paradigm that's easy to reason about in an interview".**
- ⭐⭐ **OLAP (Redshift, Snowflake, BigQuery; the diagram also lists Druid): columnar storage makes COUNT/SUM/AVG over millions of rows fast.**
- ⭐⭐ **Why not a TSDB (InfluxDB, TimescaleDB)? It suits one metric over time at low cardinality; we have millions of ad IDs and will want more dimensions (device, geo, campaign) — OLAP wins. If the interviewer only wants simple time ranges, a TSDB is fine (`04d`).**
- ⚠⚠ **Challenges (HI): ① batch delay — advertisers always see data a couple of minutes old; ② spikes — the next batch has far more data and can run longer than its interval, so lag compounds exactly when advertisers care most (a big launch).** ⭐ **A queue before the event store would absorb write spikes but not fix latency.**

> ⚠⚠ **What HI leaves loose in this rung.**
> 
> - ⚠⚠ **"Spark reads the last 5 minutes from Cassandra" is not a key lookup.** ⊕ **A time range across all ads needs a time-bucket partition key (every write hits the current bucket — a hot partition) or a full scan.** ⚠ **HI's "SSTables aren't good at range queries, hence batch" is circular.**
> - ⚠ **The diagram says cron "run every minute"; the text says every 5 minutes.**
> - ⚠⚠ **The schema stores ONE count column ("Unique Clicks") but the first SQL returns `COUNT(*)` AND `COUNT(DISTINCT UserId)`.** ⊕ **Unique users are NOT additive: summing per-minute unique counts over an hour overcounts anyone who clicked in two minutes. A distinct count needs a sketch (HyperLogLog, `04b`) or raw rows. Later the column is renamed "Click Count" — a total, not unique.**
> - ✅ ⊕ **Trade-off worth saying: Cassandra here is a staging buffer; the same data could stay in the stream (next rung).**
> 
> ■ **— end of insert · HI write-up resumes below —**

**Why climb:** ⭐ **batch can't go below minutes (Spark has startup overhead), and spikes cascade.**

#### ⭐⭐⭐ Great — stream (Kafka/Kinesis) + Flink into the OLAP database

⭐⭐ **The flow (HI's):** **① a click comes in ② the Click Processor writes the event to a stream like Kafka or Kinesis ③ a stream processor like Flink or Spark Streaming reads the events and aggregates them in real time ④ the aggregated data is stored in the OLAP database ⑤ advertisers query the OLAP database for metrics on their ads in near real time.**

- ⭐⭐ **Why Flink, not plain consumers counting in memory? Fine at mid-level, but Flink gives event-time windows (out-of-order events land in the right minute), watermarks, exactly-once, and state recovery.**
- ⭐⭐ **Event time (click occurred) not processing time (Flink saw it); watermarks track progress and handle late events; at window end, flush to OLAP.** ▸ **`02h`.**
- ⭐⭐⭐ **HI's honest admission: click-to-query latency is not much better than the batch rung at equal windows. The gain is the LEVERS: a window of a few seconds (Spark can't run that often), or a minute boundary with a flush every few seconds — the latest minute is simply incomplete.**

> ⭐⭐ **Pattern: Scaling Writes (`03e`)** — **HI: 10k clicks/s dwarfs the read load; the stream buffer, Flink pre-aggregation and partitioning by AdId all exist to absorb write throughput without losing data.**
> 
> ■ **— end of insert · HI write-up resumes below —**

> ⚠ **What HI leaves loose.**
> 
> - ⚠⚠ **The "Aggregated Data" box has one count and no distinct count (same gap as above); two flushes of the same open minute must REPLACE, not add, or the count is wrong (see DD1's "SUM" claim).**
> - ⚠ **The Flink choice lists exactly-once and state recovery as reasons. Those ARE checkpointing — DD2 then argues checkpointing is unnecessary. Pick one story (DD2).**
> 
> ■ **— end of insert · HI write-up resumes below —**

---

## 5 · Deep Dives

⭐ **HI picks four, all on the NFRs: scale, no lost data, idempotency, query latency.**

### 1) How can we scale to support 10k clicks per second?

⭐ **Walk each bottleneck from the moment of the click.**

- ⭐ **Click Processor: scale horizontally (managed auto-scaling on CPU/memory) behind a load balancer.**
- ⭐⭐ **Stream: Kinesis allows 1 MB/s or 1000 records/s per shard ⇒ shard by `AdId`, so one ad's events share a shard and shards are read in parallel.** 📐 ⊕ **≥ 10 shards (HI never says).**
- ⭐ **Stream processor: scale horizontally — HI: "a separate Flink job reading from each shard" for the AdIds in it.**
- ⭐ **OLAP: managed warehouses (Snowflake, BigQuery) scale for you. Self-managed (ClickHouse): shard by `AdvertiserId`, so an advertiser's ads live on one node — in anticipation of "all my active ads" queries. Monitor query performance against SLAs.**

#### Hot shards

⭐⭐ **A big new ad (HI's Nike + LeBron) sends all its clicks to one shard ⇒ latency, at worst data loss.** ⭐⭐⭐ **Fix: append a random number to the partition key for popular ads — `AdId:0..N` — picked by ad spend or click volume. Flink strips the suffix and writes under the real AdId. HI: "since we're doing upserts with SUM aggregation, concurrent writes combine correctly" — or keep sub-keys and sum at query time.**

> ⚠⚠ **What HI leaves loose — several of these matter.**
> 
> - ⚠⚠ **"Upserts with SUM" conflates two operations.** ⊕ **An overwrite-upsert lets partial counts clobber each other; an additive merge double-counts on replay unless the sink is exactly-once.** ⊕ **Fix: two-phase aggregation (per salted key, then per real AdId, one row written), or sum at query time.**
> - ⚠ **Salting by spend or past volume can't predict a new viral ad ⇒ ⊕ salt dynamically on a rate threshold.**
> - ⚠ **After salting, one ad sits on several shards ⇒ the merge above. One Flink job with parallelism is normal; "a job per shard" is odd.**
> - ⚠ **The OLAP key "AdvertiserId (PK), Minute (SK)" omits AdId, and PK/SK is DynamoDB vocabulary.** ⊕ **Use (advertiserId, adId, minute); advertiserId isn't in the click event ⇒ enrichment join. Sharding by advertiser has its own hot node.**
> - ⊕ **10k events/s × ~100 B ≈ 1 MB/s: a SMALL stream. The depth is salting and the merge.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 2) How can we ensure that we don't lose any click data?

⭐ **Four layers.**

#### Layer 1 — the stream itself

- ⭐⭐ **Streams are distributed, fault-tolerant, highly available: Kafka replicates across brokers; Kinesis across availability zones. A node dying does not lose data.** ⭐ **Enable retention: HI's example is 7 days, so a crashed processor restarts and re-reads what it missed.**

#### Layer 2 — checkpointing (HI argues you DON'T need it)

- ⭐⭐ **Flink checkpoints state to durable storage (S3); after a crash it resumes from the last checkpoint. Valuable when windows are large (a day, a week) — you don't want to rebuild a week of state.**
- ⭐⭐⭐ **HI's point: windows are one minute, so a Flink crash loses at most a minute of aggregate; with retention we replay and re-aggregate. Candidates often propose checkpointing and HI pushes back — questioning fit is a seniority signal.**

> ⚠⚠ **This sits badly against HI's own Flink justification.**
> 
> - ⚠⚠ **The HLD chose Flink for "exactly-once" and "state recovery" — that IS checkpointing, which DD2 calls unnecessary.** ⊕ **Pick ONE story: Flink's exactly-once, or replay + idempotent sink.** 📐 **Open state ≤ ~600k keys (10k/s × 60 s) — cheap to checkpoint anyway.**
> - ⊕ **Replay is only safe if the sink overwrites per (ad, minute); an additive write double-counts. And "replay from a known timestamp" needs an offset record — a checkpoint by another name.**
> - ⚠ **"Replay from a known timestamp" leaves open: which timestamp? You need an offset/commit record — which is a checkpoint by another name.**
> 
> ■ **— end of insert · HI write-up resumes below —**

#### Layer 3 — reconciliation (HI's answer to "things could still go wrong")

- ⭐⭐ **"Click data matters, a lot. If we lose click data, we lose money." Transient Flink errors, bad code pushes, out-of-order events can still leave small inaccuracies. Add a periodic reconciliation job (hourly or daily).**
- ⭐⭐⭐ **Alongside Flink, dump raw events to S3 (Kafka Connect S3 sink, or Kinesis Firehose) with no extra load on Flink. A daily Spark job re-aggregates, compares with OLAP, and a Reconciliation Worker fixes wrong records.**
- ⭐⭐⭐ **HI names this a Lambda architecture: a speed layer (Flink) for low-latency results and a batch layer (Spark) as the source of truth that corrects the speed layer.**

> ⚠⚠ **What reconciliation does NOT cover — HI leaves these out.**
> 
> - ⚠⚠ **"Cache-failure duplicates are caught by reconciliation" only if the batch can recognise them: it re-reads the same duplicates from S3 unless events carry `impressionId` (§2).**
> - ⚠⚠ **It cannot recover clicks lost BEFORE the stream — a Click Processor crash before the append, or a failed append. S3 is fed by the same stream.** ⊕ **That is the redirect-path question from §4.1: a replicated ack before the 302.**
> - ⚠ **Lambda's cost: two code paths that drift. ⊕ Share the aggregation logic.**
> - ⚠ **A batch overwrite can race a late streaming write ⇒ ⊕ reconcile only closed windows, overwrite not add.**
> - ✅ **The pattern is right: the raw log is the truth, aggregates are derived and periodically recomputed.** ▸ **Same thread as Payment System's CDC audit log: "fast tier decides, durable tier remembers".**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 3) How can we prevent abuse from users clicking on ads multiple times?

⭐ **Fraud detection is out of scope, but we still want idempotency: a repeat click counts once.** ⭐⭐ **A critical point in both rungs: dedupe BEFORE the stream, because a duplicate on either side of a minute boundary would be counted as two clicks.**

⚠ **Rung labels follow HI's "Good" and "Great"; the first is listed first.**

#### Good — require login; dedupe by (userId, adId)

- ⭐ **Users must be logged in to see an ad. The `userId` (from JWT or session cookie) is logged with the click; dedupe on userId + adId.**
- ⚠⚠ **Limits: ① needs login (a product decision); ② one click per user per ad EVER — retargeting deliberately shows the same ad repeatedly.** ⭐⭐ **HI: amend the problem to one click per user per ad INSTANCE.**

**Why climb:** ⭐ **we need an identity per ad display, not per (user, ad).**

#### ⭐⭐⭐ Great — a unique, signed impression ID

- ⭐⭐⭐ **A fresh impression ID per rendered ad (1000 users, 1000 IDs) is the idempotency key.** 💬 **Each placement of the same ad is a new impression.**
- ⭐⭐ **Dedupe where? Before the stream (it must span aggregation windows), using a cache of seen IDs.**
- ⭐⭐⭐ **Forgery: invented IDs are all unique and would all count. Fix: sign impression ID + adId with an HMAC; the Click Processor verifies it, which also blocks replaying an ID against another ad. Microseconds.** ✅ **Stateless.** ▸ **Payment System DD1.**

⭐⭐⭐ **The flow (HI's recap):**

- ① **Ad Placement Service: unique impression ID per ad instance shown**
- ② **ID signed with a secret key, sent to the browser with the ad**
- ③ **User clicks ⇒ browser sends the impression ID with the click data**
- ④ **Click Processor verifies the signature**
- ⑤ **Click Processor checks the cache: ID found ⇒ duplicate, ignore**
- ⑥ **Not found ⇒ write to the stream FIRST, then add the ID to the cache**
- ⭐ **Why stream first: a failed cache update loses no click; duplicates are the cheaper mistake (HI: reconciliation catches them — ⚠ see below).**

⚠⚠ **Challenges / limits (HI):**

- ⚠ **More complexity; the cache can become a bottleneck if not scaled.**
- 📐 ⭐ **Cache data is small: 100M/day × 16 B (128 bit) = 1.6 GB — HI: "tiny".**
- ⭐ **Play safe: Redis Cluster to scale; a replica takes over if the cache goes down; Redis persistence (RDB or AOF) so the data isn't lost.**

> ⚠⚠ **What HI leaves loose — the biggest cluster in this write-up.**
> 
> - ⚠⚠ **The check-then-write is a RACE.** ⊕ **Two concurrent clicks with one ID both miss the cache, both hit the stream, both count; "stream first" widens the window.** ⊕ **Use an atomic `SET impressionId NX EX ttl`; a crash after it loses a click, so compensate with `DEL` on stream failure or dedupe exactly in the batch.** ▸ **`05t`/`05u`/`05x`.**
> - ⚠⚠ **No TTL stated: without one the cache grows forever; with one, a replay after expiry counts again.** ⊕ **Put a timestamp inside the signed payload (Payment System nonce window).**
> - ⚠ **HI says cross-window dedupe "isn't easy" in Flink; keyed state with a TTL does it. The real cost of deduping before the stream is a Redis hop on the redirect path.**
> - ⚠ **1.6 GB is raw keys; real entries cost ~100 B ⇒ ~10 GB per day of retention. Still small.**
> - ⚠ **"Reconciliation catches cache-failure duplicates" only works if `impressionId` is in the stored event (see DD2).**
> - ⚠ **Harvesting IDs by loading pages is fraud (out of scope); HMAC doesn't stop it.**
> - ⭐ **"Ask the product what duplicate means" — the retargeting amendment.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 4) How can we ensure that advertisers can query metrics at low latency?

⭐ **Mostly solved already: the data is pre-aggregated into the OLAP DB, in either the batch or the stream design.**

- ⭐⭐ **Slow case: very long ranges (days, weeks, years). Create tables at a coarser grain — daily or weekly — filled by a nightly cron job. Advertisers query the rollup, and drill down to the minute table when needed.**
- ⭐ **HI: this is "a form of caching" — trade storage for query speed on the common queries.**

> ⚠ **What HI leaves loose.**
> 
> - ⚠⚠ **A nightly rollup is stale for today.** ⊕ **A query over "last 30 days including today" must UNION the rollup with the minute table for the current day.**
> - ⚠⚠ **Rollups of non-additive metrics have the same distinct-count problem as the minute table: you can't sum daily unique users. A sketch (HyperLogLog) or a separate unique store is needed.**
> - ⚠ **Sparse data: ~10 clicks per ad per day (📐) means most minute rows are 0 or 1. Don't store empty buckets; sparse storage is the realistic case.** ⊕ **Worst case is still ~100M rows/day, one per click.**
> - ⭐ **OLAP engines (ClickHouse, Druid) also offer materialized views / rollup at ingest — the same idea without a nightly cron.**
> 
> ■ **— end of insert · HI write-up resumes below —**

---

## 6 · Final Design

⚠ **Layout and arrows are mine; components are HI's.**

```
Browser ──click (GET /click?impressionId=sig…)──► LB + API Gateway ──► Click Processor × N
   ▲                                                                      │
   │ 302 → advertiser site                                                │ ⭐⭐⭐ verify HMAC
   └──────────────────────────────────────────────────────────────────────┤ ⭐⭐⭐ Redis Cluster: seen this impressionId?   (replica + RDB/AOF)
                                                                          │    ⊕ atomic SET NX + TTL
Ad Placement Service ──► Ad DB (AdId, RedirectUrl, …)                     │ ⭐⭐⭐ write to the stream, THEN remember the id
   ⭐ mints + SIGNS impressionId per rendered ad                          ▼
                                                  Kafka / Kinesis  (partition by AdId; ⭐⭐ salt hot ads AdId:0..N)
                                                  ⭐ 7-day retention · ≥10 shards      02c
                                                      │                 │
                                                      ▼                 ▼ Firehose / Connect S3 sink
                                            Flink (event-time windows,   Raw click data (S3)        ⭐⭐⭐ the truth
                                            watermarks; flush every few s)      │
                                                      │                         ▼ daily
                                                      │               Spark re-aggregation + Reconciliation Worker
                                                      ▼                         │ fixes records
                                               OLAP DB  ◄───────────────────────┘      ⭐⭐ minute table + nightly rollups
                                                      ▲
                           Analyst browser ──► Analytics Service

📐 10k/s peak ≈ 1 MB/s  ·  ⊕ ≥10 Kinesis shards (1000 records/s each)  ·  📐 batch 3M × 100 B = 300 MB
⊕ I added: signed impressionId in the click URL · SET NX + TTL · impressionId on the stored event · two-phase aggregation for salted keys
```

---

## 7 · Expected at Each Level

|Level|The bar for Ad Click Aggregator|
|---|---|
|**Mid-level**|**80/20. Meet the FRs; expect probing on what each component does. See why to pre-aggregate and at least propose batch; handle probing on idempotency and database choices.**|
|**Senior**|**60/40. Speed through the HLD; spend time on scaling, click-to-query latency, fault tolerance. Know how batch uses map-reduce and how Flink works; contrast real-time with batch; pick a couple of deep dives.**|
|**Staff+**|**40/60, from real experience. Weigh batch vs real-time processing and the implications; a fault-tolerant solution; the trade-offs between database choices and storage strategies and their effect on performance and scalability. Drive deep on chosen areas, and ideally teach the interviewer something new.**|

> ⚠ **HI's Mid-level bar says "propose a batch solution". Batch already has the Cassandra range-scan problem (§4.2) and the unique-count problem. Name them and you read as above the bar.**
> 
> ■ **— end of insert · HI write-up resumes below —**

---

## Quick Recall (pass 3+)

|Use / Question|Ad Click Aggregator answer|
|---|---|
|Calibration|**Evan King · updated Feb 2026 · ⭐⭐ "hard" · Asked at Rippling, W +4 (⭐ Rippling is on the list) · ⭐⭐ pattern: `03e` Scaling Writes.** ⭐⭐ **TWO passes. Order: HLD ladder > DD3 > DD2 > DD1 > DD4**|
|⭐⭐⭐ Design driver|⭐⭐⭐ **A write-heavy firehose that must be queryable within a minute, counted once, and never lost.** **10k/s ⇒ stream + pre-aggregate · sub-second reads ⇒ OLAP · minute freshness ⇒ Flink windows + flush interval · no lost click ⇒ replicated stream + retention + S3 + reconciliation · count once ⇒ signed impression ID + pre-stream cache · one hot ad ⇒ salted key + merge**|
|📐 Numbers|**10M ads · 10k/s peak · ~1k/s average · ~100M/day (86.4M exactly).** **Batch: 10k × 300 s = 3M events × 100 B = 300 MB.** ⊕ **Kinesis 1 MB/s or 1000 rec/s per shard ⇒ ≥10 shards.** **Cache: 100M × 16 B = 1.6 GB raw; ⚠ ~10 GB with real Redis overhead.** 📐 **~10 clicks per ad per day ⇒ sparse buckets.** **Open-window state ≤ ~600k keys**|
|FRs / NFRs|**Click an ad and be redirected · query click metrics, ≥1-minute granularity.** Below: targeting, serving, cross-device, offline. **NFRs: ⭐⭐ scale to 10k/s peak · ⭐⭐ sub-second queries · ⭐⭐⭐ no lost clicks · ⭐⭐ as real-time as possible · ⭐⭐⭐ idempotent (count once).** Below: fraud, demographics, conversion. ⚠ **Lost-click and count-once pull in opposite directions**|
|Interface + data flow|⭐ **No API: input = ad click data; output = click metrics. Flow: click → tracked and stored → redirect → advertiser queries.** ⚠ **If the store must finish first, the lost-click NFR costs redirect latency**|
|Entities|**Advertisement (AdId, RedirectUrl, metadata) · Ad Click Event (eventId, adId, userId, timestamp) · Aggregated Data (AdId, Minute, Click Count).** ⚠⚠ **The event needs `impressionId`, or reconciliation can't dedupe**|
|⭐⭐ §4.1 — redirect|⚠ **A: ship the URL, POST `/click` in parallel — simple, but users or extensions can bypass tracking.** ⭐⭐⭐ **B (pick): click hits our `/click`, we track it, answer 302 — every click seen; extra complexity and latency.** ⚠⚠ **Open: if the stream write fails, do we still redirect? "No lost click" needs a replicated ack before the 302. The signed ID must ride in the GET's query string**|
|⚠⚠ §4.2 — Bad: store + GROUP BY|**Raw events in one DB; `COUNT(*) … GROUP BY` at query time.** ⚠⚠ **HI: "at our scale, this solution sucks" — 10k writes/s and a slow GROUP BY break sub-second reads**|
|⭐⭐ §4.2 — Good: Cassandra + Spark + OLAP|**Flow: click → Click Processor → event store → cron runs Spark every N min → OLAP → advertisers query.** **Cassandra (LSM: commit log, memtable, SSTables) stores raw events; cron runs Spark (map-reduce) every N minutes; OLAP (Redshift, Snowflake, BigQuery, Druid) stores `(AdId, minute, count)`. 300 MB per batch — one machine could do it.** ⭐⭐ **OLAP, not TSDB: high cardinality, many dimensions; a TSDB is fine for one metric over low-cardinality time ranges.** ⚠⚠ **Challenges: batch delay of minutes; a spike makes the next batch longer than its interval**|
|⚠⚠ §4.2 — Good: loose ends|⚠⚠ **"Read the last 5 minutes from Cassandra" is a range scan: needs a time-bucket key (hot partition) or a full scan; HI's reason is circular.** ⚠ **Cron "every minute" in the diagram vs "5 minutes" in the text.** ⚠⚠ **Unique users are not additive: the schema has one count column but the SQL returns distinct users. ⊕ HyperLogLog (`04b`)**|
|⭐⭐⭐ §4.2 — Great: stream + Flink|**Flow: click → Click Processor → stream → Flink/Spark Streaming aggregates in real time → OLAP → advertisers query in near real time.** **Click Processor writes to Kafka/Kinesis; Flink aggregates with event-time windows, watermarks, exactly-once and state recovery; flush to OLAP.** ⭐⭐⭐ **HI: latency vs the batch rung is "not all that different" at equal windows — the gain is the levers: a window of a few seconds, or a minute boundary with a flush every few seconds (the latest minute is just incomplete). Spark can't run every few seconds.** ⭐ **Plain consumers are fine at mid-level**|
|⚠⚠ DD1 — scale|⭐ **Click Processor: scale out behind an LB. Stream: Kinesis 1 MB/s or 1000 rec/s per shard, shard by AdId; Flink: a job per shard; OLAP: managed scales itself; ClickHouse: shard by AdvertiserId.** 📐 ⊕ **≥10 shards; ~1 MB/s total — a small system**|
|⭐⭐⭐ DD1 — hot shards|⭐⭐ **A viral ad (Nike + LeBron) overloads one shard ⇒ salt the key `AdId:0..N` for popular ads; Flink strips the suffix and writes under the real AdId.** ⚠⚠ **HI: "upserts with SUM" conflates overwrite with additive merge; replays double-count. ⊕ Two-phase aggregation (local per salt, then global per AdId), or sum at query time.** ⚠ **Can't predict viral ads from spend ⇒ salt on a rate threshold. ⚠ OLAP key shows PK=AdvertiserId, SK=Minute — AdId is missing; PK/SK is DynamoDB vocabulary; advertiserId needs an enrichment join**|
|⭐⭐⭐ DD2 — no lost clicks|⭐⭐ **Stream replicated (Kafka across brokers, Kinesis across AZs) + 7-day retention ⇒ a dead processor replays.** ⭐⭐⭐ **Checkpointing: HI says unnecessary for 1-minute windows (lose ≤ 1 minute, replay) — and calls pushing back a seniority signal.** ⭐⭐⭐ **Reconciliation: dump raw events to S3 (Kafka Connect S3 sink or Kinesis Firehose); a daily Spark job re-aggregates, compares with OLAP, a worker fixes records. This is a Lambda architecture: speed layer (Flink) + batch layer (Spark = truth)**|
|⚠⚠ DD2 — loose ends|⚠⚠ **"Exactly-once + state recovery" (the Flink pick) IS checkpointing; DD2 says skip it. Choose one story.** 📐 **State is ≤ ~600k keys, cheap to checkpoint; replay needs an idempotent (overwrite) sink.** ⚠⚠ **Reconciliation can't catch cache-failure duplicates unless events carry `impressionId`, can't recover clicks lost before the stream, can race with streaming writes ⇒ reconcile only closed windows.** ⚠ **Lambda's two-code-paths drift goes unmentioned**|
|⭐⭐⭐ DD3 — Good: login + (userId, adId)|⭐ **Require login; dedupe on userId + adId from JWT/cookie.** ⚠⚠ **Needs login (a product decision); counts one click per user per ad ever — breaks retargeting. HI amends the problem to "one click per user per ad instance". Dedupe must happen BEFORE the stream: a duplicate across a minute boundary would count twice**|
|⭐⭐⭐ DD3 — Great: signed impression ID|⭐⭐⭐ **Ad Placement Service mints a unique ID per rendered ad instance and signs it together with the adId via HMAC (microseconds; stops forgeries and cross-ad replay). The browser sends it back on click; the Click Processor verifies, checks the cache, writes to the stream FIRST, then adds the ID to the cache.** ⭐ **Stream first: a duplicate beats a lost click.** 📐 **100M × 16 B = 1.6 GB; Redis Cluster + replica + RDB/AOF**|
|⚠⚠ DD3 — loose ends|⚠⚠ **Check-then-write is a race ⇒ ⊕ atomic `SET NX EX`; trade-off: crash after SET loses a click (compensate with DEL, or dedupe in batch).** ⚠⚠ **No TTL stated: a replay after expiry counts again ⇒ ⊕ put a timestamp in the signed payload (Payment System nonce window).** ⚠ **Flink keyed state with TTL CAN dedupe across windows; the real cost is a Redis hop on the redirect path.** ⚠ **1.6 GB is raw; ~10 GB real. Harvesting IDs via page loads is fraud (out of scope)**|
|⭐⭐ DD4 — query latency|⭐ **Already low: data is pre-aggregated in OLAP.** ⭐⭐ **Long ranges: nightly cron builds daily/weekly rollup tables; query the rollup, drill down to minutes. HI: like caching — trade storage for speed.** ⚠⚠ **Today is stale in a nightly rollup ⇒ UNION with the minute table; distinct counts don't roll up; most buckets are sparse (~10 clicks per ad per day)**|
|⭐⭐⭐ The meta-lesson|⭐⭐⭐ **Four ideas outlive this problem: (1) mint the dedupe identity at the source, sign it, verify it at the sink (and make the check atomic); (2) the raw log is the truth, aggregates are derived and recomputed — a fast tier decides, a durable tier remembers; (3) a hot key can be salted, but a salted key owes a merge; (4) don't add machinery the size doesn't need (checkpointing, a Spark cluster for 300 MB) — but know what guarantee it was buying**|
|Levels (one line)|**Mid (80/20):** see why to pre-aggregate; propose batch · **Senior (60/40):** real-time vs batch, Flink basics, pick a couple of deep dives · **Staff+ (40/60):** weigh batch vs real-time, a fault-tolerant design, database and storage trade-offs; teach the interviewer something|

---

> 🔗 **HI source:** https://www.hellointerview.com/learn/system-design/problem-breakdowns/ad-click-aggregator