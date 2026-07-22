# Managing Long-Running Tasks

> Hello Interview · **Patterns** · File `03g`. Overview → `03 §7`. Queues + backpressure → `02 §6`; Kafka → `02 §7`; DLQ / retries / idempotency → `03e §4.1`; multi-step chains + orchestration (Step Functions / Temporal) → `03c`; scaling writes via queues → `03e §3`; blob upload triggers async work → `03f §2.5`; numbers / throughput math → `01i`. **Calibration:** ⭐⭐⭐ **High frequency, easy to recognize — the depth is in the deep dives.** "Shows up in nearly every company at scale." Recognizing the trigger is trivial (_operation takes > a few seconds_); the interview signal is how you handle **failures, DLQ, dedup, backpressure, mixed workloads, dependencies.** For your targets: ⭐ **Stripe/payments is the on-the-nose fintech case** — sync card auth, but **async workers for fraud detection, 3DS, webhooks, and delayed settlement** (bank transfers → API returns `pending`, worker settles later). Also: report/statement generation, bulk emails, CSV imports, KYC document processing. ▸ **The one governing insight:** **decouple request acceptance from request processing.** The web server becomes a **lightweight router** — validate, enqueue, return a **job ID** in milliseconds. A separate **worker pool** does the heavy lifting at its own pace and updates status. The HTTP request completes immediately; the work finishes later. ⚠ **Don't overcomplicate it in the interview.** Pick a queue you know (**Kafka is a safe default**), use **regular server processes** for workers unless pushed, and show you understand **separation of concerns** — don't burn time debating queue vendors.

---

## 1. The Problem

▸ **CRUX** — synchronous processing breaks the moment an operation takes more than a few seconds.

- ▸ Profile fetch = a quick DB query, **< 100ms** → instant. Fine.
- ⚠ **Generate an annual PDF report** = query many tables, aggregate millions of rows, render charts → **45+ seconds.** Now sync falls apart:
    - **Timeouts** — web servers / load balancers cap requests at **~30–60s** → the request may **never complete.**
    - **Terrible UX** — user stares at a spinner with **no progress feedback.**
    - **Duplicate work** — after 30s many users assume it broke and **retry**, creating _more_ load and duplicate jobs → makes it worse.
- ▸ Same story for **video transcoding** (minutes), **photo resize/thumbnails**, **bulk newsletters**, **large CSV imports.** All exceed what users will wait for.
- ▸ **Even with infinite scale, sync gives terrible feedback.** The fix isn't "more servers" — it's a different shape.

### 1.1 HI problem breakdowns _(the canonical worked examples for this pattern)_

- **Instagram** · **LeetCode** · **ChatGPT** — each has a detailed HI breakdown showing exactly how async workers slot into the larger design. ⭐ **LeetCode** (submit code → queue → sandboxed judge worker runs test cases → poll/notify result) and **ChatGPT** (long LLM generation → async job + streamed/notified completion) are especially clean illustrations of _accept-fast, process-async, notify-when-done._

---

## 2. The Solution — Async Worker Pool

▸ **CRUX** — split the operation into **two phases: immediate acknowledgment + background processing.** On "Generate Report": **store the request in a queue, return "we'll notify you when it's ready"** in milliseconds — not minutes.

- ▸ **Web server's new job (trivial):** validate the request → push to queue → return a **job ID.** The actual work happens **elsewhere.**
- ▸ **"Async"** = the original HTTP request completes **without waiting** for the work. **"Worker pool"** = a collection of processes dedicated to the background jobs — they pull from a **shared queue**, process at their own pace, update status on completion.
- ▸ **The queue is a durable buffer** between web servers and workers → nothing is lost if a worker crashes; also gives **visibility** (how many jobs waiting, how long, how many failed). Popular choices: **Redis (with Bull/BullMQ), AWS SQS, RabbitMQ, or Kafka for higher scale** _(full comparison → §4.1)_. _(→ `02 §6`.)_

### 2.1 Why this separation wins

- ✅ **Independent scaling / hardware fit** — web servers stay **cheap general-purpose** instances; video workers get **GPU** machines; month-end PDF backlog → **spin up more workers** without touching the web fleet. Each component scales on **its own** need.
- ✅ **Better UX** — immediate confirmation; user can **check status / queue position**, navigate away, and get **notified** (email / push / WebSocket → `03a`) when done.
- ▸ Applies to **anything > a few seconds**: image/video processing, bulk imports, rate-limited third-party API calls, report generation, email campaigns. **Accept quickly, process asynchronously, notify when complete.**

---

## 3. Trade-offs _(name these — it shows maturity)_

|✅ What you gain|⚠ What you lose|
|---|---|
|**Fast response** — ms, not 30s timeouts|**System complexity** — queues + workers + status tracking = more to break|
|**Independent scaling** — workers scale separately from web tier|**Eventual consistency** — work isn't done when API returns; users may see stale data|
|**Fault isolation** — one worker crash doesn't down the API; failed jobs retry|**Job status tracking** — need infra to store states, retries, status endpoints → DB + API load|
|**Resource utilization** — right instance type per workload|**Monitoring overhead** — queue depth, worker health, failure rates, latency = distributed-system monitoring|

⚠ **New failure modes** sync systems never had: queue fills up · **poison messages** crash workers repeatedly · when to **give up** retrying. All solvable, but need planning (→ Deep Dives).

---

## 4. How to Implement

▸ Two components required: a **Message Queue** and a **Pool of Workers.**

### 4.1 Message Queue _(must be durable + safe under concurrent workers)_

▸ The queue must be **durable** (a crash can't lose pending jobs) and handle **concurrent access from many workers without duplicating work.**

|Option|▸ Sweet spot|⚠ Watch-out|
|---|---|---|
|**Redis + Bull/BullMQ**|⭐ go-to for startups; Redis stores, Bull adds job semantics (**auto-retry, delayed jobs, priority queues**); "just works" for 90%|**memory-first** → can lose jobs in a hard crash even with persistence; for true durability use SQS/RabbitMQ|
|**AWS SQS**|zero ops (Amazon manages infra, scaling, delivery guarantee); great at low volume|**pay-per-message** gets pricey at scale; **1MB msg limit** → still store job data elsewhere, pass IDs|
|**RabbitMQ**|complex routing, battle-tested enterprise; sophisticated workflows|**self-host burden** — clusters, upgrades, disk monitoring|
|**Kafka**|⭐ **safe interview default**, esp. if stack already streams events; **append-only log → replay, fan-out, long retention**; huge volume + **strict ordering (within a partition)**|heavier than you need for simple job queues|

### 4.2 Pool of Workers _(key decision: how to run them)_

|Option|▸ Sweet spot|⚠ Watch-out|
|---|---|---|
|**"Normal" servers**|⭐ simplest; 10–20 processes looping `pop → process → mark_complete`; full control, easy debug (SSH in); **long jobs fine**|manage servers + pay for **idle capacity** in quiet periods|
|**Serverless (Lambda / Cloud Functions)**|no server mgmt; **auto-scales for spiky loads** (1,000 jobs → 0); pay per execution|**15–60 min execution cap**, **cold starts**, minimal local storage|
|**Container-based (K8s / ECS)**|middle ground; Docker + orchestrator scaling; long jobs OK + good utilization|more complex than plain servers|

```python
# Simplified worker loop
while True:
    job = queue.pop()        # blocks until a job is available
    if job:
        process_job(job)
        mark_complete(job.id)
```

### 4.3 Putting it together _(the canonical 8-step flow)_

1. Web server **validates** the request, creates a job record in the DB with status **`pending`**.
2. Web server pushes a message to the queue containing the **job ID** (⭐ **not the full job data** — same rule as SQS's 1MB limit).
3. Web server returns the **job ID** to the client **immediately**.
4. Worker **pulls** the message, **fetches job details** from the DB.
5. Worker updates status → **`processing`**.
6. Worker performs the **actual work**.
7. Worker **stores results** (S3 for files → `03f`, DB for metadata).
8. Worker updates status → **`completed`** or **`failed`**.

▸ **Each component fails independently and the system still functions:** queue down → web servers still accept, jobs pile up as `pending` in DB · workers crash → jobs wait in queue for new workers · DB down → workers retry until it recovers. ⚠ **Interview move:** don't debate vendors. **Kafka (or a queue you know) + regular server workers.** Show you understand **separation of concerns.**

---

## 5. When to Use in Interviews _(be proactive — spot it before they ask)_

▸ Signals that should trigger "async workers":

- **A specific slow operation is named** — "video transcoding / image processing / PDF generation / bulk emails / data exports." Jump in: _"transcoding takes minutes → I'll return a job ID and process async."_
- ⭐ **The math doesn't work** — "1M images/day" ÷ 86,400 ≈ **12 img/sec**; at 10s each = **120s of processing per second** → web servers **saturated** → offload to a worker pool on compute-optimized hardware. _(Do this math out loud → `01i`.)_
- **Different operations need different hardware** — mixing login requests with **GPU** work (ML inference, video) → separate with async workers on GPU instances.
- **They ask about scale or failures** — "what if a server crashes mid-processing?" → _"another worker picks it up from the queue; no user request lost."_
- ▸ **The skill is being the one to point it out** — signals you're thinking about **timeouts, resource utilization, UX** before prompted.

### 5.1 Where it shows up

- **YouTube** — upload → transcode (1080/720/480), thumbnails, captions, moderation → hours across many workers.
- **Instagram** — photo → multi-size, filters, metadata, recognition tags, policy check; **feed fan-out** to millions of followers via workers _(→ `03a`/`03e` hierarchical aggregation)_.
- **Uber** — "finding drivers…" while workers evaluate availability, routes, pricing; async driver-location updates.
- ⭐ **Stripe** — card auth is sync, but **fraud detection, 3DS, webhooks** are async; **delayed settlement** (bank transfers) → API returns **`pending`**, worker settles later. **← your fintech anchor.**
- **Dropbox** — upload → virus scan, search indexing, previews, device sync; API returns immediately _(→ `03f`)_.

---

## Common Deep Dives _(this is where the interview lives)_

▸ **DD1 — Handling Failures ("worker crashes mid-job")**

- **▸ PROBLEM** — a worker dies partway through a job. How do you know, and how does the job survive?
- **✅ SOLUTION — retry via another worker, detected by heartbeat.** The worker periodically **checks in** with the queue ("still alive"). No check-in → queue assumes it's **dead** → **re-delivers** the job to another worker.
- **⚠ CAUTION — the heartbeat/timeout interval is the real design decision:**
    - Too **long** → a real crash means the job is **significantly delayed** (queue optimistically waits).
    - Too **short** → wasted chatter, or worse, you mark a job **failed while it's still running** (e.g. a **GC pause**).
- **▸ Mechanism per system:** SQS **visibility timeout** · RabbitMQ **heartbeat interval** · Kafka **session timeout**. **Pick the longest interval users can tolerate as extra delay; 10–30s is a good start.**

▸ **DD2 — Handling Repeated Failures ("a job keeps failing — bug or bad input")**

- **▸ PROBLEM** — without handling, failed jobs **retry forever**; workers waste cycles while good work backs up. A **poison message** can crash worker-after-worker and **take down the whole fleet.**
- **✅ SOLUTION — Dead Letter Queue (DLQ).** After a job fails a set number of times (**typically 3–5**), move it to a **separate queue** instead of retrying. Isolates bad jobs; healthy work continues. The DLQ becomes a **human-investigation bucket** — fix the bug / clean the data, then re-queue. _(Same DLQ concept as `03e`/`03b`.)_
- **▸ Built-in support:** SQS **redrive policy** · RabbitMQ **dead letter exchange**.
- **⚠ CAUTION — monitor DLQ depth.** A **growing DLQ = a bug** that needs immediate attention.

> ⚠ **Confusion resolved — "Who counts the failures and moves the job to the DLQ — the worker or the queue?"** **The queue/broker — not the worker.** ▸ **Why:** retries **scatter across different workers** (attempt 1 → worker A, attempt 2 → worker B…), so **no single worker knows it's the Nth attempt.** Only the broker sees every delivery, so the broker owns the count. ▸ **Mechanism** — the worker's vocabulary is just **ack (success)** or **nack / timeout (failure)**; it never reports a count. On each delivery the broker **increments a receive-count**; once it exceeds the threshold (3–5), the **broker auto-moves the message to the DLQ.**
> 
> - **SQS** — redrive policy `maxReceiveCount` (tracks `ApproximateReceiveCount`).
> - **RabbitMQ** — dead-letter exchange (DLX); attempts tracked in `x-death`.
> - **Redis + Bull** — the **Bull library** tracks `attempts` and moves to the failed set (library-owned, not your business code). ⚠ A slow-but-alive worker (long GC pause) can let the visibility timeout lapse → redelivery burns retry attempts toward the DLQ though nothing truly "failed" → same timeout-tuning tension as **DD1**.

▸ **DD3 — Preventing Duplicate Work ("user clicks Generate 3×")**

- **▸ PROBLEM** — three identical jobs → wasted processing, or worse **three emails / three charges.** Side effects compound when jobs aren't idempotent.
- **✅ SOLUTION — idempotency keys.** Require a unique ID per operation; **check before creating** — if a job with that key exists, **return the existing job ID** instead of a new one.
    - **User-initiated:** `userID + action + timestamp` (⭐ **round the timestamp** to the window you want to dedupe over).
    - **System-generated:** deterministic ID from the input data.
- **▸ Also make the WORK idempotent** — a job that fails halfway and retries must be **safe to run again** (check if the email was already sent / file already processed before proceeding). _(Same discipline as at-least-once + idempotent writes in `03e §4.1`.)_

```python
def submit_job(user_id, job_type, job_data, idempotency_key):
    existing = db.get_job_by_key(idempotency_key)
    if existing:
        return existing.id           # dedupe: return existing, don't re-enqueue
    job_id = create_job(user_id, job_type, job_data)
    db.store_idempotency_key(idempotency_key, job_id)
    queue.push(job_id)
    return job_id
```

▸ **DD4 — Managing Queue Backpressure ("Black Friday, 10× jobs, workers can't keep up")**

- **▸ PROBLEM** — workers fall behind → queue grows **unbounded** → memory explodes, wait times stretch to hours, new jobs rejected, users wait for results that never come.
- **✅ SOLUTION — backpressure: slow acceptance when overwhelmed.** Set **queue-depth limits**; when too deep, **reject new jobs immediately** with a **"system busy"** response rather than accepting work you can't do. _(General backpressure → `02 §6`.)_
- **✅ Autoscale workers on QUEUE DEPTH, not CPU.** Queue grows past a threshold → add workers; shrinks → scale down (CloudWatch alarms + Auto Scaling groups).
- **⚠ CAUTION — CPU is a lagging signal.** _"By the time CPU is high, your queue is already backed up."_ **Queue depth is the key metric.**

▸ **DD5 — Handling Mixed Workloads ("5-second reports vs 5-hour year-end exports in one queue")**

- **▸ PROBLEM — head-of-line blocking.** A simple report waits **hours** behind a massive export; worker utilization goes uneven; autoscaling becomes unpredictable (can't guess job duration).
- **✅ SOLUTION — separate queues by job type / expected duration.** A **fast** queue (many light workers) + a **slow** queue (fewer, beefier workers) → no head-of-line blocking, tune each independently.
    - **Route on submit** when you know duration.
    - ⚠ **If you can't predict duration**, start in the **fast** queue and **promote to slow** if the job exceeds a time limit → keeps the fast queue responsive.
    - **Alternative — chunk large jobs** into smaller units on the same infra (e.g. split feed fan-out into **batches of followers** → `03e` hierarchical aggregation).

```yaml
queues:
  fast: { max_duration: 60s, worker_count: 50, instance_type: t3.medium }
  slow: { max_duration: 6h,  worker_count: 10, instance_type: c5.xlarge }
```

▸ **DD6 — Orchestrating Job Dependencies ("fetch data → generate PDF → email it")**

- **▸ PROBLEM** — without orchestration you get spaghetti: workers directly queue the next step, error handling is unclear (retry the step or restart?), and finding _which_ step failed means digging through logs.
- **✅ SOLUTION — scale the tooling to the complexity:**
    - **Simple chains** → each worker **queues the next job before marking itself complete**, carrying **full context** so steps retry independently:

```json
{ "workflow_id": "report_123", "step": "generate_pdf",
  "previous_steps": ["fetch_data"],
  "context": { "user_id": 456, "data_s3_url": "s3://bucket/data.json" } }
```

- **Complex workflows** (branching, parallel steps) → a **workflow orchestrator: AWS Step Functions · Temporal · Airflow** — define workflows as code, per-step retries, visibility into where it's stuck.
- **⚠ CAUTION** — orchestration adds real complexity; **only reach for it when dependencies are truly complex.** Full treatment → **`03c` Multi-step Processes.**

---

## Quick Recall (pass 3+)

|Question|Answer|
|---|---|
|The one principle|**decouple acceptance from processing** — web server enqueues + returns job ID in ms; worker pool does the heavy work|
|Trigger|any operation **> a few seconds** (video/image/PDF/bulk email/CSV import)|
|Why sync breaks|**LB timeouts (~30–60s) · no progress feedback · retries → duplicate work**|
|The flow|**validate → create `pending` row → enqueue job ID (not full data) → return ID · worker: fetch → `processing` → work → store results (S3/DB) → `completed`/`failed`**|
|Queue must be|**durable** + safe under **concurrent workers** (no dup work)|
|Queue choices|**Redis+Bull** (⭐ startups, memory-first = crash risk) · **SQS** (zero-ops, $/msg, 1MB) · **RabbitMQ** (routing, self-host) · **Kafka** (⭐ safe default, replay/fan-out/ordering)|
|Worker choices|**normal servers** (⭐ simplest, long jobs OK, idle cost) · **serverless** (spiky, 15–60min cap, cold start) · **containers** (middle ground)|
|Store in queue|**job ID only**, not full payload (fetch details from DB)|
|Trade-offs gained|fast response · independent scaling · fault isolation · resource fit|
|Trade-offs lost|complexity · eventual consistency · status tracking · monitoring overhead|
|Interview default|**Kafka + regular-server workers**; show separation of concerns, don't debate vendors|
|DD1 worker crash|**heartbeat** → no check-in = retry elsewhere; interval tradeoff (long=delay · short=false-dead/GC pause); SQS visibility / RabbitMQ heartbeat / Kafka session timeout; **10–30s start**|
|DD2 repeated fail|**DLQ after 3–5 fails** (isolates poison messages); human investigation + requeue; ⚠ **growing DLQ = bug**; SQS redrive / RabbitMQ DLX|
|DD2 who moves to DLQ|**the broker, not the worker** — retries scatter across workers so only the broker sees every delivery; worker only **ack/nack**, broker **counts + moves** (SQS `maxReceiveCount` · RabbitMQ DLX · Bull `attempts`)|
|DD3 duplicate work|**idempotency key** (userID+action+**rounded** ts / deterministic); check-before-create, return existing; **make the work idempotent too** (`03e §4.1`)|
|DD4 backpressure|**queue-depth limit → reject "system busy"**; **autoscale on QUEUE DEPTH not CPU** (CPU lags) (`02 §6`)|
|DD5 mixed workloads|**head-of-line blocking** → **separate fast/slow queues** (route on submit, or start fast→promote slow); or **chunk** big jobs (`03e`)|
|DD6 dependencies|simple: worker **queues next + carries context**; complex: **orchestrator (Step Functions/Temporal/Airflow)** — full detail `03c`|

---

> 🔗 **HI quick reference:** https://www.hellointerview.com/learn/system-design/patterns/long-running-tasks/quick-reference