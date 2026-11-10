# Live Comment Broadcasting (FB Live Comments) — Problem Breakdown

> 📐 **Revision note (calc):** ⚠ **no capacity math — HI never sizes storage or throughput. Don't invent any.** The figures that matter are all about **perception and limits:** ⭐⭐ **<200ms end-to-end, because humans perceive anything under 200ms as instantaneous** · ⭐⭐ **~100k concurrent SSE connections per server** (⚠ **NOT 65,535 — see §5.2**) · ⭐⭐ **mega-stream: 5,000 comments/sec × ~4 words = War and Peace in under 30 seconds; show 20 on screen and each is visible for ~4ms** ▸ **that one figure is the whole argument for Part 2** · **sampling: 50% at 100/sec, 1–2% at 5,000/sec** · **ring buffer of 100–200 comments, snapshotted every second** · **flip to CDN at 100k viewers or 500 comments/sec** · **CDN costs 1–2s latency** · **replay the last ~5 minutes, 100 comments per catch-up call.**

> Hello Interview · Question Breakdowns · File `05q`. **Evan King**, updated **Feb 13, 2026** · ⭐ **"medium"** · ⭐⭐ **asked at Amazon, Bloomberg, Google (+2 unnamed)** · has a video walkthrough. ⭐ **ONE Pattern callout: `Real-time Updates` → `03a`.** ⭐⭐ **This is the file `05n §5.4` points to for Pub/Sub — same problem, an order of magnitude bigger.** Cross-refs: ⭐⭐ **real-time protocol choice → `03a`** · ⭐ **SSE + Pub/Sub cross-server fan-out → `05n §5.3`–`§5.4`** · **DynamoDB keys + cursor queries → `02f`** · ⭐ **Redis Pub/Sub → `02a`** · ⚠ **Kafka, and why it LOSES here → `02c`** · ⭐ **Zookeeper / etcd for the video→server map → `02i`** · **consistent hashing in the L7 LB → `01g`** · ⭐⭐ **CDN → `01a`** · **sharding → `01f`** · **caching → `01e`** · **pagination → `01b`** · **CAP → `01h`** · **numbers → `01i`.** **Siblings: ⭐⭐ `05n` Online Auction (the same SSE + Pub/Sub shape, smaller) · `05g` FB News Feed (hot key) · `05p` Job Scheduler (DynamoDB WCU limits + write sharding) · `05k`/`05i` (where polling BEAT push — ⚠ and this file reverses that at scale).**
> 
> **Calibration:** ⭐⭐ **High value, and the best single idea in the series so far is in Part 2 of DD2.** ▸ **One pattern, but it goes deeper than any other file: DD2 has two parts and five rungs, DD3 is substantive, and the mega-stream section reframes the problem rather than scaling it.** ⭐ **Asked at 5 companies including Amazon, Bloomberg and Google.** ⭐⭐ **TWO passes**, and **do it next to `05n`** — HI cross-references them.
> 
> - ⭐⭐ **What actually scores:**
>     - **(a)** ⭐⭐⭐ **"The requirements themselves change at extreme scale"** (§5.2 Part 2). ▸ **At 5,000 comments/sec nobody can read them, so low latency and reliable delivery STOP MATTERING.** ⭐ **HI names this as the staff-level move.**
>     - **(b)** ⭐⭐⭐ **Flipping from PUSH to PULL via CDN for mega-streams.** ▸ **A reversal of everything earlier in the series, and it's correct.**
>     - **(c)** ⭐⭐ **The three coordination options**, and ⭐ **why co-locating viewers of one video on one server is what makes partitioned pub/sub work.**
>     - **(d)** ⭐⭐ **SSE over WebSockets because of the read/write RATIO** — ▸ **a sharper reason than `05n` gave.**
>     - **(e)** ⭐⭐⭐ **Knowing the 65,535 "limit" is a myth, and why.** ▸ **Cheap to say, and almost nobody gets it right.**
>     - **(f)** ⭐⭐ **`Last-Event-ID` for reconnection replay**, plus **bounded replay and client-side position tracking.**
>     - **(g)** ⭐ **Cursor over offset pagination because offset is UNSTABLE** — ▸ **not just slower.**
> - ⭐ **Transferable primitives:**
>     - ⭐⭐⭐ **At extreme scale, re-examine the requirement before scaling the solution.** ▸ **If no human can consume the output, latency and completeness are no longer the goal.** ⭐ **Reusable for any firehose: logs, telemetry, trading tickers, chat.**
>     - ⭐⭐⭐ **Push and pull are not a hierarchy. Pull wins when the same payload serves everyone.** ▸ **A snapshot of "the last 200 comments" is identical for every viewer, so it's cacheable — and a CDN serving millions the same bytes is exactly what CDNs do.**
>     - ⭐⭐ **Choose a real-time protocol by the READ/WRITE RATIO, not by capability.** ▸ **Balanced ⇒ WebSocket. Read-heavy ⇒ SSE. Predictable cadence ⇒ polling** (`05k`).
>     - ⭐⭐ **Co-locate the clients that need the same data.** ▸ **Routing by content key turns N subscriptions per server into one.**
>     - ⭐ **Bound a channel count with `hash(key) % N`** when per-key channels would explode.
>     - ⭐ **Optimistic local insert gives read-your-own-write for free** when the shared path is slow.
> - ⭐ **Re-run (cross-ref, NOT re-explained):** **SSE mechanics + the connection map + Pub/Sub fan-out (`05n §5.3`–`§5.4` — ⭐ read that first, this is the scaled-up version)** · **cursor pagination (`01b`)** · **DynamoDB partition/sort keys (`02f`)** · **consistent hashing (`01g`)** · **`userId` from the JWT not the body (`05c`/`05h`/`05i`/`05n`)**. **Genuinely new:** ⭐⭐⭐ **the mega-stream reframe + CDN snapshot delivery** · ⭐⭐⭐ **the 65,535 myth** · ⭐⭐ **read/write ratio as the protocol test** · ⭐⭐ **partitioned pub/sub channels + L7 co-location** · ⭐⭐ **the Dispatcher Service (inverted pub/sub)** · ⭐⭐ **adaptive sampling with priority** · ⭐⭐ **`Last-Event-ID`** · ⭐ **hysteresis on a mode-switch threshold** · ⭐ **why Redis pub/sub beats Kafka for dynamic subscriptions.**

---

## 0 · Understanding the problem

📹 **What are Facebook Live Comments?**

A feature letting **viewers post comments on a live video feed** and see **a continuous stream of comments in near-real-time.**

---

## 1 · Requirements

### 1.1 Functional (what it does)

1. ⭐ **Viewers can post comments on a live video.**
2. ⭐⭐ **Viewers can see new comments while watching.**
3. ⭐ **Viewers can see comments made before they joined.**

⚠ **Below the line:** reply to comments · react to comments.

### 1.2 Non-functional (how it behaves)

1. ⭐ **Scale to millions of concurrent videos and thousands of comments/sec per video.**
2. ⭐ **Availability over consistency — eventual consistency is fine** (`01h`).
3. ⭐⭐ **Low latency — near-real-time broadcast, <200ms end-to-end under typical network conditions.**

⚠ **Below the line:** security (only authorised users post) · integrity (spam, hate speech).

> ⭐⭐ **Why 200ms — the one fact that justifies the NFR, and worth saying:**
> 
> **Humans perceive an interaction as real-time if it happens within ~200ms.** ▸ **Anything shorter reads as instantaneous.** ⭐ **So 200ms is the target for any real-time system, not an arbitrary number.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 1.3 ⭐⭐ The design driver — an extreme fan-out whose RATIO varies by orders of magnitude

|||
|---|---|
|**Write side**|▸ **trivial. One comment, one row.**|
|⭐⭐ **Read side**|**that one comment must reach millions of open connections spread across thousands of servers**|
|⭐⭐⭐ **And the ratio isn't fixed**|**a normal stream has hundreds of viewers; the World Cup final has hundreds of millions**|

- ⭐⭐⭐ **That variance is the whole problem, and it's what makes this harder than `05n`.** ▸ **You cannot solve it by adding servers, because the architecture has to change SHAPE at the top end.**
- ⭐⭐ **So the answer comes in three layers, and each one is a deep dive:**
    1. **Push to connections** — SSE (§5.1).
    2. **Coordinate across servers** — pub/sub + co-location (§5.2 Part 1).
    3. ⭐⭐⭐ **Change the delivery model entirely** — CDN pull (§5.2 Part 2).
- ⭐⭐ **And what licenses layer 3: above a threshold, the requirements themselves change.** ▸ **Nobody can read 5,000 comments/sec, so "deliver every comment in <200ms" stops being a goal.**

### 1.4 Planning the approach

▸ **Sequentially through the FRs, then let the NFRs drive the depth.** ▹ Same as `05e`/`05i`/`05k`/`05n`.

---

## 2 · Core Entities

- **User** — a viewer or a broadcaster.
- ⭐ **Live Video** — **owned and managed by a different team**, ▸ **but you integrate with it.**
- **Comment** — the message posted on a live video.

▹ ⭐ **HI's framing for why entities come before the data model:** _"we're too early in the design and likely can't accurately enumerate all the columns/fields yet."_ ▸ **Think of them as the system's nouns.**

---

## 3 · API

```
POST /comments/:liveVideoId
Header: JWT | SessionToken
{ "message": "Cool video!" }
```

```
GET /comments/:liveVideoId?cursor={last_comment_id}&pageSize=10&sort=desc
```

- **`userId` from the JWT, not the body.**
- ⭐ **Pagination matters on the GET** — ▸ **and §4.3 decides which kind.**

---

## 4 · High-Level Design

### 4.1) Post a comment

```
Commenter Client ──HTTPS──► Comment Management Service ──► Comments DB (DynamoDB)
                                                             Comment
                                                               commentId (PK)
                                                               videoId  (shard)
                                                               content
                                                               author
                                                               createdAt (SK)
```

**The flow — three steps:**

1. **User drafts a comment on their device.**
2. **Client sends it via `POST /comments/:liveVideoId`.**
3. **Comment Management Service stores it in the comments DB.**

- ⭐ **Comment Management Service does both jobs: creating comments AND querying them** for the viewer client.
- ⭐ **DynamoDB chosen because** _"we are storing simple comments that don't require complex relationships or transactions"_ (`02f`). ▹ **Postgres or MySQL would work too.**

### 4.2) See new comments while watching — the naive version

▸ **Start with polling:** `GET /comments/:liveVideoId?since={last_comment_id}`, **and the client appends whatever is newer.**

- ⚠⚠ **Why it fails:** **more comments and viewers ⇒ higher polling frequency ⇒ heavy database strain**, and ⭐ **most polls return nothing because there are no new comments.** ⚠⚠ **To hit "near real-time" you'd poll every few MILLISECONDS — not feasible.**
- ▹ ⭐ **HI's advice on starting simple:** **if you already know the complex solution you can jump straight to it — just justify it and state the trade-offs.** ▸ **Seeing the problem for the first time? Start simple; it gives you a foundation for the dives.**

### 4.3) See comments from before you joined — pagination

▸ **Two needs on joining: ⭐ new comments in real time AND ⭐ a history to scroll back through** ("infinite scrolling").

- ⚠ **The `since` parameter is the wrong direction** — it gives comments NEWER than a point. ⭐ **What you want is: "the N most recent comments BEFORE a certain timestamp."**

⚠ **Rung labels are mine.**

**⚠ Offset pagination** — `?offset=0&pagesize=10`

- ⚠ **Challenges:**
    - ⭐ **Inefficient as volume grows** — **the DB counts through every row before the offset on each query.**
    - ⭐⭐⭐ **And the real killer: it is NOT STABLE.** ▸ **A comment added or deleted mid-scroll shifts the offset ⇒ the user sees DUPLICATES or MISSES comments.** ⭐ **In a fast-moving feed that happens constantly.**

**Why climb:** an offset describes a position in a list that's changing under you. Point at an item instead.

**⭐ Cursor pagination** — `?cursor={last_comment_id}&pageSize=10`

- ⭐ **The cursor is a unique identifier pointing at a specific item.** ✅ **No counting through preceding rows (given an index on the cursor field), and it's STABLE — additions and deletions don't move it.**

```json
{
  "TableName": "comments",
  "KeyConditionExpression": "liveVideoId = :liveVideoId AND commentId < :cursor",
  "ExpressionAttributeValues": { ":liveVideoId": "liveVideoId", ":cursor": "last_comment_id" },
  "ScanIndexForward": false,
  "Limit": "pageSize"
}
```

- ✅ ⭐ **Four reasons HI gives for the choice: more efficient · stable during scrolling · fits DynamoDB's key-based queries · performance stays consistent as volume grows.**
- ⚠ **Remaining challenge:** **still one DB query per page, which is significant at this traffic.**

---

## 5 · Deep Dives

### 1) ⭐⭐ How do we broadcast comments in real-time?

⚠ **HI, bluntly: polling _"is not going to pass the interview."_** ▸ ⭐ **Stop making the client GUESS when data is ready. Push it.**

> ⭐ **Pattern: Real-time Updates** (`03a`) — **the only callout.** ▹ **SSE broadcast, pub/sub distribution, multi-server coordination — ⭐ the same principles serve collaborative editing, live dashboards and gaming.**
> 
> ■ **— end of insert · HI write-up resumes below —**

⚠ **Rung labels are mine.**

**WebSockets**

- **Approach:** ⭐ **a two-way channel held open; the server pushes new comments without further requests.** ✅ **Eliminates polling entirely.**
- ⚠ **Challenges — and the reason is the ratio, not the capability:**
    - ⭐⭐⭐ **The read/write ratio is badly unbalanced.** ▸ **_"most viewers will never post a comment, [but] they will be viewing/reading all comments."_**
    - ⭐⭐ **So a two-way channel per viewer is wasted** — **the overhead of maintaining it is high and the upstream direction is almost never used.**
    - ▹ ✅ **HI is fair to it: for a real-time CHAT app with a balanced ratio, WebSockets are optimal.**

**Why climb:** you're paying for a duplex channel and using one direction.

**⭐⭐ Server-Sent Events (SSE)**

- ⭐ **Approach:** **a persistent connection over standard HTTP** — ✅ **simpler to implement than WebSockets.** **The server pushes in real time; client→server goes over ordinary HTTP requests.**
- ⭐⭐ **Why it fits exactly:** **infrequent comment creation uses plain HTTP POST; frequent reads use SSE's one-way streaming.**
- ⚠ **Challenges — all infrastructure, and worth naming because they're non-obvious:**
    - ⚠⚠ **Some proxies and load balancers don't support streaming responses** ⇒ **buffering issues that are _"difficult to track down."_**
    - ⚠ **Browsers limit concurrent SSE connections per domain** ⇒ **a problem for users watching several live videos at once.**
    - ⚠ **Long-lived connections complicate monitoring and debugging.**

**The updated flow:** **comment posted and persisted → Comment Management Service pushes it over SSE to all connected clients subscribed to that video → clients append it to the feed.**

- ⚠ ⭐ **HI flags its own design: _"this solution does not scale."_** ▸ **One server, all connections. → §5.2.**

> ⊕ ⭐ **(mine) — the browser connection limit has a one-word fix HI doesn't give.**
> 
> - ⚠ **The ~6-connections-per-origin cap is an HTTP/1.1 limitation.** ⭐⭐ **HTTP/2 multiplexes many streams over ONE connection, so the limit effectively disappears.**
> - ⭐ **Say it in one clause** — _"on HTTP/2 the per-domain SSE cap stops mattering"_ — ▸ **it turns a listed weakness into a solved one.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 2) ⭐⭐⭐ How do we scale to millions of concurrent viewers?

⭐ **Server capacity: _"commonly in the range of 100k"_ concurrent connections** — ⚠ **CPU, memory and file descriptors become the bottleneck before any theoretical limit.** ▸ **Millions of viewers ⇒ scale horizontally.**

> ⭐⭐⭐ **Confusion resolved — the 65,535 "connection limit" is a myth, and knowing why is nearly free points.**
> 
> - ⚠ **65,535 is the range of PORT NUMBERS, not a connection count.**
> - ⭐⭐ **A TCP connection is identified by a 4-tuple: source IP + source port + destination IP + destination port.** ▸ **The server's port is fixed; the variety comes from the CLIENT side.**
> - ⭐⭐ **So ONE listening port can hold hundreds of thousands — even millions — of concurrent connections with OS tuning and enough resources.**
> 
> ■ **— end of insert · HI write-up resumes below —**

⭐⭐ **HI splits this dive in two, and the split is the lesson: Part 1 solves coordination, Part 2 solves what happens when coordination itself stops being enough.**

---

#### Part 1 · Server coordination

⚠⚠ **The core problem:** **UserA watches Video 1 on Server 1. UserB watches Video 1 on Server 2.** ▸ **A comment hits Server 1 — it reaches UserA directly, but Server 1 has NO WAY to reach UserB.**

▹ ⭐ **Identical to `05n §5.3`'s closing challenge. Same problem, bigger.**

**⭐ First, split read from write:** **create dedicated Realtime Messaging Servers for sending comments to viewers**, because **write traffic is much lower than read traffic and the two must scale independently.**

**⭐ Each messaging server keeps a local in-memory map:**

```json
{
  "liveVideoId1": ["sseConnection1", "sseConnection2"],
  "liveVideoId2": ["sseConnection3", "sseConnection4"]
}
```

> ⚠⚠ **Confusion resolved — the mechanism behind the three rungs. Read this BEFORE them.**
> 
> **① ⭐⭐ What pub/sub is, and the one cost that matters.** ▸ **A named mailbox: a publisher drops a message in, and EVERY subscriber to that mailbox gets a copy.** ⭐⭐ **The cost: subscribe to a channel and you receive EVERY message in it. There is no server-side filtering — you get it, then decide if you care.**
> 
> **② ⭐ The setup, with numbers.** **1M viewers · 1,000 live videos · ~100k connections per server ⇒ 10 servers.** ⚠⚠ **Round-robin sends each new viewer to the next server in rotation, so Server 1's 100k viewers are a RANDOM MIX — statistically, viewers of all 1,000 videos sit on every server.** ▸ **So a comment on Video 42 is needed by ALL 10 servers.**
> 
> **③ ⚠⚠ Why one channel wastes ~90%.** At **50,000 comments/sec** across all videos:
> 
> ||per server|
> |---|---|
> |**Received**|⚠ **all 50,000/sec**|
> |**Actually useful**|**~5,000** (its viewers' videos)|
> |**Discarded**|⚠⚠ **~45,000**|
> 
> ▸ **×10 servers = 500,000 deliveries/sec to do 50,000 useful ones.** ⭐ **That's "every server reads the whole firehose for its own small slice."**
> 
> **④ ⚠⚠ Why partitioning ALONE fixes nothing — the step that's easy to miss.** **Make 100 channels; Video 42 goes to `hash(42) % 100`.** ▹ **Why 100 and not one per video: each channel costs connections and bookkeeping, a million videos means a million channels, and Kafka degrades past a few thousand partitions.** ⚠⚠ **But Server 1's viewers still span all 1,000 videos, which hash into roughly ALL 100 channels ⇒ it subscribes to all 100 and receives everything again.** ⭐ **More complexity, zero gain.**
> 
> **⑤ ⭐⭐⭐ What Layer 7 gives you that Layer 4 can't:**
> 
> ||Sees|Can it route by video?|
> |---|---|---|
> |**Layer 4**|**IP + port only** — it routes packets|⚠ **no**|
> |⭐⭐ **Layer 7**|**the HTTP request — URL path, headers**|⭐⭐ **yes — it reads `liveVideoId` and sends you to the server already handling that video**|
> 
> **⑥ ⭐⭐⭐ And THAT is what makes ④ pay off.** ▸ **Server 1 now holds viewers of Videos 1–100 only ⇒ a handful of channels ⇒ every message it receives is useful. Waste ≈ 0.** ⭐⭐ **So it's TWO moves and the second is what makes the first work: partition the channels, AND co-locate the viewers.** ▹ **Consistent hashing is just HOW the LB picks the owner — chosen so adding or removing a server reshuffles a small fraction of videos, not all of them** (`01g`).
> 
> **⑦ ⭐⭐ What the Dispatcher inverts — the direction of initiative:**
> 
> ||Who initiates|
> |---|---|
> |**Pub/sub**|**servers DECLARE interest, then passively receive from their channels**|
> |**Dispatcher**|⭐ **a central brain is ASKED "who needs this?" and pushes straight to those servers over HTTP**|
> 
> ▸ **No subscriptions to manage, routing logic in one place** — ⚠ **but the map must be live and accurate, and it goes stale fastest exactly when it matters most: a stream going viral.**
> 
> ■ **— end of insert · HI write-up resumes below (the three rungs) —**

⚠ **Rung labels are mine.**

**⚠ Simple pub/sub — one channel for everything**

- **Approach:** ⭐ **the comment service publishes every new comment to a channel; ALL messaging servers subscribe and forward to their viewers of that video.** ▸ **Round-robin load balancing distributes clients.**
- ⚠ **Challenges:** ⭐⭐ **every server processes EVERY comment across ALL live videos — even when none of its viewers are watching that video.** ⇒ **wasted compute, _"impractical at Facebook scale."_**

**Why climb:** every server is reading the whole firehose to find its own small slice.

**⭐⭐ Partitioned channels + Layer 7 co-location**

- ⭐ **Partition the comment stream into channels; each server subscribes ONLY to the channels it needs.**
- ⭐⭐ **Bound the channel count with `hash(liveVideoId) % N`** — ▸ **a channel per video would consume too many resources and _"may be infeasible with systems like Kafka."_**
- ⚠⚠ **But round-robin breaks it:** **a server ends up with viewers of many different videos ⇒ it subscribes to many channels ⇒ you've recreated the inefficiency.**
- ⭐⭐⭐ **The fix is INTELLIGENT ROUTING — and this is the key move:** **a Layer 7 load balancer uses consistent hashing on `liveVideoId`** (`01g`) **to route viewers of the SAME video to the SAME server.** ▸ **NGINX or Envoy, inspecting the request path or headers.**
    - ▹ ⭐ **Alternative: a dynamic `liveVideoId → server` map in a coordination service like Zookeeper** (`02i`) — **more flexible, at the cost of operational complexity.**
- ⚠ **Challenges:** **coordinating load balancing with pub/sub subscriptions** — ▸ **a server's viewer mix changes ⇒ it must update subscriptions; servers scale up or down ⇒ routing mappings must stay in sync.**

**Why climb (or not):** this works. The next rung is an alternative, not an improvement.

**⭐ Dispatcher Service — invert the model**

- ⭐⭐ **Approach: instead of servers SUBSCRIBING, a Dispatcher ROUTES each comment to the right servers.** ▸ **The comment service asks the Dispatcher _"which servers have viewers watching this video?"_ and it forwards directly.**
- ⭐ **The Dispatcher keeps a dynamic server→video map, synced by heartbeats and registration as servers join or leave.** **Multiple instances run behind a load balancer, all reading the same coordination data (Zookeeper or etcd).**
- ✅ **Benefits:** **no pub/sub subscriptions to manage** · ⭐ **routing logic centralised and easier to reason about** · ⭐ **room for sophisticated rules (load-based routing) without touching the messaging servers.**
- ⚠ **Challenges:** ⭐ **keeping the map accurate during rapid change** — **a viral stream brings a sudden influx of viewers, so the Dispatcher must refresh frequently**, and ⚠ **multiple instances need coordinated cache invalidation to avoid stale mappings.**

> ⭐⭐ **HI's verdict and the Kafka-vs-Redis note — both worth having ready.**
> 
> - ⭐⭐ **The pick: _"Pub/sub is typically easier with fewer corner cases, so it's the one I'd reach for in an interview."_** ▸ **Both options are "great solutions"; pub/sub + co-location is the default.**
> - ⭐⭐ **Kafka vs Redis pub/sub** — ⚠ **Kafka is highly scalable and fault-tolerant but _"struggles with dynamic subscription patterns like users switching between videos."_** ⭐ **Redis pub/sub gives low latency and handles dynamic subscriptions well ⇒ the right choice here.**
> - ⭐⭐ **And why fire-and-forget is acceptable:** **comments are persisted to the database anyway, so a comment missed during a brief disconnect is recovered by §5.3's catch-up.** ▹ ⭐ **Third data point on the thread: a log is not always the right queue** (`05p §5.1`, `05i`).
> 
> ■ **— end of insert · HI write-up resumes below —**

---

#### Part 2 · ⭐⭐⭐ Mega-streams — where the requirements change

⚠ **The scenario: the World Cup final, hundreds of millions of viewers on ONE stream, thousands of comments per second.** ⭐⭐ **HI: _"This is a fundamentally different problem."_**

> ⭐⭐⭐ **The reframe. This is the best idea in the file — memorise the arithmetic, because the arithmetic IS the argument.**
> 
> - 📐 **5,000 comments/sec × ~4 words each** ⇒ ⭐⭐ **the equivalent of reading War and Peace in under 30 seconds.**
> - 📐 **Show the last 20 messages on screen** ⇒ ⭐⭐ **each one is visible for about 4 MILLISECONDS before being pushed off.** ▸ **No human reads that fast.**
> - ⭐⭐⭐ **Therefore: _"the traditional goals of real-time systems (low latency, reliable delivery of every message) become less important."_** ▸ **Users are experiencing _"a 'vibe' of collective participation rather than reading a conversation."_**
> - ⭐⭐⭐ **The transferable move: at extreme scale, re-examine the REQUIREMENT before scaling the SOLUTION.** ▸ **Reusable for any firehose — logs, telemetry, trading tickers, chat.**
> 
> ■ **— end of insert · HI write-up resumes below —**

**⭐⭐ Adaptive sampling (Good Solution)**

- ⭐ **Approach: viewers don't need every comment — just _"enough comments to feel the energy of the crowd."_** **Sample the stream per viewer.**
- ⭐⭐ **The rate adjusts to comment velocity:** **~50% at 100 comments/sec · 1–2% at 5,000/sec.** ▸ **Each viewer gets roughly the same comments per second regardless of actual volume** ⇒ ⭐ **a consistent, readable experience.**
- ⭐⭐ **And get clever with WHICH ones:** **rather than pure random, prioritise comments from users the viewer FOLLOWS, comments GETTING REACTIONS, or VERIFIED accounts.** ▸ **So the "best" comments are likelier to be seen.**
- ⚠ **Challenges:** **sampling cuts load but you're still holding persistent SSE connections to millions of viewers and pushing in real time** ⇒ **infrastructure costs stay substantial.**

**Why climb:** you've reduced the payload but not the connection count. Change the delivery model.

**⭐⭐⭐ CDN snapshot delivery — flip from push to pull (Great Solution)**

- ⭐⭐ **Approach — the architecture:**
    - **Server side: a RING BUFFER of the most recent 100–200 comments per mega-stream.**
    - ⭐ **Every second (or more often), snapshot the buffer and write it to Redis or the CDN origin.**
    - ⭐⭐ **The CDN distributes the snapshot globally, cached at edge locations** (`01a`).
    - **Client side: no SSE. The app POLLS the CDN every second for the latest snapshot.**
- ⭐⭐ **And the client-side detail that makes it feel real:** **don't dump the whole snapshot on screen — _"that would look janky."_** ▸ **Animate the new comments smoothly, spaced across the polling interval to simulate a continuous stream.** ⭐ **Use the timestamps to space them by their ACTUAL timing, so it feels organic.**
- ⭐⭐⭐ **Why it's elegant, and the line to say:** _"CDNs are designed to serve the same content to millions of users simultaneously, and that's literally their job. **A comment snapshot is just another piece of cacheable content**, no different from a video thumbnail."_
- ⭐ **The switch is dynamic:** **cross 100,000 concurrent viewers or 500 comments/sec ⇒ automatically flip from SSE to CDN.** **The client handles the transition seamlessly.**
- ⚠ **Challenges — three, and all three are worth naming:**
    - ⚠⚠ **Latency: 1–2 seconds instead of sub-200ms.** ⭐ **Acceptable only because of the reframe above — at mega-stream scale nobody can engage with individual comments.**
    - ⭐⭐ **Read-your-own-write:** **you want to see YOUR comment immediately even if others wait a second.** ▸ ⭐ **The client handles it locally by optimistically inserting your own comments, independent of CDN polling.**
    - ⭐ **Transitioning BACK to SSE when viewership drops needs HYSTERESIS in the threshold** — ▸ **otherwise it flaps between modes as viewership hovers at the cutoff.**

> ⭐⭐ **HI's summary of the whole dive — the interview calibration, worth knowing verbatim in substance:**
> 
> - **Moderate viewership ⇒ pub/sub with viewer co-location handles coordination elegantly.**
> - **Mega-stream ⇒ ⭐ sampling is the middle ground, ⭐⭐ CDN snapshots the most scalable, at the cost of latency.**
> - ⭐⭐⭐ **_"discussing the sampling approach demonstrates strong understanding while the CDN-based approach shows **staff-level thinking** because it recognizes that **the requirements themselves change at extreme scale**."_**
> 
> ■ **— end of insert · HI write-up resumes below —**

> ⊕ ⚠⚠ **(mine, not HI) — the WRITE path is never scaled, and `videoId` as the shard key breaks on exactly the stream Part 2 is about.**
> 
> - ▸ **DD2 scales the connection layer thoroughly and never touches the database.** ⚠⚠ **But the schema shards on `videoId`** — **so a mega-stream's 5,000 comments/sec all land on ONE partition.**
> - ⚠ **From `05p §5.2`: DynamoDB caps around 1,000 WCU per partition.** ⭐⭐ **5,000 writes/sec on one key is a hot partition by definition** — ▸ **`05g`'s rule: too much traffic for one key ⇒ you cannot shard your way out, you must spread the key itself.**
> - ⭐⭐ **The fix is the same write-sharding move as `05p`:** **make the partition key `videoId#bucket`** (a random suffix or a time bucket), **and read all buckets in parallel for the catch-up query.**
> - ⭐ **Worth raising unprompted** — ▸ **HI spends a whole dive on read fan-out and leaves the write hot-spot unmentioned, in the one scenario that guarantees it.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 3) ⭐⭐ How do we handle disconnections so viewers don't miss comments?

⚠ **HI's framing: _"Mobile networks are flaky."_** ▸ **Users background apps, walk through tunnels, switch between WiFi and cellular.**

⚠ **Rung labels are mine.**

**⚠ Do nothing**

- **Approach:** **on reconnect, just resume from that moment. Comments during the gap are lost to that user.**
- ⚠ **Challenges:** ⭐ **bad UX even for brief drops** — **_"a tense moment in a sports stream, your WiFi hiccups for 5 seconds, and when you reconnect, you've missed all the reactions to the big play."_** ⚠ **For longer drops the user returns to a feed with no context for what happened.**

**Why climb:** the comments exist in the database. There's no reason to lose them.

**⭐⭐ `Last-Event-ID` + explicit catch-up**

- ⭐⭐ **SSE has reconnection handling BUILT IN via the `Last-Event-ID` header.** ▸ **Every comment carries a unique event ID (the comment ID works).** **On disconnect the browser reconnects automatically and sends the last ID it received; the server replays what was missed, then resumes streaming.**
- ⭐ **For more control, the client tracks its own position** (localStorage on web, app storage on mobile) **and requests catch-up explicitly:** `GET /comments/:liveVideoId?since={last_comment_id}&limit=100`.
- ⭐⭐ **Which buys a better UX than a data dump:** **animate missed comments at 2–3× speed**, or **show _"You missed 47 comments"_ with an option to jump to live.**
- ⭐⭐ **Mobile battery optimisation, and it's a good unprompted detail:** **on backgrounding, preemptively disconnect the SSE and record the position; on foregrounding, reconnect and catch up.** ▸ **More efficient than holding a connection the OS throttles anyway.**
- ⭐⭐ **Bound the replay:** **disconnected for an hour ⇒ thousands of stale comments would overwhelm the user.** ⭐ **Replaying the last ~5 minutes is reasonable, with graceful degradation beyond that.**
- ⚠ **Challenges:**
    - ⭐⭐ **A reconnecting user likely lands on a DIFFERENT messaging server** (load balancing) — **which needs access to comment history.** ⭐ **A shared Redis cache lets any server replay recent comments for any video** (`01e`).
    - ⭐⭐ **Coordinating the SSE stream with the HTTP catch-up** — ⚠ **comments arriving via SSE while the catch-up response is in flight** ⇒ ⭐ **the client must DEDUPLICATE on comment ID and merge correctly.**

> ⭐⭐ **HI's interview calibration for this dive — the four things to mention:**
> 
> **`Last-Event-ID` as the foundation** · ⭐ **bounded replay (you can't replay an hour)** · ⭐ **client-side position tracking** · ⭐ **graceful degradation when replay isn't possible.** ▸ ⭐⭐ **_"This shows you've thought about the messy realities of mobile networks and user behavior."_**
> 
> ■ **— end of insert · HI write-up resumes below —**

---

## 6 · Final Design

⚠⚠ **I've drawn what HI RECOMMENDS, not what HI's diagram shows — the two disagree. See the ⊕ note below.** ⚠ **Layout and arrows are mine; components and field lists are HI's.**

```
Commenter Client                          Viewer Client
  │  POST /comments/:liveVideoId            │  ◄── SSE stream (normal streams)
  │  Header: JWT  ⭐ userId from the token   │  ◄── CDN poll  (mega-streams)
  │  GET  /comments/:liveVideoId            │  ⭐ optimistic local insert
  │       ?cursor&pageSize&sort=desc        │    ⇒ read-your-own-write
  ▼                                         │  ⭐ dedupe on commentId when
Load Balancer                               │    SSE + catch-up overlap
  │  ⭐⭐ LAYER 7, consistent hashing on      ▲
  │     liveVideoId  ⇒ viewers of the        │
  │     same video land on the SAME server   │
  │     (NGINX / Envoy)              01g     │
  │  ▹ alt: a liveVideoId→server map         │
  │     in Zookeeper / etcd          02i     │
  │                                          │
  ├──► Comment Management Service   ⭐ WRITE path only — low volume
  │         │
  │         ├──► Comments DB (DynamoDB)                            02f
  │         │      Comment: commentId (PK) · videoId (shard)
  │         │               content · author · createdAt (SK)
  │         │      ⭐ cursor query: liveVideoId = :id AND commentId < :cursor
  │         │               ScanIndexForward: false, Limit: pageSize
  │         │      ⊕ ⚠⚠ videoId as shard key = a hot partition on any
  │         │         mega-stream (5k writes/s vs ~1,000 WCU per partition)
  │         │         ⇒ partition on videoId#bucket, read buckets in parallel
  │         │
  │         └──► Redis Pub/Sub                                02a · 02c
  │                ⭐⭐ channels bounded by hash(liveVideoId) % N
  │                ⭐ each server subscribes ONLY to channels it needs
  │                   — which works BECAUSE of the L7 co-location above
  │                ⭐ Redis not Kafka: Kafka struggles with dynamic
  │                   subscriptions (users switching videos)
  │                ⭐ fire-and-forget is fine — comments are persisted,
  │                   and §5.3's catch-up recovers anything missed
  │
  └──► Realtime Messaging Service   ⭐⭐ READ path — scaled separately
            │   { "liveVideoId1": [conn1, conn2], ... }  in local memory
            │   ⭐ ~100k SSE connections per server
            │      (⚠ NOT 65,535 — that's the PORT range)
            │   ⭐ Last-Event-ID ⇒ replay on reconnect, bounded to ~5 min
            │
            ├──► SSE to viewers            ◄── normal streams
            │
            ├──► Shared Redis cache  ⭐ so ANY server can replay recent
            │                          comments for ANY video        01e
            │
            └──► ⭐⭐⭐ MEGA-STREAM PATH  (flip at 100k viewers or 500 c/s,
                   │                      with HYSTERESIS to stop flapping)
                   │
                   ring buffer: last 100–200 comments per stream
                   │  snapshot every ~1s
                   ▼
                 CDN  ⭐⭐ edge-cached; millions pull the SAME bytes      01a
                   │   ⚠ costs 1–2s latency instead of <200ms
                   │   ⭐ acceptable ONLY because at 5,000 c/s nobody can
                   │      read them anyway — the requirement itself changed
                   ▼
                 Client polls every ~1s, then ANIMATES the new comments
                 spaced by their real timestamps so it feels continuous

  ▹ Optional middle ground: adaptive SAMPLING over SSE —
    50% at 100 c/s, 1–2% at 5,000 c/s, prioritising followed users,
    comments with reactions, and verified accounts
```

> ⊕ ⚠⚠ **(mine) — HI's own Final Design diagram contradicts HI's own recommendation, twice.**
> 
> - ⚠ **It shows the DISPATCHER and labels the hop _"HTTPS (not pub/sub)"_** — **but the text says _"pub/sub is typically easier with fewer corner cases, so it's the one I'd reach for in an interview."_** ⭐ **I've drawn the recommendation.**
> - ⚠⚠ **And Part 2 is missing entirely** — **no CDN, no ring buffer, no snapshot** — ▸ **so the best idea in the write-up isn't in its final architecture.** ⭐ **I've added it as an explicit mega-stream path.**
> - ▹ **Third file with a stale diagram** (`05k`'s per-chunk Lambda, `05p`'s Upload Monitor). ⭐ **Trust HI's prose over HI's diagrams.**
> 
> ■ **— end of insert —**

---

## 7 · Expected at Each Level

|Level|The bar for FB Live Comments|
|---|---|
|**Mid**|⭐ **Proactively realise polling's limitations and start reasoning toward a PUSH model.** ▹ **With only minor hints, reach the pub/sub solution, and scale it with some help from the interviewer.**|
|**Senior (E5)**|⭐ **Speed through the HLD to spend time on SCALING in detail.** ⭐⭐ **Reason through the initial design's limits and reach pub/sub with minimal hints.** ⭐ **Proactively lead the scaling discussion and reason through the trade-offs between solutions.**|
|**Staff+**|**High depth on scaling the broadcast specifically.** ⭐⭐ **Not just identify pub/sub but proactively call out its reliability and scalability limits and propose fixes.** ⭐ **Know the exact technology you'd use and discuss trade-offs in detail.** ▹ ⭐⭐ **And per §5.2: the CDN reframe is explicitly named as the staff-level signal.**|

---

## Quick Recall (pass 3+)

|Use / Question|FB Live Comments answer|
|---|---|
|Calibration|⭐ Evan King · Feb 2026 · **"medium"** · ⭐⭐ **Amazon, Bloomberg, Google (+2 unnamed)** · ⭐ **ONE pattern: `Real-time Updates` (`03a`).** ⭐⭐ **High value — the best single idea in the series is DD2 Part 2.** ⭐⭐ **TWO passes, and do it beside `05n`, which points here for Pub/Sub**|
|⭐⭐ Design driver|⭐⭐ **An extreme fan-out whose RATIO varies by orders of magnitude.** **Write side trivial (one comment, one row); read side must reach millions of connections across thousands of servers; ⭐⭐⭐ and a normal stream has hundreds of viewers while the World Cup final has hundreds of millions.** ⭐⭐⭐ **You can't fix that by adding servers — the architecture changes SHAPE at the top end.** **Three layers: (1) push to connections = SSE (2) coordinate across servers = pub/sub + co-location (3) ⭐⭐⭐ change the delivery model = CDN pull.** ⭐⭐ **What licenses (3): above a threshold the REQUIREMENTS change**|
|FRs / NFRs|**post comments · see new comments live · see comments from before you joined.** Below: replies · reactions. **NFRs: millions of concurrent videos + thousands of comments/s per video · availability > consistency (eventual is fine) · ⭐⭐ <200ms end-to-end.** Below: security · integrity|
|⭐⭐ Why 200ms|**humans perceive anything under ~200ms as INSTANTANEOUS** ⇒ ⭐ **it's the target for any real-time system, not an arbitrary number**|
|Entities / API|**User · ⭐ Live Video (owned by another team — you integrate) · Comment.** `POST /comments/:liveVideoId` with `{message}` and the **JWT in the header** · `GET /comments/:liveVideoId?cursor&pageSize&sort=desc`. **`userId` from the JWT, not the body**|
|HLD + DB|**Commenter Client → Comment Management Service → Comments DB.** **Service does BOTH create and query.** ⭐ **DynamoDB because _"simple comments that don't require complex relationships or transactions"_** (`02f`); **Postgres/MySQL fine too.** **Schema: `commentId` (PK) · `videoId` (shard) · content · author · `createdAt` (SK)**|
|⚠⚠ Why polling fails|**more comments + viewers ⇒ higher frequency ⇒ heavy DB strain, and most polls return NOTHING.** ⚠⚠ **Near-real-time would need polling every few MILLISECONDS.** ⭐ HI: polling _"is not going to pass the interview"_|
|⭐⭐⭐ Offset vs cursor|⚠ **Offset: counts every row before the offset, AND — the real killer — it is NOT STABLE.** ▸ **a comment added or deleted mid-scroll shifts the offset ⇒ DUPLICATES or MISSED comments**, constantly in a fast feed. ⭐ **Cursor: points at a specific item ⇒ no counting (with an index), stable under writes, fits DynamoDB key queries, performance flat as volume grows.** ⭐ `KeyConditionExpression: liveVideoId = :id AND commentId < :cursor`, `ScanIndexForward: false`, `Limit: pageSize`. ⚠ **still one query per page**|
|⭐⭐⭐ DD1 — SSE over WebSockets|⭐⭐⭐ **The reason is the READ/WRITE RATIO, not capability** — _"most viewers will never post a comment, [but] they will be viewing/reading all comments."_ ▸ **So a two-way channel per viewer is wasted overhead.** ✅ **HI is fair: for a balanced-ratio CHAT app, WebSockets ARE optimal.** ⭐ **SSE: persistent connection over standard HTTP, simpler than WS; infrequent writes use plain POST, frequent reads use one-way streaming.** ⚠ **Challenges: some proxies/LBs don't support streaming ⇒ buffering bugs _"difficult to track down"_ · browsers cap concurrent SSE per domain · long-lived connections complicate monitoring.** ⊕ ⭐ **the browser cap is HTTP/1.1 — HTTP/2 multiplexes, so it stops mattering**|
|⭐⭐⭐ The 65,535 myth|⚠ **65,535 is the PORT NUMBER range, not a connection count.** ⭐⭐ **A TCP connection is a 4-tuple: src IP + src port + dst IP + dst port — the server port is fixed, the variety is CLIENT-side.** ⭐⭐ **So one listening port holds hundreds of thousands to millions of connections with OS tuning.** ▹ **Real server capacity ~100k, limited by CPU, memory and file descriptors**|
|⚠⚠ DD2 Part 1 — the problem|**UserA on Server 1, UserB on Server 2, both watching Video 1. A comment hits Server 1 ⇒ reaches A directly, but Server 1 has NO WAY to reach B.** ▹ **identical to `05n §5.3`'s closing challenge.** ⭐ **First move: split read from write — dedicated Realtime Messaging Servers, because write traffic ≪ read traffic and they must scale independently.** **Each keeps `{liveVideoId: [connections]}` in local memory**|
|⚠ Coordination — simple pub/sub|**publish every comment to one channel; all servers subscribe and forward.** ⚠⚠ **Every server processes EVERY comment across ALL videos even with no viewers for them ⇒ wasted compute, _"impractical at Facebook scale"_**|
|⭐⭐⭐ Coordination — partitioned + L7|⭐ **partition the stream; each server subscribes only to channels it needs.** ⭐⭐ **Bound the count with `hash(liveVideoId) % N`** — a channel per video is too many and _"may be infeasible with systems like Kafka."_ ⚠⚠ **But round-robin breaks it: a server gets viewers of many videos ⇒ many subscriptions ⇒ the same inefficiency.** ⭐⭐⭐ **THE FIX: a Layer 7 LB using consistent hashing on `liveVideoId` routes viewers of the SAME video to the SAME server** (NGINX/Envoy, inspecting path or headers) `01g`. ▹ **alt: a `liveVideoId→server` map in Zookeeper** `02i`. ⚠ **Challenge: subscriptions must track a changing viewer mix, and routing maps must stay in sync as servers scale**|
|⭐ Coordination — Dispatcher|⭐⭐ **inverts pub/sub: a Dispatcher ROUTES each comment to the right servers instead of servers subscribing.** **Comment service asks _"which servers have viewers for this video?"_; the Dispatcher keeps a dynamic map synced by heartbeats + registration; instances run behind an LB over shared Zookeeper/etcd.** ✅ **no subscriptions to manage · centralised routing · room for load-based rules.** ⚠ **keeping the map accurate during a viral influx; multiple instances need coordinated cache invalidation**|
|⭐⭐ HI's pick + Kafka vs Redis|⭐⭐ **_"Pub/sub is typically easier with fewer corner cases, so it's the one I'd reach for in an interview."_** Both are "great solutions." ⭐⭐ **Kafka is scalable and fault-tolerant but _"struggles with dynamic subscription patterns like users switching between videos."_** ⭐ **Redis pub/sub: low latency + handles dynamic subs ⇒ the choice.** ⭐⭐ **Fire-and-forget is fine because comments are persisted and §5.3's catch-up recovers misses.** ▹ **3rd data point: a log is not always the right queue** (`05p`, `05i`)|
|⭐⭐⭐ DD2 Part 2 — THE REFRAME|📐 **5,000 comments/s × ~4 words = War and Peace in under 30 seconds.** 📐 **20 on screen ⇒ each visible ~4 MILLISECONDS.** ⭐⭐⭐ **So _"the traditional goals of real-time systems (low latency, reliable delivery of every message) become less important"_ — users experience _"a 'vibe' of collective participation rather than reading a conversation."_** ⭐⭐⭐ **The transferable move: at extreme scale, re-examine the REQUIREMENT before scaling the SOLUTION.** ▸ **reusable for any firehose — logs, telemetry, tickers, chat**|
|⭐⭐ Mega-stream — sampling|**viewers need _"enough comments to feel the energy of the crowd."_** ⭐⭐ **Rate adapts to velocity: ~50% at 100/s, 1–2% at 5,000/s ⇒ each viewer gets roughly the same comments/sec regardless of volume.** ⭐⭐ **Prioritise rather than randomise: users the viewer FOLLOWS · comments GETTING REACTIONS · VERIFIED accounts.** ⚠ **Still holding millions of SSE connections ⇒ costs stay substantial**|
|⭐⭐⭐ Mega-stream — CDN snapshots|⭐⭐ **Ring buffer of the last 100–200 comments per stream → snapshot every ~1s → Redis or CDN origin → edge-cached globally.** **Client POLLS the CDN every second instead of holding SSE.** ⭐⭐ **Client must ANIMATE them spaced across the interval, using real timestamps — dumping the snapshot _"would look janky."_** ⭐⭐⭐ **The line: _"CDNs are designed to serve the same content to millions of users simultaneously… a comment snapshot is just another piece of cacheable content, no different from a video thumbnail."_** ⭐ **Flip at 100k viewers or 500 comments/s.** ⚠ **Costs 1–2s latency vs <200ms — acceptable ONLY because of the reframe.** ⭐⭐ **Read-your-own-write: optimistically insert YOUR comment locally.** ⭐ **Need HYSTERESIS on the threshold or it flaps between modes**|
|⭐⭐⭐ Push vs pull, reversed|⭐⭐⭐ **Push and pull are not a hierarchy. PULL wins when the same payload serves everyone** — a snapshot of "the last 200 comments" is IDENTICAL for every viewer, so it's cacheable. ⚠ **Note this REVERSES `05i`/`05k`/`05n`, where push or light polling beat the heavier option. ⭐ The deciding factor is whether the payload is per-viewer or shared**|
|⊕⚠⚠ The write path is never scaled|▸ **DD2 scales connections thoroughly and never touches the DB.** ⚠⚠ **But the schema shards on `videoId`, so a mega-stream's 5,000 comments/s land on ONE partition** — and from `05p §5.2`, **DynamoDB caps ~1,000 WCU per partition.** ⭐⭐ **`05g`'s rule: too much traffic for one key can't be sharded away.** ⭐ **Fix = `05p`'s write sharding: partition on `videoId#bucket`, read buckets in parallel.** ▸ **HI leaves the write hot-spot unmentioned in the one scenario that guarantees it**|
|⚠ DD3 — do nothing|**resume from the moment of reconnect; the gap is lost.** ⚠ **_"your WiFi hiccups for 5 seconds, and when you reconnect, you've missed all the reactions to the big play."_** ⚠ **Longer drops ⇒ no context at all**|
|⭐⭐ DD3 — Last-Event-ID|⭐⭐ **SSE has reconnection BUILT IN: every comment carries an event ID (the comment ID); the browser auto-reconnects sending `Last-Event-ID`; the server replays the gap then resumes.** ⭐ **For more control the client tracks position locally (localStorage / app storage) and calls `?since={last_comment_id}&limit=100`.** ⭐⭐ **Better UX than a dump: animate at 2–3× speed, or _"You missed 47 comments"_ with a jump-to-live.** ⭐⭐ **Mobile: on backgrounding, preemptively disconnect and record position — the OS throttles held connections anyway.** ⭐⭐ **BOUND the replay — an hour of comments would overwhelm; ~5 min with graceful degradation.** ⚠ **Challenges: a reconnect lands on a DIFFERENT server ⇒ ⭐ a shared Redis cache lets any server replay any video; and ⭐⭐ SSE + catch-up overlap ⇒ the client must DEDUPE on commentId and merge**|
|⭐⭐ DD3 interview calibration|**mention all four: `Last-Event-ID` as the foundation · bounded replay · client-side position tracking · graceful degradation when replay isn't possible.** ⭐ **_"shows you've thought about the messy realities of mobile networks and user behavior"_**|
|⊕⚠⚠ HI's final diagram is wrong twice|⚠ **it shows the DISPATCHER and labels the hop _"HTTPS (not pub/sub)"_ — but the text recommends PUB/SUB.** ⚠⚠ **And Part 2 is absent entirely — no CDN, no ring buffer — so the best idea isn't in the final architecture.** ▹ **3rd file with a stale diagram (`05k`, `05p`).** ⭐ **Trust HI's prose over HI's diagrams**|
|Levels (short)|**Mid:** ⭐ **proactively see polling's limits and move toward PUSH**; reach pub/sub with minor hints; scale it with help · **Senior (E5):** fast HLD, then **scaling in detail**; ⭐⭐ **reach pub/sub with MINIMAL hints**; proactively lead the scaling discussion and the trade-offs · **Staff+:** depth on broadcast scaling; ⭐⭐ **not just identify pub/sub but call out its reliability/scalability limits and fix them**; know the exact tech and its trade-offs; ▹ ⭐⭐ **the CDN reframe is explicitly named as the staff signal**|

---

> 🔗 **HI source:** https://www.hellointerview.com/learn/system-design/problem-breakdowns/fb-live-comments