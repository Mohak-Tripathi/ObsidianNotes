# Robinhood — Problem Breakdown

> 📐 **Revision note (calc):** ⚠⚠ **HI gives the inputs and never does the arithmetic — do it yourself, because the answer reframes the problem.** **20M DAU × 5 trades/day = 100M trades/day ÷ 86,400 = ⭐⭐ ~1,160 orders/sec average.** ▸ ⭐⭐⭐ **That is NOT a hard scaling problem** (compare `05u`'s 2M writes/sec). **The hard number is the one HI never states: 1000s of symbols × 20M watchers = the PRICE FAN-OUT.** ⭐ **One popular symbol with 1M watchers ticking 10×/sec is 10M messages/sec for ONE symbol.** **Other figures: <200ms for both price updates and orders · 1000s of symbols.**

> File `05v`. ⚠ **Joseph Antonakakis** — ▹ **not Evan King; the style differs (no Bad/Good/Great labels anywhere, just repeated "Approach / Challenges")** · **published Jul 15, 2024** — ⭐⭐ **"HARD" · **ONE Pattern callout: `Real-time Updates` → `03a`.** Cross-refs: ⭐⭐⭐ **`05q` FB Live Comments — the same pub/sub fan-out, and `05q` has the BETTER answer (see DD1's ⊕)** · ⭐⭐⭐ **`05u` Uber — where the queue WON; here it loses** · ⭐⭐ **partition keys → `01f`** · ⭐ **`05s` Price Tracking — also watching an external price source** · **`05t` Notification (status state machines, cleanup jobs) · `05p` Job Scheduler (sweepers, at-least-once) · `02a` Redis pub/sub + cache · `02g` Postgres partitioning + ACID · `01h` consistency · `01b` API design · `02d` API Gateway · `01i` numbers.**
> 
> **Calibration:** ⭐⭐ **ONE careful pass, not two.** ▸ ⚠ **It's "hard" but nobody is listed as asking it, it's 2+ years old, and it has only THREE dives against `05u`'s six.** ⭐⭐⭐ **But do not skip it — DD2 and DD3 are two of the most transferable ideas in your whole set, and the order-path ladder inverts a lesson your last four files taught you.** ⭐ **Priority: the §4.2 ladder > DD3 > DD2 > DD1.**
> 
> - ⭐⭐ **What actually scores:** **(a)** ⭐⭐⭐ **rejecting the QUEUE in the order path for the right reason** (§4.2 — the headline) · **(b)** ⭐⭐⭐ **spotting that the trade feed arrives keyed by `externalOrderId` while your table is partitioned by `userId`** (DD2) · **(c)** ⭐⭐⭐ **writing `pending` BEFORE calling the exchange, and saying why** (DD3) · **(d)** ⭐⭐ **naming `clientOrderId` as what makes a non-idempotent remote call recoverable** · **(e)** ⭐⭐ **clarifying the external API's shape before designing** · **(f)** ⭐ **doing the 1,160/sec arithmetic HI skipped, and saying which number is actually hard.**
> - ⭐ **Transferable primitives:**
>     - ⭐⭐⭐ **A queue decouples, and decoupling costs latency. If the user is staring at the response, you cannot decouple.** ▸ **Volume doesn't decide whether to queue — WHO IS WAITING does.**
>     - ⭐⭐⭐ **The partition key you chose for READS can be useless for writes arriving from outside.** ▸ **External events keyed differently need a lookup table from their key to your location.**
>     - ⭐⭐⭐ **Write your INTENT before you act, so a crash leaves a record of what you were trying to do** — ▸ **then a sweeper reconciles intents against reality.**
>     - ⭐⭐⭐ **Send your own ID with a remote call you can't retry blindly.** ▸ **"Did my write land?" becomes a question you can ASK instead of guess.**
>     - ⭐⭐ **When handed an external API, pin down sync-vs-async and push-vs-pull first** — ▸ **those two facts decide the architecture before you draw anything.**
>     - ⭐⭐ **A cost or contract constraint can be an NFR in its own right.**
> - ⭐ **Re-run (cross-ref, NOT re-explained):** **pub/sub fan-out (`05q`)** · **SSE vs WebSockets (`03a`)** · **sweeper jobs + at-least-once (`05p`, `05t`)** · **relational partitioning (`01f`)** · **don't trust a client `userId` (`05u §3`)**. **Genuinely new:** ⭐⭐⭐ **the queue REJECTED on latency grounds** · ⭐⭐⭐ **the external-key → partition-key lookup table** · ⭐⭐⭐ **intent-first writes with a reconciler** · ⭐⭐ **`clientOrderId` as a recovery handle on a third party** · ⭐⭐ **a NAT gateway as an architectural component** · ⭐⭐ **"clarify the external API first"** · ⭐ **`priceInCents`** · ⭐ **broker, not exchange.**

---

## 0 · Understanding the problem

📈 **What is Robinhood?** ⭐ **A commission-free trading platform for stocks, ETFs, options and crypto, with real-time market data and basic order management.**

⭐⭐⭐ **The sentence that defines the scope — HI is emphatic about it twice:** **_"Robinhood isn't an exchange in its own right, but rather a stock broker; it routes trades through market makers ('exchanges') and is compensated by those exchanges via payment for order flow."_** ⇒ **_"We are not building an exchange."_**

**Terms you need:**

- **Symbol** — the abbreviation identifying a stock (`META`, `AAPL`). Also called a **ticker**.
- **Order** — a buy or sell. Either a market order or a limit order.
- ⭐ **Market order** — **immediate** purchase/sale at the current price. **No price target**, just a share count.
- ⭐⭐ **Limit order** — at a **specified price**. Share count + target price, and ▸ **it can SIT on the exchange waiting to be filled or cancelled.** ⭐ **That "sitting" is what creates all the state management in this problem.**

> ⭐⭐⭐ **The external API, and HI's advice about it — this is new in your set and the most transferable thing in §0.**
> 
> **The interviewer HANDS you the exchange. Assume it offers exactly two things:**
> 
> - ⭐⭐ **Order Processing — _"Synchronously places orders and cancels orders via request/response API."_**
>     
> - ⭐⭐ **Trade Feed — _"Offers subscribing to a trade feed for symbols. 'Pushes' data to the client every time a trade occurs, including the symbol, price per share, number of shares, and the `orderId`."_**
>     
> - ⭐⭐⭐ **HI's instruction: _"it's in your best interest to briefly clarify the exchange interface (APIs, both synchronous and asynchronous) so you have an idea of the tools at your disposal. Typically, the assumptions you make about the interface have broad consequences in your design, so it's a good idea to align with the interviewer on the details."_**
>     
> - ⭐⭐⭐ **Why it matters here concretely: orders are SYNCHRONOUS (so you get an ID back immediately — which is what makes DD3's workflow possible) and the trade feed is PUSH (so you need a receiving fleet, not a poller).** ▸ **Change either fact and the whole design changes.**
>     
> 
> ■ **— end of insert · HI write-up resumes below —**

---

## 1 · Requirements

### 1.1 Functional (what it does)

1. ⭐ **Users can see live prices of stocks.**
2. ⭐⭐ **Users can manage orders for stocks** — **market/limit, create/cancel.**

⚠ **Below the line (out of scope):**

- **Users can trade outside of market hours.**
- **Users can trade ETFs, options, crypto.**
- ⭐ **Users can see the order book in real time.**

▹ ⭐ **HI's scoping note: this question is _"stock viewing and ordering"_ — it _"excludes advanced trading behaviors and doesn't primarily involve viewing historical stock or portfolio data."_** ⭐ **And for a feature-rich app generally: _"have some brief back and forth with the interviewer to figure out what part of the system they care the most about."_**

### 1.2 Non-functional (how it behaves)

1. ⭐⭐ **High consistency for order management** — **_"it's essential for users to see up-to-date order information when making trades."_**
2. ⭐ **Scale to a high number of trades per day** — **20M DAU, 5 trades/day average, 1000s of symbols.**
3. ⭐⭐ **Low latency on BOTH price updates and order placement — under 200ms.**
4. ⭐⭐⭐ **Minimise the number of active clients connecting to the external exchange API** — **_"Exchange data feeds / client connections are typically expensive."_**

⚠ **Below the line (out of scope):**

- **The system connects to multiple exchanges for stock trading.**
- **The system manages trading fees / calculations** (**_"we can assume fees are not in scope"_**).
- **The system enforces daily limits on trading behavior.**
- **The system protects against bot usage.**

▸ ⭐⭐ **NFR 4 is the unusual one and it's the real constraint: not latency, not throughput, but COST / CONTRACT — and it single-handedly kills the first design in §4.2.** ▹ ⭐ **Second cost-driven constraint in two files, different kind: `05u`'s $200k/day you COMPUTED; this one is STIPULATED.** ⭐ **Neither can be answered with "we'll scale horizontally," which is why both beat a QPS figure.**

▹ ⭐ **HI on why the NFRs carry this problem: _"given the small number of functional requirements, the non-functional requirements are even more important to pin down. They characterize the complexity of these deceptively simple live price / order placement capabilities."_**

### 1.3 ⭐⭐⭐ The design driver — two paths with opposite needs, through one expensive dependency

||⭐⭐ **Price path**|⭐⭐ **Order path**|
|---|---|---|
|**Volume**|⚠⚠ **huge fan-out — 1000s of symbols × 20M watchers**|⭐ **small — ~1,160/sec**|
|**Who waits**|**nobody; it's a push**|⚠⚠ **the user, staring at a confirmation**|
|**Staleness**|✅ **a 50ms-old price is fine**|⚠⚠ **unacceptable — the order either exists or it doesn't**|
|**Direction**|**server → client, one way**|**request → response**|
|**Wants**|**pub/sub · cache · SSE**|⭐⭐ **synchronous · ACID · NO QUEUE**|

- ⭐⭐⭐ **And here's the counterintuitive consequence that makes this file worth reading:** **the HIGH-volume path gets the queue-like machinery (pub/sub), and the LOW-volume path gets the direct synchronous call.** ▸ ⭐⭐⭐ **Volume did not decide the architecture. WHO IS WAITING did.**
- ⭐⭐ **NFR 4 constrains BOTH paths, which is why each one gets its own proxy tier:** **Symbol Price Processor** holds the one feed subscription; **Order Dispatch Gateway** consolidates outbound order traffic.

### 1.4 Planning the approach

▸ **Sequentially through the FRs, then let the NFRs drive the dives.** ▹ **Same boilerplate as every other file.**

---

## 2 · Core Entities

- **User** — a user of the system.
- **Symbol** — a stock being traded.
- **Order** — a buy or sell, created by a user.

▹ ⭐ **HI keeps this deliberately thin: _"In the actual interview, this can be as simple as a short list like this."_** ⭐ **The Order's real shape arrives in §4.2, and the state enum is the interesting part.**

---

## 3 · API

```
GET    /symbol/:name  -> Symbol               details + price data
POST   /order         -> Order                { position, symbol, priceInCents, numShares }
DELETE /order/:id     -> { ok: true }
GET    /orders        -> Order[]              paginated
```

- ⭐⭐ **`priceInCents`, not `price`** — **_"to avoid floating point precision issues. Especially for financial application it's better to use integers to avoid errors and financial scams."_**
- ⭐ **Auth: a session token or JWT in the headers.** **_"We shouldn't trust a `userId` from the headers or request body for that, since the client can change either one."_** ▹ **Same rule as `05u §3`.**
- ⚠ **FR 2 says _"market / limit orders"_ but there's no `orderType` field** — ⭐ **add `orderType: "market" | "limit"` (and `priceInCents` is absent for a market order). We just pass the type through to the exchange; when it executes, the trade processor handles the update identically either way** — ▸ ⭐⭐ **so market-vs-limit costs one field and nothing architecturally.**
- ⭐⭐ **And a limit order is NOT scheduling — the EXCHANGE holds it in its order book, for free.** ▸ ⚠ **Real scheduling is below the line (_"Users can trade outside of market hours"_), and that's no accident: there, YOU would have to hold the order until market open, which is a `05p`-shaped feature of its own.**

⚠ **These four are HI's §3, but they're not the final API.** ⭐⭐ **§4.1's Great rung REPLACES the price endpoint: _"re-working our API to instead have a `/subscribe` GET request, with query parameters containing the symbols we want to subscribe to."_** ▸ ⭐ **So `GET /symbol/:name` is a casualty of choosing SSE — worth saying out loud, since an API that survives your own deep dives untouched usually means you haven't gone deep enough.**

---

## 4 · High-Level Design

### 4.1) Users can see live prices of stocks

⭐ **Design for MANY symbols at once from the start** — **_"This might be one stock or many stocks, depending on what the user is viewing in the UI. To keep our design extensible, let's assume a user can see many live stock prices at once."_**

⚠ **Rung labels are mine — HI uses none.**

#### ⚠⚠ Bad — the client polls the exchange directly, per symbol

- **Approach: the client polls every few seconds per symbol and updates what the user sees from the response.**
- ⚠ **_"will not scale and will not minimize exchange client connections / calls."_** **Two fundamental problems:**
    - ⚠⚠ **Redundant exchange calls.** ⭐⭐⭐ **HI's framing is the one to keep: _"If 5000 clients are requesting a price at the same time, the price isn't different per client, yet we're expending 5000 calls (repeatedly) to disperse this information."_** ▸ ⭐ **Plus polling _"happens indiscriminately, even if the price has not changed."_**
    - ⚠⚠ **Slow updates, and the argument is arithmetic:** **the 200ms SLA means _"the only way we'd guarantee that with this solution is if we poll data every 200ms, which is unreasonable."_** ▸ ⭐⭐⭐ **With polling, the interval IS your SLA. You cannot promise latency shorter than how often you ask.**
- ⇒ **_"we can rule out polling the exchange directly as a viable option."_**

**Why climb:** 5000 clients want the same number, so fetch it once and share it.

#### Good — poll an internal cache instead

- ⭐⭐ **Approach: still polling, but polling YOUR Symbol Service, which does a key-value lookup on an internal cache _"that is kept up-to-date by a symbol price processor that is listening to prices on the exchange."_**
- ⭐⭐⭐ **What this buys — and it's the whole NFR 4 move:** **_"This approach prevents excess connections to the exchange by 'proxying' it with a service that listens and records the most essential detail: the symbol price."_** ▸ **One subscription for the whole system, instead of one per client.**
- ⚠ **Challenges — polling's two costs survive:** **_"Clients still indiscriminately poll, even if the price has not changed, leading to some wasted HTTP traffic."_** ⚠⚠ **And: _"the polling interval dictates the worst-case SLA for a price update propagating to the client. Can we do better?"_**

**Why climb:** you fixed the exchange side and left the client side untouched. The SLA is still hostage to the interval.

#### ⭐⭐ Great — Server-Sent Events

- ⭐⭐⭐ **HI DOES justify the choice, and this is the sentence:** **_"SSE is a persistent connection (similar to websockets), but it is unidirectional and goes over HTTP instead of a separate protocol. For this example, the client isn't sending us data, so SSE is a superior choice to websockets."_** ▹ ⭐ **And he points at his own FB Live Comments write-up (= `05q`) for the full trade-off analysis.**
- ⭐⭐ **It changes the API:** **_"re-working our API to instead have a `/subscribe` GET request, with query parameters containing the symbols we want to subscribe to."_**
- ⭐⭐ **Then the two-stage read: _"send the client an initial list of symbol prices. This initial list of prices is serviced by a CACHE that is kept up-to-date by a processor that is listening to the exchange."_** ▸ **After that, the processor pushes prices to the Symbol Service, which forwards them to subscribers.** ⭐ **Without that initial read a new subscriber sees a blank screen until the next tick — minutes, for an illiquid stock.**
- ⚠⚠ **Three challenges, and the first is the one candidates forget:**
    - ⭐⭐⭐ **_"The load balancer will need to be configured to support 'sticky sessions' so that a user and server can maintain a connection."_** ▸ **A persistent connection means the LB can no longer spread requests freely — ⭐ a cost that follows from SSE, not a detail.**
    - ⭐ **_"a persistent connection means we have to consider how disconnects / reconnects work."_**
    - ⭐⭐ **_"we need to consider how we route user connections and symbol data."_** ▸ **HI defers both to the deep dives — ⚠ and DD1 only answers the SECOND half. See its ⊕.**

```
Client ──/subscribe?symbols=[…]──► API Gateway ──► Symbol Service ──SSE──► Client
                                   auth · routing     │  ⚠ needs STICKY SESSIONS
                                                      │
                                                      ├──► Symbol Cache
                                                      │      key:   symbol
                                                      │      value: details + current price
                                                      │      ⭐ INITIAL prices on subscribe
                                                      │            ▲ updates
                                                      └── Symbol Price Processor ◄──subscribe()── Exchange
                                                             ⭐⭐ the ONE feed subscription          (trade feed)
                                                                for the whole system = NFR 4
```

> ⭐ **Pattern: Real-time Updates** (`03a`) — **the only callout in this file.** ⭐ **HI's own gloss: SSE gives _"persistent connections that allow our servers to push live price changes to clients instantly… without the inefficiency of constant polling."_** ▸ **Go to `03a` for the full ladder.**
> 
> ■ **— end of insert · HI write-up resumes below —**

> ⚠⚠ **Confusion resolved — nothing polls the exchange, and why there are four boxes rather than one.**
> 
> - ⭐⭐ **No polling anywhere: the trade feed PUSHES (§0), so the processor _"listens"_ and never asks.** **Path: trade ⇒ exchange pushes ⇒ processor ⇒ cache + Redis ⇒ Symbol Service ⇒ SSE ⇒ client.** ⭐⭐⭐ **Zero intervals, which is what makes <200ms possible.** ⚠ **But push ≠ instant: four hops, and 200ms is a budget across them.**
> - ⭐⭐⭐ **So what the GOOD rung actually fixes is NOT latency.** ▸ **The exchange leg became push the moment the processor existed; the Good rung only removes the 5000 redundant CALLS (NFR 4).** **The latency problem survives into the Great rung — hence _"Can we do better?"_**
> - ⭐⭐⭐ **Why the CACHE: a stream gives you DELTAS, a new subscriber needs the BASELINE.** ▸ **Subscribe to an illiquid stock and the next trade may be ten minutes away — without the cache the screen is blank.** ⭐ **Snapshot for state + stream for change, same as `05q`'s CDN snapshot. Never one component.**
> - ⭐⭐⭐ **Why TWO services: they scale in opposite directions.** **20M SSE connections ⇒ hundreds of Symbol Service instances. Merge the roles and each one opens its own exchange connection ⇒ ~400 exchange clients ⇒ the Bad rung again.** ▸ ⭐ **The split decouples "users served" from "connections the exchange sees."** ▹ **At 10k users you'd collapse them — it's a scale decision, not correctness. The cache isn't.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 4.2) ⭐⭐⭐ Users can manage orders for stocks

⚠ **Rung labels are mine — HI uses no labels at all in this write-up, just "Approach / Challenges" three times over.**

#### ⚠⚠ Bad — the client talks to the exchange directly

- **Approach: orders issued by the client go straight to the exchange.**
- ✅ **The one thing in its favour: _"a 'mainline' way to submit orders that cuts out any incurred latency from a backend proxying the exchange."_**
- ⚠ **Three problems:**
    - ⚠⚠ **_"it can lead to large number of exchange clients and concurrent requests, which will be very expensive"_** ⇒ ⭐⭐ **straight through NFR 4.**
    - ⚠⚠ **No way to check an order's status** — **_"outside of polling the exchange or directly listening to trade feeds, both of which aren't viable."_**
    - ⚠⚠ **_"the client is exclusively responsible for tracking orders… we can't consider the client's storage to be reliable; the user might uninstall the app or the phone hardware might fail."_** ▸ ⭐⭐ **Good concrete phrasing for why client storage is never the system of record.**

**Why climb:** you need a tier of your own between the user and the exchange — for cost, for status, and for durability.

#### ⚠ Good — order service → QUEUE → order dispatch service

- **Approach: the Order Service enqueues; an Order Dispatch Service dequeues and talks to the exchange.**
- ✅ **Two real wins:** ⭐ **it proxies the exchange (NFR 4 satisfied), and _"the queue prevents the dispatch service from being overloaded, and the queue volume can serve as a metric that the dispatch service could elastically scale off of."_**
- ⚠⚠⚠ **And then it fails on the SLA, which is the whole point of this rung:**

> ⭐⭐⭐ **Confusion resolved — why the QUEUE loses here, when it won in `05u`, `05t` and `05p`.**
> 
> - ⚠⚠ **HI's reason: _"this approach breaks down when we consider our tight order SLA (under 200ms as a goal)… orders might take a while to be dispatched to the exchange… Imagine a user who wants to quickly order stocks or quickly cancel an outstanding order. It would be unacceptable for them to be left waiting for our dispatcher to eventually handle their order, or for our service to start more machines up to scale up given increased queue load."_**
> - ⭐⭐⭐ **The principle: a queue DECOUPLES, and decoupling costs latency. If the user is holding the connection open waiting for the answer, you cannot decouple.**
> - ⭐⭐ **Why `05u §5.4` could queue and this can't:** **there the rider is told _"finding you a driver"_ and matching happens behind that screen — nobody is blocked on a response.** ⚠ **Here, `POST /order` returns a confirmation the user is looking at.**
> - ⭐⭐⭐ **So the deciding question is never "is the volume high?" It's "is anyone blocked on the reply?"** ▸ ⭐ **Scaling-on-queue-depth is also a trap at the moment of a spike: the queue grows FASTEST exactly when the new instances haven't booted yet.**
> 
> ■ **— end of insert · HI write-up resumes below —**

**Why climb:** keep the proxy, drop the queue.

#### ⭐⭐ Great — order service → NAT gateway → exchange, synchronously

- ⭐⭐ **Approach: the Order Service calls the exchange directly, through an Order Dispatch GATEWAY.** **_"The gateway would make the requests to the exchange appear as if they were originating from a small set of IPs."_** ⭐ **Concretely: _"our gateway would be an AWS NAT gateway"_ with elastic IPs.**
- ⭐⭐ **The trade-off this forces: the Order Service now carries the business logic AND the exchange conversation.** **_"it will need to be written in a way that is both efficient for client interaction and efficient for exchange interaction (e.g. potentially batching orders together)."_**
- ⭐⭐ **And because there's no queue to absorb spikes, scaling has to be pre-emptive:** **_"we might make the auto-scaling criterion for this service quite sensitive (e.g. auto-scale when average 50% CPU usage is hit across the fleet) or we might over-provision this service to absorb trading spikes."_** ▸ ⭐⭐ **Over-provisioning is a legitimate answer when the alternative adds latency to a blocking path. Say it out loud rather than apologising for it.**

> ⊕ ⚠ **(mine, not HI) — the NAT gateway fixes IP COUNT, not CONNECTION count.**
> 
> - **NFR 4 says minimise _"active clients"_ and notes _"client connections are typically expensive."_** ⚠ **A NAT gateway consolidates your outbound IPs — so the exchange sees a handful of addresses instead of hundreds. That solves allowlisting and client identity.**
> - ⚠⚠ **But each Order Service instance still opens its own TCP connections through that gateway.** ▸ **If the exchange prices or limits by CONNECTION, NAT alone doesn't help.**
> - ⭐⭐ **HI's own challenge note hints at the real fix without connecting it: _"potentially batching orders together."_** ▸ ⭐ **That, or a small pool of long-lived connections the instances share, is what actually reduces connection count.** ⭐⭐ **Worth saying — it shows you read the NFR precisely rather than reaching for the first AWS component.**
> 
> ■ **— end of insert · HI write-up resumes below —**

#### Storing orders on our side

⭐⭐ **Now that dispatch is settled, `GET /orders` needs a store:**

- ⭐⭐ **A RELATIONAL database** — **_"to promote consistency via ACID guarantees"_** — ⭐⭐ **horizontally partitioned on `userId`.** ▸ **_"This will make querying orders of a user fast, as the query will go to a single node."_**
- ⭐ **The Order carries an `externalOrderId`** — **_"populated by the ID that the exchange responds with when the order service submits the order synchronously."_**
- ⭐ **Plus a TRADE PROCESSOR** — **_"tailing the exchange's trades to see if orders maintained on our side get updated."_**

```
Order
  orderId · userId · externalOrderId · symbol · shares · price
  state: pending | submitted | filled | partially_filled
         | pending_cancel | cancelled | failed
  … (execution data)
```

- ⭐⭐⭐ **Read that enum as two kinds of thing: INTENTS (`pending`, `pending_cancel`) and OUTCOMES (`submitted`, `filled`, `cancelled`, `failed`).** ▸ **DD3 is entirely about getting from the first kind to the second without losing track.**
- ⚠ **`partially_filled` is listed and then never discussed anywhere in the write-up.** ▸ ⭐ **A 100-share limit order that fills 30 is an ordinary case, and it means the trade processor must ACCUMULATE fills against one order rather than flipping a status. Real gap — be ready for it as a follow-up.**

▹ ⭐ **On the trade processor's shape, HI is honest that he's hand-waving:** **_"a client of the exchange like Robinhood would setup a webhook endpoint and register that with the exchange… the trade processor would have a load balancer and a fleet of machines serving that webhook endpoint. For the sake of simplicity, we visualize the trade processor as a single square."_**

---

## 5 · Deep Dives

### 1) How can the system scale up live price updates?

⭐⭐ **The question stated precisely — worth copying the phrasing:** **_"how do we route symbol price updates to the symbol service servers connected to users who care about those symbol updates?"_**

⭐ **Answer: Redis pub/sub, one channel per symbol, with the Symbol Service tracking `Symbol → Set<userId>`.**

**The four-step workflow:**

1. **A user subscribes via a Symbol Service server. The server adds them to `Symbol → Set<userId>` for each symbol.**
2. ⭐ **The server checks whether IT has a Redis subscription for that symbol. If not, it subscribes to that symbol's channel.**
3. ⭐⭐ **A price change reaches the Symbol Price Processor, which PUBLISHES to Redis. Every server subscribed to that channel receives it and fans out over SSE to its own users.**
4. ⭐⭐ **On unsubscribe or disconnect (_"detected via some heartbeat mechanism"_), the server removes the user from each set.** ⭐ **If a symbol has no users left on that server, it UNSUBSCRIBES from the channel.**

✅ **HI's claim: _"it would be self-regulating in managing what price updates are being propagated to symbol service servers."_**

> ⊕ ⚠⚠ **(mine, not HI) — `05q` solved this exact problem better, and this write-up never addresses the gap.**
> 
> - ⚠⚠ **Users land on ANY Symbol Service server. So 1M `AAPL` watchers spread across 100 servers ⇒ all 100 subscribe to the `AAPL` channel ⇒ every tick is delivered 100 times.** ▸ **"Self-regulating" is true per SYMBOL (nobody subscribes to what nobody watches), not per SERVER.**
> - ⭐⭐⭐ **Exactly what `05q §5.2` fixed: partitioning channels alone changes nothing; you need Layer 7 routing with consistent hashing so co-watchers land on the same server.** ▸ **Then a tick goes to one or two servers, not a hundred.**
> - ⚠⚠ **And HI has no excuse here, which makes this a stronger catch than it first looks:** **§4.1 CITES the FB Live Comments write-up by name, and §4.1's own challenge list promises _"we need to consider how we route USER CONNECTIONS and symbol data"_ with _"several of these details are covered later in our deep dive sections."_** ▸ ⚠⚠ **DD1 then answers only the SYMBOL-DATA half (pub/sub) and silently drops the USER-CONNECTION half.** ⭐ **He raised it himself and never came back to it.**
> - ⭐⭐ **Say: _"he flagged user-connection routing in the HLD — I'd close it by routing subscribers by symbol at Layer 7, so a symbol's fan-out isn't duplicated across the fleet."_** ▹ ⭐ **And be fair — with only 1000s of symbols, pub/sub is cheap and it may not matter. A trade-off, not a bug.**
> 
> ■ **— end of insert · HI write-up resumes below —**

> ⊕ ⭐ **(mine, not HI) — the throttling gap, which HI only lists at the end.**
> 
> ⚠ **DD1 never handles a stock ticking hundreds of times a second.** ⭐⭐ **Fix: COALESCE rather than forward — send the latest price every N ms, not every tick.** ▸ **A price is a STATE, not an event: the client only wants the newest, so a dropped intermediate costs nothing.** ⭐ **Same reasoning as `05k`'s periodic aggregation.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 2) ⭐⭐⭐ How does the system track order updates?

⭐⭐⭐ **This dive is one structural insight, and it generalises far beyond trading.**

> ⚠ **Confusion resolved — HI says "partitioned", but it is SHARDING: separate machines, not one instance with a partitioned table.** ▸ **His own words give it away — _"the query will go to a single NODE"_ and _"go to SHARD via `userId`."_** ⭐⭐⭐ **It matters because the whole dive only exists under sharding: in one database you'd just add a secondary index on `externalOrderId` and be done. You can't build an index that spans machines — so the KV store IS that hand-built index.** ■

⚠⚠ **The problem:** **the trade feed arrives carrying `externalOrderId`. Your Order table is sharded by `userId`.** ⇒ **_"There's no efficient way for the trade processor to look-up a trade via the `externalOrderId` to update a row in the Order table, given that the table is partitioned by `userId`."_** ▸ ⭐ **You'd have to scatter-gather every shard for every trade.**

- ⭐⭐⭐ **The fix: a separate key-value store mapping `externalOrderId → (orderId, userId)`.** ⭐ **HI suggests RocksDB.** **Populated by the Order Service right after the synchronous submission.**
- ⭐⭐ **What it buys, in HI's words: it lets the trade processor _"quickly determine whether the trade involved an order from our system, and subsequently look up the order (go to shard via `userId` → look up Order via `orderId`)."_** ▸ ⭐ **Note it does double duty — it's both a FILTER (is this trade even ours? most aren't) and a ROUTER (which shard?).**

> ⭐⭐⭐ **The generalisable lesson — the sentence to carry out of the file.**
> 
> **The partition key you chose for READS can be useless for writes arriving from OUTSIDE.**
> 
> - ⭐⭐ **`userId` was right for `GET /orders`.** ⚠ **But external events don't know your `userId` — only the ID they gave you.**
> - ⭐⭐⭐ **So whenever an external system will call you back, ask: what key will they use, and can I find the row with it?** ▸ **If not, build an index from their key to your location, at the moment you learn it.**
> - ▹ ⭐ **NOT the outbox pattern: outbox publishes YOUR events; this receives THEIRS.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 3) ⭐⭐⭐ How does the system manage order consistency?

⭐ **HI's definition: _"orders being stored with consistency on our side and also consistently managed on the exchange side."_** ⭐⭐ **And the framing that follows: _"fault-tolerance is important for maintaining order consistency."_** ▸ **Consistency here is not a database setting — it's a question of what survives a crash halfway through.**

▹ **Storage recap: a horizontally partitioned relational DB (e.g. Postgres); all order reads AND writes for a user hit a single node, since it's partitioned by `userId`.**

#### ⭐⭐ The CREATE flow

1. ⭐⭐⭐ **Store the order as `pending` FIRST.** ▸ **HI's reason is the key sentence in the dive: _"If we didn't store this first, then the client could create an order on the exchange, the system could fail, and then our system has no way of knowing there's an outstanding order."_**
2. **Submit to the exchange. Get `externalOrderId` back immediately** (⭐ **because the API is synchronous — see §0**).
3. **Write `externalOrderId` to the KV store; update the order to `submitted`.**
4. **Respond success to the client.**

**The three failure points, and the handling of each:**

|Fails at|What you do|
|---|---|
|**1 — storing**|✅ **respond failure, stop. Nothing happened anywhere.**|
|**2 — submitting**|✅ **mark the order `failed`, respond.**|
|⚠⚠ **3 — after submission**|⚠⚠ **The dangerous one: the order IS live on the exchange and you don't know its ID.**|

> ⭐⭐⭐ **Confusion resolved — how failure 3 gets fixed, and why `clientOrderId` is the whole trick.**
> 
> - ⚠⚠ **The order exists on the exchange. Your row says `pending`. You cannot retry (you'd double-order) and you cannot give up (the order is real).**
> - ⭐⭐⭐ **HI's fix: a CLEAN-UP JOB that scans `pending` orders and asks the exchange. And the thing that makes asking possible: _"Most exchange APIs offer a `clientOrderId` metadata field when submitting an order (see E*TRADE example)"_** ⇒ **the job queries by that and either ① records the `externalOrderId` if it went through, or ② marks the order `failed` if it didn't.**
> - ⭐⭐⭐ **`clientOrderId` is an IDEMPOTENCY KEY, and HI never calls it that.** ▸ **You generate an ID, send it with the request, and can afterwards ASK "did you see this?" instead of GUESSING.**
> - ⭐⭐ **The transferable version: before any remote call you can't safely retry, attach your own identifier.** ▸ **It turns an unanswerable question into a lookup.**
> 
> ■ **— end of insert · HI write-up resumes below —**

#### The CANCEL flow — the same shape

1. ⭐ **Update status to `pending_cancel` FIRST** — **_"We do this first to enable resolving failed cancels later."_**
2. **Submit the cancellation to the exchange.**
3. **Record the cancellation.**
4. **Respond success.**

**Failures:** **fail at 1 ⇒ respond failure, stop.** **Fail at 2 or 3 ⇒ respond failure and let the clean-up job scan `pending_cancel` orders.** ⭐⭐ **And note HI's phrasing on the last one: _"or no-op and just update status to `cancelled` if they have already been cancelled."_** ▸ ⭐⭐ **That's an IDEMPOTENT sweeper — running it twice is harmless, which is what makes it safe to run on a schedule.**

> ⭐⭐⭐ **The one pattern underneath both flows: WRITE YOUR INTENT BEFORE YOU ACT.**
> 
> - ⭐⭐ **`pending` and `pending_cancel` are not progress indicators — they're records of what you were ABOUT to do.** ▸ **A crash then leaves evidence instead of silence.**
> - ⭐⭐⭐ **And an intent is only safe if something eventually reconciles it.** ▸ ⚠ **An intent with no sweeper is just a stuck row.**
> - ⭐ **HI's deliverable here isn't the workflow, it's the DISCOVERY: _"identified the need for a 'clean-up' background process to ensure our order state becomes consistent in the face of failures."_** ▹ **Same family as `05t`'s dedupe key and `05p`'s sweeper — the difference is you're reconciling against a THIRD PARTY you don't control.**
> 
> ■ **— end of insert · HI write-up resumes below —**

> ⚠⚠ **Confusion resolved — `externalOrderId` means ACCEPTED, not FILLED.** 💬 **(confirmed with the HI Tutor.)**
> 
> ```
> Order Service ──► Exchange          ⇒ externalOrderId = ext_123
> DB: order_1  status = submitted · externalOrderId = ext_123
> 
> …hours later…
> Exchange trade feed ──► Trade Processor:  "ext_123 filled 3 shares"
> Trade Processor ──► update order_1 status + filled quantity
> ```
> 
> - ⭐⭐⭐ **An ID back means the exchange REGISTERED the order. A limit order then _"can SIT on an exchange waiting to be filled or cancelled"_ (§0) — for minutes, or never.** ⇒ **`submitted` = "the exchange has it"; `filled` = "it executed", and only the TRADE PROCESSOR can tell you the second.** ▹ ⭐ **Market order: the two events are milliseconds apart. Limit order: days, or never. Same code path, different timescales.**
> - ⚠ **So step 4's _"successful"_ means SUBMITTED TO THE EXCHANGE, not filled — and HI never says so.** ⚠⚠ **The fill can't arrive on that HTTP response; it's long gone.** ⭐⭐ **The client learns it later via `GET /orders`, or a live order update pushed over SSE (HI's extra dive #3).** ▸ **Two channels, two meanings.**
> - ⭐ **Note the trace says "filled 3 SHARES" — that's `partially_filled`, so the processor ACCUMULATES fills rather than flipping a status.**
> - ⚠ **Failure splits three ways: REJECTED at submission ⇒ `failed`, told synchronously · NEVER FILLS ⇒ not a failure, it just stays `submitted` · ⚠ EXCHANGE REJECTS OR CANCELS IT LATER (a day order at market close) ⇒ the trade processor updates the state — the Tutor confirms this, but HI's write-up has no path for it.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### ⭐ HI's four suggested extra dives

▸ **Any of these is a plausible follow-up:**

1. ⭐⭐ **Excess price updates** ⇒ **throttle/coalesce.** ▹ **DD1's ⊕ above.**
2. ⭐⭐ **Limiting exchange correspondence** ⇒ **_"batching orders into single requests."_** ▹ **The real NFR-4 answer, per §4.2's ⊕.**
3. ⭐ **Live ORDER updates** — **so _"they see their orders get filled in real time."_** ▸ ⭐ **The machinery already exists: the trade processor knows and SSE is open. Same pub/sub shape, keyed by `userId` instead of symbol.**
4. ⭐ **Historical price / portfolio value _"over different time windows"_** — **a different storage question (time-series, pre-aggregated buckets).**

---

## 6 · Final Design

⚠ **Layout and arrows are mine; components and field lists are HI's.**

```
Client
  │  /subscribe?symbols=[…] ──────────────────┐  ⭐ replaces GET /symbol/:name
  │  POST + DELETE /order                     │
  │  GET /orders                              │
  ▼                                           │
API Gateway & Load Balancer — routing · auth · rate limiting          02d
  │                                           │
  ├──► Symbol Service ◄───────────────────────┘
  │      tracks: Symbol -> Set<userId>
  │      ──SSE──► Client   (price updates)                            03a
  │      │                 ⭐ server→client only, so SSE not WebSockets
  │      │
  │      ├──► Symbol Cache — key: symbol, value: details + price      02a
  │      │      ⭐ serves INITIAL prices on subscribe
  │      │
  │      └──► Redis pub/sub — one channel per symbol                  02a
  │             ⭐ a server unsubscribes once no user needs a symbol
  │             ⊕⚠ any user → any server, so 100 servers watching
  │                AAPL each get every tick. 05q fixed this with
  │                Layer 7 consistent-hash routing. HI doesn't.
  │                      ▲ publish
  │             Symbol Price Processor ◄──subscribe()── EXCHANGE
  │               ⭐⭐ the ONLY feed subscription in the system = NFR 4
  │
  └──► Order Service  ⚠ no queue in front — see below
         │            ⭐ sensitive autoscale (~50% CPU) or over-provision
         │
         ├──► Order Dispatch Gateway ──createOrder()──► EXCHANGE
         │      ⭐ AWS NAT gateway, elastic IPs ⇒ few IPs      = NFR 4
         │      ⊕⚠ fixes IP COUNT, not connection count
         │      ⭐⭐⭐ NO QUEUE, and that IS the lesson: a queue
         │         decouples, decoupling costs latency, and the user
         │         is blocked on this reply. Contrast 05u §5.4.
         │
         ├──► Orders DB (Postgres, partitioned by userId)             02g
         │      orderId · userId · externalOrderId · symbol · shares
         │      price · state · (execution data)
         │      state: pending | submitted | filled | partially_filled
         │             | pending_cancel | cancelled | failed
         │      ⭐⭐ pending / pending_cancel are INTENTS, written
         │         BEFORE acting ⇒ a crash leaves evidence
         │      ⚠ partially_filled listed but never discussed
         │
         └──► External Order Metadata DB (KV, e.g. RocksDB)
                externalOrderId -> (orderId, userId)
                ⭐⭐⭐ the feed is keyed by externalOrderId, the table
                   is partitioned by userId — without this, every
                   trade scatter-gathers every shard
                      ▲ query
Trade Processor ◄──trade updates── EXCHANGE
  ⭐ webhook endpoint + LB + fleet; HI draws it as one box
  └──► updates orders in the Orders DB

Order Clean-up Job ──► queries + updates the Orders DB
  ⭐⭐⭐ scans pending / pending_cancel, reconciles with the exchange
     via clientOrderId — the idempotency key HI never names
  ⭐ idempotent: re-running it is a no-op
```

---

## 7 · Expected at Each Level

|Level|The bar for Robinhood|
|---|---|
|**Mid (E4)**|**API + data model + a functional HLD for prices and ordering; converge on efficient price propagation, consistent order management, and a way of proxying the exchange to avoid excess connections.**|
|**Senior (E5)**|**Fast HLD, then real depth on the two things that matter: real-time price propagation, and an order workflow with consistency and fault tolerance in mind.**|
|**Staff+**|**Detail on all of it, plus steering the conversation to what's interesting, and articulating trade-offs as a peer.**|

---

## Quick Recall (pass 3+)

|Use / Question|Robinhood answer|
|---|---|
|Calibration|⚠ **Joseph Antonakakis, NOT Evan King — no rung labels, just "Approach / Challenges"** · **Jul 2024, oldest in your set** · ⭐⭐ **"HARD", second in a row** · ⚠⚠ **"Asked at:" is EMPTY** · **one pattern: `03a`** · **only THREE dives vs `05u`'s six.** ⭐⭐ **ONE pass, in order §4.2 > DD3 > DD2 > DD1 — but don't skip it**|
|⭐⭐⭐ Design driver|⭐⭐ **Two paths, opposite needs, one expensive dependency.** **PRICE: huge fan-out, nobody waiting, 50ms-stale is fine, one-way ⇒ pub/sub + cache + SSE. ORDER: ~1,160/sec, the USER is waiting, must be exactly right ⇒ synchronous + ACID + NO QUEUE.** ⭐⭐⭐ **The counterintuitive result: the HIGH-volume path gets the queue-like machinery, the LOW-volume path gets the direct call.** ▸ ⭐⭐⭐ **Volume didn't decide it. WHO IS WAITING did.** ⭐ **NFR 4 constrains both ⇒ each path gets its own proxy tier**|
|📐 Numbers (do them — HI doesn't)|⚠⚠ **HI gives inputs, never computes.** **20M DAU × 5 trades = 100M/day ÷ 86,400 = ⭐⭐ ~1,160 orders/sec** ⇒ ⭐⭐⭐ **NOT a hard scaling problem** (cf. `05u`'s 2M/sec). ⭐ **The hard number is unstated — the price fan-out: one symbol with 1M watchers ticking 10×/sec = 10M msg/sec for ONE symbol.** **<200ms for BOTH**|
|⭐⭐ Scope + the external API|⭐ **_"Robinhood isn't an exchange in its own right, but rather a stock broker… compensated by those exchanges via payment for order flow."_** ⇒ **_"We are not building an exchange."_** ⭐⭐ **The exchange offers exactly two things: orders are SYNCHRONOUS request/response · the trade feed is PUSH.** ⭐⭐⭐ **HI's instruction: _"briefly clarify the exchange interface (APIs, both synchronous and asynchronous)… the assumptions you make about the interface have broad consequences in your design."_** ▸ **Sync ⇒ you get an ID back ⇒ DD3 is possible. Push ⇒ you need a receiving fleet, not a poller**|
|FRs / NFRs|**Live prices · manage orders (market/limit, create/cancel).** Below: after-hours · ETFs/options/crypto · the order book live. **NFRs: ⭐⭐ high consistency for orders · scale (20M DAU, 5/day, 1000s of symbols) · ⭐⭐ <200ms on both · ⭐⭐⭐ _"minimize the number of active clients connecting to an external exchange API — exchange data feeds / client connections are typically expensive."_** ▸ ⭐⭐ **NFR 4 is a COST/CONTRACT requirement, not latency or throughput, and it alone kills the first design.** ▹ **`05u`'s $200k/day you COMPUTED; this one is STIPULATED**|
|API|`GET /symbol/:name` · `POST /order {position, symbol, priceInCents, numShares}` · `DELETE /order/:id` · `GET /orders`. ⭐⭐ **`priceInCents` — _"to avoid floating point precision issues… better to use integers to avoid errors and financial scams."_** ⭐ **JWT in headers; don't trust a client `userId`.** ⚠ **Not final: §4.1's Great rung replaces the price endpoint with `GET /subscribe?symbols=[…]`** ▸ ⭐ **an API that survives your own deep dives untouched usually means you haven't gone deep enough**|
|⚠⚠ §4.1 Bad — client polls the exchange|⚠ **_"will not scale and will not minimize exchange client connections / calls."_** ⭐⭐⭐ **The framing to keep: _"If 5000 clients are requesting a price at the same time, the price isn't different per client, yet we're expending 5000 calls (repeatedly) to disperse this information."_** ⭐ **Plus polling _"happens indiscriminately, even if the price has not changed."_** ⚠⚠ **And the arithmetic: a 200ms SLA means _"the only way we'd guarantee that… is if we poll data every 200ms, which is unreasonable."_** ▸ ⭐⭐⭐ **With polling, the INTERVAL IS YOUR SLA — you can't promise latency shorter than how often you ask**|
|§4.1 Good — poll an internal cache|⭐⭐ **Still polling, but your Symbol Service doing a KV lookup on a cache _"kept up-to-date by a symbol price processor that is listening to prices on the exchange."_** ⭐⭐⭐ **The NFR-4 move: _"prevents excess connections to the exchange by 'proxying' it with a service that listens and records the most essential detail: the symbol price."_** ⚠ **Polling's two costs survive: _"clients still indiscriminately poll, even if the price has not changed"_, and _"the polling interval dictates the worst-case SLA… Can we do better?"_**|
|⚠⚠ §4.1 — nothing polls the exchange|⭐⭐ **The feed PUSHES (§0): the processor _"listens"_, never asks.** **Path: trade ⇒ push ⇒ processor ⇒ cache + Redis ⇒ Symbol Service ⇒ SSE ⇒ client — ⭐⭐⭐ zero intervals, which is what makes <200ms possible** (⚠ **but four hops; 200ms is a budget across them**). ⭐⭐⭐ **So the GOOD rung fixes CALLS, not LATENCY — the exchange leg was already push, hence _"Can we do better?"_** ⭐⭐⭐ **Why the CACHE: a stream gives DELTAS, a new subscriber needs the BASELINE** — ▸ **subscribe to an illiquid stock and the next trade may be 10 min away; without the cache the screen is blank.** ⭐ **Snapshot + stream, same as `05q`'s CDN snapshot.** ⭐⭐⭐ **Why TWO services: 20M SSE connections ⇒ hundreds of Symbol Service instances; merge the roles and each opens its own exchange connection ⇒ ~400 exchange clients ⇒ the Bad rung again.** ▹ **At 10k users you'd collapse them — a scale decision, not correctness. The cache isn't**|
|⭐⭐ §4.1 Great — SSE|⭐⭐⭐ **HI DOES justify it: _"SSE is a persistent connection (similar to websockets), but it is unidirectional and goes over HTTP instead of a separate protocol. For this example, the client isn't sending us data, so SSE is a superior choice to websockets."_** ▹ **He points at his FB Live Comments write-up (`05q`) for the full trade-off.** ⭐⭐ **Two-stage read: an INITIAL list from the cache on subscribe, then pushes.** ⚠⚠ **Three challenges — ⭐⭐⭐ _"the load balancer will need to be configured to support 'sticky sessions'"_ (a persistent connection means the LB can't spread requests freely) · disconnect/reconnect · _"how we route user connections and symbol data"_** ▸ ⚠ **he defers both to the dives and DD1 answers only the second half**|
|⚠⚠ §4.2 Bad — client → exchange|✅ **_"cuts out any incurred latency from a backend proxying the exchange."_** ⚠⚠ **_"large number of exchange clients and concurrent requests, which will be very expensive"_ ⇒ NFR 4** · **no status check _"outside of polling the exchange or directly listening to trade feeds, both of which aren't viable"_** · ⭐⭐ **_"we can't consider the client's storage to be reliable; the user might uninstall the app or the phone hardware might fail"_** ▸ **keep that phrasing**|
|⭐⭐⭐ §4.2 Good — the QUEUE, and why it LOSES|⭐ **Order Service enqueues → Dispatch Service dequeues.** ✅ **Proxies the exchange; queue depth is a scaling metric.** ⚠⚠⚠ **But: _"breaks down when we consider our tight order SLA (under 200ms)… It would be unacceptable for them to be left waiting for our dispatcher."_** ⭐⭐⭐ **THE PRINCIPLE: a queue DECOUPLES, and decoupling costs latency. If the user holds the connection, you cannot decouple.** ⭐⭐ **Why `05u §5.4` could: the rider sees _"finding you a driver"_, nothing blocked. Here `POST /order` returns a confirmation they're staring at.** ⭐⭐⭐ **Never "is volume high?" — always "is anyone blocked on the reply?"** ⭐ **Scaling-on-depth is a spike trap: the queue grows fastest exactly when new instances haven't booted**|
|⭐⭐ §4.2 Great — NAT gateway, sync|⭐⭐ **_"an AWS NAT gateway"_ with elastic IPs so requests _"appear as if they were originating from a small set of IPs."_** ⭐⭐ **Cost: the Order Service now carries business logic AND the exchange conversation — _"efficient for client interaction and efficient for exchange interaction (e.g. potentially batching orders together)."_** ⭐⭐ **No queue to absorb spikes ⇒ pre-emptive scaling: _"auto-scale when average 50% CPU usage is hit"_ or _"over-provision… to absorb trading spikes."_** ▸ ⭐⭐ **Over-provisioning is legitimate when the alternative adds latency to a blocking path — say it, don't apologise.** ⊕⚠ **But NAT fixes IP COUNT, not CONNECTION count; batching or a shared connection pool is the real NFR-4 answer**|
|Order storage + the state enum|⭐⭐ **Relational, _"to promote consistency via ACID guarantees"_, partitioned on `userId`** ⇒ **_"querying orders of a user… will go to a single node."_** `pending \| submitted \| filled \| partially_filled \| pending_cancel \| cancelled \| failed`. ⭐⭐⭐ **Read it as INTENTS (`pending`, `pending_cancel`) vs OUTCOMES (the rest) — DD3 is entirely about crossing between them.** ⚠ **`partially_filled` listed and NEVER discussed: a 100-share order filling 30 means the trade processor must ACCUMULATE fills, not flip a status**|
|⭐⭐⭐ DD2 — the partition-key problem|⚠⚠ **The feed is keyed by `externalOrderId`; the table is partitioned by `userId`** ⇒ **_"no efficient way for the trade processor to look-up a trade via the `externalOrderId`"_** ⇒ **every trade scatter-gathers every shard.** ⭐⭐⭐ **Fix: a KV store `externalOrderId → (orderId, userId)` (HI: RocksDB), written right after submission.** ⭐ **Double duty — a FILTER (is this trade even ours? most aren't) and a ROUTER (which shard?).** ⭐⭐⭐ **THE GENERALISATION: the partition key you chose for READS can be useless for writes arriving from OUTSIDE — so whenever an external system will call you back, ask what key they'll use and whether you can find the row with it.** ▹ **Not the outbox pattern: outbox publishes YOURS, this receives THEIRS**|
|⭐⭐⭐ DD3 both flows|**CREATE: ① `pending` FIRST ② submit, get `externalOrderId` ③ write the KV entry + `submitted` ④ respond.** ⭐⭐⭐ **Why ① first: _"If we didn't store this first, then the client could create an order on the exchange, the system could fail, and then our system has no way of knowing there's an outstanding order."_** **CANCEL: ① `pending_cancel` FIRST _"to enable resolving failed cancels later"_ ② submit ③ record ④ respond.** **Failures: early ⇒ respond failure and stop · ⚠⚠ after submission ⇒ the order is LIVE and you don't know its ID**|
|⭐⭐⭐ DD3 — `clientOrderId` is the trick|⚠⚠ **After a post-submission failure you can't retry (double order) and can't give up (it's real).** ⭐⭐⭐ **A CLEAN-UP JOB scans `pending`, and what makes asking possible is _"Most exchange APIs offer a `clientOrderId` metadata field when submitting an order (see E*TRADE example)"_** ⇒ **record the `externalOrderId`, or mark `failed`.** ⭐⭐⭐ **That IS an idempotency key and HI never calls it one.** ⭐⭐ **Transferable: before any remote call you can't safely retry, attach your own ID — it turns an unanswerable question into a lookup.** ⭐⭐ **And note the sweeper is IDEMPOTENT: _"or no-op and just update status to `cancelled` if they have already been cancelled"_**|
|⭐⭐⭐ DD3's one pattern|⭐⭐⭐ **WRITE YOUR INTENT BEFORE YOU ACT.** ▸ **`pending` / `pending_cancel` aren't progress indicators — they're records of what you were ABOUT to do, so a crash leaves evidence instead of silence.** ⭐⭐⭐ **And an intent is only safe if something reconciles it: ⚠ an intent with no sweeper is a stuck row.** ⭐ **HI's real deliverable is the DISCOVERY, not the workflow — _"identified the need for a 'clean-up' background process."_** ▹ **Same family as `05t`'s dedupe key and `05p`'s sweeper; here you reconcile against a THIRD PARTY you don't control**|
|DD1 the 4 steps|**① subscribe ⇒ server adds the user to `Symbol → Set<userId>` ② the server subscribes to that symbol's Redis channel if it hasn't ③ price change ⇒ Symbol Price Processor PUBLISHES ⇒ every subscribed server fans out over SSE ④ unsubscribe/disconnect (_"detected via some heartbeat mechanism"_) ⇒ remove from the sets, and ⭐ unsubscribe from the channel if no users remain.** ⭐ **The question stated well: _"how do we route symbol price updates to the symbol service servers connected to users who care about those symbol updates?"_**|
|⊕⚠⚠ DD1 — `05q` answered this better|⚠⚠ **Users land on ANY server, so 1M `AAPL` watchers across 100 servers ⇒ all 100 subscribe ⇒ every tick delivered 100×.** ▸ **"Self-regulating" holds per symbol, not per SERVER.** ⭐⭐⭐ **`05q §5.2` fixed exactly this — partitioning channels alone changes nothing; you need Layer 7 consistent-hash routing so co-watchers share a server.** ⚠⚠ **And HI has no excuse: §4.1 CITES the FB Live Comments write-up, and its own challenge list promises _"how we route USER CONNECTIONS and symbol data"_ is _"covered later in our deep dive sections."_ DD1 answers only the symbol-data half and drops the user-connection half.** ⭐⭐ **Say: _"he flagged user-connection routing in the HLD — I'd close it with Layer 7 routing by symbol."_** ▹ ⭐ **Be fair: with 1000s of symbols, pub/sub is cheap and it may not matter — a trade-off, not a bug**|
|⭐ HI's four extra dives|**① excess price updates ⇒ ⭐⭐ COALESCE, don't forward — latest price every N ms, because a price is a STATE not an event (cf. `05k`) ② limiting exchange correspondence ⇒ _"batching orders into single requests"_ — the real NFR-4 answer ③ live ORDER updates ⇒ ⭐ the machinery already exists: same pub/sub shape keyed by `userId` instead of symbol ④ historical price / portfolio value ⇒ a different storage question**|
|⭐⭐⭐ The meta-lesson|⭐⭐⭐ **Two of your habits get inverted in one file: the QUEUE is not always the upgrade (it costs latency, and here the user is blocked), and the PARTITION KEY that's right for your reads can be wrong for everyone else's writes.** ▸ ⭐⭐ **Same root — a design is only correct relative to WHO is on the other side of it**|
|Levels (one line)|**E4:** API + data model + a functional HLD; converge on price propagation, consistent orders, proxying the exchange · **E5:** fast HLD then depth on real-time price propagation and a fault-tolerant order workflow · **Staff+:** detail on all of it, steer the conversation, trade-offs as a peer|

---

> 🔗 **HI source:** https://www.hellointerview.com/learn/system-design/problem-breakdowns/robinhood