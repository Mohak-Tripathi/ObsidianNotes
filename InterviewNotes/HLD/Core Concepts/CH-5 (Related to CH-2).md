# Database Indexing — Deep Dive

> Hello Interview · Core Concepts (deep dive) · File `01d`. Overview in `01_core_concepts §4`. **Calibration:** heavier for _infra_ roles. Full-stack/product roles → know _when & why_ to index + B-tree default + the two exceptions (geo, full-text). Depth below exceeds what full-stack usually needs.

---

## Why Indexes Exist

▸ **CRUX** — without an index, finding a row = **sequential scan of every row** (email lookup in 10M rows = 10M checks). An index is a **separate data structure** that gives a direct path to the data. Book analogy: table of contents vs reading every page.

**How it works physically** _(foundation, not asked unless DB-internals role):_

- ▹ **Where a DB actually lives** _(general infra, not indexing-specific — rarely asked head-on):_ a database is just a **server process running on a machine** (VM, physical box, k8s pod). Managed DBs (RDS, Aurora, Cloud SQL) still run on **VMs with CPU + RAM + SSD** — the provider only manages the infra, not the physics.
- Table data = a **heap file** (rows in no order). Data can only be processed **in RAM** → every query loads pages disk→RAM. Flow: **SSD → RAM (buffer pool / shared buffers) → CPU.** Frequently-hit pages stay cached → repeat queries much faster.
- No index → scan every page (millions of slow disk reads) — this is a **Full Table Scan.** Index → structured path → **minimize pages read.**
- ▹ **Random access is still slower than sequential even on SSD** (common misconception — smaller gap than HDD, but real). Makes indexing matter.

⚠ **Cost — indexes aren't free (Problem → when they hurt):**

- **Space:** each index needs disk, sometimes ~as much as the data.
- **Write penalty:** every insert/update must update the table **and every index on it** → one write → several disk writes.
- **When they hurt more than help:** write-heavy + read-rare tables (logging), and **small tables** (few hundred rows — scan is cheaper than traversing an index).
- ▹ Memory impact is often overblown (buffer-pool management). Still: monitor usage, don't create unnecessary indexes.

---

## Index Types

### B-Tree — the default ⭐

▸ **CRUX** — **when in doubt, B-tree.** Self-balancing, keeps data **sorted**, nodes have _hundreds_ of children (not 2).

- Each node sized to **one disk page (~8KB)** → finding `id=350` might take just **2–3 page reads** (root → internal → leaf).
- Handles **equality (`email='x'`) AND range (`age>25`)** equally well; stays balanced under random insert/delete.
- **Postgres** uses B-trees for PKs, unique constraints, most indexes. **Mongo** uses B+ trees (all data in leaves).
- **Why default:** sorted order (range + `ORDER BY`) · self-balancing (predictable perf) · minimizes I/O · both equality + range · no performance cliffs.

**Node roles (structure):**

|Node|Holds|Job|
|---|---|---|
|**Root**|separator keys + child pointers|entry point; first narrowing|
|**Internal**|separator keys + child pointers|keep narrowing the search|
|**Leaf**|indexed keys + row pointers (→ table page / row location)|identify the target table page|

- **Fan-out ≈ page size ÷ entry size** (not a fixed number). One 8KB page holds _hundreds_ of keys+pointers → hundreds of children → **shallow tree.**
- ▹ **Height mechanics:** grows **bottom-up** — starts as a single leaf page; when a page fills it **splits**, splits propagate upward, eventually forming internal nodes + a root. Even for millions of rows, typically **3–5 levels.** The DB never predefines height.
- **Mental model:** index pages are separate from table pages. A B-tree answers exactly one question — _"which table page holds this key?"_ — then **one table-page read** returns the row, instead of scanning the whole table.

### LSM Tree — for write-heavy workloads

▸ **CRUX** — B-tree write = find leaf → read → update → write back (**random seeks**). At 100K writes/s those seeks bottleneck. LSM flips to **append-only + sequential writes.**

- **Not a per-column index** — it's the **storage format for the whole table, sorted by primary key.** PK lookups very fast; secondary indexes need extra structures (Cassandra, DynamoDB GSIs/LSIs).

**Write path:**

1. **Memtable** — new writes go to an in-memory sorted structure (red-black tree / skip list). Fast (RAM).
2. **WAL (write-ahead log)** — every write also appended to disk log → durability, **sequential** append.
3. **Flush to SSTable** — when memtable fills (~few MB), freeze + flush to disk as an immutable **Sorted String Table** (one big sequential write).
4. **Compaction** — background merge of SSTables; removes duplicates/deletes; keeps file count + read perf manageable.

⚠ **The read cost (Problem → Fix):**

- **Problem —** a point query may check **memtable → immutable memtables → every SSTable** (newest→oldest) = dozens of files worst case.
- **Fix —** **Bloom filters** (per SSTable: "key definitely NOT here" → skip most files) · **sparse indexes** (key-range per block → skip SSTables out of range) · **compaction strategies** (size-tiered = less write amplification, more files; leveled = fewer files, more rewrites).
- **Net (CRUX):** despite these optimizations, LSM **fundamentally trades read perf for write perf** → ideal for write-heavy workloads.
- ▹ **When the trade-off is right:** systems that **write far more than they read** — metrics collection, audit logs, IoT / time-series ingestion, analytics — where queries are less frequent or tolerate slightly higher latency. For a user-facing app where every page load fires several queries, B-trees usually win. The interview signal is _knowing when each side of the trade-off applies._
- ▹ **Real-world examples** (LSM powers some of the most write-heavy systems on the internet):
    - **Cassandra** — handles Netflix's billions of viewing events; when you watch a show, that write lands without slowing playback.
    - **RocksDB** (built by Facebook) — storage engine under many databases; millions of social interactions/sec (likes, posts, messages) written to LSM for fast persistence.
    - **DynamoDB** — generally understood to use an **LSM-tree–style** architecture tuned for high write throughput. Its exact internals aren't public, and it does **not** dynamically switch storage engines based on access patterns _(correcting a common overclaim)_.

### Hash Index — exact-match only

▸ **CRUX** — a persistent hashmap: `hash(value) → bucket → row pointer`. **O(1) exact match**, but **useless for range/sort** (similar values scattered).

- **Rare in practice** — Postgres supports but B-tree is nearly as fast for equality _and_ does ranges. Shines only **in-memory** (Redis, MySQL MEMORY engine).
- ⚠ **Don't overemphasize in interviews** — "solves a problem we rarely have." B-tree covers almost every case you'd consider it for.

### Geospatial — location / proximity search

> **High value for your targets** (Swiggy/Zomato/Zepto/Uber-style "nearby" queries).

▸ **The problem (why B-tree fails):** lat/lng is a **2D** problem; two separate 1D B-tree indexes can't do it.

- Use lat index → get a **globe-spanning strip** at that latitude, then point-check each for longitude. Or intersect both → a **rectangle** far bigger than your circular radius, still must filter. Either way, slow.
- **Fix:** an index that understands 2D proximity. Three approaches:

|Approach|Idea|Trade-off|Used by|
|---|---|---|---|
|**Geohash** ⭐|recursively quarter the world → **base32 string**; nearby points **share prefix** → index string in a **regular B-tree**, do prefix/range scans|boundary edge case (neighbors across a grid line differ)|**Redis `GEOSEARCH`**|
|**Quadtree**|recursively split space into **4 quadrants** until ≤ threshold points; adaptive resolution|needs a **specialized tree**; rarer in prod now|Google Maps tiles (conceptually)|
|**R-tree**|flexible **overlapping rectangles** that adapt to data; handles points **and shapes** (polygons, roads)|overlap → may search multiple branches|**PostGIS**, MySQL (production default)|

▸ **Interview move (CRUX):** focus on **explaining the problem clearly**, then **contrast a tree-based approach with a hash-based approach.** Structure: (1) _why B-tree fails_ — it treats lat & lng as two independent dimensions; (2) **hash-based → geohash:** converts 2D coords into a 1D string that preserves proximity, so a **regular B-tree** on the geohash strings does proximity search; (3) **tree-based → R-tree:** groups nearby objects into overlapping rectangles / a hierarchy of bounding boxes → more flexibility and accuracy for shapes. **If you learn one: geohash.**

> **Say it like this (script):** "Traditional indexes like B-trees don't work well for spatial data because they treat latitude and longitude as independent dimensions. To efficiently search for nearby locations, we need an index that understands spatial relationships. Geohash is a hash-based approach that converts 2D coordinates into a 1D string, preserving proximity. This allows us to use a regular B-tree index on the geohash strings for efficient proximity searches. However, tree-based approaches like R-trees can offer more flexibility and accuracy by grouping nearby objects into overlapping rectangles, creating a hierarchy of bounding boxes."

Contrasting the two approaches is what demonstrates deeper understanding of the trade-offs. ▹ Geohash elegance: turns a 2D problem into 1D string prefix matching → leverages existing B-tree machinery, no special structure.

### Inverted Index — full-text search

▸ **The problem:** `WHERE content LIKE '%database%'` **can't use a B-tree** (B-tree only helps prefix `'database%'`). Match-anywhere → scan every char of every row.

- **Fix — flip the mapping:** instead of _document → words_, store **word → documents** (like a textbook index).

```
b-trees  -> [doc1, doc3]
fast     -> [doc1, doc2]
```

- **Analysis pipeline** (Elasticsearch/Lucene) before indexing: tokenize → lowercase → remove stop words ("the","and") → **stemming** (→ root form). So "Databases" matches "database", "DATABASE", "database's".
- **Beyond plain lookup, an inverted index adds:**
    - **Term-frequency analysis** — how often each word appears (feeds ranking).
    - **Relevance scoring** — which documents best match the query, not just which contain the word.
    - **Fuzzy matching** — finds close matches (e.g. "databas" → "database"), tolerating typos/partials.
    - **Phrase queries** — matches an exact sequence of words, not just the words in isolation.
- **Cost:** big storage + update overhead (doc changes → update every term's entry). → GitHub/Slack/docs search. Details → Elasticsearch deep dive.

---

## Optimization Patterns

### Composite Index (the common one)

> Full "why" here; `01c` name-drops `(user_id, created_at)`.

▸ **CRUX** — one index over **multiple columns in a specific order**, matching how you query.

- Feed query `WHERE user_id=123 AND created_at>X ORDER BY created_at DESC`:
    - Two separate indexes → find-by-user + find-by-date → **intersect + sort** (wasteful).
    - **`CREATE INDEX ON posts(user_id, created_at)`** → B-tree key = **tuple `(user_id, created_at)`**, sorted by user_id then created_at → traverse to user 123, scan sequentially in date order → **filtering + sorting for free** (2D query → 1D scan).

⚠ **Order matters:** the index only helps for **prefixes** of its column list. `(user_id, created_at)` serves "filter by user" (and user+date), but **not** "filter by created_at alone."

- Rule of thumb: **most selective first** — but **query patterns can trump selectivity** (include a frequent sort column to skip sort ops).
- Patterns: order history `(customer_id, order_date)` · event processing `(status, priority, created_at)` · feed `(user_id, type, timestamp)`.

### Covering Index (niche)

▸ **CRUX** — include _all_ columns the query needs (via `INCLUDE (likes)`) so results come **straight from the index — no table lookup.**

- Feed showing like-counts: regular `(user_id, created_at)` finds posts but must fetch each row's page for `likes`. Covering index returns everything from the index.
- **Trade-off:** larger index. **2026 reality — niche:** modern optimizers do well with regular indexes. Reach for it only with a clear read-heavy reason; **else prefer simplicity.**

---

## Decision Tree (the wrap-up)

```
Need an index? → will you filter/sort on this column? → yes → index it.
Which type?
  default ..................... B-Tree (equality + range, safe bet)
  write-heavy / time-series ... LSM (append-only, sequential writes)
  exact-match only, in-memory . Hash (rarely worth it)
  location / "nearby" ......... Geospatial → learn Geohash (R-tree in prod)
  full-text "contains word" ... Inverted index (Elasticsearch)
  multi-column filter+sort .... Composite (order = prefix rule)
  avoid table lookups (rare) .. Covering (INCLUDE columns)
```

---

## Quick Recall (pass 3+)

|Situation|Reach for|
|---|---|
|Default / unsure|**B-tree** (equality + range)|
|B-tree node roles|Root/Internal = separator keys + child pointers · Leaf = keys + row pointers|
|Why B-tree stays shallow|fan-out ≈ page ÷ entry → hundreds of children → 3–5 levels for millions of rows|
|No index → what happens|Full Table Scan (page-by-page); flow SSD → RAM → CPU|
|100K+ writes/s, time-series, logs|LSM tree (memtable→WAL→SSTable→compaction; Bloom filters for reads)|
|Blazing exact match, in-memory|Hash index (no ranges; rare)|
|"restaurants within 5mi"|Geospatial — **geohash** (1D string + B-tree); R-tree in prod|
|Why B-tree fails for geo|2D problem, two 1D indexes → strip/rectangle|
|`LIKE '%word%'` / full-text|Inverted index (word→docs; Elasticsearch)|
|Filter by user + sort by date|Composite `(user_id, created_at)` — order = prefix rule|
|Return cols without table hit|Covering index (`INCLUDE`) — niche|
|When indexes hurt|write-heavy+read-rare, tiny tables|
|Cost of every index|disk space + write amplification|