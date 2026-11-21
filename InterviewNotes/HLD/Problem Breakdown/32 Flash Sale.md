# Flash Sale — Problem Breakdown

> 📐 **Revision note (calc):** **10,000 units (noon) · 10M users (HI's whiteboard) · 10-minute hold · DB ~10k reservation tx/s (assumed) · admit ~8k/s.** 📐 ⊕ **10,000 ÷ 8,000/s ≈ 1.25 s to hand out EVERY unit · 10M ÷ 8,000/s ≈ 21 min to drain the queue · 10,000 ÷ 10M = 0.1% chance per user · ≤ 10,000 holders ⇒ ≤ 10k polls/s.**

> Common Problems · **Evan King, published Sep 4, 2026** · ⭐⭐ **"hard"** · **no "Asked at" tag** · ⭐⭐ **`Real-time Updates` → `03a` (⊕ derived) · `Dealing with Contention` → `03b` · `Scaling Writes` → `03e`** · Cross-refs: ⭐⭐⭐ **Payment System (PaymentIntent, webhook, idempotency)** · ⭐⭐⭐ **Ad Click (25) DD3 (signed token, `SET NX`)** · ⭐⭐ **Rate Limiter (13)** · ⭐⭐ **Ticketmaster (same shape; number unknown)**
> 
> **Calibration:** ⭐⭐ **TWO passes (my call): long ladders, plus two interview-level catches below (lease vs in-flight payment; sold-out vs lazy reclaim).** ⭐ **Order: DD1 > DD3 > DD2 > §4.3 > DD4 > §4.1/§4.2.**
> 
> - ⭐⭐ **What scores:** **(a)** ⭐⭐⭐ **why a reservation: payment is slow and third-party** · **(b)** ⭐⭐⭐ **the conditional `UPDATE` is correct but serial** · **(c)** ⭐⭐⭐ **Redis counter vs a row pool + `SKIP LOCKED`** · **(d)** ⭐⭐ **lazy reclaim** · **(e)** ⭐⭐⭐ **waiting room + signed token, not 429s** · **(f)** ⭐⭐ **fairness: pre-sale random, then FIFO, one entry per user.**
> - ⭐ **Transferable primitives:**
>     - ⭐⭐⭐ **Reserve first, settle later: a reservation is a lease, and a lease needs an expiry, a reclaim, and protection while a dependent action is in flight.**
>     - ⭐⭐⭐ **Turn one hot counter into many independently claimable rows — then it parallelises.**
>     - ⭐⭐⭐ **Every system has a finite write ceiling. Protect it upstream by holding users in a queue, not by rejecting them.**
>     - ⭐⭐ **Reclaim lazily, when someone needs the thing, not on a timer.**
>     - ⭐⭐ **Mint a signed token at the source, verify it at the edge (Ad Click DD3).**
>     - ⭐ **Fairness is a design decision — you own it the moment you order the queue.**
> - ⭐ **Re-run (cross-ref only):** **PaymentIntent + webhook + idempotency (Payment System) · signed token (Ad Click DD3) · gateway limiter, 429 storms, Lua (Rate Limiter).** **New:** ⭐⭐⭐ **row pool + `SKIP LOCKED` · waiting room** · ⭐⭐ **lazy reclaim · pre-sale lottery + FIFO** · ⭐ **polling vs SSE.**

---

## 0 · Understanding the problem

💬 **A flash sale zooms in on ONE hard part of e-commerce: selling a very small stock under extreme demand.** ▸ **Concrete: Nike releases 10,000 pairs at noon; tens of millions of users may try within seconds.**

⭐⭐ **The job: let users compete fairly for the stock and pay, without EVER overselling.**

---

## 1 · Requirements

### 1.1 Functional

1. ⭐⭐ **Users can view the flash sale item.**
2. ⭐⭐⭐ **Users can secure/reserve an available unit for a limited time while the sale is active.**
3. ⭐⭐ **Users who secure a unit can complete payment to purchase it.**

⭐⭐ **HI: FR2 is the one candidates miss. Payment is a third party taking seconds, so no open DB transaction across it; the reservation takes a unit off the table now and settles money later.**

⚠ **Below the line:** **Browsing or searching a broader catalog · Shipping, returns, refunds, order history · Admins creating, configuring or managing sales.**

> ⚠ ⊕ **"Refunds" is out of scope as a feature, but §4.3 shows why the system still needs a refund path (payment succeeds after the lease died).**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 1.2 Non-functional

📐 ⭐ **Ask scale first. HI's text says "millions" and "tens of millions"; the whiteboard says 10M wanting the same product. Use 10M.**

1. ⭐⭐⭐ **The system should prevent overselling, even when many people try to claim the same unit at the same moment.**
2. ⭐⭐⭐ **The system should handle millions of users arriving within seconds of the sale starting.**
3. ⭐⭐ **The system should give users a fair opportunity to compete for the limited inventory.**

⚠ **Below the line:** **Protecting user data / GDPR · Fault tolerance · Secure transactions.**

> ⚠ **"Fault tolerant" is dropped, yet DD3 and DD4 put the queue — which decides who wins — in Redis.** ⊕ **Say what happens to fairness if the waiting-room state is lost.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 1.3 ⭐⭐⭐ The design driver — a tiny stock, a crowd that arrives all at once, and a payment that takes seconds

|Constraint|What it breaks|Fixed by|
|---|---|---|
|⭐⭐⭐ **payment is a slow third party**|**a DB transaction held open through it**|**a reservation (a lease) (§4.2)**|
|⭐⭐⭐ **millions want the same 10,000 units**|**one counter row every request updates**|**a pool of claimable rows (DD1)**|
|⭐⭐ **abandoned reservations**|**inventory locked forever, or returned late**|**expiry + lazy reclaim (DD2)**|
|⭐⭐⭐ **the database has a finite ceiling**|**letting everyone in at once**|**a waiting room + admission token (DD3)**|
|⭐⭐ **the queue decides who gets a pair**|**latency and bot races**|**pre-sale random order, then FIFO (DD4)**|
|⭐⭐ ⊕ **a payment can finish after the lease expired**|**expiry reclaims a unit that is being paid for**|**pin the lease while a purchase is pending (§4.3)**|

### 1.4 Planning the approach

⭐ **Follow the delivery framework, one FR at a time; use the NFRs to guide the deep dives, so you don't dive into scaling too early.**

---

## 2 · Core Entities

- **Product** — ⭐ **the shoe: details, price, sale start/end, units available. One pair = one unit.**
- **Reservation** — ⭐⭐ **a temporary claim on ONE unit while a user checks out: user, product, expiry, status.**
- **Purchase** — ⭐ **a successful purchase: user, product, reservation, payment amount, payment status.**
- **User** — **the person trying to buy.**

⭐ **HI: in the interview this is just a short list; agree it with the interviewer first.**

> ⚠ **What these entities leave loose.**
> 
> - ⚠⚠ **Nothing limits a user to one unit.** ⊕ **Add a partial unique index on (userId, productId) WHERE status = ACTIVE; otherwise one user (or bot) can hold many reservations, which breaks the fairness NFR.**
> - ⚠ **`Reservation.quantity` appears in the schema, but the API reserves one unit.** ⊕ **Drop it, or cap it at 1.**
> - ⚠ **A Reservation has no `unitId`, and sizes/variants (SKUs) aren't modelled.** ⊕ **If units are interchangeable inside a pool, a returned unit is just a new row; a real shoe drop needs one pool per SKU.**
> - ⊕ **DD1 adds a fifth entity, `ReservationUnit` (`productId`, `unitId`), and DD3 a waiting-room entry.**
> 
> ■ **— end of insert · HI write-up resumes below —**

---

## 3 · API

```
GET  /products/:productId                       -> Product
POST /products/:productId/reservations          -> Reservation    { reservationId, productId, expiresAt }
POST /reservations/:reservationId/purchases     -> Purchase
```

- ⭐ **`Product` carries what the sale page needs: details, price, sale window, units available. The Reservation gives the client everything for a countdown and then the purchase call. Reserving is NOT buying — it opens a limited window.**
- ⭐ **The purchase call tries to charge the user and convert the reservation; if the reservation expired or payment failed, it fails and the unit can go to someone else.**
- ⚠ **Gaps:** ⊕ **① no idempotency key on either POST · ② `Purchase` must carry the Stripe client secret · ③ the waiting-room endpoints of DD3 are missing (`join`, `status`).**

---

## 4 · High-Level Design

⭐ **Build the simple end-to-end design first; HI says it falls apart at tens of millions of users.**

### 4.1) Users can view the flash sale item

⭐ **Client → API Gateway (auth, rate limiting, logging) → Sale Service → Postgres (ACID for later). The Sale Service fetches the `Product` row; `inventoryCount` lives on it for now.**

**Flow:** **① client sends `GET /products/:productId` ② gateway forwards ③ Sale Service queries the DB ④ the product, with the current `inventoryCount`, comes back.**

> ⚠ **What HI leaves loose.**
> 
> - ⚠⚠ **This read path is 10M people opening the page from Postgres at noon; HI never returns to it.** ⊕ **Static details on a CDN; "units left" eventually consistent (or just available / sold out), never read from the hot rows. Open the page behind the waiting room.**
> - ⚠⚠ **After DD1 there is no `inventoryCount` — yet this page shows it.** ⊕ **Keep a cached counter, or `COUNT` the pool.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 4.2) Users can secure/reserve an available unit for a limited time

⭐ **Add a `Reservation` table: `reservationId`, `productId`, `quantity`, `userId`, `expiresAt`.**

**Flow:** **① client sends `POST …/reservations` ② gateway forwards ③ the Sale Service opens a transaction and checks the product is on sale with inventory ④ inserts a Reservation with an expiry (say 10 minutes) ⑤ decrements `inventoryCount` and commits ⑥ the reservation returns to the client, who has until `expiresAt`.**

⭐⭐⭐ **Steps 3–5 are ONE transaction: if the check and the decrement can be pulled apart, two users read the same last unit and both reserve it — overselling.**

⭐⭐ **Abandoned reservations (closed tab, declined card) must expire: a cron job finds ACTIVE reservations past `expiresAt`, marks them EXPIRED and increments `inventoryCount`, again in one transaction — expire without returning the unit and that inventory is lost. Cost: a returned unit can reappear late; fine for now, improved in DD2.**

> ⚠ **What HI leaves loose.**
> 
> - ⚠ **"Now" in `expiresAt` must come from the DB clock (`now()`), not each app server — skew.**
> - ⚠⚠ **No per-user cap (see §2).**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 4.3) Users who secure a unit can complete payment

⭐ **Add a `Purchase` table (`purchaseId`, `reservationId`, `productId`, `userId`, `status` PENDING | COMPLETE | FAILED, `createdAt`) and use an external processor (Stripe), so we never touch card data.** ▸ **PaymentIntents, retries and payment state: the Payment System breakdown.** ⭐ **`Reservation` gains `status`: ACTIVE | PURCHASED | EXPIRED.**

**Flow:** **① `POST …/purchases` ② gateway forwards ③ check the reservation exists and hasn't expired ④ insert Purchase PENDING ⑤ create a Stripe PaymentIntent, return the client secret ⑥ the client pays Stripe directly ⑦ Stripe sends a WEBHOOK ⑧ success ⇒ Purchase COMPLETE, Reservation PURCHASED; failure ⇒ Purchase FAILED, reservation stays active until expiry so the user can retry.**

💬 **A webhook is an HTTP request one system sends to another when an event occurs — Stripe calls us once the payment is final, so we don't poll Stripe.**

⭐⭐ **The user's side: Stripe says "paid", but our records only change when the webhook lands. Simplest fix: the client polls `GET /purchases/:purchaseId` about once a second until final. Only reservation holders poll — "a few thousand", not the millions. Push (SSE) also works.**

> ⭐⭐ **Pattern: Real-time Updates (`03a`)** — **the waiting set is tiny and the wait is seconds, so polling beats a pushed connection; SSE wins when more clients wait or they wait longer.**
> 
> ■ **— end of insert · HI write-up resumes below —**

> ⚠⚠ **What HI leaves loose — the most important insert in the HLD.**
> 
> - ⚠⚠ **A payment can finish AFTER the reservation expired.** ⊕ **The user is confirming at 10:00; the cron (or DD2's reclaim) returns the unit; another buyer takes it; then the webhook says "paid" — two buyers, one unit. HI checks "not expired" only at step 3.** ⊕ **Pin the lease: skip reservations with a PENDING purchase when reclaiming (or extend `expiresAt`). On the webhook, `status = PURCHASED WHERE status = ACTIVE`; zero rows ⇒ refund. "Refunds" are out of scope as a feature, not as a path.** ▸ **Payment System: timeout-as-unknown.**
> - ⚠⚠ **No idempotency: a double-click makes two PENDING purchases and two PaymentIntents; webhooks are redelivered.** ⊕ **One non-failed Purchase per reservation (unique), reservationId as Stripe's idempotency key, conditional webhook transition.**
> - ⚠ **Purchase COMPLETE and Reservation PURCHASED live in two tables ⇒ ⊕ one transaction (HI says so only for reserve and expire).**
> - ⚠ **"A few thousand" pollers: with 10,000 units, 📐 ≤ 10k polls/s — as big as the reservation ceiling.** ⊕ **Most hold seconds; back off or cache.**
> 
> ■ **— end of insert · HI write-up resumes below —**

⭐ **HI: all three FRs are now met end to end. The design falls apart when tens of millions arrive at once — that is what the NFRs and deep dives address.**

---

## 5 · Deep Dives

⭐ **HI takes four: contention (NFR 1), expiry, scale (NFR 2), fairness (NFR 3). Rung labels below are mine except where HI names his pick.**

### 1) How do we maintain consistency under extreme contention?

#### Baseline — the conditional `UPDATE` (from the HLD)

- ⭐⭐ **`UPDATE Product SET inventoryCount = inventoryCount - 1 WHERE productId = ? AND inventoryCount > 0;` One row affected ⇒ secured; zero ⇒ sold out. Do it and insert the Reservation in the SAME transaction.**
- ⭐⭐⭐ **HI: "correctness isn't the problem — contention is." Millions update one Product row; each decrement depends on the previous, so the DB serialises them. His store picture: ten registers with 1,000 pairs each, versus our one register; more app servers just converge on the same row lock.**
    - 💬 **What it means:** **the database can prevent overselling correctly, but it may be too slow under huge demand. The conditional update guarantees only one request takes the last unit, so correctness is safe. But millions of requests all update the same product row, and the DB must process those writes one at a time, each waiting for the row lock. So we hand out exactly 10,000 pairs, but may take too long to serve everyone who is trying at once.**
- ⭐⭐ **The invariant to keep: never hand out more reservations than inventory, under extreme contention.**

> ⭐⭐ **Pattern: Dealing with Contention (`03b`)** — **a flash sale is the pattern in its purest form: one stock, each unit handed out exactly once.**
> 
> ■ **— end of insert · HI write-up resumes below —**

**Why climb:** ⭐ **make the hot spot faster, or remove it.**

#### Good — a Redis counter (+ sorted set + Lua)

- ⭐⭐ **Move the contended state to Redis: `available:{productId} → 10,000`; check `> 0`, decrement. Commands run one after another on one thread — atomic, in memory, no row locks ⇒ about an order of magnitude more ops/s on one key than a Postgres row.**
- ⭐⭐ **Also keep `expirations:{productId}`, a sorted set of reservationId scored by `expiresAt`, so cleanup finds expired ones, removes them and increments the counter; store the reservation under its id. Check, decrement and write run in ONE Lua script, so a crash can't lose a unit.**
- ⚠⚠ **Challenges (HI): ① state is split across two systems — Redis is now part of the source of truth (durability, recovery, reconciliation) · ② serialisation moved, not removed: hundreds of thousands of ops/s is still a ceiling.**

**Why climb:** ⭐ **fix the data model so no single row or key takes every request, and keep one source of truth.**

#### ⭐⭐⭐ Great — a pool of claimable rows (HI's pick)

⭐⭐⭐ **The idea: stop having ONE counter. Have one row per shoe.**

```
ReservationUnit            (replaces inventoryCount = 10,000)
productId | unitId
shoe-123  | 1
shoe-123  | 2
...
shoe-123  | 10000
```

- ⭐⭐ **A reservation claims ANY one free row. Different buyers lock different rows, so they stop queueing behind each other.**

**Step 1 — the naive claim (still queues):**

- `SELECT unitId FROM ReservationUnit WHERE productId = ? LIMIT 1 FOR UPDATE` — `FOR UPDATE` locks the chosen row until the transaction ends.
- ⚠ **Everyone picks the same first row: one locks it, the rest wait.**
- ⚠ **Postgres quirk: if the holder deletes that row, a waiter can get NO row back and wrongly concludes "sold out".**

**Step 2 — `SKIP LOCKED` (the fix):**

- ⭐⭐⭐ `… LIMIT 1 FOR UPDATE SKIP LOCKED` **— a locked row is skipped, not waited on.**
- **Example: A locks unit 37; B skips it and locks 38; C locks 39. All three proceed in parallel.**
- ▹ **Postgres/MySQL keyword; any DB that locks rows independently works.**

**The whole reservation is ONE transaction:**

- ⭐⭐ **① claim a unit with `SKIP LOCKED` ② none returned ⇒ sold out ③ delete that unit from the pool ④ insert the Reservation with `expiresAt` ⑤ commit.**
- **Claim and reservation succeed or fail together. When a reservation expires, its unit goes back into the pool (DD2).**

**Challenges (HI):**

- ⚠ **Up to 10,000 rows instead of one counter — fine here; at Shopify scale keep a bounded pool, refilled when low.**
- ⚠ **The DB still handles only so many transactions at once ⇒ DD3.**

⭐⭐⭐ **Why HI picks it over Redis: inventory and reservations stay in ONE transactional database — no second source of truth. (HI: Shopify uses this technique.)**

> ⚠⚠ **What HI leaves loose.**
> 
> - ⚠⚠ **HI's cashier picture IS a sharded counter — never applied to Redis.** ⊕ **Ten keys of 1,000 (random pick, steal when empty) also removes the single-key ceiling. So "Redis is serial, rows are parallel" isn't the real contrast; the pool's win is one transactional source of truth (bucket size one).**
> - ⚠⚠ **Redis failover can oversell:** ⊕ **replication is asynchronous, so a promoted replica may lack the last decrements and hand out units twice (textbook).**
> - ⚠ **"One order of magnitude more ops/s on one key" comes with no figures.** ▹ **Judgment: say you would load-test both.**
> - ⚠ **`SKIP LOCKED` returns an ARBITRARY row — fine for fungible shoes, wrong for "seat 12A" (Ticketmaster); claims also scan past locked rows, so cost grows with concurrency.** ▹ **Judgment: cap concurrency (DD3).**
> - ⚠ **A Reservation has no `unitId`, so "return a unit" is ambiguous.** ⊕ **Store `unitId` on the Reservation and reinsert exactly that row.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 2) How do we efficiently release expired reservations?

⭐ **The other side of the lifecycle: get inventory back when reservations expire, close to the exact moment.**

#### Baseline — the cron job from the HLD

- ⭐ **Every few seconds: find ACTIVE reservations past `expiresAt`, mark EXPIRED, return a unit to the pool.**
- ⚠⚠ **A reservation expires at 12:10:01, the job runs at 12:10:10: for nine seconds a buyer is told "sold out" although a unit is free. In a flash sale every unit matters.**

**Why climb:** ⭐ **act at the exact expiry instead of on a polling interval.**

#### Good — a delayed job per reservation

- ⭐⭐ **When a reservation is created, publish `ExpireReservation(reservationId)` to a delayed queue (SQS) with a 10-minute delay; at ~12:10:00 it becomes visible to a worker.**
- ⭐⭐ **The worker can't just return the unit (the user may have just paid; the message may arrive twice). One transaction: ① still ACTIVE and `expiresAt <= now`? ② mark EXPIRED ③ return a unit ④ commit; else nothing.**
- ⭐ **A durable scheduler works too, e.g. a Temporal timer — the point is that the schedule lives outside the Sale Service, so a crash doesn't drop the timer.**
- ⚠⚠ **Challenges (HI): ① scale — a big sale creates thousands or millions of delayed messages that become eligible at about the same time · ② no guarantee the job runs at the exact moment: queues back up, workers fail, messages retry.**
- ⚠ ⊕ **Textbook: an SQS delay queue holds messages for at most 15 minutes — fine for a 10-minute hold, not for longer ones.**

**Why climb:** ⭐ **we don't care that a unit is physically back at 12:10:01 — only that the NEXT buyer isn't wrongly told "sold out".**

#### ⭐⭐⭐ Great — reclaim on demand, under one lock (HI's pick)

- ⭐⭐⭐ **The normal path is unchanged: claim a unit with `SKIP LOCKED`. Only when NO free unit is found, and before saying "sold out", look for already-expired reservations and reclaim a batch.**
- ⭐⭐ **Reclaim: ① try to claim as usual ② none ⇒ find a batch of ACTIVE reservations with `expiresAt <= now` ③ mark EXPIRED ④ KEEP one unit for this request and create its Reservation ⑤ return the rest ⑥ commit. E.g. 50 expired ⇒ keep 1, return 49 to the pool. Keeping one matters: otherwise it releases all 50 and races everyone for one.**
- ⭐⭐⭐ **Thousands hitting an empty pool must not all reclaim: ONE request per product at a time, behind a short-lived lock (Postgres: a transaction-scoped advisory lock on `productId`); the rest retry the normal query and spread across the new rows.**
- ⚠⚠ **Challenges (HI): the occasional request does more work; the common path stays fast; no millions of timers; no dependence on a background process running at the right instant.**

> ⚠⚠ **What HI leaves loose — two interactions with the other dives.**
> 
> - ⚠⚠ **Lazy reclaim runs only when somebody TRIES to reserve.** ⊕ **With DD3's "sold out" short-circuit nobody does, so units whose holders never paid sit idle while the page says sold out ⇒ a backstop sweep, or a trickle of admissions.**
> - ⚠⚠ **The reclaim query ("ACTIVE and expired") must skip reservations that have a PENDING purchase (§4.3), or it hands out a unit someone is paying for.**
> - ⚠ **The batch query needs an index on (productId, status, expiresAt) and should itself use `SKIP LOCKED`; batch size is unspecified.** ⚠ **"Waiting requests retry" is a small retry storm of admitted users.**
> - ✅ **The status check makes reclaim idempotent, as in the SQS worker.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 3) How do we handle millions of users arriving at once?

⭐⭐ **No clever query helps now: the database has a physical ceiling, say ~10,000 reservation tx/s from a load test. Let millions in at once and requests pile up, latency climbs, they time out. Even with Redis the ceiling is only higher. So control how fast users reach the reservation path.**

> ⭐⭐ **Pattern: Scaling Writes (`03e`)** — **the pool already partitioned the writes; what remains is absorbing bursts with queues and load shedding — the waiting room.**
> 
> ■ **— end of insert · HI write-up resumes below —**

**Why climb:** ⭐ **the backend can't be made unlimited; cap what reaches it.**

#### Good — rate limit at the API Gateway

- ⭐ **Allow roughly 10,000 requests/s through; reject the excess with `429 Too Many Requests`. Crude, but the database never sees more than it can handle.** ▸ **Rate Limiter (13).**
- ⚠⚠ **Challenge (HI): the pain moves to the user. Most of millions get a 429 and retry at once — a thundering herd that is limited again and retried again.**

**Why climb:** ⭐ **hold users upstream and let them in at our rate, instead of bouncing them.**

#### ⭐⭐⭐ Great — a virtual waiting room (HI's pick)

- ⭐⭐⭐ **At the start users enter a waiting room, not the reservation endpoint. A separate Waiting Room Service records each in Redis and returns an ID for status checks; separate because it sees far more traffic than the Sale Service (millions polling), so they scale independently.**
- ⭐⭐ **An admission controller continuously admits users at a safe rate: if the system handles 10,000 tx/s, admit ~8,000/s to leave headroom.**
- ⭐⭐⭐ **Flow: ① join ② place stored in Redis ③ client polls status ④ the controller admits at a safe rate ⑤ the admitted user gets a short-lived SIGNED token ⑥ the client sends it with `POST …/reservations` ⑦ the Gateway validates it before the Sale Service.**
- ⭐⭐ **The token (userId, productId, expiry) is signed with a backend secret, so the Gateway verifies it with no DB lookup and users can't bypass the room.** ▸ **Same primitive as Ad Click DD3.**
- ⭐ **After admission nothing changes: the same synchronous reservation call. If one Redis can't take the state and polling, shard it — the state is light.**
- ⚠⚠ **Challenges (HI): choosing the admission rate (too fast overloads, too slow wastes capacity); and the room now decides WHO gets scarce stock, in what order ⇒ DD4.**

> ⚠⚠ **What HI leaves loose — the arithmetic undercuts the premise.**
> 
> - ⚠⚠ **📐 10,000 ÷ 8,000/s = 1.25 s: the whole stock goes in about a second; draining 10M takes ~21 min of pointless transactions.** ⊕ **When the pool is empty, answer "sold out" to the rest at once — but see DD2.**
> - ⚠⚠ **A fixed rate ties admission to DB capacity, not to stock.** ⊕ **Better: admit roughly (units still free + expected expiries) × an overbooking factor, since not every reservation converts.** ▹ **Judgment call.**
> - ⚠⚠ **The token isn't single-use: one admission can fire many reservation calls, and tokens can be shared.** ⊕ **Nonce via `SET NX`; one ACTIVE reservation per user.**
> - ⚠ **Polling is unsized: 📐 ⊕ 10M clients every 5 s = 2M req/s ⇒ 10–20 Redis shards.** ⊕ **Jitter, long-poll or SSE, a CDN "in line" page, coarse positions.**
> - ⚠ **If everyone joins at noon, joining is itself a write storm of 10M into Redis. DD4's pre-sale opening spreads it out.**
> - ⊕ **Keep the gateway limiter as a backstop behind the room (defence in depth), and prefer a concurrency limit on in-flight transactions over a fixed rate.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 4) How do we make access to limited inventory fair?

⭐⭐ **The moment the room orders people, we own fairness.**

#### ⚠ Bad — pure FIFO

- ⭐ **Whoever enters first is admitted first. For a known start time this turns the first milliseconds into a contest of network latency and automation, not of who showed up.**

#### ⭐⭐⭐ Great — pre-sale lottery, then FIFO (HI's design)

- ⭐⭐⭐ **Open the room BEFORE the sale but hold everyone until noon. At noon, randomly order everyone already waiting: 11:55 has no edge over 11:59:59. Anyone arriving after the start joins the back in FIFO order. Being there matters; racing to be first does not.**
- ⭐⭐ **One place per user: require an authenticated account, allow one active queue entry per user per sale, and put a CAPTCHA or bot challenge in front of the queue.**
- ⭐⭐ **The signed admission token stops anyone skipping ahead once the order exists.**
- ⭐⭐ **With the room sharded over several Redis instances the order must still be GLOBAL — shards must not decide independently. Give each user an ordering value that preserves the randomized pre-sale order, then FIFO for later arrivals.**

> ⚠ **What HI leaves loose.**
> 
> - ⊕ **Mechanism for the "ordering value": at join, a random score in [0, 1) before noon, else 1 + arrival time — no shuffle of 10M at noon, and the order is global.** ⊕ **To admit across shards without a merge, publish a score THRESHOLD; each shard admits entries up to it.** ▹ **Judgment call.**
> - ⚠⚠ **A lottery equalises accounts, not people: one person with 1,000 accounts holds 1,000 tickets.** ⊕ **CAPTCHA and login raise the cost; the real lever is verification per account (a phone, a payment method). Fraud is out of scope, but name the limit.**
> - ⚠ **📐 Everyone present has about a 0.1% chance (10,000 ÷ 10M). "Fair" does not mean "wins" — so tell the other 99.9% quickly (see DD3).**
> - ⚠ **The "noon" boundary for the ordering must come from server time, not the client.**
> 
> ■ **— end of insert · HI write-up resumes below —**

---

## 6 · Final Design

⚠ **Layout and arrows are mine; components are HI's.**

```
Client ──► CDN / cache ⊕ (static product page)
   │
   │ join (before noon)                                   poll status
   ▼                                                           │
API Gateway ──► Waiting Room Service ──► Redis × N (shards)   ◄┘   ⭐⭐⭐ score = random if pre-sale,
   │   ▲            admission controller: ~8k/s (⊕ or stock-based)       else 1 + arrival time
   │   └─ ⭐⭐⭐ signed admission token (⊕ single-use) validated here
   │
   │ POST /products/:id/reservations     (token required)
   ▼
Sale Service ──► Postgres (one transactional source of truth)
                   ├─ ReservationUnit (productId, unitId)   ⭐⭐⭐ SELECT … FOR UPDATE SKIP LOCKED
                   ├─ Reservation  (ACTIVE / PURCHASED / EXPIRED, expiresAt)   ⚠ ⊕ UNIQUE ACTIVE per (user, product)
                   ├─ Purchase     (PENDING / COMPLETE / FAILED)
                   └─ ⭐⭐⭐ empty pool ⇒ ONE request (advisory lock per product) reclaims expired reservations
                                        ⊕ skipping any with a PENDING purchase

POST /reservations/:id/purchases ──► Stripe PaymentIntent ──► client pays Stripe directly
                                                  └──► webhook ──► Sale Service (⊕ conditional transition; refund if the lease died)
Client ── GET /purchases/:id (poll ~1s) ──► final status

📐 10,000 ÷ 8,000/s ≈ 1.25 s to hand out every unit · 10M ÷ 8,000/s ≈ 21 min to drain the queue
⊕ I added: CDN for the product page · single-use token · one ACTIVE reservation per user · lease pin during payment · sold-out flag + reclaim backstop · score-threshold admission
```

---

## 7 · Expected at Each Level

|Level|The bar for Flash Sale|
|---|---|
|**Mid-level**|**A complete end-to-end design: view, reserve, purchase, no overselling. Understand that check-and-decrement must be atomic; the interviewer may guide you to hot-row contention, admission control or expiry. A simple cleanup job is enough; landing on `SKIP LOCKED` or a waiting room is a bonus.**|
|**Senior**|**Move fast through the basics; spot the hot `inventoryCount` row, Redis vs `SKIP LOCKED`, clean expiry, the datastore's finite ceiling; if pushed, a virtual waiting room, with trade-offs defended.**|
|**Staff+**|**Drive nearly every dive unprompted: invariant under contention, capacity numbers, reclamation without new bottlenecks, a waiting room, and fairness (pre-sale randomization, FIFO, duplicates, bots, global order).**|

> ⚠ **HI's bars never mention the payment-vs-expiry race or the sold-out/reclaim interaction. Naming them is how you read above the bar.**
> 
> ■ **— end of insert · HI write-up resumes below —**

---

## Quick Recall (pass 3+)

|Use / Question|Flash Sale answer|
|---|---|
|Calibration|**Evan King · Sep 2026 · ⭐⭐ "hard" · no "Asked at" tag · ⭐⭐ three patterns: `03a` Real-time Updates (⊕ derived), `03b` Contention, `03e` Scaling Writes.** ⭐⭐ **TWO passes. Order: DD1 > DD3 > DD2 > §4.3 > DD4**|
|⭐⭐⭐ Design driver|⭐⭐⭐ **A tiny stock, a crowd that arrives at once, and a payment that takes seconds.** **Slow third-party payment ⇒ a reservation (lease) · millions on 10,000 units ⇒ a pool of claimable rows (DD1) · abandoned holds ⇒ expiry + lazy reclaim (DD2) · finite DB ceiling ⇒ waiting room + signed token (DD3) · the queue picks winners ⇒ pre-sale lottery then FIFO (DD4) · ⊕ payment can outlive the lease ⇒ pin it**|
|📐 Numbers|**10,000 units · 10M users · 10-minute hold · DB ~10k tx/s · admit ~8k/s.** 📐 ⊕ **10,000 ÷ 8,000 ≈ 1.25 s to reserve every unit · 10M ÷ 8,000 = 1,250 s ≈ 21 min to drain the queue · 0.1% chance per user · ≤ 10k pollers ⇒ ≤ 10k req/s · 10M polling every 5 s = 2M req/s ⇒ 10–20 Redis shards**|
|FRs / NFRs|**View the item · reserve a unit for a limited time · pay for a reserved unit.** Below: catalog, shipping/returns/refunds, admin. **NFRs: ⭐⭐⭐ no overselling under contention · ⭐⭐⭐ millions arriving within seconds · ⭐⭐ fairness.** Below: GDPR, fault tolerance, secure transactions. ⚠ **FR2 is the one candidates miss: payment is slow and third-party, no open transaction across it**|
|Entities + API|**Product · Reservation · Purchase · User (+ ReservationUnit, DD1).** `GET /products/:id` · `POST /products/:id/reservations -> {reservationId, productId, expiresAt}` · `POST /reservations/:id/purchases`. ⚠ **No idempotency keys; no per-user limit; `quantity` unused; no `unitId` on Reservation; waiting-room endpoints missing; Purchase needs the client secret**|
|⭐⭐ §4.1 — view|**Client → Gateway → Sale Service → Postgres; `GET` returns the Product with `inventoryCount`.** ⚠⚠ **Tens of millions of reads hit Postgres at noon — HI never fixes it ⇒ ⊕ CDN + cached, eventually consistent availability.** ⚠⚠ **After DD1 there is no `inventoryCount` — where does "units left" come from?**|
|⭐⭐⭐ §4.2 — reserve|**One transaction: check on sale and in stock ⇒ insert Reservation (expiry ~10 min) ⇒ decrement ⇒ commit; check and decrement can't separate or two users take the last unit. Cron expires ACTIVE reservations and returns units, in one transaction.** ⚠ **DB clock, not app clock. ⚠⚠ ⊕ UNIQUE ACTIVE reservation per (user, product)**|
|⭐⭐⭐ §4.3 — purchase|**Purchase PENDING ⇒ Stripe PaymentIntent ⇒ client secret ⇒ client pays Stripe ⇒ webhook ⇒ Purchase COMPLETE + Reservation PURCHASED; failure ⇒ FAILED, the reservation stays active for a retry. Client polls `GET /purchases/:id` ~1/s (Real-time Updates: tiny waiting set, seconds ⇒ polling over SSE)**|
|⚠⚠ §4.3 — loose ends|⚠⚠ **A payment can finish AFTER the reservation expired and its unit was reassigned ⇒ ⊕ pin the lease while a purchase is PENDING; webhook does `status = PURCHASED WHERE status = ACTIVE`; zero rows ⇒ refund.** ⚠⚠ **No idempotency: unique non-failed Purchase per reservation + Stripe idempotency key; webhooks redeliver.** ⚠ **Two tables ⇒ one transaction. Pollers can be 10,000, not "a few thousand"**|
|⭐⭐⭐ DD1 — baseline + contention|**`UPDATE … SET inventoryCount = inventoryCount - 1 WHERE … AND inventoryCount > 0` is correct but every request serialises on one row (HI: ten registers vs one). Invariant: never more reservations than inventory.** ▸ **`03b`**|
|⭐⭐ DD1 — Redis counter|**`available:{productId}`; sorted set of reservations by `expiresAt`; check + decrement + write in one Lua script; one key does ~an order of magnitude more ops/s than a Postgres row.** ⚠⚠ **Challenges: state split across two systems (Redis is now source of truth; durability, reconciliation); still serial on one key (hundreds of thousands ops/s).** ⚠⚠ **Async replication ⇒ a failover can lose decrements ⇒ oversell**|
|⭐⭐⭐ DD1 — ReservationUnit + SKIP LOCKED|⭐⭐⭐ **One row per unit; claim any free row. `LIMIT 1 FOR UPDATE` convoys on the first row (and under READ COMMITTED a waiter can see "no row" ⇒ false sold-out); `FOR UPDATE SKIP LOCKED` skips locked rows so claims run in parallel. One transaction: select ⇒ delete unit ⇒ insert Reservation ⇒ commit. Challenges: many rows (bounded pool at scale), DB still finite (⇒ DD3). HI picks it: one transactional source of truth (Shopify did the same)**|
|⚠ DD1 — loose ends|⚠⚠ **HI's cashier analogy is a SHARDED counter — never applied to Redis (⊕ ten keys of 1,000, steal when empty). The pool is the bucket-size-one case; its real win is one source of truth.** ⚠ **`SKIP LOCKED` returns an arbitrary row (fine for fungible units, wrong for seats); claims scan past locked rows. "Order of magnitude" has no numbers ⇒ load-test. ⊕ `unitId` on the Reservation**|
|⭐⭐ DD2 — release expired holds|⚠ **Cron: 12:10:01 expiry, 12:10:10 run ⇒ 9 s of false "sold out".** ⭐⭐ **Delayed SQS message per reservation + worker transaction (still ACTIVE and expired? ⇒ EXPIRED + return unit); Temporal timer is the durable alternative. ⚠ Millions of delayed messages, inexact timing; ⊕ SQS delay max 15 min.** ⭐⭐⭐ **Pick: lazy reclaim — pool empty ⇒ reclaim a batch of expired reservations, keep ONE for this request, return the rest; ONE request per product holds an advisory lock, the others retry**|
|⚠⚠ DD2 — loose ends|⚠⚠ **Lazy reclaim runs only when someone tries to reserve — with the sold-out short-circuit (DD3) nobody does ⇒ expired units idle ⇒ ⊕ backstop sweep or a trickle of admissions.** ⚠⚠ **Reclaim must skip reservations with a PENDING purchase.** ⚠ **Index (productId, status, expiresAt); `SKIP LOCKED` on the batch; retry storm of waiters.** ✅ **Idempotent via the status check**|
|⭐⭐⭐ DD3 — scale|⭐⭐ **DB ceiling ~10k tx/s; unlimited arrivals ⇒ pile-up, latency, timeouts; no clever query helps ⇒ cap what reaches it.** ⭐ **Good: gateway rate limit + 429 — ⚠ thundering herd of retries.** ⭐⭐⭐ **Great: waiting room. Separate Waiting Room Service + Redis (status polling is huge), admission controller ~8k/s (headroom), SIGNED short-lived token (userId, productId, expiry) verified at the Gateway with no DB lookup; after admission the reservation call is unchanged. Challenges: the rate to choose; the room now decides who wins ⇒ DD4.** ▸ **`03e`; token = Ad Click DD3**|
|⚠⚠ DD3 — loose ends|⚠⚠ **📐 10,000 ÷ 8,000/s ≈ 1.25 s to hand out all stock; 10M ÷ 8,000 ≈ 21 min of pointless transactions ⇒ ⊕ sold-out flag (see DD2).** ⚠⚠ **Fixed rate tied to DB, not to stock ⇒ ⊕ admit by free units × overbooking factor.** ⚠⚠ **Token not single-use ⇒ ⊕ nonce via `SET NX`; one ACTIVE reservation per user.** ⚠ **📐 2M polls/s ⇒ 10–20 shards; jitter, long-poll/SSE, CDN page.** ⚠ **Joining at noon is itself a 10M write storm**|
|⭐⭐ DD4 — fairness|⚠ **Pure FIFO: the first milliseconds become a race on latency and bots.** ⭐⭐⭐ **Pick: open the room before the sale, hold everyone until noon, randomly order those present (11:55 = 11:59:59), FIFO for later arrivals. One entry per user (authenticated account), CAPTCHA, signed token stops skipping. Sharded room ⇒ ordering stays global via an ordering value**|
|⚠ DD4 — loose ends|⊕ **Score = random [0,1) if before noon, else 1 + arrival time ⇒ no shuffle at noon; admit by score THRESHOLD per shard (no global merge).** ⚠⚠ **A lottery equalises accounts, not people: verification per account is the real lever (fraud out of scope).** ⚠ **📐 0.1% win chance per user ⇒ tell the rest "sold out" quickly. Server time sets "noon"**|
|⭐⭐⭐ The meta-lesson|⭐⭐⭐ **Four ideas outlive this problem: (1) reserve first, settle later — a lease needs expiry, reclaim, and protection while a payment is in flight; (2) one hot counter becomes many independently claimable rows; (3) a system's ceiling is protected by holding users upstream, not by 429s — and the queue needs a signed token; (4) reclaim lazily, when someone needs the thing. Plus fairness is something you design**|
|Levels (one line)|**Mid (80/20):** end-to-end, atomic check-and-decrement, simple cleanup job · **Senior:** hot row, Redis vs `SKIP LOCKED`, expiry, admission control, waiting room · **Staff+:** drive every dive; capacity numbers; lazy reclaim without new bottlenecks; fairness (lottery, FIFO, duplicates, bots, global order)|

---

> 🔗 **HI source:** https://www.hellointerview.com/learn/system-design/problem-breakdowns/flash-sale