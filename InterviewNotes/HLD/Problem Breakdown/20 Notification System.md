# Notification Platform — Problem Breakdown

> 📐 **Revision note (calc):** ⭐⭐⭐ **the cleanest math in the recent batch, and every number does work.** **10M notifications/day ÷ 86,400 = ~100/sec sustained — _"honestly almost nothing."_** ⚠ **But a 1M campaign delivered in 5 min = 1M ÷ 300 = >3,000/sec, from ONE campaign** ⇒ ⭐⭐ **design for surges of ~5,000/sec = ~50× sustained.** ⭐⭐⭐ **And the number that IS deep dive 2: a 1M backlog at 5,000/sec takes ~3 min to clear (fine for a promo) — but an OTP arriving behind it waits 200 SECONDS against a 5-second SLA.** ⭐ **Draining 1M in under 5s would need 200,000/sec = 40× the design target.** **Plus: Twilio 1,000 SMS/sec split 100 reserved / 900 standard · provider p99 going 1s → 30s · dedup TTL 48h (172800s) to cover DLQ replays · cron scans every minute.**

> * ⭐⭐ **TWO Pattern callouts: `Multi-step Processes` → `03c` (FIRST appearance in your set) and `Scaling Writes` → `03e`.** ⚠ **No "Planning the Approach" section either — straight from requirements to entities.** Cross-refs: ⭐⭐⭐ **`05p` Job Scheduler overlaps heavily and HI names it directly for definition-vs-instances — treat DD1 as mostly `05p` re-run** · ⭐ **Redis token bucket + `SET NX` + dedup cache → `02a`** · **Postgres + `FOR UPDATE SKIP LOCKED` → `02g`, and ⭐ `05n §5.1` for the complementary `FOR UPDATE` lesson** · ⚠ **Kafka and why SQS wins here → `02c`** · **locks / claiming → `03b`** · **cache-with-DB-behind → `01e`** · **API design, 200 vs 202, PUT idempotency → `01b`** · **API Gateway + API keys → `02d`** · **numbers → `01i`.** **Siblings: ⭐⭐⭐ `05p` Job Scheduler (the parent) · `05r`/`05s` (the cron→queue move).**
> 
> **Calibration:** ⭐⭐ **High value, and the single best technical insight in your whole set is in DD3.** ▸ **DD1 is largely `05p` again — accept, enqueue, workers, visibility timeout, DLQ, at-least-once. Skim it via the cross-refs.** ⭐⭐⭐ **Spend your time on DD2 (priority isolation) and DD3 (the dedup ORDERING bug), both genuinely new.** ⭐ **ONE careful pass if you've done `05p`; two if you haven't.** ▹ ⚠ **I have no independent knowledge of this write-up — it postdates my training — so everything here comes from your paste.**
> 
> - ⭐⭐ **What actually scores:**
>     - **(a)** ⭐⭐⭐ **The ordering bug: claiming the idempotency key BEFORE the provider call turns at-least-once into at-most-once** (§5.3). ▸ **HI's Staff+ bar asks this by name.**
>     - **(b)** ⭐⭐⭐ **Separating queues fixes POSITION but not the shared provider rate limit or worker pool** (§5.2) — ⭐ **so you need budgets, not just lanes.**
>     - **(c)** ⭐⭐⭐ **"The ceiling is the providers rather than our own workers."** ▸ **Also from the Staff+ bar, and it's the whole problem in one line.**
>     - **(d)** ⭐⭐ **Chained idempotency: `campaignId:userId` only works if the CAMPAIGN id is itself stable.**
>     - **(e)** ⭐⭐ **"Your system is a router and a bookkeeper"** — ▸ **don't design socket connections to phones.**
>     - **(f)** ⭐⭐ **Rejecting the outbox pattern with a reason** — **_"accepting a notification is just a single publish and nothing else."_**
>     - **(g)** ⭐⭐ **Naming your delivery semantics explicitly, and pointing at each place a duplicate can enter.**
> - ⭐ **Transferable primitives:**
>     - ⭐⭐⭐ **Mark work done AFTER the irreversible side effect, never before.** ▸ **A claim written first and never released is indistinguishable from a completed job.** ⭐ **Reusable anywhere you dedupe around an external call.**
>     - ⭐⭐⭐ **When the bottleneck is someone else's rate limit, isolation means ALLOCATION, not capacity.** ▸ **You can't autoscale past a vendor ceiling — you can only decide who gets which slice.**
>     - ⭐⭐⭐ **Two traffic classes with opposite requirements need separation at EVERY shared layer** — **queue, compute, and the external budget.** ⭐ **Splitting one layer just moves the contention down a level.**
>     - ⭐⭐ **An idempotency key is only as stable as the thing it's derived from.** ▸ **Chain it all the way up.**
>     - ⭐⭐ **Record suppression as an outcome with a reason, never a silent drop.** ▸ **It's what makes the oncall question answerable.**
>     - ⭐ **Make the caller declare priority at the API** — ▸ **you can't infer it later, and every isolation decision depends on it.**
> - ⭐ **Re-run (cross-ref, NOT re-explained):** ⭐⭐⭐ **durable queue + visibility timeout + DLQ + retries with backoff (`05p §5.1`, `§5.3` — nearly identical)** · ⭐⭐ **definition-vs-instances (`05p §4.1`, HI names it)** · ⭐⭐ **at-least-once forces idempotency (`05p §5.3`)** · **a cron scanning a table for due rows (`05p §4.1`, `05r §5.3`)** · **cron → event-driven (`05p`, `05s §5.3`)** · **`FOR UPDATE` semantics (`05n §5.1`)**. **Genuinely new:** ⭐⭐⭐ **the dedup ordering bug and its 7-step trace** · ⭐⭐⭐ **per-tier provider budgets via a shared Redis token bucket** · ⭐⭐⭐ **two traffic classes as the design driver** · ⭐⭐ **circuit breaker / bulkhead / provider router** · ⭐⭐ **why the outbox pattern does NOT apply** · ⭐⭐ **device tokens pushed TO you because they rotate** · ⭐⭐ **`userId` in the path being CORRECT here** · ⭐ **`SELECT … FOR UPDATE SKIP LOCKED`** · ⭐ **dedup-store failure degradation.**

---

## 0 · Understanding the problem

🔔 **What is a Notification System?**

⭐⭐ **An INTERNAL PLATFORM that other teams use to send messages to users across push, email and SMS.** ▸ **Product services hand it a message and a recipient; the platform handles delivery.**

- ⭐⭐⭐ **The framing that changes everything downstream: _"our customers are other engineering teams inside the company."_** ▸ **Internal clients are things like **the auth service sending one-time passwords** or **the marketing team blasting a promo to a million users at once**.**
- ⭐ **Those two example clients ARE the two traffic classes.** ▸ **Notice that in §1.3 and the whole design falls out.**

---

## 1 · Requirements

### 1.1 Functional (what it does)

1. ⭐ **Send a notification to a user via push, email or SMS — immediately or in the future.**
2. ⭐⭐ **Send CAMPAIGNS — the same message to a whole SEGMENT of users, immediately or scheduled.**
3. ⭐ **Users can set notification preferences — channel opt-outs and quiet hours.**

⚠ **Below the line:** template management and rich content authoring · delivery analytics dashboards · in-app feeds and badge counts · frequency capping.

- ▹ ⭐ **HI's note, and it's blunt:** **_"you're not getting much credit (if any) for enumerating 'below the line' requirements, so skip these if you're low on time."_**

### 1.2 Non-functional (how it behaves)

▸ ⭐⭐ **HI insists on getting a number FIRST:** **_"This is a platform question, so how the system holds up under load is most of what we are being asked."_**

```
10M notifications/day  ÷ 86,400  = ~100/sec sustained   ⭐ "almost nothing"
⚠ but 1M campaign in 5 min       = >3,000/sec           from ONE campaign
⇒ ⭐⭐ design for ~5,000/sec       = ~50× sustained
```

1. ⭐⭐ **At-least-once delivery with best-effort deduplication.** ▸ **_"we'd rather send a notification twice accidentally than never at all."_**
2. ⭐ **Handle surges of ~5,000 notifications/sec.**
3. ⭐⭐ **Deliver high-priority notifications (OTPs, security alerts) within 5 SECONDS of acceptance, EVEN DURING A SURGE.**

⚠ **Below the line:** strict ordering across channels · compliance/consent/spam workflows · monitoring, alerting, CI/CD.

- ⭐⭐ **And a point worth making out loud:** **_"These requirements aren't really independent, the best-effort deduplication makes the surges harder to handle."_** ▸ ⭐ **Flagging interdependence between NFRs is cheap and reads as experience.**

### 1.3 ⭐⭐⭐ The design driver — two traffic classes, one pipeline, and the ceiling isn't yours

> ⭐⭐⭐ **HI states it plainly: _"Getting both through one system is the heart of this problem."_**

||⭐⭐ **High priority**|⭐⭐ **Standard**|
|---|---|---|
|**Examples**|**OTPs, security alerts**|**promos, digests**|
|**Volume**|⭐ **low**|⚠ **huge bursts**|
|**Latency**|⭐⭐ **5-second SLA** — ▸ **_"if you get the code to log in 20 minutes later you probably just assumed the website didn't work"_**|⭐ **_"nobody cares if they land ten minutes late"_**|

- ⭐⭐⭐ **So the API must make callers DECLARE a priority on every send.** ▸ **HI: _"It's also why our API is going to ask callers to declare a priority."_** ⭐ **You cannot infer it later, and every isolation decision in §5.2 depends on it.**
- ⭐⭐⭐ **And the second half, which is what separates this from `05p`: the ceiling is EXTERNAL.** ▸ **Providers cap you at ~5,000/sec across channels.** ⚠ **You cannot autoscale past a vendor's rate limit** — ⭐⭐ **so isolation here means ALLOCATION, not capacity.** ▹ **HI's Staff+ bar names it: _"they know the ceiling is the providers rather than our own workers."_**

▹ ⚠ **No "Planning the Approach" section in this write-up** — it goes straight to entities.

---

## 2 · Core Entities

- ⭐ **Notification** — **a single message to a single user on a single channel, plus its current status.** ▹ _"a marketing email to John at 4pm."_
- ⭐ **Campaign** — **a scheduled send to a GROUP: delivery time, channel, audience.**
- ⭐ **Segment** — **a named audience like "all users in Canada."** ⭐ **Membership is maintained by whatever tool defines the audience; you READ it at fan-out.**
- **User** — **recipient, preferences, contact info.**

> ⭐⭐ **The relationship to notice, and HI calls it out explicitly:** **_"A notification is like an instance of a class."_**
> 
> - ⭐⭐⭐ **Definition vs instances — and HI names the other two places it appears:** **`05p` Job Scheduler (a recurring job vs its executions)** and **calendar systems (an event vs its occurrences).** ▸ ⭐ **Third time this pattern has surfaced in your set.**
> 
> ■ **— end of insert · HI write-up resumes below —**

▹ ⚠ **Minor inconsistency: the whiteboard entity list includes `Template`, the prose list doesn't** — **and template authoring is explicitly out of scope.** ⭐ **It exists only as a `templateId` reference on Campaign. Use the prose list.**

---

## 3 · API

### 3.1 Send one notification

```
POST /notifications -> 200 OK { id, status }
{ userId, channel,   // push | email | sms
  priority,          // ⭐⭐ high | standard
  content,           // { title, body }
  scheduledAt }      // optional, defaults to now
```

- ▹ ⭐ **"Provider" = the third party that actually delivers — Twilio (SMS), an email service over SMTP, APNs/FCM (push).** ▸ **You never touch a phone or an inbox; you hand off.** ⭐ **Defined properly in §4.1.**
- ⭐ **It returns 200 only because the first design calls the provider INLINE, inside the request** — ▸ **so you waited for Twilio's answer and can report it.** ⭐⭐ **_"Once delivery moves off the request path, accepting a notification and delivering it stop being the same event."_** ▸ **With a queue in between, your response goes out BEFORE anyone has called the provider, so there's no outcome to report** ⇒ ⭐ **202 Accepted ("I've taken responsibility, ask later") plus `GET /notifications/{id}`** (§5.1).

### 3.2 Send a campaign

```
POST /campaigns -> 202 Accepted { id }
{ segmentId, channel, priority, templateId, scheduledAt }
```

- ⭐⭐ **Why a SEPARATE endpoint:** **you could stretch `POST /notifications` to accept a `segmentId`, _"but then one endpoint sometimes creates a notification and sometimes creates a campaign which is unnecessary overloading."_**
- ⭐ **Why 202 immediately:** **_"The sending happens later, so there's no outcome it could report at creation time."_** ▹ **HI: few interviewers care about 200 vs 202, but know it in case yours does.**
- ⭐⭐ **And flag the evolution up front:** **_"Both of these bodies grow an idempotency key before we're done. It's fine to start with the simple contract and evolve it, as long as you tell your interviewer that's what you're doing."_**

### 3.3 Preferences and devices

```
PUT /users/{userId}/preferences -> Preferences
{ optOuts,     // e.g. ["sms"]
  quietHours } // e.g. { start: "22:00", end: "08:00", tz }

PUT /users/{userId}/devices -> Device
{ platform,    // ios | android
  pushToken }
```

- ⭐ **`PUT` because preferences are a full replace of a known resource** ⇒ ⭐ **_"gives us an idempotent endpoint for free."_**

> ⭐⭐⭐ **Confusion resolved — `userId` is in the PATH here, and that's CORRECT. This is the exception to the rule.**
> 
> - ⚠ **In `05c`/`05h`/`05i`/`05n`/`05q` the rule was: identity comes from the JWT, never the client. `userId` in a path or body is a red flag.** ⭐⭐ **HI pre-empts the alarm deliberately.**
> - ⭐⭐⭐ **Why it inverts: _"our callers aren't end users at all. They are internal services authenticated with API keys, acting on behalf of the users whose preferences they are changing."_** ▸ **When someone flips a toggle in the product's settings page, **the product's backend** calls you with a `userId` **it has already authenticated**.**
> - ⭐ **So the rule generalises properly: identity must come from an authenticated principal.** ▸ **For an end-user API that's their JWT. For a service-to-service platform API it's the caller's API key plus a delegated subject.**
> - ▹ ⭐ **HI's bonus: a platform or internal-tools team may ask how authorization CARRIES through — _"delegation tokens or service accounts that allow a service to act on behalf of another service or user."_**
> 
> ■ **— end of insert · HI write-up resumes below —**

---

## 4 · High-Level Design

▹ ⭐⭐ **HI's warning before starting:** **_"We outlined some really juicy non-functional requirements but I would advise you to resist the urge to solve them now. It's more important we get a functional system working before we overwhelm ourselves jumping straight to the finish line."_**

### 4.1) Send a notification, immediately or scheduled

```
Upstream Service ──► API Gateway ──► Notification Service ──┬──► Notifications DB
(Order / Auth)        API-key auth     looks up address,     │     Notification: userId · channel
                      · rate limits    persists, calls       │                   message · status
                                       the provider          │     User: name · email · phoneNumber
                                                             ├──► SMTP     (Email)
                                                             ├──► Twilio   (SMS)
                                                             └──► APNs/FCM (Push)
```

**What we're building:**

- **API Gateway** — **the entry point for upstream services.** ⭐ **Authenticates each service's API key and applies rate limits _"so a runaway service doesn't break high-priority use-cases like authentication."_**
- **Notification Service** — **the core: looks up the recipient's address, persists the notification, calls the provider.**
- **Database** — **Notification rows plus YOUR SLICE of user data** (email, phone), ⭐ **which syncs over from the product's user service.** ▹ **Postgres, though _"frankly any modern database works here."_**
- **Provider** — **the thing that actually gets the message into the inbox.** ⭐ **_"We don't own the last mile of delivery, the provider does."_**

**The send-now flow — five steps:**

1. **Service POSTs `/notifications`.**
2. **Gateway authenticates the API key, forwards.**
3. **Notification Service looks up the address from your user slice.**
4. **Writes a row with status `PENDING`, then calls the provider.**
5. **Updates to `SENT` or `FAILED` from the provider's response, returns 200 + id + status.**

> ⭐⭐⭐ **The most common mistake on this question — HI says so explicitly.**
> 
> - ⚠⚠ **_"conflating the notification platform with the delivery provider."_**
> - ⭐⭐⭐ **The line to hold onto: _"Your system is a ROUTER and a BOOKKEEPER. It decides what to send where, and it records what happened."_** ▸ **Carrier relationships and device connections belong to APNs, Twilio and the email provider.**
> - ⚠ **_"When a candidate starts designing persistent socket connections to phones, they're solving a different and much harder problem, and a good interviewer will redirect them."_**
> 
> ■ **— end of insert · HI write-up resumes below —**

**⭐⭐ Push is the one channel that needs something extra:**

- ▸ **To send a push you hand a DEVICE TOKEN to APNs or FCM.** ⭐⭐ **Those tokens ROTATE, so _"there's nothing stable for the user service to sync over the way it syncs email addresses and phone numbers."_**
- ⭐ **So the product's mobile app sends you the token DIRECTLY — on login and whenever it changes** — via `PUT /users/{userId}/devices`. ▸ **Once it sits with the rest of your user data, a push send works exactly like an email: look up a token instead of an address.**

**⭐ Scheduled sends — one new component:**

- ▸ **Write the row with status `SCHEDULED` and stop** — don't call a provider.
- ⭐ **Add a scheduling CRON that scans the Notifications table every minute for scheduled rows whose time has arrived**, and pushes each through the same send path.
- ⭐⭐ **Why minute granularity is fine:** **_"Anything that cares about seconds, like an OTP, comes in as a synchronous request and never touches the cron job at all."_** ▹ ⭐ **Contrast `05p §5.1`, where 2-second precision forced a two-layer scheduler. Here the latency-sensitive path simply bypasses the scheduler.**

### 4.2) Campaigns

▸ **`POST /campaigns` writes a Campaign row and returns 202.** ⭐ **_"It's just CRUD until we turn that one row into deliveries."_**

**⭐ Reuse the existing cron — point it at the Campaigns table too:**

1. **Cron finds a Campaign whose `scheduledAt` has passed.**
2. **Reads the segment's membership to resolve recipients.**
3. **For each recipient, pushes a send through the same path a direct notification takes.**
4. **Marks the campaign complete.**

> ⭐⭐ **The trade-off HI wants you to NOTICE — and says so about why:**
> 
> - ⭐ **The segment is read as a SNAPSHOT when fan-out starts.** ▸ **_"someone who joins mid-publish misses this campaign and catches the next one."_** ⭐ **Fine for marketing — but say it.**
> - ⭐⭐⭐ **HI's framing of why noticing matters: _"a big thing separating senior candidates from juniors is just noticing issues like this."_**
> 
> ■ **— end of insert · HI write-up resumes below —**

**⚠⚠ HI then names three problems with the one-pipeline design — these ARE the deep dives:**

1. ⚠⚠ **The provider call is in the request path.** **A slow Twilio makes your callers wait** — ⭐ **and worse, _"if our service crashes after writing the row but before calling the provider, that notification is simply gone. So much for at-least-once."_** ▸ **→ §5.1.**
2. ⚠⚠ **A big campaign fights everything else for resources.** **_"all million sends might sit before the OTP code we want to give a user."_** ▸ **→ §5.2.**
3. ⚠ **A single host is making a million provider calls.** **_"If it dies halfway through we have no idea where it stopped."_** ▸ **→ partly §5.3, and see the ⊕ note there.**

### 4.3) Preferences

▸ ⭐ **No new components — preferences are attributes on the User.**

- ⭐ **Opt-out per channel + a quiet-hours window.** ⭐⭐ **Quiet hours apply to STANDARD notifications but NOT to high priority** — OTPs and fraud alerts go through regardless.
- **Checked right before the provider call.**
- ⭐⭐⭐ **And the detail worth stealing: when the check suppresses something, record it as `SUPPRESSED` WITH THE REASON rather than dropping silently.** ▸ **HI's reason: _"this will come in handy later when we're oncall going 'why the heck did this user not get this notification?!'"_** ⭐ **Suppression is an outcome, not an absence.**

▸ ⚠ **HI's honest summary of the HLD: _"It works, but it doesn't satisfy a single one of our non-functional requirements."_**

---

## 5 · Deep Dives

### 1) ⭐ How do we guarantee an accepted notification is never dropped?

⚠⚠ **Mostly `05p` re-run — skim it.** ▸ **Same shape: get delivery off the request path and onto a durable queue.**

> ⭐ **Pattern: Multi-step Processes** (`03c`) — **callout #1 of 2, and the first `03c` in your set.** ▹ **Delivery is accept → enqueue → deliver → record, and _"every step can fail independently."_** ⭐ **HI deliberately avoids Temporal here: _"most interviewers will wave you off because it obscures some of the most interesting aspects of this problem."_** ▹ **Contrast `05o §5.1`, where a DAG orchestrator WAS the answer.**
> 
> ■ **— end of insert · HI write-up resumes below —**

⚠ **Rung labels are mine.**

#### ⚠⚠ Bad — synchronous call with retries

- **Approach:** **keep the inline call, wrap it in retries with backoff before giving up.**
- ⚠ **Challenges — HI: _"Everything else about it is worse than what we started with."_**
    - ⚠⚠ **The retry loop lives in PROCESS MEMORY** ⇒ **a crash or a routine deploy still loses everything.**
    - ⚠⚠ **During a real outage the caller's connection is held open for the whole backoff** ⇒ ⭐ **_"the auth service starts timing out on logins because our SMS provider is degraded."_** ▸ **HI's principle: _"fail fast and fail loud, which this does neither."_**
    - ⚠⚠⚠ **And the killer: the caller can't distinguish _"we gave up"_ from _"we never got it."_** ⇒ ⭐⭐ **_"What we have built here is at-most-once delivery, the exact opposite of what we promised."_**

**Why climb:** acknowledging and delivering must stop being the same event.

#### Good — a `PENDING` table polled by a dispatcher

- **Approach:** **write the row `PENDING`, respond immediately. A background dispatcher polls for `PENDING` rows, calls providers, marks `SENT`/`FAILED`.** ✅ ⭐ **A dispatcher crash loses nothing — _"the work is still sitting in the table when it comes back."_**
- ⭐ **This is where the API becomes async:** `POST /notifications -> 202 Accepted { id }` plus `GET /notifications/{id} -> { id, status, updatedAt }`.
- ⚠ **Challenges — _"we've just signed ourselves up to build a queue on top of Postgres, and Postgres makes a mediocre queue."_**
    - ⚠ **Several dispatchers in parallel can grab the same row and send twice** ⇒ ⭐ **each must CLAIM rows, _"typically with `SELECT ... FOR UPDATE SKIP LOCKED`."_** ▹ ⭐ **Note the complement to `05n §5.1`: there the lesson was that `FOR UPDATE` doesn't block INSERTs; here `SKIP LOCKED` is the row-claiming idiom.**
    - ⚠ **You build retries yourself** — tracking attempt counts and next-attempt times.
    - ⚠ **The table becomes both queue AND history** ⇒ **every poll works around a growing pile of sent/failed rows unless you prune or partition.**
    - ⚠⚠ **Latency floor = the poll interval.** ▸ **Poll every 10s and a message that just arrived waits 10s.**

**Why climb:** stop building a bad queue.

#### ⭐ Great — a real durable queue

- ⭐ **Approach: the Notification Service hands the notification to a durable queue and returns 202 once the queue ACKS.** ⭐⭐ **The accept path no longer writes to the database at all — just to the queue.** ▸ **_"If we crash before the enqueue the caller gets an error and sends it again."_** ▹ **SQS, though any durable queue works.**

**⭐ The delivery flow — five steps, and the ORDER matters for §5.3:**

1. **Worker receives a message; the queue hides it from others for a visibility timeout.**
2. **Looks up the address or device token, checks preferences.**
3. **Calls the provider.**
4. **Writes the outcome to a Notification row — `SENT`, or `FAILED` which records the attempt and leaves it eligible for retry.**
5. ⭐ **ONLY THEN deletes the message from the queue.**

- ⭐ **Worker dies mid-flight ⇒ the message stays; the visibility timeout expires and another worker retries.** **Provider failures retry with exponential backoff; too many failures ⇒ DLQ _"for someone to inspect instead of being retried forever."_**
- ⭐ **And the operational point:** **_"The queue handles most of this for us. We configure the retry policy, visibility timeout, and dead-letter queue rather than building that machinery ourselves."_**
- ⚠ **Challenges:**
    - ⚠⚠ **More duplication than you started with.** ⭐ **SQS is at-least-once, so _"it can internally produce duplication even if we didn't start with a duplicate message"_** — plus callers create their own. ▸ **→ §5.3.**
    - ⚠ **Consuming is DESTRUCTIVE.** ⭐ **_"If we ship a bad worker build we can't rewind this afternoon's traffic to replay it."_**

> ⭐⭐ **Two choices HI makes explicitly here — both worth having ready.**
> 
> **1. ⭐⭐ Why NOT write-to-DB-then-publish, and why NOT the outbox pattern.**
> 
> - ⚠ **Many candidates propose writing the row first and publishing second** — ⭐ **that's a DUAL WRITE, and _"a crash between those two steps leaves a row that no message represents."_**
> - ⭐⭐ **The outbox pattern fixes it (the queue is derived from committed rows), but HI rejects it with a clean rule:** **_"An outbox is good when we need to commit database state AND produce a message together. Accepting a notification is just a single publish and nothing else."_** ▸ ⭐ **That's the sharpest statement of when outbox applies that you'll get.** ▹ ⚠ **Contrast `05s §5.3`, where dual writes WERE right — because there the application needed a gate between storing and notifying.**
> 
> **2. ⭐⭐ SQS vs Kafka, with Kafka's real advantage named.**
> 
> - ⭐ **_"The strongest case for Kafka is that being able to rewind and replay means that if you ship a bad worker build, you can reset the offset and reprocess this morning's sends instead of losing them."_**
> - ⭐⭐ **_"This is a real advantage, but it's not something our requirements asked for, so we stayed with SQS."_** ▸ ⭐⭐⭐ **Third data point on the log-vs-work-queue thread (`05p`, `05q`) — and the FIRST time the log side gets a genuine win named. The deciding question is still "what does this buy that nothing else does."**
> 
> ■ **— end of insert · HI write-up resumes below —**

> ⭐ **Pattern: Scaling Writes** (`03e`) — **callout #2.** ▹ **A campaign blast is a write surge; _"buffering it in a durable queue is one of the key strategies for scaling writes."_**
> 
> ■ **— end of insert · HI write-up resumes below —**

> ▸ ⭐⭐ **Status quo after DD1 — read this before DD2, because DD2's problem only makes sense against it.**
> 
> - ⭐⭐ **The synchronous provider call is gone for ALL notifications — OTPs and marketing emails alike.** ▸ **Both are accepted by publishing to the durable queue; workers deliver later.**
> - ⭐⭐ **The cron is NOT gone.** ▸ **It still handles work scheduled for the future — but when a scheduled notification or campaign comes due, it now PUBLISHES TO THE QUEUE instead of calling the provider directly.**
> 
> ```
> Send now         API ──► durable queue ──► worker ──► provider
> 
> Scheduled send   API ──► DB as SCHEDULED
>                  cron at the due time ──► durable queue ──► worker ──► provider
> ```
> 
> - ⚠⚠ **And the thing DD2 attacks: high-priority and standard messages still SHARE that one queue.** ▸ ⭐ **DD2 splits them into separate priority queues and worker pools so a campaign cannot delay an OTP.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 2) ⭐⭐⭐ How do we deliver high-priority notifications within 5 seconds during a blast?

> ⭐⭐⭐ **HI: _"This is the crux of the interview and where I spend the most time when I ask it."_**

📐 **The scenario, and the arithmetic IS the problem:**

```
9:00:00  marketing queues 1M notifications — ⭐ enqueue is fast
         providers cap us at 5,000/sec across channels
         ⇒ the backlog clears in ~3 minutes.  ✅ fine for a promo.

9:00:05  the auth service accepts a login OTP.
         It lands in the SAME queue, ⚠⚠ a MILLION messages back.
         At 5,000/sec it waits ⭐⭐⭐ 200 SECONDS — against a 5-second SLA.
```

⚠ **Rung labels are mine.**

#### ⚠⚠ Bad — just autoscale the workers

- ▹ ⭐ **HI: _"This is the first answer I get maybe half the time."_** **Autoscale the pool on queue depth and drain faster.**
- ⚠ **Challenges:**
    - 📐 ⭐⭐ **To drain 1M in under 5 seconds you'd need 200,000 sends/sec — _"which is 40x our design target."_**
    - ⚠ **Bringing up servers _"typically takes seconds to minutes"_** ⇒ **too slow for a 5-second SLA.**
    - ⚠ **AWS imposes account limits on burst provisioning** — ⭐ **and HI explains why: _"Somebody has to keep all those idle servers when you're not using them."_**
- ⭐⭐⭐ **But the deeper reason it can never work: the ceiling isn't your workers, it's the PROVIDER.** ▸ **More workers cannot exceed 5,000/sec.** ⭐ **Say that and you've skipped a rung.**

**Why climb:** you can't add capacity past someone else's rate limit. Stop trying to go faster and decide who goes first.

#### ⭐⭐ Good — split the queue by priority

- ⭐ **Approach: a HIGH PRIORITY queue and a STANDARD queue, routed by the priority the caller declared at the API.** **Workers drain high priority first.**
- ✅ ⭐ **_"our OTP sits in a small queue that gets served first even while our marketing queue is completely backed up."_**
- ⚠⚠ **Challenges — and this is the sharp insight of the dive: _"We've solved queue POSITION, but everything downstream of it is still shared."_**
    - ⚠⚠⚠ **THE PROVIDER.** **_"If standard traffic is consuming our entire Twilio rate allocation, the high priority SMS is going to get throttled by them even if it sits in a small queue on our side."_** ▸ ⭐⭐ **Your lane is clear and the road is still blocked.**
    - ⚠⚠ **THE COMPUTE.** **One shared pool draining high-priority-first works in the happy case — but _"the worker itself [could be] stuck behind a slow provider call and thus holding up the high priority queue."_**

**Why climb:** splitting one shared layer just pushes the contention down to the next one.

#### ⭐⭐⭐ Great — isolation plus budgets

> ⭐⭐ **HI's framing: _"We need more isolation (separating queues and worker pools) and more control (provider budgets and token buckets)."_**

- ⭐⭐⭐ **The token bucket, with HI's concrete numbers:**

```
Twilio sells us 1,000 SMS/sec.  Today any tier can spend all 1,000 ⇒ OTPs starve.

Shared token bucket in Redis, refilled at the top of each 1-second window:
  ⭐⭐ HIGH     → a RESERVED slice:  100 of the 1,000
  ⭐  STANDARD → the remaining 900, and ⭐⭐ it CANNOT touch the reserved 100,
                 "no matter how far behind it falls"

Every worker draws a token before it calls the provider.
```

- ⭐⭐ **Plus separate COMPUTE: the high-priority queue gets its own worker pool.** ▸ **So a stuck standard worker can't pin the high-priority path.**
- ⚠ **Challenges, and HI accepts both deliberately:**
    - ⭐⭐ **_"The high priority pool sits underused most of the time, but that's a deliberate choice worth the tradeoff. Keeping the pool ready ensures it's available for OTPs and fraud alerts."_** ▸ ⭐ **Paying for idle capacity IS the answer here — say it as a choice, not an oversight.**
    - ⭐ **The budget adds a Redis check in front of every provider call** — **_"one more moving part to build and get right. But again, that's what we want."_**

#### ⭐⭐ Surviving a provider brownout

⚠ **The other way to blow the SLA: _"Say Twilio's API p99 climbs from under a second to 30 seconds. Our workers don't know that, so they keep calling, and each stuck call pins a worker for 30 seconds."_**

- ⭐⭐ **And the honest goal: _"While a provider is browned out we cannot deliver everything on time, so the job is to keep high priority messages moving and let everything else wait it out."_**

|Pattern|What it does|
|---|---|
|⭐⭐ **Circuit breaker**|**track failure/timeout rate per provider; past a threshold the breaker OPENS so calls fail immediately instead of waiting out a 30s timeout** ⇒ ⭐ **shed non-essential load to leave room for high priority**|
|⭐⭐ **Bulkhead**|**cap in-flight calls to one provider, like a semaphore.** ▸ **_"When Twilio has its allotment outstanding, no more workers start a call to it, so we're not spinning all our capacity on a service that's mostly down."_**|
|⭐ **Provider router**|**primary + backup for channels that have substitutes.** ⭐ **And get clever in the PRODUCT: _"if SMS is down maybe email is the only option we offer for authentication."_**|

### 3) ⭐⭐⭐ How do we prevent duplicates on top of at-least-once?

⭐⭐ **Where duplicates come from — three distinct sources, name all three:**

1. ⭐⭐ **A worker calls Twilio and dies before deleting the message.** **The SMS went out, the queue doesn't know, the visibility timeout lapses, another worker sends it again.**
2. ⭐ **A caller POSTs, times out, and POSTs again.**
3. ⭐ **Your own cron crashes halfway through fanning out a segment** — **_"when it runs again everything that was already added goes back into the queue."_**

- ⭐⭐ **And set expectations honestly: _"True exactly-once delivery is impossible to achieve, but we can go a long way toward keeping duplicates rare."_**

⚠ **Rung labels are mine.**

#### ⚠⚠ Bad — claim the key BEFORE sending

- ⭐⭐ **First, the thing both rungs need: a STABLE ID.** ▸ **_"If a retry were to produce a different ID than the original, there is no way anything downstream can tell the two apart."_**
    - ⭐ **Callers pass an idempotency key on `POST /notifications`; you derive the notification's ID from it.**
    - ⭐⭐ **Campaign messages are stamped `campaignId:userId`** ⇒ **a cron that crashes and republishes a segment _"produces exactly the IDs the first pass produced."_**
    - ⭐⭐⭐ **And the chained requirement most candidates miss: that only works if the CAMPAIGN id is itself stable, which is why `POST /campaigns` takes an idempotency key too.** ▸ **_"Without one, a retried campaign creation gets a fresh campaignId, every message in it is stamped differently, and every recipient gets the promo twice."_**
- **Approach:** **before dispatching, the worker writes the ID to Redis with `SET NX`** — **_"the worker putting its hand up and saying 'I'm taking this one.'"_** ⭐ **The write is atomic, so of two workers holding the same message only one succeeds.**

> ⚠⚠⚠ **Confusion resolved — why claiming FIRST turns at-least-once into at-most-once. HI's Staff+ bar asks this by name; know the trace.**
> 
> 1. **A user taps "log in"; the auth service POSTs an OTP with idempotency key `otp-8412`.**
>     
> 2. **The service derives `n:otp-8412`, enqueues it to the high-priority queue, returns 202.**
>     
> 3. **Worker A runs `SET n:otp-8412 NX` → `OK`. It proceeds.**
>     
> 4. ⚠⚠ **Worker A's host _"gets nuked by a deploy."_ Nothing was sent, and the message was never deleted.**
>     
> 5. **The visibility timeout lapses; the queue redelivers to Worker B.**
>     
> 6. ⚠⚠⚠ **Worker B runs `SET n:otp-8412 NX` → `nil`, and WRONGLY assumes it's already handled.**
>     
> 7. ⚠⚠ **Every redelivery after that does exactly the same thing.**
>     
> 
> - ⭐⭐⭐ **_"The lock stays around even after the worker who took it dies, so every redelivery gets dropped even though nothing was ever sent. We just turned at-least-once into at-most-once."_**
> - ⭐⭐⭐ **The generalisation, and it's the most reusable thing in this file: MARK WORK DONE AFTER the irreversible side effect, never before.** ▸ **A claim written first and never released is indistinguishable from a completed job.**
> 
> ■ **— end of insert · HI write-up resumes below —**

**Why climb:** flip the order.

#### ⭐⭐⭐ Great — check before dispatch, mark after the provider accepts

- ⭐⭐⭐ **The fix: _"check whether we've already sent it before dispatching, and write the dedup marker only AFTER the provider has taken it."_**
- ⭐ **Why Redis and not the database:** **you already write status to the DB, but _"checking the database before each notification could slow us down during surges"_** ⇒ ⭐ **Redis as a cache of recently-sent IDs, with the database as the source of truth behind it** (`01e`).

```
GET sent:{notificationId}              # before dispatch: present → duplicate, drop it
SET sent:{notificationId} 1 EX 172800  # ⭐ only AFTER the provider accepts
                                       #   48h covers DLQ replays
```

> ⚠ **Confusion resolved — `NX`, `EX`, and what actually changed.**
> 
> - **`NX` = "Not eXists"** — set only if absent, returns `nil` if the key is there. ⭐ **That's what made it a CLAIM.** **`EX` = seconds of TTL** (172800 = 48h).
> - ⭐⭐⭐ **The real change is what the key MEANS: a CLAIM ("someone is working on this") became a RECEIPT ("this was delivered").** ⚠ **Both look identical in Redis — a key that exists — which is why a dead worker's claim reads as a completed send.** ▹ **Note HI's prefix changes too: `n:{id}` → `sent:{id}`.**
> - ⭐ **So the Great version drops `NX` entirely** — plain `GET` then plain `SET`, because a receipt isn't a lock. ⚠ **Cost: two workers holding the same message can both send.** ⭐ **Deliberate — _"a rare duplicate so that a drop is impossible."_**
> 
> ■ **— end of insert · HI write-up resumes below —**

- ▸ **Flow: worker grabs a notification → checks Redis → already sent? drop it and take the next → otherwise send, update the DB, update the cache.**
- ⚠ **Challenges:**
    - ⚠ **A narrow window remains:** **provider accepts → worker dies before writing the outcome row → redelivery finds no record → sends again → _"the user gets the same login code twice."_** ⭐⭐ **_"We accept a rare duplicate so that a drop is impossible."_** ▸ **That sentence IS the delivery-semantics choice.**
    - ⭐⭐⭐ **And the degradation path, which the Staff+ bar asks about explicitly:**
        - **Redis down ⇒ fall through to the outcome table, _"looking for a SUCCESSFUL send rather than any row at all"_** — ⭐ **slower but still correct.** ▸ **Note the subtlety: a `FAILED` row must not count as sent.**
        - **Table also unreachable ⇒ ⭐⭐ workers SEND ANYWAY rather than hold the message**, and ⭐ **track how many sends skipped the check _"so an alert fires when that rate climbs."_** ▸ ⭐⭐ **Fail toward the guarantee you promised: at-least-once means when in doubt, send.**

> ⭐⭐⭐ **HI's closing instruction for this dive — do this on the whiteboard:**
> 
> **_"Name your delivery semantics explicitly. Exactly-once stops at the provider boundary, so the honest design is **at-least-once with deduplication at each point duplicates can enter**. You should be able to **point at each of those points on your diagram**."_**
> 
> ▸ ⭐ **The three points: the caller's retry (idempotency key) · your own cron re-fanning (`campaignId:userId`) · the queue's redelivery (the `sent:` check).**
> 
> ■ **— end of insert · HI write-up resumes below —**

> ⊕ ⚠⚠ **(mine, not HI) — the campaign FAN-OUT is still one host, and §5.2 quietly assumes it isn't.**
> 
> - ⚠ **§4.2 listed as problem #3: _"A single host is making a million provider calls… If it dies halfway through we have no idea where it stopped."_** ▸ **DD1 fixed the PROVIDER-CALL half by moving it to workers. DD3 made a restart SAFE via `campaignId:userId`.** ⚠⚠ **Neither fixed the FAN-OUT: one cron host still loops over a million users enqueueing.**
> - ⚠⚠ **And §5.2 opens with _"We can add all million notifications to the queue almost immediately"_** — ⭐ **which a single-host serial loop cannot do.** ▸ **At even 1,000 enqueues/sec that's ~16 minutes just to enqueue.**
> - ⭐⭐ **The fix is a TWO-STAGE fan-out:** **the cron writes one message per BATCH of recipients (say 1,000 users each), and a pool of expander workers turns each batch into individual sends.** ✅ **Parallel, and a crash loses one batch instead of an unknown position in a million-row loop.**
> - ⭐ **Say it in one line:** _"I'd chunk the fan-out into batch messages so expansion is parallel and restartable — otherwise one host serially enqueueing a million sends is both slow and an unknown-progress failure."_
> 
> ■ **— end of insert · HI write-up resumes below —**

> ⊕ ⭐ **(mine) — two smaller gaps worth a sentence each.**
> 
> - ⚠ **Quiet hours SUPPRESS rather than DEFER.** ▸ **§4.3 records `SUPPRESSED` with a reason — so a promo sent at 11pm to someone with 22:00–08:00 quiet hours is never delivered at all.** ⭐ **Probably not what the product wants.** ▸ **Ask: _"do quiet hours suppress or defer? Deferring means rescheduling to the window's end, which is a different path."_**
> - ⚠ **Redis is now load-bearing for TWO things — token buckets and the dedup cache — and HI only gives a degradation path for the second.** ⭐ **If Redis dies, rate limiting dies with it: send unlimited and risk provider throttling or a ban, or stop and drop the SLA.** ▸ **Fail open with a conservative per-worker local limit, so aggregate stays under the provider ceiling without the shared bucket.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### ▹ Additional dives HI flags

|Topic|The interesting part|
|---|---|
|⭐ **Send-time optimisation**|**pick a per-user send time inside marketing's window.** ⭐ **The pipeline already handles millions of small scheduled sends — _"the interesting part is interacting with an offline ML model that scores those send times."_** ▹ **Expect this if your interviewer has an ML background**|
|⭐ **Frequency capping**|**cap notifications per user per day across all types.** ▸ **_"A good start is next to the preference check at dispatch time, but we need to talk about counters"_**|
|⭐ **Campaign cancellation**|**marketing schedules a blast, legal wants it stopped.** ⚠ **_"How can we check for cancellations without dragging on performance?"_**|
|⭐ **Timezone-aware delivery**|**"9am" means 9am for the USER** ⇒ **the campaign spreads over 24 hours.** ✅ **The scheduling machinery already fits — _"just with two dozen due times instead of one"_**|

---

## 6 · Final Design

⚠ **Layout and arrows are mine; components and field lists are HI's.**

```
Upstream Services  (Order · Auth · Marketing)  ⭐ your customers are other TEAMS
  │  POST /notifications {userId, channel, ⭐⭐ priority, content, scheduledAt}
  │  POST /campaigns     {segmentId, channel, priority, templateId, scheduledAt}
  │  PUT  /users/{userId}/preferences · /devices
  │  ⭐⭐ both POSTs carry an IDEMPOTENCY KEY
  ▼
API Gateway  — ⭐ API-KEY auth per service · rate limits so a runaway        02d
               client can't break authentication
  ▼
Notification Service   ⭐ accept path = ONE write, to the queue
  │  ⭐ derives the stable ID from the idempotency key
  │  ⭐ returns 202 once the queue ACKs  (not 200 — delivery is decoupled)
  │  ⊕ NOT db-then-publish (dual write) and ⭐ NOT outbox —
  │    "accepting a notification is just a single publish and nothing else"
  │
  ├──► Notifications DB (Postgres)                                     02g
  │      notifications: userId · channel · message · status
  │                     ⭐ SENT | FAILED | SUPPRESSED(+reason) | SCHEDULED
  │      campaigns:     campaignId · target · messageTemplate · channel
  │                     scheduledTime · status · users
  │      segments:      segmentId · userId
  │      user:          optOutChannels · quietHoursStart/End · timezone
  │                     email · phoneNumber · ⭐ pushToken (app PUSHES it —
  │                     tokens rotate, so nothing stable to sync)
  │
  ├──► Scheduler Cron  ⭐ scans every minute for due notifications AND campaigns
  │      ⭐ segment read as a SNAPSHOT at fan-out — joiners miss this campaign
  │      ⭐ stamps each send campaignId:userId ⇒ a crash+rerun is idempotent
  │      ⊕ should be a TWO-STAGE fan-out: cron → batch messages →
  │        expander workers, so expansion is parallel and restartable
  │
  └──► ⭐⭐⭐ TWO QUEUES, routed by the declared priority              03c · 03e
         │
         ├── HIGH PRIORITY Queue ──► ⭐⭐ its OWN worker pool
         │                              (idle most of the time — deliberate)
         └── STANDARD Queue ──────► separate worker pool
                │
                │  ⭐⭐⭐ Worker order (the whole of §5.3):
                │   receive → GET sent:{id} (drop if present) → preferences
                │   → draw a token → call provider → write SENT/FAILED
                │   → SET sent:{id} EX 172800 → delete the message
                │  ⚠⚠ CLAIMING up front instead of MARKING at the end
                │     turns at-least-once into AT-MOST-once
                │
                ├──► Redis                                                02a
                │      ⭐⭐ per-tier TOKEN BUCKETS — Twilio 1,000/s split
                │         100 RESERVED high / 900 standard, and standard
                │         can NEVER touch the reserved 100
                │      ⭐⭐ dedup cache: sent:{notificationId}, 48h TTL
                │      ⊕ degradation: §5.3 for dedup; ⚠ none given for the
                │        bucket — fail open on a per-worker local limit
                │
                ├──► DLQ  ⭐ after too many retries, for inspection
                │
                └──► Providers  ⚠⚠⚠ THE CEILING IS HERE, NOT YOUR WORKERS
                       Twilio (SMS) · SMTP (Email) · APNs/FCM (Push)
                       ⭐ ~5,000/sec across channels — no amount of
                         autoscaling exceeds it
                       ⭐⭐ brownout defences: CIRCUIT BREAKER (fail fast
                         past a failure threshold) · BULKHEAD (cap
                         in-flight calls per provider) · PROVIDER ROUTER
                         (primary + backup, and change the PRODUCT —
                         "if SMS is down maybe email is the only option
                         we offer for authentication")
```

---

## 7 · Expected at Each Level
Removed

---

## Quick Recall (pass 3+)

|Use / Question|Notification System answer|
|---|---|
|Calibration|⭐ Evan King · **Jul 2026** (newest in the set; postdates my training) · **"medium"** · ⚠⚠ **NO "Asked at" line — no company data.** ⭐⭐ **TWO patterns: `Multi-step Processes` (`03c`, FIRST in your set) + `Scaling Writes` (`03e`).** ⚠ **No "Planning the Approach" section.** ⭐⭐⭐ **DD1 is largely `05p` re-run — skim it. Spend your time on DD2 (priority isolation) and DD3 (the ordering bug).** ⭐ **ONE careful pass if you've done `05p`**|
|⭐⭐⭐ Design driver|⭐⭐⭐ **Two traffic classes through one pipeline — _"the heart of this problem."_** **HIGH (OTPs, security alerts): low volume, 5-SECOND SLA — _"if you get the code to log in 20 minutes later you probably just assumed the website didn't work."_ STANDARD (promos, digests): huge bursts, _"nobody cares if they land ten minutes late."_** ⇒ ⭐⭐ **which is WHY the API makes callers DECLARE a priority — you can't infer it later.** ⭐⭐⭐ **And the half that makes it different from `05p`: the CEILING IS EXTERNAL. Providers cap you at ~5,000/sec, so isolation means ALLOCATION, not capacity**|
|FRs / NFRs|**send to one user (now or scheduled) · ⭐⭐ campaigns to a SEGMENT · preferences (channel opt-outs + quiet hours).** Below: templates · analytics · in-app feeds · frequency capping — ▹ ⭐ **HI: _"you're not getting much credit (if any) for enumerating 'below the line' requirements"_.** **NFRs: ⭐⭐ at-least-once with best-effort dedup (_"we'd rather send twice accidentally than never at all"_) · ~5,000/sec surges · ⭐⭐ high priority within 5 SECONDS even during a surge.** ⭐ **Worth saying: the NFRs aren't independent — _"best-effort deduplication makes the surges harder to handle"_**|
|📐 Numbers|**10M/day ÷ 86,400 = ~100/sec sustained (_"almost nothing"_) · 1M campaign in 5 min = >3,000/sec from ONE campaign ⇒ ⭐⭐ design for ~5,000/sec ≈ 50×.** ⭐⭐⭐ **THE number: 1M backlog at 5,000/sec clears in ~3 min (fine for a promo) but an OTP behind it waits 200 SECONDS vs a 5s SLA.** ⭐ **Draining 1M in <5s = 200,000/sec = 40× target.** **Twilio 1,000/sec split 100 reserved / 900 standard · p99 1s→30s brownout · dedup TTL 48h · cron every minute**|
|Entities|**Notification** (one message, one user, one channel, + status) **· Campaign** (scheduled send to a group) **· Segment** (named audience; ⭐ membership maintained elsewhere, you READ it at fan-out) **· User.** ⭐⭐ **_"A notification is like an instance of a class"_ — definition-vs-instances, and HI names `05p` (recurring job vs executions) and calendars (event vs occurrences).** ▹ ⚠ **whiteboard list adds `Template`, prose list doesn't, and template authoring is out of scope — use the prose list**|
|API|`POST /notifications {userId, channel, ⭐⭐ priority, content, scheduledAt}` → **200 at first, ⭐ becomes 202 once delivery leaves the request path** · `POST /campaigns {segmentId, channel, priority, templateId, scheduledAt}` → **202 immediately, _"there's no outcome it could report at creation time"_** · `PUT /users/{id}/preferences` and `/devices` — ⭐ **PUT because it's a full replace ⇒ _"an idempotent endpoint for free."_** ⭐⭐ **Separate campaign endpoint because overloading `/notifications` with a `segmentId` means _"one endpoint sometimes creates a notification and sometimes creates a campaign."_** ⭐⭐ **Flag the evolution: _"both of these bodies grow an idempotency key before we're done"_**|
|⭐⭐⭐ Why `userId` in the PATH is right HERE|⚠ **A RED FLAG everywhere else in your set — it inverts because _"our callers aren't end users at all. They are internal services authenticated with API keys, acting on behalf of the users."_** ⭐ **The rule generalises: identity comes from an authenticated PRINCIPAL — a JWT for end users, an API key + delegated subject for a platform API.** ▹ **Platform teams may ask how authorization carries through: _"delegation tokens or service accounts"_**|
|⭐⭐⭐ Router and bookkeeper|⚠⚠ **_"The most common mistake I see on this question is conflating the notification platform with the delivery provider."_** ⭐⭐⭐ **_"Your system is a ROUTER and a BOOKKEEPER. It decides what to send where, and it records what happened."_** **Carriers and device connections belong to APNs, Twilio, the email provider.** ⚠ **_"When a candidate starts designing persistent socket connections to phones, they're solving a different and much harder problem."_**|
|⭐⭐ Push is the odd channel|**Email/SMS addresses SYNC over from the product's user service.** ⭐⭐ **Push tokens ROTATE — _"there's nothing stable for the user service to sync over"_** ⇒ ⭐ **the mobile app PUSHES the token to you on login and on change (`PUT /users/{id}/devices`).** ▸ **Then a push send is just an email send with a token lookup**|
|⭐ Scheduled sends|**write status `SCHEDULED` and stop; a cron scans every minute for due rows and pushes them down the same send path.** ⭐⭐ **Minute granularity is FINE because _"anything that cares about seconds, like an OTP, comes in as a synchronous request and never touches the cron job at all."_** ▹ ⭐ **contrast `05p §5.1`, where 2-second precision forced a two-layer scheduler**|
|⭐⭐ Campaign fan-out + the snapshot|**cron finds a due Campaign → reads segment membership → pushes a send per recipient → marks complete.** ⭐ **Segment read as a SNAPSHOT: _"someone who joins mid-publish misses this campaign and catches the next one."_** ⭐⭐⭐ **HI on why that matters: _"a big thing separating senior candidates from juniors is just noticing issues like this"_**|
|⚠⚠ The 3 problems with one pipeline|**(1) provider call in the request path — slow Twilio blocks callers, and ⭐ _"if our service crashes after writing the row but before calling the provider, that notification is simply gone"_ (2) a big campaign fights everything — _"all million sends might sit before the OTP"_ (3) ⚠ one host making a million provider calls — _"if it dies halfway through we have no idea where it stopped."_** ▸ **These ARE the deep dives**|
|⭐⭐⭐ Suppression is an OUTCOME|⭐ **Opt-out per channel + quiet hours; ⭐⭐ quiet hours apply to STANDARD but never to high priority.** **Checked right before the provider call.** ⭐⭐⭐ **Record `SUPPRESSED` WITH THE REASON, never a silent drop — _"this will come in handy later when we're oncall going 'why the heck did this user not get this notification?!'"_**|
|⚠⚠ DD1 Bad — sync + retries|⚠ **_"Everything else about it is worse than what we started with."_** **Retry loop in PROCESS MEMORY ⇒ a crash or deploy loses everything · connection held open for the whole backoff ⇒ ⭐ _"the auth service starts timing out on logins because our SMS provider is degraded"_ · ⚠⚠⚠ the caller can't tell _"we gave up"_ from _"we never got it"_ ⇒ ⭐⭐ _"at-most-once delivery, the exact opposite of what we promised"_**|
|DD1 Good — PENDING table + dispatcher|**write `PENDING`, respond, a background dispatcher polls and marks SENT/FAILED.** ✅ **a crash loses nothing.** ⭐ **API becomes `202` + `GET /notifications/{id}`.** ⚠ **_"Postgres makes a mediocre queue"_: parallel dispatchers can double-send ⇒ ⭐ claim rows with `SELECT … FOR UPDATE SKIP LOCKED` (▹ complements `05n §5.1`, where the lesson was that `FOR UPDATE` doesn't block INSERTs) · build retries yourself · the table becomes queue AND history · ⚠⚠ latency floor = the poll interval**|
|⭐ DD1 Great — a real queue|**hand it to a durable queue, 202 on the ACK; ⭐⭐ the accept path no longer touches the DB.** **Worker: receive → look up + check preferences → call provider → write SENT/FAILED → ⭐ ONLY THEN delete.** **Crash ⇒ visibility timeout ⇒ retry; backoff; then DLQ.** ⭐ **_"We configure the retry policy, visibility timeout, and dead-letter queue rather than building that machinery ourselves."_** ⚠ **More duplication than before (SQS is at-least-once) · consuming is DESTRUCTIVE — _"we can't rewind this afternoon's traffic"_**|
|⭐⭐ Why NOT outbox, why NOT Kafka|⚠ **write-DB-then-publish is a DUAL WRITE — _"a crash between those two steps leaves a row that no message represents."_** ⭐⭐ **Outbox fixes it, but the rule that rejects it: _"An outbox is good when we need to commit database state AND produce a message together. Accepting a notification is just a single publish and nothing else."_** ▹ ⚠ **contrast `05s §5.3`, where dual writes WERE right.** ⭐⭐ **Kafka's real win: _"reset the offset and reprocess this morning's sends"_ — _"a real advantage, but it's not something our requirements asked for."_** ▹ **3rd log-vs-work-queue data point, and the first time the LOG side gets a genuine win**|
|⭐⭐⭐ DD2 the arithmetic|**9:00:00 marketing queues 1M → providers cap at 5,000/sec → backlog clears in ~3 min, ✅ fine for a promo.** **9:00:05 an OTP lands in the SAME queue, ⚠⚠ a million messages back ⇒ ⭐⭐⭐ waits 200 SECONDS against a 5-second SLA**|
|⚠⚠ DD2 Bad — autoscale|▹ **_"the first answer I get maybe half the time."_** 📐 **1M in <5s needs 200,000/sec = 40× target · servers take _"seconds to minutes"_ · AWS caps burst provisioning (⭐ _"somebody has to keep all those idle servers"_).** ⭐⭐⭐ **But the real reason it can NEVER work: the ceiling is the PROVIDER, not your workers — more workers can't exceed 5,000/sec. Say that and you skip a rung**|
|⭐⭐ DD2 Good — split the queues|**HIGH and STANDARD queues routed by the declared priority; workers drain high first.** ✅ **_"our OTP sits in a small queue that gets served first."_** ⚠⚠ **But — the sharp insight — _"We've solved queue POSITION, but everything downstream of it is still shared"_: ⚠⚠⚠ the PROVIDER (_"if standard traffic is consuming our entire Twilio rate allocation, the high priority SMS is going to get throttled by them even if it sits in a small queue on our side"_) and ⚠⚠ the COMPUTE (a worker _"stuck behind a slow provider call"_ holds up the high-priority queue).** ▸ ⭐ **Splitting one shared layer pushes contention down to the next**|
|⭐⭐⭐ DD2 Great — isolation + budgets|⭐⭐ **_"more isolation (separating queues and worker pools) and more control (provider budgets and token buckets)."_** ⭐⭐⭐ **Shared Redis TOKEN BUCKET refilled each 1-second window: HIGH gets a RESERVED 100 of Twilio's 1,000/sec, STANDARD gets 900 and ⭐⭐ _"can't touch the reserved 100, no matter how far behind it falls."_ Workers draw a token before calling out.** ⭐⭐ **Plus a SEPARATE worker pool for high priority.** ⚠ **Both costs accepted deliberately: ⭐⭐ _"the high priority pool sits underused most of the time, but that's a deliberate choice"_ — paying for idle capacity IS the answer**|
|⭐⭐ DD2 — provider brownout|⚠ **p99 goes 1s → 30s; workers don't know and _"each stuck call pins a worker for 30 seconds."_** ⭐⭐ **Honest goal: _"we cannot deliver everything on time, so the job is to keep high priority messages moving and let everything else wait it out."_** ⭐⭐ **CIRCUIT BREAKER — track failure/timeout rate per provider; past a threshold it OPENS so calls fail fast instead of eating a 30s timeout, shedding non-essential load.** ⭐⭐ **BULKHEAD — cap in-flight calls per provider like a semaphore, so you're _"not spinning all our capacity on a service that's mostly down."_** ⭐ **PROVIDER ROUTER — primary + backup, and change the PRODUCT: _"if SMS is down maybe email is the only option we offer for authentication"_**|
|⭐⭐ DD3 — the 3 duplicate sources|**(1) worker calls Twilio then dies before deleting ⇒ visibility timeout ⇒ resend (2) a caller POSTs, times out, POSTs again (3) your cron crashes mid-fan-out and republishes.** ⭐ **_"True exactly-once delivery is impossible to achieve, but we can go a long way toward keeping duplicates rare"_**|
|⭐⭐⭐ DD3 — chained idempotency|⭐⭐ **First you need a STABLE ID — _"if a retry were to produce a different ID than the original, there is no way anything downstream can tell the two apart."_** **Callers pass an idempotency key; campaign messages are stamped `campaignId:userId` so a crashed-and-rerun fan-out _"produces exactly the IDs the first pass produced."_** ⭐⭐⭐ **And the chained bit most miss: that only works if the CAMPAIGN id is stable, which is why `POST /campaigns` takes an idempotency key too — _"without one, a retried campaign creation gets a fresh campaignId, every message in it is stamped differently, and every recipient gets the promo twice"_**|
|⚠⚠⚠ DD3 — THE ordering bug|**Claim-first with `SET NX`: Worker A claims `n:otp-8412` → gets killed by a deploy before sending → message redelivered → Worker B's `SET NX` returns `nil` → B assumes it's handled → every redelivery drops it.** ⭐⭐⭐ **_"The lock stays around even after the worker who took it dies… We just turned at-least-once into at-most-once."_** ⭐⭐⭐ **THE GENERALISATION: mark work done AFTER the irreversible side effect, never before — a claim written first and never released is indistinguishable from a completed job.** ▹ **HI's Staff+ bar asks this by name; the full 7-step trace is in §5.3**|
|⭐⭐⭐ DD3 Great — flip the order|⭐⭐⭐ **_"check whether we've already sent it before dispatching, and write the dedup marker only AFTER the provider has taken it."_** ⭐ **Redis in front, DB as source of truth, because _"checking the database before each notification could slow us down during surges."_** **`GET sent:{id}` before dispatch → present means duplicate, drop · `SET sent:{id} 1 EX 172800` only after the provider accepts (⭐ 48h covers DLQ replays).** ⚠ **A narrow window survives: provider accepts → worker dies before writing the row → redelivery sends again.** ⭐⭐ **_"We accept a rare duplicate so that a drop is impossible"_ — that sentence IS the semantics choice**|
|⭐⭐⭐ DD3 — degradation (Staff+ asks)|**Redis down ⇒ fall through to the outcome table, ⭐ _"looking for a SUCCESSFUL send rather than any row at all"_ (▸ a FAILED row must not count as sent) — slower but correct.** **Table also down ⇒ ⭐⭐ workers SEND ANYWAY rather than hold, and ⭐ track how many sends skipped the check _"so an alert fires when that rate climbs."_** ▸ ⭐⭐ **Fail TOWARD the guarantee you promised: at-least-once means when in doubt, send**|
|⭐⭐⭐ DD3 — do this on the whiteboard|⭐⭐⭐ **_"Name your delivery semantics explicitly. Exactly-once stops at the provider boundary, so the honest design is at-least-once with deduplication at each point duplicates can enter. You should be able to point at each of those points on your diagram."_** ▸ ⭐ **The three points: the caller's retry (idempotency key) · your cron re-fanning (`campaignId:userId`) · the queue's redelivery (the `sent:` check)**|
|⊕⚠⚠ Fan-out is still one host|⚠ **§4.2's problem #3 was _"a single host is making a million provider calls."_ DD1 fixed the PROVIDER-CALL half (workers); DD3 made a restart SAFE (`campaignId:userId`). ⚠⚠ Neither fixed the FAN-OUT — one cron host still loops over a million users enqueueing.** ⚠⚠ **And §5.2 opens with _"we can add all million notifications to the queue almost immediately"_, which a serial loop can't do — at 1,000 enqueues/sec that's ~16 minutes.** ⭐⭐ **Fix: TWO-STAGE fan-out — cron writes one message per BATCH (say 1,000 recipients), expander workers turn each batch into sends. Parallel, and a crash loses one batch instead of an unknown position**|
|⊕⭐ Two smaller gaps|⚠ **Quiet hours SUPPRESS rather than DEFER — a promo at 11pm to a 22:00–08:00 user is never delivered.** ⭐ **Ask: _"do quiet hours suppress or defer? Deferring means rescheduling to the window's end, which is a different path."_** ⚠ **Redis is load-bearing for TWO things (token buckets + dedup) and HI gives a degradation path only for dedup.** ⭐ **If Redis dies rate limiting dies with it ⇒ fail open with a conservative per-worker local limit so aggregate stays under the provider ceiling**|
|▹ Extra dives HI flags|⭐ **send-time optimisation (per-user time inside marketing's window; _"the interesting part is interacting with an offline ML model"_ — expect it from an ML interviewer) · frequency capping (next to the preference check, _"but we need to talk about counters"_) · campaign cancellation (_"how can we check for cancellations without dragging on performance?"_) · timezone-aware delivery (9am per USER ⇒ the machinery fits, _"just with two dozen due times instead of one"_)**|
|Levels (short)|**E4:** API + data model with ⭐ **priority on both endpoints**; working HLD; ⭐ **see that the sync call DROPS notifications, reach the Good durable rung with prompting**; ▹ isolation + dedup ordering not expected unaided · **E5:** ⭐ **drive durable delivery AND priority isolation _"without me steering"_**, think ahead; ▹ per-tier budgets and dedup ordering _"probably won't"_ come unaided · **Staff+:** ⭐⭐ **put NUMBERS on it unprompted**; ⭐⭐⭐ **know _"the ceiling is the providers rather than our own workers"_**; judgment on 3 named failure modes (dedup store down · when provider failover is worth it — high tier only · ⭐⭐⭐ why claiming before the provider call inverts the guarantee); ▹ _"teach me something, usually an operational constraint that never shows up on a diagram"_|

---

> 🔗 **HI source:** https://www.hellointerview.com/learn/system-design/problem-breakdowns/notification-system