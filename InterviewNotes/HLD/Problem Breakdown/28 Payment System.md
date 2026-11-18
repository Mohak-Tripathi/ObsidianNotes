# Payment System — Problem Breakdown

> 📐 **Revision note (calc):** **10k TPS at peak, bursty (holiday sales).** 📐 ⭐⭐ **Kafka: one partition ≈ 5–10k msg/s (HI's figure, conservative) ⇒ 3–5 partitions, RF 3, keyed by `paymentIntentId`.** 📐 ⭐⭐ **Storage: ~500 B/row × 10k/s = 5 MB/s ⇒ ~500 GB/day (a day rounded to 100k s) ⇒ ~180 TB/yr ⇒ archive to S3 after 3–6 months.** 📐 ⭐ **Postgres at 10k writes/s is "right on the edge" ⇒ read replicas + shard by `merchantId`.** ⚠⚠ ⊕ **My check: HI sizes the event log and the DB at 10k/s, but one payment writes several rows (intent, transaction/attempt, 2–3 status updates) and CDC emits one event per row change ⇒ more like 40–60k events/s. Say "10k payments/s, ~5× that in row changes".** 📐 ⊕ **Nonce store: 10k req/s × 5–15 min window ⇒ ~3–9M live nonces.** **Webhook retry: 5s, 25s, 125s … cap ~1h.**

> ⭐⭐ **Pattern: `Multi-step Processes` → `03c`** · Cross-refs: ⭐⭐⭐ **`05v` Robinhood — an order sent to a system you don't control; the Order state machine** · ⭐⭐⭐ **ChatGPT (31) DD1 — the ATTEMPT gets its own identity** · ⭐⭐ **`05q`/`05o`/ChatGPT — snapshot for state + stream for change** · ⭐⭐ **`03b` contention (double-charge race) · `03e`/`03d` scaling writes/reads · `03a` real-time updates (webhook ≠ SSE) · `02c` Kafka · `02g` Postgres · `02d` API Gateway · `02a` Redis · `01h` consistency vs availability · `01i` numbers.**
> 
> **Calibration:** ⭐⭐ **TWO passes (my call).** ⭐⭐⭐ **DD3 and DD2 are the problem. DD1 is two separate ladders. DD4 is mostly arithmetic. Webhooks is a bonus HI himself calls a whole interview.** ⭐ **Order: DD3 > DD2 > DD1 > DD4 > webhooks.** ▹ **HI's four dives are his four NFRs in order — same as `05x`: the NFRs are the agenda.**
> 
> - ⭐⭐ **What actually scores:** **(a)** ⭐⭐⭐ **a timeout is NOT a failure — it's an unknown, held as its own state** · **(b)** ⭐⭐⭐ **write the attempt BEFORE calling the network, then reconcile against the network's own records** · **(c)** ⭐⭐⭐ **idempotency key + unique constraint, so a retry can't charge twice** · **(d)** ⭐⭐⭐ **card data never touches the merchant's server: iframe, then client-side encryption, key in an HSM** · **(e)** ⭐⭐ **history comes from CDC → Kafka → S3, not from app code or in-place updates** · **(f)** ⭐⭐ **HMAC request signing with timestamp + nonce** · **(g)** ⭐ **Kafka keyed by intent, DB sharded by merchant.**
> - ⭐ **Transferable primitives:**
>     - ⭐⭐⭐ **When the other side is a system you don't control, "no answer" is a third outcome, not a failure.** ▸ **Hold the unknown as a state and resolve it by asking the authority.**
>     - ⭐⭐⭐ **Record the intent before the side effect, under an ID you generated.** ▸ **After any crash or timeout you can ask the other system "did you do X?" by that ID.**
>     - ⭐⭐⭐ **Dedupe retries in the database, not in the app: a unique constraint on (owner, client-supplied key).**
>     - ⭐⭐ **Capture history below the application — from the committed-change log — so no code path can forget to write it.** ▸ **"If it committed, it's in the log."**
>     - ⭐⭐ **Keep the secret out of every hop that doesn't need it.** ▸ **Encrypt at the source so intermediate tiers only ever hold ciphertext.**
>     - ⭐⭐ **Sign requests with timestamp + nonce so replays are detectable.** ▸ **The nonce store is SET-NX-with-TTL, TTL ≥ the timestamp window.**
>     - ⭐ **Current state in a store built for reads; history in an append-only log; many independent consumers read the log.** ▸ **Partition the log by the entity whose transitions must stay ordered.**
> - ⭐ **Re-run (cross-ref, NOT re-explained):** **Redis SET NX + TTL (`05t`/`05u`/`05x`) · Kafka keys, partitions, consumer groups (`02c`) · sharding, replicas, cold archive (`03e`/`03d`/`02g`) · unique constraint as a race guard (`03b`) · gateway auth + rate limit (`02d`) · snapshot + stream (`05q`/`05o`/ChatGPT) · attempt with its own identity (`05v`, ChatGPT DD1) · "a log is not a work queue" (`05i`/`05p`/`05q`/`05t`) — see DD3.** **Genuinely new:** ⭐⭐⭐ **timeout-as-unknown + write-ahead attempt + reconciliation, incl. batch settlement files** · ⭐⭐⭐ **CDC (reads the WAL) as the audit source** · ⭐⭐ **HMAC request signing** · ⭐⭐ **iframe + client-side public-key encryption + HSM** · ⭐ **PCI scope as a design input** · ⭐ **signed webhooks with backoff.**

---

## 0 · Understanding the problem

💬 **Merchants charge customers through us; we talk to the card networks so they don't have to.** ▸ **Merchant = the business calling our API. Customer = the cardholder paying.**

⚠ **HI's opening picture is the BAD design on purpose** — **the customer types card details on the merchant's site and the merchant sends them to us.** ▸ **DD1 reverses this. Don't draw it as the final answer.**

⭐ **Ask for scale first, as HI does: ~10k TPS at peak.** ▹ **HI on webhooks: agree early with the interviewer on what you're building — _"on the same page"_.** ⊕ **Default: webhooks out of scope unless asked.**

---

## 1 · Requirements

### 1.1 Functional

1. ⭐ **Merchants should be able to initiate payment requests (charge a customer for a specific amount).**
2. ⭐⭐ **Users should be able to pay for products with credit/debit cards.**
3. ⭐ **Merchants should be able to view status updates for payments (e.g., pending, success, failed).**

⚠ **Below the line:** **Customers should be able to save payment methods for future use. · Merchants should be able to issue full or partial refunds. · Merchants should be able to view transaction history and reports. · Support for alternative payment methods (e.g., bank transfers, digital wallets). · Handling recurring payments (subscriptions). · Payouts to merchants.**

### 1.2 Non-functional

📐 ⭐ **Scale first: ~10,000 TPS at peak.**

1. ⭐⭐ **The system should be highly secure**
2. ⭐⭐⭐ **The system should guarantee durability and auditability with no transaction data ever being lost, even in case of failures.**
3. ⭐⭐⭐ **The system should guarantee transaction safety and financial integrity despite the inherently asynchronous nature of external payment networks**
4. ⭐ **The system should be scalable to handle high transaction volume (10,000+ TPS) and potentially bursty traffic patterns (e.g., holiday sales).**

⚠ **Below the line:** **The system should adhere to various financial regulations globally (depending on supported regions). · The system should be extensible to easily add new payment methods or features later.**

> ⭐⭐ **NFR 3 is the unusual one — and the heart of the problem.** ▸ **It's the opposite stance from ChatGPT's `01h` "availability over consistency": here you want integrity first.** ⚠ **But HI's own bar for mid-level accepts "timeout = failure" — the exact approach he calls "a disaster waiting to happen" in DD3.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 1.3 ⭐⭐⭐ The design driver — you are moving money through a system you don't control, and "did it work?" can be "unknown"

|Constraint|What it breaks|Fixed by|
|---|---|---|
|⭐⭐⭐ **the network can succeed and lose the reply**|**"timeout = failed"**|**DD3 attempt record + reconciliation**|
|⭐⭐ **history must be provable months later**|**in-place updates, app-written audit rows**|**DD2 CDC → Kafka → S3**|
|⭐⭐ **a card number must exist only where it's needed**|**merchant relays the card**|**DD1 iframe + client-side encryption**|
|⭐ **anyone can claim to be a merchant**|**a static API key**|**DD1 request signing**|
|⭐ **10k/s with bursts**|**one DB, one partition**|**DD4 partition + shard**|

> ⭐⭐ **The queue question from `05v` and ChatGPT, applied here.** ▸ **There is NO queue in the charge path: the checkout page waits for the authorisation result, so the answer IS the work (as in `05v`'s order confirmation).** ▸ **Kafka sits BEHIND the write, fed by CDC, and serves audit, reconciliation and webhooks.** ⊕ **My reading — HI never says it.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 1.4 Planning the approach

⭐ **Work through the FRs one by one for the HLD, then the NFRs are the deep dives.**

---

## 2 · Core Entities

- **Merchant** — **the business: identity, bank account details, API keys.**
- **PaymentIntent** — ⭐⭐ **the merchant's intention to collect an amount; tracks the lifecycle and owns the state machine (`created → authorized → captured / canceled / refunded`); enforces idempotency for retries.**
- **Transaction** — ⭐⭐ **one money-movement record linked to ONE PaymentIntent: Charge, Refund, Dispute, Payout. Amount, currency, status, timestamps, refs to intent and merchant. Only Charges here.**

⭐⭐ **PaymentIntent → Transaction is ONE-TO-MANY.** **Retry after insufficient funds: same intent, new Transaction · partial payments: several Transactions · refund: a NEGATIVE-amount Transaction on the original intent.** ▸ **The merchant sees only the intent; we handle the transaction mess.** ▹ **Production splits these into Charge / Refund / Dispute / Payout plus double-entry `LedgerEntry` rows; one polymorphic table is the interview simplification.**

> ⚠⚠ **HI is loose here, and it costs you in DD3.**
> 
> - ⚠⚠ **Three status vocabularies for one intent:** **entity text `created → authorized → captured…` · §4.3 `created / processing / succeeded / failed` · DD3 adds `pending_verification`.** ⊕ **Pick one and say it: `created → processing → succeeded | failed`, plus `pending_verification` while an attempt is unresolved. Use `authorized/captured` only if you split auth from capture — HI never does (one `type: charge`).**
> - ⚠ **Names drift: PaymentIntent / Payment / `paymentId` / `pi_123` / `pay_123`; PaymentIntent Service vs Payment Service; `customerId` with no Customer entity.** ⊕ **One name each.**
> - ⚠⚠ **The ATTEMPT has no home.** **§4.2 creates a `pending` Transaction before the network call; DD3 then adds "a separate table to track every attempt" and an "attempt record" with its own status.** ⊕ **Simplest consistent reading: for a charge, the Transaction row IS the attempt — created `pending` before the call, carrying OUR reference ID.** ⚠ **Say this, or "what's the difference?" is the follow-up.** ▸ **Same primitive as ChatGPT's Run and `05v`'s Order state machine.**
> 
> ■ **— end of insert · HI write-up resumes below —**

---

## 3 · API

```
POST /payment-intents                              { amountInCents, currency, description }  -> paymentIntentId
POST /payment-intents/{paymentIntentId}/transactions   { type: "charge", card: { number, exp_month, exp_year, cvc } }
GET  /payment-intents/{paymentIntentId}            -> PaymentIntent  (status + error details)
POST {merchant_webhook_url}   { type: "payment.succeeded", data: { paymentId, amountInCents, currency, status } }
```

- ⭐ **`POST /payment-intents` is called when the customer reaches checkout; the returned id is what the checkout page and client code carry forward.**
- ⭐ **Amounts are integer cents + currency, never floats.** ▹ **Textbook.**
- ⚠⚠ **The raw card number in the second endpoint is planted.** **HI: _"we'd never pass raw card details directly to our backend like this"_ — "tokenization" is promised and then never designed (see DD1).** ⊕ **After DD1: the browser SDK sends the ENCRYPTED card plus the intent id straight to us; the merchant server never sees it; the charge refers to an opaque token, not a card.**
- ⚠⚠ **No idempotency key anywhere,** **though the entity says the intent enforces idempotency and DD3 rests on a unique constraint on (merchantId, idempotencyKey).** ⊕ **Add an `Idempotency-Key` header to both POSTs, above all the charge.**
- ⭐ **Webhooks (the 4th call) are the push alternative to polling `GET`.** ⚠ **Deferred to the bonus dive.**
- ⭐ **Merchant identity comes from the API key, never the body.**

---

## 4 · High-Level Design

### 4.1) Merchants should be able to initiate payment requests

```
Merchant ──► API Gateway ──► Payment Service ──► Database
            auth·limits·routing   create PaymentIntent   PaymentIntents + merchant info
```

- **API Gateway** — **auth, rate limiting, routing.** · **Payment Service** — **creates and manages PaymentIntents.** · **Database** — **PaymentIntents (status, amount, currency, metadata) + merchants (API keys, config).**
- **PaymentIntent:** `id · merchantId · customerId · status: created · amount · product · metadata`

**Flow:** **① merchant `POST /payment-intents` (amount, currency, description) ② gateway authenticates, routes to the PaymentIntent Service ③ it writes a record, status `created` ④ it returns the generated id.** ⭐ **Nothing is charged: this only records the intention and mints the id the rest of the flow uses.**

- ⭐⭐ **The id is crucial: the merchant embeds it in the checkout page or passes it to their client-side code, and it is used when the customer's payment details are collected (4.2). It is also the reference that tracks this payment through its whole lifecycle.**
- ⭐ **End state of 4.1: a PaymentIntent in `created`, waiting for payment details; processing starts in 4.2.**
- ⊕ **This is why the id must exist BEFORE the card is entered: after DD1 the browser SDK sends the encrypted card with this id, so the card and the intent are tied together without the merchant's server ever touching the card.**

### 4.2) Users should be able to pay for products with credit/debit cards

⭐⭐ **Why it's multi-step: payment is inherently asynchronous — the first authorisation answer is only step one of a process that can take minutes or days (fraud checks, chargebacks).** ⭐⭐ **Pattern: Multi-step Processes (`03c`) — authorisation, capture, settlement, refunds, disputes; each step can fail alone and needs retries or compensation, so state must be tracked carefully.**

```
Customer ─card─► Merchant ─► Transaction Service ─► External Payment Network (Visa, Mastercard…)   ┄ outside our system
                                   │  writes Transaction: id · paymentId · amount · type · status · network · metadata
                                   └──► Database
```

- ⭐ **Transaction Service** — **ONE service: receives card details, manages transaction records, talks to the networks.** ▹ **HI: combines concerns on purpose — fewer network hops, and PCI compliance lives in one service.** ✅ **One service in PCI scope.**
- **External Payment Network** — **dotted: not ours.**

**Flow:** **① customer enters card in the merchant's form ② merchant sends it to our Transaction Service with the PaymentIntent id ③ Transaction Service creates a Transaction, status `pending` ④ it handles the network itself: (a) connect, send the authorisation request (b) receive the first approve/decline (c) update the Transaction (d) keep listening for callbacks on the private connection (e) later callbacks — settlement, chargeback — update the records ⑤ it updates the PaymentIntent as the Transaction progresses.**

> ⚠⚠ **Three things HI leaves hanging in this section.**
> 
> - ⚠⚠ **Steps ①–② are the BAD design from DD1** (card goes through the merchant's server). **DD1 rewires that arrow; this section is never redrawn.**
> - ⚠⚠ **Sync or async?** **Does `POST …/transactions` block until the network answers? DD3 has a 30–60s timeout, so the call is inline — yet DD2 brags about "sub-10ms API responses" and §4.3 has a `processing` state.** ⊕ **Say it: return the result if the network answers quickly; otherwise return `processing` and let poll/webhook finish it.**
> - ⚠⚠ **Contradiction: step 4d has the Transaction Service holding a private connection and "listening for callbacks" — a stateful role — while DD4 says every service is stateless and scales horizontally.** ⊕ **A callback to a dead or wrong instance is lost; the reconciliation in DD3 (queries + settlement files) is what makes that safe, not the service.** ▹ **Same shape as ChatGPT DD2, "the instance in the middle will vanish" — fixed there by a log, here by asking the authority.**
> - ▹ **Aside — don't spend time here:** **networks run on private, separate networks: HSMs, ISO 8583, leased lines, VPN, mutual TLS. HI: "highly unusual" to be asked.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 4.3) The system should provide status updates for payments

⭐ **No new service: the PaymentIntent Service already owns the intents.**

**Flow:** **① merchant `GET /payment-intents/{paymentIntentId}` ② gateway authenticates, routes ③ service reads status, error message if failed, related transactions ④ returns it.** ⭐ **Polling.** **Statuses: `created` (merchant created it) · `processing` (details received, being processed) · `succeeded` · `failed` (with reason).** ⚠ **Polling is "not ideal for real-time updates or high-frequency status checks" ⇒ webhooks in the bonus dive.**

- ⭐⭐ **Status is per PaymentIntent, not per Transaction.** **The merchant only holds the intent id; the Transaction is our internal record of each attempt. The intent status is a roll-up: attempt in flight ⇒ `processing` · a charge succeeded ⇒ `succeeded` · latest attempt failed ⇒ `failed` · retry on the same intent ⇒ back to `processing`.** ▹ **Transactions appear in the GET only as detail.**
- ⚠ **HI never states the roll-up rule, and `paymentId` / intent id / transaction id are used interchangeably.** ⊕ **Say the rule out loud.**

---

## 5 · Deep Dives

▹ ⭐ **HI's four dives are his four NFRs in order. The planted weaknesses in §3–§4 (raw card, timeout, no admission to the network) are what they fix.**

### 1) The system should be highly secure

⭐⭐ **Two separate questions, two separate ladders: A) is the caller who they say they are? B) is customer card data protected?**

#### A) Merchant authentication

⚠ **Rung labels are mine.**

##### Good — static API keys

- **At onboarding we mint a random key (`pk_live_…`) per merchant, store it, and the merchant sends it as `Authorization: Bearer` or `X-API-Key`. The gateway looks it up and identifies the merchant.**
- ⚠⚠ **It is static and replayable forever: nothing detects a replay; sniffing is possible on insecure connections; and, more likely, keys end up hard-coded in client apps, config, repos and backups.** ⭐ **HI: unacceptable for a financial system — fraud, breach, reputational damage.** ⊕ ⚠ **Over TLS, leakage is the real risk, not sniffing — lead with that.**

**Why climb:** ⭐ **a leaked key works forever; make every request prove itself and expire.**

##### ⭐⭐ Great — HMAC-signed requests

- **Two keys: a public API key (identifies) and a private secret key that stays on the merchant's server, never in client code. This authenticates the merchant's server to us; card data is a separate problem (B).**
- **The merchant hashes method, endpoint, params, body + a timestamp + a unique nonce with the secret. Headers: `Authorization: Bearer pk_live_…`, `X-Request-Timestamp`, `X-Request-Nonce`, `X-Signature: sha256=…`.**
- ⭐⭐⭐ **Gateway: ① fetch the secret by API key ② recompute HMAC-SHA-256 ③ compare ④ timestamp inside a 5–15 min window ⑤ nonce not seen in the window (cache/DB).** ▸ **HMAC gives authenticity + integrity; timestamp + nonce make replay detectable.**
- ⊕ **Costs HI doesn't list:** **the gateway must hold a RECOVERABLE secret, not a hash ⇒ KMS/HSM-backed · the nonce check is a Redis `SET NX` + TTL ≥ the window on every request, ~3–9M live (`02a`; same primitive as the lock in `05t`/`05u`/`05x`) · ⚠ HI's sample comments the signature as "Hash of body" but the text signs method, path, params, body, timestamp and nonce — sign all of it.**

#### B) Protecting card data

⚠ **Rung labels are mine.**

##### ⚠⚠ Bad — the merchant collects the card on their own servers

- **Customer types the card on the merchant's site → merchant's server over HTTPS → the merchant encrypts and forwards it to us; their server gets the responses.**
- ⚠⚠ **Card data must never touch merchant servers: best practice AND a PCI DSS requirement. Every merchant server becomes an attack target, and the merchant carries the liability for a breach.**
- ▸ **This is the design in §3 and §4.2.**

**Why climb:** ⭐ **take the merchant's server out of the card's path.**

##### Good — our iframe

- **A JS SDK loads an iframe from OUR domain on the merchant's page; the card goes straight to us over HTTPS. The browser's same-origin policy keeps the merchant's code out of the frame. The merchant is out of PCI scope and liability.**
- ⚠ **Challenges: the security rests on browser policy (sophisticated attacks); the card is protected only by HTTPS in transit, exposed if the frame is compromised; less customisation; usability problems on mobile browsers.**

**Why climb:** ⭐ **add a second layer so one failure doesn't expose the card.**

##### ⭐⭐⭐ Great — iframe + client-side public-key encryption

- **We manage keypairs; the SDK encrypts with our PUBLIC key in the browser, before the data leaves the device. HTTPS then carries ciphertext. The PRIVATE key sits in HSMs and decrypts on our side.** ▸ **Defence in depth: compromise of the merchant's site yields only ciphertext; if one layer fails, others hold.**
- ⚠ **HI's argument is loose.** ⊕ **If the SDK code inside the frame is itself compromised, it reads the card BEFORE encrypting. What the encryption really buys is that every hop between browser and decrypter — gateway, load balancers, logs, TLS termination — only ever holds ciphertext. Decrypt only inside the Transaction Service / HSM boundary.** ▹ **Judgment call.**
- ⚠⚠ **"Tokenization" is promised in §3 and in the Staff+ bar, and never designed.** ⊕ **Token = an opaque id for the card held in the vault; DB, Kafka, S3 and webhooks hold only the token / last four.**
- ⚠⚠ **This dive and the next collide.** **DD2 copies every row change into Kafka and S3 permanently. A card number in any row — including the free-form `metadata` — becomes an immutable, replicated PCI problem.** ⊕ **Keep the card out of every row; the reconciler only ASKS the network about an attempt, it never re-sends the card.**

### 2) The system should guarantee durability and auditability with no transaction data ever being lost, even in case of failures.

⭐⭐ **It isn't enough to know the current state — we need the whole sequence: a dispute six months later needs "when initiated, what amount authorised, when captured, were refunds made". PCI-DSS, SOX and audits require complete, immutable records. Webhook delivery, reconciliation and fraud analysis all stand on this trail.**

⚠ **Rung labels are mine.**

#### ⚠⚠ Bad — update in place, rely on backups

- **`UPDATE payment_intents SET status = 'captured' …`: ACID, fast current state, simple dashboards. Durability = daily snapshots + transaction logs for point-in-time restore.**
- ⚠⚠ **Four challenges:** **① history is destroyed — we lose that it was `pending`, when it changed, who did it · ② a buggy deploy corrupts statuses silently and the original is gone; backups can't say which rows · ③ fails audits: auditors need full history and proof of no tampering · ④ support pieces events together from server logs — "archeology rather than investigation".**

**Why climb:** ⭐ **keep the history.**

#### Good — an audit table written in the same transaction

- **`BEGIN; UPDATE` main row; `INSERT INTO payment_audit_log` (payment_id, change_type, old_status, new_status, changed_by, changed_at, metadata); `COMMIT`. Append-only, insert-only permissions at the DB level. We can answer disputes and compliance, and replay the log to rebuild state.**
- ⚠ **Challenges: ① application code must remember both writes — a forgotten insert silently loses the trail, unrecoverable · ② the 10k-TPS operational DB must also hold billions of audit rows; the two can't be tuned independently, and compliance queries slow operational ones.**
- ⊕ **① has a cheap fix HI skips: a DB trigger writes the audit row whatever the app does. ② still stands.** ▹ **Judgment call.**

**Why climb:** ⭐ **capture below the application, and off the operational DB.**

#### ⭐⭐⭐ Great — CDC → Kafka → independent consumers + S3

- **Operational DB: pure current-state tables, no audit tables. CDC reads the WAL (or oplog) and emits every committed change — at the database level, not the app. Kafka: append-only log keyed by `payment_intent_id`, carrying before/after state.**
- **Consumers read the same stream independently: Audit Service (immutable history) · Analytics (denormalised views) · Reconciliation (DD3) · Webhook delivery (bonus).** ▹ **Most are out of scope; naming them shows you see where it grows.**
- **Durability: replication factor 3 across brokers and AZs; 7–30 days on disk; everything flushed to S3 for permanent retention — hot for operations, cold for compliance.** ⭐⭐ **Why it works: _"if a change commits to the database, it will appear in the event stream"_ — no code path can forget.**
- ⭐ **HI's CDC-is-a-SPOF answer: run several independent CDC instances against the same DB, each into a different Kafka cluster; alert on lag within seconds; keep a replay procedure from DB logs; add an app-level fallback that writes straight to Kafka if CDC hasn't confirmed in time.**
- ⚠⚠ **That fallback is the dual-write problem HI rejected two rungs up** ("the app must remember both"). **And several CDC streams into several clusters means duplicate events; consumers must dedupe, which he doesn't say.**
- ⚠ **"Cryptographically verifiable immutability" is asserted, not designed.** ⊕ **Kafka isn't immutable (retention expires, topics can be deleted). Tamper-evidence needs S3 Object Lock (WORM) and/or hash-chained records.** ▹ **Textbook.**
- ⚠ **"Sub-10ms API responses" holds for creating an intent; the charge call is bounded by the network (see 4.2).**
- ▸ ⭐⭐ **Primitive: DB row = snapshot (what is true now), log = stream (what happened) — `05q`/`05o`/ChatGPT's "snapshot + stream, never one component".** ⊕ **Inverts `05e`/`05h`/`05i`/`05p`/`05t`'s "fast tier decides, durable tier remembers": here the DB decides and the log remembers.**

### 3) The system should guarantee transaction safety and financial integrity despite the inherently asynchronous nature of external payment networks

⭐⭐⭐ **The network is not ours: a request we call "timed out" may still be in flight; another may have succeeded and lost its reply.** ⚠⚠ **Two failure modes: DOUBLE-CHARGE (timeout, merchant retries, customer sees two charges) and the reverse — charged at the bank but we tell the merchant "failed", so nothing ships.** ⭐ **HI: we can't remove the asynchrony; we design for the uncertainty — and the CDC stream is the foundation.**

⚠ **Rung labels are mine.**

#### ⚠⚠⚠ Bad — treat the network like an internal call: timeout ⇒ failed

- **30–60s timeout; no reply ⇒ mark `failed`. Merchants get fast feedback; every payment is `succeeded` or `failed`, never stuck.**
- ⚠⚠⚠ **A timeout tells us nothing about what happened.** **The scenario: $200 charge → bank approves and debits → reply lost → our 30s timeout marks it `failed` → merchant shows "try again" → customer retries → second $200 ⇒ $400 for a $200 purchase.**
- ⚠ **HI's own mid-level bar accepts this approach if you can explain it clearly.**

**Why climb:** ⭐ **don't guess — track the unknown explicitly.**

#### Good — `pending_verification` + an attempts table + idempotency

- **On timeout, mark `pending_verification`, not failed. A separate table records every attempt: what we sent, when, and "the reference ID the network assigned". A background service periodically queries the network with that reference to learn the outcome, separately from the merchant API.**
- **Idempotency: a unique DB constraint on (merchantId, idempotencyKey); a retry with the same key returns the existing payment instead of creating a second charge.**
- ⚠ **HI's challenges: ① manual reconciliation — finance reviews pending payments daily against bank files; on Black Friday thousands are stuck · ② reconciliation is an exception case bolted onto a design built for synchronous replies · ③ the one DB takes operational AND reconciliation load at peak.**
- ⚠⚠ **Two things don't hold together.** **① "the reference ID the network assigned" — on a timeout we never got one, so the poller has nothing to ask with. Only an ID WE generated and sent works (rung 3 fixes it by writing before calling).** **② The approach is an automated background poller; challenge ① is a manual finance process. The challenge doesn't follow from the approach.**
- ⚠⚠ **Idempotency lives ONLY here** — it's missing from the API, from the PaymentIntent schema (no column), and from rung 3. **And it doesn't cover the case in §2:** **a retry after failure makes a NEW Transaction on the same intent; a fresh key plus a still-unknown first attempt = double charge.** ⊕ **Guard in the state machine: no new charge on an intent while an attempt is unresolved, and at most one succeeded charge per intent (conditional update or partial unique index).** ▸ **`03b`; mirrors `05v`'s Order state machine.**

**Why climb:** ⭐ **make uncertainty first-class: record the attempt before acting, and resolve from the network's authoritative data automatically.**

#### ⭐⭐⭐ Great — write-ahead attempt + CDC events + automated reconciliation

- ⭐⭐⭐ **_"Track our intentions before acting on them."_ The flow:** **① record the attempt BEFORE calling the network — network name, reference ID, purpose; it commits and CDC emits our intention ② call the network with a timeout ③ branch: success ⇒ attempt `succeeded` (CDC event) · timeout ⇒ attempt `timeout` (CDC event for the reconciler) · explicit failure ⇒ `failed` + reason ④ a reconciliation service consumes timeout events and queries the network by our reference ID.**
- ⭐⭐ **Two ways to verify: direct API queries (real time) and batch reconciliation files — complete records of everything processed in a period, daily or hourly, strictly formatted, "the definitive record".** **The reconciler correlates external events with our attempts and sets statuses from authoritative data, not from timeouts.**
- ⭐ **Every step, success, failure or timeout, is an immutable event.**
- ▹ **Production aside — Stripe's two-phase event model:** **a "created" event is emitted when the Transaction Service starts, before the DB write completes (emit fails ⇒ transaction locked/failed, retryable); a "completed" event is emitted after the write (emit fails ⇒ locked, further updates blocked until it is). On retry, compare the created event with DB state: if the write happened, just re-emit "completed". HI: most missing "completed" events come from external timeouts before the DB write, not from emission failures.**
- ⚠⚠ **Rung 3 does not contain rung 2.** **The reconciler sees a timeout event once. If the network says "not yet", who asks again? ⊕ A periodic sweep over unresolved attempts — rung 2's poller.** ▸ **So rung 3 = write-ahead ID + settlement-file backstop + CDC as the trigger, ON TOP of a sweep, plus the idempotency/state guard from rung 2.** ▸ **"A log is not a work queue" (`05i`/`05p`/`05q`/`05t`): the log announces; a durable per-attempt state and a sweep do the retrying.**
- ⚠⚠ **"Not found" is not "didn't happen".** **HI says a timed-out request "might still be winding its way through"; a query that finds nothing doesn't contradict it.** ⊕ **Don't mark `failed` on the first "not found": stay `pending_verification` until the settlement file or a reversal/void after a grace period. A crash between commit and call lands in the same case: attempt `pending`, nothing sent.** ▹ **Judgment call.**
- ⚠ **The two-phase aside has the Transaction Service emitting events itself, a SECOND event source beside CDC — against "no reliance on application code". HI never reconciles the two. The "most missing events" claim is unsupported.**
- ⚠⚠ **Named, never designed: HI's Staff+ bar asks for "payment network outages through fallback processing paths".** ⊕ **Health-checked routing across acquirers — but never re-send an UNRESOLVED attempt on another network before it's resolved, or you double-charge across networks.**
- ⭐⭐⭐ **HI's close: good distributed systems _"embrace and design for"_ their external dependencies rather than fight them.**

### 4) The system should be scalable to handle high transaction volume (10,000+ TPS)

▹ ⭐ **HI saves scale for last so he knows the full system he's scaling.**

- **Servers** — ⭐ **stateless behind load balancers; mention it, don't draw it.**
- ⭐⭐ **Kafka** — **~5–10k msg/s per partition ⇒ 3–5 partitions. Key by `payment_intent_id`: in-order per intent, parallel across intents. Replication factor 3. A consumer group per service.** ⚠⚠ **"Exactly-once processing" holds only inside Kafka; a consumer that calls a network, a webhook endpoint or the DB is at-least-once ⇒ idempotent consumers keyed on the event/attempt id.** ⚠⚠ **"10k TPS ⇒ 10k events/s" undercounts (see calc).** ⊕ ⚠ **CDC emits per table; an intent row and its transaction rows go to different topics, and Kafka orders only within a partition — per-intent order across them isn't guaranteed unless you design for it.**
- ⭐⭐ **Database** — **~10k writes/s is "right on the edge" of a tuned Postgres with replicas and indexes ⇒ shard by `merchantId`.** ✅ **The unique (merchantId, idempotencyKey) constraint stays on ONE shard.** ⚠ **A hot merchant on a big sale day is one hot shard; HI is silent.** ▸ **"Too much data → shard; too much traffic for one key → replicate" (`05g`).**
- 📐 ⭐⭐ **Storage: 10,000 × 500 B = 5 MB/s × 100,000 s = 500 GB/day × 365 ≈ 180 TB/yr.** ⊕ **An upper bound: it treats peak as the whole day.** ⭐ **Cold storage (S3/GCS) after 3–6 months via a scheduled export-and-purge job, still reachable for audit.** ⚠ **DD2's "dispute six months later" lands exactly on that cut-off; say how fast a restore is.**
- ⭐ **Reads** — **read replicas + a cache (Redis/Memcached) for recent statuses.** ⊕ ⚠ **Replica lag: create-then-GET can miss the row; route recent intents to the primary.**

### Bonus) How can we expand the design to support Webhooks?

▹ ⭐ **HI: a standalone interview in its own right — outline only.**

- **Merchants add two fields: `callbackUrl` and `subscribedEvents`.** ⭐⭐ **Webhooks are SERVER-TO-SERVER (our server → the merchant's server), not SSE/WebSocket, which are server-to-browser (`03a`).** ▸ **Needs a public HTTPS endpoint on the merchant's side.**
- **Flow: ① DB changes ② CDC publishes them to Kafka ③ a new Webhook Service consumes the same stream as Reconciliation, checks the merchant's subscription, builds the payload, signs it with a shared secret, POSTs it ④ each delivery attempt is recorded with its status; on failure, exponential backoff — 5s, 25s, 125s … up to ~1h ⑤ the merchant verifies the signature, processes, and returns 2xx to stop retries.**
- **Payload:** `{ id: "evt_…", type: "payment.succeeded", created, data: { object: { id, amountInCents, currency, status, created } } }`
- **Production extras: idempotency keys, delivery monitoring, logs, a merchant dashboard with replay.** **A dedicated interview adds exactly-once delivery, outage backlogs, payload versioning, adaptive rate limiting.**
- ⚠ **Payload drift: §3's example is `data.paymentId`; this one is `data.object.id` plus `evt_` ids.** ⊕ ⚠ **At-least-once delivery + retries ⇒ merchants must dedupe on the event id, and events can arrive reordered ⇒ treat the webhook as a nudge and re-`GET` the intent.** ⚠ **Events built from CDC row diffs tie the public contract to internal table schema.** ▹ **Judgment calls.**

---

## 6 · Final Design

⚠ **Layout and arrows are mine; components are HI's.**

```
Customer browser ── iframe SDK (our domain) ── encrypts card with OUR PUBLIC key
      │               ⭐⭐⭐ ciphertext only; merchant page can't read the frame
      ▼
Merchant server ──► API Gateway ──► Payment (PaymentIntent) Service ──► Postgres        02d · 02g
   signed requests    HMAC · timestamp ·      create intent · serve status     sharded by merchantId
   (public key +      nonce (Redis SET NX     ⭐ unique (merchantId,           intents · transactions/attempts
    secret)            + TTL)             02a    idempotencyKey)                     │
                                                                                   │ WAL
Transaction Service  (PCI scope · HSM holds the private key)                       ▼
   ① write attempt `pending` + OUR ref id → COMMIT                        CDC ──► Kafka  02c
   ② call network with a timeout ──► External Payment Network               key = paymentIntentId · RF 3
   ③ attempt → succeeded / timeout / failed                                 3–5 partitions
                                                                              │
              ┌──────────────────────┬────────────────────────┬───────────────┤
              ▼                      ▼                        ▼               ▼
        Audit Service      Reconciliation Worker      Webhook Service        S3
        (immutable)        ⭐⭐⭐ queries network by    signed POST to        retention ·
                           OUR ref id + batch         callbackUrl ·         ⊕ Object Lock
                           settlement files ──►       backoff 5s·25s·125s…
                           writes status back to Postgres
                           ⊕ plus a periodic sweep of unresolved attempts

📐 10k TPS ⇒ ~5× that in row changes ⊕ · 500 B/row ⇒ ~500 GB/day ⇒ ~180 TB/yr · archive after 3–6 months
```

---

## 7 · Expected at Each Level

|Level|The bar for Payment System|
|---|---|
|**Mid-level**|**Core flow: create intent, take a card, return status. Know security matters and that card data shouldn't touch merchant servers; tokenization nuance not expected. "Timeout = failure" is acceptable if you can explain it. Expect guidance on the deeper challenges.**|
|**Senior**|**Move fast through the basics, then drive to security and consistency yourself. Propose the iframe approach and say why it beats merchants collecting cards. See that a timeout isn't a failure: idempotent transactions + pending resolution. Name the race conditions and how the design prevents a double charge. Scale services and DBs horizontally; may need prompting on Kafka partitioning and event sourcing.**|
|**Staff+**|**Deep payment expertise; check whether complexity is needed before reaching for it. Justify event sourcing + reconciliation by how financial systems work (async networks). Multi-layer security: tokenization with client-side encryption. Cover the hardest edges: network outages via fallback processing paths; reconciliation that guarantees eventual consistency with the networks.**|

> ⊕ **My reading: Senior ≈ the Good rungs (iframe; `pending_verification` + idempotency). Staff+ ≈ the Great rungs.** ⚠ **HI's Staff+ bar names fallback paths and "resilient reconciliation" — he designs neither. Be ready to sketch both (see DD3).**
> 
> ⊕ ▹ **HI's own Temporal deep dive uses this exact failure (charge succeeded, server crashed, did it happen?) and points to Multi-step Processes (`03c`) for safe retries.** ⚠ **This write-up carries the pattern name but never reaches for a durable workflow engine; it hand-builds a state machine + reconciler. Be ready to say why: no orchestrator needed, because the network is the source of truth.**
> 
> ■ **— end of insert · HI write-up resumes below —**

---

## Quick Recall (pass 3+)

|Use / Question|Payment System answer|
|---|---|
|Calibration|**Evan King · updated Jul 2025 · ⭐⭐ "HARD" · ⚠ "Asked at" unreadable ("C +4") · ⭐⭐ pattern `03c` Multi-step Processes · four dives + webhooks bonus.** ⭐⭐ **TWO passes, order DD3 > DD2 > DD1 > DD4 > webhooks**|
|⭐⭐⭐ Design driver|⭐⭐⭐ **You move money through a system you don't control, and "did it work?" can be "unknown".** **Network can succeed and lose the reply ⇒ no "timeout = failed" (DD3) · history must be provable later ⇒ no in-place updates (DD2) · card must exist only where needed ⇒ no merchant relay (DD1) · anyone can claim to be a merchant ⇒ no static key (DD1) · 10k/s with bursts ⇒ partition + shard (DD4)**|
|📐 Numbers|**10k TPS peak.** **Kafka ~5–10k msg/s per partition ⇒ 3–5 partitions, RF 3, key `paymentIntentId`.** **500 B/row × 10k/s = 5 MB/s ⇒ ~500 GB/day ⇒ ~180 TB/yr ⇒ archive after 3–6 months.** **Postgres at 10k writes/s "on the edge" ⇒ replicas + shard by `merchantId`.** ⊕ **A payment is several row writes ⇒ ~40–60k events/s.** **Timestamp window 5–15 min.** **Webhook backoff 5s, 25s, 125s … ~1h**|
|FRs / NFRs|**Merchants initiate payment requests · customers pay by card · merchants view status.** Below: saved methods · refunds · history/reports · other payment methods · subscriptions · payouts. **NFRs: ⭐⭐ highly secure · ⭐⭐⭐ durability + auditability, no transaction data ever lost · ⭐⭐⭐ transaction safety + financial integrity despite async networks · ⭐ scale to 10k+ TPS, bursty.** Below: global regulations · extensibility|
|⭐⭐ Queue in the path?|⊕ **No queue in the charge path: the checkout waits for the authorisation, so the answer IS the work (as in `05v`). Kafka sits behind the write via CDC.** ▸ **Contrast ChatGPT: there the response didn't wait, so a queue was fine**|
|Entities + the loose spots|**Merchant · PaymentIntent (state machine, idempotency) · Transaction (polymorphic money movement; ONE intent → MANY transactions: retry, partial payment, negative-amount refund).** ⚠⚠ **Loose: three status vocabularies (`created/authorized/captured…` vs `created/processing/succeeded/failed` vs `pending_verification`); drifting names; and the ATTEMPT has no home — ⊕ for a charge the Transaction row IS the attempt, written `pending` with OUR reference id before the call**|
|API + two planted gaps|`POST /payment-intents {amountInCents, currency, description}` · `POST /payment-intents/{id}/transactions {type: "charge", card{…}}` · `GET /payment-intents/{id}` · `POST {merchant_webhook_url}`. ⚠⚠ **The raw card in the second call is planted — DD1 fixes it but the API is never redrawn.** ⚠⚠ **No idempotency key anywhere, though DD3 depends on one.** ⭐ **Integer cents + currency; merchant from the API key**|
|§4.2 flow + three gaps|**Customer → merchant → Transaction Service → pending Transaction → network auth request → first answer → listen for callbacks → update Transaction + PaymentIntent.** ⭐ **One service ⇒ one PCI scope.** ⚠⚠ **Gaps: ① card goes via merchant (the DD1 Bad rung) ② sync or async never stated — DD3 implies inline with a 30–60s timeout, §4.3 has `processing` ③ "listens for callbacks" is stateful but DD4 says every service is stateless**|
|⭐⭐ DD1A — merchant auth|⭐ **Good: static key, looked up by the gateway — replayable forever, leaks via repos/clients, no replay detection.** ⭐⭐ **Great: public key + secret key; sign method/path/params/body + timestamp + nonce with HMAC-SHA-256; gateway checks signature, 5–15 min window, nonce unused.** ⊕ **Costs: recoverable secret (KMS/HSM), nonce = Redis `SET NX` + TTL ≥ window, sign everything**|
|⭐⭐⭐ DD1B — card data|⚠⚠ **Bad: merchant collects the card — breaks PCI DSS, every merchant server is a target, they carry the liability.** **Good: iframe from our domain, same-origin policy hides it from the merchant — still rests on browser policy, HTTPS-only in transit, less customisable, awkward on mobile.** ⭐⭐⭐ **Great: SDK encrypts in the browser with our PUBLIC key; private key in HSMs; HTTPS carries ciphertext — defence in depth**|
|⚠⚠ DD1 — what HI leaves loose|⊕ **Encryption's real win: every hop (gateway, LB, logs) holds only ciphertext — not protection from a compromised SDK, which reads the card first.** ⚠⚠ **Tokenization promised, never designed ⇒ token = opaque id for a vaulted card.** ⚠⚠ **DD1 × DD2: CDC copies every row into Kafka + S3 forever — a card number in any row or `metadata` becomes an immutable PCI problem**|
|⚠⚠ DD2 Bad — update in place|**`UPDATE … SET status = 'captured'` + backups.** ⭐ **① history destroyed (was pending, when, by whom) ② a buggy deploy corrupts silently, backups can't say which rows ③ fails audits (full history + proof of no tampering) ④ support does "archeology"**|
|DD2 Good — audit table|**Same-transaction `UPDATE` + `INSERT INTO payment_audit_log`, append-only, insert-only permissions.** ⚠ **① app must remember both ② 10k-TPS DB also stores billions of audit rows, no independent tuning.** ⊕ **A DB trigger answers ①; ② stands**|
|⭐⭐⭐ DD2 Great — CDC|⭐⭐⭐ **CDC reads the WAL, emits every committed change; Kafka keyed by intent id, before/after state; consumers: Audit · Analytics · Reconciliation · Webhooks; RF 3, 7–30 days, all flushed to S3.** ⭐⭐ **"If a change commits to the database, it will appear in the event stream."** ▸ **Snapshot (DB) + stream (log) — `05q`/`05o`/ChatGPT; here the DB decides and the log remembers**|
|⚠⚠ DD2 — what HI leaves loose|⚠⚠ **CDC is a SPOF; his fix has an app-level fallback writing straight to Kafka = the dual-write he rejected one rung up; several CDC streams ⇒ duplicate events, consumers must dedupe.** ⚠ **"Cryptographically verifiable immutability" asserted not designed ⇒ ⊕ S3 Object Lock / hash chain.** ⚠ **"Sub-10ms" is intent creation, not the charge**|
|⚠⚠⚠ DD3 Bad — timeout = failed|**30–60s timeout ⇒ mark `failed`.** ⚠⚠⚠ **$200 charge: bank debits, reply lost, we mark failed, merchant says "try again", customer retries ⇒ $400.** **The reverse: charged but we say failed ⇒ nothing ships.** ⚠ **HI's mid-level bar accepts this**|
|⭐⭐ DD3 Good — pending + attempts + idempotency|**Timeout ⇒ `pending_verification`; an attempts table (what we sent, when, "the reference ID the network assigned"); a background poller queries the network; unique (merchantId, idempotencyKey) returns the existing payment on retry.** ⚠ **HI's challenges: manual reconciliation, an exception bolted on, one DB bears both loads**|
|⚠⚠ DD3 Good — what doesn't hold|⚠⚠ **① "reference ID the network assigned" — none exists after a timeout ⇒ only an ID WE generated and sent works.** ⚠⚠ **② Approach is an automated poller, challenge is manual finance review.** ⚠⚠ **③ Idempotency exists only here (not in API, schema, or rung 3) and a retry after failure makes a NEW Transaction ⇒ ⊕ state guard: no new charge while an attempt is unresolved; at most one succeeded charge per intent (`03b`)**|
|⭐⭐⭐ DD3 Great — write-ahead + reconcile|⭐⭐⭐ **① record the attempt BEFORE the call (network, reference id, purpose) ⇒ CDC event ② call with a timeout ③ succeeded / timeout / failed, each a CDC event ④ reconciliation service consumes timeouts and queries the network by OUR reference id.** ⭐⭐ **Two truth sources: direct queries (real time) and batch settlement files (the definitive record, daily/hourly).** ⭐ **Statuses come from authoritative data, not from timeouts**|
|⚠⚠ DD3 Great — what doesn't hold|⚠⚠ **Rung 3 doesn't contain rung 2: the reconciler sees a timeout once; "not yet" needs a periodic sweep (rung 2's poller) ⇒ ⊕ a log announces, durable per-attempt state retries (`05i`/`05p`/`05q`/`05t`).** ⚠⚠ **"Not found" ≠ "didn't happen" ⇒ ⊕ stay pending until the settlement file or a void after a grace period.** ⚠ **Two-phase "created/completed" events are emitted by the service — a second event source beside CDC — and "most missing events…" is unsupported**|
|⭐ Two-phase events (production aside)|**"Created" emitted when processing starts, before the DB write (fail ⇒ locked, retryable); "completed" emitted after the write (fail ⇒ locked, updates blocked). On retry compare the created event with DB state; if written, re-emit "completed" only**|
|⚠⚠ Staff+ bar not designed|**HI asks for network-outage fallback paths and resilient reconciliation; neither is built.** ⊕ **Health-checked routing across acquirers, but never re-send an UNRESOLVED attempt elsewhere — double-charge across networks**|
|⭐⭐ DD4 — Kafka + DB|**Stateless services behind LBs (say it, don't draw it).** **Kafka: 3–5 partitions, key `payment_intent_id` (ordered per intent, parallel across), RF 3, a consumer group per service.** ⚠⚠ **"Exactly-once" only inside Kafka; consumers hitting networks/webhooks/DB are at-least-once ⇒ idempotent consumers.** ⊕ ⚠ **Per-table CDC topics ⇒ no cross-table order.** **DB: shard by `merchantId`** ✅ **idempotency constraint stays on one shard** ⚠ **hot merchant = hot shard**|
|📐 DD4 — storage + reads|📐 **500 B × 10k/s = 5 MB/s × 100k s = 500 GB/day ⇒ ~180 TB/yr (⊕ upper bound: peak ≠ average).** **Cold storage after 3–6 months via scheduled export + purge.** ⚠ **DD2's "dispute six months later" sits on that cut-off.** **Read replicas + Redis/Memcached for recent statuses.** ⊕ ⚠ **Replica lag: create-then-GET can miss**|
|⭐⭐ Webhooks (bonus)|**Merchant adds `callbackUrl` + `subscribedEvents`. Server-to-server, NOT SSE/WebSocket (`03a`). CDC → Kafka → Webhook Service (same stream as Reconciliation) → check subscription → sign with shared secret → POST → record delivery → exponential backoff (5s, 25s, 125s … ~1h) → merchant verifies signature, returns 2xx.** ⚠ **Payload shape differs from §3.** ⊕ ⚠ **At-least-once + reordering ⇒ dedupe on event id, treat it as a nudge and re-`GET`**|
|⭐⭐ §4.1 + §4.3 flows|**Create: merchant `POST /payment-intents` → gateway authenticates → PaymentIntent Service writes `created` → returns the id; nothing is charged.** **Status: merchant `GET /payment-intents/{id}` → gateway authenticates → service reads status, error, related transactions → returns.** ⭐ **Statuses: `created` · `processing` · `succeeded` · `failed`. Polling is "not ideal" for real-time ⇒ webhooks.** ⭐⭐ **Status is per INTENT (the only id the merchant holds), a roll-up of its Transactions: in flight ⇒ `processing` · a charge succeeded ⇒ `succeeded` · latest attempt failed ⇒ `failed` · retry ⇒ `processing` again.** ⚠ **HI never states the rule**|
|⭐⭐ ⊕ One state machine to say out loud|**Intent: `created → processing → succeeded / failed`, plus `pending_verification` while an attempt is unresolved.** **Attempt (= the Transaction row for a charge): `pending → succeeded / failed / timeout → resolved by the reconciler`.** ⭐ **Guards: no new charge while an attempt is unresolved; at most one succeeded charge per intent.** ▹ **HI's own text mixes `authorized/captured` with these; use them only if you split auth from capture**|
|⭐⭐⭐ ⊕ Idempotency, the whole picture|**`Idempotency-Key` on both POSTs (above all the charge) · unique (merchantId, key) returns the existing record · state guard for NEW retries with NEW keys · one succeeded charge per intent · idempotent Kafka consumers (keyed on event/attempt id) · merchants dedupe webhooks on event id.** ⚠ **HI shows the first two only, and only in DD3 rung 2**|
|⭐⭐ ⊕ Sync or async charge?|**Return the result if the network answers quickly; otherwise return `processing` and let poll/webhook finish. The reconciler covers the long tail.** ⚠ **HI never says; his "sub-10ms" and 30–60s timeout can't both describe the charge call**|
|⭐⭐⭐ Later dives that break earlier ones|⚠⚠ **DD2 CDC × DD1: a card number in any row ends up in Kafka + S3 for good ⇒ tokens only.** ⚠⚠ **DD3 Great × DD3 Good: the event-driven reconciler still needs rung 2's sweep, and idempotency vanished from rung 3.** ⚠ **DD4 × DD2: events/s is a multiple of TPS.** ⚠ **DD4 "stateless" × §4.2 "listens for callbacks".** ⚠ **DD2 "no app code" × the two-phase events emitted by the service.** ▸ **Say "I checked whether my fixes compose" out loud**|
|⭐ Threads this file extends|**"Snapshot for state + stream for change" (DB + CDC log) · "attempt gets its own identity" (Transaction row / `05v` Order / ChatGPT Run) · "a log is not a work queue" (reconciler needs a sweep) · "Redis SET NX + TTL" (nonce store) · "a queue is fine when the RESPONSE doesn't wait" (no queue in the charge path, as `05v`) · "too much traffic for one key → replicate" (hot merchant shard, `05g`)**|
|⭐⭐⭐ The meta-lesson|⭐⭐⭐ **Three ideas outlive this problem: (1) "no answer" from a system you don't control is an unknown, not a failure — hold it as a state and ask the authority; (2) record the intent under your own ID BEFORE the side effect; (3) dedupe retries in the database, and capture history below the app**|
|Levels (one line)|**Mid:** core flow, card data off merchant servers, "timeout = failure" tolerated · **Senior:** iframe, timeouts aren't failures, idempotency + pending resolution, name the double-charge race · **Staff+:** event sourcing + reconciliation, tokenization + client-side encryption, outage fallback paths|

---

> 🔗 **HI source:** https://www.hellointerview.com/learn/system-design/problem-breakdowns/payment-system