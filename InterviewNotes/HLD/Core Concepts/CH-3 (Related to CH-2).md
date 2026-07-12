# Networking — Deep Dive

> Hello Interview · Core Concepts (deep dive) · File `01a`. The overview lives in `01_core_concepts §1`; this is the full version. **Calibration:** networking is weighted heavily for _infra / distributed-systems_ roles. For full-stack/product roles you need surface fluency + the ability to survive probes. Depth below is "know it, don't lead with it."


### What "networking" actually covers

Networking = _how independent machines talk to each other over a network._ That has **four** parts, and OSI is only part one:

1. **Protocols (OSI layers)** — the _language_ machines speak. ✅ this is what you were thinking of.
2. **Load balancing** — spreading that talk across _many_ machines (routing traffic).
3. **Latency & regionalization** — the network is **slow**. This is _physics of the network_ — speed of light through fiber is literally a networking property. You can't discuss it anywhere else.
4. **Fault tolerance** — the network is **unreliable**. Packets drop, cables cut, connections time out.





---

## The OSI Layers

> Hello Interview only covers **L3, L4, L7** — the three that matter in interviews. Layers 1, 2, 5, 6 below are **my addition for completeness** (not in the source).

|Layer|Name|Protocols / examples|Job (one line)|Source|
|---|---|---|---|---|
|**L7**|Application|HTTP, DNS, WebSocket, WebRTC|app-facing protocols built on L4|**HI**|
|L6|Presentation|TLS/SSL, JSON, compression|translate / encrypt / compress data into a format the app understands|_mine_|
|L5|Session|sockets, RPC session mgmt|open, manage, and close sessions between two apps|_mine_|
|**L4**|Transport|**TCP, UDP, QUIC**|end-to-end guarantees on IP: reliability, ordering, flow control; **ports**|**HI**|
|**L3**|Network|**IP**, routers|route packets _across_ networks; **IP addressing**, best-effort delivery|**HI**|
|L2|Data Link|Ethernet, Wi-Fi, switches|node-to-node delivery on the _same local_ network; **MAC addresses**, frames|_mine_|
|L1|Physical|cables, fiber, radio|raw **bits** over the physical medium (voltages, light, radio waves)|_mine_|

▹ In practice most people use the collapsed **TCP/IP model** (4 layers) — L5/L6 usually fold into L7, and TLS (L6) is often just spoken of as "on top of TCP." Higher up the stack = more latency + processing (drives the L4-vs-L7 load balancer choice later).

### How data flows between two devices _(my addition)_

▸ **CRUX** — data goes **down** the stack on the sender and **up** the stack on the receiver. Not one direction — both, one per machine.

- **Sender: L7 → L1.** Each layer wraps the payload in its own header = **encapsulation**.
- **Wire:** only L1 transmits — raw bits.
- **Receiver: L1 → L7.** Each layer strips its own header = **decapsulation**, passes the inside upward. ▹ Mental model: nested envelopes / Russian dolls — sender keeps wrapping, receiver opens in reverse. You never "study" app→physical as an order; that's just the sender's path. ▹ Refinement: **L2 wraps on both ends** — a header _and_ a trailer (the FCS, for local-link error detection). Every other layer adds a header only.

### OSI — Personal Deep Notes _(independently worked out — verified correct)_

> The concept I found hardest, consolidated. Encapsulation/decapsulation already covered above — this captures the extra insights.

▸ **Golden rule:** every message — TCP SYN, TLS handshake, HTTP request alike — takes the **same full path**: `App → Transport → Network → Data Link → Physical → 🌐 → Physical → Data Link → Network → Transport → App`. Higher layers define **what** the communication means (logical); **L1 is the only layer that physically moves bits.**

▸ **There is never a direct L4 ↔ L4 connection.** Even a pure TCP SYN (no app payload, so it _starts_ at L4) still goes L4→L3→L2→L1 across the wire, then L1→L2→L3→L4 up the server. Layers talk **logically** to their peer layer; physically, everything funnels through L1.

▸ **Does every layer handshake? No.**

|Layer|Handshake?|
|---|---|
|L4 Transport (TCP)|✅ 3-way: SYN / SYN-ACK / ACK (UDP: none)|
|L7 / L6 Application-side|Some do — **TLS handshake**, HTTP req/res|
|L3 / L2 / L1|❌ no universal handshake — just forwarding (Wi-Fi has link-specific control exchanges, but that's not an OSI-layer handshake)|

▸ **Full HTTPS flow** (`https://google.com`): `DNS lookup (usually UDP) → TCP 3-way handshake → TLS handshake (encryption) → HTTP GET → 200 OK + HTML → browser renders` ▹ This is the HTTPS-complete version of "How a Web Request Works" above — the extra step vs plain HTTP is the **TLS handshake** (L6) slotting in after TCP, before HTTP.

▸ **Mnemonic** (top-down, L7→L1, A·P·S·T·N·D·P): _"All People Seem To Need Data Processing."_

---

## How a Web Request Actually Works

▸ **CRUX** — the sequence: **DNS → TCP handshake → HTTP request → server processing → HTTP response → TCP teardown.**

- **TCP 3-way handshake:** SYN → SYN-ACK → ACK. **Teardown:** FIN → ACK → FIN → ACK. ▹ This packet-level detail is the old "what happens when you type a URL" question — rarely asked now, nice-to-know only.

**The 4 observations that actually matter:**

1. **Abstraction is a gift** — TCP hands you reliability + ordering; DNS + IP handle finding the server. You reason at the app layer.
2. **One "request" = many packets** — each adds latency. Ignorable _until it isn't_ (drives the LB discussion).
3. **A connection is shared state** — both client and server maintain it.
4. **Setup repeats per request** unless you reuse it → **HTTP keep-alive / HTTP/2 multiplexing**. Critical for systems needing persistent connections (real-time).

---

## Network Layer (L3) — IP

> HI walks the stack bottom-up: **Network (L3) → Transport (L4) → Application (L7)**. This is the L3 stop.

▸ **CRUX**

- **IP owns L3: routing + addressing.** That's the whole job; the rest is detail interviews rarely need.
- Nodes get an IP at boot, usually from a **DHCP** server.
- **Private vs public IPs:**
    - **Private —** arbitrary, you assign them on your own network; **not reachable from the internet.**
    - **Public —** **routable**, allocated by an **RIR** (Regional Internet Registry). The internet backbone is optimized to route between public IPs and knows where they live (e.g. anything `17.x.x.x` → Apple's routers). ▹ HI note: internet routing goes much deeper, but it's out of scope — know "IP = addressing + routing," then move up to L4.

---

## Transport Layer — TCP vs UDP (the real choice)

▸ **CRUX**

- **Default TCP.** In interviews it's assumed — often needn't even be said.
- **UDP** = "spray and pray": connectionless, no delivery/order guarantee, lower latency. Earn points by justifying it _correctly_.
- **QUIC** = "better TCP" (HTTP/3), modern perf, but not yet ubiquitous. Impresses perf-focused interviewers; spend your time elsewhere usually.

**Choose UDP when — any one of these holds.** Each row: the _criterion_, then a concrete _example_.

|Criterion (why UDP fits)|Examples|
|---|---|
|**Low latency is critical** — can't afford handshake + retransmit delays|online gaming, real-time apps|
|**Some data loss is acceptable** — a missing packet doesn't ruin the output|media streaming, VoIP|
|**High-volume telemetry / logs** — occasional loss is fine at scale|metrics, event logs|
|**You don't need browser support** (or have a fallback)|internal services, native apps|

**Two things to understand behind that table:**

- **Why loss-tolerance actually works (VoIP example).** In a voice call, a dropped packet = one tiny audio hiccup, and the conversation stays intelligible. That's _far_ better than TCP's alternative: detect the loss, retransmit the packet, and flood the network with ACKs — which adds delay and congestion to a live call. So "accept the hiccup" beats "guarantee every byte."
    
- **The browser catch (and the design fix).** Browsers can't speak raw UDP — only via **WebRTC**. So if a feature wants UDP (e.g. the flood of hearts/reactions in Facebook Live), you need a plan for browser users.
    
    - **Fix —** split by client: **native-app users** get the real-time **UDP** stream; **browser users** get a **batched HTTP** stream you spread out over time in the UI. Same feature, two delivery paths.

|Feature|UDP|TCP|
|---|---|---|
|Connection|connectionless|connection-oriented|
|Reliability|best-effort|guaranteed|
|Ordering|none|maintained|
|Flow/congestion control|no|yes|
|Header|8 bytes|20–60 bytes|
|Speed|faster|slower (overhead)|
|Use|streaming, gaming, VoIP|everything else|

---

## Application Layer — The Protocol Menu

> This is the meat. Pick the connection style the problem needs.

### HTTP / HTTPS

▸ **CRUX**

- Request-response, **stateless** (each request independent) — minimize stateful surface area; a simple HTTP server ≈ a pure function of its request.
- **Methods:** GET (idempotent, no body) · POST (create) · PUT (update) · PATCH (partial) · DELETE (idempotent).
- **Status codes:** 2xx success · 3xx moved (301 perm / 302 temp) · 4xx client (401 unauth, 403 forbidden, 404, 429 too many) · 5xx server (500, 502 bad gateway).
- **Headers** = flexible key/values (great API-design lesson — content negotiation via `Accept-Encoding`/`Content-Encoding` gives backward compat + graceful degradation).
- **HTTPS** = TLS/SSL, encrypts in transit vs eavesdropping/MITM. Public site → HTTPS always.

⚠ **Security (Problem → Fix):**

- **Problem —** HTTPS encrypts the body but doesn't prove the client generated it honestly. Trusting a `user_id` in the request body → attacker edits it → reads arbitrary users' data.
- **Fix —** never trust request-body identity; **validate server-side / derive identity from the auth token.** You _can_ include IDs, but only ones you can verify.

### REST / GraphQL / gRPC (API paradigms)

> Full modeling guidance → API Design deep dive. Here: when to reach for each.

- **REST** — default. Resources + HTTP verbs. Core Entities → resources (`GET /users/{id}`, `POST /users`, nested `GET /users/{id}/posts`). Think **resources, not operations** (`updateUser` → `PUT /users/{id}`; `startGame` → `PATCH /games {status:"started"}`). JSON is inefficient but rarely the bottleneck.
- **GraphQL** — client requests exactly the fields it needs.
    - **Problem it solves:** REST forces **under-fetching** (many round trips), **over-fetching** (bloated responses), or a new API per page.
    - **Where:** diverse clients / multiple teams / requirements that iterate. **Murky for interviews** (fixed requirements) — raise only when the problem is explicitly about _flexibility/uncertainty_.
- **gRPC** — HTTP/2 + Protocol Buffers (binary, ~15 bytes vs ~40 JSON, up to ~10× throughput). Strong typing catches errors at compile time.
    - **Where:** **internal** service-to-service, perf-critical, network-bound. **Not public-facing** (browsers don't support it; tooling immature). Pattern: REST external + gRPC internal.

⚠ **Rejection trap:** hyper-optimizing RPC protocol choice before handling real bottlenecks. Premature optimization.

### Server-Sent Events (SSE)

▸ **CRUX** — server pushes **many messages over one HTTP response**, processed line-by-line as they arrive. **Unidirectional** (server→client).

- Vs normal HTTP: you'd wait for the whole JSON blob; SSE streams chunks (`data: {...}` per line).
- **Where:** client needs events as they happen — notifications, live auction price, live scores.

⚠ **SSE limitations (Problem → Fix):**

- **Problem —** connection can't stay open forever (server/LB/proxy kills it); some bad networks batch all chunks into one response (defeating the point).
- **Fix —** the `EventSource` object **auto-reconnects with the last-received message ID**; server must **track prior messages and resend** what was missed. ▹ Most interviewers don't know these limits; mentioning them signals real implementation experience.

### WebSockets

▸ **CRUX** — persistent, **bidirectional**, TCP-style connection. Server can push without a prompt; client too.

- Initiated via HTTP **"upgrade"** → reuses cookies/headers, then WebSocket takes over the TCP connection. Binary messages; you define the payload (JSON is fine).
- **Where:** high-frequency **bidirectional** real-time — chat, games, live collaboration.
- **Needs an L4 load balancer** (persistent TCP). Every proxy/firewall/LB in the path must support WS.

⚠ **Rejection trap:** jumping to WebSockets unjustified. Stateful connections at scale are expensive and infra-heavy. If SSE or long-polling suffices, WS is overkill.

### WebRTC

▸ **CRUX** — **peer-to-peer** browser-to-browser, uses **UDP**. The only P2P protocol here; the goal is to send audio/video/data **directly between two clients** without relaying through your server.

**Why P2P is hard (the problem WebRTC solves):**

- Most clients **can't accept inbound connections** (security), and most users sit behind a **NAT** (Network Address Translation — your router shares one public IP among many private devices). So two browsers can't just "dial" each other directly by default.
- WebRTC's job is to punch through this so a direct connection can form. Two helpers make it work:
    - **STUN** = _Session Traversal Utilities for NAT._ Tells a client its own **public IP + port** (via "hole punching") so it can be reached from outside.
    - **TURN** = _Traversal Using Relays around NAT._ A **relay server** that bounces traffic between the two peers when a direct connection can't be established. Fallback only.

**Setup — the 4 steps (happy path):**

1. **Discover peers** — each client connects to a central **signaling server** that tracks who's available and their connection info.
2. **Find own address** — each client asks a **STUN** server for its public IP + port.
3. **Exchange info** — clients swap that connection info **through the signaling server**.
4. **Connect directly** — clients open a **direct P2P** connection and start streaming data (server no longer in the path).

▹ If step 4 fails (strict NATs/firewalls) → fall back to **TURN** relay. The signaling server is only used to _set up_ the call; media flows peer-to-peer after.

- **Where:** **video/audio calling & conferencing.** Occasionally collaborative editors — but those usually need a central server anyway to store/coordinate → **WebSockets** wins there (e.g. Google Docs). _(Alternative exists: WebRTC + CRDTs for truly serverless collab, but niche.)_

⚠ **Rejection trap:** designing P2P systems with WebRTC when the problem doesn't need it — the #1 way candidates go off the rails. It's genuinely painful to implement (connection losses even in the best builds). **Keep it to calling/conferencing** and you're safe. Don't over-invest here — low interview yield for your target roles.

---

## Load Balancing

> **Why it's in the networking chapter:** scaling out means adding more servers — but that only helps if clients know _which_ server to talk to. Deciding where each request goes is a **traffic-routing** problem, i.e. networking. So load balancing is the bridge from "one server" to "many."

### Scaling: vertical vs horizontal

▸ **CRUX** — **vertical** (bigger server) vs **horizontal** (more servers).

- Author's lean: **prefer vertical where possible** — modern hardware is powerful (→ `01_core_concepts §9`). But interviews usually default to **horizontal**, which _needs_ load balancing to route traffic.

### Client-side vs Dedicated LB

> Two ways to answer _"which server should this request go to?"_ — the **client decides**, or a **middleman decides**.

**Client-side LB — the client picks the server itself.**

- **How:** client queries a **service registry/directory** for the list of live servers, caches it, then connects **directly** to one. It polls (or gets pushed) updates when the list changes.
- **Why fast:** no extra hop per request — you sync the server list _periodically_, not on every call. Client can even pick the fastest server.
- **Cost:** every client must know your servers and keep that list fresh. Update speed is bounded by how fast you can notify all clients.
- **Examples:**
    - **Redis Cluster** — nodes run a **gossip** protocol so every node knows the full membership. Client connects to any node, learns the nodes + which shard holds what, then **hashes the key** to pick the right node. Hit the wrong one → Redis replies **`MOVED`** pointing to the correct node.
    - **DNS** — resolver returns a **rotated** IP list, so different clients hit different servers — DNS _is_ client-side LB. Bonus: this is how you avoid a **single-LB SPOF** (run two LBs, DNS rotates between them; one dies → clients try the other). Downside: updates bounded by **TTL** (far-flung resolvers cache entries).
- **Where:** (1) **few clients you control** (Redis client, gRPC's built-in internal LB) or (2) **many clients that tolerate slow updates** (DNS).

**Dedicated LB — a server/appliance sits between clients and backends.**

- **How:** client talks only to the LB; the LB knows the backend pool and picks a server.
- **Cost:** one **extra hop** per request.
- **Win:** clients stay dumb (never know backends exist) · server-list updates are **instant** · **fine-grained routing control** (L4/L7, algorithms, health checks).
- **Where:** everything else — especially **large numbers of clients you don't control** (most public-facing systems).

**When to use which:**

||Client-side LB|Dedicated LB|
|---|---|---|
|Who decides the server|the client|the LB (middleman)|
|Extra hop?|❌ no (direct connect)|✅ yes (client → LB → server)|
|Clients know backends?|yes — must sync the list|no — LB hides them|
|Update speed on server change|slow (bounded by sync / TTL)|fast (instant)|
|Routing control|limited|rich (L4/L7, algorithms, health checks)|
|Best for|internal microservices; coarse geo|public-facing, many uncontrolled clients|
|Examples|Redis Cluster, gRPC, DNS|AWS ELB/ALB/NLB, NGINX, HAProxy, F5|

▸ **The practical default (what people actually reach for):**

- **Public-facing / general case → dedicated LB.** This is the norm; assume it unless there's a reason not to.
- **Internal service-to-service → client-side** (gRPC ships with it). Interviewers often don't probe the lines between services, but say "client-side LB" if asked.
- **Global coarse distribution / LB failover → DNS** (a client-side form).

### L4 vs L7 (the interview question)

> Both are _dedicated_ LBs — this is the next choice once you've picked "dedicated." | | **L4** (transport) | **L7** (application) | |---|---|---| | Routes on | IP / ports, no content | HTTP content: URL, headers, cookies | | Connection | maintains persistent TCP client↔server | terminates + opens new to backend | | Speed | fast (minimal inspection) | more CPU (packet inspection) | | Best for | **WebSockets / persistent conns**, raw perf | HTTP traffic, smart routing, API-gateway-like |

▸ **Rule:** WebSockets → **L4**. Everything HTTP → **L7**. (Long-polling → L7 fine.)

### Health checks & algorithms

- **Health checks** — LB stops routing to dead servers → automatic failover = high availability. **TCP check** (accepting connections?) or **L7 check** (HTTP 200 vs 500/no-response).
- **Algorithms:** Round Robin · Random · Least Connections · Least Response Time · IP Hash (session persistence).
    - **Default:** round robin / random for stateless (new servers get traffic automatically).
    - **Persistent connections (SSE/WS):** **Least Connections** — stops one server hoarding all the long-lived connections.
- **Implementations:** hardware (F5 BIG-IP, 100s of M req/s) · software (HAProxy, NGINX, Envoy) · cloud (AWS ELB/ALB/NLB). Scaling the LB itself is rarely in scope → if throughput is huge, "use a hardware LB" is the escape hatch.

---

## Fault Tolerance & Regionalization _(deep-dive probe territory)_

> **Why this is still "networking":** networking isn't only the OSI stack — that's just _how_ machines talk. It also covers the two brutal realities of a real network: it's **slow** (latency = physics of the network) and **unreliable** (calls drop/time out). **Regionalization** addresses the slowness; **fault tolerance** addresses the unreliability. Same subject, practical half. _(Whole-chapter arc: protocols = the language · load balancing = spreading traffic · regionalization = the network is slow · fault tolerance = the network is unreliable.)_

### Regionalization & latency

▸ **CRUX**

- **Problem —** physics sets a latency floor. NY↔London ≈ **56ms theoretical** (fiber ≈ ⅔ c ≈ 200,000 km/s, ~5,600 km round trip), **~80ms real**; local **<1ms**. You can't beat the speed of light.
- **Fix —** **data locality**: keep data close together and close to the user. **Two ways to get it, depending on whether the data is cacheable:**
    - **Approach 1 — CDN** _(for static / cacheable data)._ Edge servers in hundreds of cities cache content near users, so a request is answered "just up the road" instead of crossing an ocean. Cuts latency **and** backend load (e.g. caching FB search results globally).
    - **Approach 2 — Regional partitioning** _(for dynamic / region-scoped data a CDN can't cache)._ Split data by region so each region holds only its own.
        - _Uber:_ a Miami rider never wants a NY driver. Bundle nearby cities → "Northeast US" region → its own DB + co-located servers → queries answered locally (very fast). Millions globally, but only thousands per city.

### Handling failures

> The fallacy of "the network is reliable." Design assuming calls fail, delay, or return garbage.

▸ **How the next three fit together** _(they always travel as a set — this is the frame):_

- They're **layers of one story**, not independent tricks, and they stack because they operate at different scopes:
    
    1. **Idempotency = the foundation** (design-time). Makes retrying _safe_ — without it you can't retry a write without risking a double-charge. Comes **first**, even though it feels like a "later" concern.
    2. **Retries + backoff = first response** to a _transient_ blip (one call's bad luck). Safe _because_ of idempotency.
    3. **Circuit breaker = escalation** when failure is _sustained_ — stops the collective retry storm so the dependency can recover.
- **Scope is why they don't overlap:** retries handle _one request's_ bad luck; the breaker watches the _failure rate across many requests_ and cuts them all off. Different levels.
    
- **One-liner:** _make writes idempotent → so you can retry safely with backoff → and if retries keep failing, a circuit breaker stops the storm so the dependency can recover._
    
- **Timeouts + Retries + Backoff** (Problem → Fix)
    
    - **Problem —** transient failures (slow server) need retrying; but naive immediate retries = a synchronized "jackhammer" that makes it worse.
    - **Fix —** **retry with exponential backoff + jitter** (randomness so clients don't retry in lockstep). Magic phrase interviewers want: _"retry with exponential backoff"_; senior add-on: _"with jitter."_
- **Idempotency** (Problem → Fix)
    
    - **Problem —** retrying a write with side effects double-charges ($10 → $20). Reads (GET) are naturally idempotent; writes aren't.
    - **Fix —** an **idempotency key** (unique per logical request, e.g. `userID + date`); server processes a given key **once**, returns the same result to retries.
- **Circuit Breakers** (Problem → Fix)
    
    - **Problem —** a dependency goes down → everyone retries → **cascading failure / thundering herd** pins it so it can't even restart.
    - **Fix —** circuit breaker states: monitor failures → exceed threshold → **trip open** (requests fail fast, no call attempted) → after timeout → **half-open** (test request) → success closes it, failure re-opens.
    - **Wins:** fail fast · reduce load on the struggling service · self-heal · fast fallbacks · contains blast radius.
    - **Apply to:** third-party API calls · DB connections · service-to-service · any network call that can slow/fail. Great answer when probed on reliability / failure modes / disaster recovery.

---

## Quick Recall (pass 3+)

|Situation|Reach for|
|---|---|
|Default transport|TCP (assumed)|
|Low-latency, loss-tolerant (gaming, media, VoIP)|UDP|
|Internal service-to-service, perf-critical|gRPC (binary, ~10×)|
|Client needs server pushes, one-way|SSE (auto-reconnect w/ last ID)|
|Bidirectional real-time (chat, games)|WebSocket + **L4 LB**|
|Video/audio calling|WebRTC (P2P/UDP, STUN/TURN)|
|Flexible client data needs, many teams|GraphQL (else murky in interviews)|
|Persistent-connection load balancing|L4 LB + Least Connections|
|Smart HTTP routing (URL/cookie/header)|L7 LB|
|LB single point of failure|2 LBs + DNS rotation|
|Global cacheable static content|CDN (edge)|
|City/region-scoped data (Uber)|regional partitioning|
|Retrying writes safely|idempotency key|
|Retry storms|exponential backoff + jitter|
|Dependency-down cascade / thundering herd|circuit breaker|
|Don't-trust-client identity|derive from auth token, validate server-side|
