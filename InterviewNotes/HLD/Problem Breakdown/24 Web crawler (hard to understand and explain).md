# Web Crawler — Problem Breakdown

> 📐 **Revision note (calc):** ⭐⭐⭐ **The most complete BOE chain in your set — it runs from a hardware spec all the way to a machine count, and you should be able to reproduce it.** **10B pages · 2MB avg page · 5-day deadline.** **A network-optimised instance (`c6in.32xlarge`, `c7gn.16xlarge`) does 200 Gbps** ⇒ **200 Gbps ÷ 8 ÷ 2MB = 12,500 pages/sec theoretical** ⇒ ⭐ **assume 30% real utilisation = 3,750 pages/sec** ⇒ **10B ÷ 3,750 = 2,666,667 sec ≈ 30.9 days on one machine** ⇒ ⭐⭐ **÷ 8 machines ≈ 3.9 days, under the 5-day bar.** **Other figures: 1 req/sec/domain · `Crawl-delay: 10` in HI's example · 5 retries then "offline" · max depth 15–20 · DNS was up to 70% of thread time (Mercator) · SQS visibility timeout 30s default, up to 12 HOURS · skip files over 10MB.**

> Hello Interview · Common Problems · File `05x`. **Evan King**, updated **Feb 15, 2026** · ⭐⭐ **"HARD" — third hard problem in a row** · ⭐⭐ **asked at ZoomInfo (+6) = 7 companies** · has a video walkthrough. ⚠ **NO Pattern callout — the first file in your set with none.** Cross-refs: ⭐⭐⭐ **`05p` Job Scheduler — SQS visibility timeout, `DelaySeconds`, `ApproximateReceiveCount`, DLQ. THE cross-ref; this file SHARPENS your confusion-resolved block there** · ⭐⭐ **`05u §5.3` + `05t §5.3` — the Redis lock with TTL and `SET NX`, reused here as a per-domain lock** · ⭐⭐ **`05u §5.4` — where KAFKA won; here SQS wins** · ⭐⭐ **`05o` YouTube — pipeline stages + S3 for intermediates** · ⭐ **`05r` News Aggregator — the scraping sibling** · **`02c` Kafka · `02a` Redis · `02f` DynamoDB · `01a` blob storage · `01e` caching · `01f` sharding · `03b` contention · `01i` numbers.**
> 
> **Calibration:** ⭐⭐⭐ **TWO passes, and this is the highest-value file since `05u`.** ▸ **Three dives, all three substantial, and they map one-to-one onto the three NFRs.** ⭐⭐⭐ **But read it once for the SYSTEM and once for HI's META-ADVICE — the advice in this write-up is the richest in your whole set, and some of it directly answers questions you have asked me.**
> 
> - ⭐⭐ **What actually scores:**
>     - **(a)** ⭐⭐⭐ **The full BOE chain — bandwidth ⇒ pages/sec ⇒ days ⇒ machine count** (DD3).
>     - **(b)** ⭐⭐⭐ **Pipelining the crawler into stages, and giving the SECOND reason, not just fault tolerance** (DD1).
>     - **(c)** ⭐⭐⭐ **Resolving "how do you hit 3,750/sec if you're limited to 1/sec per domain?"** ▸ **Interviewers ask this.**
>     - **(d)** ⭐⭐ **The per-domain LOCK, because `lastCrawlTime` alone races across crawlers** (DD2).
>     - **(e)** ⭐⭐ **Knowing DNS is a real bottleneck, and the round-robin-providers answer HI calls Staff-level.**
>     - **(f)** ⭐⭐ **Preferring the hash INDEX over the Bloom filter — ⚠ the famous answer is the wrong one here.**
>     - **(g)** ⭐ **Max depth for crawler traps, and knowing depth means HOPS not path segments.**
> - ⭐ **Transferable primitives:**
>     - ⭐⭐⭐ **Split the pipeline where EXPENSIVE+IRREVERSIBLE meets CHEAP+REVISABLE.** ▸ **Fetching costs bandwidth and politeness budget; parsing is free. Store the raw artefact so you can re-parse forever without re-fetching.**
>     - ⭐⭐⭐ **A per-key rate limit is not a global throughput limit.** ▸ **Slow to everyone, simultaneously, is still fast in aggregate.**
>     - ⭐⭐⭐ **Your NFRs ARE your deep-dive agenda.** ▸ **One dive per NFR, and you don't run out of things to say.**
>     - ⭐⭐⭐ **Never put a large payload in a queue — put an ID and keep the payload in blob storage.**
>     - ⭐⭐ **A timestamp column is not a lock.** ▸ **Two workers reading `lastCrawlTime` both see it stale. You need an atomic claim.**
>     - ⭐⭐ **Add JITTER wherever many workers wait on the same clock**, ▸ **or they all wake together and only one wins.**
>     - ⭐⭐ **Scaling goes LAST, because earlier dives create the bottlenecks you'd otherwise miss.**
>     - ⭐ **For a non-user-facing system, replace the API section with a System Interface + a Data Flow.**
> - ⭐ **Re-run (cross-ref, NOT re-explained):** ⭐⭐⭐ **SQS visibility timeout / DLQ / `ApproximateReceiveCount` (`05p`)** · ⭐⭐ **Redis `SET NX` + TTL as a lock (`05t §5.3`, `05u §5.3`)** · ⭐⭐ **in-memory timers are not timeouts (`05t §5.1`, `05u §5.3`)** · ⭐ **pass S3 URLs, not payloads (`05o §5.1`)** · **exponential backoff (`05p`, `05t`)** · **blob storage for large objects (`01a`, `05o`)**. **Genuinely new:** ⭐⭐⭐ **the bandwidth-to-machine-count chain** · ⭐⭐⭐ **robots.txt, `Crawl-delay`, politeness as an NFR** · ⭐⭐⭐ **`DelaySeconds` is for NEW messages only — in-flight needs `ChangeMessageVisibility`** · ⭐⭐⭐ **per-key vs aggregate throughput** · ⭐⭐ **jitter against synchronised retries** · ⭐⭐ **content-hash dedup, and the Bloom filter being overkill** · ⭐⭐ **DNS as the hidden bottleneck + multiple providers** · ⭐⭐ **crawler traps + max depth** · ⭐ **`HEAD` + `Content-Length` to skip big files** · ⭐ **the URL Scheduler for continual crawls.**

---

## 0 · Understanding the problem

🕸️ **What is a web crawler?** **A program that _"automatically traverses the web by downloading web pages and following links from one page to another."_** **Used to index the web for search engines, collect research data, or monitor sites for changes.**

> ⭐⭐⭐ **The scoping move that comes FIRST, and it changes the whole design — ask what the output is for.**
> 
> - ⭐⭐ **HI: _"a search engine would need to index the data and rank it (using PageRank or other algorithms), while a company like OpenAI would dump the raw text from the pages into a database to be used to train LLMs."_**
> - ⭐ **But either way: _"the interview is likely to focus on the crawling task—how can we efficiently crawl the web, extract the necessary data, and store it in a way that is easily accessible?"_**
> - ⭐⭐ **This write-up picks: extract text to train an LLM.** ▸ **Which is why there's no ranking, no index, no search — just fetch, extract, store.**
> 
> ■ **— end of insert · HI write-up resumes below —**

---

## 1 · Requirements

### 1.1 Functional (what it does)

1. ⭐ **Crawl the web starting from a given set of seed URLs.**
2. ⭐ **Extract text data from each web page and store the text for later processing.**

⚠ **Below the line (out of scope):**

- **The actual processing of the text data (e.g., training an LLM).**
- **Handling of non-text data (e.g., images, videos, etc.).**
- **Handling of dynamic content (e.g., JavaScript-rendered pages).**
- **Handling of authentication (e.g., login-required pages).**

> ⭐⭐ **And one honesty caveat worth saying out loud, because it sounds like a weakness and isn't:**
> 
> **_"It's not possible to scrape the entire internet. Instead, we are going to scrape the vast majority of the web. Many small sites exist in the dark corners of the internet that we will not be able to reach. It may be worth clarifying this with your interviewer, but it's a general assumption of web crawling that you can't reach every page on the web."_**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 1.2 Non-functional (how it behaves)

1. ⭐⭐ **Fault tolerance** — **_"to handle failures gracefully and resume crawling without losing progress."_**
2. ⭐⭐⭐ **Politeness** — **_"to adhere to robots.txt and not overload website servers inappropriately."_**
3. ⭐⭐ **Efficiency** — **_"to crawl the web in under 5 days."_**
4. ⭐⭐ **Scalability** — **_"to handle 10B pages."_**

⚠ **Below the line (out of scope):** **Security** (**_"to protect the system from malicious actors"_**) · **Cost** (**_"to operate the system within budget constraints"_**) · **Compliance** (**_"to adhere to legal requirements and privacy regulations"_**).

> ⭐⭐⭐ **THE most important paragraph in this file for you — read it twice.**
> 
> **_"This is why defining good non-functional requirements is so important -- especially for more senior candidates! So often I see candidates rush through the requirements and then look at me, the interviewer, wide eyed, unsure of what to do next after they have a simple design. If you've taken your time to define quality non-functional requirements, then you shouldn't run out of things to talk about until your system has met all functional and non-functional requirements, at which point, you've likely passed the interview!"_**
> 
> - ⭐⭐⭐ **Your NFRs ARE your deep-dive agenda.** ▸ **HI says it outright: _"we are going to go 1-by-1 through our non-functional requirements."_**
> - ⭐⭐⭐ **And this file is the cleanest proof in your whole set: DD1 = fault tolerance · DD2 = politeness · DD3 = scale + efficiency. Three NFRs, three dives, nothing else.**
> - ⭐⭐ **So the fix for "I ran out of things to say" is not more technology. It's better NFRs, earlier.**
> 
> ■ **— end of insert · HI write-up resumes below —**

> ⭐⭐⭐ **Two more sequencing rules, both contrarian.**
> 
> - ⭐⭐ **DELAY the math:** **_"I recommend delaying these calculations until they are necessary for solving a specific problem. This approach avoids unnecessary computations."_** ▸ ⭐ **Do it where it decides something, not as a ritual at the top.**
> - ⭐⭐⭐ **SCALING LAST, with a concrete reason:** **_"had scaling been our first deep dive we would have missed bottlenecks like the parser workers introduced in subsequent deep dives."_** ▸ ⭐⭐ **You can't size components you haven't invented yet.**
> - ▹ **But ASK for the numbers early — _"the scale will have a large impact on the database design and the overall architecture."_** ⇒ ⭐ **Numbers early, arithmetic late.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 1.3 ⭐⭐⭐ The design driver — go as fast as physics allows, while being deliberately slow to everyone

||⭐⭐ **Aggregate**|⭐⭐ **Per domain**|
|---|---|---|
|**Target**|**3,750 pages/sec across 8 machines**|⚠ **1 request/SECOND. And obey `Crawl-delay: 10`**|
|**Driven by**|**the 5-day deadline over 10B pages**|**politeness — an NFR, not an optimisation**|
|**Wants**|**max parallelism, max bandwidth**|**restraint, locks, deferral**|

- ⭐⭐⭐ **These look like a contradiction and aren't, and HI's resolution is the thing to be able to say:** **_"we're crawling MILLIONS of different domains in parallel. Each crawler maintains thousands of concurrent connections to different sites simultaneously, so while any single domain sees at most 1 request/second, the aggregate throughput across all domains is very high."_**
- ⭐⭐⭐ **The primitive: a per-key rate limit is not a global throughput limit.** ▸ **You are not going fast at anyone. You are going slow at everyone, at once.**
- ⭐⭐ **Second axis, and it decides where the pipeline splits: FETCHING is expensive and irreversible (bandwidth, politeness budget, the site may be gone tomorrow). PARSING is cheap and revisable.** ⇒ **Store the raw HTML, and you can re-parse forever without re-crawling.**

### 1.4 Planning the approach

⭐⭐ **Different from every other file in your set, and HI says why:** **_"Given this system isn't a user-facing system, we'll instead focus on the abstract interface it has with the outside world and break down the data flow before proceeding to the high-level design. This will give us a good high-level picture of how the pieces should fit together which we can use as scaffolding."_**

---

## 2 · System Interface + Data Flow

⚠⚠ **There is NO API section in this file — this replaces it.** ⭐⭐ **HI's rule: _"For data processing system design questions like this one, it helps to start by defining the system's interface. This includes clearly outline what data the system receives and what it outputs, establishing a clear boundary of the system's functionality."_**

**System Interface**

- **Input: seed URLs to start crawling from.**
- **Output: text data extracted from web pages.**

**Data Flow** — ⭐ **_"the sequential series of steps we'll cover in order to get from the inputs to our system to the outputs. Clarifying this flow early will help to align with our interviewer before the high-level design."_**

1. **Take a seed URL from the frontier and request the IP from DNS.**
2. **Fetch HTML from the external server using the IP.**
3. **Extract text data from the HTML.**
4. **Store the text data in a database.**
5. **Extract any linked URLs and add them to the list of URLs to crawl.**
6. **Repeat 1–5 until all URLs have been crawled.**

▹ ⭐ **HI's framing: _"Note that this is simple, we will improve upon as we go, but it's important to start simple and build up from there."_**

> ⭐⭐ **Worth stealing for any non-user-facing problem: System Interface (in/out) + numbered Data Flow, instead of REST endpoints.** ▸ **It gives the interviewer the same alignment an API would, and it's the actual scaffolding of the HLD.** ⭐ **Watch for this shape in pipeline, ETL, indexing and ingestion questions.**
> 
> ■ **— end of insert · HI write-up resumes below —**

---

## 3 · High-Level Design

⭐ **Just the data flow, drawn.**

```
Frontier Queue ──► Crawler ──DNS lookup──► DNS
  ▲                 - fetch webpage
  │                 - extract text        ──fetch HTML──► Webpage (external)
  │                 - extract urls
  │                      │
  └──put extracted ──────┴──► S3 Text Data
     URLs back
```

**The five components:**

- ⭐ **Frontier Queue** — **the URLs still to crawl.** **Starts as the seed set, grows as you crawl.** ▹ **_"The technology used could be something like Kafka, Redis, or SQS. We'll decide on the technology later."_**
- **Crawler** — **fetches pages, extracts text, extracts new URLs.**
- ⭐ **DNS** — **resolves domains to IPs.** ▹ **_"There are interesting discussions to be had about how to cache DNS lookups, handle DNS failures, and ensure that we are not overloading DNS servers."_** ⇒ **DD3.**
- **Webpage** — **the external server. Outside the system boundary.**
- ⭐ **S3 Text Data** — **_"highly scalable and durable… designed to store large amounts of data cheaply."_** ▹ **GCS or Azure Blob equally fine.**

▹ ⭐ **HI's diagram convention: _"The dotted rectangle represents the boundary of our system."_** ▸ **Drawing that boundary is cheap and it makes "what do I control?" explicit.**

> ⭐⭐ **A one-line question that earns credit — ask about the seed URLs.**
> 
> **_"Are they provided to you, or do you need to come up with them yourself? In almost all cases, the seed URLs will be provided to you. But this question shows that you are thinking holistically about the problem."_** ⭐ **If they're not provided: _"starting with the most popular search engines, news sites, social media platforms, and/or web directories."_**
> 
> ■ **— end of insert · HI write-up resumes below —**

---

## 4 · Deep Dives

▹ ⭐⭐ **HI: _"We are going to go 1-by-1 through our non-functional requirements."_** ⇒ **three NFRs, three dives.**

### 1) How can we ensure we are fault tolerant and don't lose progress?

⚠⚠ **The observation: _"our crawler service is doing a lot. It's hitting DNS, fetching web pages, extracting text data, and extracting new URLs… If there is a failure in any single task, ALL PROGRESS WILL BE LOST."_** ⭐ **And the riskiest task is named: _"Fetching web pages is the most likely task to fail. The internet is a messy place… The server might be down, the connection might be slow, the page might be too large."_**

⭐⭐⭐ **The fix: break the crawler into PIPELINED STAGES.**

- ⭐ **URL Fetcher** — **fetches the HTML and stores the RAW HTML in blob storage.**
- ⭐ **Text & URL Extraction** — **pulls text out of the HTML and pulls links out for the frontier.**
- ▹ ⭐ **HI's judgment call, worth copying as a style: _"There is an argument that text extraction and URL extraction should be separate stages, but these tasks are both simple and can be done in parallel without much overhead so I'd prefer to simplify the design and combine them into a single stage."_**

**Plus new state — a Metadata DB** (⭐ **_"DynamoDB is fine here. PostgreSQL/MySQL could also work"_**):

```
URL:  id · url · s3Link · lastCrawlTime
```

> ⭐⭐⭐ **Two rules HI states here, and the second one is the better argument.**
> 
> - ⭐⭐⭐ **① Never put the payload in the queue.** **_"it is an anti-pattern to store the raw HTML in the queue itself. Queues are not optimized for large payloads… the queue message will just be the ID of the URL in the Metadata DB."_** ▹ ⭐ **Same move as `05o §5.1`. Pointer in the queue, payload in blob storage.**
> - ⭐⭐⭐ **② The real reason to pipeline isn't fault tolerance — it's that you'll want to redo the CHEAP half.** **_"the ML team… wants to change the text extraction process. A simple example could be including image alt text. If we have a separate stage for text extraction, we can easily swap out the text extraction function WITHOUT NEEDING TO REDO THE EXPENSIVE PART of fetching the web pages."_**
> - ⭐⭐⭐ **Generalise: split where expensive-and-irreversible meets cheap-and-revisable, and persist the raw artefact at the seam.** ▸ **Then every future change to the cheap half is free.**
> - ⭐⭐ **HI's rule for the whole class: _"If you get a data processing question like this, your first thought should be to break the system down into smaller, pipelined stages."_**
> 
> ■ **— end of insert · HI write-up resumes below —**

> ⚠⚠ **Confusion resolved — the full flow, end to end. Read this BEFORE the retry rungs.** 💬 **(walked through with the HI Tutor.)**
> 
> ⭐⭐ **The Parsing Queue is the HANDOFF between fetching a page and parsing its saved HTML. It carries only a small `urlId` — never the HTML.**
> 
> ```
> ①  Frontier Queue holds the URL            https://a.com/page
> ②  URL Fetcher takes it, resolves DNS, downloads the HTML
> ③  URL Fetcher writes the HTML ──────────► S3
> ④  URL Fetcher writes the record ────────► Metadata DB
> 	   urlId=42 · url · htmlS3Path · status=FETCHED
> ⑤  URL Fetcher sends  urlId=42  ─────────► Parsing Queue   ⭐ ID only
> ───────────────────── stage boundary · retries stop here ─────────────────────
> ⑥  Parsing Worker takes  urlId=42
> ⑦  Parsing Worker reads htmlS3Path ◄───── Metadata DB
> ⑧  Parsing Worker downloads the HTML ◄─── S3
> ⑨  Parsing Worker extracts text + links
> ⑩  writes the text ─────► S3   ·   updates ─────► Metadata DB
> ⑪  pushes newly found URLs ──────────────► Frontier Queue   ⭐ the loop closes
> ```
> 
> - ⭐⭐⭐ **Why the Parsing Queue exists at all: fetching and parsing are separate FAILURE POINTS.** ▸ **If parsing fails you retry step ⑥ with `urlId=42` only — ⭐ you do NOT download the page again.** ⚠ **Without the queue, one parse error throws away a fetch you already paid bandwidth and politeness budget for.**
> - ⭐⭐ **Three stores, three jobs — keep them straight:** **the QUEUES carry tiny IDs and nothing else · the METADATA DB is the record of where each URL IS in the pipeline (its status and its pointers) · S3 holds the big HTML and text files.**
> - ⭐ **Note step ⑪ — the parser, not the fetcher, is what feeds the frontier.** ▸ **That's what makes it a crawl rather than a one-shot fetch, and it's the component HI's extra dive #4 replaces with a URL Scheduler for recurring crawls.**
> 
> ■ **— end of insert · HI write-up resumes below —**

#### What if we fail to fetch a URL?

> ⚠⚠ **Confusion resolved — this whole section is about the FRONTIER queue, not the Parsing Queue.** 💬 **(checked with the HI Tutor.)**
> 
> ```
> fetch path:   Frontier Queue ──► URL Fetcher ──► website
> on success:   Frontier Queue ──► Fetcher ──► HTML in S3 ──► Parsing Queue ──► Parser
> ```
> 
> - ⭐⭐ **The fetcher deletes the SQS message ONLY after it has successfully fetched the page AND saved the HTML to S3.** ⚠ **Fail or crash before that and it simply doesn't delete — so after the visibility timeout the same URL becomes visible in the FRONTIER queue again for another fetcher to retry.**
> - ⭐⭐⭐ **So: a FETCH failure retries from the Frontier Queue. A PARSE failure retries from the Parsing Queue.** ▸ **Two queues, two independent retry domains — which is the stage boundary drawn in the flow above, and the entire reason for splitting the stages.**
> - ⭐ **The Parsing Queue doesn't exist for a URL until the fetch has already succeeded.** ▸ ⚠ **Which also means each queue needs its OWN visibility timeout and its own DLQ — HI's diagram only draws one.**
> 
> ■ **— end of insert · HI write-up resumes below —**

⚠ **Rung labels are mine.**

**⚠⚠ Bad — an in-memory timer.** **_"The easiest (and worst) thing we could do is to just wait a few seconds using an in-memory timer and try again."_** ⚠⚠ **_"this isn't robust because if a crawler were to go down, we would lose the timer."_** ⭐ **Plus _"it is also very likely that the fetch won't succeed in just a few more seconds"_ ⇒ you need exponential backoff, not a fixed wait.** ▹ ⭐⭐ **Fourth appearance of this exact failure: `05t §5.1`, `05u §5.3`, `05p §5.3`. A timeout in process memory is not a timeout.**

**Good — build backoff on Kafka yourself.** **_"Kafka does not support retries out of the box."_** **A separate topic for failed URLs, a service reading it, and _"we could store the time that the next fetch should occur in the message itself. When a consumer reads a message, it will check the time and if it is in the future, it will wait until that time."_** ⚠ **_"This can work, it's just complex to implement and maintain."_**

**⭐⭐ Great — SQS's visibility timeout.** ▹ ⭐ **You already know these primitives from `05p` — not re-explained.**

- ⭐ **_"when a consumer receives a message but doesn't delete it, the message becomes visible again after the visibility timeout expires (default 30 seconds, configurable up to 12 hours)."_**
- ⭐⭐ **Backoff: use `ChangeMessageVisibility` driven by `ApproximateReceiveCount`, _"which tracks how many times a message has been received."_**
- ⭐ **Give-up: the redrive policy's `maxReceiveCount` moves it to a DLQ automatically.** **_"For our purposes, we'll consider the site offline after 5 retries."_**

#### What happens if a crawler goes down?

⭐ **_"The answer is simple: we spin up a new one."_** ⭐⭐ **The guarantee: _"the URL will stay in the queue until it is confirmed to have been fetched by a crawler AND the HTML is stored in blob storage."_**

- **Kafka:** **_"retains messages in a log and does not remove them even after they are read. Crawlers track their progress via offsets, which are not updated until the URL is successfully fetched and processed."_**
- **SQS:** **_"messages remain in the queue until they are explicitly deleted. A visibility timeout hides a message from other crawlers once it's fetched… once the HTML is stored in blob storage, the crawler will delete the message."_**
- ⭐ **_"Of course, the same applies if a parsing worker goes down."_**

⭐⭐ **The verdict: _"Given SQS's visibility timeout mechanism (which makes implementing exponential backoff straightforward), automatic dead-letter queue support, and managed scaling, we'll use SQS."_**

> ⭐⭐ **Note the contrast with `05u §5.4`, where KAFKA won.** ▸ **Both problems need "the work survives a dead worker", but the deciding feature differs: there it was commit-offset-after-match for replay; here it's built-in backoff + DLQ.** ⭐ **Same requirement, opposite technology, and both are defensible — which is exactly HI's next point.**
> 
> ⭐⭐⭐ **And this is HI giving you explicit permission on something you have asked me about directly:**
> 
> **_"When it comes to choosing a technology, there is usually no right or wrong answer. It's all about trade-offs and your ability to justify your decision. Additionally, it's TOTALLY REASONABLE THAT YOU WOULD NOT KNOW THE SPECIFICS of how Kafka or SQS handle retries. If that's the case, this may not be a place where you choose to go deep."_**
> 
> ▸ ⭐⭐ **You asked whether you need to be able to write Redis commands. This is the author's answer: pick where you go deep, justify the choice, and say plainly when something isn't your depth.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 2) ⭐⭐⭐ How can we ensure politeness and adhere to robots.txt?

⭐ **Politeness = _"being respectful with the resources of the websites we are crawling… ensuring that our crawling activity does not disrupt the normal function of the site by overloading its servers, respecting the website's bandwidth, and adhering to any specific restrictions."_**

⭐⭐ **`robots.txt` = _"a file that websites use to communicate with web crawlers. It tells crawlers which pages they are allowed to crawl and which pages they are not. It also tells crawlers how frequently they can crawl the site."_**

```
User-agent: *          ⭐ which crawler the rules apply to (* = all)
Disallow: /private/    ⭐ paths you may not crawl
Crawl-delay: 10        ⭐ seconds to wait between requests
```

▹ ⭐⭐ **A precise detail worth keeping: _"`Crawl-delay` is not part of the official Robots Exclusion Protocol standard and is ignored by some major crawlers (notably Googlebot). However, respecting it demonstrates good crawling etiquette and is appropriate for our use case."_**

⭐ **Two jobs: ① respect `robots.txt` ② rate-limit per domain — _"The industry standard is to limit the number of requests to 1 request per second."_**

#### ① Respecting robots.txt

- ⭐ **Store the file per domain.** ▹ **_"you may have a discussion about how regularly you should check for updates to this file. For simplicity, we'll just assume it's a one-time download."_**
- ⭐ **Disallowed? _"we can ack the message (remove it from the queue) and move on."_**
- ⭐⭐ **Crawl-delay? Add a Domain table holding the last crawl time, and if it's too recent, _"use SQS's `ChangeMessageVisibility` API to extend the visibility timeout, deferring when the message becomes available again."_**

```
Domain:  domain · lastCrawlTime · robots
```

**The seven steps:**

1. **Fetch the `robots.txt` for the domain.**
2. **Parse it and store it in the Metadata DB.**
3. **On pulling a URL off the queue, check that domain's stored rules.**
4. **Disallowed ⇒ ack the message, move on.**
5. **Allowed ⇒ check `Crawl-delay`.**
6. ⭐ **Delay not yet elapsed ⇒ `ChangeMessageVisibility` to defer.**
7. **Delay elapsed ⇒ crawl, and update the domain's last crawl time.**

> ⭐⭐⭐ **Confusion resolved — two things here close gaps you've already hit.**
> 
> - ⭐⭐⭐ **① A timestamp column is NOT a lock.** **HI: _"Since we have multiple crawlers running in parallel, two crawlers could pull URLs from the same domain simultaneously and both see a stale 'last crawl time.' To prevent this, we can use an atomic operation (like Redis `SET` with `NX` and a TTL matching the crawl delay) to acquire a per-domain lock before crawling. If a crawler can't acquire the lock, it defers the message."_** ▸ ⭐⭐ **Identical to `05u §5.3`'s lock on `driverId` and `05t §5.3`'s `NX`/`EX` — fourth appearance, not re-explained.** ⭐ **The only new part is the KEY: the domain, not a driver or a message.**
> - ⭐⭐⭐ **② This SHARPENS your `05p` confusion-resolved block on `DelaySeconds`.** **HI: _"`DelaySeconds` only applies when sending a NEW message. For messages already in-flight (which is our case), use `ChangeMessageVisibility` to defer reprocessing. Visibility timeout can be extended up to 12 HOURS per message."_** ▸ ⭐⭐⭐ **So the 15-minute cap you noted in `05p` applies to NEW messages only — and the in-flight path gives you 12 hours. Two different APIs for two different situations; go back and link this.**
> 
> ■ **— end of insert · HI write-up resumes below —**

#### ② Rate limiting

⚠ **_"With multiple crawlers, this can get a little trickier since, in theory, all N crawlers could be hitting a single domain at the same time."_**

- ⭐⭐ **_"a global, domain-specific rate limiting mechanism using a centralized data store (like Redis) to track request counts per domain per second… We'll use a SLIDING WINDOW algorithm."_** **Over the limit ⇒ wait for the next second.**
- ⚠⚠ **And then the failure mode that one creates:** **_"the risk of SYNCHRONIZED BEHAVIOR among multiple crawlers. If several crawlers are waiting to make requests and simultaneously retry when the rate limit window resets, they'll all try and only one will succeed and the process will repeat."_**
- ⭐⭐⭐ **Fix: JITTER.** **_"By introducing a small amount of randomness to the rate-limiting algorithm, we can prevent synchronized behavior among crawlers… adding a random delay to each crawler's request, ensuring that they do not all retry at the same time."_** ▸ ⭐⭐ **The primitive: any time N workers wait on the SAME clock, they wake together. Jitter breaks the convoy.**

### 3) ⭐⭐⭐ How to scale to 10B pages and efficiently crawl them in under 5 days?

⭐⭐ **_"Since scalability and efficiency go hand in hand, we'll tackle these two requirements together."_** ⭐ **The framing: _"we should recognize that this is an I/O intensive task."_**

> 📐 ⭐⭐⭐ **The full BOE chain — reproduce this, it's the best one in your set.**
> 
> |Step|Figure|
> |---|---|
> |**A network-optimised instance** (`c6in.32xlarge` / `c7gn.16xlarge`)|**200 Gbps**|
> |**÷ 8 bits/byte ÷ 2MB per page**|⭐ **≈ 12,500 pages/sec** — **_"That's a ton, but it's likely not actually possible"_**|
> |⭐ **× 30% real utilisation**|⭐⭐ **3,750 pages/sec**|
> |**10B pages ÷ 3,750/sec**|**2,666,667 sec ≈ 30.9 days on ONE machine**|
> |⭐⭐ **÷ 8 machines** (**_"This scales linearly"_**)|⭐⭐ **≈ 3.9 days — under the 5-day bar** ✅|
> 
> - ⭐⭐ **Why only 30%: _"There will be practical limitations on the number of requests we can make per second dictated by factors like server response latency, DNS resolution, rate limiting, politeness, retries, etc."_** ▹ **HI admits _"We get very hand-wavy here."_**
> - ⭐⭐ **And the permission slip: _"There are a lot of assumptions in these estimations and, in reality, you would need to do load testing… But for an interview, it's less about being right and more about showing that you can reason through the problem."_**
> - ⭐ **Note where the 2MB came from: _"the total transfer size including HTML and any inline resources, though the HTML alone is typically much smaller at ~30KB, but 2MB is a reasonable worst-case for planning bandwidth."_** ▸ ⭐⭐ **Being explicit about which number you chose and why is half the credit.**
> 
> ■ **— end of insert · HI write-up resumes below —**

> ⭐⭐⭐ **Confusion resolved — "1 request/sec per domain" vs "3,750 pages/sec". An interviewer WILL ask this.**
> 
> **_"You might wonder how we can achieve thousands of pages per second when we're rate-limited to 1 request/second per domain. The key insight is that we're crawling MILLIONS of different domains in parallel. Each crawler maintains THOUSANDS OF CONCURRENT CONNECTIONS to different sites simultaneously, so while any single domain sees at most 1 request/second, the aggregate throughput across all domains is very high."_**
> 
> ▸ ⭐⭐⭐ **A per-key limit constrains the KEY, not the system. 3,750/sec needs only ~3,750 distinct domains in flight — and there are millions.**
> 
> ■ **— end of insert · HI write-up resumes below —**

**Parser workers** — ⭐ **_"This should be easier… Rather than estimating how many we need, we can just scale this up and down dynamically based on the number of pages in the queue. This could be via Lambda functions, ECS on Fargate, or other auto-scaling compute."_** ▸ ⭐ **Scale on queue depth where nothing is blocked on the reply; estimate only where you must pre-provision.**

> ⭐⭐ **Don't forget DNS — the bottleneck candidates skip.**
> 
> - ⚠⚠ **_"You might wonder why we call it out explicitly, since tools like curl handle DNS automatically. The issue is SCALE. At thousands of requests per second across millions of unique domains, DNS resolution becomes a real bottleneck. Each lookup for a new domain requires multiple network round-trips through the DNS hierarchy."_**
> - ⭐⭐⭐ **The figure that makes it concrete: _"early web crawler research (like the Mercator crawler paper) found that DNS lookups accounted for UP TO 70% of each thread's elapsed time before they built a custom resolver."_**
> - **Two fixes:** ⭐ **DNS caching in the crawlers** — **_"all URLs to the same domain will reuse the same DNS lookup"_** · ⭐⭐ **multiple DNS providers, round-robined** — **_"distribute the load across multiple providers and reduce the risk of hitting rate limits."_**
> 
> ■ **— end of insert · HI write-up resumes below —**

#### Efficiency — don't crawl the same thing twice

⭐⭐ **Two layers, and the first is not enough:**

- ⭐ **URL-level dedup: _"check if a URL has already been crawled by checking the Metadata DB before putting it on the queue. If the URL already exists in our URL table, we skip it. This is our FIRST LINE OF DEFENSE."_**
- ⭐⭐ **Content-level dedup, because _"different URLs can serve identical content. For example, `http://example.com` and `http://www.example.com` might return the same page. It's also common for totally different domains to have exactly the same content (a maybe depressing fact about the internet)."_** ⇒ **hash the page content after fetching and compare.** ⭐ **Match ⇒ _"we skip the expensive parsing step."_**

⚠ **Rung labels are mine.**

**⭐⭐ Approach A — a hash column with an index (HI's pick).** **Store the content hash in the URL table, index the hash column, look up on each fetch.** ⭐ **And HI pre-empts the objection: _"While the index will become large and may slow down writes, this would be OVERLY PESSIMISTIC. Modern databases are quite efficient at handling indexes, even large ones… this overhead is generally well-optimized in modern systems so it's safe to overlook this concern."_**

**Approach B — a Bloom filter.** ⭐ **_"a probabilistic data structure… It can tell us DEFINITIVELY if an element is NOT in the set, but it can only tell us with some probability if an element IS in the set."_** **Redis with the RedisBloom module (`BF.ADD`, `BF.EXISTS`), or bit operations, or in-process memory.** ⚠ **False positives ⇒ you skip a page you never crawled; tune by growing the filter and adding hash functions.**

> ⚠⚠ **The famous answer is the WRONG answer here, and the author says so.**
> 
> **_"To be honest, I think the bloom filter here is a bit overkill. It's a cool data structure, and it's fun to talk about in an interview, but I think the INDEX APPROACH IS MORE PRACTICAL. It's simpler, and modern DB indexes are quite efficient. I note this as a solution more because CANDIDATES ALWAYS BRING IT UP. I assume this is because it's a common solution in the literature."_**
> 
> - ⚠ **So reaching for the Bloom filter here signals "I read the textbook", not "I've built this."**
> - ⭐⭐ **How to use it anyway: name it, then reject it.** _"A Bloom filter is the classic answer, but an indexed hash column is simpler and modern indexes handle this scale fine — I'd only reach for the filter if the index genuinely became a write bottleneck."_ ▸ **That shows you know it AND have judgment, which is strictly better than either alone.**
> - ⭐ **Same shape as `05u`'s DD6 and `05v`'s NAT gateway: the first component that comes to mind is not automatically the right one.**
> 
> ■ **— end of insert · HI write-up resumes below —**

#### ⭐⭐ Crawler traps

⚠ **_"pages that are designed to keep crawlers on the site indefinitely… created by having a page that links to itself many times or by having a page that links to many other pages on the site. If we're not careful, we could end up crawling the same site over and over again and never finish."_**

- ⭐ **Fix: a maximum depth, 15–20, stored as a `depth` field on the URL and incremented on each followed link. Over threshold ⇒ stop that branch.**
- ⭐⭐⭐ **And the clarification that matters: _"Here, 'depth' means the number of LINK HOPS from a seed URL, NOT the number of path segments in the URL. A seed URL starts at depth 0, any page linked from the seed is depth 1, pages linked from those are depth 2, and so on."_**

### ⭐ HI's five suggested extra dives

1. ⭐ **Dynamic content** — **JS-rendered pages need _"a headless browser like Puppeteer to render the page and extract the content."_**
2. **Monitoring** — **Datadog or New Relic on crawlers and parser workers.**
3. ⭐⭐ **Large files** — **_"send an HTTP HEAD request first to check the `Content-Length` header and skip files that exceed a threshold (say 10MB) without downloading the full content."_** ▸ ⭐ **Cheap, concrete, and a nice thing to volunteer.**
4. ⭐⭐ **Continual updates** — **the real architectural one: _"adding a new component 'URL Scheduler' that is responsible for scheduling URLs to be crawled. So rather than putting URLs on the queue directly from the parser workers, the parser workers would put URLs in the Metadata DB and the URL Scheduler would be responsible for scheduling URLs to be crawled by using some logic based on last crawl time, popularity, etc."_** ▸ ⭐⭐ **One-time crawl ⇒ workers push to the queue. Recurring crawl ⇒ workers record intent, a scheduler decides. Same inversion as `05r`'s tiered polling.**
5. ⭐ **Priority crawling** — **_"multiple SQS queues with different priorities and have crawlers poll the high-priority queue first. Kafka doesn't natively support priority-based consumption, but you can achieve a similar effect with separate topics per priority level."_** ▹ **Same conclusion as `05t §5.2` and `05u §5.4`.**

---

## 5 · Final Design

⚠ **Layout and arrows are mine; components and field lists are HI's.**

```
Frontier Queue (SQS) ──► Crawler ───DNS lookup──► DNS
  ▲   ⭐ holds URL IDs,     - fetch & store webpage       ▲
  │      never HTML              │  ──fetch HTML──► Webpage (external)
  │   ⭐ ChangeMessageVisibility │
  │      defers a URL whose      ├──► S3 HTML Data   ⭐ RAW html kept, so the
  │      Crawl-delay hasn't      │                      cheap half can be redone
  │      elapsed (up to 12h)     │                      without re-fetching
  │   ⚠ DelaySeconds is for      │
  │      NEW messages only       └──► URL Metadata (DynamoDB / Postgres)
  │                                    id · url · s3Link · lastCrawlTime
  │   ┌──Retry w/ backoff──► DLQ       hash (GSI) ⭐ content dedup
  │   │  ⭐ ChangeMessageVisibility    depth      ⭐ traps, 15-20 = link
  │   │     × ApproximateReceiveCount              HOPS, not path segments
  │   │  ⭐ maxReceiveCount ⇒ DLQ, offline after 5
  │   │
  │  Parsing Queue (SQS) ──► Parsing Worker
  │                            - check hash FIRST
  │                            - S3 html in, S3 text out
  │                            ⭐ autoscale on queue depth
  └──put extracted URLs back──────┘    (Lambda / ECS Fargate)
     ⭐ dedup against the URL table BEFORE enqueuing

Domain table: domain · lastCrawlTime · robots   ⭐ one-time download

Redis — rate limiter + DNS cache + per-domain lock
  ⭐⭐ sliding window, 1 req/sec/domain, + JITTER so crawlers don't
     all wake on the same window reset
  ⭐⭐⭐ SET NX + TTL = the per-domain lock, because two crawlers
     reading lastCrawlTime both see it stale (cf. 05u §5.3, 05t §5.3)
  ⭐ DNS cache — lookups were up to 70% of thread time (Mercator)
     ⭐⭐ + round-robin MULTIPLE providers = HI's Staff-level answer

📐 8 machines × 3,750 pages/sec ⇒ 10B pages in ~3.9 days
   ⭐ 1/sec/domain and 3,750/sec don't conflict: millions of domains
      in parallel, thousands of concurrent connections each
```

---

## 6 · Expected at Each Level

|Level|The bar for Web Crawler|
|---|---|
|**Mid (E4)**|**Understand the data flow, build the simple HLD, discuss politeness and robots.txt basics, some idea of scaling — depth on queueing tech and rate limiting not expected.**|
|**Senior (E5)**|**HLD fast, then real detail on politeness/robots.txt, plus how to scale and hit the 5-day window.**|
|**Staff+**|**Deep in 3+ areas, practical over academic, and the interviewer comes away having learned something.**|

---

## Quick Recall (pass 3+)

|Use / Question|Web Crawler answer|
|---|---|
|Calibration|**Evan King · Feb 2026** · ⭐⭐ **"HARD", third in a row** · ⭐⭐ **ZoomInfo (+6) = 7 companies** · ⚠ **NO Pattern callout — first in your set with none** · **3 dives, one per NFR.** ⭐⭐⭐ **TWO passes: once for the system, once for the META-ADVICE, which is the richest in your set**|
|⭐⭐⭐ Design driver|⭐⭐ **Go as fast as physics allows while being deliberately slow to everyone.** **Aggregate: 3,750 pages/sec on 8 machines to hit 5 days. Per domain: ⚠ 1 req/SEC plus `Crawl-delay`.** ⭐⭐⭐ **Not a contradiction — _"we're crawling MILLIONS of different domains in parallel… while any single domain sees at most 1 request/second, the aggregate throughput across all domains is very high."_** ▸ ⭐⭐⭐ **A per-key limit constrains the KEY, not the system.** ⭐⭐ **Second axis: FETCHING is expensive + irreversible, PARSING is cheap + revisable — which is where the pipeline splits**|
|📐 The BOE chain (reproduce it)|**200 Gbps instance (`c6in.32xlarge`/`c7gn.16xlarge`) ÷ 8 bits ÷ 2MB = ⭐ 12,500 pages/sec** (**_"a ton, but likely not actually possible"_**) **× 30% = ⭐⭐ 3,750/sec.** **10B ÷ 3,750 = 2,666,667s ≈ 30.9 days on one machine ÷ 8 = ⭐⭐ 3.9 days** ✅. ⭐ **Why 30%: _"server response latency, DNS resolution, rate limiting, politeness, retries"_ — HI admits _"we get very hand-wavy here."_** ⭐ **The 2MB is _"total transfer size… the HTML alone is typically ~30KB, but 2MB is a reasonable worst-case for planning bandwidth."_** ⭐⭐ **_"it's less about being right and more about showing that you can reason through the problem"_**|
|⭐⭐⭐ The NFR paragraph (read twice)|⭐⭐⭐ **_"So often I see candidates rush through the requirements and then look at me, the interviewer, wide eyed, unsure of what to do next after they have a simple design. If you've taken your time to define quality non-functional requirements, then you shouldn't run out of things to talk about until your system has met all functional and non-functional requirements, at which point, you've likely passed the interview!"_** ▸ ⭐⭐⭐ **Your NFRs ARE your deep-dive agenda — HI: _"we are going to go 1-by-1 through our non-functional requirements."_** ⭐⭐ **This file proves it: DD1 = fault tolerance, DD2 = politeness, DD3 = scale + efficiency. The fix for "I ran out of things to say" is better NFRs, earlier**|
|⭐⭐⭐ Two sequencing rules|⭐⭐ **DELAY the math: _"I recommend delaying these calculations until they are necessary for solving a specific problem. This approach avoids unnecessary computations."_** ⭐⭐⭐ **SCALING LAST: _"had scaling been our first deep dive we would have missed bottlenecks like the parser workers introduced in subsequent deep dives."_** ▸ ⭐⭐ **You can't size components you haven't invented yet.** ▹ **But GET the numbers early — _"the scale will have a large impact on the database design and the overall architecture"_** ⇒ ⭐ **numbers early, arithmetic late**|
|FRs / NFRs|**Crawl from seed URLs · extract text and store it.** Below: processing the text (training) · non-text data · dynamic content · auth. **NFRs: ⭐⭐ fault tolerance _"resume crawling without losing progress"_ · ⭐⭐⭐ politeness _"adhere to robots.txt and not overload website servers"_ · efficiency _"under 5 days"_ · scale _"10B pages"_.** Below: security · cost · compliance. ⭐ **Honesty caveat: _"It's not possible to scrape the entire internet… it's a general assumption of web crawling that you can't reach every page."_**|
|⭐ Scope question that comes FIRST|⭐⭐ **Ask what the output is FOR: _"a search engine would need to index the data and rank it (using PageRank…), while a company like OpenAI would dump the raw text… to train LLMs."_** **This file picks LLM training — which is why there's no ranking or index, just fetch/extract/store**|
|⭐⭐ No API — System Interface + Data Flow|⚠⚠ **First file in your set with NO API section.** ⭐ **HI: _"Given this system isn't a user-facing system, we'll instead focus on the abstract interface it has with the outside world and break down the data flow."_** **Interface: IN = seed URLs, OUT = extracted text.** **Flow: ① frontier → DNS ② fetch HTML ③ extract text ④ store ⑤ extract links → queue ⑥ repeat.** ▸ ⭐⭐ **Steal this shape for any pipeline / ETL / ingestion question**|
|HLD components|**Frontier Queue** (⭐ _"Kafka, Redis, or SQS. We'll decide on the technology later"_) · **Crawler** · **DNS** (⭐ caching + failures deferred to DD3) · **Webpage** (external) · ⭐ **S3** (_"highly scalable and durable… designed to store large amounts of data cheaply"_). ⭐ **Draw the dotted system BOUNDARY.** ⭐ **Ask about seed URLs — _"In almost all cases… provided to you. But this question shows that you are thinking holistically"_; else popular search engines, news, social, web directories**|
|⭐⭐⭐ DD1 — pipeline the stages|⚠⚠ **_"our crawler service is doing a lot… If there is a failure in any single task, ALL PROGRESS WILL BE LOST."_** ⭐ **And _"fetching web pages is the most likely task to fail. The internet is a messy place."_** ⭐⭐⭐ **Split into URL Fetcher (fetch + store RAW HTML) and Text & URL Extraction.** ▹ ⭐ **HI merges text + URL extraction deliberately: _"both simple and can be done in parallel without much overhead so I'd prefer to simplify."_** ⭐⭐ **HI's class-wide rule: _"If you get a data processing question like this, your first thought should be to break the system down into smaller, pipelined stages."_**|
|⚠⚠ DD1 — the full flow (11 steps)|**① Frontier Queue holds the URL ② URL Fetcher resolves DNS + downloads HTML ③ HTML → S3 ④ record → Metadata DB (`urlId=42 · url · htmlS3Path · status=FETCHED`) ⑤ ⭐ `urlId=42` → Parsing Queue, ID ONLY ⑥ Parsing Worker takes it ⑦ reads `htmlS3Path` ← Metadata DB ⑧ downloads HTML ← S3 ⑨ extracts text + links ⑩ text → S3, update → Metadata DB ⑪ ⭐ new URLs → Frontier Queue, loop closes.** ⭐⭐⭐ **Why the Parsing Queue exists: fetching and parsing are separate FAILURE POINTS — a parse failure retries step ⑥ with `urlId=42` only, and does NOT re-download the page.** ⭐⭐ **Three stores, three jobs: QUEUES carry tiny IDs · METADATA DB records where each URL IS in the pipeline · S3 holds the big files.** ⭐ **And note ⑪ — the PARSER feeds the frontier, which is what makes it a crawl**|
|⭐⭐⭐ DD1's two rules|⭐⭐⭐ **① _"it is an anti-pattern to store the raw HTML in the queue itself. Queues are not optimized for large payloads… the queue message will just be the ID of the URL in the Metadata DB."_** ▹ **Same as `05o §5.1`: pointer in the queue, payload in blob storage.** ⭐⭐⭐ **② The BETTER reason to pipeline: _"the ML team… wants to change the text extraction process… we can easily swap out the text extraction function WITHOUT NEEDING TO REDO THE EXPENSIVE PART of fetching."_** ▸ ⭐⭐⭐ **Split where expensive+irreversible meets cheap+revisable, and persist the raw artefact at the seam. Then every future change to the cheap half is free**|
|DD1 retry ladder|⚠⚠ **Bad: an in-memory timer — _"if a crawler were to go down, we would lose the timer"_, and _"it is also very likely that the fetch won't succeed in just a few more seconds."_** ▹ ⭐⭐ **FOURTH appearance of this failure (`05t §5.1`, `05u §5.3`, `05p §5.3`).** **Good: DIY on Kafka — a failed-URL topic, next-fetch time in the message body. ⚠ _"complex to implement and maintain."_** ⭐⭐ **Great: SQS — visibility timeout (_"default 30 seconds, configurable up to 12 hours"_), `ChangeMessageVisibility` driven by `ApproximateReceiveCount`, `maxReceiveCount` ⇒ DLQ, _"offline after 5 retries"_**|
|Crawler-down + the SQS verdict|⭐⭐ **_"the URL will stay in the queue until it is confirmed to have been fetched AND the HTML is stored in blob storage."_** **Kafka: offsets _"are not updated until the URL is successfully fetched and processed."_ SQS: visibility timeout hides it; delete only after S3.** ⭐ **_"the same applies if a parsing worker goes down."_** ⭐⭐ **Verdict: SQS, for _"visibility timeout… automatic dead-letter queue support, and managed scaling."_** ⭐⭐ **Contrast `05u §5.4` where KAFKA won — same requirement, opposite tech, both defensible**|
|⭐⭐⭐ HI's permission slip|⭐⭐⭐ **_"there is usually no right or wrong answer. It's all about trade-offs and your ability to justify your decision. Additionally, it's TOTALLY REASONABLE THAT YOU WOULD NOT KNOW THE SPECIFICS of how Kafka or SQS handle retries. If that's the case, this may not be a place where you choose to go deep."_** ▸ ⭐⭐ **This is the author answering the question you asked me about Redis commands: pick where you go deep, justify the choice, say plainly when something isn't your depth**|
|robots.txt|`User-agent: *` (**which crawler**) · `Disallow: /private/` (**forbidden paths**) · `Crawl-delay: 10` (**seconds between requests**). ⭐⭐ **_"`Crawl-delay` is not part of the official Robots Exclusion Protocol standard and is ignored by some major crawlers (notably Googlebot). However, respecting it demonstrates good crawling etiquette."_** ⭐ **Store per domain, _"assume it's a one-time download."_** ⭐ **Disallowed ⇒ _"ack the message and move on."_**|
|⭐⭐⭐ DD2 — a timestamp is NOT a lock|⚠⚠ **_"two crawlers could pull URLs from the same domain simultaneously and both see a stale 'last crawl time.'"_** ⭐⭐⭐ **Fix: _"an atomic operation (like Redis `SET` with `NX` and a TTL matching the crawl delay) to acquire a per-domain lock before crawling. If a crawler can't acquire the lock, it defers the message."_** ▸ ⭐⭐ **Identical to `05u §5.3` (`driverId`) and `05t §5.3` (`NX`/`EX`) — fourth appearance. ⭐ Only the KEY is new: the domain**|
|⭐⭐⭐ DD2 — this fixes your `05p` note|⭐⭐⭐ **_"`DelaySeconds` only applies when sending a NEW message. For messages already in-flight (which is our case), use `ChangeMessageVisibility` to defer reprocessing. Visibility timeout can be extended up to 12 HOURS per message."_** ▸ ⭐⭐⭐ **So `05p`'s 15-minute cap applies to NEW messages only; the in-flight path gives you 12 hours. Two APIs, two situations — go back and link `05p §5.1` to this**|
|⭐⭐ DD2 rate limiting + jitter|⭐⭐ **_"a global, domain-specific rate limiting mechanism using a centralized data store (like Redis)… a SLIDING WINDOW algorithm"_**, 1 req/sec/domain. ⚠⚠ **The failure it creates: _"the risk of SYNCHRONIZED BEHAVIOR… If several crawlers are waiting… and simultaneously retry when the rate limit window resets, they'll all try and only one will succeed and the process will repeat."_** ⭐⭐⭐ **Fix: JITTER — _"a random delay to each crawler's request, ensuring that they do not all retry at the same time."_** ▸ ⭐⭐ **Any time N workers wait on the SAME clock, they wake together. Jitter breaks the convoy**|
|⭐⭐⭐ The 1/sec vs 3,750/sec question|⭐⭐⭐ **_"You might wonder how we can achieve thousands of pages per second when we're rate-limited to 1 request/second per domain. The key insight is that we're crawling MILLIONS of different domains in parallel. Each crawler maintains THOUSANDS OF CONCURRENT CONNECTIONS to different sites simultaneously."_** ▸ ⭐⭐⭐ **3,750/sec needs only ~3,750 distinct domains in flight, and there are millions. Interviewers ask this — have the sentence ready**|
|Parser workers|⭐ **_"Rather than estimating how many we need, we can just scale this up and down dynamically based on the number of pages in the queue"_** — **Lambda, ECS on Fargate.** ▸ ⭐ **Scale on depth where nothing is blocked on the reply; estimate only where you must pre-provision** (⚠ **contrast `05v §4.2`, where the user IS blocked**)|
|⭐⭐ DNS, the skipped bottleneck|⚠⚠ **_"The issue is SCALE. At thousands of requests per second across millions of unique domains, DNS resolution becomes a real bottleneck. Each lookup for a new domain requires multiple network round-trips through the DNS hierarchy."_** ⭐⭐⭐ **_"the Mercator crawler paper found that DNS lookups accounted for UP TO 70% of each thread's elapsed time before they built a custom resolver."_** **Fixes: ⭐ cache in the crawler · ⭐⭐ round-robin MULTIPLE providers.** ⭐⭐⭐ **HI on the second: _"suggested by a Staff candidate… I love how practical it is. It BREAKS OUT OF THE 'ACADEMIC ANSWER'."_** ▸ ⭐⭐ **Practical beats clever**|
|Dedup — two layers|⭐ **① URL-level: check the Metadata DB BEFORE enqueuing — _"our first line of defense."_** ⭐⭐ **② Content-level, because _"different URLs can serve identical content… `http://example.com` and `http://www.example.com`"_ and _"totally different domains [have] exactly the same content (a maybe depressing fact about the internet)."_** ⇒ **hash after fetching; match ⇒ _"we skip the expensive parsing step"_**|
|⚠⚠ The Bloom filter trap|⭐⭐ **HI PREFERS the indexed hash column, and pre-empts the objection: _"While the index will become large and may slow down writes, this would be OVERLY PESSIMISTIC. Modern databases are quite efficient at handling indexes, even large ones."_** ⚠⚠ **On the Bloom filter: _"a bit overkill… fun to talk about in an interview, but I think the index approach is more practical… I note this as a solution more because CANDIDATES ALWAYS BRING IT UP."_** ⭐⭐ **So name it, then REJECT it — that shows knowledge AND judgment, which beats either alone.** ▹ **Bloom = definitively NOT in the set, probably in it; RedisBloom `BF.ADD`/`BF.EXISTS`**|
|⭐⭐ Crawler traps|⚠ **_"pages designed to keep crawlers on the site indefinitely… a page that links to itself many times."_** ⭐ **Fix: a `depth` field, threshold 15–20, stop the branch above it.** ⭐⭐⭐ **And the clarification: _"'depth' means the number of LINK HOPS from a seed URL, NOT the number of path segments in the URL. A seed URL starts at depth 0."_**|
|⭐ HI's five extra dives|**① dynamic content ⇒ _"a headless browser like Puppeteer"_ ② monitoring ⇒ Datadog/New Relic ③ ⭐⭐ large files ⇒ _"send an HTTP HEAD request first to check the `Content-Length` header and skip files that exceed a threshold (say 10MB)"_ ④ ⭐⭐ continual updates ⇒ a URL SCHEDULER: _"the parser workers would put URLs in the Metadata DB and the URL Scheduler would be responsible for scheduling… based on last crawl time, popularity"_** ▸ ⭐⭐ **one-time crawl: workers push. recurring: workers record intent, a scheduler decides** **⑤ priority ⇒ multiple SQS queues, poll high first; _"Kafka doesn't natively support priority-based consumption"_**|
|⭐⭐⭐ The meta-lesson|⭐⭐⭐ **Three things from this file outlive the problem: (1) your NFRs are your dive agenda, so weak NFRs are why you run dry; (2) numbers early, arithmetic late, scaling last; (3) the practical answer beats the textbook one — multiple DNS providers reads as Staff, a Bloom filter reads as "I read the literature."**|
|Levels (one line)|**E4:** the data flow, the simple HLD, politeness basics, some idea of scaling — no depth needed on queueing or rate limiting · **E5:** fast HLD then real detail on politeness/robots.txt and hitting 5 days · **Staff+:** 3+ deep areas, practical over academic, interviewer learns something|

---

> 🔗 **HI source:** https://www.hellointerview.com/learn/system-design/problem-breakdowns/web-crawler