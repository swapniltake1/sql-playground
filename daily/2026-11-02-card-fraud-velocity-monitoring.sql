/*
===============================================================================
DAILY SQL PRACTICE — 2026-11-02
Topic: Card Fraud Velocity, Peer Baselines & Idempotent Alerting
Engine: PostgreSQL 14+

Problem statement
-----------------
Build a small, explainable card-transaction monitoring workflow. Detect rapid
spending bursts, unusually large purchases relative to a merchant-category
baseline, cross-border activity, and repeated authorization attempts. Persist
the rule hits safely so rerunning the same batch does not create duplicate
alerts.

Run this file independently. It drops and recreates only the practice tables
with the practice_fraud_ prefix. All timestamps are explicit UTC instants.
===============================================================================
*/

-- ---------------------------------------------------------------------------
-- 0. Isolated schema and realistic sample data
-- ---------------------------------------------------------------------------

DROP VIEW IF EXISTS practice_fraud_rule_hits;
DROP TABLE IF EXISTS practice_fraud_alerts;
DROP TABLE IF EXISTS practice_fraud_txn;
DROP TABLE IF EXISTS practice_fraud_merchant;
DROP TABLE IF EXISTS practice_fraud_card;

CREATE TABLE practice_fraud_card (
    card_id       text PRIMARY KEY,
    home_country  char(2) NOT NULL,
    risk_tier     text NOT NULL CHECK (risk_tier IN ('STANDARD', 'ELEVATED'))
);

CREATE TABLE practice_fraud_merchant (
    merchant_id   text PRIMARY KEY,
    merchant_name text NOT NULL,
    category      text NOT NULL,
    country_code  char(2) NOT NULL
);

CREATE TABLE practice_fraud_txn (
    transaction_id text PRIMARY KEY,
    card_id        text NOT NULL REFERENCES practice_fraud_card(card_id),
    merchant_id    text NOT NULL REFERENCES practice_fraud_merchant(merchant_id),
    event_ts       timestamptz NOT NULL,
    amount         numeric(12,2) NOT NULL CHECK (amount >= 0),
    currency       char(3) NOT NULL,
    status         text NOT NULL CHECK (status IN ('APPROVED', 'DECLINED', 'REVERSED')),
    channel        text NOT NULL CHECK (channel IN ('POS', 'ECOM', 'ATM'))
);

INSERT INTO practice_fraud_card (card_id, home_country, risk_tier) VALUES
    ('CARD-1001', 'US', 'STANDARD'),
    ('CARD-1002', 'US', 'STANDARD'),
    ('CARD-1003', 'IN', 'ELEVATED');

INSERT INTO practice_fraud_merchant
    (merchant_id, merchant_name, category, country_code) VALUES
    ('M-GROC-US',   'Market Street Grocery', 'GROCERY',     'US'),
    ('M-ELEC-US',   'Metro Electronics',    'ELECTRONICS', 'US'),
    ('M-FUEL-US',   'Highway Fuel',         'FUEL',        'US'),
    ('M-TRAVEL-US', 'City Travel Desk',     'TRAVEL',      'US'),
    ('M-TRAVEL-GB', 'Northstar Travel',     'TRAVEL',      'GB');

-- Historical approved transactions form the 30-day category baseline.
INSERT INTO practice_fraud_txn
    (transaction_id, card_id, merchant_id, event_ts, amount, currency, status, channel)
VALUES
    ('H-001', 'CARD-1001', 'M-GROC-US',   '2026-10-20 10:00:00+00',  24.00, 'USD', 'APPROVED', 'POS'),
    ('H-002', 'CARD-1001', 'M-GROC-US',   '2026-10-20 12:00:00+00',  38.00, 'USD', 'APPROVED', 'POS'),
    ('H-003', 'CARD-1001', 'M-GROC-US',   '2026-10-21 10:00:00+00',  42.00, 'USD', 'APPROVED', 'POS'),
    ('H-004', 'CARD-1002', 'M-GROC-US',   '2026-10-21 12:00:00+00',  55.00, 'USD', 'APPROVED', 'ECOM'),
    ('H-005', 'CARD-1001', 'M-ELEC-US',   '2026-10-20 11:00:00+00',  85.00, 'USD', 'APPROVED', 'POS'),
    ('H-006', 'CARD-1001', 'M-ELEC-US',   '2026-10-20 13:00:00+00', 110.00, 'USD', 'APPROVED', 'POS'),
    ('H-007', 'CARD-1002', 'M-ELEC-US',   '2026-10-21 14:00:00+00', 125.00, 'USD', 'APPROVED', 'ECOM'),
    ('H-008', 'CARD-1003', 'M-ELEC-US',   '2026-10-22 10:00:00+00', 145.00, 'USD', 'APPROVED', 'POS'),
    ('H-009', 'CARD-1003', 'M-TRAVEL-US', '2026-10-20 10:00:00+00', 180.00, 'USD', 'APPROVED', 'ECOM'),
    ('H-010', 'CARD-1003', 'M-TRAVEL-US', '2026-10-21 10:00:00+00', 220.00, 'USD', 'APPROVED', 'ECOM'),
    ('H-011', 'CARD-1003', 'M-TRAVEL-US', '2026-10-22 10:00:00+00', 260.00, 'USD', 'APPROVED', 'ECOM'),
    ('H-012', 'CARD-1001', 'M-TRAVEL-US', '2026-10-22 11:00:00+00', 300.00, 'USD', 'APPROVED', 'ECOM'),
    ('H-013', 'CARD-1002', 'M-FUEL-US',   '2026-10-20 09:00:00+00',  35.00, 'USD', 'APPROVED', 'POS'),
    ('H-014', 'CARD-1002', 'M-FUEL-US',   '2026-10-21 09:00:00+00',  45.00, 'USD', 'APPROVED', 'POS'),
    ('H-015', 'CARD-1003', 'M-FUEL-US',   '2026-10-22 09:00:00+00',  55.00, 'USD', 'APPROVED', 'POS');

-- Current-day transactions include deliberate patterns for the exercises.
INSERT INTO practice_fraud_txn
    (transaction_id, card_id, merchant_id, event_ts, amount, currency, status, channel)
VALUES
    ('T-001', 'CARD-1001', 'M-GROC-US',   '2026-11-02 09:00:00+00',  45.00, 'USD', 'APPROVED', 'POS'),
    ('T-002', 'CARD-1001', 'M-GROC-US',   '2026-11-02 09:04:00+00',  52.00, 'USD', 'APPROVED', 'POS'),
    ('T-003', 'CARD-1001', 'M-ELEC-US',   '2026-11-02 09:08:00+00', 480.00, 'USD', 'APPROVED', 'ECOM'),
    ('T-004', 'CARD-1001', 'M-ELEC-US',   '2026-11-02 09:10:00+00', 510.00, 'USD', 'APPROVED', 'ECOM'),
    ('T-005', 'CARD-1001', 'M-FUEL-US',   '2026-11-02 09:21:00+00',  35.00, 'USD', 'APPROVED', 'POS'),
    ('T-006', 'CARD-1002', 'M-ELEC-US',   '2026-11-02 09:02:00+00', 120.00, 'USD', 'APPROVED', 'POS'),
    ('T-007', 'CARD-1002', 'M-ELEC-US',   '2026-11-02 09:16:00+00', 130.00, 'USD', 'APPROVED', 'POS'),
    ('T-008', 'CARD-1002', 'M-ELEC-US',   '2026-11-02 09:31:00+00', 125.00, 'USD', 'APPROVED', 'POS'),
    ('T-009', 'CARD-1003', 'M-TRAVEL-GB', '2026-11-02 09:03:00+00', 950.00, 'USD', 'DECLINED', 'ECOM'),
    ('T-010', 'CARD-1003', 'M-TRAVEL-GB', '2026-11-02 09:05:00+00', 930.00, 'USD', 'APPROVED', 'ECOM'),
    ('T-011', 'CARD-1003', 'M-TRAVEL-GB', '2026-11-02 09:06:00+00', 940.00, 'USD', 'APPROVED', 'ECOM'),
    ('T-012', 'CARD-1003', 'M-GROC-US',   '2026-11-02 09:40:00+00',  20.00, 'USD', 'REVERSED', 'POS'),
    ('T-013', 'CARD-1002', 'M-GROC-US',   '2026-11-02 10:00:00+00',  20.00, 'USD', 'APPROVED', 'POS'),
    ('T-014', 'CARD-1001', 'M-GROC-US',   '2026-11-02 10:02:00+00',  49.00, 'USD', 'APPROVED', 'ECOM'),
    ('T-015', 'CARD-1001', 'M-GROC-US',   '2026-11-02 10:03:00+00',  49.00, 'USD', 'APPROVED', 'ECOM'),
    ('T-016', 'CARD-1001', 'M-TRAVEL-GB', '2026-11-02 10:20:00+00', 900.00, 'USD', 'APPROVED', 'ECOM'),
    ('T-017', 'CARD-1001', 'M-TRAVEL-GB', '2026-11-02 10:22:00+00', 920.00, 'USD', 'APPROVED', 'ECOM');

CREATE TABLE practice_fraud_alerts (
    transaction_id    text NOT NULL REFERENCES practice_fraud_txn(transaction_id),
    rule_code         text NOT NULL,
    first_detected_at timestamptz NOT NULL,
    last_detected_at  timestamptz NOT NULL,
    evidence          jsonb NOT NULL,
    PRIMARY KEY (transaction_id, rule_code)
);

-- ---------------------------------------------------------------------------
-- Q1. Build the eligible transaction stream.
-- Problem: Return current-day approved transactions with card and merchant
-- context. Exclude declined/reversed activity before downstream analytics.
-- ---------------------------------------------------------------------------

SELECT
    t.transaction_id,
    t.card_id,
    t.event_ts,
    t.amount,
    m.category,
    m.country_code AS merchant_country,
    c.home_country,
    t.channel
FROM practice_fraud_txn AS t
JOIN practice_fraud_card AS c
  ON c.card_id = t.card_id
JOIN practice_fraud_merchant AS m
  ON m.merchant_id = t.merchant_id
WHERE t.status = 'APPROVED'
  AND t.event_ts >= TIMESTAMPTZ '2026-11-02 00:00:00+00'
  AND t.event_ts <  TIMESTAMPTZ '2026-11-03 00:00:00+00'
ORDER BY t.event_ts, t.transaction_id;

-- Explanation: Apply selective status and timestamp predicates before window
-- calculations. The half-open UTC range is safe for timestamp precision and
-- can use a B-tree or time partition pruning. Do not cast event_ts to DATE in
-- the WHERE clause.

-- ---------------------------------------------------------------------------
-- Q2. Detect card velocity in a rolling 10-minute event-time window.
-- Problem: For each approved transaction, count and sum the same card's
-- approved transactions in the preceding 10 minutes, including the current
-- event. Flag rows where count >= 3.
-- ---------------------------------------------------------------------------

WITH approved AS (
    SELECT transaction_id, card_id, event_ts, amount
    FROM practice_fraud_txn
    WHERE status = 'APPROVED'
      AND event_ts >= TIMESTAMPTZ '2026-11-02 00:00:00+00'
      AND event_ts <  TIMESTAMPTZ '2026-11-03 00:00:00+00'
),
velocity AS (
    SELECT
        transaction_id,
        card_id,
        event_ts,
        amount,
        COUNT(*) OVER (
            PARTITION BY card_id
            ORDER BY event_ts
            RANGE BETWEEN INTERVAL '10 minutes' PRECEDING AND CURRENT ROW
        ) AS txn_count_10m,
        SUM(amount) OVER (
            PARTITION BY card_id
            ORDER BY event_ts
            RANGE BETWEEN INTERVAL '10 minutes' PRECEDING AND CURRENT ROW
        ) AS amount_10m
    FROM approved
)
SELECT *
FROM velocity
WHERE txn_count_10m >= 3
ORDER BY card_id, event_ts;

-- Expected spot check: T-003 has 3 transactions / USD 577 in its window;
-- T-004 has 4 transactions / USD 1,087. RANGE is time-based and includes
-- events exactly 10 minutes before the current event. ROWS would mean a fixed
-- number of preceding records, not a fixed duration.

-- ---------------------------------------------------------------------------
-- Q3. Compare current purchases with a 30-day merchant-category P95.
-- Problem: Identify approved current-day transactions whose amount exceeds
-- the category's historical 95th percentile.
-- ---------------------------------------------------------------------------

WITH category_baseline AS (
    SELECT
        m.category,
        percentile_cont(0.95) WITHIN GROUP (ORDER BY t.amount::double precision)::numeric AS p95_amount
    FROM practice_fraud_txn AS t
    JOIN practice_fraud_merchant AS m
      ON m.merchant_id = t.merchant_id
    WHERE t.status = 'APPROVED'
      AND t.event_ts >= TIMESTAMPTZ '2026-10-03 00:00:00+00'
      AND t.event_ts <  TIMESTAMPTZ '2026-11-02 00:00:00+00'
    GROUP BY m.category
)
SELECT
    t.transaction_id,
    t.amount,
    m.category,
    b.p95_amount,
    ROUND(t.amount - b.p95_amount, 2) AS amount_above_p95
FROM practice_fraud_txn AS t
JOIN practice_fraud_merchant AS m
  ON m.merchant_id = t.merchant_id
JOIN category_baseline AS b
  ON b.category = m.category
WHERE t.status = 'APPROVED'
  AND t.event_ts >= TIMESTAMPTZ '2026-11-02 00:00:00+00'
  AND t.event_ts <  TIMESTAMPTZ '2026-11-03 00:00:00+00'
  AND t.amount > b.p95_amount
ORDER BY amount_above_p95 DESC;

-- Expected spot check: T-003/T-004 (ELECTRONICS) and T-010/T-011/T-016/T-017
-- (TRAVEL) exceed their sample category baselines. In production, calculate
-- baselines from a maintained aggregate table rather than rescanning all raw
-- history for every micro-batch.

-- ---------------------------------------------------------------------------
-- Q4. Find cross-border approvals and inspect the prior approved country.
-- Problem: Flag transactions where merchant country differs from card home
-- country. Use LAG to retain sequence context for analyst review.
-- ---------------------------------------------------------------------------

WITH sequenced AS (
    SELECT
        t.transaction_id,
        t.card_id,
        t.event_ts,
        c.home_country,
        m.country_code AS merchant_country,
        LAG(m.country_code) OVER (
            PARTITION BY t.card_id
            ORDER BY t.event_ts, t.transaction_id
        ) AS previous_approved_country
    FROM practice_fraud_txn AS t
    JOIN practice_fraud_card AS c
      ON c.card_id = t.card_id
    JOIN practice_fraud_merchant AS m
      ON m.merchant_id = t.merchant_id
    WHERE t.status = 'APPROVED'
      AND t.event_ts >= TIMESTAMPTZ '2026-11-02 00:00:00+00'
      AND t.event_ts <  TIMESTAMPTZ '2026-11-03 00:00:00+00'
)
SELECT
    transaction_id,
    card_id,
    home_country,
    merchant_country,
    previous_approved_country,
    event_ts
FROM sequenced
WHERE merchant_country <> home_country
ORDER BY card_id, event_ts;

-- Expected spot check: T-010, T-011, T-016 and T-017 are cross-border.
-- A country mismatch is a review signal, not proof of fraud. A production
-- rule should incorporate travel notices, tokenization, IP/device signals,
-- and trusted cardholder context.

-- ---------------------------------------------------------------------------
-- Q5. Detect repeated same-amount authorizations within two minutes.
-- Problem: Identify a later approved transaction for the same card, merchant,
-- and amount when the previous matching authorization occurred <= 2 minutes
-- earlier.
-- ---------------------------------------------------------------------------

WITH attempts AS (
    SELECT
        transaction_id,
        card_id,
        merchant_id,
        amount,
        event_ts,
        LAG(event_ts) OVER (
            PARTITION BY card_id, merchant_id, amount
            ORDER BY event_ts, transaction_id
        ) AS previous_matching_ts
    FROM practice_fraud_txn
    WHERE status = 'APPROVED'
      AND event_ts >= TIMESTAMPTZ '2026-11-02 00:00:00+00'
      AND event_ts <  TIMESTAMPTZ '2026-11-03 00:00:00+00'
)
SELECT
    transaction_id,
    card_id,
    merchant_id,
    amount,
    previous_matching_ts,
    event_ts - previous_matching_ts AS elapsed
FROM attempts
WHERE previous_matching_ts IS NOT NULL
  AND event_ts <= previous_matching_ts + INTERVAL '2 minutes'
ORDER BY card_id, event_ts;

-- Expected spot check: T-015 follows T-014 for the same card, merchant, and
-- USD 49 amount one minute later. The deterministic transaction_id tie-breaker
-- makes ordering stable when event timestamps match.

-- ---------------------------------------------------------------------------
-- Q6. Combine rule hits into an explainable transaction risk score.
-- Problem: Give each independent rule hit 25 points (cap at 100), retain the
-- rule list, and classify the transaction. This is a teaching score, not a
-- calibrated production probability.
-- ---------------------------------------------------------------------------

WITH approved_current AS (
    SELECT
        t.transaction_id,
        t.card_id,
        t.merchant_id,
        t.event_ts,
        t.amount,
        m.category,
        m.country_code AS merchant_country,
        c.home_country
    FROM practice_fraud_txn AS t
    JOIN practice_fraud_card AS c
      ON c.card_id = t.card_id
    JOIN practice_fraud_merchant AS m
      ON m.merchant_id = t.merchant_id
    WHERE t.status = 'APPROVED'
      AND t.event_ts >= TIMESTAMPTZ '2026-11-02 00:00:00+00'
      AND t.event_ts <  TIMESTAMPTZ '2026-11-03 00:00:00+00'
),
velocity AS (
    SELECT
        transaction_id,
        COUNT(*) OVER (
            PARTITION BY card_id
            ORDER BY event_ts
            RANGE BETWEEN INTERVAL '10 minutes' PRECEDING AND CURRENT ROW
        ) AS txn_count_10m,
        SUM(amount) OVER (
            PARTITION BY card_id
            ORDER BY event_ts
            RANGE BETWEEN INTERVAL '10 minutes' PRECEDING AND CURRENT ROW
        ) AS amount_10m
    FROM approved_current
),
baseline AS (
    SELECT
        m.category,
        percentile_cont(0.95) WITHIN GROUP (ORDER BY t.amount::double precision)::numeric AS p95_amount
    FROM practice_fraud_txn AS t
    JOIN practice_fraud_merchant AS m
      ON m.merchant_id = t.merchant_id
    WHERE t.status = 'APPROVED'
      AND t.event_ts >= TIMESTAMPTZ '2026-10-03 00:00:00+00'
      AND t.event_ts <  TIMESTAMPTZ '2026-11-02 00:00:00+00'
    GROUP BY m.category
),
repeat_attempts AS (
    SELECT
        transaction_id,
        LAG(event_ts) OVER (
            PARTITION BY card_id, merchant_id, amount
            ORDER BY event_ts, transaction_id
        ) AS previous_matching_ts
    FROM approved_current
),
rule_hits AS (
    SELECT
        v.transaction_id,
        'CARD_VELOCITY_10M'::text AS rule_code
    FROM velocity AS v
    WHERE v.txn_count_10m >= 3

    UNION ALL

    SELECT
        a.transaction_id,
        'CATEGORY_AMOUNT_P95'
    FROM approved_current AS a
    JOIN baseline AS b
      ON b.category = a.category
    WHERE a.amount > b.p95_amount

    UNION ALL

    SELECT
        transaction_id,
        'CROSS_BORDER'
    FROM approved_current
    WHERE merchant_country <> home_country

    UNION ALL

    SELECT
        r.transaction_id,
        'REPEATED_AUTH_2M'
    FROM repeat_attempts AS r
    JOIN approved_current AS a
      ON a.transaction_id = r.transaction_id
    WHERE r.previous_matching_ts IS NOT NULL
      AND a.event_ts <= r.previous_matching_ts + INTERVAL '2 minutes'
)
SELECT
    transaction_id,
    COUNT(*) AS rule_count,
    LEAST(100, COUNT(*) * 25) AS risk_score,
    CASE
        WHEN COUNT(*) >= 3 THEN 'HIGH'
        WHEN COUNT(*) = 2 THEN 'MEDIUM'
        ELSE 'REVIEW'
    END AS risk_band,
    array_agg(rule_code ORDER BY rule_code) AS triggered_rules
FROM rule_hits
GROUP BY transaction_id
ORDER BY risk_score DESC, transaction_id;

-- Explanation: Each rule emits one row per transaction. UNION ALL preserves
-- independent evidence; GROUP BY then calculates the score. Do not use
-- COUNT(DISTINCT rule_code) unless duplicate rule emissions are possible and
-- should be collapsed. Production weights should be calibrated and versioned.

-- ---------------------------------------------------------------------------
-- Q7. Produce an hourly operational control report by merchant category.
-- Problem: Compare approved, declined, and reversed counts and approved value
-- without multiplying rows through separate one-to-many joins.
-- ---------------------------------------------------------------------------

SELECT
    date_trunc('hour', t.event_ts) AS event_hour_utc,
    m.category,
    COUNT(*) FILTER (WHERE t.status = 'APPROVED') AS approved_count,
    COUNT(*) FILTER (WHERE t.status = 'DECLINED') AS declined_count,
    COUNT(*) FILTER (WHERE t.status = 'REVERSED') AS reversed_count,
    COALESCE(
        SUM(t.amount) FILTER (WHERE t.status = 'APPROVED'),
        0
    ) AS approved_amount
FROM practice_fraud_txn AS t
JOIN practice_fraud_merchant AS m
  ON m.merchant_id = t.merchant_id
WHERE t.event_ts >= TIMESTAMPTZ '2026-11-02 00:00:00+00'
  AND t.event_ts <  TIMESTAMPTZ '2026-11-03 00:00:00+00'
GROUP BY date_trunc('hour', t.event_ts), m.category
ORDER BY event_hour_utc, m.category;

-- Expected control check: across all categories, the 09:00 UTC hour contains
-- 10 approved, 1 declined, and 1 reversed transaction. The 10:00 UTC hour
-- contains 5 approved transactions.

-- ---------------------------------------------------------------------------
-- Q8. Persist rule hits idempotently and reconcile the alert sink.
-- Problem: Store one alert per transaction/rule pair. Re-running the batch
-- must update the existing observation, not create duplicate alerts.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE VIEW practice_fraud_rule_hits AS
WITH approved_current AS (
    SELECT
        t.transaction_id,
        t.card_id,
        t.merchant_id,
        t.event_ts,
        t.amount,
        m.category,
        m.country_code AS merchant_country,
        c.home_country
    FROM practice_fraud_txn AS t
    JOIN practice_fraud_card AS c
      ON c.card_id = t.card_id
    JOIN practice_fraud_merchant AS m
      ON m.merchant_id = t.merchant_id
    WHERE t.status = 'APPROVED'
      AND t.event_ts >= TIMESTAMPTZ '2026-11-02 00:00:00+00'
      AND t.event_ts <  TIMESTAMPTZ '2026-11-03 00:00:00+00'
),
velocity AS (
    SELECT
        transaction_id,
        COUNT(*) OVER (
            PARTITION BY card_id
            ORDER BY event_ts
            RANGE BETWEEN INTERVAL '10 minutes' PRECEDING AND CURRENT ROW
        ) AS txn_count_10m,
        SUM(amount) OVER (
            PARTITION BY card_id
            ORDER BY event_ts
            RANGE BETWEEN INTERVAL '10 minutes' PRECEDING AND CURRENT ROW
        ) AS amount_10m
    FROM approved_current
),
baseline AS (
    SELECT
        m.category,
        percentile_cont(0.95) WITHIN GROUP (ORDER BY t.amount::double precision)::numeric AS p95_amount
    FROM practice_fraud_txn AS t
    JOIN practice_fraud_merchant AS m
      ON m.merchant_id = t.merchant_id
    WHERE t.status = 'APPROVED'
      AND t.event_ts >= TIMESTAMPTZ '2026-10-03 00:00:00+00'
      AND t.event_ts <  TIMESTAMPTZ '2026-11-02 00:00:00+00'
    GROUP BY m.category
),
repeat_attempts AS (
    SELECT
        transaction_id,
        card_id,
        merchant_id,
        amount,
        event_ts,
        LAG(event_ts) OVER (
            PARTITION BY card_id, merchant_id, amount
            ORDER BY event_ts, transaction_id
        ) AS previous_matching_ts
    FROM approved_current
)
SELECT
    v.transaction_id,
    'CARD_VELOCITY_10M'::text AS rule_code,
    jsonb_build_object(
        'transaction_count_10m', v.txn_count_10m,
        'amount_10m', v.amount_10m
    ) AS evidence
FROM velocity AS v
WHERE v.txn_count_10m >= 3

UNION ALL

SELECT
    a.transaction_id,
    'CATEGORY_AMOUNT_P95',
    jsonb_build_object(
        'amount', a.amount,
        'category', a.category,
        'category_p95', b.p95_amount
    )
FROM approved_current AS a
JOIN baseline AS b
  ON b.category = a.category
WHERE a.amount > b.p95_amount

UNION ALL

SELECT
    a.transaction_id,
    'CROSS_BORDER',
    jsonb_build_object(
        'home_country', a.home_country,
        'merchant_country', a.merchant_country
    )
FROM approved_current AS a
WHERE a.merchant_country <> a.home_country

UNION ALL

SELECT
    r.transaction_id,
    'REPEATED_AUTH_2M',
    jsonb_build_object(
        'card_id', r.card_id,
        'merchant_id', r.merchant_id,
        'amount', r.amount,
        'previous_matching_ts', r.previous_matching_ts
    )
FROM repeat_attempts AS r
WHERE r.previous_matching_ts IS NOT NULL
  AND r.event_ts <= r.previous_matching_ts + INTERVAL '2 minutes';

INSERT INTO practice_fraud_alerts (
    transaction_id,
    rule_code,
    first_detected_at,
    last_detected_at,
    evidence
)
SELECT
    transaction_id,
    rule_code,
    clock_timestamp(),
    clock_timestamp(),
    evidence
FROM practice_fraud_rule_hits
ON CONFLICT (transaction_id, rule_code)
DO UPDATE SET
    last_detected_at = EXCLUDED.last_detected_at,
    evidence = EXCLUDED.evidence;

-- Expected spot check: the sample produces 13 transaction/rule alert pairs.
-- Run the INSERT block again: the table should still contain 13 rows because
-- (transaction_id, rule_code) is the idempotency key.

SELECT
    COUNT(*) AS persisted_alert_rows,
    COUNT(DISTINCT transaction_id) AS alerted_transactions,
    COUNT(*) FILTER (WHERE rule_code = 'CARD_VELOCITY_10M') AS velocity_alerts,
    COUNT(*) FILTER (WHERE rule_code = 'CATEGORY_AMOUNT_P95') AS amount_alerts,
    COUNT(*) FILTER (WHERE rule_code = 'CROSS_BORDER') AS cross_border_alerts,
    COUNT(*) FILTER (WHERE rule_code = 'REPEATED_AUTH_2M') AS repeated_auth_alerts
FROM practice_fraud_alerts;

-- Reconciliation: every current rule hit must have exactly one persisted row.
SELECT h.transaction_id, h.rule_code
FROM practice_fraud_rule_hits AS h
LEFT JOIN practice_fraud_alerts AS a
  ON a.transaction_id = h.transaction_id
 AND a.rule_code = h.rule_code
WHERE a.transaction_id IS NULL;

-- The reconciliation query should return zero rows.

-- ---------------------------------------------------------------------------
-- Performance notes and interview follow-ups
-- ---------------------------------------------------------------------------

/*
Candidate indexes (benchmark on representative volumes; do not assume every
index helps a small or write-heavy table):

1. CREATE INDEX ON practice_fraud_txn (card_id, event_ts)
   WHERE status = 'APPROVED';
   Supports card-scoped time windows and approved-event access.

2. CREATE INDEX ON practice_fraud_txn (event_ts)
   INCLUDE (status, card_id, merchant_id, amount);
   May help time-range reporting when the selected range is selective.

3. CREATE INDEX ON practice_fraud_txn (merchant_id, event_ts)
   INCLUDE (amount, status);
   May help merchant/category baseline extraction.

4. For a large append-only fact table, evaluate RANGE partitioning by event_ts
   (for example, monthly partitions) and BRIN on event_ts when physical row
   order correlates with time.

Optimization choices:
- Filter to the required status and event-time range before windowing.
- Keep predicates on the raw timestamp column to preserve index/partition use.
- Use RANGE for elapsed-time windows; use ROWS only for record-count windows.
- Aggregate category baselines separately, then join the small result.
- Use one grouped conditional-aggregation pass for hourly status metrics.
- Persist alerts with a natural idempotency key and ON CONFLICT.
- Inspect EXPLAIN (ANALYZE, BUFFERS); compare estimated vs actual rows, sort
  spills, heap fetches, and partition pruning.
- At scale, maintain rolling category quantiles in scheduled aggregate tables
  or use an approximate quantile strategy where the business accepts it.
- Late-arriving events require a bounded reprocessing horizon or alert
  correction policy; event-time watermarks alone do not retract persisted
  alerts automatically.

Interview follow-ups:
1. Why is RANGE INTERVAL '10 minutes' different from ROWS BETWEEN 10 PRECEDING?
2. How would you handle two transactions with the same event_ts?
3. How would you prevent a late event from changing an already-issued alert?
4. When would you use a materialized baseline table instead of percentile_cont?
5. How would you avoid alert duplication across parallel batch workers?
6. What changes if amounts arrive in multiple currencies?
7. How would you tune the card_id/event_ts index on a partitioned transaction
   table?
8. Which signals would you add before treating a rule hit as confirmed fraud?
*/
