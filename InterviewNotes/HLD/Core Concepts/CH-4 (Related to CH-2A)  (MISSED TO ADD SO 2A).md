# Data Modeling — Deep Dive

> Hello Interview · Core Concepts (deep dive) · File `01c`. Overview in `01_core_concepts §3`. **Non-repetition:** index _internals_ → `01d_database_indexing`; shard _mechanics_ → `01_core_concepts §6`. This file = **DB-type choice + schema design + the whiteboard checklist.**

---

## The Meta-Rule (read first)

▸ **CRUX**

- **Not the focus.** The bar is far lower than a data-engineering interview — you don't normalize everything or draw a full ERD. Design something **clear, functional, aligned with requirements**, then move on.
- **Shows up twice in the delivery framework:** (1) **Core Entities** during requirements (≈1:1 with tables), (2) a **schema sketch** in HLD next to the DB box — key fields, relationships, a note on indexing/partitioning.
- A sloppy model causes pain later (consistency, scaling, auditability). A "good enough" one keeps the conversation where it belongs.

---

## Step 1 — Pick the Database Type

▸ **CRUX — default to relational (PostgreSQL).** Resist exotic choices to look clever; pick a specialized model only when requirements _clearly_ signal it. Knowing _when_ each fits shows tradeoff thinking.

|Model|What it is|Pick when (over SQL)|Data-modeling impact|Examples|
|---|---|---|---|---|
|**Relational (SQL)** ⭐|tables, fixed schema, FKs, **ACID**|**default**; clear entities + relationships; strong consistency|normalized tables, joins|Postgres, MySQL, SQLite|
|**Document**|JSON-like docs, flexible schema|**evolving/unknown schema**, deeply nested data, records with very different shapes|embed/nest; denormalize aggressively|MongoDB, Firestore, CouchDB|
|**Key-Value**|fetch value by exact key; blazing fast, minimal queries|caching, sessions, feature flags, high-write single-key lookups|very flat; duplicate across keys per access pattern|Redis, DynamoDB, Memcached|
|**Wide-Column**|column families, rows vary in columns|**massive writes**, time-series, append+aggregate|design around query patterns; **time is first-class**; key by `(user_id, timestamp)`|Cassandra, HBase|
|**Graph**|nodes + edges, traverse relationships|**almost never in interviews**|—|Neo4j, Neptune|

▹ **SQL scalability knock is exaggerated** — read replicas, sharding, connection pooling, caching. FB/Airbnb run on relational foundations. Scaling is about how you _architect around_ the DB, not just the DB. ▹ **Key-value "over SQL" is misleading** — you usually use **both**: SQL = source of truth, Redis = cache for hot data.

⚠ **Rejection traps:**

- **Graph DB** — sounds sophisticated, adds operational complexity. Even LinkedIn/Twitter/FB model core relationships in **MySQL**. If it's good enough for the largest social graph, it's good enough for your interview.
- **Document DB by default** — interviews scope requirements tightly, so "evolving schema" rarely applies. Only reach for it if the interviewer _explicitly_ says rapidly-changing structures.

---

## Step 2 — Schema Design

### Start with Requirements — the 3 factors that drive everything

▸ **CRUX** — every schema technique (keys, normalization, indexes, sharding) is just a tool to serve these three:

1. **Data volume** — how much / where it can physically live (may force splitting user vs post data onto separate stores → distinct schemas that reference each other).
2. **Access patterns** — ⭐ **the most important factor.** _How will data be queried?_ Comes straight from your APIs: _"what queries does each endpoint need?"_ A "recent posts by followed users" feed → denormalized data or careful indexes.
3. **Consistency requirements** — strong (financial: no partial charge → keep related data in one ACID DB) vs eventual (activity feed: a like showing up seconds late is fine → distribute freely).

▸ **In the interview, tie choices back to these out loud:** _"Since feeds must load fast and likes can be eventually consistent, I'll denormalize like-counts into the posts table."_ That's reasoning, not memorizing.

### Entities, Keys & Relationships

▸ **CRUX**

- Map core entities → tables/collections. Each needs a **primary key**.
- **Use system-generated IDs** (`user_id`, `post_id`), **not business data** (email) — stable when business rules change.
- **Relationships:** **1:N** (user → posts) · **N:M** (users ↔ likes ↔ posts) · **1:1** (rare — usually a sign to merge the two tables).

```
users:    id (PK), username, email
posts:    id (PK), user_id (FK → users.id), content, created_at
comments: id (PK), post_id (FK → posts.id), user_id (FK → users.id), content
likes:    user_id (FK → users.id), post_id (FK → posts.id)
```

- **Foreign keys → referential integrity** (no orphaned records: a post can't reference a deleted user).
    - **Cost:** DB validates every insert/update. **At very large scale**, some drop FKs for write speed and enforce integrity in the app. Mentioning this tradeoff scores points.
- **Constraints** (`NOT NULL`, `UNIQUE`, `CHECK`) enforce correctness at the DB level (unique emails, positive prices) — at the cost of write overhead.

### Indexing for Access Patterns

▸ **CRUX** — index the columns your **important queries** hit; **connect each index to an API endpoint** out loud.

- `posts.user_id` → find a user's posts.
- `posts.created_at` → recent posts chronologically.
- **Composite `(user_id, created_at)`** → a user's _recent_ posts efficiently.
- _"`GET /users/{id}/posts` needs an index on `posts.user_id`."_ ← this is the phrasing that scores.

▹ Index internals (B-tree, hash, composite ordering) → `01d_database_indexing`.

### Normalization vs Denormalization

▸ **CRUX — start normalized, denormalize only when a real read problem shows up.**

- **Normalize** = each fact stored **once** (user data only in `users`). Prevents update anomalies.
- **Denormalize** = duplicate to skip joins → faster reads.

⚠ **The denormalization problem → fix:**

- **Problem —** copy `username` into every post; user renames → you must update _every_ post. Miss one → inconsistent data (worse than the perf problem you were solving).
- **Fix (preferred) —** keep the **source of truth normalized**, put a **cache in front** holding the denormalized / pre-computed / pre-joined shape. Clean truth + fast reads.

**Legit denormalization exceptions:** analytics/reporting (aggregates over rarely-changing data) · event logs / audit trails (point-in-time snapshot) · heavily read-optimized systems like search (speed > consistency).

### Scaling & Sharding

▸ **CRUX — shard by your primary access pattern** so related data stays together.

- Mostly query "posts by user" → **shard by `user_id`** → a user's posts on one shard, no cross-shard query.

⚠ **Time-range sharding trap:**

- **Problem —** sharding by time sounds great for "recent posts," but **all current writes hit the latest shard → hot shard.** Anti-pattern for write-heavy systems.
    
- **When it's fine —** archival / analytics (recent data read-heavy, writes spread out).
    
- **Avoid cross-shard queries** — timeline showing posts from many followed users, sharded by `user_id`, means querying many shards + merging. Expensive.
    
- **Shard key is ~permanent** and touches every query — choose from access patterns deliberately.
    

▹ Shard strategies (hash / range / directory), consistent hashing → `01_core_concepts §6–7`.

---

## The Whiteboard Checklist (do this when you draw the DB in HLD)

> This is the actual sequence to run. Memorize it.

1. **DB type** — relational unless requirements scream otherwise.
2. **Columns** per entity — only those needed for the functional reqs (skip obvious ones).
3. **Keys** — primary key per entity, foreign keys per relationship.
4. **Indexes** — which columns, tied to which endpoints.
5. **Denormalize?** — only for a real read hot-path (else cache it instead).
6. **Shard?** — only after justifying it; shard key = primary access pattern.

---

## Quick Recall (pass 3+)

|Situation|Reach for|
|---|---|
|Default database|Relational / PostgreSQL|
|Evolving / unknown schema|Document (Mongo) — rare in interviews|
|Cache, sessions, feature flags|Key-value (Redis) — alongside SQL|
|Massive writes / time-series / IoT|Wide-column (Cassandra), key `(id, timestamp)`|
|Relationship traversal|Graph — but ⚠ almost never; use SQL|
|What drives the schema|volume · **access patterns** · consistency|
|Primary key choice|system-generated ID, not email|
|Prevent orphaned records|foreign keys (drop at huge scale for write speed)|
|Query hits a column often|index it; tie to the endpoint|
|Recent-per-user query|composite index `(user_id, created_at)`|
|Default normalization stance|normalized; denormalize only on real read pain|
|Need denormalized reads safely|normalized source of truth + denormalized cache|
|Outgrew one DB|shard by primary access pattern|
|"Recent" sharding|⚠ time-range = hot shard; only for archival|
|Whiteboard DB steps|type → columns → keys → indexes → denorm? → shard?|
QR => https://www.hellointerview.com/learn/system-design/core-concepts/data-modeling/quick-reference