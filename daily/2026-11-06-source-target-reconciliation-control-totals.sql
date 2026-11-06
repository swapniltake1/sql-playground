-- =============================================================================
-- Daily SQL Practice — 2026-11-06
-- Topic: Source-to-Target Reconciliation, Control Totals & Exception Reporting
-- PostgreSQL 14+
--
-- Run this file independently in a disposable PostgreSQL database.
-- Each question is followed by a commented reference solution.
-- =============================================================================

DROP TABLE IF EXISTS target_transactions;
DROP TABLE IF EXISTS source_transactions;
DROP TABLE IF EXISTS reconciliation_batches;

CREATE TABLE reconciliation_batches (
    batch_id       bigint PRIMARY KEY,
    source_name    text NOT NULL,
    business_date  date NOT NULL,
    extracted_at   timestamptz NOT NULL,
    status         text NOT NULL CHECK (status IN ('READY', 'CLOSED'))
);

CREATE TABLE source_transactions (
    source_row_id  bigint PRIMARY KEY,
    batch_id       bigint NOT NULL REFERENCES reconciliation_batches(batch_id),
    source_txn_id  text NOT NULL,
    account_id     bigint NOT NULL,
    txn_ts         timestamptz NOT NULL,
    currency       char(3) NOT NULL,
    amount         numeric(14,2) NOT NULL,
    operation      text NOT NULL CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE')),
    source_version integer NOT NULL,
    ingested_at    timestamptz NOT NULL
);

CREATE TABLE target_transactions (
    source_name    text NOT NULL,
    source_txn_id  text NOT NULL,
    account_id     bigint NOT NULL,
    txn_ts         timestamptz NOT NULL,
    currency       char(3) NOT NULL,
    amount         numeric(14,2) NOT NULL,
    source_version integer NOT NULL,
    is_deleted     boolean NOT NULL DEFAULT false,
    updated_at     timestamptz NOT NULL,
    PRIMARY KEY (source_name, source_txn_id)
);

INSERT INTO reconciliation_batches VALUES
(501, 'CORE_BANKING', DATE '2026-11-05', TIMESTAMPTZ '2026-11-06 01:00:00+00', 'READY'),
(502, 'CARD_SWITCH',  DATE '2026-11-05', TIMESTAMPTZ '2026-11-06 01:05:00+00', 'READY');

INSERT INTO source_transactions VALUES
(1, 501, 'TX1001', 10001, '2026-11-05 09:00:00+00', 'INR', 1200.00, 'INSERT', 1, '2026-11-06 01:01:00+00'),
(2, 501, 'TX1002', 10002, '2026-11-05 10:00:00+00', 'INR',  500.00, 'INSERT', 1, '2026-11-06 01:01:10+00'),
(3, 501, 'TX1002', 10002, '2026-11-05 10:00:00+00', 'INR',  550.00, 'UPDATE', 2, '2026-11-06 01:02:00+00'),
(4, 501, 'TX1003', 10003, '2026-11-05 11:00:00+00', 'INR',  900.00, 'INSERT', 1, '2026-11-06 01:02:10+00'),
(5, 501, 'TX1003', 10003, '2026-11-05 11:00:00+00', 'INR',  900.00, 'INSERT', 1, '2026-11-06 01:03:00+00'),
(6, 501, 'TX1004', 10004, '2026-11-05 12:00:00+00', 'INR',  250.00, 'DELETE', 2, '2026-11-06 01:04:00+00'),
(7, 501, 'TX1005', 10005, '2026-11-05 13:00:00+00', 'INR',  700.00, 'INSERT', 1, '2026-11-06 01:04:10+00'),
(8, 502, 'CARD77', 20001, '2026-11-05 14:00:00+00', 'INR', 1800.00, 'INSERT', 1, '2026-11-06 01:05:00+00');

INSERT INTO target_transactions VALUES
('CORE_BANKING', 'TX1001', 10001, '2026-11-05 09:00:00+00', 'INR', 1200.00, 1, false, '2026-11-06 01:10:00+00'),
('CORE_BANKING', 'TX1002', 10002, '2026-11-05 10:00:00+00', 'INR',  500.00, 1, false, '2026-11-06 01:10:00+00'),
('CORE_BANKING', 'TX1004', 10004, '2026-11-05 12:00:00+00', 'INR',  250.00, 1, false, '2026-11-06 01:10:00+00'),
('CORE_BANKING', 'TX9999', 10999, '2026-11-05 15:00:00+00', 'INR',   50.00, 1, false, '2026-11-06 01:10:00+00');

-- Q1. Deduplicate source events by business key, keeping the highest version.
-- SELECT DISTINCT ON (source_name, source_txn_id) ...
-- Prefer ROW_NUMBER when portability to other SQL engines matters.
WITH ranked AS (
    SELECT s.*,
           ROW_NUMBER() OVER (
               PARTITION BY b.source_name, s.source_txn_id
               ORDER BY s.source_version DESC, s.ingested_at DESC, s.source_row_id DESC
           ) AS rn
    FROM source_transactions s
    JOIN reconciliation_batches b USING (batch_id)
    WHERE s.batch_id = 501
)
SELECT source_txn_id, operation, source_version, amount
FROM ranked
WHERE rn = 1
ORDER BY source_txn_id;

-- Q2. Produce source-versus-target control totals at batch and currency grain.
-- Compare row counts and signed monetary totals; do not mix currencies.
WITH src AS (
    SELECT b.source_name, s.currency,
           COUNT(*) FILTER (WHERE s.operation <> 'DELETE') AS source_rows,
           SUM(s.amount) FILTER (WHERE s.operation <> 'DELETE') AS source_amount
    FROM source_transactions s
    JOIN reconciliation_batches b USING (batch_id)
    WHERE s.batch_id = 501
    GROUP BY b.source_name, s.currency
), tgt AS (
    SELECT source_name, currency,
           COUNT(*) FILTER (WHERE NOT is_deleted) AS target_rows,
           SUM(amount) FILTER (WHERE NOT is_deleted) AS target_amount
    FROM target_transactions
    WHERE source_name = 'CORE_BANKING'
    GROUP BY source_name, currency
)
SELECT COALESCE(src.source_name, tgt.source_name) AS source_name,
       COALESCE(src.currency, tgt.currency) AS currency,
       source_rows, target_rows, source_amount, target_amount,
       COALESCE(source_rows, 0) - COALESCE(target_rows, 0) AS row_delta,
       COALESCE(source_amount, 0) - COALESCE(target_amount, 0) AS amount_delta
FROM src
FULL OUTER JOIN tgt USING (source_name, currency);

-- Q3. Identify missing and extra business keys using a FULL OUTER JOIN.
WITH latest_source AS (
    SELECT DISTINCT ON (b.source_name, s.source_txn_id)
           b.source_name, s.source_txn_id, s.operation
    FROM source_transactions s
    JOIN reconciliation_batches b USING (batch_id)
    WHERE s.batch_id = 501
    ORDER BY b.source_name, s.source_txn_id,
             s.source_version DESC, s.ingested_at DESC, s.source_row_id DESC
)
SELECT COALESCE(s.source_txn_id, t.source_txn_id) AS transaction_id,
       CASE
         WHEN s.source_txn_id IS NULL THEN 'EXTRA_IN_TARGET'
         WHEN t.source_txn_id IS NULL AND s.operation <> 'DELETE' THEN 'MISSING_IN_TARGET'
         WHEN s.operation = 'DELETE' AND t.is_deleted = false THEN 'DELETE_NOT_APPLIED'
         ELSE 'MATCHED_OR_EXPECTED_DELETE'
       END AS reconciliation_status
FROM latest_source s
FULL OUTER JOIN target_transactions t
  ON t.source_name = s.source_name
 AND t.source_txn_id = s.source_txn_id
WHERE t.source_txn_id IS NULL
   OR s.source_txn_id IS NULL
   OR (s.operation = 'DELETE' AND t.is_deleted = false)
ORDER BY transaction_id;

-- Q4. Find attribute-level mismatches for matching, non-deleted records.
WITH latest_source AS (
    SELECT DISTINCT ON (b.source_name, s.source_txn_id)
           b.source_name, s.*
    FROM source_transactions s
    JOIN reconciliation_batches b USING (batch_id)
    WHERE s.batch_id = 501
    ORDER BY b.source_name, s.source_txn_id,
             s.source_version DESC, s.ingested_at DESC, s.source_row_id DESC
)
SELECT s.source_txn_id,
       s.amount AS source_amount, t.amount AS target_amount,
       s.account_id AS source_account, t.account_id AS target_account,
       s.currency AS source_currency, t.currency AS target_currency
FROM latest_source s
JOIN target_transactions t
  ON t.source_name = s.source_name
 AND t.source_txn_id = s.source_txn_id
WHERE s.operation <> 'DELETE'
  AND NOT t.is_deleted
  AND (s.amount, s.account_id, s.currency)
      IS DISTINCT FROM
      (t.amount, t.account_id, t.currency);

-- Q5. Detect duplicate source events and quantify replay volume.
SELECT batch_id, source_txn_id, source_version,
       COUNT(*) AS copies,
       MIN(ingested_at) AS first_seen,
       MAX(ingested_at) AS last_seen
FROM source_transactions
GROUP BY batch_id, source_txn_id, source_version
HAVING COUNT(*) > 1
ORDER BY copies DESC, source_txn_id;

-- Q6. Build an exception summary suitable for a pipeline quality gate.
WITH latest_source AS (
    SELECT DISTINCT ON (b.source_name, s.source_txn_id)
           b.source_name, s.source_txn_id, s.operation, s.amount, s.account_id, s.currency
    FROM source_transactions s
    JOIN reconciliation_batches b USING (batch_id)
    WHERE s.batch_id = 501
    ORDER BY b.source_name, s.source_txn_id,
             s.source_version DESC, s.ingested_at DESC, s.source_row_id DESC
), exceptions AS (
    SELECT 'MISSING_TARGET' AS issue_type
    FROM latest_source s
    LEFT JOIN target_transactions t
      ON t.source_name = s.source_name AND t.source_txn_id = s.source_txn_id
    WHERE t.source_txn_id IS NULL AND s.operation <> 'DELETE'
    UNION ALL
    SELECT 'EXTRA_TARGET'
    FROM target_transactions t
    LEFT JOIN latest_source s
      ON s.source_name = t.source_name AND s.source_txn_id = t.source_txn_id
    WHERE s.source_txn_id IS NULL AND NOT t.is_deleted
    UNION ALL
    SELECT 'ATTRIBUTE_MISMATCH'
    FROM latest_source s
    JOIN target_transactions t
      ON t.source_name = s.source_name AND t.source_txn_id = s.source_txn_id
    WHERE s.operation <> 'DELETE' AND NOT t.is_deleted
      AND (s.amount, s.account_id, s.currency)
          IS DISTINCT FROM (t.amount, t.account_id, t.currency)
)
SELECT issue_type, COUNT(*) AS exception_count
FROM exceptions
GROUP BY issue_type
ORDER BY issue_type;

-- Q7. Demonstrate a safe incremental target upsert from the canonical latest event.
-- In production, execute inside a transaction and persist a batch watermark only
-- after the target write and reconciliation gate both succeed.
WITH ranked AS (
    SELECT b.source_name, s.*,
           ROW_NUMBER() OVER (
               PARTITION BY b.source_name, s.source_txn_id
               ORDER BY s.source_version DESC, s.ingested_at DESC, s.source_row_id DESC
           ) AS rn
    FROM source_transactions s
    JOIN reconciliation_batches b USING (batch_id)
    WHERE s.batch_id = 501
)
INSERT INTO target_transactions (
    source_name, source_txn_id, account_id, txn_ts, currency,
    amount, source_version, is_deleted, updated_at
)
SELECT source_name, source_txn_id, account_id, txn_ts, currency,
       amount, source_version, operation = 'DELETE', ingested_at
FROM ranked
WHERE rn = 1
ON CONFLICT (source_name, source_txn_id) DO UPDATE
SET account_id = EXCLUDED.account_id,
    txn_ts = EXCLUDED.txn_ts,
    currency = EXCLUDED.currency,
    amount = EXCLUDED.amount,
    source_version = EXCLUDED.source_version,
    is_deleted = EXCLUDED.is_deleted,
    updated_at = EXCLUDED.updated_at
WHERE EXCLUDED.source_version > target_transactions.source_version;

-- Q8. Validate reconciliation after Q7. Expected: no missing/extra active rows
-- for batch 501 after applying the latest source state; TX9999 remains extra.
SELECT source_txn_id, is_deleted, source_version
FROM target_transactions
WHERE source_name = 'CORE_BANKING'
ORDER BY source_txn_id;

-- Performance and production notes:
-- 1. Index source_transactions(batch_id, source_txn_id, source_version DESC).
-- 2. The target primary key supports the upsert conflict lookup.
-- 3. For large batches, partition source staging by business_date or batch_id
--    only after measuring partition count and pruning effectiveness.
-- 4. Keep amounts grouped by currency; never sum unlike currencies together.
-- 5. Store reconciliation results and batch watermarks transactionally.
-- 6. Use EXPLAIN (ANALYZE, BUFFERS) with representative volumes; small fixtures
--    are for correctness, not meaningful index benchmarks.
-- 7. Define whether source deletes are hard deletes or tombstones and reconcile
--    with the same semantic contract on both sides.
