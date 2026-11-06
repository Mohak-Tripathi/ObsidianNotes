# Social News Feed (FB News Feed) — Problem Breakdown

> 📐 **Revision note (calc):** only one calculation, but it's the most reusable in the series — **10 bytes/postId × 200 posts = 2KB per user × 2B users = 4TB total** for every precomputed feed on earth (§5.1). ⭐⭐ **And the rule-of-thumb attached to it: price it per user. 2KB ≈ a fraction of a cent/month against ~$100/year revenue per US user.** Also carry: **1 minute staleness budget** (the thing that licenses async fan-out), **<500ms**, **2B users**, and HI's threshold — ⭐ **10s–100s of requests per incoming request is normal; 1000s is not.**

> Hello Interview · Question Breakdowns · File `05g`. **Stefan Mai**, Jul 2024, last updated **Feb 2026** · ⭐ **"medium"** · pattern: **Scaling Reads (`03d`)** · has a video walkthrough. ⭐ **HI's framing: "a classic system design problem dealing with fan-out and data management."** ⚠ **Scoped to uni-directional "follow", not bi-directional "friend".** Cross-refs: ⭐⭐ **`05f` Instagram — the same problem with different choices; revise them as a pair (see §1.4)**. Fan-out / hot keys / hierarchical aggregation → `03e`. Async workers behind a queue → `03g`. DynamoDB PK/SK, **GSI**, hot partitions → `02f`. Redis, LRU, TTL → `02a`. Kafka/queues → `02c`. Caching → `01e`. Sharding → `01f`. API design → `01b`. API Gateway → `02d`. CAP → `01h`. Numbers → `01i`.
> 
> **Calibration:** ⭐⭐ **Do this immediately after `05f`. Roughly 70% overlaps, and the 30% that doesn't is the most interesting material in either file.**
> 
> - ⭐⭐ **What actually scores — and note three of these are unique to this problem, not in `05f`:**
>     - **(a)** ⭐⭐ **The fan-out ladder named properly** — fan-out on read vs fan-out on write, with HI's calibration (1000s of requests per read is not acceptable).
>     - **(b)** ⭐⭐ **Sharded vs replicated cache for hot keys** (§5.3) — ⭐ **unique to this write-up and the best single idea in it.**
>     - **(c)** ⭐ **The `precomputed` flag on the Follow row** (§5.2) — a per-_follow_ decision, not a per-_user_ one. Different from `05f` and arguably better.
>     - **(d)** ⭐⭐ **Asking whether the product can change** — Facebook caps friends at 5,000. The senior/staff move of solving it outside the system.
>     - **(e)** ⭐ **Capping the precomputed feed at ~200 posts with a fallback to the naive query** beyond it.
>     - **(f)** ⭐ **Pricing the design per user in dollars** — the rule-of-thumb from §5.1.
>     - **(g)** **Rejecting a graph database, with a reason** (§4.2).
> - ⭐ **Transferable primitives:**
>     - ⭐⭐ **Hybrid per-entity, not per-system.** HI states it as a principle: _"in most situations we don't need a one-size-fits-all solution."_ The precompute decision is made **per account**, and most users get a bit of both.
>     - ⭐⭐ **Replicate, don't shard, to survive a hot key.** Sharding spreads _data_; it concentrates _traffic for one key_. Replication spreads the traffic.
>     - ⭐ **A staleness budget is a resource — spend it.** The 1-minute NFR is what makes async fan-out legal.
>     - ⭐ **Ask whether the requirement can move** before engineering around its tail.
> - ⭐ **Re-run (cross-ref, NOT re-explained):** fan-out on read → write → hybrid (`05f §5.1`) · the Follows GSI reversal (`05f §4.3` + its Tutor Q&A) · async queue workers (`03g`) · caching + TTL (`01e`) · DynamoDB key design (`02f`). **Genuinely new:** cursor-by-timestamp paging, the graph-DB rejection, `PUT` for follow idempotency, the 200-post feed cap + naive fallback, the cost-per-user check, the per-follow `precomputed` flag, variable work per queue item, and ⭐⭐ **the sharded-vs-replicated cache dive.**

---

## 0 · Understanding the problem

📰 **What is [Facebook's News Feed](https://www.facebook.com/)?**

Facebook is a social network which pioneered the **News Feed**, a product which shows recent stories from users in your social graph.

> 💬 **My question → HI Tutor:** _"FB News Feed means what — just a user post feed like Instagram?"_
> 
> Yes. A Facebook News Feed is **like Instagram's home feed.** It shows posts from accounts you follow, usually with the **newest posts first.** ⭐ **The system-design challenge is building that feed quickly even when some users follow millions of people.**
> 
> ■ **— end of insert —**

▹ ⚠ **Scope note:** this breakdown assumes **uni-directional "follow"** relationships, **not** the bi-directional "friend" relationships that mattered for the earliest versions of Facebook. ⭐ **Say this out loud — it halves the problem**, because a friend edge would need both directions written and agreed.

---

## 1 · Requirements

### 1.1 Functional (what it does)

1. ⭐ **Users should be able to create posts.**
2. ⭐ **Users should be able to friend/follow people.**
3. ⭐ **Users should be able to view a feed of posts from people they follow, in reverse chronological order (newest first).**
4. ⭐ **Users should be able to page through their feed.**

⚠ **Below the line (out of scope):** like and comment on posts · posts being **private or restricted visibility.**

▹ ⭐ **Assume authentication is done** — the user ID is in the session or JWT. HI notes this holds for most system design problems; don't spend time on it.

### 1.2 Non-functional (how it behaves)

1. ⭐ **Highly available, availability over consistency** — ⭐⭐ **tolerate up to 1 minute of post staleness** (eventual consistency) (`01h`).
2. ⭐ **Posting and viewing the feed < 500ms.**
3. ⭐ **A massive number of users — 2B.**
4. ⭐⭐ **Unlimited follows AND unlimited followers** — both directions unbounded. ▸ **This is the requirement that creates both deep dives.**

> 💬 **My question → HI Tutor:** _"Doesn't 'uni-directional' (§0) contradict 'unlimited followers and follows'?"_
> 
> No. They are **different statements.**
> 
> - ⭐ **Uni-directional = direction.** Each follow is **independent** — A follows B does not automatically mean B follows A.
> - ⭐ **Unlimited = count.** A user can follow many accounts, and many accounts can follow that user.
> - ▸ **Both at once:** you can follow Messi while Messi does not follow you, **and** millions of others can follow Messi too.
> 
> ■ **— end of insert · HI write-up resumes below —**

> ⭐⭐ **The NFR lesson worth stealing — HI says it directly:** _"Having **quantities** on your non-functional requirements will help you make decisions during your design. A system which is **single-digit millisecond** fast requires a **dramatically different architecture** than a 'fast' system which can take a second to respond."_
> 
> ▹ ⭐ **So never write "low latency" — write a number.** The number is what lets you reject designs instead of debating them.
> 
> ■ **— end of insert · HI write-up resumes below —**

### 1.3 ⭐⭐ The design driver — fan-out in both directions

> ⭐⭐ **HI names the hard part before designing anything, and so should you:** _"The hard part of this design is going to be dealing with the potential of users who are **following a massive number of people**, or **people with lots of followers** — a problem known as **fan out**."_

- ▸ **Two independent explosions, from NFR #4:**

||Which direction|Breaks|Deep dive|
|---|---|---|---|
|**Following thousands**|read side|building one feed needs 1000s of queries|⭐ **§5.1**|
|**Having millions of followers**|write side|one post needs millions of feed writes|⭐ **§5.2**|

- ⭐ **And a third, which is the subtle one:** even with both solved, **a viral post is a single hot key** read by millions — §5.3.
- ⭐⭐ **The resource that makes everything possible: the 1-minute staleness budget.** It's what allows the write-side fan-out to be **asynchronous**. ▸ **Without that NFR, none of §5.2 is legal.** ⭐ **Say that connection out loud — it shows the NFRs are driving the design rather than decorating it.**

### 1.4 ⭐⭐ `05f` Instagram vs `05g` News Feed — what's shared and what's different

> ⭐⭐ **Read this table before revising either file. ~70% is the same problem; the differences are where the learning is.**

||`05f` Instagram|⭐ `05g` News Feed|
|---|---|---|
|**Precomputed feed store**|**Redis ZSET** `feed:{userId}`|**DynamoDB `PrecomputedFeed`** (userId PK, createdAt SK)|
|**Feed cap**|not specified|⭐ **~200 postIds**, then **fall back to the naive query**|
|**Celebrity marker**|`followerCount` / `isCelebrity` on the **User** record|⭐⭐ **`precomputed` flag on the Follow row**|
|**Hydration**|ZSET ids + Redis **HASH** metadata, `BatchGetItem` for misses|**Post Cache** in front of the Posts table|
|**Hot keys**|not covered|⭐⭐ **sharded vs replicated cache — the unique dive**|
|**Queue**|generic message queue|⭐ **SQS, at-least-once delivery**|
|**Media**|S3 + CDN + variants (a whole deep dive)|**entirely out of scope**|
|**Ordering**|chronological|**reverse chronological + timestamp cursor**|
|**Scale**|500M DAU, 100M posts/day|**2B users**|

- ⭐ **The conceptual core is identical:** fan-out on read fails → precompute on write → carve out the celebrities. ⭐⭐ **Learn that once; learn the differences as variations.**

---

## 2 · Core Entities

▸ **CRUX** — starting with entities gives you **the vocabulary for the rest of the interview**, and shows the data model you'll need.

- **User** — a user in our system.
- ⭐ **Follow** — a **uni-directional link** between users. ▹ **HI makes this an explicit entity**, not an implied join.
- **Post** — a post made by a user; shown in the feed of users who follow the poster.

---

## 3 · API

### 3.1 Create a post

```
POST /posts
{ "content": { } }
-> 200 OK
{ "postId": ... }
```

- ⭐ **`content` left deliberately empty** to account for rich content or other structured data later.
- ▹ Auth tokens are in the **header** — say that and move on unless asked.

### 3.2 Follow a user

```
PUT /users/[id]/follow
{ }
-> 200 OK
```

- ⭐⭐ **Why `PUT` and not `POST`: the follow action is binary, so `PUT` makes it idempotent** — it doesn't fail if the user clicks follow twice. ▹ **Unfollow (out of scope) would be `DELETE`.** ⭐ **This is a cheap, high-signal detail — most candidates reach for `POST` by reflex.**
- ▹ The authenticated user (from the JWT) is the follower; `[id]` is who they follow. Body is an empty stub.

### 3.3 View and page the feed

```
GET /feed?pageSize={size}&cursor={timestamp?}
-> { items: Post[], nextCursor: string }
```

- ⭐⭐ **The cursor is a timestamp — the oldest post the user has seen so far.** ▸ Because the feed is **reverse chronological**, paging moves **backwards in time**, so each page returns **N posts older than that timestamp.**
- ▹ Don't dive into the `Post` structure — ⭐ save the time for the interesting parts.

▹ ⭐ **"I'll come back to this if I have time"** is explicitly sanctioned by HI as "a great strategy" — use it on the Post schema, auth, the load balancer.

---

## 4 · High-Level Design

### 4.1) Users should be able to create posts

```
Client ──► API Gateway / LB ──► Post Service (horizontally scaled) ──► DynamoDB
                                                                      Posts
                                                                        id · content
                                                                        creatorId · createdAt
```

- ⭐ **Horizontally scaled service behind an API gateway / load balancer** from the start, since we know this must scale. ▹ Caching comes later.
- ⭐ **Why it's trivially scalable right now: each host is stateless** — it's only **writing** to the database, and we aren't handling reads yet. ⭐ **So scaling = adding hosts.**
- ⭐ **DynamoDB** for simplicity and scalability. ⭐⭐ **Note the caveat HI plants here, because it comes back in §5.3:** _"DynamoDB allows us to provision extremely high throughput **provided we spread our load evenly across our partitions.**"_

### 4.2) Users should be able to friend/follow people

- ▸ Following is a **many-to-many relationship** — a graph.

> ⭐⭐ **Confusion resolved — why not a graph database (Neo4j, a triple store)?**
> 
> - ⭐ **Graph databases earn their keep on traversals and comprehensions** — stepping between nodes, friends-of-friends, building embeddings for a recommendation system.
> - ▸ **We have none of that.** Our queries are one hop deep.
> - ⭐⭐ **HI's honest reason, worth borrowing nearly verbatim:** keeping it simple _"saves ourselves from scarier questions like **'how do you scale Neo4j?'**"_ ▸ **Don't introduce a technology you can't defend under pressure.**
> 
> ■ **— end of insert · HI write-up resumes below —**

- ⭐ **So model the graph yourself in a key-value store:**

||Partition key|Sort key|
|---|---|---|
|**Follow**|`userFollowing`|`userFollowed`|
|⭐ **Follow GSI**|`userFollowed`|`userFollowing`|

- ⭐⭐ **The three queries this unlocks — name all three:**
    1. **Is A following B?** → query with **both PK and SK** → ⭐ **a simple point lookup.**
    2. **Who does A follow?** → query with the **PK** → **range query.**
    3. **Who follows A?** → query the **GSI** by its PK → **range query.** ▸ This is the one the write-side fan-out needs.
- ▹ ⭐ **AWS actually recommends single-table design for DynamoDB**, but **separate tables keep the discussion clearer and are totally fine in an interview.** ⭐ **Saying this shows you know the real-world practice and are choosing clarity deliberately.**

### 4.3) Users should be able to view a feed

▸ **Three steps:** get everyone the user follows → get all posts from those users → **sort by time** and return.

- ⭐ **Add a Feed Service.** It's **read-heavy with very different query patterns** than Post and Follow, so separating it makes sense.
- ⭐⭐ **The index that's missing:** we have an index to find who a user follows, but ⚠ **no index on the Post table to look up posts from a set of users.** ▸ **Add a Post GSI: `creatorId` (PK), `createdAt` (SK)** → pull all posts from a set of users **in chronological order.**

▸ **Pattern: Scaling Reads (`03d`).** ⭐ HI's note adds the detail that shapes everything: _"**users typically only read the first few items**, so aggressive caching of recent content delivers massive performance gains."_ ▹ **That's the justification for capping the precomputed feed at 200 in §5.1.**

⚠⚠ **Three flags to name verbally, right now:**

1. **Our user may be following lots of users.**
2. **Each of those users may have lots of posts.**
3. **The total set of posts may be very large** because of (1) or (2).

> ⭐⭐ **Say it the way HI says it, nearly verbatim:** _"I know this is not going to scale, but I'm going to start with a naive solution and then solve the scaling problems separately."_
> 
> ⭐ **Why this sentence matters:** it converts an obviously-broken design from a mistake into a deliberate step. ⚠ **Without it, the interviewer can't tell whether you noticed.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 4.4) Users should be able to page through their feed

- ▸ **Goal: "infinite scroll".** We need to know what the user has already seen.
- ⭐⭐ **The insight: "what they've already seen" compresses to a single value — the timestamp of the oldest post they've looked at.** ▸ Since they read **youngest → oldest**, that one timestamp says exactly where they stopped.
- ⭐ **And we already have the index for it** — the Post GSI is sorted by `createdAt`, so return only posts **older than the cursor.** ▸ **This looks just like the previous functional requirement with one addition:**

1. First, we get **all of the users who a given user is following.**
2. Next, we get all of the posts from those users **that are older than the input timestamp.**
3. Finally, we **sort all those posts by time** and return them to the user.

---

## 5 · Deep Dives

### 1) How do we handle users following a large number of users? ⭐⭐

- ⚠ **The failure:** the Follow query is slow, and then you issue **a large number of queries to the Post table** to assemble the feed.
- ⭐⭐ **Name it: this is fan-out on read — a single read request fans out into many more requests.**
- ⭐⭐ **HI's calibration, which is the most quotable number in the file:** _"It's not uncommon to generate **10s to 100s of requests** to satisfy an incoming request, but it is **rarer to have to generate 1000's of requests**, especially for a service that needs to serve users with low latency."_ ▸ **Use it to justify the pivot instead of just asserting "too slow".**
- ⭐ **The instinct to voice:** compute the feed **at write time** rather than read time → ⭐⭐ **fan-out on write.**

> ⭐⭐ **Confusion resolved — before engineering around the tail, ask whether the product can change.**
> 
> - ⭐ **HI's question: _"can we adjust the product in these instances?"_** ▸ **Facebook caps friends at 5,000.** Setting a max on follows, or giving those users a **slightly different experience**, is **"a very common approach for production systems."**
> - ⭐⭐ **And the line that makes the case:** _"Is your user with 100k follows really going to notice if their posts are appearing a couple of minutes late?"_
> - ▹ ⭐ **Same move as `05e §5.3`'s waiting queue — the senior/staff answer is sometimes to change the requirement, not to out-engineer it.** ⚠ **But ask; don't assume you may.**
> 
> ■ **— end of insert · HI write-up resumes below —**

#### ⭐ The solution — a `PrecomputedFeed` table

- **Approach:** keep a **`PrecomputedFeed`** table. Instead of querying Follow and Post at read time, **pull from this table**; when a new post is created, **add it to the relevant feeds.**
- ⭐ **Shape:** keyed by **`userId`**, value is a **list of post IDs in reverse chronological order**, limited to a **small number — say 200.** ▸ **Keep each entry compact to minimize space.**
- ⭐ **No secondary indexes needed** — ▸ **we only ever access this table by user ID.**

> ⭐⭐ **Confusion resolved — "but what if a user pages 100 pages deep?"**
> 
> - ⭐ **HI's answer: most systems simply don't support it.** _"Try to go a few dozen pages deep into Google."_ ▸ **Real users aren't doing this.**
> - ⭐ **The 200 figure is a dial**, tuned by how much it hurts those tail users against the cost.
> - ⭐⭐ **And there's a safety net: fall back to the naive query** against the base Follow and Post tables for anyone who reaches the end of their precomputed feed. ▸ **So the naive design from §4.3 isn't thrown away — it becomes the cold path.** ⭐ **Say that; it makes the whole design feel considered rather than replaced.**
> 
> ■ **— end of insert · HI write-up resumes below —**

#### ⭐ Storage gut-check — and the rule-of-thumb to steal

|||
|---|---|
|One postId|**10 bytes**|
|200 posts per user|**2KB per user**|
|× 2B users|⭐ **4TB total**|

- ▸ ⭐ **"Quite reasonable for a modern system."** ▹ Every precomputed feed on Earth fits in 4TB.
- ⭐⭐ **The reusable technique — price it per user in dollars:** _"ask how much a given user, tenant, or item is going to cost in dollars. **2KB of data is a fraction of a cent per month** and Facebook earns something like **$100 per year for US-based users.** So this is pretty reasonable."_ ▸ ⭐ **A unit-economics check is far more persuasive than a byte count, and almost nobody does it.**

⚠ **But this creates the next problem:** when a user with a lot of followers posts, **we now need to write to millions of feeds.** → §5.2

### 2) How do we handle users with a large number of followers? ⭐⭐

- ▸ **The mirror problem: one post → millions of Feed records.**
- ⭐⭐ **And here's where the NFR pays off:** because we allowed inconsistency, we have **a < 1 minute window** to perform those writes. ▸ **That budget is the whole reason this is solvable.**

#### ⚠ Bad Solution — blast out all the writes synchronously

- **Approach:** the Post Service writes to every follower's feed at post-creation time.
- ⚠⚠ **HI's verdict is blunt: "This will fail."**
- ⚠ **Challenges:**
    - **Connection limits** on a single Post Service host, plus the latency budget.
    - ⭐ **Even if it works, the load is wildly uneven** — **one host writing to millions of feeds while another is basically idle.** ▸ **That unevenness is what makes it unscalable**, not just the volume.

**Why climb:** the work is bursty and unbounded, and it's sitting on the request path. Get it off.

#### Good Solution — async workers behind a queue

- ⭐ **Approach:** queue the write requests and have **a fleet of workers** consume them and update feeds. ▸ **Legal because we tolerate delay** (`03g`).
- ⭐ **Queue requirements — state them:** **at-least-once delivery** and **highly scalable.** ▹ **SQS works great here.**
- **Mechanism:** on post creation, enqueue **the post ID and the creator user ID**. Each worker **looks up all followers of that creator** (via the Follow GSI) and **prepends the post to the front of each follower's feed entry.**
- ⚠ **Challenges:**
    - ⭐ **Worker throughput must be enormous.** Small accounts are trivial (a few hundred feeds); **mega accounts are a lot of work.**
    - ⭐⭐ **Variable work per queue item** — one message for a user with **1M followers** is dramatically more work than one for **1k followers.** ▸ ⭐ **"We may need to break up these tasks."** ▹ **This is the detail that separates a real answer from a hand-wave: a queue with wildly uneven item cost needs chunking, or one slow message blocks a worker for minutes.**

**Why climb:** we've made the work asynchronous but not smaller. For the biggest accounts it's still 90M writes for one post.

#### ⭐ Great Solution — per-account precompute, flagged on the Follow row

- ⭐⭐ **Approach: choose which accounts get precomputed into feeds and which don't.** For Justin Bieber, instead of writing to 90+ million followers:
    - ⭐⭐ **Add a `precomputed` flag on the Follow table** marking that this particular follow **isn't** precomputed.
    - **The async workers ignore requests for these users.**
    - ⭐ **On read, the Feed Service grabs the (partially) precomputed feed and merges it with recent posts from the non-precomputed accounts.**
- ⭐⭐ **HI states the general principle, and it's worth quoting:** _"This hybrid approach allows us to choose whether we **fan out on read or fan out on write on a per-account basis**, and for most users we'll do a little of both. This is a great system design principle! **In most situations we don't need a one-size-fits-all solution** — we can instead come up with clever ways to solve for different types of problems and combine them."_
- ⚠ **Challenges:** merging at read time means **more computation in the Feed Service**; ⭐ **the threshold is a dial to tune.**

> ⊕ **(not in HI) — why the flag sits on the Follow row, and why that beats `05f`'s approach.**
> 
> - ▸ `05f` Instagram marks the **celebrity** (`followerCount` / `isCelebrity` on the **User** record). This file marks the **relationship** (`precomputed` on the **Follow** row).
> - ⭐⭐ **The read path is why it matters.** The Feed Service already queries _"who does this user follow?"_ — ⭐ **so with the flag on the Follow row, the non-precomputed followees come back in that same query, for free.** With the flag on the User record you'd get back the followee list and then need **a second lookup per followee** to discover which are celebrities.
> - ⭐ **The write path keeps working either way** — the worker reads the Follow rows anyway to know whose feeds to update, so the flag is right there.
> - ⚠ **The cost: denormalization.** A user crossing the threshold means **updating every one of their Follow rows**, not one User field. ▸ For an account going from 99k to 101k followers that's a 100k-row backfill — ⭐ **fine as a background job, since the flag only changes when someone crosses the line.**
> - ⭐ **Worth saying in either interview:** _"I'd put the flag on the relationship rather than the user, so the read path gets it in a query it already makes."_
> 
> ■ **— end of insert · HI write-up resumes below —**

### 3) How can we handle uneven reads of Posts? ⭐⭐

> ⭐⭐ **The best material in this write-up and it has no equivalent in `05f`. If you only deep-dive one section here, make it this one.**

- ▸ **The read distribution:** most posts are read for a few days and **never again.** Some posts — especially from high-follower accounts — take **massive reads in the first few hours.**
- ⭐⭐ **Why that's a problem specifically for DynamoDB (and most KV stores):** they scale to very high throughput **provided load is even across the keyspace.** ▸ **Underneath are physical machines with real limits.** ⭐ **HI's example: "If Post1 gets 500 requests per second and Post2 through Post1000 get 0 requests per second, this is not even load!"**
- ▹ ✅ **One thing in our favour: posts are far more likely to be created than edited.** ▸ That's what makes long cache TTLs safe.

#### Good Solution — a distributed (sharded) post cache

- **Approach:** insert a **cache between the readers of the Post table and the table itself.** Since posts are rarely edited, use a **long TTL** and **LRU eviction** (`02a`). ⭐ **With N hosts × M memory, the cache holds as many posts as fit in N×M.** ▹ **Redis, keyed off post ID** so posts distribute evenly across the cluster.
- ⭐ **Invalidation is easy: when a post is _edited_ (not created), invalidate that post ID.**
- ⚠⚠ **Challenge — and it's the whole point of the next rung: the cache has exactly the same hot-key problem the table did.** ▸ For the unlucky shard holding multiple viral posts, **those hosts take an unequal share of load**, which makes the cache **very hard to scale** — ⭐ **and many hosts sit underutilized.**

**Why climb:** sharding spreads the **data** evenly. It does nothing for **traffic concentrated on one key** — the viral post still lives on exactly one node.

#### ⭐ Great Solution — a replicated post cache

- ⭐⭐ **The key difference, and the idea to carry out of this file:** instead of a **sharded** cache where each post lives on **exactly one node**, use **replicated cache instances where every instance can serve any post.**
    - ▸ A **load balancer** distributes requests across the instances.
    - ⭐ **Each instance independently handles a fraction of total traffic, and they need no coordination.**
    - ⭐⭐ **So a viral post's read traffic spreads across all N instances instead of hammering a single shard.**
- ⚠ **The tradeoff, stated honestly:** **more cache misses initially** — for a very viral post with N instances you may get **N requests to the database instead of 1.** ⭐ **But N is much, much smaller than the millions of requests you'd face with no cache at all.**
- ⭐⭐ **The summary line:** _"N times the throughput for a hot key **without any additional coordination required.**"_
- ⚠ **Challenge:** you cache **fewer distinct posts overall** than a partitioned cache — each instance holds a copy, so capacity is **M, not N×M.** ⭐ **Probably fine: DynamoDB can absorb some variability in read throughput and is still fast.**

> ⊕ **(not in HI) — the general rule, because this generalizes well beyond feeds.**
> 
> |Problem|Fix|
> |---|---|
> |**Too much data** for one node|⭐ **shard** — split the keyspace|
> |⭐⭐ **Too much traffic for one key**|⭐ **replicate** — every node can serve that key|
> 
> - ⚠ **Sharding is the instinct, and it's the wrong tool here** — splitting the keyspace cannot help when all the traffic is for a single key, because that key lands on one shard by definition. ⭐ **Adding shards makes it worse: the same hot node, with more idle neighbours.**
> - ▹ Connects to `03b`'s **hot resource / celebrity** row — _"scaling all fails (same row, writes); change the problem."_ ⭐ **Here it's the read-side twin: same key, reads → replicate.**
> 
> ■ **— end of insert · HI write-up resumes below —**

---

## 6 · Final Design

```
Client
  │
  ▼
API Gateway / LB                                                       02d
  │
  ├──► Post Service ──► DynamoDB                                       02f
  │         │             Posts   id (PK) · content · creatorId · createdAt
  │         │             Post GSI   creatorId (PK) · createdAt (SK)
  │         │
  │         └──► Post Create Queue (SQS, at-least-once) ──► Feed Workers ×N
  │                                                             │
  │                                        skip follows flagged │ precomputed = false
  │                                                             ▼
  │                                                    PrecomputedFeed
  │                                                      userId (PK) · createdAt (SK) · postId
  │                                                      (capped ~200 posts/user ≈ 4TB total)
  ├──► Follow Service ──► Follow        userFollowing (PK) · userFollowed (SK) · precomputed
  │                       Follow GSI    userFollowed (PK) · userFollowing (SK)   ← write-side fan-out
  │
  └──► Feed Service ──┬──► PrecomputedFeed  (the hot path)
                      ├──► Follow + Post GSI  (cold path: non-precomputed accounts, and
                      │                        anyone who pages past their 200)
                      └──► Post Cache (Redis, REPLICATED not sharded) ──► Posts
                                 long TTL · LRU · invalidate on edit
```

---

## 7 · Expected at Each Level

|Level|The bar for News Feed|
|---|---|
|**Mid (E4)**|Clearly defined **API endpoints and data model**, and a **functional HLD** that meets the requirements. May reach some of the **"Good"** solutions; ⭐ **not expected to cover all the scaling edge cases**|
|**Senior (E5)**|⭐ **Speed through the HLD**, then discuss **at least 2 deep dives in detail**; articulate pros and cons of architectural choices against scalability, performance, maintainability; ⭐⭐ **proactively surface the fan-out and bottleneck issues**|
|**Staff+**|⭐ **Likely covers all the deep dives** (and some HI didn't enumerate); surfaces potential issues unprompted and discusses ⭐ **performance tuning.** Interviewer **intervenes only to focus, not to steer**|

---

## Quick Recall (pass 3+)

|Use / Question|News Feed answer|
|---|---|
|Calibration|⭐ Stefan Mai · **medium** · pattern **Scaling Reads `03d`** · ⚠ **uni-directional follow, not friend.** ⭐⭐ **Do straight after `05f` — ~70% overlap.** Score points: **fan-out named + the 1000s-of-requests calibration** · ⭐⭐ **sharded vs replicated cache** · **`precomputed` flag on the Follow row** · **asking to change the product (FB caps friends at 5,000)** · **200-post cap + naive fallback** · **cost per user in dollars** · **rejecting a graph DB with a reason**|
|⭐⭐ Design driver|**fan-out in BOTH directions** (NFR: unlimited follows AND followers): **following thousands → read side → §5.1** · **millions of followers → write side → §5.2** · ⭐ **plus a viral post = one hot key → §5.3.** ⭐⭐ **The 1-minute staleness budget is what makes async fan-out legal** — say that link out loud|
|FRs|create posts · follow people · **feed in reverse chronological order** · **page through it.** Below: like/comment · private/restricted visibility. ▹ assume auth done (JWT/session)|
|NFRs|**availability > consistency, ≤1 min staleness** · **post + view < 500ms** · **2B users** · ⭐ **unlimited follows AND followers**|
|⭐⭐ NFR lesson|_"having **quantities** on your NFRs helps you make decisions"_ — **single-digit-ms fast needs a dramatically different architecture than 1-second fast.** ⭐ **never write "low latency", write a number**|
|⭐⭐ Process warning|_"a very common failure mode is **getting lost in the weeds of a scaling problem before having a (mostly) complete design**."_ **Breadth first, then depth** — while moving fast|
|Entities|User · ⭐ **Follow (explicit entity, uni-directional)** · Post|
|API|`POST /posts {content:{}} → {postId}` (content empty for rich data later) · ⭐⭐ **`PUT /users/[id]/follow`** — **PUT because the action is binary ⇒ idempotent, double-click safe**; unfollow = DELETE · `GET /feed?pageSize&cursor → {items, nextCursor}`|
|⭐⭐ Cursor|**a timestamp = the oldest post seen.** Reverse chronological ⇒ paging moves **backwards in time**, each page returns **N posts older than the cursor.** ⭐ **the Post GSI already sorts by `createdAt`, so no new index needed for paging**|
|⭐⭐ Seniority note|_"too much time on obvious elements **signals you may not distinguish complex pieces from trivial ones — a critical skill for senior engineers**."_ ⭐ **"I'll come back to this if I have time" is explicitly "a great strategy"**|
|Post creation|API gateway/LB → **horizontally scaled, stateless** Post Service → DynamoDB. ⭐ **stateless because it's write-only so far ⇒ scale = add hosts.** ⭐⭐ **the planted caveat: DynamoDB gives huge throughput _provided load is even across partitions_** → §5.3|
|⭐⭐ Why not a graph DB|graph DBs win on **traversals/comprehensions** (friends-of-friends, embeddings) — ▸ **we're one hop deep.** ⭐ HI's reason: it _"saves us from scarier questions like **how do you scale Neo4j?**"_ ⚠ **don't introduce tech you can't defend**|
|⭐ Follow keys|**Follow:** PK `userFollowing`, SK `userFollowed` · ⭐ **GSI:** PK `userFollowed`, SK `userFollowing`. **Three queries:** is A→B? **both keys, point lookup** · who does A follow? **PK, range** · ⭐ **who follows A? GSI PK, range** (the write-side fan-out query). ▹ **AWS prefers single-table design; separate tables are fine in an interview** — say so|
|⭐ Feed HLD|**add a Feed Service** (read-heavy, different query patterns). ⭐⭐ **missing index: no way to get posts for a set of users → add Post GSI `creatorId` (PK) + `createdAt` (SK)**. ⚠ **name 3 flags: many followees · many posts each · huge total.** ⭐⭐ say _"I know this won't scale; I'll start naive and solve scaling separately"_|
|⭐ Paging|**"what they've seen" compresses to one value — the oldest post's timestamp**, because they read youngest→oldest|
|⭐⭐ DD1 fan-out on read|**one read request fans out into many.** ⭐ **HI's calibration: 10s–100s of requests per incoming request is normal; 1000s is not** — especially under a latency SLA|
|⭐⭐ DD1 change the product?|_"can we adjust the product in these instances?"_ ⭐ **FB caps friends at 5,000**; a max or a different experience for tail users is **very common in production.** ⭐ _"Is your user with 100k follows really going to notice if their posts appear a couple of minutes late?"_ ▹ same move as `05e §5.3`|
|⭐ DD1 PrecomputedFeed|keyed by **`userId`**, value = **postIds in reverse chronological order, capped ~200**, kept compact. ⭐ **no secondary index needed — only ever read by userId**|
|⭐⭐ "page 100 deep?"|**most systems just don't support it** (_"try a few dozen pages into Google"_) — **real users don't.** 200 is a dial. ⭐⭐ **fall back to the naive Follow+Post query past the cap → the naive design becomes the cold path, not dead code**|
|⭐⭐ DD1 sizing|**10 B/postId × 200 = 2KB/user × 2B users = 4TB** — _"quite reasonable."_ ⭐⭐ **the technique: price it per user in dollars — 2KB ≈ a fraction of a cent/month vs ~$100/yr revenue per US user.** Almost nobody does this|
|⚠ DD2 Bad — sync blast|⚠ **"This will fail."** Connection limits on one host + latency; ⭐ **and even working, load is wildly uneven — one host writing millions of feeds, another idle** → unscalable|
|DD2 Good — queue + workers|⭐ **legal only because of the 1-min budget** (`03g`). Queue needs **at-least-once delivery + high scalability** → **SQS**. Enqueue **postId + creatorId**; workers read the **Follow GSI** and **prepend to each follower's feed**. ⚠ throughput must be enormous; ⭐⭐ **variable work per item — 1M followers vs 1k is wildly different ⇒ break up the tasks**|
|⭐ DD2 Great — per-account|⭐⭐ **`precomputed` flag on the Follow row**; workers **skip** those follows; read path **merges the partial precomputed feed with recent posts from non-precomputed accounts.** ⭐⭐ HI's principle: _"choose fan-out on read or write **per account** — most users get a little of both; **we don't need a one-size-fits-all solution**."_ ⚠ more read-time compute; threshold is a dial|
|⊕ flag on Follow vs User|`05f` flags the **User** (`isCelebrity`); here the **relationship.** ⭐⭐ **the read path already queries "who do I follow", so the flag comes back free** — on the User record you'd need a **second lookup per followee.** ⚠ cost = **denormalization**: crossing the threshold means backfilling all that user's Follow rows (fine as a background job)|
|⭐⭐ DD3 why hot keys hurt|**DynamoDB/KV stores need even load across the keyspace** — real physical machines underneath. ⭐ _"Post1 at 500 req/s and Post2–1000 at 0 is not even load."_ ▹ helped by posts being **created far more than edited** ⇒ long TTLs are safe|
|DD3 Good — sharded cache|Redis between readers and Posts, **long TTL + LRU**, keyed by postId; capacity **N hosts × M memory**; ⭐ **invalidate on edit, not create.** ⚠⚠ **same hot-key problem as the table** — the shard with viral posts is overloaded while other hosts idle|
|⭐⭐ DD3 Great — replicated cache|⭐⭐ **every instance can serve ANY post** (not one post per node); **LB spreads requests; no coordination.** ⭐ **a viral post's traffic spreads across all N instances.** ⚠ tradeoff: **N initial misses instead of 1** (still ≪ millions) and **capacity is M, not N×M.** ⭐⭐ _"N times the throughput for a hot key without any additional coordination"_|
|⊕⭐⭐ The general rule|**too much DATA for one node → shard.** ⭐ **too much TRAFFIC for one key → replicate.** ⚠ **sharding cannot help a single hot key** — it lands on one shard by definition, and more shards just means more idle neighbours. ▹ read-side twin of `03b`'s hot-resource row|
|⭐⭐ `05f` vs `05g`|**store:** Redis ZSET vs **DynamoDB table** · **cap:** none vs **200 + naive fallback** · **celebrity marker:** User field vs **Follow-row flag** · **hydration:** ZSET+HASH vs **Post Cache** · **hot keys:** absent vs ⭐⭐ **sharded-vs-replicated** · **media:** whole dive vs **out of scope** · **order:** chronological vs **reverse chronological + cursor**|
|Levels (short)|**E4:** API + data model + functional HLD, some "Good" solutions, **not all edge cases** · **E5:** fast HLD then ⭐ **≥2 deep dives in detail**, **proactively surfaces fan-out** · **Staff+:** ⭐ **all the dives**, plus **performance tuning**; interviewer **focuses, doesn't steer**|

---

> 🔗 **HI source:** https://www.hellointerview.com/learn/system-design/problem-breakdowns/fb-news-feed
> 
> ▹ **Changelog worth knowing** (the write-up was revised Feb 2026): fixed **reverse chronological** terminology, **corrected the storage calculation**, clarified the follow API endpoint, **added fan-out on read/write terminology**, improved the **cache strategy** descriptions, and noted **DynamoDB single-table design** as the real-world best practice.
> 
> ✅ **Source complete** — all FRs/NFRs, the planning step, entities, API, four HLD sections, DD1 with the product-constraint discussion and sizing, DD2's three rungs, DD3's two rungs, the final design and all three level bars are reconciled against the original. **No known gaps.**