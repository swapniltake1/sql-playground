-- Daily SQL Interview Practice — 2026-11-26
-- Topic: Subscription coverage gaps, overlaps, and point-in-time status
-- Dialect: PostgreSQL 14+
--
-- Problem
-- SaaS subscription records contain effective intervals. Find invalid/overlapping
-- periods, gaps between consecutive periods, and the subscription active on an
-- as-of date. Intervals use [start_date, end_date): end_date is exclusive; NULL
-- end_date means open-ended.
--
-- Setup: intentionally includes a gap, an overlap, an open interval, and adjacent
-- intervals. Run this file in a fresh PostgreSQL schema.

DROP TABLE IF EXISTS subscription_periods;
CREATE TABLE subscription_periods (
    period_id       BIGINT PRIMARY KEY,
    customer_id     BIGINT NOT NULL,
    plan_code       TEXT NOT NULL,
    start_date      DATE NOT NULL,
    end_date        DATE,
    monthly_price   NUMERIC(10,2) NOT NULL,
    CHECK (end_date IS NULL OR end_date > start_date)
);

INSERT INTO subscription_periods VALUES
(1, 101, 'BASIC',   DATE '2026-01-01', DATE '2026-03-01',  19.00),
(2, 101, 'PRO',     DATE '2026-03-01', DATE '2026-05-01',  49.00), -- adjacent
(3, 101, 'PRO',     DATE '2026-05-10', DATE '2026-07-01',  49.00), -- 9-day gap
(4, 101, 'TEAM',    DATE '2026-06-20', DATE '2026-08-01',  99.00), -- overlap
(5, 102, 'BASIC',   DATE '2026-02-01', NULL,               19.00), -- open-ended
(6, 103, 'STARTER', DATE '2026-01-01', DATE '2026-02-01',   9.00),
(7, 103, 'PRO',     DATE '2026-02-01', DATE '2026-04-01',  49.00); -- adjacent

-- Q1. Compare each period with the immediately preceding period per customer.
-- LAG avoids a self-join and makes the ordering requirement explicit.
WITH ordered AS (
    SELECT p.*,
           LAG(end_date) OVER (
               PARTITION BY customer_id
               ORDER BY start_date, period_id
           ) AS previous_end_date
    FROM subscription_periods p
)
SELECT customer_id, period_id, previous_end_date, start_date,
       CASE
         WHEN previous_end_date IS NULL THEN 'FIRST_PERIOD'
         WHEN previous_end_date = start_date THEN 'CONTIGUOUS'
         WHEN previous_end_date < start_date THEN 'GAP'
         ELSE 'OVERLAP'
       END AS relationship
FROM ordered
ORDER BY customer_id, start_date, period_id;

-- Q2. Find all overlaps, including nested intervals. Comparing only LAG(end_date)
-- can miss an earlier long interval; use the maximum prior end boundary instead.
WITH checked AS (
    SELECT p.*,
           MAX(COALESCE(end_date, DATE '9999-12-31')) OVER (
               PARTITION BY customer_id
               ORDER BY start_date, period_id
               ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
           ) AS max_prior_end
    FROM subscription_periods p
)
SELECT customer_id, period_id, start_date, end_date, max_prior_end
FROM checked
WHERE max_prior_end > start_date
ORDER BY customer_id, start_date, period_id;

-- Q3. Report uncovered date ranges between adjacent periods.
WITH ordered AS (
    SELECT customer_id, period_id, start_date, end_date,
           LAG(end_date) OVER (
               PARTITION BY customer_id ORDER BY start_date, period_id
           ) AS previous_end
    FROM subscription_periods
)
SELECT customer_id, previous_end AS gap_start, start_date AS gap_end,
       start_date - previous_end AS gap_days
FROM ordered
WHERE previous_end IS NOT NULL
  AND previous_end < start_date
ORDER BY customer_id, gap_start;

-- Q4. Point-in-time plan lookup. The half-open predicate prevents a boundary date
-- from matching both the expiring and newly-started subscription.
WITH params AS (SELECT DATE '2026-06-25' AS as_of_date)
SELECT p.customer_id, p.plan_code, p.monthly_price, p.start_date, p.end_date
FROM subscription_periods p
CROSS JOIN params x
WHERE p.start_date <= x.as_of_date
  AND (p.end_date IS NULL OR x.as_of_date < p.end_date)
ORDER BY p.customer_id, p.start_date DESC;

-- Q5. Validate that each customer has at most one active subscription on a date.
-- This catches overlaps that make a point-in-time lookup ambiguous.
WITH params AS (SELECT DATE '2026-06-25' AS as_of_date),
active AS (
    SELECT p.customer_id, COUNT(*) AS active_periods
    FROM subscription_periods p
    CROSS JOIN params x
    WHERE p.start_date <= x.as_of_date
      AND (p.end_date IS NULL OR x.as_of_date < p.end_date)
    GROUP BY p.customer_id
)
SELECT customer_id, active_periods
FROM active
WHERE active_periods > 1;

-- Q6. Optimized integrity scan: keep the window input narrow, then join details
-- only for exceptions. This reduces sort width for wide production dimensions.
WITH boundaries AS (
    SELECT customer_id, period_id, start_date,
           MAX(COALESCE(end_date, DATE '9999-12-31')) OVER (
               PARTITION BY customer_id
               ORDER BY start_date, period_id
               ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
           ) AS max_prior_end
    FROM subscription_periods
),
exceptions AS (
    SELECT customer_id, period_id, max_prior_end
    FROM boundaries
    WHERE max_prior_end > start_date
)
SELECT e.customer_id, p.period_id, p.plan_code, p.start_date, p.end_date,
       e.max_prior_end
FROM exceptions e
JOIN subscription_periods p USING (customer_id, period_id)
ORDER BY e.customer_id, p.start_date;

-- Suggested index for customer-scoped temporal scans; benchmark on production data.
CREATE INDEX IF NOT EXISTS ix_subscription_customer_start
    ON subscription_periods (customer_id, start_date, period_id)
    INCLUDE (end_date, plan_code, monthly_price);

-- Expected spot checks:
-- * Q1: customer 101 has one CONTIGUOUS boundary, then GAP, then OVERLAP.
-- * Q2: period 4 is an overlap (the preceding PRO period ends 2026-07-01).
-- * Q3: customer 101 has a gap [2026-05-01, 2026-05-10), 9 days.
-- * Q4/Q5: customer 101 has two active rows on 2026-06-25, exposing the overlap.
-- * customer 102's open-ended subscription remains active on 2026-06-25.
--
-- Optimization notes:
-- 1. Use [start,end) predicates consistently; BETWEEN is wrong for adjacent ranges.
-- 2. LAG is enough for immediate-neighbor gap checks, but MAX of all prior ends
--    is required to reliably detect nested/long-running overlaps.
-- 3. Window functions require ordering within customer partitions; the composite
--    index can help access/order but PostgreSQL may still choose a sort.
-- 4. Keep window projections narrow; fetch descriptive columns after filtering.
-- 5. For large histories, consider range types and GiST exclusion constraints to
--    prevent overlaps at write time rather than merely detecting them afterward.
--
-- Interview follow-ups:
-- 1. Why can LAG(end_date) miss a nested interval overlap?
-- 2. How would you enforce no-overlap at insert/update time in PostgreSQL?
-- 3. How do NULL end dates change the comparison strategy?
-- 4. Why are half-open intervals safer than inclusive BETWEEN boundaries?
-- 5. How would you handle backdated corrections and bitemporal history?
-- 6. What changes if intervals are timestamp-with-time-zone rather than DATE?
-- 7. How would you scale the check for millions of customers and long histories?
