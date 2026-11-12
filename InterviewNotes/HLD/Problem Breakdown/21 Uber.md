# Ride-Sharing Platform (Uber) — Problem Breakdown

> 📐 **Revision note (calc):** ⭐⭐⭐ **two numbers, and the second is the best argument in your whole set.** **(1) 10M drivers ÷ a ping every 5 seconds = 2 MILLION location writes/second.** **(2) ⭐⭐⭐ Price it: 2M writes/sec × 100 bytes on DynamoDB on-demand ($1.25/million WRU) = _"over $200k a DAY."_** ▸ **First time in the series a design is rejected on COST rather than latency or throughput.** **Other figures: <1 minute to match or fail · 100k requests from one location at peak · 10 seconds for a driver to accept/deny · Redis geohash = a 52-bit integer score in a sorted set · stale-driver cleanup at 30s · `GEOSEARCH` since Redis 6.2.**

> **Evan King**, updated **Feb 15, 2026** · ⭐⭐⭐ **"HARD" — · ⭐⭐ **asked at Amazon, Google (+4 unnamed) — 6 companies** . ⭐⭐ **TWO Pattern callouts: `Real-time Updates` → `03a` and `Multi-step Processes` → `03c`.** Cross-refs: ⭐⭐⭐ **proximity search, quad-trees, geohashing → `04a` (this is THE problem that uses it)** · ⭐⭐⭐ **`05e` Ticketmaster — HI names it directly for the lock problem** · ⭐⭐ **contention ladder → `03b`** · ⭐ **Redis geo commands + sorted sets + distributed locks → `02a`** · **DynamoDB + its cost → `02f`** · **Postgres + PostGIS → `02g`** · **Kafka offset commits → `02c`** · ⭐ **why B-trees fail on 2D data → `01d`** · **geographic sharding → `01f`, `01g`** · **CAP → `01h`** · **API design → `01b`** · **API Gateway → `02d`** · **numbers → `01i`.** **Siblings: ⭐⭐⭐ `05e` (the same lock problem) · `05c` Yelp / `05d` GoPuff (geospatial) · `05k` Strava (client-side GPS logic) · `05t` Notification (in-memory timeouts, Temporal, APNs/FCM).**
> 
> **Calibration:** ⭐⭐⭐ ▸ **Six dives, uneven: DD1, DD3, DD4, DD5 are strong ladders; ⚠ DD2 has only ONE approach and no ladder; ⚠ DD6 is generic vertical-vs-horizontal that HI itself calls _"hardly worth discussing."_** ⭐⭐ **TWO passes, and prioritise DD1 and DD3** — ▸ **HI's E4 bar names exactly those two as the minimum.**
> 
> - ⭐⭐ **What actually scores:**
>     - **(a)** ⭐⭐⭐ **Doing the 2M-writes/sec math AND pricing it out** (§5.1). ▸ **_"over $200k a day"_ ends the discussion.**
>     - **(b)** ⭐⭐⭐ **Knowing WHY a B-tree can't serve a proximity search** — **it's one-dimensional and coordinates are two.**
>     - **(c)** ⭐⭐⭐ **The lock ladder, and why the middle rung fails: an IN-MEMORY timeout dies with the process** (§5.3).
>     - **(d)** ⭐⭐ **Redis geospatial concretely** — **geohash → 52-bit score in a sorted set, `GEOADD` / `GEOSEARCH`.**
>     - **(e)** ⭐⭐ **Why losing the location store barely matters** — ▸ **the data rebuilds itself in 5 seconds.**
>     - **(f)** ⭐⭐ **Committing the Kafka offset only AFTER a match is found** (§5.4).
>     - **(g)** ⭐⭐ **Adaptive ping intervals computed on the device** (§5.2) — ⭐ **HI: _"Don't neglect the client."_**
> - ⭐ **Transferable primitives:**
>     - ⭐⭐⭐ **Price the naive design before rejecting it.** ▸ **A cost figure is a harder argument than a latency figure, and almost nobody produces one.**
>     - ⭐⭐⭐ **A timeout stored in process memory is not a timeout.** ▸ **Put the expiry where it survives a crash — a TTL in Redis, a queue's visibility timeout, a persisted workflow.** ⭐ **Same lesson as `05t §5.1`'s retry loop.**
>     - ⭐⭐⭐ **Data that refreshes itself needs no durability guarantee.** ▸ **Driver locations are rewritten every 5 seconds, so losing the whole store costs 5 seconds.** ⭐ **Match the storage guarantee to the data's lifetime, not to its importance.**
>     - ⭐⭐ **A B-tree orders on ONE dimension. Two coordinates need a structure that partitions space** — **quad-tree, geohash, R-tree** (`04a`).
>     - ⭐⭐ **Geographic sharding buys latency AND scale at once**, ▸ **and the only scatter-gather is a proximity search that straddles a boundary.**
>     - ⭐ **Push work to the device when the device knows more than you do** — ▸ **it has the accelerometer; you don't.**
> - ⭐ **Re-run (cross-ref, NOT re-explained):** ⭐⭐⭐ **the hold-with-expiry pattern (`05e` — HI says this is _"almost exactly the same"_ problem)** · ⭐⭐ **geospatial indexing choice (`04a`, applied in `05c`/`05d`)** · ⭐ **Redis sorted sets (`05i`, `05k`, `05r` — this is the 4th use, now with a geohash as the score)** · **client-side logic as a design tier (`05h`, `05k`, `05s`)** · **APNs/FCM push (`05h §4.4`, `05t`)** · **Temporal (`05o §5.1`, `05p §5.1`, `05t §5.1`)**. **Genuinely new:** ⭐⭐⭐ **cost as a rejection argument** · ⭐⭐⭐ **why B-trees fail on multi-dimensional data** · ⭐⭐ **Redis `GEOADD`/`GEOSEARCH` and the 52-bit geohash score** · ⭐⭐ **the in-memory-timeout failure mode** · ⭐⭐ **PostGIS as the Postgres alternative** · ⭐⭐ **adaptive ping intervals** · ⭐⭐ **commit-offset-after-match** · ⭐ **delay queue vs durable execution** · ⭐ **boundary scatter-gather.**

---

## 0 · Understanding the problem

🚗 **What is Uber?**

A ride-sharing platform **connecting passengers with drivers**, booking **on-demand from a smartphone**, **matching a rider with a nearby driver** who takes them to their destination.

---

## 1 · Requirements

### 1.1 Functional (what it does)

1. ⭐ **Riders input a start location and destination and get a FARE ESTIMATE.**
2. ⭐ **Riders request a ride based on that estimate.**
3. ⭐⭐ **On request, riders are matched with a nearby, available driver.**
4. ⭐ **Drivers accept/decline and navigate to pickup/drop-off.**

⚠ **Below the line:** rating rides and drivers · drivers rating passengers · scheduling in advance · ride categories (X, XL, Comfort).

> ▹ ⭐⭐ **HI's framing advice at the top of this write-up is the most explicit in the series — worth internalising:**
> 
> - ⭐ **Functional requirements are _"Users should be able to…"_ statements; non-functional are _"The system should…"_ statements.**
> - ⭐⭐ **PRIORITISE THE TOP 3.** ▸ **Everything else _"shows your product thinking, but clearly note it as 'below the line'."_** ⭐ **Then CHECK IN — _"see if your interviewer wants to move anything above the line or move anything down."_**
> - ⭐ **Why three: _"Choosing just the top 3 is important to ensuring you stay focused and can execute in the limited time window."_**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 1.2 Non-functional (how it behaves)

1. ⭐ **Low latency matching — <1 minute to match OR failure.** ▹ ⭐ **Note "or failure" — a fast no is also a valid outcome.**
2. ⭐⭐⭐ **Strong consistency in matching — _"prevent any driver from being assigned multiple rides simultaneously."_**
3. ⭐ **High throughput at peak — **100k requests from the same location**.**

⚠ **Below the line:** GDPR/privacy · resilience and failover · monitoring and alerting · CI/CD.

### 1.3 ⭐⭐⭐ The design driver — two problems that look like one, pulling opposite ways

||⭐⭐ **Location data**|⭐⭐ **Matching state**|
|---|---|---|
|**Volume**|⚠⚠ **2M writes/sec**|**low — one per ride**|
|**Lifetime**|⭐⭐ **5 seconds; overwritten constantly**|**durable; the ride record is the truth**|
|**If you lose it**|⭐ **nothing — it rebuilds in 5s**|⚠⚠ **a rider waits forever for a match that never comes**|
|**Needs**|**throughput + a SPATIAL index, cheaply**|⭐⭐ **strong consistency + a timeout that survives a crash**|

- ⭐⭐⭐ **So the answer is three stores chosen by DATA CHARACTER, not by convenience:**
    - ⭐ **Redis GEO for locations** — **ephemeral, self-healing, spatially indexed.**
    - ⭐ **Redis with TTL for driver locks** — **the expiry must outlive the process that set it.**
    - ⭐ **Postgres/DynamoDB for Ride and Fare** — **durable truth.**
- ⭐⭐ **And the thing that makes this "hard" rather than "medium": the matching half is `05e` Ticketmaster, the location half is `05c` Yelp at 2M writes/sec, and you have to do both in 45 minutes.**

### 1.4 Planning the approach

▸ **Sequentially through the FRs, then let the NFRs drive the dives.**

---

## 2 · Core Entities

- **Rider** — personal info, payment methods.
- **Driver** — personal details, **vehicle info**, preferences, **availability status.**
- ⭐ **Fare** — **an ESTIMATE: pickup, destination, estimated fare, ETA.** ▹ **HI: could live on the Ride object instead — _"there is no right or wrong answer here."_**
- ⭐⭐ **Ride** — **the whole lifecycle from fare confirmation to completion:** rider and driver identities, vehicle, **state**, planned route, **actual fare charged at the end**, pickup/drop-off timestamps.
- ⭐⭐ **Location** — **real-time driver location: lat, long, and the timestamp of the last update.** ▸ **_"crucial for matching riders with nearby drivers and for tracking the progress of a ride."_**

▹ ⭐ **Note Fare (an estimate) and Ride (the actual charge) are deliberately separate things.** ▸ **That split is what §5.1's ⊕ note is about.**

---

## 3 · API

```
POST  /fare -> Fare                    { pickupLocation, destination }
POST  /rides -> Ride                   { fareId }          ⭐ just the fare id
POST  /drivers/location -> Success     { lat, long }       ⭐ driverId from the JWT
PATCH /rides/:rideId -> Ride           { accept/deny }
```

- ⭐ **`POST /fare` because you're CREATING a Fare entity**, not just reading.
- ⭐⭐ **`POST /rides` takes ONLY `fareId`** — ▸ **the price comes from the stored Fare, never from the client.**
- ▹ **Matching needs no endpoint — _"this is all happening in the backend."_**

> ⭐⭐⭐ **The security paragraph — the strongest version of this in the series, and it names a THIRD thing.**
> 
> - ⚠ **_"I regularly see candidates passing in data like `userId`, `timestamps`, or even `fareEstimate` in the body or query parameters. This is a red flag."_**
> - ⭐ **`userId` → from the session/JWT.** ⭐ **`timestamps` → generated by the server.**
> - ⭐⭐⭐ **And the new one: _"Data like `fareEstimate` should be retrieved from the database and never passed in by the client."_** ▸ **Otherwise the rider sets their own price.**
> - ⭐ **The general rule: anything the client could profit from changing must come from your side of the boundary.**
> 
> ■ **— end of insert · HI write-up resumes below —**

---

## 4 · High-Level Design

### 4.1) Fare estimate

```
Rider Client ──► API Gateway & LB ──► Ride Service ──┬──► 3rd-Party Mapping API
(iOS/Android)     routing · auth      fare estimation │     (distance + travel time)
                  · rate limiting                     └──► DB
                                                            Fare: id · userId · source
                                                                  destination · price · eta
```

**What we're building:**

- **Rider Client** — iOS/Android, the primary touchpoint.
- **API Gateway** — **routes to microservices, plus authentication and rate limiting.**
- ⭐ **Ride Service** — **manages ride state, starting with fare estimates.** **Calls the mapping API for distance and travel time, then applies the pricing model.** ▹ **HI abstracts the pricing model away.**
- ⭐ **Third-Party Mapping API** — **Google Maps or similar, for distance and routing.**
- **Database** — **stores Fare entities.**

**The flow:** **rider enters pickup + destination → `POST /fare` → Gateway auths and forwards → Ride Service calls the mapping API, applies pricing → creates a Fare row → returns it so the rider can decide.**

> ⊕ ⚠⚠ **(mine, not HI) — the Fare has no expiry, and that's a real hole.**
> 
> - ▸ **HI says the rider _"will then have a chance to request a ride with this fare or do nothing."_** ⚠ **Nothing bounds how long "do nothing" lasts.**
> - ⚠⚠ **Accept a 20-minute-old estimate and you honour a pre-surge price during a surge** — ⭐ **a direct revenue leak, and the sharper version of the security point above: taking the price from the DB only helps if the DB value is still valid.**
> - ⭐⭐ **Say it in one line:** _"I'd put a short TTL on the Fare — a few minutes — and re-quote on expiry, since surge pricing makes a stale estimate a liability."_ ▸ **Cheap, and it shows you're thinking about the business and not just the data flow.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 4.2) Request a ride

▸ ⭐ **No new services — just a Ride table.**

- **Flow: rider confirms → `POST /rides {fareId}` → Ride Service creates a Ride row linked to that Fare, status `requested` → triggers the matching flow.**
- **Ride: `rideId · riderId · driverId? · fareId · source · destination · status`.** ▹ ⭐ **Note `driverId?` is nullable — it's unassigned until matching succeeds.**

### 4.3) Match with a nearby driver

⭐ **Three new components:**

- ⭐ **Driver Client** — **receives ride requests and sends location updates.**
- ⭐ **Location Service** — **receives driver location updates, stores them, and serves the latest locations to matching.**
- ⭐⭐ **Ride Matching Service** — **takes ride requests and runs the matching algorithm** (⭐ **abstracted away**) **over proximity, availability, driver rating and other factors.**

**The flow, step by step:**

1. ⭐ **The rider CONFIRMS the request in the client app** ⇒ **`POST /rides` carrying only the `fareId` they're accepting.** ▹ **The price is already on the server; the client just points at it.**
2. **API Gateway authenticates and rate-limits, then forwards to the Ride Service.**
3. ⭐ **Ride Service creates the Ride object** (status `requested`, `driverId` still null) **and forwards to the Ride Matching Service to TRIGGER the matching workflow.** ▹ ⭐ **HI flags this as deliberately naive — _"we'll discuss ways to make this more robust later, keeping it simple for now"_** ⇒ ⚠ **this direct call is what §5.4 replaces with a queue.**
4. ⭐⭐ **Meanwhile — and this runs CONTINUOUSLY, independent of any ride** — **every driver is posting their current location to the Location Service, which keeps the latest lat/long per driver.** ▸ ⭐ **This is the 2M writes/sec stream, already warm before any rider asks.**
5. ⭐ **Matching then queries THOSE locations for the closest available drivers** ⇒ **an optimal match.**

▸ ⭐⭐ **The shape worth noticing: steps 1–3 are request-driven, step 4 is a standing background stream, and step 5 just READS what step 4 has already built.** ⭐ **Matching is fast because nothing is collected on demand — the index is always current.**

### 4.4) Driver accepts/declines

⭐ **One new component: Notification Service** — **dispatches real-time notifications to drivers via APNs (iOS) and FCM (Android).** ▸ **_"It ensures that drivers are promptly informed so they can accept ride requests in a timely manner."_**

**The flow:**

1. **Matching produces a RANKED LIST of eligible drivers and notifies the TOP one.**
2. **Driver accepts ⇒ `PATCH /rides/:rideId`.** ⭐ **Declines ⇒ notify the NEXT driver on the list.**
3. **Ride Service sets status `accepted`, assigns the driver, returns the pickup coordinates.**
4. ⭐ **The driver navigates using on-client GPS.**

> ⭐ **Pattern: Real-time Updates** (`03a`) — **callout #1.** ▹ **Pushing to drivers: the options run from long-polling to SSE to WebSockets** — ⭐ **go read `03a`'s flow chart.**
> 
> ■ **— end of insert · HI write-up resumes below —**

---

## 5 · Deep Dives

### 1) ⭐⭐⭐ How do we handle frequent driver location updates and efficient proximity searches on location data?

⭐⭐ **Two separate problems — name both:**

**⚠⚠ Problem 1 — write volume.** 📐 **10M drivers × a ping every 5 seconds = ~2 MILLION updates/second.** ▸ **_"Whether we choose DynamoDB or PostgreSQL (both great choices for the rest of the system), either one would either fall over under the write load, or need to be scaled up so much that it becomes prohibitively expensive."_**

> ⭐⭐⭐ **And then HI PRICES IT — the single most powerful argument in the series.**
> 
> **_"For DynamoDB in particular, 2M writes a second of 100 bytes at on-demand pricing ($1.25 per million WRUs) would cost you **over $200k a day**."_**
> 
> - ⭐⭐⭐ **First time a design in this series is killed on COST rather than latency or throughput.** ▸ **A dollar figure ends an argument that a QPS figure only starts.**
> - ⭐⭐ **The reusable move: when you reject a naive design, try pricing it.** ▸ **`writes/sec × 86,400 × unit price` is one line of arithmetic and almost no candidate does it.**
> 
> ■ **— end of insert · HI write-up resumes below —**

**⚠⚠ Problem 2 — query efficiency.** ▸ **Querying by lat/long with no optimisation means a FULL TABLE SCAN, computing distance to every driver.** ⭐⭐⭐ **And the key reason indexing doesn't save you: _"traditional B-tree indexes are not well-suited for multi-dimensional data like geographical coordinates."_** ▸ **A B-tree orders on ONE dimension; a coordinate is TWO.** ⚠ **HI: _"essentially a non-starter."_**

⚠ **Rung labels are mine.**

#### ⚠⚠ Bad — write every update straight to the DB

- ▸ **What the HLD left you with.** ⚠ **Doesn't scale with millions of drivers, and proximity searches stay inefficient** ⇒ **_"system overload, high latency, and poor user experience."_**

**Why climb:** too many writes, and the wrong index shape.

#### Good — batch the writes + a geospatial database

- ⭐ **Batch: aggregate updates over a short interval, then write in one batch operation.** ▸ **Fewer write transactions ⇒ better write throughput and less lock contention.**
- ⭐⭐ **Index: a specialised geospatial database using structures like QUAD-TREES** (`04a`) — ▸ **_"they partition the space into quadrants recursively"_, which is what makes "all drivers within this area" fast.**
- ⭐ **And the Postgres option worth knowing: PostGIS**, a plugin giving **geospatial data types and functions _"without needing an additional database."_**
- ⚠ **Challenge:** ⭐ **the batch interval introduces a DELAY** ⇒ **locations in the DB aren't current** ⇒ **_"suboptimal driver matches."_**

**Why climb:** you traded freshness for throughput, and freshness is the product.

#### ⭐⭐ Great — Redis with geospatial commands

- ⭐⭐ **How it works under the hood:** **Redis uses GEOHASHING to encode lat/long into a **52-bit integer score** within a SORTED SET**, where **each member (the `driverId`) carries its geohash score.** ▹ ⭐ **Fourth use of Redis sorted sets in your set (`05i`, `05k`, `05r`) — here the score is a geohash instead of a timestamp or a rank.**

```
GEOADD    drivers <long> <lat> <driverId>     # add/update a location
GEOSEARCH drivers FROMLONLAT … BYRADIUS …     # query nearby
```

> ⚠ **Confusion resolved — the three slots, and what the search is actually doing.**
> 
> - **Key = `drivers:locations` (ONE set for all drivers; per CITY once sharded) · Member = `driverId` · Score = the geohash.** ▸ ⭐ **`GEOADD` IS a `ZADD` — so re-writing a driver just overwrites that member's score, and `ZREM` deletes them (there's no `GEOREM`).**
> - ⚠⚠ **The set is sorted by ABSOLUTE geohash, NOT by distance from the rider — there is no "top" to read.** ▸ ⭐ **What the sort buys you: a geohash RANGE = a box on the map.**
> - ⭐⭐ **So `GEOSEARCH` jumps to the RIDER's own geohash in the middle of the set, scans the ranges around it, and only THEN computes true distance to rank.** ⚠ **Adjacent scores ≠ adjacent drivers.**
> 
> ■ **— end of insert · HI write-up resumes below —**

- ▹ ⭐ **`GEOSEARCH` arrived in Redis 6.2 and _"replaces and enhances"_ the older `GEORADIUS` / `GEORADIUSBYMEMBER`.**
- ⭐⭐ **Batching disappears** — **Redis handles the volume in real time.** ⭐ **And each `GEOADD` OVERWRITES the driver's previous location, so you always have the latest position with no cleanup.**
- ⭐ **The one cleanup you DO need — offline drivers:** **a periodic process removing drivers whose last update is older than a threshold (e.g. 30 seconds).** ▸ ⭐ **HI's approach: keep a COMPANION sorted set keyed by timestamp and periodically remove old entries from both sets.**
- ⚠ **Challenge — durability, since Redis is in-memory.** **Mitigations: RDB or AOF persistence; Redis Sentinel for automatic failover.**
- ⭐⭐⭐ **But the real answer to the durability worry is the best line in the dive:** **_"Since driver location updates come in every 5 seconds, we would only need that long to recover and rebuild the state of our system."_** ▸ ⭐⭐ **The data heals itself. Match the storage guarantee to the data's LIFETIME, not to its importance.**

> ⊕ ⭐⭐ **(mine, not HI) — 2M writes/sec doesn't fit on one Redis either, and DD6 is the answer HI never connects.**
> 
> - ⚠ **From `05r §5.5`: one Redis instance serves ~100k ops/sec.** ▸ **2M/sec needs ~20 instances minimum.** ⭐ **HI rejects DynamoDB on volume and cost, moves to Redis, and never shards it.**
> - ⭐⭐ **§5.6's GEOGRAPHIC SHARDING is exactly the fix:** **each city or region gets its own location Redis, so the 2M divides naturally by geography** — ▸ **and drivers only ever need to be found near riders in the same region.**
> - ⭐ **Say it in DD1 rather than waiting for DD6:** _"locations shard geographically, which both divides the 2M writes and keeps every proximity query inside one shard."_ ▸ **That also sets up DD6's boundary scatter-gather point.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 2) ⚠ How can we manage system overload from frequent driver location updates while ensuring location accuracy?

⚠⚠ **Only ONE approach in this dive — no ladder.** ▹ ⭐ **HI's framing of why it's asked: _"In most candidates' original design, they have drivers ping a new location every 5 seconds. This follow up question is designed to see if they can intelligently reduce the number of pings while maintaining accuracy."_**

- ⭐⭐ **The answer: ADAPTIVE update intervals**, adjusted dynamically on **speed, direction of travel, proximity to pending ride requests, and driver status.**
- ⭐ **Computed ON THE DEVICE using its own sensors:** **stationary or slow ⇒ less frequent; moving fast or changing direction often ⇒ more frequent.**
- ⚠ **Challenge: _"the complexity of designing effective algorithms to determine the optimal update frequency"_** — **needs careful testing.** ✅ **_"But, if done well, it will significantly reduce the number of location updates."_**

> ⭐⭐ **HI's lesson here is broader than the dive, and it's the fifth time this thread has appeared.**
> 
> - ⭐⭐⭐ **_"Don't neglect the client when thinking about your design. Many candidates get in a habit of drawing a small client box and moving on."_**
> - ⭐ **HI's own second example: _"in the case of a file upload service, the client is responsible for chunking and compression"_** (`05b`, `05o`).
> - ▹ ⭐ **Your running thread: `05h` (caches its own swipes) · `05k` (records its own activity) · `05o` (picks the ABR format) · `05s` (collects data for you) · `05u` (decides its own ping rate).** ⭐⭐ **The deciding question each time: does the client know something the server doesn't?** ▸ **Here it has the accelerometer. You don't.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 3) ⭐⭐⭐ How do we prevent multiple ride requests from being sent to the same driver simultaneously?

⭐⭐ **First, state the requirement precisely — it's TWO things:** **_"we only request one driver at a time for a given ride request AND that each driver only receives one ride request at a time."_** ⭐ **Plus the window: **10 seconds** to accept or deny before moving to the next driver.**

> ⭐⭐⭐ **HI names the sibling outright: _"If you've solved Ticketmaster before, you know this problem well — as it's almost exactly the same as ensuring that a ticket is only sold once while being reserved for a specific amount of time at checkout."_** ▸ ⭐ **So this is `05e §5.1` with `driverId` in place of `seatId`.**
> 
> ■ **— end of insert · HI write-up resumes below —**

⭐ **The intuition: you need to LOCK drivers. The ladder is just "where does the lock live?"**

> ⚠⚠ **Confusion resolved — WHAT is locked, WHO locks, WHO releases. HI drifts on all three. Read this BEFORE the rungs.**
> 
> |Rung|Locked|Who locks|Who releases|Timeout lives in|
> |---|---|---|---|---|
> |**Bad**|⚠ **HI writes _"ride request"_ — he means the DRIVER**|a Ride **Matching** instance|**the same instance, manually**|⚠⚠ **that instance's memory**|
> |**Good**|⭐ **the DRIVER** — status column `outstanding_request`|whoever writes the row|⚠ **a timeout in the RIDE Service**|⚠⚠ **Ride Service's memory**|
> |**Great**|⭐ **the DRIVER** — a Redis key on `driverId`|Ride **Matching** Service|**accept ⇒ the service clears it · silence ⇒ ⭐⭐ NOBODY, the TTL does**|⭐⭐⭐ **Redis**|
> 
> - ⭐⭐⭐ **The whole ladder is ONE idea: the timeout moves from instance memory → service memory → infrastructure.** ▸ **Each rung puts it one step further from the thing that can crash.**
> - ⚠ **On "ride request" vs "driver": HI's own intuition line says _"we need to lock drivers"_, then the Bad and Good rungs say _"ride request"_ — and the Good rung contradicts itself one sentence apart (_"lock a ride request"_, then _"update the status of that DRIVER"_).** ⭐ **The Great rung and his diagram both settle on `driverId`. Read "ride request" as "driver" in the first two rungs.**
> - ⚠ **Why the Good rung names the RIDE Service — not a typo, a real seam:** **Ride MATCHING takes the lock, but the driver's accept arrives at `PATCH /rides/:rideId`, which is RIDE Service.** ▸ **The release crosses a service boundary, and HI never says so.** ⭐⭐ **In the Great rung that stops mattering: lose the release message and the lock still expires in 10s.**
> - ⭐⭐ **And the lock only covers HALF the NFR:** ✅ **_"each driver only receives one ride request at a time"_** · ⚠ **NOT _"we only request one driver at a time for a given ride request"_** — ▸ **that falls out of the serial ranked-list walk plus §5.4's one-consumer-per-partition. HI never connects it.**
> 
> ■ **— end of insert · HI write-up resumes below —**

⚠ **Rung labels are mine.**

#### ⚠⚠ Bad — application-level locking

- **Approach:** **each Ride Matching Service instance marks a request "locked" when it sends it to a driver, starts a timer, and releases manually on timeout.**
- ⚠ **Three problems:**
    - ⚠⚠ **No coordination.** **Multiple instances, no central authority** ⇒ **_"two instances might attempt to lock the same ride request simultaneously."_**
    - ⚠⚠ **Inconsistent lock state.** **One instance sets a lock and crashes before releasing** ⇒ **_"other instances have no knowledge of this lock"_** ⇒ **locked indefinitely.**
    - ⚠ **Gets worse as you scale** — more instances, more coordination failures.

**Why climb:** a lock only works if everyone can see it.

#### Good — put the lock in the database

- **Approach:** ⭐ **use the database's transactional capabilities so only one instance can lock at a time.** **Set the driver's status to `outstanding_request` on send; `accepted` on accept; `available` on decline.** **A timeout in the Ride Service releases it after 10 seconds.**
- ✅ **Coordination solved.**
- ⚠⚠⚠ **Challenge, and it's the lesson of the whole dive: the TIMEOUT IS STILL IN MEMORY.** ▸ **_"If the Ride Service crashes or is restarted, the timeout will be lost and the lock will remain indefinitely."_** ⭐⭐ **HI: _"This is a common issue with in-memory timeouts and why they should be avoided when possible."_**
- ▹ ⚠ **The patch — a cron sweeping for expired locks — _"works, but adds unnecessary complexity and introduces a delay in unlocking."_**

**Why climb:** move the expiry somewhere that survives the process that set it.

#### ⭐⭐ Great — a distributed lock with a TTL

- ⭐⭐⭐ **Approach: a Redis lock keyed on `driverId` with a TTL equal to the 10-second acceptance window.** ▸ **Acquire ⇒ no other instance can send to that driver until it expires or is released.** **Accept within the window ⇒ ride status `accepted` in the DB, lock released.** ⭐⭐ **No accept ⇒ the lock EXPIRES BY ITSELF and the driver becomes eligible again.**
- ⭐⭐⭐ **Why it closes the gap: the TTL lives in Redis, not in the process.** ▸ **The Ride Service can crash and the lock still expires on schedule.** ⭐ **Same lesson as `05t §5.1`'s in-process retry loop, and `05p §5.3`'s visibility timeout.**
- ⚠ **Challenge: you now depend on Redis's availability and performance for correctness** ⇒ **needs monitoring and failover.** ⭐⭐ **But HI's mitigation is the data's own nature again: _"Given locks are only held for 10 seconds, this is a reasonable tradeoff as the ephemerality of the data makes it easier to recover from failures."_**

### 4) ⭐⭐ How can we ensure no ride requests are dropped during peak demand periods?

⚠ **Two failure modes, and the second is easy to miss:** **(1) surges overwhelm the service** · ⚠⚠ **(2) _"an instance of the Ride Matching Service crashes or is restarted, leading to dropped rides."_**

⚠ **Rung labels are mine.**

#### ⚠ Bad — process as they arrive

- ⚠ **Doesn't scale in a surge; horizontal scaling can't react fast enough to _"sudden surges in demand."_**
- ⚠⚠ **And if an instance dies, its in-flight requests are LOST** ⇒ **_"riders waiting indefinitely for a match that will never come."_** ⭐ **_"There's no built-in mechanism for request recovery or failover."_**

**Why climb:** in-flight work needs to live somewhere other than the process doing it.

#### ⭐⭐ Great — a queue with dynamic scaling

- ⭐ **Approach: ride requests go into a queue; Ride Matching consumes FIFO; scale instances horizontally on queue depth.** ⭐ **And partition the queues by GEOGRAPHIC REGION for efficiency.**
- ⭐⭐⭐ **The Kafka detail that solves failure mode 2:** **_"commit the offset of the message in the queue only AFTER we have successfully found a match. This way, if the Ride Matching Service goes down, the match request would still be in the queue, and a new instance would pick it up."_** ▸ ⭐ **Commit-after-success is the same shape as `05p`'s delete-after-success and `05t`'s mark-after-provider.**
- ⚠ **Challenges:**
    - ⚠ **Operational complexity** — ⭐ **and HI's framing is sharper than "complexity": _"We need to ENSURE that the queue is scalable, fault-tolerant, and highly available."_** ▸ **Those are the GOAL, not a given — self-hosting means you own brokers, partitions, replication, rebalancing, retention and consumer-lag monitoring.** ⇒ ⭐ **use a managed service — SQS, Amazon MSK, Confluent Cloud — _"so we can focus on the business logic."_**
    - ⚠⚠ **FIFO means HEAD-OF-LINE BLOCKING:** **_"you could have requests that are stuck behind a request that is taking a long time to process."_** ⇒ ⭐ **use a PRIORITY queue instead, ranked on driver proximity, driver rating and other factors.** ▹ ⭐ **Same problem `05t §5.2` solved with priority queues, and `05p §5.1` noted for Kafka partitions.**

> ⚠⚠ **Confusion resolved — SQS is NOT managed Kafka, and HI's own argument doesn't survive the swap.**
> 
> - ⭐ **MSK = Managed Streaming for Apache Kafka · Confluent Cloud = managed Kafka. ⚠⚠ SQS = AWS's own proprietary queue — not Kafka, not a log, NO OFFSETS.**
> - ⚠ **So HI justifies the queue with _"commit the offset… only after we have successfully found a match"_, then lists SQS as interchangeable. There is no offset to commit in SQS.** ⭐⭐ **Its equivalent: read ⇒ invisible for the visibility timeout ⇒ `DeleteMessage` on success. No delete ⇒ it reappears for another worker.** ▸ **Same guarantee, different mechanism** (`05p §5.3`).
> - ⚠ **And _"since it is a FIFO queue"_ is loose: standard SQS is best-effort order, SQS FIFO is a separate type, Kafka orders only WITHIN a partition.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 5) ⭐⭐ What happens if a driver fails to respond in a timely manner?

⚠ **The scenario: _"what if they drop their phone in the passenger seat and take a break?"_** ▸ **You want the system to move to the next driver automatically.**

> ⭐⭐ **Pattern: Multi-step Processes** (`03c`) — **callout #2, and the backstory justifies it.** ▹ ⭐⭐ **_"Human-in-the-loop processes are a big signal of when to use the Multi-Step Processes pattern. In fact, Uber is the original author of the open source project Cadence which gave birth to… Temporal, built specifically for use-cases like this one."_** ▸ ⭐ **Fourth Temporal appearance in your set (`05o` DAG, `05p` orchestrator, `05t` deliberately avoided) — and the FIRST where it's the winning answer.**
> 
> ■ **— end of insert · HI write-up resumes below —**

⚠ **Rung labels are mine.**

#### Good — a delay queue

- ⭐ **Approach: when you send a request to a driver, simultaneously schedule a DELAYED message (e.g. an SQS delay queue) that fires after the 10-second timeout.** ▸ **It carries the ride details and the driver contacted.** **On processing, check whether the ride is still unassigned; if so, move to the next driver and schedule another delayed message.** ▹ ⭐ **Same `DelaySeconds` mechanism as `05p §5.1`.**
- ⚠ **Challenges:**
    - ⚠⚠ **Cancellation:** **_"If a driver accepts the ride after the delayed message is already scheduled but before it's processed, we need to ensure the delayed message is handled gracefully and doesn't cause the ride to be reassigned incorrectly."_**
    - ⚠ **Needs careful coordination with matching _"to ensure consistency and avoid race conditions."_**

**Why climb:** you're hand-rolling a state machine out of timers.

#### ⭐⭐ Great — durable execution (Temporal / Step Functions)

- ⭐⭐ **Approach: model the whole matching flow as a DURABLE WORKFLOW with built-in timeouts, retries and state management _"in a way that survives service crashes and restarts."_** ⭐ **State is persisted, so a crashed service RESUMES where it left off.**
- ⭐ **The workflow:** **send to driver 1 → 10-second timeout → accept ⇒ complete → decline or timeout ⇒ next driver → repeat until matched or exhausted.**
- ⚠ **Challenge: _"the additional complexity of introducing a workflow orchestration system"_** — **new concepts, new tooling, another component to monitor.** ✅ ⭐ **But: _"the benefits of guaranteed execution, built-in fault tolerance, and simplified business logic often outweigh these challenges, especially for mission-critical systems like ride-sharing platforms where dropped requests directly impact revenue."_**

### 6) ⚠ How can you further scale the system to reduce latency and improve throughput?

⚠⚠ **The thinnest dive — and HI says so: vertical scaling _"is hardly worth discussing… as it's not practical for a system of this scale."_** ⭐ **Two things here are worth keeping:**

- ⭐⭐ **GEOGRAPHIC SHARDING buys two things at once:** **it scales, AND _"it reduces latency by reducing the distance between the client and the server."_** ▸ **Applies to **everything** — services, message queue, databases.**
- ⭐⭐⭐ **And the single sharp sentence in the dive:** **_"The only time that we would need to scatter gather (i.e., query multiple shards) is when we are doing a proximity search on a BOUNDARY."_** ▸ ⭐ **A rider at a city edge may have the nearest driver in the next shard.** ⭐ **That's the one case geography doesn't cleanly partition.**
- ▹ **Plus read replicas for read throughput, and consistent hashing to distribute data** (`01g`).

---

## 6 · Final Design

⚠ **Layout and arrows are mine; components and field lists are HI's.**

```
Rider Client                                   Driver Client
(iOS/Android)                                  (iOS/Android)
  │  POST /fare  {pickupLocation, destination}    │  POST /drivers/location {lat,long}
  │  POST /rides {fareId}  ⭐ fareId only          │    ⭐ driverId from the JWT
  │                                               │    ⭐⭐ ADAPTIVE interval, decided
  │                                               │       on-device from speed/direction
  │                                               │  PATCH /rides/:rideId {accept/deny}
  ▼                                               ▼
API Gateway & Load Balancer — routing · auth · rate limiting            02d
  │
  ├──► Ride Service                                3rd-Party Mapping API
  │      fare estimation ──────────────────────►   (distance + travel time)
  │      ride creation
  │      triggers matching
  │      updates the DB on accept/decline
  │         │
  │         ├──► DB (DynamoDB or Postgres)                        02f · 02g
  │         │      Fare:  id · userId · source · destination · price · eta
  │         │             ⊕ needs a short TTL — a stale estimate honoured
  │         │                during a surge is a revenue leak
  │         │      Ride:  rideId · riderId · driverId? · fareId
  │         │             source · destination · status
  │         │      Rider · Driver (vehicle · name)
  │         │      ⭐ geographically sharded, with read replicas     01f
  │         │
  │         └──► Match Queue (Kafka)                                   02c
  │                ⭐⭐ commit the offset ONLY after a match is found
  │                   ⇒ a crashed matcher loses nothing
  │                ⭐ partitioned by region · ⚠ FIFO head-of-line
  │                   blocking ⇒ prefer a PRIORITY queue
  │                ▼
  │         Ride Matching Service  ⭐ scales on queue depth
  │                │
  │                ├──► Location DB (Redis GEO)               02a · 04a
  │                │      ⭐⭐ geohash → 52-bit score in a SORTED SET
  │                │      GEOADD (overwrites ⇒ always current)
  │                │      GEOSEARCH (since 6.2; replaced GEORADIUS)
  │                │      📐 2M writes/sec — ⭐ which is WHY not DynamoDB:
  │                │         that would be "over $200k a day"
  │                │      ⭐ companion timestamp ZSET ⇒ purge drivers
  │                │         silent >30s
  │                │      ⭐⭐ durability barely matters — the whole store
  │                │         rebuilds in 5 seconds
  │                │      ⊕ shard it geographically: ~100k ops/s per
  │                │         instance means 2M/s needs ~20
  │                │
  │                ├──► Distributed Lock (Redis, TTL = 10s)            03b
  │                │      ⭐⭐⭐ keyed on driverId — one outstanding request
  │                │         per driver, and the TTL EXPIRES ITSELF
  │                │      ▸ the point: the expiry outlives the process
  │                │         that set it (cf. 05e Ticketmaster)
  │                │
  │                └──► ⭐ durable workflow (Temporal / Step Functions)  03c
  │                       send → 10s timeout → accept? done :
  │                       next driver → repeat until matched or exhausted
  │                       ⭐ survives crashes; resumes where it stopped
  │
  └──► Notification Service (APNs / FCM)  ──► the top-ranked driver      03a
         ⭐ decline ⇒ notify the next driver on the ranked list

⭐⭐ Shard EVERYTHING geographically — services, queue, databases.
   Scatter-gather is needed ONLY for a proximity search on a boundary.
```

---

## 7 · Expected at Each Level

|Level|The bar for Uber|
|---|---|
|**Mid (E4)**|**API + data model + a functional HLD; recognise the need for a spatial index (specific solution optional); land at least the GOOD lock solution.**|
|**Senior (E5)**|**Fast HLD, then depth on at least 2 of: location-search speed · the lock problem · request queueing — with trade-offs articulated.**|
|**Staff+**|**Depth in 3+ areas, and the interviewer should leave having learned something.**|

---

## Quick Recall (pass 3+)

|Use / Question|Uber answer|
|---|---|
|Calibration|⭐ Evan King · Feb 2026 · ⭐⭐⭐ **"HARD" — the first hard problem in your set** · ⭐⭐ **Amazon, Google (+4) = 6 companies** · ⭐⭐ **TWO patterns: `Real-time Updates` (`03a`) + `Multi-step Processes` (`03c`).** ⭐⭐⭐ **The problem your `04a` notes exist for.** ▸ **6 dives: DD1/DD3/DD4/DD5 strong; ⚠ DD2 has ONE approach, no ladder; ⚠ DD6 is generic and HI calls it _"hardly worth discussing."_** ⭐⭐ **TWO passes, prioritise DD1 + DD3 (the E4 bar names exactly those)**|
|⭐⭐⭐ Design driver|⭐⭐⭐ **Two problems that look like one, pulling opposite ways.** **LOCATION: 2M writes/sec, 5-second lifetime, loss costs nothing ⇒ needs throughput + a SPATIAL index, cheaply. MATCHING: low volume, durable, loss means a rider waits forever ⇒ needs strong consistency + a timeout that survives a crash.** ⭐⭐⭐ **So THREE stores chosen by DATA CHARACTER: Redis GEO (ephemeral, self-healing, spatial) · Redis TTL locks (expiry outlives the process) · Postgres/DynamoDB (durable truth).** ⭐⭐ **And why it's "hard": the matching half IS `05e`, the location half is `05c` at 2M writes/sec, and you have 45 minutes**|
|FRs / NFRs|**fare estimate · request a ride on that estimate · ⭐⭐ match with a nearby available driver · driver accepts/declines and navigates.** Below: ratings · advance scheduling · ride categories. **NFRs: <1 min to match OR FAILURE (▹ a fast no is a valid outcome) · ⭐⭐⭐ strong consistency — _"prevent any driver from being assigned multiple rides simultaneously"_ · 100k requests from one location.** Below: GDPR · failover · monitoring · CI/CD|
|⭐⭐ HI's requirements framing|⭐ **FRs are _"Users should be able to…"_, NFRs are _"The system should…"_** ⭐⭐ **PRIORITISE THE TOP 3**; everything else below the line _"shows your product thinking"_; ⭐ **then CHECK IN — _"see if your interviewer wants to move anything above the line."_** ⭐ **Why 3: _"important to ensuring you stay focused and can execute in the limited time window"_**|
|📐 Numbers|**10M drivers ÷ 5s ping = ⭐⭐ 2 MILLION writes/sec.** ⭐⭐⭐ **Priced: 2M/sec × 100 bytes on DynamoDB on-demand ($1.25/M WRU) = _"over $200k a DAY"_ — the first COST-based rejection in the series.** **<1 min match · 100k from one location · 10s accept window · geohash = 52-bit score · stale cleanup at 30s · `GEOSEARCH` since Redis 6.2**|
|Entities|**Rider · Driver (vehicle, availability) · ⭐ Fare (the ESTIMATE — pickup, destination, fare, ETA; ▹ _"could also just be put on the ride object… no right or wrong answer"_) · ⭐⭐ Ride (the whole lifecycle, incl. the ACTUAL fare charged) · ⭐⭐ Location (lat, long, last-update timestamp).** ▹ ⭐ **Fare ≠ Ride deliberately: estimate vs actual**|
|API|`POST /fare {pickupLocation, destination}` (⭐ POST because you CREATE a Fare) · `POST /rides {fareId}` — ⭐⭐ **fareId ONLY, the price comes from the DB** · `POST /drivers/location {lat,long}` (⭐ driverId from the JWT) · `PATCH /rides/:rideId {accept/deny}`. ▹ **matching needs no endpoint — _"all happening in the backend"_**|
|⭐⭐⭐ The security rule, strongest version|⚠ **_"I regularly see candidates passing in `userId`, `timestamps`, or even `fareEstimate` in the body or query parameters. This is a red flag."_** ⭐ **userId → JWT · timestamps → server-generated · ⭐⭐⭐ NEW: _"Data like `fareEstimate` should be retrieved from the database and never passed in by the client"_ — otherwise the rider sets their own price.** ⭐ **General rule: anything the client could PROFIT from changing must come from your side**|
|HLD components|**Rider Client · API Gateway (routing, auth, rate limiting) · ⭐ Ride Service (fare estimation → ride creation → triggers matching → records accept/decline) · 3rd-Party Mapping API (distance + travel time; ⭐ pricing model abstracted) · DB · then ⭐ Driver Client · ⭐ Location Service · ⭐⭐ Ride Matching Service (⭐ algorithm abstracted — proximity, availability, rating) · ⭐ Notification Service (APNs/FCM)**|
|⭐ Accept/decline flow|**matching produces a RANKED LIST → notify the TOP driver → accept ⇒ `PATCH /rides/:rideId`, status `accepted`, driver assigned, pickup coords returned → ⭐ decline ⇒ notify the NEXT on the list → driver navigates with on-client GPS.** ▹ **`driverId?` on Ride is nullable until matched**|
|⊕⚠⚠ The Fare never expires|▸ **HI: the rider _"will then have a chance to request a ride with this fare or do nothing"_ — nothing bounds how long.** ⚠⚠ **A 20-minute-old estimate honoured during a surge is a direct revenue leak** — ⭐ **and the sharper version of the security point: taking the price from the DB only helps if the DB value is still VALID.** ⭐⭐ **One-liner: _"short TTL on the Fare, re-quote on expiry, since surge pricing makes a stale estimate a liability"_**|
|⚠⚠ DD1 — the two problems|**(1) WRITE VOLUME: 2M/sec — _"either one would either fall over under the write load, or need to be scaled up so much that it becomes prohibitively expensive."_ (2) QUERY EFFICIENCY: lat/long with no optimisation = a FULL TABLE SCAN, and ⭐⭐⭐ even indexed, _"traditional B-tree indexes are not well-suited for multi-dimensional data like geographical coordinates"_ — a B-tree orders on ONE dimension, a coordinate is TWO. ⚠ _"essentially a non-starter"_**|
|⭐⭐⭐ Price the naive design|⭐⭐⭐ **_"2M writes a second of 100 bytes at on-demand pricing ($1.25 per million WRUs) would cost you over $200k a day."_** ▸ **A dollar figure ENDS an argument a QPS figure only starts.** ⭐⭐ **The reusable move: `writes/sec × 86,400 × unit price` — one line of arithmetic almost no candidate does**|
|DD1 Good — batch + geospatial DB|⭐ **Batch: aggregate over a short interval, write once ⇒ fewer transactions, better throughput, less lock contention.** ⭐⭐ **Index: a geospatial DB using QUAD-TREES — _"they partition the space into quadrants recursively"_** (`04a`). ⭐ **Postgres option: PostGIS gives geo types and functions _"without needing an additional database."_** ⚠ **The batch interval = a DELAY ⇒ stale locations ⇒ _"suboptimal driver matches"_**|
|⭐⭐ DD1 Great — Redis GEO|⭐⭐ **Under the hood: GEOHASHING encodes lat/long into a **52-bit integer score** in a SORTED SET, member = `driverId`.** `GEOADD` **to write,** `GEOSEARCH` **to query** (▹ **since 6.2, _"replaces and enhances"_ `GEORADIUS`**). ⭐ **Batching disappears — Redis takes the volume live, and each `GEOADD` OVERWRITES so you always have the latest position.** ⭐ **The one cleanup: offline drivers — purge anyone silent >30s, via a COMPANION timestamp sorted set.** ⚠ **Durability: RDB/AOF persistence, Sentinel failover —** ⭐⭐⭐ **but the real answer is _"we would only need [5 seconds] to recover and rebuild the state"_: the data HEALS ITSELF.** ▸ ⭐⭐ **Match the storage guarantee to the data's LIFETIME, not its importance**|
|⊕⭐⭐ 2M/sec needs ~20 Redis|⚠ **From `05r §5.5`: ~100k ops/sec per instance ⇒ 2M/sec needs ~20.** ⭐ **HI rejects DynamoDB on cost, moves to Redis, never shards it.** ⭐⭐ **§5.6's GEOGRAPHIC SHARDING is the fix — each region gets its own location Redis, dividing the 2M naturally, and proximity queries stay inside one shard.** ⭐ **Say it in DD1, not DD6**|
|⚠ DD2 — adaptive intervals|⚠⚠ **ONE approach, no ladder.** ▹ **Asked to see _"if they can intelligently reduce the number of pings while maintaining accuracy."_** ⭐⭐ **Adjust the interval on speed, direction, proximity to pending requests, and driver status — computed ON-DEVICE from its own sensors: stationary/slow ⇒ less often; fast or turning ⇒ more often.** ⚠ **Challenge: designing the algorithm well needs real testing**|
|⭐⭐⭐ Don't neglect the client (5th time)|⭐⭐⭐ **_"Many candidates get in a habit of drawing a small client box and moving on."_** ▹ **HI's other example: _"in the case of a file upload service, the client is responsible for chunking and compression."_** ⭐ **Your thread: `05h` (caches its own swipes) · `05k` (records its own activity) · `05o` (picks the ABR format) · `05s` (collects data for you) · `05u` (decides its ping rate).** ⭐⭐ **The deciding question: does the client know something the server doesn't? Here it has the accelerometer**|
|⭐⭐ DD3 — state it precisely|⭐ **TWO things: _"we only request one driver at a time for a given ride request AND that each driver only receives one ride request at a time"_**, with a **10-second** window. ⭐⭐⭐ **HI names the sibling: _"almost exactly the same as ensuring that a ticket is only sold once while being reserved for a specific amount of time at checkout"_ ⇒ `05e §5.1` with `driverId` for `seatId`**|
|⚠⚠ DD3 Bad — app-level lock|**each instance marks "locked", starts a timer, releases manually.** ⚠⚠ **No coordination — _"two instances might attempt to lock the same ride request simultaneously"_ · inconsistent state — an instance crashes mid-lock and _"other instances have no knowledge of this lock"_ ⇒ locked forever · worsens as you scale**|
|⚠⚠⚠ DD3 Good — lock in the DB|⭐ **use the DB's transactions; driver status `outstanding_request` → `accepted` / `available`.** ✅ **Coordination solved.** ⚠⚠⚠ **But the TIMEOUT IS STILL IN MEMORY: _"If the Ride Service crashes or is restarted, the timeout will be lost and the lock will remain indefinitely."_** ⭐⭐ **HI: _"a common issue with in-memory timeouts and why they should be avoided when possible."_** ▹ ⚠ **the cron patch _"works, but adds unnecessary complexity and introduces a delay"_**|
|⭐⭐⭐ DD3 Great — Redis lock + TTL|⭐⭐⭐ **Lock on `driverId`, TTL = the 10-second window.** **Acquire ⇒ nobody else can send to that driver. Accept ⇒ status `accepted`, lock released. No accept ⇒ ⭐⭐ the lock EXPIRES BY ITSELF.** ⭐⭐⭐ **Why that closes the gap: the TTL lives in REDIS, not the process — the service can crash and the lock still expires on time.** ▹ **Same lesson as `05t §5.1` and `05p §5.3`.** ⚠ **Now Redis availability is a correctness dependency —** ⭐⭐ **but _"locks are only held for 10 seconds, so the ephemerality of the data makes it easier to recover"_**|
|⚠ DD4 — two failure modes|**(1) surges overwhelm the service and horizontal scaling can't react fast enough (2) ⚠⚠ an instance crashes and its in-flight requests are LOST ⇒ _"riders waiting indefinitely for a match that will never come"_ — _"no built-in mechanism for request recovery or failover"_**|
|⭐⭐ DD4 Great — queue + scaling|⭐ **requests into a queue, FIFO consumption, scale on depth, ⭐ partition by REGION.** ⭐⭐⭐ **The Kafka detail: _"commit the offset… only AFTER we have successfully found a match"_ ⇒ a crashed matcher loses nothing, a new instance picks it up.** ▸ ⭐ **Same shape as `05p`'s delete-after-success and `05t`'s mark-after-provider.** ⚠ **Ops complexity ⇒ managed service (SQS, MSK, Confluent).** ⚠⚠ **FIFO = HEAD-OF-LINE BLOCKING — _"requests stuck behind a request taking a long time"_ ⇒ ⭐ PRIORITY queue ranked on proximity + rating**|
|⭐⭐ DD5 — the Temporal backstory|⭐⭐ **_"Human-in-the-loop processes are a big signal of when to use the Multi-Step Processes pattern. In fact, Uber is the original author of… Cadence which gave birth to… Temporal, built specifically for use-cases like this one."_** ▸ ⭐ **4th Temporal appearance (`05o` DAG, `05p` orchestrator, `05t` deliberately AVOIDED) and the first where it WINS**|
|DD5 Good — delay queue|⭐ **on send, also schedule a DELAYED message firing after 10s carrying the ride + the driver contacted; on processing, if still unassigned move to the next driver and schedule another.** ▹ **same `DelaySeconds` as `05p §5.1`.** ⚠⚠ **CANCELLATION is the hard part: _"if a driver accepts after the delayed message is already scheduled but before it's processed"_ you must not reassign · ⚠ needs careful coordination to avoid race conditions**|
|⭐⭐ DD5 Great — durable execution|⭐⭐ **model matching as a DURABLE WORKFLOW with built-in timeouts, retries and state _"in a way that survives service crashes and restarts"_** — ⭐ **state persisted, so a crash RESUMES where it stopped.** **Flow: send → 10s timeout → accept ⇒ done; decline/timeout ⇒ next driver; repeat until matched or exhausted.** ⚠ **New concepts, new tooling, another component to monitor —** ✅ ⭐ **but worth it _"especially for mission-critical systems… where dropped requests directly impact revenue"_**|
|⚠ DD6 — two things worth keeping|⚠⚠ **thinnest dive; HI: vertical scaling _"is hardly worth discussing… not practical for a system of this scale."_** ⭐⭐ **(1) GEOGRAPHIC SHARDING buys scale AND latency — _"it reduces latency by reducing the distance between the client and the server"_ — and applies to services, queue AND databases.** ⭐⭐⭐ **(2) _"The only time that we would need to scatter gather is when we are doing a proximity search on a BOUNDARY"_ — a rider at a city edge may have the nearest driver in the next shard**|
|⚠ A boilerplate slip in the levels|⚠ **HI's Senior bar says _"knowing how to use a search-optimized data store like Elasticsearch for event searching is essential."_** ▸ **There is no event searching anywhere in this problem** — ⭐ **it's copy-paste from another breakdown. Ignore it; don't go looking for where Elasticsearch fits**|
|⭐⭐⭐ The meta-lesson|⭐⭐⭐ **A timeout stored in process memory is not a timeout.** ▸ **DD3's whole ladder is about moving the expiry somewhere that outlives the process: a Redis TTL, a queue's visibility timeout, a persisted workflow.** ⭐ **Same failure in `05t §5.1` (in-process retry loop) — ▸ and the fix is always the same: let infrastructure own the clock**|
|Levels (one line)|**E4:** API + data model + functional HLD; see the need for a spatial index; land at least the GOOD lock · **E5:** fast HLD then depth on 2 of {location search, locking, queueing} with trade-offs · **Staff+:** depth in 3+ areas, and the interviewer leaves having learned something|

---

> 🔗 **HI source:** https://www.hellointerview.com/learn/system-design/problem-breakdowns/uber