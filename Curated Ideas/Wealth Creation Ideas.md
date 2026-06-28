# Idea Catalog 

_One-stop log of every product/startup idea raised so far. Each entry: **Name → Context (how it surfaced) → Opportunity → Status.** Status tags are load-bearing — nothing here is validated, and most are explicitly "do not build." All ideas live in the Wealth bucket (B2B = help someone make/save money), and all must clear the standing gates: validation (Mom Test before code) → AI-native filter → $100M Offers market/offer/value filters → vertical-vs-horizontal test → buyer-economics check._

---

## A. Active wedge candidates (mapped, not chosen)

### 1. FirmBrain — compounding knowledge layer for Indian lawyers

- **Context:** Surfaced from the "Token Capital" thesis (Satya Nadella, 36kr article) converging with Karpathy's "LLM Wiki" idea — the insight that the durable asset in an AI business is the _portable knowledge layer a company owns_, not the foundation model it rents. Pushed away from building that thesis as horizontal infra and toward making it the _spine of a vertical_. Law was the natural fit given the law-degree × engineering moat.
- **Opportunity:** A firm-owned system that learns each firm's precedents, templates, drafting voice, and judgment; gets compounding-better with every matter; stays model-agnostic underneath. The customer owns their loop; you own the relationship and the moat. Clears every filter on paper: AI-native ✓, domain moat ✓, B2B vertical ✓, and "your judgment compounds, never locked to one model" is a credibility-led sales story in a trust-dependent market.
- **Landmines:** Buyer economics — billable-hour structures mean efficiency tools can _reduce_ firm revenue; must validate before building. Vitamin-not-painkiller risk (chronic vs acute pain). RAG pipeline alone is not the moat.
- **Status:** **Idea #1. Parked — not validated, do not build.** Next step on revival: Mom Test with Indian lawyers on how knowledge dies in folders/inboxes today.

### 2. AI real-estate CRM (TeriSage-adjacent)

- **Context:** Raised repeatedly as the wedge that's "already half-solved" — TeriSage is live, it's a family venture, and the UK relatives are potential design partners. Adjacent to work already shipped.
- **Opportunity:** Strongest on _easy-to-target_ and decent on purchasing power (commissions flow). Real-estate operations are part of the domain × engineering moat. AI-augmented CRM for channel partners / broker teams.
- **Landmine:** Purchasing power not yet pressure-tested — what will an Indian broker actually pay monthly, and is it worth the time? Re-score at a payer sub-segment (e.g. luxury/commercial brokers), not the generic market.
- **Status:** Candidate wedge, not selected. Purchasing-power validation pending.

### 3. Career transition tools for Indian graduates

- **Context:** Came up as a wedge drawn from your own path (law → engineering) and your law batch as a live sample of people who left the profession.
- **Opportunity:** High, emotional pain; strong tailwind. Targeting is moderate–strong (you can reach your own batch). The payer fork matters — grads are broke, but parents / working professionals re-skilling can pay.
- **Landmine:** Buyer ≠ pain-feeler. Re-score purchasing power at the working-pro re-skilling sub-segment.
- **Status:** Candidate wedge, not selected. Needs market-sizing (how many of your batch left, and where to).

### 4. "Boring B2B" cluster — strong-purchasing-power zone

- **Context:** Emerged while running the 4-indicator market filter — the observation that money-rich, unglamorous B2B ideas cluster in the strong-purchasing-power zone and score better on the grid than the exciting ones.
- **Opportunity (sub-ideas):** insurance-broker back-office automation; GST / CA reconciliation agents; **law-firm intake/qualification** (revenue-attached, not generic lawyer tooling — this dodges the FirmBrain billable-hour landmine by attaching to _new revenue_); CPA/CA client-comms tooling. The unifying logic: sell to/through the party that holds the money (e.g. a CA channel beats selling to price-sensitive SMBs directly).
- **Status:** Idea cluster, none worked up individually. Note: law-firm intake/qualification is arguably the sharpest unbuilt one here.

---

## B. Ruled out

### 5. AI-builder / solo-founder tools

- **Context:** The "romantic wedge" — the world you belong to and want to serve, which is exactly why it's the romantic choice, not the rational one.
- **Why ruled out:** Fails purchasing power (broke, cheap, high-churn — the "resume-guy trap") **and** has no domain moat (engineering-only, not domain × engineering). Loses on multiple indicators at once.
- **Status:** **Ruled out.** Kept as a cautionary example of the romantic-wedge trap.

### 6. AI content distribution / automation tool (LinkedIn, X, Medium, Instagram)

- **Context:** Raised as a "future build" idea — multi-platform persona-building + automated post generation — primarily framed as a _learning_ project to develop AI-eng / Claude Code muscles.
- **Why ruled out (commercially):** One of the most saturated categories alive (Taplio, Hypefury, Typefully, Buffer, AuthoredUp). Breaks your own filters — consumer/creator tool, not B2B vertical SaaS; "AI can write posts now" is everyone's why-now, so it's nobody's edge. Also the wrong lesson: career-ops proves _useful thing + build in public → distribution follows_, not _build a distribution tool → get distribution_. You learn distribution by distributing manually first.
- **Status:** **Killed commercially. Fine as a dogfooded learning project only** — keep the label honest so it doesn't drift into "my startup."

### 7. "Feeling heard" app (venting / acknowledgement)

- **Context:** Born from a personal anecdote — venting to a cab driver who just nodded, and finding that being _acknowledged_ (without advice or fixing) was emotionally sufficient.
- **Why ruled out:** Runs against your B2B-vertical preference; saturated consumer-emotional category with well-funded incumbents and no moat; consumer emotional-app economics repeat prior pitfalls; liability exposure is structurally wrong for a solo founder.
- **Salvage:** The _principle_ — "people want to feel heard before they want to be fixed" — is a valid UX/tone idea to embed as a _feature_ inside a B2B workflow, not a standalone company.
- **Status:** **Advised against as a standalone product.** Keep the insight, drop the execution.

---

## C. On the horizon (parked by design)

### 8. Personal Agent OS ("JARVIS" / superhuman automation)

- **Context:** Coined while exploring the Hermes Agent repo (Nous Research). The vision: an always-on, JARVIS-style assistant that automates email triage, daily planning, prioritization, learning intake, and notes — Telegram as the interface. Explicitly flagged as the comfortable-builder retreat in a new costume mid job-hunt, and deferred.
- **Opportunity:** Personal-productivity leverage (10–20x, _measured_ not vibes) for yourself first — toolkit landscape mapped: Hermes (agent-OS layer), Obsidian (notes/memory hub), career-ops (narrow job-specific), n8n (flagged for later). Potentially a product later, but framed as a personal experiment, not a company.
- **Guardrails carried forward:** read-only OAuth scopes only (no delete capability), git-backed/synced notes vault (not live), Docker isolation, DM allowlisting. Define 2–3 measurable proxy metrics _before_ the 3-month run.
- **Status:** **Parked until the job offer lands. Do not build now.** Structured hypothesis, not active work.

---

## D. Trend theses (real trend, shape unresolved)

### 9. AEO / Machine-Readable Trust — being discovered & trusted by agents

- **Context:** Second-order thinking. The chain: SEO existed because _humans_ discover through search → AI shifts the discoverer from human to _agent_ → so the optimization target shifts from human-readable persuasion to machine-readable structure + machine-_verifiable_ trust → a new discipline emerges (Agent/Answer Engine Optimization) → and the scarce thing agents need that humans never did is **machine-readable trust** (structured, verifiable signals of reliability/provenance/policy/reputation an agent can consume as data, not infer from vibes). Same _flavour_ of origin as FirmBrain — a sharp macro thesis spotted before the obvious crowd.
- **Opportunity (the whitespace, after the reality check):** The obvious slices are already swarmed — protocols are owned by giants (Google UCP, OpenAI+Stripe ACP, Anthropic MCP, AP2, A2A; "do not build a protocol, that race is over"), marketing-GEO is crowded, merchant-enablement is filling fast in e-commerce. The _less-solved_ parts: (1) machine-readable **trust/reputation/verification** for agents — protocols handle discover→checkout→pay but not "should an agent trust this vendor?"; (2) **non-commerce** agent discovery (APIs, tools, professional/local/B2B services, not just SKUs); (3) **vertical adapters in high-entropy, regulated, trust-critical domains**; (4) the _agent's_ side — tools that help agents evaluate/rank trust.
- **The honest filter flag (don't skip this):** As written, this is **horizontal infrastructure** — which is your standing "wrong lane for a solo founder" filter, and the romantic/comfortable-builder pull in a new costume (a big, general, "I could build anything" thesis with no specific customer yet). It also carries its own self-identified central risk: **protocol-eaten** — UCP/ACP may absorb trust signals into the spec, turning any standalone trust layer into a free, commoditized feature. And "who pays" is unresolved (businesses to be found, or agent-builders to find trustworthy vendors?).
- **The one slice that touches your moat:** whitespace #3 — **vertical trust/adapter for one high-entropy regulated domain you actually know** (law / real-estate). This is the _exact same move that rescued FirmBrain_: don't build the horizontal thesis as a product, pull it down into a vertical where domain × engineering compounds. "Agent-trustable vendor layer for [legal services / property transactions]" is a candidate; the generic horizontal version is not.
- **Status:** **Logged, exploratory — do not build the horizontal version.** If it advances at all, it advances only as a vertical slice, behind the validation gate. Watch for the entry signal the brief names: agents shifting from _research_ to _autonomous purchase with delegated payment_ — that's when the trust layer becomes a live pressure point rather than two years early.

---

## Cross-cutting notes

- **Lead wedge still unresolved.** Prerequisite decision before committing: which customer type do you genuinely _enjoy_ talking to.
- **The moat is domain × engineering, not engineering.** Every idea that wins (FirmBrain, real-estate CRM, law-firm intake) leans on law or real-estate domain knowledge; every idea ruled out (builder tools, content automation) is engineering-only.
- **The recurring shape: a sharp horizontal thesis that has to be pulled down into a vertical.** Token Capital → FirmBrain was that move; AEO/machine-readable-trust (#9) is the same pattern again, not yet pulled down. The thesis is the easy part and the romantic trap; the discipline is forcing it into a domain where your moat compounds.
- **Validation gate is absolute.** Nothing above has had a single Mom Test conversation. None are "build" — they're "explore, then validate."