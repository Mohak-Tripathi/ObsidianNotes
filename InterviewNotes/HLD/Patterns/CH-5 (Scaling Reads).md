# Scaling Reads

> Hello Interview · **Patterns** · File `03d`. Overview → `03 §4`. Indexing → `01d`; data modeling → `01c`; caching → `01e`; sharding → `01f`; consistency/replication lag → `01h`; numbers → `01i`; Redis cache + hot key → `02a`; CDN → `02 §10`. **Calibration:** ⭐⭐ **High.** The _most common_ scaling topic — almost every interview ends here for read-heavy systems. For your targets: product catalog + feed reads, dashboards, portfolio/holdings views, URL-shortener-style lookups. ▸ **The governing progression (climb in order, don't skip):** **1) optimize within the DB** (index → denormalize) → **2) scale the DB horizontally** (replicas, then sharding) → **3) add caching layers** (Redis → CDN). Most candidates **jump straight to caching** — the senior move is to exhaust the cheap in-DB wins first. ⚠ **This is physics, not a code bug.** CPU cores, RAM, and disk I/O are bounded; past a point **no amount of clever code helps** — you must change the architecture.

---

## The Problem

▸ **CRUX** — reads bottleneck **first**, because read traffic grows far faster than writes. Instagram feed = **100+ read ops** to load (photos, user info, like counts, comment previews); you post **once a day** = one write.

- **Read:write ratio** starts ~**10:1**, often **100:1+** for content-heavy apps (every tweet read by thousands; every product browsed by hundreds).

### Where it shows up (HI breakdowns)

- Bitly · Instagram · FB News Feed · YouTube · Yelp · Ticketmaster · News Aggregator · Metrics Monitoring.
- ⭐ **Fintech/unicorn:** catalog + feed reads, analytics dashboards, portfolio views. ⚠ but **money/inventory reads need care** — see _When NOT to use_.

---

## 1. Optimize Within Your Database _(do this first — free headroom)_

> ▸ Before adding infra, a well-tuned single DB has more room than most engineers assume.

### 1.1 Indexing → full mechanics `01d`

▸ **CRUX** — an index is a **sorted lookup table** pointing at rows (like a book's index). No index → **full table scan O(n)** (read every row); with index → **jump to rows, O(log n)** (scan 1M rows vs check ~20 index entries).

- **Index the columns you frequently query / join on / sort by.** _(B-tree = general; hash = exact match; specialized = full-text/geo → `01d`.)_
- ⚠ **Ignore the "too many indexes slows writes" fear** — it's real but **wildly overblown** on modern engines. **Under-indexing kills more apps than over-indexing.** In interviews, **confidently add indexes** for your query patterns.
- ▹ **Compound index column order matters:** `(status, created_at)` helps filters on `status` and on both, **but not** on `created_at` alone _(→ `01d`)_.

### 1.2 Vertical scaling (hardware) — the boring lever

▸ SSDs (10–100× random I/O) · more RAM (more dataset in memory) · faster CPUs/cores (more concurrent queries).

- ▹ **Fastest way to buy breathing room**, but ⚠ **rarely what the interviewer wants** — it sidesteps the question. Mention it, don't dwell.

### 1.3 Denormalization → data modeling `01c`

▸ **CRUX** — normalization splits data across tables to kill redundancy → but that forces **expensive joins** at read time. **Denormalization stores redundant data** in one table → **trades storage for read speed.**

- Normalized order summary = join `users` + `orders` + `order_items` + `products`. Denormalized = one `order_summary` table with the names/prices duplicated → **single-table read.**
- ⚠ **Classic read-at-the-expense-of-writes** — a name change now updates **many rows.** **Check your read/write ratio first**; only denormalize when reads ≫ writes.
- ▸ **Materialized views** take it further — **precompute expensive aggregations** (avg product rating) via a **background job**, store the result, serve it directly instead of `GROUP BY`-ing on every page load.

---

## 2. Scale the Database Horizontally

▸ **When?** Rough rule: past **~50k–100k read RPS** (with proper indexing already in place), a single DB needs to scale out or get a cache _(→ `01i`)_. In interviews a rough estimate is enough to justify the move.

### 2.1 Read replicas

▸ **CRUX** — copy data from the **primary** to additional servers. **All writes → primary; reads → any replica** → read load spreads across servers.

- ▸ **Bonus: redundancy** — primary fails → **promote a replica** → minimal downtime.
- **Leader-follower replication:** one leader writes, many followers read. **Sync** (consistent, slower) vs **async** (faster, possibly stale).

⚠ **The key challenge — replication lag** _(common interview question → `01h`):_

- A write hits the primary, then takes time to reach replicas → a user reading a lagging replica **may not see their own change** (read-your-own-writes anomaly).
- **The trade:** sync = consistent but higher latency · async = fast but stale window.

### 2.2 Database sharding → `01f`

▸ **CRUX** — replicas spread _load_ but **don't shrink the dataset** each server holds. If even well-indexed queries are slow because the dataset is huge, **sharding splits data across DBs** → smaller datasets = faster queries **and** distributed load.

- **Functional sharding** — split by **domain/feature** (user DB, product DB) → profile requests hit only the smaller user DB.
- **Geographic sharding** — US data in US DBs, EU in EU DBs → faster nearby reads + less load per DB.
- ⚠ **But sharding is primarily a WRITE-scaling technique** and adds serious operational complexity → **for most read problems, caching is more effective and easier.** Don't shard for reads if a cache will do.

---

## 3. Add External Caching Layers → caching `01e`, Redis `02a §1`

▸ **CRUX — why caching beats replicas for read-heavy loads:** access is **highly skewed** — millions read the _same_ viral tweet, thousands view the _same_ popular product. You're repeatedly fetching **identical, rarely-changing data.** A cache stores it in **RAM** → **sub-ms** vs tens of ms from disk.

> ▹ **Replica-first vs cache-first (skewed → cache · diverse → replicas)** — full decision block in **overview `03 §4`.** Short version: caches win for skewed hot sets; replicas win for diverse long-tail + freshness + redundancy. You usually **layer both.**

### 3.1 Application-level caching (Redis / Memcached)

▸ Sits between app and DB. **Cache-aside:** check cache → **hit** = sub-ms → **miss** = query DB + populate for next time _(→ `01e`)_. Popular data stays resident; cold data expires after TTL.

⚠ **Cache invalidation = the primary challenge.** Strategies _(→ `01e` for write-through/-behind/-around)_:

- **TTL** — fixed lifetime; simple, serves stale until expiry; good for predictable update patterns.
- **Write-through invalidation** — update/delete cache on write; consistent, adds write latency.
- **Write-behind invalidation** — queue invalidations async; lower write latency, stale window.
- **Tagged invalidation** — tag entries (`user:123:posts`), invalidate by tag; powerful for dependencies, needs tag bookkeeping.
- **Versioned keys** — version in the key, bump on update → old entries naturally orphaned _(full pattern in the deep dive below)_.
- ▸ **Most systems combine:** short TTL (**5–15 min**) as a safety net **+ active invalidation** for critical data (profiles, inventory).
- ▸ **Drive the TTL from a data-staleness NFR (this is the clean way to pick a number):** let the requirement's tolerance for stale data _be_ the TTL. If the spec says _"search results may be at most 30s stale"_ → **TTL = 30s.** If user profiles can tolerate 5 min of staleness → **TTL = 5 min.** This way the TTL isn't a guess — it directly **bounds your consistency guarantee** and makes the whole cache-strategy decision fall out of the requirement.

### 3.2 CDN / edge caching → `01e`, `02 §10`

▸ Extends caching to **global edge locations.** Originally static assets; modern CDNs cache **dynamic content + API responses** too.

- Tokyo user → Tokyo edge (**200ms → <10ms**); can cut **origin load 90%+.**
- ⚠ **Only for data accessed by multiple users.** **Never CDN-cache user-specific data** (personal prefs, private messages, account settings) — one requester = **zero hit-rate benefit.** Target **shared** content (public posts, product catalogs, search results).

---

## In interviews

▸ **Look at each external API request; for the high-volume ones, optimize.** Order: **query optimization → caching → replicas.**

- ▸ **Proactively flag bottlenecks:** _"This profile endpoint gets hit on every profile view — millions of users → billions of reads/day. Let me address it in a deep dive."_

▸ **Scenario cheat-sheet:**

- **Bitly / URL shortener** — extreme read:write (shortened once, read millions of times). ⭐ Caching dream: cache short→long in Redis **with no expiration** (URLs don't change) + CDN; DB only for cold-link misses.
- **Ticketmaster** — event pages hammered on sale. Cache event details / venue / seat charts aggressively; ⚠ **never cache actual seat availability** (you'd oversell — that's `03b` contention). Read replicas for browsing, primary for purchases.
- **News feed** — precompute feeds for active users, cache recent posts; users read only the first few items → caching recent content pays off.
- **YouTube** — cache video metadata (titles/thumbnails rarely change); **view counts eventually consistent** (update every few min, not per view); CDN for thumbnails.

⚠ **When NOT to lean on read scaling:**

- **Write-heavy** (Uber location pings, ~1:1) → scale **writes** first _(→ `03e`)_.
- **Small scale** ("1000 users") → a well-indexed single DB is plenty; don't over-engineer.
- **Strongly consistent** (financial txns, inventory) → stale data causes real harm → aggressive invalidation + short TTLs, or don't cache. ⭐ **fintech caution.**
- **Real-time collaborative** (Google Docs) → needs real-time updates, not caching; caching _hurts_ when every keystroke must be visible _(→ `03a`)_.
- ▸ Read scaling reduces **DB load**; if you only need lower **latency** on a healthy DB, that's a different problem.

---

## Common Deep Dives

▸ **DD1 — "Queries slow as the dataset grows?"** → **indexing.** Without it, `WHERE email = …` scans all 10M rows (full table scan); an index turns it into a handful of lookups. Compound-index column order matters. _(Mechanics + `EXPLAIN` → `01d`.)_

▸ **DD2 — "Millions of concurrent reads for the SAME cached data?"** → the **hot key** problem _(→ `02a` hot key)_. Two read-specific tools:

- **Request coalescing** — combine concurrent requests for the same key into **one** backend fetch; the rest await it. ▸ Reduces backend load from ∞ to **exactly N = number of app servers** (one per server).
    - ▹ **Why exactly N (plain-language):** a load balancer spreads millions of users across your app servers, so each server ends up holding thousands of requests for the **same key.** Coalescing is a per-server rule: _"if I'm already fetching this key, don't fetch again — wait for the in-flight one."_ So on each server the **first** miss starts one DB query; the other thousands **attach to that same fetch** → that server sends the DB **1 query, not thousands.** Every server does this independently → the DB gets **one query per server = N total.** Backend load stops depending on **# users** and depends only on **# app servers**. It can't be **1** because Server 1 doesn't know Server 2 is already fetching (no cross-server dedupe) — hence **N**. _(This is the "depth" fix from `02a` — protects one hot key, not millions of cold keys.)_
- **Cache key fanout** — store the hot value under **N copies** (`feed:taylor-swift:1…:10`); clients pick a **random** suffix → 500k RPS spread across 10 keys at 50k each. _(Same mechanic as `02a` "key copies.")_ ⚠ Trade-off: **more memory + harder invalidation** (clear all copies).

▸ **DD3 — "Many requests rebuild an expired entry at once?"** → **cache stampede / thundering herd** _(related to `02a` warm-up block)_. A popular key with a 1-hr TTL expires → 100k simultaneous misses → all hit the DB (self-inflicted DDoS). ▸ **The real enemy is the _cliff_** — expiry is **binary** (valid at 59:59, gone at 60:00), so everyone hits the wall in the same instant. The three fixes are a **spectrum, not versus** — climb only when the cheaper one's weakness bites:

- **1) Distributed lock / coalescing on rebuild** _(the default; = the "policing" idea → `03b`, `02a`)_ — only the **first** miss rebuilds and fills the cache; everyone else **waits**, then reads the filled cache.
    
    - ⚠ **Its weakness = a slow/expensive rebuild.** If the rebuild joins 10 tables / calls an external API and takes seconds, **all 100k requests block and start timing out** — the lock protected the DB but stalled the users. And if that one rebuild **fails**, every waiter fails. Everyone still reaches the **cliff**; you just funnel them through one door.
- **2) Probabilistic early refresh** ⭐ _(reach for this when the rebuild is expensive)_ — **removes the cliff.** The entry stays valid the whole time (users always get an **instant hit, nobody waits**); but on **each read** the server rolls a dice — _"refresh in the background now?"_ — whose odds **rise as the entry ages**:
    
    |Entry age (60-min TTL)|Chance a read triggers a background refresh|
    |---|---|
    |~min 50|~1%|
    |~min 55|~5%|
    |~min 59|~20%|
    
    - So in the last ~10 min, a **few of the incoming _requests_** (not keys — this is **one** hot key) each quietly kick off a **background** rebuild **while still serving the old value** → the entry gets refreshed **before** it expires, and the refreshes are **staggered** (a trickle), never synchronized.
    - ⚠ **Why the dice, not a flat "refresh at min 50":** a flat trigger just **moves the stampede to min 50** (everyone refreshes together). Randomness makes it a trickle.
    - ⚠ **It's statistical, not a hard guarantee** — a rare traffic dip could mean no read rolls "yes" in time and it _does_ expire. Fine for most hot data; for the rest → option 3.
- **3) Continuous background refresh** _(for keys where even a rare stampede is unacceptable)_ — a **dedicated job** refreshes the entry on a schedule (every 50 min for a 60-min TTL) → users **never** trigger a rebuild. ⚠ Cost: extra infra + **wasted refreshes** on keys nobody asked for. Worth it only for your hottest/most-critical content.
    

▸ **Decision rule:** default to **coalescing/policing**; switch to **probabilistic early refresh when the rebuild is slow/expensive** (so nobody waits on it); use **continuous background refresh** only for the most critical keys where you can't leave freshness to a dice roll. ▸ **One-line hold:** _lock = funnel the stampede through one door at expiry (everyone waits) · probabilistic = restock a little early via a rising-odds dice per read so the cache never empties (nobody waits) · continuous = restock on a fixed schedule for your hottest keys._

▸ **DD4 — "Invalidation when updates must be immediately visible?"** _(→ `01e`)_

- ▸ **The setup:** for some data, eventual consistency is **unacceptable** — if an event organizer updates the **venue address**, attendees must not see the old location for another hour just because it's cached. ⚠ And your data may sit in **multiple layers at once** — Redis, CDN edges, even browser caches — so invalidating _all_ of them is famously hard.
- ⚠ **Naive approach — "delete the cache entry on write." Sounds simple, three real problems:**
    - **Which caches do you delete from** — app cache, CDN, _and_ browser?
    - **What if an invalidation request fails** (one layer doesn't get the delete)?
    - **The race:** a read that lands **right after you delete the old value but before the new value is written** will **recompute and re-cache the stale data** — you're back to serving stale.
- ⭐ **Better for entity-level data — cache versioning (key versioning):** don't delete; **route around** stale entries by changing the key whenever data changes:
    - Each record has a **version in the DB**; bump it **in the same transaction** as the update.
    - **Read:** get version → build key `event:123:v42` → read that key (miss → DB + write back under the versioned key).
    - **Write:** txn — update row + `version = version + 1` + commit → new data written under `event:123:v43`.
    - ▸ **Why it's clean:** old keys just become **unreachable** (no delete); **no race** (a late writer can't win — the DB forces a new version); **atomic** → keys never collide. CDN/browser caches expire stale versions naturally (version is in the URL/key).
    - ⚠ Trade-off: **two lookups** (version + data); old versions accumulate → set TTLs to clean up; **shines for single entities** (profile, product), **not** computed data (search/feeds).
- **Deleted-items cache** — for search/feeds where versioning doesn't fit: keep a **small cache of recently deleted/hidden IDs**; filter them out of served results → serve mostly-correct cached data now while properly invalidating the big structures in the background. Efficient for moderation/privacy changes.

---

## Quick Recall (pass 3+)

|Question|Answer|
|---|---|
|The progression|**① optimize in-DB (index → denormalize) → ② scale out (replicas → shard) → ③ cache (Redis → CDN).** Don't skip to caching|
|Why reads bottleneck first|read:write **10:1 → 100:1+**; it's **physics** (CPU/RAM/disk bounded), not a code bug|
|Indexing|full scan **O(n)** → index **O(log n)**; index query/join/sort columns; ⚠ **under-indexing** kills more than over-indexing (`01d`)|
|Denormalization|store redundant data → **trade storage + write-complexity for read speed**; check read/write ratio; **materialized views** precompute aggregations (`01c`)|
|When to scale out|past **~50k–100k read RPS** with indexing (`01i`)|
|Read replicas|writes→primary, reads→replicas; **redundancy** bonus; ⚠ **replication lag** (sync=consistent/slow · async=fast/stale) (`01h`)|
|Sharding for reads|shrinks dataset + spreads load (functional / geographic); ⚠ **primarily a write technique**, complex → prefer caching for reads (`01f`)|
|Why cache > replica (read-heavy)|**skewed access** — same hot data read repeatedly; RAM = **sub-ms**. Replica-first vs cache-first → **`03 §4`**|
|Cache invalidation|TTL · write-through · write-behind · tagged · versioned keys; **short TTL + active invalidation**; drive TTL from **staleness NFR** (`01e`)|
|CDN|edge cache, dynamic + API too, origin load −90%; ⚠ **never cache user-specific data** (`02 §10`)|
|Hot key (same key)|**coalescing** (backend load → N app servers) · **fanout** (N random-suffixed copies) (`02a`)|
|Cache stampede|expiry **cliff** → DB flood. Spectrum: **lock/coalescing** (default; ⚠ everyone waits on slow rebuild) → **probabilistic early refresh** (rising-odds dice per read, no cliff, nobody waits; for **expensive** rebuilds) → **continuous background refresh** (fixed schedule; hottest keys)|
|Immediate-visibility invalidation|naive delete = **race**; **cache versioning** (version in DB, `:v42→:v43`, old keys orphaned, atomic, no race) · **deleted-items cache** for feeds/search|
|When NOT|write-heavy (`03e`) · small scale · strongly-consistent money/inventory · real-time collab (`03a`)|
|⭐ Fintech caution|catalog/dashboards cache fine; **money/inventory/seat availability must not serve stale** → contention (`03b`)|

---

> 🔗 **HI quick reference:** https://www.hellointerview.com/learn/system-design/patterns/scaling-reads/quick-reference