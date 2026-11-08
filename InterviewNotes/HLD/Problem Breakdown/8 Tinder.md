# Dating / Swipe App (Tinder) — Problem Breakdown

> 📐 **Revision note (calc):** **20M DAU × ~100 swipes/day = 2B swipes/day**, and **× ~100 bytes = ~200GB/day** of swipe data (§4.3) — ⭐ **that one figure is what justifies a separate write-optimized database.** Plus **<300ms** stack load. ⚠ **Source inconsistency to ignore:** one line says "200 swipes a day… 4B swipes a day" while the NFR, the storage math and DD1 all use **100/day → 2B/day.** ⭐ **Use 100 → 2B → 200GB; they're mutually consistent.**

> Hello Interview · Question Breakdowns · File `05h`. **Joseph Antonakakis**, Jul 2024 · ⭐ **"medium"** · ⭐ **asked at Amazon** · has a video walkthrough. ⚠ **Note: this write-up carries no "Pattern:" callouts**, unlike `05c`–`05g` — but three patterns converge in it anyway. Cross-refs: ⭐⭐ **Cassandra — partition keys, CommitLog/Memtable/SSTable, LWT → `02e` (first problem in the series that actually uses it as a primary store)**. Contention / atomic check-and-set → `03b` (**which already covers Cassandra LWT**). Redis Lua, hashes, consistent hashing → `02a`. Elasticsearch → `02b`. ⭐ **Geospatial indexing → `04a`.** ⭐ **Bloom filter mechanism → `04b`.** Indexing → `01d`. Caching → `01e`. Partitioning → `01f`. CAP → `01h`. Numbers → `01i`. API design → `01b`. API Gateway → `02d`. **Siblings: `05c` Yelp (geo + search ladder) · `05e` Ticketmaster (atomic contention) · `05f`/`05g` (feed precompute + staleness).**
> 
> **Calibration:** ⭐⭐ **Three patterns converge here, like `05e` — and it's the only problem in the series where Cassandra is the primary store. Worth real time.**
> 
> - ⭐⭐ **What actually scores:**
>     - **(a)** ⭐⭐ **The `user_pair` sorted-key trick** (§5.1) — **the single best idea in this file**, and the most transferable.
>     - **(b)** ⭐⭐ **Redis for the atomic op, Cassandra for durability** (§5.1 Great) — and **why losing Redis is survivable.**
>     - **(c)** ⭐ **The cached-stack + Elasticsearch fallback**, refreshed when a few profiles remain, so **"the stack seemed infinite."**
>     - **(d)** ⭐⭐ **Stale feeds as a named problem** (§5.2) — what makes a profile stale, and the **tunable-parameters** principle.
>     - **(e)** ⭐ **Client-side swipe cache** — treating the client as part of the system, and **the assumption that licenses it.**
>     - **(f)** **Bloom filter for huge swipe histories** — ⚠ **and knowing it's borderline over-engineering** (`04b`).
>     - **(g)** ⭐ **Separate service AND separate DB** — the one problem in the series where splitting wins (§4.3).
> - ⭐ **Transferable primitives:**
>     - ⭐⭐ **Sort the two IDs to turn a symmetric relationship into one deterministic key.** `min:max` makes A→B and B→A land in the same partition. ▸ **Reuse for mutual follows, friendships, 1:1 chat threads, any pairwise state.**
>     - ⭐⭐ **Put the atomic operation where atomicity is cheap, and durability where storage is cheap.** Redis decides; Cassandra remembers.
>     - ⭐ **Design tunable parameters, not fixed behaviour** — TTL, cache size, which users to warm. Operators tune without a rewrite.
>     - ⭐ **The client is part of the system** — when you can assume one device, it's a legitimate cache tier.
> - ⭐ **Re-run (cross-ref, NOT re-explained):** geospatial index choice (`04a`) · Elasticsearch + CDC (`05c §5.3`, `05e §5.4`) · precompute-then-serve (`05f §5.1`) · `userId` from the token not the body (`05c §3.3`) · bloom filter internals (`04b`). **Genuinely new:** Cassandra as primary + its partition design, **LWT/Paxos single-partition limits**, the **`user_pair`** key, the **Redis Lua atomic swipe**, **no pagination** (recommendations, not pages), **push notification for the asymmetric notify**, **stale-feed taxonomy**, **client-side swipe cache**, **bloom filter for the seen-set**.

---

## 0 · Understanding the problem

❤️ **What is [Tinder](https://tinder.com/)?**

Tinder is a mobile dating app that helps people connect by allowing users to **swipe right to like or left to pass** on profiles. It uses **location data and user-specified filters** to suggest potential matches nearby.

---

## 1 · Requirements

### 1.1 Functional (what it does)

1. ⭐ **Users can create a profile with preferences** (age range, interests) and specify a **maximum distance.**
2. ⭐ **Users can view a stack of potential matches** in line with their preferences and **within max distance of their current location.**
3. ⭐ **Users can swipe right / left on profiles one-by-one** — "yes" or "no".
4. ⭐ **Users get a match notification if they mutually swipe on each other.**

⚠ **Below the line (out of scope):** upload pictures · **chat via DM after matching** · "super swipes" / premium features.

> ▹ ⭐ **HI's scoping note:** this question is **mostly about the recommendation "feed" and the swiping experience**, not auxiliary features. ⭐⭐ **And the reusable rule:** if you're unsure what to focus on, have a brief back-and-forth with the interviewer — _"It'll typically be **the functionality that makes the app unique or the most complex**."_
> 
> ■ **— end of insert —**

### 1.2 Non-functional (how it behaves)

1. ⭐⭐ **Strong consistency for swiping.** If a user swipes "yes" on someone who **already** swiped "yes" on them, they **must get a match notification.** ▸ **This is the hard requirement of the problem.**
2. ⭐ **Scale — 20M daily actives, ~100 swipes/user/day** on average.
3. ⭐ **Stack loads with low latency — < 300ms.**
4. ⭐ **Avoid showing profiles the user has previously swiped on.**

⚠ **Below the line:** protect against fake profiles · monitoring / alerting.

▹ ⚠ **Note NFR #4 looks functional but is listed as non-functional** — it's a quality-of-experience constraint rather than a feature, and it gets its own deep dive (§5.3).

### 1.3 ⭐⭐ The design driver — two halves pulling opposite ways

- ▸ **The swipe path needs strong consistency** (NFR #1) but is **write-heavy at 2B/day.**
- ▸ **The stack path needs low latency** (NFR #3) over a **geospatial + multi-filter query.**

|Path|Volume|Needs|Therefore|
|---|---|---|---|
|**Swipe**|⭐ **2B/day, ~200GB/day**|⭐⭐ **atomicity on a pair of users**|**Cassandra for durability + Redis for the atomic check** (§5.1)|
|**Stack**|every app open|**<300ms over geo + filters**|**precomputed cache + Elasticsearch fallback** (§5.2)|

- ⭐⭐ **And the thing that makes the swipe half hard:** the contended state is **a pair of users**, not a row. ▸ **A→B and B→A are two different writes that must be read together** — which is exactly why the `user_pair` key (§5.1) is the whole answer.

### 1.4 Planning the approach

▸ **Build up sequentially through the functional requirements, then let the non-functional requirements drive the deep dives.** ▹ Same step as `05e §1.4` / `05d`.

---

## 2 · Core Entities

- ⭐ **User** — represents **both** the person using the app **and** a profile that might be shown to someone else. ▹ ⭐ **HI notes you'd normally omit "User" from an entity list, but include it here because users swipe on users.**
- **Swipe** — "yes" or "no" on a profile; belongs to a user (**`swiping_user`**) and is about another (**`target_user`**).
- **Match** — a connection between two users from mutual "yes".

---

## 3 · API

### 3.1 Create / update profile

```
POST /profile
{ "age_min": 20, "age_max": 30, "distance": 10,
  "interestedIn": "female" | "male" | "both", ... }
```

### 3.2 Get the stack

```
GET /feed?lat={}&long={}&distance={} -> User[]
```

- ⭐ **Age, interests etc. are NOT passed** — ▸ **the user already set them in app settings, so load them server-side.**
- ⭐⭐ **Location IS passed client-side, not persisted**, ▸ **because it always changes.** (Premium radius features are out of scope.)

> ⭐⭐ **Confusion resolved — why no pagination here, when every other feed problem has it?**
> 
> - ⭐ **HI: pagination is "superfluous for Tinder because we're really generating recommendations."** ▸ There is **no fixed result set to page through** — so rather than "paging", **the app just hits the endpoint again** when the current stack is exhausted.
> - ▹ ⚠ **Contrast `05g` News Feed**, where the cursor is load-bearing because the feed is an **ordered timeline** you walk backwards. ⭐ **A recommendation stack has no stable order to resume from.**
> 
> ■ **— end of insert —**

### 3.3 Swipe

```
POST /swipe/{userId}
{ "decision": "yes" | "no" }
```

- ⚠⚠ **The security trap, same as `05c §3.3`: do NOT take the caller's `userId` from the request body or headers — the client can forge either.** ⭐ **Validate the session token / JWT and use that to identify the current user.**
- ⭐⭐ **The `{userId}` in the path is the profile being swiped ON, not the account doing the swiping.**
- ▹ ⭐ **Worth saying: mark which endpoints need auth.** Here, **all of them do.**

---

## 4 · High-Level Design

### 4.1) Users can create a profile with preferences

```
Client ──► API Gateway & LB ──► Profile Service ──► Profile DB
            routing · auth                          Profile
            · rate limiting                           name · description
                                                      agePreference · genderPreference
                                                      maxDistance · …
```

1. Client `POST /profile` with the profile body.
2. Gateway routes to the **Profile Service.**
3. Profile Service **updates the user's preferences** in the database.
4. Result returned via the gateway.

### 4.2) Users can view a stack of potential matches

▸ On app open the user is immediately served a stack obeying **their filters** (age, interests) **and their location** (< 2 / 5 / 15 miles).

- ▸ **Start simple:** query the DB for users matching preferences **and** near the current location.

```sql
SELECT * FROM users
WHERE age BETWEEN 18 AND 35
  AND interestedIn = 'female'
  AND lat  BETWEEN userLat  - maxDistance AND userLat  + maxDistance
  AND long BETWEEN userLong - maxDistance AND userLong + maxDistance
```

- ⚠ **Flag it immediately:** this is **incredibly inefficient** — ⭐ **"searching by location in particular, even with basic indexing, would be incredibly slow."** → §5.2 (`04a`).
- ▹ ⭐ **Serving this feed efficiently is the key challenge of the system** — say that, then move on.

### 4.3) Users can swipe right / left

▸ **Two new components: a Swipe Service and a Swipe Database.**

> ⭐⭐ **Confusion resolved — why a separate service AND a separate DB here, when `05c`/`05d`/`05e`/`05f` all argued for sharing one?**
> 
> ⭐ **Three reasons, and they're the general decision rule:**
> 
> 1. ⭐ **Write-volume asymmetry.** Profile views and creation happen **far less often than swipe writes** → the swipe service can **scale up independently.**
>     
> 2. ⭐⭐ **Data volume.** 20M DAU × 100 swipes/day × ~100 bytes = **~200GB per day.**
>     
> 3. ⭐⭐ **A different engine is genuinely better.** Swipes want a **write-optimized store like Cassandra**, which is **"maybe not the right fit for our profile database."**
>     
> 
> - ▸ Plus: it enables **swipe-specific logic and caching strategies without affecting the profile service.**
> - ⭐ **HI's own hedge, worth repeating:** _"Separating isn't the right choice for all systems, but for this one the pros outweigh the cons."_
> - ⭐⭐ **So the rule across the series: share the database by default; split when the write pattern, the data volume, AND the ideal engine all differ.** ▸ **Here all three differ. In Yelp/Gopuff/Ticketmaster none did.**
> 
> ■ **— end of insert —**

- ⭐⭐ **Cassandra, partitioned by `swiping_user_id`** (`02e`). ▸ **"An access pattern to see if user A swiped on user B will be fast, because we can predictably query a single partition."**
- ⭐ **Why Cassandra handles the writes:** its **write-optimized storage engine — CommitLog + Memtables + SSTables.**
- ⚠ **The con we inherit: eventual consistency of swipe data.** → ⭐ **which is exactly what §5.1 has to fix.**

**The flow:**

1. Client `POST /swipe` with the profile ID and direction.
2. Gateway → **Swipe Service.**
3. Swipe Service **writes the swipe** to the Swipe DB.
4. Swipe Service **checks for an inverse swipe** and, if found, **returns a match** to the client.

### 4.4) Users get a match notification if they mutually swipe

▸ **Call the first swiper Person A and the second Person B.**

- ⭐ **Notifying B is free — we've already done it.** They swiped second, so **immediately after their swipe we check A's swipe** and, if it's a yes, show the **"You matched!"** graphic on B's device.
- ⭐⭐ **A is the hard one.** They may have swiped **weeks ago**, so we need a **push notification** — ▸ **APNS (Apple Push Notification Service)** or **FCM (Firebase Cloud Messaging).**

**The full recap:**

1. Some time in the past, **A swiped right on B** and we persisted it.
2. **B swipes right on A.**
3. Server **checks for the inverse swipe** — it exists.
4. **"You Matched!"** shown to **B** immediately.
5. ⭐ **Push notification via APNS/FCM to A.**

▹ ⭐ **This design is less concerned with the after-match flow** — you can skip match-storage details and **assume an external service handles push.** ⚠ **Clarify both assumptions with your interviewer.**

---

## 5 · Deep Dives

### 1) How can we ensure swiping is consistent and low latency? ⭐⭐

#### ⚠ The failure, spelled out — lead with this

> **A and B both swipe right at roughly the same time:**
> 
> 1. **A's swipe hits the server** → check for inverse → **nothing.**
> 2. **B's swipe hits the server** → check for inverse → **nothing.**
> 3. We save **A's swipe on B.**
> 4. We save **B's swipe on A.**
> 
> ⭐⭐ **Both swipes are stored, and the match was never detected.** ▸ HI: _"They will both go on forever not knowing that they matched and **true love may never be discovered.**"_

> ⭐⭐ **Confusion resolved — you could solve this WITHOUT strong consistency. Offer it, expect to be steered back.**
> 
> - ⭐ **The alternative:** a **reconciliation process** running periodically to find matching swipe pairs that were never processed as a match, then notify both users. ⭐ _"They won't be any the wiser and will just assume the other person swiped on them in that moment."_ ▸ **This prioritizes availability over consistency** (`01h`) and is **an interesting trade-off to discuss.**
> - ⚠ **But HI's own warning:** it **makes the problem slightly less challenging**, so _"there is a decent chance the interviewer will **appreciate the conversation but suggest you stick with prioritizing consistency**."_
> - ⭐ **How to play it: raise it as a deliberate alternative in one sentence, then design for consistency** — because the requirement says **notify the last swiper immediately.**
> 
> ■ **— end of insert —**

#### ⚠ Bad Solution — periodically poll for reciprocal swipes

- **Approach:** a job polls the database for reciprocal swipes and creates matches. ⚠ **A non-starter against "notify immediately" — but worth mentioning.**
- ⚠ **Challenges:** latency from the poll interval means **no immediate feedback**; ⭐ **"the timely dopamine hit associated with immediate match notifications is a critical component of the user experience"**; frequent polling puts **unnecessary load on the database.**

**Why climb:** the notification has to be synchronous with the swipe. Put the check in the write path.

#### Good Solution — a database transaction

- **Approach:** do the **swipe write and the reciprocal check in the same transaction**, so either both succeed or neither does.
- ⭐⭐ **Cassandra's "lightweight transactions" (LWT) — know the limits precisely** (`02e`, and `03b` covers them too):
    - Use a **Paxos consensus protocol** to give **linearizable consistency**…
    - ⚠ **…but only within a single partition.**
    - ⚠ **Unlike true ACID: no multi-partition atomicity, no isolation levels, no rollbacks.**
    - ⚠ **Significant performance overhead** — **multiple round trips between nodes** to reach consensus.
    - ⭐ **Verdict: fine for simple conditional updates, not for complex transactional workflows.**
- ⚠ **Challenge — scale.** **2B swipes/day cannot sit on a single partition**, so transactions would need to **span partitions**, which LWTs don't support.

**Why climb:** the limit is single-partition. So make the two swipes land in the _same_ partition by design.

#### ⭐⭐ Better Solution — the `user_pair` key (the best idea in this file)

- ⭐⭐ **The trick: make the partition key the _sorted pair_ of user IDs, so A→B and B→A are always in one partition.**

```sql
CREATE TABLE swipes (
    user_pair  text,       -- partition key: smaller_id:larger_id
    from_user  uuid,       -- clustering key
    to_user    uuid,       -- clustering key
    direction  text,
    created_at timestamp,
    PRIMARY KEY ((user_pair), from_user, to_user)
);
```

```python
def get_user_pair(user_a, user_b):
    # Sort IDs so (A->B) and (B->A) are in the same partition
    sorted_ids = sorted([user_a, user_b])
    return f"{sorted_ids[0]}:{sorted_ids[1]}"
```

- ▸ Then the insert **and** the reciprocal check go in one `BEGIN BATCH … APPLY BATCH` against that single partition.
- ⊕ ⚠⚠ **(not in HI) — HI's code here is not valid CQL.** A Cassandra `BATCH` takes only **INSERT / UPDATE / DELETE** — ⚠ **you cannot put a `SELECT` inside one.** ▸ The real way to do a conditional check in one partition is **LWT** (`IF NOT EXISTS` / `IF direction = …`), ⭐ **which puts Paxos round trips on every single swipe.** The _concept_ (co-locate the pair) is sound; the snippet isn't.
- ⭐ **Why it works: the partition key design eliminates cross-partition operations entirely**, so you get atomicity **without distributed-transaction complexity.**
- ⚠ **Challenges:**
    - **Partition growth** — as pairs accumulate swipe history, **partition sizes grow** and performance suffers.
    - ⭐ **Highly active users can create hot partitions.**
    - ▸ **So you need a cleanup strategy** — **archive or delete old swipe data** to keep partitions bounded.
    - ⊕ ⚠⚠ **(not in HI) — the flaw HI never mentions: `user_pair` partitioning breaks §5.3.** ▸ DD3's seen-set filter needs **"every profile user A has swiped on"**, and it says that's efficient _"because it will be routed to the appropriate partition based on `swiping_user_id`"_. ⚠ **With `user_pair` as the partition key you cannot query by `from_user` alone** — you'd need to know every pair A appears in, i.e. **a full cross-partition scan.** ⭐⭐ **So DD1's Better solution and DD3 contradict each other** unless you maintain a second table or index. ▸ **This is the strongest argument for the Redis solution below: it leaves Cassandra partitioned the way the rest of the design needs.**

**Why climb:** Cassandra can now do it, but it's doing a job it isn't built for — and paying Paxos round trips on every swipe.

#### ⭐ Great Solution — Redis for the atomic op, Cassandra for durability

- ⭐⭐ **The framing:** _"Cassandra excels at **durability and storing large amounts of data**, [but] it's **not designed for the kind of atomic operations we need** for real-time match detection."_ ▸ **So split the job.**
- ⭐ **Same key insight, different store:** swipes between the same users must land on the **same shard**, via a key that **combines both IDs consistently.**

```
Key:   "swipes:123:456"            # sorted, so both directions collide
Value: { "123_swipe": "right",
         "456_swipe": "left"  }    # a Redis HASH
```

```python
script = """
redis.call('HSET', KEYS[1], ARGV[1], ARGV[2])
return redis.call('HGET', KEYS[1], ARGV[3])
"""
other_swipe = redis.eval(script, keys=[key],
                         args=[f"{from_user}_swipe", direction,
                               f"{to_user}_swipe"])
if direction == 'right' and other_swipe == 'right':
    create_match(from_user, to_user)
```

- ⭐⭐ **The Lua script makes "record my swipe" and "check theirs" a single atomic operation** (`02a`) — consistency **plus** Redis's in-memory latency. ▸ **Scales horizontally; consistent hashing keeps related swipes together.**
- ⚠ **Challenges:**
    - **Managing the Redis cluster** — **node failures and rebalancing the consistent-hashing ring.** ⭐ **But "more manageable than trying to achieve consistency in Cassandra."**
    - ⭐⭐ **Memory management — and the answer is the best part of this dive:** since **Cassandra is the durable layer**, you can **be aggressive about expiring data from Redis.** Periodically **flush swipes to Cassandra** and keep only **recent** swipes in Redis.

> ⭐⭐ **The general pattern: put the atomic decision where atomicity is cheap, and the durable record where storage is cheap.** ▸ **Redis decides; Cassandra remembers.**
> 
> - ▹ ⭐ **Identical two-layer logic to `05e §5.1`** (Redis is the hold, Postgres is the guarantee) and `05f`'s Redis-durability answer (feeds are derived, so rebuildable). ⭐ **Three problems, one idea — a cache may be load-bearing for latency but must never be the only copy of truth.**
> 
> ■ **— end of insert —**

> ⚠⚠ **Confusion resolved — HI never mentions the Cassandra fallback, and without it the design is broken.** ▹ **This gap is why this dive is confusing on a first read.**
> 
> - ⚠ **HI's claim:** expire Redis aggressively; on loss _"users can always swipe again."_ ⚠⚠ **It doesn't hold:** A swiped B **a year ago**, entry expired ⇒ B swipes today ⇒ the Lua script finds nothing ⇒ **match lost forever.** ⭐ **And B cannot "swipe again" — A will never be shown B's profile again** (§5.3). **Breaks NFR #1.**
> 
> **⭐⭐ The unlock — Redis has TWO jobs, and only one of them matters:**
> 
> |Job|Needs|Hit rate|
> |---|---|---|
> |⭐ **A. Serialize concurrent swipes**|TTL > the race window (seconds)|⭐ **100% of the cases that matter**|
> |**B. Avoid a Cassandra read**|TTL in weeks|low — ⭐ **give up on it**|
> 
> - ⭐⭐ **So Redis is a serialization point, not a cache.** Single-threaded per key, and the Lua script is **one indivisible unit** ⇒ of two swipes on the same pair key, **one MUST observe the other.** ▸ **A guarantee, not a probability — true even 10ns apart.**
> 
> **⭐ The fallback** (B swipes A today; A swiped a year ago): ① **Cassandra write**, partition B ② **Redis Lua** → miss on A's side ③ ⭐ **point read Cassandra partition A for `A→B`** ④ ⭐ **idempotent match ID `min(A,B):max(A,B)`** so neither path double-creates ⑤ **refill Redis, short TTL.**
> 
> **⭐⭐ Why the fallback never races — and why the TTL number IS the argument:**
> 
> |Gap between the two swipes|Who answers|Atomic?|
> |---|---|---|
> |**ms – seconds**|⭐ **Redis** (both sides present)|⭐ **yes, the Lua script**|
> |**minutes – years**|**Cassandra** (reverse-partition point read)|**not needed — the other swipe is settled**|
> 
> - ⭐⭐ **The TTL is the boundary between the two jobs, and it must be comfortably longer than any window in which two swipes could be concurrent.** ▸ Race window = ms–seconds, TTL = 10 min ⇒ **nothing racy ever reaches Cassandra.** ⚠ **If anything racy could, the two-partition read would be unsafe and the whole design would break** — that is exactly why the number matters.
> 
> **⚠ Write order:** ⭐⭐ **Cassandra FIRST, then Redis** — synchronously per swipe, ⚠ **not HI's "periodic flush."** ▸ Redis-succeeds-but-Cassandra-fails = a match detected with **no durable swipe**, and §5.3 won't filter it ⇒ **the user sees that profile again.** The other order is harmless: the swipe is safe and only detection is missed ⇒ ⭐ **caught by the reconciliation sweep HI floated earlier in this dive.**
> 
> ■ **— end of insert —**

### 2) How can we ensure low latency for feed/stack generation? ⭐⭐

▸ The naive query from §4.2 won't hit **<300ms.**

#### Good Solution — an indexed / search-optimized database

- **Approach:** index the fields feed generation uses — **preferences, age range, and especially geospatial location.** ⭐ **A geospatial index efficiently retrieves users within a geographic area** (`04a`).
- ⭐ **Use a search-optimized store — Elasticsearch or OpenSearch** (`02b`): built for **fast search and complex querying** over large volumes with minimal latency.
- ⚠ **Challenge — keeping the index in sync with the primary DB.** Any delay or failure means **outdated profiles or missed new matches.** ▸ **Fix with CDC.**
- ⭐⭐ **And a point that's new versus `05c`/`05e`:** depending on the update rate, **batch the writes to the index** — ▸ **"Elasticsearch is optimized for read-heavy workloads, not write-heavy workloads."** ⚠ **Relevant here because profiles and locations change constantly.**

#### Good Solution (alternative) — pre-compute and cache feeds

- **Approach:** **periodic background jobs** generate feeds from preferences and location, stored in a **cache for instant retrieval** on app open. ⭐ **Pre-computation can be scheduled off-peak** to spare system resources.
- ⚠ **Challenges:**
    - ⭐ **Highly active users quickly exhaust their cached feed** → delays while new matches are generated.
    - **Pre-computed feeds miss recent changes** — profiles, preferences, new users.
    - ⭐⭐ **And the killer: "if the user swipes through their pre-computed cached stack, we need to run the expensive query again"** — inefficient and slow.

**Why climb:** one gives freshness without instant load; the other gives instant load without freshness. Use both.

#### ⭐ Great Solution — cached stack, with Elasticsearch as the overflow

- ⭐ **Approach:** **pre-compute and cache** feeds periodically → the user gets an **instant** stack on open. **As they swipe through and exhaust it, the system transitions seamlessly to real-time generation via Elasticsearch.**
- ⭐⭐ **And the detail that makes it feel magic: trigger the refresh when the user has only a few profiles left** → ▸ **"as far as the user is concerned, the stack seemed infinite."**

#### ⭐⭐ The sub-problem: stale feeds

> ⭐ **HI names this explicitly — a _stale profile_ is one that no longer fits the user's filter criteria.**

- ⚠ **Two ways a cached profile goes stale on its own:**
    1. The **suggested user changed location** and is no longer close enough.
    2. The **suggested user changed their profile** (e.g. interests) and no longer fits.
- ⭐ **Fixes:**
    - **A strict TTL on cached feeds (< 1h)** plus **scheduled background recomputation.**
    - ⭐⭐ **Pre-compute only for users active within a chosen window, not everyone.** ▸ _"Doing upfront work for a user feed several times a day will be expensive at scale, so we might **warm these caches only for users we know will eventually use** the cached profiles."_
- ⚠ **Two user-triggered causes — both should trigger a background refresh:**
    
    1. **The viewing user changes their filter criteria.**
    2. **The viewing user changes location significantly** (different neighbourhood or city).
    
    - ▸ ⭐ **Refresh in the background so the feed is ready if they start swiping shortly after.**

> ⭐⭐ **The design principle attached here — genuinely reusable, and this is the only file in the series that states it.**
> 
> - ⭐ _"It's very useful if the system has **parameters that can be tuned without changing the overall logic** of the system… This gives the operators **strong control over the health of the system without having to rework the system itself.**"_
> - ⭐ **The tunables in this design:** the **TTL** for cached profiles · the **number of profiles** cached · **which users** get warmed caches.
> - ▹ **Say it in the room:** _"I'd make the TTL, stack size and the warm-set membership configuration rather than code, so this can be tuned under load without a redesign."_
> 
> ■ **— end of insert —**

### 3) How do we avoid re-showing profiles the user already swiped on? ⭐

▸ **Why it matters:** re-showing a profile makes users think **their "yes" wasn't recorded**, or just annoys them by resurfacing people they said "no" to.

#### Good Solution — query the swipe DB and do a contains check

- **Approach:** the feed builder queries the Swipe DB and **filters out already-swiped users.** ⭐ **Efficient, because it routes to a single partition by `swiping_user_id`.**
- ⚠ **Two challenges:**
    1. ⭐ **In an availability-skewing system, not all swipe data has landed in every replica** by feed-generation time → **you can miss swipes and re-show profiles.**
    2. ⭐ **A long swipe history returns a lot of user IDs, and the contains check gets progressively more expensive.**

**Why climb:** the freshest swipes are the ones most likely to be missing from replicas — and the client already knows them.

#### Better Solution — a client-side swipe cache

- ⭐⭐ **Approach: keep the recent-swipe cache on the client, not the backend.** ▸ _"Managing a cache on the backend merely to store data before it 'lands' on all partitions in a NoSQL system would be expensive. We can take advantage of the fact that **the client is part of the system**."_ The client stores the **K most recent swipes** and filters suggestions itself.
- ⭐ **Doubly useful for stack depletion.** Swiping through 200 prefetched profiles, at about #150 the client can:
    1. **Ping the backend** to generate a new feed.
    2. **Request that feed** once it's ready.
    3. ⭐ **Filter out any profiles the user swipes on in the meantime.**
- ⭐⭐ **The assumption that licenses this — state it out loud:** _"the user is only using this app on one device."_ ▸ **That's what makes the client a legitimate cache tier.**

> ⊕ **What "client-side cache" means here, and why the backend lags:**
> 
> - ▸ **Data stored locally in the app on the user's phone**, not on the backend — the recently-swiped IDs, e.g. `swipedIds = {user_22, user_45, user_91}`. When the server returns a new feed, **the app strips those IDs before rendering.**
> - ⚠ **The lag scenario:** A swipes left on B → **the write is accepted by one Cassandra replica** → the feed service then reads A's history **from another replica that is briefly behind** → B isn't in it → **B gets served again.** ⭐ **Cassandra is masterless: any node accepts the write, but replicas sync asynchronously unless you raise the read/write consistency levels.** ▸ **The phone already knows, so it filters B out.**
> - ⭐ **Not the same cache as §5.1's Redis:** that one is **server-side pair state** (`swipes:A:B`) for atomicity; this one lives **only on A's phone** and holds **A's recent swipes** for de-duplication.
> 
> ■ **— end of insert —**

- ⚠ **Still vulnerable to** very large swipe histories and slow contains checks.

**Why climb:** the client can hold recent swipes, not years of them.

#### ⭐ Great Solution — a bloom filter for heavy swipers

- ⚠⚠ **HI's own framing, which you should repeat:** this _"skews somewhat **over-engineered**, but is a legit use case for a bloom filter."_ ⭐ **And `04b` says the same thing harder: reaching for a bloom filter when a plain hash table would do is a red flag. So gate it.**
- **Approach:** **once a user's swipe history exceeds a size** that makes cache storage unwieldy or contains checks slow, **build and cache a bloom filter for that user** and use it in the filtering step (`04b`).
- ⭐⭐ **Why the error direction is exactly right here:**
    - **False positives happen** → we sometimes think a user swiped when they didn't → ⭐ **a small number of profiles are never shown.**
    - ⭐⭐ **False negatives never happen** → ▸ **we never re-show a profile they actually swiped on.**
    - ⭐ **The acceptable failure is the one that costs nothing.** Missing a few candidates in a pool of millions is invisible; re-showing a profile is the exact bug we're fixing.
- ⭐ **Tunable:** bloom filters trade **error rate against space** — tune for **low false positives, reasonable space, fast filtering.**
- ⚠ **Challenge: managing the filter cache** — it must be **updated** and **recovered if the cache goes down.** ⭐ **Easy to rebuild from swipe data, but expensive at scale during a node outage.**

---

## 6 · Final Design

```
Client  (⭐ holds the K most recent swipes — client-side filter)
  │
  ▼
API Gateway & LB  (routing · auth · rate limiting)                      02d
  │
  ├──► Profile Service ──► Profile DB
  │       setProfile()       Profile: name · description · agePreference
  │       getStack()                  genderPreference · maxDistance
  │          │
  │          ├──► Stack Cache ◄──Cron── (pre-computed feeds, TTL < 1h,
  │          │                           warmed only for recently-active users)
  │          │
  │          └──► Elasticsearch ◄──CDC(batched)── Profile DB              02b
  │                 geospatial index + age/interest filters               04a
  │                 (the overflow path when the cached stack runs out)
  │
  └──► Swipe Service ──┬──► Redis   ⭐ atomic swipe + match check (Lua)    02a
          swipe(y|n)   │             key "swipes:{min}:{max}" → HASH
                       │             recent swipes only, aggressively expired
                       │
                       ├──► Swipe DB (Cassandra)  ⭐ durable record        02e
                       │      partition: user_pair = smaller_id:larger_id
                       │      CommitLog + Memtable + SSTable
                       │
                       ├──► Swipe Cache + Bloom filter  (seen-set filtering) 04b
                       │
                       └──► Push Notification Service (APNS / FCM)
                              → notifies Person A, who swiped weeks ago
```

---

## 7 · Expected at Each Level

|Level|The bar for Tinder|
|---|---|
|**Mid (E4)**|API endpoints + data model defined; HLD **functional for feed creation, swiping and matching.** In-depth tech knowledge **not** expected, but ⭐ **must support both traditional filters and geospatial filters**, and ⭐ **must design something to avoid re-showing swiped profiles**|
|**Senior (E5)**|⭐ **Quickly through the HLD**, then detail on **efficient/scalable feed generation and management** and **ensuring successful match creation.** ⭐⭐ **Proactive on feed-building trade-offs**, knows **which index type** powers the feed, and ⭐ **is aware of when feed caches go stale**|
|**Staff+**|Detail on **each** topic above; ⭐ **may steer the conversation** toward something they find interesting; solid grasp of trade-offs between solutions, ⭐⭐ **articulated treating the interviewer as a peer**|

---

## Quick Recall (pass 3+)

|Use / Question|Tinder answer|
|---|---|
|Calibration|⭐ Joseph Antonakakis · **medium** · ⭐ **asked at Amazon** · ⚠ **no "Pattern:" callouts in this write-up**, but **geo + contention + feed-precompute converge.** ⭐⭐ **Only problem in the series using Cassandra as the primary store.** Score points: ⭐⭐ **`user_pair` sorted key** · **Redis atomic + Cassandra durable** · **cached stack + ES overflow** · **stale-feed taxonomy + tunables** · **client-side swipe cache** · **bloom filter (gated)** · **separate service AND DB**|
|⭐⭐ Design driver|**two halves pulling opposite ways.** **Swipe:** 2B/day, ~200GB/day, needs ⭐ **atomicity on a PAIR of users** (not a row) → **Cassandra + Redis.** **Stack:** every app open, **<300ms over geo + filters** → **precomputed cache + ES.** ⭐ **A→B and B→A are two writes that must be read together — that's why `user_pair` is the answer**|
|FRs|profile + preferences + **max distance** · **stack** within preferences and distance of **current location** · **swipe left/right one-by-one** · **match notification on mutual yes.** Below: pictures · DM chat · super swipes/premium|
|NFRs|⭐⭐ **strong consistency for swiping** (match notification must fire) · **20M DAU, ~100 swipes/day** · **stack < 300ms** · ⭐ **never re-show a swiped profile.** Below: fake profiles · monitoring|
|📐 Numbers|**20M × 100 = 2B swipes/day**; **× 100 bytes = ~200GB/day.** ⚠ **ignore the "200 swipes/day → 4B" line — the NFR, the storage math and DD1 all use 100 → 2B**|
|⭐ Scoping rule|_"it'll typically be **the functionality that makes the app unique or the most complex**"_ — ask the interviewer if unsure what to focus on|
|Entities|⭐ **User** (both the app user **and** a shown profile — HI includes it specially **because users swipe on users**) · **Swipe** (`swiping_user` → `target_user`) · **Match**|
|API|`POST /profile {age_min, age_max, distance, interestedIn}` · `GET /feed?lat&long&distance → User[]` · `POST /swipe/{userId} {decision}`. ⭐ **filters loaded server-side, NOT passed** · ⭐⭐ **location passed client-side, never persisted — it always changes** · ▹ **mark that all endpoints need auth**|
|⭐⭐ Why NO pagination|_"superfluous… **we're really generating recommendations**"_ — **no fixed result set to page.** The app just **hits the endpoint again.** ▹ ⚠ **contrast `05g`**, where the cursor is load-bearing because the feed is an **ordered timeline**|
|⚠⚠ API security|**never take the caller's `userId` from the body or headers — the client can forge either.** ⭐ **Validate the JWT/session.** ⭐⭐ **`{userId}` in the path = the profile being swiped ON**|
|⚠ Naive stack query|`age BETWEEN … AND interestedIn = … AND lat/long BETWEEN …` → **incredibly inefficient**; ⭐ **"location in particular, even with basic indexing, would be incredibly slow"** → §5.2 / `04a`|
|⭐⭐ Separate service AND DB|**the one problem in the series where splitting wins. Three reasons, all must hold: (1)** profile reads ≪ swipe writes ⇒ independent scaling **(2)** ⭐ **~200GB/day** **(3)** ⭐ **a different engine is better — Cassandra, "maybe not the right fit for the profile DB."** ⭐ HI: _"separating isn't right for all systems, but here the pros outweigh the cons."_ ▸ **rule: share by default; split when write pattern + data volume + ideal engine ALL differ**|
|⭐ Cassandra choice|**partition by `swiping_user_id`** ⇒ "did A swipe on B?" is **a single-partition query.** ⭐ **write-optimized engine: CommitLog + Memtables + SSTables.** ⚠ **con inherited: eventual consistency** → §5.1|
|⭐ Match notification|**B is free** — second swiper, so check A's swipe right after and show **"You matched!"** instantly. ⭐⭐ **A is the problem** — swiped weeks ago ⇒ **push via APNS / FCM.** ▹ after-match flow + push service assumed external — **clarify both**|
|⚠⚠ DD1 the race|A swipes → check inverse → **nothing** · B swipes → check inverse → **nothing** · save A→B · save B→A. ⭐⭐ **both stored, match never detected** — _"true love may never be discovered"_|
|⭐⭐ DD1 the non-consistent option|**reconciliation job** finds unprocessed matching pairs and notifies both — _"they won't be any the wiser."_ ⚠ **but it makes the problem easier, so expect the interviewer to steer you back to consistency.** ⭐ **raise it in one sentence, then design for consistency**|
|⚠ DD1 Bad — polling|**non-starter** (no immediate notification) but **worth mentioning.** ⭐ _"the timely **dopamine hit** of immediate match notifications is a critical component of the UX"_; polling also loads the DB|
|DD1 Good — transaction|⭐⭐ **Cassandra LWT: Paxos, linearizable — but SINGLE PARTITION only.** ⚠ **no multi-partition atomicity, no isolation levels, no rollbacks**, and **multiple node round trips ⇒ significant overhead.** ⭐ fine for **simple conditional updates**, not workflows. ⚠ **2B swipes/day can't fit one partition ⇒ would span partitions ⇒ unsupported**|
|⭐⭐ DD1 Better — `user_pair`|⭐⭐ **partition key = the SORTED pair, `smaller_id:larger_id`**, so **A→B and B→A always land in one partition** → `PRIMARY KEY ((user_pair), from_user, to_user)`, insert + check in one `BEGIN BATCH`. ⭐ **eliminates cross-partition operations entirely.** ⚠ **partitions grow unbounded** + **hot partitions for active users** ⇒ **need an archive/delete cleanup strategy**|
|⭐ DD1 Great — Redis + Cassandra|⭐⭐ _"Cassandra excels at durability… **not designed for the atomic operations we need**."_ Key **`swipes:{min}:{max}`** → **HASH** with both users' swipes; ⭐ **Lua script HSET+HGET = one atomic op**; consistent hashing keeps pairs together. ⚠ cluster ops: **node failure + ring rebalancing** (still easier than consistency in Cassandra)|
|⭐⭐ The two-layer pattern|**atomicity where it's cheap, durability where it's cheap — Redis decides, Cassandra remembers.** ▹ same shape as `05e §5.1` (Redis = the hold, Postgres = the guarantee) and `05f` (feeds are derived ⇒ rebuildable). ⭐ **a cache can be load-bearing for latency but must never be the only copy of truth**|
|⚠⚠ HI is WRONG on expiry|HI: _"expire aggressively… users can always swipe again."_ ⚠⚠ **A swiped B a year ago, entry expired ⇒ B swipes today ⇒ Lua finds nothing ⇒ match lost forever**, and **B can't "swipe again" — A will never be shown B again** (§5.3). ⭐ **HI never mentions the Cassandra fallback — that omission is why this dive confuses on first read**|
|⭐⭐ Redis has TWO jobs|**(A) serialize concurrent swipes** — needs TTL > the race window (seconds), ⭐ **100% hit rate on the cases that matter** · **(B) avoid a Cassandra read** — needs weeks, low hit rate, ⭐ **give up on it.** ⭐⭐ **So Redis is a SERIALIZATION POINT, not a cache**: single-threaded per key + Lua is **one indivisible unit** ⇒ **one of two swipes MUST observe the other.** A guarantee, not a probability|
|⭐⭐ The fix|Cassandra keeps history by **`swiping_user_id`** (the §4.3 design, **not** `user_pair`). **B swipes A today:** ① atomic write+check Redis pair key → ② **Redis miss on A's side ⇒ read Cassandra partition A for `A→B`** → ③ found → ④ ⭐ **idempotent match ID `min(A,B):max(A,B)`** so neither path double-creates → ⑤ **refill Redis, short TTL.** ⭐ slower, **but only on expiry/loss**|
|⭐⭐ Why the fallback is safe|**the two paths cover DISJOINT cases.** **ms–seconds ⇒ Redis** (both sides present, Lua atomic) · **minutes–years ⇒ Cassandra** (reverse-partition point read, **not atomic and doesn't need to be — the other swipe is settled**). ⭐⭐ **The TTL is the BOUNDARY between the two jobs and must be comfortably longer than any concurrency window** — race window ms–seconds vs TTL 10 min ⇒ **nothing racy ever reaches Cassandra.** ⚠ **if it could, the two-partition read would be unsafe and the design would break**|
|⚠ Write order|⚠ **Redis-first + async flush** (HI's implication) leaves a window where the swipe is **only in Redis** ⇒ node failure loses it — **that window is why HI needed the weak "swipe again" line.** ⭐⭐ **write Cassandra FIRST, then the Redis atomic op** — Cassandra is write-optimized, so it isn't the bottleneck. **Durable before coordinated.** ⭐ Redis step fails ⇒ swipe safe, only detection missed ⇒ **caught by the reconciliation sweep** HI floated earlier|
|⊕⚠⚠ `user_pair` breaks §5.3|DD3's seen-set filter needs **"all profiles A swiped on"**, routed by **`swiping_user_id`**. ⚠ **With `user_pair` as partition key you can't query `from_user` alone ⇒ cross-partition scan.** ⭐⭐ **DD1-Better and DD3 contradict each other** unless you keep a second table/index — ▸ **the strongest argument for the Redis solution, which leaves Cassandra partitioned the way the rest of the design needs.** ⊕ ⚠ **also: HI's `BEGIN BATCH … SELECT … APPLY BATCH` is invalid CQL** — a BATCH takes only INSERT/UPDATE/DELETE, so the real version needs **LWT ⇒ Paxos on every swipe**|
|DD2 Good — indexed store|index **preferences, age, especially geospatial** (`04a`); **Elasticsearch/OpenSearch** (`02b`); ⚠ **sync via CDC.** ⭐⭐ **new vs `05c`/`05e`: BATCH the index writes — "Elasticsearch is optimized for read-heavy, not write-heavy"**, and profiles/locations change constantly|
|DD2 Good — precompute|**cron jobs build feeds into a cache**, ⭐ **schedulable off-peak.** ⚠ **active users exhaust the cache** · **misses recent profile/preference/new-user changes** · ⭐⭐ **exhausting the stack means re-running the expensive query**|
|⭐ DD2 Great — both|**cached stack for instant open + Elasticsearch for the overflow.** ⭐⭐ **refresh when only a few profiles remain → "the stack seemed infinite"**|
|⭐⭐ DD2 stale feeds|**stale = no longer fits the filter criteria.** **On its own:** suggested user **moved** · suggested user **changed profile.** ⭐ fixes: **strict TTL < 1h** + scheduled recompute; ⭐⭐ **warm caches only for recently-active users** (upfront work several times a day is expensive at scale). **User-triggered:** viewer **changes filters** or **moves significantly** ⇒ **trigger a background refresh**|
|⭐⭐ DD2 tunables principle|_"parameters that can be **tuned without changing the overall logic**… operators get **strong control over system health without reworking the system**."_ ⭐ here: **TTL · stack size · which users get warmed.** ▹ only file in the series that states this|
|DD3 Good — DB contains check|query Swipe DB, filter swiped users; ⭐ **efficient — single partition by `swiping_user_id`.** ⚠ **(1)** availability-skewed ⇒ **swipes not yet in all replicas ⇒ re-showing** **(2)** ⭐ **long history ⇒ many IDs ⇒ contains check gets progressively slower**|
|⭐⭐ DD3 Better — client cache|⭐ **cache the K most recent swipes ON THE CLIENT** — _"managing a backend cache merely to hold data before it lands on all partitions would be expensive; **the client is part of the system**."_ ⭐ **also powers prefetch: at ~#150 of 200, ping → fetch → filter what's swiped meanwhile.** ⭐⭐ **the licensing assumption: "the user is only using this app on one device" — say it out loud**|
|⭐ DD3 Great — bloom filter|⚠⚠ **HI: "skews somewhat over-engineered, but a legit use case"**; ⭐ **`04b`: a bloom filter where a hash table would do is a RED FLAG ⇒ gate it** on swipe history exceeding a size. ⭐⭐ **false positives yes, false negatives NEVER** ⇒ **a few profiles never shown, but never a re-show.** ⭐ **the acceptable failure is the one that costs nothing.** Tunable **error rate vs space.** ⚠ must be **updated and recoverable** — cheap to rebuild from swipe data, **expensive at scale during an outage**|
|Levels (short)|**E4:** API + data model + working feed/swipe/match; ⭐ **must handle both normal and geospatial filters**, and **must avoid re-shows** · **E5:** fast HLD then **feed generation + match creation in detail**, **proactive on trade-offs**, **knows the index type**, ⭐ **aware of stale caches** · **Staff+:** depth on all of it, **may steer**, **treats the interviewer as a peer**|

---

> 🔗 **HI source:** https://www.hellointerview.com/learn/system-design/problem-breakdowns/tinder
> 
> ✅ **Source complete** — all FRs/NFRs, the planning step, entities, API, four HLD sections, DD1's four rungs plus the availability alternative, DD2's three rungs plus the stale-feed sub-problem, DD3's three rungs, the final design and all three level bars are reconciled against the original. **No known gaps.**