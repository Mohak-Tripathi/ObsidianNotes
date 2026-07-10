# API Design — Deep Dive

> Hello Interview · Core Concepts (deep dive) · File `01b`. Overview in `01_core_concepts §2`. **Non-repetition:** protocol _nature_ (TCP/HTTP, binary, SSE/WS persistent connections) lives in `01a_networking §Application Layer`. This file = **resource modeling + design mechanics**.

---

## The Meta-Rule (read first)

▸ **CRUX**

- Most interviewers **don't care about perfect APIs.** Show a reasonable design, then move to the hard architecture.
- **≤ 5 minutes** on this step. Candidates fail more often by **over-investing** here than under-investing.
- Matters _more_ for **frontend / product / junior** roles (they spend more interview time on APIs).
- Unsure? Literally say _"I'll use REST APIs"_ and move on.

---

## Step 1 — Pick a Protocol

> _What_ each protocol is → `01a`. Here: the **signal words** that tell you which to pick.

|Protocol|Pick when — interviewer signal|Default?|
|---|---|---|
|**REST**|standard CRUD, web/mobile — maps to resources + HTTP verbs|✅ **yes, 90%**|
|**GraphQL**|"flexible data fetching" · "over/under-fetching" · mobile-vs-web need different data|only if signaled|
|**RPC (gRPC)**|"microservices" · "internal APIs" · high-performance service-to-service|internal only|

▹ Real-time (notifications, chat, live updates) → **WebSockets / SSE** — persistent connections, not traditional request/response APIs (→ `01a`).

---

## REST — The Default (spend your time here)

### Resource Modeling

▸ **CRUX**

- **Resources = your Core Entities** (from the delivery framework — bonus, they map straight over).
- Model **things that exist, not actions.** `book`/`purchase` are actions → wrong. `events`, `tickets`, `bookings` are resources → right.
- **Plural nouns** (`/bookings`, `/events`). Some interviewers check this; cheap to get right.

_Ticketmaster:_

```
GET  /events                 # list events
GET  /events/{id}            # one event
GET  /events/{id}/tickets    # tickets for an event
POST /events/{id}/bookings   # create a booking
GET  /bookings/{id}          # one booking
```

**Relationships — nested vs flat (Problem → choice):**

- **Problem —** how do you express "tickets belong to an event"?
- **Choice —** by whether the relationship is **required** or **optional**:
    - **Required → path / nested:** `/events/{id}/tickets` (you always need to say _which_ event).
    - **Optional → query param:** `/tickets?event_id=123&section=VIP` (you might want all tickets, or filtered).

### HTTP Methods + Idempotency

|Method|Does|Safe?|Idempotent?|
|---|---|---|---|
|**GET**|read, no change|✅|✅|
|**POST**|create new resource|❌|❌ (retry → duplicate booking)|
|**PUT**|replace whole resource (or create)|❌|✅|
|**PATCH**|partial update|❌|⚠️ depends ("set email"=yes; "append to list"=no)|
|**DELETE**|remove|❌|✅ (stays deleted; codes may differ 204→404)|

▸ **Why idempotency matters:** networks fail, clients retry. **GET/PUT/DELETE** are safe to retry; **POST/PATCH** aren't guaranteed → a retried POST can double-book. (Fix = idempotency key → `01a §Handling failures`.)

### Passing Data — 3 places, 3 roles

|Where|Role|Use for|Example|
|---|---|---|---|
|**Path param**|_structural_ — which endpoint/resource|required identifier|`/events/123`|
|**Query param**|_modifier_ — how to retrieve|optional filter/sort/paginate|`/events?city=NYC&page=2&limit=20`|
|**Request body**|_payload_ — the data itself|create/update data, large/sensitive|booking details JSON|

_Combined example:_

```
POST /events/123/bookings?notify=true
{ "tickets": [{"section":"VIP","quantity":2}], "payment_method":"credit_card" }
```

▹ Path `123` = which event (required) · query `notify` = optional behavior · body = the booking data.

### Returning Data

▸ **CRUX** — response = **status code + body (JSON).**

- Common codes: **200** ok · **201** created · **400** bad request · **401** auth required · **404** not found · **500** server error.
- **What interviewers actually want:** you know **4xx = client error** vs **5xx = server error.** Don't memorize the rest — obscuring exact codes with `X`s is fine.

---

## GraphQL — When Over/Under-Fetching Is the Problem

> _What it is_ → `01a`. Here: design mechanics + the one gotcha.

▸ **CRUX**

- Single endpoint; client sends a **query describing exactly the fields it wants**; server returns that exact shape.
- **Solves (Problem):** REST forces either **endpoint proliferation** (a new endpoint per client need) or **over-fetching** (one fat endpoint returns MBs clients don't use).
- **Pick when:** diverse clients with different data needs · frontend needs to iterate without backend changes.
- **Don't default to it** — adds query parsing, schema validation, caching complexity. Solve core architecture with simpler tools first.

**Schema design** — define **types + relationships** (not endpoints):

```graphql
type Event { id: ID!  name: String!  venue: Venue!  tickets: [Ticket!]! }
type Query { event(id: ID!): Event   events(limit: Int, after: String): [Event!]! }
```

Clients traverse `Event → Venue` in one query.

⚠ **The N+1 problem (Problem → Fix):**

- **Problem —** query 100 events with their venues → 1 query for events + N queries for each venue = **101 queries** instead of 2.
- **Fix —** **batching / DataLoader** pattern groups the related lookups. (Adds complexity REST doesn't have.)

▹ **Authz is field-level** (not endpoint-level): a user might see `name`/`date` but not `venue` — controlled in the field resolver.

---

## RPC / gRPC — Internal Service-to-Service

> _What it is / binary perf_ → `01a`. Here: the design shape, how it actually works, + interview handling.

▸ **CRUX**

- **Action-oriented**, not resource-oriented — call remote functions like local ones: `getEvent("123")`, `createBooking(eventId, userId, tickets)`. Contrast REST's `GET /events/123`.
- Runs on **HTTP/2 + Protocol Buffers (binary)** → faster than JSON-over-HTTP, especially service-to-service. (Apache Thrift is the other notable RPC framework.)

**How it works (the mechanism):**

1. Write a **`.proto` file** — the service contract: methods + message shapes.
2. Run **`protoc` + the gRPC plugin** → generates a **client stub** and a **server skeleton** in each language you need.
3. Client calls a method on the **local stub** as if it were a normal function → the stub serializes the args into a protobuf message, ships it over HTTP/2, and hands back the deserialized response. Network details stay hidden. ▹ _Why it feels local:_ the stub **is** a local object mirroring the remote service's methods. You call `stub.GetEvent(...)`; gRPC does the wire work.

_Example `.proto`:_

```proto
service TicketService {
  rpc GetEvent(GetEventRequest) returns (Event);
  rpc CreateBooking(CreateBookingRequest) returns (Booking);
}
message GetEventRequest { string event_id = 1; }
message Event { string id = 1; string name = 2; int64 date = 3; Venue venue = 4; }
```

▹ One definition → generated code in many languages → **compile-time type safety** across a polyglot backend (Go ↔ Java catches mismatches before deploy). The field numbers (`= 1`, `= 2`) are **tags**: protobuf serializes the _tag_, not the field name → compact binary.

**4 call types gRPC supports** (the streaming edge over REST):

|Type|Shape|
|---|---|
|**Unary**|1 request → 1 response (normal function call)|
|**Server-streaming**|1 request → stream of responses|
|**Client-streaming**|stream of requests → 1 response|
|**Bidirectional**|both stream freely|

**Use when:** perf critical (binary + HTTP/2) · type safety matters · **internal service-to-service** (don't need REST's resource semantics) · **streaming** needed.

▸ **Interview handling:** you usually **don't outline internal APIs** in the API step — design the **user-facing** APIs only. At most, note in HLD: _"internal services talk over gRPC."_ Pattern: **REST external + gRPC internal.**

> 📎 **Resource (for later — implementation):**
> 
> - Concept + protobuf (official intro): `https://grpc.io/docs/what-is-grpc/introduction/`
> - Core concepts / the 4 call types: `https://grpc.io/docs/what-is-grpc/core-concepts/`
> - Hands-on quickstart (~15 min, working client+server): `https://grpc.io/docs/languages/go/quickstart/` — swap `go` for your language.

---

## Common Patterns (all API types)

### Pagination

▸ **CRUX** — never return millions of rows at once; chunk them.

||Offset-based|Cursor-based|
|---|---|---|
|How|skip N, take M: `?offset=20&limit=10`|pointer to last record: `?cursor=abc&limit=10`|
|Pro|simple, "jump to page 5" works|**stable** under inserts|
|Con|**Problem —** inserts shift rows → duplicates/missed records|no random page jumps; harder to build|
|Cursor =|—|encoded ref to last record (id/timestamp)|

▸ **Interview:** **offset is fine** unless real-time / high-volume data — then **cursor**. Interviewers care more that you _remembered_ pagination than which kind.

### Versioning

▸ **CRUX** — evolve APIs without breaking existing clients.

- **URL versioning** (`/v1/events`) — explicit, easy to explain → **default for interviews.**
- **Header versioning** (`API-Version: 2`) — cleaner URLs, less obvious/harder to test. ▹ HI often omits versioning in breakdowns — low interviewer interest, though it matters in practice.

### Security

▸ **Mental model — every request passes 3 gates:** ① **AuthN** (who are you? → API key or JWT) → ② **AuthZ** (allowed? → RBAC roles) → ③ **Rate limit** (not too much? → 429).

▸ **CRUX** — **Authentication** = _who are you?_ (verify identity). **Authorization** = _are you allowed?_ (verify permission). Both checked per request.

**API keys vs JWT:**

||API Keys|JWT|
|---|---|---|
|What|long random string = app password|signed token encoding user info + expiry|
|Server state|lookup key in DB|**stateless** — verify signature, read claims, no DB lookup|
|Best for|**server-to-server**, 3rd-party dev access|**user sessions** (web/mobile)|
|Not for|user-facing apps (no expiry, no user context)|—|

- **RBAC** — assign **roles → permissions**; check authz against role (customer / venue_manager / admin). E.g. `GET /bookings/{id}` → authenticated? **and** owns-it-or-admin?
- **Rate limiting (Problem → Fix):** **Problem —** abuse/scalping/accidental overuse. **Fix —** per-user / per-IP / per-endpoint limits; return **429 Too Many Requests**. Implement at API gateway / middleware.

▸ **Interview handling:** usually low-focus. Say _"these endpoints require auth — JWT or DB-backed session,"_ note which **roles** hit which endpoints, and _"we'll rate-limit to prevent abuse."_ Don't design the algorithms unless asked.

---

## Quick Recall (pass 3+)

|Situation|Reach for|
|---|---|
|Default protocol|REST (say it, move on)|
|Over/under-fetching, diverse clients|GraphQL (+ DataLoader for N+1)|
|Internal service-to-service, perf|gRPC (action-oriented, protobuf)|
|Real-time push|WebSockets / SSE (→ `01a`)|
|Resource naming|plural nouns, things-not-actions|
|Required relationship in URL|path / nested `/events/{id}/tickets`|
|Optional filter|query param `?event_id=123`|
|Which resource / how to retrieve / the data|path / query / body|
|Safe-to-retry methods|GET, PUT, DELETE (POST/PATCH not)|
|Retry-safe writes|idempotency key (→ `01a`)|
|Big result set|pagination — offset default, cursor for real-time|
|API evolution|URL versioning `/v1/`|
|Who are you / are you allowed|authN / authZ|
|Server-to-server auth|API key|
|User session auth|JWT (stateless)|
|Different user powers|RBAC (roles → permissions)|
|Abuse protection|rate limit → 429|
|Meta|≤5 min, don't over-invest, REST + move on|