# Activity Tracking App (Strava) — Problem Breakdown

> 📐 **Revision note (calc):** one storage chain, and it is the whole of DD2. **~100M activities/day × 365 = ~36.5B/year.** Per activity: **~100 bytes metadata** + the route — **30-min activity, a GPS point every ~3s = ~600 points × (8+8+8 bytes) ≈ 15KB.** ⇒ ⭐⭐ **15KB × 36.5B = 547.5TB/year.** ⭐ **HI's verdict is the point, not the number:** _"a good amount of data, but it's far from unmanageable."_ ⚠ **Two loose figures — don't memorise either:** **(1)** the **100M DAU** is never stated as a requirement (the NFR says **10M _concurrent activities_**, a different quantity); **(2)** _"a factor of 100x"_ fewer requests is really **360–600×** by HI's own 2–5s GPS intervals. ⭐ **What to carry: `points × 24 bytes = route size`, then `× activities/year`.**

> ⭐⭐ **TWO Pattern callouts — `Scaling Writes` →  and `Real-time Updates`.** Cross-refs: ⭐⭐ **the client as an active tier → `05b` Dropbox (HI names it explicitly) and `05h §5.3` Tinder** · **scaling writes → `03e`** · **polling vs WebSockets → `03a`** · ⭐⭐ **Redis ZSET leaderboard → `05i §5.2` (just covered — do NOT re-learn it here)** · **Redis → `02a`** · **Haversine → `04a`, applied in `05c`** · **sharding → `01f`** · **caching → `01e`** · **cold/archival storage → `01a`** · **CAP → `01h`** · **numbers → `01i`** · **API design, PATCH vs PUT, pagination → `01b`** · **Postgres → `02g`.** **Siblings: `05b` Dropbox (client does the work) · `05i` LeetCode (monolith + ZSET + polling-over-WebSockets) · `05g` FB News Feed (fan-out, which this file never addresses).**
> 
> **Calibration:** ⭐⭐.** ▸ **Every other breakdown adds machinery. This one removes it.** ⭐ **One realization in DD1 — let the phone record locally — simultaneously delivers the offline requirement, kills the write-scaling problem, and makes the live-stats requirement trivial.** ⚠ **Second file in a row where HI rejects microservices.** ⭐⭐ **Give it one pass. Then spend the time you saved on DD3, which is the only genuinely unfinished part of the write-up — and the best place to score.**
> 
> - ⭐⭐ **What actually scores:**
>     - **(a)** ⭐⭐ **Recognising the client can record locally** (§5.1) — HI: _"an impactful realization that **re-shapes the entire system**."_ ⚠ **HI says most candidates miss it:** _"most of the time I ask this question, candidates overlook this optimization."_ ▸ **Say it in the HLD, not the deep dive, and you're ahead of the median candidate.**
>     - **(b)** ⭐⭐ **The status-event log instead of a `startTimeStamp`** (§4.1) — **the one genuinely clever modelling trick in the HLD**, and it's five lines.
>     - **(c)** ⭐ **Doing the storage math, then shard-by-`completionTime` + hot/warm/cold tiering** (§5.2).
>     - **(d)** ⭐⭐ **Rejecting WebSockets with 2 reasons** (§5.3) — **predictable cadence** and **precision isn't critical.** ▹ **Third file running where this is the scored move** (`05i` ×2, `05g`).
>     - **(e)** ⭐ **Smart buffering — intentional lag for smooth animation** (§5.3). ▸ **Nothing else in the series has this. Cheap to say, very memorable.**
>     - **(f)** ⭐ **"It doesn't really matter" on the database choice** (§5.2) — ⚠ **a calibration answer, and knowing when it's the right one.**
>     - **(g)** ⭐ **Monolith, justified** — _"we offloaded so much of the write load to the client that we don't have a ton for our backend to do."_
> - ⭐ **Transferable primitives:**
>     - ⭐⭐ **The client is a tier, not a renderer.** Sensors, local storage, CPU, buffering. ▸ **HI's own list: _"for systems like Strava, Dropbox, or Spotify, the client often plays a critical role."_** ⭐ **Extends `05h`'s client-side swipe cache from an optimisation to the primary architecture.**
>     - ⭐⭐ **Model state as an event log when you need a _derived duration_, not a snapshot.** ▸ **Reusable for SLA/uptime timers, billable hours, shift tracking, pause-able anything.**
>     - ⭐⭐ **A predictable update cadence turns push into polling.** ▸ **If you know when the next update arrives, you don't need a socket to be told.**
>     - ⭐ **Intentional lag buys smoothness.** ▸ **Buffer deliberately so the UI animates instead of jumping. Reusable for any live-tracking map.**
>     - ⭐ **Shard on the dimension your queries filter by** — `completionTime`, because queries want recent (`01f`).
>     - ⭐ **Tier storage by age**, not by importance: hot → warm (3–12mo) → cold archival (>1yr).
> - ⭐ **Re-run (cross-ref, NOT re-explained):** ⭐⭐ **Redis sorted sets — `05i §5.2` covers the structure, `ZADD`/`ZRANGE`, and why one score per member forces a composite** · **Haversine (`04a`, `05c`)** · **client-as-tier (`05b`, `05h §5.3`)** · **polling vs WebSockets (`03a`, `05i §5.2`)** · **offset pagination + `Partial<>` (`01b`, `05i §3.1`)** · **sharding (`01f`)** · **cache-aside (`01e`)**. **Genuinely new:** ⭐⭐ **offline-first local buffer with a persist cadence (and the "lose at most 10s" guarantee)** · ⭐⭐ **the status-event time log** · ⭐ **`ZINCRBY` for cumulative scores** (vs `05i`'s recompute-and-`ZADD`) · ⭐ **country-sharded ZSET keys** · ⚠ **time-range filtering via ZSET-of-timestamps + HASH (and why it's broken)** · ⭐⭐ **smart buffering / intentional lag** · **data tiering** · ⭐ **"the DB choice doesn't matter" as a legitimate answer.**

---

## 0 · Understanding the problem

🏃‍♂️🚴‍♀️ **What is [Strava](https://www.strava.com/)?**

Strava is a **fitness tracking application** that lets users **record and share their physical activities**, primarily **running and cycling**, with their network. It provides **detailed analytics on performance and routes**, and allows **social interactions** among users.

- ⭐ **HI narrows scope immediately:** _"While Strava supports a wide variety of activities, we'll focus on **running and cycling** for this question."_ ▸ **Do the same out loud — it's a free scoping point.**

---

## 1 · Requirements

### 1.1 Functional (what it does)

1. ⭐ **Start, pause, stop, and save runs and rides.**
2. ⭐⭐ **While active, view activity data — route, distance, and time.**
3. ⭐ **View details of completed activities — their own and their friends'.**

⚠ **Below the line (out of scope):** adding/deleting friends (friend management) · authentication and authorization · commenting or liking runs.

### 1.2 Non-functional (how it behaves)

1. ⭐ **Highly available — availability >> consistency** (`01h`). ▹ **Note the `>>`, not `>`.**
2. ⭐⭐ **Must function in remote areas with no network connectivity.** ▸ **This is the hard requirement, and it's the one that reshapes the design.**
3. ⭐ **Accurate, up-to-date _local_ statistics during the run/ride.** ▹ ⭐ **The word "local" is doing work here** — it's a client-side latency requirement, not a server one.
4. ⭐ **Scale to 10 million concurrent activities.**

⚠ **Below the line:** GDPR / data-privacy compliance · advanced security measures.

### 1.3 ⭐⭐ The design driver — the hard requirement hands you the scaling answer for free

▸ **Unlike every other problem in the series, the NFRs are not in tension. They all point the same way: off the server.**

|NFR|Points toward|
|---|---|
|**No network connectivity**|⭐⭐ **record on the device**|
|**Up-to-date _local_ stats**|⭐⭐ **compute on the device** (synchronous, no round trip)|
|**10M concurrent activities**|⭐ **…which the first two have already solved** — one write per activity instead of hundreds|
|**Availability >> consistency**|⭐ **sync late and sync loosely; nothing here needs a transaction**|

- ⭐⭐ **So the shape of the answer: the "scaling" deep dive is mostly already won by the "offline" deep dive.** ▸ **HI's word for it is _"re-shapes the entire system."_** ⭐ **Say that connection explicitly — it's the single highest-value sentence in this interview.**
- ⚠⚠ **And the thing to watch: DD3 (realtime sharing) puts the write load straight back.** ▸ **See the ⊕ block in §5.3 — HI never reconciles it, and spotting it is the strongest move available in this question.**

### 1.4 Planning the approach

▸ **HI: _"start with the simplest possible system that satisfies the functional requirements and then layer on complexity to satisfy the non-functional requirements during your deep dives."_**

> ▹ ⭐ **HI answers the obvious objection, and the answer is nuanced — worth knowing both halves.**
> 
> - **Q: _"If I already know the more complex design, should I still start simple?"_**
> - ⭐ **If you have a well-thought-out sophisticated solution, _"it's perfectly acceptable to present it during the high-level design."_**
> - ⚠ **But: _"Going deep too early can result in you running out of time before you've met all the functional requirements and, thus, not answered the question."_**
> 
> ■ **— end of insert · HI write-up resumes below —**

---

## 2 · Core Entities

- **User** — the person using the app; profile information and settings.
- ⭐ **Activity** — one run or ride: **type (run/ride), start time, end time, route data (GPS coordinates), distance, duration.**
- **Route** — **a collection of GPS coordinates recorded during the activity.** ▹ ⭐ **HI's own hedge: _"this could also just be a field on the Activity entity."_**
- **Friend** — a connection between users for sharing. ▹ ⚠ **Friend management is out of scope, _"but the concept is necessary for sharing."_**

▹ ⭐ **Contrast `05i` LeetCode, where HI deliberately OMITTED User as _"implied."_** ⚠ **Here it's listed.** ▸ **Not an inconsistency — in LeetCode nothing is done _to_ a user; here activities and friendships both hang off one.**

---

## 3 · API

▸ ⭐ **HI's framing: endpoints usually map 1:1 to functional requirements, _"but there are times when multiple endpoints are needed… or where a single endpoint meets the needs of multiple functional requirements (as is the case with our activity state update endpoint below)."_**

### 3.1 Create an activity

```
POST /activities -> Activity
{ type: "RUN" | "RIDE" }
```

### 3.2 ⭐ Update activity state — one endpoint, three jobs

```
PATCH /activities/:activityId -> Activity
{ state: "STARTED" | "PAUSED" }
```

```
PATCH /activities/:activityId -> Activity
{ state: "COMPLETE" }        // ⭐ saving AND sharing are the same call
```

- ⭐⭐ **Sharing needs no endpoint.** HI: it _"happens automatically when an activity is saved"_, so **`COMPLETE` on the existing state endpoint covers FR #3's sharing half.** ▸ **Say this — reusing one endpoint across requirements is exactly the point HI made above.**

> ▹ **PATCH vs PUT** — **PATCH sends only changed fields, PUT the whole resource.** ⭐ **HI: _"functionally equivalent"_ in an interview, but some are _"RESTful API hawks"_** ⇒ **use PATCH, have the one-liner, move on.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 3.3 Add a location to the route

```
POST /activities/:activityId/routes -> Activity
{ location: GPSCoordinate }
```

- ⚠⚠ ⭐⭐ **This endpoint largely DISAPPEARS in §5.1.** ▸ **Once the client records locally, you don't call this every few seconds — you sync in bulk at the end.** ⭐ **Flag it when you draw it:** _"I'll define this now, but I expect to batch or drop it once we handle offline."_

### 3.4 List and detail

```
GET /activities?mode={USER|FRIENDS}&page={page}&pageSize={pageSize} -> Partial<Activity>[]
GET /activities/:activityId -> Activity
```

- ⭐ **Two-step read, same as `05i`:** the list returns **basic info (distance, duration, date) + the `activityId`**; **clicking one fires a second detailed GET.**
- ▹ **`Partial<Activity>` is TypeScript shorthand for a subset of fields, _"done to limit the amount of data we send over the network."_** ⭐ **HI: _"you can use whatever notation you'd like. This is just a personal preference."_**

---

## 4 · High-Level Design

### 4.1) Start, pause, stop, and save

```
Client ──► Activity Server ──► Database
                                Activity
                                  id · type: RUN | BIKE · startTime
                                  status · statusUpdateEvents: JSON · …
```

- **Client App** — users interact through a mobile app.
- **Activity Service** — handles create and update requests.
- **Database** — stores activity info including route, distance, time.

**The flow:**

1. **"Start Activity"** ⇒ `POST /activities` specifying run or ride.
2. **Activity Service creates the activity** and returns the object to the client.
3. **Pause/resume** ⇒ `PATCH /activities/:activityId` with the new state.
4. **"Save Activity"** ⇒ `PATCH` with `state: "COMPLETE"`.

#### ⭐⭐ The modelling trick — how to handle elapsed time across pauses

- ⚠ **The naive approach HI rejects:** store a `startTimeStamp`, and on stop compute `now − startTimeStamp`. ▸ **Breaks on pause — _"the `startTimeStamp` would remain unchanged and the elapsed time would continue to increment, which would be inaccurate."_**
- ⭐⭐ **The fix: keep a log of (status, timestamp) pairs.**

```json
[
    { "status": "STARTED", "timestamp": "2021-01-01T00:00:00Z" },
    { "status": "PAUSED",  "timestamp": "2021-01-01T00:10:00Z" },
    { "status": "RESUMED", "timestamp": "2021-01-01T00:15:00Z" },
    { "status": "STOPPED", "timestamp": "2021-01-01T00:20:00Z" }
]
```

- ⭐ **On stop, sum the durations between pairs, excluding pauses** ⇒ **10 min + 5 min = 15 minutes elapsed** (wall clock was 20).
- ⭐⭐ **And the justification that makes it not-over-engineering — this is the line to say:** _"This may seem like overkill for our simple requirement, but it would allow for natural expansions into a feature that shows athletes **when they were paused and for how long**, as well as a breakdown of **'total time' vs 'active time'**."_

> ⊕ ⭐ **(mine, not HI) — why this generalises, and the name for it.**
> 
> - ▸ **This is event sourcing in miniature:** **store the transitions, derive the aggregate.** ⭐ **The rule: when a value is a _duration_ rather than a _quantity_, store the events and compute it — never store the running total.**
> - ⭐ **Reusable for:** SLA / uptime clocks · billable hours · shift and break tracking · video watch-time · anything pause-able.
> - ▹ ⚠ **The cost to name if asked:** the log grows per pause, and every read of "elapsed" is a fold over it. ⭐ **Fine here (a handful of events per activity); cache the computed total on `COMPLETE`.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 4.2) View activity data while running or cycling

▸ **The important half is accurately tracking distance and route.** ⭐ **Record GPS coordinates at a constant interval** and **compute distance with the Haversine formula** (`04a` — ▹ **same formula as `05c` Yelp**).

```
Client ──► Activity Server ──► Database
                                Activity   id (PK) · type · startTime
                                           status · statusUpdateEvents: JSON
                                GPS        routeId · distance
                                Route      activityId (PK) · latitude
                                           longitude · timestamp
```

**The flow:**

1. ⭐ **Client records GPS at a constant interval** — **~2 seconds for a bike ride, ~5 seconds for a run.**
2. **Client sends the coordinates to `/activities/:activityId`.**
3. **Activity Service writes the new coordinate + timestamp to the Route table.**
4. ⭐ **Distance updated by Haversine between the new coordinate and the previous one.**

▹ **The platform APIs, for colour only — iOS: Core Location / `CLLocationManager`, `startUpdatingLocation()`. Android: Google Location Services / `FusedLocationProviderClient`, `requestLocationUpdates()`.**

- ⭐⭐ **HI's explicit calibration, and it's reassuring:** _"You absolutely do not need to know the libraries and frameworks to use here… The point of this question is to test your knowledge of **system design, not mobile development**."_ ▸ **Know only that modern phones have GPS and apps use the platform APIs for it.**

> ⊕ ⚠⚠ **(mine, not HI) — HI's Route schema cannot be right.**
> 
> - ⚠ **The diagram says `Route — activityId (PK)`.** ▸ **But a 30-minute activity has ~600 route rows, all with the same `activityId`.** ⭐⭐ **`activityId` alone cannot be the primary key — the second GPS point would collide.**
> - ⭐ **The fix: a composite key `(activityId, timestamp)`**, or `(activityId, seq)` if two points can share a timestamp. ▸ **`activityId` is the partition/sort prefix, which is what you want anyway — the whole route is read together.**
> - ▹ ⚠ **The `GPS — routeId · distance` box is also ambiguous** — it reads as a third table but is almost certainly two fields (`routeId`, `distance`) on **Activity.** ⭐ **Draw them on Activity and say so.**
> - ⭐ **Worth one sentence in the room.** It's the kind of concrete catch that signals you actually read your own data model.
> 
> ■ **— end of insert · HI write-up resumes below —**

> ⭐⭐ **HI's deliberate setup — and you should pre-empt it.**
> 
> - _"Astute readers are likely already yelling at their screen as they've realized that **we don't need to send these updates to the server**, instead handling the logic locally on the client. You're right. We'll get into this in the deep dive."_
> - ⚠ **And the tell:** _"The reality is **most of the time I ask this question, candidates overlook this optimization** and we get to it later in the interview."_
> - ⭐⭐ **So: say it HERE, in the HLD.** _"I'll draw the server-write version, but note the client can record this locally — which I think is the real design, and I'll come back to it."_ ▸ **That one sentence puts you ahead of the median candidate on this question.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 4.3) View completed activities — own and friends'

▸ **Nothing new is needed** — activities are already in the DB; `COMPLETE` is just a state. ⭐ **Query on state + the `mode` param with a simple `WHERE` clause.**

```sql
-- mode = USER
SELECT * FROM activities
WHERE state = "COMPLETE" AND userId = :userId
LIMIT :pageSize OFFSET (:page - 1) * :pageSize

-- mode = FRIENDS
SELECT * FROM activities
WHERE state = "COMPLETE"
  AND userId IN (SELECT friendId FROM friends WHERE userId = :userId)
LIMIT :pageSize OFFSET (:page - 1) * :pageSize
```

- ⭐⭐ **The friends-table design, and it's a tidy three-part answer:**
    - **Two columns: `userId`, `friendId`.**
    - ⭐ **Relationships are bi-directional, so each friendship writes TWO rows** — `(A,B)` and `(B,A)`.
    - ⭐ **A composite primary key on `(userId, friendId)`** plus **an index on `userId`** ⇒ **efficient lookup of a user's friends while preventing duplicate friendships.**
- ⭐ **Map rendering:** pass the coordinate array to the **Google Maps API**, which **draws a line connecting all the points.**

```
Client ──► Activity Server ──► Database
                                Activity · GPS · Route
                                Friend     user1 (PK) · user2 · createdAt
```

▹ ⚠ **Note the schema drift: the prose says the friends table is `(userId, friendId)`, the diagram says `Friend — user1 (PK) · user2 · createdAt`.** ⭐ **Use the prose version; it's the one with the reasoning attached.**

> ⊕ ▹ **(mine) — the one thing to be ready for if pushed on the FRIENDS query.**
> 
> - ⚠ **`userId IN (subquery)` + `OFFSET` is the classic fan-out-on-read** (`03d`, and the whole subject of `05f`/`05g`). ⭐ **It's fine here and HI is right to leave it** — read throughput is genuinely low, and a user has tens of friends, not millions of followers.
> - ⭐ **But know the trigger for changing your mind:** _if_ a user could follow thousands of athletes, or the activity feed needed ranking, **this becomes precompute-on-write** (`05f §5.1`). ▹ **Say "I'd keep it fan-out-on-read at this scale" and name the condition that would flip it.**
> 
> ■ **— end of insert · HI write-up resumes below —**

---

## 5 · Deep Dives

▹ **HI: _"This list of deep dives is… not exhaustive. It is instead an accumulation of some of the most popular directions I've seen this interview take."_**

### 1) ⭐⭐ How can we support tracking activities while offline?

▸ **Many athletes work out in remote areas with no connectivity and still want tracking.** ⭐⭐ **HI: _"This brings us to an impactful realization that **re-shapes the entire system**."_**

#### ⭐⭐ The key insight

> ⭐⭐ **_"**so long as we don't support realtime-sharing**… record activity data locally, directly on the client's device and only sync… when the activity completes and/or the user is back online."_**

▸ ⚠⚠ **That opening clause is what DD3 revokes.**

- ⭐⭐ **It solves three problems at once — list all three, this is the scoring moment:**
    1. ⭐ **Track activities without worrying about network reliability on the client side.**
    2. ⭐⭐ **Even on a good connection, save network bandwidth** by not pinging location updates every few seconds — **only on completion or pause.**
    3. ⭐ **Accurate, up-to-date stats are easy** — _"it all happens synchronously on their device."_

> ⭐⭐ **HI's framing of the general lesson — the most quotable passage in the file.**
> 
> - _"This question highlights an important, often overlooked aspect of system design: **the client as an active participant**. Modern smartphones and browsers have access to a wide variety of **sensors, substantial memory and processing power, and significant local storage**. Many candidates overlook the client's capabilities, focusing solely on server-side solutions. However, for systems like **Strava, Dropbox, or Spotify**, the client often plays a critical role in the overall design, enabling **offline functionality, reducing server load, and improving user experience**."_
> - ▹ ⭐ **Note HI names `05b` Dropbox.** ⭐⭐ **And compare `05h §5.3` Tinder, where the client cached recent swipes.** ▸ **Difference in degree: in Tinder the client was an optimisation; here it is the primary architecture.**
> 
> ■ **— end of insert · HI write-up resumes below —**

#### ⭐ How it works in practice — the seven steps

1. **On-device location services record GPS at a constant interval** (as in §4.2).
2. ⭐ **Record the events locally in an in-memory buffer** — _"an array of GPS coordinate and timestamp pairs."_
3. ⭐⭐ **Periodically persist the buffer to local storage every ~10 seconds**, to survive device shutdown or battery depletion.
    - ▹ **iOS: Core Data for larger structured datasets, UserDefaults for small key-value. Android: Room for structured, SharedPreferences for small.**
4. ⭐ **On app reopen or activity resume, check local storage first** and **load saved data into the in-memory buffer** before recording new data.
5. ⭐ **On completion + online, send all accumulated data in a single request.** ⚠ **_"For very long activities, we might need to implement a chunking strategy."_**
6. ⭐ **Optionally, background sync** that uploads periodically when a connection appears, **even before the activity completes** — _"this balances efficiency with data durability."_
7. ⭐ **On confirmation the data is saved remotely, delete the local buffer.**

- ⭐⭐ **The guarantee: _"we'll only lose a maximum of 10 seconds of activity data."_**
- ⚠ ⭐ **And the cost to name in the same breath:** _"it's important to **balance the frequency of GPS tracking and data persistence with battery life** considerations."_ ▸ **Mentioning battery unprompted reads as mobile-aware.**

▹ **HI's scope note: _"For larger datasets, using a local SQLite database might be more appropriate than options like UserDefaults or SharedPreferences. But the details of this are reserved more for **Mobile System Design** interviews, not a general SWE interview."_**

> ⭐⭐ **Why there are still no microservices — HI addresses it head-on, and the reasoning is reusable.**
> 
> - ⭐ **No microservices — and no hard-and-fast rule:** _"**we offloaded so much of the write load to the client that we don't have a ton for our backend to do**… no significant **read/write skew across different paths**."_
> - ▹ **Counter-argument dismissed: one codebase is harder to grow a team on — _"if Meta can famously manage it, so can we."_**
> - ⭐⭐ **The reusable test: is there read/write skew across paths?** ▸ **`05h §4.3` is the one problem where there was — split only when write pattern + data volume + ideal engine ALL differ.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 2) How can we scale to support 10 million concurrent activities? ⭐

▸ ⭐⭐ **DD1 already won this one:** _"**scaling our backend became pretty easy**"_ — **requests cut by a claimed 100x, since data goes up once per activity.**

#### 📐 The storage math

- **~100M DAU × 1 activity/day = ~100M new activities/day** ⇒ **~36,500M ≈ 36.5B activities/year.**
- **Metadata** — status, userID, start/end time ⇒ **~100 bytes per activity.** ▹ **cheap.**
- ⭐ **The route is the expensive part.** **30-min average activity, a GPS point every ~3s ⇒ ~600 points.** Each row is **latitude + longitude + timestamp = (8 + 8 + 8) bytes.**
    - **24 bytes × 600 = ~15KB per activity.**
- ⭐⭐ **15KB × 36.5B = 547.5TB of data each year.**
- ⭐ **HI's verdict matters more than the number:** _"This is a good amount of data, but it's **far from unmanageable**."_

#### ⭐ The three things to do about it

1. ⭐⭐ **Shard the database** across instances — **shard by the time the activity was completed**, _"since the majority of our queries will want to see recent activities"_ (`01f`).
2. ⭐⭐ **Data tiering** — _"The chances that someone wants to view a run from several years ago are pretty low."_
    - **Hot (recent)** → fast, expensive storage.
    - **Warm (3–12 months)** → slower, cheaper storage.
    - **Cold (>1 year)** → archival storage like **S3** (`01a`).
3. ⭐ **Caching, but explicitly deprioritised** (`01e`) — _"This would **not be a priority for me**, as read throughput should be pretty low, but it's **the first thing we would do if load times become unacceptable**."_ ▹ ⭐ **Note the shape: name the fix, rank it last, give the trigger that would promote it.**

> ⭐ **Pattern: Scaling Writes** (`03e`) — **callout #1 of 2.** ▹ **All three fixes above are the standard write-scaling moves; go read `03e`.**
> 
> ■ **— end of insert · HI write-up resumes below —**

#### ⭐ "What database should we choose?" — HI's hot take

> ⭐⭐ _"**Hot take. It doesn't really matter.** This is a large but **totally manageable** amount of data; there is **no crazy read or write throughput**, and data is **relational but not heavily so**. Realistically, **all popular major database technologies would work great here**."_

- ⭐ **And the service, same logic:** read and write throughput are both low, so **no microservices** — _"when we run into issues with memory, cpu, or network limitation we can just **scale the service horizontally**."_
- ⭐⭐ **Why this is worth rehearsing: "it doesn't matter" is a legitimate answer, but only with the three reasons attached.** ▸ **Volume manageable · throughput unremarkable · relational-but-not-heavily.** ⚠ **Without them it sounds like you don't know the options.**

> ⊕ ⚠ **(mine) — two figures in this dive not to memorise.**
> 
> - ⚠ **The 100M DAU appears from nowhere.** ▸ **NFR #4 says 10 million _concurrent activities_, which is a different quantity entirely** (concurrency, not daily volume). ⭐ **HI never derives one from the other. Use 100M for the storage math since that's what HI does, but know it's an unstated assumption.**
> - ⚠ **"A factor of 100x" is understated by HI's own numbers.** ▸ **A 30-min activity at 2–5s intervals is 360–900 location posts collapsing to 1 sync.** ⭐ **The real figure is 360–600×.** ▹ **Same class as `05i`'s "a million records" — rhetorical, not computed.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 3) ⭐⭐ How can we support realtime sharing of activities with friends?

▸ ⭐ **A common follow-up: friends watch mid-run, stats and routes updating live.** ▹ **HI: _"closer to other popular realtime systems like FB Live Comments or WhatsApp."_**

- ⭐⭐ **The change: reintroduce periodic server updates during activities.** ▸ **_"While maintaining local device logic for user-facing data"_, send location updates to the server **every 2–5 seconds.** ⭐ **The server persists them and broadcasts to the user's friends.**
- ▹ ⭐ **Note what survives: the client still computes the athlete's own stats locally.** ▸ **DD1 isn't reverted for the athlete — only for the observers.**

#### ⭐⭐ Why polling, not WebSockets

- ⚠ **WebSocket / SSE + pub-sub would work — HI calls it over-engineering.** ▸ **Name it, then reject it.**
- ⭐⭐ **The two reasons — name both:**
    1. ⭐⭐ **Updates are predictable** — **the next one lands in 2–5s.** ▸ **Unlike Messenger or Live Comments, so you don't need a socket to be told.**
    2. ⭐ **Precision isn't critical** — **a few seconds' delay is fine for a spectator.**
- ⭐ **Implementation: friends poll at the athlete's post interval, offset a few seconds for latency.**

> ⭐ **Pattern: Real-time Updates** (`03a`) — **callout #2 of 2.**
> 
> - ⭐⭐ HI: _"One of the most important things to understand about the realtime updates pattern is **when it's not necessary**! In our pattern breakdown we give you a simple flow chart that you can follow to determine which protocols to use."_
> - ▹ **Go read that flow chart in `03a` — it's the generalisation of this whole dive.**
> 
> ■ **— end of insert · HI write-up resumes below —**

#### ⭐ Smart buffering — intentional lag

- ⭐⭐ **Deliberately lag the displayed location by one or two update intervals (~5–10 seconds).**
- ⭐ **Why:** _"we can create a **smoother, more continuous animation** of the athlete's movement. This eliminates the **jarring effect of sudden position changes**… the athlete will appear to be in constant motion, creating a more engaging, **'live-stream-like' experience**."_
- ⭐ **And the second benefit:** _"The intentional lag also helps **compensate for any network latency**, ensuring a more consistent experience across different network conditions."_
- ▸ **The trade stated plainly: _"this approach sacrifices absolute real-time accuracy"_ for _"a significantly improved visual experience."_**
- ⭐⭐ **Why it's worth remembering: it's the only place in the series where the right answer is to make the system _less_ fresh on purpose.**

> ⊕ ⚠⚠ **(mine, not HI) — DD3 reintroduces the load DD1 removed, and HI never re-costs it. The strongest thing to raise in this question.**
> 
> - ⚠ **Frame it as an EXTENSION not re-costed, not a self-contradiction.** ▸ **DD1's premise was _"so long as we don't support realtime-sharing."_ DD3 turns it on and the premise is gone — but HI never revisits DD2's numbers.** ⭐ **Say: _"turning this on reintroduces the write load DD1 removed — let me re-cost it."_**
> - 📐 **Write side:** **10M concurrent × 1 update per 2–5s** ⇒ ⚠⚠ **~2–5M writes/sec vs DD2's ~1,150/sec.** ⭐ **~2,000–4,000×**, and HI says only that updates _"will be persisted in the database and broadcast."_
> - ⚠ **Read side is worse and HI never mentions fan-out at all.** ▸ **Every friend of every live athlete polls every 2–5s** ⇒ **at 50 friends, ~100M+ polls/sec** — **`05g`'s problem, unaddressed.**
> 
> **⭐⭐ The fix — four moves, and the first is a product change, not an engineering one:**
> 
> 1. ⭐⭐ **Make live sharing OPT-IN per activity.** ▸ **Ask at start: share, or private?** ⭐ **Only shared activities stream. The multiplier becomes a fraction of 10M, not 10M** — **this is the actual scaling answer.** ▹ ⭐⭐ **Same thread as `05e` (virtual waiting queue) and `05g` (the 5,000-friend cap): ask whether the PRODUCT can change before engineering around its tail.**
> 2. ⭐⭐ **Live positions → Redis, short TTL. NOT the primary DB.** ▸ **The authoritative route still arrives in one bulk sync at the end.** ⭐ **Redis decides, the durable store remembers** — ▹ **same two-layer shape as `05e §5.1`, `05h §5.1`, `05i §5.2`.**
> 3. ⭐⭐ **One cached payload per athlete; all their friends poll the same key.** ▸ **One Redis read per poll, ZERO per-friend work.** ⭐ **This is what kills the fan-out, and it's the half most candidates forget.**
> 4. ⭐⭐ **Connectivity DEGRADES the feature — it does not gate it.** ⚠⚠ **Don't hide the share option for "remote areas" — you cannot know at start time.** ▸ **Signal is a property of the whole route, not the start: full bars in town, nothing in the valley 20 minutes later, and the user already opted in.** ⭐ **So: offer it always, buffer locally on drop, upload on reconnect, friends see a lag or a gap.** ▸ **Reuses DD1's buffer — no new machinery.**
> 
> ⚠ ⭐ **Keep the two syncs separate in your head:**
> 
> |Sync|Cadence|For whom|Purpose|
> |---|---|---|---|
> |**Durability**|occasional, batched, whenever a connection appears|⭐ **every activity**|don't lose data|
> |**Live sharing**|⭐ **every 2–5s**|⚠ **opted-in activities only**|spectators|
> 
> - ⚠⚠ **Syncing EVERYONE at 2–5s "for durability" quietly rebuilds the load you just removed.** ⭐ **That conflation is the trap.**
> - ⭐⭐ **The four-sentence answer:** _"Live sharing is opt-in per activity, so the multiplier is a fraction of concurrent activities. Live positions go to Redis with a short TTL, not the primary DB — the authoritative route still arrives in one bulk sync at the end. Friends poll one cached payload per athlete, so fan-out costs nothing. And if the connection drops mid-activity it degrades: buffer locally, upload on reconnect, friends see a gap."_
> 
> ■ **— end of insert · HI write-up resumes below —**

### 4) How can we expose a leaderboard of top athletes? ⭐

▸ **A natural extension: top athletes by activity type and distance, filterable by country, region, city.**

⚠⚠ **Rung labels below are mine — see the handover note.** ⭐⭐ **And read this dive against `05i §5.2`, which already covers what a sorted set is. Only the three new things matter here: `ZINCRBY`, country-sharded keys, and time-range filtering.**

#### ⚠ Bad Solution — aggregate on read

- **Approach:** query all activities, **group by user, sum the distance.**

```sql
SELECT u.name, SUM(a.distance) as total_distance
FROM activities a
JOIN users u ON a.userId = u.userId
WHERE a.state = "COMPLETE" AND a.type = "RUN"
GROUP BY u.userId
ORDER BY total_distance DESC
```

- ⚠ **Challenges:**
    - ⭐ **_"this query will be pretty slow given it is running an aggregation over millions of activities."_**
    - **Query performance degrades rapidly as activities grow** — **scan and aggregate millions of records per leaderboard request** ⇒ **high latency, increased DB load.**
    - ⭐ **_"this method doesn't account for the dynamic nature of leaderboards, where rankings can change frequently as new activities are logged."_**

**Why climb:** the same aggregate is recomputed for every viewer. Compute it once.

#### Good Solution — periodic aggregation

- **Approach:** ⭐ **a separate leaderboard table of pre-calculated per-user totals**, refreshed by **a background job at regular intervals (e.g. daily).** ▸ **The query becomes `SELECT … ORDER BY total_distance`.**
    - ▹ **The table HI draws: `Leaderboard — user · distance · activity · location · completionDate`.**
- ⚠ **Challenges:**
    - ⭐ **It introduces eventual consistency** — _"The leaderboard won't reflect real-time changes, potentially leading to **user confusion if their latest activity isn't immediately reflected** in their ranking."_
    - ⭐⭐ **Picking the interval is the trap:** _"too frequent updates could strain system resources, while infrequent updates lead to stale data."_ ▹ **Same tension as `05h §5.2`'s stale feeds — and the same fix applies: make it a tunable, not a constant.**

**Why climb:** a batch job is either stale or expensive. Update the ranking incrementally, on write.

#### ⭐ Great Solution — Redis sorted sets

- **Approach:** ⭐ **a ZSET with user IDs as members and total distances as scores** (`02a`, and **`05i §5.2` for the structure**). ⭐⭐ **On each new activity, INCREMENT the user's score.** **Query = top N members.**

```python
# Add an activity to the leaderboard (increment user's total distance)
redis.zincrby(f"leaderboard:run:global", distance, user_id)
redis.zincrby(f"leaderboard:run:USA",    distance, user_id)

# Query the leaderboard (get top users by total distance)
redis.zrange(f"leaderboard:run:global", 0, -1, desc=True, withscores=True)
```

- ⭐⭐ **New vs `05i`: `ZINCRBY`, not `ZADD`.** ▸ **`05i` recomputed a composite score and overwrote it; here the score is a running total, so you add to it in place.** ⭐ **Rule: `ZINCRBY` for cumulative metrics, `ZADD` for recomputed ones.**
- ⭐⭐ **Country filtering — one ZSET per country:**
    - **Separate sorted sets per country** — `leaderboard:run:USA`, `leaderboard:run:Canada`, …
    - ⭐ **Each activity updates BOTH the global and the country-specific set.**
    - **Querying a country board just means picking the right key.**
- ⭐ **Time-range filtering — a ZSET of timestamps plus a HASH per activity:**
    - **ZSET entry:** activity ID as member, **timestamp as the score.**
    - **HASH per activity:** fields for **user ID and distance.**
    - **To query a range: `ZRANGEBYSCORE` for the activity IDs, fetch each one's hash, aggregate distances by user in memory, sort.**

```python
# When logging a new activity
activity_id = generate_unique_id()
redis.zadd("activities:timestamps", {activity_id: timestamp})
redis.hset(f"activity:{activity_id}", mapping={"user_id": user_id, "distance": distance})

# Querying the leaderboard for last 24 hours
now = current_timestamp()
day_ago = now - 24*60*60
activity_ids = redis.zrangebyscore("activities:timestamps", day_ago, now)

user_distances = {}
for activity_id in activity_ids:
    activity_data = redis.hgetall(f"activity:{activity_id}")
    user_id  = activity_data["user_id"]
    distance = float(activity_data["distance"])
    user_distances[user_id] = user_distances.get(user_id, 0) + distance

leaderboard = sorted(user_distances.items(), key=lambda x: x[1], reverse=True)
```

- ⭐ **HI adds: _"We can cache the results with a short TTL to limit the in-memory aggregation while still ensuring freshness."_**
- ⚠ **Challenges:**
    - ⭐⭐ **Consistency between Redis and the primary database** — _"We need to implement a robust system to handle **failures and retries** when updating Redis."_
    - ⭐⭐ **Redis memory limits** — _"storing complete leaderboard data for **all possible combinations of activity types, time ranges, and geographical filters** could consume significant memory."_
    - ⭐ **The mitigation:** _"keep only the **most frequently accessed** leaderboards in Redis and **calculate less common ones on-demand**."_ ▹ **Same shape as `05h §5.2`'s "warm caches only for recently-active users."**

> ⊕ ⚠⚠ **(mine, not HI) — three problems with HI's code. The second and third are real.**
> 
> **1. ⚠ `zrange(key, 0, -1)` returns the ENTIRE sorted set.** ▸ The prose directly above says _"retrieve the **top N** members."_ ⭐ **`0, -1` is every member — for a global board that's every athlete on Strava.** ▸ **Should be `redis.zrange(key, 0, N-1, desc=True, withscores=True)`.** ▹ ⚠ **Same prose-vs-code mismatch as `05i`'s `MIN`/`MAX` bug.**
> 
> **2. ⚠⚠ The time-range code is O(activities in range) with a round trip each.** ▸ **At HI's own 100M activities/day, a global 24-hour board means ~100M `HGETALL` calls in a Python loop** — ⭐⭐ **presented as the _"more scalable and real-time"_ solution.** **It is neither.**
> 
> - ⭐ **Minimum fix: pipeline the hash reads, or restructure as `HMGET`** — removes the round trips, **not the O(n) aggregation.**
> - ⭐⭐ **Real fix: keep a ZSET per time bucket** — `leaderboard:run:global:2026-11-08`, `…:2026-W45`, `…:2026-11`. **`ZINCRBY` into the day/week/month buckets on write; `ZUNIONSTORE` buckets to answer a range.** ▸ **Pre-aggregated, so the read is O(N) in the page size, not O(n) in activities.**
> 
> **3. ⚠ `ZINCRBY` and time-range filtering are incompatible, not complementary.** ▸ **A cumulative counter cannot be windowed — you can't decrement an activity out of the set as it ages past 24 hours.** ⭐⭐ **That's _why_ HI switches to the ZSET-of-timestamps + HASH model mid-dive — but HI never says the first model was abandoned.** ▸ **Read them as two separate designs: `ZINCRBY` for all-time boards, bucketed ZSETs for windowed ones.**
> 
> - ⭐ **In the room:** give HI's `ZINCRBY` + per-country keys (that part is clean and correct), then say _"for time ranges I'd pre-aggregate into day/week/month ZSETs rather than aggregating activities at read time."_
> 
> ■ **— end of insert · HI write-up resumes below —**

---

## 6 · Final Design

⚠⚠ **This diagram is MY reconstruction — HI's Final Design section is a heading and one sentence in the source, with no diagram.** ▸ **Components, labels and field lists are HI's, assembled from the incremental diagrams in §4 and §5. The layout and arrows are mine.** ⭐ **Check it against the diagram on HI's page.**

```
Client  ⭐⭐ THE PRIMARY WRITE TIER — not just a renderer
  │
  │   On-device location services (Core Location / FusedLocationProvider)
  │     └─ GPS point every ~2s (ride) / ~5s (run)
  │   In-memory activity buffer   — array of (coordinate, timestamp)
  │     └─ persisted to local storage every ~10s  ⇒ ⭐ lose ≤ 10s on crash
  │   Haversine distance + elapsed time computed LOCALLY  ⇒ instant stats
  │   On complete + online: ONE bulk sync (chunked if very long)
  │   ⭐ Background sync retries when a connection appears
  │   ⊕ DD3 only: live position posts every 2–5s, display lagged 5–10s
  │
  │   POST   /activities                    {type}
  │   PATCH  /activities/:id                {state: STARTED|PAUSED|COMPLETE}
  │   POST   /activities/:id/routes         ⚠ largely replaced by bulk sync
  │   GET    /activities?mode=USER|FRIENDS&page&pageSize
  │   GET    /activities/:id
  ▼
Activity Server   ⭐ MONOLITH — no microservices, scaled horizontally
  │                 ("no significant read/write skew across paths")
  │
  ├──► Database                                                    01f · 02g
  │      ⭐ shard by completionTime  (queries want recent)
  │      ⭐ tiering: hot → warm (3–12mo) → cold archival S3         01a
  │
  │      Activity   id (PK) · type: RUN|BIKE · startTime · status
  │                 statusUpdateEvents: JSON  ⭐⭐ the (status,ts) log
  │                 routeId · distance
  │      Route      ⊕ (activityId, timestamp) composite PK
  │                 latitude · longitude · timestamp
  │                 ⚠ HI's diagram says activityId alone — can't be,
  │                   ~600 rows per activity
  │      Friend     (userId, friendId) composite PK + index on userId
  │                 ⭐ bi-directional ⇒ TWO rows per friendship
  │      Leaderboard  user · distance · activity · location · completionDate
  │                 ▹ only needed for DD4's periodic-aggregation rung
  │
  ├──► Recent-activity Cache                                            01e
  │      ⚠ HI deprioritises this — "not a priority… but the first
  │        thing we would do if load times become unacceptable"
  │
  └──► Redis                                                       02a · 05i
         ⭐ Leaderboard sorted sets
            leaderboard:run:global · leaderboard:run:USA · …
            ZINCRBY distance user_id   ⭐ cumulative, not recomputed
            ZRANGE … desc              ⊕ use 0, N-1 — NOT 0, -1
         ⊕ time ranges: bucket ZSETs per day/week/month + ZUNIONSTORE
            (NOT HI's per-activity HGETALL loop)
         ⊕ DD3: live athlete position, short TTL, one key per athlete
            ⇒ all friends poll the same key, zero per-friend work

Google Maps API  ◄── route coordinate array ⇒ draws the connecting line
```

---

## Quick Recall (pass 3+)

|Use / Question|Strava answer|
|---|---|
|Calibration|⭐ Evan King · **Jul 2024** · **"medium"** · ⚠ **"Asked at:" empty in source** · ⭐⭐ **TWO Pattern callouts, a series first: `Scaling Writes` (`03e`) + `Real-time Updates` (`03a`).** ⭐⭐ **The only problem in the series that REMOVES machinery instead of adding it.** Score points: ⭐⭐ **client records locally** · **status-event log** · **storage math → shard + tier** · **polling over WebSockets, two reasons** · **smart buffering** · **"DB choice doesn't matter"** · **monolith**|
|⭐⭐ Design driver|⭐⭐ **The NFRs are NOT in tension — they all point off the server.** **no network ⇒ record on device · "local" stats ⇒ compute on device · 10M concurrent ⇒ already solved by those two · availability≫consistency ⇒ sync late and loose.** ⭐ **The hard requirement (offline) hands you the scaling answer for free.** ⚠⚠ **DD3 puts it all back**|
|FRs|**start/pause/stop/save** · **view route + distance + time DURING the activity** · **view completed activities, own and friends'.** Below: friend management · auth · comments/likes|
|NFRs|⭐ **availability ≫ consistency** (note the `≫`) · ⭐⭐ **must work with NO network** · ⭐ **accurate up-to-date _LOCAL_ stats** (the word "local" is doing work) · **10M concurrent activities.** Below: GDPR · advanced security|
|📐 Numbers|**~100M activities/day × 365 = ~36.5B/yr.** **~100B metadata** + route: **30min ÷ 3s = ~600 points × 24B (8+8+8) ≈ 15KB.** ⭐⭐ **15KB × 36.5B = 547.5TB/yr.** ⭐ HI: _"far from unmanageable."_ ⚠ **don't memorise: the 100M DAU is never a stated requirement (NFR says 10M CONCURRENT); "100x" is really 360–600×**|
|Entities|**User · Activity · Route** (▹ _"could also just be a field on Activity"_) **· Friend** (⚠ **management out of scope but _"the concept is necessary for sharing"_**). ▹ **contrast `05i`, which omitted User as "implied"**|
|API|`POST /activities {type}` · `PATCH /activities/:id {state}` · `POST /activities/:id/routes {location}` · `GET /activities?mode=USER\|FRIENDS&page&pageSize → Partial<Activity>[]` · `GET /activities/:id`. ⭐⭐ **`COMPLETE` on the state endpoint = save AND share — no sharing endpoint needed**|
|▹ PATCH vs PUT|**PATCH sends only changed fields; PUT needs the whole resource** — _"a, albeit minor, improvement in efficiency."_ ⭐ **HI's real point: _"functionally equivalent"_ in an interview, but some interviewers are _"RESTful API hawks"_ ⇒ have the one-liner ready, spend no more on it**|
|⭐⭐ The status-event log|⚠ **naive `now − startTimeStamp` BREAKS on pause** — _"elapsed time would continue to increment."_ ⭐⭐ **Fix: a log of (status, timestamp) pairs** — `STARTED 00:00 · PAUSED 00:10 · RESUMED 00:15 · STOPPED 00:20` ⇒ **sum the active gaps = 10 + 5 = 15 min** (wall clock 20). ⭐ **HI's justification: enables "when were you paused and for how long" + "total time vs active time."** ⊕ **event sourcing in miniature — store transitions, derive the aggregate; use it whenever a value is a DURATION not a quantity**|
|GPS + distance|⭐ **client records at a constant interval — ~2s ride, ~5s run.** ⭐ **distance via Haversine between consecutive points** (`04a`, same as `05c`). ▹ **iOS Core Location/`CLLocationManager`, Android `FusedLocationProviderClient`** — ⭐ **HI: _"you absolutely do not need to know the libraries… system design, not mobile development"_**|
|⊕⚠⚠ Route schema bug|**HI's diagram: `Route — activityId (PK)`.** ⚠ **But there are ~600 route rows per activity ⇒ the 2nd GPS point collides.** ⭐ **needs composite `(activityId, timestamp)`** (or `(activityId, seq)`). ▹ ⚠ **the `GPS — routeId · distance` box is also almost certainly two FIELDS on Activity, not a table**|
|⭐⭐ HI's planted setup|_"Astute readers are likely already yelling at their screen as they've realized **we don't need to send these updates to the server**… You're right."_ ⚠⚠ **_"most of the time I ask this question, candidates overlook this optimization."_** ⭐⭐ **So SAY IT IN THE HLD, not the deep dive — one sentence puts you ahead of the median candidate**|
|Friends table|⭐ **two columns `userId, friendId`** · ⭐ **bi-directional ⇒ TWO rows per friendship** `(A,B)` and `(B,A)` · ⭐ **composite PK `(userId, friendId)` + index on `userId`** ⇒ **efficient friend lookup AND no duplicate friendships.** ▹ ⚠ **the diagram says `user1/user2/createdAt` — use the prose version**|
|View activities|**`WHERE state = "COMPLETE"`** + `userId = :userId`, or `userId IN (SELECT friendId FROM friends WHERE userId = :userId)`, with `LIMIT/OFFSET`. ⭐ **two-step read: list (basic info + activityId) → detail GET.** **Map: pass the coordinate array to Google Maps API, it draws the line.** ⊕ **it's fan-out-on-read and that's FINE at this scale — name the condition that would flip it to precompute (`05f §5.1`)**|
|⭐⭐ DD1 — the key insight|_"**so long as we don't support realtime-sharing**, we can record activity data locally… and only sync when the activity completes and/or the user is back online."_ ⭐⭐ **HI: _"an impactful realization that re-shapes the entire system."_** ⚠ **Remember that opening clause — DD3 revokes it**|
|⭐⭐ DD1 — three wins at once|**(1)** ⭐ **no dependence on network reliability** **(2)** ⭐⭐ **saves bandwidth even on a good connection** — send on completion/pause, not every few seconds **(3)** ⭐ **accurate live stats are trivial** — _"it all happens synchronously on their device"_|
|⭐⭐ The client as a tier|⭐ HI: _"**the client as an active participant**… sensors, substantial memory and processing power, and significant local storage. Many candidates overlook the client's capabilities."_ ⭐⭐ **Named systems: Strava, `05b` Dropbox, Spotify.** ▸ **vs `05h §5.3` Tinder: there the client was an OPTIMISATION, here it is the PRIMARY ARCHITECTURE**|
|⭐ DD1 — how it works|**in-memory buffer of (coordinate, timestamp)** → ⭐⭐ **persisted to local storage every ~10s** (iOS Core Data/UserDefaults, Android Room/SharedPreferences) → **on reopen/resume load local storage FIRST** → **on complete + online, ONE bulk request** (⚠ **chunk very long activities**) → ⭐ **background sync retries when a connection appears** → **delete the buffer on confirmation.** ⭐⭐ **The guarantee: _"we'll only lose a maximum of 10 seconds."_** ⚠ **name the cost: battery**|
|⭐⭐ Why no microservices|_"we **offloaded so much of the write load to the client** that we don't have a ton for our backend to do… **no significant read/write skew across different paths**."_ ▹ **counter-argument raised and dismissed: _"if Meta can famously manage it, so can we."_** ⭐⭐ **The reusable test: is there read/write skew across paths? Compare `05h §4.3` — split only when write pattern + data volume + ideal engine ALL differ**|
|⭐ DD2 — three fixes|**(1)** ⭐⭐ **shard by `completionTime`** — _"the majority of our queries will want to see recent activities"_ (`01f`) **(2)** ⭐⭐ **tiering: hot → warm (3–12mo) → cold S3** (`01a`) — _"chances someone wants a run from several years ago are pretty low"_ **(3)** ⭐ **caching, EXPLICITLY deprioritised** — _"not a priority for me… but the first thing we would do if load times become unacceptable"_ ▹ **note the shape: name it, rank it last, give the promotion trigger**|
|⭐⭐ DD2 — "which DB?"|⭐⭐ _"**Hot take. It doesn't really matter.**"_ **Three reasons, all required: (1) large but totally manageable volume (2) no crazy read or write throughput (3) relational but not heavily so** ⇒ _"all popular major database technologies would work great here."_ ⚠ **Without the three reasons it sounds like you don't know the options**|
|⭐⭐ DD3 — polling over WebSockets|⚠ _"I know what you're likely thinking, **'Websockets!'**… I'd **strongly argue it's over-engineering**."_ ⭐⭐ **TWO insights: (1) updates are PREDICTABLE — _"we know the next update should come in the next 2-5 seconds"_, unlike Messenger/Live Comments (2) real-time precision isn't critical.** ⭐ **Friends poll at the athlete's post interval, offset for latency.** ⭐⭐ **`03a`: _"the most important thing… is when it's not necessary!"_** ▹ **3rd file running where this is the scored move**|
|⭐ DD3 — smart buffering|⭐⭐ **intentionally lag the display by 1–2 intervals (~5–10s).** ▸ **smooth continuous animation instead of _"the jarring effect of sudden position changes"_ ⇒ _"a 'live-stream-like' experience."_** ⭐ **Also absorbs network latency.** ⭐⭐ **The only place in the series where the right answer is to make the system LESS fresh on purpose**|
|⊕⚠⚠ DD3 undoes DD2|⚠ **Frame as an EXTENSION not re-costed, not a self-contradiction** — _"turning this on reintroduces the write load DD1 removed, let me re-cost it."_ 📐 **10M concurrent × 1 per 2–5s ≈ 2–5M writes/sec vs DD2's ~1,150/sec ⇒ ~2,000–4,000×.** ⚠ **fan-out never mentioned: at 50 friends, ~100M+ polls/sec ⇒ `05g`'s problem.** ⭐⭐ **The fix, 4 moves: (1) ⭐⭐ live sharing OPT-IN per activity — a PRODUCT change, and the actual scaling answer (`05e`/`05g` thread) (2) live points → Redis short TTL, NOT the primary DB; authoritative route still bulk-syncs at the end (3) ⭐⭐ ONE cached payload per athlete, all friends poll the same key ⇒ zero per-friend work — the half candidates forget (4) ⭐⭐ connectivity DEGRADES, never GATES** — ⚠⚠ **you can't hide the share option for "remote areas": signal is a property of the whole route, not the start.** ⚠ **Keep the two syncs separate: durability = occasional/batched/every activity · live = 2–5s/opted-in only. Syncing everyone at 2–5s rebuilds the load you removed**|
|⚠ DD4 Bad — aggregate on read|`SUM(a.distance) … GROUP BY u.userId ORDER BY total_distance DESC`. ⚠ **_"pretty slow given it is running an aggregation over millions of activities"_ · degrades rapidly · high DB load · ⭐ _"doesn't account for the dynamic nature of leaderboards"_**|
|DD4 Good — periodic aggregation|⭐ **a separate pre-calculated leaderboard table, refreshed by a daily background job** ⇒ read becomes a simple sorted SELECT. ⚠ **eventual consistency — _"user confusion if their latest activity isn't immediately reflected"_** · ⭐⭐ **interval is the trap: _"too frequent… strain system resources, while infrequent updates lead to stale data"_** ▹ **same tension as `05h §5.2` stale feeds ⇒ make it a tunable**|
|⭐ DD4 Great — Redis ZSET|⭐⭐ **read `05i §5.2` for the structure — do NOT re-learn it.** **Only 3 things are new: (1)** ⭐⭐ **`ZINCRBY` not `ZADD`** — the score is a RUNNING TOTAL, so add in place; **rule: `ZINCRBY` for cumulative, `ZADD` for recomputed (2)** ⭐⭐ **country = separate keys** `leaderboard:run:global` / `:USA`, **each activity updates BOTH (3)** **time range = ZSET of (activityId→timestamp) + HASH per activity, `ZRANGEBYSCORE` then aggregate in memory**|
|⚠ DD4 challenges|⭐⭐ **consistency between Redis and the primary DB — _"a robust system to handle failures and retries"_** · ⭐⭐ **memory limits — _"all possible combinations of activity types, time ranges, and geographical filters could consume significant memory"_** ⇒ ⭐ **keep only the most-accessed boards in Redis, compute rare ones on demand** ▹ **same shape as `05h §5.2` warm-set membership**|
|⊕⚠⚠ Three bugs in DD4's code|**(1)** ⚠ **`zrange(key, 0, -1)` returns the ENTIRE set** while the prose says _"top N"_ ⇒ **should be `0, N-1`** ▹ **same prose-vs-code mismatch as `05i`'s `MIN`/`MAX`.** **(2)** ⚠⚠ **the time-range loop is one `HGETALL` per activity ⇒ ~100M round trips for a global 24h board**, presented as _"more scalable and real-time."_ ⭐ **min fix: pipeline/`HMGET`. Real fix: bucket ZSETs per day/week/month + `ZUNIONSTORE`.** **(3)** ⚠ **`ZINCRBY` and time ranges are INCOMPATIBLE** — a cumulative counter can't be windowed (you can't decrement activities as they age out) ⭐⭐ **which is WHY HI silently switches data model mid-dive**|
|⭐⭐ The meta-lesson|**this file's scoring axis is SUBTRACTION.** **Rejected with reasons: server-side GPS writes · microservices (×2) · WebSockets · caching-as-a-priority · even "which database."** ⭐⭐ **Pair it with `05i`: two files running where the answer is "I know the complex version and here's why I'm not using it"**|

---

> 🔗 **HI source:** https://www.hellointerview.com/learn/system-design/problem-breakdowns/strava
> 
> ⚠ **Source gaps — nothing below was filled in from my own knowledge:**
> 
> 1. ⚠⚠ **§7 "Expected at Each Level" is OMITTED from this file.** HI's section was not in the paste, and **you asked to skip it** — so there is no §7 heading here at all, unlike `05a`–`05i`. ⭐ **Say the word and I'll add the section back once you send it.**
> 2. ⚠ **The Final Design diagram was not in the paste** (HI's section is a heading plus one sentence). ⭐ **§6 is my reconstruction** from the incremental diagrams in §4 and §5 plus the component lists — **fields and labels are HI's, layout and arrows are mine.** ▹ **You read diagrams from the source page, so check it there.**
> 3. ⚠ **DD4's rung LABELS are missing** — HI renders them as tabbed cards and only the `Approach` / `Challenges` bodies came through. **"aggregate on read" / "periodic aggregation" / "Redis sorted sets" are my labels**, derived from the body text. **The content under each is HI's.**
> 4. ▹ **`Asked at:` is empty in the source** — the label is present with no companies after it.
> 
> ✅ **Reconciled against the original:** all 3 FRs and 4 NFRs with both below-the-line lists · the start-simple planning note with HI's "should I start complex?" aside · all 4 entities · all 6 API endpoints with the PATCH/PUT note · all three HLD sections including the status-event log, the Haversine/GPS flow and the friends-table design · DD1's key insight, three wins, seven implementation steps and the no-microservices justification · DD2's full storage math, three mitigations and the "which database" hot take · DD3's two polling insights and smart buffering · DD4's three rungs with every challenge listed, both code blocks and both memory/consistency challenges · both Pattern callouts. ⚠ **Gaps are limited to items 1–4 above.**