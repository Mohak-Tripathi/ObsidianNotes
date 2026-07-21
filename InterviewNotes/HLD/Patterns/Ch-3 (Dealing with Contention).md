# Dealing with Contention

> Hello Interview · **Patterns** · File `03b`. Overview → `03 §3`. Redis lock → `02a §2`; distributed lock concept → `02 §8`; consistent hashing → `01g`; isolation/consistency → `01h`. **Calibration:** ⭐⭐⭐ **Critical — THE fintech pattern.** Double-charge, double-spend, wallet-balance safety, inventory decrement, idempotency all live here. A Razorpay/CRED-shaped prompt hits contention almost immediately. Learn this one deeply. ▸ **The governing idea (three sentences that carry the whole file):**
> 
> 1. Every contention bug is a **lost update** — a read-modify-write where the gap between read and write lets someone slip in.
> 2. Every fix is the same move — **compare-and-set**: make your write **conditional on the value not having changed** since you read it.
> 3. It all works only because the contended thing has **one authoritative home** (a single row/key/cell). Your #1 job is to make sure that home exists; then escalate tools only as the gap you must protect grows.

---

## The Race Condition — the "lost update"

▸ **CRUX** — one seat left, Alice and Bob both hit Buy. Naive flow: **read** count (both see 1) → **check** > 0 (both pass) → **write** decrement. Alice commits (1→0), Bob commits against the stale read (0→−1). **Both cards charged, both get seat A15.** One gets kicked out, venue eats a refund.

▹ **The culprit is the gap.** Reading the count and writing the new value aren't one action — the world changes in between. Bob reads a number Alice is about to invalidate and acts on stale data. The window is microseconds in memory, milliseconds over a network — enough. ⚠ **It only gets worse with scale** — 10k concurrent users on the same row, then coordination **across nodes**.

### Where it shows up (HI breakdowns)

- Ticketmaster · Online Auction · Rate Limiter · Online Chess.
- ⭐ **Fintech:** payment processing (no double-charge), wallet/balance updates, flash-sale inventory, seat/room reservations.

---

## The unifying move — compare-and-set, then escalate

▸ Every tool below closes the read→write gap the same way: **read a value, make the write conditional on it not having changed.** Start with the simplest; add coordination **only as each approach hits its limit.**

- SQL spells compare-and-set as a **`WHERE` clause**. The same move elsewhere: DynamoDB **`ConditionExpression`**, Redis **`SET NX`**, Cassandra **lightweight transaction**, HTTP **`If-Match`**.

---

## Rung 1 — Conditional Writes _(reach for this FIRST)_

▸ **CRUX** — when your rule is an **`if` about the current data**, the DB can check it and make the change in **one atomic statement** — no locks, no version numbers.

```sql
UPDATE concerts SET available_seats = available_seats - 1
WHERE concert_id = 'weeknd_tour' AND available_seats > 0;
```

▸ **Why it's already concurrency-safe:** the DB won't let two updates change the same row at once — it makes them **take turns.** Alice goes 1→0; Bob **waits**, re-checks `> 0` against the row Alice left, finds it false, **matches zero rows.** Check + decrement are a single atomic step → no gap to slip into.

▸ **Bundling multiple writes → transaction.** A real purchase also inserts a ticket row — two writes that must stick together. Wrap in `BEGIN`/`COMMIT`. ⚠ **The trap:** an `UPDATE` matching **zero rows is NOT an error** — it "succeeds" having done nothing. Run the `INSERT` unconditionally and Bob's failed decrement **still creates a ticket for a seat he never got.**

- **Fix:** make the insert **depend on whether the update changed anything** — a CTE with `RETURNING` feeding `INSERT ... SELECT`, or check the affected-row count and roll back when it's zero.

⚠ **The lesson worth memorizing — guard the thing actually being contended.**

- 20 seats left, Alice & Bob both grab seat **A15**. Both decrements pass (20>0, 19>0), both inserts write **A15**. Count is perfect; **two people own A15.** The DB did nothing wrong — you never told it A15 was contendable.
- **Fix:** give **every seat its own row** and aim the conditional write at the **ticket**, not the counter:

```sql
UPDATE tickets SET status='sold', user_id='user123'
WHERE concert_id='weeknd_tour' AND seat_number='A15' AND status='available';
```

- ▸ **A counter can answer "is there a seat left." Only the ticket row can answer "is THIS seat left."** The seat count becomes derived/cached data.

⚠ **The limit:** the DB can only enforce a rule it can read in a **`WHERE` clause.** Plenty of real decisions can't be written that way → Rung 2.

> ▹ **In plain words (SQL-light recap):**
> 
> - Normally you **read → think → write** (three steps, gaps in between). A conditional write folds the **check and the change into one uninterrupted step** — that's **compare-and-set**.
> - `SET available_seats = available_seats - 1` = "new value = old − 1." The extra line `AND available_seats > 0` = "but only if a seat is still left." The DB does the check **and** the subtract as **one atomic action** — no gap.
> - **Why it's safe with no lock:** the DB won't let two writes touch the **same row** at once — it makes them **take turns** (one bathroom, one key). Bob's write **waits**, then re-checks `> 0` against the value Alice _left behind_ (now 0) → fails → **changes nothing**. The check runs at write time against the latest value, not Bob's stale read.
> - ⚠ **The trap:** an `UPDATE` that matches **0 rows is not an error** — it "succeeds" doing nothing. So a blind `INSERT` after it still creates a ticket for a seat nobody got. **Fix:** chain the insert to the update (the `WITH … RETURNING` block), **or simpler** — check "rows affected" in your app code and roll back if it's `0`. _(For SQL-light comfort, use the app-code check.)_
> - ▸ **The real lesson — guard the RIGHT thing.** `available_seats > 0` only protects the **count** ("is there _a_ seat"). It can't stop two people both grabbing **A15**. Give each seat **its own row** and aim the same conditional write at that row (`… AND status='available'`) → whoever flips it to `sold` first wins. _A counter answers "is there a seat"; only the seat's row answers "is THIS seat left."_

---

## Rung 2 — Pessimistic Locking

▸ **CRUX** — when the decision is **application logic** (find four _adjacent_ open seats), read and write **can't collapse into one statement** — the middle step runs in your app. Two groups both read the map, both pick A15–A18, both claim it → lost update again.

- **Fix:** `SELECT ... FOR UPDATE` **locks the rows you read** so you can decide while they're held still, then write before releasing.

```sql
BEGIN;
SELECT seat_number FROM seats
WHERE concert_id='weeknd_tour' AND section='floor' AND status='available'
FOR UPDATE;                 -- locks every returned row
-- app finds A15–A18 adjacent, then:
UPDATE seats SET status='sold', user_id='user123'
WHERE seat_number IN ('A15','A16','A17','A18');
COMMIT;
```

▸ **"Pessimistic"** = assume conflict, **block it upfront.** The shape covers any **read-decide-write** where the decision isn't a predicate: checking a balance against a daily limit before moving money, reading stock across items before claiming a bundle. ▸ ▹ **If your logic ever simplifies back to a single `WHERE`, drop the lock** and return to a conditional write. Don't pay for a lock you don't need.

⚠ **Two failure modes (the interviewer will probe these):**

- **Locking too much, for too long.** A lock only buys safety for the **rows it covers** and the **time it's held** — keep both minimal.
    - Lock a whole table → you serialize every writer.
    - Hold for seconds not ms → buyers pile into a bottleneck.
    - **Worst offender: slow I/O.** A payment API call **inside** the transaction makes everyone wait on a third party's latency → do external work **before** taking or **after** releasing the lock.
- **Deadlocks from inconsistent ordering.** Two txns grab the same rows in **opposite orders** → each holds one, waits forever on the other.
    - **Fix:** always acquire locks in a **consistent order** (sorted by ID). DB **detects the cycle and kills one** → treat the error as **retryable.** _(Full walkthrough in Deep Dives.)_

⚠ **The real cost:** **every** transaction pays for the lock — including the vast majority that were never going to collide. You're buying insurance on every purchase against an event that almost never happens → Rung 3.

> ▹ **In plain words (SQL-light recap):**
> 
> - `SELECT … FOR UPDATE` = a normal read **plus** a **"reserved / being-decided" sticky note** on every row it returns. While your transaction is open, anyone else trying those rows **waits in line** (no error, just pauses) until you `COMMIT`, which also **peels the notes off**.
> - **Line by line:** `BEGIN` (open bundle) → `SELECT … status='available' FOR UPDATE` (fetch free seats **and lock them**) → _your app scans the list, finds A15–A18 adjacent_ → `UPDATE … WHERE seat_number IN (…)` (mark those sold) → `COMMIT` (finalize + release). `IN (…)` = "any of these values."
> - **Why lock at all?** On Rung 1 the DB could check the rule itself (`> 0`) → one statement, no lock. Here the decision — _"which 4 seats are adjacent and free?"_ — runs in **your code between read and write**, and the DB **can't put that in a `WHERE`**. So you lock the rows, decide while they're **held still**, then write.
> - ⚠ **The catch:** to grab **4** seats you locked **every** free seat in the section → under heavy traffic everyone **queues here** (serializes). That cost is what pushes you to OCC next.
> - ▸ Same shape for any **read-decide-write** that isn't a predicate (balance vs daily limit, stock across items for a bundle). If it ever simplifies to a single `WHERE`, **drop the lock**.
> - **One-line hold:** _DB can check it → one statement, no lock (Rung 1). YOU must decide in code → lock the rows so they can't move while you think (Rung 2)._

---

## Rung 3 — Optimistic Concurrency Control (OCC)

▸ **CRUX** — the **opposite bet**: conflicts are **rare**, so **detect after the fact** instead of blocking. Let everyone proceed; catch the collision **at write time.**

- **Mechanism:** keep one value that **changes on every write** (a **version**). Read it; write **only if it's still what you read.** Someone slipped in → they bumped it → your `WHERE` matches nothing → **zero rows → retry.**

```sql
-- both read version 42
UPDATE concerts SET available_seats = available_seats - 1, version = version + 1
WHERE concert_id='weeknd_tour' AND version = 42;
-- Alice: 1 row, version→43.  Bob: 0 rows (row is on 43) → roll back, retry/​sold-out.
```

⚠ Same **zero-rows-isn't-an-error** trap → check affected count, roll back, skip the insert.

▸ **What can serve as the version:**

- **Dedicated integer** bumped every write → the **safe default.**
- **Last-updated timestamp** — only if every write touches it and clock resolution is fine enough.
- **A business value you already track** (seat count, high bid) — **only if it moves in one direction.**

⚠ **The ABA problem** (a favorite deep-dive): a business value goes **A→B→A** between your read and write; an equality check **can't tell anything happened.** Balance $100→$50→$100 → your check passes though the account changed meaningfully. → Use a **dedicated ever-incrementing version** when in doubt.

▸ **Pessimistic vs OCC — the deciding question is collision frequency:**

- Collisions **common** → **lock upfront** (constant retries cost more than the lock).
- Collisions **rare** (most e-commerce) → **OCC**, eat the occasional retry.

---

## Rung 4 — Isolation Levels (for write skew)

▸ **CRUX** — sometimes two txns read an **overlapping set of rows**, each makes a decision valid on its own, and **only together** do they break a rule — but **no single row collides.** Conditional write, row lock, and version check **all sail through.** This is **write skew.**

- **On-call example:** rule = ≥1 engineer on call. Alice & Bob both on call, both try to step down. Each reads the schedule, sees the _other_ still on, removes **themselves** (different rows). Both commit → **nobody on call.** Neither did anything wrong alone.
- ▸ The conflict is in **what they read to decide**, not a shared write.

> ▹ **Why "all three sail straight through" (the key line):** conditional UPDATE, row lock, and version check are **all armed to watch ONE specific row** — "did _this_ row change under me?"
> 
> - **Conditional UPDATE** — `WHERE status='available'` guards **the row it writes**.
> - **Row lock** (`FOR UPDATE`) — locks **the rows it selected**.
> - **Version check** — `WHERE version=42` on **the row it writes**.
> - In write skew the two txns **write different rows** (Alice's row · Bob's row), so there's **no same-row collision for any of them to catch** → all three pass, both commit, rule breaks. The conflict is between **one txn's write and the other's read**, on different rows — and **none of the three watch your reads.** That blind spot **is** write skew.
> - **Fix:** **SERIALIZABLE** tracks read-write dependencies _across_ rows → notices both leaned on data the other changed → aborts one. **Cheaper:** collapse the invariant onto **one shared row** (an `on_call_count` both must update) → now they _do_ collide → the simple tools work again.

▸ **The four standard levels** _(options, not a ladder to climb — → `01h`)_:

|Level|Sees|Note|
|---|---|---|
|READ UNCOMMITTED|uncommitted changes of others|rarely used|
|READ COMMITTED|only committed changes|**Postgres default**|
|REPEATABLE READ|repeated reads stay consistent|**MySQL default**|
|SERIALIZABLE|as if txns ran one-at-a-time|**the only one that catches write skew**|

⚠ **SERIALIZABLE isn't free — three things to know before reaching for it:**

▸ **1. It's the most expensive tool.** To catch write skew the DB must **track every row each transaction reads _and_ writes**, then check whether two overlapping transactions stepped on each other.

- That bookkeeping costs CPU/memory.
- On a clash it **aborts one transaction** → all its work is thrown away and **retried**. Under heavy contention, many aborts = lots of wasted-and-redone work.

▸ **2. It could solve the earlier rungs too — but don't use it for them.** SERIALIZABLE is the _strongest_ guarantee (txns behave as if run one-at-a-time), so it would **also** prevent the plain lost update (Rung 1) and the read-decide-write races (Rungs 2–3).

- ▸ **But pessimistic locking / OCC solve those same-row problems far more cheaply.** So: **try the cheaper rung first; climb to SERIALIZABLE only for the one thing they genuinely can't catch — cross-row write skew.**

▸ **3. It's relational-only.** Isolation levels are a **relational-DB feature** (Postgres, MySQL). Most **NoSQL / distributed** stores (DynamoDB, Cassandra…) **don't offer true SERIALIZABLE.**

- So on those you **can't use this rung at all** → your only option is the cheaper move anyway: **fold the invariant onto a single cell/item** and guard it directly (conditional write / version check).

▸ **The cheaper fix even when you DO have SERIALIZABLE — materialize the conflict onto ONE row.** Restructure so the invariant lands on a single guardable cell:

- On-call: instead of each engineer's **own** row, keep an `active_count` on the **team row**. Both step-downs now decrement **the same row** → they **collide** → a conditional write (`WHERE active_count > 1`) or a `FOR UPDATE` on that row handles it with the **cheap** tools.
- ▸ This converts a **cross-row** invariant into **same-row** contention — the exact seat-example lesson (each seat its own row = the only way the DB could tell two A15 buyers apart).
- ▸ **The principle:** the DB can only protect a conflict it can **see as a single cell.** Your job in all of this is to **make the contended thing that single cell** (row / key / item).

---

## Rung 5 — Distributed Locks

▸ **CRUX** — every tool so far lives **inside one DB transaction**, and a DB lock lasts only as long as that transaction. Sometimes you must hold exclusive access across something a transaction **can't span** — the classic **10-minute seat hold during checkout.**

- ⚠ `FOR UPDATE` can't: it **pins a connection** for 10 minutes, stalls every other txn needing the row, and is **invisible to your other stateless web servers.**
- **Fix:** stop holding the lock as a _transaction_ and hold it as **data** — a **lease** (who holds it + when it expires) that **any server can read** and that **outlives any single transaction.** That's a distributed lock. _(Concept → `02 §8`.)_

▸ **Where the lease lives — three options, trading speed / infra / failure-handling:**

|Store|How|Advantage|⚠ Disadvantage|
|---|---|---|---|
|**Redis (TTL)**|`SET key holder NX EX 600` — atomic, auto-expires|fast, simple, any server reads the key|**not airtight** — holder stalls past TTL (GC pause, slow net) → Redis re-grants → **two holders**; SPOF _(→ `02a §2`)_|
|**DB columns**|`reserved_by` + `reserved_until`; conditional write claims if free or lapsed|no new infra, same consistency as your data; expiry in the `WHERE` = no cleanup job|writes slower than cache; the **lock row becomes a contention point** under load|
|**ZooKeeper / etcd**|ephemeral nodes + consensus (ZAB / Raft)|robust — strong consistency through partitions/leader failure; **auto-cleanup** on session end|**operational complexity** — run a separate coordination cluster|

⚠ **The Redis caveat matters for fintech:** a TTL lock is an **efficiency tool, not a correctness guarantee.** Fine for a **soft** seat hold (a rare double-grant is harmless); **never** where a double-grant would **corrupt data / money** — enforce that invariant where the data lives (conditional write / OCC in the DB) or use ZooKeeper/etcd. _(Same conclusion as `02a §2`.)_ ▸ ▹ Reservations are a **UX win** too — they shrink the fight window from the whole checkout down to the **instant of selection**, so nobody fills out payment only to lose the seat.

#### ▹ DB-column lock in depth (the option you'll most likely reach for)

▸ **The idea:** hold the lock as **two columns on the seat row** — `reserved_by` (who, or `NULL` = free) + `reserved_until` (expiry) — instead of a separate system.

```sql
UPDATE seats
SET reserved_by = 'user123',
    reserved_until = NOW() + INTERVAL '10 minutes'          -- claim for 10 min
WHERE seat_id = 'A15'
  AND (reserved_until IS NULL OR reserved_until < NOW());    -- ...only if free
```

- `NOW() + INTERVAL '10 minutes'` = a timestamp 10 min ahead → stamps "reserved until then."
- The `WHERE` **is** the safety: claim **only if** `reserved_until IS NULL` (never reserved) **or** `reserved_until < NOW()` (prior hold **already expired** → treat as free).
- ▸ This is just **Rung 1's compare-and-set reused** — check + claim in one atomic statement.

▸ **How you learn if you won — the rows-affected count:**

```javascript
const result = await db.query(`
  UPDATE seats
  SET reserved_by = $1, reserved_until = NOW() + INTERVAL '10 minutes'
  WHERE seat_id = $2
    AND (reserved_until IS NULL OR reserved_until < NOW())
`, ['user123', 'A15']);

if (result.rowCount === 1) { /* got the hold → checkout */ }
else                       { /* 0 rows → someone holds a live hold → "seat taken" */ }
```

- **1 row = you got it · 0 rows = taken.** (Same "0 rows isn't an error, check the count" rule as Rung 1.)

▸ **Expiry needs no cleanup job.** Because expiry is checked **in the `WHERE`** (`reserved_until < NOW()`), a lapsed hold **auto-reads as free** for the next claimant — their `WHERE` sees the stale timestamp and overwrites it. **Time releases the lock.** (Explicit release on checkout = `SET reserved_by=NULL, reserved_until=NULL`.)

⚠ **Redis vs DB-column — same compare-and-set, different _where the check lives_ (your instinct was right):**

||Redis (`SET NX`)|DB-column|
|---|---|---|
|Mechanism|a **gate** — refuses the 2nd setter at the key level (purpose-built lock)|**emulated** — you attempt a conditional `UPDATE` and **read back `rowCount`**|
|Feel|**gate-first** (blocked before you act)|**try-then-check** (act, then find out you won)|
|Speed|µs, in-memory|slower, disk-backed write|
|Infra|a **separate** system|**none** — reuses your DB|
|Consistency|⚠ can double-grant on TTL stall|**same guarantees as your data** — no double-grant|

- ⚠ **"Try-then-check" is NOT a race** — the DB still serializes writes to row A15 (the take-turns rule), so exactly one concurrent claim gets `rowCount=1`. It's atomic and safe, just _optimistic in feel_.
- ▸ **Pick DB-column** when you're already on a DB, want no extra infra, and need the lock to have the **same correctness as your data** (money/inventory — no double-grant). **Pick Redis** for speed/offload when a rare double-grant is harmless.

⚠ **Does this work when the DB is SHARDED? Yes — because sharding splits ROWS, never a single row.**

- Seat A15 is **one row → lives entirely on one shard.** All the atomicity you need (serialize concurrent writes to A15, evaluate the `WHERE`, update-or-zero) happens **inside that one shard's engine.** The query behaves identically with 1 DB or 100 shards. _(This is the single-source-of-truth principle — the contended cell has one home.)_
- ⚠ **Two things must hold:**
    - The write must **target the shard key / row identity** (`WHERE seat_id='A15'` = point lookup → one shard), not filter on a non-shard-key column that scatters across shards.
    - Rows you lock **together** must be **co-located** — reserving A15 **and** A16 atomically needs them on the **same shard** (e.g. shard by `concert_id`). Otherwise it's a cross-shard transaction, which this pattern doesn't cover.
- ▸ **Where it genuinely breaks = the pattern boundary, not a flaw:** an invariant that must **atomically span multiple shards** (move money from an account on shard 1 to one on shard 3) is a **distributed transaction → `03g`.**
- ▹ Redis-cluster locks shard the same way — `lock:seat:A15` hashes to one node → safe for one key; neither Redis nor DB gives you a free **multi-shard** lock.
- ▸ **One-line hold:** _sharding never splits a single row, so a lock guarding one row is fully shard-safe; it only breaks when the invariant must atomically span rows on different shards — and that's `03g` territory, not this pattern._

---

## The escalation ladder (one table)

|Rung|In SQL|Same move elsewhere|
|---|---|---|
|Conditional write|`WHERE` predicate on the write|DynamoDB `ConditionExpression` · Redis `SET NX` · Cassandra LWT · HTTP `If-Match`|
|Optimistic concurrency|`version` column + `WHERE version = …`|HTTP `ETag`/`If-Match` · etcd revision · DynamoDB version attribute|
|Pessimistic locking|`SELECT … FOR UPDATE`|a mutex / distributed lock held while you decide|
|Serializable isolation|`ISOLATION LEVEL SERIALIZABLE`|mostly relational — elsewhere fold the invariant onto one cell|
|Distributed lock|reservation row with a TTL|Redis `SET NX EX` · ZooKeeper/etcd lease|

---

## The whole game — a single source of truth

▸ **Every technique aims at ONE authoritative home for the contended resource.** If you need strong consistency under contention, **keep the data in a single database first** — nine times out of ten that's possible, and a modern Postgres absorbs far more contention at one source of truth than people assume.

⚠ **Two situations genuinely break the single-home assumption — both live OUTSIDE this pattern:**

- **One operation must atomically span multiple services/shards** (transfer between two _sharded_ accounts) → that's a **distributed transaction → `03g` Multi-Step Processes.**
- **The same record is writable in multiple places at once** (multi-leader / leaderless replication) → no single home to defend → **conflict resolution** (last-write-wins, vector clocks, CRDTs) → a replication topic, beyond this pattern.
- ▸ **The boundary to state out loud:** the moment an operation spans **multiple sources of truth**, you've left contention and entered distributed-transaction territory.

---

## Choosing the right approach — walk down, take the first that fits

- **Check is a predicate on the row you're writing** (counter, status flip, claim a row) → **conditional write.** Simplest; reach first.
- **Read → decide in app code → write** (open block of seats; a value on another row), **high contention** → **pessimistic locking.**
- **Same read-decide-write, but collisions rare** → **OCC** (version/timestamp/one-way business value).
- **Invariant spans rows that never collide** (write skew) → **SERIALIZABLE**, or **materialize onto one row.**
- **Hold must outlive a single transaction** (reservation, external call, multi-step) → **distributed lock.**

|Approach|Use when|Avoid when|Latency|Complexity|
|---|---|---|---|---|
|**Conditional write**|check is a predicate on the written row|decision needs app logic / spans other rows|low (one atomic stmt)|low|
|**Pessimistic lock**|read-decide-write, not a `WHERE`; high contention|low contention, or a conditional write covers it|low/op, but others wait|low|
|**OCC**|same, but collisions rare; high read/write ratio|high contention (retries pile up)|low; retry cost on conflict|medium|
|**SERIALIZABLE**|write skew / cross-row invariant, no single row|hot high-contention paths (abort/retry cost)|medium (conflict tracking)|medium|
|**Distributed lock**|exclusivity spans a wait / external call / steps|a single-row guard in one txn already works|low (simple status writes)|medium|

▸ **Default:** keep it in a single DB and reach for the **simplest tool that fits** — conditional write if the check is a predicate, pessimistic locking once you have real read-decide-write. Tighten later.

---

## In interviews

▸ **Call contention out proactively** — usually when your **non-functional requirements** establish that the system needs **strong consistency.** Don't wait to be asked.

▸ **Recognition signals:**

- Multiple users competing for a limited resource (tickets, auction, flash-sale, driver-rider matching).
- Prevent double-booking / double-charging (payments, reservations, room scheduling).
- Consistency under high concurrency (balance updates, inventory).
- Race conditions where outcome is order-sensitive across servers.

▸ **Scenario → tool cheat-sheet:**

- **Auction** → **OCC**, current high bid as the version _(bids only rise → no ABA)_.
- **Ticketmaster** → **distributed lock** reservation, 10-min TTL (the UX win beats pure seat-select locking).
- ⭐ **Banking/Payments** → single-DB → **pessimistic or OCC here**; once it spans services/shards → **distributed transaction `03g`.**
- **Ride dispatch** → status `pending_request` with **TTL** (cache or expiry column) so a stale request reads as free, no cleanup job.
- **Flash sale** → **OCC** on inventory + cart **holds** (distributed lock TTL) to cut checkout contention.
- **Yelp rating** → **OCC** with a version column so concurrent reviews don't corrupt the average.

---

## When NOT to overcomplicate

⚠ **The common mistake: reaching for a distributed lock (Redis) when a DB transaction with row locking or OCC is enough.** New components = new failure modes.

- **Low contention** (admin edits a product description) → basic **OCC + retry.**
- **Single-user ops** (todo list, private doc, preferences) → **no coordination.**
- **Read-heavy** with occasional writes → **OCC** for the rare conflict.

---

## Common Deep Dives

▸ **"How do you prevent deadlocks with pessimistic locking?"**

- Bank transfer: A locks Alice→then Bob; B locks Bob→then Alice → circular wait.
- **Fix = ordered locking:** sort **all** resources by a deterministic global key (user ID / PK) and acquire in that order. ⚠ **Not "lock the initiator first"** — sort by the same key for everyone: if IDs are 123 and 456, **always lock 123 first**, whoever initiated.
- Even so, **treat deadlock as handled, not ruled out** — every major DB runs **auto-detection**, aborts one, you **retry the loser** with locks taken in order. A lock-wait **timeout** is a coarser backstop for "held too long," not a true cycle.

▸ **"How do you handle the ABA problem?"**

- **Dedicated version column** that increments on **every** update, regardless of business change → `SET …, version = version + 1 WHERE version = 42`.
- **Fallback** (no version column): put **every field you read** into the `WHERE` so the write applies only if the whole row still matches. Heavier, but catches the round trip.
- Some DBs expose a built-in row version (Postgres **`xmin`**).

▸ **"Performance when everyone wants the same resource?"** — the **hot partition / celebrity problem.**

- ⚠ **Normal scaling all breaks** here: **sharding** splits rows but everyone wants the _same_ row; **load balancing** just queues requests onto that row; **read replicas** don't help a **write** fight. _(Same phenomenon → `02a` hot key, `03e`.)_
- **First move — change the problem, not the infra:** maybe 10 identical items → 10 separate auctions; maybe likes/follows can be **eventually consistent** (a follow appearing a few seconds late is invisible).
- **If you truly need strong consistency on one hot resource → queue-based serialization:** funnel all requests for that resource into **one queue → one worker → sequential** processing. Eliminates contention by making it serial; the queue absorbs spikes.
    - ⚠ **Tradeoff = throughput, not just latency.** One worker caps the resource's max speed and is a **SPOF** (back it with a standby). Often the better deal than the whole system grinding to a halt.

---

## Quick Recall (pass 3+)

|Question|Answer|
|---|---|
|The one bug|**lost update** — read-modify-write with a gap; someone acts on a stale read|
|The one fix (all rungs)|**compare-and-set** — write conditional on the value being unchanged|
|The whole game|contended thing must have **one authoritative home** (row/key/cell); enforce there|
|Rung 1 — conditional write|`WHERE` predicate = atomic check+write; reach FIRST; ⚠ **guard the contended thing** (ticket row, not counter); 0-rows ≠ error|
|Rung 2 — pessimistic lock|`SELECT … FOR UPDATE` for **read-decide-write** (app logic); ⚠ lock small+short, **no slow I/O in txn**, order locks to avoid deadlock|
|Rung 3 — OCC|version column, retry on 0 rows; for **rare** collisions; ⚠ **ABA** → dedicated incrementing version|
|Rung 4 — isolation|**write skew** = cross-row invariant, no shared row → **SERIALIZABLE** (only level that catches it) or **materialize onto one row**|
|Rung 5 — distributed lock|hold **beyond a transaction** (10-min reservation); lease as data; Redis TTL / DB columns / ZooKeeper-etcd|
|↳ DB-column lock|`reserved_by`+`reserved_until`; conditional `UPDATE … WHERE reserved_until IS NULL OR < NOW()`; **rowCount 1 = won, 0 = taken**; expiry in `WHERE` = no cleanup job|
|↳ Redis vs DB-column|Redis = **gate** (blocked before acting) · DB = **try-then-check** (`rowCount`); DB slower but **same consistency as data** (no double-grant)|
|↳ works when sharded?|**yes** — sharding splits rows, never one row → a one-row lock stays on one shard. ⚠ breaks only if invariant spans **multiple shards** atomically → `03g`|
|Redis lock caveat|⚠ **efficiency, not correctness** — stall past TTL → double-grant; fine for soft holds, **never for money** (→ `02a §2`)|
|Pessimistic vs OCC|collisions **common → pessimistic** · **rare → OCC**|
|Escalation order|conditional write → OCC → pessimistic → SERIALIZABLE → distributed lock (simplest that fits)|
|Boundary (leaves this pattern)|atomic across services/shards → **distributed txn `03g`** · multi-leader writes → conflict resolution (CRDTs)|
|Deadlock fix|**ordered locking** by global key (not "initiator first") + DB auto-detect + retry loser|
|Hot resource / celebrity|scaling all fails (same row, writes); **change the problem** or **queue-based serialization** (1 worker, ⚠ throughput cap + SPOF) → `02a`, `03e`|
|Fintech home|money in **one DB** → conditional write / OCC / pessimistic **here**; spans services → **`03g`**|
|Interview trigger|flag during **NFR** when strong consistency required; name the tool per scenario|


QR => https://www.hellointerview.com/learn/system-design/patterns/dealing-with-contention/quick-reference