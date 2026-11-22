# FB Post Search — Problem Breakdown

> 📐 **Revision note (calc):** **1B users · 1 post and 10 likes per user per day · HI rounds a day to 100k s ⇒ 10k posts/s · 100k likes/s · 10k searches/s (bursts 10×+).** 📐 **Storage: 1B posts/day × 365 × 10 years = 3.6T posts × 1 KB = 3.6 PB.** 📐 ⊕ **My index maths (HI never does it): 10k posts/s × ~100 keywords × 2 indexes = 2M index writes/s. A like must update the post's score under EVERY keyword ⇒ 100k likes/s × ~100 = 10M sorted-set updates/s. Index size: 3.6T posts × 100 keywords × 8 B id ≈ 2.9 PB per index, ~5.8 PB for two — in RAM.**

> Common Problems · **Stefan Mai, published Jul 5, 2024** · ⭐⭐ **"hard"** · **Asked at: LinkedIn, Amazon** · ⭐⭐ **Patterns: `Scaling Reads` → `03d` · `Scaling Writes` → `03e`** · Cross-refs: ⭐⭐⭐ **Distributed Cache (12) — caching, hot keys, DD5 write batching** · ⭐⭐ **Ad Click (25) — pre-aggregation, batch windows** · ⭐⭐ **Rate Limiter (13) — Redis sorted sets** · **`02a` Redis · `02c` Kafka · `02d` Elasticsearch (inverted index) · `04b` Count-Min Sketch.**
> 
> **Calibration:** ⭐⭐ **TWO passes (my call): "hard", infrastructure-style, and the index arithmetic HI skips is where an interviewer will push.** ⭐ **Order: §4.2 (inverted index) > §4.3 (two indexes) > DD3 (writes) > DD4 (storage) > DD2 (phrases) > DD1 (caching).**
> 
> - ⭐⭐ **What actually scores:** **(a)** ⭐⭐⭐ **noticing it's WRITE-heavy (likes 10× posts, both above searches)** · **(b)** ⭐⭐⭐ **the inverted index, from scratch** · **(c)** ⭐⭐⭐ **one index per sort order: list for time, sorted set for likes** · **(d)** ⭐⭐ **caching unpersonalised queries with TTL < freshness SLA, plus a CDN** · **(e)** ⭐⭐ **phrases: intersection vs bigrams** · **(f)** ⭐⭐⭐ **likes: batching, then milestone writes + two-stage re-rank** · **(g)** ⭐⭐ **storage: cap lists, move cold keywords to blob storage.**
> - ⭐ **Transferable primitives:**
>     - ⭐⭐⭐ **Organise data the way it will be queried — precompute the answer's shape (an index per sort order).**
>     - ⭐⭐⭐ **Approximate cheaply in storage, then re-rank a small candidate set exactly (two-stage retrieval).**
>     - ⭐⭐ **A freshness SLA is a cache TTL budget.**
>     - ⭐⭐ **Write less often: batch, or write only at milestones.**
>     - ⭐⭐ **Hot in memory, cold in blob storage.**
> - ⭐ **Re-run (cross-ref only):** **caching, CDN, TTL (Distributed Cache) · write batching (Distributed Cache DD5) · Kafka buffering (Ad Click) · Redis sorted sets (Rate Limiter).** **Genuinely new:** ⭐⭐⭐ **inverted index + tokenization** · ⭐⭐⭐ **two-stage retrieval** · ⭐⭐ **bigrams / shingles** · ⭐⭐ **hot/cold index tiering.**

---

## 0 · Understanding the problem

💬 **Facebook is a social network built around posts that users read in a timeline, and can reply to, like or share.** ⭐ **We design only SEARCH over posts — an infrastructure-style question about data layout, indexing and scaling.**

⭐⭐⭐ **The twist: the interviewer forbids Elasticsearch or any pre-built full-text index (e.g. Postgres full-text). HI: this really happens — it tests the fundamentals of data organisation, not a product.**

---

## 1 · Requirements

### 1.1 Functional

1. ⭐⭐ **Users can create and like posts.**
2. ⭐⭐⭐ **Users can search posts by keyword.**
3. ⭐⭐⭐ **Users can get results sorted by recency or like count.**

⚠ **Below the line:** **Fuzzy matching ("bird" → "ostrich") · Personalisation · Privacy rules and filters · Sophisticated relevance ranking · Images and media · Real-time updates to the results page.** ⭐⭐ **HI: dropping personalisation simplifies everything and makes caching effective — ask whether it's firm.**

### 1.2 Non-functional

1. ⭐⭐ **Fast: median query < 500 ms.**
2. ⭐⭐ **High request volume (estimated below).**
3. ⭐⭐⭐ **Fresh: a new post is searchable in < 1 minute.**
4. ⭐⭐ **All posts discoverable, including old or unpopular ones — these may take longer.**
5. ⭐ **Highly available.**

⭐⭐ **HI: lots of data usually means HOT data (served fast, from memory) and COLD data (disk, remote DB, even tape). NFR 4's "more time for old posts" foreshadows that split.**

### 1.3 Scale estimates

⭐⭐ **The common mistake is to assume search means reads dominate. Estimate first.** **Assume 1B users, each making ~1 post (20% post 5, 80% post none) and 10 likes per day; round a day to 100k seconds.**

- 📐 **Posts: 1B × 1 ÷ 100k = 10k/s.**
- 📐 **Likes: 1B × 10 ÷ 100k = 100k/s — 10× posts; say so out loud.**
- 📐 **Searches: 1B × 1 ÷ 100k = 10k/s (bursts 10×+).** ⭐⭐⭐ **⇒ the system is WRITE-heavy.**
- 📐 **Storage: 10 years × 365 × 1B posts/day = 3.6T posts; at 1 KB each = 3.6 PB. We must constrain it.**

▹ **HI: estimate to shape the design and say how each number changes it — never estimate for its own sake.**

> ⚠⚠ **What HI leaves loose — the numbers that matter are the INDEX numbers.**
> 
> - ⚠⚠ **A post with ~100 keywords is ~100 index writes, twice (two indexes) ⇒ 📐 ⊕ ~2M writes/s, not 10k.**
> - ⚠⚠ **A like changes the score under every keyword of that post ⇒ 📐 ⊕ 100k × ~100 ≈ 10M sorted-set updates/s. This is why DD3's like fixes are the heart of the problem.**
> - ⚠ **3.6 PB is post content. The index is a separate cost: 📐 ⊕ ~2.9 PB of 8-byte ids per index, in Redis. DD4's caps are not optional.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 1.4 ⭐⭐⭐ The design driver — find posts by word in trillions, sorted two ways, under a write firehose

|Constraint|What it breaks|Fixed by|
|---|---|---|
|⭐⭐⭐ **no search engine allowed**|**`LIKE '%word%'` scans everything**|**our own inverted index (§4.2)**|
|⭐⭐⭐ **sort by time or likes**|**sorting millions of ids per request**|**one index per order (§4.3)**|
|⭐⭐ **10k searches/s, same queries**|**re-running every search**|**cache with TTL < 1 min + CDN (DD1)**|
|⭐⭐ **phrase queries**|**intersecting huge lists**|**bigrams for common phrases (DD2)**|
|⭐⭐⭐ **likes 10× posts, ~100 keys each**|**updating every keyword per like**|**batching, milestones + two-stage re-rank (DD3)**|
|⭐⭐ **3.6T posts**|**everything in RAM**|**capped lists + cold blob storage (DD4)**|

### 1.5 Planning the approach

⭐ **Solve the FRs one by one, then come back to scale and NFRs in the deep dives; keep checking against the requirements.**

---

## 2 · Core Entities

- **User** — **creates posts.**
- **Post** — ⭐ **what we search: content, author, and implicitly a like count.**
- **Like** — ⭐ **created when a user likes a post; we mostly care about the COUNT.**

---

## 3 · API

```
GET  /search?query=THE_QUERY&sort_order=LIKES|TIME
POST /post
POST /post/{id}/like
```

- ⭐⭐ **Two paths: a QUERY path (search) and a WRITE path (posts, likes). Writes land in a database; searches read from it.**
- ⭐ **In reality both writes would probably arrive as events on Kafka; separate endpoints are just clearer — tell the interviewer.**
- ⚠ ⊕ **Gaps: no pagination (`cursor`, `limit`) for millions of hits · search returns post ids, so posts must be hydrated from the Post Service · no edit or delete — deleted posts must leave the index.**

---

## 4 · High-Level Design

### 4.1) Users can create and like posts

⭐ **Search is part of a bigger product, so assume an internal Post Service and Like Service already take client requests. They send creates and likes to our Ingestion Service, which writes the Index (Post: content, likes).**

⭐ **Post and like rates differ a lot, but ingestion is simple for now: one service, and flag the concern.** ▹ **HI: name the over-simplification out loud — interviewers assume unacknowledged flaws went unseen.**

### 4.2) Users can search posts by keyword

⭐ **Read side: API Gateway (auth, rate limiting) → a horizontally scaled Search Service → the Index. The Index does the real work: find every post containing a keyword, across trillions of posts.**

#### ⚠⚠ Bad — a relational DB with `LIKE '%keyword%'`

**What it is:**

- ⭐ **All posts in MySQL; search runs `SELECT * FROM Posts WHERE content LIKE '%keyword%'`. Technically correct.**

**Challenges:**

- ⚠⚠ **Terribly slow: every query scans every post's content at query time. Databases are fast only when data is organised like the queries — with no index, petabytes means pain.**
- ⚠⚠ **Sharding or replication only divides the scan: N posts over M nodes is still N/M per node. A dead end.**

**Why climb:** ⭐ **organise the data by keyword ahead of time.**

#### ⭐⭐⭐ Great — an inverted index in Redis

**What it is:**

- ⭐⭐⭐ **A dictionary from each keyword to the ids of the posts containing it: `Taylor → [1, 5, 10]`, `Boat → [2, 5, 13]`. A search is one key lookup.** ▸ **Same structure as inside Elasticsearch (`02d`).**
- ⭐⭐ **Store it in Redis — in memory, so lookups are very fast. Durability is a concern but solvable (MemoryDB, or a deep dive).**
- ⭐⭐ **Write side: the Ingestion Service TOKENISES each post (splits it into every keyword it could match) and appends the post id to each keyword's list.**

**Flow:**

- **Write:** ① **post arrives** ② **tokenise** ③ **append the post id to each keyword's list.**
- **Read:** ① **look up the keyword** ② **return its post ids.**

**Challenges:**

- ⚠⚠ **Lists for common words get huge — handled later (DD4).**
- ⚠⚠ **Each post writes 10–1,000 keys — a scaling problem (DD3).**

> ⚠ **What HI leaves loose.**
> 
> - ⚠⚠ **Tokenising needs stop-word removal ("the", "a" would list nearly every post) and normalisation (lower-case, maybe stemming).**
> - ⚠ **The index returns ids only; showing results needs a hydration call to the Post Service — part of the 500 ms budget.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 4.3) Users can get results sorted by recency or like count

⭐ **"Taylor" by recency ⇒ newest posts first; by likes ⇒ most-liked first.**

#### ⚠⚠ Bad — sort at request time

**What it is:**

- ⭐ **Fetch all ids for the keyword, look up each post's timestamp or like count from the Post Service, sort in the Search Service, return.**

**Challenges:**

- ⚠⚠ **"Taylor" may have tens of millions of ids — a payload of hundreds of MB from the index.**
- ⚠⚠ **Then tens of millions of lookups, one per id.**
- ⚠ **Then sorting millions of items per request adds latency. HI: "not great".**

**Why climb:** ⭐ **store the ids already in the order we will read them.**

#### ⭐⭐⭐ Great — two indexes, one per sort order

**What it is:**

- ⭐⭐⭐ **A CREATION index and a LIKES index, as separate Redis keys per keyword.**
- ⭐⭐ **Creation index: a plain Redis LIST — always append, always read from the end.**
- ⭐⭐ **Likes index: a Redis SORTED SET scored by like count — ordered like a priority queue, with the same insert and query complexity.**
- ⭐⭐ **New post ⇒ add it to BOTH indexes for every keyword. New like ⇒ update the post's score in the likes index.**

💬 **Example — one Redis key per keyword per sort order, each holding many post ids:**

```
Creation index                      Likes index
key:   creation:taylor              key:   likes:taylor
value: Redis List                   value: Redis Sorted Set
       [post_9, post_6, post_2]            member=post_2  score=12
        oldest ───────► newest             member=post_6  score=450
                                           member=post_9  score=81
```

- ⭐⭐ **Creation: a new post containing "taylor" is APPENDED, so the newest id is at the end; the Search Service reads from the end ⇒ newest first.**
- ⭐⭐ **Likes: one key, many members; each member is a postId and its score is that post's like count. Redis keeps members ordered by score, so asking for the highest scores returns post_6 (450), post_9 (81), post_2 (12).**
- ⭐⭐ **Fan-out: a post "Taylor Swift concert" adds its id to THREE creation lists and THREE likes sorted sets — one per word.**

**Challenges:**

- ⚠ **Index storage doubles — worth it for the query speed, but it costs.**
- ⚠⚠ **Likes are frequent, and each like updates MANY scores (one per keyword) — stress to address in DD3.**

> ⚠ **What HI leaves loose.**
> 
> - ⚠ **"Append and read the end" assumes posts arrive in creation order; a delayed event from Kafka lands out of place.** ⊕ **A sorted set scored by timestamp is safe for both.**
> - ⚠ **A sorted set costs far more memory per entry than a list of 8-byte ids — the likes index is the expensive one.**
> 
> ■ **— end of insert · HI write-up resumes below —**

---

## 5 · Deep Dives

⭐ **Anchor the dives on the bottlenecks you already flagged; some interviewers quiz you, others expect you to find your own gaps.**

### 1) How can we handle the large volume of requests from users?

⭐⭐ **The in-memory index is fast, but traffic is high. Two requirements help: no personalisation (same query ⇒ same results for everyone), and up to 1 minute before a post must appear. Stale-tolerant + duplicate requests ⇒ CACHE.**

> ⭐⭐ **Pattern: Scaling Reads (`03d`)** — **caching is the main tool when reads must scale.**
> 
> ■ **— end of insert · HI write-up resumes below —**

#### Good — a distributed search cache (Redis)

**What it is:**

- ⭐⭐ **A cache beside the Search Service holds recent results per query. Hit ⇒ return it; miss ⇒ run the search and store the result.**
- ⭐⭐⭐ **Eviction by TTL: with a 1-minute freshness SLA, set TTL < 1 minute, so we never serve results missing a newly created post.**

**Why climb:** ⭐ **answer even closer to the user.**

#### ⭐⭐⭐ Great — add a CDN in front

**What it is:**

- ⭐⭐ **A CDN (Cloudflare, CloudFront) is a set of geographically spread HTTP caches: point it at an origin, route DNS through it; a hit returns from a nearby location, a miss is proxied to our servers.**
- ⭐⭐ **On `/search` responses, set cache-control headers saying how long to cache. A hit costs tens of milliseconds instead of hundreds (gateway → search service → cache → back).**

> ⚠⚠ **What HI leaves loose.**
> 
> - ⚠⚠ **TTL < 1 minute does NOT guarantee freshness on its own: a new post first waits in Kafka and the like batcher (DD3), then sits behind a cached result for up to the TTL.** ⊕ **Freshness ≈ ingestion lag + CDN TTL + Redis cache TTL; the SUM must stay under a minute — e.g. 20 s of ingestion, 20 s per cache layer.**
> - ⚠ **Query normalisation (lower-case, sorted terms, sort order in the key) raises the hit rate; long-tail queries will mostly miss anyway.**
> - ⚠ **A CDN hit skips the API Gateway — fine for unpersonalised results, but rate limiting and auth no longer see those requests.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 2) How can we handle multi-keyword, phrase queries?

⭐ **"Dog" is easy; "Taylor Swift" or "All your base are belong" are not. Full boolean query languages exist ("+Taylor +Swift -Red"); assume just multi-word phrases.**

#### Good — intersect the keyword lists

**What it is:**

- ⭐⭐ **The least invasive change. For "Taylor Swift" by likes: ① fetch the post ids for "Taylor" and for "Swift" ② intersect them ③ load each surviving post and check it really contains the phrase (not "my friend Taylor made a swift exit") ④ return those that pass, in order.**

**Challenges:**

- ⚠⚠ **Both lists may hold millions of ids — megabytes over the network, built into a hash table and intersected; hard inside 500 ms.**
- ⚠ **Worst case: heavy overlap but few true phrases ⇒ lots of expensive filtering for nothing.**

**Why climb:** ⭐ **index the phrase itself so the read is one lookup.**

#### ⭐⭐ Great — index bigrams ("shingles")

**What it is:**

- ⭐⭐ **Also index each pair of adjacent words. "I saw Taylor Swift at the concert" ⇒ "I saw", "saw Taylor", "Taylor Swift", "Swift at", "at the", "the concert" — into both the likes and creation indexes. "Taylor Swift" is now one key lookup, no intersection.**

**Challenges:**

- ⚠⚠ **The index grows a lot: bigrams per sentence are linear in words, but bigrams are far more UNIQUE ("Swift at" is rare), so keys are sparse — ~10M single-word keys may become 100M+.**
- ⭐ **Mitigation: index only bigrams likely to be searched (estimate frequency with a Count-Min Sketch, `04b`), and fall back to intersection when no bigram key exists. More complexity again.**

> ⚠ **What HI leaves loose.**
> 
> - ⚠ **Bigrams answer two-word phrases. A longer phrase still needs an intersection of its bigrams plus the content check.**
> - ⊕ **Textbook alternative: a positional index (store word positions per post) answers any phrase, at a storage cost.**
> - ⚠ **Each bigram is one more key per word of every post: the write fan-out of DD3 roughly doubles.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 3) How can we address the large volume of writes?

⭐ **Two sources: post creation and likes.**

#### Post creation — buffer and partition

- ⭐⭐ **Ingestion tokenises each post and writes its id into both indexes: a 100-word post ⇒ 100+ writes. A burst can overwhelm ingestion and, at worst, lose posts or events.**
- ⭐⭐⭐ **Fix: put Kafka in front ⇒ fan out to many ingestion instances, partition the load, and buffer bursts. Shard the indexes by KEYWORD so writes spread across many Redis instances.**

> ⭐⭐ **Pattern: Scaling Writes (`03e`)** — **a frequent deep-dive; keep a toolkit for it.**
> 
> ■ **— end of insert · HI write-up resumes below —**

> ⚠⚠ **What HI leaves loose — sharding by keyword has a real cost.**
> 
> - ⚠⚠ **Sharding by keyword is a TERM-partitioned index: each post's ~100 keywords live on ~100 different shards, so one post ⇒ ~100 network writes. Popular words ("love") make HOT shards.** ⊕ **The textbook alternative is DOCUMENT-partitioning (each shard indexes its own posts): a write touches ONE shard, but every query is scatter-gather over all shards and merges top-N. Search engines usually partition by document. Name the trade-off.**
> - ⚠ **Phrase intersection (DD2) across two keyword shards is a cross-network join.**
> 
> ■ **— end of insert · HI write-up resumes below —**

#### Likes — the elephant in the room

⭐⭐ **Each like means many index writes, and likes are 10× posts. How do we write less?**

#### Good — batch likes per post

**What it is:**

- ⭐⭐ **Aggregate likes for a postId over a window (say 30 s), then write once: a viral post with 500 likes in the window is ONE update of +500, not 500.**
- ⭐ **A separate Like Batcher consumes like events, aggregates per window, and writes the batch back to Kafka for ingestion.**

**Challenges:**

- ⚠⚠ **Helps only viral posts. Most posts aren't viral: a post with 1 like per minute (1,440 a day) gains nothing from a 30 s window — still one write per like — and the batcher adds overhead.**

**Why climb:** ⭐ **cut writes for ordinary posts too.**

#### ⭐⭐⭐ Great — write only at milestones, then re-rank (two-stage)

**What it is:**

- ⭐⭐⭐ **Update the index only when a post's count crosses a milestone — powers of 2 (or 10): at 1, 2, 4, 8 … likes. 1,000 likes ⇒ ~10 writes, not 1,000.**
- ⭐⭐ **The trade-off: the index is now STALE — counts can't be trusted, but ORDER is roughly right (10k likes still beats 1).**
- ⭐⭐⭐ **To return N results: take the top 2N from the likes index, ask the Like Service for each one's CURRENT count, sort by that, return N.**
- ⭐⭐⭐ **Storage is approximate, the answer is exact. This two-stage shape — a cheap approximate stage, then an expensive precise re-rank — is standard in information retrieval and recommendation.**

💬 **Example — Redis is only a cheap shortlist; the Like Service has the exact counts.** **The Like Service records every like; `likes:taylor` in Redis is updated only at milestones:**

```
Actual likes (Like Service)     Index score (Redis likes:taylor)
1                               update to 1
2                               update to 2
3                               stays 2
4                               update to 4
5, 6, 7                         stays 4
8                               update to 8
...
1000                            last update was at 512   (writes at 1, 2, 4, 8 … 512 ⇒ 10 writes)
```

- ⭐⭐ **A post with 1,000 real likes may sit in Redis at 512 — stale, but still high enough to place popular posts near the top.**
- ⭐⭐⭐ **Top 10 results: fetch the top 20 ids from Redis ⇒ ask the Like Service for their real counts ⇒ sort those 20 by real count ⇒ return the best 10.**
- ⭐⭐⭐ **Redis finds the likely winners cheaply; the Like Service makes the final order correct.**

**Flow:**

- ① **Query the likes index for the top 2N ids.**
- ② **Fetch fresh like counts from the Like Service.**
- ③ **Re-sort by those counts and return the top N.**

**Challenges:**

- ⚠ **More complex; more engineering effort.**
- ⚠ **The index's like counts change meaning — name the field `logLikes` or `approxLikes` so developers aren't misled.**

> ⚠⚠ **What HI leaves loose.**
> 
> - ⚠⚠ **Is 2N enough? With powers of 2, a post's stored count can be up to ~2× below its true count, so a post just under a milestone can rank below N×2 and never reach the re-rank.** ⊕ **Over-fetch more (or use finer milestones, e.g. powers of 1.5); the re-rank only fixes order INSIDE the candidate set.**
> - 📐 ⊕ **Milestones cut ~10M updates/s (my estimate) by orders of magnitude, since most posts stop at a few milestones. Batching + milestones together cover both viral and ordinary posts.**
> - ⚠ **Step ② is 2N calls to the Like Service per query (and per page) — batch them; it eats into 500 ms.**
> - ⚠ **HI writes "Elasticsearch" here although the problem forbids it — he means our Redis index.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 4) How can we optimize storage of our system?

⭐⭐ **We index a huge amount, but users care about a vanishingly small part.**

- ⭐⭐⭐ **Cap each inverted list: we don't need all 10M posts containing "Mark". Keep 1k–10k per keyword ⇒ orders of magnitude less storage.**
- ⭐⭐⭐ **Move cold keywords out: most keywords are rarely or never searched. From search analytics, a monthly batch job moves keywords not queried in the past month from Redis to cheap blob storage (S3, R2).**
- ⭐⭐ **Read path: try Redis; on a miss, read the keyword's index from blob storage, with a small latency penalty.**

> ⚠⚠ **What HI leaves loose — the cap breaks a requirement.**
> 
> - ⚠⚠ **Capping lists at 1k–10k contradicts NFR 4, "all posts discoverable, including old or unpopular ones": the 10,001st post for "Mark" is now unfindable.** ⊕ **Keep the newest / top entries in Redis, and the FULL list in blob storage; serve deep pages from the cold tier. That is the hot/cold split HI foreshadowed in §1.2, applied within a keyword.**
> - ⚠ **Cold keywords hold only their posts' ids — the newest posts for a cold keyword still get written somewhere.** ⊕ **New writes for a cold keyword go to Redis again (or an append log merged into the blob later).**
> - ⚠ **A capped likes index can't admit a post whose likes climb later — it needs eviction of the lowest score when a newcomer passes it (a sorted set makes that cheap: `ZREMRANGEBYRANK`).**
> 
> ■ **— end of insert · HI write-up resumes below —**

---

## 6 · Final Design

⚠ **Layout is mine; components are HI's.** ⭐ **HI: most candidates, especially mid-level, won't get through every deep dive.**

```
Post Service ─┐                                        ⭐⭐⭐ two-stage: top 2N ──► Like Service (fresh counts)
              ├─► Kafka ─► Ingestion Service × N ─► Index (Redis, sharded by keyword)
Like Service ─┘     ▲      tokenise (+ bigrams)        ├─ Creation: keyword → [postIds] (list)
     │              │                                  └─ Likes:    keyword → sorted set (⭐⭐ milestone scores)
     └─► Like Batcher (30 s windows) ─┘                     │  rarely searched keywords ▼ (monthly job)
                                                       Cold indexes (blob storage)
Client ─► CDN (cache-control) ─► API Gateway ─► Search Service ─► Search Cache (Redis, TTL < 1 min)
                                                      └─► Index (Redis) ─miss─► Cold indexes

⊕ freshness budget: ingestion lag + CDN TTL + cache TTL < 1 min
⊕ full lists kept in blob storage (NFR 4) · stop-words removed · hydrate posts from Post Service
```

---

## 7 · Expected at Each Level

|Level|The bar for Post Search|
|---|---|
|**Mid-level**|**80/20 breadth. Clearly defined API and data model, with BOTH sides built: ingestion and query. Expect probing on basics (e.g. your cache's eviction policy). Starting from a "Bad" solution is fine if the discussion is good; you needn't jump straight to Great.**|
|**Senior**|**60/40. Speed through the HLD to spend time optimising the critical paths. Write volume, storage and duplicate queries should jump out at you. Minimum: ingestion and query detailed, a proper inverted index, and a sensible caching strategy.**|
|**Staff+**|**40/60, "been there, done that". Get through several deep dives with insight and optimal solutions; the measure is whether the interviewer learns something new. Many valid ways to solve it.**|

---

## Quick Recall (pass 3+)

|Use / Question|FB Post Search answer|
|---|---|
|Calibration|**Stefan Mai · Jul 2024 · ⭐⭐ "hard" · Asked at LinkedIn, Amazon · ⭐⭐ `03d` Scaling Reads + `03e` Scaling Writes.** ⭐⭐ **TWO passes. Order §4.2 > §4.3 > DD3 > DD4 > DD2 > DD1.** ⭐⭐⭐ **No Elasticsearch or built-in full-text allowed — build it**|
|⭐⭐⭐ Design driver|⭐⭐⭐ **Find posts by word in trillions, sorted two ways, under a write firehose.** **No engine ⇒ own inverted index · two sort orders ⇒ two indexes · repeated unpersonalised queries ⇒ cache TTL < 1 min + CDN · phrases ⇒ bigrams · likes ⇒ batching + milestones + re-rank · 3.6T posts ⇒ capped lists + cold blobs**|
|📐 Numbers|**1B users; 100k s/day; 10k posts/s · 100k likes/s · 10k searches/s (bursts 10×) ⇒ WRITE-heavy. 3.6T posts × 1 KB = 3.6 PB.** ⊕ **~100 keywords × 2 indexes ⇒ ~2M index writes/s for posts; likes ~10M score updates/s; index ids ≈ 2.9 PB per index**|
|FRs / NFRs|**Create and like posts · search by keyword · sort by recency or likes.** Below: fuzzy, personalisation, privacy, relevance, media, live updates. **NFRs: ⭐⭐ median < 500 ms · ⭐⭐ high volume · ⭐⭐⭐ searchable < 1 min · ⭐⭐ all posts discoverable (old ones may be slower) · ⭐ HA.** ⭐⭐ **Dropping personalisation is what makes caching work**|
|Entities + API|**User · Post (content, implicit like count) · Like (we need the count).** `GET /search?query=&sort_order=LIKES/TIME` · `POST /post` · `POST /post/{id}/like`; in reality events on Kafka. ⚠ **No pagination; ids need hydrating; no delete/edit path**|
|⭐⭐ §4.1 — ingestion|**Assume Post and Like Services exist; they feed one Ingestion Service that writes the index. Flag that it's oversimplified**|
|⭐⭐⭐ §4.2 — search ladder|⚠⚠ **Bad: MySQL `LIKE '%word%'` scans everything; sharding only divides the scan (N/M).** ⭐⭐⭐ **Great: inverted index in Redis, keyword → [postIds]; ingestion tokenises and appends the id to each keyword; durability via MemoryDB.** ⚠ **Huge lists for common words; 10–1,000 keys per post. ⊕ Stop-words, normalisation; hydrate from Post Service**|
|⭐⭐⭐ §4.3 — sort ladder|⚠⚠ **Bad: fetch all ids, look up each timestamp/count, sort per request — hundreds of MB, tens of millions of lookups.** ⭐⭐⭐ **Great: two indexes per keyword — Creation = Redis list (append, read the end); Likes = Redis sorted set by count. New post ⇒ both; new like ⇒ update scores.** ⚠ **2× storage; each like updates many keys. ⊕ Out-of-order events break "append = time order"**|
|⭐⭐ DD1 — read volume|**No personalisation + 1-minute SLA ⇒ cache. Good: Redis search cache per query, TTL < 1 min. Great: + CDN with cache-control headers; hits in tens of ms.** ⚠⚠ **Freshness = ingestion lag + every cache TTL ⇒ the SUM must be < 1 min. ⚠ CDN hits bypass the gateway; normalise query keys**|
|⭐⭐ DD2 — phrases|**Good: intersect the keyword lists, then check the text really contains the phrase; ⚠ megabytes per list, heavy filtering.** ⭐⭐ **Great: index bigrams ("Taylor Swift", "Swift at") ⇒ one lookup; ⚠ 10M keys ⇒ 100M+ sparse keys ⇒ index only likely bigrams (Count-Min Sketch), fall back to intersection.** ⚠ **Longer phrases still intersect; ⊕ positional index; bigrams double write fan-out**|
|⭐⭐⭐ DD3 — post writes|**100-word post ⇒ 100+ writes; bursts can lose posts ⇒ Kafka to buffer and fan out to many ingestion instances; shard indexes by keyword.** ⚠⚠ **Term-partitioning ⇒ ~100 shards per post and hot shards for common words. ⊕ Document-partitioning: one shard per write, scatter-gather per query — what search engines usually do**|
|⭐⭐⭐ DD3 — likes|**Good: Like Batcher aggregates per post over ~30 s ⇒ +500 in one write; ⚠ useless for ordinary posts (1 like/min).** ⭐⭐⭐ **Great: write only at milestones (powers of 2/10) ⇒ 1,000 likes ≈ 10 writes; index stale but order roughly right; read top 2N, fetch fresh counts from Like Service, re-sort, return N — approximate storage, exact answer (two-stage retrieval). ⚠ Complex; rename the field `approxLikes`.** ⚠⚠ **2N may miss posts just under a milestone ⇒ over-fetch. ⚠ HI says "Elasticsearch" here by mistake**|
|⭐⭐ DD4 — storage|**Cap lists at 1k–10k per keyword; monthly job moves keywords unsearched for a month to blob storage (S3/R2); read Redis first, then blob.** ⚠⚠ **The cap breaks NFR 4 (all posts discoverable) ⇒ ⊕ keep full lists in blob, hot top in Redis. ⚠ New posts for cold keywords; capped likes sets need eviction by lowest score**|
|⭐⭐⭐ The meta-lesson|⭐⭐⭐ **Four ideas outlive this problem: (1) estimate first — here the "search" problem is write-heavy, and the index fan-out is the real number; (2) organise data the way it's queried — an index per sort order; (3) approximate cheaply, then re-rank a small candidate set exactly; (4) a freshness SLA is a budget shared by every cache and queue**|
|Levels (one line)|**Mid (80/20):** API, data model, both ingestion and query · **Senior (60/40):** fast HLD; spot write volume, storage, duplicate queries; proper inverted index + caching · **Staff+ (40/60):** several deep dives with insight; teach the interviewer|

---

> 🔗 **HI source:** https://www.hellointerview.com/learn/system-design/problem-breakdowns/fb-post-search