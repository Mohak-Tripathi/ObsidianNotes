# Real-time Updates

> Hello Interview · **Patterns** · File `03a`. Overview → `03 §1`. Networking internals → `01a` (not re-explained here). **Calibration:** ⭐⭐ **High value.** Shows up in _almost every_ interactive-system interview. For your targets: Razorpay **payment-status** updates, Groww/smallcase/Robinhood **price ticks**, Swiggy/Zomato **live order tracking**, chat. ▸ **The governing insight: START SIMPLE, ESCALATE ONLY WHEN FORCED.** Most candidates reach for WebSockets when polling or SSE would do. The senior signal is proposing the _simplest thing that meets the latency requirement_ — and saying so out loud. ⚠ **Many strong engineers have never built this** (it's usually a specialized team's job). You're not expected to have shipped it — you're expected to reason about the trade-offs.

---

## The Problem

▸ **CRUX** — standard HTTP is **request-response**: client asks, server answers, connection closes. That breaks the moment the **server needs to push** to the client as events happen (new chat message, doc edit, price move). You can't have every client hammer-polling every few ms without crushing your infra.

### Where this pattern shows up (HI problem breakdowns)

▸ **Recognize these as real-time-update problems the moment they appear** — naming the pattern early is the senior signal.

- **Chat / messaging** — WhatsApp, Online Chess _(bi-directional → WebSockets)_.
- **Collaborative editing** — Google Docs _(heavy per-connection state → consistent hashing + CRDTs)_.
- **Live feeds / dashboards** — ⭐ **Robinhood** (price ticks), Strava _(one-way → SSE)_.
- **Location tracking** — Uber _(driver location push)_.
- **High-contention buy/bid** — Ticketmaster, Online Auction _(status while holding a lock → often long-polling)_.
- **Massive fan-out** — FB Live Comments _(millions concurrent → hierarchical aggregation → `03e`)_.
- **Token streaming** — ChatGPT _(one-way stream → SSE)_.

⚠ **Fintech read:** Robinhood (price feed) and the Ticketmaster/Auction "wait for status" shape map straight onto **Groww/smallcase tickers** and **Razorpay payment-status** flows.

---

## The Organizing Idea — TWO HOPS

> ⭐ **This is the whole file. Every real-time design decomposes into two independent hops, each with its own trade-offs, chosen separately.**

▸ **Hop 1 — Server → Client:** how does the update travel the last mile to the user's device? _(Connection protocol.)_ ▸ **Hop 2 — Source → Server:** how does the update get _from where it originated_ to the server holding that client's connection? _(The trigger / propagation.)_

⚠ **Don't conflate them.** "I'll use WebSockets" answers only Hop 1. You still owe Hop 2 (how does a message from User A reach the _specific server_ User C is connected to?).

---

# HOP 1 — Server → Client (connection protocols)

## Networking prerequisites → `01a`

▸ OSI layers 3/4/7, TCP vs UDP, the SYN/handshake lifecycle, keep-alive — all in `01a`, don't re-derive. ▸ **The one line to carry into realtime:** every HTTP call rides a TCP connection, and TCP gives you two things that matter here — **latency** (each round trip, including the setup handshake, costs time) and **state** (an open connection is memory both sides hold). Realtime is largely about **paying the setup once and keeping the connection open** rather than re-handshaking per update.

### L4 vs L7 load balancer _(the decision that actually bites in realtime)_

> Expanded here on purpose — it's _the_ infra call for persistent connections. _(General LB treatment → `02 §5`.)_

▸ **Why an LB is even in the picture:** multiple servers sit behind one → the LB spreads connections across them. For realtime, **which layer it operates at changes whether a persistent connection survives.**

▸ **L4 (transport layer — TCP/UDP):** routes on **IP + port only**, never looks inside the packet.

- Keeps **one persistent TCP connection** pinned client↔server for the whole session.
- **Fast** — minimal inspection.
- **Can't** route on application data (URL, headers, cookies).
- Reach for it when **raw performance / persistent connections** are the priority.
- ▸ **Mental model:** as if the client has a **direct TCP pipe** to one backend — exactly what a **WebSocket** needs.

▸ **L7 (application layer — understands HTTP):** reads the actual request.

- **Terminates** the incoming connection and opens a **new** one to the backend (connection is _not_ preserved end-to-end).
- **Routes on content** — URL, headers, cookies (e.g. all of a user's requests → same server; acts like an API gateway).
- **More CPU** — it inspects every request.
- More **flexibility / features**; best for **HTTP-based** traffic.

▸ **The realtime call:**

- **WebSocket → L4.** The connection must stay pinned; L7's terminate-and-recreate breaks that (some L7s _do_ support WS, but support is spotty).
- **Long polling / SSE → L7.** They're plain HTTP, so you want L7's routing flexibility.
- ⚠ **SSE caveat:** many L7 proxies/LBs **buffer** a streaming response until it "completes" → silently blocks your stream. Opaque, painful to debug.

---

## The Five Options — an escalation ladder

> Go down this list **only as far as the requirement forces you.** Each rung adds latency-improvement _and_ infra cost.

### 1. Simple Polling — the baseline _(not really real-time)_

▸ Client hits `GET /updates` on a fixed interval (e.g. every 2–5s); server returns current state.

**Advantages**

- Simple to implement.
- Stateless.
- No special infrastructure needed.
- Works with any standard networking infrastructure.
- Doesn't take much time to explain.

**Disadvantages**

- Higher latency — updates delayed up to (polling interval + processing time).
- Limited update frequency.
- More bandwidth usage.
- Can be resource-intensive with many clients (constantly establishing new connections).

▸ **Commentary:**

- **Use when** you're **not** latency-sensitive, or the update window is short _(LeetCode-contest style)_.
- ⚠ **"Doesn't take much time to explain" is underrated** — if real-time isn't the _crux_, polling preserves interview time/energy for what matters.
- ▸ **Efficiency tip:** set HTTP **keep-alive longer than the poll interval** → reuse one TCP connection, skip repeated setup/teardown.
- ⚠ **Hidden read load:** 1M clients ÷ 10s = **100k TPS** — easy to forget.
- ▸ **Interview move:** _"I'll start with polling to focus on X; we can upgrade if latency demands."_ Gives a backdoor. **Float it first** — if they want WebSockets, learn that early.

### 2. Long Polling — near-real-time, still just HTTP

▸ Client requests; **server holds it open until data exists**, then responds; client **immediately re-requests**. Like a deliberately slow response.

**Advantages**

- Builds on standard HTTP, works everywhere HTTP works.
- Easy to implement.
- No special infrastructure needed.
- Stateless server-side.

**Disadvantages**

- Higher latency than the alternatives below.
- More HTTP overhead.
- Can be resource-intensive with many clients.
- Not suitable for frequent updates (see the callback gap).
- Makes monitoring painful — requests hang around a long time.
- Browsers cap concurrent connections per domain → only a few long-polls per domain.

▸ **Commentary:**

- **Use when** updates are **infrequent** and you want an easy upgrade from polling. ⭐ **Classic fit: waiting on a long async job — long-poll for payment status, then show the success page (Razorpay-shaped).**
- ⚠ **The callback gap kills high frequency:** after each response the client must re-connect. At 100ms RTT, two updates 10ms apart arrive at ~100ms and ~**290ms** (finish response + new request + new response).
- ⚠ **Tune the interval so every hop agrees** — don't let the LB hang up at 30s while the server holds 60s (**15–30s** is common).

### 3. Server-Sent Events (SSE) — the efficient one-way street

▸ Extends long-polling: server responds with `Transfer-Encoding: chunked` and **streams chunks** on one open request instead of one atomic response. Browser `EventSource` handles it natively.

▸ **How it works:**

- Client establishes an SSE connection (one HTTP request).
- Server keeps the connection open.
- Server sends a message **as a chunk** whenever data changes/updates.
- Client receives updates in real time as they stream in.
- ▸ Client side is trivial — the browser's **`EventSource`** object manages the connection and reconnection for you.

**Advantages**

- Built into browsers.
- Automatic reconnection.
- Works over HTTP.
- More efficient than long polling (less connection initiation/teardown).
- Simple to implement.

**Disadvantages**

- One-way communication only.
- Limited browser support (a non-issue on modern browsers).
- Some proxies/networking equipment don't support streaming — nasty to debug.
- Browsers cap concurrent connections per domain → only a few SSE connections per domain.
- Makes monitoring painful — requests hang around a long time.

▸ **Commentary:**

- **Use when** you need **one-way** server→client push. ⭐ Live dashboards, **price/quote feeds (Robinhood/Groww/smallcase)**, and **AI token streaming** (very common today).
- ▸ **Reconnection:** SSE carries a **`Last-Event-ID`** — on reconnect the client sends the last ID it saw and the server replays the gap. Design event IDs to support this.
- ⚠ The proxy **buffering** trap from the LB section lands here — a buffering L7 silently blocks the stream.

#### ⚠ Confusion resolved — when to use Long Polling vs SSE?

> **My doubt:** _"when to use long polling vs SSE NOT CLEAR TO ME"_

▸ **Both hold a request open waiting for data. The difference is updates-per-request.**

- **Long polling = ONE update per request.** Server holds the request, sends **one** response when data's ready, connection **closes**, client opens a **new** request. One request : one message — still request-response, just delayed. Every message pays a **reconnect** (the callback gap above).
- **SSE = MANY updates per request.** Server holds **one** request open and streams chunk after chunk. Connection **stays open**; updates flow as they happen, no re-requesting. One request : many messages — a stream.

▸ **They're both one-way and HTTP-based, so the deciding axis is FREQUENCY:**

||Long polling|SSE|
|---|---|---|
|Updates per connection|**one, then reconnect**|**many, stays open**|
|Best at|**infrequent / one-shot**|**continuous / high-frequency**|
|Infra need|works **everywhere HTTP works**|needs **streaming-capable** infra (proxies may buffer/block)|
|Canonical use|⭐ **wait for one event** — payment status, then done|⭐ **price ticks, AI tokens, live feed**|

- **Infrequent or one-shot → long polling.** Reconnect cost is negligible when updates are rare, and it's maximally simple + universal. "Wait for the payment to finish" = you expect **one** meaningful update, then you're done.
- **Frequent / continuous → SSE.** Once updates stream fast, long-polling's per-message reconnect becomes the bottleneck; SSE pays setup **once** and pushes freely.

▸ **One-liner:** _SSE is long-polling's high-frequency upgrade — trade universal infra support for a single connection that streams many updates._ Need frequent writes **back** too? Neither — that's WebSockets.

### 4. WebSockets — the full-duplex champion

▸ **Upgrades** an HTTP connection to a persistent, bi-directional L7 protocol over the same TCP socket (reuses cookies/headers from the handshake). Both sides send opaque message blobs (JSON, Protobuf, …).

**Advantages**

- Full-duplex (read + write) communication.
- Lower latency than HTTP — reduced overhead (e.g. no repeated headers).
- Efficient for frequent messages.
- Wide browser support.

**Disadvantages**

- More complex to implement.
- Requires special infrastructure.
- Stateful connections → load balancing and scaling are harder.
- Need to handle reconnection.

▸ **Commentary:**

- **Use when** you need **high-frequency, bi-directional** comms. ⭐ Chat, collaborative editing, multiplayer.

⚠ **The extra challenges — all flow from ONE fact: the connection is persistent + stateful, so it can't be treated like a stateless HTTP request.** Three consequences:

▸ **1. Infrastructure must support the persistent connection (L4 vs L7).**

- **Problem:** an **L7** LB terminates each incoming connection and opens a fresh one to the backend → it does **not** guarantee the _same_ TCP connection is reused → WebSocket support is **spotty**.
- **Fix:** use an **L4** LB — it routes at TCP level, so the **same TCP connection is pinned** client↔server for the whole session, which is exactly what a WebSocket is. _(L4/L7 detail → the LB section above.)_
- ⚠ Every hop between client and server must support the upgrade — one non-WS-aware proxy in the path breaks it.

▸ **2. Deployments churn connections.**

- **Problem:** connections are long-running, but servers get **redeployed**. When a server restarts, its open connections have to go somewhere. Two options:
    - **Sever all old connections → clients reconnect** _(preferred — simpler)_.
    - **New servers take over and keep connections alive** _(complex, rarely worth it)_.
- ⚠ **Ramification:** choosing sever-and-reconnect means you can't actually promise a _truly_ persistent connection — clients **will** drop periodically (every deploy), so the client must be built to reconnect gracefully.
- ⚠ On reconnect a client may have **missed messages** while disconnected → you need replay (seq numbers / **Redis Streams** → `02a §6`, see deep dive below).

▸ **3. Load balancing / scaling is harder (uneven load → hotspots).**

- **Problem:** once a long-running connection is **placed** on a server, you're **stuck with that decision** — the LB can't later move it to rebalance without **breaking** the connection. So load can drift **uneven** → some WS servers become hotspots and fail.
- **Fix:** use a **"least connections"** LB strategy (send new connections to the least-loaded server), **and keep WS servers light** — do minimal work per message so a busy connection doesn't starve its neighbors.

▸ **Reference architecture (the mitigation for all three):** terminate WebSockets into a dedicated **WebSocket service** early in the infra.

- Connection-management **state is isolated** there → the rest of the system stays **stateless** and scales normally.
    
- That service **changes rarely** → fewer deploys → fewer connection drops.
    
- Offload heavy per-message processing to **other services** that scale independently → keeps the WS layer light (feeds directly into fix #3).
    
- ▸ **Senior/staff signal:** the whole game is **minimizing the spread of state** across your architecture — say this out loud.
    
- ⚠ **Don't over-reach:** pair **SSE for reads + plain HTTP POST/PUT for the occasional write** and skip WebSockets entirely. Only adopt WS when writes are _also_ high-frequency.
    

▸ **In the interview — lead with these talking points (delivery checklist):**

- **Connection management + reconnection** — heartbeats to detect zombie connections; replay missed messages on reconnect.
- **Deployment / server-restart strategy** — state you'll sever-and-reconnect, and that clients handle it gracefully.
- **Minimize state spread** — the senior/staff signal; isolate connection state in a WS service, keep the rest stateless.
- **Scaling WS servers** — call out uneven load → hotspots; fix with **"least connections"** + keep servers light + offload heavy processing.

### 5. WebRTC — peer-to-peer _(rarely needed for product SDE2)_

▹ Direct **browser↔browser** via a lightweight **signaling server** (which itself needs SSE/WebSockets to exchange peer info). **STUN** = NAT hole-punching to find a routable address; **TURN** = relay when hole-punching fails.

**Advantages**

- Direct peer-to-peer communication.
- Lower latency.
- Reduced server costs (bandwidth offloaded to peers).
- Native audio/video support.

**Disadvantages**

- Complex setup (more than WebSockets).
- Requires a signaling server.
- NAT/firewall issues.
- Connection-setup delay.

▸ **Commentary:**

- **Use when** you need **audio/video calls**, screen share, or to **offload server bandwidth** by letting clients talk directly (Canva presence, Google-Docs cursors + CRDTs).
- ▹ **In an interview it should be obvious why** (video, or scale forces P2P). Otherwise don't reach for it.

### Hop-1 decision table

|Option|Direction|Builds on|Latency|Infra cost|Reach for when|
|---|---|---|---|---|---|
|**Simple polling**|pull|HTTP|interval-bound|none|not latency-sensitive; short window|
|**Long polling**|~push|HTTP|near-real-time (poor at high freq)|none|infrequent updates · **await async job (payment)**|
|**SSE**|server→client only|HTTP (chunked)|real-time|low (streaming support)|**one-way** feeds, dashboards, **AI token stream**|
|**WebSockets**|full-duplex|HTTP upgrade → TCP|lowest|**high** (stateful, L4)|**high-freq bi-directional** (chat, editing)|
|**WebRTC**|peer↔peer|UDP + signaling|lowest|highest|**video/audio**, P2P offload|

▸ **Flowchart in words:** not latency-sensitive → **polling**. One-way → **SSE**. Frequent + bi-directional → **WebSockets**. Audio/video → **WebRTC**.

---

# HOP 2 — Source → Server (the trigger / propagation)

> Once a client holds a persistent connection to **one** server, how does an update originating elsewhere reach _that_ server? Three patterns.

### A. Pull via Polling

▸ **The model:** the client is **constantly asking** the server for updates, so the server must **hold the state** needed to answer. The usual way: updates get written to a **DB** (e.g. every chat message), and clients **pull from that DB** whenever they poll.

▸ **The concrete mechanic — poll with a cursor, not "give me everything":** the client tracks the **last thing it saw** (a timestamp or ID) and asks for **only what's newer.**

- Chat example: _"what messages were sent to this room with a timestamp **greater than the last message I received**?"_
- Each poll advances the cursor → the client never re-fetches what it already has → each response is small.

▸ **Why the DB matters — it decouples the producer from the consumer.** Think of the DB as a **drop-box** sitting between them:

- In a **push** model there's an **unbroken path** from producer to client — the update travels straight through, as it happens.
- In **polling** that path is **broken in the middle by the DB** — it becomes **two separate, disconnected actions:**
    1. The producer **writes the update into the DB and stops.** It doesn't know or care who will read it.
    2. **Later, on its own schedule, the consumer polls the DB** and picks it up.
- Nothing flows producer→consumer **directly** — the producer drops the update in the box, the consumer checks the box whenever it polls.
- ⚠ **We tolerate delay on purpose:** the **poll itself is the trigger**, even though the update may have landed in the DB some time _earlier_. That gap is the **lost real-time** — the deliberate price of the decoupling.
- ✅ The upside of the same decoupling: producer and consumer **scale independently** and neither needs to know the other exists.

**Advantages**

- Dead simple to implement.
- State is constrained to the DB.
- No special infrastructure.
- Doesn't take much time to explain.

**Disadvantages**

- High latency.
- Excess DB load when updates are infrequent but polling is frequent (the 100k-TPS trap again).

▸ **Commentary:** use when you want _somewhat_ fresh data but true real-time isn't required.

### B. Push via Consistent Hashing

▸ **The problem:** to push to User C you must know **which server holds C's connection.**

- **Simple hashing** — a coordination service (**ZooKeeper/etcd**) tracks N servers; server `n = hash(userId) % N` owns that user. Client connects anywhere → gets redirected to its owner server → server maps user→connection.
- ⚠ **Modulo breaks on scaling** — changing N reshuffles almost _everyone_ → mass reconnect. **Fix → consistent hashing** _(full mechanics → `01g`)_: users + servers on a ring; scaling moves only the affected arc.

**Advantages**

- Predictable server assignment.
- Minimal connection disruption during scaling.
- Works well with stateful connections.
- Easy to add/remove servers.

**Disadvantages**

- Complex to implement correctly.
- Requires a coordination service (ZooKeeper/etcd).
- All servers must maintain routing information.
- Connection state is lost if a server fails.

▸ **Commentary:**

- **Use when** connections carry **heavy per-connection state** expensive to rebuild (⭐ Google Docs: server holds the loaded doc + pending ops). State lives in **one** place; scaling churns few connections.
- ⚠ Scaling needs orchestration — dual-write to old+new during transition, drain slowly, update the registry.

#### ⚠ Confusion resolved — the actual data flow (users, servers, ZooKeeper, update server) + what a "socket" is

> **My doubt:** _"how first of all users getting connected to the server, and then what ZooKeeper is doing… when the update will happen, then how ZooKeeper is telling the correct server, and then finally data reaching to user… data flow is not clear."_ and _"what do you mean by socket? …what is socket in WebSocket?"_

**Cast:** users A–F · three connection servers **S0/S1/S2** · **ZooKeeper** · an **Update Server**. Say `hash(C)` lands C's ownership on **S2**.

▸ **Who holds what (get this first):**

- **Connection servers (S0–S2)** — hold the actual persistent connections; each keeps an **in-memory map `userId → socket`**.
- **ZooKeeper** — holds **only the ring membership** (which servers exist + their positions/addresses). **No connections, no routing, no messages.**
- **Update Server** — produces/receives updates, must deliver to the right user.

▸ **Phase 1 — C connects (build the live pipe):**

1. C opens a connection to a **random** server, say S0.
2. S0 asks "who owns C?" → reads the ring from ZooKeeper, computes `hash(C)` → clockwise → **S2**.
3. S0 **redirects**: "not me, go to S2."
4. C connects to S2.
5. S2 stores `C → socket` in **its own memory**. S2 now holds C's live connection.

▸ **Phase 2 — an update for C arrives (new message / "download complete"):**

1. Update Server gets "deliver X to C."
2. It **already has the ring cached** → computes `hash(C)` → **S2** (same computation S0 did → same owner).
3. It sends X **directly to S2**. ⚠ **ZooKeeper is NOT contacted here** — no per-message ZooKeeper call.
4. S2 looks up C in its **local map** → finds C's socket.
5. S2 writes X over that socket → C receives it in real time. Push done.

⚠ **The three things that were fuzzy — the real answer:**

- **ZooKeeper doesn't route or push.** It's a shared **phone book** ("which servers exist, where they sit on the ring"). Everyone _reads_ it to agree on ownership; at delivery time it's **not in the path.** It never "tells the correct server" anything.
- **Ownership is COMPUTED, not stored.** No table says "C lives on S2." Both the connecting server and the Update Server **independently derive S2** from `hash(C)` + the shared ring. That's the whole trick — **no central `user→server` registry to maintain.**
- **The connection lives only in the owner server's memory.** ZooKeeper gives you the _server_; that server knows the _socket_.

▸ **Why persistent ZooKeeper (your own reasoning, confirmed):** connection/update servers are **ephemeral**, so you need **one durable place** everyone agrees on for ring membership → ZooKeeper. The Update Server **caches** that ring in memory so it doesn't call ZooKeeper per message.

▸ **When does ZooKeeper actually act?** Only on **membership change** (add/remove a server = scaling): the ring changes, ZooKeeper notifies servers, only users on the affected arc reconnect (`01g`). **In steady-state delivery, ZooKeeper is idle.**

⚠ **"Why not just send the update to all servers?"** You could broadcast, but C's connection is on **exactly one** server and you can **compute which for free** → broadcasting means N−1 servers get something useless (worse as N grows). Targeting is free, so target. _(Pub/Sub `§C` deliberately goes the broadcast route — which is why it wins when per-client state is light and you don't want to track ownership.)_

---

**What is a "socket"? (a socket is NOT a port)**

> The other half of the doubt: _"is it the meaning of port? we connect WebSocket with one port… what is socket in WebSocket?"_

▸ **Port vs socket:**

- **Port** = one number the server **listens** on — the "door." Your WS server listens on **one** port (e.g. 443). One door.
- **Socket** = one specific **established connection** through that door with **one** client — the live conversation, not the door.

▸ **The key fact:** one listening port holds **many** sockets at once. The server does **NOT** open "one port per user." It has **one** listening port and **N sockets** (one per connected user), all sharing that port.

▸ **How do they share port 443?** The OS identifies each connection by a **4-tuple**, not just the server port:

```
(client IP, client port, server IP, server port)
```

Server side is `serverIP:443` for _everyone_, but each client brings its own `(clientIP, clientPort)` → the **full 4-tuple is unique per connection** → the OS keeps 50,000 conversations straight on one port.

▹ **Phone analogy:** the **port** is a company's single reception number (everyone dials it); each **active call** is a separate conversation = a **socket**; 500 callers can be connected "at the same number" = 500 sockets, one number.

▸ **What the socket IS in code:**

```js
wss.on('connection', (ws) => { ... })
```

That `ws` object **is the socket** — a handle to that one client's open connection (under the hood a file descriptor pointing at the TCP connection). So the server's map is literally `userId → ws`:

```
"C" → <socket to C's device>
```

▸ **So "push to C" physically means:** owner server looks up C → gets C's `ws` → **writes bytes into that socket** → they travel down the already-open connection to C. No new connection, no port juggling — just writing into a pipe the server already holds.

⚠ **WRONG vs CORRECT:**

- ❌ "Each user gets their own port; the server manages ports 1…N."
- ✅ "The server listens on **one** port; each user gets their own **socket** (connection handle); all sockets share that port, distinguished by the client's IP:port."

▸ **One-line hold:** _port = the door the server listens on · socket = one held-open conversation through it · `userId → socket` = which open pipe to write into to reach that user._

### C. Push via Pub/Sub ⭐ (the default for broadcast)

▸ A **Pub/Sub service (Redis / Kafka)** collects updates and broadcasts to subscribers. Connections now terminate on **lightweight, interchangeable endpoint servers** that just subscribe to topics and forward. _(Pub/Sub mechanics → `02a §7`, `02 §7`.)_

- **Flow:** client connects to _any_ endpoint server → server subscribes to that user's topic → update published to topic → Pub/Sub fans out to subscribed endpoint servers → they forward over the open connection.

**Advantages**

- Load on endpoint servers is easy to manage — simple **"least connections"** LB.
- Broadcasts to a large number of clients efficiently.
- Minimizes the proliferation of state through the system.

**Disadvantages**

- Endpoint server doesn't know whether a subscriber is still connected, or when it disconnects.
- Pub/Sub service is a **SPOF and bottleneck**.
- Extra layer of indirection adds latency (~<10ms).
- Many-to-many connections between Pub/Sub hosts and endpoint servers.

▸ **Commentary:**

- **Use when** broadcasting to **many** clients with **little per-client state** — the common case.
- ▸ **Scale the SPOF** via **Redis Cluster**, sharding subscriptions by key (accepting the many-to-many endpoint↔cluster fan-out).

### ⚠ Consistent Hashing vs Pub/Sub — the deciding question

||Consistent Hashing|Pub/Sub|
|---|---|---|
|Where state lives|**on the endpoint server** (pinned per user/doc)|**in the Pub/Sub service**; endpoints lightweight|
|Client→server binding|**must** hit its owner server|connect to **any** endpoint|
|Best for|**heavy** per-connection state (Google Docs)|**broadcast**, light per-client state (chat, feeds)|
|Scaling pain|orchestrated ring resizing|scale the Pub/Sub cluster (many-to-many)|

- ▸ **One-liner:** _heavy per-connection state → consistent hashing; light broadcast → Pub/Sub._

---

## When to use in interviews

▸ **Proactively name it early.** _"Messages need instant delivery — I'll use WebSockets with Pub/Sub for fan-out."_ Don't wait to be asked.

- **Chat** → WebSockets + Pub/Sub.
- **Live comments** (millions concurrent) → hierarchical aggregation + batching _(fan-out → `03e`)_.
- **Collaborative editing** → WebSockets + CRDTs/OT for conflicts.
- **Live dashboards / price feeds** → SSE.
- **Gaming / video** → WebRTC + WebSockets for coordination.

⚠ **When NOT to:** if polling every few seconds suffices, **do that** — you skip _both_ hops (no protocol choice, no propagation). Simplicity is a senior+ signal; over-engineering real-time is the common failure.

---

## Common Deep Dives

▸ **Reconnection / missed messages.** Networks drop constantly; a WebSocket can look alive while the server has cleaned it up (**zombie connection**) → use **heartbeats** to detect. On reconnect, replay what was missed via **per-user queue or sequence numbers** — **Redis Streams** is the popular backing _(→ `02a §6`)_.

▸ **Celebrity fan-out.** One user, millions of followers, same update → naive per-follower writes crash the system. Cache the update once, distribute **hierarchically** (regional servers pull, then push locally). ⭐ Full treatment → **Scaling Writes `03e`** + hot-key remediations `02a`.

▹ **Message ordering.** Two messages ms apart can arrive out of order across servers. Vector clocks / logical timestamps exist, but for **product** interviews **funnel related messages through a single server/partition** and stamp a total order there — trades some scale for simplicity. _(Vector clocks = deep-infra, rarely needed for product SDE2.)_

---

## Quick Recall (pass 3+)

|Question|Answer|
|---|---|
|The organizing idea|**two hops** — Hop 1 server→client (protocol) · Hop 2 source→server (trigger). Chosen **independently**|
|Governing rule|**start simple, escalate only when forced** — candidates over-reach for WebSockets|
|L4 vs L7 for realtime|**WebSocket → L4** (pins TCP) · HTTP polling/SSE → L7 · ⚠ L7 may **buffer SSE** streams|
|Simple polling|baseline, not real-time; ⚠ 1M clients ÷ 10s = **100k TPS**; keep-alive > interval|
|Long polling|hold request open till data; ⭐ **await async job → payment status**; ⚠ bad at high freq (callback gap)|
|SSE|**one-way** stream (chunked); dashboards, **price feeds, AI tokens**; auto-reconnect via **`Last-Event-ID`**|
|Long polling **vs** SSE|**one update/request (reconnect each) vs many updates/one open stream** → infrequent/one-shot (payment) = long-poll · continuous/high-freq (ticks, tokens) = SSE. SSE needs streaming-capable infra|
|WebSockets|**full-duplex**, high-freq bi-directional (chat); ⚠ **stateful** → L4, hard scaling, redeploy churn; terminate into a **WS service**|
|Cheaper than WS?|**SSE for reads + HTTP POST for writes** — skip WS unless writes are also high-freq|
|WebRTC|P2P audio/video or bandwidth offload; needs **signaling + STUN/TURN**; ▹ rarely in product SDE2|
|Hop 2 — pull|updates in DB, poll is the trigger; ⚠ DB load|
|Hop 2 — consistent hashing|route to the **owner server** (`01g`); for **heavy per-connection state** (Google Docs); ⚠ ZooKeeper/etcd, state lost on server death|
|↳ data flow|**connect:** random server → reads ring from ZK → computes `hash(C)`=owner → redirect → owner stores `user→socket`. **deliver:** update server computes `hash(C)` (ring **cached**) → sends straight to owner → owner writes down socket. ⚠ **ZK not called per message** — only on membership change|
|↳ ZooKeeper's role|shared **phone book** (ring membership only); ownership **computed not stored**; idle at delivery time|
|↳ socket vs port|**port = one door the server listens on** · **socket = one open connection through it**; one port holds **many** sockets, unique by **4-tuple** (client IP:port + server IP:port). `ws` object = the socket = `userId→socket`|
|Hop 2 — Pub/Sub ⭐|Redis/Kafka broadcasts to **lightweight endpoint servers**; **least-connections** LB; ⚠ SPOF → Redis Cluster, many-to-many|
|Hashing vs Pub/Sub|**heavy state → hashing · light broadcast → Pub/Sub**|
|Reconnection|heartbeats detect zombies; replay via seq numbers / **Redis Streams** (`02a §6`)|
|Celebrity fan-out|cache once + hierarchical distribution → **`03e`**, `02a`|
|Ordering (product)|funnel through **one partition**, stamp total order; vector clocks = deep-infra|
|When NOT to use|polling suffices → do it, skip both hops|
QR => https://www.hellointerview.com/learn/system-design/patterns/realtime-updates/quick-reference