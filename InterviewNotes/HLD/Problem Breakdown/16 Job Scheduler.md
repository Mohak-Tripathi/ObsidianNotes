# Distributed Job Scheduler — Problem Breakdown

> 📐 **Revision note (calc):** the numbers here all defend one architectural choice. **10k jobs/sec · 2s precision · 3 retries.** ⭐⭐ **Why you can't just poll faster: polling every 2s means each query fetches ~20k jobs (10k/s × 2s), takes several hundred ms, and ~500ms gone before you even start work.** ⭐ **Queue capacity: 10k/s × 300s = 3M jobs per 5-min window × ~200 bytes = 600MB** — trivial for SQS. ⭐⭐ **Why the window is 5 minutes and not an hour: SQS `DelaySeconds` is capped at 15 minutes.** ⭐ **DynamoDB: 1,000 WCU per partition.** **Backoff: 5s → 25s → 125s. Visibility timeout 30s, heartbeat every 15s. Retention 1 year, then S3.** ⚠ **One figure of HI's is wrong — see the ⊕ note in §5.3 on the 50k lease updates.**

> Hello Interview · Question Breakdowns · File `05p`. **Evan King**, updated **Feb 15, 2026** · ⭐ **"medium"** · ⭐⭐ **asked at LinkedIn +22 more — 23 companies, by far the most-asked problem in the series.** ⭐⭐ **TWO Pattern callouts: `Managing Long Running Tasks` → `03g` and `Scaling Writes` → `03e`.** ⚠⚠ **First INFRA-style problem in the series — HI explicitly switches to the `Ch-1` delivery framework and adds a DATA FLOW step between the API and the HLD** (_"less of a user-facing product and more focused on data processing"_). Cross-refs: ⭐⭐ **definition-vs-instance split → `05d` GoPuff (HI names it explicitly)** · **DynamoDB, GSIs, WCU → `02f`** · **Cassandra → `02e`** · ⭐ **Redis ZSET → `02a`, and `05i §5.2` / `05k §5.4` for the structure** · ⚠ **Kafka, and why NOT here → `02c`** · **write sharding → `01f`** · **GSI / indexing → `01d`** · ⭐ **job leasing IS distributed locking → `03b`** · **cold storage → `01a`** · **CAP → `01h`** · **API design → `01b`** · **API Gateway → `02d`** · **numbers → `01i`.** **Siblings: `05i` LeetCode (SQS work queue, containers-vs-Lambda, the "is this queue overkill" debate — ⚠ and HI answers it the OPPOSITE way here) · `05e` Ticketmaster (the lease/hold pattern) · `05d` GoPuff.**
> 
> **Calibration:** ⭐⭐ **The highest-value file so far, and the one place to spend real time.** ▸ **Three reasons: (1) 23 companies ask it (2) all three deep dives are substantial, each with a genuine ladder — unlike `05i`/`05k`, nothing here is padding (3) the two-layered architecture is a primitive you'll reuse.** ⭐ **Give it TWO passes.** ▹ ⭐⭐ **And HI's Senior bar is unusually specific about what to be able to say** — _"specifically be able to articulate the need for a two-phased architecture"_ — ▸ **so rehearse that one sentence.**
> 
> - ⭐⭐ **What actually scores:**
>     - **(a)** ⭐⭐ **Splitting Jobs (definition) from Executions (instances)** (§4.1) — ▸ **the single best idea in the file, and the most transferable.**
>     - **(b)** ⭐⭐ **`time_bucket` as the partition key**, and ⭐ **knowing it creates a hot partition that write sharding fixes.**
>     - **(c)** ⭐⭐ **The two-layered scheduler — DB for durability, queue for precision** (§5.1). ▸ **Named by HI as the senior bar.**
>     - **(d)** ⭐⭐ **Why a LOG queue can't do this** — **Kafka orders within a partition, so a job due sooner queues behind everything already there.**
>     - **(e)** ⭐⭐ **Visible vs invisible failure as a named taxonomy** (§5.3), and **a different mechanism for each.**
>     - **(f)** ⭐⭐ **Visibility timeout + `ChangeMessageVisibility` heartbeat** — ▸ **worker crash recovery with zero extra infrastructure.**
>     - **(g)** ⭐ **At-least-once FORCES idempotency**, and ⭐ **the right answer is to push it into the task, not the scheduler.**
> - ⭐ **Transferable primitives:**
>     - ⭐⭐ **Separate a definition from its instances.** ▸ **A CRON expression is a definition; a row per firing is an instance.** ⭐ **Querying instances is cheap; evaluating definitions is not.** ▹ **HI's own list: calendars (event vs occurrences), notifications (template vs sent), `05d` GoPuff.**
>     - ⭐⭐ **Durability and precision want different stores — so use both, and move work between them in slices.** ▸ **The DB is the source of truth, the queue is the delivery mechanism.** ⭐ **Fourth appearance of the two-layer shape** (`05e`, `05h`, `05i`, now here).
>     - ⭐⭐ **A log is not a work queue.** ▸ **An ordered, replayable log gives you head-of-line blocking and no per-message delay. A task queue gives you delayed delivery, per-message ack and redelivery.** ⭐ **Pick by which you need.**
>     - ⭐⭐ **Bucket a timestamp to make time queryable.** ▸ **`(t // 3600) * 3600` turns "find everything due soon" into 1–2 partition reads.**
>     - ⭐ **A failure you can see and a failure you can't need different mechanisms.** ▸ **try/catch for the first; a timeout someone else owns for the second.**
>     - ⭐ **Push idempotency down to the thing being executed.** ▸ **"set counter to X" instead of "increment counter."**
> - ⭐ **Re-run (cross-ref, NOT re-explained):** **DynamoDB GSIs (`02f`, `05i §4.4`)** · **SQS as a work queue + containers-vs-Lambda (`05i §5.3`)** · **Redis sorted sets (`05i §5.2`, `05k §5.4`)** · **distributed locking / leases (`03b`, `05e`)** · **definition-vs-instance (`05d`)** · **cold-storage tiering (`01a`, `05k §5.2`)** · **write sharding (`01f`)**. **Genuinely new:** ⭐⭐ **Task vs Job vs Execution as three levels** · ⭐⭐ **`time_bucket` partition key + the rounding formula** · ⭐⭐ **the two-layered scheduler** · ⭐⭐ **delayed delivery / `DelaySeconds` and its 15-min cap** · ⭐⭐ **why log queues fail at scheduling** · ⭐⭐ **visibility timeout + heartbeat extension** · ⭐ **`ApproximateReceiveCount` for retry counting** · ⭐ **job leasing and why it loses** · ⭐⭐ **visible vs invisible failure** · ⭐⭐ **the idempotency ladder** · ⭐ **write sharding with a random suffix** · ⭐ **Data Flow as a framework step.**

---

## 0 · Understanding the problem

⏰ **What is a job scheduler?**

A program that **automatically schedules and executes jobs at specified times or intervals** — to **automate repetitive tasks, run scheduled maintenance, or execute batch processes.**

**⭐⭐ Define the vocabulary FIRST — HI does, and the whole data model follows from it:**

|Term|What it is|Example|
|---|---|---|
|⭐ **Task**|**the abstract concept of work to be done.** ⭐ **Reusable — many jobs can execute the same task**|`"send an email"`|
|⭐⭐ **Job**|**an INSTANCE of a task** = **the task + the schedule + the parameters**|`"send an email to john@example.com at 10:00 AM Friday"`|
|⭐⭐ **Execution**|⊕ **(my term, HI's table) — one actual firing of a job**|`"the 10:00 AM run on Friday the 14th"`|

- ⭐⭐ **That three-level split IS the answer to §4.1.** ▸ **Task is a template, Job is a definition, Execution is an instance.** ⭐ **HI only names the first two up front, then discovers it needs the third.**

---

## 1 · Requirements

### 1.1 Functional (what it does)

1. ⭐⭐ **Schedule jobs to run immediately, at a future date, or on a recurring schedule** (e.g. "every day at 10:00 AM").
2. ⭐ **Monitor the status of their jobs.**

⚠ **Below the line:** cancel or reschedule jobs.

### 1.2 Non-functional (how it behaves)

1. ⭐ **Highly available — availability > consistency** (`01h`).
2. ⭐⭐ **Execute jobs within 2s of their scheduled time.**
3. ⭐ **Scale to 10k jobs per second.**
4. ⭐⭐ **At-least-once execution.** ▸ **Note: at-LEAST-once, not exactly-once** — ⭐ **that choice is what forces §5.3's idempotency discussion.**

⚠ **Below the line:** security policies · CI/CD pipeline.

- ⭐ **HI's prompt on scale, worth copying:** _"Now is a good time to ask about the scale of the system in your interview."_ ▸ **The 10k/sec figure comes from the interviewer, not from you.**

### 1.3 ⭐⭐ The design driver — durability and precision want different stores

||**A database**|**A queue**|
|---|---|---|
|✅ **Gives you**|⭐ **durable record · recoverable after a crash · queryable for status**|⭐⭐ **sub-second delivery · high throughput · no polling bound**|
|⚠ **Can't give you**|⚠⚠ **precision — you're bounded by poll frequency, and polling every 2s means 20k-row queries**|⚠ **"what is my job's status?" — a queue isn't a store**|

- ⭐⭐ **So use both: the DB is the source of truth, the queue is the delivery mechanism, and a Watcher moves work from one to the other in 5-minute slices.** ▸ **That sentence is what HI's Senior bar asks you to articulate.**
- ⭐ **Plus the special case that makes it correct:** **a job created to run in under 5 minutes goes STRAIGHT to the queue** — the Watcher would never see it.
- ▹ ⭐⭐ **And the 5-minute window isn't arbitrary: SQS `DelaySeconds` caps at 15 minutes.** ▸ **The infrastructure constraint sets the architecture's magic number. Say that.**

### 1.4 Planning the approach

⚠⚠ **Different from every previous file.** ▸ **HI: this is _"less of a user-facing product and more focused on data processing"_**, so instead of walking the FRs through the design, it follows the **`Ch-1` delivery framework: core entities → API → DATA FLOW → high-level design → deep dives.**

- ⭐ **The new step is Data Flow (§4.0).** ▸ **Use it for any infra-flavoured prompt: pipelines, schedulers, queues, log processors.**

---

## 2 · Core Entities

- **Task** — a task to be executed.
- **Job** — an instance of a task to run at a given time with given parameters.
- ⭐ **Schedule** — **either a CRON expression or a specific DateTime.**
- **User** — schedules jobs, views status.

▹ ⭐ **HI's framing note, worth saying out loud:** _"I'm going to start with just a simple list, but as we get to the high-level design, I'll document the data model more thoroughly."_

---

## 3 · API

```
POST /jobs
{
  "task_id": "send_email",
  "schedule": "0 10 * * *",
  "parameters": { "to": "john@example.com", "subject": "Daily Report" }
}
```

```
GET /jobs?user_id={}&status={}&start_time={}&end_time={} -> Job[]
```

- ⭐ **Only two endpoints — one per FR.** ▹ **The status query filters on user, status and a time range, which is what drives §4.2's GSI.**

---

## 4 · High-Level Design

### 4.0 ⭐ Data Flow — the extra framework step

▸ **Five steps. State them before designing anything.**

1. **User schedules a job** — task + schedule + parameters.
2. **The job is persisted.**
3. **A worker picks it up and executes it at the scheduled time.**
4. ⭐ **On failure, retry with exponential backoff.**
5. **Update the job status.**

- ⭐⭐ **Why the step earns its place** (HI's three reasons): **aligns you with the interviewer on core functionality before implementation · gives a roadmap for the HLD · surfaces bottlenecks before you commit to an architecture.**
- ▹ **HI: _"it's important to start simple and build up from there."_**

### 4.1) ⭐⭐ Schedule jobs — immediate, future, or recurring

**The flow:** `POST /jobs` with task ID + schedule + parameters → **store with status `PENDING`.**

- ⭐ **Why persist first — three reasons:** **a persistent record of all jobs · recovery if the system crashes · status tracking through the lifecycle.**

#### ⭐ Database choice — and HI's honest answer

> ⭐⭐ _"the hard truth is that **any modern database will work**."_

- ⭐ **HI picks DynamoDB** (`02f`): **no need for strong consistency, few relationships** ⇒ **a flexible key-value store makes scaling easier later.**
- ▹ ⭐ **The alternatives, and when:** **Cassandra if the company prefers open source** (`02e`) · ⚠ **Postgres/MySQL would work, _"you'd just need to pay closer attention to scaling later on."_**

#### ⚠⚠ The naive schema, and why it breaks

```json
{
  "job_id": "123e4567-...", "user_id": "user_123", "task_id": "send_email",
  "scheduled_at": 1715548800,
  "parameters": { "to": "john@example.com", "subject": "Daily Report" },
  "status": "PENDING"
}
```

- ✅ **Fine for one-time jobs.** ⚠⚠ **Breaks on recurring ones.** ▸ **You could store the CRON expression `0 10 * * *` — but then to find what runs in the next few minutes you must EVALUATE EVERY CRON EXPRESSION IN THE DATABASE.** ⭐ **Not scalable.**

#### ⭐⭐ The key insight — separate the DEFINITION from its EXECUTION INSTANCES

> ⭐⭐ **HI's analogy, and it's the one to use in the room:** _"Think of it like a calendar: you might have an event that repeats every Monday, but in your calendar app, you see **individual instances** of that event on each Monday."_

**Jobs table — the definition:**

```json
{
  "job_id": "123e4567-...",          // ⭐ Partition key
  "user_id": "user_123",
  "task_id": "send_email",
  "schedule": { "type": "CRON" | "DATE", "expression": "0 10 * * *" },
  "parameters": { "to": "john@example.com", "subject": "Daily Report" }
}
```

**Executions table — one row per firing:**

```json
{
  "time_bucket": 1715547600,          // ⭐⭐ Partition key — unix ts rounded DOWN to the hour
  "execution_time": "1715548800-123e4567-...",  // ⭐ Sort key — exact time + jobId, so the
                                                //    composite primary key is unique
  "job_id": "123e4567-...",
  "user_id": "user_123",
  "status": "PENDING",
  "attempt": 0
}
```

```python
time_bucket = (execution_time // 3600) * 3600   # round down to the nearest hour
```

- ⭐⭐ **Why the time bucket wins: you only query 1–2 partitions** (the current hour, maybe the next) **to find everything due soon.**
- ⭐ **Recurring jobs need no special machinery:** **when an execution completes, calculate the next execution time and insert a new Executions row.** ▸ **The definition never changes; you keep minting instances.**
- ⚠⚠ **HI flags the cost immediately:** **all writes for a given hour land on ONE partition ⇒ a hot partition under load.** ▸ **Fixed with write sharding in §5.2.**

> ⭐⭐ **The transferable pattern, stated by HI:** **separating a definition from its instances.** ▸ **Calendars (event vs occurrences) · notification systems (template vs individual notifications) · ⭐ `05d` GoPuff, which HI names explicitly.**
> 
> ■ **— end of insert · HI write-up resumes below —**

**⭐ The worker's query:** **Executions where `execution_time` is within the next few minutes AND `status = "PENDING"`** → **then look up the full definition in Jobs and execute.**

- ▹ ⚠ **HI: _"don't stop reading here"_** — this gets reworked substantially in the dives.

> ⊕ ⚠⚠ **(mine, not HI) — who creates the NEXT execution row, and what happens if that write is lost?**
> 
> - ⚠ **HI's only answer: _"when a recurring job completes, we can easily schedule its next occurrence."_** ▸ **So the WORKER mints the next row.** ⚠⚠ **If the worker dies after executing but before that insert, the recurrence chain breaks and the job silently never runs again.** ⭐ **A single lost write kills a daily report forever — and nothing in the design detects it.**
> - ⭐⭐ **Two fixes, and the second is what real schedulers do:**
>     1. **Make minting the next row part of the same retry scope as the status update** ⇒ **at-least-once applies to it too** (and it's idempotent, since the composite key is `execution_time + job_id`).
>     2. ⭐⭐ **A separate MATERIALIZER that walks CRON definitions ahead of time** — e.g. nightly, writing tomorrow's Executions rows. ▸ **Decouples recurrence from execution entirely, so a worker crash can't break the chain.**
> - ⭐ **Raising this is a strong move** — ▸ **it's a durability hole in a system whose whole point is durability.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 4.2) Monitor job status

▸ **On execution, update the Executions row:** `COMPLETED` · `FAILED` · `IN_PROGRESS` · `RETRYING`.

**⚠ The problem: querying by `user_id` is awful with the current keys.**

- ⚠ **Two inefficient steps:** **scan Jobs for all `job_id`s for a user (a full table scan)**, then **query Executions for each.**

**⭐⭐ The fix — a GSI on Executions** (`02f`, `01d`):

```
Partition key: user_id
Sort key:      execution_time + job_id
```

- ✅ ⭐ **Gives you: all executions for a user, sorted by time, paginated, filterable by status.**
- ⚠ ⭐ **The trade, name it:** **a GSI adds write overhead and cost** — **worth it to serve user queries without compromising the primary access pattern of finding jobs due soon.**
- ⭐⭐ **And the reasoning that generalises:** **in DynamoDB you support multiple access patterns with GSIs rather than denormalising.** ▸ **The alternative — duplicating `user_id` into the base table — makes the model more complex and harder to maintain.**

---

## 5 · Deep Dives

### 1) ⭐⭐ How do we execute jobs within 2s of their scheduled time?

**⚠ The limitation: you're polling the DB every few minutes, so the poll interval is the upper bound on precision.** ▸ **Poll every 2 minutes ⇒ a job can fire 2 minutes early or late.**

**⚠⚠ So why not just poll every 2 seconds? Four reasons — the math is the argument:**

1. 📐 ⭐⭐ **At 10k jobs/sec, each query fetches ~20k jobs** (everything due in the next 2s). **A large payload to transfer and process, constantly.**
2. ⭐ **Even well-indexed, a 20k-row query takes several hundred ms** — **with network and serialization, ~500ms just to GET the data.**
3. ⭐ **Then you still have to initialise, distribute to workers and start executing** — **more of the 2s window gone.**
4. ⭐ **Huge queries every 2s put significant load on the DB**, hurting everything else.

#### ⭐⭐ The answer — a two-layered scheduler

|Phase|What it does|Why|
|---|---|---|
|⭐ **1 · Query the DB**|**Every ~5 min, pull Executions due in the next ~5 min** (buffer for latency)|⭐ **durability + low DB load**|
|⭐⭐ **2 · Message queue**|**Push those jobs to a queue; workers pull and execute**|⭐⭐ **precision — high throughput, no polling bound**|

- ⭐⭐ **The payoff in one line:** **DB queries drop to once per 5 minutes while precision comes from the queue.** ▸ **Workers pull as fast as jobs become available, which removes the upper bound entirely.**

**⚠⚠ But: what about a job created to run in under 5 minutes?** ▸ **It's written to the DB, and the 5-minute cron either missed it or won't see it for another 5 minutes.**

> ⚠⚠ **Confusion resolved — why not just push every new job straight onto the queue?**
> 
> - ⚠⚠ **Because with a LOG-based queue like Kafka, order is per-partition.** ▸ **A new job lands at the END of the partition and waits behind every job already queued — even if it's due sooner.** ⭐ **2-second precision becomes impossible.**
> - ⭐⭐ **So you need a queue with DELAYED DELIVERY: jobs stay invisible to workers until their execution time.**
> - ▹ ⭐ **The general lesson: a log is not a work queue.** ▸ **Logs give ordering and replay; task queues give per-message delay, ack and redelivery.**
> 
> ■ **— end of insert · HI write-up resumes below (the queue ladder) —**

#### ⚠ The queue ladder

⚠ **Rung labels are mine — see the handover note.**

**Option — Redis sorted sets** (`02a`; structure in `05i §5.2`)

- **Approach:** ⭐ **a priority queue with the execution timestamp as the score.** **Workers fetch entries with scores below now.**
- ⚠ **Challenges:** ✅ **sub-ms latency and atomic ops**, but ⚠ **you implement your own retry logic, handle failures yourself, and manage replication to avoid a single point of failure.** ▸ **Works at moderate scale; needs real operational expertise and custom code.**

**Option — RabbitMQ**

- **Approach:** ⭐ **delayed delivery via a TTL + Dead Letter Exchange** — **publish with a per-message TTL, and a DLX routes expired messages to the real processing queue.** ✅ **Persistence and publisher confirms out of the box.**
- ⚠ **Challenges:** ⭐⭐ **HA requires QUORUM queues** — ⚠ **clustering alone replicates only topology (exchanges, bindings), NOT queue contents, so a node failure makes that queue's messages unavailable.** ⚠ **TTL+DLX is more complex than native delay, and horizontal scaling needs careful cluster config.**

**⭐⭐ Option (HI's choice) — Amazon SQS**

- **Approach:** ⭐⭐ **native delayed delivery.** **Send with `DelaySeconds: 10` and SQS delivers it 10 seconds later.** ✅ **Fully managed.**
- ✅ **What you get free:** **delivery delay keeps messages invisible until execution time** · **visibility timeouts handle worker failure after consumption** (⭐ **"after consumption" = the worker already TOOK the message and then died** — ▸ **full mechanism in §5.3's Confusion-resolved block**) · **dead-letter queues capture failed jobs** · **HA across AZs** · **automatic scaling.**
- ⚠⚠ **Two caveats HI names, and both matter:**
    - ⭐⭐ **`DelaySeconds` is capped at 15 minutes** — ▸ **which is why the window is 5 minutes.**
    - ⭐⭐ **`DelaySeconds` is a MINIMUM delay, not a precision guarantee.** ▸ **Acceptable here only because workers poll continuously, so extra latency is typically negligible.** ⭐ **Say this — it's a self-aware caveat on your main NFR.**

> ⚠ **Confusion resolved — why does a 15-minute cap force a 5-minute window?**
> 
> - ⭐⭐ **`DelaySeconds` = "hide this message for N seconds."** ▸ **The Watcher sets N = time until the job is due**, so **the QUEUE does the waiting, not your cron.** ▹ due 10:03:30, now 10:00:00 ⇒ **N = 210**.
> - ⚠⚠ **SQS rejects N > 900 (15 min)** ⇒ ⭐ **the Watcher can only look ahead 15 minutes.**
> - ⭐⭐ **So the cap BOUNDS the look-ahead window.** ⚠ **A 1-hour window would break the design** — a job due in 50 min can't be delayed that long.
> 
> ■ **— end of insert · HI write-up resumes below —**

> ⚠ **Confusion resolved — "minimum delay, not a precision guarantee" — so what?**
> 
> - ⭐⭐ **AWS promises: not delivered BEFORE the delay expires. It does NOT promise on time.**
> - ⚠ **The risk: visible 5s late ⇒ you've blown the 2s NFR through no fault of your own design.**
> - ✅ **Fine in practice:** **the delay controls VISIBILITY, and workers already poll continuously** ⇒ **no extra wait for a poll cycle**, and **real overshoot is small.**
> - ⭐⭐ **The point to say: _"not before"_ is contractual, _"not much after"_ is observed.** ⚠ **Never claim SQS gives you 2-second precision.**
> 
> ■ **— end of insert · HI write-up resumes below —**

**⭐ The full recap — five steps:**

1. **User creates a job → written to the DB.**
2. **A cron runs every 5 min, querying for jobs due in the next ~5 min.**
3. **It sends them to SQS with appropriate `DelaySeconds`.**
4. **Workers continuously poll SQS and process messages as they become visible.**
5. ⭐⭐ **A job created for <5 minutes out goes DIRECTLY to SQS with the right delay.**

- ⚠ ⭐ **HI's caveat on managed services, worth knowing:** **many interviewers or companies prefer you avoid SQS.** ▸ **Then build your own priority queue on Redis** — ⭐ **but check with them first.**

> ⭐ **Pattern: Managing Long Running Tasks** (`03g`) — **callout #1 of 2.** ▹ **The API persists the job and returns; workers pull and execute later. ⭐ That decoupling is what lets you retry failures and scale the worker pool independently of job creation.**
> 
> ■ **— end of insert · HI write-up resumes below —**

> ⊕ ▹ **(mine) — one vestigial line that confuses on a first read.**
> 
> - ⚠ **Phase 2 says push to the queue _"ordered by execution_time"_ and have workers _"pull jobs from the queue in order."_** ▸ **That idea is abandoned two paragraphs later.** ⭐ **With `DelaySeconds`, visibility time does the ordering — and SQS Standard doesn't guarantee order anyway.** ▸ **Read Phase 2 as "push them to the queue"; drop the ordering.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 2) ⭐ How do we scale to 10k jobs per second?

> ⭐⭐ **HI's method, and it's the reusable part:** _"work left to right looking for any bottlenecks and addressing them one-by-one."_

#### Job creation

- ⭐ **10k/sec is the UPPER bound, and it's unlikely** — **because recurring jobs mint their own executions without new API calls.** ⭐⭐ **So ask the interviewer: what proportion of jobs are recurring vs one-time?** ▸ **Mostly one-time ⇒ job creation could become the bottleneck.**
- ▸ **The option: a Kafka/RabbitMQ buffer between the API and the Job Creation service** — **absorbs spikes, enables horizontal scaling by adding consumers, gives durability.**

> ⚠⚠ **HI argues AGAINST its own component here — and note this contradicts the call in `05i`.**
> 
> - ⚠ **HI: that queue is _"likely overcomplicating the design."_** ▸ **The DB can take the write throughput directly, and you'll always need a horizontally-scalable service in front of it anyway.** ⭐ **Unless there's expensive business logic to isolate, keep it simpler and just scale the service.** ▹ **_"I'll leave it in the diagram but consider it optional."_**
> - ⭐⭐ **The contrast with `05i §5.3`, where HI KEPT an admittedly-overkill queue:** ▸ **there the queue bought RETRIES on container failure. Here it buys nothing the DB and the service don't already give you.** ⭐ **The deciding question is never "is a queue overkill" — it's "what does this queue buy that nothing else does."**
> 
> ■ **— end of insert · HI write-up resumes below —**

#### ⭐ Jobs DB

- ⭐ **DynamoDB supports up to 1,000 WCU per partition**, so partition design decides whether you scale.

|Table|Partition key|Verdict|
|---|---|---|
|**Jobs**|`job_id`|✅ ⭐ **distributes evenly — every job has a unique ID**|
|⚠⚠ **Executions**|`time_bucket`|⚠⚠ **ALL writes for the current hour hit ONE partition ⇒ hot partition**|

- ⭐⭐ **The fix — write sharding** (`01f`): **append a random suffix to the partition key** (`time_bucket#shard_3`), **spreading writes across partitions.** ▸ **Workers then query all shards for a bucket IN PARALLEL.**
- ⭐ **Retention:** **executed jobs stay queryable, but after ~1 year move them to cheaper storage like S3** (`01a`). ▹ **Same tiering move as `05k §5.2`.**

> ⊕ ▹ **(mine) — name the cost of write sharding; HI doesn't.**
> 
> - ⚠ **§4.1 sold `time_bucket` on _"we only need to query 1–2 partitions."_** ⭐ **With N shards it's 2N parallel queries.** ▸ **Still cheap, but the selling point is gone, so pick N as small as the write load allows** — ⭐ **it's a knob trading read fan-out against write distribution.**
> 
> ■ **— end of insert · HI write-up resumes below —**

#### ⭐ Message queue capacity

- 📐 **Per 5-minute window: 10k/s × 300s = ~3M jobs.** **Messages are small — ~200 bytes (job ID, execution time, metadata)** ⇒ ⭐ **~600MB per window.** ▹ **SQS allows up to 1MB per message, so there's enormous headroom.**
- ✅ ⭐ **SQS Standard throughput is virtually unlimited** — **10k msg/sec needs no special configuration, and AWS handles sharding and distribution.**
- ⭐ **Multiple queues only for FUNCTIONAL separation** (job priorities or types), **not for scaling.**
- ▹ **Even on the Redis route, 3M jobs fit in memory easily** — ⚠ **you'd just worry about fault tolerance if Redis goes down.**

#### ⭐ Workers — containers vs Lambda

||✅ **Good at**|⚠ **Bad at**|
|---|---|---|
|**Containers** (ECS / K8s)|⭐ **cost-effective for steady workloads · better for long-running jobs, keep state between executions**|**more operational overhead · less elastic**|
|**Lambda**|**serverless, minimal ops · perfect for short jobs <15 min · auto-scales instantly**|⚠⚠ **cold starts threaten the 2s precision requirement** · **more expensive for steady high volume**|

- ⭐⭐ **HI's choice: containers on ECS with auto-scaling** — **steady, predictable, high-volume workload with a tight precision requirement.** ▹ ⭐ **_"there is no wrong answer here."_**
- ⭐ **Four optimisations worth naming:** **spot instances for cost · auto-scale on QUEUE DEPTH · pre-warm the pool for baseline load · scaling policies for spikes.**

> ⭐ **Pattern: Scaling Writes** (`03e`) — **callout #2 of 2.** ▹ ⭐⭐ **HI's framing: a job scheduler is write-heavy at its core, and _"the trickiest problems all live on the write path"_ — the hourly `time_bucket` hot partition and the write sharding that fixes it.** ▸ **Designing partition keys so writes fan out evenly is the heart of this dive.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 3) ⭐⭐ How do we ensure at-least-once execution?

**⭐⭐ Start by splitting failures in two — this taxonomy is the scoring move:**

||What it is|Likely cause|
|---|---|---|
|⭐ **Visible failure**|**the job fails in a way you can observe**|**a bug in the task code, or bad input parameters**|
|⭐⭐ **Invisible failure**|**the job fails silently**|⚠ **the worker itself went down**|

#### ⭐ Visible failures — the easy case

- ⭐ **Wrap the task in try/catch**, **log the error**, **write status `RETRYING` + the attempt count to Executions.**
- ⭐⭐ **Re-enqueue to SQS with an increasing `DelaySeconds` per attempt** — **5s → 25s → 125s.** ▸ **Use the attempt count to compute the backoff.**
- ⭐ **After 3 failed attempts, mark `FAILED` and stop retrying.**
- ⭐⭐ **SQS gives you three of the building blocks:** **visibility timeouts make failed messages reappear** · **`ApproximateReceiveCount` tracks retry attempts** · **dead-letter queues catch messages past the limit.** ▸ **You only write the backoff timing.**

#### ⚠ Invisible failures — the ladder

**Option — health checks**

- **Approach:** **each worker exposes `GET /health`; a central monitor polls every few seconds and reassigns jobs from workers that miss several consecutive checks.**
- ⚠ **Challenges:** ⭐ **doesn't scale to thousands of workers** — the monitor polls each one · ⭐ **network issues cause FALSE POSITIVES ⇒ unnecessary retries** · **extra infrastructure to build and maintain** · **complex coordination with the scheduler to avoid race conditions** · ⚠ **and what happens when the monitoring service itself goes down.**

**Why climb:** you've built a second system that can also fail, and it guesses.

**Option — job leasing** (`03b`, and the `05e` hold pattern)

- **Approach:** ⭐ **distributed locking via the DB.** **A worker acquires a lease by writing its worker ID + an expiration timestamp** — _"Job 123 is leased to Worker A until 10:30:15"_ — **and must periodically EXTEND it.** ▸ **Crash ⇒ the lease isn't renewed ⇒ after expiry another worker takes it.**
- ⚠ **Challenges:**
    - ⭐ **Heavy write amplification from constant lease renewals.** ▸ HI: _"The database must process frequent lease renewal operations, which at our scale of 10k jobs per second could mean **50k lease updates per second** (assuming 5-second lease intervals)."_ ⚠⚠ **That 50k is wrong — see the ⊕ block below. The point stands; the number doesn't.**
    - ⭐⭐ **Clock synchronisation matters** — ⚠ **if A's clock says 10:30:00 and B's says 10:30:20, B steals a job A is still running.**
    - ⭐⭐ **Network partitions:** ⚠ **A can't reach the DB to renew but IS still processing ⇒ another worker starts the same job ⇒ duplicate execution.**

**Why climb:** you're rebuilding, with clocks and locks, something the queue already does.

**⭐⭐ Option (HI's choice) — SQS visibility timeouts**

- **Approach:** ⭐⭐ **on receive, SQS makes the message invisible to other workers for a configurable period.** **Worker deletes it on success.** ▸ **Crash or overrun ⇒ SQS makes it visible again automatically.**
- ⭐⭐ **The tuning that makes it work for long jobs:** **a SHORT visibility timeout (e.g. 30s)** plus **workers heartbeating via `ChangeMessageVisibility` to extend it** — ▸ **a 5-minute job extends every 15 seconds.** ⭐ **So a crash is picked up within 30s instead of waiting out a long timeout.**
- ✅ **Benefits:** ⭐⭐ **no additional infrastructure and no complex coordination** · **fast failure detection AND support for long jobs** · **automatic DLQ after N retries** · **precise control over job ownership without added complexity.**

> ⚠ **Confusion resolved — how does a visibility timeout catch a worker that died AFTER taking the message?**
> 
> - ⭐⭐ **Because reading a message does NOT delete it — it only HIDES it, and starts a ~30s timer.**
> - **Success ⇒ the worker calls `DeleteMessage` and it's gone. Crash ⇒ no delete ever comes ⇒ the timer expires ⇒ the message reappears ⇒ another worker runs it.**
> - ⭐⭐ **So the crash is detected by the ABSENCE of a delete.** ▸ **Nobody watches the worker** — which is the whole advantage over health checks.
> - ⚠ **Tuning trap: 30s timeout on a 5-min job expires MID-WORK ⇒ two workers run it.** ⭐ **Fix: extend every 15s — a healthy worker keeps extending, a dead one stops, so it's retried within 30s.** ▸ **The extension call IS the heartbeat.**
> - ⭐⭐ **This IS a lease — one AWS runs for you.** ▸ **No DB writes, no clock skew.** ⚠ **But two workers remain possible, which is why idempotency stays mandatory.**
> 
> ■ **— end of insert · HI write-up resumes below —**

> ⊕ ⚠⚠ **(mine, not HI) — HI's lease arithmetic is backwards.**
> 
> - ⚠ **HI: _"at our scale of 10k jobs per second could mean 50k lease updates per second (assuming 5-second lease intervals)."_** ▸ **That's 10k × 5. But a LONGER renewal interval must produce FEWER updates, not more** — **updates/sec = concurrent jobs ÷ interval.**
> - ⚠ **And no job DURATION is stated anywhere in the write-up, so concurrent-job count can't be derived.** ⭐ **The 50k doesn't follow from any given figure.**
> - ⭐⭐ **The conclusion still holds — leases mean constant extra writes — so make the POINT, not the number:** _"every in-flight job writes a renewal every few seconds, so lease traffic scales with concurrency, not with job count."_ ⚠ **Don't quote 50k.**
> 
> ■ **— end of insert · HI write-up resumes below —**

#### ⭐⭐ The consequence — at-least-once FORCES idempotency

> ⭐ **HI: running the task multiple times must have the same outcome as running it once.**

**⚠ Bad — just execute every time**

- ⚠ **Challenges:** ⭐⭐ **serious consistency issues.** ▸ **A money transfer transfers twice. A counter increments too many times.** ⚠ **_"clearly not acceptable for most real-world applications."_**

**Why climb:** duplicates are guaranteed by at-least-once, so the task must tolerate them.

**Good — a deduplication table**

- **Approach:** ⭐ **before executing, check a dedup table keyed on `job_id + execution_timestamp`.** **Match found ⇒ skip.**
- ⚠ **Challenges:** **extra DB operations on EVERY execution** · **another table to maintain** · ⭐ **needs periodic cleanup to avoid unbounded growth** · ⚠ **a small race window between the check and the write.**

**Why climb:** you're paying a read and a write per execution to patch a problem the task could avoid by design.

**⭐⭐ Great — make the jobs naturally idempotent**

- ⭐⭐ **Use idempotency keys and conditional operations.** ▸ **Instead of _"increment counter"_, make the job _"set counter to X"_.** ▸ **Instead of _"send welcome email"_, first check whether the welcome-email flag is already set on the user's profile.**
- ⭐ **Each execution carries a unique identifier downstream services can deduplicate on.**
- ⭐⭐ **HI: the most robust approach, _"essentially offloading idempotency concerns to the task's implementation."_** ▸ **The scheduler's job is delivery, not exactly-once semantics.**

---

## 6 · Final Design

⚠ **Layout and arrows are mine; components, labels and field lists are HI's** — see the handover note.

```
client
  │  POST /jobs  {task_id, schedule, parameters}
  │  GET  /jobs?user_id&status&start_time&end_time
  ▼
API Gateway                                                        02d
  │
  ├──► Scheduler Service   ⭐ writes the job definition + first execution
  │         │              ⚠ HI's optional Kafka/RabbitMQ buffer in front
  │         │                — HI calls it "likely overcomplicating"
  │         │
  │         └─ ⭐⭐ job due in < 5 min? → straight to SQS with the delay
  │
  ├──► Query Service  ──► reads the GSI (user_id / execution_time+job_id)
  │
  ▼
Job Store (DynamoDB)                                         02f · 01f
  │
  │   Jobs        ⭐ partition: job_id   (the DEFINITION)
  │                 id · userId · taskId · params · schedule{type,expression}
  │
  │   Executions  ⭐⭐ partition: time_bucket = (t // 3600) * 3600
  │                 sort: execution_time + jobId   (unique composite PK)
  │                 time · jobId · userId · status · attempt
  │                 ⚠⚠ one partition per hour ⇒ HOT
  │                 ⭐ fix: write sharding → time_bucket#shard_N,
  │                    workers query all shards in parallel
  │                 ⊕ cost: §4.1's "only 1–2 partitions" becomes 2N
  │                 ⭐ GSI: user_id / execution_time+job_id  (status queries)
  │                 ⭐ after ~1 year → S3                              01a
  │                 ⊕ consider a MATERIALIZER that pre-writes CRON
  │                   occurrences, so a worker crash can't break the chain
  ▲
  │ update status: PENDING → IN_PROGRESS → COMPLETED | RETRYING | FAILED
  │
Watcher  ⭐⭐ cron every ~5 min — polls Executions for jobs due in ~5 min
  │          (5 min, because SQS DelaySeconds caps at 15)
  ▼
Message Queue (SQS)                                                  03g
  │   ⭐⭐ delivery delay until execution time  (⚠ a MINIMUM, not a guarantee)
  │   ⭐ visibility timeout ~30s  → invisible failure recovery
  │   ⭐ retry with exponential backoff: 5s → 25s → 125s, then FAILED
  │   ⭐ ApproximateReceiveCount tracks attempts · DLQ past the limit
  │   ⚠ NOT Kafka: a log orders per partition, so a sooner job queues last
  ▼
Workers  ⭐ containers on ECS + auto-scaling (NOT Lambda — cold starts
  │        threaten the 2s precision requirement)
  │        ⭐ spot instances · auto-scale on QUEUE DEPTH · pre-warm the pool
  │        ⭐ heartbeat ChangeMessageVisibility every ~15s on long jobs
  │        ⭐ try/catch for visible failures → status RETRYING + attempt
  │        ⭐⭐ tasks must be IDEMPOTENT — "set counter to X", not "increment"
  │
  ├─ execute job · execute job · execute job
  └─ on completion of a recurring job → mint the next Executions row
```

---

## 7 · Expected at Each Level

|Level|The bar for Job Scheduler|
|---|---|
|**Mid**|**A reasonable HLD with a clear, cohesive data model.** ⭐ **Then respond well to interviewer questions on durability, precise scheduling and retries.** ▹ **Right answers NOT expected unguided** — **what's expected is strong problem-solving and working WITH the interviewer to reach them.**|
|**Senior**|⭐ **Much more autonomy — lead the conversation on TWO deep dives** and **show hands-on experience with the relevant technologies.** ⭐⭐ **Specifically: articulate the need for a two-phased architecture**, even if you pick Redis over SQS for the queue. ⭐ **Proactively identify issues and adapt to thrown scenarios** — e.g. _"what happens if a worker goes down mid-job execution."_|
|**Staff+**|**Breeze through setup and HLD, spend most of the time leading deep dives.** ⭐ **Understand the major bottlenecks and propose well-justified solutions.** ⭐ **Deep on at least one technology, justified by hands-on experience.** ▹ ⭐⭐ **And HI's bonus bar: _"the best staff candidates have the ability to teach the interviewer something, no matter how small."_**|

---

## Quick Recall (pass 3+)

|Use / Question|Job Scheduler answer|
|---|---|
|Calibration|⭐ Evan King · Feb 2026 · **"medium"** · ⭐⭐ **LinkedIn +22 = 23 companies, the MOST-asked problem in the series** · ⭐⭐ **TWO patterns: `Managing Long Running Tasks` (`03g`) + `Scaling Writes` (`03e`).** ⚠⚠ **First INFRA-style problem — HI switches to the `Ch-1` framework and adds a DATA FLOW step.** ⭐⭐ **Highest-value file so far: 3 substantial dives, no padding ⇒ TWO passes.** ⭐ **Senior bar names the sentence to rehearse: "articulate the need for a two-phased architecture"**|
|⭐⭐ Design driver|⭐⭐ **Durability and precision want DIFFERENT stores.** **DB: durable, recoverable, queryable — ⚠ but precision is capped by poll frequency. Queue: sub-second delivery, no polling bound — ⚠ but can't answer "what's my status".** ⭐⭐ **So use both: DB is the source of truth, queue is the delivery mechanism, a Watcher moves work across in 5-min slices.** ⭐ **Plus: a job due in <5 min goes STRAIGHT to the queue.** ▹ ⭐⭐ **And 5 min isn't arbitrary — SQS `DelaySeconds` caps at 15**|
|⭐⭐ Vocabulary|**Task = the abstract work, REUSABLE ("send an email") · Job = an INSTANCE of a task = task + schedule + params ("email john at 10am Friday") · ⊕ Execution = one actual firing.** ⭐⭐ **That 3-level split IS the §4.1 answer: Task = template, Job = definition, Execution = instance**|
|FRs / NFRs|**Schedule jobs immediately / future / recurring · monitor status.** Below: cancel or reschedule. **NFRs: availability > consistency · ⭐⭐ within 2s of scheduled time · 10k jobs/sec · ⭐⭐ AT-LEAST-once.** Below: security · CI/CD. ⭐ **at-LEAST-once (not exactly-once) is what forces §5.3's idempotency.** ▹ **HI: _"now is a good time to ask about the scale"_ — 10k comes from the interviewer**|
|📐 Numbers|**10k jobs/s · 2s precision · 3 retries.** ⭐⭐ **Why not poll every 2s: ~20k jobs per query (10k×2), several hundred ms to query, ~500ms before you start.** ⭐ **3M jobs per 5-min window (10k×300) × ~200B = 600MB** — trivial. **DynamoDB 1,000 WCU/partition. Backoff 5s→25s→125s. Visibility 30s, heartbeat 15s. Retention 1yr → S3.** ⚠ **HI's "50k lease updates/sec" is backwards — see below**|
|⚠ Framework switch|⚠⚠ **first infra problem: _"less of a user-facing product and more focused on data processing"_** ⇒ **`Ch-1` framework: entities → API → ⭐ DATA FLOW → HLD → deep dives.** ⭐ **Use the Data Flow step for any pipeline, scheduler, queue or log-processing prompt**|
|⭐ Data Flow (5 steps)|**user schedules (task+schedule+params) → job persisted → worker picks it up at the scheduled time → ⭐ on failure retry with exponential backoff → update status.** ⭐⭐ **Why it earns a step: aligns you with the interviewer before implementation · gives a roadmap · surfaces bottlenecks before you commit**|
|Entities / API|**Task · Job · ⭐ Schedule (CRON expression OR a specific DateTime) · User.** `POST /jobs {task_id, schedule, parameters}` · `GET /jobs?user_id&status&start_time&end_time`. ▹ ⭐ **say up front: _"simple list now, I'll document the data model properly in the HLD"_**|
|DB choice|⭐⭐ _"the hard truth is that **any modern database will work**."_ **HI picks DynamoDB: no strong consistency needed, few relationships ⇒ a KV store eases later scaling.** ▹ **Cassandra if they prefer open source; ⚠ Postgres/MySQL fine but _"you'd need to pay closer attention to scaling"_**|
|⚠⚠ Why one table breaks|**one-time jobs are fine.** ⚠⚠ **Recurring aren't: store the CRON string and finding what runs in the next few minutes means EVALUATING EVERY CRON EXPRESSION IN THE DB**|
|⭐⭐ The key insight|⭐⭐ **Separate the DEFINITION from its EXECUTION INSTANCES.** ⭐ **HI's analogy to use in the room:** _"like a calendar: you might have an event that repeats every Monday, but in your calendar app, you see **individual instances** on each Monday."_ ⭐⭐ **Reusable: calendars (event vs occurrences) · notifications (template vs sent) · `05d` GoPuff**|
|⭐⭐ The two tables|**Jobs (⭐ partition `job_id`): id · userId · taskId · params · `schedule{type: CRON\|DATE, expression}`.** **Executions (⭐⭐ partition `time_bucket`, ⭐ sort `execution_time + jobId` so the composite PK is unique): jobId · userId · status · attempt.** ⭐ **`time_bucket = (execution_time // 3600) * 3600`.** ⭐⭐ **Win: only 1–2 partitions to find everything due soon.** ⭐ **Recurring needs no machinery — on completion, compute the next time and insert a new row; the definition never changes**|
|⊕⚠⚠ The recurrence chain is fragile|⚠ **HI's only answer is that the WORKER mints the next Executions row on completion.** ⚠⚠ **Worker dies after executing but before that insert ⇒ the chain breaks and the job NEVER runs again, silently.** ⭐⭐ **Two fixes: (1) put the insert in the same retry scope as the status update — it's idempotent, the PK is `execution_time + job_id` (2) ⭐⭐ a separate MATERIALIZER that pre-writes CRON occurrences (e.g. nightly for tomorrow), decoupling recurrence from execution.** ⭐ **A durability hole in a system whose whole point is durability — strong raise**|
|⭐⭐ Status queries ⇒ GSI|⚠ **by `user_id` the current keys force a full scan of Jobs then N queries on Executions.** ⭐⭐ **Fix: GSI on Executions — partition `user_id`, sort `execution_time + job_id`** ⇒ **all a user's executions, time-sorted, paginated, status-filterable.** ⚠ **Trade: GSI write overhead + cost, worth it to avoid compromising the primary access pattern.** ⭐⭐ **Reasoning that generalises: in DynamoDB serve extra access patterns with GSIs rather than denormalising**|
|⚠⚠ DD1 — why not poll every 2s|**4 reasons: (1)** 📐 **~20k jobs per query at 10k/s (2) several hundred ms even well-indexed, ~500ms with network + serialization (3) you still must initialise, distribute and start executing (4) huge queries every 2s hammer the DB**|
|⭐⭐ DD1 — two-layered scheduler|⭐ **Phase 1: query the DB every ~5 min for jobs due in the next ~5 min ⇒ durability + low DB load.** ⭐⭐ **Phase 2: push to a message queue; workers pull and execute ⇒ precision.** ⭐⭐ **Payoff: DB queries drop to once per 5 min while precision comes from the queue — workers pull as fast as jobs appear, removing the polling bound**|
|⭐⭐ Why not push new jobs onto a log|⚠⚠ **Kafka orders within a partition ⇒ a new job lands at the END and waits behind everything queued, even if due sooner ⇒ 2s precision impossible.** ⭐⭐ **You need DELAYED DELIVERY — jobs invisible until their execution time.** ▹ ⭐ **General lesson: a log is not a work queue. Logs give ordering + replay; task queues give per-message delay, ack and redelivery**|
|DD1 queue option — Redis ZSET|⭐ **priority queue, execution timestamp as the score; fetch entries scored below now** (`02a`, structure in `05i §5.2`). ✅ **sub-ms, atomic.** ⚠ **you build your own retry logic, failure handling and replication ⇒ works at moderate scale but needs real ops expertise + custom code**|
|DD1 queue option — RabbitMQ|⭐ **delayed delivery via TTL + Dead Letter Exchange** — per-message TTL, DLX routes expired messages to the real queue. ✅ **persistence + publisher confirms built in.** ⚠⚠ **HA needs QUORUM queues — clustering alone replicates only topology (exchanges, bindings), NOT queue contents, so a node failure makes its messages unavailable.** ⚠ **TTL+DLX is more complex than native delay**|
|⭐⭐ DD1 Great — SQS|⭐⭐ **native `DelaySeconds`** — send with delay 10, delivered 10s later. ✅ **free: delivery delay · visibility timeouts for worker failure · DLQs · HA across AZs · auto-scaling.** ⚠⚠ **Two caveats: (1)** ⭐⭐ **`DelaySeconds` caps at 15 MIN — which is why the window is 5 (2)** ⭐⭐ **it's a MINIMUM delay, not a precision guarantee** — fine only because workers poll continuously. ⚠ **HI's warning: many interviewers dislike managed services ⇒ offer Redis, but ASK first**|
|⭐ DD1 recap (5 steps)|**create → DB · cron every 5 min queries for jobs due in ~5 min · sends to SQS with the right `DelaySeconds` · workers poll continuously · ⭐⭐ a job due in <5 min goes DIRECTLY to SQS**|
|⊕▹ DD1 vestigial line|⚠ **Phase 2 says push _"ordered by execution_time"_ and pull _"in order"_ — abandoned two paragraphs later.** ⭐ **With `DelaySeconds`, visibility time does the ordering, and SQS Standard doesn't guarantee order anyway. Drop the ordering**|
|⭐⭐ DD2 method|⭐⭐ _"work **left to right** looking for any bottlenecks and addressing them one-by-one."_ ▸ **creation → DB → queue → workers**|
|DD2 — job creation|⭐ **10k/s is the UPPER bound and unlikely, because recurring jobs mint executions without API calls.** ⭐⭐ **So ask: what % are recurring vs one-time?** — mostly one-time ⇒ creation could bottleneck|
|⚠⚠ DD2 — HI rejects its own component|⚠ **the Kafka/RabbitMQ buffer in front of Job Creation is _"likely overcomplicating the design"_** — **the DB handles the write throughput, and you need a horizontally-scalable service anyway.** ▹ _"I'll leave it in the diagram but consider it optional."_ ⭐⭐ **Contrast `05i §5.3`, where HI KEPT an admittedly-overkill queue — because there it bought RETRIES. ⭐ The question is never "is a queue overkill" but "what does this queue buy that nothing else does"**|
|⭐ DD2 — partition keys|⭐ **DynamoDB caps at 1,000 WCU per partition.** **Jobs by `job_id` ⇒ ✅ even.** ⚠⚠ **Executions by `time_bucket` ⇒ ALL of the current hour's writes hit ONE partition.** ⭐⭐ **Fix: write sharding — random suffix `time_bucket#shard_3`, workers query all shards IN PARALLEL** (`01f`). ⭐ **Retention: queryable, then ~1yr → S3** (`01a`, same as `05k`). ⊕ ▹ **cost HI doesn't name: §4.1's "1–2 partitions" becomes 2N — keep N as small as the write load allows**|
|⭐ DD2 — queue + workers|📐 **3M jobs / 5-min window × ~200B = 600MB** (SQS allows 1MB per message). ✅ **Standard throughput virtually unlimited; AWS shards it.** ⭐ **Multiple queues only for FUNCTIONAL separation (priority, type), never for scale.** **Workers: ⭐ containers (ECS) — cost-effective for steady load, better for long jobs, keep state; ⚠⚠ NOT Lambda — cold starts threaten the 2s precision** (though great <15min, instant scaling). ⭐ **Optimise: spot instances · auto-scale on QUEUE DEPTH · pre-warm the pool · spike policies**|
|⭐⭐ DD3 — the failure taxonomy|⭐ **VISIBLE: fails observably — a bug in task code or bad parameters.** ⭐⭐ **INVISIBLE: fails silently — the worker itself went down.** ▸ **Different mechanism for each; naming the split is the scoring move**|
|⭐ DD3 — visible failures|**try/catch → log → write `RETRYING` + attempt count.** ⭐⭐ **Re-enqueue with increasing `DelaySeconds`: 5s → 25s → 125s**, computed from the attempt count. **After 3 ⇒ `FAILED`, stop.** ⭐⭐ **SQS gives 3 of the 4 pieces: visibility timeouts make failures reappear · `ApproximateReceiveCount` tracks attempts · DLQs catch over-limit messages. You write only the backoff timing**|
|⚠ DD3 invisible — health checks|**workers expose `GET /health`, a monitor polls every few seconds, reassigns after consecutive misses.** ⚠ **doesn't scale to thousands of workers · ⭐ network blips cause FALSE POSITIVES ⇒ needless retries · extra infra · race conditions with the scheduler · ⚠ and what if the monitor itself dies**|
|⚠ DD3 invisible — job leasing|⭐ **distributed locking in the DB** (`03b`, the `05e` hold shape): write worker ID + expiry (_"Job 123 leased to Worker A until 10:30:15"_), **periodically EXTEND**; crash ⇒ no renewal ⇒ another worker takes it after expiry. ⚠ **heavy write amplification · ⭐⭐ CLOCK SKEW: A says 10:30:00, B says 10:30:20 ⇒ B steals a running job · ⭐⭐ NETWORK PARTITION: A can't renew but IS still running ⇒ duplicate execution**|
|⭐⭐ DD3 Great — visibility timeout|⭐⭐ **on receive, SQS hides the message from other workers; the worker deletes it on success; crash or overrun ⇒ it reappears automatically.** ⭐⭐ **The tuning: SHORT timeout (~30s) + workers heartbeat `ChangeMessageVisibility` to extend it** (a 5-min job extends every 15s) ⇒ **a crash is retried within 30s, not after a long timeout.** ✅ **no extra infrastructure, no coordination, auto-DLQ**|
|⊕⚠⚠ HI's lease math is backwards|⚠ **_"10k jobs per second could mean 50k lease updates per second (assuming 5-second lease intervals)"_ = 10k × 5.** ▸ **But updates/sec = concurrent jobs ÷ interval — a LONGER interval means FEWER updates.** ⚠ **And no job DURATION is given anywhere, so concurrency can't be derived.** ⭐⭐ **Make the POINT, not the number: _"lease traffic scales with concurrency, not job count."_ Don't quote 50k**|
|⚠ Bad idempotency — just run it|⚠ **a money transfer transfers twice; a counter increments too many times** — _"clearly not acceptable for most real-world applications"_|
|Good idempotency — dedup table|⭐ **check a dedup table keyed `job_id + execution_timestamp` before executing; match ⇒ skip.** ⚠ **extra DB ops on EVERY execution · another table · ⭐ needs periodic cleanup for unbounded growth · ⚠ a small race window between check and write**|
|⭐⭐ Great idempotency — design it in|⭐⭐ **idempotency keys + conditional operations.** ▸ **"SET counter to X" not "increment counter" · for "send welcome email", first check the welcome-email flag on the profile.** ⭐ **Each execution carries a unique ID downstream services dedupe on.** ⭐⭐ **HI: most robust — _"offloading idempotency concerns to the task's implementation."_** ▸ **The scheduler's job is delivery, not exactly-once**|
|⭐⭐ The meta-lesson|⭐⭐ **Fourth appearance of the two-layer shape** — `05e` (Redis hold / Postgres guarantee) · `05h` (Redis serialization / Cassandra history) · `05i` (Redis ZSET / DynamoDB) · **`05p` (DynamoDB truth / SQS delivery).** ▸ **Every time: the fast tier does the time-critical thing, the durable tier remembers**|
|Levels (short)|**Mid:** reasonable HLD + cohesive data model; respond well on durability, precision, retries — ▹ **right answers not expected unguided, problem-solving is** · **Senior:** ⭐ **lead TWO deep dives**, hands-on with the tech, ⭐⭐ **specifically articulate the need for a two-phased architecture** (Redis instead of SQS is fine), adapt to _"what if a worker dies mid-execution"_ · **Staff+:** breeze through setup/HLD, lead the dives, know the bottlenecks, deep on ≥1 technology from experience, ⭐⭐ **and ideally teach the interviewer something**|

---

> 🔗 **HI source:** https://www.hellointerview.com/learn/system-design/problem-breakdowns/job-scheduler
> 
>