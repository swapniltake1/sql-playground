/*
Topic: Double-Entry General Ledger Controls & Trial-Balance Reconciliation
Dialect: PostgreSQL 14+
Run independently. The deliberately invalid rows are included for control testing.
*/

DROP TABLE IF EXISTS gl_journal_lines;
DROP TABLE IF EXISTS gl_journal_entries;
DROP TABLE IF EXISTS gl_accounts;

CREATE TABLE gl_accounts (
    account_id      INTEGER PRIMARY KEY,
    account_code    VARCHAR(20) NOT NULL UNIQUE,
    account_name    VARCHAR(100) NOT NULL,
    account_type    VARCHAR(20) NOT NULL
        CHECK (account_type IN ('ASSET','LIABILITY','EQUITY','REVENUE','EXPENSE')),
    is_active       BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE gl_journal_entries (
    entry_id        BIGINT PRIMARY KEY,
    batch_id        VARCHAR(30) NOT NULL,
    entry_date      DATE NOT NULL,
    posted_at       TIMESTAMP,
    status          VARCHAR(10) NOT NULL
        CHECK (status IN ('POSTED','DRAFT','VOID')),
    source_system   VARCHAR(30) NOT NULL,
    source_ref      VARCHAR(60) NOT NULL,
    currency_code   CHAR(3) NOT NULL DEFAULT 'USD'
);

-- account_id intentionally has no FK: staging/control exercises must be able
-- to identify unknown account codes before a production posting constraint rejects them.
CREATE TABLE gl_journal_lines (
    line_id         BIGINT PRIMARY KEY,
    entry_id        BIGINT NOT NULL REFERENCES gl_journal_entries(entry_id),
    account_id      INTEGER NOT NULL,
    debit_amount    NUMERIC(18,2) NOT NULL DEFAULT 0 CHECK (debit_amount >= 0),
    credit_amount   NUMERIC(18,2) NOT NULL DEFAULT 0 CHECK (credit_amount >= 0),
    line_memo       VARCHAR(200),
    CHECK (NOT (debit_amount > 0 AND credit_amount > 0))
);

INSERT INTO gl_accounts VALUES
(1000, '1000', 'Operating Cash',       'ASSET',     TRUE),
(1100, '1100', 'Trade Receivables',    'ASSET',     TRUE),
(2000, '2000', 'Trade Payables',       'LIABILITY', TRUE),
(2100, '2100', 'Tax Payable',          'LIABILITY', TRUE),
(3000, '3000', 'Retained Earnings',    'EQUITY',    TRUE),
(4000, '4000', 'Sales Revenue',        'REVENUE',   TRUE),
(5000, '5000', 'Operating Expense',    'EXPENSE',   TRUE),
(5100, '5100', 'Bank Fees',            'EXPENSE',   TRUE),
(5200, '5200', 'Legacy Expense',       'EXPENSE',   FALSE);

INSERT INTO gl_journal_entries
(entry_id, batch_id, entry_date, posted_at, status, source_system, source_ref, currency_code)
VALUES
(5001, 'B-OPEN', '2026-10-01', '2026-10-01 08:00:00', 'POSTED', 'ERP', 'OPEN-001', 'USD'),
(5002, 'B-SALES', '2026-10-02', '2026-10-02 09:05:00', 'POSTED', 'POS', 'SALE-1002', 'USD'),
(5003, 'B-AR', '2026-10-03', '2026-10-03 10:15:00', 'POSTED', 'BILLING', 'INV-2040', 'USD'),
(5004, 'B-AP', '2026-10-04', '2026-10-04 11:30:00', 'POSTED', 'ERP', 'PAY-883', 'USD'),
(5005, 'B-ERROR', '2026-10-05', '2026-10-05 12:00:00', 'POSTED', 'MANUAL', 'JV-778', 'USD'),
(5006, 'B-DRAFT', '2026-10-05', NULL, 'DRAFT', 'MANUAL', 'JV-779', 'USD'),
(5007, 'B-FEES', '2026-10-06', '2026-10-06 08:20:00', 'POSTED', 'BANK', 'FEE-010', 'USD'),
(5008, 'B-REPLAY', '2026-10-06', '2026-10-06 08:25:00', 'POSTED', 'POS', 'SALE-1002', 'USD'),
(5009, 'B-AR2', '2026-10-07', '2026-10-07 14:00:00', 'POSTED', 'BILLING', 'INV-2041', 'USD'),
(5010, 'B-UNKNOWN', '2026-10-08', '2026-10-08 09:00:00', 'POSTED', 'IMPORT', 'LEG-900', 'USD'),
(5011, 'B-INACTIVE', '2026-10-08', '2026-10-08 09:05:00', 'POSTED', 'IMPORT', 'LEG-901', 'USD'),
(5012, 'B-EMPTY', '2026-10-08', '2026-10-08 09:10:00', 'POSTED', 'IMPORT', 'LEG-902', 'USD');

INSERT INTO gl_journal_lines
(line_id, entry_id, account_id, debit_amount, credit_amount, line_memo)
VALUES
(1, 5001, 1000, 10000, 0, 'Opening cash'),
(2, 5001, 3000, 0, 10000, 'Opening equity'),
(3, 5002, 1000, 1200, 0, 'Card settlement'),
(4, 5002, 4000, 0, 1200, 'Retail sale'),
(5, 5003, 1100, 800, 0, 'Customer invoice'),
(6, 5003, 4000, 0, 700, 'Invoice revenue'),
(7, 5003, 2100, 0, 100, 'Sales tax'),
(8, 5004, 5000, 300, 0, 'Supplier expense'),
(9, 5004, 1000, 0, 300, 'Supplier payment'),
(10, 5005, 1000, 500, 0, 'Intentional imbalance'),
(11, 5005, 4000, 0, 450, 'Intentional imbalance'),
(12, 5006, 1000, 75, 0, 'Draft only'),
(13, 5006, 4000, 0, 75, 'Draft only'),
(14, 5007, 5100, 25, 0, 'Monthly bank fee'),
(15, 5007, 1000, 0, 25, 'Bank debit'),
(16, 5008, 1000, 1200, 0, 'Replayed POS settlement'),
(17, 5008, 4000, 0, 1200, 'Replayed POS sale'),
(18, 5009, 1100, 400, 0, 'Customer invoice'),
(19, 5009, 4000, 0, 400, 'Invoice revenue'),
(20, 5010, 9999, 50, 0, 'Unknown account in imported batch'),
(21, 5010, 1000, 0, 50, 'Offset to unknown account'),
(22, 5011, 5200, 10, 0, 'Posting to inactive account'),
(23, 5011, 1000, 0, 10, 'Offset to inactive account');

-- Q1. Which posted journal entries do not balance?
-- A valid entry has total debits equal to total credits at entry + currency grain.
WITH entry_totals AS (
    SELECT
        e.entry_id,
        e.batch_id,
        e.entry_date,
        e.currency_code,
        SUM(l.debit_amount)  AS total_debits,
        SUM(l.credit_amount) AS total_credits
    FROM gl_journal_entries e
    JOIN gl_journal_lines l ON l.entry_id = e.entry_id
    WHERE e.status = 'POSTED'
    GROUP BY e.entry_id, e.batch_id, e.entry_date, e.currency_code
)
SELECT *,
       total_debits - total_credits AS imbalance
FROM entry_totals
WHERE total_debits <> total_credits
ORDER BY entry_date, entry_id;
-- Expected: entry 5005, imbalance 50.00.
-- Optimization: aggregate only posted entries; the partial entry-date index below
-- helps date-scoped controls, while entry_id PK lookups support the line join.

-- Q2. Produce a trial balance by account for posted entries through 8 Oct 2026.
-- Debit-normal accounts: assets/expenses. Credit-normal: liabilities/equity/revenue.
WITH account_totals AS (
    SELECT
        a.account_id,
        a.account_code,
        a.account_name,
        a.account_type,
        COALESCE(SUM(l.debit_amount), 0)  AS debits,
        COALESCE(SUM(l.credit_amount), 0) AS credits
    FROM gl_accounts a
    LEFT JOIN gl_journal_lines l ON l.account_id = a.account_id
    LEFT JOIN gl_journal_entries e
        ON e.entry_id = l.entry_id
       AND e.status = 'POSTED'
       AND e.entry_date <= DATE '2026-10-08'
    WHERE a.is_active = TRUE
    GROUP BY a.account_id, a.account_code, a.account_name, a.account_type
)
SELECT
    account_code,
    account_name,
    debits,
    credits,
    CASE
        WHEN account_type IN ('ASSET','EXPENSE') THEN debits - credits
        ELSE credits - debits
    END AS normal_balance
FROM account_totals
ORDER BY account_code;
-- Note: for a strict production trial balance, move the entry filter into a
-- filtered-entry CTE before joining lines. This preserves zero-activity accounts
-- without accidentally counting non-posted lines.

-- Q3. Calculate each account's chronological running balance (posted entries only).
WITH account_activity AS (
    SELECT
        a.account_id,
        a.account_code,
        a.account_name,
        a.account_type,
        e.entry_date,
        e.entry_id,
        l.line_id,
        CASE
            WHEN a.account_type IN ('ASSET','EXPENSE')
                THEN l.debit_amount - l.credit_amount
            ELSE l.credit_amount - l.debit_amount
        END AS signed_amount
    FROM gl_journal_entries e
    JOIN gl_journal_lines l ON l.entry_id = e.entry_id
    JOIN gl_accounts a ON a.account_id = l.account_id
    WHERE e.status = 'POSTED'
      AND a.is_active = TRUE
)
SELECT
    account_code,
    account_name,
    entry_date,
    entry_id,
    line_id,
    signed_amount,
    SUM(signed_amount) OVER (
        PARTITION BY account_id
        ORDER BY entry_date, entry_id, line_id
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS running_normal_balance
FROM account_activity
ORDER BY account_code, entry_date, entry_id, line_id;
-- Optimization: the explicit ROWS frame and stable tie-breakers make the running
-- total deterministic. For large ledgers, filter the date range before the window.

-- Q4. Detect replayed source transactions before downstream reconciliation.
SELECT
    source_system,
    source_ref,
    COUNT(*) AS entry_count,
    ARRAY_AGG(entry_id ORDER BY entry_id) AS entry_ids
FROM gl_journal_entries
WHERE status = 'POSTED'
GROUP BY source_system, source_ref
HAVING COUNT(*) > 1
ORDER BY source_system, source_ref;
-- Expected: POS / SALE-1002. In production, enforce idempotency with a unique
-- source key after historical duplicates have been resolved.

-- Q5. Find posted lines that use unknown or inactive accounts.
SELECT
    e.entry_id,
    e.batch_id,
    l.line_id,
    l.account_id,
    a.account_name,
    a.is_active,
    l.debit_amount,
    l.credit_amount,
    CASE
        WHEN a.account_id IS NULL THEN 'UNKNOWN_ACCOUNT'
        WHEN a.is_active = FALSE THEN 'INACTIVE_ACCOUNT'
    END AS control_failure
FROM gl_journal_entries e
JOIN gl_journal_lines l ON l.entry_id = e.entry_id
LEFT JOIN gl_accounts a ON a.account_id = l.account_id
WHERE e.status = 'POSTED'
  AND (a.account_id IS NULL OR a.is_active = FALSE)
ORDER BY e.entry_id, l.line_id;
-- Expected: line 20 (unknown 9999) and line 22 (inactive 5200).

-- Q6. Find posted entries with no journal lines.
SELECT e.entry_id, e.batch_id, e.entry_date, e.source_system, e.source_ref
FROM gl_journal_entries e
WHERE e.status = 'POSTED'
  AND NOT EXISTS (
      SELECT 1
      FROM gl_journal_lines l
      WHERE l.entry_id = e.entry_id
  )
ORDER BY e.entry_date, e.entry_id;
-- Expected: entry 5012. NOT EXISTS avoids materializing a potentially large
-- anti-join result and can use the entry_id-leading line index.

-- Q7. Reconcile each posted batch and expose both the debit/credit difference
-- and the number of distinct journal lines.
SELECT
    e.batch_id,
    e.currency_code,
    COUNT(l.line_id) AS line_count,
    SUM(l.debit_amount) AS debits,
    SUM(l.credit_amount) AS credits,
    SUM(l.debit_amount) - SUM(l.credit_amount) AS difference,
    CASE
        WHEN COUNT(l.line_id) = 0 THEN 'EMPTY'
        WHEN SUM(l.debit_amount) <> SUM(l.credit_amount) THEN 'OUT_OF_BALANCE'
        ELSE 'BALANCED'
    END AS batch_status
FROM gl_journal_entries e
LEFT JOIN gl_journal_lines l ON l.entry_id = e.entry_id
WHERE e.status = 'POSTED'
GROUP BY e.batch_id, e.currency_code
ORDER BY e.batch_id;
-- If a batch can contain multiple currencies, never net unlike currencies.
-- Keep currency_code in the grouping key or convert using a governed FX rate.

-- Q8. Build a compact control-exception feed for a daily finance pipeline.
WITH imbalance AS (
    SELECT e.entry_id::TEXT AS object_key, 'ENTRY_IMBALANCE' AS issue_code
    FROM gl_journal_entries e
    JOIN gl_journal_lines l ON l.entry_id = e.entry_id
    WHERE e.status = 'POSTED'
    GROUP BY e.entry_id
    HAVING SUM(l.debit_amount) <> SUM(l.credit_amount)
),
bad_account AS (
    SELECT DISTINCT e.entry_id::TEXT, 'INVALID_ACCOUNT'
    FROM gl_journal_entries e
    JOIN gl_journal_lines l ON l.entry_id = e.entry_id
    LEFT JOIN gl_accounts a ON a.account_id = l.account_id
    WHERE e.status = 'POSTED'
      AND (a.account_id IS NULL OR a.is_active = FALSE)
),
empty_entry AS (
    SELECT e.entry_id::TEXT, 'EMPTY_ENTRY'
    FROM gl_journal_entries e
    WHERE e.status = 'POSTED'
      AND NOT EXISTS (
          SELECT 1 FROM gl_journal_lines l WHERE l.entry_id = e.entry_id
      )
)
SELECT object_key, issue_code FROM imbalance
UNION ALL
SELECT object_key, issue_code FROM bad_account
UNION ALL
SELECT object_key, issue_code FROM empty_entry
ORDER BY object_key, issue_code;
-- A production exception feed should include detection timestamp, batch/run ID,
-- severity, owner, and remediation state so alerts can be tracked to closure.

-- Candidate indexes: benchmark with representative production volumes.
CREATE INDEX idx_gl_entries_posted_date
    ON gl_journal_entries (entry_date, entry_id)
    WHERE status = 'POSTED';

CREATE INDEX idx_gl_lines_entry_account
    ON gl_journal_lines (entry_id, account_id);

CREATE INDEX idx_gl_entries_source_key
    ON gl_journal_entries (source_system, source_ref)
    WHERE status = 'POSTED';

-- Performance checklist:
-- 1. Keep currency in every balancing/reconciliation grain.
-- 2. Filter to POSTED and the required date range before expensive windows.
-- 3. Use stable tie-breakers for all running totals and ARRAY_AGG results.
-- 4. Resolve historical duplicate source keys before adding a UNIQUE constraint.
-- 5. Validate account status and entry balance before committing a posting batch.
-- 6. Run EXPLAIN (ANALYZE, BUFFERS) on realistic volumes; these indexes are candidates,
--    not guaranteed wins for this deliberately small teaching dataset.
