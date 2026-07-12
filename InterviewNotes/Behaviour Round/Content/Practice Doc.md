# Behavioral Playbook — Mohak Tripathi

> **This is the practice document.** Stories first. Open it and start talking. `behavioral_prep.md` is the _theory_ (Hello Interview chapter notes) — keep it, but don't practice from it. Target: **SDE2 / mid-level** at Razorpay · Meesho · Swiggy · CRED tier. Last updated: July 2026.

---

## ⚡ THE 60-SECOND CARD — read this immediately before every round

**The three rules. Nothing else matters as much.**

1. **Headline in the first breath.** What it was · my role · the outcome. _Then_ the story. No throat-clearing.
2. **Always name what I rejected, and why.** "I chose X" = execution. "I rejected Y because Z, chose X, mitigated its risk with W" = **judgment**. That gap _is_ the mid-level bar.
3. **Close the loop.** Before → what I did → after. If I can't say what changed, I don't have a story yet.

**Shape of every story:** **C**ontext (10%) → **A**ctions (60%) → **R**esults + **L**earnings (30%). 2–4 minutes. **"I", never "we."**

**🔴 The numbers are memorised, not estimated:**

|Fact|The number|
|---|---|
|Experience|**3.5 years.** Not "four."|
|TerrySage customers|**~4 trial/pilot.** Pre-revenue. Never a range. Never "15+."|
|TerrySage pipeline|~200 prospects|
|CEO revamp|~1 month of work → **8 days** (vs. the 2-day ask)|
|MSME report generation|~60 min → **under 10 min**|
|Proposal throughput|4 → 7 / week|

**Am I mid-level?** Yes. SDE2 = mid everywhere. I do **not** need org-spanning stories. Don't fabricate them — follow-ups expose it.

**The four ways I lose (from the July 2026 mock):** no headline · no rejected alternative · unclosed loop · two thin stories instead of one deep one.

---

## 🎯 SELECTION MAP — question → story, decided _before_ the room

> The single biggest failure in the last mock was **improvising selection under pressure.** Decide here, once.

|They ask…|I reach for|Why that one|
|---|---|---|
|Proudest / most impactful / biggest project|**1 · TerrySage**|Scope + total ownership|
|Hardest technical problem|**1 · TerrySage** (multi-tenancy + reliability)|Real tradeoffs|
|Ambiguity / changing requirements|**1 · TerrySage**|Spec moved under me for 9 months|
|Conflict with a **manager** / influenced without authority / pushed back|**2 · CEO**|Managing up with evidence|
|Most difficult **working relationship** / difficult coworker|**4 · Lone-wolf AI lead**|⚠️ **NOT the CEO.** That's a timeline negotiation, not a relationship.|
|A failure / a risk that didn't pay off / gave up on something|**3 · LiftUP**|The failure I **killed**|
|Major obstacles / pushed through repeated failure / when do you stop?|**6 · Scopely**|The failure I **pushed through**. Different signal — don't confuse it with LiftUP.|
|Critical feedback / how you handle criticism / changed how you work|**5 · MSME escalation**|Feedback story, not a third conflict|
|Ownership / did something no one asked for|**1** (0→1 solo) or **2** (the risk plan)||
|Quality / highest standards / security pushback|**2** (vibe-coding risk) + **1** (test + observability)||
|Customer obsession / difficult customer request|**1** (privacy pushback) + **3** (the ROI insight)||
|Hard deadline / under pressure|**2** (8-day delivery) + **1** (built while employed full-time)||
|Tell me about yourself / why leaving / strength / weakness / 5 years|**Short answers** (bottom of this doc)||

**Amazon caveat:** they _penalise_ reusing one story. Spread across all six.

**⬜ Known gaps — build these:**

- **A positive teamwork story** (not a conflict). My thinnest area _and_ the exact thing an interviewer worries about with a solo profile. Source: Jago AI — onboarding the two engineers I hired, the collaboratively-built CLAUDE.md. **HIGH.**
- **Learned something new fast / curiosity.** Easy — Rails on the job, or the deliberate AI pivot.
- **"Why _this_ company"** — research-driven, per application. Cannot be pre-written.

---

# THE STORIES

---

## STORY 1 · TerrySage — the flagship

**Signals:** Scope · Ownership · Ambiguity · Perseverance **Guardrails:** ~4 pilot customers, pre-revenue. Say it plainly — the honesty _earns_ credibility, an interviewer said so directly. Just pair it with a real engineering outcome so honesty doesn't read as emptiness. Precise tools: supertest = backend, Maestro = mobile E2E.

**▶ THE OPENER (say roughly this):**

> "TerrySage — a B2B real-estate CRM I built 0→1 as the sole engineer over eight or nine months, alongside a full-time job. It's live on web, iOS and Android, and in active pilot with four trial customers.
> 
> The problem: Indian property portals are spammy and fraud-heavy, and agents end up juggling leads across MagicBricks, 99acres, old CRMs and WhatsApp. My brother-in-law saw the gap and I owned the entire technical side.
> 
> **Four things made it hard, and I'll walk through each: the multi-tenant architecture decision, the lead-capture integrations, AI extraction reliability, and holding quality together as a solo dev on a spec that kept moving.**"

_(That last line is the Table of Contents. It's what stops the rambling. Say it every time.)_

### Actions

**① Architecture — the decision, with the alternative named** Three options for tenant isolation: **database-per-tenant**, **schema-per-tenant**, **shared schema with row-level isolation by `tenant_id`**.

- **Rejected** database- and schema-per-tenant: the schema is identical across tenants and there's no PII/financial-grade isolation requirement. You'd take on migration complexity across N databases and pay it _every time_ you iterate — the wrong bill for a solo dev on a product still finding its shape.
- **Chose** shared-schema, row-level. And the risk of that choice is obvious: one forgotten `WHERE tenant_id` and you leak data across tenants.
- **So I made it structurally impossible, not a matter of discipline:** middleware attaches the logged-in user's `tenant_id` to every query by default, and `tenant_id` is resolved server-side — never trusted from the client.
- **Residual risk I know about:** raw SQL and background jobs that bypass the middleware. Handled separately.
- The _other_ call was doing it **on day one** rather than retrofitting. That was the real bet — I'd carried the pattern from Jago AI and LiftUP, and retrofitting tenancy into a live product is brutal.
- **GraphQL** so one API serves mobile _and_ web, each fetching exactly the fields it needs. (Mobile bandwidth. **Not** "to avoid joins.")

**② Integrations** — automated lead capture from Meta Ads, MagicBricks, 99acres and web forms, routed into the CRM. Meta's data-handling rules are compliance, not preference.

**③ AI** — voice-to-text agent notes; LLM property-description extraction that auto-fills the property form.

- It worked in testing and started failing on real inputs — an agent pastes a description that clearly contains the price and the pipeline misses it.
- **First I made it fail _safely_:** confidence threshold — below ~80%, don't populate the field. Output is _suggestive_, not authoritative. That was a **product** decision before a technical one: a wrong autofill is worse than an empty field, because it destroys trust in every other field.
- **Then I built an eval harness** instead of eyeballing it — human, model-graded and programmatic evals over a real dataset, producing a score I could actually move.
- **Then I iterated against the score:** system prompt, single-shot → multi-shot examples, and prompt caching once the context grew, to hold token cost down.

**④ Reliability under solo constraints — the real "hardest part"**

- Two testers and me building. New features kept breaking modules that were already signed off. A circular labyrinth.
- **I responded with systems, not heroics:** integration-heavy suite (supertest) · Maestro for mobile E2E over real networks · a regression discipline — _every bug gets a regression test before the fix ships_ · observability with Sentry (staging + prod) and UptimeRobot.

**⑤ Uncertainty** — requirements moved as the founder talked to more agents. I treated it as continuous validation: cut scope deliberately as signal sharpened, sequenced the commodity modules instead of building everything at once.

### Results

Live, in **active pilot with ~4 trial customers**, pre-revenue, ~200-prospect pipeline. **The outcome I actually claim is an engineering one:** regressions stopped reaching users. Sentry caught issues — an N+1 on the lead query, among others — _before_ trial users hit them. A solo-built, fast-moving product stayed stable enough to put in a customer's hands. That's the claim.

### Leverage — what I left behind for others

> **This is the follow-up that sank the mock. It will be asked. Have it loaded.**

- **Public architecture repo** (`terrisage-architecture`) — sanitised README + screenshots documenting the tenancy model and integration design, no source. Built so someone can understand the system without me in the room.
- **Tests as executable documentation** — the supertest + Maestro suites encode what the system is _supposed_ to do. On handover, that was the contract.
- **Handover documentation, complete** — the product is transferable, not just working. That was the forcing function for all of the above.
- **Structured feedback loops instead of ad-hoc opinion** — Hotjar for real behaviour, Sentry for real failures, founder→agent conversations as a defined intake path. Replaced _"the founder heard someone complain"_ with evidence.
- **The honest gap — say it out loud:** I never wrote **ADRs**. The multi-tenancy call and the hashing rejection live in my head. _Ending on a real gap beats a manufactured strength._

### Learnings

Multi-tenant pattern reused across three products. Validate-or-kill before over-building (that came from LiftUP). And: **quality at solo scale comes from tests and observability, not effort.**

### Follow-ups — loaded

- **What would you do differently?** → _Write ADRs from day one._ I made real calls — shared-schema over schema-per-tenant, rejecting at-rest hashing — and none of the reasoning is written down. When the first large client asks the privacy question, whoever answers needs to know what we ruled out and why. I optimised for shipping and under-invested in decision memory.
- **Trial customers pushed back on privacy — what did you build vs defer, and who decided?** → Concern came from our largest _prospects_: "how do I know my leads aren't visible to my competitor?" Real concern; the data does sit with us. I explored **hashing lead data at rest** and **rejected it** — column-level hashing degrades every lookup to a full table scan with a per-row decrypt, which kills the core CRM read path, which is the entire product. So I made a **segmentation call** with the CEO: large clients care about isolation; smaller agents care about lead volume — for them privacy is theoretical and lead-gen is existential, and _that's_ our pilot cohort. Deferred the heavy privacy work, gated on the first large client. **Did not defer:** tenant-isolation guarantees already in the architecture, and Meta's data-handling rules. What I'd do differently: write it down as an ADR.
- **How is tenant isolation enforced?** → Middleware attaches `tenant_id` by default to every query; resolved server-side; never trust the client. Edge case: raw SQL / background jobs bypass it.
- **N+1?** → Caught via Sentry, fixed with batching / DataLoader.
- **Hardest part?** → Recurring regressions while solo on a shifting scope. Solved with test infra + observability + regression discipline.

---

## STORY 2 · The CEO and the two-day revamp — _core conflict (manager)_

**Signals:** Conflict Resolution · Communication · influence-without-authority · technical judgment **Guardrail:** The CEO stays **reasonable** throughout. His AI optimism was fair; I surfaced what a non-engineer couldn't see. **Never** "he didn't get it / he was clueless" — that makes _me_ the jerk the question is screening for. Keep "2 vs 8 days" honest; never mock the 2-day number.

**▶ THE OPENER:**

> "My CEO wanted a full UI-and-backend revamp done in two days by handing the codebase to Claude. I disagreed — but I didn't argue in the room. I went away and came back with a risk-mitigation plan, and we shipped it in eight days with no data-layer breakage."

### Context (~20s)

Non-technical CEO, reasonably excited about how much AI tooling could accelerate us. He saw the revamp as "mostly prompt engineering" on a low-risk UI. What he couldn't see: it was a **two-year-old production codebase**, the revamp touched **backend API contracts**, and data came from the client side — so naive AI-generated changes risked breaking the data layer.

### Actions

- **Didn't litigate it in the heat of the room.** Took it away and built a **risk-mitigation plan** documenting the _specific_ failure modes of vibe-coding into a mature production codebase — API-contract breakage, data-layer integrity, security on client-supplied data — versus greenfield, where it genuinely _is_ low-risk. **I conceded the part of his instinct that was right.**
- Brought it back and walked him through the concrete risks **in business terms**. In those terms he agreed immediately: take a bit more time, do it right.
- **Turned the plan into guardrails, not just a warning** — put the risk doc into a `CLAUDE.md` (tight instructions + reflection/double-check steps) so the AI tooling itself was constrained. **All three engineers designed the CLAUDE.md together** so nothing slipped.
- **Divided the revamp by prior component ownership** — each engineer took the sections whose APIs and roles they already knew, so every AI-assisted change had a human owner who could catch a contract break. Feature branches, frequent PR merges to keep three people in sync.
- **Showed progress every two days** — even when the work wasn't finished.

### Results

Shipped the full revamp (~50 pages + backend changes) in **8 days** — against a 2-day ask, close to my original 7-day estimate — through staging to production with **zero data-layer breakage**. Roughly a month of conventional work. The collaboratively-built CLAUDE.md is what made AI-assisted work on a mature codebase safe.

### Learnings

- AI tooling is a **multiplier on greenfield**; on a mature codebase the _discipline_ — guardrails, contracts, ownership — is what makes it safe.
- **Translating technical risk into business terms is how you move a non-technical decision-maker.** Don't expect them to feel a risk they can't see; express it in their vocabulary and they'll fund it.
- **Don't litigate a risk call in the room. Bring evidence and a plan.**
- And: a founder gives aggressive deadlines to create urgency, not to be unreasonable. **Show progress and the deadline negotiates itself.**

### Follow-ups — loaded

- **Why not just do what he asked?** → I did the part that was right — use AI for speed — and added the guardrails the production context required. The goal was _his_ outcome, safely.
- **How did you know the risks were real?** → API contracts + client-supplied data on a two-year-old codebase. I documented the concrete failure modes rather than asserting a feeling.
- **What if he'd insisted on two days?** → Show the throughput data and scope a _safe subset_ to ship first — give him something real in two days rather than everything, broken.

---

## STORY 3 · LiftUP — the failure I killed

**Signals:** Learning from failure · customer/business judgment · self-awareness **Guardrails:** The failure is **my sequencing mistake** — I built off one excited customer before validating a market. **Not** "great product, dumb market." Don't badmouth the owners who said no; their ROI question was rational and _it's the whole insight_. **Caveat:** this is a _product/judgment_ failure. If they specifically want a **technical** failure — a bug, an outage, a bad technical call — use TerrySage's recurring-regressions-before-test-infra instead.

**▶ THE OPENER:**

> "I built a complete gym-management SaaS in four weeks off the enthusiasm of a single customer — and then killed it about seven weeks in, because I'd never checked whether a market existed. The product was fine. The demand wasn't. The mistake was sequencing."

### Context (~20s)

I had the itch to build 0→1. A gym owner I'd known for years — a three-branch chain — was running everything on paper plus a dead desktop app: local MySQL, no updates in six or seven years, unresponsive vendor. He asked for a modern cloud version and was excited enough to pay.

### Actions

- **Loosely** validated with him (designer mockups, he liked them), then built a full multi-gym / multi-branch SaaS in ~4 weeks alongside a full-time job — members, staff, equipment, attendance, a rewards mechanism, multi-tenant for chains.
- **Hit a unit-economics wall:** the biometric punch-machine integration needed the vendor's APIs at **₹80K/year**, against **~₹50K** of revenue from my one customer, plus cloud infra. Serving 1–3 customers was never going to work. I needed scale.
- **So I did the customer discovery I should have done first** — talked to other gym owners. Broadly: no.
- **Diagnosed why, properly:** gym software is a commodity (cheap options sold over WhatsApp); most local gyms are fighting for members under Cult.fit pressure and have no scale, so management software is **nice-to-have, not must-have**; and every single owner asked the one question I couldn't answer — _"if I spend ₹50K, how much will I make?"_ It's a **cost-centre, not a revenue driver.** The only real buyers were large chains — rare, and hard to reach.

### Results

**I killed it after ~45–50 days.** The real failure was _sequencing_: I built a complete product off one enthusiastic customer before validating that a market existed. Two weeks of conversations before writing any code would have told me it didn't.

### Learnings

- **Validate demand before building, not after** — many potential customers, not one excited one.
- Separate **must-have from nice-to-have**, and **cost-centre from revenue-driver**. That distinction is the whole game in B2B.
- Respect my own bandwidth — sales + building + a full-time job was not a real plan.
- **Applied all of it directly on TerrySage:** continuous customer discovery through the founder, phased rollout on recurring feedback, validate-or-kill before over-building.

### Follow-ups — loaded

- **Would you do it again?** → Yes — validate-first. 15–20 owner conversations before a line of code.
- **Wasn't it a waste?** → No. It's where my validate-or-kill discipline _and_ the multi-tenant pattern came from — both shaped TerrySage.
- _Edge: don't brag about the product. Don't blame the market._

---

## STORY 4 · The lone-wolf AI/ML lead — _most difficult working relationship_

**Signals:** working with difficult people · communication · empathy · influence-without-authority **Guardrail:** A **working-style difference**, never a character flaw. "A strong engineer who'd worked solo for years, loved experimenting, found coordination genuinely costly." Professional friction, never personal. **I still work with him.** Never "uncooperative" or "frustrating."

**▶ THE OPENER:**

> "The AI/ML lead on Jago AI. Not a personality clash — a working-style mismatch with a real delivery cost. He'd change the API contract on his side without flagging it, my integration would break, and it would surface in front of the demo team who had no idea where the fault was."

### Context (~20s)

Microservice architecture: my Rails backend and DB on one side, his AI/ML service on the other. To ship anything end-to-end — the RAG document-analysis pipeline, for instance — the two had to integrate over a shared API contract. He's senior, had worked solo most of his career, experimented constantly and moved at his own pace. Scheduled, tightly-coordinated contract work was **genuinely hard for him.**

### Actions

- **The concrete friction:** as his experiments evolved he'd change the response schema without telling anyone. My integration broke. From his side it just looked like _"the response isn't coming through."_ Chasing it reactively ate days.
- **I stopped treating it as his failure.** I sat with how he actually works — autonomy and owning the AI/ML design, not coordination overhead — and accepted that process ceremony costs him something real. **Any fix that required him to change how he works was going to fail.**
- **So I lowered the cost of compliance to nearly zero.** Not a standup, not a ritual: **one email, whenever the schema changes.** And I explicitly **took the burden of proof onto my side** — I'd do the monitoring, I'd do the verification. He just had to tell me. He agreed, because it cost him almost nothing.
- **I took the coordination on actively** — pulled the information out of him proactively and built the contract around it, rather than waiting to be surprised.
- **I didn't depend on goodwill.** I put contract-level checks on my side, so a changed response shape shows up as a **failing check, not a broken demo.** The email is the fast path; the check is the safety net.

### Results — the loop, closed

- **Before:** schema changes surfaced as _breakage_. Days lost per incident. Demos failing for reasons neither team could explain.
- **After:** schema changes arrived **before** they broke, not after. Unannounced contract changes stopped. The RAG pipeline integrated cleanly. The demo failures went away.
- **The relationship held** — professional disagreements, never personal. **I still work with him today.**

### Learnings

Forcing my process on someone who works differently backfires. What worked was **making the right behaviour cheaper than the wrong one** — I absorbed the cost so his only obligation was one email. I don't try to change how someone works anymore. **I redesign the interface so their natural way of working doesn't break mine.** Empathy is a tool, not just a nicety.

### Follow-ups — loaded

- **Why not escalate to a manager?** → It was a working-style gap, not a performance issue. A lightweight norm solved it without making it adversarial.
- **What if the norm hadn't held?** → It wouldn't have mattered as much, because of the contract-level checks. Beyond that: contract _versioning_, so breakage becomes impossible rather than merely visible.
- **And if it still kept breaking?** → Escalate to my manager — but as a **process gap between two services**, never as a complaint about a person. _Escalating a person makes an enemy. Escalating a missing contract gets you a contract._
- _Edge: lead with "good engineer, different style," not with the breakage._

---

## STORY 5 · The MSME client escalation — _difficult feedback_

**Signals:** receiving feedback without defensiveness · stakeholder communication · ownership **Guardrails:** Own **my** part cleanly — "I learned this once and changed my practice." **Never a recurring trait.** Don't blame sales or the client; their anxiety was understandable. **Note:** this is a **feedback** story, _not_ a third conflict. Told as a conflict it reads as a communication weakness. Told as feedback it reads as maturity.

**▶ THE OPENER:**

> "A first-time client escalated to my management that they'd lost confidence the work was progressing. It was hard to hear — and they were right, though not about the thing they thought."

### Context (~20s)

Services company, first-time client, MSME self-assessment platform. I build in the technically-sound order — architecture, then API contracts and backend, then frontend, which comes together fast once the backend is solid. But the client had nothing **visual** to see for weeks. And I compounded it: I went a couple of days without proactively updating them, **because I felt I had nothing tangible to show.**

### Actions

- **I didn't get defensive**, and I didn't defend the (correct) sequencing. I owned my actual part: **silence reads as no progress** — and a first-time client has no trust bank to draw on yet.
- **Shipped a thin end-to-end vertical slice** — a small ~20% piece working frontend-to-backend — so they could see real, tangible progress, while I continued building the full backend architecture in parallel.
- **Set a regular update cadence** regardless of whether there was new UI to demo. **Progress is communicated, not just shown.**

### Results

The client's confidence recovered. We delivered the platform — **report generation dropped from ~60 minutes to under 10.** The relationship held.

### Learnings

Technically-correct sequencing isn't enough. Stakeholder confidence needs a **visible end-to-end slice early**, _and_ proactive communication even when there's nothing to demo. I carried this straight into TerrySage — phased rollout, continuous communication with the founder, **never go dark.**

### Follow-ups — loaded

- **Wasn't backend-first wrong?** → No, the sequencing was sound. The mistake was treating _"no UI yet"_ as _"nothing to communicate."_ I kept the architecture discipline and **added** the visible slice + the cadence.
- **How do you handle it now?** → Ship a thin end-to-end increment early. Communicate on a fixed cadence regardless of demo-ability.
- _Edge: a one-time lesson that changed my practice. Never make going dark sound like a habit._

---

## STORY 6 · Scopely — three iterations to a proposal engine

**Signals:** Perseverance · Ambiguity · Growth · knowing when to quit **Guardrails:** Both failures are **mine** — I asked the wrong questions. **Never** blame the sales team; their objections were correct both times. It's in use but still iterating — don't call it done. **Why not LiftUP:** LiftUP is the failure I **killed**. Scopely is the failure I **pushed through**. Different signal entirely.

**▶ THE OPENER:**

> "An internal proposal engine that failed twice before it worked. Sales rejected v1 and v2 — and both times they were right. The third version is in use. What made the difference was realising both failures were in the _input_, not the output."

### Context (~20s)

Services company. Sales has to turn a proposal around fast or a hot lead goes cold — that lag was costing real deals. I owned the build end-to-end.

### Actions

- **V1 — traditional software.** A 40-question intake form producing an FRD and scope of work. **Sales wouldn't fill it.** Their objection was _correct_: you can't pre-define the questions, and no client answers forty of them. Rejected.
- **V2 — reduced + RAG.** Cut to 12 questions, added a RAG pipeline embedding all our past proposals. **Accuracy wasn't good enough.** Rejected again.
- **The diagnosis — this is the actual insight:** both versions failed on **input**, not on generation. **I was asking sales to _produce_ information they didn't have** — when the information already existed in the system: meeting transcripts, the client's first email, their BRD, the industry vertical, the SIC code.
- **V3 — end-to-end.** Pull all of it automatically. Generate the proposal. Let sales **edit and tweak** — they stay in control. Run a feasibility / RFR verification check against publicly available documentation.

### Results

**V3 is in use** by the sales team, and I'm still on the feedback loop. Turnaround went from a manual multi-day drafting cycle to a generated, editable draft. **[▶ TODO: get the real before/after turnaround number from sales. This is the weakest part of an otherwise strong story.]**

### Learnings

The learning isn't "don't give up." It's that **when an internal tool gets rejected, the bug is usually in what you're asking the user to _do_, not in what you're _producing_.** Both failed versions made the user work. And the skill I was actually missing: **asking the right question, of the right person, at the right time.**

### Follow-ups — loaded

- **Your honest reaction to the second rejection?** → _Lead with the feeling, then the reasoning._ "The second one stung more than the first. On v1 I could tell myself the approach was wrong. On v2 I had **listened** to the feedback and it still got rejected — that's the one that makes you wonder if the problem is unsolvable."
- **Why a third attempt rather than shelving it?** → **Two reasons, and "I'm persistent" isn't one of them.** (1) **The feedback wasn't exhausted** — sales kept surfacing _new_ objections, not repeating old ones. New objections mean the problem is still being understood. Repeated objections would have meant stop. (2) **I'd diagnosed the real failure, and it was mine** — input, not output.
- **So when _do_ you stop?** → When feedback stops producing new information **and** the tool still isn't crossing the usefulness threshold after I've incorporated it. That's an **information test**, not a sunk-cost feeling. **And I've applied it:** on LiftUP the feedback _was_ exhausted — every owner asked the same ROI question — so I killed it.
- _Edge: never suggest the sales team was being difficult. They were right, twice._

---

# SHORT ANSWERS

## Tell Me About Yourself (~50 sec)

> Lead **SDE**, not AI. AI is a _feature I shipped_, not an identity. Honest about pilot stage. ~50 seconds — don't ramble into a fourth accomplishment.

> "I'm a backend-heavy full-stack engineer with about three and a half years of production experience. Most of my work is multi-tenant SaaS on Rails and Node with PostgreSQL — owning the data model, the APIs and the integrations — and I bring AI in as a production feature, things like RAG pipelines and voice/LLM workflows, not standalone experiments.
> 
> In my current role I own the backend for an AI-driven SaaS product — a multi-tenant Rails and Postgres system integrating with separate AI/ML microservices, including a RAG document-analysis pipeline I integrated end-to-end. Alongside that I built TerrySage, a B2B real-estate CRM, 0→1 as sole engineer — multi-tenant from day one, a single GraphQL API serving both a mobile app and a web client, automated lead-capture integrations, and AI features like voice-to-text notes and generated property descriptions. When bugs started slipping through, I added an integration-test suite, Sentry and uptime monitoring so a fast-moving solo build stayed stable enough for pilot users.
> 
> What I want next is to take that end-to-end ownership and apply it at real scale — systems with meaningful load, alongside a strong engineering team I can go deeper with. Which is exactly why I'm targeting SDE2 roles at product companies like yours."

## Why are you leaving?

> "I've spent the last couple of years doing deep 0→1 backend ownership, often as the sole or lead engineer. I've gotten a lot out of it — but I've now done it end-to-end several times, and what I want next is to operate at scale, real load and complexity, alongside a strong team I can learn from. That's the growth step I'm optimising for."

**🔴 Trap:** never volunteer the real frustrations — traction, dated stack, the CEO. If pushed _"but why really?"_ — **stay on the growth framing.**

## Greatest strength

> "End-to-end ownership under ambiguity. Give me a vague problem and I'll take it from requirements through architecture, implementation, integrations and production reliability — and ship it. TerrySage is the clearest example: built solo, made the architecture calls, put in the testing and observability to keep it stable."

## Weakness / growth area

> "Most of my experience is 0→1 in small teams, so I've had less exposure to large-scale distributed systems and big-team engineering process — heavy code review, established design practice, services under very high load. That's my real gap, and it's why I'm targeting this kind of role. I've been working through system design deliberately to close the conceptual side, but the real depth comes from building those systems with people who've done it."

**🔴 Trap:** don't swap in a fake humblebrag. Don't volunteer "LLD" or "I clash with people." **The solo→scale gap is real, safe and on-narrative.**

## Where do you see yourself / professional goals

> "Growing into a senior backend engineer who owns significant systems at scale — making the architecture and reliability calls on services that matter, and eventually mentoring others. I like being close to the product and the impact, so I see myself going deeper on backend and distributed systems, not away from the code."

## Greatest accomplishment

→ **Story 1, TerrySage.**

---

# QUESTIONS I ASK THEM

> Asked at the end of **every** round. Never "no." Pick 2–3, tailored to _who's in the room_. Make a couple double as fit-checks for my own priorities — collaboration culture, engineering-quality bar.

**Recruiter (screen) — intel, not tech:**

- What does the full loop look like, and which signals matter most in each round?
- Who will I meet, and what does each of them value?
- What most often trips candidates up at the onsite, or causes a down-level?

**Peer engineer / IC:**

- How does the team handle technical disagreements? _(doubles as my solo→team fit-check)_
- What are code review and the testing/deploy pipeline actually like?
- What's the biggest engineering challenge the team is wrestling with right now?
- What do you know now that you wish you'd known before joining?
- _Fintech (Razorpay/PhonePe/CRED): ask about their correctness and reliability bar. It signals my quality instinct._

**Hiring Manager:**

- What does success look like at 90 days and 6 months?
- How is the team structured, and where does this role fit?
- How is growth thought about, and how is performance evaluated?
- Why is this role open?

**Senior leader / Bar Raiser:**

- Where is the product headed over the next 2–3 years, and what bets are you making?
- How do the company's values actually show up in day-to-day decisions?
- What sets apart the engineers who thrive here?

**🚫 Never:** anything googleable · comp (recruiter or offer stage only) · "how did I do?"

---

# PER-COMPANY LAYER — applied _at interview time_, never baked in

**Razorpay** — runs a genuine values-driven loop. Six values: _Customer Delight · Ownership (no micromanagement) · Transparency · Question the status quo · Integrity · Collaboration over individual recognition._ Worth a real tailoring pass. My natural fits: Ownership (Story 1), Question the status quo (Story 2), Customer Delight (Story 3's ROI insight).

**Meesho / Swiggy / CRED** — behavioural is _lighter_, folded into a hiring-manager round that's mostly **project deep-dive + culture fit**. Six stories + short answers cover it. **The heavier lift is the project deep-dive** — TerrySage under hostile questioning, "for every line, a counter-question."

**Amazon (stretch/mock)** — behavioural is the _main event_. ~25 min per question, a Bar Raiser digging deep, "I" not "we", measurable outcomes — and **they penalise reusing one story.** Map stories to LPs: Ownership → 1 · Have Backbone, Disagree and Commit → 2 · Learn and Be Curious / Are Right A Lot → 3 · Earn Trust → 4 · Insist on Highest Standards → 5 · Deliver Results / Bias for Action → 6.

**Meta** — values rarely surface in-round; interviewers assess the universal signals directly. Light touch.

---

# THE PITFALL GATE — run this on any new story before it's "done"

1. **Did I decode the signal?** Am I delivering the signal the question tests, or just a good story?
2. **Are Actions ~60%?** Specific, repeatable. _30 seconds with no action named = cut it._
3. **Is Context ≤10%?** Stakes only. No org chart, no project history.
4. **"I", not "we"?** Every "we" audited.
5. **Right story?** Scope > Relevance > Uniqueness > Recency.
6. **No fairy-tale ending?** A real obstacle, mistake or imperfection. Learnings show _application_, not "X is important."
7. **Practised out loud?** If it only exists on paper, it isn't ready.

**🔴 My two personal high-risk pitfalls:**

- **"I built it."** My default as a solo dev. Force the _non-technical_ actions — aligning, communicating, deciding — or every answer collapses into implementation.
- **Fairy-tale TerrySage.** Pride tempts a flawless telling. Every TerrySage answer needs a real obstacle or gap in it.