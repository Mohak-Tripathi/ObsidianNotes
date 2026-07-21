# Multi-Step Processes

> Hello Interview · **Patterns** · File `03c`. Overview → `03 §7`. Streams/event-sourcing → `02 §7`, `02a §6`; queues → `02 §6`; Pub/Sub → `02a §7`; contention boundary → `03b`. **Calibration:** ⭐⭐⭐ **High — fintech + AI relevant.** Payment orchestration (auth → capture → settle), refunds, order fulfillment, KYC onboarding all live here. ⭐ **AI angle:** agent pipelines are long chains of exactly these flaky, stateful steps — a natural wedge for your background. Depth scales with seniority: mid = spot it + name an engine; **SDE2/senior = defend the choice, walk failure + compensation, field the deep dives.** ▸ **The governing idea:** a multi-step process coordinates **many flaky services (and humans) over a long time** and must **survive crashes, retries, and waits.** Every rung below is you **hand-rolling more of what a workflow engine gives for free** — durable state, retries, compensation, audit. The recurring survival tool is **idempotency.**

---

## The Problem

▸ **CRUX** — clean systems do one read/write; real apps **coordinate dozens of flaky services** to do the user's bidding, quickly and reliably. That's startlingly hard. _(Jimmy Bogard's "Six Little Lines of Fail" — a simple sequence becomes surprisingly hard in a distributed system.)_

▸ **Running example — e-commerce order fulfillment:** charge payment → reserve inventory → create shipping label → **wait for a warehouse human to pick** → send confirmation email.

- Each step calls a different service or waits on a human; **any can fail or time out.**
- Some call **external systems** (payment gateway) and wait for them.
- Your server may **crash or be redeployed** mid-flow.
- You may want to **reorder / change** steps later.

⚠ **The structural sin:** patching each service with failure/retry/wait logic **interweaves system-level concerns (crashes, retries) with business-level concerns (what if the item's gone?).** That tangle is what makes these systems miserable to operate — which is exactly why interviewers probe it (it tests _experience_, not just knowledge).

### Where it shows up (HI breakdowns)

- Uber (human-in-the-loop: driver must accept) · Payment System.
- ⭐ **Fintech:** payments/e-commerce — _never_ leave a user charged for a product they didn't get.

### The three solution families (preview)

▸ The article names **three** answers to this problem — and they show up in interviews **whenever there's a lot of state + a lot of failure handling** (⭐ and even harder in **AI system design**, since agent pipelines are long chains of exactly these flaky, stateful steps). They aren't rivals so much as **points on the same escalation path** below:

- **Event-driven sagas** — no central brain; steps are coordinated by **events**, each step carrying a **compensating undo**. The flow _emerges_ from workers reacting to events. → **Rungs 2–3.**
- **Durable execution** — write the flow as **ordinary code**; the engine makes it crash-proof by **replaying** it from a recorded history and resuming where it left off (**Temporal**). → **Rung 4a.**
- **Workflow systems (managed)** — describe the flow **declaratively** as a state machine / DAG and let a managed engine run it (**AWS Step Functions**). → **Rung 4b.**
- ▸ **The through-line:** all three give you the same thing — **durable state + retries + compensation + an audit trail** — differing only in _who holds the flow_ (emergent events vs. explicit code vs. declarative definition).

---

## The escalation ladder — each rung hand-rolls what the next gives free

> ▸ **Bird's-eye view — read this as a ladder, not a ranking.** Each rung **solves the previous rung's pain but adds cost/complexity.** The later rung is **not automatically "the answer"** — you climb **only as far as your state + failure-handling actually demand**, and the **simplest rung that fits wins.** Rung 4 (a full workflow engine) isn't "best"; it's what you reach for when the flow is genuinely hairy. In an interview, **start low and justify each climb** — that progression is the signal of maturity.

### Rung 1 — Single-server primitives

▸ One server walks the steps top-to-bottom, then responds.

```javascript
await chargePayment(order);
await reserveInventory(order);
// 💥 server crashes here
await createShippingLabel(order);
await sendConfirmationEmail(order);
```

⚠ **Two problems the moment you need reliability:**

- **Crashes** — server dies after charging, before reserving → on restart it has **no memory** of where it was.
- **Callback routing** — the payment gateway answers **later, via webhook** (an HTTP call back to us). Behind a load balancer that callback can land on a **different host** than the one that started the order → that host has **no idea which in-flight order** it belongs to.

▸ **The patch:**

- Persist order state to a **DB after each step** → no single host has to remember.
- Route callbacks through a **Pub/Sub layer** (`02a §7`) → any free server can load the order and continue.

⚠ **But look at what you've now hand-built:**

- A manual **state machine** with DB checkpoints after each step.
- A **poller + locking scheme + retry logic** to notice stalled orders and claim them without two servers grabbing the same one.
- And you **still haven't solved compensation** — undoing committed steps (refund on inventory-fail, release inventory on ship-fail).
- ▸ Net result: state + error + compensation logic **scattered across your servers** → a structural mess.

▸ **Why climb to Rung 2:** we got a working happy-path and even patched crash/scale survival (DB state + Pub/Sub). But **two committed steps can't be undone** — there's no compensation — and every bit of state/retry/undo logic is **hand-rolled and scattered.** We need a _disciplined_ way to unwind committed steps → the **Saga** pattern names exactly that.

### Rung 2 — The Saga pattern _(the core concept)_

▸ **CRUX** — a saga is a **sequence of local steps, each with a matching compensating action that undoes it.** Run steps one at a time; if a later one fails, **walk backwards firing compensations** to unwind what already happened.

- Our order: shipping falls through → **release inventory + refund the charge.**

⚠ **Why not one big distributed transaction / two-phase commit (2PC)?**

- **Nobody can hold a lock that long** — 2PC keeps every participant locked while the slowest decides; a stalled coordinator stalls everyone.
- **External systems (payment gateway) don't speak your transaction protocol.** You can't get atomicity across services you don't control.
- ▸ **Sagas accept this:** instead of "all steps happen together or none," they guarantee **whatever did happen can be undone.**

⚠ **The costs of that trade:**

- **A brief inconsistency window** — right after the charge the customer is out money for an unshipped order → hold it in a **`pending`** state until it ships.
- **Compensations are as fragile as forward steps** — a refund can fail too → they need **their own retries + idempotency**, plus a **human escape hatch** for the ones that still won't go.

#### ⚠ Confusion resolved — 2PC vs Saga vs distributed lock (and "isn't 2PC just distributed locking?")

> **My doubt:** _"Why does 2PC feel like it's done by a distributed lock? For a financial transaction you lock two resources (sorted by ID so no deadlock), then do a two-phase commit… and is industry practice saga or 2PC?"_

▸ **First — 2PC is NOT a kind of saga. They're opposite answers to the same question** ("make a multi-service operation all-succeed-or-all-fail"):

||Two-Phase Commit (2PC)|Saga|
|---|---|---|
|Strategy|**prevent** partial failure — lock all, commit together|**allow** partial failure, then **undo** it|
|Atomicity|**real** (all commit or all abort)|**none** — each step commits alone|
|Locks|**long** — held until the slowest is ready|**short** — each step locks only itself|
|Inconsistency window|none|yes (the **`pending`** state)|
|Across systems you don't control|**No** (all must speak the protocol)|**Yes** (compensation is just "call refund")|

- ▸ So 2PC is the thing a saga is the **alternative to**, not a flavor of it. _(This block's "why not 2PC?" is the article rejecting 2PC and choosing saga.)_

▸ **Why 2PC _feels_ like distributed locking — because it IS built on locks. Your instinct is right:**

- **Distributed lock = the primitive** ("freeze this resource").
- **2PC = a protocol that _uses_ locks** across multiple participants, adding a **coordinator** + a **two-round handshake** (prepare → commit).
- ▸ So it's not "2PC vs distributed lock" — **2PC is one recipe you build _with_ locks.** Lock = ingredient; 2PC = the ceremony around it.

⚠ **The distinction your bank example hides — where do the two accounts live?**

- **Same database** → "sort by ID, lock both, write both, commit" is **one ordinary local transaction** (`03b` pessimistic locking) — **NOT 2PC.** The DB gives atomicity for free. **Prefer this whenever possible.**
- **Different DBs / services** (account A on shard 1, B on shard 3) → no single DB can commit both → **now** you need real **2PC** (coordinator: prepare → all ready? → commit). This is the expensive, fragile one.
- ▸ So the "lock two and transfer" you remembered is usually the **single-DB** version (cheap, correct, not 2PC). 2PC only enters when resources sit in **separate systems.**

▸ **Industry practice — your read is correct ✅:**

- **Money in one DB** → **local transaction + row locks / OCC** (`03b`). Not 2PC, not saga. Preferred.
- **Short, controlled, cross-DB, all speak the protocol** → **2PC possible** but avoided where it can be (cross-system locks + a stalled coordinator freezes everyone).
- **Long-running or spanning systems you don't control** (payment gateway, warehouse, email) → **Saga.**
- ▸ **Refinement:** real payment systems lean **saga for the cross-service parts** (auth → capture → settle across gateways) precisely because those steps are long and span systems you don't control; **2PC is rare**, seen in tightly-controlled internal setups.

▸ **What you got exactly right:** saga is a **concept** · its two variations are **orchestration** and **choreography** · **event-driven choreography = the choreography flavor** · orchestration = central coordinator (Temporal / Step Functions, Rung 4). ✅

▸ **One-line hold:** _distributed lock = primitive · 2PC = a locking protocol across systems (same-DB transfers aren't 2PC, just local row locks) · saga = the escape hatch when steps are long or span systems you don't control — which is why real payments lean saga._

▸ **Two ways to coordinate a saga:**

- **Choreography** — **no coordinator.** Each worker subscribes to events it cares about, does its piece, emits new events. The flow **emerges** from reactions (dancers who each know their steps). Best for **independent services** (separate teams) and **mid-complexity** flows.
- **Orchestration** — a **single coordinator owns the flow** and tells workers what to do. The whole sequence lives in **one place** → best for **very complex** flows needing central control + visibility.
- ⚠ **Either way, the coordination must survive crashes** — if the saga-runner dies after charging but before reserving, it must come back and **know exactly where it left off.** That durable bookkeeping (state that outlives crashes + retries + compensation) is **the hard part**, and the part you'd rather not build by hand.

▸ **Why climb to Rung 3:** the Saga gives us the _concept_ — steps + compensating undos — but it's **just a concept.** _Something_ still has to coordinate it, and that coordination must **survive crashes** — the durable bookkeeping is still unbuilt. The first principled way to get that (without a central brain) is to **store the events and let workers react** → event-driven choreography.

### Rung 3 — Event-driven choreography

▸ **CRUX — the principled evolution of Rung 1.** Back in Rung 1 we patched things by storing the **current state** (a DB checkpoint after each step). Rung 3 flips that: **stop storing the current state, and instead store the _stream of events_ that got you there** — then let workers **react** to those events to drive the process forward.

- ▸ **Why "more principled":** current-state checkpoints throw away _how_ you got there; an event log keeps the full causal history **and** doubles as the thing that drives the next step (see below). One artifact replaces the hand-rolled state machine + poller from Rung 1.
- **Storage:** a **durable log** — **Kafka** (popular), sometimes **Redis Streams** _(→ `02 §7`, `02a §6`)_.
- ▹ **Event sourcing** is a close cousin — it treats the log as the **source of truth** and derives state from it; here we mainly use the log to **coordinate work.** They travel together but needn't.
- ▹ **Deep read on durable logs** (Jay Kreps' classic, referenced by HI): https://www.linkedin.com/blog/engineering/distributed-systems/log-what-every-software-engineer-should-know-about-real-time-datas-unifying

▸ **How it flows:** the event store does double duty — holds the **full history** _and_ **drives next steps.**

- Payment worker sees `OrderPlaced` → calls payment service → on callback emits `PaymentCharged` / `PaymentFailed`.
- Inventory worker sees `PaymentCharged` → emits `InventoryReserved` / `InventoryFailed`.
- **Compensation flows backwards the same way:** payment worker also subscribes to `InventoryFailed` → issues refund → emits `PaymentRefunded`.
- The **API service becomes a thin wrapper** — it just emits `OrderPlaced`; services stop exposing APIs and become **workers that consume events.**

**Advantages**

- **Fault tolerance** — workers consume as a **consumer group**, committing their log position **only after** an event is fully processed. Worker dies → partitions reassigned → next worker resumes from last committed position.
- **Scalability** — add workers up to the topic's **partition count**.
- **Observability** — the log **is a complete audit trail.**
- **Flexibility** — appending a **new reaction** is easy (just a new worker on existing events).

**Disadvantages**

- ⚠ Some events get **processed twice** on handoff → **workers must be idempotent** _(the recurring theme)_.
- ⚠ **Inserting a step into the middle is hard** — the neighbors' **event contracts** must change.
- ⚠ **You're building real infra** — event store, queues, worker orchestration → its own distributed-systems project.
- ⚠ **The implicit flow is the ceiling** — **no single place knows the whole sequence**, so making sense of the log at scale needs custom tooling ("why did no worker pick up this `PaymentFailed`?").

▸ **Why climb to Rung 4:** Rung 3 bought us real wins — a durable log gives **fault tolerance, scalability, and an audit trail**, and a genuine saga runs via events. But the **flow is implicit** — no single place knows the whole sequence, so changing it means editing many workers' **event contracts**, and operating it needs custom tooling. We want the **whole flow in one explicit place + a durable coordinator, without hand-rolling the infra** → workflow orchestration. _(Good news: choreography is a fine resting place for **mid-complexity** — only climb when the flow is genuinely hairy.)_

### Rung 4 — Workflow orchestration ⭐ (the destination)

▸ **CRUX** — describe a **reliable, long-running workflow** that survives crashes and **continues where it left off**, _without hand-rolling the infra._ You get the event-driven benefits **plus a durable saga coordinator** for free. Two camps differ only in **how the workflow is described.**

#### 4a. Durable Execution Engines — **Temporal** (code-defined)

▸ Write the workflow as a **function**; the engine orchestrates it. The code looks almost identical to Rung-1 single-server orchestration — **the difference is how it's run.**

```javascript
const paymentResult = await processPayment(input);
if (paymentResult.success) {
  const inv = await reserveInventory(input);
  if (inv.success) { await shipOrder(input); await sendConfirmationEmail(input); return {success:true}; }
  else { await refundPayment(input); return {success:false, error:"inventory"}; }  // compensation
} else return {success:false, error:"payment"};
```

▸ **Two primitives + two obligations:**

- **Workflow** = the **recipe** (ordered steps + decisions). ⚠ **Must be deterministic** — same inputs + history → same decisions. Anything nondeterministic (network call, DB read, `random()`, timestamps) belongs in an Activity. (Temporal's SDK sandboxes the runtime to enforce this.)
- **Activity** = one **step that touches the outside world** (call a service, charge a card, send email). ⚠ **Must be idempotent** — Temporal won't retry an Activity that _reported_ success, but a crash can leave it **unsure** whether one finished → it retries in that gray zone → idempotency makes the retry harmless.

▸ **Why determinism? Because recovery = replay.**

- Every Activity result is recorded to a **history DB.**
- Crash → a new worker **re-executes the Workflow function from the top.** Each time replay hits an Activity that already ran, **history hands back the recorded result** instead of re-running it.
- Deterministic code + no Activity re-fires → replay is **side-effect-free** and lands **exactly where it left off.**
- **Crash walkthrough:** `processPayment` runs (→ history) · `reserveInventory` runs (→ history) · **server dies** · new worker replays from top → payment & inventory return from history (**no re-charge, no re-reserve**) · replay reaches `shipOrder`, finds nothing in history → **continues live.** Customer charged once, inventory reserved once, business code never knew a crash happened.

▸ **Deployment (mirrors choreography infra):**

- **Temporal Server** — the **bookkeeper**: hands out tasks, tracks timeouts, records progress. **Never runs your code.**
- **History DB** — append-only log of decisions + Activity results.
- **Worker pools** — **your** processes: **workflow workers** run the Workflow fn to decide the next step; **activity workers** execute Activities.
- ▹ **Division of labor (trips people up):** at `await processPayment()`, the **workflow worker doesn't call the payment service** — it tells the Server "schedule this Activity"; the Server queues it for an **activity worker**, which makes the real call and reports back; the workflow worker then resumes from the recorded history. **The flow lives explicitly in one piece of code** (vs implicitly in who-consumes-which-topic).

▸ **Signals — waiting for external events cheaply:** a workflow can **wait for a signal** (human picks the order, a 30-day signature) **without holding a thread or CPU.** The engine **persists its state and frees the worker**, then **rehydrates** on signal arrival. That's how a workflow "waits 30 days" for free.

#### ⚠ Confusion resolved — execution / data flow: event choreography vs Temporal vs Step Functions (one e-commerce order through all three)

> **My doubt:** _"how basically there is an event source or Kafka kind of a thing in event-driven… how this temporal is working, whether there is a centralized server which is doing orchestration, and how the worker… Worker is executing only activity, right?… take the e-commerce example only and try to explain how things are different… Event sourcing and this temporal one… include 4B as well."_

You're asking exactly the right question — the _execution/data-flow_ difference between the three, which is where people actually get confused. Let me run **one e-commerce order** (charge payment → reserve inventory → ship → email) through all three, focusing on **who stores the flow, who decides the next step, and what the worker does.**

First, the one-line mental model for each:

||Where the **flow** lives|Who decides **next step**|What a **worker** does|
|---|---|---|---|
|**Rung 3 — event choreography**|nowhere central — **implicit** in event subscriptions|**no one** — each worker reacts to an event|react to an event, do work, **emit the next event**|
|**4a — Temporal (code)**|**your workflow function** (explicit code)|the **Temporal Server** replaying your fn|run **one Activity**, report result back|
|**4b — Step Functions (declarative)**|a **JSON state machine**|the **AWS-managed engine** reading the JSON|run **one Lambda/task**, report result back|

Now the same order through each.

---

**Rung 3 — Event-driven choreography (what you already learned)**

There's a **Kafka log** in the middle. No coordinator. Each worker independently subscribes to an event, does its job, and **emits the next event.** The sequence isn't written anywhere — it _emerges_ from who-subscribes-to-what.

```
API emits            → OrderPlaced
Payment worker  hears OrderPlaced   → charges card → emits PaymentCharged
Inventory worker hears PaymentCharged → reserves   → emits InventoryReserved
Shipping worker hears InventoryReserved → ships     → emits OrderShipped
Email worker    hears OrderShipped   → sends email  → emits OrderCompleted
```

**Where is "the next step" written?** Nowhere in one place. It's encoded in the fact that _the inventory worker happens to subscribe to `PaymentCharged`._ To know the whole flow you have to trace every worker's subscriptions. **That's the pain** — the flow is _implicit_.

**Compensation** is just more subscriptions: the payment worker _also_ subscribes to `InventoryFailed`, and on hearing it, refunds and emits `PaymentRefunded`.

Kafka's job: **store + transport events.** It does **zero** logic. The "brain" is smeared across all the workers.

---

**4a — Temporal (code-defined orchestration)**

Now there **is** a central brain, and — this is the key correction to your mental model — **the flow lives in a normal function you write**, not "inside the Temporal server." Let me be precise about who holds what, because this is your main confusion:

```
myWorkflow() {                          ← THIS function is the flow. You write it.
  await processPayment(order)           ← each await = "schedule an Activity"
  await reserveInventory(order)
  await shipOrder(order)
  await sendConfirmationEmail(order)
}
```

Three parties:

- **Temporal Server** — the **bookkeeper**. It stores the **history** (what's happened) and hands out tasks. ⚠ **It does NOT contain your workflow code and never runs it.** It just tracks progress and queues tasks.
- **Workflow worker** — a process **you run** that **hosts your `myWorkflow` function.** It executes the _deciding_ logic: "given the history so far, what's the next Activity?"
- **Activity worker** — a process **you run** that executes the actual side-effecting steps (`processPayment`, `shipOrder`).

**The data flow for ONE step** (this is the part that trips everyone, including you):

1. Workflow worker runs `myWorkflow` and reaches `await processPayment(order)`.
2. It does **not** call the payment service. It tells the **Server**: "schedule a `processPayment` Activity."
3. Server writes "processPayment scheduled" to history and **queues the task.**
4. An **Activity worker** picks up the task, **actually calls the payment gateway**, gets the result, **reports it back to the Server.**
5. Server appends "processPayment → success" to history, and wakes the workflow worker.
6. Workflow worker **resumes `myWorkflow`**, now past the first `await`, hits `await reserveInventory(...)` → back to step 2 for the next Activity.

So: **workflow worker = decides the next step (runs your flow code). Activity worker = does the step (touches the outside world). Server = records everything + routes tasks.** Your instinct "worker only executes activity" is _half_ right — there are **two kinds** of worker, and only the _activity_ worker executes activities; the _workflow_ worker runs the flow.

**Where does "next step" live?** In your `myWorkflow` code — **explicitly, in one place.** That's the whole upgrade over Rung 3. To know the flow you read one function, not fifty subscriptions.

**How does a crash recover?** The Server has the history. A new workflow worker **re-runs `myWorkflow` from the top**, but every `await` whose result is already in history **returns instantly from history instead of re-calling** — so it fast-forwards to exactly where it died and continues live. (That's why workflow code must be deterministic and activities idempotent — the replay deep-dive.)

---

**4b — AWS Step Functions (declarative orchestration)** _(preview, full treatment next)_

**Same three-party shape as Temporal** — central engine + tasks + a recorded position — but two differences:

1. **The flow is written as JSON, not code.** Instead of a `myWorkflow` function, you describe a **state machine**: "state `ProcessPayment` → on success go to `ReserveInventory` → on failure go to `RefundPayment`."
2. **AWS runs the engine for you** (managed/serverless — no cluster to operate), and the **steps are usually Lambda functions** instead of your activity workers.

```json
"ProcessPayment":   { "Next": "ReserveInventory", "Catch": [→ "RefundPayment"] },
"ReserveInventory": { "Next": "ShipOrder",        "Catch": [→ "RefundPayment"] },
"ShipOrder":        { "Next": "SendEmail" },
...
```

**Where does "next step" live?** In the **JSON `"Next"` fields** — explicit, one place, same as Temporal. The engine reads the JSON, sees you're in `ProcessPayment`, calls that Lambda, gets the result, moves to the state named in `"Next"`, records the new position server-side.

**Recovery difference:** Temporal recovers by **replaying your code** against history; Step Functions just **tracks the state-machine position server-side** and continues from it — no replay, because there's no code to replay, just a position in a diagram.

---

**The one crisp contrast that resolves your confusion:**

- **Event choreography (3):** the flow is **implicit** — "next step" = whatever worker subscribed to the last event. Kafka only stores/moves events; the workers _are_ the brain, scattered.
- **Temporal (4a):** the flow is **explicit code you write**; a workflow worker runs that code to decide next, activity workers do the steps, the server records history and recovers by **replaying your code**.
- **Step Functions (4b):** the flow is **explicit JSON**; AWS's managed engine reads it to decide next, Lambdas do the steps, and recovery is just **resuming a saved position** (no replay).

And the umbrella you named is right: **all three are sagas.** Choreography = the no-coordinator saga (3). Temporal and Step Functions = orchestration sagas (4a/4b) — same "one brain owns the flow" idea, one expressed as **code**, the other as **JSON**.

**One-line hold:** _choreography = the flow emerges from event subscriptions (Kafka just carries events); orchestration = one place owns the flow and a worker only executes single steps — Temporal writes that flow as replayable code, Step Functions as a resumable JSON state machine._

#### 4b. Managed Workflow Systems — **AWS Step Functions** (declarative)

▸ Describe the workflow as a **state machine / DAG** in JSON/YAML/DSL; the engine runs it. Same job under the covers (orchestrate, call activities, record progress, resume on failure).

- ✅ **Visualizes as a diagram** → nicer UI.
- ⚠ **Cost = expressiveness** — you bend your logic into the declarative model; complex logic gets awkward.
- ▹ Don't harp on "ugly JSON" — **CDK generates it from real code**, and at Amazon that complaint reads as an AWS-knowledge gap.

#### ⚠ Confusion resolved — what "a state machine in JSON" actually means (Step Functions)

> **My doubt:** _"What do you mean when you say state machines in JSON regarding AWS Step Functions?"_

▸ A **state machine** is just a formal way of saying: **a set of named states + rules for which state you move to next.** At any moment you're in exactly **one** state; each state says "when I finish, go to state X (on success) or state Y (on failure)."

▸ **"In JSON"** means you **don't write code** — you write that state list as a **JSON document**, and AWS's engine reads it and walks it for you. Our order:

```json
{
  "StartAt": "ProcessPayment",
  "States": {
    "ProcessPayment":   { "Type": "Task", "Next": "ReserveInventory",
                          "Catch": [{ "Next": "RefundPayment" }] },
    "ReserveInventory": { "Type": "Task", "Next": "ShipOrder",
                          "Catch": [{ "Next": "RefundPayment" }] },
    "ShipOrder":        { "Type": "Task", "Next": "SendEmail" },
    "SendEmail":        { "Type": "Task", "End": true },
    "RefundPayment":    { "Type": "Task", "End": true }
  }
}
```

▸ **Read it plainly:**

- Each **key is a state** (`ProcessPayment`, `ShipOrder`…).
- `"Type": "Task"` = this state **runs something** (a Lambda).
- `"Next"` = on success, **go here**.
- `"Catch"` = on failure, **jump here instead** — that's your **compensation branch**.
- `"End": true` = terminal state.

▸ **So the entire flow is DATA, not code** — a diagram written as JSON. That's the contrast with Temporal (flow is a real function with `if`/`await`). Same job (ordered steps + branching + failure routing), expressed as a **declarative document** instead of **imperative code**. And because it's just states + transitions, AWS can render it as a **visual diagram** — the main selling point.

#### ⚠ Confusion resolved — the recovery difference (replay vs bookmark) & "durable execution"

> **My doubt:** _"Temporal recovers by replaying your code against history; Step Functions just tracks the state-machine position server-side and continues from it — no replay. Explain this… both provide durable execution so state persists across failures, restarts, and even code deployments…"_

▸ **"Durable execution"** = the workflow's progress is saved somewhere **permanent**, so a crash / restart / redeploy doesn't lose it. Both engines give this.

- ⚠ **"even code deployments"** is the strong part: you can ship new code while a workflow is **mid-flight** and it survives (that's the versioning / `patched()` deep-dive below).

▸ **The recovery mechanics differ — this is the core distinction:**

- **Temporal → replay your code.** On crash, a new worker **re-runs `myWorkflow` from the top.** It doesn't re-do the real work — each `await` whose result is already in **history** returns that recorded result **instantly**, so it fast-forwards through completed steps and resumes live at the first unfinished one. State is **reconstructed by running the code again** against saved results. _(This is why workflow code must be **deterministic** — replay must make the same decisions.)_
- **Step Functions → resume a saved position.** There's **no code to replay** — the flow is a JSON diagram. AWS records _"currently in state `ShipOrder`"_ server-side; on recovery it reads that pointer and **continues from that state.** No re-execution.

▸ **The analogy that locks it in:**

- **Temporal** recovers like **re-reading a recipe from step 1 but instantly skipping every step already checked off**, until it reaches the first unchecked one.
- **Step Functions** recovers like a **bookmark** — it just remembers "you were on page 4" and opens straight there.
- ▸ Same outcome (resume where you died), different machinery: **replay code vs. read a saved position.**

▸ **The payoff line:** either way your code/JSON _looks_ like the naive Rung-1 sequential version (charge → reserve → ship → email), but you now get **fault-tolerance, scalability, and observability for free** — the exact things Rungs 1–3 made you hand-build.

#### Engine cheat-sheet

|Engine|Style|Notes|
|---|---|---|
|**Temporal**|code (durable execution)|most powerful OSS; wait days/months, full history; ⚠ **you operate it** (or Temporal Cloud)|
|**AWS Step Functions**|declarative state machine|managed/serverless; ⚠ **1-year** exec cap, **256KB** payload between states|
|Azure Durable Functions · Google Cloud Workflows|mixed|cloud-native, easier to run, less flexible|
|Apache Airflow|Python DAGs|⭐ **scheduled batch / ETL**, _not_ event-driven long-running|
|DBOS · Hatchet · Netflix Conductor|varied|name-drop if asked|

- ▸ **For interviews the pick matters less than you'd think.** What gets you marked down isn't the choice — it's **not knowing your chosen engine's recovery model + limits.** Pick one, know how it recovers and where it caps.

▸ **Top of the ladder — where we landed:** Rung 4 hands you **everything the lower rungs made you build by hand** — durable state, retries, compensation, audit trail, _and_ an explicit flow — as a managed capability. This is the **destination**, but not a default: it's **another distributed system to operate**, so climb here only when the flow's state + failure-handling genuinely justify the cost. _(The rest of the file is how to defend that choice — when to use it, when not, and the deep dives.)_

---

## When to use in interviews

▸ **Trigger:** a **state machine / stateful process / flow-chart of steps** in the design. Listen for **"if step X fails we must undo step Y"** or **"all steps complete or none."** That's the signal.

- **Payment systems / e-commerce** — lots of state, must handle failure gracefully.
- **Human-in-the-loop** — Uber driver accepting a ride; document signing.

⚠ **When NOT to (don't overcomplicate):**

- **Simple async single-step** (resize an image, send an email) → just a **queue** _(→ `02 §6`)_.
- **Synchronous / latency-sensitive** (client waits) → not a workflow.
- **High-frequency, low-value** — every Activity costs engine round-trips + history writes → millions of trivial ops aren't worth it.
- ▸ **Show maturity: start simple**, introduce a workflow only when you name the specific problem it solves — partial-failure handling, long-running waits, complex orchestration, or audit requirements.

---

## Common Deep Dives

▸ **"Process running the saga crashes partway — what does it know on restart?"**

- If progress was **in memory** → nothing → can't tell whether to push forward, retry, or compensate.
- **Fix = durable progress:** record completed steps to a **crash-surviving store**; on restart read it and resume forward or fire compensations. Recovering coordinators may re-run an unsure step → steps + compensations must be **idempotent.**
- ▸ This is **exactly what a workflow engine gives free** — crash-safe checkpointing + resume on a new worker.

▸ **"How do you update a workflow with 10,000 in-flight executions?"** (e.g. add a compliance step)

- **Versioning** — deploy the new code as a **new version**; old executions finish on old code, new ones use new code. Simplest, but you **can't force the change onto in-flight** ones immediately.
- **Migration** — change the definition **in place** so running executions pick it up. ⚠ **Only needed when the change must take effect immediately — even in in-flight workflows** (e.g. an urgent compliance fix). If you could just let the 10,000 legacy workflows finish on old code, **versioning already handles it**; migration is the harder path you take precisely because waiting for them to drain isn't acceptable.
    - **Step Functions** pins a running execution to the definition it **started with** → updates only affect **new** executions (to change in-flight ones, stop+restart, or pre-model the branch).
    - **Durable engines** use a **`patched()`** guard for a **deterministic** path choice — new executions take the new branch; executions whose history already passed this point stay on legacy → one deploy serves both without breaking replay.

▸ **"How do you keep workflow state size in check?"** (replay needs the whole history)

- **Minimize Activity inputs/results** — pass an **ID to look up**, not a huge payload.
- **Continue-as-New** (Temporal) — snapshot current state, start a **fresh run with empty history** seeded by that state → picks up where it was, without dragging full history. Standard fix for long-looping / months-long per-user workflows.

▸ **"Workflow waits for a customer to sign — 5 minutes or 5 days?"**

- Use **signals** + a **durable timer.** External webhook fires → calls the engine API with the workflow ID → engine **wakes the right execution.** While waiting it holds **no thread, no worker memory** — just persisted state. Handles human tasks, webhook callbacks, external integrations.

▸ **"Ensure a step runs exactly once?"** ⭐ (idempotency — the theme)

- ⚠ True **exactly-once _delivery_ is impossible** across a network: an Activity can finish but its success report gets lost → engine retries.
- **Fix = idempotent Activity:** store an **idempotency key**, check it before the irreversible action.
- ⚠ **Check + action still aren't atomic** (crash after emailing, before recording the key). **Shrink the window:** mark key **`IN_PROGRESS` before**, **`COMPLETED` after.** Retry finding `COMPLETED` → skip; finding nothing → proceed; **`IN_PROGRESS`** → **park for reconciliation** (ask the provider what it received), don't blind-refire.
- ▸ **Precise guarantee:** attempts are **at-least-once**; the **effect** is **exactly-once** because idempotency makes repeats harmless. _(Don't avoid side effects in Activities — charging/emailing are fine; idempotency makes them safe to retry.)_

---

## The one thing to recognize

▸ **Most of the skill is spotting that you're hand-building what a workflow engine already provides:** state persistence across failures, orchestration of many services, long-running waits, automatic retries + compensation, and an audit trail. **If you're implementing distributed sagas by hand or building state machines in Redis → reach for a workflow system.** ⚠ Be ready on the tradeoff: yes, it's **another distributed system to operate** + a learning curve — but for the right problems it's the difference between an on-call that dreads stuck orders and one that **reads the workflow history and moves on.**

---

## Quick Recall (pass 3+)

|Question|Answer|
|---|---|
|What is this pattern|coordinate **many flaky services/humans over long time**, surviving crashes/retries/waits|
|Governing insight|every DIY rung **hand-rolls what a workflow engine gives free**; survival tool = **idempotency**|
|Rung 1 — single server|walk steps in one process; ⚠ **crash = no memory**, **webhook lands on wrong host**; patch = DB checkpoints + Pub/Sub, but no compensation|
|Rung 2 — Saga|steps + **compensating actions**; on failure **walk back compensating**; each step commits alone|
|Why not 2PC / distributed txn|can't hold locks that long; **external systems don't speak your txn protocol** → saga guarantees **undo**, not atomicity|
|↳ 2PC vs saga vs lock|**opposites**, not parent/child: 2PC = **prevent** partial failure (lock all, commit together) · saga = **allow** it, then **undo**. **2PC is built _on_ distributed locks** (lock = primitive, 2PC = the ceremony). Same-DB transfer = local txn, **not 2PC**|
|↳ industry practice|one DB → **local txn/OCC** · short controlled cross-DB → 2PC possible (avoided) · long / uncontrolled services → **saga** (real payments lean saga)|
|Saga costs|**inconsistency window** (`pending` state) · compensations need **own retries + idempotency + human escape hatch**|
|Choreography vs orchestration|**no coordinator, emergent flow** (independent services, mid-complexity) · **central coordinator** (very complex, needs visibility)|
|Rung 3 — event-driven choreography|durable log (**Kafka** / Redis Streams); workers consume→emit; compensation flows backwards; ⚠ implicit flow, mid-step insert = contract change, **idempotent workers**|
|Event sourcing|log as **source of truth**, derive state — close cousin, not required|
|Rung 4 — workflow orchestration|durable coordinator **without hand-rolling infra**; code (**Temporal**) or declarative (**Step Functions**)|
|Temporal primitives|**Workflow** (recipe, **deterministic**) + **Activity** (step, **idempotent**)|
|Temporal recovery|**replay** — re-run workflow from top, history returns recorded Activity results (no re-fire), lands where it stopped|
|Temporal parts|**Server** (bookkeeper, never runs your code) · **History DB** · **workflow + activity worker pools**|
|Signals|wait for external events (human, 30-day signature) with **no thread/CPU** — engine persists state, rehydrates on signal|
|Engine pick|matters less than **knowing its recovery model + limits**; Step Functions caps **1yr / 256KB**|
|↳ "state machine in JSON" (SF)|flow written as **data** — named states + `Next`/`Catch` transitions; engine walks it; renders as a **diagram**. (Temporal = flow as **code**)|
|↳ recovery: replay vs bookmark|**Temporal replays your code** (skips already-recorded `await`s → resumes live; needs determinism) · **Step Functions = bookmark** (saved position server-side, no replay)|
|Update in-flight workflows|**versioning** (old finish on old code) or **migration** (`patched()` deterministic branch · SF pins to start definition)|
|State size|pass **IDs not payloads** · **Continue-as-New** (fresh history seeded with state)|
|Exactly-once|impossible as _delivery_; make Activity **idempotent** (key + `IN_PROGRESS`/`COMPLETED`); **at-least-once attempts, exactly-once effect**|
|When NOT|single-step async → **queue** · synchronous/latency-sensitive · high-freq low-value|
|Recognize it|doing sagas by hand / state machines in Redis → use a workflow engine|
|⭐ Fintech / AI|payment orchestration + refunds (saga) · **AI agent pipelines = long flaky stateful chains**|


Quick Reference => https://www.hellointerview.com/learn/system-design/patterns/multi-step-processes/quick-reference