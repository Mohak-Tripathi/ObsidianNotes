# ChatGPT — Problem Breakdown

> 📐 **Revision note (calc):** **200M+ DAU · a few prompts each ⇒ ~20k prompts/sec peak · a response takes several seconds ⇒ ⭐⭐ ~120k streaming AT ANY MOMENT.** **TTFT <~500ms · 99.9%+ availability · a long answer up to 30s.** 📐 ⭐⭐ **Polling check: 120k streams ÷ 300ms = 400k req/sec, nearly all empty.** 📐 ⭐⭐⭐ **GPU cost: weights split across ~8 GPUs per server ⇒ 120k streams needs thousands of servers ⇒ TENS OF THOUSANDS of GPUs ⇒ "hundreds of millions to billions a year."** ⭐ **Anchor: OpenAI's inference compute ~$1.8B in 2024.** **Context: a 50-turn chat × ~500 tokens = ~25k input tokens EVERY turn.**

>  Common Problems · File `05ae` ⚠ **(code unverified — the single-letter scheme runs out at 26; confirm)**. **Evan King, published May 21, 2026** — ⭐⭐ **the NEWEST write-up in your set** · ⭐⭐ **"HARD", fourth in a row** · ⚠ **"Asked at:" is EMPTY** · ⭐⭐ **TWO patterns: `Real-time Updates` → `03a` and `Managing Long Running Tasks` → `03?`** ⚠ **(confirm that code too).** Cross-refs: ⭐⭐⭐ **`05q` FB Live — pub/sub fan-out, and here it gets UPGRADED to a log** · ⭐⭐⭐ **`05v` Robinhood — the SSE-vs-WebSocket argument, and the queue question it seemed to settle gets REFINED (see §1.3)** · ⭐⭐ **`05t` Notification — priority queues, token buckets** · ⭐ **`05o` YouTube — long work on a worker pool** · **`02a` Redis (pub/sub, Streams, token bucket) · `02g` Postgres · `01b` cursor pagination · `01h` availability over consistency · `02d` API Gateway · `01i` numbers.**
> 
> **Calibration:** ⭐⭐⭐ **TWO passes. Five dives, all five substantial, and nothing here is filler.** ▸ ⭐⭐ **Also the most CURRENT problem in your set — a live hot topic, so expect it.** ⭐ **Order: DD2 > DD3 > DD4 > DD1 > DD5.**
> 
> - ⭐⭐ **What actually scores:** **(a)** ⭐⭐⭐ **the Run entity — a Message is the RESULT, a Run is the ATTEMPT** · **(b)** ⭐⭐⭐ **pub/sub loses tokens in the reconnect gap; a Redis Stream replays them** · **(c)** ⭐⭐⭐ **continuous batching, and WHY (memory-bandwidth bound)** · **(d)** ⭐⭐⭐ **metering TOKENS not requests, with reserve-then-refund** · **(e)** ⭐⭐ **SSE over WebSocket from the one-way argument** · **(f)** ⭐⭐ **prefix caching, and that a rewritten summary INVALIDATES it** · **(g)** ⭐ **closing the tab is not a cancel.**
> - ⭐ **Transferable primitives:**
>     - ⭐⭐⭐ **When work can fail halfway, the ATTEMPT needs its own identity and lifecycle — separate from the artefact it produces.**
>     - ⭐⭐⭐ **A queue is fine when the RESPONSE doesn't wait for the work.** ▸ **Split the acknowledgement from the result and you can queue anything.** ⭐ **This refines `05v`.**
>     - ⭐⭐⭐ **Pub/sub has no memory. If a gap in delivery is VISIBLE to the user, you need a log, not a broadcast.**
>     - ⭐⭐⭐ **Meter the scarce RESOURCE, not the request count.** ▸ **And put the meter where the cost is known, not at the edge.**
>     - ⭐⭐⭐ **Reserve the worst case on admission, refund the difference.** ▸ **Then you never have to kill work in flight to stay inside a budget.**
>     - ⭐⭐ **Send deltas, not snapshots.** ▸ **Re-sending the growing prefix is quadratic.**
>     - ⭐⭐ **Two hops can want two different transports.** ▸ **gRPC internally, SSE to the browser — chosen for different reasons.**
>     - ⭐ **Introduce an entity when the design needs it, not upfront.** ▸ **HI holds the Run back on purpose.**
> - ⭐ **Re-run (cross-ref, NOT re-explained):** **SSE vs WebSocket vs polling (`03a`, `05q`, `05v`)** · **Redis pub/sub fan-out (`05q`)** · **cursor pagination (`01b`)** · **token buckets + tier priority queues (`05t`)** · **`userId` from the JWT (`05u`, `05v`)**. **Genuinely new:** ⭐⭐⭐ **the Run / Message split** · ⭐⭐⭐ **Redis STREAMS with `XADD`/`XREAD` from last-seen ID** · ⭐⭐⭐ **continuous batching + memory-bandwidth bound** · ⭐⭐⭐ **reserve-then-refund token budgets** · ⭐⭐ **prefix caching / KV cache, and its tension with summarization** · ⭐⭐ **backpressure with an admission policy** · ⭐⭐ **gRPC server-streaming on the internal hop** · ⭐ **a cancel CONTROL channel** · ⭐ **speculative decoding.**

---

## 0 · Understanding the problem

💬 **Prompts in, responses streamed back from an LLM, conversations saved so you can resume.**

⭐⭐⭐ **The scoping sentence that defines the whole problem: _"we treat the LLM as a black box we call, not something we train or run the internals of. All the design lives in the serving system around it."_**

⭐⭐ **And HI names the three interesting parts upfront: _"how we stream tokens back fast, how we schedule limited GPU capacity, and how we keep cost sane as conversations grow."_** ▸ **Those are DD1–2, DD3–4, DD5.**

**Scope: text in, text out. No images/audio/video, no editing or branching.**

---

## 1 · Requirements

### 1.1 Functional

1. ⭐ **Users should be able to send a prompt in a chat and receive an AI-generated response.**
2. ⭐⭐ **Users should be able to view past chats and resume a conversation, with the chat's prior context carried into the prompt.**

⚠ **Below the line:** **editing or branching messages · image/audio/video · sharing or collaborating on a chat · custom GPTs, tool calling, web browsing · full-text search across history.**

▹ ⭐ **HI on out-of-scope items: _"Adding an out-of-scope feature can show product thinking and give your interviewer a chance to reprioritize. But it is optional. If an extra feature does not come to you quickly, move on."_**

### 1.2 Non-functional

📐 ⭐⭐ **The scale HI fixes here, and every later dive leans on it:** **200M+ DAU · _"a few prompts each per day"_ ⇒ ~20k prompts/sec at peak · and since a response takes several seconds to generate, ⭐⭐ roughly ~120k are STREAMING AT ANY GIVEN MOMENT.** ▸ **_"That's the scale we'll design against."_**

1. ⭐⭐⭐ **Low time-to-first-token (<~500ms).** ▸ ⭐ **Why TTFT and not total time: _"ChatGPT feels broken if you stare at a blank screen for a few seconds after hitting enter."_**
2. ⭐⭐ **Fault tolerant — _"recovering an in-flight stream without dropping tokens when a connection drops or a server fails."_**
3. ⭐ **Availability over strong consistency for conversation state (~99.9%+).**
4. ⭐⭐⭐ **Scale under GPU-CONSTRAINED capacity, with fair allocation across a tiered user base (free, Plus, Pro).**

⚠ **Below the line:** ⭐ **durability of every streamed token** (**_"we persist the final assistant message, not each chunk"_**) · **auth, abuse prevention, moderation · GDPR and residency · monitoring and CI/CD.**

> ⭐⭐ **NFR 4 is the unusual one and it drives three of the five dives.** ▸ **"GPU-constrained" means you cannot buy your way out — the capacity is fixed, so the design has to decide WHO gets it.** ⭐ **Third flavour of cost-as-a-constraint in your set: `05u` you COMPUTED it, `05v` it was STIPULATED, here it is PHYSICALLY SCARCE.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 1.3 ⭐⭐⭐ The design driver — a 30-second unit of work, on a resource you can't buy more of, with a user watching

|Constraint|What it breaks|Fixed by|
|---|---|---|
|⭐⭐ **30s to generate, user staring**|**a synchronous response**|**DD1 streaming**|
|⭐⭐ **the instance in the middle will vanish**|**a stream pinned to one server**|**DD2 Redis Stream**|
|⭐⭐⭐ **GPUs are fixed and cost billions**|**"just scale horizontally"**|**DD3 queue + batching**|
|⭐⭐ **one tenant can starve everyone**|**a flat rate limit**|**DD4 token budgets + tiers**|
|⭐⭐ **the input grows every turn**|**replaying full history**|**DD5 summary + prefix cache**|

> ⭐⭐⭐ **And this file RESOLVES the apparent contradiction with `05v` Robinhood — worth getting straight, because it looks like the two files disagree.**
> 
> - ⚠ **`05v` REJECTED a queue in the order path: _"a queue decouples, and decoupling costs latency"_, and the user was blocked on `POST /order`.**
> - ⭐⭐ **Here, `POST /chats/{id}/messages` ALSO returns fast — it returns `{runId}` immediately. The queue sits BEHIND that, and the client watches a separate SSE stream.**
> - ⭐⭐⭐ **So the rule holds and sharpens: a queue is fine when the RESPONSE doesn't wait for the work. Split the acknowledgement from the result, and you can queue anything.** ⚠ **Robinhood couldn't, because an order confirmation IS the result.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 1.4 Planning the approach

⭐ **Sequentially through the FRs — _"There are only two of them, so the high-level design will be intentionally short."_** ⭐⭐ **_"The work that actually makes this problem interesting lives in the non-functional requirements."_** ▹ **Same lesson as `05x`: the NFRs are the agenda.**

---

## 2 · Core Entities

- **User** — ⭐ **carries the TIER (free vs paid), _"which is going to matter a lot once we get to fairness and scheduling."_**
- **Chat** — **one thread, one user, an ordered sequence of messages, title, timestamps.**
- **Message** — **one turn, `chatId` + role (user/assistant) + content + token count.**

> ⭐⭐⭐ **HI deliberately WITHHOLDS the fourth entity, and says so: _"We'll introduce one more entity, a Run, later once the deep dives actually need it, since it isn't something you'd naturally reach for this early."_**
> 
> ▸ ⭐⭐ **Worth copying as technique — introduce an entity when the design demands it, so its justification is visible. Listing it upfront looks like you memorised the answer.**
> 
> ■ **— end of insert · HI write-up resumes below —**

---

## 3 · API

```
POST /chats                                      -> { chatId }
POST /chats/{chatId}/messages    { content }     -> Message     ⚠ changes in DD1
GET  /chats?cursor=&limit=                       -> Chat[]
GET  /chats/{chatId}/messages?cursor=&limit=     -> Message[]
```

- ⭐ **Both GETs are cursor-paginated — _"a heavy user can have thousands of chats and a long chat can have thousands of messages."_**
- ⭐ **`userId` appears nowhere: from the session token, ownership checked server-side.** **_"Passing `userId` in the body is a classic red flag, since anything the client sends can be forged."_**
- ⚠⚠ **The messages endpoint is temporary: _"this hands back the finished message on an ordinary HTTP response, so the client waits out the whole generation before it sees a word. That's the first thing we fix in the deep dives, and the fix splits this endpoint in two."_**

---

## 4 · High-Level Design

⭐ **Deliberately naive — _"Starting with a working system and then breaking it is far better than starting with a 'perfect' one that's hard to reason about."_**

### 4.1) Send a prompt, receive a response

```
Web Client ──► API Gateway ──► Chat Service (stateless) ──sync HTTP──► Inference Service
              auth · limits        │                                     (GPU workers)
                                   └──► Postgres   chats · messages
```

- **API Gateway** — **auth, rate limiting, routing.**
- ⭐ **Chat Service** — **stateless; owns chat/message persistence and orchestrates the model call.**
- **Postgres** — **system of record.** ▹ ⭐ **HI is honest it's arbitrary: _"almost any database would work here. We reach for Postgres as a sensible default rather than because anything about the problem demands a relational store."_**
- ⭐⭐ **Inference Service** — **the GPU pool. Each machine runs a model server with weights resident in GPU memory; these are the WORKERS.** ⭐ **_"There's no tier in between, a request goes to a worker and that worker generates."_**

**Flow: prompt → gateway auths → Chat Service writes the user message → synchronous call to inference → writes the assistant message → returns it.**

> ⭐⭐ **The one decision to dwell on, in HI's words: _"The chat tier is cheap and stateless, while inference is GPU-bound and expensive, and since we'll want to scale the two independently, we separate them now."_**
> 
> ⚠⚠ **And the two problems he plants deliberately: ① fully synchronous ⇒ _"30 seconds of blank screen"_ ② _"the Chat Service calls a GPU worker directly with no ADMISSION CONTROL. Nothing decides which requests to accept or turn away when the workers are already full."_** ▸ ⭐ **Those become DD1 and DD3.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 4.2) View past chats and resume with context

⭐ **No new services — two read endpoints on the existing tables, plus a context-loading step inside the Chat Service.**

**The read path:**

- ⭐ **`GET /chats`** — **the user's chats ORDERED BY RECENT ACTIVITY, cursor-paginated. This is the sidebar.**
- ⭐ **`GET /chats/{chatId}/messages`** — **one chat's messages, cursor-paginated _"so a long conversation doesn't load all at once."_**

**Context carry-over, when the user sends a follow-up on an existing chat:**

1. **Chat Service queries the `messages` table for prior messages in that `chatId`, ordered by creation time.**
2. ⭐ **It builds the prompt by concatenating those messages WITH THEIR ROLES (user vs assistant), then the new user message.**
3. **It sends that combined prompt to the Inference Service — _"just like the first turn."_**
4. ⭐ **The new assistant message is written back to `messages`, so the next turn can read it too.**

⭐⭐ **Why it works at all: _"The model sees the whole conversation every turn, so it behaves like it remembers."_** ▸ **The memory lives in your prompt assembly, not in the model.**

⚠⚠ **Two problems planted here on purpose: it breaks once the chat outgrows the context window, and input tokens are billed per call so it _"gets more expensive every turn."_** ⇒ **summarization and prefix caching in DD5.**

---

## 5 · Deep Dives

▹ ⭐ **HI: _"There's no one right set of deep dives here, or one order to tackle them in."_** ⭐ **His order follows the design's own pressure: stream it → keep it alive → schedule the GPUs → share them fairly → cut the context cost.**

### 1) How do we stream tokens back to the client?

⭐⭐ **Two connections, not one: worker → Chat Service, and Chat Service → browser.** ⭐ **Treat the first as given: **server-streaming gRPC**.** ▸ **Why not request/response: _"it would force the worker to buffer the entire 30-second completion and hand it back in one lump, which is the blank screen all over again."_** ⭐ **Why gRPC not WebSockets internally: HTTP/2 binary framing + multiplexing, and protobuf gives a typed contract.**

> ⭐ **Pattern: Real-time Updates** (`03a`) — **_"Streaming LLM tokens is a textbook realtime updates problem."_** ▹ **Same transports and the same backend fan-out as live comments and collaborative editing.**
> 
> ■ **— end of insert · HI write-up resumes below —**

⚠ **Rung labels are mine.**

#### ⚠⚠ Bad — polling a status endpoint

- **The client asks every few hundred ms; tokens have to be buffered somewhere the endpoint can read.** ▹ ⭐ **HI picks Postgres _"for the sake of argument, recognizing neither is a good idea"_ — Redis is fast but loses everything on restart, Postgres turns one response into hundreds of tiny writes.**
- ⚠⚠ **Three failures, and the first is fatal to the main NFR:**
    - ⭐⭐ **TTFT is gated by the poll interval — a 500ms poll adds 500ms of dead time before the first token can appear.**
    - 📐 ⭐⭐ **Wasteful: 120k streams polling every 300ms = 400k req/sec, _"the overwhelming majority of those come back empty."_**
    - ⭐ **Lumpy: tokens arrive in batches, which _"kills the smooth typing illusion that makes the product feel alive."_**

**Why climb:** ⭐ **_"The fix for all three problems is the same idea, stop asking and let the server push."_**

#### Good — a WebSocket

- **One persistent full-duplex channel for the life of the generation. Two streams chained through one Chat Service instance: gRPC in, WebSocket out.** ✅ **TTFT now bounded by the model, not a poll interval.**
- ⚠ **But it's more than the job needs: _"during a generation we only ever push one way."_** ⚠ **Costs: a stateful two-way protocol, its upgrade handshake, per-connection bookkeeping, and _"every load balancer and proxy in the path also has to speak WebSocket."_**

**Why climb:** ⭐ **you're paying for a direction you never use.**

#### ⭐⭐ Great — Server-Sent Events

- ⭐⭐ **_"purpose-built for one-way server-to-client streaming."_** **The client opens an ordinary HTTP request with `EventSource`; the server holds the response open and writes `data:` events.**
- ✅ **Plain HTTP, no upgrade — _"every proxy and load balancer in the path already handles it."_**
- ⭐⭐ **And the bonus that DD2 depends on: _"the `EventSource` API reconnects on its own when a connection drops."_**
- ⭐ **The backend is unchanged from the WebSocket option — same gRPC in, SSE out instead.**

> ⭐⭐⭐ **Confusion resolved — the Run entity, and why none of the existing three would do.**
> 
> - ⭐⭐⭐ **HI: _"A message is the finished text, while what we're streaming is an ATTEMPT to produce it, and that attempt has a lifecycle of its own."_** ▸ **It can be queued, run, fail halfway, be cancelled, be retried — all before there's a message to write down.**
> - ⭐ **`runs`: `runId · chatId · messageId · status (queued → streaming → done/cancelled/failed) · model · input & output token counts`** (⭐⭐ **those two counts carry DD4's billing**).
> - ⭐⭐⭐ **It reshapes the API: `POST /chats/{id}/messages` stops waiting, creates the Run and returns `{runId}`; the client follows `GET /runs/{runId}/stream`.** ▸ ⭐⭐ **And the reason it must be a GET: _"the browser's native `EventSource` API only opens GET requests."_** ⭐ **An API constraint deciding a design — worth noticing.**
> - ⭐⭐⭐ **The primitive: when work can fail halfway, the ATTEMPT needs its own identity, separate from the artefact it produces.** ▸ **Everything later — the queue, the workers, cancellation — refers to the run.**
> 
> ■ **— end of insert · HI write-up resumes below —**

**The flow: persist the user message → create a Run → return `runId` → client opens SSE → prompt goes to a worker → worker streams tokens over gRPC → Chat Service forwards each one down SSE.**

### 2) ⭐⭐⭐ How do we keep the stream alive across reconnects and deploys?

⚠⚠ **The flaw: one specific Chat Service instance holds both the SSE connection and the gRPC stream, so it must survive 30 seconds.** ⚠ **But that tier is _"stateless, horizontally scaled behind a load balancer, and redeployed all day long, which makes that instance disappearing mid-generation ROUTINE."_**

⭐⭐ **The goal: _"the worker shouldn't need to know which instance is holding the user's connection"_, and a reconnect landing elsewhere should resume the same run.**

> ⚠⚠ **Confusion resolved — the whole dive, worked through. Read this BEFORE the rungs.**
> 
> **① What has to change**
> 
> ⭐⭐⭐ **The worker shouldn't know which instance holds the user. The instance shouldn't know which worker is generating.**
> 
> **So you put something in the middle that both sides talk to instead of each other, and you name that thing after the `runId`.**
> 
> ⭐⭐ **This is why the Run entity exists. The worker dies, the instance dies — `run:abc123` is the one name that survives both. Without a `runId` there's nothing to key the middle on.**
> 
> **② Attempt 1 — Redis Pub/Sub**
> 
> **What pub/sub is, concretely: a channel with a name. Anyone publishes to it. Anyone subscribed RIGHT NOW receives it. Nothing is stored.**
> 
> ```
> worker #42 ──publish token──► channel "run:abc123" ──► whoever is subscribed
> ```
> 
> - **Worker #42 publishes each token to `run:abc123`. It has no idea who's listening.**
> - **Whichever instance holds the SSE connection subscribes to `run:abc123` and forwards down to the browser.**
> - ✅ **Browser reconnects onto instance #3? Instance #3 just subscribes to `run:abc123` and starts forwarding.**
> 
> **That looks like it solves everything. It doesn't.**
> 
> **③ ⚠⚠ Where pub/sub breaks — the actual failure, on a clock**
> 
> **Pub/sub has NO MEMORY. If nobody is subscribed at the exact instant a message is published, that message is gone forever.**
> 
> ```
> t=0.0s   instance #7 subscribed, forwarding fine ........ tokens 1-199 ✅
> t=5.0s   instance #7 dies (deploy)
>          ⚠ nobody is subscribed to run:abc123 any more
> t=5.0s   worker publishes token 200 ──► no subscriber ──► GONE
>   ...    worker publishes tokens 201-240 ──► no subscriber ──► GONE
> t=5.8s   browser reconnects, lands on instance #3, subscribes
> t=5.8s+  tokens 241 onward arrive fine ................. 241+ ✅
> ```
> 
> ⭐ **The user sees tokens 1–199, then 241 onward. Tokens 200–240 are a hole in the middle of the sentence — and they never arrive, because nothing kept them. The gap only fills in when generation finishes and the client refetches the whole message from Postgres, ~25 seconds later.**
> 
> **④ ⭐⭐ Attempt 2 — a Redis Stream**
> 
> **Same idea, but the middle thing REMEMBERS. A Redis Stream is an append-only log where every entry gets an auto-incrementing ID:**
> 
> ```
> run:abc123
>    199-0   " the"
>    200-0   " quick"
>    201-0   " brown"
>    202-0   " fox"     ← entries SIT HERE whether anyone is reading or not
> ```
> 
> **Two commands:**
> 
> - `XADD run:abc123 * token " fox"` — **the worker APPENDS**
> - `XREAD BLOCK 0 STREAMS run:abc123 199-0` — **a reader says _"give me everything after 199, and if there's nothing yet, wait."_**
> 
> ⭐⭐⭐ **That last-ID argument is the entire fix.** **Same failure, replayed:**
> 
> ```
> t=5.0s   instance #7 dies, having forwarded up to entry 199
> t=5.0s   worker XADDs 200-240 ──► they sit in the log ✅
> t=5.8s   browser reconnects → instance #3
>          instance #3: XREAD from 199
>          → Redis instantly returns 200-240   (the catch-up)
>          → then blocks and streams 241+ live
> ```
> 
> **No hole. One continuous answer, even though the connection AND the server behind it both changed.**
> 
> **⑤ How does the client know it last saw 199?**
> 
> ⭐⭐ **SSE does it for you. The server attaches an `id:` to each event; on reconnect the browser automatically sends `Last-Event-ID` back.**
> 
> **That's the DD1 bonus being cashed in — _"the `EventSource` API reconnects on its own"_ was not a nice-to-have, it's the mechanism DD2 depends on.** ▸ **Same `Last-Event-ID` you have from `05q`.**
> 
> **⑥ Two details that matter**
> 
> **Send DELTAS, not the message-so-far.** **If each publish carried the cumulative text, a 4,000-token answer would re-send a growing prefix 4,000 times: 1+2+3+…+4000 ≈ 8 MILLION tokens' worth of traffic for a 4,000-token answer. 2,000× more data. At 120k concurrent streams that's not a design, it's a bill.**
> 
> **The stream is SCRATCH SPACE, not storage.** **`MAXLEN` caps its length, a short TTL deletes it after generation.** ⭐ **Postgres gets the final message and is the system of record — which is exactly why "durability of every streamed token" stays below the line even though tokens briefly live in Redis.**
> 
> ⭐⭐⭐ **The one-line test to carry away: is a delivery gap VISIBLE to the user?** **Here it's a hole mid-sentence ⇒ you need a log.** **In `05q` a missed comment was refetched on reconnect and nobody could tell ⇒ pub/sub was fine.**
> 
> ■ **— end of insert · HI write-up resumes below —**

⚠ **Rung labels are mine.**

#### Good — Redis Pub/Sub keyed by `runId`

- **The worker publishes each token to `run:{runId}`; whichever instance holds the SSE connection subscribes and forwards.** ✅ **Neither side knows about the other. A reconnect to a different instance just subscribes to the same channel.**
- ⭐⭐⭐ **Publish DELTAS, not the message-so-far:** **_"Republishing the cumulative text on every token would be quadratic. A 4,000-token answer would re-send a steadily growing prefix 4,000 times."_** ▸ ⭐ **At 120k streams and answers up to 30k tokens, a non-starter.**
- ⚠⚠⚠ **And then the fatal gap: pub/sub _"delivers a message only to the subscribers connected at the instant it's published, and it buffers nothing."_** ⇒ **during the window between the old instance dropping and a new one subscribing, there is no subscriber and those tokens are PERMANENTLY LOST.** ⭐ **_"The user is left with a hole in the middle of their answer."_**

**Why climb:** ⭐⭐ **the gap is visible mid-sentence, so the transport needs a memory.**

#### ⭐⭐ Great — a Redis Stream

- ⭐⭐⭐ **Same `runId` key, but an append-only log that remembers its entries, each with an ID.** **Worker `XADD`s each delta; the Chat Service does a blocking `XREAD` starting from this client's LAST-SEEN entry ID, forwards new entries, and tracks the latest ID.**
- ⭐⭐⭐ **Which makes reconnect clean: the new instance _"replays exactly the entries that were missed during the gap, then continues live. No hole, no waiting until the end."_**
- ⭐ **Bounded with `MAXLEN` plus a short TTL** — **_"The stream is short-lived working state, not a second copy of history."_**
- ⭐⭐ **And the durability line that keeps per-token durability below the line: _"the stream is not our system of record. When generation finishes, the worker writes the complete assistant message to Postgres and marks the Run done."_**

▸ ⭐⭐ **One last framing: this is `05i`/`05p`/`05t`'s "a log is not a work queue" run backwards — a BROADCAST is not a log.** ⭐ **Pick by whether anyone can tell that something was dropped.**

### 3) ⭐⭐⭐ How do we route and schedule generation requests across GPU workers?

⭐⭐⭐ **The cost framing, and it's the thing Staff+ is expected to volunteer unasked:** **a frontier model is too big for one GPU, so its weights split across ~8 in a server; 120k concurrent streams means thousands of those servers ⇒ tens of thousands of GPUs ⇒ _"easily hundreds of millions to billions of dollars a year."_** ⭐ **Anchor: _"OpenAI's reported inference compute ran around $1.8B in 2024."_**

⭐⭐⭐ **_"When the hardware costs that much, every percentage point of unused capacity is real money."_**

> ⭐ **Pattern: Managing Long Running Tasks** — **_"A single generation can run for 30 seconds on a limited, expensive worker."_** ▹ **Hand work to a pool through a queue and let workers PULL when they have capacity. Same shape as video transcoding and batch ML.**
> 
> ■ **— end of insert · HI write-up resumes below —**

⚠ **Rung labels are mine.**

#### Good — a pull-based request queue

- **Chat Service enqueues (prompt + `runId`) and returns fast; workers pull when they have capacity and append tokens to the run's stream.** ⭐ **Pull-based matters: _"a server only takes new work when it can actually do it."_**
- ⭐⭐ **What it buys: _"The queue absorbs the spike and lets it drain at whatever pace the workers can sustain, so a surge becomes a few seconds of extra wait instead of a pile of errors."_**
- ⚠⚠ **Two problems left:**
    - ⭐⭐ **It's UNBOUNDED — sustained demand above capacity grows the line forever, and a user has _"no idea whether their answer is two seconds away or two minutes."_**
    - ⭐⭐ **One-request-per-slot wastes the GPU: _"GPUs are most efficient when they process many sequences together."_**

**Why climb:** cap the wait, and stop under-using the thing that costs billions.

#### ⭐⭐ Great — continuous batching + backpressure

- ⭐⭐⭐ **Each worker runs many active sequences at once, and _"a single forward pass can generate the next token for every sequence in the batch."_**
- ⭐⭐ **The "continuous" part: _"When one sequence finishes, the worker removes it and pulls another request from the queue into the newly available slot"_** ⇒ **no waiting for a whole batch to drain.**

```
one forward pass            next pass                   next pass
A -> token 42               A -> 43                     A -> 44
B -> token 17        ⇒      B -> 18             ⇒       B -> 19
C -> token 91               C -> finished  ───┐          E -> 1   ◄── pulled in
D -> token 8                D -> 9            └─evicted  D -> 10
```

- ⭐⭐ **Backpressure: a bounded queue depth plus an admission policy.** **Over the limit ⇒ reject, defer or shed.** ⭐ **_"Users either enter a queue of manageable size or get a fast 'we're at capacity, try again' instead of joining an ever-growing backlog."_**
- ⚠ **Cost: a much more complex serving layer juggling variable-length sequences, and _"a batch of wildly different prompt lengths can still leave some GPU work idle."_** ▹ **The inference framework handles most of it.**

> ⚠⚠ **Confusion resolved — why batching matters this much. (HI's warehouse analogy, rebuilt.)**
> 
> - ⭐⭐⭐ **① To produce ONE token, the GPU must do math with EVERY weight in the model — say 100 GB of them.**
> - ⭐⭐ **② The math can only happen in a few MB of on-chip memory, so all 100 GB gets shovelled from main memory through the compute cores, for every single token.**
> - ⭐⭐⭐ **③ 📐 Put numbers on it: ~3 TB/s bandwidth ⇒ 100 GB takes ~33ms to MOVE. The arithmetic itself takes microseconds.** ▸ **The GPU is idle, waiting on bytes, nearly the whole time. That is MEMORY-BANDWIDTH BOUND.**
> - ⭐⭐⭐ **④ So while those weights are passing through, you can serve 1 sequence or 50 for the SAME 33ms. Same hardware, 50× the output.** ▸ **The moving was the cost, and you already paid it.**
> - ⭐⭐ **⑤ The bus: driving A→B costs the same with 1 passenger or 50. One forward pass = one bus trip; each sequence = a passenger. Batch-of-1 is running the bus for one person.**
> - ⭐⭐ **⑥ And CONTINUOUS: a fixed batch waits for every passenger to reach their stop, so the bus runs half-empty — _"a one-line reply can sit next to a 2,000-token essay."_ Continuous batching drops a sequence the moment it finishes and picks up a queued one. The bus stays full.** ▹ **vLLM and TGI.**
> - ⭐ **⑦ Which is why DD3's queue is PULL-based: a worker pulls when a SEAT opens, not when it's "free."**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 4) ⭐⭐⭐ How do we keep heavy users from taking over the pool while giving paid tiers a better experience?

⚠⚠ **The setup: one limited pool, wildly uneven costs — _"One user firing a 30k-token prompt burns far more compute than a hundred users sending one-liners."_** ⭐⭐ **TWO separate needs: fair sharing so nobody starves everyone, and business priority across tiers.** ⚠ **_"A flat requests-per-minute cap can't express either of those."_**

⚠ **Rung labels are mine.**

#### ⚠⚠ Bad — one global rate limit

- **A single counter at the API Gateway, atomic increment-and-check, 429 over the limit. In Redis, since the app tier is stateless.**
- ⚠⚠⚠ **And it causes the exact problem it was meant to solve:** **_"One counter for everyone means the limit has no idea who is asking. A single user hammering the API burns through the global budget, and everyone else starts collecting 429s for traffic they didn't send. That's the starvation problem we came here to solve, now enforced by our own rate limiter."_**

**Why climb:** a limit that can't tell who is asking can't be fair.

#### Good — key the limiter by `userId`

- ⭐ **Same machinery, different key — one bucket per user.** **For concurrency: a per-user counter in Redis, incremented when a generation starts, decremented when it finishes or is cancelled; at the cap, reject or queue.**
- ⭐⭐ **HI's line is the lesson: _"The only thing that really changed from the global limit is the key, from one shared bucket to one bucket per user. But that's the change that stops a single heavy user from starving the pool."_**
- ⚠⚠ **Still wrong, though: it counts REQUESTS, not COST.** **_"A per-user cap of '5 in-flight generations' treats five 50-token replies the same as five 30k-token generations."_** ⚠ **And it still gives paid tiers nothing.**

**Why climb:** meter the thing that's actually scarce.

#### ⭐⭐ Great — token budgets by tier, plus a tier-aware queue

- ⭐⭐⭐ **Meter TOKENS, not requests.** ⭐ **You already have both numbers: input is known once the prompt is assembled, output comes back down the stream — which is why the Run row records both.**
- ⭐⭐⭐ **And the check MOVES: _"off the API Gateway and into the Chat Service, since the gateway only sees a raw request while the Chat Service is what assembles the prompt and therefore knows what it will cost."_** ▸ ⭐⭐ **Put the meter where the cost is known, not at the edge.**
- ⭐⭐⭐ **Reserve-then-refund:** **debit the exact input count and RESERVE the requested max output on admission; when the run finishes, the true output count goes to the Run row and the unused reservation returns to the bucket.** ⭐⭐⭐ **Why it matters: _"a run can never cost more than the user could afford when it started, so we never have to kill a stream mid-sentence to stay inside a budget."_**
- ⭐⭐ **Then tier priority on top: bigger budgets, higher concurrency, and the DD3 queue becomes tier-aware — paid pulled ahead when workers free up.** ⭐ **_"Under normal load everyone's served fast and nobody notices; the tiers only diverge when capacity is tight, which is when paying customers should feel the difference."_**
- ⚠ **Two honest costs:** ⭐ **the reservation bounds a user's throughput by their WORST case, not their average** (**_"Reserve too tightly and you truncate real answers, too loosely and the budget stops meaning much"_**) · ⭐⭐ **and strict priority can starve free users, so **_"you reserve a floor of capacity for free traffic rather than letting paid traffic fully crowd it out."_**

> ⭐⭐ **Keep these two apart — HI's Staff+ bar names exactly this separation:** **FAIRNESS ACROSS USERS = cost-aware per-user budgets.** **PRIORITY ACROSS TIERS = tier-weighted queueing.** ▸ ⚠ **Conflating them is the trap; they're different mechanisms solving different problems.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 5) ⭐⭐ As conversations get longer, how do we control inference cost without making the assistant feel forgetful?

📐 **The problem: a 50-turn chat at ~500 tokens/turn ships ~25k input tokens on the next prompt, billed every call.** ⚠⚠ **Plus a hard ceiling — past the context window the request simply can't fit.**

▹ ⭐ **HI on the cop-out: real assistants just tell you the chat got too long, but _"leaning on that as your only answer means the product stops working for the power users who chat the most."_**

⚠ **Rung labels are mine.**

#### Good — truncate to the last N turns

```sql
SELECT * FROM "messages" WHERE "chatId" = $1
ORDER BY "createdAt" DESC LIMIT $2      -- then flip back to chronological
```

✅ **Bounded prompt, and it's just a bounded read.** ⚠⚠ **But _"abrupt amnesia at turn N+1 is a bad look"_ for a product whose appeal is that it remembers.**

#### ⭐⭐ Great — prefix caching + a rolling summary

- ⭐⭐⭐ **PREFIX CACHING is the biggest win.** **Across turns, most of the prompt is identical — system prompt plus everything already said — so inference servers cache the model's intermediate state (the **KV cache**) for a stable prefix instead of recomputing it.** ⭐ **Only the tail changes.** ⭐⭐ **And it _"cuts both the cost and the LATENCY of processing the input, which helps our TTFT goal directly."_**
- ⭐ **Pairs with conversation-aware routing — send each turn to a worker where its prefix is already warm.**
- ⚠ **The catch: finite worker memory, so prefixes are evicted LRU-style. _"A conversation that goes quiet and comes back later finds its prefix cold and pays full price."_**
- ⭐⭐ **But caching doesn't move the hard ceiling, so add a ROLLING SUMMARY:** **the prompt becomes `system prompt → summary of older turns → last few turns verbatim → new message`**, **updated in the background as old turns age out.** ⭐ **Recent context stays exact; older context survives compressed.**
- ⚠ **Costs: an extra (cheaper) model call, and a summary can drop a detail that mattered.** ⭐⭐ **The principle: _"protect the most recent turns and the most important user context first, and accept some lossiness on old history."_**

> ⭐⭐⭐ **The interaction between the two fixes, which is easy to miss and is exactly the "does a later dive break an earlier one?" check.**
> 
> ⚠⚠ **A rolling summary rewrites the start of the prompt. Prefix caching needs the start of the prompt to be STABLE.** ⇒ **_"If we rewrite the summary every turn, we invalidate the cache, so we update it on a SLOWER CADENCE to keep the prefix warm."_**
> 
> ▸ ⭐⭐ **Two cost fixes that fight each other, resolved by how often you apply one. Say this out loud — it shows you checked whether your own solutions compose.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### ⭐⭐ Cancelling a run, and reclaiming the GPU

⭐ **`POST /runs/{runId}/cancel`** — ⭐⭐ **and note why it's a separate request: _"SSE only pushes one way, so anything the client needs to send mid-stream travels over a separate request like this one."_**

**The Chat Service flips the Run to `cancelled` and publishes on a CONTROL CHANNEL keyed by `runId`. The worker checks that channel between token batches and drops the sequence.** ⭐ **Reclaiming that capacity _"the instant the user stops caring is real money back."_**

> ⭐⭐⭐ **_"Closing the tab is not a cancel."_**
> 
> **_"We built the Redis Stream and SSE reconnect precisely so a dropped connection isn't read as the end of a run, and like ChatGPT we keep generating in the background."_** **The user can reopen and reconnect, or refetch the finished message from Postgres.** ⭐⭐ **_"Cancellation has to be an explicit signal from the user, never an accident of the network."_**
> 
> ▸ ⭐⭐ **This is the clearest payoff of making the Run first-class: a connection and a unit of work are different things, so losing one says nothing about the other.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### ⭐ HI's four suggested extra dives

1. ⭐⭐ **Safety and moderation** — **a cheap classifier on the prompt in, a second pass on the output as it streams.** ⚠ **The hard part: _"you've usually already streamed some tokens to the user by the time the check trips"_** ⇒ **moderate in chunks before flushing, or pull the message back after.**
2. ⭐ **Why one model spans a server** — **TENSOR parallelism (each GPU holds a slice of every layer) vs PIPELINE parallelism (each holds whole layers and hands off).** **Both lean on NVLink inside a server and InfiniBand between them, _"and that interconnect can become its own bottleneck."_**
3. ⭐⭐ **Speculative decoding** — ⭐ **HI says know this for senior/staff:** **_"a small cheap 'draft' model can guess the next few tokens and the big model verifies all of them in a single forward pass. When the draft guesses right you get several tokens for the cost of one step."_**
4. ⭐ **Cheaper requests** — **route simple queries to a smaller model; cache responses for semantically similar prompts, _"keyed off an embedding rather than the exact string."_** ▹ **Pairs with DD4 — free traffic gets routed down first.**
5. ⭐ **Multimodal + cross-chat memory** — **cross-chat memory is a RETRIEVAL problem (embed past messages, pull relevant ones in), not the single-conversation summarization done here.**

---

## 6 · Final Design

⚠ **Layout and arrows are mine; components are HI's.**

```
Web Client ──► API Gateway ──► Chat Service (stateless)                       02d
  │  POST /chats/{id}/messages ⇒ { runId }   ⭐ returns IMMEDIATELY
  │  GET  /runs/{runId}/stream  ⇒ SSE        ⭐ GET, because EventSource
  │  POST /runs/{runId}/cancel              only opens GETs
  ◄──────── SSE ────────────────┤
                                │
                                ├──► Postgres  chats · messages · runs        02g
                                │      run: runId · chatId · messageId
                                │           status · model · in/out tokens
                                │      ⭐⭐ a Message is the RESULT,
                                │         a Run is the ATTEMPT
                                │
                                ├──► Rate limiter (Redis)                     02a
                                │      ⭐⭐⭐ TOKEN buckets keyed by userId,
                                │         refill by TIER — not request counts
                                │      ⭐⭐ debit input + RESERVE max output,
                                │         refund the unused part on finish
                                │      ⭐ lives HERE, not at the gateway: only
                                │         the Chat Service knows the cost
                                │
                                ├──► Priority Queue  ⭐ tier-aware; paid pulled
                                │      first · bounded depth + admission policy
                                │      ⭐ reserve a FLOOR for free traffic
                                │           │  (pull-based)
                                │           ▼
                                │     Inference Service × N  (GPU workers)
                                │       ⭐⭐⭐ CONTINUOUS BATCHING — one forward
                                │          pass advances every sequence; evict
                                │          on finish, pull a queued one in
                                │       ⭐⭐ PREFIX CACHING (KV cache) + routing
                                │          to a worker where the prefix is warm
                                │       ⚠ LRU eviction ⇒ a cold prefix pays full
                                │       ⭐ gRPC server-streaming for the token feed
                                │           │ XADD each DELTA
                                │           ▼
                                └──► Redis Stream  run:{runId}                02a
                                       ⭐⭐⭐ append-only log ⇒ a reconnect
                                          XREADs from last-seen ID and replays
                                          the gap. Pub/Sub would LOSE those.
                                       ⭐ MAXLEN + short TTL — working state,
                                          not a second copy of history
                                       ⭐ a separate CONTROL channel carries cancel

📐 20k prompts/sec peak · ~120k concurrent streams · TTFT <500ms
   ⭐⭐ ~8 GPUs hold one model ⇒ thousands of servers ⇒ tens of thousands
      of GPUs ⇒ hundreds of millions to billions a year
```

---

## 7 · Expected at Each Level

|Level|The bar for ChatGPT|
|---|---|
|**Mid (E4)**|**API + data model + a working synchronous HLD; recognise a 30s blank screen won't fly and reach for SSE (prompting allowed); know GPUs are the bottleneck and propose a queue — continuous batching and backpressure not expected.**|
|**Senior (E5)**|**Speed through the HLD, then two of {streaming fan-out, GPU scheduling, fairness} in detail; justify SSE-vs-WebSocket from the one-way nature; queue + continuous batching; see that cost grows with conversation length and propose summarization or truncation.**|
|**Staff+**|**Three dives with real depth, GPU economics volunteered unasked, prefix caching reached unaided, fairness-across-users kept separate from priority-across-tiers, plus one non-obvious serving choice explained well.**|

---

## Quick Recall (pass 3+)

|Use / Question|ChatGPT answer|
|---|---|
|Calibration|**Evan King · ⭐⭐ May 2026, the NEWEST in your set** · ⭐⭐ **"HARD", fourth in a row** · ⚠ **"Asked at:" EMPTY** · ⭐⭐ **TWO patterns: `03a` + Managing Long Running Tasks** · **five dives, none filler.** ⭐⭐ **TWO passes, order DD2 > DD3 > DD4 > DD1 > DD5.** ⭐ **Most current problem you have — expect it**|
|⭐⭐⭐ Design driver|⭐⭐ **A 30-second unit of work, on a resource you can't buy more of, with a user watching.** **30s + watching ⇒ no sync response (DD1) · the middle instance will vanish ⇒ no pinned stream (DD2) · GPUs fixed and billions ⇒ no "scale horizontally" (DD3) · one tenant starves all ⇒ no flat limit (DD4) · input grows per turn ⇒ no full replay (DD5)**|
|📐 Numbers|**200M+ DAU ⇒ ~20k prompts/sec peak; several seconds each ⇒ ⭐⭐ ~120k streaming at any moment.** **TTFT <500ms · 99.9%+ · up to 30s per answer.** 📐 **Polling: 120k ÷ 300ms = 400k req/sec, nearly all empty.** 📐 ⭐⭐⭐ **~8 GPUs hold one model ⇒ thousands of servers ⇒ tens of thousands of GPUs ⇒ _"hundreds of millions to billions of dollars a year"_; OpenAI ~$1.8B in 2024.** **Context: 50 turns × 500 tokens = ~25k input tokens per turn**|
|Scope|⭐⭐⭐ **_"we treat the LLM as a black box we call… All the design lives in the serving system around it."_** ⭐ **HI names the three interesting parts upfront — stream fast, schedule GPUs, keep cost sane — and they ARE the dives.** **Text in, text out; no editing or branching**|
|FRs / NFRs|**Send a prompt + get a response · view past chats and resume with prior context carried in.** Below: edit/branch · multimodal · sharing · custom GPTs/tools · full-text search. **NFRs: ⭐⭐⭐ TTFT <500ms (_"feels broken if you stare at a blank screen"_) · ⭐⭐ recover an in-flight stream without dropping tokens · availability over consistency · ⭐⭐⭐ GPU-CONSTRAINED scale with fair allocation across free/Plus/Pro.** Below: ⭐ per-token durability (_"we persist the final assistant message, not each chunk"_) · auth/moderation · GDPR · monitoring|
|⭐⭐ Why NFR 4 is the driver|**"GPU-constrained" = you can't buy your way out, so the design must decide WHO gets capacity.** ⭐ **Third flavour of cost-as-constraint: `05u` you COMPUTED it · `05v` it was STIPULATED · here it's PHYSICALLY SCARCE**|
|⭐⭐⭐ The `05v` contradiction, resolved|⚠ **`05v` rejected a queue because _"decoupling costs latency"_ and the user was blocked on `POST /order`.** ⭐⭐ **Here `POST .../messages` also returns fast — it returns `{runId}`; the queue sits BEHIND it and the client watches a separate SSE stream.** ⭐⭐⭐ **So the rule sharpens: a queue is fine when the RESPONSE doesn't wait for the work. Split the acknowledgement from the result and you can queue anything.** ⚠ **Robinhood couldn't — an order confirmation IS the result**|
|Entities + HI's technique|**User (⭐ carries the TIER, _"going to matter a lot once we get to fairness"_) · Chat · Message.** ⭐⭐⭐ **And HI WITHHOLDS the Run on purpose: _"once the deep dives actually need it, since it isn't something you'd naturally reach for this early."_** ▸ ⭐⭐ **Introduce an entity when the design demands it — listing it upfront looks memorised**|
|API|`POST /chats` · `POST /chats/{id}/messages {content}` · `GET /chats?cursor=` · `GET /chats/{id}/messages?cursor=`. ⭐ **Both GETs cursor-paginated — thousands of chats, thousands of messages.** ⭐ **No `userId` anywhere: _"anything the client sends can be forged."_** ⚠⚠ **The messages endpoint is temporary — _"the fix splits this endpoint in two"_**|
|§4 HLD + the two planted bugs|**Client → Gateway (auth, limits) → Chat Service (stateless, owns persistence + orchestrates) → sync HTTP → Inference Service (GPU pool, weights resident, _"no tier in between"_); Postgres as system of record.** ⭐ **HI is honest Postgres is arbitrary: _"almost any database would work here."_** ⭐⭐ **The one decision: _"the chat tier is cheap and stateless, while inference is GPU-bound and expensive"_ ⇒ scale separately.** ⚠⚠ **Two deliberate bugs: fully synchronous ⇒ 30s blank screen · and _"no ADMISSION CONTROL. Nothing decides which requests to accept or turn away when the workers are already full"_**|
|§4.2 context carry-over|**Query prior messages by `chatId` and time → concatenate WITH ROLES → new message → send.** ⭐⭐ **_"The model sees the whole conversation every turn, so it behaves like it remembers."_** ⚠⚠ **Breaks past the context window, and costs more every turn ⇒ DD5**|
|⚠⚠ DD1 Bad — polling|⭐⭐ **TTFT is gated by the interval — a 500ms poll adds 500ms of dead time before the first token can appear.** 📐 **400k req/sec, _"the overwhelming majority… come back empty."_** ⭐ **And lumpy: batches of tokens _"kills the smooth typing illusion that makes the product feel alive."_** ⭐⭐ **_"The fix for all three problems is the same idea, stop asking and let the server push"_**|
|DD1 Good → Great (WS → SSE)|**WebSocket works and bounds TTFT by the model.** ⚠ **But _"during a generation we only ever push one way"_ — you pay for a stateful two-way protocol, an upgrade handshake, per-connection bookkeeping, and _"every load balancer and proxy in the path also has to speak WebSocket."_** ⭐⭐ **SSE: plain HTTP, no upgrade, _"every proxy and load balancer in the path already handles it"_, and ⭐⭐ `EventSource` _"reconnects on its own"_ — which DD2 depends on.** ⭐ **Backend unchanged either way**|
|⭐⭐ Two hops, two transports|⭐ **Worker → Chat Service is server-streaming gRPC.** **Why not request/response: _"it would force the worker to buffer the entire 30-second completion and hand it back in one lump."_** ⭐ **Why gRPC not WebSockets internally: HTTP/2 binary framing + multiplexing, protobuf for a typed contract.** ▸ ⭐⭐ **Candidates pick one protocol for everything; two hops can want two**|
|⭐⭐⭐ The Run entity|⭐⭐⭐ **_"A message is the finished text, while what we're streaming is an ATTEMPT to produce it, and that attempt has a lifecycle of its own"_** — **queued, run, fail halfway, cancelled, retried, all before a message exists.** **`runs: runId · chatId · messageId · status · model · in/out token counts` (⭐⭐ those counts carry DD4).** ⭐⭐⭐ **It reshapes the API: `POST .../messages` returns `{runId}`, client follows `GET /runs/{runId}/stream` — ⭐⭐ a GET because _"the browser's native `EventSource` API only opens GET requests."_** ⭐⭐⭐ **PRIMITIVE: when work can fail halfway, the ATTEMPT needs its own identity, separate from the artefact**|
|⚠⚠ DD2 — the flaw|**One Chat Service instance holds both the SSE connection and the gRPC stream for 30 seconds.** ⚠ **But the tier is _"stateless, horizontally scaled behind a load balancer, and redeployed all day long, which makes that instance disappearing mid-generation ROUTINE"_**|
|DD2 Good — Pub/Sub, and its fatal gap|**Worker publishes to `run:{runId}`; whichever instance holds the SSE subscribes.** ⭐⭐⭐ **DELTAS not snapshots: _"Republishing the cumulative text on every token would be quadratic. A 4,000-token answer would re-send a steadily growing prefix 4,000 times."_** ⚠⚠⚠ **But pub/sub _"delivers a message only to the subscribers connected at the instant it's published, and it buffers nothing"_ ⇒ tokens in the reconnect gap are PERMANENTLY LOST ⇒ _"a hole in the middle of their answer"_**|
|⭐⭐⭐ DD2 Great — Redis Stream|⭐⭐⭐ **An append-only log, entries have IDs. Worker `XADD`s each delta; Chat Service blocking-`XREAD`s from this client's LAST-SEEN ID.** ⭐⭐⭐ **_"replays exactly the entries that were missed during the gap, then continues live. No hole, no waiting until the end."_** ⭐ **`MAXLEN` + short TTL — _"short-lived working state, not a second copy of history."_** ⭐⭐ **And _"the stream is not our system of record"_ — on finish the worker writes the full message to Postgres, which is why per-token durability stays below the line**|
|⭐⭐⭐ Pub/sub vs log — the test|⭐⭐⭐ **Is a delivery gap VISIBLE to the user?** ⚠ **Here: a hole mid-sentence ⇒ you need the LOG.** ✅ **In `05q`: a missed comment was refetched on reconnect and nobody noticed ⇒ pub/sub sufficed.** ▸ ⭐⭐ **Mirror of "a log is not a work queue" (`05i`/`05p`/`05t`): a BROADCAST is not a log**|
|⭐⭐⭐ DD3 — the GPU economics|**A frontier model is too big for one GPU ⇒ weights split across ~8 in a server ⇒ 120k streams means thousands of servers ⇒ tens of thousands of GPUs ⇒ _"easily hundreds of millions to billions of dollars a year."_** ⭐ **Anchor: _"OpenAI's reported inference compute ran around $1.8B in 2024."_** ⭐⭐⭐ **_"When the hardware costs that much, every percentage point of unused capacity is real money."_** ▸ **Staff+ is expected to volunteer this unasked**|
|DD3 Good — a pull queue|⭐ **Pull-based matters: _"a server only takes new work when it can actually do it."_** ⭐⭐ **_"The queue absorbs the spike and lets it drain at whatever pace the workers can sustain, so a surge becomes a few seconds of extra wait instead of a pile of errors."_** ⚠⚠ **Two gaps: UNBOUNDED (a user has _"no idea whether their answer is two seconds away or two minutes"_) and one-request-per-slot wastes the GPU**|
|⭐⭐⭐ DD3 Great — continuous batching|⭐⭐⭐ **Many sequences per worker; _"a single forward pass can generate the next token for every sequence in the batch."_** ⭐⭐ **Continuous: _"When one sequence finishes, the worker removes it and pulls another request from the queue into the newly available slot."_** ⭐⭐ **Plus BACKPRESSURE — bounded depth + admission policy: _"a fast 'we're at capacity, try again' instead of joining an ever-growing backlog."_** ⚠ **Cost: a complex serving layer, and _"a batch of wildly different prompt lengths can still leave some GPU work idle"_**|
|⭐⭐⭐ WHY batching works|⭐⭐⭐ **① One token needs math with EVERY weight — say 100 GB. ② The math only happens in a few MB of on-chip memory, so all 100 GB is shovelled through the compute cores per token. ③ 📐 ~3 TB/s ⇒ ~33ms to MOVE it; the arithmetic takes microseconds ⇒ the GPU is idle waiting on bytes = MEMORY-BANDWIDTH BOUND. ④ So the same 33ms serves 1 sequence or 50 — same hardware, 50× output, because the MOVING was the cost and you already paid it.** ⭐⭐ **⑤ The bus: A→B costs the same with 1 passenger or 50; one forward pass = one trip, each sequence = a passenger. ⑥ CONTINUOUS = don't wait for every passenger to reach their stop (_"a one-line reply can sit next to a 2,000-token essay"_) — drop one, pick up a queued one, bus stays full.** ▹ **vLLM, TGI.** ⭐ **⑦ Hence DD3's queue is PULL-based: a worker pulls when a SEAT opens, not when it's "free"**|
|⚠⚠ DD4 Bad — one global limit|⭐⭐ **It causes the problem it was meant to solve: _"One counter for everyone means the limit has no idea who is asking. A single user hammering the API burns through the global budget, and everyone else starts collecting 429s for traffic they didn't send. That's the starvation problem we came here to solve, now enforced by our own rate limiter"_**|
|DD4 Good — key by `userId`|⭐⭐ **_"The only thing that really changed from the global limit is the key, from one shared bucket to one bucket per user. But that's the change that stops a single heavy user from starving the pool."_** **Per-user concurrency counter in Redis, incr on start, decr on finish/cancel.** ⚠⚠ **Still counts REQUESTS not COST: _"five 50-token replies the same as five 30k-token generations"_**|
|⭐⭐⭐ DD4 Great — token budgets|⭐⭐⭐ **Meter TOKENS, not requests — input known at assembly, output comes down the stream, both recorded on the Run.** ⭐⭐⭐ **And the check MOVES: _"off the API Gateway and into the Chat Service, since the gateway only sees a raw request while the Chat Service is what assembles the prompt and therefore knows what it will cost."_** ⭐⭐⭐ **RESERVE-THEN-REFUND: debit exact input + reserve max output; refund the unused part on finish — _"a run can never cost more than the user could afford when it started, so we never have to kill a stream mid-sentence."_** ⭐⭐ **Then a tier-aware queue: _"the tiers only diverge when capacity is tight, which is when paying customers should feel the difference."_** ⚠ **Costs: throughput bounded by worst case, and ⭐⭐ _"you reserve a FLOOR of capacity for free traffic rather than letting paid traffic fully crowd it out"_**|
|⭐⭐ Keep these two apart|**FAIRNESS ACROSS USERS = cost-aware per-user budgets. PRIORITY ACROSS TIERS = tier-weighted queueing.** ⚠ **HI's Staff+ bar names exactly this separation — conflating them is the trap**|
|DD5 — truncate vs cache+summary|📐 **50 turns × 500 tokens = ~25k input tokens every turn, plus a hard context-window ceiling.** **Truncate = `ORDER BY createdAt DESC LIMIT N`, then flip chronological** ⚠ **but _"abrupt amnesia at turn N+1 is a bad look."_** ⭐⭐⭐ **PREFIX CACHING is the big win: most of the prompt repeats, so the server caches the KV cache for a stable prefix; only the tail changes, and it cuts cost AND latency ⇒ helps TTFT directly.** ⭐ **Pair with routing to a worker where the prefix is warm.** ⚠ **LRU eviction ⇒ _"a conversation that goes quiet and comes back later finds its prefix cold and pays full price."_** ⭐⭐ **ROLLING SUMMARY for the ceiling: `system → summary of old turns → last few verbatim → new message`, updated in the background**|
|⭐⭐⭐ DD5 — the two fixes FIGHT|⚠⚠ **A rolling summary rewrites the start of the prompt; prefix caching needs the start to be STABLE.** ⇒ **_"If we rewrite the summary every turn, we invalidate the cache, so we update it on a SLOWER CADENCE to keep the prefix warm."_** ▸ ⭐⭐ **Say this out loud — it shows you checked whether your own solutions compose.** ⭐ **Principle: _"protect the most recent turns and the most important user context first, and accept some lossiness on old history"_**|
|⭐⭐ Cancellation|**`POST /runs/{runId}/cancel` — ⭐⭐ separate because _"SSE only pushes one way."_** **Chat Service flips the Run to `cancelled` and publishes on a CONTROL CHANNEL keyed by `runId`; the worker checks between token batches and drops the sequence.** ⭐⭐⭐ **And: _"closing the tab is not a cancel… Cancellation has to be an explicit signal from the user, never an accident of the network."_** ▸ ⭐⭐ **The clearest payoff of a first-class Run: a connection and a unit of work are different things**|
|⭐ HI's five extras|**① moderation — classifier in, second pass on the stream; ⚠ _"you've usually already streamed some tokens by the time the check trips"_ ② tensor vs pipeline parallelism; NVLink / InfiniBand _"can become its own bottleneck"_ ③ ⭐⭐ SPECULATIVE DECODING (know it for senior/staff): _"a small cheap 'draft' model can guess the next few tokens and the big model verifies all of them in a single forward pass"_ ④ route simple queries to a smaller model + semantic cache _"keyed off an embedding rather than the exact string"_ ⑤ cross-chat memory is a RETRIEVAL problem, not summarization**|
|⭐⭐⭐ The meta-lesson|⭐⭐⭐ **Three ideas outlive this problem: (1) when work can fail halfway, the ATTEMPT gets its own identity; (2) a queue is fine whenever the RESPONSE doesn't wait for the work; (3) meter the scarce RESOURCE, not the request, and put the meter where the cost is known**|
|Levels (one line)|**E4:** API + data model + working sync HLD, reach for SSE with prompting, propose a queue · **E5:** fast HLD then 2 of {streaming, scheduling, fairness}, justify SSE from the one-way nature, queue + continuous batching, propose summarization · **Staff+:** 3 dives deep, GPU economics unasked, prefix caching unaided, fairness-vs-priority kept separate|

---

> 🔗 **HI source:** https://www.hellointerview.com/learn/system-design/problem-breakdowns/chatgpt