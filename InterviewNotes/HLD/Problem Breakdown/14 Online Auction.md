# Online Auction / Bidding System — Problem Breakdown

> 📐 **Revision note (calc):** ⭐⭐ **real math here, and it drives two decisions.** **Throughput: 10M concurrent auctions × ~100 bids each ÷ 7-day average auction = ~140M bids/day ÷ 100,000 s = ~1,400 bids/sec → ×10 for peak = ~15K bids/sec.** ▸ ⭐ **That 15K is what breaks a single Postgres instance and forces sharding by `auctionId`.** **Storage: 10M concurrent × 52 weeks = 520M auctions/year × (1kb auction + 100 × 0.5kb bids = 51kb) ≈ 25TB/year.** ▸ ⭐ **HI's verdict: _"a decent amount for sure, but nothing crazy"_ — modern SSDs do 100+TB, so storage is NOT the constraint; write throughput is.** ▹ **Other figures: Kafka adds 2–10ms · long-poll timeout 30–60s · 100M potential SSE connections.** ▹ ⭐ **Note HI rounds a day to 100,000 seconds** (really 86,400) — **the `01i` shortcut.**

>  ·** ⭐⭐ **TWO Pattern callouts: `Dealing with Contention` → `03b` and `Real-time Updates` → `03a`.** ▹ **HI follows the `Ch-1` framework explicitly.** Cross-refs: ⭐⭐ **OCC, row locking, compare-and-set → `03b`** · ⭐⭐ **polling / long-polling / SSE / WebSocket → `03a`** · ⭐ **Redis Lua CAS → `02a`, and `05h §5.1` for the identical mechanism** · **Kafka partitioning + ordering → `02c`** · **Postgres → `02g`** · **sharding by entity ID → `01f`** · **normalization → `01c`** · **CAP → `01h`** · **blob storage for images → `01a`** · **API design → `01b`** · **API Gateway → `02d`** · **numbers → `01i`.** **Siblings: ⭐⭐ `05e` Ticketmaster (the contention twin) · `05h` Tinder (same Redis-Lua CAS, and the same "offer eventual consistency, then design for strong") · ⭐ `05p` Job Scheduler (HI's dynamic-end-time answer IS a delayed task scheduler) · ▹ FB Live Comments for Pub/Sub — HI names it, but it's not in your set yet.**
> 
> **Calibration:** ⭐⭐ **DD1 IS the question — HI says so: _"Bidding is the most interesting part of this problem, and where we will spend the most time."_** ▸ **DD1 is excellent, DD3 is solid, DD2 is thin ("add Kafka, here's why"), DD4 is a numbers walk.** ⭐ **So: ONE careful pass, but know DD1's ladder cold.** ⚠ **Not a mid-level question** — HI: _"I don't typically ask it in mid-level interviews."_ ▸ **Senior+.**
> 
> - ⭐⭐ **What actually scores:**
>     - **(a)** ⭐⭐ **Knowing that `SELECT … FOR UPDATE` does NOT block INSERTs** (§5.1 Bad). ▸ **The single best technical point in the file, and the reason the whole ladder exists.**
>     - **(b)** ⭐⭐ **Moving `maxBidPrice` onto the Auction row** ⇒ **lock ONE row, briefly** (§5.1 Great).
>     - **(c)** ⭐⭐ **OCC using the value itself as the version** — `WHERE max_bid = :original_max_bid`.
>     - **(d)** ⭐⭐ **"Avoid destroying historical data"** — ▸ **keep the bids table; don't just overwrite a max.** ⭐ **The audit argument is the one to say out loud.**
>     - **(e)** ⭐⭐ **SSE over WebSockets, with the reason: the channel is unidirectional.**
>     - **(f)** ⭐⭐ **Pub/Sub for cross-server SSE fan-out** — ▸ **Server A has a bid, the viewer is on Server B.**
>     - **(g)** ⭐ **Kafka partitioned by `auctionId` for durability AND ordering** — ⭐ **ordering matters for fairness on equal bids.**
> - ⭐ **Transferable primitives:**
>     - ⭐⭐ **Row locks protect rows that exist. They do not stop new rows appearing.** ▸ **If the thing you're guarding is an aggregate over a set, lock the PARENT row, not the set.** ⭐ **This is the lesson of the whole dive.**
>     - ⭐⭐ **Keep the contended value on a single row you can lock or version.** ▸ **Denormalising `max_bid` onto Auction is a correctness move, not a performance one.**
>     - ⭐⭐ **OCC works when conflicts are RARE** — **read a version, write conditionally, retry on failure.** ⭐ **No locks at all, at the cost of occasional retries.**
>     - ⭐⭐ **Never overwrite history to store a derived value.** ▸ **Store the events, derive the aggregate, cache the aggregate.** ⭐ **You will be asked to prove a bid existed.**
>     - ⭐ **Get the write into a durable queue before you reason about it.** ▸ **Accept first, validate later.**
>     - ⭐ **Fan-out across a server fleet needs a bus, not a broadcast.** ▸ **Pub/Sub so any server can reach any connection.**
> - ⭐ **Re-run (cross-ref, NOT re-explained):** **Redis Lua compare-and-set (`05h §5.1`, `02a`)** · **Kafka partitioning by key (`02c`, `05p §5.1` for why a log suits ordering)** · **sharding by entity ID (`01f`)** · **polling vs push (`03a`, `05i §5.2`, `05k §5.3`)** · **images to blob storage (`01a`, `05b`)** · **offering eventual consistency then designing for strong (`05h §5.1`)**. **Genuinely new:** ⭐⭐ **`FOR UPDATE` doesn't block inserts** · ⭐⭐ **OCC with the value as the version** · ⭐⭐ **the don't-destroy-history argument** · ⭐⭐ **long-polling mechanics + thundering herd** · ⭐⭐ **SSE vs WebSocket and the server-side connection map** · ⭐⭐ **Pub/Sub for cross-server push** · ⭐ **the three cache↔DB consistency options and why none is clean** · ⭐ **dynamic auction end times.**

---

## 0 · Understanding the problem

🛍️ **What is an online auction?**

Users **list items for sale** while others **compete by placing bids that top the current high bid** until the auction ends. **Highest bidder wins.**

---

## 1 · Requirements

### 1.1 Functional (what it does)

1. ⭐ **Post an item for auction** with a **starting price and end date.**
2. ⭐⭐ **Bid on an item — accepted only if higher than the current highest bid.**
3. ⭐ **View an auction, including the current highest bid.**

⚠ **Below the line:** search · filter by category · sort by price · view an item's auction history.

### 1.2 Non-functional (how it behaves)

1. ⭐⭐ **Strong consistency for bids** — **all users see the same highest bid** (`01h`).
2. ⭐⭐ **Fault tolerant and durable — _"We can't drop any bids."_**
3. ⭐⭐ **Display the current highest bid in real-time.**
4. ⭐ **Scale to 10M concurrent auctions.**

⚠ **Below the line:** observability/monitoring · security & user data · CI/CD.

- ⭐ **HI's prompt, same as `05p`:** **ask the interviewer for the expected scale before writing the NFRs** — ▸ **it informs everything downstream.**

### 1.3 ⭐⭐ The design driver — the contended value is a MAXIMUM, and it's also the hottest read

▸ ⭐⭐ **Every NFR lands on one field: `maxBidPrice`.**

||Why that one field is hard|
|---|---|
|⭐⭐ **NFR 1 — consistency**|**Every bid is a read-compare-write against a MOVING target.** ▸ **Not "is this taken?" (a boolean) but "is mine bigger?" (ordered)** — ⭐ **which is what makes this harder than `05e` Ticketmaster.**|
|⭐⭐ **NFR 3 — real-time**|**The same field every writer contends on is the field every viewer wants pushed to them.** ▸ **The serialization point and the hottest read are the same value.**|
|⭐ **NFR 2 — durability**|**A dropped bid is unprovable and unrecoverable** ⇒ **get it into a durable log before validating it.**|
|⭐ **NFR 4 — scale**|**15K bids/sec at peak** ⇒ **shard, and the shard key is forced: `auctionId`, because that's the contention scope.**|

- ⭐⭐ **So both Pattern callouts converge on `maxBidPrice`:** **`03b` guards writing it, `03a` pushes reading it.**
- ⭐ **And the shard key falls out for free:** **all reads and writes for one auction live on one shard** ⇒ ⭐ **no scatter-gather.**

### 1.4 Planning the approach

▹ ⚠ **HI gives no explicit planning section here** — it states it follows the **`Ch-1` Hello Interview framework** and goes straight to entities. ▸ **Entities → API → HLD per FR → deep dives driven by the NFRs.**

---

## 2 · Core Entities

- **Auction** — starting price, end date, the item being auctioned.
- **Item** — name, description, image.
- **Bid** — amount, the user placing it, the auction.
- **User** — starts auctions or bids on them.

> ⭐ **Why Item is separate from Auction — HI's three reasons, and it's a normalization answer** (`01c`)**:**
> 
> - **Items can be REUSED across auctions** (relisting an unsold item).
> - **Item details update independently of auction details.**
> - **Easier to add item-specific features later** — categories, search.
> - ▹ ⭐ **HI: _"I'm fine with either option - the key is to explain your reasoning."_**
> 
> ■ **— end of insert · HI write-up resumes below —**

---

## 3 · API

```
POST /auctions -> Auction & Item
{ item: Item, startDate: Date, endDate: Date, startingPrice: number }

POST /auctions/:auctionId/bids -> Bid
{ Bid }

GET  /auctions/:auctionId -> Auction & Item
```

> ⊕ ⚠⚠ **(mine, not HI) — fix the bid body. This is the fourth appearance of the same security point and HI misses it here.**
> 
> - ⚠ **HI's body is `{ Bid }`, and a Bid entity carries `userId`.** ⭐⭐ **Never take the bidder's identity from the request body — the client forges it and bids as someone else.**
> - ⭐ **Make it `{ amount: number }`**, with **`userId` from the session/JWT** and **`createdAt` generated server-side.**
> - ▹ **Flagged in `05c §3.3`, `05h §3.3`, `05i §3.3` — ⭐ treat it as a scored item, and raise it unprompted here since HI doesn't.**
> 
> ■ **— end of insert · HI write-up resumes below —**

---

## 4 · High-Level Design

### 4.1) Post an item for auction

```
Client ──► API Gateway ──► Auction Service ──► Database
            routing          validates            Auction: id · itemId · startTime
            · auth           + stores                      endTime · creatorId
                                                           startingPrice
                                                   Item:   id · name · description
                                                           imageLinks
```

- ▸ **Basic CRUD. The Auction Service is _"just a thin wrapper around the database"_ at this point**, and it also **handles reading/viewing auctions.**

**The flow — ⭐ walk it explicitly even though it's CRUD:**

1. **Client sends `POST /auctions` with the auction details.**
2. **API Gateway routes the request to the Auction Service.**
3. **Auction Service validates the request and stores the auction and item data in the database.**
4. **Database stores the auction and item data in tables.**

- ▹ ⭐ **HI deliberately skips images, and you should too:** **they'd go in blob storage, referenced by URL in the items table** (`01a`). ⭐ **Say that and move on — _"align on this not being the focus."_**

### 4.2) ⭐⭐ Bid on an item

▸ **HI: this is where the interview lives.**

**⭐ A separate Bid Service, with four jobs:** **validate incoming bids (is the amount higher than the current max?)** · **update the auction with the new highest bid** · **store bid history** · **notify relevant parties.**

**⭐⭐ Why split it from the Auction Service — three reasons, and all three hold:**

|Reason|The specific|
|---|---|
|⭐⭐ **Independent scaling**|**~100× more bids than auctions** ⇒ scale the bidding infrastructure separately|
|⭐ **Isolation of concerns**|**bidding owns the complex logic** — validation, race conditions, real-time updates|
|⭐ **Performance optimization**|**Bid Service tuned for high-throughput WRITES; Auction Service for read-heavy**|

▹ ⭐⭐ **Compare the series rule from `05h §4.3`: split when the write pattern, the data volume AND the ideal engine all differ.** ▸ **Here the first two clearly differ. The engine stays Postgres for both — so this is a 2-of-3 split, justified by the 100× asymmetry.**

**The simple flow:**

1. `POST /auctions/:auctionId/bids`.
2. Gateway → Bid Service.
3. ⭐ **Bid Service queries the DB for the current highest bid, then stores the bid as `accepted` or `rejected`, and returns the status.**
4. **Stored in a `bids` table linked by `auctionId`.**

> ⭐⭐ **The data-integrity principle — HI's strongest argument in the HLD, and it's a line to say out loud.**
> 
> - ⚠ **Many candidates propose storing only a `maxBidPrice` on the auction and skipping the bids table.** ⭐⭐ **That _"violates a core principle of data integrity: avoid destroying historical data."_**
> - ⭐⭐ **Overwriting the max each time permanently loses information** ⇒ **you cannot audit the bidding process, investigate disputes, or analyse behaviour.**
> - ⭐⭐ **The concrete argument that wins it:** _"Inevitably, a user is going to complain that their bid was not recorded and that they should have won the auction. **Without a complete audit trail, you have no way to prove them wrong.**"_
> - ▹ ⚠ **Note: §5.1 DOES add `maxBidPrice` to Auction — but as a cached aggregate ALONGSIDE the bids table, never instead of it.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 4.3) View an auction

⭐ **Two reasons to view, with different requirements — separate them:**

|Why|What it needs|
|---|---|
|**Learn about the item**|▸ **read-only**|
|⭐⭐ **Decide what to bid**|⭐⭐ **real-time consistency**|

- ▸ `GET /auctions/:auctionId` returns the auction and item details for the page.
- ⚠⚠ **The problem if the max never refreshes:** **the user bids against a stale amount and is _"confused (and frustrated)"_ when told it wasn't accepted** — ⭐ **worst on a busy auction.**
- ⭐ **The HLD answer: poll for the latest max bid every few seconds.** ▹ **_"While imperfect"_, it gives some consistency** — ▸ **and §5.3 replaces it.**

---

## 5 · Deep Dives

### 1) ⭐⭐ How do we ensure strong consistency for bids?

**⭐⭐ Lead with the failure, concretely — HI's own worked example:**

```
Current max = $10.   A bids $100.   B bids $20 shortly after.

1. A reads max          → $10
2. A writes $100        → accepted ($100 > $10)  ✓
3. B reads max          → ⚠ STILL $10 (stale read / propagation delay)
4. B writes $20         → accepted ($20 > $10)   ✗ WRONG
```

- ⭐⭐ **Both bids accepted, and two users think they're winning.** ▸ **B's $20 should have been compared against $100 and rejected.**

> ⭐ **Pattern: Dealing with Contention** (`03b`) — **callout #1 of 2.** ▹ **Multiple users bidding on the same auction simultaneously ⇒ race conditions ⇒ only one bid may win. ⭐ The toolkit: optimistic concurrency control, row locking, caching strategies.**
> 
> ■ **— end of insert · HI write-up resumes below —**

> ⚠ **Confusion resolved — a staff-level argument that strong consistency isn't needed. Offer it, expect to be steered back.**
> 
> - ⭐ **The argument:** **accept both bids, then rectify client-side** — later tell B that a higher bid came in and they're no longer winning. ▸ ⭐ **Whether A's or B's landed first doesn't matter (unless the amounts are equal); A wins either way.**
> - ⚠ **What it costs:** **careful client-side rendering, and a process that waits for eventual consistency to settle before telling anyone the outcome.**
> - ⚠⚠ **HI's verdict: valid, but it _"largely dodges the complexity of the problem, so most interviewers will still ask that you solve for strong consistency."_**
> - ⭐⭐ **How to play it: one sentence, then design for consistency.** ▹ **Identical move to `05h §5.1`'s reconciliation alternative — second time in the series.**
> 
> ■ **— end of insert · HI write-up resumes below (the ladder) —**

⚠ **Rung labels below are mine — see the handover note.**

#### ⚠⚠ Bad — row-level locking on the bids table

- **Approach:** **lock all existing bid rows for the auction while you check the max and insert:** **`BEGIN` → `SELECT … FOR UPDATE` on all the auction's bids → read `MAX(amount)` → compare → insert → `COMMIT`.**

```sql
BEGIN;
-- Lock all existing bid rows for this auction
SELECT id, amount FROM bids WHERE auction_id = :auction_id FOR UPDATE;
-- Get current max (from the locked rows)
SELECT MAX(amount) AS max_bid FROM bids WHERE auction_id = :auction_id;
-- Insert if the new bid beats the current max
INSERT INTO bids (auction_id, user_id, amount, bid_time)
VALUES (:auction_id, :user_id, :amount, NOW())
WHERE :amount > COALESCE(:max_bid, 0);
COMMIT;
```

- ⚠ **Challenges — and HI's first one is the key insight of the entire dive:**
    - ⭐⭐⭐ **It doesn't actually prevent concurrent inserts.** ▸ **`SELECT … FOR UPDATE` locks rows that EXIST; it does not block another transaction INSERTING a new row for the same auction.** ⭐⭐ **Two transactions can both read the same max, both pass the check, and both insert — exactly the race you're fixing.** ▹ **You'd need an advisory lock or a separate row to lock in order to serialize.**
    - ⚠ **Performance and scalability:** **locking all bid rows serializes most bid processing, and you lock MORE rows as the auction grows** ⇒ **a bottleneck with rising latency.**
    - ⚠ **Poor UX:** **lock contention ⇒ slow responses or timeouts** — **unacceptable in competitive bidding.**
- ⭐⭐ **HI's general rule, worth memorising:** **use row locking sparingly — (a) lock as FEW rows as possible and (b) for as SHORT a duration as possible.** ⚠ **This approach respects neither.**

> ⊕ ⚠⚠ **(mine, not HI) — HI's SQL is not valid SQL.**
> 
> - ⚠⚠ **`INSERT … VALUES … WHERE` does not exist.** ▸ **A `WHERE` clause cannot be attached to a `VALUES` insert.** ⭐ **The valid form is `INSERT … SELECT … WHERE`:**
> 
> ```sql
> INSERT INTO bids (auction_id, user_id, amount, bid_time)
> SELECT :auction_id, :user_id, :amount, NOW()
> WHERE :amount > COALESCE(:max_bid, 0);
> ```
> 
> - ⭐ **The CONCEPT is fine; the snippet isn't.** ▹ ⚠ **Same class as `05h §5.1`'s invalid `BEGIN BATCH … SELECT` CQL — ⭐ HI's code blocks are worth reading sceptically.**
> - ⊕ ▹ **And name the real database term for HI's first challenge: this is a PHANTOM.** ▸ **Preventing it needs `SERIALIZABLE` isolation or a lock on a row that already exists — which is exactly where the ladder ends up.**
> 
> ■ **— end of insert · HI write-up resumes below —**

**Why climb:** you're holding many locks for a long time, and it still doesn't work.

#### Good — cache the max bid in Redis

- **Approach:** ⭐ **keep the max bid per auction in Redis.** **Flow: read the max from Redis → if the new bid is higher, update it → write the bid to the DB as accepted or rejected.**
- ⚠ **Challenges — HI's framing: _"We solved one problem, but created another."_** ▸ **A consistency problem WITHIN the database became a consistency problem BETWEEN the database and the cache.** **Two things must hold:**

**⭐⭐ (i) The cache read and write must be atomic.** ✅ **Redis is single-threaded and supports atomic operations — use a Lua script for the read-modify-write.** ⚠ **`MULTI`/`EXEC` alone will NOT work: it can't read a value and conditionally write based on it in the same transaction.**

```lua
local current_max_bid = tonumber(redis.call('GET', auction_key) or '0')
local proposed_bid_amount = tonumber(proposed_bid)
if proposed_bid_amount > current_max_bid then
    redis.call('SET', auction_key, proposed_bid_amount)
    return true
else
    return false
end
```

▹ ⭐ **Identical mechanism to `05h §5.1`'s swipe script — Lua makes compare-and-set one indivisible unit** (`02a`).

**⚠⚠ (ii) The cache must be strongly consistent with the DB** — **otherwise the cache says the max is X but that bid isn't in the database.** **HI's three options:**

|Option|What it trades|
|---|---|
|**Redis as source of truth during the auction, DB written asynchronously**|⚠ **trades consistency for performance** — ▹ HI: _"pragmatic"_|
|**OCC with retries: update cache atomically, then write the DB; roll back the cache if the write fails**|⚠⚠ **see the ⊕ note below — the rollback isn't safe**|
|**DB first, then the cache; invalidate the cache entry if the cache update fails**|⚠ **a window where the cache is stale or empty**|

- ⚠⚠ **HI's honest conclusion, and it's the quotable one:** _"there's **no clean way** to make Redis and a relational database transactionally consistent. Redis doesn't support distributed transaction protocols like two-phase commit."_ ⭐⭐ **And the advice that generalises: _"If you find yourself in an interview needing cross-system atomicity, consider whether you can restructure to keep everything in one system."_** ▸ **That sentence is the bridge to the Great solution.**

> ⊕ ⚠⚠ **(mine, not HI) — option 2's cache rollback loses a valid bid, which breaks NFR #2.**
> 
> - ⚠ **Walk it: A bids $100 → cache set to $100 → the DB write fails → roll the cache back to $10.** ▸ **But in between, B bid $50, read $100, and was REJECTED.**
> - ⚠⚠ **After the rollback the max is $10, and B's $50 — which should now win — is already recorded as rejected.** ⭐ **A valid bid is lost, and NFR #2 says _"we can't drop any bids."_**
> - ⭐ **The general point: you cannot undo a value other transactions have already read and acted on.** ▸ **It's why the Great solution puts the compare and the insert in ONE system, in ONE transaction.**
> 
> ■ **— end of insert · HI write-up resumes below —**

**Why climb:** two systems can't be made transactional. Put the contended value in the system that already has transactions.

#### ⭐⭐ Great — store the max bid in the database, on the Auction row

- ⭐⭐ **The move: add `maxBidPrice` to the Auction table — _"effectively using the Auction table as our cache."_** ▸ **Both earlier problems vanish: one row to lock, and nothing to keep consistent across systems.**

**The pessimistic version — five steps:**

1. ⭐⭐ **Lock the auction row — just ONE row.**
2. **Read the max bid from the Auction table.**
3. **Write the bid as accepted or rejected.**
4. **Update `maxBidPrice` if the new bid is higher.**
5. **Commit.**

- ⭐⭐ **Now you lock one row, briefly — satisfying both of HI's locking rules.**

**⭐⭐ The optimistic version (OCC) — and this is the better answer:**

- ⭐ **Why OCC fits:** **bid conflicts are RARE — most bids don't land simultaneously on the same auction.**

```sql
-- 1. read the auction row, get current max_bid  ← this value IS the "version"
-- 2. validate the new bid is higher
-- 3. update only if the max hasn't changed since you read it:
UPDATE auctions
SET max_bid = :new_bid
WHERE id = :auction_id AND max_bid = :original_max_bid
-- 4. succeeded → write the bid record.  Failed → retry from step 1.
```

- ⭐⭐ **It avoids locks entirely while staying consistent, _"at the cost of occasional retries when conflicts do occur."_**

> ⊕ ⭐ **(mine) — why using `max_bid` as the version column is safe here, and when it wouldn't be.**
> 
> - ⭐⭐ **It works because `max_bid` is MONOTONICALLY INCREASING** — it never returns to a previous value, so `max_bid = :original_max_bid` reliably means "nothing changed."
> - ⚠ **A field that can return to an old value would need a real version counter instead** — ▸ **otherwise you get the ABA problem: it changed twice and came back, your check passes, and you overwrite someone's work.**
> - ⭐ **Worth one sentence if asked why there's no `version` column.** ▸ **It shows you know you're relying on a property of the data, not on luck.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 2) How do we make the system fault tolerant and durable?

⚠ **HI's framing: _"Dropping a bid is a non-starter… that would be catastrophic for trust in the platform."_**

**⭐⭐ The answer: a durable message queue, and get bids into it as soon as possible.** ▸ ⭐ **Accept first, validate later.**

**⭐ Three benefits, each with HI's specific reason:**

|Benefit|The specific|
|---|---|
|⭐⭐ **Durable storage**|**write the bid to the queue immediately** ⇒ **even if the whole Bid Service crashes, the bid survives.** ▹ **HI's analogy: _"writing your name on a waiting list at a restaurant — even if the host takes a break, your place in line is secured."_**|
|⭐⭐ **Buffering load spikes**|**a popular auction's final minutes = thousands of bids/sec.** ⚠ **Without a queue you must drop bids (unacceptable), crash (unacceptable), or massively over-provision (expensive).**|
|⭐⭐ **Ordering within an auction**|**Kafka guarantees order within a partition** ⇒ ⭐ **partition by `auctionId` so one auction's bids process in arrival order.** ⭐⭐ **Why it matters: FAIRNESS — if two users bid the same amount, the first should win.**|

**⭐ Why Kafka specifically** (`02c`) — _RabbitMQ or SQS would work too_: **high throughput (millions msg/sec)** · **durability (persists to disk, configurable replication)** · **partitioning by `auctionId` for in-order processing per auction with parallelism across auctions.**

**The flow:**

1. **User submits a bid.**
2. **Gateway routes to a producer, which immediately writes to Kafka.**
3. ⭐ **Kafka acks the write, and you tell the user the bid was RECEIVED.**
4. **Bid Service consumes at its own pace.**
5. **Valid ⇒ written to the DB.**
6. ⭐ **Bid Service fails ⇒ the bid stays in Kafka and is retried.**

- ⭐ **The latency cost, named:** **queues add ~2–10ms under normal conditions** — **worth it for durability.**
- ⚠⚠ **And the gap HI opens here and closes in §5.3:** **"received" ≠ "accepted".** ▸ **The user doesn't yet know if they're winning.** ⭐ **HI defers it — _"I will discuss bid broadcasting later on… which solves the asynchronous notification problem"_** — ▸ ⭐⭐ **so the SSE channel from §5.3 IS the answer. Say that link; it's the architectural payoff.**

> ⊕ ⚠⚠ **(mine, not HI) — DD2's Kafka partly subsumes DD1's concurrency control, and HI never reconciles them.**
> 
> - ▸ **Partitioning by `auctionId` means all of one auction's bids sit in ONE partition, consumed by ONE consumer, SEQUENTIALLY.** ⭐⭐ **That alone serializes bids per auction — so the race DD1 spent a whole ladder on largely cannot occur.**
> - ⚠ **HI builds both and never says one covers the other.** ⭐ **Don't drop OCC, though — keep it, and say WHY it's still needed:**
>     - ⚠ **Consumer-group REBALANCING** can briefly have two consumers touch one partition.
>     - ⚠ **At-least-once delivery** means a message can be reprocessed after a crash.
>     - ⭐ **OCC + the monotonic `max_bid` check makes reprocessing harmless** — ▸ **a replayed bid simply fails its conditional update.**
> - ⭐⭐ **Say it as defence in depth, not redundancy:** _"the partition gives me ordering and near-serialization; OCC covers rebalances and redelivery."_ ▸ **Spotting that a later dive overlaps an earlier one scored in `05h` and `05k` too.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 3) ⭐⭐ How do we display the current highest bid in real-time?

⚠ **Two problems with §4.3's polling:**

- ⚠ **Too slow** — **every few seconds isn't fast enough for a hot auction.**
- ⚠ **Inefficient** — **every client hits the database every time, and _"in the overwhelming majority of cases, the max bid hasn't changed."_**

> ⭐ **Pattern: Real-time Updates** (`03a`) — **callout #2 of 2.** ▹ **Keeping clients current on the highest bid is the textbook application.** ⭐ **Read `03a`'s protocol flow chart — it generalises this whole dive.**
> 
> ■ **— end of insert · HI write-up resumes below —**

⚠ **Rung labels below are mine.**

#### Good — long polling

- **Approach:** ⭐ **hold the connection OPEN until either the max bid changes or a timeout (typically 30–60s).** ▸ **On a new accepted bid the server responds to all waiting requests; clients immediately re-open** ⇒ **a near-continuous connection.**
- ⭐ **Server-side: maintain a map of pending requests per auction.**

```js
async function pollMaxBid(auctionId) {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), 30000);
  try {
    const response = await fetch(`/api/auctions/${auctionId}/max-bid`, { signal: controller.signal });
    clearTimeout(timeoutId);
    if (response.ok) { const { maxBid } = await response.json(); updateUI(maxBid); }
  } catch (error) { /* timeout or network error */ }
  pollMaxBid(auctionId);          // immediately start the next long poll
}
```

- ⚠ **Challenges:**
    - ⚠ **The server holds open connections for every client watching an auction** ⇒ **significant resource use on popular auctions.**
    - ⭐⭐ **THUNDERING HERD** — **all clients watching one auction reconnect simultaneously after an update.**
    - ⚠ **The timeout adds a delay:** **a bid landing just after a client's poll times out isn't seen until the next request completes.** ⭐ **A real trade: shorter timeouts = more requests, longer timeouts = delayed updates.**
    - ⚠⚠ **Scaling:** **each server keeps its own connections**, so **horizontal scaling needs extra infrastructure (Redis or a queue) to coordinate updates across servers.** ▸ **→ §5.4.**

**Why climb:** you're simulating push with repeated requests. Use a protocol built for push.

#### ⭐⭐ Great — Server-Sent Events (SSE)

- ⭐ **Approach:** **a unidirectional server→client channel.** **One SSE connection per viewer; the server pushes each new max bid as it changes.** ▸ **True real-time, more efficient than either polling form.**

```js
const eventSource = new EventSource(`/api/auctions/${auctionId}/bid-stream`);
eventSource.onmessage = (event) => {
  const { maxBid } = JSON.parse(event.data);
  updateUI(maxBid);
};
```

- ⭐ **Server-side: a set of active connections per auction, pushed to on every accepted bid.**

```ts
class AuctionEventManager {
  private connections: Map<string, Set<Response>> = new Map();
  addConnection(auctionId: string, connection: Response) {
    if (!this.connections.has(auctionId)) this.connections.set(auctionId, new Set());
    this.connections.get(auctionId).add(connection);
  }
  broadcastNewBid(auctionId: string, maxBid: number) {
    const connections = this.connections.get(auctionId);
    if (connections) {
      const event = `data: ${JSON.stringify({ maxBid })}\n\n`;
      connections.forEach(response => response.write(event));
    }
  }
}
```

- ⭐⭐ **SSE over WebSockets, and know the reason:** **the communication is UNIDIRECTIONAL, and SSE is _"typically lighter weight and easier to implement."_** ▸ ⭐ **WebSockets would work; SSE is the better fit.** ▹ ⭐⭐ **Third file running where a lighter protocol beats WebSockets** (`05i`, `05k`) — **but note this is the first time the answer is a PUSH protocol rather than polling, because here the NFR actually says real-time.**
- ⚠⚠ **Challenge — the one that drives §5.4: cross-server coordination.** ▸ **User 1 on Server A and User 2 on Server B both watch Auction X. A bid arrives at Server A ⇒ only User 1 gets it, because Server A only knows its OWN connections.**

### 4) ⭐ How do we scale to 10M concurrent auctions?

> ⭐⭐ **HI's method, same as `05p`:** **work left to right, and for each component ask — what are the peak resource requirements (storage, compute, bandwidth)? does the current design meet them? if not, how do we scale it?**

**📐 The throughput chain:**

```
10M concurrent auctions × ~100 bids each ÷ 7-day auctions
  = ~140M bids/day
  ÷ 100,000 s/day        ⭐ HI rounds; a day is really 86,400s
  = ~1,400 bids/sec
  × 10 for peak          ⭐ popular auctions ending, evening surges
  = ~15K bids/sec at peak
```

|Component|Verdict at peak|
|---|---|
|**Kafka**|✅ ⭐ **a modest partition count handles 15K/sec comfortably**, and **partitioning by `auctionId` gives natural parallelism** — different consumers handle different auctions|
|**Bid + Auction Services**|✅ **stateless ⇒ horizontal scaling + auto-scaling on memory or CPU**|
|**Database — storage**|✅ 📐 **10M × 52 = 520M auctions/yr × (1kb + 100 × 0.5kb) = 25TB/yr.** ⭐ **_"nothing crazy"_ — modern SSDs do 100+TB** ⇒ **storage is NOT the constraint**|
|⚠⚠ **Database — writes**|⚠⚠ **15K writes/sec _"pushing past what a single well-provisioned Postgres instance can handle"_** ⇒ ⭐⭐ **shard by `auctionId`.** ✅ ⭐ **And no scatter-gather worries, because all reads/writes for one auction land on one shard**|
|⚠⚠ **SSE connections**|⚠⚠ **10M auctions, 100M users ⇒ potentially 100M connections, which won't fit on one server** ⇒ ⭐⭐ **Pub/Sub**|

**⭐⭐ The Pub/Sub fix for SSE fan-out:**

- ▸ **Server A receives a bid ⇒ publishes it to the Pub/Sub system.** ⭐ **Every Bid Service instance subscribes to the same channel.** ▸ **On receipt, each checks whether any of ITS connections are watching that auction and pushes if so.**
- ⭐ **Redis Pub/Sub, Kafka, or a custom solution all work.**
- ▹ **HI points to the FB Live Comments breakdown for depth** — ⚠ **not in your set yet.**

> ⊕ ⭐ **(mine) — Pub/Sub fixes ROUTING, not fleet size. Two things to add.**
> 
> - ⚠ **100M connections still need somewhere to live.** ▸ **At ~50k connections per server that's ~2,000 servers purely for SSE.** ⭐ **HI never costs this.**
> - ⭐⭐ **But 100M users ≠ 100M concurrent connections** — **only people with an auction page OPEN need one.** ▸ ⭐ **Say that: _"I'd scope connections to active viewers, which is a small fraction of registered users, and hold them on a dedicated connection tier separate from the Bid Service so I can scale the two independently."_**
> - ▹ **Separating the connection tier also stops a bid-processing deploy from dropping every open stream.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### ▹ Additional dives HI flags

|Topic|HI's answer|
|---|---|
|⭐⭐ **Dynamic end times** (end an hour after the last bid)|**Simple and probably good enough: update `endTime` on every new bid, and a cron finds ended auctions.** ⭐ **If they want precision: a DELAYED TASK SCHEDULER** — **on each bid, schedule a task for an hour later (a DB-backed job queue, a Redis sorted set of timestamps, or AWS Step Functions with a Wait state); when it fires, check the bid is still the latest.** ▹ ⭐⭐ **That's `05p` Job Scheduler, and the "still the latest?" check is its idempotency lesson**|
|**Purchasing**|**email the winner to pay; no payment within N ⇒ go to the next highest bidder**|
|**Bid history in real-time**|▹ **the same problem as real-time max-bid updates — reuse §5.3**|

---

## 6 · Final Design

⚠ **Layout and arrows are mine; components, labels and field lists are HI's** — see the handover note.

```
Client  ⭐ holds one SSE connection per auction being viewed
  │
  │  POST /auctions                      {item, startDate, endDate, startingPrice}
  │  POST /auctions/:auctionId/bids      ⊕ {amount} only — userId from the JWT
  │  GET  /auctions/:auctionId
  │  ◄── SSE stream: max bid updates
  ▼
API Gateway  — routing · auth · rate limiting                          02d
  │
  ├──► Auction Service ──┐    createAuction() · getAuction()
  │                      │    ⭐ read-optimised
  │                      │
  └──► producer ──► Message Queue (Kafka)                              02c
                      │   ⭐⭐ partition by auctionId
                      │   ⭐ ordering per auction ⇒ FAIRNESS on equal bids
                      │   ⭐ durability: bid survives a Bid Service crash
                      │   ⭐ buffers final-minute surges
                      │   ▹ adds 2–10ms
                      ▼
                 Bid Service   createBid()  ⭐ write-optimised, stateless,
                      │                        auto-scaled
                      │        ⭐⭐ OCC: UPDATE auctions SET max_bid = :new
                      │              WHERE id = :id AND max_bid = :original
                      │              → succeed ⇒ insert the bid; fail ⇒ retry
                      │        ⊕ still needed despite partition ordering —
                      │          covers rebalances + redelivery
                      │
                      ├──► Database (Postgres)                   02g · 01f
                      │      ⭐⭐ shard by auctionId  (15K writes/s peak;
                      │         one auction = one shard ⇒ no scatter-gather)
                      │      📐 ~25TB/yr — storage is NOT the constraint
                      │
                      │      Auction: id · itemId · startTime · endTime
                      │               creatorId · startingPrice
                      │               ⭐⭐ maxBidPrice   ← the contended field
                      │      Item:    id · name · description · imageLinks
                      │               (▹ images in blob storage)        01a
                      │      Bid:     id · auctionId · price · userId
                      │               createdAt · status: accepted|rejected
                      │               ⭐⭐ NEVER replaced by maxBidPrice —
                      │                  the audit trail is the point
                      │
                      └──► Pub/Sub  ⭐⭐ so ANY server can reach ANY connection
                             │        (Redis Pub/Sub · Kafka · custom)
                             ▼
                      every Bid Service instance subscribes, checks its own
                      connections for that auctionId, and pushes via SSE
                      ⊕ scope connections to ACTIVE VIEWERS, and consider a
                        dedicated connection tier scaled separately
```

---

## 7 · Expected at Each Level

|Level|The bar for Online Auction|
|---|---|
|**Mid**|⚠ ⭐ **HI doesn't normally ask this at mid-level — _"a more challenging question."_** If asked: **produce an HLD, then respond reasonably on consistency, scaling and the other NFRs.** ▹ **The interviewer drives; what's assessed is problem-solving and thinking on your feet.** ▸ **It's fine to propose the caching solution without seeing the distributed-transaction downsides.**|
|**Senior**|⭐⭐ **Recognise that consistency AND real-time broadcasting are foundational, and LEAD toward a solution.** ⭐ **Must arrive at the consistency answer and explain how bids stay current on the client.** ▹ **May not reach scale in depth — but should recognise the problems their own design introduced.**|
|**Staff**|**Mastery of consistency and real-time, PLUS proactively surfacing adjacent complexity.** ⭐⭐ **HI's named example: unprompted, discuss how ENDING auctions is its own distributed-systems problem** — **dynamic endings need clock-drift handling, concurrent termination attempts and delayed valid bids** — ⭐ **proposing a dedicated scheduling service (Airflow or a queue-based solution).** ▸ ⭐⭐ **_"the most important thing is that they lead the conversation, go deep, and show technical accuracy and expertise."_**|

---

## Quick Recall (pass 3+)

|Use / Question|Online Auction answer|
|---|---|
|Calibration|⭐ Evan King · Feb 2026 · **"medium"** · ⚠ **"Asked at" is truncated to `A` +1 in the source — 2 companies, one unnamed; don't guess** · ⭐⭐ **TWO patterns: `Dealing with Contention` (`03b`) + `Real-time Updates` (`03a`).** ⭐⭐ **DD1 IS the question** — HI: _"bidding is the most interesting part… where we will spend the most time."_ ▸ **DD1 excellent · DD3 solid · DD2 thin · DD4 a numbers walk.** ⭐ **ONE careful pass, know DD1's ladder cold.** ⚠ **Senior+ — HI doesn't ask it at mid-level**|
|⭐⭐ Design driver|⭐⭐ **The contended value is a MAXIMUM, and it's also the hottest read.** **Every bid is a read-compare-write against a MOVING target — not "is this taken?" (boolean, `05e`) but "is mine bigger?" (ordered).** ⭐⭐ **Both patterns converge on ONE field, `maxBidPrice`: `03b` guards writing it, `03a` pushes reading it.** ⭐ **And the shard key falls out free — `auctionId` is the contention scope, so one auction = one shard = no scatter-gather**|
|FRs / NFRs|**post an item (starting price + end date) · bid, accepted only if higher than current max · view auction incl. current max.** Below: search · filter · sort · auction history. **NFRs: ⭐⭐ strong consistency for bids · ⭐⭐ fault tolerant, _"can't drop any bids"_ · ⭐⭐ real-time max bid · 10M concurrent auctions.** Below: observability · security · CI/CD. ⭐ **Ask for scale BEFORE writing the NFRs**|
|📐 Numbers|**10M auctions × ~100 bids ÷ 7 days = ~140M bids/day ÷ 100,000s = ~1,400/s → ×10 peak = ⭐⭐ ~15K bids/sec.** ▸ **that 15K is what breaks one Postgres box.** **Storage: 10M × 52 = 520M auctions/yr × (1kb + 100×0.5kb = 51kb) ≈ 25TB/yr** — ⭐ _"nothing crazy"_, **SSDs do 100+TB ⇒ storage is NOT the constraint, write throughput is.** ▹ **Kafka +2–10ms · long poll 30–60s · up to 100M SSE connections.** ▹ ⭐ **HI rounds a day to 100,000s (really 86,400)**|
|Entities|**Auction · Item · Bid · User.** ⭐ **Why Item is separate** (`01c`): **items REUSED across auctions (relisting) · item details update independently · easier to add categories/search later.** ▹ ⭐ HI: _"I'm fine with either option - the key is to explain your reasoning"_|
|API|`POST /auctions {item, startDate, endDate, startingPrice}` · `POST /auctions/:auctionId/bids` · `GET /auctions/:auctionId`. ⊕ ⚠⚠ **HI's bid body is `{ Bid }`, which carries `userId` — the client would forge it and bid as someone else.** ⭐ **Make it `{ amount }`, userId from the JWT, `createdAt` server-side.** ▹ **4th appearance of this point (`05c`/`05h`/`05i`) and HI MISSES it here — raise it unprompted**|
|⭐⭐ Why split the Bid Service|**(1)** ⭐⭐ **~100× more bids than auctions ⇒ scale independently (2) bidding owns the hard logic — validation, races, real-time (3) tune Bid Service for WRITES, Auction Service for READS.** ▹ **vs `05h §4.3`'s rule (write pattern + volume + engine must ALL differ): this is 2-of-3 — the engine stays Postgres — justified by the 100× asymmetry**|
|⭐⭐ Don't destroy history|⚠ **candidates propose keeping only `maxBidPrice` and skipping the bids table** — ⭐⭐ **that _"violates a core principle of data integrity: avoid destroying historical data."_** **No audit, no dispute investigation, no behaviour analysis.** ⭐⭐ **The winning line: _"Inevitably, a user is going to complain that their bid was not recorded… without a complete audit trail, you have no way to prove them wrong."_** ▹ ⚠ **§5.1 DOES add `maxBidPrice` — as a cached aggregate ALONGSIDE the bids table, never instead**|
|View auction|⭐ **two reasons, different requirements: learn about the item (read-only) vs decide what to bid (⭐⭐ needs real-time consistency).** ⚠ **Stale max ⇒ the user bids low and is _"confused (and frustrated)"_ when rejected — worst on busy auctions.** **HLD answer: poll every few seconds, _"while imperfect"_ ⇒ replaced in §5.3**|
|⚠⚠ DD1 the race|**max $10 · A reads $10, writes $100 ✓ · B reads ⚠ STILL $10 (stale) · B writes $20 ✓ WRONG.** ⭐⭐ **Both accepted, two users think they're winning.** B's $20 should have been compared to $100|
|⭐⭐ DD1 the non-consistent option|**staff argument: accept both, rectify client-side later — tell B a higher bid came in.** ⭐ **Whether A or B landed first doesn't matter (unless amounts are equal); A wins either way.** ⚠ **Needs careful client rendering + a process that waits for eventual consistency before notifying.** ⚠⚠ **HI: valid but _"largely dodges the complexity… most interviewers will still ask that you solve for strong consistency."_** ⭐ **One sentence, then design for consistency.** ▹ **2nd time in the series (`05h §5.1`)**|
|⚠⚠⚠ DD1 Bad — row locking|**`BEGIN` → `SELECT … FOR UPDATE` all the auction's bids → `MAX(amount)` → compare → insert → `COMMIT`.** ⭐⭐⭐ **THE KEY INSIGHT: `FOR UPDATE` locks rows that EXIST — it does NOT block another transaction INSERTING a new row.** ▸ **Two transactions both read the same max, both pass, both insert — the exact race.** ▹ **needs an advisory lock or a separate row to lock.** ⚠ **Also: locking ALL bid rows serializes processing and gets worse as bids grow ⇒ latency ⇒ bad UX in competitive bidding.** ⭐⭐ **HI's rule: lock as FEW rows as possible, for as SHORT a time as possible — this respects neither**|
|⊕⚠⚠ DD1 Bad — invalid SQL|⚠⚠ **`INSERT … VALUES … WHERE` is not valid SQL** — a WHERE can't attach to a VALUES insert. ⭐ **Valid form: `INSERT … SELECT :a, :b, :c WHERE :amount > COALESCE(:max_bid, 0)`.** ▹ ⚠ **same class as `05h`'s invalid `BEGIN BATCH … SELECT` CQL — read HI's code blocks sceptically.** ⊕ **And the DB term for HI's first challenge: it's a PHANTOM — preventing it needs SERIALIZABLE or a lock on an existing row**|
|DD1 Good — Redis cache|**keep max bid per auction in Redis: read → update if higher → write bid to DB.** ⚠⚠ **_"We solved one problem, but created another"_ — consistency WITHIN the DB became consistency BETWEEN DB and cache.** **(i)** ⭐⭐ **cache read+write must be atomic ⇒ Lua script; ⚠ `MULTI`/`EXEC` alone can't read then conditionally write** (same as `05h §5.1`). **(ii)** ⚠ **three options, none clean: Redis as source of truth + async DB · OCC with cache rollback · DB-first then invalidate on failure.** ⭐⭐ **HI: _"no clean way to make Redis and a relational database transactionally consistent"_ — no 2PC.** ⭐⭐ **The generalising advice: _"if you need cross-system atomicity, consider whether you can restructure to keep everything in one system"_**|
|⊕⚠⚠ DD1 — the rollback option is broken|**A bids $100 → cache=$100 → DB write fails → roll back to $10.** ⚠⚠ **But B bid $50 in between, read $100, got REJECTED — and after the rollback B's $50 should win.** ⭐ **A valid bid is lost ⇒ breaks NFR #2.** ⭐⭐ **General point: you can't undo a value other transactions already read and acted on**|
|⭐⭐ DD1 Great — max bid in the DB|⭐⭐ **put `maxBidPrice` on the Auction row — _"effectively using the Auction table as our cache."_** **Both problems vanish: ONE row to lock, nothing cross-system.** **Pessimistic: lock the auction row → read max → write bid accepted/rejected → update max if higher → commit.** ⭐⭐ **Now you satisfy both locking rules.** **⭐⭐ OCC (better): read `max_bid` as the version → validate → `UPDATE auctions SET max_bid = :new WHERE id = :id AND max_bid = :original` → succeed ⇒ insert bid; fail ⇒ retry.** ⭐ **Fits because conflicts are RARE.** ⭐⭐ **Avoids locks entirely, costs occasional retries**|
|⊕⭐ Why `max_bid` works as a version|⭐⭐ **because it's MONOTONICALLY INCREASING — it never returns to an old value**, so `max_bid = :original` reliably means "unchanged." ⚠ **A field that CAN return to an old value needs a real version counter — else the ABA problem: changed twice, came back, your check passes, you overwrite someone's work.** ⭐ **One sentence if asked why there's no `version` column**|
|⭐⭐ DD2 — durable queue|⚠ **_"Dropping a bid is a non-starter… catastrophic for trust."_** ⭐⭐ **Get bids into a durable queue ASAP — accept first, validate later.** **3 benefits: (1)** ⭐⭐ **durability — survives a full Bid Service crash** (▹ HI: _"writing your name on a waiting list… your place in line is secured"_) **(2)** ⭐⭐ **buffers final-minute surges** — ⚠ **without it you drop bids, crash, or massively over-provision (3)** ⭐⭐ **ordering within an auction: Kafka orders per partition ⇒ partition by `auctionId` ⇒ FAIRNESS on equal bids, first wins**|
|⭐ DD2 — why Kafka + the flow|**high throughput (millions/s) · durability (disk + replication) · partitioning by `auctionId` for in-order per auction with cross-auction parallelism** (`02c`). ▹ **RabbitMQ or SQS would work.** **Flow: submit → producer writes to Kafka → ⭐ ack ⇒ tell the user the bid was RECEIVED → Bid Service consumes at its own pace → valid ⇒ DB → ⭐ failure ⇒ stays in Kafka, retried.** ▹ **+2–10ms.** ⚠⚠ **"received" ≠ "accepted" — ⭐⭐ the SSE channel from §5.3 IS the answer to that gap; say the link**|
|⊕⚠⚠ DD2 partly subsumes DD1|▸ **partitioning by `auctionId` puts one auction's bids in ONE partition, consumed SEQUENTIALLY by ONE consumer ⇒ ⭐⭐ the DD1 race largely can't occur, and HI never says so.** ⭐ **Don't drop OCC — say WHY it stays: ⚠ consumer-group REBALANCING can briefly double up on a partition · ⚠ at-least-once means redelivery after a crash · ⭐ OCC + monotonic `max_bid` makes a replayed bid simply fail its conditional update.** ⭐⭐ **Frame as DEFENCE IN DEPTH: _"the partition gives ordering and near-serialization; OCC covers rebalances and redelivery"_**|
|⚠ DD3 — why polling fails|⚠ **too slow for a hot auction** · ⚠ **inefficient — every client hits the DB and _"in the overwhelming majority of cases, the max bid hasn't changed"_**|
|DD3 Good — long polling|⭐ **hold the connection open until the max changes or a 30–60s timeout; on a new bid respond to ALL waiters; clients immediately re-open.** **Server keeps a map of pending requests per auction.** ⚠ **open connections per watcher ⇒ heavy on popular auctions · ⭐⭐ THUNDERING HERD on simultaneous reconnect · ⚠ a bid just after a timeout isn't seen until the next request (shorter timeout = more requests, longer = more delay) · ⚠⚠ each server holds its OWN connections ⇒ horizontal scaling needs Redis/a queue to coordinate**|
|⭐⭐ DD3 Great — SSE|⭐ **unidirectional server→client channel; one connection per viewer; push each new max.** **Client: `new EventSource(...)` + `onmessage`.** **Server: `Map<auctionId, Set<Response>>`, `broadcastNewBid` writes `data: {...}\n\n` to each.** ⭐⭐ **SSE over WebSockets BECAUSE the channel is unidirectional and SSE is _"lighter weight and easier to implement"_** — WebSockets would work. ▹ ⭐ **3rd file where a lighter protocol beats WebSockets (`05i`, `05k`) — but the FIRST where the answer is real PUSH, because here the NFR demands real-time.** ⚠⚠ **Challenge: User 1 on Server A, User 2 on Server B, bid arrives at A ⇒ only User 1 gets it ⇒ §5.4**|
|⭐ DD4 method + verdicts|⭐⭐ **left to right: peak requirements? does the design meet them? if not, how to scale?** **Kafka ✅ modest partitions handle 15K/s + natural parallelism · Services ✅ stateless, horizontal + auto-scale · Storage ✅ 25TB/yr is fine · ⚠⚠ Writes: 15K/s _"pushing past what a single well-provisioned Postgres instance can handle"_ ⇒ ⭐⭐ shard by `auctionId`, ✅ no scatter-gather since one auction = one shard · ⚠⚠ SSE: 10M auctions + 100M users ⇒ up to 100M connections, won't fit one server**|
|⭐⭐ DD4 — Pub/Sub for SSE fan-out|**Server A gets a bid ⇒ publishes to Pub/Sub ⇒ ALL Bid Service instances subscribe ⇒ each checks its own connections for that `auctionId` and pushes.** ⭐ **Redis Pub/Sub, Kafka, or custom.** ▹ **HI points to FB Live Comments — not in your set yet.** ⊕ ⚠ **Pub/Sub fixes ROUTING, not FLEET SIZE: 100M connections at ~50k/server ≈ 2,000 servers, uncosted.** ⭐⭐ **But 100M users ≠ 100M connections — only ACTIVE VIEWERS need one. Say: _"scope connections to active viewers, on a dedicated connection tier scaled separately"_ — which also stops a bid-service deploy dropping every stream**|
|▹ Extra dives HI flags|⭐⭐ **Dynamic end times (end 1hr after the last bid): simple — update `endTime` on each bid + a cron finds ended auctions. Precise — a DELAYED TASK SCHEDULER: on each bid schedule a task for +1hr (DB-backed queue · Redis sorted set of timestamps · Step Functions Wait); on fire, check that bid is still the latest.** ▹ ⭐⭐ **that's `05p`, and "still the latest?" is its idempotency lesson.** **Purchasing: email the winner; no payment in N ⇒ next highest bidder. Bid history real-time: same problem as §5.3**|
|⭐⭐ The meta-lesson|⭐⭐ **Row locks protect rows that EXIST — they don't stop new rows appearing.** ▸ **If you're guarding an aggregate over a SET, lock the PARENT row, not the set.** ⭐ **That single sentence is the whole of DD1, and it generalises to any "max/count/sum over child rows" contention**|
|Levels (short)|⚠ **Mid:** rarely asked — produce an HLD, respond reasonably on consistency and scale; **interviewer drives**; ▸ fine to propose caching without seeing the distributed-transaction downsides · **Senior:** ⭐⭐ **recognise consistency AND real-time broadcasting as foundational and LEAD toward a solution**; arrive at the consistency answer + explain client freshness; ▹ may not reach scale but should recognise the problems introduced · **Staff:** mastery plus ⭐⭐ **unprompted: ending auctions is its own distributed-systems problem — clock drift, concurrent termination, delayed valid bids** ⇒ propose a dedicated scheduling service (Airflow / queue-based); ⭐⭐ **_"lead the conversation, go deep, show technical accuracy"_**|

---

> 🔗 **HI source:** https://www.hellointerview.com/learn/system-design/problem-breakdowns/online-auction
> 
> ⚠ **Rung labels and §6's layout are MINE, not HI's** — HI's tabbed cards and diagrams don't paste as text, so only the `Approach`/`Challenges` bodies and the component/field names are HI's. ▹ **Check §6 against the source page.**