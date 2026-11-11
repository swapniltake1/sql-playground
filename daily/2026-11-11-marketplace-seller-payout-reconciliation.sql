-- Daily SQL Practice — 2026-11-11
-- Topic: Marketplace seller payout reconciliation, reserves, and settlement controls
-- PostgreSQL 14+
-- Run in a disposable practice database. Each section is self-contained after setup.

DROP TABLE IF EXISTS payout_adjustments;
DROP TABLE IF EXISTS payout_items;
DROP TABLE IF EXISTS seller_payouts;

CREATE TABLE seller_payouts (
    payout_id       bigint PRIMARY KEY,
    seller_id       bigint NOT NULL,
    period_start    date NOT NULL,
    period_end      date NOT NULL,
    currency        char(3) NOT NULL,
    status          text NOT NULL CHECK (status IN ('draft','approved','paid','held')),
    paid_at         timestamptz,
    UNIQUE (seller_id, period_start, period_end, currency)
);

CREATE TABLE payout_items (
    item_id         bigint PRIMARY KEY,
    payout_id       bigint NOT NULL REFERENCES seller_payouts,
    order_id        bigint NOT NULL,
    item_type       text NOT NULL CHECK (item_type IN ('sale','refund','fee','tax')),
    amount_minor    bigint NOT NULL,
    source_event_id text NOT NULL,
    recorded_at     timestamptz NOT NULL,
    UNIQUE (source_event_id)
);

CREATE TABLE payout_adjustments (
    adjustment_id  bigint PRIMARY KEY,
    payout_id      bigint NOT NULL REFERENCES seller_payouts,
    reason         text NOT NULL,
    amount_minor   bigint NOT NULL,
    approved       boolean NOT NULL,
    created_at     timestamptz NOT NULL
);

INSERT INTO seller_payouts VALUES
(1001, 501, DATE '2026-11-01', DATE '2026-11-07', 'INR', 'paid',     '2026-11-09 10:00+05:30'),
(1002, 502, DATE '2026-11-01', DATE '2026-11-07', 'INR', 'approved', NULL),
(1003, 501, DATE '2026-11-08', DATE '2026-11-14', 'INR', 'held',     NULL),
(1004, 503, DATE '2026-11-01', DATE '2026-11-07', 'USD', 'paid',     '2026-11-09 12:00+00');

INSERT INTO payout_items VALUES
(1,1001,9001,'sale',  125000,'evt-1','2026-11-07 18:00+05:30'),
(2,1001,9001,'fee',    -5000,'evt-2','2026-11-07 18:01+05:30'),
(3,1001,9002,'sale',   80000,'evt-3','2026-11-07 19:00+05:30'),
(4,1001,9002,'refund',-20000,'evt-4','2026-11-08 08:00+05:30'),
(5,1002,9010,'sale',  200000,'evt-5','2026-11-07 20:00+05:30'),
(6,1002,9011,'sale',   50000,'evt-6','2026-11-07 20:05+05:30'),
(7,1002,9011,'fee',    -2500,'evt-7','2026-11-07 20:06+05:30'),
(8,1003,9020,'sale',   90000,'evt-8','2026-11-10 11:00+05:30'),
(9,1004,9030,'sale',  100000,'evt-9','2026-11-07 10:00+00');

INSERT INTO payout_adjustments VALUES
(11,1001,'goodwill credit',  1500,true,'2026-11-08 09:00+05:30'),
(12,1001,'manual correction',-500,false,'2026-11-08 10:00+05:30'),
(13,1002,'chargeback reserve',-10000,true,'2026-11-08 11:00+05:30'),
(14,1003,'risk reserve',-15000,true,'2026-11-10 12:00+05:30');

-- Q1. Calculate each payout's gross sales, refunds, fees, approved adjustments,
--     and net payable. Keep currency and payout grain; do not multiply rows.
-- Solution:
WITH item_totals AS (
    SELECT payout_id,
           SUM(amount_minor) FILTER (WHERE item_type = 'sale') AS sales_minor,
           SUM(amount_minor) FILTER (WHERE item_type = 'refund') AS refunds_minor,
           SUM(amount_minor) FILTER (WHERE item_type = 'fee') AS fees_minor
    FROM payout_items
    GROUP BY payout_id
),
adjustment_totals AS (
    SELECT payout_id, SUM(amount_minor) AS approved_adjustments_minor
    FROM payout_adjustments
    WHERE approved
    GROUP BY payout_id
)
SELECT p.payout_id, p.seller_id, p.currency,
       COALESCE(i.sales_minor,0) AS sales_minor,
       COALESCE(i.refunds_minor,0) AS refunds_minor,
       COALESCE(i.fees_minor,0) AS fees_minor,
       COALESCE(a.approved_adjustments_minor,0) AS approved_adjustments_minor,
       COALESCE(i.sales_minor,0) + COALESCE(i.refunds_minor,0)
         + COALESCE(i.fees_minor,0) + COALESCE(a.approved_adjustments_minor,0) AS net_payable_minor
FROM seller_payouts p
LEFT JOIN item_totals i USING (payout_id)
LEFT JOIN adjustment_totals a USING (payout_id)
ORDER BY p.payout_id;

-- Q2. Find paid payouts whose paid amount would be negative or zero.
-- Solution: reuse the one-row-per-payout aggregates from Q1; filter net_payable_minor <= 0.

-- Q3. Identify duplicate source events before enforcing a unique constraint in a
--     legacy ingestion table. Return every duplicate event and its occurrences.
-- Solution:
SELECT source_event_id, COUNT(*) AS occurrences,
       ARRAY_AGG(item_id ORDER BY recorded_at, item_id) AS item_ids
FROM payout_items
GROUP BY source_event_id
HAVING COUNT(*) > 1;

-- Q4. Rank sellers by net payable within each currency and payout period.
-- Solution:
WITH net AS (
    SELECT p.seller_id, p.currency, p.period_start, p.period_end,
           SUM(i.amount_minor) AS item_net_minor
    FROM seller_payouts p
    JOIN payout_items i USING (payout_id)
    GROUP BY p.seller_id, p.currency, p.period_start, p.period_end
)
SELECT *, DENSE_RANK() OVER (
    PARTITION BY currency, period_start, period_end
    ORDER BY item_net_minor DESC
) AS seller_rank
FROM net;

-- Q5. Find approved adjustments that were created after a payout was already paid.
-- Solution:
SELECT a.adjustment_id, a.payout_id, a.reason, a.amount_minor,
       p.paid_at, a.created_at
FROM payout_adjustments a
JOIN seller_payouts p USING (payout_id)
WHERE a.approved
  AND p.status = 'paid'
  AND a.created_at > p.paid_at;

-- Q6. Reconcile expected payout totals to an external settlement feed.
CREATE TEMP TABLE bank_settlements (
    payout_id bigint,
    currency char(3),
    settled_minor bigint
);
INSERT INTO bank_settlements VALUES
(1001,'INR',181500),(1002,'INR',237500),(1004,'USD',100000);

-- Solution: full outer join preserves missing and unexpected bank rows.
WITH expected AS (
    SELECT p.payout_id, p.currency,
           COALESCE(SUM(i.amount_minor),0)
           + COALESCE((SELECT SUM(a.amount_minor)
                       FROM payout_adjustments a
                       WHERE a.payout_id = p.payout_id AND a.approved),0) AS expected_minor
    FROM seller_payouts p
    LEFT JOIN payout_items i USING (payout_id)
    GROUP BY p.payout_id, p.currency
)
SELECT COALESCE(e.payout_id,b.payout_id) AS payout_id,
       COALESCE(e.currency,b.currency) AS currency,
       e.expected_minor, b.settled_minor,
       CASE WHEN e.payout_id IS NULL THEN 'unexpected_bank_row'
            WHEN b.payout_id IS NULL THEN 'missing_bank_row'
            WHEN e.currency <> b.currency THEN 'currency_mismatch'
            WHEN e.expected_minor <> b.settled_minor THEN 'amount_mismatch'
            ELSE 'matched' END AS reconciliation_status
FROM expected e
FULL OUTER JOIN bank_settlements b
  ON b.payout_id = e.payout_id AND b.currency = e.currency
ORDER BY payout_id;

-- Q7. Detect held payouts whose approved reserve exceeds 10% of positive sales.
-- Solution:
WITH totals AS (
    SELECT p.payout_id,
           SUM(i.amount_minor) FILTER (WHERE i.item_type = 'sale') AS sales_minor,
           -SUM(a.amount_minor) FILTER (WHERE a.reason LIKE '%reserve%') AS reserve_minor
    FROM seller_payouts p
    LEFT JOIN payout_items i USING (payout_id)
    LEFT JOIN payout_adjustments a ON a.payout_id = p.payout_id AND a.approved
    WHERE p.status = 'held'
    GROUP BY p.payout_id
)
SELECT payout_id, sales_minor, reserve_minor
FROM totals
WHERE sales_minor > 0
  AND reserve_minor > sales_minor * 0.10;

-- Q8. Return the latest payout state per seller and currency.
-- Solution:
SELECT DISTINCT ON (seller_id, currency)
       seller_id, currency, payout_id, status, period_end
FROM seller_payouts
ORDER BY seller_id, currency, period_end DESC, payout_id DESC;

-- Performance notes:
-- * Aggregate each one-to-many child table before joining it to payout headers.
--   Joining items and adjustments raw creates fanout and inflates money amounts.
-- * Candidate indexes for production-sized tables:
--   CREATE INDEX ON payout_items (payout_id, item_type);
--   CREATE INDEX ON payout_adjustments (payout_id) WHERE approved;
--   CREATE INDEX ON seller_payouts (seller_id, currency, period_end DESC);
-- * Keep monetary values in integer minor units and never aggregate across currencies.
-- * Validate settlement uniqueness at (payout_id, currency); define an explicit policy
--   for partial settlements and FX conversion rather than silently netting currencies.
-- * Benchmark with EXPLAIN (ANALYZE, BUFFERS) on representative volumes.
