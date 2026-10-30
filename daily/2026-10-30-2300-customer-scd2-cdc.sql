-- ============================================================================
-- Customer CDC -> Slowly Changing Dimension Type 2 (SCD2)
-- Platform: PostgreSQL 14+
-- Topic: Idempotent CDC processing, effective dating, and point-in-time joins
--
-- Run this file in a dedicated practice database. Setup is executable.
-- Solutions are provided in commented blocks so you can attempt each question.
--
-- Batch contract for this exercise:
--   * source_event_id identifies one logical CDC event (re-deliveries can repeat).
--   * each customer has at most one distinct effective change in this batch.
--   * source_updated_at is the business-effective timestamp; ingested_at is not.
--   * updates/deletes older than the current version are quarantined, not applied.
-- ============================================================================

DROP TABLE IF EXISTS customer_cdc_raw;
DROP TABLE IF EXISTS customer_dimension;

CREATE TABLE customer_dimension (
    customer_sk       BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id       BIGINT NOT NULL,
    customer_name     TEXT NOT NULL,
    city              TEXT NOT NULL,
    customer_tier     TEXT NOT NULL,
    valid_from        TIMESTAMPTZ NOT NULL,
    valid_to          TIMESTAMPTZ NOT NULL DEFAULT 'infinity'::timestamptz,
    is_current        BOOLEAN NOT NULL,
    source_event_id   TEXT,
    CONSTRAINT ck_customer_valid_range CHECK (valid_from < valid_to),
    CONSTRAINT ck_customer_current_end CHECK (
        (is_current AND valid_to = 'infinity'::timestamptz)
        OR (NOT is_current AND valid_to <> 'infinity'::timestamptz)
    )
);

-- Enforce exactly one current row per business key.
CREATE UNIQUE INDEX ux_customer_dimension_current
    ON customer_dimension (customer_id)
    WHERE is_current;

CREATE TABLE customer_cdc_raw (
    raw_record_id     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    source_event_id   TEXT NOT NULL,
    customer_id       BIGINT NOT NULL,
    operation         CHAR(1) NOT NULL CHECK (operation IN ('I', 'U', 'D')),
    customer_name     TEXT,
    city              TEXT,
    customer_tier     TEXT,
    source_updated_at TIMESTAMPTZ NOT NULL,
    ingested_at       TIMESTAMPTZ NOT NULL
);

INSERT INTO customer_dimension
    (customer_id, customer_name, city, customer_tier, valid_from, valid_to, is_current, source_event_id)
VALUES
    (101, 'Asha Rao',  'Mumbai', 'Silver', '2026-10-01 00:00:00+00', 'infinity', TRUE, 'seed-101'),
    (102, 'Rohan Shah','Pune',   'Gold',   '2026-10-01 00:00:00+00', 'infinity', TRUE, 'seed-102'),
    (103, 'Mira Das',  'Nashik', 'Silver', '2026-10-01 00:00:00+00', 'infinity', TRUE, 'seed-103');

INSERT INTO customer_cdc_raw
    (source_event_id, customer_id, operation, customer_name, city, customer_tier, source_updated_at, ingested_at)
VALUES
    ('evt-501', 101, 'U', 'Asha Rao',   'Pune',      'Gold',     '2026-10-30 09:00:00+00', '2026-10-30 09:03:00+00'),
    -- Same logical event delivered twice. Only one copy should be applied.
    ('evt-501', 101, 'U', 'Asha Rao',   'Pune',      'Gold',     '2026-10-30 09:00:00+00', '2026-10-30 09:08:00+00'),
    ('evt-502', 102, 'U', 'Rohan Shah', 'Pune',      'Platinum', '2026-10-30 10:00:00+00', '2026-10-30 10:02:00+00'),
    ('evt-503', 103, 'D', 'Mira Das',   'Nashik',    'Silver',   '2026-10-30 11:00:00+00', '2026-10-30 11:01:00+00'),
    ('evt-504', 104, 'I', 'Neha Kulkarni','Ahmednagar','Silver', '2026-10-30 12:00:00+00', '2026-10-30 12:01:00+00'),
    -- Orphan update: no existing customer 999.
    ('evt-505', 999, 'U', 'Unknown',   'Pune',      'Bronze',   '2026-10-30 13:00:00+00', '2026-10-30 13:01:00+00'),
    -- Stale change: effective before the current version began.
    ('evt-506', 102, 'U', 'Rohan Shah','Mumbai',    'Silver',   '2026-09-30 12:00:00+00', '2026-10-30 13:05:00+00');

-- ============================================================================
-- Q1. Find duplicate deliveries by logical source_event_id.
-- SOLUTION:
-- SELECT source_event_id, COUNT(*) AS delivery_count,
--        MIN(ingested_at) AS first_seen, MAX(ingested_at) AS last_seen
-- FROM customer_cdc_raw
-- GROUP BY source_event_id
-- HAVING COUNT(*) > 1
-- ORDER BY source_event_id;
--
-- Why: deduplicate on the source's stable event identifier, not on all
-- business columns. Two legitimate changes can have identical values.
-- ============================================================================

-- ============================================================================
-- Q2. Classify CDC records that should not be applied: orphan U/D events and
--     events older than the current dimension version.
-- SOLUTION:
-- SELECT r.source_event_id, r.customer_id, r.operation, r.source_updated_at,
--        CASE
--          WHEN d.customer_id IS NULL THEN 'ORPHAN_UPDATE_OR_DELETE'
--          WHEN r.source_updated_at <= d.valid_from THEN 'STALE_OR_ALREADY_APPLIED'
--        END AS exception_reason
-- FROM customer_cdc_raw r
-- LEFT JOIN customer_dimension d
--   ON d.customer_id = r.customer_id AND d.is_current
-- WHERE r.operation IN ('U', 'D')
--   AND (d.customer_id IS NULL OR r.source_updated_at <= d.valid_from)
-- ORDER BY r.customer_id, r.source_updated_at;
--
-- Why: an ingestion timestamp is not a substitute for business-effective time.
-- Route these records to a quarantine/replay workflow rather than silently
-- overwriting a newer state.
-- ============================================================================

-- ============================================================================
-- Q3. Apply this CDC batch as an idempotent SCD Type 2 transaction.
--     Execute this solution once, then execute it again to test idempotency.
-- SOLUTION:
-- BEGIN;
--
-- CREATE TEMP TABLE batch_to_apply ON COMMIT DROP AS
-- WITH ranked AS (
--     SELECT r.*,
--            ROW_NUMBER() OVER (
--                PARTITION BY source_event_id
--                ORDER BY ingested_at, raw_record_id
--            ) AS delivery_rank
--     FROM customer_cdc_raw r
-- ),
-- deduplicated AS (
--     SELECT *
--     FROM ranked
--     WHERE delivery_rank = 1
-- )
-- SELECT e.*
-- FROM deduplicated e
-- LEFT JOIN customer_dimension d
--   ON d.customer_id = e.customer_id
--  AND d.is_current
-- WHERE
--       (e.operation = 'I' AND d.customer_id IS NULL)
--    OR (e.operation = 'U'
--        AND d.customer_id IS NOT NULL
--        AND e.source_updated_at > d.valid_from
--        AND ROW(e.customer_name, e.city, e.customer_tier)
--            IS DISTINCT FROM
--            ROW(d.customer_name, d.city, d.customer_tier))
--    OR (e.operation = 'D'
--        AND d.customer_id IS NOT NULL
--        AND e.source_updated_at > d.valid_from);
--
-- -- Close the old version for updates and deletes.
-- UPDATE customer_dimension d
-- SET valid_to = b.source_updated_at,
--     is_current = FALSE
-- FROM batch_to_apply b
-- WHERE d.customer_id = b.customer_id
--   AND d.is_current
--   AND b.operation IN ('U', 'D');
--
-- -- Insert a new current version for inserts and updates.
-- INSERT INTO customer_dimension
--     (customer_id, customer_name, city, customer_tier,
--      valid_from, valid_to, is_current, source_event_id)
-- SELECT customer_id, customer_name, city, customer_tier,
--        source_updated_at, 'infinity'::timestamptz, TRUE, source_event_id
-- FROM batch_to_apply
-- WHERE operation IN ('I', 'U');
--
-- COMMIT;
--
-- Expected state after one application:
--   101: old Mumbai/Silver row closed; new Pune/Gold row current
--   102: old Gold row closed; new Platinum row current
--   103: old row closed; no current row (soft delete)
--   104: new Silver row current
--   999: unchanged; orphan update is not applied
--
-- Why: stage the deduplicated actionable set once, then close and insert
-- versions in one transaction. Half-open validity intervals [valid_from,
-- valid_to) make point-in-time joins unambiguous. The partial unique index
-- protects the one-current-row invariant.
-- ============================================================================

-- ============================================================================
-- Q4. Resolve facts against the customer attributes valid at event time.
-- SOLUTION:
-- WITH fact_events(event_id, customer_id, event_ts, amount) AS (
--     VALUES
--       ('tx-1', 101, '2026-10-30 08:30:00+00'::timestamptz, 100.00::numeric),
--       ('tx-2', 101, '2026-10-30 09:30:00+00'::timestamptz, 150.00::numeric),
--       ('tx-3', 102, '2026-10-30 10:30:00+00'::timestamptz,  75.00::numeric),
--       ('tx-4', 103, '2026-10-30 11:30:00+00'::timestamptz,  50.00::numeric)
-- )
-- SELECT f.event_id, f.customer_id, f.event_ts, f.amount,
--        d.customer_name, d.city, d.customer_tier
-- FROM fact_events f
-- LEFT JOIN customer_dimension d
--   ON d.customer_id = f.customer_id
--  AND f.event_ts >= d.valid_from
--  AND f.event_ts <  d.valid_to
-- ORDER BY f.event_ts;
--
-- Why: joining only to is_current would rewrite historical reporting when a
-- customer changes city or tier. The effective-date predicate preserves the
-- attributes that were true when each fact occurred.
-- ============================================================================

-- ============================================================================
-- Q5. Detect gaps/overlaps between consecutive versions and multiple current
--     records for the same customer.
-- SOLUTION:
-- WITH ordered AS (
--     SELECT customer_id, valid_from, valid_to, is_current,
--            LAG(valid_to) OVER (
--                PARTITION BY customer_id ORDER BY valid_from
--            ) AS previous_valid_to
--     FROM customer_dimension
-- )
-- SELECT customer_id, previous_valid_to, valid_from, valid_to, is_current
-- FROM ordered
-- WHERE previous_valid_to IS NOT NULL
--   AND previous_valid_to <> valid_from;
--
-- SELECT customer_id, COUNT(*) AS current_rows
-- FROM customer_dimension
-- WHERE is_current
-- GROUP BY customer_id
-- HAVING COUNT(*) > 1;
--
-- Why: contiguous half-open ranges should meet exactly at the next valid_from.
-- The unique partial index already prevents multiple current rows, but this
-- query is useful as a post-load data-quality assertion.
-- ============================================================================

-- ============================================================================
-- Q6. Produce a current customer snapshot by tier and city.
-- SOLUTION:
-- SELECT customer_tier, city, COUNT(*) AS customer_count
-- FROM customer_dimension
-- WHERE is_current
-- GROUP BY customer_tier, city
-- ORDER BY customer_tier, city;
--
-- Why: filter to current rows before aggregation; the partial current-row
-- index can support selective lookups, although a full scan may be cheaper
-- when most customers are current.
-- ============================================================================

-- ============================================================================
-- Q7. Review access paths for point-in-time lookups and CDC deduplication.
-- SOLUTION:
-- CREATE INDEX ix_customer_dimension_asof
--     ON customer_dimension (customer_id, valid_from DESC)
--     INCLUDE (valid_to, customer_name, city, customer_tier);
--
-- CREATE INDEX ix_customer_cdc_event_delivery
--     ON customer_cdc_raw (source_event_id, ingested_at, raw_record_id);
--
-- EXPLAIN (ANALYZE, BUFFERS)
-- SELECT customer_name, city, customer_tier
-- FROM customer_dimension
-- WHERE customer_id = 101
--   AND valid_from <= '2026-10-30 09:30:00+00'::timestamptz
--   AND valid_to   >  '2026-10-30 09:30:00+00'::timestamptz;
--
-- Performance notes:
--   1. Keep customer_id as the leading index column for selective as-of reads.
--   2. Avoid wrapping valid_from/valid_to in DATE() or other functions; that
--      can prevent efficient index access.
--   3. For large batches, load into a staging table and analyze it before
--      joining; avoid one UPDATE/INSERT round trip per customer.
--   4. Serialize concurrent batches by business key (or use an appropriate
--      locking strategy). The unique partial index is a final safety net,
--      not a substitute for a concurrency design.
--   5. Late events older than the current version require ordered replay or a
--      controlled history rebuild; do not force them into the latest row.
--   6. Benchmark with representative volumes using EXPLAIN (ANALYZE, BUFFERS).
--      Tiny practice data will often correctly choose sequential scans.
-- ============================================================================
