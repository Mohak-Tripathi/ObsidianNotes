# WhatsApp — Problem Breakdown

> 📐 **Revision note (calc):** **200M active users × ~20 messages/day = 4B messages/day ≈ 40k/s (⊕ exactly 4B ÷ 86,400 ≈ 46k/s) · Message + Inbox writes ≈ 100k writes/s with groups.** 📐 **1B users ⇒ ~200M connected · 1–2M connections per host ⇒ ⊕ 100–200 Chat Servers.** 📐 **Kafka: ~50 KB per topic × 1B topics = 50 TB+ of overhead.** 📐 **Heartbeats: 200M ÷ 10 s = 20M ping/pong per second; detection ≤ 10 s interval + 5 s timeout = 15 s. Polling: 200M ÷ 30 s ≈ 7M queries/s.** 📐 **Limits: 100 per group · 30 days offline · 3 clients per account · ACK timeout 500–2000 ms.**

> Common Problems · **Stefan Mai, updated Feb 16, 2026** · ⭐⭐ **"medium"** · **Asked at: +24 companies** (names not shown in the paste) · ⭐⭐ **Pattern: `Real-time Updates` → `03a`** · Cross-refs: ⭐⭐⭐ **ChatGPT (31) DD2 — pub/sub has no memory** · ⭐⭐⭐ **Distributed Cache (12) DD3 — consistent hashing; DD4 — hot keys** · ⭐⭐ **Rate Limiter (13) DD5 — push needs a poll backstop** · ⭐⭐ **Ad Click (25) — Flink watermarks (out-of-order)** · **`02a` Redis · `02c` Kafka · `02b` DynamoDB · `02i` ZooKeeper.**
> 
> **Calibration:** ⭐⭐⭐ **TWO passes (my call): it's the canonical real-time question, asked at many companies, and its ideas (durable write, then best-effort push; ACKs; heartbeats; sequence numbers) recur everywhere.** ⭐ **Order: DD1 > §4.3 > DD4 > DD3 > DD2 > DD6 > DD5 > §4.1 / §4.4.**
> 
> - ⭐⭐ **What actually scores:** **(a)** ⭐⭐⭐ **WebSockets as the API, with client ACKs** · **(b)** ⭐⭐⭐ **the Inbox: write durably first, then deliver, delete on ACK** · **(c)** ⭐⭐⭐ **routing across Chat Servers: why LB-only and Kafka-per-user fail; consistent hashing vs Redis Pub/Sub** · **(d)** ⭐⭐ **multiple devices ⇒ per-client inbox** · **(e)** ⭐⭐ **dead-connection detection: ACK timeout + heartbeats** · **(f)** ⭐⭐ **missed pub/sub messages: sequence numbers + polling** · **(g)** ⭐ **ordering by server timestamp; "last seen" from disconnects.**
> - ⭐ **Transferable primitives:**
>     - ⭐⭐⭐ **Write durably first, then push best-effort; the durable store is the backstop for every lost push.**
>     - ⭐⭐⭐ **Only an end-to-end ACK proves delivery.**
>     - ⭐⭐⭐ **Reason on a single node first; scale out after the mechanics work.**
>     - ⭐⭐ **A silent connection needs an active probe (heartbeat), not a timeout.**
>     - ⭐⭐ **Sequence numbers turn "did I miss something?" into a cheap comparison.**
> - ⭐ **Re-run (cross-ref only):** **consistent hashing (Distributed Cache DD3) · pub/sub at-most-once (ChatGPT DD2) · Redis `INCR` (Rate Limiter) · conditional writes (Payment System) · watermarks (Ad Click).** **Genuinely new:** ⭐⭐⭐ **WebSocket command API + ACKs** · ⭐⭐⭐ **per-recipient Inbox** · ⭐⭐⭐ **routing between stateful connection servers** · ⭐⭐ **heartbeats and gap detection** · ⭐ **presence from connect/disconnect.**

---

## 0 · Understanding the problem

💬 **WhatsApp sends and receives encrypted messages and calls from phones and computers; famously built on Erlang and run at high scale with a small team and little infrastructure.**

⭐ **Don't dawdle on requirements: cover the obvious features and ask the interviewer whether to go beyond.**

---

## 1 · Requirements

### 1.1 Functional

1. ⭐⭐ **Users can start group chats with multiple participants (limit 100).**
2. ⭐⭐⭐ **Users can send/receive messages.**
3. ⭐⭐⭐ **Users can receive messages sent while they were offline (up to 30 days).**
4. ⭐⭐ **Users can send/receive media in their messages.**

⭐ **HI: the third isn't obvious to everyone, but it's interesting to design — he would guide you to it.**

⚠ **Below the line:** **Audio/video calling · Interactions with businesses · Registration and profile management.**

### 1.2 Non-functional

⭐ **First ask how the app is used: mostly 1:1 or large groups? How often do people send? Not requirements, but they drive later decisions.**

1. ⭐⭐ **Messages delivered to available users with low latency, < 500 ms.**
2. ⭐⭐⭐ **Guaranteed deliverability: messages must reach users.**
3. ⭐⭐ **Billions of users with high throughput.**
4. ⭐⭐ **Messages stored on central servers no longer than necessary.**
5. ⭐⭐ **Resilient to failures of individual components.**

⚠ **Below the line:** **Exhaustive security treatment · Spam and scraping prevention.** ▹ **Extra out-of-scope features show product thinking, but are only a nice-to-have — don't burn time on them.**

> ⚠ **Two tensions.** ⊕ **NFR 2 ("guarantee delivery") is at-least-once — so the client must dedupe redeliveries (see §3). NFR 4 ("no longer than necessary") sits badly with a 30-day TTL on the Message table (§4.3).**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 1.3 ⭐⭐⭐ The design driver — persistent connections spread over hundreds of servers, a delivery guarantee, and recipients who are often offline

|Constraint|What it breaks|Fixed by|
|---|---|---|
|⭐⭐⭐ **high-frequency, two-way traffic**|**REST request/response**|**a WebSocket per client (§3)**|
|⭐⭐⭐ **recipients offline up to 30 days**|**fire-and-forget delivery**|**Inbox + ACK + delete (§4.3)**|
|⭐⭐⭐ **sender and recipient on different servers**|**one server's connection map**|**consistent hashing or Redis Pub/Sub (DD1)**|
|⭐⭐ **one user, several devices**|**a per-user inbox**|**Clients table + per-client inbox (DD2)**|
|⭐⭐ **sockets die silently**|**TCP keepalive (minutes)**|**ACK timeout + heartbeats (DD3)**|
|⭐⭐ **pub/sub drops messages**|**best-effort push alone**|**sequence numbers + polling (DD4)**|
|⭐ **media is heavy**|**Chat Server + DB**|**a separate HTTP upload path (§4.4)**|

### 1.4 Planning the approach

- ⭐⭐ **1:1 chats are just groups of two — solve the general group case.**
- ⭐⭐ **Two halves: delivering DURABLY, and delivering in REAL TIME.**
- ⭐ **Walk the FRs as simply as possible (slow, not scalable), then fix scale and extras in the deep dives.**

---

## 2 · Core Entities

- **Users**
- **Chats** — ⭐ **2–100 users.**
- **Messages**
- **Clients** — ⭐⭐ **a user can have several devices.**

⭐ **Interviewers don't grade the entity list, but wrong entities are a broken foundation — spend a few moments and move on.**

---

## 3 · API — commands over a WebSocket

⭐⭐⭐ **Chat traffic is high-frequency in both directions ⇒ a bidirectional socket, not REST. WebSockets over TLS (a custom protocol over raw TLS/TCP would also work). The client connects on app open; commands over the socket ARE the API.**

> ⭐⭐ **Pattern: Real-time Updates (`03a`)** — **persistent connections for low latency, pub/sub to scale across servers, careful state management for reliability — the same for chat, live dashboards, collaborative editing, gaming.**
> 
> ■ **— end of insert · HI write-up resumes below —**

**Commands sent (client → server):**

```
createChat              { participants: [], name }            -> { chatId }
sendMessage             { chatId, message, attachments: [] }  -> { status: SUCCESS|FAILURE, messageId }
createAttachment        { body, hash }                        -> { attachmentId }     (amended in §4.4)
modifyChatParticipants  { chatId, userId, operation: ADD|REMOVE } -> SUCCESS|FAILURE
```

**Commands received (server → client), each answered with an ACK:**

```
chatUpdate   { chatId, participants: [] }                  -> RECEIVED
newMessage   { chatId, userId, message, attachments: [] }  -> RECEIVED
```

- ⭐⭐⭐ **The ACK is non-obvious but crucial: when the client confirms receipt, the server knows the message reached the device and needn't resend it.**
- ▹ **HI: in the interview, write just the command names; "I'll come back to this" is fine.**

> ⚠ **What HI leaves loose.**
> 
> - ⚠⚠ **No client-generated id on `sendMessage`.** ⊕ **A sender who times out and retries creates a duplicate. Have the client send a `clientMessageId` (idempotency key) and dedupe on it (Payment System idempotency).**
> - ⚠⚠ **At-least-once delivery means redelivery after a lost ACK.** ⊕ **`newMessage` must carry `messageId` so the client drops duplicates. HI's `newMessage` has no id.**
> 
> ■ **— end of insert · HI write-up resumes below —**

---

## 4 · High-Level Design

### 4.1) Users can start group chats (limit 100)

⭐ **A Chat Server behind an L4 load balancer writes chat metadata to DynamoDB (fast key-value, scales).**

- ⭐⭐ **Why L4? L7 balancers support WebSockets, but we need no L7 features (path/header routing, spreading HTTP requests); L4 is enough and faster.**

**Flow:**

- ① **The user connects and sends `createChat`.**
- ② **The service writes a `Chat` row and one `ChatParticipant` row per member — one DynamoDB transaction for small chats (up to 100 items); near the 100 limit, batch the writes.**
- ③ **It returns the `chatId`.**

**Data model:**

- ⭐ **`Chat` (`id`, `name`, `metadata`): primary key on the chat id.**
- ⭐⭐ **`ChatParticipant`: partition key `chatId`, sort key `participantId` ⇒ all members of a chat. A GSI with `participantId` as partition key and `chatId` as sort key ⇒ all chats of a user; DynamoDB keeps the GSI in sync.**

> ⚠ **What HI leaves loose.**
> 
> - ⚠ **"Batch the writes" gives up atomicity: a crash halfway leaves a chat with some members.** ⊕ **Write the Chat row last (or mark it ACTIVE at the end) so a half-made chat is invisible; make `createChat` idempotent so a retry finishes it.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 4.2) Users can send/receive messages

⭐⭐⭐ **Start with ONE Chat Server — terrible for scale (say so), but the mechanics are clear. HI: for infrastructure interviews, reason on a single node first; solving scale before the mechanics backs you into a corner.**

- ⭐⭐ **The server keeps an in-memory hash map: userId → WebSocket connection.**

**Flow:**

- ① **The user sends `sendMessage`.**
- ② **The Chat Server looks up the chat's members in `ChatParticipant`.**
- ③ **For each member it finds the connection in its map and sends the message.**

⚠ **Strong assumptions: everyone is online, on this one server, with a live connection. Under those, it works.**

### 4.3) Users can receive messages sent while offline (up to 30 days)

⭐⭐⭐ **Store messages so offline users can get them, and add robustness: an INBOX per user holding undelivered messages. On send, write to every recipient's inbox; deliver at once if online, otherwise wait.**

📐 ⭐⭐ **Write load: most chats are 1:1; ~20 messages per user per day × 200M active users = 4B/day ≈ 40k/s. Each 1:1 message = one Message write + one Inbox write; with groups, ~100k writes/s — fine for DynamoDB with `userId` as partition key.**

**Tables:** **`Message` (`id`, `chatId`, `contents`, `creatorId`, `timestamp`) · `Inbox` (`recipientId`, `messageId`).**

**Send flow:**

- ① **The sender sends `sendMessage`.**
- ② **The Chat Server looks up the members.**
- ③ **It (a) writes the `Message` row and (b) writes an `Inbox` row for each recipient.**
- ④ **It returns SUCCESS or FAILURE with the final message id.**
- ⑤ **It finds each member's connection and delivers via `newMessage`.**
- ⑥ **A connected client ACKs; the server deletes that `Inbox` row.**

**Reconnect flow (offline users):**

- ① **Look up the user's Inbox for undelivered message ids.**
- ② **Fetch each message from the `Message` table.**
- ③ **Send them over the connection with `newMessage`.**
- ④ **The client ACKs; the server deletes the Inbox rows.**

⭐ **Cleanup: a TTL on Inbox and Message items removes old ones.**

> ⚠⚠ **What HI leaves loose.**
> 
> - ⚠⚠ **Step ③ is several writes with no stated atomicity.** ⊕ **If the server dies after the Message row but before every Inbox row, some recipients never get the message — the exact guarantee NFR 2 promises. Use one DynamoDB transaction (1 Message + 99 Inbox = 100 items, just at the limit), or write the Message first and have a retry/outbox create the Inbox rows. After DD2 (3 clients each), a 100-person chat needs ~300 Inbox rows — past the transaction limit.**
> - ⚠⚠ **The Message row lives for the full TTL (30 days) even after every recipient ACKed — against NFR 4.** ⊕ **Delete it when its last Inbox row is deleted (a per-message count of pending recipients), and keep the TTL only as a backstop.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 4.4) Users can send/receive media

⭐⭐ **Media is bandwidth- and storage-heavy. The Chat Server and DB could do it, but purpose-built technology is better — HI: WhatsApp really uploads attachments through a separate HTTP service.**

#### ⚠⚠ Bad — send media over the WebSocket, store it in the database

**What it is:**

- ⭐ **The Chat Server accepts the file over the existing WebSocket and saves it in the database; a new message type lets users fetch attachments.**

**Challenges:**

- ⚠⚠ **Most databases, DynamoDB included, aren't built for large binary blobs.**
- ⚠⚠ **It eats the Chat Servers' bandwidth with dumb storage and retrieval work, taking it from real-time messaging.**

**Why climb:** ⭐ **move the bytes to storage built for blobs.**

#### Good — Chat Server forwards the file to blob storage

**What it is:**

- ⭐⭐ **The Chat Server still receives the file, then pushes it to blob storage (S3) with a 30-day TTL — we don't keep messages forever.**
- ⭐⭐ **Recipients download straight from blob storage with a pre-signed URL (that's the authorisation).**
- ⭐ **A CDN could sit in front, but chats are capped at 100 people, so the cache gain is small.**

**Challenges:**

- ⚠⚠ **The Chat Server still handles every upload only to pass it on — a wasted hop.**
- ⚠ **Media isn't deleted once every recipient has downloaded it (only the TTL removes it).**
- ⚠ **Encryption and security need extra steps.**

**Why climb:** ⭐ **take the Chat Server out of the upload path too.**

#### ⭐⭐⭐ Great — upload directly with a pre-signed URL (HI's pick)

**What it is:**

- ⭐⭐⭐ **The client asks the Chat Server for an upload target (`getAttachmentTarget`) and gets back a pre-signed URL.**
- ⭐⭐ **It uploads straight to blob storage, then sends the resulting attachment URL to the Chat Server as an opaque value inside the message.**
- ⭐⭐ **Downloads work as in Good: recipients read from blob storage with a pre-signed URL; a CDN adds little at ≤ 100 recipients.**

**Flow:**

- ① **Client → `getAttachmentTarget` → pre-signed upload URL.**
- ② **Client uploads the file directly to blob storage.**
- ③ **Client sends `sendMessage` with the attachment URL.**
- ④ **Recipients fetch the file from blob storage with a pre-signed GET.**

**Challenges:**

- ⚠ **Still no deletion once all recipients have downloaded it.**
- ⚠ **Encryption and security still need extra steps.**

> ⚠ **What HI leaves loose.**
> 
> - ⚠⚠ **"Delete once everyone has downloaded" is named in all three rungs and solved in none.** ⊕ **Reuse the message's pending-recipients count (§4.3): when the last recipient ACKs, delete the blob; the 30-day TTL stays as a backstop.**
> - ⚠ **This replaces `createAttachment { body, hash }` from §3 — the "amended later" HI promised.** ⊕ **Keep the `hash` to dedupe identical uploads.**
> - ⊕ **With end-to-end encryption, the client encrypts the file and puts the key inside the (encrypted) message, so storage only ever holds ciphertext — that's the "extra steps".**
> - ⚠ **The pre-signed upload URL should be short-lived and limit size and content type, or it's an open bucket.**
> 
> ■ **— end of insert · HI write-up resumes below —**

⭐ **We now have real-time delivery, offline persistence and attachments. It just doesn't scale — yet.**

---

## 5 · Deep Dives

⭐⭐ **All levels should point out that one host won't scale. Beyond that, at mid-level the interviewer may drive; at senior and staff+ you should spot problems yourself and propose fixes.**

### 1) How can we handle billions of simultaneous users?

⭐⭐ **One host can't serve billions, and deploys and failures would be a nightmare ⇒ many Chat Servers.** 📐 **1B users ⇒ ~200M connected at once; WhatsApp served 1–2M users per host ⇒ hundreds of servers.** ▹ **HI: do maths just-in-time, when you need it to find a bottleneck.**

⭐⭐⭐ **The new problem — routing: User A on Server 1 sends to B and C; B is on Server 1 and gets it, C is on Server 2 and doesn't. We must route messages to the server holding each recipient's connection.** ▸ **Realtime Updates lesson.**

#### ⚠⚠ Bad — just put a load balancer in front

**What it is:**

- ⭐ **Scale horizontally: add hosts behind the load balancer.**

**Challenges:**

- ⚠⚠ **A server accepts the message but has no guarantee it holds the recipients' connections — it can't deliver. HI: don't do this in an interview.**

**Why climb:** ⭐ **we need a way to get a message to the right server.**

#### ⚠ Bad — a Kafka topic per user

**What it is:**

- ⭐ **Candidates often reach for a queue: turn each user's Inbox into a Kafka topic. On connect, the Chat Server subscribes to that user's topic; to send, publish to the recipient's topic; every subscribed server receives it and forwards it to the socket.**

**Challenges:**

- ⚠⚠ **Kafka isn't built for billions of topics: ~50 KB overhead per topic ⇒ 50 TB+ for 1B users.**
- ⚠ **"Super topics" (one per Chat Server) start to reinvent the options below, with little of their benefit.**

**Why climb:** ⭐ **route directly, or use a channel that is cheap per user.**

#### ⭐⭐ Good — consistent hashing of users to Chat Servers

**What it is:**

- ⭐⭐ **Assign every user to one Chat Server by user id, so we always know who holds a user's connection.**
- ⭐⭐ **A central registry (ZooKeeper or etcd) holds the server list, their addresses, and which part of the hash space each owns.**
- ⭐ **On connect, the user is sent to their assigned server. To deliver, a Chat Server calls the owning server directly, which pushes to the user if connected.**

**Challenges:**

- ⚠⚠ **Every Chat Server keeps connections to every other one ⇒ servers must be big and few.**
    - 💬 **Why:** **ZooKeeper/etcd only answers WHO owns a user — it doesn't carry messages. Users are spread over many servers, so Chat Server 1 asks the registry "who owns User C?", gets Chat Server 2's address, then must send the message to Server 2 itself, over a direct connection. Any server may need to reach any other ⇒ each keeps a connection to every other server (a full mesh).**
    - 📐 ⊕ **200 servers ⇒ ~199 connections each, 200 × 199 ÷ 2 ≈ 20,000 links in total, growing with N². Fewer, bigger servers keep the mesh small. Redis Pub/Sub (Great) removes the mesh: every server talks only to the few Redis nodes.**
- ⚠⚠ **Adding servers needs careful orchestration: drop connections so users reconnect elsewhere without a thundering herd, and send events to BOTH old and new servers during the move so none are lost.**
- ⚠ **HI rates it Good, not Great: solvable, but it creates many problems you must explain.**

**Why climb:** ⭐ **let a purpose-built system ferry messages between servers.**

#### ⭐⭐⭐ Great — Redis Pub/Sub (HI's pick)

**What it is:**

- ⭐⭐⭐ **A lightweight hashmap of subscriber connections that ferries messages anywhere: subscribe to a channel per user id; publish to it; delivery is "at most once".**
- ⭐⭐ **Unlike Kafka, it stores nothing (no disk, no offsets): a channel is an in-memory pointer to subscribers. Shard across a Redis cluster by user id.**

**Flow on connect:**

- ① **The Chat Server subscribes to the channel for that user id.**
- ② **Anything arriving on it is forwarded to the user's WebSocket.**

**Flow on send — the order matters:**

- ① **Write the Message row and Inbox rows (durable).**
- ② **Return success to the sender.**
- ③ **Publish to each recipient's channel (best-effort); subscribed servers forward to the sockets.**
- ⭐⭐⭐ **If ③ fails the message is still stored; the recipient gets it on reconnect (Inbox sync) or through polling (DD4).**

⭐ **Scale note: Canva ran 100,000 updates/s on one Redis host at 27% utilisation — Pub/Sub just passes messages.**

**Challenges:**

- ⚠ **Extra latency for the Redis hop — single-digit milliseconds.**
- ⚠ **Every Chat Server connects to every Redis node — fine, since few Redis instances are needed.**

#### Partition channels by chat or by user?

- ⭐⭐ **Depends on (a) chats per user and (b) chat size. WhatsApp is mostly 1:1, so per-chat channels mean hundreds of redundant subscriptions for little benefit; groups are capped at 100 ⇒ per user.**
- ⭐⭐ **Senior follow-up — a "celebrity problem": rare large chats cost a lot. Adapt by size: on connect, also subscribe to channels for the user's chats above a threshold (say 25 members); messages to those chats go to the chat channel, not to each user's. Edge case: when a chat crosses the threshold, publish to BOTH channels for a while so servers have time to subscribe.**

> ⚠⚠ **What HI leaves loose.**
> 
> - ⚠⚠ **"Shard Redis by user id" is not free in classic Redis Cluster: a `PUBLISH` is broadcast to EVERY node.** ⊕ **Redis 7's sharded pub/sub (`SSUBSCRIBE`/`SPUBLISH`) keeps a channel on its slot's node; or shard in the client with consistent hashing (textbook).**
> - ⚠ **Pub/Sub channels have no memory (ChatGPT DD2): a server that briefly lost its Redis connection misses messages and must resubscribe — DD4 is the backstop.**
> - ⚠ **On a deploy, drain servers gradually or reconnects become a thundering herd.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 2) What do we do to handle multiple clients for a given user?

⭐⭐ **Phone, tablet, laptop, work computer: my phone got the latest message but my laptop was off — when it wakes, it must sync. A per-user Inbox can't track that.**

**Three new problems:**

- ① **Resolve a user to the 1+ clients active at a time.**
- ② **Deactivate clients that no longer exist, so we stop storing messages for them.**
- ③ **Deliver to every client.**

**Changes (minimal):**

- ⭐⭐ **A new `Clients` table (`id`, `userId`).**
- ⭐⭐ **Looking up a chat's participants now also looks up each user's clients.**
- ⭐⭐⭐ **The Inbox becomes per CLIENT: `recipientClientId`, `messageId`.**
- ⭐ **Send to every client of each user.**
- ⭐ **Pub/Sub is unchanged: servers still subscribe by userId.**
- ⭐ **Cap it, e.g. 3 clients per account, to bound storage and throughput.**

> ⚠ **What HI leaves loose.**
> 
> - ⚠⚠ **Problem ② gets no mechanism.** ⊕ **Track `lastActiveAt` per client; deactivate after N days unseen (or on logout), and drop its Inbox rows.**
> - ⚠ **Inbox writes grow ×3: a 100-person chat ⇒ up to ~300 rows per message — past a single DynamoDB transaction (see §4.3).**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 3) What happens if the WebSocket connection fails?

⭐⭐ **On a poor network the socket can look open but be dead; we only find out when a send times out. TCP keepalives can take minutes — far too slow for chat.**

#### ⚠ Bad — do nothing special

**What it is:**

- ⭐ **Wait for TCP to time out and close the socket; the client reconnects and syncs from the Inbox.**

**Challenges:**

- ⚠⚠ **Keepalives are configured in minutes: the user stares at a "connected" app that is dead, missing messages.**

**Why climb:** ⭐ **detect the dead socket ourselves, faster.**

#### Good — server-side ACK timeout

**What it is:**

- ⭐⭐ **After delivering, the server waits for the client's ACK. No ACK within ~500–2000 ms ⇒ retry. After a few failed retries, assume the socket is broken, close it, and force a reconnect + Inbox sync.**
- ✅ **Reuses the existing ACK (the one that clears the Inbox); only a timeout is added.**

**Challenges:**

- ⚠ **Detects failures only while we're sending. A socket that dies in a quiet period goes unnoticed until the next message.**

**Why climb:** ⭐ **probe even when there's nothing to send.**

#### ⭐⭐⭐ Great — application heartbeats

**What it is:**

- ⭐⭐⭐ **The server sends a ping every 10–30 s; the client must pong within ~5 s, or the server closes the connection. The client reconnects and syncs. Dead sockets are caught in seconds, not minutes.**

**Challenges:**

- 📐 ⚠ **200M connections at a 10 s interval = 20M ping/pong per second — tiny messages, fine, but worth saying.**
- ✅ **A guaranteed upper bound: 10 s interval + 5 s timeout ⇒ any dead connection found within 15 s.**

> ⚠ **What HI leaves loose.**
> 
> - ⚠ **Only the SERVER detects here. The client must also notice silence (no ping for > interval + timeout) and reconnect itself.**
> - ⚠ **Backgrounded mobile apps rely on the OS push service (APNs/FCM) — missing from the design.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 4) What happens if Redis fails to deliver a message?

⭐⭐ **Pub/Sub is at-most-once: no subscriber or a Redis blip ⇒ message lost. Durability is already handled (Inbox written first ⇒ everything is delivered EVENTUALLY). The question is how a CONNECTED client gets a dropped message quickly.**

#### Good — periodic polling

**What it is:**

- ⭐⭐ **Every 30–60 s the client sends a "sync"; the server checks its Inbox and sends anything undelivered.**

**Challenges:**

- 📐 ⚠⚠ **Load grows with connected users: 200M polling every 30 s ≈ 7M queries/s just for sync. Longer intervals cut load but add latency — a tunable knob, "good enough" for most cases.**

**Why climb:** ⭐ **detect a gap instead of checking blindly.**

#### Good — sequence numbers per chat

**What it is:**

- ⭐⭐ **Each message gets a monotonically increasing sequence number per chat (Redis `INCR`, atomic). The client tracks the last number seen; receiving #5 after #3 ⇒ it missed #4 ⇒ re-sync.**

**Challenges:**

- ⚠⚠ **Only detects a gap when a LATER message arrives. If the chat goes quiet after the lost one, nothing triggers — polling is still needed as a backstop.**

**Why climb:** ⭐ **use a signal that arrives even when chats are quiet.**

#### ⭐⭐⭐ Great — heartbeats carrying a per-user sequence

**What it is:**

- ⭐⭐⭐ **One incrementing counter per USER: every message to that user increments it.**
- ⭐⭐⭐ **Each heartbeat ping includes the user's current sequence number.**
- ⭐⭐ **If the client's local number is behind, it syncs immediately.**
- ✅ **Missed messages are caught within one heartbeat interval at almost no extra cost, and one sequence covers every chat.**

**Challenges:**

- ⚠ **An atomic counter per user adds coordination and another dependency (Redis `INCR`).**

⭐⭐ **In practice combine all three: heartbeats find dead sockets, sequence numbers find missed messages, polling is the final backstop.**

> ⚠⚠ **What HI leaves loose.**
> 
> - ⚠⚠ **The counters live in Redis, which replicates asynchronously: after a failover the counter can go BACKWARDS and hand out a number twice — a gap check then sees nothing.** ⊕ **Store the sequence with the message in DynamoDB (atomic counter update), or put an epoch in front of it that changes on failover.**
> - ⚠ **With multiple clients (DD2) the comparison must be per client: the server must know which sequence each client has seen.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 5) How do we handle out-of-order messages?

⭐⭐ **HI: we don't — not directly.** **Exact ordering needs delays (to wait for late messages) and a re-ordering step, as with Flink's bounded-out-of-orderness watermarks (Ad Click). Chat users would rather see new messages fast than in guaranteed order.**

- ⭐⭐⭐ **Chat Servers sync clocks with NTP (not perfect, good enough). Stamp each message with the time the server RECEIVED it; clients display messages ordered by that stamp. Every client sees the same order, even if messages arrived in a different order.**
- ⭐ **Sometimes a message pops in "above" one sent later. Users accept that.**

> ⚠ **What HI leaves loose.**
> 
> - ⚠⚠ **DD4 already gives a per-chat sequence number from one atomic counter — that IS a total order per chat, with no clock involved.** ⊕ **Display by sequence and the "pop-in" mostly disappears; HI never connects the two.**
> - ⚠ **Two Chat Servers with skewed clocks can stamp a reply BEFORE the message it answers.** ⊕ **Clamp: a message's stamp must exceed the newest stamp the sender had seen.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 6) How can we handle "last seen"?

⭐ **"Show when the other person was last online" — efficiently and at scale.**

#### ⚠ Bad — update `lastSeen` on every action

**What it is:**

- ⭐ **Write a timestamp to the database every time the user sends, receives, or answers a heartbeat.**

**Challenges:**

- ⚠⚠ **Massive write amplification: 200M connected users with heartbeats every 10–30 s ⇒ millions of writes per second for low-value data. Even DynamoDB would struggle, and it costs a fortune.**
- ⚠ **The value is stale the moment it's written — we pay for consistency we don't need.**

**Why climb:** ⭐ **write only on rare events, and ask online users directly.**

#### ⭐⭐⭐ Great — record disconnects, ask live servers (HI's pick)

**What it is — two insights:**

- ⭐⭐ **We KNOW when a user connects and disconnects (or when we close a dead connection).**
- ⭐⭐ **If the user is online, their server can say so.**

**Design:**

- ⭐⭐ **A `LastSeen` table in DynamoDB: one row per user holding the last disconnect time, updated on each disconnect. A conditional write (only if the new time is later) stops two servers overwriting a newer value.**
- ⭐ **New commands: `getLastSeen { targetUserId, requestingUserId }` and `updateLastSeen { targetUserId, reporter: DATABASE|SERVER, lastSeen: ONLINE|$DATE }`.**

**Flow:**

- ① **The client sends `getLastSeen`.**
- ② **The Chat Server, in parallel: (a) reads `LastSeen` and publishes `updateLastSeen` to the requester's channel; (b) forwards `getLastSeen` to the target's channel.**
- ③ **If the target's server has the user connected, it publishes `updateLastSeen` = ONLINE to the requester.**
- ④ **The client merges: ONLINE ⇒ green bubble; otherwise show the last disconnect time.**
- ✅ **One record per user; durable writes only on disconnect.**

**Challenges:**

- ⚠ **The two answers can arrive at different times for an online user — wait a moment, or update the UI smoothly.**
- ⚠ **Relies on Chat Servers reporting disconnects; a crashed server reports nothing. Users reconnect quickly anyway; to be safer, also write on connect.**

> ⚠ **What HI leaves loose.**
> 
> - ⚠⚠ **`requestingUserId` comes from the client — spoofable.** ⊕ **Take it from the authenticated connection.**
> - ⚠ **A server crash leaves `LastSeen` stuck at an OLD disconnect, so an offline user looks "last seen hours ago" while they were online until the crash.** ⊕ **Writing on connect too (HI's fix) bounds the error.**
> 
> ■ **— end of insert · HI write-up resumes below —**

---

## 6 · Final Design

⚠ **The paste has no final-design section; this is assembled from the deep dives. Layout is mine.**

```
Client (≤3 per user) ══ WebSocket over TLS ══► L4 LB ──► Chat Server × ~100–200 (1–2M conns each)
   ▲  ⭐⭐ ACK every newMessage / chatUpdate                │  in-memory map: userId → socket
   │  ⭐⭐ ping every 10–30 s, pong ≤ 5 s (+ user seq)      │
   │                                                       │ ① write Message + Inbox rows (durable)
   │  media: pre-signed upload ──► blob store             │ ② ACK sender   ③ publish (best-effort)
   │                                                       ▼
   │                                    DynamoDB: Chat · ChatParticipant (+ GSI by participant)
   │                                              Message · Inbox (per client) · Clients · LastSeen
   │                                                       │
   └──────────── forward ◄── Chat Server ◄── Redis Pub/Sub (sharded by userId; chat channels for > 25 members)
                                                           Redis INCR: per-user sequence

Backstops: heartbeat seq check ⇒ sync · periodic poll (30–60 s) · Inbox sync on reconnect
⊕ I added: clientMessageId (dedupe) · atomic/outbox Inbox writes · delete Message after last ACK ·
           sharded pub/sub (SPUBLISH) · per-chat sequence for ordering · client deactivation
```

---

## 7 · Expected at Each Level

|Level|The bar for WhatsApp|
|---|---|
|**Mid-level**|**80/20 breadth. A clearly defined API and a working high-level design that meets the requirements; expect probing on basics (what a WebSocket does, how it works). The scaling answer can have rough edges, as long as you know its flaws. The interviewer may drive the later stages.**|
|**Senior**|**60/40. Speed through the HLD and spend time on scaling and robustness. Consistent hashing is essential here; understand long-running sockets. Argue trade-offs such as partitioning pub/sub by chat or by user, and their effect on scalability and maintainability.**|
|**Staff+**|**40/60, from experience. Go 2–3 levels deep on failure modes and bottlenecks; plenty to discuss on fault tolerance, database optimisation, regionalisation and cell-based architecture. The interviewer only focuses, never steers.**|

> ⚠ **Senior bar: "consistent hashing is essential", yet HI's pick is Redis Pub/Sub. Read it as: know consistent hashing well enough to argue why you didn't pick it (full mesh, rebalancing).**
> 
> ■ **— end of insert · HI write-up resumes below —**

---

## Quick Recall (pass 3+)

|Use / Question|WhatsApp answer|
|---|---|
|Calibration|**Stefan Mai · Feb 2026 · ⭐⭐ "medium" · Asked at +24 · ⭐⭐ pattern `03a` Real-time Updates.** ⭐⭐⭐ **TWO passes. Order DD1 > §4.3 > DD4 > DD3 > DD2 > DD6 > DD5**|
|⭐⭐⭐ Design driver|⭐⭐⭐ **Persistent connections over hundreds of servers, a delivery guarantee, recipients often offline.** **Two-way, frequent ⇒ WebSocket · offline 30 days ⇒ Inbox + ACK · different servers ⇒ consistent hashing or Pub/Sub · many devices ⇒ per-client inbox · silent sockets ⇒ ACK timeout + heartbeats · pub/sub drops ⇒ sequence + polling · media ⇒ separate HTTP path**|
|📐 Numbers|**200M active × 20/day = 4B/day ≈ 40k/s (⊕ 46k) ⇒ ~100k writes/s with Inbox and groups · 1B users ⇒ 200M connected ÷ 1–2M per host ⇒ 100–200 servers · Kafka 50 KB × 1B = 50 TB · heartbeats 20M/s, detect ≤ 15 s · polling ~7M/s · limits 100 per chat, 30 days, 3 clients, ACK timeout 500–2000 ms**|
|FRs / NFRs|**Group chats (≤100) · send/receive · receive while offline (30 days) · media.** Below: calls, businesses, registration/profile. **NFRs: ⭐⭐ <500 ms to online users · ⭐⭐⭐ guaranteed delivery · ⭐⭐ billions of users · ⭐⭐ stored no longer than necessary · ⭐⭐ resilient to component failure.** Below: exhaustive security, spam/scraping|
|Entities + API|**Users · Chats (2–100) · Messages · Clients.** ⭐⭐⭐ **WebSocket over TLS; commands sent: `createChat`, `sendMessage`, `createAttachment`, `modifyChatParticipants`; received: `newMessage`, `chatUpdate` — each ACKed ("RECEIVED"), so the server knows delivery happened.** ⚠⚠ **No `clientMessageId` (retries duplicate) and no `messageId` in `newMessage` (redeliveries can't be deduped)**|
|⭐⭐ §4.1 — create chat|**Chat Server behind an L4 LB (no L7 features needed; faster) → DynamoDB. `Chat` keyed by id; `ChatParticipant` PK chatId + SK participantId, GSI participantId → chatId. One transaction up to 100 items, else batch.** ⚠ **Batching loses atomicity ⇒ write Chat last; GSI is eventually consistent**|
|⭐⭐ §4.2 — send (one server)|**Single node first (HI: reason there before scaling). Map userId → socket; look up members; push to each socket. Assumes all online on one server**|
|⭐⭐⭐ §4.3 — offline + Inbox|⭐⭐⭐ **Send: members ⇒ write Message + Inbox per recipient ⇒ return SUCCESS + id ⇒ push `newMessage` ⇒ client ACK ⇒ delete Inbox row. Reconnect: read Inbox ⇒ fetch Messages ⇒ push ⇒ ACK ⇒ delete. TTL cleans old rows.** ⚠⚠ **Multi-row write not atomic ⇒ transaction (100 items) or outbox; ~300 rows after DD2. ⚠⚠ Message kept 30 days after delivery ⇒ delete after last ACK (NFR 4)**|
|⭐⭐ §4.4 — media|**Bandwidth- and storage-heavy ⇒ a separate HTTP upload service (as WhatsApp does).** ⚠⚠ **Bad: over the WebSocket into the DB (DBs hate blobs; eats Chat Server bandwidth).** ⭐⭐ **Good: Chat Server forwards to blob storage, 30-day TTL, pre-signed GET; ⚠ wasted hop.** ⭐⭐⭐ **Great: `getAttachmentTarget` ⇒ pre-signed upload straight to storage; send the URL in the message. CDN adds little at ≤ 100. ⚠ No delete-after-all-downloaded ⇒ ⊕ pending-recipient count; E2E key inside the message**|
|⭐⭐⭐ DD1 — routing ladder|⚠⚠ **LB only: the server lacks recipients' sockets.** ⚠ **Kafka topic per user: ~50 KB each ⇒ 50 TB for 1B; super-topics reinvent the rest.** ⭐⭐ **Consistent hashing + etcd/ZooKeeper registry: direct server-to-server; ⚠ full mesh (few, big servers), rebalancing without a thundering herd, double-send during moves.** ⭐⭐⭐ **Redis Pub/Sub per user: subscribe on connect; write durably ⇒ ACK sender ⇒ publish best-effort; ⚠ a few ms, Chat Server ↔ Redis connections. Canva: 100k msgs/s at 27% on one host**|
|⭐⭐ DD1 — by chat or user?|⭐⭐ **Mostly 1:1 and capped at 100 ⇒ per user. Celebrity case: chats above ~25 members get a chat channel too; publish to both while switching.** ⚠⚠ **Classic Redis Cluster broadcasts `PUBLISH` to all nodes ⇒ ⊕ sharded pub/sub (`SPUBLISH`) or client-side sharding.** ⚠ **Pub/sub has no memory (ChatGPT DD2). "SUCCESS" means stored, not delivered**|
|⭐⭐ DD2 — many devices|**Clients table; participants ⇒ clients; Inbox per client (`recipientClientId`); send to every client; Pub/Sub unchanged (by userId); cap 3 per account.** ⚠⚠ **Deactivation has no mechanism ⇒ ⊕ `lastActiveAt`, expire after N days.** ⚠ **×3 Inbox rows; each server delivers only to its own sockets; new devices get no history**|
|⭐⭐ DD3 — dead sockets|⚠ **Do nothing: TCP keepalive takes minutes.** ⭐⭐ **ACK timeout (500–2000 ms) ⇒ retry ⇒ close and force reconnect; ⚠ only while sending.** ⭐⭐⭐ **Heartbeats: ping 10–30 s, pong ≤ 5 s, else close; detect ≤ 15 s; 📐 20M/s at 200M and 10 s.** ⚠ **Client must also watch for silence; mobile needs APNs/FCM when backgrounded**|
|⭐⭐⭐ DD4 — Pub/Sub drops|**Durability is already covered by the Inbox; the goal is fast recovery for connected clients.** ⭐⭐ **Polling every 30–60 s (~7M/s; a latency-vs-load knob).** ⭐⭐ **Per-chat sequence via Redis `INCR`: see #5 after #3 ⇒ resync; ⚠ quiet chats hide the gap.** ⭐⭐⭐ **Per-user sequence in every heartbeat ⇒ behind ⇒ sync; caught within one interval. Combine all three.** ⚠⚠ **Redis failover can rewind a counter ⇒ store it durably or add an epoch; per-client tracking needed**|
|⭐⭐ DD5 — ordering|**Don't enforce order (would need waits and re-ordering, like Flink watermarks). NTP-synced servers stamp the RECEIVE time; clients sort by it; same order everywhere; occasional pop-in is acceptable.** ⚠⚠ **DD4's per-chat sequence already gives a total order — use it.** ⚠ **Clock skew can put a reply before its question ⇒ clamp**|
|⭐⭐ DD6 — last seen|⚠ **Write on every action/heartbeat ⇒ millions of writes/s, stale anyway.** ⭐⭐⭐ **Write `LastSeen` only on disconnect (conditional: only if later). `getLastSeen` ⇒ in parallel read the table AND ask the target's channel; an online target's server replies ONLINE; the client merges (green bubble or last disconnect).** ⚠ **Answers arrive at different times; a crashed server never reports ⇒ write on connect too. ⚠⚠ `requestingUserId` must come from auth, not the client**|
|⭐⭐⭐ The meta-lesson|⭐⭐⭐ **Four ideas outlive this problem: (1) write durably first, then push best-effort — the store backs up every lost push; (2) only an end-to-end ACK proves delivery, and at-least-once means the client dedupes; (3) silence needs an active probe, and sequence numbers turn "missed?" into a comparison; (4) write state on rare events (disconnect), not on every heartbeat**|
|Levels (one line)|**Mid (80/20):** clear API, working HLD, scaling with known flaws · **Senior (60/40):** fast HLD, scaling and robustness, consistent hashing, long-lived sockets, chat-vs-user partitioning · **Staff+ (40/60):** 2–3 levels deep on failures; regions, cells, DB optimisation|

---

> 🔗 **HI source:** https://www.hellointerview.com/learn/system-design/problem-breakdowns/whatsapp