# Query 2 – Time-bucketed Aggregation by City

## Purpose

This query benchmarks **time-series aggregation** with **moderate cardinality grouping** and **selective filtering**.

It introduces:

* Time bucketing (`DATE_TRUNC('month')`)
* Multi-column `GROUP BY`
* Predicate filtering on a **small IN-list**
* Ordered output on grouped keys

This is a very common **dashboard / reporting** pattern.

---

## Query intent (logical)

> For a fixed set of major UK cities, compute **monthly transaction counts and average prices** since 2020.

---

## What this query stresses

* Predicate selectivity (`IN (...)`)
* Time bucketing cost
* Group-by cardinality expansion (city × month)
* Sort behavior on grouped columns
* Temp memory vs disk spill behavior

Compared to Query 1, this adds:

* More groups
* Wider intermediate results
* Higher memory pressure

---

## PostgreSQL – Native HEAP

**Engine**

* PostgreSQL 18.1
* Heap storage
* B-tree indexes on `(town, date)`

### SQL

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    town,
    DATE_TRUNC('month', date) AS month,
    COUNT(*) AS transactions,
    ROUND(AVG(price)) AS avg_price
FROM uk_price_paid_pg
WHERE town IN ('LONDON', 'MANCHESTER', 'BRISTOL', 'BIRMINGHAM', 'NOTTINGHAM')
  AND date >= '2020-01-01'
GROUP BY town, DATE_TRUNC('month', date)
ORDER BY town, month;
```

### Observed plan highlights

* Bitmap index scan on `(town, date)`
* Parallel bitmap heap scan
* Sort + Gather Merge
* GroupAggregate with temp file spill
* JIT compilation overhead is visible

📄 Full plan: `postgres-q2.plan.txt`

⏱ **Execution time:** ~690 ms

> This highlights PostgreSQL’s strength in **selective filtering**, but also its cost when grouping and sorting large intermediate result sets.

---

## CedarDB

**Engine**

* CedarDB v2025-12-19
* Row-based with modern MVCC
* Minimal indexing

### SQL

```sql
EXPLAIN (ANALYZE)
SELECT
    town,
    DATE_TRUNC('month', date) AS month,
    COUNT(*) AS transactions,
    ROUND(AVG(price)) AS avg_price
FROM uk_price_paid_ingest
WHERE town IN ('LONDON', 'MANCHESTER', 'BRISTOL', 'BIRMINGHAM', 'NOTTINGHAM')
  AND date >= '2020-01-01'
GROUP BY town, DATE_TRUNC('month', date)
ORDER BY town, month;
```

### Observed plan highlights

* Single table scan
* In-memory group-by
* No temp spill
* Compact aggregation state
* Very low executor overhead

📄 Full plan: `cedar-q2.plan.txt`

⏱ **Execution time:** ~30 ms

> CedarDB handles time bucketing efficiently due to **low MVCC and executor overhead**, even without heavy indexing.

---

## PostgreSQL + pg_clickhouse (FDW Pushdown)

**Engine**

* PostgreSQL 18
* pg_clickhouse FDW
* Aggregation fully pushed to ClickHouse

### SQL

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    town,
    DATE_TRUNC('month', date) AS month,
    COUNT(*) AS transactions,
    ROUND(AVG(price)) AS avg_price
FROM uk_price_paid
WHERE town IN ('LONDON', 'MANCHESTER', 'BRISTOL', 'BIRMINGHAM', 'NOTTINGHAM')
  AND date >= '2020-01-01'
GROUP BY town, DATE_TRUNC('month', date)
ORDER BY town, month;
```

### Observed plan highlights

* Entire aggregation pushed down
* PostgreSQL executor effectively bypassed
* Very small FDW coordination overhead

📄 Full plan: `fdw-q2.plan.txt`

⏱ **Execution time:** ~50 ms

> PostgreSQL becomes a **control plane**, not an execution engine.

---

## ClickHouse

**Engine**

* ClickHouse 25.12
* MergeTree
* Columnar + vectorized execution

### SQL

```sql
EXPLAIN PIPELINE
SELECT
    town,
    DATE_TRUNC('month', date) AS month,
    COUNT(*) AS transactions,
    ROUND(AVG(price)) AS avg_price
FROM uk_price_paid
WHERE town IN ('LONDON', 'MANCHESTER', 'BRISTOL', 'BIRMINGHAM', 'NOTTINGHAM')
  AND date >= '2020-01-01'
GROUP BY
    town,
    DATE_TRUNC('month', date)
ORDER BY
    town,
    month;
```

### Observed pipeline highlights

* Parallel MergeTree scan
* Vectorized aggregation
* Multi-stage merge + sort
* Fully pipelined execution

📄 Full pipeline: `clickhouse-q2.plan.txt`

⏱ **Execution time:** ~13 ms

---

## Summary (qualitative)

| Engine              | Strength shown in Query 2              | Main cost driver                      |
| ------------------- | -------------------------------------- | ------------------------------------- |
| PostgreSQL HEAP     | Accurate filtering, parallel execution | Sort + temp spill + executor overhead |
| CedarDB             | Fast in-memory aggregation             | Scan cost only                        |
| pg_clickhouse (FDW) | Transparent pushdown                   | Network + orchestration               |
| ClickHouse          | Time-series aggregation throughput     | CPU-efficient batch execution         |

---

## Key takeaway

Query 2 clearly shows how **execution architecture dominates performance** once grouping cardinality increases:

* PostgreSQL pays for **flexibility and correctness**
* CedarDB minimizes executor overhead
* FDW pushdown avoids PostgreSQL execution entirely
* ClickHouse thrives on **time-bucketed analytics**

This query is a strong bridge between **simple rollups (Query 1)** and **complex analytics (Query 3 & 4)**.
