# FB News Feed — Delta from Instagram (`05f`)

> ⭐⭐ **What this file is.** Everything in `05g` (FB News Feed) that is **NOT** already in `05f` (Instagram). ▸ **How to use it: revise `05f` Instagram as the canonical feed design, then read this. Skip the full `05g` unless you have spare time.** File `05g-Δ`.
> 
> ⚠ **What this file deliberately leaves out — because `05f` already covers it:**
> 
> - The three functional requirements (create post · follow · view feed) → `05f §1.1`
> - **Fan-out on read → fan-out on write → hybrid** — the whole ladder and why read-time fan-out fails → `05f §5.1`
> - The **Follows GSI reversal** ("who do I follow" vs "who follows me") → `05f §4.3` + its Tutor Q&A
> - The **Post GSI** on `creatorId` + `createdAt` → `05f §4.3`
> - **Async queue + fan-out workers** → `05f §5.1` write flow
> - The **celebrity carve-out** and threshold tuning → `05f §5.1` Great Solution
> - The **shared-database-across-services** argument → `05f §4.2`
> - **Media, S3, CDN, variants** — ⚠ **entirely out of scope in News Feed**, so Instagram is strictly richer there
> 
> ⭐ **Net: about 10 additions. One is big (§5), the rest are a line or two each.**
> 
> ⭐⭐ **If you read one thing, read §5.** It is the **only** place in either file where the **hot-key problem is solved** — and ⚠ **Instagram's design has that problem and never addresses it.** ▸ **Your interview answer = Instagram's architecture + §5 grafted on** (the script is in §5's last block).

---

## 1 · Requirement differences

- ⚠ **Uni-directional "follow", not bi-directional "friend."** ⭐ Say it out loud — **it halves the problem**, since a friend edge needs both directions written and agreed.
- ⭐ **Feed is explicitly reverse chronological (newest first)**, and ⭐ **"page through the feed" is a fourth functional requirement in its own right** — Instagram treats paging as an API detail.
- ⭐⭐ **NFR: unlimited follows AND unlimited followers.** ▸ **This single requirement is what creates both deep dives** — following thousands breaks the read side, having millions of followers breaks the write side.
- ⭐⭐ **NFR: ≤ 1 minute of staleness.** ▸ **This is a resource, and the async fan-out spends it.** ⭐ **Without that budget, none of the queue-based write path is legal.** Say the connection out loud; it shows the NFRs are driving the design.
- Scale is stated as **2B users** (vs Instagram's 500M DAU / 100M posts/day).

> ⭐⭐ **The NFR lesson — not in `05f` at all:** _"Having **quantities** on your non-functional requirements will help you make decisions during your design. A system which is **single-digit millisecond** fast requires a **dramatically different architecture** than a 'fast' system which can take a second to respond."_
> 
> ▹ ⭐ **So never write "low latency" — write a number.** The number is what lets you _reject_ designs instead of debating them.
> 
> ■ **— end of insert —**

---

## 2 · API differences

- ⭐⭐ **`PUT /users/[id]/follow`, not `POST`.** ▸ The follow action is **binary**, so `PUT` makes it **idempotent** — it doesn't fail if the user double-clicks. Unfollow would be `DELETE`. ⭐ **Cheap, high-signal detail; most candidates reach for `POST` by reflex.** ▹ Instagram uses `POST /follows`.
- ⭐⭐ **The cursor mechanism, spelled out** (Instagram only says `?cursor=`):

```
GET /feed?pageSize={size}&cursor={timestamp?}
-> { items: Post[], nextCursor: string }
```

- ▸ **The cursor is a timestamp — the oldest post the user has already seen.**
- ⭐ **Why a timestamp works:** the feed is **reverse chronological**, so paging moves **backwards in time**. Each page returns **N posts older than the cursor.**
- ⭐ **No new index needed** — the Post GSI already sorts by `createdAt`.
- ⊕ **Why cursor beats offset here (you said this yourself):** new posts arrive constantly, so `OFFSET` shifts under you and you get duplicates or skips. **A timestamp is a fixed point in the data, not a position in a result set.**

---

## 3 · High-level design additions

### ⭐⭐ Why NOT a graph database — Instagram never discusses this

- ⭐ **Graph databases earn their keep on traversals and comprehensions** — stepping between nodes, friends-of-friends, building embeddings for recommendations.
- ▸ **We have none of that. Our queries are one hop deep.**
- ⭐⭐ **HI's honest reason, worth borrowing nearly verbatim:** keeping it simple _"saves ourselves from scarier questions like **'how do you scale Neo4j?'**"_ ▸ ⚠ **Don't introduce a technology you can't defend under pressure.**

### ⭐ The three Follow queries, named

|Question|How|
|---|---|
|**Is A following B?**|query with **both PK and SK** → ⭐ **a point lookup**|
|**Who does A follow?**|query the **PK** → range query|
|**Who follows A?**|query the **GSI** by its PK → range query ▸ _the write-side fan-out query_|

▹ ⭐ **AWS actually recommends single-table design for DynamoDB**; separate tables keep the interview discussion clearer. **Saying that shows you know the real practice and chose clarity deliberately.**

---

## 4 · Deep-dive additions

### ⭐⭐ Ask whether the product can change — nothing like this in `05f`

- ⭐ **HI's question: _"can we adjust the product in these instances?"_** ▸ **Facebook caps friends at 5,000.** Setting a max on follows, or giving tail users a slightly different experience, is _"a very common approach for production systems."_
- ⭐⭐ **The line that makes the case:** _"Is your user with 100k follows really going to notice if their posts are appearing a couple of minutes late?"_
- ▹ ⭐ **Same senior/staff move as `05e §5.3`'s waiting queue — sometimes the answer is to change the requirement, not out-engineer its tail.** ⚠ **But ask; don't assume you may.**

### ⭐ The 1000s-of-requests calibration

- ⭐⭐ _"It's not uncommon to generate **10s to 100s of requests** to satisfy an incoming request, but it is **rarer to have to generate 1000's of requests**, especially for a service that needs to serve users with low latency."_
- ▹ **Use it to justify abandoning fan-out on read with a threshold rather than an assertion.** ⭐ Instagram justifies the same pivot via DynamoDB's batch limits (100 items / 16MB) — **two different framings of the same conclusion; either works.**

### ⭐⭐ The 200-post cap and the fallback — Instagram's ZSET has no cap

- ⭐ **`PrecomputedFeed` is keyed by `userId`, value = postIds in reverse chronological order, capped at ~200.** Keep entries **compact** to minimize space. ⭐ **No secondary index needed — it's only ever read by userId.**
- ⭐⭐ **"But what if someone pages 100 pages deep?"** → **most systems simply don't support it.** _"Try to go a few dozen pages deep into Google."_ ▸ **Real users aren't doing this.**
- ⭐⭐ **And there's a safety net: fall back to the naive Follow + Post query** for anyone who reaches the end of their precomputed feed. ▸ **So the naive design isn't thrown away — it becomes the cold path.** ⭐ **Say that; it makes the design read as considered rather than replaced.**
- ⊕ **This is the piece that completes the paging story:** the cursor walks the precomputed feed until it runs out, then the same cursor keeps working against the base tables. **Instagram cannot answer "what happens at page 11."**

### ⭐⭐ Feed sizing, and the cost rule-of-thumb

|||
|---|---|
|One postId|**10 bytes**|
|200 posts/user|**2KB per user**|
|× 2B users|⭐ **4TB total**|

- ▸ **Every precomputed feed on Earth fits in 4TB.** _"Quite reasonable for a modern system."_
- ⭐⭐ **The technique to steal — price it per user in dollars:** _"ask how much a given user, tenant, or item is going to cost in dollars. **2KB is a fraction of a cent per month** and Facebook earns something like **$100 per year for US-based users.**"_ ▸ ⭐ **A unit-economics check persuades far better than a byte count, and almost nobody does it.** ▹ Instagram sizes **media** (200TB/day, 750PB/10yr) but never sizes the **feed store.**

### ⚠ The Bad rung Instagram skips — blast the writes synchronously

- **Approach:** Post Service writes to every follower's feed at post time. ⚠⚠ **HI: "This will fail."**
- ⚠ **Why:** **connection limits** on a single host plus the latency budget — and ⭐ **even if it works, load is wildly uneven: one host writing to millions of feeds while another sits idle.** ▸ **The unevenness is what makes it unscalable, not just the volume.**

### ⭐ Queue requirements, and variable work per item

- ⭐ **State the queue's requirements:** **at-least-once delivery** + **highly scalable** → **SQS** works. Enqueue **postId + creatorId**; workers read the Follow GSI and **prepend to each follower's feed.**
- ⭐⭐ **Variable work per queue item — Instagram never raises this.** One message for a **1M-follower** account is dramatically more work than one for **1k followers.** ▸ ⭐ **"We may need to break up these tasks."**
- ⊕ **Why it matters:** with wildly uneven item cost, **one fat message blocks a worker for minutes** while the queue backs up. Chunking (e.g. 10k followers per message) keeps worker time bounded and lets you hit the 1-minute budget.

### ⭐⭐ The `precomputed` flag lives on the Follow row, not the User

- ⭐ **Mechanism:** add a **`precomputed` flag to the Follow table** marking that this particular follow **isn't** precomputed. **Workers skip those follows.** On read, the Feed Service **merges the partially precomputed feed with recent posts from the non-precomputed accounts.**
- ⭐⭐ **HI states it as a principle:** _"choose whether we fan out on read or fan out on write **on a per-account basis**, and for most users we'll do a little of both… **in most situations we don't need a one-size-fits-all solution.**"_

> ⊕ **(not in HI) — why the relationship beats the user record, and why I'd use this version in both interviews.**
> 
> - ▸ `05f` Instagram flags the **celebrity** (`followerCount` / `isCelebrity` on the **User**). `05g` flags the **relationship** (`precomputed` on the **Follow row**).
> - ⭐⭐ **The read path is the argument.** The Feed Service already queries _"who does this user follow?"_ — ⭐ **so with the flag on the Follow row, the non-precomputed followees come back in that same query, free.** With the flag on the User record you get the followee list, then need **a second lookup per followee** to discover which are celebrities.
> - ⭐ **The write path works either way** — the worker reads the Follow rows anyway to know whose feeds to update.
> - ⚠ **The cost is denormalization:** a user crossing the threshold means **backfilling every one of their Follow rows**, not updating one User field. ▸ For 99k → 101k followers that's a 100k-row update — ⭐ **fine as a background job, since the flag only changes when someone crosses the line.**
> - ⭐ **The line to say:** _"I'd put the flag on the relationship rather than the user, so the read path gets it in a query it already makes."_
> 
> ■ **— end of insert —**

---

## 5 · ⭐⭐ The one genuinely big addition — uneven reads of Posts (hot keys)

> ⭐⭐ **No equivalent in `05f` at all. If you read nothing else in this file, read this.**

### The problem

- ▸ **Most posts are read for a few days and never again.** Some — especially from high-follower accounts — take **massive reads in the first few hours.**
- ⭐⭐ **A viral post means millions of reads for ONE key.**
- ⭐⭐ **Why that specifically breaks DynamoDB (and most KV stores):** they deliver huge throughput **only when load is even across the keyspace.** ▸ **Underneath are physical machines with real limits.** One scorching key means **one partition absorbs all that traffic, and that partition's ceiling becomes your ceiling.** ⭐ **HI's example: "If Post1 gets 500 requests per second and Post2 through Post1000 get 0 requests per second, this is not even load!"**
- ▹ ✅ **One thing in our favour: posts are created far more often than edited** — which is what makes long cache TTLs safe.

### Good Solution — a distributed (sharded) post cache

- **Approach:** cache between the readers and the Post table. **Long TTL** (posts rarely change), **LRU eviction.** ⭐ **With N hosts × M memory it holds as many posts as fit in N×M.** Redis, **keyed by postId** so posts spread evenly.
- ⭐ **Invalidation is easy: invalidate on _edit_, not on create.**
- ⚠⚠ **Challenge — the whole point of the next rung: the cache has exactly the same hot-key problem the table had.** ▸ Keying by postId means **the viral post lives on exactly one Redis node.** That node melts; ⭐ **many other hosts sit underutilized.** You moved the hot spot, you didn't remove it.

**Why climb:** sharding spreads **data** evenly. It does nothing for **traffic concentrated on one key** — by definition that key lands on one shard.

### ⭐ Great Solution — a replicated post cache

- ⭐⭐ **The key difference: instead of a sharded cache where each post lives on exactly one node, use replicated instances where _every instance can serve any post._**
    - A **load balancer** spreads requests across the instances.
    - ⭐ **Each handles a fraction of total traffic, and they need no coordination with each other.**
    - ⭐⭐ **So a viral post's read traffic spreads across all N instances instead of hammering one shard.**
- ⚠ **Two honest costs:**
    - **More initial misses** — for a cold viral post with N instances you get **N database requests instead of 1**, since each instance fetches independently. ⭐ **But N is minuscule next to the millions you'd face with no cache.**
    - **Less total distinct caching** — each instance holds the same working set, so capacity is **M, not N×M.** ⭐ **Probably fine: DynamoDB absorbs some read variability and is still fast.**
- ⭐⭐ **The summary line:** _"**N times the throughput for a hot key** without any additional coordination required."_

> ⊕ **(not in HI) — the general rule, which is why this dive is worth more than the problem it appears in.**
> 
> |Problem|Fix|
> |---|---|
> |**Too much DATA** for one node|⭐ **shard** — split the keyspace|
> |⭐⭐ **Too much TRAFFIC for one key**|⭐ **replicate** — every node can serve that key|
> 
> - ⚠ **Sharding is always the reflex, and here it's the wrong tool.** Splitting the keyspace cannot help when all the traffic targets a single key. ⭐ **Adding shards makes it worse: the same hot node, with more idle neighbours.**
> - ▹ **Read-side twin of `03b`'s hot-resource / celebrity row** (_"scaling all fails — same row, writes; change the problem"_). ⭐ **Same key, reads → replicate.**
> 
> ■ **— end of insert —**

### ⊕ ⭐⭐ How to graft this onto the Instagram answer — the part you'll actually say

> ⚠ **Terminology first:** HI labels the **sharded** cache _"Distributed Post Cache"_ — the **Bad** rung. ⭐⭐ **So say "replicated", never "distributed"** — an interviewer may hear "distributed" as "sharded" and think you missed the point.
> 
> - ⭐ **The feed layer is already fine.** `feed:{userId}` ZSETs are **per-user**, so they distribute by construction. ▸ **No hot key there — the hot key is one layer down, in hydration.**
> - ⚠ **Not "celebrity vs viral" — in this scope those are the same accounts**, since the feed only contains people you follow. ⭐⭐ **The distinction is two OPERATIONS on the same celebrity — the query vs the fetch — so two cache entries:**
> 
> |Operation|The question|Cache key|Mutable?|TTL|
> |---|---|---|---|---|
> |⭐⭐ **The LIST** (fan-out-on-read path only)|"which posts did `user_9` post recently?" ⚠ **every follower asks this on every feed load** — 90M identical queries|**`creatorId`**|⭐ **yes — changes on every new post**|⭐ **short, 10–30s** (the **≤1-min staleness NFR pays for it**)|
> |**The CONTENT** (⭐ **serves BOTH paths**)|"what is `post_123`?" — ▸ hydration for **precomputed-feed postIds too**, not only celebrity posts|**`postId`**|**no** — immutable unless edited|**long**; **invalidate on edit**|
> 
> - ⭐ **Why they can't be one entry:** merge them and the TTL fights itself — **short TTL re-fetches immutable content constantly; long TTL hides new posts.**
>     
> - ⚠⚠ **Don't cache only the content.** Then you still hit the Post GSI **90M times just to discover which posts are recent.** ⭐ **The query is the expensive part, not the fetch.**
>     
> - ⭐ **Both caches replicated**, so one key's reads divide across N instances.
>     
> - ▹ **A miss still goes to the table** — this is reduction, not elimination; the first reader after a TTL expiry pays the DB cost. ⭐ **Say "mostly served from cache, falling back to the table on a miss."**
>     
> - ⚠⚠ **The list cache has a thundering-herd risk:** when the 10–30s TTL expires, **all 90M requests miss in the same instant** and stampede the Post GSI together — ⭐ **briefly worse than having no cache.** Fix with any one of: ⭐ **single-flight / request coalescing** (the first miss fetches, everyone else waits on that result) · **refresh-ahead** (a background job repopulates just before expiry) · **jittered TTLs** (so different celebrities don't expire together).
>     
> - ▹ ⚠ **Keep the layers separate: media bytes → CDN** (`05f §5.2`) · **post metadata → Redis.** Different layers, different reasons — don't merge them into one sentence.
>     
> - ⭐⭐ **"How will we know which posts are going viral?" — you don't need to.** High-follower accounts are **already flagged** for the hybrid, and for everything else ⭐ **LRU discovers hotness by itself.** ▸ **The only thing you must decide up front is the deployment shape** — you cannot switch sharded → replicated reactively.
>     
> - ⭐⭐ **The script:** _"The feed ZSETs are per-user so they distribute naturally. The hot keys are the celebrity post lists and viral post content. I'd cache the celebrity list by creator with a few seconds' TTL — one entry serves all their followers — and cache post content with a long TTL. Both replicated rather than sharded, so one key's traffic spreads across instances instead of hammering one node."_
>     
> - ▹ **Out of scope but name it properly if asked:** an **explore / non-follower feed** is a **recommendation system** (candidate generation + ranking) — a different problem. ⚠ **And it would make hot keys much worse, since a post's audience would no longer be capped by follower count.**
>     
> 
> ■ **— end of insert —**

---

## Quick Recall — delta only (pass 3+)

|Use / Question|The addition|
|---|---|
|How to use this file|⭐⭐ **revise `05f` Instagram as the canonical feed design, then read this.** `05g` full file is optional|
|Requirement deltas|⚠ **uni-directional follow, not friend** (halves the problem) · **reverse chronological** + **paging as its own FR** · ⭐⭐ **unlimited follows AND followers = the requirement that creates both dives** · ⭐⭐ **≤1 min staleness = the budget async fan-out spends** · 2B users|
|⭐⭐ NFR lesson|_"having **quantities** on your NFRs helps you make decisions"_ — single-digit-ms needs a **dramatically different architecture** than 1-second. ⭐ **never write "low latency", write a number**|
|⭐⭐ API: PUT not POST|follow is **binary ⇒ `PUT` is idempotent**, safe on double-click; unfollow = `DELETE`. ▹ Instagram uses `POST /follows`|
|⭐⭐ Cursor|**= timestamp of the oldest post seen.** Reverse chronological ⇒ paging goes **backwards in time**, each page = **N posts older than the cursor.** ⭐ **Post GSI already sorts by `createdAt`, so no new index.** ⊕ beats `OFFSET` because new posts shift offsets ⇒ dupes/skips|
|⭐⭐ Why not a graph DB|graph DBs win on **traversals/comprehensions** (friends-of-friends, embeddings) — **we're one hop deep.** ⭐ _"saves us from scarier questions like **how do you scale Neo4j?**"_ ⚠ **don't introduce tech you can't defend**|
|⭐ Three Follow queries|is A→B? **both keys, point lookup** · who does A follow? **PK, range** · **who follows A? GSI PK, range** (fan-out). ▹ **AWS prefers single-table design; separate tables are fine in an interview** — say so|
|⭐⭐ Change the product?|_"can we adjust the product in these instances?"_ ⭐ **FB caps friends at 5,000.** ⭐ _"Is your user with 100k follows really going to notice if their posts appear a couple of minutes late?"_ ▹ same move as `05e §5.3`|
|⭐ The calibration|**10s–100s of requests per incoming request is normal; 1000s is not** — under a latency SLA. ▹ Instagram argues the same pivot via **DynamoDB batch limits (100 items / 16MB)**|
|⭐⭐ 200-post cap|`PrecomputedFeed`: **userId key, ~200 postIds, compact, no secondary index.** ⭐ **"page 100 deep?" — most systems don't support it** (_"try a few dozen pages into Google"_). ⭐⭐ **fall back to the naive Follow+Post query past the cap → the naive design becomes the cold path.** ⊕ **this is what answers "what happens at page 11"**|
|⭐⭐ Sizing + cost rule|**10 B × 200 = 2KB/user × 2B = 4TB** for every feed on Earth. ⭐⭐ **price it per user in dollars — 2KB ≈ a fraction of a cent/month vs ~$100/yr revenue per US user.** ▹ Instagram sizes media, never the feed store|
|⚠ The Bad rung|**sync blast to every follower → "This will fail."** Connection limits + latency, and ⭐ **load is wildly uneven — one host writing millions of feeds, another idle.** ▸ **the unevenness is the killer, not the volume**|
|⭐ Queue + variable work|**at-least-once + highly scalable → SQS**; enqueue **postId + creatorId**. ⭐⭐ **variable work per item — 1M followers vs 1k is wildly different ⇒ break up the tasks.** ⊕ one fat message **blocks a worker for minutes**; chunk (e.g. 10k followers/message)|
|⭐⭐ Flag on Follow, not User|workers **skip** flagged follows; read path **merges partial feed + recent posts from non-precomputed accounts.** ⭐⭐ **the read path already queries "who do I follow", so the flag comes back free** — on the User record you'd need a **second lookup per followee.** ⚠ cost = **denormalization** (backfill that user's Follow rows; background job). ⭐ HI's principle: _"fan out on read or write **per account** — most users get a bit of both"_|
|⭐⭐ DD3 why hot keys hurt|**KV stores need even load across the keyspace** — real machines underneath; **one hot key ⇒ one partition's ceiling is your ceiling.** ⭐ _"Post1 at 500 req/s and Post2–1000 at 0 is not even load."_ ▹ helped by posts being **created far more than edited** ⇒ long TTLs safe|
|⚠ DD3 Good — sharded cache|Redis, **long TTL + LRU**, keyed by postId, capacity **N×M**; ⭐ **invalidate on edit, not create.** ⚠⚠ **same hot-key problem** — the viral post lives on **one node**; it melts while others idle. **Hot spot moved, not removed**|
|⭐⭐ DD3 Great — replicated|⭐⭐ **every instance can serve ANY post**; LB spreads reads; **zero coordination.** ⭐ **viral traffic ÷ N.** ⚠ costs: **N cold misses instead of 1** (still ≪ millions) and **capacity M, not N×M.** ⭐⭐ _"N times the throughput for a hot key without any additional coordination"_|
|⊕⭐⭐ The general rule|**too much DATA for one node → shard.** ⭐ **too much TRAFFIC for one key → replicate.** ⚠ **sharding cannot help a single hot key** — it lands on one shard by definition, and more shards just means more idle neighbours. ▹ read-side twin of `03b`'s hot-resource row|
|⊕⭐⭐ Grafting it onto Instagram|⚠ **say "replicated", NOT "distributed"** — HI's _"Distributed Post Cache"_ **is** the sharded Bad rung. ⭐ **feed ZSETs are per-user ⇒ already fine**; the hot keys are one layer down. ⚠ **not "celebrity vs viral" — same accounts in this scope.** ⭐⭐ **The split is two OPERATIONS — the query vs the fetch: (1) the LIST** "which posts did user_9 post?" — key **`creatorId`**, **mutable ⇒ short TTL 10–30s**, because **every follower asks on every feed load** (90M identical queries) · **(2) the CONTENT** "what is post_123?" — key **`postId`**, **immutable ⇒ long TTL, invalidate on edit**, and ⭐ **it serves BOTH paths** (precomputed-feed hydration too). ⭐ **One entry can't do both — the TTL fights itself.** ⚠⚠ **cache only the content and you still hit the GSI 90M times to find which posts are recent — the QUERY is the expensive part.** ⚠⚠ **list TTL expiry = thundering herd** → **single-flight / refresh-ahead / jittered TTL.** ▹ miss still goes to the table; **media → CDN, metadata → Redis**|
|⭐⭐ "How do we detect virality?"|**you don't.** High-follower accounts are **already flagged** for the hybrid; for the rest, ⭐ **LRU discovers hotness by itself.** ▸ **only the deployment shape must be chosen up front** — you can't switch sharded → replicated reactively. ▹ explore/non-follower feed = a **recommendation system**, out of scope, ⚠ **and it would uncap a post's audience, making hot keys worse**|

---

> 🔗 **Companion files:** `05f` Instagram (the canonical feed design) · `05g` FB News Feed (the full write-up, kept for reference) · HI source: https://www.hellointerview.com/learn/system-design/problem-breakdowns/fb-news-feed