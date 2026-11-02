/*
===============================================================================
Daily SQL Practice — 2026-11-02
Topic: PostgreSQL Declarative Partitioning, Pruning & Retention
Dialect: PostgreSQL 14+

Problem context
---------------
A multi-tenant product platform stores high-volume event data. The platform
needs predictable time-range queries, safe replay handling, monthly partition
maintenance, and a low-lock retention process.

This file creates an isolated partitioned event table and reproducible data.
Run the setup first, then work through Q1-Q8 in order. The solutions are
executable; Q5 creates the December partition and Q8 detaches October.

Important design detail
-----------------------
The primary key is (event_ts, event_id), because PostgreSQL declarative
partitioned-table UNIQUE/PRIMARY KEY constraints must include the partition
key. This guarantees uniqueness for that pair, not global uniqueness of
event_id across every partition. Q7 demonstrates the distinction.

===============================================================================
0. SETUP — isolated sample schema and monthly partitions
===============================================================================
*/

-- Clean up both attached and previously detached objects so the script can
-- be rerun after completing Q8.
DROP TABLE IF EXISTS de_event_log CASCADE;
DROP TABLE IF EXISTS de_event_log_2026_10;
DROP TABLE IF EXISTS de_event_log_2026_10_archive;
DROP TABLE IF EXISTS de_event_log_2026_12_stage;

CREATE TABLE de_event_log (
    event_id       text          NOT NULL,
    tenant_id      integer       NOT NULL,
    event_ts       timestamptz   NOT NULL,
    event_type     text          NOT NULL,
    amount         numeric(12,2),
    source_system  text          NOT NULL,
    payload        jsonb         NOT NULL DEFAULT '{}'::jsonb,
    PRIMARY KEY (event_ts, event_id)
) PARTITION BY RANGE (event_ts);

CREATE TABLE de_event_log_2026_10
    PARTITION OF de_event_log
    FOR VALUES FROM ('2026-10-01 00:00:00+00')
                 TO ('2026-11-01 00:00:00+00');

CREATE TABLE de_event_log_2026_11
    PARTITION OF de_event_log
    FOR VALUES FROM ('2026-11-01 00:00:00+00')
                 TO ('2026-12-01 00:00:00+00');

-- A B-tree supports tenant-scoped newest-first access. A BRIN index can be
-- useful for very large append-oriented partitions whose physical order
-- correlates with event_ts; benchmark it against the B-tree for your workload.
CREATE INDEX de_event_log_tenant_ts_idx
    ON de_event_log (tenant_id, event_ts DESC, event_id DESC);

CREATE INDEX de_event_log_event_ts_brin_idx
    ON de_event_log USING BRIN (event_ts)
    WITH (pages_per_range = 64);

INSERT INTO de_event_log
    (event_id, tenant_id, event_ts, event_type, amount, source_system, payload)
VALUES
    ('evt-1001',       10, '2026-10-28 10:00:00+00', 'ORDER_PAID', 125.00, 'checkout',
     '{"order_id":"O-7001","channel":"web"}'),
    ('evt-1002',       10, '2026-10-28 10:05:00+00', 'REFUND',     -25.00, 'payments',
     '{"order_id":"O-7001","reason":"partial"}'),
    ('evt-replay-900', 20, '2026-10-29 08:15:00+00', 'LOGIN',        NULL, 'identity',
     '{"device":"mobile","batch":"oct-29"}'),
    ('evt-2001',       10, '2026-11-01 00:15:00+00', 'ORDER_PAID',  80.00, 'checkout',
     '{"order_id":"O-7101","channel":"mobile"}'),
    ('evt-2002',       10, '2026-11-01 09:00:00+00', 'ORDER_PAID',  45.00, 'checkout',
     '{"order_id":"O-7102","channel":"web"}'),
    ('evt-2003',       20, '2026-11-01 09:02:00+00', 'LOGIN',        NULL, 'identity',
     '{"device":"desktop"}'),
    ('evt-2004',       10, '2026-11-02 10:30:00+00', 'REFUND',     -10.00, 'payments',
     '{"order_id":"O-7101","reason":"shipping"}'),
    -- Intentional repeated event_id in another month. The composite primary
    -- key allows it because event_ts differs; Q7 detects this global replay.
    ('evt-replay-900', 20, '2026-11-02 11:45:00+00', 'LOGIN',        NULL, 'identity',
     '{"device":"mobile","batch":"nov-02"}');

ANALYZE de_event_log;

-- Setup assertion: three October rows and five November rows.
DO $$
DECLARE
    october_rows integer;
    november_rows integer;
BEGIN
    SELECT count(*) INTO october_rows
    FROM de_event_log
    WHERE event_ts >= timestamptz '2026-10-01 00:00:00+00'
      AND event_ts <  timestamptz '2026-11-01 00:00:00+00';

    SELECT count(*) INTO november_rows
    FROM de_event_log
    WHERE event_ts >= timestamptz '2026-11-01 00:00:00+00'
      AND event_ts <  timestamptz '2026-12-01 00:00:00+00';

    IF october_rows <> 3 OR november_rows <> 5 THEN
        RAISE EXCEPTION 'Unexpected seed counts: October %, November %',
            october_rows, november_rows;
    END IF;
END $$;


/*
===============================================================================
Q1. Partition pruning with a SARGable timestamp predicate
===============================================================================

Problem:
Return November 2026 events for tenant 10. Show that PostgreSQL can eliminate
the October partition.

Solution:
*/
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT event_id, event_ts, event_type, amount
FROM de_event_log
WHERE tenant_id = 10
  AND event_ts >= timestamptz '2026-11-01 00:00:00+00'
  AND event_ts <  timestamptz '2026-12-01 00:00:00+00'
ORDER BY event_ts, event_id;

/*
Explanation:
- The half-open range [start, end) matches the monthly partition bounds.
- The predicate leaves event_ts unwrapped, so partition pruning can occur.
- The tenant/time B-tree can support the tenant-scoped ordered access path.

Performance notes:
- Avoid WHERE date(event_ts) = DATE '2026-11-01' or casting event_ts to text;
  those expressions can prevent straightforward pruning/index use.
- With tiny sample tables PostgreSQL may choose a sequential scan inside the
  surviving partition. That does not mean partition pruning failed.
- Inspect the plan for Subplans Removed or only the November child being scanned.
*/


/*
===============================================================================
Q2. Daily tenant roll-up without sacrificing partition pruning
===============================================================================

Problem:
Calculate event count and signed monetary amount per tenant and UTC day for
November 2026. Events without an amount must not reduce the total.

Solution:
*/
SELECT
    tenant_id,
    (event_ts AT TIME ZONE 'UTC')::date AS event_day_utc,
    count(*) AS event_count,
    sum(coalesce(amount, 0)) AS net_amount
FROM de_event_log
WHERE event_ts >= timestamptz '2026-11-01 00:00:00+00'
  AND event_ts <  timestamptz '2026-12-01 00:00:00+00'
GROUP BY tenant_id, (event_ts AT TIME ZONE 'UTC')::date
ORDER BY event_day_utc, tenant_id;

/*
Expected spot checks:
- 2026-11-01 / tenant 10: 2 events, net amount 125.00
- 2026-11-01 / tenant 20: 1 event, net amount 0.00
- 2026-11-02 / tenant 10: 1 event, net amount -10.00
- 2026-11-02 / tenant 20: 1 event, net amount 0.00

Explanation:
Filter on the raw partition key first, then derive the UTC date for grouping.
COALESCE is applied to the measure, not to the partition predicate.

Performance notes:
- For recurring dashboards, consider a daily aggregate table or materialized
  view rather than repeatedly scanning every raw event.
- Keep the aggregation grain explicit: tenant + UTC date.
*/


/*
===============================================================================
Q3. Latest event per tenant using an index-aligned access pattern
===============================================================================

Problem:
Return the latest November event for every tenant. Break timestamp ties using
event_id so the result is deterministic.

Solution:
*/
SELECT DISTINCT ON (tenant_id)
    tenant_id,
    event_id,
    event_ts,
    event_type
FROM de_event_log
WHERE event_ts >= timestamptz '2026-11-01 00:00:00+00'
  AND event_ts <  timestamptz '2026-12-01 00:00:00+00'
ORDER BY tenant_id, event_ts DESC, event_id DESC;

/*
Expected result:
- tenant 10 -> evt-2004
- tenant 20 -> evt-replay-900

Explanation:
DISTINCT ON keeps the first row in each tenant group. The ORDER BY defines
which row is first and includes a deterministic tie-breaker.

Performance notes:
- The parent index (tenant_id, event_ts DESC, event_id DESC) is aligned with
  the grouping and ordering.
- For a small number of tenants and very large history, compare this approach
  with a LATERAL lookup driven from a tenant dimension.
*/


/*
===============================================================================
Q4. Replay-safe insert within the declared partition key
===============================================================================

Problem:
A source retries an already-landed November event. Reprocess it without
creating a duplicate row.

Solution:
*/
INSERT INTO de_event_log
    (event_id, tenant_id, event_ts, event_type, amount, source_system, payload)
VALUES
    ('evt-2001', 10, '2026-11-01 00:15:00+00', 'ORDER_PAID', 80.00, 'checkout',
     '{"order_id":"O-7101","channel":"mobile"}')
ON CONFLICT (event_ts, event_id) DO NOTHING;

DO $$
DECLARE
    november_rows integer;
BEGIN
    SELECT count(*) INTO november_rows
    FROM de_event_log
    WHERE event_ts >= timestamptz '2026-11-01 00:00:00+00'
      AND event_ts <  timestamptz '2026-12-01 00:00:00+00';

    IF november_rows <> 5 THEN
        RAISE EXCEPTION 'Replay created an unexpected row; November count is %',
            november_rows;
    END IF;
END $$;

/*
Explanation:
The conflict target exactly matches the declared primary key. Replaying the
same event timestamp and event ID is idempotent for this table's key.

Important limitation:
The key does not prevent the same event_id from appearing with a different
event_ts in another partition. Q7 demonstrates this. If event_id must be
globally unique, maintain a separate non-partitioned event registry with
PRIMARY KEY(event_id), and claim the ID transactionally before inserting into
the partitioned fact table.

Performance notes:
- Keep the conflict target backed by a unique index.
- Avoid a pre-check SELECT followed by INSERT; that pattern is race-prone.
*/


/*
===============================================================================
Q5. Load and attach a prebuilt December partition
===============================================================================

Problem:
Prepare a new monthly partition outside the live partition tree, validate its
date range, then attach it with minimal validation work.

Solution:
*/
CREATE TABLE de_event_log_2026_12_stage
    (LIKE de_event_log INCLUDING DEFAULTS INCLUDING CONSTRAINTS);

ALTER TABLE de_event_log_2026_12_stage
    ADD CONSTRAINT de_event_log_2026_12_stage_bounds
    CHECK (
        event_ts >= timestamptz '2026-12-01 00:00:00+00'
        AND event_ts < timestamptz '2027-01-01 00:00:00+00'
    );

INSERT INTO de_event_log_2026_12_stage
    (event_id, tenant_id, event_ts, event_type, amount, source_system, payload)
VALUES
    ('evt-3001', 10, '2026-12-01 00:05:00+00', 'ORDER_PAID', 210.00, 'checkout',
     '{"order_id":"O-7201","channel":"web"}'),
    ('evt-3002', 20, '2026-12-02 13:20:00+00', 'LOGIN', NULL, 'identity',
     '{"device":"tablet"}');

ALTER TABLE de_event_log_2026_12_stage
    VALIDATE CONSTRAINT de_event_log_2026_12_stage_bounds;

ALTER TABLE de_event_log
    ATTACH PARTITION de_event_log_2026_12_stage
    FOR VALUES FROM ('2026-12-01 00:00:00+00')
                 TO ('2027-01-01 00:00:00+00');

ANALYZE de_event_log_2026_12_stage;

DO $$
DECLARE
    december_rows integer;
BEGIN
    SELECT count(*) INTO december_rows
    FROM de_event_log
    WHERE event_ts >= timestamptz '2026-12-01 00:00:00+00'
      AND event_ts <  timestamptz '2027-01-01 00:00:00+00';

    IF december_rows <> 2 THEN
        RAISE EXCEPTION 'Expected 2 December rows, found %', december_rows;
    END IF;
END $$;

/*
Explanation:
A validated CHECK constraint matching the partition bounds lets PostgreSQL
avoid a full validation scan of the staging table during ATTACH PARTITION.
The attach operation also ensures the partition participates in the parent's
partitioned indexes.

Performance notes:
- Load and validate the staging table before the attach window.
- Confirm no rows fall outside the intended half-open range.
- Test lock duration and index-build behavior with production-sized partitions.
*/


/*
===============================================================================
Q6. Inspect partition boundaries, approximate rows, and storage footprint
===============================================================================

Problem:
Build a small operational inventory of the attached leaf partitions.

Solution:
*/
SELECT
    tree.relid::regclass AS partition_name,
    pg_get_expr(child.relpartbound, child.oid) AS partition_bound,
    child.reltuples::bigint AS estimated_rows,
    pg_size_pretty(pg_total_relation_size(child.oid)) AS total_size
FROM pg_partition_tree('de_event_log'::regclass) AS tree
JOIN pg_class AS child
  ON child.oid = tree.relid
WHERE tree.isleaf
ORDER BY tree.relid::regclass::text;

/*
Explanation:
pg_partition_tree exposes the hierarchy; pg_get_expr renders each leaf's
partition bound. reltuples is a planner estimate, not an exact count.

Performance notes:
- Use pg_total_relation_size to include table, indexes, and auxiliary storage.
- Run ANALYZE after large loads so planner statistics remain useful.
- Monitor partition count: thousands of tiny partitions can increase planning
  and maintenance overhead even when pruning is effective.
*/


/*
===============================================================================
Q7. Detect global event-ID replays across different time partitions
===============================================================================

Problem:
Find event IDs that occur more than once even though the composite partition
key permits them.

Solution:
*/
SELECT
    event_id,
    count(*) AS occurrences,
    min(event_ts) AS first_seen,
    max(event_ts) AS last_seen
FROM de_event_log
GROUP BY event_id
HAVING count(*) > 1
ORDER BY occurrences DESC, event_id;

/*
Expected result:
evt-replay-900 appears twice: once in October and once in November.

Explanation:
A partitioned-table UNIQUE/PRIMARY KEY constraint must include the partition
key. Therefore PRIMARY KEY(event_ts, event_id) cannot enforce uniqueness on
event_id alone across all partitions.

Production design option:
Create a compact, non-partitioned registry:
    CREATE TABLE de_event_registry (
        event_id text PRIMARY KEY,
        first_event_ts timestamptz NOT NULL
    );
In one transaction, insert the event ID into the registry with
ON CONFLICT DO NOTHING RETURNING event_id, then insert only returned IDs into
the partitioned event table. Define retry and correction semantics explicitly.

Performance notes:
- A registry adds a write and index-maintenance cost; use it only when global
  identity is a real business invariant.
- For large audits, run incrementally by ingestion batch or use a maintained
  duplicate-control table instead of repeatedly grouping all retained history.
*/


/*
===============================================================================
Q8. Retention: detach an expired month before archiving or dropping it
===============================================================================

Problem:
Remove October 2026 from the active query path without deleting the data
immediately.

Solution:
*/
ALTER TABLE de_event_log
    DETACH PARTITION de_event_log_2026_10;

-- The detached table remains available as a standalone relation.
ALTER TABLE de_event_log_2026_10
    RENAME TO de_event_log_2026_10_archive;

/*
Optional lower-lock variant (PostgreSQL 14+):
    ALTER TABLE de_event_log
        DETACH PARTITION de_event_log_2026_10 CONCURRENTLY;

The CONCURRENTLY form cannot run inside an explicit transaction block and
has additional restrictions. Validate those operational constraints before
using it in a deployment script.

Explanation:
Detaching removes the month from the active partition tree without rewriting
or row-by-row deleting its contents. The archive can then be exported,
compressed, moved to cheaper storage, or dropped according to retention policy.

Performance notes:
- DROP TABLE on an expired partition is usually much faster than DELETE over
  millions of rows because it avoids per-row deletion and vacuum work.
- DETACH/ATTACH still require metadata locks; coordinate with long-running
  queries and DDL.
- Keep retention policy, legal hold, backup, and restore requirements aligned.
*/


/*
===============================================================================
INTERVIEW FOLLOW-UPS
===============================================================================

1. Why must a unique constraint on a range-partitioned table include the
   partition key?
2. When would you choose RANGE, LIST, or HASH partitioning?
3. How do plan-time and execution-time partition pruning differ?
4. Why are half-open timestamp intervals safer than BETWEEN for adjacent
   monthly partitions?
5. When is BRIN preferable to B-tree, and what data-order assumptions matter?
6. What lock and validation work can ATTACH PARTITION perform?
7. What is the operational difference between DETACH PARTITION and
   DETACH PARTITION CONCURRENTLY?
8. How would you guarantee global event-ID idempotency across partitions?
9. How can too many partitions hurt planning and catalog operations?
10. How would you test pruning and index choices at production scale?

===============================================================================
PERFORMANCE CHECKLIST
===============================================================================

- Filter directly on the partition key with half-open timestamp boundaries.
- Verify pruning using EXPLAIN (ANALYZE, BUFFERS); do not infer it from runtime
  alone on tiny sample tables.
- Choose partition granularity from retention, ingest volume, and query shape.
- Keep indexes aligned with actual predicates and ordering; benchmark each.
- Consider BRIN for large append-oriented, physically correlated data.
- Preload and validate a staging table before ATTACH PARTITION.
- Prefer partition detach/drop for retention over massive row-by-row DELETE.
- Run ANALYZE after large loads and monitor planning time as partition count grows.
- Test concurrent ingest, DDL locks, replay behavior, and rollback procedures.

End of practice file.
===============================================================================
