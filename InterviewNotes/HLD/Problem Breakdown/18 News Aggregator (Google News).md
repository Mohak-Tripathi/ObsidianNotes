# News Aggregator (Google News) — Problem Breakdown

> 📐 **Revision note (calc):** ⭐⭐ **the one ratio that explains the whole design.** **Writes: ~50–100 new articles/hour at peak ⇒ ~2,400/day.** **Reads: 100M DAU × 5–10 refreshes = 500M–1B feed requests/day.** ⇒ ⭐⭐⭐ **a read:write ratio around 200,000:1** — ▸ **compare `05o` YouTube at 100:1.** ⭐ **That is why there is exactly one Pattern callout and why every answer is "precompute on the write."** **Other figures: <200ms feed load · 100M DAU spiking to 500M · 10M concurrent users per region at peak · ⭐ one app server = 10k–100k concurrent connections · ⭐⭐ one Redis instance ≈ 100k req/sec ⇒ 10M ÷ 100k = 100 Redis instances · 1,000–2,000 articles cached per regional feed · `ZREVRANGE` <5ms · Redis replication lag <200ms · thumbnails 20–50KB, served at 150×100 / 300×200 / 600×400 · CDN cuts S3 requests >90% · 25+ categories × 10 regions = 250 cache keys · personalisation: 1,000 articles × 50M users = 50B entries, 200–500× bigger.** ⚠ **Two figures not to trust — see the ⊕ notes in §5.2 and §5.6.**

> Hello Interview · Question Breakdowns · File `05r`. **Evan King**, published **Jun 2, 2025** · ⭐ **"medium"** · ⭐⭐⭐ **asked at Rippling, Amazon (+5 unnamed) — 7 companies, and Rippling is first-named.** ⭐ **ONE Pattern callout: `Scaling Reads` → `03d`.** ⚠ **Seven deep dives — the most in the series — and DD6/DD7 were ADDED after commenters said they'd been asked them.** Cross-refs: ⭐⭐ **precompute-on-write + feed caches → `05f`/`05g`** · ⭐⭐ **cursor pagination + Redis sorted sets → `05q §4.3`, `05q §5.2`** · **Redis commands → `02a`** · **blob storage + CDN → `01a`, and `05o §5.3` for the CDN argument** · **caching / cache-aside / TTL → `01e`** · ⭐ **hot key ⇒ replicate → `05g`** · **composite index → `01d`** · **sharding + consistent hashing → `01f`, `01g`** · **CDC → `05c §5.3`, `05h §5.2`** · **CAP → `01h`** · **API design → `01b`** · **API Gateway → `02d`** · **numbers → `01i`.** **Siblings: ⭐⭐ `05f`/`05g` (the feed-precompute parent) · `05q` FB Live Comments (cursors, sorted sets, CDN) · `05o` YouTube (thumbnails, CDN, read-skew).**
> 
> **Calibration:** ⭐⭐⭐ **Do this one properly — Rippling is on your target list and it's the first company named on the write-up.** ▸ **Seven dives, six of them real ladders — DD1, DD2, DD3, DD4, DD6, DD7; only DD5 is a component walk.** ⭐⭐ **TWO passes, and prioritise DD1, DD2, DD3, DD6.** ▹ ⭐ **DD6 and DD7 exist because readers reported being asked them — treat them as core, not bonus.** ⚠ **No "Expected at Each Level" section in this write-up, so there's no §7 here.**
> 
> - ⭐⭐ **What actually scores:**
>     - **(a)** ⭐⭐⭐ **The pagination ladder ending in "just make the IDs monotonic"** (§5.1). ▸ **The third rung DISSOLVES the problem instead of solving it.**
>     - **(b)** ⭐⭐⭐ **CDC-updated caches instead of TTL**, and ⭐ **knowing that killing the TTL forces a new bound** (`ZREMRANGEBYRANK`).
>     - **(c)** ⭐⭐ **Naming the thundering herd on TTL expiry** (§5.2).
>     - **(d)** ⭐⭐⭐ **"In my opinion, the above is overkill"** (§5.6) — ▸ **HI builds 250 category caches then rejects them for in-memory filtering.** ⭐ **The Great rung is SIMPLER than the Good one.**
>     - **(e)** ⭐⭐ **Regionality as a free scaling win** (§5.5) — ▸ **a product fact doing engineering work.**
>     - **(f)** ⭐⭐ **Read replicas, not sharding, for Redis** — ⭐ **because 2,000 articles fit anywhere; the problem is throughput, not size.**
>     - **(g)** ⭐⭐ **Preference vectors + mixing category feeds** (§5.7) — **100× less memory than per-user caches.**
> - ⭐ **Transferable primitives:**
>     - ⭐⭐⭐ **Make the ID itself ordered and your cursor problem disappears.** ▸ **ULIDs or auto-increment instead of random UUIDs.** ⭐ **Reusable for any chronological data — feeds, logs, events, messages.**
>     - ⭐⭐⭐ **Push the cache update onto the write path (CDC), not the read path (TTL).** ▸ **TTL trades freshness for simplicity AND gives you a thundering herd. CDC gives you both freshness and flat load.**
>     - ⭐⭐⭐ **Before building N specialised caches, check whether one general cache plus in-memory filtering is enough.** ▸ **Reading 1,000 cached rows costs <10ms; filtering costs 1–2ms.**
>     - ⭐⭐ **A payload identical for many users is cacheable once.** ▸ **One regional feed serves millions.** ⭐ **Same insight as `05q`'s CDN snapshot — and the reason personalisation is the dive that threatens the whole design.**
>     - ⭐⭐ **Find the natural partition in the PRODUCT, not the data.** ▸ **News consumption is regional, so regional deployments are smaller systems that scale independently.**
>     - ⭐ **Own your copy of an external asset.** ▸ **Don't hot-link publisher images — their servers may be slow, overloaded or gone, and you can't standardise size or quality.**
> - ⭐ **Re-run (cross-ref, NOT re-explained):** **cursor vs offset pagination (`05q §4.3` — ⭐ and `05q` used `commentId` as the cursor, which is exactly §5.1's Great solution without the reasoning)** · **Redis sorted sets as a feed (`02a`, `05q`)** · **CDN for globally-read assets (`01a`, `05o §5.3`)** · **thumbnails to blob storage not the DB (`01a`, `05b`)** · **precompute on the rare write (`05c`, `05f`, `05g`)** · **hot key ⇒ replicate (`05g`)**. **Genuinely new:** ⭐⭐⭐ **monotonic IDs as the cursor (ULID)** · ⭐⭐⭐ **CDC-driven cache updates + `ZADD`/`ZREMRANGEBYRANK` bounding** · ⭐⭐ **thundering herd on TTL expiry** · ⭐⭐ **in-memory category filtering over per-category caches** · ⭐⭐ **regional deployments** · ⭐⭐ **Redis read replicas + Sentinel failover** · ⭐⭐ **preference vectors + feed mixing** · ⭐ **RSS mechanics** · ⭐ **the priority-tiered ingestion (RSS / scraper / webhook)** · ⭐ **multi-size thumbnails + `srcset`**.

---

## 0 · Understanding the problem

📰 **What is Google News?**

A service that **aggregates and displays news articles from thousands of publishers worldwide** in a **scrollable interface.**

---

## 1 · Requirements

### 1.1 Functional (what it does)

1. ⭐ **View an aggregated feed of articles from thousands of publishers worldwide.**
2. ⭐ **Scroll the feed "infinitely".**
3. ⭐ **Click an article and get redirected to the publisher's site** for the full content.

⚠ **Below the line:** customise the feed by interests · save articles for later · share to social media.

▹ ⚠ **Note the first two "bonus" dives (§5.6 categories, §5.7 personalisation) are the out-of-scope items coming back** — ⭐ **because readers reported being asked them.**

### 1.2 Non-functional (how it behaves)

1. ⭐ **Availability over consistency** (`01h`) — ⭐ **and HI gives the reason, which is a good line:** **users _"would prefer to see slightly outdated content rather than no content at all."_**
2. ⭐ **Scale to 100M DAU, spiking to 500M.**
3. ⭐⭐ **Low-latency feed loads — <200ms.**

⚠ **Below the line:** user data and privacy · breaking-news traffic spikes · monitoring and observability · resilience to publisher API failures.

▹ ⚠⚠ **Note what's NOT here: there is no FRESHNESS requirement.** ⭐ **§5.2 and §5.3 both reference one anyway — see the ⊕ note in §5.3.**

### 1.3 ⭐⭐ The design driver — the most read-skewed system in the series, and one feed serves millions

|||
|---|---|
|**Writes**|**~50–100 articles/hour at peak ⇒ ~2,400/day**|
|⭐⭐ **Reads**|**500M–1B feed requests/day**|
|⭐⭐⭐ **Ratio**|**~200,000 : 1** ▸ **vs `05o` YouTube at 100:1**|

- ⭐⭐⭐ **So every answer in this file is the same answer: do the work on the rare write, make the read a single Redis range query.** ▹ **Same thread as `05c` (`avgRating`), `05f`/`05g` (feeds), `05o` (segments + manifests).**
- ⭐⭐⭐ **And the second half, which is what makes precompute CHEAP here: the feed is IDENTICAL for everyone in a region.** ▸ **One cache per region, not per user.** ⭐ **Same insight as `05q`'s CDN snapshot — a payload shared by millions is cacheable once.**
- ⚠⚠ **Which is exactly why §5.7 personalisation is the dive that threatens the whole design** — ▸ **per-user feeds destroy the shared payload.** ⭐ **And that's why its answer is "don't build per-user caches."**

### 1.4 Planning the approach

▸ **Sequentially through the FRs, then let the NFRs drive the dives.** ⭐ **HI adds the specific balance to name here: _"carefully balance scalability and performance to meet our high traffic demands."_**

---

## 2 · Core Entities

- ⭐ **Article** — **id, title, summary, thumbnail URL, publish date, publisher ID, region, media URLs.** ▸ **The core content entity.**
- **Publisher** — **id, name, URL, feed URL, region.** ▸ **The origin of content.**
- ⭐ **User** — **id and region** — ▹ **region _"may be inferred from IP or explicitly set."_** ⭐ **Even anonymous users get basic tracking.**

▹ ⭐ **HI's framing tip, and it's a good habit:** **when presenting entities, explain the RELATIONSHIPS and purpose — don't list every attribute.**

---

## 3 · API

```
GET /feed?page={page}&limit={limit}&region={region} -> Article[]
```

- ⭐ **One endpoint. There is NO endpoint for viewing an article** — ▸ **the browser navigates to the publisher using the `url` field.**
- ⚠ **Starting with offset pagination deliberately**, and HI says so: **it has performance issues for infinite scroll, fixed in §5.1.**

---

## 4 · High-Level Design

⭐⭐ **Two distinct halves, and naming the split early is the structure of the whole answer: INGESTING from thousands of publishers, and SERVING to millions of users.**

### 4.1) View an aggregated feed

#### ⭐ The ingestion half

```
External Publishers ──RSS──► Data Collection Service ──► Database
                                                          Article: id · title · summary
                                                                   thumbnailUrl · publishDate · url
                                                          Publisher: id · name · url
                                                                     rssFeedUrl · lastScraped
                                        └──► S3 (thumbnails)
```

- ⭐ **Data Collection Service: a BACKGROUND process polling publisher RSS feeds and APIs every 3–6 hours**, **based on each publisher's update frequency.** ⚠ **That interval is the problem §5.3 attacks.**

**The workflow — three steps:**

1. **Query the DB for the list of publishers and their RSS feed URLs, then query each one in turn.**
2. **Extract article content and metadata; download media files for thumbnails.**
3. **Store thumbnails in object storage, article data + media URLs in the database.**

> ⭐ **What RSS is, in four lines — worth knowing, it's the backbone of this problem.**
> 
> - **A simple XML format letting publishers syndicate content to other sites and readers.**
> - ⭐ **Why aggregators use it: a simple, standardised format many publishers ALREADY support**, and **relatively lightweight to parse.**
> - **It works over plain HTTP** — ▸ **GET the feed URL, get back XML with the article title, link and metadata.**
> 
> ■ **— end of insert · HI write-up resumes below —**

> ⭐⭐ **Confusion resolved — why download publisher images instead of just linking to them?**
> 
> - ⭐⭐ **Two reasons, and both are the kind that generalise:**
>     1. ⭐ **You don't want to depend on publisher servers** — **they may be _"slow, overloaded, or go down entirely"_**, and then your feed is broken.
>     2. ⭐ **You can't STANDARDISE quality and size** on someone else's asset ⇒ **inconsistent UX.**
> - ▸ **The general rule: own your copy of any external asset your product's experience depends on.**
> 
> ■ **— end of insert · HI write-up resumes below —**

#### ⭐ The serving half

```
Client ──► API Gateway ──► Feed Service ──► Database
            routing · auth   queries by region,   (articles, ordered by publishDate)
            · rate limiting  formats response
                                └──► S3 (thumbnails requested directly by the client)
```

- ⭐⭐ **Why Feed Service is SEPARATE from Data Collection — three reasons, all of which hold:**
    - ⭐ **Completely different scaling requirements** — **read-heavy vs write-heavy.**
    - ⭐ **Different update frequencies** — **real-time vs batch.**
    - ⭐ **Different operational needs** — **user-facing vs background processing.**
- ▹ ⭐ **Compare `05h §4.3`'s three-part rule (write pattern + data volume + ideal engine). Here it's read/write skew plus operational mode — a cleaner split than most.**

**The request flow:** `GET /feed?region=US&limit=20` → **Gateway routes to Feed Service** → **queries the DB for recent articles in the user's region, ordered by publish date** → **DB returns metadata + media URLs** → **Feed Service formats and returns.**

### 4.2) Infinite scroll — the naive version

▸ **Offset pagination on the existing Feed Service.**

- **First load:** `?region=US&limit=20&page=1` → **first 20 by publish date** → **response includes pagination metadata (`total_pages`, `current_page`)** → **client stores the page number.**
- **On scroll:** `?page=2` → **Feed Service computes the offset `(page-1) * limit`** → **DB fetches with `OFFSET` and `LIMIT`.**
- ⚠ **HI flags its own limitations around performance and consistency.** ▸ **→ §5.1.**

### 4.3) Click through to the publisher

▸ ⭐ **Nothing to build — the browser redirects to the `url` stored in the DB.**

- ⭐ **The framing worth stating:** **aggregators _"don't actually host the content themselves."_** ▸ **They point at the publisher.**
- ▹ ⭐ **Out of scope but worth one sentence: real Google News routes clicks through a tracking endpoint** — **`GET /article/{article_id}` logs the click and returns a 302 to the publisher** — **which trains recommendations and measures engagement.**

---

## 5 · Deep Dives

### 1) ⭐⭐⭐ How do we make pagination consistent and efficient?

⚠⚠ **The problem — "pagination drift":** **a user on page 2 while new articles are published to the TOP of the feed.** ▸ **Content shifts down, so page 3 shows DUPLICATES or SKIPS articles entirely.**

- 📐 ⭐ **Why it's not theoretical: 50–100 new articles/hour at peak means a user browsing for 10 minutes _"could easily encounter this pagination drift problem multiple times."_**

⚠ **Rung labels are mine.**

#### Good — timestamp cursors

- **Approach:** ⭐ **return a cursor = the timestamp of the last article in the response.** **Next request queries `WHERE published_at < cursor_timestamp ORDER BY published_at DESC LIMIT 20`.**
- ✅ ⭐⭐ **Why it fixes drift: you're querying relative to a FIXED POINT IN TIME, not a shifting offset.** ▸ **New articles above the boundary can't affect pagination of older content.**
- ▹ **Needs an index on `published_at`** (`01d`).
- ⚠ **Challenge — TIMESTAMP COLLISIONS, and they're common here:** ⭐ **publishers batch-import articles or use automated systems that assign the SAME timestamp to many articles.** ▸ **Query "before timestamp X" and you MISS everything sharing exactly timestamp X** ⇒ **gaps in the feed.**

**Why climb:** a timestamp isn't unique, so it can't be a reliable position.

#### ⭐ Better — composite (timestamp, id) cursor

- **Approach:** ⭐⭐ **a cursor like `"2024-01-15T10:30:00Z_article123"`** — **timestamp PLUS the unique article ID**, so **the ID breaks ties.**

```sql
WHERE (published_at, article_id) < (cursor_timestamp, cursor_id)
ORDER BY published_at DESC, article_id DESC
LIMIT 20
```

- ⭐ **Uses SQL tuple comparison, with a composite index on `(published_at, article_id)`.**
- ✅ ⭐ **Total ordering even with identical timestamps ⇒ never duplicates, never gaps.** ▹ **HI: _"Major platforms like Twitter and Instagram use similar composite cursor approaches."_**
- ⚠ **Challenges:** **cursor generation and parsing get more complex (encode/decode both components)** · **queries are marginally more complex** · **slightly longer cursors and extra index storage** — ▹ **both negligible.**

**Why climb:** you're building tie-breaking machinery because the ID is random. Make the ID ordered instead.

#### ⭐⭐⭐ Great — monotonically increasing IDs

- ⭐⭐⭐ **The move: design the IDs to be ordered from the start.** **Time-ordered UUIDs (ULIDs) or database auto-increment, instead of random UUIDs.** ▸ **Articles are collected chronologically, so newer articles always have higher IDs.**

```sql
WHERE article_id < cursor_id ORDER BY article_id DESC LIMIT 20
```

- ⭐⭐⭐ **Now pagination is trivial: the cursor is ONE ID.** ✅ **No composite cursors, no timestamp handling, no tuple comparison, a simple single-column index.**
- ⭐ **And collisions are impossible by construction** — every article has a unique ordered identifier.
- ⭐ **The database only needs a simple index on the `article_id` column, and the queries are as fast and simple as possible.** ▹ **Many modern systems use ULIDs (Universally Unique Lexicographically Sortable Identifiers), which combine the benefits of UUIDs with chronological ordering.**
- ⚠ **Challenges:** ⭐⭐ **it requires planning the ID strategy UP FRONT** — **migrating off random UUIDs needs careful data migration** · ⚠ **ID generation must handle high throughput without becoming a bottleneck** · **distributed generation needs coordination (ULIDs or a centralised ID service solve it).**
- ⭐⭐ **HI's verdict: _"often the simplest and most performant solution for chronological data like news feeds."_**

> ⭐⭐⭐ **The transferable lesson — and this ladder is the best example of it in the series.**
> 
> - ▸ **Rungs 1 and 2 SOLVE the ordering problem. Rung 3 DISSOLVES it** by changing a decision made earlier in the design.
> - ⭐⭐ **Reusable instinct: when a fix is getting complicated, check whether an upstream choice is what made it hard.**
> - ▹ ⭐ **And note `05q §4.3` already used `commentId` as the cursor** — ▸ **that WAS this solution; this file is the explanation of why it works.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 2) ⭐⭐⭐ How do we get <200ms feed requests?

📐 **The load: 100M DAU × 5–10 refreshes/day = 500M–1B feed requests/day.** ⚠ **Even well-indexed, querying millions of articles and filtering by region per request _"could push response times well beyond our 200ms target."_**

> ⭐ **Pattern: Scaling Reads** (`03d`) — **the only callout.** ▹ ⭐⭐ **HI's framing: _"news consumption vastly outweighs news creation, making read optimization critical."_** ▸ **Demands aggressive caching of regional feeds and pre-computed rankings.**
> 
> ■ **— end of insert · HI write-up resumes below —**

⚠ **Rung labels are mine.**

#### Good — cache regional feeds with a TTL

- **Approach:** ⭐ **Redis sorted sets, one key per region** — `feed:US`, `feed:UK` — **scored by timestamp.** ⭐ **Classic cache-aside** (`01e`): **miss ⇒ query the DB, cache with TTL, return.** **TTL = 30 minutes.**
- ⭐ **Note the constraint HI calls out:** **the TTL is on the WHOLE FEED, not individual articles** — ▸ **_"not possible with redis sorted sets."_**
- ⭐ **Pagination still works:** `ZREVRANGEBYSCORE` **with the cursor as the score.**
- ⚠ **Challenges — three, and the second and third are the ones to name:**
    - ⚠ **Cache misses still mean expensive DB queries that violate the latency target.**
    - ⚠⚠ **30 minutes of staleness on a NEWS platform** — ⭐ **unacceptable where timely delivery is the product.**
    - ⚠⚠⚠ **THUNDERING HERD on expiry:** **every user for a region hits the DB simultaneously** ⇒ **_"hundreds of concurrent expensive queries overwhelm the database"_**, giving **periodic degradation lasting minutes** and ⭐ **an inconsistent experience — some requests fast, others very slow.**

**Why climb:** a TTL means the cache is refreshed by READS, so it's stale between refreshes and stampeded at every expiry. Refresh it on the WRITE instead.

#### ⭐⭐⭐ Great — precomputed feeds updated by CDC

- ⭐⭐⭐ **The move: when a new article is stored, CDC immediately updates the relevant regional caches. No TTL, no waiting.**
- **The pipeline:** **Data Collection Service writes the article → the DB emits a CDC event → Feed Generation Workers consume it, decide which regional feeds need updating, and `ZADD` the article with its timestamp as the score** ⇒ ⭐ **chronological ordering maintained automatically.**
- ⭐⭐⭐ **And the consequence most candidates miss — killing the TTL removes your only bound on cache growth, so you need a new one:**

```
ZADD              feed:US <timestamp> <articleId>      -- insert
ZREMRANGEBYRANK   feed:US 0 -2001                      -- trim to the newest ~2,000
```

- ⭐ **Keep only the most recent N (typically 1,000–2,000) per regional feed** ⇒ **manageable size, still enough for several pages of scrolling.**
- ⭐⭐ **Reads become `ZREVRANGE`, completing in under 5ms.** ▹ **Full metadata either stored in the cache directly or fetched by a secondary lookup on the IDs.**
- ⚠ **Challenges:** **a CDC pipeline, message queues and workers to maintain** ⇒ **harder to operate and debug** · **storage grows because article data is duplicated across regional caches** · ⚠ **edge cases like cache corruption or worker failure need robust error handling and cache REBUILDING.** ▹ ⭐ **HI: used by major news and social platforms because it gives the best balance of performance and freshness.**

> ⊕ ⚠ **(mine) — one HI figure not to repeat.**
> 
> - ⚠ **HI writes _"the Redis response times are typically under 200ms."_** ▸ **That's a nonsense framing for an in-memory store** — ⭐ **Redis is SUB-MILLISECOND**, and HI's own later numbers say **`ZREVRANGE` <5ms** and **sub-50ms from the nearest cluster.**
> - ⭐ **Say "sub-millisecond" or "single-digit ms."** ⚠ **Saying "Redis is under 200ms" in an interview reads as never having used it.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 3) ⭐⭐ How do we get articles into feeds within 30 minutes of publication?

⚠⚠ **The problem:** **polling every 3–6 hours means _"by the time we discover breaking news, users have already learned about it from social media."_** ▸ **Hours of delay makes the feed _"stale and irrelevant"_** — ⭐ **and for a major story _"users expect to see it in their feeds within minutes, not hours."_**

▹ ⭐⭐ **HI's calibration first: _"especially when asked of mid-level or junior candidates, the interviewer will ask you to 'black box' the ingestion pipeline."_** ▸ **Senior candidates do get asked how it works, at least at a high level.** ⭐ **So ASK before you build it — see the script at the end of this dive.**

⚠ **Rung labels are mine.**

#### Good — crank up RSS polling, with priority tiers

- ⭐⭐ **Approach: don't poll everything on one schedule — tier it by publisher characteristics.**

|Tier|Who|Interval|
|---|---|---|
|⭐⭐ **High**|**major news outlets, breaking-news sources** — **CNN, BBC, Reuters: dozens of articles daily, frequently break stories**|⭐ **every 5–10 min**|
|**Medium**|ordinary sources|**every 30 min**|
|**Low**|**weekly magazines, niche publications**|**every 2–3 hours**|

- ⭐ **How the tier is decided:** **the Data Collection Service keeps a `priority` on the publisher row in the DB, tracking each source's HISTORICAL PUBLISHING PATTERNS.** ▸ **High-priority sources go into a fast polling queue.**
- ⭐ **Separate worker processes per tier**, with **high-priority workers running continuous loops that sleep only 5–10 minutes between cycles.**

**The polling workflow — three steps:**

1. **High-priority workers query the DB for high-priority publishers and HTTP GET each feed URL every 5–10 min.**
2. ⭐ **New articles are detected by comparing article GUIDs or publication timestamps against the database**, then immediately handed to the ingestion pipeline.
3. ⭐⭐ **Workers track `Last-Modified` headers and ETags from RSS responses** — ▸ **so an unchanged feed costs nothing to process.** ⭐ **Cheap, concrete, and the kind of detail that reads as experience.**

- ⚠ **Challenges — four, and the last one is the one that forces the next rung:**
    - 📐 ⚠ **Request volume explodes: 10,000+ publishers polled every 5–10 min means _"100,000+ HTTP requests per hour instead of our current 2,000-3,000."_** ⇒ **substantially higher server cost.**
    - ⚠⚠ **It risks _"overwhelming smaller publishers' servers with too many requests, potentially getting our IP addresses blocked."_** ▸ **You can break the thing you depend on.**
    - ⚠ **Still REACTIVE, not proactive.** ▸ **Even at 5 minutes, breaking news takes up to 5 minutes plus processing** — ⭐ **still slow next to social media when every minute counts.**
    - ⚠⚠⚠ **And HI's own emphasis: _"Maybe most importantly, **not all publishers have RSS feeds!**"_** ▸ **Many newer publishers have limited feeds or none at all.**

**Why climb:** no polling frequency helps a publisher that has no feed to poll.

#### Better — intelligent web scraping

- **Approach:** ⭐ **for publishers with no RSS or infrequently-updated feeds, visit the sites programmatically and extract articles from the HTML.** ▸ **The system keeps a database of website patterns and CSS selectors per major site.**
- ⭐ **How it finds articles:** **crawl publisher homepages and category pages for new article links** — **elements with classes like `article-headline`, `story-link`, `news-item`** — **extracting URLs, titles and publication timestamps.** **Then follow each URL to pull headline, body text, author and publication date, normalise into the standard article format, and feed the SAME pipeline as RSS content.**
- ⭐⭐ **How it knows what's new — and this is what the `hash` field in the schema is for:** **per site, scrapers keep a FINGERPRINT DATABASE of previously-seen articles, using URL hashes or content checksums.**
- ⭐ **Same tiered scheduling applies:** **high-traffic news sites scraped every 10–15 min, smaller sites hourly.**
- ⭐⭐ **HI's framing of why both exist: _"we combine the best of both worlds — we get the freshness of RSS, but we also get the coverage of web scraping."_**
- ▹ **HI notes the infrastructure is _"very similar to our web crawler breakdown"_ and abstracts it away** — ⚠ **that's a separate HI problem, not in your set yet.**
- ⚠ **Challenges:**
    - ⚠⚠ **Significant maintenance overhead** — **_"websites frequently change their HTML structure, breaking our extraction logic."_**
    - ⚠ **Slower and less reliable than RSS parsing.**
    - ⚠⚠ **Legal concerns** around extracting content from sites that prohibit scraping.
    - ✅ ⭐ **Which is why HI positions it carefully: _"we use scraping strategically as a fallback for publishers without RSS feeds, not as our primary method."_** ▸ **RSS when available, scraping when necessary.**

**Why climb:** both rungs are you going out to look. Get them to tell you instead.

#### ⭐⭐⭐ Great — publisher webhooks, with polling as fallback

- ⭐⭐⭐ **The move: flip from PULL to PUSH.** ▸ **Publishers notify you the moment they publish.** ⭐ **_"instead of us trying to find new articles, we can rely on them telling us about them!"_**
- ⭐⭐⭐ **And the argument that makes it realistic — use your leverage:** **_"If we assume we really have 100M DAU, then publishers should be clamoring to get their articles on our platform."_** ▸ ⭐ **Your traffic is the negotiating position. Say that out loud; it's what turns a nice idea into a defensible design.**

```
POST /webhooks/article-published
{ url, title, publicationTimestamp, content? }     ⭐ full payload optional
```

- ⭐ **The infrastructure:** **a high-availability endpoint that handles sudden spikes when a major story breaks and many publishers fire at once.** **It validates the payload, extracts the article data, and immediately queues it through the standard ingestion pipeline.**
- ⭐⭐ **Security, and don't skip it:** **webhook AUTHENTICATION via shared secrets or API keys** — ▸ **to prevent spam and _"ensure content authenticity."_** ⚠ **An unauthenticated public ingestion endpoint is an open door into your feed.**
- ⭐⭐⭐ **The payoff number:** **content is processed _"within seconds of publication"_**, and **the webhook immediately triggers cache updates for the relevant regional feeds** ⇒ ⭐⭐ **it appears in user feeds **within 30 SECONDS**.** ▸ **Against a dive titled "within 30 minutes," that's 60× better than the target.**
- ⭐ **Keep RSS polling and scraping as the fallback for publishers who don't support webhooks** ⇒ **a hybrid: real-time where possible, polling elsewhere.**
- ⚠ **Challenges — and the first is structural, not technical:**
    - ⚠⚠⚠ **Webhooks need coordination and buy-in from publishers**, **_"which we can't implement unilaterally like polling or scraping approaches."_** ▸ ⭐ **Polling and scraping you can just do. This one requires someone else to agree.**
    - ⚠ **Many smaller publishers lack the technical resources to implement a webhook integration.**
    - ⚠ **Some are reluctant to add an external dependency to their publishing workflow.**

**⭐⭐ So the final shape is all three at once**, reflected in the design as **High / Mid / Low Priority Collection Services + a Web Scraper + a Webhook Service**, with **`scrapeType: RSS | Web | Webhook`** and **`priority`** on the Publisher row:

|Route|For whom|Latency|
|---|---|---|
|⭐⭐ **Webhooks**|**premium real-time partners who agree**|⭐⭐ **~30 seconds**|
|⭐ **Tiered RSS polling**|**cooperative publishers with feeds**|**5–10 min (high tier)**|
|⭐ **Web scraping**|**sites with no feed**|**10–15 min (high traffic)**|

> ⭐⭐ **HI's interview script for this dive — the most directly usable thing in the file. Ask, don't assume:**
> 
> 1. ⭐⭐ **_"Can I black box the ingestion pipeline?"_** ▹ **Usually yes, especially at mid-level.**
> 2. **_"Do our publishers maintain RSS feeds?"_**
> 3. ⭐ **_"Given we have such high traffic, can we assume publishers would be willing to implement webhooks to tell us when new articles are published?"_**
> 
> ▸ ⭐⭐ **The third is the good one — it gets the interviewer to hand you permission to use your market power, which is what unlocks the Great solution.**
> 
> ■ **— end of insert · HI write-up resumes below —**

> ⊕ ⭐⭐ **(mine) — two notes: one thread, one gap in the requirements.**
> 
> **1. ⭐⭐⭐ Second delivery-model flip in two files, in OPPOSITE directions.** ▸ **`05q §5.2` flipped PUSH→PULL (CDN snapshots) to survive extreme scale. This flips PULL→PUSH (webhooks) to win freshness.** ⭐⭐ **The lesson isn't "push is better" or "pull is better" — it's that the delivery model is a CHOICE, and you pick it from what you're optimising for.**
> 
> **2. ⚠ §1.2 has NO freshness NFR** — only availability, 500M DAU scale and <200ms latency. ▸ **Yet §5.2 says the 30-minute TTL _"violates our freshness requirement"_ and this dive's title asserts 30 minutes.** ⭐⭐ **Add it yourself: _"for a news product I'd add a freshness requirement — articles visible within minutes of publication — because that's the core value proposition."_** ▸ **Then §5.2 and §5.3 both have something to be measured against.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 4) ⭐ How do we handle media (thumbnails) efficiently?

▸ ⭐ **Scope first: since users click through to publishers, you only need THUMBNAILS** — **enough to make the feed visually appealing and scannable.** ⭐ **But at 100M+ daily users even thumbnails must be fast and cheap.**

⚠ **Rung labels are mine.**

#### ⚠⚠ Bad — thumbnails in the database as binary

- ▹ ⚠ **HI's own note: _"This is so bad we don't even do it in our high level design"_** — included only to show why.
- ⚠ **Challenges:** **even 20–50KB each × millions of articles ⇒ slow queries, enormous backups**, and ⭐⭐ **the DB server's memory consumed by IMAGE data instead of being available for queries.** ⚠ **Doesn't scale past a few thousand articles.**
- ⭐⭐ **The rule to state: _"Databases are meant to store structured data, not binary data. If you have large binary blobs, always store them in object storage."_**

**Why climb:** blobs belong in a blob store.

#### Good — S3 with URLs in the DB

- **Approach:** **on collection, download the original, generate a thumbnail (300×200), upload to S3, store the S3 URL in the article metadata.** ✅ **Proper separation: S3 does files, the DB does structured data.** ⭐ **Thumbnails load S3→browser directly, off your app servers.**
- ⚠ **Challenges:** ⚠ **global users get high latency from distant S3 regions** · **S3 egress costs add up over millions of daily views** · ⚠ **no support for different screen densities (retina vs standard) or slow connections.**

**Why climb:** one region can't serve the world quickly.

#### ⭐ Great — S3 + CloudFront CDN + multiple sizes

- ⭐ **Approach:** **serve from S3 through a CDN** (`01a`), **generating multiple sizes — 150×100 mobile, 300×200 desktop, 600×400 retina** — **selected via HTML `srcset` or client-side logic based on device and screen density.**
- ✅ ⭐ **CloudFront caches at edge locations worldwide ⇒ sub-200ms thumbnail loads globally.**
- ⚠ **Challenge: higher storage for multiple variants** — ▹ **minimal versus the gain.** ⭐⭐ **And the payoff figure: _"The CDN caching reduces S3 requests by over 90%"_**, so it **lowers overall cost while improving UX.**

### 5) ⭐⭐ How do we handle breaking-news traffic spikes?

⚠ **The scenario: normal 100M DAU spiking to _"10M concurrent users within minutes"_** — **everyone wants the latest simultaneously.** ▹ ⭐ **HI's own honesty: _"10M concurrent users is a lot and probably an overestimate, but… many interviewers push you to design for such semi-unrealistic scenarios."_**

> ⭐⭐⭐ **The gift in this problem — a product fact that solves an engineering problem. Say this before you scale anything.**
> 
> - ⭐⭐ **_"news consumption is inherently regional."_** ▸ **Americans want US news, Europeans want EU news.** **Some users seek international news, but the vast majority of traffic is regional.**
> - ⭐⭐⭐ **So deploy infrastructure per region, and each deployment handles only its own content and traffic.** ▸ **_"Rather than building one massive global system, we can build several smaller regional systems that are much easier to scale and operate."_**
> - ▹ ⭐ **Same thread as `05e` (virtual waiting queue), `05g` (the 5,000-friend cap), `05k` (opt-in live sharing): look for the product fact before engineering around the tail.**
> 
> ■ **— end of insert · HI write-up resumes below —**

⭐⭐ **Then walk the components left to right — peak requirement, does it hold, how to scale:**

|Component|At 10M concurrent per region|
|---|---|
|**Feed Service**|⭐ **one server handles 10k–100k concurrent connections ⇒ not enough.** **Horizontal scaling + auto-scaling groups behind load balancers.** ✅ ⭐ **Easy because the service is STATELESS — spin up in seconds, tear down when traffic subsides**|
|**Database**|⚠ **a single instance cannot serve 10M concurrent reads — I/O, network and CPU all bottleneck, and hardware upgrades won't fix it.** ✅ ⭐⭐ **But the cache already solved this: all feed reads hit Redis, so the scaling challenge is OFFLOADED from the DB to the cache**|
|⭐⭐ **Redis**|⚠ **one instance serves only ~100k req/sec.** 📐 **10M ÷ 100k = 100 instances.** ⭐⭐ **The fix is READ REPLICAS, not sharding**|

> ⭐⭐ **Why replicas and not shards — the reasoning is the reusable part.**
> 
> - ⭐⭐ **_"Since we only have ~2,000 recent articles per region, each master can easily store all the regional content without complex sharding — the scaling challenge is purely about read throughput."_**
> - ⭐⭐⭐ **That's `05g`'s rule, fourth appearance: too much DATA for one node ⇒ shard. Too much TRAFFIC for one key ⇒ replicate.** ▸ **Here the data is tiny and the traffic is enormous.**
> - ⭐ **The setup: writes go to the master, reads load-balanced across replicas (round-robin or least-connections).** **Redis Sentinel promotes a replica automatically if the master fails.** ⭐ **Replication lag under 200ms — fine for news, where users won't notice.**
> - ▹ ⭐ **Not using Redis? _"The concept is the same. Use consistent hashing to shard the data across multiple instances and ensure each instance has a replica or two"_** (`01g`).
> - ✅ **The regional payoff: sub-50ms cache responses from the nearest cluster · a spike in one region doesn't affect others · scale each region independently.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 6) ⭐⭐⭐ How do we support category feeds (Sports, Politics, Tech)?

▹ ⭐ **A "bonus" dive added because readers reported being asked it — treat it as core.**

⚠ **The problem: 25+ categories, hundreds of daily articles each, and up to 10M requests for specific categories at peak.** ▸ **A major sporting event means 10M users requesting Sports simultaneously** ⇒ **millions of DB hits for the SAME content.**

⚠ **Rung labels are mine.**

#### ⚠ Bad — filter by category at request time

- **Approach:** **add a `category` column; query `WHERE region = 'US' AND category = 'sports' ORDER BY published_at DESC LIMIT 20`** with **a composite index on `(region, category, published_at)`.**
- ⭐ **Where the category comes from:** **RSS feed metadata (publishers often emit `<category>Sports</category>`) · webpage structure analysis · keyword matching on title and content.**
- ⚠ **Challenges:** ⚠⚠ **every category request is a DB query** ⇒ **millions of DB operations, connection pools exhausted.** ⚠ **And caching gets awkward: 25 categories × 10 regions = 250 cache keys, each with its own invalidation pattern and traffic volume.**

**Why climb:** you're recomputing the same filtered list for millions of users.

#### Good — precompute a cache per category-region

- **Approach:** ⭐ **separate sorted sets — `feed:sports:US`, `feed:politics:UK`, `feed:technology:CA`.** **During ingestion, Feed Generation Workers categorise each article and update MULTIPLE sorted sets: a US sports article goes into both `feed:US` and `feed:sports:US`.**
- ✅ ⭐ **Reads are blazing: `ZREVRANGE feed:sports:US 0 19` in under 5ms.**
- ⚠ **Challenges:** ⚠ **250+ sorted sets instead of 10, each holding 1,000–2,000 articles** ⇒ **much higher Redis memory.** ⚠⚠ **And invalidation gets genuinely complex: one article lives in several sets, so expiry needs COORDINATED cleanup across keys** — **which can hurt read performance during heavy publishing.**

**Why climb:** HI's own next line.

#### ⭐⭐⭐ Great — one regional cache, filter in memory

> ⭐⭐⭐ **HI rejects its own previous rung: _"In my opinion, the above is overkill."_**

- ⭐⭐ **The move: store FULL article metadata as JSON in the regional cache, then filter in application memory.**

```json
{
  "id": "123",
  "title": "NBA Finals Game 7 Results",
  "description": "Warriors defeat Celtics in thrilling finale",
  "url": "https://espn.com/nba/finals/game7",
  "category": "sports",
  "region": "US",
  "published_at": "2024-06-21T22:30:00Z"
}
```

- **On `/feed?region=US&category=sports`:** **`ZREVRANGE feed:US 0 999`** to get the most recent 1,000, **then filter in memory for `category === "sports"`** before paginating.
- 📐 ⭐⭐⭐ **The numbers that justify it: reading 1,000 cached articles takes <10ms, filtering adds 1–2ms.** ▸ **For categories with decent representation you easily find 20–50 relevant articles without touching the DB.**
- ✅ ⭐⭐ **And look at what it costs: almost nothing.** **Minimal architecture change (the CDC pipeline already populates regional caches — just change the cached FORMAT)** · ⭐ **memory stays flat because articles aren't duplicated across caches** · **cache management stays simple.**
- ⭐⭐⭐ **HI's closing line, and it's the lesson: _"This is an example where the best solution is often the most straightforward one."_**

> ⭐⭐⭐ **Why this ladder is worth more than its content — the Great rung is SIMPLER than the Good one.**
> 
> - ▸ **Normally a ladder climbs toward sophistication. Here rung 3 is less machinery than rung 2 and beats it on every axis — memory, complexity, invalidation.**
> - ⭐⭐ **The reusable check: before building N specialised caches, ask whether ONE general cache plus in-memory filtering is enough.** ▸ **It usually is when the general cache is small (here 1,000–2,000 rows) and the filter is cheap.**
> - ⚠ **Know the limit, though: this works because 1,000 regional articles contain enough sports.** ⭐ **For a RARE category you'd scan 1,000 and find 2 — ▸ then the per-category cache earns its place after all. Say that boundary; it shows you know why it works, not just that it does.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 7) ⭐⭐ How do we personalise feeds?

▹ ⭐ **Also a reader-requested dive.** ▹ ⭐ **And HI's scoping gift: _"The actual ranking/scoring function itself is usually a machine learning model, but we can abstract this away… This isn't an MLE interview after all!"_**

⚠ **Rung labels are mine.**

#### ⚠ Bad — score at request time

- **Approach:** **maintain user profiles (reading history, topic preferences, behavioural data) and rank recent articles against the profile when the feed is requested.** ▸ **Signals: clicks, reading time, shares, subscribed topics, preferred publishers.** ⭐ **Plus collaborative filtering — _"users who read A and B also engage with C."_**
- ⚠⚠ **Challenges:** **scoring thousands of articles against 100M profiles = _"billions of calculations per hour, taking several seconds instead of our target 200ms."_** ⚠ **Prohibitively expensive, and it degrades catastrophically during spikes.**

**Why climb:** you can't do per-user work on the read path at this scale.

#### Good — precompute a feed per user

- **Approach:** ⭐ **`feed:user:12345` sorted sets, maintained by background workers as articles arrive**, **scored by relevance rather than chronology.** ▸ **Active daily users get dedicated caches; inactive users get on-demand generation from category caches.**
- ⚠⚠ **Challenges:** 📐 **1,000 articles × 50M active users = 50 BILLION cache entries — _"200-500x larger than category caching."_** ⚠ **Plus cache staleness when interests shift**, and ⭐ **personalised feeds might MISS globally important breaking news that everyone should see.**

**Why climb:** per-user storage explodes, and you lose the shared-payload property that made the whole design cheap.

#### ⭐⭐ Great — preference vectors + feed mixing

- ⭐⭐ **The move: store a LIGHTWEIGHT preference vector per user (kilobytes), and assemble the feed on demand by MIXING pre-computed category feeds.**
- ⭐⭐ **The concrete example to repeat:** **a tech-interested user gets 60% `feed:technology:US` + 30% `feed:business:US` + 10% `feed:trending:US`**, **with the mixing ratios set by their preference vector.** ⭐ **During breaking news, temporarily boost the trending weight while keeping personal preferences.**
- ✅ ⭐⭐ **_"reducing memory requirements by 100x"_** — **a few hundred category caches instead of 100M user caches** — **and it builds on infrastructure §5.6 already created.** ▹ **ML tunes the ratios from engagement.**
- ⚠ **Challenges:** **less personalisation depth than a full recommendation engine** · ⭐ **assembly needs careful tuning to balance personalisation against DIVERSITY** — ▸ **very narrow interests miss important global stories, very broad interests feel generic.**

---

## 6 · Final Design

⚠ **Layout and arrows are mine; components and field lists are HI's.**

```
External Publishers
  │  RSS feeds  ·  websites  ·  webhook pushes
  ▼
⭐ PRIORITY-TIERED INGESTION
  High Pri Collection Service  ─┐
  Mid  Pri Collection Service  ─┤── RSS polling (interval by publisher priority)
  Low  Pri Collection Service  ─┘
  Web Scraper        ⭐ for publishers with no feed
  Webhook Service    ⭐⭐ premium real-time partners — push, not poll
  │
  │  extract content + metadata · download the primary image
  ▼
Database                                                    02g · 01d
  │  Article:   id · title · summary · thumbnailUrl · publishDate
  │             url · hash · region · publisherId
  │             ⭐⭐ make `id` a ULID / auto-increment ⇒ the ID IS the cursor
  │             ⭐ index on id (or composite (published_at, id) if not)
  │             ⭐ `hash` = the SCRAPER's fingerprint (URL hash / content
  │                checksum) to tell new articles from already-seen ones
  │                ⊕ but NOT cross-publisher dedupe — see below
  │  Publisher: id · name · url · rssFeedUrl
  │             ⭐ scrapeType: RSS | Web | Webhook · priority · lastScraped
  │
  ├──► S3  ⭐ thumbnails at 150×100 / 300×200 / 600×400          01a
  │      │
  │      └──► CDN (CloudFront)  ⭐⭐ edge-cached worldwide
  │             ⭐ cuts S3 requests >90% · client picks size via srcset
  │             └──────────────────────────► Client (thumbnails direct)
  │
  └──► CDC  ⭐⭐⭐ the write path updates the cache — NO TTL
         │
         ▼
      Feed Generation Workers
         │  decide which feeds this article belongs to
         ▼
      Redis  (per region, read-replicated)                   02a · 03d
         │  ⭐⭐ ZADD feed:US <ts> <article JSON>
         │  ⭐⭐ ZREMRANGEBYRANK feed:US 0 -2001   ← the bound that
         │       replaces the TTL; keeps ~1,000–2,000 newest
         │  ⭐⭐⭐ store FULL article JSON, not just IDs
         │       ⇒ category filtering happens IN MEMORY, so no
         │         feed:sports:US / feed:politics:UK proliferation
         │  ⭐ reads: ZREVRANGE (<5ms) · ZREVRANGEBYSCORE for the cursor
         │
         │  ⭐⭐ Master ──write──► Replica 1 · Replica 2 · … · Replica N
         │       reads round-robin across replicas · Sentinel auto-promotes
         │       📐 10M concurrent ÷ ~100k req/s = ~100 instances
         │       ⭐ REPLICAS not shards — 2,000 articles fit anywhere;
         │          the problem is throughput, not size            05g
         ▲
         │
Feed Service  ⭐ STATELESS ⇒ horizontal + auto-scaling
         │   ⭐ reads the regional cache, filters by category in memory,
         │      paginates by cursor
         │   ⭐⭐ personalisation: mix category feeds by the user's
         │      preference vector (60/30/10), NOT per-user caches
         ▲
         │
API Gateway  — routing · auth · rate limiting                    02d
         ▲
         │  GET /feed?region=US&limit=20&cursor={last_article_id}
         │  ▹ article clicks go straight to the publisher's url
         │    (or via GET /article/{id} → 302, for analytics)
Client

⭐⭐⭐ DEPLOY ALL OF THIS PER REGION — news consumption is regional, so each
       deployment is a smaller, independently scalable system.
       Sub-50ms from the nearest cluster · a spike in one region
       doesn't touch the others.
```

> ⊕ ⭐⭐ **(mine) — `hash` does ONE job, and the other job you'd expect it to do is missing.**
> 
> - ✅ ⭐ **What it IS for** (§5.3's scraping rung): **the scraper's fingerprint — a URL hash or content checksum per site, to tell a NEW article from one already seen.** ▸ **Within one publisher.**
> - ⚠⚠ **What it is NOT for, and the gap is real: CROSS-PUBLISHER deduplication.** ▸ **One AP or Reuters story is syndicated to dozens of outlets, so a single breaking story floods the feed with 30 near-identical entries** — ⭐ **the most visible possible failure for an aggregator, and HI never addresses it anywhere.**
> - ⭐⭐ **Raise it as a one-liner:** _"I'd also hash title + normalised body ACROSS publishers and collapse duplicates into one feed entry with multiple sources — otherwise one wire story takes over the feed."_ ▸ **Note it's a second, different hash from the scraper's.**
> 
> ■ **— end of insert —**

---

## Quick Recall (pass 3+)

|Use / Question|News Aggregator answer|
|---|---|
|Calibration|⭐ Evan King · Jun 2025 · **"medium"** · ⭐⭐⭐ **Rippling, Amazon (+5 unnamed) — 7 companies, Rippling FIRST-named** · ⭐ **ONE pattern: `Scaling Reads` (`03d`).** ⚠ **SEVEN dives — six are real ladders (DD1/DD2/DD3/DD4/DD6/DD7), only DD5 is a component walk.** ⭐⭐ **TWO passes, prioritise DD1, DD2, DD3, DD6.** ▹ **DD6/DD7 were ADDED because readers reported being asked them ⇒ core, not bonus.** ⚠ **No levels section in the source**|
|⭐⭐⭐ Design driver|📐 **Writes ~2,400 articles/day vs reads 500M–1B requests/day ⇒ ~200,000:1** (vs `05o` at 100:1) — ⭐⭐ **the most read-skewed system in the series.** ⭐⭐⭐ **So every answer is "do the work on the rare write, make the read one Redis range query."** ⭐⭐⭐ **And the half that makes precompute cheap: the feed is IDENTICAL for everyone in a region ⇒ one cache per region, not per user** (same insight as `05q`'s CDN snapshot). ⚠⚠ **Which is exactly why DD7 personalisation threatens the whole design, and why its answer is "no per-user caches"**|
|FRs / NFRs|**aggregated feed from thousands of publishers · infinite scroll · click through to the publisher.** Below: customise feed · save articles · social sharing — ▹ **and the first two come BACK as DD6/DD7.** **NFRs: availability > consistency (⭐ _"users would prefer slightly outdated content rather than no content at all"_) · 100M DAU spiking to 500M · ⭐⭐ <200ms feed load.** Below: privacy · spike handling · monitoring · publisher-API resilience. ⚠⚠ **NOTE: there is NO freshness NFR, yet DD2 and DD3 both cite one**|
|📐 Numbers|**<200ms · 100M→500M DAU · 10M concurrent per region at peak · RSS polled every 3–6h (the problem) · 50–100 new articles/hour peak · ⭐ 1 app server = 10k–100k connections · ⭐⭐ 1 Redis = ~100k req/s ⇒ 10M÷100k = 100 instances · 1,000–2,000 articles per regional feed · `ZREVRANGE` <5ms · replication lag <200ms · sub-50ms from nearest cluster · thumbnails 20–50KB at 150×100/300×200/600×400 · CDN cuts S3 >90% · 25+ categories × 10 regions = 250 keys · personalisation 1,000 × 50M = 50B entries, 200–500× bigger**|
|Entities / API|**Article** (id, title, summary, thumbnailUrl, publishDate, publisherId, region, media URLs) **· Publisher** (id, name, url, feedUrl, region) **· User** (id, region — ▹ **inferred from IP or set explicitly; even anonymous users get basic tracking**). **`GET /feed?page&limit&region`** — ⭐ **no endpoint for viewing an article; the browser goes to the `url` field.** ▹ ⭐ **HI's tip: present entities by RELATIONSHIPS and purpose, not by listing attributes**|
|⭐⭐ Two halves|⭐⭐ **Name the split early: INGEST from thousands of publishers vs SERVE to millions of users.** **Data Collection Service polls RSS every 3–6h by publisher update frequency → extract content + metadata, download media → thumbnails to S3, article data to the DB.** ⭐⭐ **Separate Feed Service for 3 reasons: different scaling (read vs write-heavy) · different update frequency (real-time vs batch) · different operational needs (user-facing vs background)**|
|⭐ What RSS is|**a simple XML format for publishers to syndicate content.** ⭐ **Why aggregators use it: standardised, ALREADY supported by many publishers, lightweight to parse.** **Works over plain HTTP — GET the feed URL, get XML with title, link and metadata**|
|⭐⭐ Why copy publisher images|**(1) don't depend on publisher servers — _"slow, overloaded, or go down entirely"_ (2) you can't STANDARDISE quality and size on someone else's asset.** ▸ **General rule: own your copy of any external asset your UX depends on**|
|⚠⚠ DD1 the problem|**"pagination drift": a user on page 2 while new articles land at the TOP ⇒ content shifts ⇒ page 3 shows DUPLICATES or SKIPS articles.** 📐 ⭐ **at 50–100 new articles/hour, 10 minutes of browsing hits it _"multiple times"_**|
|DD1 Good — timestamp cursor|`WHERE published_at < cursor_timestamp ORDER BY published_at DESC LIMIT 20`. ✅ ⭐⭐ **fixes drift because you query relative to a FIXED POINT IN TIME, not a shifting offset.** ⚠ **TIMESTAMP COLLISIONS: publishers batch-import or auto-assign the SAME timestamp to many articles ⇒ you MISS everything sharing the cursor's exact timestamp ⇒ gaps**|
|⭐ DD1 Better — composite cursor|`"2024-01-15T10:30:00Z_article123"` ⇒ `WHERE (published_at, article_id) < (cursor_timestamp, cursor_id) ORDER BY published_at DESC, article_id DESC`. ⭐ **SQL tuple comparison + composite index on `(published_at, article_id)`.** ✅ **total ordering ⇒ no duplicates, no gaps.** ▹ **Twitter and Instagram do this.** ⚠ **encode/decode complexity, marginally longer cursors, extra index storage — all negligible**|
|⭐⭐⭐ DD1 Great — monotonic IDs|⭐⭐⭐ **Make the ID ordered from the start: ULID or auto-increment instead of random UUID.** ⇒ `WHERE article_id < cursor_id ORDER BY article_id DESC LIMIT 20`. ⭐⭐⭐ **The cursor is ONE ID — no composites, no timestamps, no tuples, simple single-column index**, and **collisions are impossible by construction.** ⚠ **Requires planning UP FRONT — migrating off UUIDs needs care; ID generation mustn't bottleneck; distributed generation needs coordination (ULID or a central ID service).** ⭐⭐ HI: _"often the simplest and most performant solution for chronological data."_ ⭐⭐⭐ **Rungs 1–2 SOLVE the problem; rung 3 DISSOLVES it by changing an upstream decision — when a fix gets complicated, check what earlier choice made it hard.** ▹ **`05q` already used `commentId` as the cursor — this is WHY that works**|
|📐 DD2 the load|**100M DAU × 5–10 refreshes = 500M–1B requests/day.** ⚠ **Even indexed, querying millions of articles + filtering by region per request blows past 200ms**|
|DD2 Good — TTL cache|⭐ **Redis sorted sets per region (`feed:US`, `feed:UK`), scored by timestamp, cache-aside, TTL 30 min** (`01e`). ⭐ **TTL is on the WHOLE FEED, not individual articles — _"not possible with redis sorted sets."_** **Pagination via `ZREVRANGEBYSCORE` with the cursor as score.** ⚠ **3 problems: misses still hit the DB · ⚠⚠ 30 min stale on a NEWS product · ⚠⚠⚠ THUNDERING HERD on expiry — every user for a region hits the DB at once ⇒ _"hundreds of concurrent expensive queries"_ ⇒ minutes of degradation and an inconsistent UX**|
|⭐⭐⭐ DD2 Great — CDC|⭐⭐⭐ **Move the cache update to the WRITE path: article stored → CDC event → Feed Generation Workers `ZADD` it to the right regional sorted sets with timestamp as score ⇒ chronology automatic, no TTL, no staleness, no stampede.** ⭐⭐⭐ **The consequence most miss: killing the TTL removes your growth bound ⇒ `ZREMRANGEBYRANK` after each `ZADD` to keep the newest ~1,000–2,000.** ⭐ **Reads = `ZREVRANGE` <5ms.** ⚠ **Costs: CDC + queues + workers to operate and debug · article data duplicated across regional caches · ⚠ cache corruption / worker failure need robust rebuild paths**|
|⊕⚠ Don't repeat this figure|⚠ **HI writes _"Redis response times are typically under 200ms."_** ⭐ **Redis is SUB-MILLISECOND**, and HI's own later numbers say `ZREVRANGE` <5ms and sub-50ms from the nearest cluster. ⚠ **Saying "Redis is under 200ms" reads as never having used it — say "sub-millisecond" or "single-digit ms"**|
|⚠⚠ DD3 the problem|**3–6h polling means _"by the time we discover breaking news, users have already learned about it from social media"_** ⇒ **the feed feels _"stale and irrelevant."_** ▹ ⭐⭐ **HI's calibration: mid-level/junior candidates are usually told to _"black box"_ the pipeline; senior candidates get asked how it works — so ASK first**|
|DD3 Good — tiered RSS polling|⭐⭐ **Tier by publisher: HIGH (CNN/BBC/Reuters — dozens daily, break stories) every 5–10 min · MEDIUM every 30 min · LOW (weekly magazines, niche) every 2–3h.** ⭐ **A `priority` column tracks each source's HISTORICAL PUBLISHING PATTERNS; separate workers per tier, high-pri loops sleeping 5–10 min.** **Detect new articles by comparing GUIDs or publish timestamps against the DB.** ⭐⭐ **And the detail worth saying: track `Last-Modified` + ETags so an unchanged feed costs nothing.** ⚠ **Challenges: 📐 10,000+ publishers ⇒ _"100,000+ HTTP requests per hour instead of our current 2,000-3,000"_ · ⚠⚠ risks _"overwhelming smaller publishers' servers… potentially getting our IP addresses blocked"_ · ⚠ still REACTIVE — 5 min + processing · ⚠⚠⚠ _"Maybe most importantly, **not all publishers have RSS feeds!**"_**|
|DD3 Better — web scraping|**For sites with no feed: crawl homepages and category pages for article links (`article-headline`, `story-link`, `news-item`), follow URLs, extract headline/body/author/date, normalise into the SAME pipeline.** ⭐ **Keeps a DB of site patterns + CSS selectors.** ⭐⭐ **And a FINGERPRINT database per site — URL hashes or content checksums — to tell new from seen; ▸ this is what the `hash` column is for.** ⭐ **Same tiering: high-traffic sites every 10–15 min, smaller hourly.** ⭐⭐ **_"best of both worlds — the freshness of RSS, but also the coverage of web scraping."_** ⚠ **Challenges: ⚠⚠ sites change HTML and break extraction · slower + less reliable than RSS · ⚠⚠ legal concerns where scraping is prohibited.** ✅ ⭐ **So: _"strategically as a fallback… not as our primary method"_**|
|⭐⭐⭐ DD3 Great — webhooks|⭐⭐⭐ **Flip PULL → PUSH: _"instead of us trying to find new articles, we can rely on them telling us about them!"_** ⭐⭐⭐ **The leverage argument that makes it realistic: _"If we assume we really have 100M DAU, then publishers should be clamoring to get their articles on our platform."_** **`POST /webhooks/article-published {url, title, publicationTimestamp, content?}`.** ⭐ **HA endpoint for simultaneous spikes; validates, extracts, queues into the standard pipeline.** ⭐⭐ **Auth via shared secrets or API keys — prevents spam and _"ensures content authenticity"_** (⚠ **an unauthenticated public ingestion endpoint is an open door**). ⭐⭐⭐ **Payoff: processed _"within seconds"_ and in feeds within 30 SECONDS — 60× better than the dive's own 30-minute title.** ⚠ **Challenges: ⚠⚠⚠ needs publisher BUY-IN — _"which we can't implement unilaterally like polling or scraping"_ · smaller publishers lack the resources · some won't add an external dependency to their workflow**|
|⭐⭐ DD3 — the final shape|**All three at once: ⭐⭐ webhooks (~30s) for partners who agree · ⭐ tiered RSS (5–10 min high tier) for publishers with feeds · ⭐ scraping (10–15 min) for sites without.** ⇒ **High/Mid/Low Pri Collection Services + Web Scraper + Webhook Service, with `scrapeType: RSS\|Web\|Webhook` and `priority` on Publisher**|
|⭐⭐ DD3 — the interview script|⭐⭐ **Ask, don't assume: (1) _"Can I black box the ingestion pipeline?"_** ▹ **usually yes, especially at mid-level (2) _"Do our publishers maintain RSS feeds?"_ (3)** ⭐ **_"Given we have such high traffic, can we assume publishers would be willing to implement webhooks?"_** ▸ ⭐⭐ **(3) is the good one — it gets the interviewer to hand you permission to use your market power, which is what unlocks the Great solution**|
|⊕⭐⭐⭐ Two flips in two files|⭐⭐⭐ **`05q §5.2` flipped PUSH→PULL (CDN snapshots) to survive extreme scale. `05r §5.3` flips PULL→PUSH (webhooks) to win freshness.** ▸ ⭐⭐ **The lesson isn't that one is better — it's that the DELIVERY MODEL IS A CHOICE, picked from what you're optimising for**|
|⊕⚠ DD3 answers an unstated requirement|⚠ **§1.2 has NO freshness NFR, yet DD2 cites a _"freshness requirement"_ and DD3's title asserts 30 minutes.** ⭐⭐ **Fix it yourself: _"for a news product I'd add a freshness requirement — articles visible within minutes of publication — because that's the core value proposition."_** ▸ **Then both dives have something to measure against**|
|⚠⚠ DD4 Bad — blobs in the DB|▹ ⚠ **_"so bad we don't even do it in our high level design."_** **20–50KB × millions ⇒ slow queries, enormous backups, and ⭐⭐ the DB's memory consumed by IMAGES instead of queries.** ⭐⭐ **The rule: _"Databases are meant to store structured data, not binary data. If you have large binary blobs, always store them in object storage."_**|
|DD4 Good — S3 + URL|**download → resize to 300×200 → upload to S3 → store the URL.** ✅ **proper separation; thumbnails load S3→browser, off your app servers.** ⚠ **global users get distant-region latency · S3 egress costs · no retina/density support**|
|⭐ DD4 Great — S3 + CDN + sizes|⭐ **CloudFront in front of S3** (`01a`), **multiple sizes — 150×100 mobile / 300×200 desktop / 600×400 retina — chosen via `srcset` or client logic.** ✅ **edge caching ⇒ sub-200ms globally.** ⭐⭐ **And the payoff: _"CDN caching reduces S3 requests by over 90%"_ ⇒ cheaper AND faster.** ⚠ **more storage for variants — minimal**|
|⭐⭐⭐ DD5 — regionality is the gift|⭐⭐ **_"news consumption is inherently regional"_** — Americans want US news, Europeans EU news. ⭐⭐⭐ **So deploy PER REGION: _"rather than building one massive global system, we can build several smaller regional systems that are much easier to scale and operate."_** ▹ ⭐ **Same thread as `05e` (waiting queue), `05g` (5,000-friend cap), `05k` (opt-in sharing): find the PRODUCT fact before engineering around the tail.** ▹ ⭐ **HI's own honesty: 10M concurrent is _"probably an overestimate, but many interviewers push you to design for such semi-unrealistic scenarios"_**|
|⭐⭐ DD5 — component walk|**Feed Service: ⭐ 1 server = 10k–100k connections ⇒ horizontal + auto-scaling; easy because STATELESS.** **Database: ⚠ can't serve 10M concurrent reads — but ✅ ⭐⭐ the cache already took that load off it.** **Redis: ⚠ ~100k req/s each ⇒ 📐 10M÷100k = 100 instances ⇒ ⭐⭐ READ REPLICAS, not sharding**|
|⭐⭐⭐ DD5 — replicas not shards|⭐⭐ **_"Since we only have ~2,000 recent articles per region, each master can easily store all the regional content without complex sharding — the scaling challenge is purely about read throughput."_** ⭐⭐⭐ **`05g`'s rule, 4th appearance: too much DATA ⇒ shard; too much TRAFFIC for one key ⇒ replicate.** **Setup: writes to master, reads round-robin/least-connections across replicas, ⭐ Redis Sentinel auto-promotes on master failure, replication lag <200ms (fine for news).** ▹ **Not Redis? same idea — consistent hashing to shard + a replica or two each** (`01g`)|
|⚠ DD6 Bad — filter at request time|**add a `category` column, `WHERE region AND category ORDER BY published_at`, composite index `(region, category, published_at)`.** ⭐ **Category comes from RSS metadata (`<category>Sports</category>`), page structure analysis, or keyword matching.** ⚠⚠ **Every request is a DB query ⇒ millions of operations, connection pools exhausted.** ⚠ **And caching is awkward: 25 categories × 10 regions = 250 keys with separate invalidation**|
|DD6 Good — cache per category-region|⭐ **`feed:sports:US`, `feed:politics:UK`… workers categorise on ingestion and update MULTIPLE sets (a US sports article → both `feed:US` and `feed:sports:US`).** ✅ **`ZREVRANGE feed:sports:US 0 19` <5ms.** ⚠ **250+ sets × 1,000–2,000 articles ⇒ much more memory.** ⚠⚠ **Invalidation gets complex — one article in several sets needs COORDINATED cleanup, which hurts reads during heavy publishing**|
|⭐⭐⭐ DD6 Great — in-memory filter|⭐⭐⭐ **HI rejects its own rung: _"In my opinion, the above is overkill."_** ⭐⭐ **Store FULL article JSON (id, title, description, url, category, region, published_at) in the regional set; on a category request do `ZREVRANGE feed:US 0 999` and filter in memory.** 📐 ⭐⭐⭐ **Reading 1,000 cached articles <10ms, filtering 1–2ms** ⇒ **easily 20–50 relevant articles, no DB.** ✅ **Minimal change (CDC already fills regional caches — just change the FORMAT) · memory flat, no duplication · simple management.** ⭐⭐⭐ **_"This is an example where the best solution is often the most straightforward one."_** ⭐⭐⭐ **Note the Great rung is SIMPLER than the Good one — before building N specialised caches, check whether ONE general cache + in-memory filtering suffices.** ⚠ **Know the boundary: it works because 1,000 regional articles contain enough sports — for a RARE category you'd scan 1,000 and find 2, and then per-category caches DO earn their place**|
|⚠ DD7 Bad — score at request time|**user profiles from clicks, reading time, shares, subscribed topics, preferred publishers + collaborative filtering (_"users who read A and B also engage with C"_).** ⚠⚠ **Thousands of articles × 100M profiles = _"billions of calculations per hour, taking several seconds instead of our target 200ms"_ — and it degrades catastrophically in spikes**|
|DD7 Good — cache per user|⭐ **`feed:user:12345` sorted sets maintained by background workers, scored by RELEVANCE not chronology; active users get dedicated caches, inactive ones on-demand from category caches.** ⚠⚠ **📐 1,000 × 50M = 50 BILLION entries, _"200-500x larger than category caching"_** · ⚠ **staleness when interests shift** · ⭐ **and personalised feeds can MISS globally important breaking news**|
|⭐⭐ DD7 Great — preference vectors|⭐⭐ **Store a lightweight preference VECTOR per user (kilobytes) and assemble on demand by MIXING category feeds.** ⭐⭐ **The example to repeat: 60% `feed:technology:US` + 30% `feed:business:US` + 10% `feed:trending:US`, ratios from the vector; ⭐ during breaking news boost the trending weight.** ✅ ⭐⭐ **_"reducing memory requirements by 100x"_ — a few hundred category caches, not 100M user caches — built on DD6's infrastructure.** ⚠ **Less depth than a real recommender · ⭐ needs tuning for DIVERSITY — narrow interests miss global stories, broad ones feel generic.** ▹ ⭐ **HI's scoping gift: _"the ranking function is usually an ML model, but we can abstract this away. This isn't an MLE interview after all!"_**|
|⊕⭐⭐ The `hash` field — one job, one gap|✅ ⭐ **What it IS for (§5.3 scraping): the scraper's FINGERPRINT — URL hash or content checksum per site, to tell a new article from one already seen. Within ONE publisher.** ⚠⚠ **What it's NOT: CROSS-PUBLISHER dedupe — and that gap is real. One AP/Reuters story syndicates to dozens of outlets, so a breaking story floods the feed with 30 near-identical entries — the most visible possible failure for an aggregator, unaddressed anywhere.** ⭐⭐ **One-liner: _"I'd also hash title + normalised body ACROSS publishers and collapse duplicates into one entry with multiple sources."_** ▸ **A second, different hash from the scraper's**|
|⭐⭐⭐ The meta-lesson|⭐⭐⭐ **Two rungs in this file get SIMPLER as they get better** — **DD1's monotonic IDs (delete the cursor machinery) and DD6's in-memory filter (delete 240 caches).** ▸ **Both work by undoing an earlier decision rather than adding a layer on top of it.** ⭐ **Pair with `05i`/`05p`'s restraint thread**|

---

> 🔗 **HI source:** https://www.hellointerview.com/learn/system-design/problem-breakdowns/news-aggregator