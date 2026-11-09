# Video Sharing Platform (YouTube) — Problem Breakdown

> 📐 **Revision note (calc):** ⚠ **HI does no arithmetic in this write-up — there is no capacity math to re-derive. Don't invent any.** The given figures: **~1M videos uploaded/day · 100M watched/day · videos 10s of GBs · 5–10MB upload chunks · ~365M metadata records/year.** ⭐⭐ **The one number worth deriving yourself: 100M ÷ 1M = a 100:1 read:write ratio** — that single ratio justifies the CDN, the metadata cache and the whole `03d` framing. ⭐ **And HI's one worked figure, worth keeping:** **a 10GB video on 100 Mbps takes 13+ minutes to download** — ▸ **that's what kills download-then-play.**

> Hello Interview · Question Breakdowns · File `05o`. **Evan King**, published **Jul 10, 2024** · ⭐ **"medium"** · ⭐ **asked at Amazon (+4 more, not named in the source)** · has a video walkthrough. ⭐⭐ **TWO Pattern callouts: `Handling Large Blobs` → `03f` and `Scaling Reads` → `03d`.** ⚠⚠ **HI opens by telling you to read Dropbox first** — _"There's some conceptual overlap between this question and designing Dropbox… I'd recommend reading that guide first."_ Cross-refs: ⭐⭐ **presigned URL + multipart + chunk fingerprints → `05b` Dropbox (HI defers to it twice and gives only a TL;DR)** · **blob store + CDN → `01a`** · **Cassandra → `02e`** · **partitioning → `01f`** · **consistent hashing → `01g`** · **LRU cache → `01e`** · ⭐ **hot key → replicate → `05g`** · **CAP → `01h`** · **DAG / long-running work → `03g`** · **API design → `01b`** · **API Gateway → `02d`** · **numbers → `01i`.** **Siblings: `05b` Dropbox (the parent problem) · `05k` Strava (client as active participant) · `05g` FB News Feed (the hot-key dive) · `05e` Ticketmaster (HI cites its shard-by-concertId reasoning as the contrast).**
> 
> **Calibration:** ⚠ **"Medium" is right on reasoning, wrong on risk.** ▸ **Conceptually this is Dropbox plus a transcoding pipeline. But it's the most VOCABULARY-heavy problem in the series** — codec, container, bitrate, manifest, ABR, transcode — ⭐⭐ **and vocabulary is the one thing you cannot derive in the room.** ⭐ **So: one pass on the design, plus a separate 10-minute drill on §4.0's table.** ▹ **Reassurance from HI: mid-level candidates are explicitly NOT expected to know video internals.**
> 
> - ⭐⭐ **What actually scores:**
>     - **(a)** ⭐⭐ **The two ladders are COUPLED** (§4.1 ↔ §4.2) — **you store segments in many formats because ABR needs them.** ▸ **Every upload decision is justified by a streaming requirement. Say that link out loud; it's the structure of the whole answer.**
>     - **(b)** ⭐⭐ **Manifest files — primary → media → segments.** ▸ **An index of an index. This is the single most-probed new concept here.**
>     - **(c)** ⭐⭐ **Post-processing as a DAG**, and ⭐ **why transcoding is the parallel part — no dependencies between segments.**
>     - **(d)** ⭐ **Presigned URL + multipart upload direct to S3** (`05b`) — **the server never touches video bytes.**
>     - **(e)** ⭐ **The ABR client loop, five steps** (§4.2 Great).
>     - **(f)** ⭐⭐ **CDN for segments, cache for metadata — two DIFFERENT hot problems.** ⚠ **Candidates conflate them.**
>     - **(g)** ⭐ **Codec vs container, stated precisely** — **a one-line answer that signals you did the reading.**
> - ⭐ **Transferable primitives:**
>     - ⭐⭐ **Produce at write time exactly the artifact the read path needs.** ▸ **Segments + manifests exist only to serve streaming.** ⭐ **Same thread as `05c` (`avgRating`), `05f`/`05g` (feeds): precompute on the rare write, keep the frequent read trivial.**
>     - ⭐⭐ **An index file turns a blob into a random-access resource.** ▸ **The manifest is what makes a video seekable and adaptive. Reusable for any large artifact you can't load whole.**
>     - ⭐⭐ **Work units with no dependencies between them are embarrassingly parallel** ⇒ **split, fan out to workers, fan in.** ▸ **Reusable for any batch pipeline.**
>     - ⭐ **Pass references, not payloads, between workers** — **S3 URLs, not files.**
>     - ⭐ **Let the client decide when only the client knows.** ▸ **Only the device knows its bandwidth and screen, so the client picks the format.** ⭐ **Same move as `05k` Strava.**
>     - ⭐ **If your only access pattern is a point lookup, shard on that key and stop thinking about it.**
> - ⭐ **Re-run (cross-ref, NOT re-explained):** ⭐⭐ **presigned URLs, multipart upload, chunk fingerprints, resumable-upload tracking — ALL of it is `05b` Dropbox, and HI says so explicitly** · **CDN + blob store (`01a`)** · **Cassandra partition keys (`02e`, `01f`)** · **hot key ⇒ replicate, not shard (`05g`)** · **LRU cache (`01e`)** · **client as active participant (`05k`)** · **availability > consistency (`01h`)**. **Genuinely new:** ⭐⭐ **codec vs container** · **bitrate** · ⭐⭐ **manifest files (primary + media)** · ⭐⭐ **adaptive bitrate streaming** · ⭐⭐ **the post-processing DAG + an orchestrator (Temporal)** · ⭐ **transcoding as the CPU-bound parallel step** · ⭐ **S3 as inter-worker scratch space** · **S3 part number + ETag** · **`ObjectCreated:CompleteMultipartUpload` fires exactly once per object.**

---

## 0 · Understanding the problem

📹 **What is [YouTube](https://www.youtube.com/)?**

A video-sharing platform to **upload, view and interact with video content.** ▹ **HI: _"the second most visited website in the world 🤯."_**

---

## 1 · Requirements

### 1.1 Functional (what it does)

1. ⭐ **Users can upload videos.**
2. ⭐ **Users can watch (stream) videos.**

⚠ **Below the line:** view counts · search · comments · recommendations · channels · subscriptions.

▹ ⭐ **Only two FRs — unusual, and deliberate.** ▸ **HI: the question is _"mostly focused [on the] video-sharing aspects."_** ⭐ **For a feature-rich product, ask the interviewer which part they care about.**

### 1.2 Non-functional (how it behaves)

1. ⭐ **Highly available — availability over consistency** (`01h`).
2. ⭐⭐ **Upload and stream large videos — 10s of GBs.**
3. ⭐⭐ **Low-latency streaming, even in low-bandwidth environments.** ▸ **This is what forces ABR.**
4. ⭐ **Scale — ~1M uploaded/day, 100M watched/day.**
5. ⭐ **Resumable uploads.**

⚠ **Below the line:** bad-content protection · bots/fake accounts · monitoring & alerting.

- ⭐⭐ **HI's framing, and it's the reason to pin the NFRs down carefully here:** with only two FRs, the NFRs _"characterize the complexity of these deceptively simple 'upload' and 'watch' interactions."_

### 1.3 ⭐⭐ The design driver — two systems joined by S3, and the first exists to serve the second

|Path|Volume|Needs|Therefore|
|---|---|---|---|
|**Upload**|⭐ **1M/day — rare**|**10s of GBs · resumable · CPU-bound post-processing**|⭐ **presigned URL + multipart to S3, then a DAG** (§4.1, §5.1, §5.2)|
|**Watch**|⭐⭐ **100M/day — 100:1**|**low latency on variable bandwidth**|⭐ **segments + manifests + ABR + CDN** (§4.2, §5.3)|

- ⭐⭐ **The coupling is the whole insight: the upload path's job is to produce exactly the artifacts the watch path needs.** ▸ **Segments exist because ABR needs them. Multiple formats exist because devices and bandwidths differ. Manifests exist because the client must choose per segment.**
- ⚠ **So don't present §4.1's ladder as a storage question.** ⭐ **Each rung is rejected for a STREAMING reason** — HI even says so mid-ladder: _"As we will see later, downloading 'part' of a video is really important."_
- ▹ **The server never touches video bytes.** ⭐ **Client → S3 on upload, CDN → client on watch. The backend only moves metadata and orchestrates work.**

### 1.4 Planning the approach

▸ **Sequentially through the FRs, then let the NFRs drive the deep dives.** ▹ Same step as `05e`/`05i`/`05k`.

---

## 2 · Core Entities

- **User** — uploader or viewer.
- **Video** — the thing uploaded / watched.
- ⭐ **VideoMetadata** — the uploading user, URL references, transcript reference, etc. ▸ **This is the only entity the database actually holds; Video lives in S3.**

---

## 3 · API

### 3.1 The naive pair (both get replaced)

```
POST /upload              { Video, VideoMetadata }
GET  /videos/{videoId} ->  Video & VideoMetadata
```

> ⭐⭐ **Say this out loud before you write them — it buys you permission to change them later:**
> 
> _"I am going to outline some simple APIs, but may come back and improve them as we delve deeper into the design."_
> 
> ■ **— end of insert —**

### 3.2 What they become

```
POST  /presigned_url            { VideoMetadata }  -> presigned S3 URL
      ⭐ payload is metadata ONLY — the video goes straight to S3

GET   /videos/{videoId}      -> VideoMetadata
      ⭐ returns metadata only; it CONTAINS the manifest URL

PATCH /videos/{id}/chunks       { partNumber, eTag }   (§5.2)
```

- ⭐⭐ **Both endpoints shrink to metadata because bytes bypass the server entirely.** ▸ **Name that as the reason, not as an implementation detail.**

---

## 4 · High-Level Design

### 4.0 ⭐⭐ Video background — the vocabulary drill

▹ ⭐ **HI: you don't need to be an expert, but you need these four terms.** ⭐⭐ **This table is the part of the file to memorise.**

|Term|What it is|The distinction that matters|
|---|---|---|
|⭐⭐ **Codec**|**"encoder/decoder" — compresses and decompresses video**|⭐ **Trades off: compression time · platform support · compression efficiency · lossy or not.** ▸ **H.264, H.265 (HEVC), VP9, AV1, MPEG-2, MPEG-4**|
|⭐⭐ **Container**|**the FILE FORMAT holding frames, audio and metadata** (can hold transcripts too)|⭐⭐ **Codec = HOW it's compressed. Container = HOW it's stored.** ⚠ **Support varies by device/OS.** ▹ **"format" below = container + codec**|
|⭐ **Bitrate**|**bits transmitted per unit time (kbps / Mbps)**|▸ **Higher resolution + higher FPS ⇒ much higher bitrate — literally more data.** ⭐ **Better codecs lower it for the same quality**|
|⭐⭐ **Manifest files**|**text documents indexing the available streams**|⭐⭐ **TWO kinds — see below**|

**⭐⭐ Manifest structure — draw this, it's the core new concept:**

```
PRIMARY manifest  (the "root" — lists every available version)
   ├── MEDIA manifest: 1080p / h264  →  seg1 · seg2 · seg3 · …
   ├── MEDIA manifest:  720p / h264  →  seg1 · seg2 · seg3 · …
   └── MEDIA manifest:  480p /  vp9  →  seg1 · seg2 · seg3 · …

⭐ Each segment is a few seconds long and independently playable.
⭐ The media manifest IS the index the player uses to stream.
```

### 4.1) Users can upload videos

▸ **Three questions to answer out loud:**

1. **Where do we store the video metadata (name, description, etc.)?**
2. **Where do we store the video data (frames, audio, etc.)?**
3. ⭐⭐ **What do we store for video data?** ▸ **The third is the one with a ladder.**

#### ⭐ Metadata — Cassandra, partitioned by `videoId`

- **1M/day ⇒ ~365M records/year** ⇒ **needs horizontal partitioning** (`02e`, `01f`).
- ⭐⭐ **Partition on `videoId`, and the reason is the whole justification:** **the only access pattern is a point lookup of one video.** ▸ **No bulk access, so no careful partition design needed.**
- ⭐ **Cassandra also gives high availability**, which matches NFR #1.

> ⭐⭐ **HI's three-way framing of partitioning — worth reusing in any problem.**
> 
> |Kind of system|What it needs|Example|
> |---|---|---|
> |**Read from few nodes**|⭐ **careful partitioning**|anything with range or bulk queries|
> |**Consistency in a scope**|⭐ **relational + ACID, sharded by that scope**|⚠ **`05e` Ticketmaster — shard by concertId to keep ticket purchases consistent**|
> |**Point look-ups only**|⭐⭐ **shard on the lookup key and stop thinking**|**this problem — `videoId`**|
> 
> ■ **— end of insert · HI write-up resumes below —**

#### ⭐ Video data — presigned URL + multipart, direct to S3

- ⚠⚠ **This is all `05b` Dropbox and HI gives only the TL;DR.** ▸ **_"it's most efficient to upload data directly to a blob store like S3 via a presigned URL with multi-part upload."_** ⭐ **Read `05b` for the analysis; don't re-derive it here.**
- ⭐⭐ **The API consequence:** `POST /upload` becomes `POST /presigned_url`. **Payload = metadata only.**

> ⭐ **Pattern: Handling Large Blobs** (`03f`) — **callout #1 of 2.** ▹ **Multi-GB files bypass app servers via presigned URLs, resumable chunked transfer, CDN distribution. Same pattern for photo storage, document sharing, backups.**
> 
> ■ **— end of insert · HI write-up resumes below —**

#### ⚠⚠ The ladder: what exactly do we store?

⚠ **Rung labels are mine — see the handover note.**

**⚠ Bad — store the raw uploaded file, no post-processing**

- ⚠ **Challenge:** ⭐ **different devices require different formats to play back.** ▸ **Non-starter.**

**Why climb:** one file can't play everywhere.

**Good — transcode into multiple formats, store each as a whole file**

- **Approach:** **S3 fires an event notification to a Video Processing Service** on upload ⇒ **it converts the original into different formats**, **stores each as a file in S3**, and **writes the format URLs back onto the metadata record.**
- ⚠ **Challenge:** ⭐⭐ **whole files can't be partially downloaded.** ▸ **_"As we will see later, downloading 'part' of a video is really important for streaming."_**

**Why climb:** streaming needs pieces, not files.

**⭐⭐ Great — split into segments FIRST, then transcode each segment**

- ⭐ **Approach:** **split into small independently-playable segments (a few seconds each)**, then **convert each segment into the different formats.**
- ✅ ⭐ **HI: _"strictly better"_** — it's what makes efficient streaming possible at all.
- ⚠ **Challenges:**
    - ⭐⭐ **The post-processor becomes a PIPELINE** — split, then generate formats per segment.
    - ⭐ **You must store references to all those segments sanely** and use them downstream. ▸ **→ §5.1.**

### 4.2) Users can watch videos

- ⭐⭐ **`GET /videos/{videoId}` returns VideoMetadata only** — **because that record holds the URL(s) needed to watch.**

**⚠ Bad — download the whole video, then play**

- ⚠ **Not streaming at all.** **Challenges:**
    - 📐 ⭐⭐ **A 10GB video on 100 Mbps = 13+ minutes before playback starts.** ⚠ **Unacceptable.**
    - ⭐ **One HTTP request means a network disruption loses all progress.**

**Why climb:** playback must start in seconds, and a drop must not cost you everything.

**Good — download segments incrementally**

- **Approach:** ⭐ **the client picks a format from device + bandwidth + user preference**, **loads the first segment (a few seconds), starts playing**, and **loads more in the background.**
- ⚠ **Challenge:** ⭐⭐ **the format is chosen ONCE.** ▸ **Network degrades mid-video ⇒ 1080p segments arrive slowly ⇒ buffering.**

> ▹ ⭐⭐ **Why HI insists this is NOT just "chunked download" — a precision point worth making.**
> 
> - ⚠ **Chunking a file by bytes (5MB at a time) only yields playable output for SOME formats** — it depends on how the container orders data.
> - ⭐ **Splitting into playable SEGMENTS is explicit and format-independent.** ▸ **And it's the rung that leads directly to ABR.**
> 
> ■ **— end of insert · HI write-up resumes below —**

**Why climb:** bandwidth changes mid-video, so the format choice must too.

**⭐⭐ Great — adaptive bitrate streaming (ABR)**

⭐ **Depends on two upstream decisions: segments stored in multiple formats, AND a manifest file created at upload time.**

**⭐⭐ The client loop — five steps, know them in order:**

1. **Fetch `VideoMetadata`** → it holds the **manifest URL in S3.**
2. **Download the manifest.**
3. ⭐ **Choose a format from network conditions / user settings**, get that segment's URL from the manifest, **download segment 1.**
4. **Play it, keep downloading ahead.**
5. ⭐⭐ **On network change, switch format mid-stream** — **degrading ⇒ fetch more-compressed, lower-resolution segments to avoid interruption.** ▸ **Improving ⇒ switch back up.**

- ⚠ **Challenge HI names, and it's a positive:** ⭐⭐ **the client becomes _"a more active participant in the system (which isn't a bad thing)."_** ▹ ⭐ **Direct echo of `05k` Strava — same principle, different job: there the client WROTE, here the client DECIDES.**

---

## 5 · Deep Dives

### 1) ⭐⭐ How do we process a video to support ABR?

**⭐ The pipeline's output — state these two first:**

1. **Segment files in different formats** (container + codec combinations) **in S3.**
2. ⭐⭐ **Manifest files — one primary plus several media manifests — in S3**, the media ones **referencing the segment files.**

**⭐⭐ The four steps, in order:**

1. ⭐ **Split the original into segments** (ffmpeg or similar).
2. ⭐⭐ **Transcode each segment** + **process audio and generate transcripts.**
3. ⭐⭐ **Create the manifest files** referencing every segment in every format.
4. **Mark the upload "complete".**

> ⚠ **Confusion resolved — is it ONE manifest listing every resolution, or several?**
> 
> - ⭐⭐ **Several. One master + one media manifest PER quality** — ⚠ **not a single file.**
> - ⭐ **Segments are grouped per quality too:** **4 resolutions ⇒ 4 parallel groups of segments**, each group covering the whole video.
> 
> ```
> master manifest
>   → 1080p media manifest → seg_001 · seg_002 · seg_003 …
>   →  720p media manifest → seg_001 · seg_002 · seg_003 …
>   →  480p media manifest → seg_001 · seg_002 · seg_003 …
> ```
> 
> - ⭐⭐ **Player: read master → pick a quality → download that quality's segments in order → switch media manifest when the network changes.**
> - ▹ **HI says "primary", HLS says "master" — same file.**
> 
> ■ **— end of insert · HI write-up resumes below (the DAG) —**

**⭐⭐ Why it's a DAG, and this is the scoring part:**

- ▸ **Each step fans out / fans in based on dependencies, and the dependencies run one way** ⇒ **a directed acyclic graph** (`03g`).
- ⭐⭐ **Segment processing parallelises because there are NO dependencies between segments once split.** ▸ **Transcode, audio and transcription for segment 7 need nothing from segment 6.**
- ⭐⭐ **Transcoding is the most expensive step — CPU-bound codec conversion** ⇒ **do it with extreme parallelism across many machines and cores.**
- ⭐ **Orchestration: assume an existing engine.** ▸ **HI names [Temporal](https://temporal.io/blog/media-processing-workflows), which supports media-processing workflows.** ⭐ **Say "I'd use a workflow orchestrator" rather than building one.**
- ⭐⭐ **Any temporary data the pipeline produces — segments, audio files, etc. — goes to S3, so workers never pass files between themselves. They pass URLs referencing those files.** ▸ **The reusable rule: pass references between workers, never payloads.**

▹ ⭐ **HI's depth calibration:** don't draw a full DAG with exact transcoding steps. ⭐ **Do nail the explicit INPUTS and OUTPUTS, and the parallelism.**

> ⭐ **HI's own noted simplification — worth raising as your own optimisation.**
> 
> - ▸ **This design uploads the full original BEFORE processing starts.** ⭐ **Some services start earlier: the client segments on upload, so downstream work begins before the upload finishes.**
> - ⭐ **Offer it as a pipelining improvement** — ⚠ **cost: the client joins the processing path, and a half-finished upload leaves "garbage" segments.**
> 
> ■ **— end of insert · HI write-up resumes below —**

> ⊕ ⚠⚠ **(mine, not HI) — two holes in this dive, and both are fair game for an interviewer.**
> 
> **1. ⚠⚠ Nothing bounds storage, and this is the biggest omission in the write-up.** ▸ **You now keep the original (10s of GBs) PLUS every segment in every format.** ⭐⭐ **Storage is a multiple of the upload, and HI never says whether originals are retained, nor mentions tiering.** ▹ ⭐ **`05k` Strava tiers hot → warm → cold for far less data.** ⭐ **Say: _"I'd archive originals to Glacier once processing completes and keep only the derived segments hot — the original is only needed to re-transcode for a new codec."_** ▸ **That sentence is cheap and shows you thought past the pipeline.**
> 
> **2. ⚠ HI calls transcoding "the most expensive computation" and never costs it.** ▸ **Compare `05i` LeetCode, where HI did the CPU math for exactly this shape of problem.** ⭐ **Volunteer the SHAPE, not a fake number:** _"transcode cost scales with duration × number of formats; with segments it's embarrassingly parallel, so the constraint is total core-minutes, not wall-clock per video."_ ⚠ **Don't invent a per-segment time — HI gives none.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 2) How do we support resumable uploads?

⚠⚠ **This is `05b` Dropbox's large-file dive. HI gives a TL;DR and defers.** ▸ **Note it tracks the ORIGINAL upload, not the segments.**

1. ⭐ **Client splits the file into chunks, each with a fingerprint hash — ~5–10MB each.**
2. ⭐ **`VideoMetadata` gets a `chunks` field: a list of `{ fingerprint, status }`.**
3. **Client POSTs the chunk list, all `NotUploaded`.**
4. **Client uploads each chunk to S3.**
5. ⭐⭐ **S3 returns a part number + ETag per part. The client relays it (`PATCH /videos/{id}/chunks`), and the SERVER verifies fingerprint/ETag against S3 before marking `Uploaded`.** ▸ ⭐ **The server verifying is the point — never trust a client's claim that a write landed.**
6. ⭐ **On `CompleteMultipartUpload`, S3 emits ONE object-level event** (`ObjectCreated:CompleteMultipartUpload`) — ⚠ **exactly once per object, not per part.** ▸ **That single event kicks off §5.1's pipeline.**
7. ⭐⭐ **To resume: fetch `VideoMetadata`, skip the chunks already `Uploaded`.**

- ▹ ⭐ **HI: in practice [AWS multipart upload](https://docs.aws.amazon.com/AmazonS3/latest/userguide/mpuoverview.html) handles all of this** — **but walk the details anyway, that's where the depth shows.**

> ⊕ ⚠⚠ **(mine, not HI) — the chunk-tracking table is largely redundant, and the diagram contradicts the prose.**
> 
> **1. ⚠⚠ S3 already knows which parts landed.** ▸ **`ListParts` on an in-progress multipart upload returns every uploaded part with its ETag.** ⭐⭐ **So on resume you can ask S3 directly instead of maintaining a parallel `chunks` list** — which is exactly why HI's closing line admits _"the above, in practice, is handled by AWS multipart upload."_
> 
> - ⭐ **When your own tracking IS justified: cross-device resume, a progress bar for other clients, or if the `uploadId` could be lost.** ▸ **Say that distinction — it's the difference between parroting the design and understanding it.**
> 
> **2. ⚠⚠ A 10GB file at 5MB chunks is 2,000 chunk entries in ONE Cassandra row**, PATCHed continuously throughout the upload. ▸ ⭐ **A single growing, write-hot partition with constant updates is the one thing Cassandra handles worst** (tombstones, compaction pressure). ⭐⭐ **Second reason to let S3 own it.**
> 
> **3. ⚠ The diagram contradicts the prose.** ▸ **HI's diagram shows `S3 event notification → Upload Monitor (Lambda) → Store chunk data`, but the prose says chunk tracking _"remains client-driven"_ and that S3 fires only ONE object-level event.** ⭐ **There is no per-part event for a Lambda to consume. The prose is the corrected version — go with it.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 3) ⭐ How do we scale to 1M uploads / 100M watches per day?

⭐⭐ **Walk the components one by one — that's the method, and it's reusable.**

|Component|How it scales|⚠ The bottleneck HI names|
|---|---|---|
|**Video Service**|⭐ **stateless ⇒ horizontal behind a load balancer.** Only serves presigned URLs and metadata point queries|—|
|**Video Metadata (Cassandra)**|⭐ **leaderless replication + internal consistent hashing** (`01g`); **uniform distribution via `videoId`**|⚠⚠ **a node holding a POPULAR video goes hot**|
|**Video Processing Service**|⭐ **distributes DAG work across workers**; ⭐⭐ **an internal queue absorbs upload bursts**, and ⭐ **queue depth is the autoscaling trigger**|—|
|**S3**|**scales to high traffic and file volume.** ⚠ **A bucket lives in ONE region** (auto-replicated across AZs)|⚠⚠ **far from many viewers ⇒ slow initial load and buffering**|

**⭐⭐ The two fixes, and keep them separate — they solve different problems:**

|Problem|Fix|
|---|---|
|⭐ **Hot METADATA** (one popular video's row)|⭐⭐ **Replicate that data to several Cassandra nodes so more than one can serve it** + ⭐ **a distributed LRU cache partitioned on `videoId`** (`01e`)|
|⭐⭐ **Distant VIEWERS** (segment bytes travelling too far)|⭐⭐ **CDN caching popular segments AND manifest files at edge servers** (`01a`)|

- ⭐⭐ **The payoff line for the CDN, and it's the strongest sentence in this dive:** **with manifests and segments both in the CDN, _"the service would never need to interact with the backend at all to continue streaming a video."_**

> ⭐ **Pattern: Scaling Reads** (`03d`) — **callout #2 of 2.** ▹ **Popular videos create read hotspots ⇒ metadata caching, CDN for content, read replicas.** ⭐⭐ **HI's framing: _"The read-to-write ratio is extreme — viral videos might be watched millions of times but uploaded only once."_**
> 
> ■ **— end of insert · HI write-up resumes below —**

> ⊕ ⭐ **(mine) — get the hot-key framing right; candidates conflate the two.**
> 
> - ⭐⭐ **`05g`'s rule applies cleanly: too much DATA for one node ⇒ shard. Too much TRAFFIC for one key ⇒ replicate.** ▸ **A hot video is one key, so sharding cannot help it — HI's "replicate to a few nodes" is the correct move for exactly that reason.**
> - ⚠ **But note the asymmetry: hot metadata is the CHEAP problem** (a row of text, trivially cacheable). ⭐ **Hot SEGMENTS are the expensive one, and the CDN — not Cassandra — is what solves them.** ▸ **Keep the two answers in separate sentences.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### ▹ Additional dives HI flags but doesn't develop

- ⭐ **Speeding up uploads** — pipeline upload and post-processing (§5.1's insert).
- **Resume watching where the user left off** — more per-user-per-video data.
- ⚠ **View counts** — _"can easily be a dedicated deep-dive on its own."_ ▹ **Out of scope here, but know it's the usual follow-up.**

---

## 6 · Final Design

⚠ **Layout and arrows are mine; components, labels and field lists are HI's** — see the handover note.

```
Client  ⭐ an active PARTICIPANT: picks the format, adapts mid-stream
  │
  │  POST  /presigned_url  { VideoMetadata }
  │  PATCH /videos/:id/chunks  { partNumber, eTag }
  │  GET   /videos/:videoId -> VideoMetadata (holds the manifest URL)
  ▼
API Gateway & Load Balancer  — routing · auth · rate limiting          02d
  │
  ▼
Video Service  ⭐ stateless, horizontally scaled
  │              only presigned URLs + metadata point queries
  │
  ├──► Video Metadata DB (Cassandra)                            02e · 01f
  │      ⭐ partition: videoId  (point look-ups only)
  │      ⭐ leaderless replication + consistent hashing            01g
  │      ⚠ popular video ⇒ HOT node ⇒ replicate wider              05g
  │        VideoMetadata: videoId · uploaderId · name
  │                       description · chunks · S3 URLs
  │
  └──► Video Metadata Cache  ⭐ distributed · LRU · by videoId      01e
                                insulates the DB for popular videos

Client ──────► S3  ⭐ DIRECT upload via presigned URL (multipart)  03f · 05b
                │     the server never touches video bytes
                │
                │  Stores: DAG temp files · video segments · manifest files
                │
                ├─ S3 event: ObjectCreated:CompleteMultipartUpload
                │     ⚠ fires exactly ONCE per object, not per part
                │     ⊕ the diagram's per-chunk "Upload Monitor (Lambda)"
                │       contradicts HI's prose — chunk tracking is
                │       client-driven, or better: just call ListParts
                ▼
         Video Processing Service  ⭐⭐ a DAG, orchestrated (Temporal)  03g
                │
                Video Splitter
                     ├──► Transcoding ┐  ⭐⭐ parallel — NO dependencies
                     ├──► Transcoding ├─   between segments
                     ├──► Transcoding ┘    ⭐ the CPU-bound step
                     ├──► Audio Processing
                     └──► Transcript Generation
                              │
                              ▼
                     Build + store manifest files
                              │
                              ▼
                     Mark video upload "done"
                     ⭐ writes manifest S3 URLs onto VideoMetadata
                     ⊕ archive the ORIGINAL to cold storage here —
                       HI never bounds this                        01a

CDN  ◄── caches popular manifest files + segments at the edge      01a · 03d
  │        ⭐⭐ with both cached, streaming never touches the backend
  ▼
Client  — adaptive bitrate streaming:
           manifest → pick format → segment 1 → play → prefetch
           → re-pick format as bandwidth changes
```

---

## 7 · Expected at Each Level

|Level|The bar for YouTube|
|---|---|
|**Mid**|**API endpoints + data model defined; a functional HLD for upload and playback.** ⚠ ⭐ **In-depth video-streaming knowledge NOT expected** — but must **converge on multipart upload and segment-based streaming**, and ⭐ **understand the need to interface with S3 directly.** **Drive clarity on one deep dive.**|
|**Senior**|⭐ **Quickly through the HLD**, then detail on **video post-processing and upload mechanics.** ⭐⭐ **Must know multipart upload and how it gives resumability**, and ⭐⭐ **how a video is post-processed efficiently to enable adaptive streaming.**|
|**Staff+**|**Depth on every topic above**; ⭐ **may steer toward something they find interesting**; ⭐⭐ **solid grasp of trade-offs, articulated treating the interviewer as a peer.**|

---

## Quick Recall (pass 3+)

|Use / Question|YouTube answer|
|---|---|
|Calibration|⭐ Evan King · **Jul 2024** · **"medium"** · ⭐ **asked at Amazon (+4 unnamed)** · ⭐⭐ **TWO patterns: `Handling Large Blobs` (`03f`) + `Scaling Reads` (`03d`).** ⚠⚠ **HI says read `05b` Dropbox FIRST and defers to it twice.** ⚠ **Most vocabulary-heavy problem in the series — and vocabulary can't be derived in the room.** ⭐ **One design pass + a separate drill on §4.0**|
|⭐⭐ Design driver|⭐⭐ **Two systems joined by S3, and the first exists to serve the second.** **Upload: 1M/day, 10s of GBs, resumable, CPU-bound. Watch: 100M/day (⭐ 100:1), low latency on variable bandwidth.** ⭐⭐ **Segments exist because ABR needs them; formats because devices differ; manifests because the client must choose per segment.** ▸ **Every upload decision is justified by a streaming requirement.** ⭐ **And the server never touches video bytes**|
|FRs / NFRs|**Upload · watch.** Below: view counts · search · comments · recommendations · channels · subs. **NFRs: availability > consistency · 10s-of-GB videos · low latency even on low bandwidth · 1M up / 100M watched per day · resumable uploads.** Below: bad content · bots · monitoring. ⭐ **Only 2 FRs, so the NFRs _"characterize the complexity"_ — pin them down**|
|📐 Numbers|⚠ **HI does NO arithmetic — don't invent any.** Given: **1M up/day · 100M watched/day · 10s of GBs · 5–10MB chunks · ~365M records/yr.** ⭐⭐ **Derive yourself: 100:1 read:write** — justifies CDN + cache + `03d`. ⭐ **HI's one figure: 10GB on 100 Mbps = 13+ min** ⇒ **kills download-then-play**|
|Entities|**User · Video · VideoMetadata.** ⭐ **Only VideoMetadata is in the DB — Video lives in S3**|
|API|`POST /upload` → ⭐ **`POST /presigned_url` { VideoMetadata }** · `GET /videos/{id}` → ⭐ **returns VideoMetadata ONLY, which holds the manifest URL** · `PATCH /videos/:id/chunks { partNumber, eTag }`. ⭐⭐ **Both shrink to metadata because bytes bypass the server.** ⭐ **Say up front: _"I may come back and improve these as we go"_**|
|⭐⭐ Codec vs Container|⭐⭐ **Codec = HOW it's compressed** (encoder/decoder) — **trades compression time · platform support · efficiency · lossy-or-not.** H.264, H.265/HEVC, VP9, AV1, MPEG-2/4. ⭐⭐ **Container = HOW it's STORED** (frames + audio + metadata, maybe transcripts); **support varies by device/OS.** ▹ **"format" = container + codec**|
|⭐ Bitrate|**bits per unit time (kbps/Mbps).** ▸ **higher resolution + FPS ⇒ much higher bitrate, literally more data.** ⭐ **better codecs lower it at the same quality**|
|⭐⭐ Manifest files|⭐⭐ **PRIMARY = the root, lists every available version → points to MEDIA manifests, one per format → each lists that format's segment links.** ⭐ **The media manifest IS the player's index.** ⭐ **Segments are a few seconds, independently playable.** ▸ **An index of an index — this is what makes a blob random-access**|
|⭐ Metadata store|⭐ **Cassandra, partition `videoId`** (`02e`) — **1M/day ⇒ 365M rows/yr ⇒ needs horizontal partitioning**, and **Cassandra gives the availability NFR.** ⭐⭐ **The justification: the ONLY access pattern is a point lookup, so no careful partitioning is needed**|
|⭐⭐ HI's 3-way partitioning frame|**(1) range/bulk queries ⇒ careful partitioning (2) consistency in a scope ⇒ relational + ACID sharded by that scope (⚠ `05e` shards by concertId for ticket consistency) (3) ⭐⭐ point lookups only ⇒ shard on the lookup key and stop thinking.** ▸ **This problem is (3)**|
|⭐ Upload mechanics|⚠⚠ **all `05b` Dropbox, HI gives only a TL;DR: presigned URL + multipart, direct to S3** (`03f`). ⭐ **API consequence: `POST /upload` → `POST /presigned_url`, payload = metadata only**|
|⚠ Upload Bad — store raw|⚠ **non-starter: different devices need different formats**|
|Upload Good — transcode whole files|**S3 event → Video Processing Service → converts to N formats → stores each as a file → writes format URLs to metadata.** ⚠ **Whole files can't be PARTIALLY downloaded** — ⭐ _"downloading 'part' of a video is really important for streaming"_|
|⭐⭐ Upload Great — segment THEN transcode|⭐ **split into small independently-playable segments first, then convert each segment to each format.** ✅ HI: _"strictly better."_ ⚠ **cost: the post-processor becomes a PIPELINE, and you must track all those segment references sanely ⇒ §5.1**|
|⚠ Watch Bad — download then play|📐 ⭐⭐ **10GB on 100 Mbps = 13+ min before playback.** ⚠ **and one HTTP request ⇒ a disruption loses all progress**|
|Watch Good — incremental segments|**client picks a format from device + bandwidth + preference, loads segment 1 (seconds), plays, prefetches.** ⚠⚠ **format chosen ONCE ⇒ network degrades ⇒ buffering.** ▹ ⭐ **NOT the same as byte-chunking: chunking only yields playable output for some containers; segments are explicit and format-independent**|
|⭐⭐ Watch Great — ABR|⭐ **Needs segments-in-many-formats AND a manifest built at upload.** **5 steps: (1) GET metadata → manifest URL (2) download manifest (3) pick format from network/settings, get that segment URL, download segment 1 (4) play + prefetch (5)** ⭐⭐ **on network change, switch format mid-stream — worse ⇒ more compressed / lower res to avoid interruption.** ⭐ **HI frames the "cost" as a positive: _"the client being a more active participant… which isn't a bad thing"_** ▹ **echo of `05k`: there the client WROTE, here it DECIDES**|
|⭐⭐ DD1 — the DAG|**Outputs: (1) segment files per format in S3 (2) a primary + several media manifests in S3.** **Steps: split (ffmpeg) → transcode each segment + audio + transcripts → build manifests → mark complete.** ⭐⭐ **It's a DAG because one-way dependencies with fan-out/fan-in.** ⭐⭐ **Parallel because segments have NO dependencies on each other once split.** ⭐ **Transcoding is the expensive CPU-bound step ⇒ extreme parallelism.** ⭐ **Orchestrator: assume one (Temporal).** ⭐⭐ **Temp data in S3 — pass URLs between workers, never files.** ▹ **HI: don't draw the full DAG; DO nail inputs, outputs and the parallelism**|
|⭐ DD1 — HI's own simplification|**this design uploads the FULL original before processing.** ⭐ **Offer pipelining: client segments on upload so downstream work starts early.** ⚠ **cost: client joins the processing path + a half-finished upload leaves garbage segments**|
|⊕⚠⚠ DD1 — two holes|**(1)** ⚠⚠ **NOTHING bounds storage — the biggest omission in the write-up.** ▸ **you keep the original (10s of GBs) PLUS every segment in every format, and HI never says if originals are retained or mentions tiering** (⭐ **`05k` tiers for far less data**). ⭐ **Say: _"archive originals to Glacier after processing; keep only derived segments hot — the original is only needed to re-transcode for a new codec."_** **(2)** ⚠ **transcoding is called "the most expensive computation" and never costed** (contrast `05i`, where HI did the CPU math). ⭐ **Volunteer the SHAPE: cost scales with duration × formats; with segments it's embarrassingly parallel, so the constraint is total core-minutes, not wall-clock per video.** ⚠ **don't invent a per-segment time**|
|DD2 — resumable uploads|⚠⚠ **`05b`'s dive; tracks the ORIGINAL upload, not segments.** **client splits into 5–10MB fingerprinted chunks → `VideoMetadata.chunks` = `{fingerprint, status}` list, all `NotUploaded` → upload each → ⭐⭐ S3 returns part number + ETag, client relays via `PATCH /videos/:id/chunks`, SERVER verifies against S3 before marking `Uploaded` → ⭐ `CompleteMultipartUpload` emits ONE object-level event (⚠ once per object, NOT per part) which kicks off the pipeline → ⭐⭐ resume = fetch metadata, skip uploaded chunks.** ⭐ **The server verifying is the point — never trust a client's claim a write landed.** ▹ **HI: AWS multipart does all this, but walk it anyway**|
|⊕⚠⚠ DD2 — it's largely redundant|**(1)** ⚠⚠ **S3's `ListParts` already returns every uploaded part + ETag ⇒ ask S3 on resume instead of keeping a parallel list** — ⭐ **which is why HI admits _"in practice, handled by AWS multipart upload."_** ⭐ **Own tracking IS justified for cross-device resume, a progress bar for other clients, or a lost `uploadId` — say that distinction.** **(2)** ⚠⚠ **10GB ÷ 5MB = 2,000 chunk entries in ONE Cassandra row, PATCHed throughout the upload** ⇒ ⭐ **a growing write-hot partition is what Cassandra handles worst** (tombstones, compaction). **(3)** ⚠ **the diagram's per-chunk `Upload Monitor (Lambda)` contradicts the prose** — **there is no per-part event; prose says chunk tracking is client-driven. Go with the prose**|
|⭐ DD3 — walk the components|**Video Service: stateless ⇒ horizontal. Cassandra: leaderless replication + consistent hashing (`01g`), uniform via `videoId` — ⚠⚠ but a popular video makes a node HOT. Processing Service: distributes DAG work; ⭐⭐ an internal queue absorbs bursts and queue depth triggers autoscaling. S3: scales well but ⚠ a bucket is ONE region ⇒ distant viewers get slow loads**|
|⭐⭐ DD3 — two DIFFERENT hot problems|⚠ **candidates conflate these.** **Hot METADATA ⇒ ⭐⭐ replicate the row to several Cassandra nodes + a distributed LRU cache on `videoId`** (`01e`). **Distant VIEWERS / hot SEGMENTS ⇒ ⭐⭐ CDN at the edge caching segments AND manifests** (`01a`). ⭐⭐ **The payoff: with both cached, _"the service would never need to interact with the backend at all to continue streaming a video."_** ⊕ ⭐ **`05g`'s rule: too much DATA for one node ⇒ shard; too much TRAFFIC for one key ⇒ replicate — a hot video is ONE key, so sharding can't help it.** ⚠ **and note the asymmetry: hot metadata is the cheap problem; hot segments are the expensive one**|
|▹ Dives HI flags, doesn't develop|⭐ **speeding up uploads (pipelining) · resume-where-you-left-off (more per-user-per-video data) · ⚠ view counts — _"can easily be a dedicated deep-dive on its own"_**|
|Levels (short)|**Mid:** API + data model + functional upload/playback HLD; ⚠ **video internals NOT expected**, but ⭐ **must converge on multipart upload + segment-based streaming** and **know to hit S3 directly**; drive one deep dive · **Senior:** fast HLD, then **post-processing + upload mechanics in detail**; ⭐⭐ **multipart ⇒ resumability**, and ⭐⭐ **how post-processing enables adaptive streaming** · **Staff+:** depth on all of it, **may steer**, ⭐⭐ **trade-offs articulated treating the interviewer as a peer**|

---

> 🔗 **HI source:** https://www.hellointerview.com/learn/system-design/problem-breakdowns/youtube
> 
> ⚠ **Source complete in substance. Three paste artifacts, nothing filled in from my own knowledge:**
> 
> 1. ⚠ **Rung labels are missing.** HI renders the two ladders as tabbed cards; the paste carries every `Approach` / `Challenges` body but no tab titles. **The labels in §4.1 ("store raw", "transcode whole files", "segment then transcode") and §4.2 ("download then play", "incremental segments", "adaptive bitrate streaming") are mine, derived from the body text.** The content under each is HI's.
> 2. ⚠ **Diagram text is flattened** — HI's diagrams arrived as loose lines. **§6's layout and arrows are my reconstruction**; components, labels, field lists and the DAG step names are HI's. ▹ **Check it against the source page.**
> 3. ▹ **The `+4` additional companies under "Asked at" are not named in the source** (only Amazon is).
> 
> ✅ **Reconciled against the original:** both FRs and all 5 NFRs with both below-the-line lists · the planning step · entities · both naive endpoints and all three evolved ones · the full video-streaming background (codec, container, bitrate, manifest types) · §4.1's metadata/Cassandra reasoning and HI's three-way partitioning aside · both three-rung ladders with every challenge listed, including HI's "why segments aren't chunking" aside · both Pattern callouts · DD1's outputs, four steps, DAG reasoning, orchestrator note and the early-processing simplification · DD2's seven steps · DD3's four-component walkthrough and both fixes · the three undeveloped dives HI flags · the final design · all three level bars. **No content gaps.**