# Online Judge / Code Execution Platform (LeetCode) — Problem Breakdown

> 📐 **Revision note (calc):** one calculation, and it is the whole argument for horizontal scaling (§5.3). **10k concurrent submissions × ~100 test cases = 1M test cases**; at a **conservative 100ms each = 100,000 CPU-seconds ≈ 27.8 hours** serial ⇒ **~1,667 cores to clear it in 60s.** ⊕ ⚠⚠ **But HI budgets 60s here, not its own 5s NFR — at 5s the same math needs ~20,000 cores.** ⭐ **Memorise the shape, not the number: `concurrent submissions × test cases × per-case ms ÷ target seconds = cores`.** ▹ The other scale figures are deliberately tiny: **few hundred thousand users · ~4,000 problems · 100k competition users · 90-min / 10-problem competitions.** ⚠ **There is no storage math in this write-up and none is needed — don't invent any.**

> Hello Interview · Question Breakdowns · File `05i`. **Evan King**, updated **Feb 15, 2026** · ⭐ **"medium"** · ⭐ **asked at Whatnot, LinkedIn (+3 more, not named in the source)** · has a video walkthrough. ⭐ **One Pattern callout only: `Managing Long Running Tasks` → `03g`.** Cross-refs: ⭐⭐ **long-running tasks / job-ID + poll → `03g`** · **DynamoDB, GSIs → `02f`** · ⭐ **Redis sorted sets → `02a`** · **polling vs WebSockets → `03a`** · **caching → `01e`** · **scaling reads → `03d`** (the leaderboard dive, loosely) · **CAP / availability>consistency → `01h`** · **API design, pagination, auth → `01b`** · **numbers → `01i`** · **queues: HI picks SQS, not Kafka — contrast `02c`.** ⚠ **`03b` contention does NOT apply here** — your starter-prompt guess was wrong; there is no contended resource in this problem. **Siblings: `05e` Ticketmaster (Redis + durable store two-layer) · `05h` Tinder (the mirror image — strong consistency; here availability wins).**
> 
> **Calibration:** ⚠ **I disagree with "medium" — this is the easiest problem in the series so far, and HI half-admits it:** _"I don't typically ask this question of staff+ candidates given it is on the easier side."_ ⭐ **Two of the four dives are thin** (DD1 is a 5-item security checklist; DD3 is "scale horizontally, add a queue"). ⭐⭐ **Give it ONE pass, not three.** ▸ **What makes it worth that one pass is unusual: the scoring axis here is restraint, not sophistication.** HI rejects WebSockets twice, rejects vertical scaling, rejects microservices, and calls its own chosen queue _"likely overkill."_ ⭐⭐ **This is the only file in the series where "I know the complex answer and here is why I'm not using it" IS the answer.**
> 
> - ⭐⭐ **What actually scores:**
>     - **(a)** ⭐⭐ **The four-rung isolation ladder — API server → VM → container → serverless** (§4.3), and **being able to state the VM-vs-container difference precisely** (kernel sharing). ▸ **This is the single most-probed thing in the question.**
>     - **(b)** ⭐⭐ **The test-harness question (§5.4)** — _"How would you actually take test cases and run them against user code of any language?"_ ▸ **HI says this exists to break candidates out of "box drawing mode."** ⭐ **Nothing else in the file separates candidates this cleanly.**
>     - **(c)** ⭐ **The security checklist as five named bounds** (§5.1) — read-only FS · CPU/memory · timeout · no network · seccomp. ▹ **HI explicitly says one sentence naming them is enough.**
>     - **(d)** ⭐⭐ **Doing the CPU math out loud before choosing horizontal over vertical** (§5.3). ▸ **The math IS the justification; without it "scale horizontally" is a guess.**
>     - **(e)** ⭐ **Redis sorted set for the leaderboard** (§5.2) + ⭐⭐ **saying WebSockets are overkill and why.**
>     - **(f)** ⭐⭐ **Declaring the system small and choosing a monolith** (§4 preamble) — ▸ **the only problem in the series where HI rejects microservices.**
>     - **(g)** ⭐ **Justifying the queue on retries, not throughput** (§5.3) — ▸ **and conceding it may be over-engineering in the same breath.**
> - ⭐ **Transferable primitives:**
>     - ⭐⭐ **Name the sophisticated solution, then reject it with a specific reason.** WebSockets (×2), vertical scaling, microservices, the queue itself. ▸ **HI: staff candidates _"articulate that they know what the more complex solution is, but they are clear about why it's likely overkill."_** ⭐ **Reusable in every single design interview.**
>     - ⭐⭐ **Untrusted code ⇒ isolate at the kernel boundary and bound EVERY resource** — CPU, memory, wall-clock, filesystem, network, syscalls. ▸ **Reusable for plugin systems, user-defined functions, CI runners, webhook sandboxes.**
>     - ⭐ **Write fixtures once in a neutral serialization, then one thin adapter per runtime.** ▸ **Reusable for any multi-language or multi-client system — never write the same test N times.**
>     - ⭐ **Do the capacity math before picking vertical vs horizontal.** `work × unit-cost ÷ target-latency = parallelism needed`.
>     - ⭐ **A queue can earn its place on retries and buffering alone, even when throughput doesn't demand it.**
> - ⭐ **Re-run (cross-ref, NOT re-explained):** `userId` from the session/JWT, never the body (`05c §3.3`, `05h §3.3` — ⭐ **third appearance, it is clearly a scored item**) · offset pagination (`01b`) · cache-aside with TTL (`01e`) · polling vs WebSockets (`03a`, `05f`/`05g`) · DynamoDB GSI mechanics (`02f`) · Redis as a fast tier over a durable store (`05e §5.1`, `05h §5.1`). **Genuinely new:** ⭐⭐ **the isolation ladder and VM-vs-container kernel distinction** · ⭐⭐ **the five container security bounds (seccomp, read-only FS, network off)** · ⭐⭐ **the cross-language test-harness / serialization problem** · **CPU-bound capacity math** · **Redis ZSET as a leaderboard** · ⭐ **"the system is small, so don't over-engineer" as an explicit scoring axis** · **the job-ID + `GET /check/:id` polling shape (`03g`)**.

---

## 0 · Understanding the problem

🧑‍💻 **What is [LeetCode](https://leetcode.com/)?**

LeetCode is a platform that helps software engineers prepare for coding interviews. It offers a **vast collection of coding problems** from easy to hard, lets users **submit solutions and get feedback**, and **runs periodic coding competitions.**

---

## 1 · Requirements

### 1.1 Functional (what it does)

1. ⭐ **Users can view a list of coding problems.**
2. ⭐ **Users can view a given problem and code a solution in multiple languages.**
3. ⭐⭐ **Users can submit their solution and get instant feedback.**
4. ⭐ **Users can view a live leaderboard for competitions.**

⚠ **Below the line (out of scope):** user authentication · user profiles · payment processing · user analytics · social features.

- ⭐ **HI's standing assumption, state it and move on:** _"we can assume that users are already authenticated and that we have their user ID stored in the session or JWT."_

### 1.2 Non-functional (how it behaves)

1. ⭐⭐ **Availability over consistency** (`01h`). ▸ **The exact inverse of `05h` Tinder** — note the contrast out loud, it's cheap and it shows you know the axis is a choice.
2. ⭐⭐ **Isolation and security when running user code.** ▸ **This is the hard requirement of the problem.**
3. ⭐ **Submission results returned within 5 seconds.**
4. ⭐ **Scale to competitions with 100,000 users.**

⚠ **Below the line:** fault tolerance · secure transactions for purchases · CI/CD · regular backups.

- ⭐⭐ **Scale disclaimer — say it early:** **few hundred thousand users · ~4,000 problems** ⇒ _"a small-scale system"_ with **"a significant impact on our design."**

> ⊕ **Two notes (mine).**
> 
> - ⭐⭐ **Most load-bearing line in the file.** Every later rejection — microservices, WebSockets, vertical scaling, the queue — cites it. ▸ **State it in requirements, re-cite it on each rejection.**
> - ⚠ **Stale vs real LeetCode** (an order of magnitude higher). ⭐ **Use HI's number anyway** — the test is whether small scale changes your design.
> 
> ■ **— end of insert · HI write-up resumes below —**

### 1.3 ⭐⭐ The design driver — a hostile, CPU-bound subsystem bolted to a trivial CRUD app

▸ **Unlike every other problem in the series, the constraint is NOT data volume, read QPS, or contention.** ⭐⭐ **It is that you are running an adversary's code on your own hardware, on a clock.**

|Path|Volume|Needs|Therefore|
|---|---|---|---|
|**Problems list / view**|tiny — ~4,000 problems|nothing special|⭐ **a monolith + one NoSQL table** (§4.1)|
|⭐⭐ **Submit & execute**|10k concurrent at competition peak|⭐⭐ **isolation from hostile code** + **CPU parallelism** + **<5s**|**containers, bounded six ways, horizontally scaled behind a queue** (§4.3, §5.1, §5.3)|
|**Leaderboard**|100k pollers every 5s|**cheap repeated reads**|**Redis sorted set, written on submission** (§5.2)|

- ⭐⭐ **The two forces pulling against each other:** **security wants maximum isolation** (a full VM per submission) · **the 5s budget and cost want minimum isolation** (a warm shared process). ▸ **Containers are the answer because they sit exactly between the two** — kernel-level isolation at near-process start-up cost.
- ⚠ **And the trap:** the 5s NFR and the CPU math do not actually reconcile at peak. **See §5.3 and the ⊕ block there.** ⭐ **Raising this yourself is a senior move.**

### 1.4 Planning the approach

▸ **Build up sequentially through the functional requirements, then let the non-functional requirements drive the deep dives.** ▹ Identical step to `05e §1.4` / `05h §1.4`.

---

## 2 · Core Entities

- **Problem** — the problem statement, test cases, and expected output.
- **Submission** — the user's code submission and the result of running it against the test cases.
- **Leaderboard** — the leaderboard for a competition.

▹ ⭐ **HI deliberately omits User:** _"You can add User here too; many candidates do, but in general, I find this implied and not necessary to call out."_ ⚠ **Contrast `05h` Tinder, where User WAS listed — because there, users swipe on users.** ⭐ **The rule: include an entity only if the system does something _to_ it.**

---

## 3 · API

### 3.1 List problems

```
GET /problems?page=1&limit=100 -> Partial<Problem>[]
```

- ⭐ **`Partial<>` is borrowed from TypeScript** — only **title, id, level, and maybe tags/category.** ▸ **Not the full statement or code stubs.**
- ▹ **HI: _"How you short hand this is not important so long as you are clear with your interviewer."_**
- ⭐ **Pagination is justified, not decorative:** more problems than belong in one request or one page (`01b`).

### 3.2 View one problem

```
GET /problems/:id?language={language} -> Problem
```

- ⭐ **`language` is a query param with a default** (say python) **so the response carries the right code stub.**

### 3.3 Submit

```
POST /problems/:id/submit -> Submission
{
  code: string,
  language: string
}
```

- **`userId` from the session/JWT, not the API** — 3rd time (`05c §3.3`, `05h §3.3`). HI calls passing it a **red flag.**
- ⭐ **New here: timestamps too — server-generated.** ▸ **A client-supplied `submittedAt` lets a competitor rewrite their solve time.**

### 3.4 Leaderboard

```
GET /leaderboard/:competitionId?page=1&limit=100 -> Leaderboard
```

▹ ⚠ **Note: §5.2 later renames this to `GET /competitions/:competitionId/leaderboard?top=100`.** ⭐ **Harmless, but pick one and stay consistent on the whiteboard.**

### 3.5 ⊕ The endpoint that only appears in §5.3

```
GET /check/:id -> Submission | { status: "processing" }
```

> ⊕ ⭐⭐ **(mine, not HI) — this endpoint is the single biggest structural consequence in the file, and HI introduces it 300 lines late.**
> 
> - ▸ Once a queue sits between the API server and the runners, **`POST /submit` can no longer return results.** It returns a submission ID; the client polls `/check/:id` **every second** until done.
> - ⭐ **Say this at API-design time, not at deep-dive time:** _"I'll have submit return a submission ID and add a status endpoint, because execution is a long-running task"_ (`03g`). ▸ **Designing for it up front reads as experience; retrofitting it reads as a correction.**
> 
> ■ **— end of insert · HI write-up resumes below —**

---

## 4 · High-Level Design

> ⭐⭐ **The architecture decision HI makes first, and it is unique in the series.**
> 
> - ⭐ _"The majority of systems designed in interviews are best served with a microservices architecture… However, this isn't always the case. For smaller systems like this one, a **monolithic architecture might be more appropriate**… the overhead of managing multiple services isn't worth it."_
> - ▸ **So: a simple client-server architecture.** ⚠ **No API Gateway in this design** (`02d`) — unlike `05c`–`05h`.
> - ⭐ **Why it scores: it shows you size the architecture to the problem instead of reciting a template.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 4.1) Users can view a list of coding problems

```
Client ──► API Server ──► Primary DB (DynamoDB)
                            Problem
                              id · description · code stubs
                              test cases · metadata
```

- **API Server** — handles incoming requests and returns data. One endpoint so far.
- ⭐ **Database choice — DynamoDB** (`02f`). HI's reasoning, verbatim in substance: **_"we don't need complex queries and I plan to nest the test cases as a subdocument in the problem entity."_** ▹ **Either SQL or NoSQL would work; the nesting is the tiebreaker.**
- ⚠ **Must be indexed to support pagination.**

**The Problem schema:**

```json
{
  id: string,
  title: string,
  question: string,
  level: string,
  tags: string[],
  codeStubs: {
    python: string,
    javascript: string,
    typescript: string,
    ...
  },
  testCases: {
    type: string,
    input: JSON,
    output: JSON
  }[]
}
```

- ▹ ⭐ **On authoring the stubs:** manually entered by an admin, or _"in the modern day of LLMs, could be generated automatically given a single language example."_ ▸ **A cheap, current-sounding line to drop.**

### 4.2) Users can view a problem and code a solution

▸ `GET /problems/:id` returns the full statement and code stub. ⭐ **A Monaco Editor in the browser** gives the IDE. ▹ ⚠ _(HI's diagram misspells it "Manaco".)_

- ▹ **Nothing new in the backend here — one more read path on the same table.** ⭐ **Move through this in seconds.**

### 4.3) ⭐⭐ Users can submit their solution and get instant feedback

▸ **HI: _"it's been easy so far, but here is where things get interesting."_**

⚠ **The whole question is: where do you run hostile code?** ⭐⭐ **HI puts the full four-rung ladder here, in the HLD — not in a deep dive.** ▹ **Structurally unusual for the series; don't save it for later or you'll have nothing to say in §5.**

#### ⚠ Bad Solution — run it directly in the API server

- **Approach:** save the code to a file on the local filesystem, run it, capture the output. ⚠⚠ **HI: _"This is a terrible idea, don't do it!"_**
- ⚠ **Challenges:**
    - ⭐⭐ **Security.** _"Running user code on your server is a massive security risk."_ ▸ Concretely: **delete all your data · exfiltrate data to a third party · mine cryptocurrency · launch DDoS attacks.**
    - ⭐ **Performance.** Running code is **CPU intensive** and can **crash your server**, especially on an **infinite loop or memory leak.**
    - ⭐ **Isolation.** Same process as the API server ⇒ **the code crashes, your server goes with it, and no other requests are served.**

**Why climb:** the user's process must not be able to touch your process or your host.

#### Good Solution — a VM on the physical API server

- **Approach:** run the code in a **virtual machine** on the server. **An isolated environment that can be easily reset** if something goes wrong. ▸ **Even if the user's code crashes the VM, your server and other users are unaffected.**
- ⚠ **Challenges:**
    - ⭐ **VMs are resource intensive and slow to start up.**
    - **You must carefully manage them** so you aren't wasting resources, and can **spin up new ones quickly as needed.**
    - ⭐ **Lifecycle management** — running out of resources, or **leaving VMs running when they're not needed, which can prove costly.**

**Why climb:** the isolation is right but you're paying for a whole OS per submission, and the start-up cost eats the 5s budget.

#### ⭐⭐ Great Solution — containers (HI's choice)

- ⭐ **HI: _"A great (and arguably optimal) solution."_**
- ⭐⭐ **The VM-vs-container distinction — know this verbatim, it is the most likely follow-up in the whole question:**

||**VMs**|**Containers**|
|---|---|---|
|**Runs on**|physical hardware via a **hypervisor** (VMware, Hyper-V)|⭐⭐ **share the host system's kernel**|
|**Contains**|⭐ **a full copy of an OS** + app + binaries + libraries|**app + its dependencies, but NOT a full OS**|
|**Size / start-up**|**larger, slower to start**|⭐ **lightweight, faster start times**|
|**Isolation**|⭐ **fully isolated, entire OS stack — strong isolation and security**, with overhead|⚠ **less isolation than VMs**, but **more efficient on resources and scalability**|

- ⭐ **The design:** **one container image per runtime** (Python, JavaScript, Java) with its dependencies installed, running code in a sandbox. ⭐⭐ **And the efficiency move: _"Rather than spinning up a new VM for each user submission, we can reuse the same containers for multiple submissions."_**
- ⚠ **Challenges:**
    - ⭐⭐ **Because containers share the host kernel, you must properly configure and secure them to prevent users breaking out of the container and accessing the host.**
    - ⭐ **You must enforce resource limits** so no single submission consumes excessive resources and affects other users.
    - ▸ **HI defers both to §5.1.**

#### Great Solution (alternative) — serverless functions

- **Approach:** **small, stateless, event-driven functions** run in response to triggers, **managed by a cloud provider and auto-scaled on demand** — _"a great option for running code that is CPU intensive or unpredictable in terms of load."_ **One function per runtime**, triggered on submission.
- ⚠ **Challenges:**
    - ⭐⭐ **Cold start time**, which **introduces latency for the first request to a function.**
    - ⭐ **Resource limits** that can **impact long-running or resource-intensive code.**
- ⭐⭐ **HI's decision and the exact reasoning — rehearse this sentence:** _"While Serverless (lambda) functions are a great option, I am going to proceed with the container approach given **I don't anticipate a significant variance in submission volume** and **I'd like to avoid any cold start latency**."_
- ▹ ⭐ **Note the shape of that justification: one fact about the workload + one fact about the NFR.** ▸ **That's how to close any ladder.**

> ⭐ **Pattern: Managing Long Running Tasks** (`03g`) — **HI's only Pattern callout in this write-up.**
> 
> - HI: code execution takes several seconds as containers run user code against hundreds of test cases. **APIs immediately return job IDs while background workers handle time-consuming operations** — video transcoding, report generation, data processing — **preventing timeouts and enabling systems to scale.**
> 
> ⊕ ⚠⚠ **(mine) — the callout contradicts the flow HI draws directly beneath it.** ▸ The banner describes **returning a job ID**, but HI's own numbered flow below is **fully synchronous** (API server waits, then returns results). ⭐⭐ **The async job-ID design doesn't actually arrive until §5.3's third rung.** ▸ **In the room, resolve it the way the banner implies: go async at `POST /submit` from the start** (see §3.5).
> 
> ■ **— end of insert · HI write-up resumes below —**

**The flow HI gives (synchronous):**

1. **API Server** receives the code submission and problem ID and **sends it to the appropriate container for the language specified.**
2. ⭐ **The isolated container runs the code in a sandbox.** ⭐⭐ **The container itself makes no outbound calls** — _"the worker that manages the container invokes it synchronously (e.g. via Docker's exec API), waits for completion, and reads the output directly from stdout or a mounted volume."_
3. **API Server stores the submission results in the database** and **returns the results to the client.**

▹ ⭐ **Step 2 is a quietly important detail: the container is a pure function.** ▸ **Input in, output out, no network.** That's what makes §5.1's "disable network access" affordable.

### 4.4) Users can view a live leaderboard for competitions

▸ **First, pin down what a competition is** — ⭐ **HI defines it before designing it, and so should you:**

- **90 minutes long**
- **10 problems**
- **Up to 100k users**
- ⭐ **Scoring: the number of problems solved in the 90 minutes.** ⭐⭐ **Tie-break: the time it took to complete all 10 problems** (starting from competition start time).

▸ **The naive approach: query the submission table for the `competitionId`, group by `userId`, order by distinct problems solved.**

```sql
SELECT userId, COUNT(DISTINCT problemId) as numSolvedProblems, MIN(submittedAt) as lastSolveTime
FROM submissions
WHERE competitionId = :competitionId AND passed = true
GROUP BY userId
ORDER BY numSolvedProblems DESC, lastSolveTime ASC
```

- ⭐ **`COUNT(DISTINCT problemId)` is deliberate** — _"a user might submit multiple passing solutions for the same problem."_
- ⭐ **The DynamoDB equivalent** (`02f`): a **Global Secondary Index with `competitionId` as the partition key.** ▸ **Why a GSI and not the primary key:** _"competitionId… is optional and not unique."_ ⚠ **Then you pull the results into memory to group and sort.**
- **Freshness:** the client **re-requests every ~5 seconds.**

> ⊕ ⚠⚠ **(mine, not HI) — HI's SQL is wrong, and it's wrong in a way an interviewer may well catch.**
> 
> - ⚠ **The tie-break rule says "the time it took to complete all 10 problems" — that is the timestamp of a user's LAST passing solve.** ▸ **`MIN(submittedAt)` returns their FIRST.** ⭐ **It should be `MAX(submittedAt)`.**
> - ⚠ **And the alias `lastSolveTime` on a `MIN()` gives the bug away** — the name says what was intended, the function does the opposite.
> - ⭐ **As written, the query ranks tied users by who solved their easiest problem earliest.** ▸ **Say "I'd use MAX here, since the tiebreak is finish time" — it's a free, concrete catch.**
> 
> ■ **— end of insert · HI write-up resumes below —**

**Tying it together:**

1. User requests `/leaderboard/:competitionId`.
2. API server **queries the submission table for all successful submissions for the competition.**
3. **Whether via the query itself or in memory**, rank users by **distinct problems solved, ties broken by solve time.**
4. **Return the leaderboard.**
5. **The client requests again after 5 seconds.**

- ⚠ ⭐ **HI flags its own design immediately:** _"Astute readers will realize this solution isn't very good as it will put a significant load on the database. We'll optimize this in a deep dive."_ ▸ **Do the same — build the naive version, name its flaw, defer it.**

---

## 5 · Deep Dives

▹ ⭐ **HI's framing on who drives:** mid-level candidates can let the interviewer lead the dives; **senior and staff+ are expected to _"proactively anticipate challenges and identify potential issues with their design, while suggesting solutions."_**

### 1) How will the system support isolation and security when running user code? ⭐⭐

▸ **Containers already did the heavy lifting. This dive is five named bounds on top.** ⚠ **Not a ladder — a checklist.**

|Bound|What it does|
|---|---|
|⭐ **Read-only filesystem**|**Mount the code directory read-only**; write output to a **temp directory deleted shortly after completion.**|
|⭐ **CPU and memory bounds**|Limits on the container; **exceeded ⇒ the container is killed**, preventing resource exhaustion.|
|⭐⭐ **Explicit timeout**|**Wrap the user's code in a timeout** that kills the process past a limit, **say 5 seconds** — ▸ **stops infinite loops AND _"help[s] us meet our requirement of returning submission results within 5 seconds."_**|
|⭐ **Limit network access**|**Disable network access in the container** so no external calls. ▸ **In AWS: VPC Security Groups and NACLs restricting all inbound/outbound except predefined essential connections.**|
|⭐ **No system calls (seccomp)**|**Restrict the syscalls the container can make**, so users can't compromise the host.|

- ⭐⭐ **HI's calibration on depth — this is the actionable part of the dive:** _"you're likely not expected to go into a ton of detail on how you'd implement each of these… To be concrete, this means just saying, **'We'd use docker containers while limiting network access, setting CPU and memory bounds, and enforcing a timeout on the code execution'** is likely sufficient."_
- ▹ ⭐ **So: say the sentence, then stop talking.** **If the interviewer wants seccomp, they'll ask.**

> ⊕ ⚠ **(mine) — one bound HI omits that is worth naming if you're asked to go deeper.**
> 
> - ⚠ **Nothing above stops a fork bomb.** CPU and memory caps don't bound **process count**; `--pids-limit` (a PID cgroup cap) does. ▸ **Also worth a word: drop all Linux capabilities and run as a non-root user inside the container.**
> - ⭐ **Offer HI's five first.** This is a bonus for a follow-up, not a replacement.
> 
> ■ **— end of insert · HI write-up resumes below —**

### 2) How would you make fetching the leaderboard more efficient? ⭐

▸ **The §4.4 design is _"far too inefficient."_**

#### ⚠ Bad Solution — poll the database directly (the status quo)

- **Approach:** all submission results in the main DB. **Clients poll every few seconds**; each poll **queries the DB for the top N users, sorts, returns.**
- ⚠ **Challenges:**
    - ⭐ **High database load from frequent queries**, and **increased latency as the number of users grows.**
    - **Doesn't scale for real-time updates**, especially during competitions with many participants.
    - ⭐⭐ _"This approach would put an enormous strain on the database… the database would struggle to keep up, especially during peak times or competitions."_ ▸ **Frequent querying and sorting also consumes significant computational resources.**
- ▹ ⚠ **HI says this works better on a relational DB but still falls over.**

> ⊕ ⚠ **(mine) — a numeric slip to ignore, same class as `05h`'s 100-vs-200 swipes.**
> 
> - ⚠ **HI writes _"each user poll triggering a query for a million records every 5 seconds"_**, but the stated competition scale is **100k users**, and the whole platform is "a few hundred thousand." ▸ **The million is rhetorical.** ⭐ **Use 100k; it's the number in the NFR.**
> 
> ■ **— end of insert · HI write-up resumes below —**

**Why climb:** every poll re-does identical work. Do the work once and share the result.

#### Good Solution — a periodically-refreshed cache

- **Approach:** **a cache (e.g. Redis) stores the current leaderboard**, refreshed **every ~30 seconds** by querying the DB. **Client polls hit the cache, not the DB** (`01e`).
- ⚠ **Challenges:**
    - ⭐ **Updates are only as fresh as the 30-second refresh**, and **clients still poll to pick them up.**
    - **Potential for race conditions if the cache update frequency is too low.**
- ✅ ⭐ **HI's own verdict: _"a significant improvement over the previous approach and could work well for smaller-scale competitions."_**

**Why climb:** the cache is still rebuilt by the expensive query. Make the leaderboard a structure you _update on write_ instead of _recompute on a timer_.

#### ⭐ Great Solution — Redis sorted set, written on submission

- **Approach:** ⭐⭐ **on each processed submission, write BOTH the main database AND a Redis sorted set.** **Clients poll every 5s; the server returns the top N from the ZSET** — _"wicked fast and requires no expensive database queries."_
- ⭐ **Why a ZSET** (`02a`): an in-memory structure that **stores and retrieves data by score**, so you can **update a user's score and retrieve the top N** directly.

```
Key:    competition:leaderboard:{competitionId}
Score:  the user's total score or solve time
Member: userId

Write:  ZADD   competition:leaderboard:{competitionId} {score} {userId}
Read:   ZRANGE competition:leaderboard:{competitionId} 0 N-1 REV WITHSCORES
API:    GET /competitions/:competitionId/leaderboard?top=100
```

- ▹ ⭐ **HI's version note, worth knowing:** **`ZREVRANGE` is deprecated as of Redis 6.2** in favour of **`ZRANGE` with the `REV` flag.**
- ⭐ **Paging:** send **the first couple of pages (maybe the top 1,000)** up front, then **fetch further pages from the server as the user scrolls.**
- ✅ **Benefits:** ⭐ **simpler than WebSockets while still near-real-time** · **the 5-second delay is generally acceptable** · **significantly reduces load on the main database** · **scales well for the expected user base.**

> 💬 **My question → HI Tutor (verbatim answer):** _"So you mean by key will be only one, feed user one, and here Redis keys competition leaderboard com 01:23, and then there are, after key there is a member, member is like again sub key with value, which is score. That is how it works?"_
> 
> Yes. That is the right mental model, with one small wording change. **A Redis sorted set has one Redis key, then many members, and each member has one numeric score. The members are not separate Redis keys.**
> 
> ```
> Redis key
> competition:leaderboard:comp_123
> 
> Sorted-set entries
> user_1  -> score 300
> user_9  -> score 250
> user_4  -> score 100
> ```
> 
> So `competition:leaderboard:comp_123` is the **only** Redis key here. `user_1` is a member, and 300 is its score. **Redis keeps all members ordered by score automatically.**
> 
> ▹ **Also from the Tutor — the `05f` contrast:** _"This is similar to Instagram's `feed:user_1` ZSET, but the meaning changes. In a feed, postId is the member and createdAt is the score. In a leaderboard, userId is the member and a ranking score is the score."_
> 
> ■ **— end of insert —**

> ⊕ ⭐⭐ **(mine) — three consequences of "one key, many members, one score each."**
> 
> ||member|score|
> |---|---|---|
> |`05f` feed — `feed:user_1`|postId|**createdAt — handed to you**|
> |`05i` leaderboard — `competition:leaderboard:{cid}`|userId|⭐⭐ **a ranking score you must construct**|
> 
> - ⭐ **`ZADD` on an existing member OVERWRITES its score — it does not append.** ▸ Solve your 4th problem ⇒ recompute, `ZADD` again, same member. **No duplicates, no cleanup.**
> - ⭐⭐ **Redis orders on WRITE, not on read.** ▸ `ZRANGE … REV` is a slice of an already-sorted structure — **no sort at request time.** ⭐ **That is the whole win over §4.4's `ORDER BY`.**
> - ⚠⚠ **One score per member is a hard constraint** — ▸ **which is exactly why the composite formula below is needed.** You cannot keep "4 solved" and "finished at 71:20" as two fields. **One float; encode both.**
> 
> ■ **— end of insert · HI write-up resumes below (the ⊕ holes in HI's ZSET design) —**

> ⊕ ⚠⚠ **(mine, not HI) — HI's ZSET design does not actually implement HI's own scoring rule. Two holes, and the second one is a real bug.**
> 
> **Hole 1 — a ZSET score is ONE float, but the ranking needs two keys.** HI says _"the score being the user's total score **or** solve time"_ and never resolves the _or_. ⭐ **Encode both into one number:**
> 
> ```
> score = solvedCount * 10_000_000 + (COMPETITION_SECONDS - secondsOfLastSolve)
> # 90 min ⇒ time term is 0…5400, far below the 10^7 multiplier
> # max 10 * 10^7 = 10^8, exact in a float64 (safe to 2^53)
> # higher = better, so ZRANGE … REV sorts correctly on both keys at once
> ```
> 
> **Hole 2 — ⚠⚠ `ZADD` alone silently breaks `COUNT(DISTINCT problemId)`.** ▸ HI's own SQL uses `DISTINCT` _because users re-submit passing solutions to the same problem._ **A bare `ZADD` per passing submission has no idea whether that problem was already solved.** ⭐ **Fix: keep a per-user set and only bump the ZSET on first solve —**
> 
> ```
> SADD comp:{cid}:user:{uid}:solved {problemId}   -- returns 1 only the first time
> if result == 1 then recompute score; ZADD ... end   -- both in one Lua script
> ```
> 
> - ⭐⭐ **Worth raising unprompted.** ▸ **It's the same shape as `05h`'s Lua atomicity** — Redis decides, the durable store remembers.
> 
> ■ **— end of insert · HI write-up resumes below —**

> ⭐⭐ **HI on WebSockets — the most transferable paragraph in the file.**
> 
> - ⚠ **Many candidates propose WebSockets for real-time updates** (`03a`). _"While this isn't necessarily wrong, they would be **overkill** for our system given the modest number of users and the acceptable 5-second delay."_
> - ⭐ **The Redis ZSET + polling solution _"strikes a good balance between real-time updates and system simplicity."_**
> - ⭐ **The tuning idea worth stealing — progressive polling:** poll **every 2 seconds in the last few minutes of a competition** and **every 10 seconds otherwise.** ▹ **Same shape as `05h §5.2`'s tunable-parameters principle.**
> - ⭐⭐ **And the scoring line, say it almost verbatim:** _"Staff candidates in particular are effective at striking these balances. They **articulate that they know what the more complex solution is, but they are clear about why it's likely overkill** for the given system."_
> 
> ■ **— end of insert · HI write-up resumes below —**

### 3) How would the system scale to support competitions with 100,000 users? ⭐⭐

▸ **The concern: a sudden traffic spike overwhelms the containers running user code.** ⭐ **HI's framing: _"100k is still not a lot of users, and our API server, via horizontal scaling, should be able to handle this load without any issues. However, given code execution is CPU intensive, we need to be careful about how we manage the containers."_**

#### ⚠ Bad Solution — vertical scaling

- **Approach:** **run the containers on a larger instance type with more CPU and memory.** ⭐ **The simplest way to add capacity.**
- 📐 ⭐⭐ **HI does the math here, and the math is the entire rejection:**
    - **Peak: ~10k simultaneous submissions** (a competition), **~100 test cases each.**
    - **Conservative: 100ms per test case** _(in practice most finish in 10–50ms)_.
    - ⇒ **each submission up to 10s worst case** _(typical submissions land within the 5s target)_.
    - ⇒ **10k × 100 = 1,000,000 test cases × 100ms = 100,000 seconds** = ⭐ **over 27 hours** serial.
    - ⇒ ⭐⭐ **~1,667 CPU cores to clear it within one minute.**
- ⚠ **Challenges:**
    - ⭐⭐ **Not viable — _"even the largest AWS instance types top out at a few hundred vCPUs."_**
    - ⭐ **And the cost point:** _"it's not easy to vertically scale dynamically so we'd have a big expensive machine sitting around most of the time not doing much. Big waste of money!"_

> ⊕ ⚠⚠ **(mine, not HI) — HI's own math quietly abandons HI's own NFR, and this is the best thing in the file to raise unprompted.**
> 
> - ⚠ **The 1,667 figure is sized to clear the backlog in 60 seconds.** **NFR #3 says 5 seconds.** ⭐ **At 5s the same arithmetic gives `100,000 ÷ 5 = ~20,000 cores.`**
> - ⚠ **And the per-submission number breaks the §5.1 timeout:** 100 test cases × 100ms = **10s**, but §5.1 kills any execution at **5s.** ▸ **Under HI's own conservative assumption, a correct solution gets killed.**
> - ⭐⭐ **How to play it:** give HI's math, then say — _"note the 5-second NFR can't hold at true peak; I'd either relax it to a p50 target with a queued-wait caveat, or cut per-case cost, since 10–50ms is realistic."_ ▸ **Spotting that your own number violates your own requirement is exactly the proactivity HI says separates senior from mid.**
> 
> ■ **— end of insert · HI write-up resumes below —**

**Why climb:** you need ~1,667 cores. No single machine has them, and you don't want them idle between competitions.

#### Good Solution — horizontal scaling with auto-scaling

- **Approach:** ⭐ **horizontally scale each language-specific container** — **multiple containers per language, submissions distributed across them.** ▸ **Managed by auto-scaling groups that adjust instance count in response to traffic, CPU utilization, or memory metrics.** ⭐ **In AWS: ECS + ECS Auto Scaling.**
- ⚠ **Challenges:**
    - ⭐ **Risk of over-provisioning** — too many containers wastes resources and incurs unnecessary cost.
    - ✅ **But: _"modern cloud providers make it easy to scale up and down based on demand, so this is a manageable risk."_**

**Why climb:** auto-scaling reacts _after_ the spike arrives. A buffer absorbs the spike while the scaler catches up — and gives you retries for free.

#### ⭐ Great Solution — horizontal scaling + a queue (HI's choice, with a caveat)

- **Approach:** **the same as above, plus a queue between the API server and the containers.** ⭐ **Buffers submissions during peak times so the containers aren't overwhelmed.** ▸ **A managed service like SQS.**
    - **API server puts the submission on the queue; containers pull submissions off as they become available.**
    - ⭐ **Once the worker has results, it notifies the App Server, which updates both the database and the cache.**
- ⭐⭐ **The structural consequence — the system is now asynchronous** (`03g`): **`POST /submit` can no longer return results.** ▸ **New endpoint `GET /check/:id`, polled every second by the client**, which **looks up the submission and returns results if ready, or a "processing" message if not.**
- ▹ ⭐ **WebSockets rejected a second time:** _"This could certainly work, but it adds complexity… and is likely not necessary given the polling interval is only a second."_
- ⭐ **HI's verification tip, and it's a great line to drop:** _"Fun fact, this is exactly what LeetCode does when you submit a solution… Click submit with your network tab open and you'll see the polling in action!"_
- ⚠ **Challenges — HI argues against its own choice:**
    - ⭐⭐ _"There could be a really strong case made that this is **overengineering** and adding unnecessary complexity."_ ▸ **At this scale you could handle the load without a queue**, and **if users register for competitions you'd know when peak traffic is coming and could scale up in advance.**
- ⭐⭐ **HI picks it anyway, and the justification is the lesson:** _"I would still opt for this approach with my main justification being that **it also enables retries in the event of a container failure**… We'd simply requeue the submission and try again."_ ▸ **Plus the buffer means no submissions are lost in a sudden spike.**
- ⭐ **And the closing calibration:** _"There is no right or wrong answer here, **weighing the pros and cons of each approach is really the key** in the interview."_

> ⊕ ⭐ **(mine) — why SQS and not Kafka** (`02c`)**, if asked.**
> 
> - ▸ **This is a work queue, not an event log.** You want **per-message ack, visibility timeout, and automatic redelivery on worker death** — SQS gives those directly. ⭐ **A Kafka partition gives you an ordered, replayable log with consumer-group offsets, which is the wrong shape:** one slow submission would head-of-line block its partition.
> - ⭐ **Say it in one line, don't lecture:** _"SQS over Kafka — I want per-message retry semantics, not an ordered replayable log."_
> 
> ■ **— end of insert · HI write-up resumes below —**

### 4) ⭐⭐ How would the system handle running test cases?

> ⭐⭐ **HI's own framing — this is why the dive exists:** _"One follow up question I like to ask is, 'How would you actually do this? How would you take test cases and run them against user code of any language?' **This breaks candidates out of 'box drawing mode'** and forces them to think about the actual implementation of their design."_

- ⚠ **The thing you must NOT propose:** _"You definitely don't want to have to write a set of test cases for each problem in each language. That would be a nightmare to maintain."_
- ⭐⭐ **The answer, in two parts:**
    1. ⭐ **One set of test cases per problem, in a standard serialized form**, language-agnostic.
    2. ⭐⭐ **A test harness per language** which **deserializes the input, passes it to the user's code, and compares the output to the deserialized expected output.**

**HI's worked example — max depth of a binary tree:**

```python
# Definition for a binary tree node.
# class TreeNode(object):
#     def __init__(self, val=0, left=None, right=None):
#         self.val = val
#         self.left = left
#         self.right = right
class Solution(object):
    def maxDepth(self, root):
        """
        :type root: TreeNode
        :rtype: int
        """
```

▸ **The function takes a `TreeNode` object, so the container must already hold a `TreeNode` file in the same directory as the user's code.** ⭐ **Take the serialized test-case input, deserialize it into a `TreeNode`, pass it to the user's code.**

```json
{
  "id": 1,
  "title": "Max Depth of Binary Tree",
  ...
  "testCases": [
    { "type": "tree", "input": [3,9,20,null,null,15,7], "output": 3 },
    { "type": "tree", "input": [1,null,2],              "output": 2 }
  ]
}
```

- ⭐⭐ **The serialization choice, stated explicitly:** _"For a Tree object, we've decided to serialize it into an array using **level-order (BFS) traversal**."_ ▸ **Each language has its own `TreeNode` class that deserializes this array.**
- ⭐ **The general rule:** **define a serialization strategy per data structure**, and **ensure each language's harness can deserialize the input and compare the output.**
- ▹ ⭐ **This is also what the `type` field in the schema is for** — `"type": "tree"` tells the harness which deserializer to use.

> ⊕ ⭐ **(mine) — one sentence to add that shows you've thought past HI.**
> 
> - ⚠ **Output comparison is not always equality.** ▸ **Some problems have multiple valid answers** (any valid anagram grouping, any shortest path of equal length) **and some return unordered collections.** ⭐ **So the test case needs a comparator type alongside the serializer type** — `exact` · `unordered` · `custom validator`.
> - ▹ **Mention it only if the interviewer stays on this dive** — it's a bonus, not part of HI's answer.
> 
> ■ **— end of insert · HI write-up resumes below —**

---

## 6 · Final Design

```
Client  (Monaco IDE in browser)
  │   GET  /problems?page&limit
  │   GET  /problems/:id?language
  │   POST /problems/:id/submit        ──► returns submission id (async)
  │   GET  /check/:id                  ──► polled every ~1s          03g
  │   GET  /leaderboard/:compId        ──► polled every ~5s          03a
  ▼
Primary Server  (⭐ monolith — small system, no gateway, no microservices)
  │
  ├──► Primary DB (DynamoDB)                                          02f
  │       Problem     : id · description · codeStubs · testCases · metadata
  │       Submission  : id · competitionId · submittedAt
  │                     testCaseResults · runtime · error?
  │       ⭐ GSI on competitionId  (leaderboard fallback query)
  │
  ├──► Redis                                                          02a
  │       ⭐ Leaderboard sorted set
  │         key   competition:leaderboard:{competitionId}
  │         ZADD on first solve · ZRANGE … REV for top N
  │         ⊕ composite score = solved·10^7 + (5400 − lastSolveSec)
  │         ⊕ SADD comp:{cid}:user:{uid}:solved  ⇒ enforces DISTINCT
  │
  └──► AWS SQS  (⭐ buffer + retries — "likely overkill, kept for retries")
          │
          ▼
       Worker ──► AWS Fargate / Docker containers
          │         Java Runtime Service
          │         Python Runtime Service
          │         JavaScript Runtime Service
          │         X Runtime Service
          │
          │       ⭐ On the box:
          │         - configured runtime environments
          │         - test harnesses (deserialize + compare)      §5.4
          │         - data-structure classes + language deps
          │
          │       ⭐ Security:                                     §5.1
          │         - Docker for isolation (shared kernel)
          │         - read-only filesystem (writes to tmp)
          │         - CPU and memory bounds
          │         - explicit timeout per execution (~5s)
          │         - VPC / security groups — no network access
          │         - no system calls (seccomp)
          │
          └──► writes submission data back ──► Primary DB + Redis
```

▹ ⭐ **Worth noting on the whiteboard: the container is a pure function** — the worker invokes it synchronously via Docker's exec API and reads stdout or a mounted volume. **The container never calls out.**

---

## 7 · Expected at Each Level

|Level|The bar for LeetCode|
|---|---|
|**Mid (IC4)**|⭐ **API endpoints and data model clearly defined**; a **functional HLD that meets the requirements.** ⭐⭐ **Must have understood the need for security and isolation when running user code**, and **proposed either a container, VM, or serverless approach.** ▹ No depth expected on how any of them work.|
|**Senior (IC5)**|⭐ **Speed through the HLD** to spend time on **running user code securely and in isolation.** ⭐⭐ **Must be able to argue container vs VM vs serverless and justify the choice.** ⭐⭐ **Must break out of box-drawing mode and explain how test cases actually run against user code** (§5.4).|
|**Staff+**|⚠ ⭐ **HI doesn't normally ask this question at staff+ — _"it is on the easier side."_** If asked: **drive the whole conversation**, proactively surface issues, **justify trade-offs**, cover both §5.1 and §5.4 **while meeting the 5s requirement**, and ⭐⭐ **"design a very simple system free of over engineering, but with a clear path to scale if needed."**|

---

## Quick Recall (pass 3+)

|Use / Question|LeetCode answer|
|---|---|
|Calibration|⭐ Evan King · Feb 2026 · **"medium"** · ⭐ **Whatnot, LinkedIn (+3 unnamed)** · ⭐ **one Pattern: Managing Long Running Tasks (`03g`)** · ⚠ **easiest in the series — HI: _"on the easier side"_, not asked of staff+.** ⭐⭐ **ONE pass only.** Score points: **isolation ladder** · **test-harness question** · **CPU math** · **ZSET leaderboard** · **monolith** · ⭐⭐ **restraint — rejecting WebSockets/vertical/microservices with reasons**|
|⭐⭐ Design driver|**a hostile, CPU-bound subsystem bolted to a trivial CRUD app.** ⭐ **Not volume, not QPS, not contention** — **you're running an adversary's code on your hardware, on a 5s clock.** **Security wants max isolation (VM); latency + cost want min (warm process); ⭐⭐ containers sit exactly between** — kernel isolation at near-process startup cost|
|FRs|**list problems** · **view a problem + code in multiple languages** · ⭐⭐ **submit and get instant feedback** · **live competition leaderboard.** Below: auth · profiles · payments · analytics · social|
|NFRs|⭐ **availability > consistency** (⚠ **inverse of `05h` Tinder — say so**) · ⭐⭐ **isolation + security running user code** · **results < 5s** · **100k-user competitions.** Below: fault tolerance · secure purchases · CI/CD · backups|
|⭐⭐ The scale disclaimer|_"a few hundred thousand users and roughly **4,000 problems**… a **small-scale system**. Keep this in mind as it will have a significant impact on our design."_ ⭐⭐ **Most load-bearing sentence in the file — every later rejection cites it.** ⊕ factually stale vs real LeetCode; **use HI's number anyway**|
|📐 The one calculation|**10k concurrent subs × ~100 test cases = 1M cases × 100ms = 100,000 CPU-s ≈ 27.8 h serial ⇒ ~1,667 cores in 60s.** ⊕ ⚠⚠ **HI budgets 60s, not its own 5s NFR — at 5s it's ~20,000 cores.** ⊕ ⚠ **and 100×100ms = 10s per submission, which §5.1's 5s timeout would kill.** ⭐ **Raise both**|
|Entities|**Problem · Submission · Leaderboard.** ⭐ **HI deliberately omits User** — _"implied and not necessary to call out."_ ⚠ **contrast `05h`, which included it because users swipe on users.** ▸ **rule: include an entity only if the system acts on it**|
|API|`GET /problems?page&limit → Partial<Problem>[]` · `GET /problems/:id?language` · `POST /problems/:id/submit {code, language}` · `GET /leaderboard/:compId?page&limit` · ⊕ `GET /check/:id` (§5.3). ⭐ **`Partial<>` = title, id, level, tags only**|
|⚠⚠ API security (3rd time)|**no `userId` in body or query — session/JWT only.** ⭐ **New vs `05c`/`05h`: _"timestamps should be generated by the server"_** ▸ **else a competitor rewrites their solve time.** HI calls client-supplied userId **"a red flag"**|
|⭐⭐ Monolith, not microservices|**the only problem in the series where HI rejects microservices.** _"For smaller systems like this one, a monolithic architecture might be more appropriate… the overhead of managing multiple services isn't worth it."_ ⚠ **no API Gateway here** (`02d`), unlike `05c`–`05h`|
|DB choice|⭐ **DynamoDB** (`02f`) — _"we don't need complex queries and I plan to **nest the test cases as a subdocument**."_ ▹ **SQL would also work; the nesting is the tiebreaker.** ⚠ **must be indexed for pagination**|
|⚠ Exec Bad — run in API server|⚠⚠ _"This is a **terrible idea, don't do it**!"_ **(1) Security** — delete data · exfiltrate to third party · **mine crypto** · **launch DDoS. (2) Performance** — CPU-intensive, infinite loops, memory leaks crash the server. **(3) Isolation** — same process ⇒ crash takes the server and all other requests down|
|Exec Good — VM|**isolated env on the server, easily reset; crash doesn't affect host or other users.** ⚠ **resource intensive · slow to start · lifecycle management · leaving VMs running is costly**|
|⭐⭐ Exec Great — containers|_"A great (and **arguably optimal**) solution."_ ⭐⭐ **VM = hypervisor + full OS copy ⇒ larger, slower, strong isolation. Container = shares the host kernel, app + deps but no OS ⇒ lightweight, fast start, LESS isolation, more efficient.** ⭐ **one image per runtime; reuse containers across submissions.** ⚠ **shared kernel ⇒ must prevent breakout + enforce resource limits** → §5.1|
|Exec Great (alt) — serverless|**stateless, event-driven, provider-managed, auto-scaling; one function per runtime.** ⚠ **cold start latency · resource limits.** ⭐⭐ **HI's rejection line to rehearse: _"I don't anticipate a significant variance in submission volume and I'd like to avoid any cold start latency."_** ▸ **one workload fact + one NFR fact = how to close any ladder**|
|⊕⚠⚠ Pattern banner contradicts HLD|**the `03g` callout says "APIs immediately return job IDs," but HI's flow right below it is fully synchronous.** ⭐ **Async doesn't arrive until §5.3's 3rd rung.** ▸ **Resolve it by going async at `POST /submit` from the start**|
|⭐ Container is a pure function|**worker invokes it synchronously via Docker's exec API, waits, reads stdout or a mounted volume.** ⭐ **The container makes NO outbound calls** — which is what makes "disable network access" affordable|
|Competition definition|⭐ **90 minutes · 10 problems · up to 100k users.** **Score = problems solved; tie-break = time to complete all 10 from competition start.** ▸ **define it before designing it**|
|⊕⚠⚠ HI's leaderboard SQL is wrong|**tie-break is FINISH time ⇒ should be `MAX(submittedAt)`, HI wrote `MIN`** — ⭐ **and aliased it `lastSolveTime`, which gives the bug away.** ⚠ **As written it ranks ties by who solved their easiest problem earliest.** ⭐ **free, concrete catch**|
|DynamoDB leaderboard query|⭐ **GSI with `competitionId` as partition key** — needed **because `competitionId` is optional and not unique**, so it can't be the table's primary key. ⚠ **then group + sort in memory.** ⭐ `COUNT(DISTINCT problemId)` **because users re-submit passing solutions**|
|⚠ DD2 Bad — poll the DB|**every client poll re-queries + re-sorts.** ⚠ **high DB load · latency grows with users · doesn't scale for real-time · _"enormous strain on the database."_** ⊕ ⚠ **ignore HI's "a million records" — the NFR says 100k**|
|DD2 Good — periodic cache|**Redis holds the leaderboard, refreshed every ~30s from the DB** (`01e`). ⚠ **only as fresh as the refresh · clients still poll · race conditions if refresh is too slow.** ✅ **"could work well for smaller-scale competitions"**|
|⭐ DD2 Great — Redis ZSET|**write DB + ZSET on each processed submission.** `ZADD competition:leaderboard:{cid} {score} {userId}` · `ZRANGE … 0 N-1 REV WITHSCORES`. ▹ **`ZREVRANGE` deprecated since Redis 6.2.** ⭐ **send top ~1,000 up front, page the rest.** ✅ **simpler than WebSockets · 5s delay fine · big DB load reduction**|
|💬 ZSET structure|⭐⭐ **ONE Redis key per competition; many members, one numeric score each. Members are NOT keys.** ⭐ **`ZADD` on an existing member OVERWRITES, doesn't append** ⇒ no duplicates, no cleanup. ⭐⭐ **Redis orders on WRITE ⇒ `ZRANGE … REV` is a slice of an already-sorted structure, no sort at read time** — **the whole win over §4.4's `ORDER BY`.** ⚠⚠ **one score per member is a HARD constraint ⇒ the composite formula is forced.** ▹ **vs `05f`: `feed:user_1` member=postId, score=createdAt (handed to you); here member=userId, score=⭐ one you must construct**|
|⊕⚠⚠ Two holes in HI's ZSET|**(1) a ZSET score is ONE float but ranking needs TWO keys** ⇒ ⭐ **composite: `solved·10^7 + (5400 − lastSolveSec)`**, exact in float64, `REV` sorts both at once. **(2) ⚠⚠ bare `ZADD` breaks HI's own `COUNT(DISTINCT)`** — re-submits double-count ⇒ ⭐ **`SADD comp:{cid}:user:{uid}:solved {pid}`, bump the ZSET only when it returns 1, both in one Lua script.** ▸ **same shape as `05h`'s Lua atomicity**|
|⭐⭐ WebSockets rejected (×2)|**DD2:** _"overkill… given the modest number of users and the acceptable 5-second delay."_ **DD3:** _"adds complexity and is likely not necessary given the polling interval is only a second."_ ⭐ **progressive polling: 2s in the final minutes, 10s otherwise.** ⭐⭐ **the scoring line: staff candidates _"articulate that they know what the more complex solution is, but they are clear about why it's likely overkill."_**|
|⚠ DD3 Bad — vertical|**bigger instance.** ⚠⚠ **_"even the largest AWS instance types top out at a few hundred vCPUs"_ vs ~1,667 needed.** ⚠ **can't scale dynamically ⇒ _"a big expensive machine sitting around most of the time… Big waste of money!"_**|
|DD3 Good — horizontal|**multiple containers per language, submissions distributed; auto-scaling groups on traffic/CPU/memory metrics; AWS ECS + ECS Auto Scaling.** ⚠ **over-provisioning risk**, ✅ **but easy to scale down ⇒ manageable**|
|⭐ DD3 Great — + SQS queue|**queue between API server and containers; workers pull; worker notifies App Server which updates DB + cache.** ⭐⭐ **makes the system ASYNC** ⇒ **`GET /check/:id` polled every 1s, returns results or "processing"** (`03g`). ⭐ **_"this is exactly what LeetCode does — click submit with your network tab open."_** ⚠⚠ **HI's own objection: _"a really strong case… that this is overengineering"_** — could handle load without it, and registration reveals peak in advance. ⭐⭐ **HI picks it anyway for RETRIES on container failure + no lost submissions.** _"There is no right or wrong answer here"_|
|⊕ SQS not Kafka|⭐ **work queue, not event log** — want **per-message ack, visibility timeout, redelivery on worker death.** ⚠ **a Kafka partition is ordered + replayable ⇒ one slow submission head-of-line blocks it** (`02c`)|
|⭐⭐ DD4 — the test harness|⭐⭐ **HI's purpose: _"This breaks candidates out of 'box drawing mode'."_** ⚠ **never write test cases per problem per language — _"a nightmare to maintain."_** ⭐ **One serialized set per problem + one harness per language** that **deserializes input, calls user code, compares to deserialized expected output.** ⭐ **Tree ⇒ serialized as a level-order (BFS) array `[3,9,20,null,null,15,7]`**; each language has its own `TreeNode` deserializer sitting in the container next to the user's code. ⭐ **the `type` field picks the deserializer.** ⊕ **also needs a comparator type — `exact` / `unordered` / custom — since some problems accept multiple valid answers**|
|⭐ DD1 — security, 5 bounds|**read-only FS (writes to deleted tmp) · CPU + memory limits (exceed ⇒ killed) · explicit timeout ~5s (kills infinite loops AND meets the NFR) · no network (VPC security groups + NACLs) · seccomp (no syscalls).** ⭐⭐ **HI's depth calibration: one sentence is enough** — _"We'd use docker containers while limiting network access, setting CPU and memory bounds, and enforcing a timeout."_ **Then stop talking.** ⊕ **omitted: `--pids-limit` (fork bombs), drop capabilities, non-root user**|
|⭐⭐ The meta-lesson|**this file's scoring axis is RESTRAINT.** **Rejected with reasons: microservices · vertical scaling · WebSockets (×2) · and HI's own chosen queue, called "likely overkill."** ⭐⭐ **Name the sophisticated solution, then reject it with a specific reason. Reusable in every design interview**|
|Levels (short)|**IC4:** API + data model + functional HLD; ⭐⭐ **must grasp isolation/security and propose container, VM, or serverless** · **IC5:** fast HLD, then **container vs VM vs serverless justified**, and ⭐⭐ **break out of box-drawing mode on test harnesses** · **Staff+:** ⚠ **rarely asked — "on the easier side"**; drive it all, ⭐⭐ **"a very simple system free of over engineering, but with a clear path to scale"**|

---

> 🔗 **HI source:** https://www.hellointerview.com/learn/system-design/problem-breakdowns/leetcode
> 
> ⚠ **Source complete in substance, with three paste artifacts to be aware of — nothing was filled in from my own knowledge:**
> 
> 1. ⚠ **Option/rung LABELS are missing.** HI renders the ladders as tabbed cards; the paste carries the `Approach` / `Challenges` bodies but **not the tab titles.** The rung names in §4.3, §5.2 and §5.3 (**"run in the API server", "VM", "containers", "serverless"; "poll the DB", "periodic cache", "Redis sorted set"; "vertical", "horizontal", "+ queue"**) are **my labels, taken from the body text.** The content under each is HI's, verbatim in substance. **If a label is off, it's mine, not HI's.**
> 2. ⚠ **Diagram text is flattened.** HI's architecture diagrams arrived as loose lines (`Client / - Simple Manaco IDE / GET /problems / …`). **The §6 ASCII diagram is my reconstruction from those fragments** plus the component lists. **The components, labels and security bullets are HI's; the arrows and layout are mine.**
> 3. ▹ **Two non-content omissions:** the `+3` additional companies under "Asked at" are **not named in the source**, and the closing **"Test Your Knowledge"** quiz carries no design content.
> 
> ✅ **Reconciled against the original:** all 4 FRs and 4 NFRs with both below-the-line lists · the planning step · entities · all 4 API endpoints plus `/check/:id` · the monolith decision · all four HLD sections · the four-rung execution ladder with every challenge listed · the Pattern callout · the competition definition and leaderboard SQL · all four deep dives (DD1's five bounds, DD2's three rungs, DD3's three rungs with the full capacity math, DD4's worked example) · the final design · all three level bars. **No content gaps.**