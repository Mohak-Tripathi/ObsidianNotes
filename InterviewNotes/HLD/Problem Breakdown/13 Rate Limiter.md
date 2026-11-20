# Rate Limiter — Problem Breakdown

> 📐 **Revision note (calc):** **1M req/s · 100M DAU · check <10ms · availability ≫ consistency.** 📐 ⭐⭐ **One Redis ≈ 100–200k ops/s; ≥2 ops per check ⇒ 50–100k checks/s ⇒ 10 shards.** ⚠⚠ ⊕ **My check: HI's own flow sends 6 commands per check (`HMGET`, `MULTI`, 2×`HSET`, `EXPIRE`, `EXEC`) ⇒ ~17–33k checks/s per shard ⇒ 30–60 shards. 10 shards holds only with ONE Lua call per check (5–10 shards) — and then with zero headroom.** 📐 **Fixed-window boundary: 200 in ~2s · TCP handshake 20–50ms · `EXPIRE` 3600s · 16,384 cluster slots · rules polled every 30s.**

>  **Evan King, published Jul 31, 2025** · ⭐⭐ **"medium"** · **Asked at: Microsoft +12** · ⭐⭐ **THREE patterns: `Dealing with Contention` → `03b` · `Scaling Writes` → `03e` · `Scaling Reads` → `03d`** · Cross-refs: ⭐⭐⭐ **`05t` — token buckets, already met there** · ⭐⭐⭐ **ChatGPT (31) DD4 (request-count vs cost limiter) and DD2 (pub/sub has no memory)** · ⭐⭐ **Payment System DD1 — nonce store, same Redis primitive** · ⭐⭐ **`05g` — one hot key ⇒ replicate** · **`02a` Redis · `02d` API Gateway · `02i` Zookeeper · `01h` · `01i`.**
> 
> **Calibration:** ⭐⭐ **ONE pass, plus a second look at the atomicity and failure-mode points (my call).** ⭐⭐ **HI says this question is asked very differently at different companies — some want LLD and even code.** ⭐ **Order: §4.2 (algorithm + atomicity) > DD1 > DD2 > DD4 > DD3 > DD5.**
> 
> - ⭐⭐ **What actually scores:** **(a)** ⭐⭐⭐ **Token Bucket explained: capacity = burst, refill = steady rate** · **(b)** ⭐⭐⭐ **gateway placement, and why** · **(c)** ⭐⭐⭐ **Redis shared state; the read-modify-write race fixed by ONE Lua script, not MULTI/EXEC** · **(d)** ⭐⭐⭐ **shard by client key; Redis Cluster; the ops/s arithmetic** · **(e)** ⭐⭐⭐ **fail-open vs fail-closed, chosen with a reason, plus replicas** · **(f)** ⭐⭐ **429 + headers; fail fast** · **(g)** ⭐ **hot keys, pooling, regions, poll vs push.**
> - ⭐ **Transferable primitives:**
>     - ⭐⭐⭐ **A read-modify-write on shared state must be ONE atomic unit — the read has to be inside, not just the write.**
>     - ⭐⭐⭐ **Shard by the identity you limit.** ▸ **A single hot key can't be sharded — split, lease or block it.**
>     - ⭐⭐⭐ **A guard on the hot path of everything is a dependency of everything.** ▸ **Pick its failure mode first; give it a degraded fallback.**
>     - ⭐⭐ **Where the check runs decides what it can see.**
>     - ⭐⭐ **State you can afford to lose is easy to make available.**
>     - ⭐ **Poll for config; push needs a poll as backstop.**
>     - ⭐ **Ask whether the PRODUCT can change first (clients that limit themselves, tiers for heavy users).**
> - ⭐ **Re-run (cross-ref, NOT re-explained):** **token bucket (`05t`) · Redis as shared state (`02a`) · gateway (`02d`) · consistent hashing, shards, replicas (`03e`) · hot key ⇒ replicate (`05g`) · request-count limiter vs cost metering (ChatGPT DD4) · pub/sub loses messages (ChatGPT DD2) · ZooKeeper (`02i`).** **Genuinely new:** ⭐⭐⭐ **the four window algorithms side by side** · ⭐⭐⭐ **Lua script as the unit of atomicity** · ⭐⭐ **fail-open vs fail-closed as a designed choice** · ⭐⭐ **Redis Cluster hash slots** · ⭐ **dynamic rules: poll vs push.**

---

## 0 · Understanding the problem

💬 **A rate limiter controls how many requests a client can make in a window; over the limit gets HTTP 429.** ▸ **It prevents abuse, protects servers from bursts, and keeps usage fair.**

⭐⭐ **Scope: a request-level limiter for a social platform's API, server-side only — clients can't be trusted to regulate themselves. Client-side limiting is a complement (DD4).**

⭐ **HI's path: algorithm choice + distributed HLD; entities and interface short; most time on algorithms and scaling.** ⚠ **Some interviewers want LLD with code.** ⊕ **LLD version: a `RateLimiter` interface, a Strategy per algorithm, rules as config, thread-safe per-key state — a different interview.**

---

## 1 · Requirements

### 1.1 Functional

1. ⭐⭐ **The system should identify clients by user ID, IP address, or API key to apply appropriate limits.**
2. ⭐⭐⭐ **The system should limit HTTP requests based on configurable rules (e.g., 100 API requests per minute per user).**
3. ⭐ **When limits are exceeded, the system should reject requests with HTTP 429 and include helpful headers (rate limit remaining, reset time).**

⚠ **Below the line:** **Complex querying or analytics on rate limit data · Long-term persistence of rate limiting data.**

### 1.2 Non-functional

📐 ⭐ **Ask scale first. Assumed: 1M requests/s across 100M DAU.**

1. ⭐⭐ **The system should introduce minimal latency overhead (< 10ms per request check).**
2. ⭐⭐⭐ **The system should be highly available. Eventual consistency is ok as slight delays in limit enforcement across nodes are acceptable.**
3. ⭐⭐ **The system should handle 1M requests/second across 100M daily active users.**

⚠ **Below the line:** **Strong consistency guarantees across all nodes.**

> ⚠ **HI drifts on the scale: 100M DAU here, "10M users" at the start of the deep dives.** ⊕ **Use 1M req/s; the user count never enters the maths.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 1.3 ⭐⭐⭐ The design driver — a check on every request, against shared mutable state, that must cost less than the request it guards

|Constraint|What it breaks|Fixed by|
|---|---|---|
|⭐⭐ **limits are global across gateways**|**per-server counters**|**central state in Redis (§4.2)**|
|⭐⭐⭐ **many gateways update one client's counter**|**read, then write — a race**|**one atomic Lua script (§4.2)**|
|⭐⭐ **1M checks/s**|**one Redis**|**DD1 shard by client key**|
|⭐⭐⭐ **the limiter sits in front of everything**|**its outage = the API's outage**|**DD2 failure mode + replicas**|
|⭐ **<10ms on every request**|**a new connection per check, a far region**|**DD3 pooling + regions**|
|⭐⭐ **one client can flood one shard**|**sharding by key**|**DD4 hot keys**|
|⭐ **rules change in production**|**hard-coded limits**|**DD5 poll or push**|

### 1.4 Planning the approach

⭐ **Entities and interface fast; then the three FRs; then deep dives on the NFRs.**

---

## 2 · Core Entities

- **Rules** — ⭐ **the policies: requests per window, which clients, which endpoints (e.g. authenticated users 1000/hour; search 10/min per IP).**
- **Clients** — ⭐ **who is limited: user ID, IP, API key, or a combination; each has usage state per applicable rule.**
- **Requests** — **the input: client identity, endpoint, timestamp.**

**Flow: a Request arrives → identify the Client → look up its Rules → check usage → allow or deny.**

> ⚠ **The thing we actually STORE is none of these.** ⊕ **It is the bucket: `{tokens, lastRefill}` keyed by (client, rule). "Requests" is an input, not a stored entity. HI only reaches the bucket in §4.2.**
> 
> ■ **— end of insert · HI write-up resumes below —**

---

## 3 · System Interface

```
isRequestAllowed(clientId, ruleId) -> { passes: boolean, remaining: number, resetTime: timestamp }
```

- ⭐ **`remaining` and `resetTime` feed `X-RateLimit-Remaining` / `X-RateLimit-Reset`.**
- ⚠⚠ **It takes ONE `ruleId`, but §4.1 says a request is checked against several rules (user, IP, global, endpoint) and the most restrictive wins.** ⊕ **The honest signature takes a client and an endpoint and resolves the rules itself.**
- ⚠ **"Reset time" is a window idea. A token bucket has no reset — it refills continuously.** ⊕ **For a bucket, say "time until the next token" and send it as `Retry-After`.**

---

## 4 · High-Level Design

⭐ **An MVP first — it need not scale. Walk the FRs one by one.**

### 4.1) The system should identify clients by user ID, IP address, or API key to apply appropriate limits

⭐⭐ **Two decisions, connected: where the limiter lives, and how a client is identified.**

⚠ **Rung labels are mine, except that HI himself calls the dedicated service "Good".**

#### ⚠⚠ Bad — in-process, inside each application server

- **Each server or microservice limits from its own in-memory counters: fast, no network call, no dependency.**
- ⚠⚠ **Each server sees only its own traffic. With 5 servers behind a load balancer, one user can do 100 per minute on each — 500 in total — and if the balancer's routing changes, limits become unpredictable.** ⭐ **Works only with a single server, or if limits can be off by a factor of the server count.**
- ⊕ **Cheap fix HI skips: route each client to one server, so local counters are exact (at the cost of uneven load).**

**Why climb:** ⭐ **a limit needs one global view of each client.**

#### Good — a dedicated rate-limiting service

- **Its own microservice. The app server asks "should I allow user 12345?" and gets yes or 429. The service holds global state, so 100/min means exactly 100/min whatever the server count.** ⭐ **Flexibility: the app can pass rich context (tier, account status, endpoint, even "extra allowance on Black Friday"), and different services can have different limiters.**
- ⚠⚠ **Four costs:** **① latency: an extra network round trip before every request (HI's example: 10ms) · ② another point of failure: fail open (risk overload) or fail closed (API offline)? · ③ operational weight: deploy, monitor, scale, redundancy, replication · ④ network issues: slow limiter — wait, or time out and guess? Partitions?**

**Why climb:** ⭐ **stop bad traffic before it costs an app-server hop, and drop the extra service.**

#### ⭐⭐⭐ Great — in the API Gateway (HI's pick)

- **The limiter runs at the edge, in the gateway or load balancer. It inspects the request (IP, auth headers, API key), applies limits, and either forwards or returns 429.** ✅ **The most popular production choice: simple, strong, and app servers never see blocked requests — HI's bouncer: troublemakers are turned away at the door.**
- ⚠ **Limits: ① context — it sees only the HTTP request (headers, URL, IP, basic auth), so "premium gets 10× limits" works only if the tier is in the JWT · ② state needs a fast store, usually Redis, which brings its own slow/unavailable cases.**
- ⚠⚠ **HI says the gateway gives "centralized control without adding extra network calls to every request". That is wrong.** **Every check is a gateway → Redis round trip; DD3 says exactly that.** ⊕ **The real difference from the dedicated service: ONE hop (gateway → Redis) instead of two (app → limiter → Redis), and blocked requests never reach the app.**

#### How do we identify clients?

⭐ **At the gateway we have only the request: path, headers (`Authorization`, `User-Agent`, `X-API-Key`), query params, IP. External lookups add latency, so avoid them.**

- ⭐ **User ID (JWT in `Authorization`) · IP (`X-Forwarded-For`; beware NATs) · API key (`X-API-Key`).** ▹ **Ask the interviewer which apply.**
- ⭐⭐ **In practice you layer rules and enforce the most restrictive:** **per-user ("Alice 1000/hour") · per-IP ("100/min") · global ("50,000 requests/second total") · endpoint-specific (search 10/min, profile updates 100/min).** **Alice at 50 of 1000 but her IP at its 100 limit ⇒ blocked.**

> ⚠⚠ **Three things HI leaves loose in this one block.**
> 
> - ⚠⚠ **Layered rules mean several buckets per request — user, IP, endpoint — and under sharding (DD1) they live on DIFFERENT shards.** ⊕ **That is several round trips, and they aren't atomic: a token taken from the user bucket is lost if the IP bucket then rejects. HI never says. The NFR allows approximation, so accept the small leak and run the checks in parallel.**
> - ⚠⚠ **A global limit of 50,000 req/s contradicts the 1M req/s target, and one global key is a single hot key on one shard (DD4).**
> - ⚠ **`X-Forwarded-For` is client-controlled unless a trusted proxy sets it. Reading the wrong hop lets an attacker rotate fake IPs — a strange gap given HI's "clients can't be trusted".** ⊕ **Take the hop your own proxy appended.** ▹ **Judgment call.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 4.2) The system should limit requests based on configurable rules

⭐ **HI: "not commonly the central focus" of this interview — name the options, choose, don't write pseudocode.**

#### The four algorithms

- **Fixed window counter** — ⭐ **time cut into fixed windows (1 min); a counter per client resets each window; over the limit ⇒ reject until reset. Simplest: a map of client → (counter, window start).** ⚠ **Boundary effect: 100 at 12:00:59 then 100 at 12:01:00 ⇒ 200 in ~2s. Also starvation if the limit is hit early in the window.**
- **Sliding window log** — ⭐ **a log of request timestamps per client; drop those older than the window; reject if the rest exceeds the limit. Exact: no boundary effect, no unfair bursts.** ⚠ **Memory: 1000 req/min ⇒ 1000 timestamps per user, times millions of users; plus the scan on every request.**
- **Sliding window counter** — ⭐ **hybrid: counters for the current and previous window, weighted by how far into the current window you are (30% in ⇒ 70% of previous + 100% of current). Much better than fixed, two counters per client.** ⚠ **An approximation that assumes even traffic within windows; the maths is easy to get wrong.**
- **Token bucket** — ⭐⭐⭐ **a bucket holds up to N tokens (burst capacity) and refills at a steady rate; each request takes one; none left ⇒ reject. Example: capacity 100, refill 10 per minute ⇒ 100 at once, then wait. Track `(tokens, last_refill_time)` per client.** ⚠ **Hard parts: choosing capacity and refill rate, and cold start (idle clients begin with a full bucket).**

⭐⭐⭐ **HI picks Token Bucket: best balance of simplicity, memory and real bursty traffic (he cites Stripe).**

> ⚠ **A loose end in the choice itself.**
> 
> - ⚠ **Parameters drift: 100 tokens + 10/min in the explanation, 1 token/s in the Redis walkthrough, and the FR example is "100 per minute".** ⊕ **"100/min" isn't a bucket setting. Capacity = the burst you allow; refill = 100/60 per second. A full 100-token bucket also refills during the minute, so up to ~200 can pass in the first minute — the same shape as the fixed-window boundary he criticises.**
> 
> ■ **— end of insert · HI write-up resumes below —**

#### Where does the bucket live? Redis

⭐⭐ **Per-gateway memory is the in-process problem again: Alice's 50 + 50 requests across Gateways A and B look like 50 each, and both allow them. So all gateways share one Redis, the single source of truth.**

**The flow (HI's):** **① a request for `alice` reaches Gateway A ② `HMGET alice:bucket tokens last_refill` ③ the gateway adds tokens for the elapsed time (30s at 1 token/s ⇒ +30), capped at capacity ④ it writes back atomically: `MULTI` · `HSET alice:bucket tokens <new>` · `HSET alice:bucket last_refill <now>` · `EXPIRE alice:bucket 3600` · `EXEC` ⑤ at least 1 token ⇒ allow and decrement; none ⇒ reject.** ▹ **`EXPIRE` deletes idle buckets after an hour, preventing a memory leak.**

⭐⭐⭐ **"But wait — there's a race condition."** **The `HMGET` is OUTSIDE the transaction. Two gateways read the same count, both decide to allow, both write: 2 requests pass on 1 token.** ⭐⭐⭐ **The fix: move read, calculate and write into ONE Lua script. Redis runs a script atomically, so the whole decision is race-free.**

> ⭐⭐ **Pattern: Dealing with Contention (`03b`)** — **a classic: concurrent read-modify-write loses updates even if each command is atomic. Widen the atomic boundary to the whole sequence.**
> 
> ■ **— end of insert · HI write-up resumes below —**

⭐ **Why Redis, per HI: sub-millisecond speed · `EXPIRE` cleans inactive buckets · replication for availability · atomic operations.**

> ⚠⚠ **HI contradicts himself, and the Senior bar repeats the error.**
> 
> - ⚠⚠ **He has just shown `MULTI`/`EXEC` does NOT prevent the race. Then "Why Redis" lists "The MULTI/EXEC transaction ensures no race conditions between gateways" as a benefit.** ⚠⚠ **The Senior bar says candidates should "suggest MULTI/EXEC transactions". Say Lua.** ⊕ **Textbook: `MULTI`/`EXEC` batches writes; guarding a read needs `WATCH` or a script.**
> - ⚠⚠ **The flow is inconsistent: ④ writes the REFILLED count in the transaction, ⑤ then decrements in a second, non-atomic write.** ⊕ **In the script, refill, check and decrement happen together.**
> - ⚠ **The gateway supplies `<now>`; with many gateways, clock skew corrupts refill.** ⊕ **Read `TIME` inside the script.** ⚠ **`EXPIRE 3600` is wrong if a bucket needs longer than an hour to refill.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 4.3) When limits are exceeded, reject requests with HTTP 429 and helpful headers

#### Drop or queue?

- ⭐⭐ **Fail fast: return 429 immediately.** ⚠ **Queuing "sounds user-friendly" but costs more: queued requests hold memory and resources; users think they failed and retry, adding load; and queue delay makes response times unpredictable.** ▹ **Batch systems are the niche exception.**

#### Make the response helpful

- ⭐ **`429 Too Many Requests` is the standard code. Headers: `X-RateLimit-Limit` (ceiling, e.g. 100) · `X-RateLimit-Remaining` (e.g. 0) · `X-RateLimit-Reset` (Unix timestamp). Some systems add `Retry-After` (seconds).**

```
HTTP/1.1 429 Too Many Requests
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 0
X-RateLimit-Reset: 1640995200
Retry-After: 60
Content-Type: application/json

{ "error": "Rate limit exceeded",
  "message": "You have exceeded the rate limit of 100 requests per minute. Try again in 60 seconds." }
```

- ⭐ **Well-behaved clients back off from these.** ▹ **In the interview, just call out 429 + headers.** ⊕ **For a token bucket, `Retry-After` is the honest value (§3).**

---

## 5 · Deep Dives

⭐ **Up to now: one Redis, many gateways. HI leads with the NFRs (scale, availability, latency), then two extras (hot keys, dynamic rules). He expects the interviewer to jump in.**

### 1) How do we scale to handle 1M requests/second?

📐 ⭐⭐ **One Redis does ~100–200k ops/s; a check needs at least `HMGET` + `HSET` ⇒ ~50–100k checks/s per instance. At 1M/s the single instance is the bottleneck: partition the data so each request knows which instance to ask.**

> ⭐⭐ **Pattern: Scaling Writes (`03e`)** — **millions of counter updates per second, each an atomic read-modify-write.**
> 
> ■ **— end of insert · HI write-up resumes below —**

- ⭐⭐⭐ **Shard so all of a client's requests always hit the same shard — otherwise Alice's state is split and useless.** **Consistent hashing on the client key: user ID for authenticated users, IP for anonymous, API key for developer requests. Each client lives on exactly one shard; load spreads evenly.**
- ⭐ **Each gateway gets routing logic: extract the identifier, hash it, send the check to that shard. The Token Bucket logic is unchanged — only the Redis instance differs.** 📐 **10 shards × ~100k ⇒ 1M/s.**
- ⭐⭐ **In production use Redis Cluster: 16,384 hash slots spread over the nodes; `alice:bucket` maps to a node by its slot, so gateways just connect to the cluster and routing is automatic.**

> ⚠⚠ **What HI leaves loose.**
> 
> - ⚠⚠ **The sizing assumes two commands per check; his §4.2 flow sends six.** ⊕ **Only Lua makes it one — then 10 shards is exactly 1M/s with no room for bursts or a failover; plan ~2×.**
> - ⚠⚠ **Layered rules put one request's buckets on different shards (see §4.1). A Lua script can only touch keys on ONE shard; in Cluster, keys must share a slot.** ⊕ **You can co-locate one client's own rules with a hash tag, but never a user's key with an IP's key.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 2) How do we ensure high availability and fault tolerance?

⚠⚠ **Each shard is now critical: if one dies, every client whose data lives there loses rate limiting, and aggressive retries can cascade.** ⭐ **First, the failure mode.**

⚠ **HI: both are "good" options and it depends on the system — so these are not a ladder.**

#### Option A — fail closed

- **Can't reach Redis ⇒ reject everything (503 or 429); nothing unverified gets through.**
- ⚠⚠ **It takes the API offline in an outage, even with healthy backends; retries add load — often worse than the problem it solves.** ⭐ **Legit uses: financial systems and high-security environments that prefer rejecting to unlimited access.**

#### Option B — fail open

- **Can't reach Redis ⇒ skip the check and forward everything; the API stays up.**
- ⚠⚠ **No protection: attackers can overwhelm the backend. Worse, if Redis failed BECAUSE of load, failing open sends all of it downstream — on a social platform in a viral spike, a limiter outage becomes a platform outage.**

⭐⭐⭐ **HI's choice for this system: fail closed.** **Limiter failures often coincide with traffic spikes, which is when protection matters most; brief rejected requests beat a cascading collapse.**

⭐⭐ **Then prevention, which beats damage control: master–replica replication per shard; a replica is promoted automatically when the master fails; Redis Cluster does this itself. Costs: more infrastructure, and replica lag.**

> ⚠⚠ **HI's choice sits badly with his own requirements.**
> 
> - ⚠⚠ **NFR 2 says "highly available", "availability ≫ consistency". Fail closed makes a limiter outage an API outage — the limiter becomes the product's single dependency, and HI's own challenge text calls it often worse. He cites financial systems as the legit case, then picks it for a social feed.**
> - ⚠⚠ **The choice is binary. The standard answer is a third option.** ⊕ **Fail open to a LOCAL limiter: each gateway keeps in-memory buckets with a conservative limit (about limit ÷ gateway count). You degrade to the Bad rung of §4.1 — approximate but still protective — for the outage only.** ▹ **Judgment call.**
> - ⚠ **With sharding, one shard down hits ~1/10 of clients, not the whole API; HI's "offline" is the all-shards case.**
> - ✅ ⊕ **Eventual consistency makes replication easy: async replication lag after a failover only means a few clients get a few extra tokens.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 3) How do we minimize latency overhead?

⭐ **Every check is a round trip to Redis. Redis answers in under a millisecond; the network adds several ms. At 1M req/s that matters.**

- ⭐⭐⭐ **Connection pooling — the most important one.** **Persistent, reused connections instead of a new one per check avoid the TCP handshake (20–50ms by distance). Most clients pool automatically; tune pool size to request volume and Redis response time.**
- ⭐⭐ **Geographic distribution — the biggest win.** **Gateways and Redis clusters in several regions; a user in Tokyo should not talk to Virginia. Trade-off: data consistency across regions — HI accepts eventual consistency between regions for lower latency.**

> ⚠⚠ **Two contradictions.**
> 
> - ⚠⚠ **Lua appears here as an optional "optimisation to avoid unless asked". In §4.2 Lua is the REQUIRED fix for the race, and in DD1 it is what makes the 10-shard sizing true.** ⊕ **Treat it as core, not optional.**
> - ⚠⚠ **"Eventual consistency between regions" has no mechanism.** ⊕ **If each region has its own Redis, a client who reaches two regions gets up to double the limit. Options: pin a client to a home region, or give each region a share of the limit.** ▹ **Judgment call.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 4) How do we handle hot keys (viral content scenarios)?

⭐ **A hot key = one client generating tens of thousands of checks/s, enough to overwhelm its shard. It can be abuse (DDoS, a misconfigured bot) or a legitimate heavy client (analytics, data pipelines, an aggressively refreshing mobile app).**

> ⭐ **Pattern: Scaling Reads (`03d`)** — **HI: rate limiters mostly write, but a hot key creates extreme pressure on one shard.**
> 
> ■ **— end of insert · HI write-up resumes below —**

- ⭐ **Legitimate heavy clients: client-side limiting (SDKs obey the headers) · batching operations into fewer requests · premium tiers, maybe dedicated infrastructure.**
    
- ⭐ **Abusive traffic: auto-block after repeated limit hits (say 10 in a minute) into a blocklist held on one Redis shard and checked on cache misses · DDoS protection (Cloudflare, AWS Shield).**
    

⭐⭐ **The insight: client-side limiting complements the server side. You can't trust it for security, but it cuts load and stops good clients from creating hot shards.** ⭐ **Shared IPs (corporate NATs, public WiFi): set higher IP limits up front and lean on per-user limits.**

> ⚠⚠ **This dive barely answers its own title.**
> 
> - ⚠⚠ **Almost every item is a product or ops change, not a hot-key technique.** ⊕ **Missing: split the key into k sub-buckets (limit ÷ k each) · let gateways LEASE a batch of tokens and serve locally · a short-lived local deny list.** ▸ **One client is one key is one shard — sharding can't help; "too much traffic for one key → replicate" (`05g`).**
> - ✅ **Matches the thread "ask whether the PRODUCT can change first": client-side limiting and tiers cut load before any engineering does.**
> - ⚠ **"Cache misses": no cache exists, and a blocklist on ONE shard is itself a hot key ⇒ ⊕ cache it locally with a TTL. The global limit from §4.1 is a hot key by design.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 5) How do we handle dynamic rule configuration?

⭐ **Production needs to change limits without a deploy: raise them for a launch, give premium customers more, cut them fast under attack.**

⚠ **HI gives two approaches; not strictly better, so no ladder.**

#### Approach A — poll a config store

- ⭐ **Rules in a database or config service; gateways poll (say every 30s) and cache locally. Most common: simple, covers most cases.**
- ⚠ **Update delay: an emergency cut can take up to ~30s to reach all gateways. Fine for most operations, bad for urgent ones.**

#### Approach B — push

- ⭐ **Changes pushed to every gateway at once: ZooKeeper (`02i`) was built for this (watch notifications); alternatives are Redis pub/sub or a custom service. Updates land within seconds.**
- ⚠⚠ **Much more complexity: connection failures, making sure every gateway gets the update, partial failures where some update and others don't, and a fallback when push is down.** ⭐ **Justified for very fast updates, such as security incidents.**

> ⚠ **What HI leaves loose.**
> 
> - ⚠⚠ **Redis pub/sub as the push channel has no memory: a gateway that was disconnected misses the update permanently (ChatGPT DD2).** ⊕ **Push needs a version number and a slow poll as backstop; ZooKeeper watches re-read on reconnect for the same reason.**
> 
> ■ **— end of insert · HI write-up resumes below —**

---

## 6 · Final Design

⚠ **Layout and arrows are mine; components are HI's.**

```
Client ──► API Gateway × N  (the rate limiter lives here)                       02d
              │  ⭐⭐⭐ Token Bucket; ONE Lua script per check (refill + test + decrement)
              │  ⭐ allowed ──► app servers   ·   ⭐ rejected ──► 429 + X-RateLimit-* + Retry-After
              │  ⊕ local fallback limiter if a shard is unreachable
              │
              │ hash(client key) → shard          ⭐⭐ Redis Cluster: 16,384 slots     02a
              ▼
   ┌──────────────┬──────────────┬──────────────┐
   │ Redis shard 1│ Redis shard 2│ Redis shard 3│  … ~10 shards (⊕ plan 2× headroom)
   │  buckets     │  buckets     │  buckets     │  key: tokens · last_refill · EXPIRE
   └──────┬───────┴──────┬───────┴──────┬───────┘
          ▼ async        ▼ async        ▼ async
      read replica   read replica   read replica        ⭐ auto-promoted on failure

ZooKeeper (or etcd) ── maintains rules ──► gateways WATCH for changes     02i
   ⭐ or: gateways poll a config table every ~30s

📐 1M req/s ÷ ~100k ops/s per shard ≈ 10 shards, IF one command per check
   ⊕ HI's 6-command flow ⇒ 30–60 shards until Lua collapses it
```

---

## 7 · Expected at Each Level

|Level|The bar for Rate Limiter|
|---|---|
|**Mid-level**|**Breadth over depth (80/20). Meet the FRs with a high-level design; expect "how does Redis work and why?". Explain ONE algorithm (Token Bucket is fine), place the limiter at the API Gateway, name Redis as shared state, and see that Redis must be sharded.**|
|**Senior**|**60/40. Justify the algorithm against alternatives. Consistent hashing, Redis Cluster and connection pooling without guidance; Redis operations must be atomic. Fail-open vs fail-closed and the placement trade-offs. Raise hot keys, Redis availability and latency yourself; have opinions on config management.**|
|**Staff+**|**40/60, from real experience. Edge cases, observability and operational procedures unprompted; multi-region and cross-region consistency; gradual rollouts and canaries. HI: Staff+ candidates often aren't asked this one; if you are, fix the basics fast and spend the time on production failure modes.**|

> ⚠⚠ **HI's Senior bar says to "suggest MULTI/EXEC transactions" — his own §4.2 shows it doesn't close the race.** ⊕ **Say Lua (or `WATCH` + retry), and mention the local-fallback and key-splitting answers.**
> 
> ■ **— end of insert · HI write-up resumes below —**

---

## Quick Recall (pass 3+)

|Use / Question|Rate Limiter answer|
|---|---|
|Calibration|**Evan King · Jul 2025 · ⭐⭐ "medium" · Asked at Microsoft +12 · ⭐⭐ three patterns: `03b` Contention, `03e` Scaling Writes, `03d` Scaling Reads.** ⭐⭐ **ONE pass + a second look at atomicity and failure mode. Order §4.2 > DD1 > DD2 > DD4 > DD3 > DD5.** ⚠ **Some interviewers want LLD with code instead**|
|⭐⭐⭐ Design driver|⭐⭐⭐ **A check on every request, on shared mutable state, that must cost less than the request it guards.** **Limits are global ⇒ not per-server (§4.2) · many gateways update one counter ⇒ one atomic Lua script · 1M/s ⇒ shard (DD1) · limiter in front of everything ⇒ pick its failure mode (DD2) · <10ms ⇒ pool + regions (DD3) · one client floods one shard ⇒ hot keys (DD4) · rules change ⇒ poll or push (DD5)**|
|📐 Numbers|**1M req/s · 100M DAU · <10ms.** **Redis ~100–200k ops/s; ≥2 ops per check ⇒ 50–100k checks/s ⇒ 10 shards.** ⚠⚠ ⊕ **His own flow is 6 commands ⇒ 30–60 shards; Lua (1 command) ⇒ 5–10, with no headroom.** **Redis Cluster 16,384 slots · TCP handshake 20–50ms · `EXPIRE` 3600 · poll 30s · fixed-window burst 200 in ~2s**|
|FRs / NFRs|**Identify clients by user ID, IP or API key · limit requests by configurable rules (e.g. 100/min/user) · reject with 429 and helpful headers (remaining, reset).** Below: analytics on limit data · long-term persistence. **NFRs: ⭐⭐ <10ms per check · ⭐⭐⭐ highly available, eventual consistency OK · ⭐⭐ 1M req/s across 100M DAU.** Below: strong consistency across nodes. ⚠ **HI says "10M users" later**|
|Entities + interface|**Rules · Clients · Requests.** ⚠ **The stored thing is the bucket `{tokens, lastRefill}` per (client, rule).** `isRequestAllowed(clientId, ruleId) -> {passes, remaining, resetTime}`. ⚠⚠ **One `ruleId`, yet several rules apply and the strictest wins.** ⚠ **"Reset" doesn't fit a bucket ⇒ `Retry-After`**|
|⚠⚠ Placement — Bad: in-process|**Each server limits from its own memory: fast, no dependency.** ⚠⚠ **Sees only its own traffic: 100 on each of 5 servers = 500; unpredictable if routing changes; off by the server count.** ⊕ **Sticky routing by client would fix it, at the cost of uneven load**|
|⭐⭐ Placement — Good: dedicated service|**Own microservice; global state ⇒ exact limits; apps can pass rich context (tier, endpoint, promos).** ⚠ **Four costs: extra round trip (~10ms in HI's example) · another point of failure (open or closed?) · operational weight · slow/partitioned network (wait or guess?)**|
|⭐⭐⭐ Placement — Great: API Gateway|**At the edge; inspects IP, auth headers, API key; forwards or 429. Most popular: simple, strong, app servers never see blocked traffic (HI's bouncer).** ⚠ **Sees only the request, so "premium 10×" needs the tier in the JWT; state needs a fast store (Redis) with its own failure cases.** ⚠⚠ **HI's "no extra network calls" is false: gateway → Redis IS a call. The real gain: one hop instead of two**|
|⭐ Identifying clients + layered rules|**User ID (JWT) · IP (`X-Forwarded-For`; NATs) · API key (`X-API-Key`). Layer rules, enforce the strictest: per-user · per-IP · global · per-endpoint.** ⚠⚠ **Several buckets per request on different shards, not atomic ⇒ ⊕ accept the leak, check in parallel.** ⚠⚠ **A 50k/s global limit contradicts 1M/s and is one hot key.** ⚠ **`X-Forwarded-For` is spoofable unless your own proxy set it**|
|⭐⭐⭐ The four algorithms|⭐ **Fixed window: counter per window; simplest; ⚠ 200 in ~2s at the boundary.** ⭐ **Sliding log: timestamps; exact; ⚠ memory + scan.** ⭐ **Sliding counter: current + previous window weighted (30% in ⇒ 70% prev + 100% cur); two counters; ⚠ approximation.** ⭐⭐⭐ **Token bucket: capacity = burst, refill = steady rate; `(tokens, last_refill)`; handles bursts and sustained load; ⚠ tuning + cold start (idle ⇒ full).** ⭐⭐⭐ **HI picks Token Bucket**|
|⚠ Token bucket — loose ends|⚠ **Parameters drift (100 + 10/min, then 1 token/s, then "100/min").** ⊕ **"100/min" isn't a bucket setting: choose capacity (burst) and refill (100/60 per s); a full bucket plus refill can pass ~200 in the first minute — the boundary problem again.** ⚠ **HI treats the bucket as free of it**|
|⭐⭐⭐ Redis flow + the race|**Why Redis, not per-gateway memory: Alice's 50 + 50 across two gateways each look like 50.** **Flow: `HMGET alice:bucket tokens last_refill` → add refill for elapsed time (cap at capacity) → `MULTI`, `HSET` tokens, `HSET` last_refill, `EXPIRE 3600`, `EXEC` → ≥1 token ⇒ allow + decrement, else reject.** ⭐⭐⭐ **"But wait" — `HMGET` is outside the transaction: two gateways read the same count and both allow ⇒ fix with ONE Lua script (atomic read-calculate-update).** ▸ **`03b`: widen the atomic boundary to the whole read-modify-write**|
|⚠⚠ §4.2 contradictions|⚠⚠ **"Why Redis" still claims `MULTI`/`EXEC` prevents races, right after showing it doesn't; the Senior bar says to suggest it. ⊕ Say Lua.** ⚠⚠ **Decrement happens after the transaction — a second, non-atomic write.** ⚠ **Gateway-supplied `<now>` + many gateways ⇒ clock skew ⇒ read `TIME` in the script.** ⚠ **`EXPIRE 3600` is wrong if a bucket needs longer than an hour to refill**|
|⭐⭐ §4.3 — drop or queue? 429|⭐⭐ **Fail fast: 429 at once.** ⚠ **Queuing costs memory and resources, makes users retry (more load), and makes latency unpredictable; niche exception: batch systems.** **Headers: `X-RateLimit-Limit` · `X-RateLimit-Remaining` · `X-RateLimit-Reset` (Unix time) · `Retry-After` (seconds).** ▹ **Interview: say 429 + headers and move on**|
|⭐⭐⭐ DD1 — scale to 1M/s|📐 **A Redis does ~100–200k ops/s; ≥2 ops per check ⇒ one instance ⇒ 50–100k checks/s. Shard so a client's requests ALWAYS hit the same shard: consistent hashing on user ID / IP / API key; gateways route; bucket logic unchanged; ~10 shards.** ⭐⭐ **Production: Redis Cluster, 16,384 slots, automatic routing.** ▸ **`03e`**|
|⚠⚠ DD1 — loose ends|⚠⚠ **10 shards assumes 1 command per check; HI's flow is 6 ⇒ only after Lua, and with no headroom (⊕ plan 2×).** ⚠ **Cluster uses slots, not a hash ring.** ⚠⚠ **Multi-rule checks span shards; a Lua script touches one shard's keys; hash tags co-locate one client's rules, never a user with an IP.** ✅ **Counters are soft state: a lost bucket is a fresh bucket**|
|⭐⭐⭐ DD2 — fail closed vs open|⭐⭐⭐ **Closed: reject all (503/429) — ⚠ takes the API offline, retries pile on; legit for payments-style or high-security systems.** ⭐⭐⭐ **Open: allow all — ⚠ no protection, and if Redis died from load, failing open dumps ALL of it downstream. HI: both are "good"; it depends. His pick: CLOSED, because limiter failures coincide with spikes and a cascade is worse.** ⭐⭐ **Prevention: master–replica per shard, auto-promotion (Redis Cluster does it); cost + lag.** ▹ **Monitor shard health, limiter success rate, and fail-open entries**|
|⚠⚠ DD2 — loose ends|⚠⚠ **Fail closed vs NFR "highly available, availability ≫ consistency": the limiter becomes the API's SPOF, and HI's own challenge text says it's often worse.** ⚠⚠ **Binary choice; ⊕ third option: fail open to a LOCAL limiter (~limit ÷ gateways) until Redis returns.** ⚠ **One shard down hits ~1/10 of clients, not the whole API.** ⚠ **Don't answer a limiter outage with 429; use 503 + `Retry-After`.** ✅ **Async replica lag = a few extra tokens, fine**|
|⭐⭐ DD3 — latency|**Redis < 1ms, network adds several ms.** ⭐⭐⭐ **Connection pooling first (avoids the 20–50ms handshake; tune the pool).** ⭐⭐ **Then regions (biggest win; eventual consistency across them).** ▹ **Local caching (stale ⇒ wrong), pipelining/Lua, request batching — "avoid unless asked".** ⚠⚠ **But Lua is REQUIRED for the race and for the shard sizing.** ⚠⚠ **Multi-region has no mechanism: a client in two regions gets ~double; ⊕ pin to a home region or split the limit**|
|⭐⭐ DD4 — hot keys|⭐ **One client doing tens of thousands of checks/s overwhelms its shard: abuse or a legit heavy client.** **Legit: client-side limiting (SDKs obey the headers) · batching · premium tiers.** **Abusive: auto-block after repeated hits (~10/min) into a blocklist; DDoS protection (Cloudflare, AWS Shield).** ⭐ **Set higher IP limits for shared NATs.** ⚠⚠ **No real hot-key technique: ⊕ split into k sub-buckets (limit ÷ k) · lease token batches to gateways · local deny cache with TTL.** ⚠ **"Cache misses" — no cache exists.** ▸ **"Too much traffic for one key → replicate" (`05g`)**|
|⭐ DD5 — dynamic rules|**Poll (most common): rules in a DB or config service, gateways poll ~30s and cache; ⚠ up to ~30s delay.** **Push: ZooKeeper (`02i`) watches, or Redis pub/sub, or a custom service; seconds, but complex (failures, partial updates, fallback); for fast cases like security incidents.** ⚠ **Pub/sub drops updates for a disconnected gateway ⇒ version + poll backstop (ChatGPT DD2)**|
|⭐⭐⭐ The meta-lesson|⭐⭐⭐ **Three ideas outlive this problem: (1) a read-modify-write on shared state is ONE atomic unit — wrapping only the write isn't enough; (2) shard by the identity, but a single hot identity can't be sharded — split, lease or block it; (3) a guard on every request's path needs its failure mode designed first, ideally with a degraded fallback**|
|Levels (one line)|**Mid (80/20):** explain Token Bucket, gateway placement, Redis shared state, sharding · **Senior (60/40):** algorithm trade-offs, consistent hashing, Cluster, pooling, atomicity (say Lua, not MULTI/EXEC), fail-open vs closed, hot keys, config · **Staff+ (40/60):** production ops, observability, multi-region, canaries; often not asked|

---

> 🔗 **HI source:** https://www.hellointerview.com/learn/system-design/problem-breakdowns/distributed-rate-limiter