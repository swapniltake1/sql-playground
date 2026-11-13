-- ============================================================================
-- Daily SQL Practice — Loan Delinquency Vintage Curves & Roll-Rate Analytics
-- PostgreSQL 14+
--
-- Scenario:
-- A retail lender receives monthly loan snapshots from a servicing platform.
-- Source deliveries can be replayed or corrected, one loan can miss a monthly
-- snapshot, and collections teams need reliable delinquency and vintage metrics.
--
-- Run this file in a disposable PostgreSQL database. It drops and recreates
-- only the two loan-practice tables and the canonical snapshot view below.
-- The sample is intentionally small; suggested indexes are for plan exercises,
-- not proof of a speed-up on this dataset.
-- ============================================================================

DROP VIEW IF EXISTS v_loan_snapshot;
DROP TABLE IF EXISTS loan_snapshot_raw;
DROP TABLE IF EXISTS loan_account;

CREATE TABLE loan_account (
    loan_id             BIGINT PRIMARY KEY,
    customer_id         BIGINT NOT NULL,
    branch_code         TEXT NOT NULL,
    product_code        TEXT NOT NULL,
    origination_date    DATE NOT NULL,
    original_principal  NUMERIC(14,2) NOT NULL CHECK (original_principal > 0),
    term_months         INTEGER NOT NULL CHECK (term_months > 0),
    annual_rate         NUMERIC(7,4) NOT NULL,
    loan_status         TEXT NOT NULL
        CHECK (loan_status IN ('active', 'closed', 'charged_off'))
);

-- This is a raw landing table on purpose: no FK to loan_account and no
-- business-value CHECK constraints, so the data-quality exercise can detect
-- malformed and orphan source records instead of rejecting them at ingestion.
CREATE TABLE loan_snapshot_raw (
    snapshot_event_id       BIGINT PRIMARY KEY,
    loan_id                 BIGINT NOT NULL,
    snapshot_month          DATE NOT NULL,
    outstanding_principal  NUMERIC(14,2) NOT NULL,
    days_past_due           INTEGER NOT NULL,
    scheduled_due           NUMERIC(14,2) NOT NULL,
    paid_amount             NUMERIC(14,2) NOT NULL,
    source_updated_at       TIMESTAMPTZ NOT NULL,
    ingested_at             TIMESTAMPTZ NOT NULL,
    source_sequence          INTEGER NOT NULL
);

INSERT INTO loan_account
    (loan_id, customer_id, branch_code, product_code, origination_date,
     original_principal, term_months, annual_rate, loan_status)
VALUES
    (1001, 501, 'PUN', 'PERSONAL',       DATE '2026-01-10', 100000,  24, 0.1450, 'active'),
    (1002, 502, 'PUN', 'HOME',           DATE '2026-01-25', 300000, 120, 0.0950, 'active'),
    (1003, 503, 'MUM', 'PERSONAL',       DATE '2026-02-05',  80000,  24, 0.1600, 'active'),
    (1004, 504, 'MUM', 'AUTO',           DATE '2026-02-20', 150000,  48, 0.1150, 'active'),
    (1005, 505, 'BLR', 'PERSONAL',       DATE '2026-03-01', 120000,  36, 0.1400, 'active'),
    (1006, 506, 'PUN', 'PERSONAL',       DATE '2026-03-15',  90000,  24, 0.1500, 'active'),
    (1007, 507, 'BLR', 'PERSONAL',       DATE '2026-01-05',  60000,  18, 0.1550, 'active'),
    (1008, 508, 'MUM', 'SMALL_BUSINESS', DATE '2026-02-10', 250000,  36, 0.1350, 'charged_off');

-- snapshot_month is the first day of the reporting month. Loan 1007 deliberately
-- has no February row. Loan 1001's March row is corrected later; loan 1002's
-- April row is delivered twice. Loan 9999 is an intentional orphan/invalid row.
INSERT INTO loan_snapshot_raw
    (snapshot_event_id, loan_id, snapshot_month, outstanding_principal,
     days_past_due, scheduled_due, paid_amount, source_updated_at,
     ingested_at, source_sequence)
VALUES
    (10001, 1001, DATE '2026-01-01',  96000,   0, 4500, 4500, '2026-02-01 08:00:00+05:30', '2026-02-01 08:05:00+05:30', 1),
    (10002, 1001, DATE '2026-02-01',  92000,  12, 4500, 3000, '2026-03-01 08:00:00+05:30', '2026-03-01 08:05:00+05:30', 1),
    (10003, 1001, DATE '2026-03-01',  88000,  42, 4500,    0, '2026-04-01 01:00:00+05:30', '2026-04-01 01:05:00+05:30', 1),
    (10004, 1001, DATE '2026-03-01',  88000,  38, 4500,    0, '2026-04-01 02:00:00+05:30', '2026-04-01 02:05:00+05:30', 2),
    (10005, 1001, DATE '2026-04-01',  84000,   0, 4500, 9000, '2026-05-01 08:00:00+05:30', '2026-05-01 08:05:00+05:30', 1),

    (10011, 1002, DATE '2026-01-01', 295000,   0, 6000, 6000, '2026-02-01 08:00:00+05:30', '2026-02-01 08:05:00+05:30', 1),
    (10012, 1002, DATE '2026-02-01', 290000,   0, 6000, 6000, '2026-03-01 08:00:00+05:30', '2026-03-01 08:05:00+05:30', 1),
    (10013, 1002, DATE '2026-03-01', 285000,   0, 6000, 6000, '2026-04-01 08:00:00+05:30', '2026-04-01 08:05:00+05:30', 1),
    (10014, 1002, DATE '2026-04-01', 280000,   0, 6000, 6000, '2026-05-01 07:00:00+05:30', '2026-05-01 07:05:00+05:30', 1),
    (10015, 1002, DATE '2026-04-01', 280000,   0, 6000, 6000, '2026-05-01 07:00:00+05:30', '2026-05-01 07:10:00+05:30', 1),

    (10021, 1003, DATE '2026-02-01',  77000,   0, 4000, 4000, '2026-03-01 08:00:00+05:30', '2026-03-01 08:05:00+05:30', 1),
    (10022, 1003, DATE '2026-03-01',  74000,  65, 4000,    0, '2026-04-01 08:00:00+05:30', '2026-04-01 08:05:00+05:30', 1),
    (10023, 1003, DATE '2026-04-01',  72000,  95, 4000,    0, '2026-05-01 08:00:00+05:30', '2026-05-01 08:05:00+05:30', 1),

    (10031, 1004, DATE '2026-02-01', 145000,   0, 5000, 5000, '2026-03-01 08:00:00+05:30', '2026-03-01 08:05:00+05:30', 1),
    (10032, 1004, DATE '2026-03-01', 140000,   0, 5000, 5000, '2026-04-01 08:00:00+05:30', '2026-04-01 08:05:00+05:30', 1),
    (10033, 1004, DATE '2026-04-01', 135000,   0, 5000, 5000, '2026-05-01 08:00:00+05:30', '2026-05-01 08:05:00+05:30', 1),

    (10041, 1005, DATE '2026-03-01', 116000,   0, 4500, 4500, '2026-04-01 08:00:00+05:30', '2026-04-01 08:05:00+05:30', 1),
    (10042, 1005, DATE '2026-04-01', 112000,  35, 4500, 1000, '2026-05-01 08:00:00+05:30', '2026-05-01 08:05:00+05:30', 1),

    (10051, 1006, DATE '2026-03-01',  87000,   0, 4500, 4500, '2026-04-01 08:00:00+05:30', '2026-04-01 08:05:00+05:30', 1),
    (10052, 1006, DATE '2026-04-01',  83000,   0, 4500, 4500, '2026-05-01 08:00:00+05:30', '2026-05-01 08:05:00+05:30', 1),

    (10061, 1007, DATE '2026-01-01',  58000,   0, 3000, 3000, '2026-02-01 08:00:00+05:30', '2026-02-01 08:05:00+05:30', 1),
    -- February 2026 intentionally missing for loan 1007.
    (10062, 1007, DATE '2026-03-01',  55000,  15, 3000, 2000, '2026-04-01 08:00:00+05:30', '2026-04-01 08:05:00+05:30', 1),
    (10063, 1007, DATE '2026-04-01',  52000,   0, 3000, 6000, '2026-05-01 08:00:00+05:30', '2026-05-01 08:05:00+05:30', 1),

    (10071, 1008, DATE '2026-02-01', 242000,   0, 8500, 8500, '2026-03-01 08:00:00+05:30', '2026-03-01 08:05:00+05:30', 1),
    (10072, 1008, DATE '2026-03-01', 238000,  95, 8500,    0, '2026-04-01 08:00:00+05:30', '2026-04-01 08:05:00+05:30', 1),
    (10073, 1008, DATE '2026-04-01', 234000, 125, 8500,    0, '2026-05-01 08:00:00+05:30', '2026-05-01 08:05:00+05:30', 1),

    (10999, 9999, DATE '2026-04-01',    -50,  -3, -100,  -20, '2026-05-01 09:00:00+05:30', '2026-05-01 09:05:00+05:30', 1);

-- Deterministic canonicalization:
-- 1) prefer the latest source correction;
-- 2) break ties by ingestion time, source sequence, then immutable event ID.
-- This keeps replayed/corrected deliveries at one row per loan and month.
CREATE INDEX ix_loan_snapshot_dedupe
    ON loan_snapshot_raw
       (loan_id, snapshot_month, source_updated_at DESC,
        ingested_at DESC, source_sequence DESC, snapshot_event_id DESC);

CREATE INDEX ix_loan_snapshot_month_loan
    ON loan_snapshot_raw (snapshot_month, loan_id);

CREATE INDEX ix_loan_account_origination
    ON loan_account (origination_date, loan_id)
    INCLUDE (original_principal, branch_code, product_code);

CREATE OR REPLACE VIEW v_loan_snapshot AS
SELECT DISTINCT ON (loan_id, snapshot_month)
       snapshot_event_id,
       loan_id,
       snapshot_month,
       outstanding_principal,
       days_past_due,
       scheduled_due,
       paid_amount,
       source_updated_at,
       ingested_at,
       source_sequence
FROM loan_snapshot_raw
ORDER BY loan_id,
         snapshot_month,
         source_updated_at DESC,
         ingested_at DESC,
         source_sequence DESC,
         snapshot_event_id DESC;

-- ============================================================================
-- PROBLEM 1 — Replay/correction audit
-- Return only loan-month keys with multiple raw deliveries, the number of
-- versions, and the event selected by the canonicalization rule.
--
-- OPTIMIZED SOLUTION:
-- Aggregate the raw rows at the business key and join to the one-row-per-key
-- view. The view's ORDER BY is deterministic, so reruns select the same winner.
--
-- SELECT r.loan_id,
--        r.snapshot_month,
--        COUNT(*) AS source_versions,
--        c.snapshot_event_id AS canonical_event_id,
--        c.days_past_due AS canonical_dpd
-- FROM loan_snapshot_raw r
-- JOIN v_loan_snapshot c
--   ON c.loan_id = r.loan_id
--  AND c.snapshot_month = r.snapshot_month
-- GROUP BY r.loan_id, r.snapshot_month,
--          c.snapshot_event_id, c.days_past_due
-- HAVING COUNT(*) > 1
-- ORDER BY r.loan_id, r.snapshot_month;
--
-- EXPECTED SPOT CHECK:
-- Loan 1001 / 2026-03-01 selects event 10004 (38 DPD).
-- Loan 1002 / 2026-04-01 selects event 10015 (later ingestion time).
--
-- WHY THIS IS OPTIMIZED:
-- DISTINCT ON is concise for PostgreSQL's ordered first-row-per-group pattern.
-- The composite index matches the key and tie-break ordering, allowing an
-- ordered index path to be considered instead of an unrelated full sort.
-- Validate with EXPLAIN; the planner may still prefer a sequential scan on
-- small tables.

-- ============================================================================
-- PROBLEM 2 — Latest portfolio by delinquency bucket
-- Find each loan's latest valid snapshot and report loan count, outstanding
-- exposure, and share of total exposure for CURRENT, 01-30, 31-60, 61-90, and
-- 90+ DPD buckets.
--
-- OPTIMIZED SOLUTION:
-- WITH latest AS (
--     SELECT DISTINCT ON (s.loan_id)
--            s.loan_id, s.snapshot_month, s.outstanding_principal,
--            s.days_past_due
--     FROM v_loan_snapshot s
--     JOIN loan_account a ON a.loan_id = s.loan_id
--     ORDER BY s.loan_id, s.snapshot_month DESC
-- ),
-- bucketed AS (
--     SELECT loan_id, outstanding_principal,
--            CASE
--              WHEN days_past_due = 0 THEN 'CURRENT'
--              WHEN days_past_due BETWEEN 1 AND 30 THEN '01-30'
--              WHEN days_past_due BETWEEN 31 AND 60 THEN '31-60'
--              WHEN days_past_due BETWEEN 61 AND 90 THEN '61-90'
--              ELSE '90+'
--            END AS dpd_bucket
--     FROM latest
-- )
-- SELECT dpd_bucket,
--        COUNT(*) AS loan_count,
--        SUM(outstanding_principal) AS outstanding_exposure,
--        ROUND(
--          100.0 * SUM(outstanding_principal)
--          / NULLIF(SUM(SUM(outstanding_principal)) OVER (), 0),
--          2
--        ) AS exposure_share_pct
-- FROM bucketed
-- GROUP BY dpd_bucket
-- ORDER BY CASE dpd_bucket
--            WHEN 'CURRENT' THEN 1 WHEN '01-30' THEN 2
--            WHEN '31-60' THEN 3 WHEN '61-90' THEN 4 ELSE 5
--          END;
--
-- WHY THIS IS OPTIMIZED:
-- DISTINCT ON retrieves one row per loan without ranking every output column.
-- The account join excludes orphan landing records before aggregation.
-- Windowed SUM computes the portfolio denominator after bucket aggregation,
-- avoiding a second scan of the classified result.

-- ============================================================================
-- PROBLEM 3 — Origination vintage delinquency curve
-- For every origination-month vintage and month-on-book (MOB), calculate the
-- 30+ DPD loan count, 30+ DPD outstanding balance, and delinquent balance as a
-- percentage of the vintage's original booked principal.
--
-- OPTIMIZED SOLUTION:
-- WITH vintage_month AS (
--     SELECT date_trunc('month', a.origination_date)::date AS vintage_month,
--            (
--              (EXTRACT(YEAR FROM s.snapshot_month)
--                 - EXTRACT(YEAR FROM a.origination_date)) * 12
--              + EXTRACT(MONTH FROM s.snapshot_month)
--                 - EXTRACT(MONTH FROM a.origination_date)
--            )::integer AS mob,
--            a.original_principal,
--            s.outstanding_principal,
--            s.days_past_due
--     FROM v_loan_snapshot s
--     JOIN loan_account a ON a.loan_id = s.loan_id
-- )
-- SELECT vintage_month,
--        mob,
--        COUNT(*) FILTER (WHERE days_past_due >= 30) AS loans_30_plus,
--        SUM(outstanding_principal)
--          FILTER (WHERE days_past_due >= 30) AS balance_30_plus,
--        ROUND(
--          100.0 * SUM(outstanding_principal)
--            FILTER (WHERE days_past_due >= 30)
--          / NULLIF(SUM(original_principal), 0),
--          2
--        ) AS 30_plus_balance_to_booked_pct
-- FROM vintage_month
-- GROUP BY vintage_month, mob
-- ORDER BY vintage_month, mob;
--
-- METRIC DEFINITION:
-- The denominator is original booked principal for the loans represented in
-- that vintage/MOB cell, not the remaining performing balance. State this
-- definition whenever comparing vintage curves across portfolios.
--
-- WHY THIS IS OPTIMIZED:
-- Join at the canonical loan-month grain before aggregating. FILTER clauses
-- calculate delinquent measures in the same grouped pass; they avoid separate
-- scans for each DPD bucket. The origination index is useful when the workload
-- also filters or ranges over origination dates.

-- ============================================================================
-- PROBLEM 4 — Month-over-month delinquency roll-rate matrix
-- Count loans and compare opening versus closing exposure for every transition
-- between consecutive calendar-month DPD buckets.
--
-- OPTIMIZED SOLUTION:
-- WITH bucketed AS (
--     SELECT s.loan_id, s.snapshot_month, s.outstanding_principal,
--            CASE
--              WHEN s.days_past_due = 0 THEN 'CURRENT'
--              WHEN s.days_past_due BETWEEN 1 AND 30 THEN '01-30'
--              WHEN s.days_past_due BETWEEN 31 AND 60 THEN '31-60'
--              WHEN s.days_past_due BETWEEN 61 AND 90 THEN '61-90'
--              ELSE '90+'
--            END AS dpd_bucket
--     FROM v_loan_snapshot s
--     JOIN loan_account a ON a.loan_id = s.loan_id
-- ),
-- transitions AS (
--     SELECT *,
--            LAG(snapshot_month) OVER w AS prior_month,
--            LAG(dpd_bucket) OVER w AS prior_bucket,
--            LAG(outstanding_principal) OVER w AS prior_exposure
--     FROM bucketed
--     WINDOW w AS (PARTITION BY loan_id ORDER BY snapshot_month)
-- )
-- SELECT prior_bucket,
--        dpd_bucket AS current_bucket,
--        COUNT(*) AS loan_count,
--        SUM(prior_exposure) AS opening_exposure,
--        SUM(outstanding_principal) AS closing_exposure
-- FROM transitions
-- WHERE prior_month = (snapshot_month - INTERVAL '1 month')::date
-- GROUP BY prior_bucket, dpd_bucket
-- ORDER BY prior_bucket, current_bucket;
--
-- WHY THIS IS OPTIMIZED:
-- LAG calculates all transitions in one ordered window pass. The explicit
-- calendar-month check prevents a January-to-March jump from being mislabeled
-- as a February-to-March transition when a snapshot is missing.
-- For very large histories, persist the canonical loan-month grain and index
-- it on (loan_id, snapshot_month) before running repeated transition reports.

-- ============================================================================
-- PROBLEM 5 — Delinquency cure rate
-- For each month, calculate how many loans that were delinquent in the prior
-- calendar month returned to CURRENT (0 DPD), and the cure rate.
--
-- OPTIMIZED SOLUTION:
-- WITH transitions AS (
--     SELECT s.loan_id, s.snapshot_month, s.days_past_due,
--            LAG(s.snapshot_month) OVER w AS prior_month,
--            LAG(s.days_past_due) OVER w AS prior_dpd
--     FROM v_loan_snapshot s
--     JOIN loan_account a ON a.loan_id = s.loan_id
--     WINDOW w AS (PARTITION BY s.loan_id ORDER BY s.snapshot_month)
-- ),
-- eligible AS (
--     SELECT *
--     FROM transitions
--     WHERE prior_month = (snapshot_month - INTERVAL '1 month')::date
--       AND prior_dpd > 0
-- )
-- SELECT snapshot_month,
--        COUNT(*) AS previously_delinquent_loans,
--        COUNT(*) FILTER (WHERE days_past_due = 0) AS cured_loans,
--        ROUND(
--          100.0 * COUNT(*) FILTER (WHERE days_past_due = 0)
--          / NULLIF(COUNT(*), 0),
--          2
--        ) AS cure_rate_pct
-- FROM eligible
-- GROUP BY snapshot_month
-- ORDER BY snapshot_month;
--
-- METRIC DEFINITION:
-- A cure means DPD returns to exactly zero. A move from 60 DPD to 20 DPD is
-- an improvement, but not a full cure under this definition.
--
-- WHY THIS IS OPTIMIZED:
-- Compute the prior-month attributes once in a window CTE, then reuse them for
-- eligibility and aggregation. COUNT(*) FILTER keeps numerator and denominator
-- in a single grouped pass.

-- ============================================================================
-- PROBLEM 6 — Collections efficiency by month, branch, and product
-- Calculate total scheduled dues, collections received, and weighted
-- collection efficiency. Do not average individual loan-level percentages.
--
-- OPTIMIZED SOLUTION:
-- SELECT s.snapshot_month,
--        a.branch_code,
--        a.product_code,
--        SUM(s.scheduled_due) AS scheduled_due,
--        SUM(s.paid_amount) AS amount_collected,
--        ROUND(
--          100.0 * SUM(s.paid_amount)
--          / NULLIF(SUM(s.scheduled_due), 0),
--          2
--        ) AS collection_efficiency_pct
-- FROM v_loan_snapshot s
-- JOIN loan_account a ON a.loan_id = s.loan_id
-- GROUP BY s.snapshot_month, a.branch_code, a.product_code
-- ORDER BY s.snapshot_month, a.branch_code, a.product_code;
--
-- WHY THIS IS OPTIMIZED:
-- Aggregate raw amounts first and divide once. An AVG(paid_amount /
-- scheduled_due) would give a small loan the same weight as a large loan and
-- can distort branch performance. NULLIF protects zero-denominator groups.
-- Catch-up payments can legitimately make the ratio exceed 100%.

-- ============================================================================
-- PROBLEM 7 — Latest branch-level risk concentration
-- Rank branches by 30+ DPD outstanding exposure and report delinquent exposure
-- as a percentage of each branch's total outstanding portfolio.
--
-- OPTIMIZED SOLUTION:
-- WITH latest AS (
--     SELECT DISTINCT ON (s.loan_id)
--            s.loan_id, s.outstanding_principal, s.days_past_due
--     FROM v_loan_snapshot s
--     JOIN loan_account a ON a.loan_id = s.loan_id
--     ORDER BY s.loan_id, s.snapshot_month DESC
-- )
-- SELECT a.branch_code,
--        COUNT(*) AS loan_count,
--        SUM(l.outstanding_principal) AS total_exposure,
--        SUM(l.outstanding_principal)
--          FILTER (WHERE l.days_past_due >= 30) AS exposure_30_plus,
--        ROUND(
--          100.0 * SUM(l.outstanding_principal)
--            FILTER (WHERE l.days_past_due >= 30)
--          / NULLIF(SUM(l.outstanding_principal), 0),
--          2
--        ) AS delinquent_exposure_pct
-- FROM latest l
-- JOIN loan_account a ON a.loan_id = l.loan_id
-- GROUP BY a.branch_code
-- ORDER BY exposure_30_plus DESC NULLS LAST;
--
-- WHY THIS IS OPTIMIZED:
-- Reduce the history to one row per loan before joining to branch attributes.
-- This prevents historical months from multiplying portfolio exposure and
-- keeps the branch aggregation at the intended latest-snapshot grain.

-- ============================================================================
-- PROBLEM 8 — Missing monthly snapshot detection
-- Generate each loan's expected month series from origination through the
-- latest available reporting month and return missing loan-month snapshots.
--
-- OPTIMIZED SOLUTION:
-- WITH reporting_horizon AS (
--     SELECT MAX(snapshot_month)::timestamp AS last_month
--     FROM v_loan_snapshot
-- )
-- SELECT a.loan_id,
--        g.expected_month::date AS missing_snapshot_month
-- FROM loan_account a
-- CROSS JOIN reporting_horizon h
-- CROSS JOIN LATERAL generate_series(
--     date_trunc('month', a.origination_date),
--     h.last_month,
--     INTERVAL '1 month'
-- ) AS g(expected_month)
-- LEFT JOIN v_loan_snapshot s
--   ON s.loan_id = a.loan_id
--  AND s.snapshot_month = g.expected_month::date
-- WHERE s.loan_id IS NULL
-- ORDER BY a.loan_id, missing_snapshot_month;
--
-- EXPECTED SPOT CHECK:
-- Loan 1007 is missing 2026-02-01.
--
-- WHY THIS IS OPTIMIZED:
-- Compute the reporting horizon once, generate only the months each loan
-- should exist, and use an anti-join pattern to find absent rows. For large
-- portfolios, a persisted calendar table and a materialized canonical
-- loan-month table can be more efficient than repeatedly expanding series.

-- ============================================================================
-- PROBLEM 9 — Canonical snapshot data-quality exceptions
-- Return canonical rows with an unknown loan, negative DPD/balance/payment,
-- balance above original principal, or a snapshot before origination.
--
-- OPTIMIZED SOLUTION:
-- SELECT s.snapshot_event_id,
--        s.loan_id,
--        s.snapshot_month,
--        ARRAY_REMOVE(ARRAY[
--          CASE WHEN a.loan_id IS NULL
--               THEN 'UNKNOWN_LOAN' END,
--          CASE WHEN s.days_past_due < 0
--               THEN 'NEGATIVE_DPD' END,
--          CASE WHEN s.outstanding_principal < 0
--               THEN 'NEGATIVE_BALANCE' END,
--          CASE WHEN a.loan_id IS NOT NULL
--                 AND s.outstanding_principal > a.original_principal
--               THEN 'BALANCE_EXCEEDS_ORIGINAL' END,
--          CASE WHEN s.scheduled_due < 0
--               THEN 'NEGATIVE_SCHEDULED_DUE' END,
--          CASE WHEN s.paid_amount < 0
--               THEN 'NEGATIVE_PAYMENT' END,
--          CASE WHEN a.loan_id IS NOT NULL
--                 AND s.snapshot_month
--                     < date_trunc('month', a.origination_date)::date
--               THEN 'SNAPSHOT_BEFORE_ORIGINATION' END
--        ], NULL) AS exception_codes
-- FROM v_loan_snapshot s
-- LEFT JOIN loan_account a ON a.loan_id = s.loan_id
-- WHERE a.loan_id IS NULL
--    OR s.days_past_due < 0
--    OR s.outstanding_principal < 0
--    OR s.scheduled_due < 0
--    OR s.paid_amount < 0
--    OR (a.loan_id IS NOT NULL
--        AND s.outstanding_principal > a.original_principal)
--    OR (a.loan_id IS NOT NULL
--        AND s.snapshot_month
--            < date_trunc('month', a.origination_date)::date)
-- ORDER BY s.loan_id, s.snapshot_month;
--
-- WHY THIS IS OPTIMIZED:
-- Validate after canonicalization so replayed versions do not inflate the
-- exception count. The LEFT JOIN is intentional: an INNER JOIN would silently
-- discard orphan source records. ARRAY_REMOVE returns only the triggered
-- exception codes without requiring one UNION branch per rule.

-- ============================================================================
-- PERFORMANCE LAB
--
-- 1. Compare the canonical view with a ROW_NUMBER() implementation:
--      ROW_NUMBER() OVER (
--        PARTITION BY loan_id, snapshot_month
--        ORDER BY source_updated_at DESC, ingested_at DESC,
--                 source_sequence DESC, snapshot_event_id DESC
--      )
--    Keep rn = 1. Both approaches should return identical keys and winners.
--
-- 2. Run representative exercises with:
--      EXPLAIN (ANALYZE, BUFFERS)
--    Inspect sort method, rows removed by filters, heap fetches, shared reads,
--    and whether the deduplication index is used. Do not assume an index is
--    beneficial merely because it exists.
--
-- 3. Keep predicates on snapshot_month SARGable. Prefer:
--      snapshot_month >= DATE '2026-03-01'
--      AND snapshot_month < DATE '2026-05-01'
--    over DATE_TRUNC('month', snapshot_month) in the WHERE clause.
--
-- 4. At production scale, consider monthly range partitioning of the raw
--    landing table, partition retention, and an incrementally maintained
--    canonical loan-month table with UNIQUE (loan_id, snapshot_month).
--    Refresh/materialize only after late corrections are reconciled.
--
-- 5. Avoid over-indexing a write-heavy ingestion table. Every additional index
--    increases insert/update cost and storage. Benchmark with representative
--    data volume, realistic duplicate rates, and current PostgreSQL statistics.
--
-- 6. Define the business meaning of DPD, cure, charge-off, and exposure before
--    publishing risk metrics. A month-end snapshot is not a daily delinquency
--    history, and missing snapshots must not be interpreted as cures.
-- ============================================================================
