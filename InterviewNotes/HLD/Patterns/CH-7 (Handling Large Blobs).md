# Handling Large Blobs

> Hello Interview · **Patterns** · File `03f`. Overview → `03 §6`. Object storage / CDN → `02 §10`; queues + events (SNS/SQS) → `02 §6`; Kafka → `02 §7`; API design → `01b`; numbers / bandwidth math → `01i`; real-time progress push → `03a`; long-running processing after upload → `03g`. **Calibration:** ⭐⭐ **Medium — recognition-heavy, not hard.** The pattern is almost mechanical once you see the trigger: **file > 10MB → don't proxy it through your servers.** The _depth_ interviewers probe is in **state synchronization** (DB metadata vs blob reality) — that's where candidates stumble, so that's where your notes should be densest. For your targets: **KYC / identity documents, invoices & statements, receipt uploads, chat media, profile photos.** ⭐ **Fintech twist:** the _"when NOT to use"_ compliance case (scan/inspect bytes before storing) is a **real Razorpay/CRED-class concern**, not a footnote — call it out. ▸ **The one governing insight:** **stop being a dumb pipe.** Your server's job shifts from _moving bytes_ → **(1) issuing scoped, time-limited credentials** (presigned URLs) so the client talks to storage directly, and **(2) reconciling state** (DB metadata row vs what's actually in the blob store). Bytes flow client↔storage/CDN; your server only handles _permission_ and _truth_. ⚠ **Don't reach for this on small files.** Under ~10MB, the two-step presign dance adds latency + complexity for nothing — use a normal API endpoint.

---

## 1. The Problem

▸ **CRUX** — large files belong in **blob storage (S3/GCS/Azure), not the database.** But that only solves _storage_; it doesn't solve _transfer_. The naive transfer path **routes every byte through your app servers** (client → API server → S3, and back) — which collapses as files grow.

### 1.1 Why blob storage (not the DB)

▸ Databases are built for **structured data + complex queries**; they're **terrible at large binary objects.**

- ⚠ A 100MB BLOB in a row **wrecks query performance, backup times, and replication.**
- ✅ Object stores are purpose-built: **unlimited capacity, 11 nines durability (99.999999999%), per-object pricing.**
- ▸ **Rule of thumb: > 10MB and doesn't need SQL queries → blob storage.** _(→ `02 §10`.)_

### 1.2 The "server as a proxy" bottleneck _(the thing to fix)_

▸ Routing file bytes through app servers makes them **dumb pipes** — they add **no value**, only **latency + cost.**

- ⚠ Cloud providers already have **global infra, resume capability, massive bandwidth.** Inserting your limited app servers as middlemen **manufactures a bottleneck where none needs to exist.**
- ▸ **The fix (spoiler):** client uploads **directly** to blob storage; downloads come from a **CDN**. Your servers **never touch the bytes.**

### 1.3 …but going direct creates NEW problems

▸ Removing your server from the byte path turns "moving files" into a **distributed-state problem:**

- ⚠ **Failed upload at 99%** (a 25GB upload dying near the end) means **starting over** — unless you add resumability.
- ⚠ **No progress visibility** — the transfer bypasses your servers, so you can't natively show a progress bar.
- ⚠ **State drift** — your DB says `pending` while S3 may already hold the complete file (or may not) — and **you can't tell without checking.** → eventual consistency, progress tracking, state sync.
- ▸ These new problems are exactly what the rest of the pattern solves.

---

## 2. The Solution

> ▸ The shift, in five parts: **2.1 serverless data access → 2.2 direct upload → 2.3 direct download → 2.4 resumable uploads → 2.5 state synchronization.** The first three are the happy path; the last two handle the _new_ problems (§1.3) that going direct created.

### 2.1 Serverless Data Access _(the core shift)_

▸ **CRUX** — instead of proxying data, hand clients **temporary, scoped credentials** to talk to storage directly. Your server's role becomes **access control**, not data transfer: **validate the request → generate credentials → get out of the way.**

- ▹ **Ticket-booth analogy:** you don't personally escort every ticket-holder to their seat — you **verify the ticket, hand them a wristband, let them find their own way.** Authorize once, then let the client interact with storage directly.
- ▸ All three providers support this: **temporary upload/download URLs**; CDNs can validate **signed tokens** before serving.

---

### 2.2 Direct Upload — Presigned URLs

#### 2.2a What a presigned URL is

▸ **CRUX** — client asks your server for **permission to upload**, not to receive the file. Server **validates the user, checks quotas, generates a temporary upload URL** encoding permission to upload **one specific file, to one specific location, for a limited time** (typically **15 min – 1 hr**). That's a **presigned URL.**

- ⭐ **Generated entirely in your app's memory — NO network call to blob storage.** Your server uses its cloud credentials to create a **signature** the storage service can verify later.
- ▹ **WHY it verifies:** the signature is a **crypto hash of request details** (HTTP method, resource path, expiry) + your **secret key.** On upload, the storage service **recomputes the same hash** with its copy of your credentials — **signatures match + not expired → upload proceeds.**
- ▸ Client then does a plain **HTTP PUT** to that URL with the file as the body. From their side they're uploading straight to storage; your infra never sees the bytes. ⭐ A Sydney user hits **Sydney's** storage region at full speed while your Virginia servers do other work.

#### 2.2b Restrictions baked into the signature _(the detail interviewers want)_

▸ **CRUX** — anyone with the URL can use it → **encode restrictions at generation time**, validated during upload:

- **`content-length-range`** — min/max size → stops someone uploading **10GB when you expect 10MB.**
- **`content-type`** — a profile-pic endpoint accepts **images only, not videos.**
- ⚠ These are **part of the signature** — a URL minted for a 5MB image is **rejected** if used for a 500MB video. _(Always set size limits, or a "small image" URL becomes a terabyte storage-bomb vector → DD2.)_

---

### 2.3 Direct Download — Signed URLs

#### 2.3a Blob storage vs CDN _(pick by access frequency)_

▸ Downloads mirror uploads: generate **signed URLs** granting **temporary read access** to specific files.

|Path|Cost|Best for|
|---|---|---|
|**Direct blob storage**|cheaper, simpler|**infrequent** downloads|
|**CDN (CloudFront etc.)**|costs more|**frequently accessed** files → geo-distribution + edge caching → single-digit-ms latency|

#### 2.3b Who validates the signature _(the distinction to name out loud)_

▸ **CRUX** — both use signatures, but **who checks them differs** — and that's the interview-worthy point:

- **Blob-storage signatures** (S3 presigned) → validated by the **storage service** using **your cloud credentials** (it holds your secret key).
- **CDN signatures** (CloudFront signed URLs/cookies) → validated by **CDN edge servers** via **public/private-key crypto.** You hold the **private key** and sign; the CDN holds the **public key** and validates **at edge locations worldwide** — **no callback** to your servers or origin storage.
- ▸ **Why it matters:** CDN validation happening at the edge (no origin round-trip) is _why_ CDN downloads are fast globally.

---

### 2.4 Resumable Uploads _(large files)_

▸ **CRUX** — a 5GB video at 100 Mbps ≈ **429 s (7 min 9 s)**; a drop at 99% shouldn't restart from zero. **Chunked upload APIs** solve this — split the file into parts, **resume only the failed parts.** _(Bandwidth math → `01i`.)_

#### 2.4a Chunked / multipart mechanics

- **AWS S3** — **Multipart Upload**: each **5MB+ part** gets its **own presigned URL.**
- **GCS** — **Resumable Uploads**: upload chunks with **range headers** to a **single session URL** (flexible chunk sizes).
- **Azure** — **Block Blobs** (4MB–100MB blocks).
- ▸ All let you **resume from failed chunks**; only the **URL structure** differs.
- ▸ **Resume flow:** client tracks **completion checksums** (cheap hashes) per part. Drop after 60/100 parts → client **queries the storage API** for which parts already landed (`ListParts` in S3, session status in GCS, committed blocks in Azure) → **resumes from part 61.** Storage tracks this via a **session ID** (upload ID in S3, resumable URL in GCS).
- ▹ Some teams persist the session ID in **localStorage** so uploads survive an **app restart.**

#### 2.4b Progress, completion & cleanup

- ✅ **Progress tracking falls out for free** — each completed part = a known % → client-side math → progress bar.
- ⚠ **Completion is a required final step** — after all parts upload, client calls a **completion endpoint** with the part numbers + checksums; storage then **assembles** them into the final object. **Until completion succeeds, you have parts but no accessible file.**
- ⭐ Once complete, the "chunks" **cease to exist** from storage's view — it's one object, as if uploaded in a single shot.
- ⚠ **Incomplete multipart uploads cost money** → set **lifecycle rules** to clean them up after **24–48 h.**

---

### 2.5 State Synchronization _(where candidates stumble — go deep)_

▸ **CRUX** — moving your server out of the byte path introduces **distributed state management.** Standard pattern: **file metadata in your DB · actual file in blob storage** → fast metadata queries + unlimited file storage. The hard part is **keeping them in sync**, because DB and blob store are **separate systems that update at different times.**

#### 2.5a The metadata table

▸ A Dropbox-style `files` row: `id · user_id · filename · size_bytes · content_type · storage_key · status · timestamps`.

- ▸ **`storage_key`** (e.g. `s3://bucket/user123/files/abc-123.pdf`) is the **join point** between DB and blob.
- ▸ **`status`** ∈ `pending · uploading · completed · failed` — tells you whether a file is **ready to download** or still in flight.

#### 2.5b Why "just trust the client" breaks

▸ Simplest approach: client uploads, then calls your API saying _"done!"_, you flip status to `completed`. ⚠ This breaks four ways:

- **Race condition** — DB shows `completed` **before** the file actually exists in storage.
- **Orphaned files** — client **crashes after upload but before notifying** → file in storage, no DB record.
- **Malicious clients** — users mark uploads complete **without uploading anything.**
- **Network failures** — the completion notification **never reaches** your servers.

#### 2.5c The fix — event notifications + reconciliation

▸ **CRUX — two layers: storage events as the primary signal, a reconciliation job as the safety net.**

- ✅ **Primary — storage event notifications:** when S3 receives the file, it **publishes an event** (via **SNS/SQS**) containing the **object key** — the **same `storage_key`** you stored when minting the presigned URL → you find the **exact row** to update. **The storage service itself confirms what exists → removes the client from the trust equation.** _(→ `02 §6`.)_
- ✅ **Safety net — reconciliation:** events can **fail** (network, outage, processing error) → a **periodic job** scans for rows **stuck in `pending`** and **verifies them against storage.**
- ▸ **Net:** events keep it fast + accurate; reconciliation catches stragglers. The small **status-update delay** is a fair price for **not proxying gigabytes** through your servers.

> ⚠ **Confusion resolved — "If I must virus-scan / content-check a 3GB (or 500GB) file, doesn't that force synchronous validation → proxy through my server → no direct upload?"** **No — and this is the trap.** _"Validation happens"_ is **not** the same as _"synchronous validation."_ The real axis is **WHAT gets gated:**
> 
> - **Synchronous validation gates the UPLOAD** — bytes may **not be stored at all** until inspected (reject-_before_-accept) → server **must** sit in the byte path (proxy). _(CSV header validation; compliance scan where card data legally can't land even briefly.)_
> - **Asynchronous validation gates the ACCESS** — the file **is** stored immediately via **direct-to-S3 upload**, but into a **private quarantine bucket the user can't read.** A background worker scans it _after_ upload; on pass, status → `available`. **The server never touched the bytes.** ▸ **DD2 (abuse prevention) is ASYNC — no contradiction.** Virus scan / image-recognition / 18+ checks all run **after** the direct upload, on the file already in quarantine. What's delayed is the **user's ability to see/share** it — **not** the upload. _Delayed access ≠ synchronous validation._
> 
> |Model|Byte path|When validated|Use when|
> |---|---|---|---|
> |Direct, no validation|client → S3|never|small/trusted, happy path|
> |⭐ **Direct + async (quarantine)**|client → S3 quarantine|_after_ upload (worker)|**default for user content** (photos/video, DD2). **Huge files fine.**|
> |Proxy + sync|client → **your server** → S3|_during_ upload, before accept|**must** reject-before-store: compliance (card/HIPAA), CSV headers|
> 
> ▸ **3GB / 500GB resolution:** if validation can be **async** (99% of cases incl. all abuse/content scanning) → **multipart direct upload** to quarantine, scan after → **size is irrelevant.** Only if validation **must** be sync (compliance forces reject-before-store) do you proxy — and _that's_ why the doc says **"still in chunks, of course"**: you **stream** it through your servers chunk-by-chunk (never buffer the whole file), inspecting as it flows. Slower + costlier → exactly why sync is the rare, reluctant exception under _"When NOT to use."_ ▸ **The deciding question:** _"Must this file be rejected BEFORE it's ever stored, or can it land first and be validated after?"_ Land-first → async quarantine (direct). Reject-before-store → sync proxy (stream in chunks).

> ⚠ **Confusion resolved — "What actually IS a quarantine bucket? Does the cloud scan the file and promote it for me, or do I write that?"** **A quarantine bucket is not a product — it's a ROLE you assign to an ordinary bucket:** (1) **private** (no public read, no CDN), and (2) the **only** place your presigned upload URLs point. The cloud doesn't "know" it's quarantine; you made it one by keeping it private and treating it as the landing zone. ⚠ **The cloud gives you plumbing, NOT the scanner.** You write the pipeline:
> 
> - **Event** (S3 `ObjectCreated` → SNS/SQS/Lambda) — plumbing ✅ cloud.
> - **Compute** (Lambda / ECS / worker) — plumbing ✅ cloud.
> - **The actual check** — **your code**, usually calling: **ClamAV** (virus, self-run), **Rekognition / Vision SafeSearch** (18+/content, managed API), magic-byte + size checks (plain code). Cloud never silently scans + promotes for you.
> 
> ```
> 1. Client → multipart PUT → QUARANTINE bucket   (direct; server never sees bytes)
> 2. S3 fires ObjectCreated event → SQS/Lambda
> 3. YOUR worker pulls the object key from the event
> 4. Worker fetches the FINISHED file, runs checks (ClamAV + Rekognition + type/size)
> 5a. PASS → COPY/MOVE to PUBLIC bucket + UPDATE Postgres 'pending' → 'available'
> 5b. FAIL → DELETE from quarantine (or reject bucket) + UPDATE status → 'rejected'
> ```
> 
> ▸ **Two corrections to the intuitive picture:**
> 
> - **Not chunks.** By the time the event fires, multipart upload is **already assembled into one object** (§2.4b). The worker fetches the **finished file**, not parts. Chunking was only about _transfer_; it's invisible afterward.
> - **Two actions, not one.** The worker does (1) the **physical file op** (copy quarantine→public / delete) **and** (2) the **metadata flip** (Postgres status). Not just the DB. ⚠ Flip status **after** the move succeeds — a public file with no `available` row (or vice-versa) is a consistency bug (same ordering discipline as offset-commit in `03e §4.1`). ▸ **Who runs the scan is your choice:** fully yours (ClamAV container) · managed API (Rekognition/Vision) · dedicated SaaS. In all three, **the orchestrating worker + the Postgres update is YOUR code.**

---

## Cloud Provider Terminology _(names differ; concept is identical — you rarely need exact SDK calls)_

|Feature|AWS|Google Cloud|Azure|
|---|---|---|---|
|Temporary upload URLs|**Presigned URLs** (PUT/POST)|**Signed URLs** (resumable/simple)|**SAS tokens** (Shared Access Signature)|
|Multipart uploads|**Multipart Upload** (5MB–5GB parts)|**Resumable Uploads** (flexible chunks)|**Block Blobs** (4MB–100MB blocks)|
|Event notifications|**S3 Event Notifications** (→ Lambda/SQS/SNS)|**Cloud Storage Pub/Sub** (→ Cloud Functions)|**Event Grid** (blob events)|
|CDN with signed URLs|**CloudFront** (signed URLs/cookies)|**Cloud CDN** (signed URLs)|**Azure CDN** (SAS tokens)|
|Cleanup policies|**Lifecycle Rules**|**Lifecycle Management**|**Lifecycle Management Policies**|

---

## When to use in interviews

▸ **The rule is simple — don't overthink it: moving files > 10MB through your API → reach for this pattern immediately.** 10MB is where the pain gets real (exact threshold depends on infra).

- **YouTube / video** — presigned S3 URL → client uploads direct (multipart for resumability) → S3 event triggers transcoding → CloudFront serves segments via signed URLs.
- **Instagram / photos** — presigned URLs for originals (50MB+ from modern cameras) → S3 events trigger async thumbnail/filter/metadata workers → feed served via CloudFront signed URLs (anti-hotlinking).
- **Dropbox / file sync** — presigned chunked uploads → direct to blob → sync workflows; shares = time-limited signed URLs (no account needed).
- **WhatsApp / chat media** — upload direct to storage; chat system only passes the **file reference**; recipients get **expiring** signed download URLs.

## When NOT to use _(know these cold — the "senior" answer)_

- ⚠ **Small files (< 10MB)** — JSON, form posts, small images → normal API endpoint. The two-step dance is pure overhead.
- ⚠ **Synchronous validation** — if you must **reject invalid data before accepting** (e.g. CSV import validating headers/types up front), you **must proxy** to see the bytes.
- ⭐ ⚠ **Compliance / data inspection** — regulatory frameworks that require data to **pass through certified systems or be scanned before storage** (financial services scanning for card numbers, HIPAA) → **proxy through your servers** (still chunked). **← the fintech-relevant exception for your targets.**
- ⚠ **Experience demands immediate response** — profile photo appearing instantly with face detection, live document preview → the async **upload→process→notify** round-trip is too slow for truly interactive UX.

---

## Common Deep Dives

▸ **DD1 — Upload fails at 99%**

- **▸ PROBLEM** — a huge upload dies near the end; restarting from scratch is unacceptable (mobile flaky connections, multi-hour uploads).
- **✅ SOLUTION — chunked uploads with resume.** For files > 10MB: **S3 multipart (5MB+ parts) · GCS resumable (any chunk) · Azure block blobs (4MB+).** Storage tracks which parts landed; on reconnect the client **queries** (`ListParts` / session status / committed blocks) and **resumes from the first missing part** — parts 1–19 done, part 20 failed → resume at 20.
- **▸ Requirement** — client tracks the **session identifier** (upload ID / resumable URL / block container URL); some teams stash it in **localStorage** to survive app restarts.
- **⚠ CAUTION** — incomplete uploads **cost money** (providers charge for stored parts) → **lifecycle policies** to clean up after **1–2 days.**

▸ **DD2 — How do you prevent abuse?**

- **▸ PROBLEM** — users uploading malicious content and immediately sharing the link, or exploding your storage costs.
- **✅ SOLUTION — quarantine-then-promote pipeline.** Uploads land in a **quarantine bucket** first → run **virus scans, content validation, file-type checks (a "photo" that's actually an executable), size checks (storage bombs)** → **only after checks pass**, move to the public bucket and set status `available`.
- **▸ WHY it's better** — far more robust than real-time abuse detection: even if someone bypasses rate-limiting, they **can't use** the content until systems approve it. The **processing delay also throttles abuse** (attackers can't instantly confirm success → automation is harder).
- **⚠ CAUTION** — **always** include **file-size limits** in the presigned URL conditions, or a URL meant for a small image can be used to upload **terabytes.**

▸ **DD3 — How do you handle metadata?**

- **▸ PROBLEM** — presigned URLs upload **raw bytes** to object storage; files still need metadata (uploader, purpose, processing instructions). How do you associate it?
- **✅ SOLUTION — metadata lives in your primary DB, keyed by `storage_key`.** When you **generate the presigned URL, create the DB record immediately with status `pending`** (including the storage key) → you have a **reference before the file exists.** When storage events fire, they carry that key → you find the exact row.
- **▸ Key-naming** — use a consistent, collision-proof pattern like `uploads/{user_id}/{timestamp}/{uuid}`. ⚠ **Never let clients specify their own keys** — invites overwrites + security holes.
- **⚠ CAUTION — don't stuff rich metadata into object tags.** S3 allows ~10 tags × 256 chars, but you **can't efficiently query** "all PDFs by user X last week" by scanning tags. Keep rich metadata **in the DB.** _(For metadata that must be atomic with the upload, presigned URLs can require specific headers — but that's extra complexity most cases don't need.)_

▸ **DD4 — How do you ensure downloads are fast?**

- **▸ PROBLEM** — three _separate_ problems get mashed together here; the fix is to split them. Each has its own cause and its own remedy.
- **① Distance (geography) → CDN.** A file in Virginia + a user in Sydney = **~200ms round-trip per request** before any bytes move. Fine for one big file; brutal for a page pulling **hundreds** of small assets. **CDN caches copies at edge servers near users:** the _first_ regional user pulls from origin (slow), everyone after gets the **local edge copy at ~5ms.** 200ms → 5ms × hundreds of requests = huge.
- **② Size + dropped connection → range requests.** CDN fixes distance, does **nothing** for size — a 5GB file still takes minutes, and a naive download **restarts from zero** on a wifi blip. **Range requests** = an HTTP feature letting the client ask for **only bytes X–Y** (`Range: bytes=0-10485759` = first 10MB) instead of the whole file. Client pulls byte-range pieces, tracks what it has, and on reconnect asks only for the **missing** pieces → **resumable download.** ⭐ **You don't build this** — browsers/download managers do it automatically, storage + CDN all support it; your **only** job is **don't block it** (don't restrict the HTTP verbs/headers in the signed URL). _(This is the download mirror of the resumable **upload** in §2.4 — same "chunk it so a drop doesn't cost everything," other direction.)_
- **③ Speed cap (per-connection throttling) → parallel chunks _(exotic, usually skip)_.** Some teams pull **4–6 byte-range chunks simultaneously** over separate connections + reassemble client-side → 3–4× faster by dodging per-connection caps. **⚠ Rarely worth it** — most users are limited by **total bandwidth**, not per-connection: 6 connections on a 50 Mbps pipe still total 50 Mbps. Reserve for multi-GB datasets / game assets where users have fat pipes but hit per-connection throttling _and_ complain.

|Problem|Symptom|Fix|Who builds it|
|---|---|---|---|
|**Distance**|Sydney→Virginia = ~200ms/request|**CDN** — edge copies near users|you (point downloads at CDN)|
|**Size**|5GB redownloads from 0 on a drop|**Range requests** — pull byte-ranges, resume missing|⭐ **automatic** — just don't block it in the signed URL|
|**Speed cap**|one connection throttled|**Parallel chunks** — 4–6 at once, reassemble|you — **but rarely worth it**|

- **▸ Pragmatic default (say this):** serve everything through a **CDN** with good cache headers, ensure **range requests work** for big files, let CDN + browser optimize. Reach for parallel downloads **only** for multi-GB files where users complain despite good connectivity.

---

## Quick Recall (pass 3+)

|Question|Answer|
|---|---|
|The one principle|**stop being a dumb pipe** — server issues **scoped credentials** + **reconciles state**; bytes flow client↔storage/CDN|
|Trigger|**file > 10MB → don't proxy through your servers**|
|Why blob not DB|DB wrecked by large BLOBs (queries/backups/replication); S3 = unlimited + **11 nines** + per-object pricing (`02 §10`)|
|Proxy problem|app servers = **dumb pipes** adding latency/cost → manufactured bottleneck|
|New problems from going direct|**failed-at-99% · no progress visibility · DB/blob state drift**|
|Presigned URL|temporary scoped upload permission (**15min–1hr**); **generated in app memory, no network call**; signature = hash(method+path+expiry+secret)|
|URL restrictions|**`content-length-range`** (size) + **`content-type`** — baked into signature; always set size limits (storage bombs)|
|Download paths|**direct blob** (cheap, infrequent) vs **CDN** (costlier, frequent → edge caching, single-digit ms)|
|Who validates signature|**blob** → storage service w/ your secret key · **CDN** → edge servers w/ **public/private key**, no origin callback|
|Resumable uploads|**S3 multipart (5MB+) · GCS resumable · Azure block blobs**; resume failed parts via session ID; ⚠ **completion endpoint required**; ⚠ lifecycle cleanup 24–48h|
|Progress bar|falls out of chunked upload (completed parts = %)|
|State sync pattern|**metadata in DB · file in blob**, joined by **`storage_key`**; status = pending/uploading/completed/failed|
|Trust-client breaks|**race · orphaned files · malicious marks · network fail**|
|State sync fix|**storage event notifications (SNS/SQS w/ object key) = primary** + **reconciliation job (scan `pending`) = safety net** (`02 §6`)|
|sync vs async validation|**sync gates the UPLOAD** (reject-before-store → **must proxy**) · **async gates the ACCESS** (store to quarantine → scan after → **direct upload, size irrelevant**)|
|DD2 = async, not sync|virus/content/18+ checks run **after** direct upload on quarantined file; delayed **access ≠** synchronous validation → no contradiction with direct-to-S3|
|deciding question|_"reject BEFORE stored, or land-first-validate-after?"_ → land-first = async quarantine · reject-before = sync proxy (stream in chunks)|
|quarantine bucket|**not a product — a private bucket** you point uploads at (no public read/CDN); cloud gives **event + compute + ML APIs**, **you write the scanning worker + Postgres flip**|
|scan pipeline|S3 event → your worker fetches **finished file** (not chunks) → ClamAV/Rekognition/type+size → **PASS: move to public + status `available` · FAIL: delete + `rejected`**; flip status **after** move (`03e §4.1` ordering)|
|When NOT|**<10MB · sync validation-before-accept · ⭐ compliance/scan-before-store (fintech!) · instant-response UX**|
|DD1 fail@99%|chunked resume; client tracks session ID (localStorage survives restart); lifecycle cleanup|
|DD2 abuse|**quarantine bucket → scan/validate → promote**; always size-limit the URL|
|DD3 metadata|DB row at presign time (status `pending`), keyed by `storage_key`; ⚠ never let clients pick keys; don't query via object tags|
|DD4 fast downloads|**3 separate problems**: distance → **CDN** (edge cache, 200ms→5ms) · size/drop → **range requests** (byte-ranges, resumable, automatic — just don't block it; download-mirror of §2.4) · speed cap → **parallel chunks** (rarely worth it, bandwidth-bound)|

---

> 🔗 **HI quick reference:** https://www.hellointerview.com/learn/system-design/patterns/large-blobs/quick-reference