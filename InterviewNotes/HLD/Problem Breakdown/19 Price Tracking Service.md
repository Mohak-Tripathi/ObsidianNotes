
# Price Tracking Service (CamelCamelCamel) — Problem Breakdown

> 📐 **Revision note (calc):** ⭐⭐⭐ **ONE calculation decides this entire problem.** **500M products ÷ Amazon's ~1 request/sec per IP = 500M seconds ⇒ _"over 15 years just to visit each product page once."_** ⭐ **Even with 1,000 servers on different IPs ⇒ _"5+ days for a complete catalog refresh, during which millions of price changes will go undetected."_** ▸ **That arithmetic proves comprehensive crawling is impossible, and every answer in the file follows from it.** **Other figures: 1M Chrome-extension users · 500M products · ~3,000 new products/day · <500ms price-history queries · notifications within 1 hour · the naive cron runs every 2 hours · consensus thresholds 2–5 reports · verification crawl within 1–5 min.** ⚠ **No storage math anywhere — see the ⊕ note in §5.4.**

>  ⚠ **"Asked at:" Amazon⚠⚠ **NO Pattern callouts at all — first since `05h` Tinder.** ▹ **Follows the `Ch-1` framework and includes a DATA FLOW step, like `05p`.** Cross-refs: ⭐⭐⭐ **`05r` News Aggregator is the close sibling — crawling at scale, priority tiers, CDC, and the pre-aggregate-vs-purpose-built-store choice all recur. Read them together.** · ⭐⭐ **the client as part of the system → `05h §5.3`, `05k §5.1` (and here it goes much further)** · ⭐⭐ **time-series DB → `04d`** · **Postgres → `02g`** · **Kafka → `02c`** · **CDC → `05c §5.3`, `05r §5.2`** · **priority queues + cron→event-driven → `05p`** · **indexing → `01d`** · **partitioning → `01f`** · **CAP → `01h`** · **API design → `01b`** · **API Gateway → `02d`** · **numbers → `01i`.** ▹ **HI twice points at its own Web Crawler breakdown — not in your set yet.**
> 
> **Calibration:** ⭐⭐ **One genuinely novel idea, and the rest overlaps `05r` heavily.** ▸ **DD1's crawling tiers and DD3's CDC are `05r §5.3`/`§5.2` again; DD4 is the same pre-aggregate-vs-purpose-built fork `05r §5.6` had, resolved differently.** ⭐⭐⭐ **What's new and worth the pass: the Chrome extension as a free distributed crawler (DD1), and trust-but-verify on untrusted data (DD2).** ⭐ **ONE pass, leaning on the `05r` cross-refs.** ⚠ **Note DD3 has no ladder and never picks between its two options — see the ⊕ note there.**
> 
> - ⭐⭐ **What actually scores:**
>     - **(a)** ⭐⭐⭐ **Doing the 15-years arithmetic before proposing anything** (§5.1). ▸ **It's the whole problem in one line.**
>     - **(b)** ⭐⭐⭐ **Realising the 1M-user Chrome extension IS the crawler** — ▸ **HI: _"turning our biggest constraint into our competitive advantage."_**
>     - **(c)** ⭐⭐⭐ **Trust-but-verify over consensus** (§5.2) — **accept immediately, verify the suspicious within 1–5 min, correct and downgrade the reporter.**
>     - **(d)** ⭐⭐ **Pareto priority crawling with a feedback loop** — **subscriptions and searches set the priority; successful notifications raise it.**
>     - **(e)** ⭐⭐ **CDC vs dual writes, with the real trade-off named** — ▸ **the clearest statement of it in your set.**
>     - **(f)** ⭐⭐ **A separate time-series store for prices**, and ⭐ **four concrete reasons for the split.**
>     - **(g)** ⭐⭐ **"We're asking the wrong question at the wrong time"** (§5.3) — ▸ **the best one-line case for event-driven over polling you'll get.**
> - ⭐ **Transferable primitives:**
>     - ⭐⭐⭐ **When you can't afford to collect the data, find who is already looking at it.** ▸ **1M browsers were on those pages anyway.** ⭐ **The client isn't caching for itself here — it's COLLECTING for you.** ▸ **Extends `05h`/`05k`'s client-as-tier into client-as-data-source.**
>     - ⭐⭐⭐ **Accept optimistically, verify asynchronously, correct publicly.** ▸ **Beats waiting for consensus, because consensus delays the legitimate case worst** (flash sales expire). ⭐ **Same family as `05p`'s at-least-once + idempotency.**
>     - ⭐⭐⭐ **Spend scarce capacity where the demand is, not evenly.** ▸ **Pareto: subscriptions are a free signal of what users actually want refreshed.**
>     - ⭐⭐ **Ask "who cares about this change?" on the write, not "what changed?" on a timer.**
>     - ⭐⭐ **A different data SHAPE earns a different store.** ▸ **Billions of rows, append-only, time-bucketed queries, tolerates staleness ⇒ time-series DB, not your OLTP table.**
>     - ⭐ **When the data source is an adversary, the rate limit is a hard design input, not an implementation detail.**
> - ⭐ **Re-run (cross-ref, NOT re-explained):** ⭐⭐ **priority-tiered crawling (`05r §5.3` Good rung — identical shape)** · ⭐⭐ **CDC for change events (`05r §5.2`, `05c §5.3`)** · ⭐⭐ **cron → event-driven (`05p §5.1`)** · **pre-aggregation vs a purpose-built read path (`05r §5.6`)** · **client as part of the system (`05h §5.3`, `05k §5.1`)** · **priority queues (`05p §5.2`)** · **composite indexes (`01d`)**. **Genuinely new:** ⭐⭐⭐ **crowdsourcing collection through a browser extension** · ⭐⭐⭐ **trust-but-verify on untrusted user-submitted data** · ⭐⭐⭐ **the rate-limit arithmetic that kills comprehensive crawling** · ⭐⭐ **the CDC-vs-dual-writes trade-off** · ⭐⭐ **TimescaleDB + `time_bucket()`** (`04d`) · ⭐ **consensus validation and why it loses** · ⭐ **designing around a hostile data source.**

---

## 0 · Understanding the problem

📈 **What is CamelCamelCamel?**

A price tracking service that **monitors Amazon product prices over time** and **alerts users when prices drop below their thresholds.** ⭐⭐ **It also has a Chrome extension with 1 million active users** that shows price history **directly on Amazon product pages**, with **one-click subscription without leaving the page.**

- ⭐⭐⭐ **That extension is mentioned in the product description and again in the FRs. It is not a detail — it's the answer to §5.1. Notice it early.**

---

## 1 · Requirements

### 1.1 Functional (what it does)

1. ⭐ **View price history for Amazon products** — **via website or Chrome extension.**
2. ⭐ **Subscribe to price drop notifications with thresholds** — **via website or Chrome extension.**
3. ⭐⭐ **The Chrome extension itself:** **1M active users, price history shown on Amazon product pages, one-click subscribe without leaving the page.**

⚠ **Below the line:** search/discover products · price comparison across retailers · reviews and ratings.

### 1.2 Non-functional (how it behaves)

1. ⭐ **Availability over consistency — eventual consistency acceptable** (`01h`).
2. ⭐⭐ **Handle 500 million Amazon products.**
3. ⭐ **Price history queries < 500ms.**
4. ⭐⭐ **Price drop notifications within 1 hour of the change.**

⚠ **Below the line:** strong consistency for price data · real-time (sub-minute) price updates.

> ⭐⭐⭐ **The constraint that defines the problem — state it in requirements, not later.**
> 
> - ⚠⚠ **_"Amazon is not friendly to price tracking services. They don't provide an API, actively discourage scraping, and implement rate limiting (typically 1 request per second per IP address)."_**
> - ⭐⭐ **HI's framing: you're building a system that must be _"polite"_ to Amazon while serving millions of users.**
> - ▸ ⭐ **This is the first problem in your set where the DATA SOURCE IS AN ADVERSARY.** **Everywhere else the data was yours.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 1.3 ⭐⭐⭐ The design driver — you don't own the data, and the arithmetic says you can't go get it

```
500,000,000 products  ÷  1 request/sec per IP
  = 500M seconds
  = ⭐⭐ over 15 YEARS for one crawler to see each product once
  ÷ 1,000 servers on different IPs
  = ⭐ 5+ DAYS per full refresh — and millions of price changes are missed in between
```

- ⭐⭐⭐ **That calculation is the problem. Three responses follow from it, and they are DD1 and DD2:**
    1. ⭐ **Don't crawl everything equally** ⇒ **Pareto priority tiers.**
    2. ⭐⭐⭐ **Don't crawl at all where you don't have to** ⇒ **1M extension users are already on those pages.**
    3. ⚠⚠ **But now your data comes from strangers** ⇒ **trust-but-verify.**
- ⭐⭐ **And the second, separate axis: price history is TIME-SERIES data** — **billions of rows, append-only, queried in time buckets, tolerates staleness.** ▸ **Different shape ⇒ its own store (§4.1, §5.4).**

### 1.4 Planning the approach

▸ **The `Ch-1` framework: sequentially through the FRs, NFRs drive the dives.** ⭐ **Plus a DATA FLOW step**, same as `05p`.

---

## 2 · Core Entities

- **Product** — an Amazon product being tracked: **current price + metadata** for history display and notifications.
- **User** — **contact information and notification preferences.**
- ⭐ **Subscription** — **links a user to a product, with the price threshold that triggers a notification.**
- ⭐⭐ **Price** — **time-series data capturing price changes over time per product**, enabling the historical chart.

▹ ⭐ **HI's framing line, worth saying:** _"I'm going to start with just a simple list, but as we get to the high-level design, I'll document the data model more thoroughly."_

---

## 3 · API

```
GET  /products/{product_id}/price?period=30d&granularity=daily -> PriceHistory[]

POST /subscriptions
{ product_id, price_threshold, notification_type } -> 200
```

- ⭐ **`product_id` goes in the PATH, not the body** — **_"for better caching and REST compliance."_**
- ⭐⭐ **The `granularity` parameter is doing real work:** **daily averages for long periods, hourly data for recent timeframes.** ▸ **It's what makes §5.4's bucketed queries possible.**

### 3.1 ⭐ Data Flow — the extra framework step

▸ ⭐⭐ **HI's point here is the one to take:** _"the **hidden requirement** is that we need to be able to get the data in the first place!"_

1. ⭐ **Web crawlers AND the Chrome extension collect current prices from Amazon product pages.**
2. **Price data is validated and stored.**
3. **Price changes trigger events for notification processing.**
4. **User receives an email when the price drops below their threshold.**

- ⭐⭐ **Note step 1 already names the extension as a collector, and step 2 already says "validated."** ▸ **The data flow forecasts DD1 and DD2 before you design anything.**

---

## 4 · High-Level Design

### 4.1) View price history

```
Client ──► API Gateway ──► Price History Service ──► Price DB
 website/            auth · rate                     Price: productId · timestamp · price
 extension           limiting · routing
                                             ──► Primary DB
                                                   Product: id · amazonId · lastScraped
                                                   (+ Users, Subscriptions)
Web Crawler ──► Amazon.com        ⭐ black-boxed for now
```

**What we're building:**

- **Client** — **the website or the Chrome extension.** ▸ **Either way, this is how the user views price history graphs.**
    
- **API Gateway** — **authentication, rate limiting, and routing to the appropriate service.**
    
- **Price History Service** — **manages price data retrieval and coordinates with the database.**
    
- **Web Crawler Service** — **scrapes Amazon product pages to collect current prices.**
    
- **Price Database** — **current product information and historical price data.**
    
- **Primary Database** — **everything else: Users, Products, Subscriptions.**
    
- ⭐⭐ **Why Price History Service is separate from the crawler:** **the history service handles many CONCURRENT READS from users viewing charts; the crawler runs on a SCHEDULE with consistent write patterns.** ▸ **Optimise and scale each independently.**
    

> ⭐⭐⭐ **The database split, and this is the crispest version of this reasoning in your set — four reasons.**
> 
> ||**Primary DB**|**Price DB**|
> |---|---|---|
> |**Holds**|**Users, Products, Subscriptions**|**price history only**|
> |**Size**|⭐ **relatively small**|⭐⭐ **grows to BILLIONS of rows**|
> |**Access**|**traditional CRUD**|⭐⭐ **append-only**|
> |**Needs**|**ordinary indexing**|⭐⭐ **time-series optimisations**|
> |**Consistency**|normal|⭐ **tolerates eventual consistency**|
> 
> ▸ ⭐⭐ **Four independent differences, which is why the split is obviously right here.** ▹ **Compare `05h §4.3`'s three-part rule (write pattern + data volume + ideal engine) — all three differ here too.**
> 
> ■ **— end of insert · HI write-up resumes below —**

- ▹ ⭐ **HI black-boxes the crawler deliberately:** **assume it periodically scrapes Amazon and updates the Price table.** ▸ **→ §5.1.**

**The read flow:** `GET /products/{id}/price?period=30d` → **Gateway authenticates and routes** → **Price History Service queries the Price table by `product_id` + time range** → **JSON returned, ready for chart rendering.**

### 4.2) Subscribe to price drop notifications

▸ **Two new components:** ⭐ **a Subscription Service** (create/update/delete subscriptions) and ⭐ **a Notification Cron.**

- ⭐ **Why Subscription Service is separate from Price History:** **different user actions and different data access patterns** — **account operations vs read-heavy price queries.**

**⚠ The naive notification flow — a cron every 2 hours:**

1. **Cron runs every 2 hours.**
2. **Query the Price table for changes in the last 2 hours.**
3. **For each change, query Subscriptions for users with `threshold >= new_price`.**
4. **Send emails.**
5. ⭐ **Mark notifications as sent to avoid duplicates.**

- ⚠⚠ **HI flags its own design immediately, and note it's knowingly NON-COMPLIANT:** **users wait up to 2 hours** — ▸ **against an NFR of 1 hour** — **and _"we're doing expensive database scans every few hours."_** ⭐ **→ §5.3.**

**The subscribe flow:** **user submits → Gateway routes POST to Subscription Service → record created `(user_id, product_id, price_threshold)` → confirmation returned.**

---

## 5 · Deep Dives

### 1) ⭐⭐⭐ How do we discover and track 500 million products?

⭐⭐ **Split it into two problems first — HI does, and it clarifies everything:**

|Problem|What it is|
|---|---|
|⭐ **Product DISCOVERY**|**find all 500M existing products at launch, plus the ~3,000 new ones Amazon adds daily**|
|⭐ **Price MONITORING**|**keep prices updated for millions of known products, prioritising which to check most often**|

▸ **Both hit the same rate limit, but separating them produces better solutions.**

⚠ **Rung labels are mine.**

#### ⚠⚠ Bad — a traditional web crawler

- **Approach:** **seed URLs (homepage, category pages) → extract product links → recursively follow.** **A frontier queue of URLs to visit, a visited-URL tracker to avoid cycles, crawlers processing sequentially.** ⭐ **"Customers also viewed" links get added to the frontier.** ▹ **HI: this is largely its own Web Crawler breakdown.**
- ⚠ **Challenges — and the first one is the entire problem:**
    - 📐 ⭐⭐⭐ **_"a single crawler would require over 15 years just to visit each product page once."_** **Even 1,000 servers on different IPs ⇒ _"5+ days for a complete catalog refresh, during which millions of price changes will go undetected."_**
    - ⚠ **DISCOVERY LAG:** **new products _"might not be found for weeks or months"_** depending on crawl order.
    - ⚠ **Popular products that change price several times a day have stale data for long stretches** ⇒ **unreliable for time-sensitive deals.**
    - ⚠ **And the cost:** **thousands of crawling servers is _"economically unfeasible for most companies."_**

**Why climb:** you cannot buy your way out of a per-IP rate limit at this catalog size. Stop treating all products equally.

#### ⭐⭐ Good — Pareto priority tiers

- ⭐⭐ **The realisation: _"we have fundamentally limited crawling resources, so we better use them wisely."_** ▸ **Product popularity follows a PARETO distribution** — **a small percentage gets the vast majority of attention, with a long tail nobody cares about.**
- ⭐⭐ **The priority signals, and they're free:**
    - ⭐⭐ **Products with many price-drop SUBSCRIPTIONS get the highest priority** — ▸ **users are literally waiting on those.**
    - ⭐ **Products users SEARCH for frequently get elevated priority** — **current interest even without a subscription.**
    - ⭐⭐ **A FEEDBACK LOOP: successful notifications (ones leading to clicks or purchases) boost a product's score** ⇒ **_"a self-reinforcing system that focuses on the most valuable updates."_**
- ⭐ **Priority queues drive the schedule: high-interest every few hours · medium daily · low weekly or less.**
- ✅ **Result: excellent coverage where it matters _"while using a fraction of the infrastructure."_**
- ⚠ **Challenge:** ⭐ **COVERAGE GAPS for new or trending products that haven't built user-interest signals yet.** ▸ **_"A hot new product release might not get discovered quickly if no users are searching for it yet"_** — **missing exactly the early window where prices are most volatile.**

**Why climb:** priority tells you _what_ to crawl, but you still pay to crawl it — and new products have no signal yet.

#### ⭐⭐⭐ Great — the Chrome extension IS the crawler

> ⭐⭐⭐ **HI's reveal, and it's the best idea in the file:** _"Remember that Chrome extension with 1 million users we mentioned earlier? It turns out to be more than just a convenience feature — **it's actually our secret weapon for data collection.**"_

- ⭐⭐⭐ **The mechanism: 1M users browsing Amazon with the extension installed become a DISTRIBUTED DATA COLLECTION NETWORK.** **It captures product IDs, current prices and page metadata by DOM-parsing the product page, and reports to a price-reporting API.**
- ⭐⭐ **And the properties that fall out for free:**
    - ⭐⭐ **Real-time price data for products users are ACTIVELY VIEWING** ⇒ ⭐ **which naturally prioritises popular and trending items** — **no priority scoring needed for them.**
    - ⭐⭐ **DISCOVERY too:** **a user visiting a previously-unknown product page adds it to the Product table.** ▸ ⭐ **That fixes the Good rung's coverage gap on new products.**
    - ⭐ **Crawlers now only handle products the extension hasn't seen recently.**
- ⭐⭐⭐ **The framing to say out loud:** _"Instead of fighting Amazon's rate limits with massive crawler infrastructure, we leverage user behavior"_ — ▸ **_"turning our biggest constraint into our competitive advantage."_**
- ⚠ **Challenges:**
    - ⚠ **Dependency on user adoption and browsing patterns** ⇒ **niche categories still get infrequent updates.**
    - ⚠⚠⚠ **And the big one: _"user-generated price reports could be manipulated or incorrect."_** ▸ **→ §5.2.**

> ⭐⭐⭐ **Don't panic about not knowing Chrome extensions — HI tells you exactly how the interviewer hands this to you.**
> 
> - ⭐ **HI: _"If you're thinking to yourself, 'How the hell would I know this? I know nothing about Chrome Extensions!' don't sweat it."_**
> - ⭐⭐ **The actual prompt you'll get: _"Your extension is installed on millions of browsers actively viewing product pages. **Can you make use of that somehow?**"_**
> - ▸ ⭐⭐ **So the skill being tested isn't extension knowledge — it's noticing that an existing asset solves a different problem.** ⭐ **That's a general interview move: when something is mentioned twice in the prompt, it's load-bearing.**
> 
> ■ **— end of insert · HI write-up resumes below —**

> ⊕ ⭐⭐ **(mine) — where this sits in the client-as-tier thread, and why it's further than anything before it.**
> 
> |File|What the client does|
> |---|---|
> |`05h §5.3` **Tinder**|**caches ITS OWN recent swipes** — an optimisation for itself|
> |`05k §5.1` **Strava**|**records and computes ITS OWN activity** — the primary write tier for itself|
> |⭐⭐⭐ `05s §5.1` **here**|⭐⭐ **collects data about OTHER products for OTHER users** — **the client is your data source**|
> 
> - ⭐⭐⭐ **The generalisation: when you can't afford to collect the data, find who is already looking at it.** ▸ **Reusable for crowdsourced maps, traffic data, outage detection, availability tracking.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 2) ⭐⭐⭐ How do we handle malicious price updates from extension users?

⚠⚠ **The scenario HI gives, and it's the one to repeat:** **a malicious user reports the latest iPhone at $0.01 ⇒ price-drop notifications fire to thousands of subscribers ⇒ they rush to Amazon, find the normal price** ⇒ ⭐ **_"damaging our credibility and user trust."_**

- ⭐ **Why it's existential, not cosmetic:** **_"Our notification system's effectiveness depends entirely on data accuracy."_**

⚠ **Rung labels are mine.**

#### Good — consensus ("validate by committee")

- **Approach:** ⭐ **hold incoming reports in a `pending validation` state. A consensus table tracks how many UNIQUE users reported each specific price for each product within a window (say 1 hour).** **Accept only at threshold.**
- ⭐⭐ **And the threshold SCALES with risk:** **3 independent users for popular products, 2 for less popular** — ⭐ **but a $500 drop on the latest iPhone might need 5 confirmations, while a $2 change on a book needs 2.** ⭐ **User REPUTATION weights the count: reports from consistently accurate users count more.**
- ✅ ⭐⭐ **Why it defends well: a lone bad actor _"can't trigger false notifications because they need multiple accomplices"_**, and ⭐ **technical glitches (browser cache, network) _"are unlikely to affect multiple users simultaneously in the same way"_** ⇒ **filtered out automatically.**
- ⚠ **Challenges — and the first one is fatal for the product:**
    - ⚠⚠⚠ **It DELAYS the legitimate case, worst where it matters most.** ▸ **A niche product monitored by few users _"might take hours or even days to reach consensus threshold."_** ⭐ **_"Flash sales or limited-time offers could expire before enough users browse the product."_**
    - ⚠ **Popular products break it the other way:** **when Amazon drops prices on thousands of items at once, pending validations BACKLOG** ⇒ **delays even for products that reach consensus quickly.**
    - ⚠ **And it's still beatable:** **_"it's still possible for bad actors to coordinate and 'beat' your consensus system."_**

**Why climb:** consensus taxes every honest report to catch rare dishonest ones — and the tax lands hardest on exactly the time-sensitive deals users want.

#### ⭐⭐⭐ Great — trust but verify

> ⭐⭐ **HI: _"trust the extension data immediately, but verify it quickly with our crawlers when something looks suspicious."_**

- ⭐⭐⭐ **Accept the report at once and send notifications immediately.** **Then, if it looks fishy, queue a HIGH-PRIORITY verification crawl.**
- ⭐⭐ **The three suspicion triggers:**
    1. ⭐ **A huge price drop.**
    2. ⭐ **A reporter who has been wrong before** (reputation).
    3. ⭐⭐ **A popular product with many subscribers** — ▸ **i.e. high blast radius.**
- ⭐⭐ **Verification uses the EXISTING crawler infrastructure at high priority** ⇒ **checked **within 1–5 minutes** instead of waiting for the regular schedule.**
- ⭐⭐ **And what happens when it was wrong:** **send CORRECTION notifications** and **mark that user as less trustworthy.** ▸ ⭐ **Correcting publicly is what preserves trust — the mistake is visible and owned.**
- ⭐ **Hybrid where it's warranted:** **for really important products, wait for multiple reports before fully trusting.** **Conflicting reports from different users ⇒ dispatch a crawler immediately to settle it.**
- ✅ ⭐⭐⭐ **The payoff: _"most extension data gets processed immediately (fast notifications), but we catch the bad stuff quickly enough that it doesn't cause real damage."_**
- ⚠ **Challenges:** **significant extra complexity in the crawling infrastructure — priority queue management and rapid-response capability consume server resources** · ⚠⚠ **and verification crawling puts MORE load on Amazon**, ▸ **raising your risk of rate limiting or IP blocking.** ⭐ **Note the irony: the fix for untrusted data spends the exact resource that was scarce in DD1.**

> ⊕ ⭐⭐ **(mine) — the pattern name, and where else it applies.**
> 
> - ⭐⭐⭐ **Accept optimistically → verify asynchronously → correct publicly.** ▸ **Chosen over consensus because **consensus penalises the honest majority to catch a rare minority**, and the penalty falls on the time-sensitive case.**
> - ⭐ **The test for when it's right: is a wrong answer CHEAP TO REVERSE?** ▸ **Here yes — a correction email.** ⚠ **If the action were irreversible (a payment, a deletion), you'd verify FIRST and consensus would win.**
> - ▹ **Same family as `05p`'s at-least-once + idempotency: let the fast path be wrong occasionally, and make being wrong recoverable.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 3) ⭐⭐ How do we process price changes and notify users efficiently?

⚠ **The 2-hour cron _"fails to meet our non-functional requirement of delivering notifications within 1 hour"_**, and ⚠ **polling _"creates massive database load as we scale."_**

> ⭐⭐⭐ **The reframe, and it's the best one-line case for event-driven in your whole set:**
> 
> _"The fundamental problem with our current polling approach is that **we're asking the wrong question at the wrong time**. Instead of asking **'what changed in the last 2 hours?'** every 2 hours, we should be asking **'who cares about this change?'** immediately when a change happens."_
> 
> ▹ ⭐ **Same move as `05p §5.1`'s two-layer scheduler and `05r §5.2`'s CDC — but this is the clearest statement of WHY.**
> 
> ■ **— end of insert · HI write-up resumes below —**

⚠ **Two options, presented side by side — ⚠ HI never picks between them:**

||⭐ **Option A — CDC**|⭐ **Option B — dual writes**|
|---|---|---|
|**How**|**DB triggers publish events to Kafka on every price insert: product ID, old price, new price**|**the price collection service writes to the DB AND publishes to Kafka itself**|
|✅ **Wins**|⭐⭐ **automatic — _"we don't need to remember to publish events in our application code."_** **No application-level coordination**|⭐⭐ **you can FILTER: drop tiny fluctuations that wouldn't interest users, or BATCH rapid changes before publishing.** ⭐ **No trigger overhead on every update**|

- ⭐ **Either way the consumers are identical:** **read price-change events from Kafka → query Subscriptions for users whose thresholds are triggered → send email.**
- ⭐⭐ **And the efficiency argument:** **_"we only process actual price changes rather than expensive table scans of millions of records."_** ▸ **Most products don't change price often, so **even at scale the event volume is manageable.** One query per price drop finds all affected subscribers.**

> ⊕ ⚠⚠ **(mine, not HI) — HI doesn't pick, but DD2 already picked for it. Dual writes.**
> 
> - ▸ **§5.2's design accepts extension data immediately but gates SUSPICIOUS changes behind verification.** ⚠⚠ **With CDC, the DB trigger fires the moment the row is inserted — the notification is already on its way before you can gate it.**
> - ⭐⭐ **Dual writes puts the decision in the application, which is exactly where the suspicion check lives.** ▸ **The service writes the price, evaluates the triggers, and publishes the notification event only when it's confident — or publishes after verification returns.**
> - ⭐⭐ **Say it as the tiebreaker: _"I'd use dual writes rather than CDC, because DD2's trust-but-verify needs an application-level gate between storing a price and notifying on it — and a database trigger gives me nowhere to put that."_**
> - ▹ ⚠ **And name the cost you're accepting: dual writes can diverge (DB succeeds, Kafka fails).** ⭐ **Tolerable here because the NFRs say eventual consistency is fine and a missed notification is recoverable on the next price check.**
> 
> ■ **— end of insert · HI write-up resumes below —**

### 4) ⭐⭐ How do we serve fast price-history queries?

⚠ **The problem:** **prices in a plain Postgres table indexed on `(product_id, timestamp)` won't hit <500ms for popular products.** ▸ **_"Popular products might have price data points every few hours for several years, resulting in many thousands of records per product."_** ⚠ **A 2-year chart means aggregating all of it into buckets, and _"raw database queries struggle with this aggregation workload."_**

⚠ **Rung labels are mine.**

#### Good — scheduled pre-aggregation

- **Approach:** ⭐ **a nightly batch job computes daily, weekly and monthly summaries per product** — **average, minimum, maximum, opening and closing price per period** — **into a `price_aggregations` table with a `granularity` column.**
- ⭐ **Charts query the aggregation table, not raw prices:** **a 30-day chart reads daily rows, a 2-year chart reads monthly rows.** ⭐ **With an index on `(product_id, granularity, date)`, _"these queries return dozens of pre-computed records in milliseconds instead of aggregating thousands of raw price points."_**
- ⚠ **Challenges:** ⭐ **data is up to 24 hours stale** — ▹ **HI judges that acceptable, since _"users are looking at historical trends rather than real-time prices"_** · **extra storage for the summaries, scaling linearly with products × periods.**

**Why climb:** you're building and operating an aggregation pipeline to make a general-purpose database do something a specialised one does natively.

#### ⭐⭐ Great — TimescaleDB

- ⭐⭐ **Approach: TimescaleDB, a time-series EXTENSION for Postgres** (`04d`). ▸ ⭐ **The key argument is operational: you're already on Postgres for users, products and subscriptions, so this gives specialised time-series performance _"within the same database ecosystem."_**
- ⭐⭐ **No pre-computation at all — aggregate on demand:**

```sql
SELECT time_bucket('1 day', timestamp), avg(price)
FROM prices WHERE product_id = ?
GROUP BY 1
```

- ⭐⭐ **_"and get results in milliseconds even with billions of price records."_** ▸ **What makes it work: automatic partitioning and compression** (`01f`).
- ✅ ⭐⭐ **And the simplicity payoff: no aggregation jobs, no second database system, and users can request ANY time range or granularity on demand.**
- ▹ ⭐⭐ **The alternative named, with the trade-off:** **_"Alternatives like ClickHouse could provide even higher analytical performance, but TimescaleDB offers the best balance of performance and operational simplicity by keeping our entire data stack unified."_** ▸ ⭐ **Worth repeating — it shows you're weighing operations, not just benchmarks.**

> ⊕ ⚠⚠ **(mine, not HI) — there is NO storage math in this write-up, and the omission hides a real design decision.**
> 
> - ⚠ **HI says the Price table _"will grow to billions of rows"_ and never sizes it.** ▹ **Compare `05k` and `05r`, which both did storage math.**
> - ⭐⭐⭐ **And the decision it hides: do you write a row per OBSERVATION or per CHANGE?** ▸ **The schema is `(productId, timestamp, price)`, append-only — which reads as per-observation.** ⚠ **500M products checked even a few times a day is BILLIONS of rows daily, and almost all of them record no change.**
> - ⭐⭐⭐ **Store only CHANGES.** ▸ **Most prices are stable, so the table collapses by orders of magnitude.** ⭐ **The chart renders as a STEP FUNCTION — price held at X from `t1` until the next row — which is also how a price chart should look.**
> - ⭐ **Say it in one line:** _"I'd only write a row when the price actually differs from the last recorded value, with a separate `lastChecked` on the product so we still know the data is fresh."_ ▸ **That `lastScraped` field is already in HI's Product schema, so the design is half there.**
> 
> ■ **— end of insert · HI write-up resumes below —**

---

## 6 · Final Design

▹ ⭐ **HI's own admission: _"I'll admit the drawing got a little out of hand with all the crossing arrows."_** ⚠ **Layout and arrows are mine; components and field lists are HI's.**

```
Amazon.com   ⚠⚠ NO API · actively discourages scraping · ~1 req/sec per IP
  ▲                 📐 500M ÷ 1/sec = 15+ YEARS for one crawler
  │
  ├──◄── Crawler ◄── Frontier Queue  ⭐⭐ PRIORITY queues
  │         │           high = many subscriptions / frequent searches
  │         │           ⭐ feedback loop: successful notifications raise priority
  │         │           ⭐⭐ + HIGH-PRI VERIFICATION JOBS from §5.2 (1–5 min)
  │         └─ Scheduler
  │
  └──◄── ⭐⭐⭐ 1M CHROME EXTENSION USERS  — the real crawler
              DOM-parses the product page the user is already on
              ⇒ real-time prices for popular items, for free
              ⇒ also DISCOVERS unknown products
              │
              ▼
         Price Update Service   ⭐⭐ the trust-but-verify gate
              │  accept immediately → notify immediately
              │  suspicious? (big drop · bad reporter · many subscribers)
              │    → queue a verification crawl, correct + downgrade if wrong
              │  ⊕ this gate is WHY dual writes beats CDC — see §5.3
              │
              ├──► Price DB (TimescaleDB)                        04d · 02g
              │      Price: productId · timestamp · price
              │      ⭐ append-only · billions of rows · eventual consistency
              │      ⭐⭐ SELECT time_bucket('1 day', timestamp), avg(price)
              │         … GROUP BY 1   ⇒ ms, no pre-aggregation jobs
              │      ⭐ automatic partitioning + compression
              │      ⊕ write a row only on CHANGE, not per observation —
              │        chart renders as a step function
              │
              └──► Price Change Stream (Kafka)                        02c
                        │  ⊕ dual writes, so the app can filter tiny
                        │    fluctuations and batch rapid changes
                        ▼
                   Worker ──► Send Email
                        ⭐ one query per change: who has threshold ≥ new price?
                        ⭐⭐ "who cares about this change?" on the write —
                           NOT "what changed?" on a 2-hour timer

Client (website or extension)
  │  GET  /products/{id}/price?period=30d&granularity=daily
  │  POST /subscriptions {product_id, price_threshold, notification_type}
  ▼
API Gateway  — auth · rate limiting · routing                        02d
  │
  ├──► Price History Service   ⭐ read-heavy, many concurrent chart queries
  │         └──► Price DB (above)
  │
  └──► Subscription Service    ⭐ CRUD on subscriptions
            └──► Primary DB (Postgres)
                   Product:      id · amazonId · lastScraped
                   Subscriptions: id · userId · productId · priceThreshold
                   Users
                   ⭐⭐ split from Price DB on FOUR axes: size · access
                      pattern · optimisations needed · consistency
```

---

## 7 · Expected at Each Level

|Level|The bar for Price Tracking|
|---|---|
|**Mid**|**A working HLD covering both FRs, plus a straightforward schema (products, users, subscriptions, price history).** ⭐ **Understand the basic challenge of getting price data from Amazon and propose simple scraping, _"even if it's not scalable."_** ▹ **Suggesting "poll every product frequently" is fine — but ⭐ with guidance you should recognise the scale limit and see why PRIORITISATION is necessary.**|
|**Senior**|⭐⭐ **Quickly identify that DATA COLLECTION is the core technical challenge and drive toward the Chrome extension solution.** ⭐ **Understand the trade-offs between crawling strategies, and that 500M products needs _"either immense resources or endless time."_** ⭐⭐ **Explain why polling doesn't scale and propose event-driven alternatives with message queues.** ▹ **Go deep on a couple of dives — _"even if not the ones I have above."_**|
|**Staff+**|⭐⭐⭐ **Proactively recognise that the extension _"isn't just a user feature"_ but the solution to the data-collection scaling problem.** ⭐ **Discuss system EVOLUTION: how to start simple but design for eventual scale.** ⭐⭐ **Understand business implications — e.g. _"why data validation affects user trust and retention, not just technical correctness."_** ⭐⭐⭐ **And HI names what strong candidates raise UNPROMPTED: handling Amazon's anti-scraping measures · managing extension user PRIVACY · planning for Amazon changing their page structure.**|

> ⊕ ⭐⭐ **(mine) — HI names three unprompted staff topics and answers none. Here's a line for each.**
> 
> |Topic|One line to say|
> |---|---|
> |⭐⭐ **Extension privacy**|**_"The extension sees every Amazon page the user visits, so I'd send only product ID and price — no URLs with session or affiliate parameters, and no user identifier on the price report. Collection is disclosed in the extension permissions, and reputation is tracked against an anonymous install ID, not an account."_**|
> |⭐ **Anti-scraping**|**_"Rotate residential IPs, respect `robots.txt` where it binds us, back off hard on 429s, and keep the extension as the primary source precisely so our crawl volume stays low enough not to attract attention."_**|
> |⭐ **Page-structure changes**|**_"DOM selectors are versioned config, not code. A parse-success-rate metric per selector alerts us when Amazon changes the page, and the extension falls back to reporting nothing rather than reporting garbage."_**|
> 
> ▸ ⭐⭐ **That last one matters most: a silent parse failure is worse than an outage, because it feeds wrong prices into notifications.**
> 
> ■ **— end of insert —**

---

## Quick Recall (pass 3+)

|Use / Question|Price Tracking answer|
|---|---|
|Calibration|⭐ Evan King · Jun 2025 · **"medium"** · ⚠ **"Asked at" shows a bare `B`, Amazon, +1 — 3 companies, first truncated; don't guess** · ⚠⚠ **NO Pattern callouts, first since `05h`.** ⭐⭐⭐ **`05r` is the close sibling — crawling tiers, CDC and the aggregation fork all recur.** ⭐⭐ **What's NEW and worth the pass: the extension as a free crawler (DD1) + trust-but-verify (DD2).** ⭐ **ONE pass, lean on `05r` cross-refs.** ⚠ **DD3 has no ladder and never picks**|
|⭐⭐⭐ Design driver|⭐⭐⭐ **You don't own the data and the arithmetic says you can't go get it.** 📐 **500M ÷ 1 req/sec per IP = 15+ YEARS for one crawler; 1,000 IPs = 5+ days per refresh with millions of changes missed.** ⭐⭐ **Three responses: (1) don't crawl evenly ⇒ Pareto tiers (2) ⭐⭐⭐ don't crawl at all where you needn't ⇒ 1M extensions are already on those pages (3) ⚠⚠ but now the data comes from strangers ⇒ trust-but-verify.** ⭐⭐ **Second axis: price history is TIME-SERIES — billions of rows, append-only, bucketed queries, tolerates staleness ⇒ its own store.** ▸ ⭐ **First problem in the set where the DATA SOURCE IS AN ADVERSARY**|
|⭐⭐⭐ The constraint to state early|⚠⚠ **_"Amazon is not friendly to price tracking services. They don't provide an API, actively discourage scraping, and implement rate limiting (typically 1 request per second per IP address)."_** ⭐ **HI's framing: be _"polite"_ to Amazon while serving millions**|
|FRs / NFRs|**view price history · subscribe with a price threshold · ⭐⭐ and the Chrome extension itself (1M users, history on the Amazon page, one-click subscribe).** Below: search/discovery · multi-retailer comparison · reviews. **NFRs: availability > consistency · ⭐⭐ 500M products · <500ms history queries · ⭐⭐ notifications within 1 HOUR.** Below: strong consistency · sub-minute updates|
|📐 Numbers|**1M extension users · 500M products · ~3,000 new/day · <500ms queries · 1-hour notifications · ⚠ the naive cron is every 2 HOURS (already violating the NFR) · consensus 2–5 reports · verification crawl 1–5 min · pre-aggregation 24h stale.** ⚠ **NO storage math anywhere — see below**|
|Entities / API|**Product · User · Subscription (links user→product with the threshold) · ⭐⭐ Price (time-series, per-product price changes).** `GET /products/{id}/price?period=30d&granularity=daily` · `POST /subscriptions {product_id, price_threshold, notification_type}`. ⭐ **`product_id` in the PATH _"for better caching and REST compliance."_** ⭐⭐ **`granularity` is load-bearing — daily averages for long periods, hourly for recent — it's what makes §5.4's bucketing possible**|
|⭐⭐ Data Flow — the hidden requirement|⭐⭐ **_"the **hidden requirement** is that we need to be able to get the data in the first place!"_** **(1) crawlers AND the extension collect prices (2) data is VALIDATED and stored (3) changes trigger events (4) email on threshold breach.** ▸ ⭐ **Step 1 already names the extension as a collector and step 2 already says "validated" — the data flow forecasts DD1 and DD2**|
|⭐⭐⭐ The DB split — 4 reasons|**Primary DB (Users, Products, Subscriptions): relatively SMALL · traditional CRUD · ordinary indexing · normal consistency.** **Price DB: ⭐⭐ BILLIONS of rows · ⭐⭐ append-only · ⭐⭐ needs time-series optimisations · ⭐ tolerates eventual consistency.** ▸ ⭐⭐ **Four independent differences — the crispest version of this reasoning in your set.** ▹ **`05h §4.3`'s three-part rule also fully satisfied**|
|⭐⭐ Service splits|**Price History vs Crawler: history handles many CONCURRENT READS from chart viewers; the crawler runs on a SCHEDULE with consistent writes ⇒ scale each independently.** **Subscription vs Price History: account CRUD vs read-heavy price queries**|
|⚠⚠ The naive notification path|**cron every 2 hours → query Price for changes in the window → for each, query Subscriptions for `threshold >= new_price` → email → ⭐ mark as sent to avoid duplicates.** ⚠⚠ **Knowingly non-compliant: up to 2 hours against a 1-hour NFR, plus _"expensive database scans every few hours"_**|
|⭐⭐ DD1 — split the problem first|**(1) DISCOVERY: find all 500M at launch + the ~3,000 Amazon adds daily. (2) MONITORING: keep known prices updated, prioritising which to check.** ▸ **Same rate limit, but separating them produces better solutions**|
|⚠⚠ DD1 Bad — traditional crawler|**seed URLs → extract product links → recurse; frontier queue + visited tracker; "customers also viewed" feeds the frontier.** 📐 ⭐⭐⭐ **_"over 15 years just to visit each product page once"_; 1,000 IPs ⇒ _"5+ days for a complete catalog refresh, during which millions of price changes will go undetected."_** ⚠ **DISCOVERY LAG — new products _"might not be found for weeks or months"_** · ⚠ **popular products go stale between visits** · ⚠ **thousands of servers is _"economically unfeasible"_**|
|⭐⭐ DD1 Good — Pareto tiers|⭐⭐ **_"we have fundamentally limited crawling resources, so we better use them wisely."_** **Popularity is PARETO — a few products get most attention, long tail nobody cares about.** ⭐⭐ **Free priority signals: (1) many SUBSCRIPTIONS = users literally waiting (2) frequent SEARCHES = current interest (3) ⭐⭐ a FEEDBACK LOOP where successful notifications raise the score ⇒ _"a self-reinforcing system."_** **Schedule: high every few hours · medium daily · low weekly+.** ⚠ **Challenge: COVERAGE GAPS for new/trending products with no signal yet — _"a hot new product release might not get discovered quickly"_, missing the most volatile window**|
|⭐⭐⭐ DD1 Great — the extension IS the crawler|⭐⭐⭐ **_"it's actually our secret weapon for data collection."_** **1M users browsing Amazon = a DISTRIBUTED COLLECTION NETWORK; the extension DOM-parses the page and reports product ID, price and metadata.** ⭐⭐ **Three free properties: (1) real-time data for products users ACTIVELY VIEW ⇒ popular items prioritised automatically (2) ⭐⭐ DISCOVERY — an unknown product page visited adds it to the Product table, fixing the Good rung's gap (3) crawlers only handle what the extension hasn't seen.** ⭐⭐⭐ **The line: _"Instead of fighting Amazon's rate limits with massive crawler infrastructure, we leverage user behavior"_ — _"turning our biggest constraint into our competitive advantage."_** ⚠ **Depends on user adoption ⇒ niche gaps · ⚠⚠⚠ and _"user-generated price reports could be manipulated or incorrect"_ ⇒ DD2**|
|⭐⭐⭐ DD1 — you don't need extension knowledge|⭐ **HI: _"If you're thinking… 'I know nothing about Chrome Extensions!' don't sweat it."_** ⭐⭐ **The prompt you'll actually get: _"Your extension is installed on millions of browsers actively viewing product pages. **Can you make use of that somehow?**"_** ▸ ⭐⭐ **The skill tested is noticing that an existing asset solves a different problem.** ⭐ **General move: something mentioned TWICE in the prompt is load-bearing**|
|⊕⭐⭐ Client-as-tier, three stages|`05h` **caches its OWN swipes** (optimisation for itself) → `05k` **records and computes its OWN activity** (primary write tier for itself) → ⭐⭐⭐ `05s` **collects data about OTHER products for OTHER users** (the client is your DATA SOURCE). ⭐⭐⭐ **Generalisation: when you can't afford to collect the data, find who is already looking at it** — crowdsourced maps, traffic, outage detection, availability|
|⚠⚠ DD2 the scenario|**a malicious user reports the latest iPhone at $0.01 ⇒ notifications fire to thousands ⇒ they rush to Amazon and find the normal price ⇒ _"damaging our credibility and user trust."_** ⭐ **_"Our notification system's effectiveness depends entirely on data accuracy"_**|
|DD2 Good — consensus|**hold reports in `pending validation`; a consensus table counts UNIQUE users reporting the same price per product within ~1 hour.** ⭐⭐ **Threshold SCALES with risk: 3 for popular, 2 for less popular, ⭐ 5 for a $500 iPhone drop vs 2 for a $2 book change; REPUTATION weights the count.** ✅ **A lone actor _"can't trigger false notifications because they need multiple accomplices"_, and glitches _"are unlikely to affect multiple users simultaneously."_** ⚠⚠⚠ **But it DELAYS the legitimate case worst: a niche product _"might take hours or even days"_, and _"flash sales or limited-time offers could expire before enough users browse."_** ⚠ **Mass sales create validation BACKLOGS.** ⚠ **And _"bad actors [can] coordinate and 'beat' your consensus system"_**|
|⭐⭐⭐ DD2 Great — trust but verify|⭐⭐ **_"trust the extension data immediately, but verify it quickly with our crawlers when something looks suspicious."_** **Accept + notify at once.** ⭐⭐ **Three suspicion triggers: a huge drop · a reporter wrong before · ⭐⭐ a popular product with many subscribers (blast radius).** ⭐⭐ **Verification runs on the EXISTING crawler at high priority ⇒ checked in 1–5 MINUTES.** ⭐⭐ **Wrong ⇒ send CORRECTION notifications and downgrade that user's trust** — ▸ **correcting publicly is what preserves trust.** ⭐ **Conflicting reports ⇒ dispatch a crawler immediately.** ✅ ⭐⭐⭐ **_"most extension data gets processed immediately… but we catch the bad stuff quickly enough that it doesn't cause real damage."_** ⚠ **Costs priority-queue complexity and ⚠⚠ MORE load on Amazon — the fix spends the exact resource DD1 said was scarce**|
|⊕⭐⭐⭐ The pattern + when it fails|⭐⭐⭐ **Accept optimistically → verify asynchronously → correct publicly.** **Beats consensus because consensus PENALISES THE HONEST MAJORITY to catch a rare minority, and the penalty lands on the time-sensitive case.** ⭐ **The test: is a wrong answer CHEAP TO REVERSE? Here yes — a correction email.** ⚠ **If the action were irreversible (a payment, a deletion) you'd verify FIRST and consensus would win.** ▹ **Same family as `05p`'s at-least-once + idempotency**|
|⭐⭐⭐ DD3 the reframe|⭐⭐⭐ **_"we're asking the wrong question at the wrong time. Instead of asking **'what changed in the last 2 hours?'** every 2 hours, we should be asking **'who cares about this change?'** immediately when a change happens."_** ▹ **same move as `05p §5.1` and `05r §5.2` — but the clearest statement of WHY**|
|⚠ DD3 — CDC vs dual writes|⚠ **HI presents both and NEVER picks.** **CDC: DB triggers publish to Kafka on insert (productId, old price, new price). ✅ ⭐⭐ automatic — _"we don't need to remember to publish events in our application code."_** **Dual writes: the collection service writes the DB AND publishes. ✅ ⭐⭐ you can FILTER tiny fluctuations and BATCH rapid changes, and avoid trigger overhead.** **Consumers identical either way: read event → query Subscriptions for triggered thresholds → email.** ⭐⭐ **Efficiency: _"we only process actual price changes rather than expensive table scans"_ — most prices rarely move, so event volume stays manageable**|
|⊕⚠⚠ DD3 — DD2 already picked: dual writes|▸ **§5.2 accepts immediately but gates SUSPICIOUS changes behind verification.** ⚠⚠ **With CDC the trigger fires on insert — the notification is gone before you can gate it.** ⭐⭐ **Dual writes puts the decision in the application, where the suspicion check lives.** ⭐⭐ **The tiebreaker line: _"I'd use dual writes, because DD2's trust-but-verify needs an application-level gate between storing a price and notifying on it — a database trigger gives me nowhere to put that."_** ▹ ⚠ **Name the cost: dual writes can diverge (DB succeeds, Kafka fails) — tolerable because eventual consistency is explicitly fine and a missed notification recovers on the next check**|
|⚠ DD4 the problem|**plain Postgres on `(product_id, timestamp)` misses <500ms.** **_"Popular products might have price data points every few hours for several years, resulting in many thousands of records per product"_**, and a 2-year chart must bucket all of it — ⚠ **_"raw database queries struggle with this aggregation workload"_**|
|DD4 Good — pre-aggregation|⭐ **nightly job computes daily/weekly/monthly avg, min, max, open, close into `price_aggregations` with a `granularity` column.** **Charts read aggregates: 30-day → daily rows, 2-year → monthly.** ⭐ **Index `(product_id, granularity, date)` ⇒ _"dozens of pre-computed records in milliseconds."_** ⚠ **24h stale** — ▹ **HI calls that acceptable since users want trends not live prices** · **extra storage, linear in products × periods**|
|⭐⭐ DD4 Great — TimescaleDB|⭐⭐ **a time-series EXTENSION for Postgres** (`04d`) — ⭐ **and the key argument is OPERATIONAL: you're already on Postgres, so you get time-series performance _"within the same database ecosystem."_** ⭐⭐ **No pre-computation: `SELECT time_bucket('1 day', timestamp), avg(price) FROM prices WHERE product_id = ? GROUP BY 1`** ⇒ **_"results in milliseconds even with billions of price records"_** via **automatic partitioning + compression.** ✅ **No aggregation jobs, no second DB, ANY range or granularity on demand.** ▹ ⭐⭐ **_"Alternatives like ClickHouse could provide even higher analytical performance, but TimescaleDB offers the best balance of performance and operational simplicity by keeping our entire data stack unified"_ — repeat this; it shows you weigh operations, not benchmarks**|
|⊕⚠⚠ No storage math — and what it hides|⚠ **HI says _"billions of rows"_ and never sizes it** (contrast `05k`, `05r`). ⭐⭐⭐ **The hidden decision: a row per OBSERVATION or per CHANGE?** **The schema `(productId, timestamp, price)` reads as per-observation — ⚠ 500M products checked even a few times daily is BILLIONS of rows/day, almost all recording no change.** ⭐⭐⭐ **Store only CHANGES: most prices are stable, so the table collapses by orders of magnitude, and the chart renders as a STEP FUNCTION** — which is how a price chart should look anyway. ⭐ **One-liner: _"write a row only when the price differs from the last recorded value, with `lastChecked` on the product so we still know the data is fresh"_** ▸ **`lastScraped` is already in HI's schema, so it's half there**|
|⊕⭐⭐ Staff topics HI names but never answers|⭐⭐ **PRIVACY: _"send only product ID and price — no URLs with session or affiliate parameters, no user identifier on the report; collection disclosed in the extension permissions; reputation tracked against an anonymous install ID."_** ⭐ **ANTI-SCRAPING: _"rotate residential IPs, honour `robots.txt` where it binds us, back off hard on 429s, and keep the extension primary so crawl volume stays low."_** ⭐ **PAGE CHANGES: _"DOM selectors are versioned config, not code; a parse-success-rate metric per selector alerts on Amazon changing the page, and the extension reports NOTHING rather than garbage."_** ▸ ⭐⭐ **That last matters most — a silent parse failure is worse than an outage, because it feeds wrong prices into notifications**|
|Levels (short)|**Mid:** working HLD + schema; understand the collection challenge, propose simple scraping _"even if it's not scalable"_; ⭐ **with guidance, recognise the scale limit and why PRIORITISATION is needed** · **Senior:** ⭐⭐ **identify DATA COLLECTION as THE challenge and drive to the extension**; know crawling trade-offs and that 500M needs _"either immense resources or endless time"_; ⭐⭐ **explain why polling doesn't scale and propose event-driven with queues**; go deep on a couple of dives · **Staff+:** ⭐⭐⭐ **proactively see the extension _"isn't just a user feature"_**; discuss EVOLUTION (start simple, design for scale); ⭐⭐ **business implications — _"why data validation affects user trust and retention"_**; ⭐⭐⭐ **raise unprompted: anti-scraping · extension PRIVACY · Amazon changing page structure**|

---

> 🔗 **HI source:** https://www.hellointerview.com/learn/system-design/problem-breakdowns/price-tracking-service