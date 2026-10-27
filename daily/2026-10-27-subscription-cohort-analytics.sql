/*
===============================================================================
SQL PRACTICE — SUBSCRIPTION COHORT & REVENUE ANALYTICS
Date: 2026-10-27
Dialect: PostgreSQL 14+
Level: Intermediate / Advanced

TOPICS
- Month-end active-subscriber snapshots
- Monthly recurring revenue (MRR)
- First-time subscribers vs reactivation
- Churn counts and churn rate
- Cohort retention
- Month-over-month MRR movement
- Plan-level revenue mix

HOW TO USE
1. Run the setup section first.
2. Read each numbered problem and attempt your own query.
3. Review the optimized solution in the commented answer block.
4. Use EXPLAIN (ANALYZE, BUFFERS) with larger data to compare query plans.

DATA MODEL ASSUMPTIONS
- end_date is exclusive: a subscription is active on date D when
  start_date <= D AND (end_date IS NULL OR end_date > D).
- The sample covers January–June 2026.
- Customers have no overlapping paid subscription periods in this sample.
- MRR is a month-end snapshot, not recognized accounting revenue.
===============================================================================
*/

-- ============================================================================
-- SETUP: independent sample schema and realistic test data
-- ============================================================================

DROP TABLE IF EXISTS sa_subscriptions;
DROP TABLE IF EXISTS sa_customers;

CREATE TABLE sa_customers (
    customer_id       INTEGER PRIMARY KEY,
    customer_name     VARCHAR(80) NOT NULL,
    signup_date       DATE NOT NULL,
    acquisition_channel VARCHAR(20) NOT NULL
);

CREATE TABLE sa_subscriptions (
    subscription_id   INTEGER PRIMARY KEY,
    customer_id       INTEGER NOT NULL REFERENCES sa_customers(customer_id),
    plan_name         VARCHAR(20) NOT NULL,
    monthly_price     NUMERIC(10, 2) NOT NULL CHECK (monthly_price >= 0),
    start_date        DATE NOT NULL,
    end_date          DATE,
    CHECK (end_date IS NULL OR end_date > start_date)
);

INSERT INTO sa_customers
    (customer_id, customer_name, signup_date, acquisition_channel)
VALUES
    (1,  'Aarav Shah',    DATE '2026-01-05', 'Organic'),
    (2,  'Diya Patel',    DATE '2026-01-15', 'Referral'),
    (3,  'Kabir Joshi',   DATE '2026-02-02', 'Paid'),
    (4,  'Anaya Rao',     DATE '2026-02-18', 'Organic'),
    (5,  'Ishaan Mehta',  DATE '2026-03-10', 'Referral'),
    (6,  'Sara Khan',     DATE '2026-03-20', 'Paid'),
    (7,  'Vivaan Nair',   DATE '2026-04-08', 'Organic'),
    (8,  'Myra Desai',    DATE '2026-04-18', 'Paid'),
    (9,  'Reyansh Kulkarni', DATE '2026-05-03', 'Referral'),
    (10, 'Aditi Singh',   DATE '2026-06-12', 'Organic');

INSERT INTO sa_subscriptions
    (subscription_id, customer_id, plan_name, monthly_price, start_date, end_date)
VALUES
    (101, 1,  'Basic', 10.00, DATE '2026-01-05', NULL),
    (102, 2,  'Pro',   30.00, DATE '2026-01-15', DATE '2026-04-01'),
    (103, 3,  'Basic', 10.00, DATE '2026-02-02', NULL),
    (104, 4,  'Pro',   30.00, DATE '2026-02-18', DATE '2026-03-15'),
    (105, 5,  'Basic', 10.00, DATE '2026-03-10', NULL),
    (106, 6,  'Pro',   30.00, DATE '2026-03-20', DATE '2026-05-01'),
    (107, 7,  'Basic', 10.00, DATE '2026-04-08', NULL),
    (108, 8,  'Pro',   30.00, DATE '2026-04-18', DATE '2026-06-01'),
    -- Customer 2 returns after a one-month gap: this is a reactivation.
    (109, 2,  'Pro',   30.00, DATE '2026-05-10', NULL),
    (110, 9,  'Basic', 10.00, DATE '2026-05-03', NULL),
    (111, 10, 'Pro',   30.00, DATE '2026-06-12', NULL);

-- Optional indexes for larger datasets. On this tiny sample, a sequential scan
-- may be faster; confirm with EXPLAIN (ANALYZE, BUFFERS).
CREATE INDEX ix_sa_subscriptions_start_customer
    ON sa_subscriptions (start_date, customer_id);

CREATE INDEX ix_sa_subscriptions_end_customer
    ON sa_subscriptions (end_date, customer_id)
    WHERE end_date IS NOT NULL;

ANALYZE sa_customers;
ANALYZE sa_subscriptions;

-- Shared month calendar for all questions.
-- Use a half-open calendar range in production pipelines when filtering timestamps.
-- Here month_start is a DATE, and each snapshot is taken at calendar month-end.

-- ============================================================================
-- Q01. How many paid customers were active at the end of each month?
-- Optimized approach: generate the small month calendar once, then count
-- distinct customers active on the month-end snapshot.
-- ============================================================================

/*
WITH months AS (
    SELECT gs::date AS month_start
    FROM generate_series(
        DATE '2026-01-01', DATE '2026-06-01', INTERVAL '1 month'
    ) AS gs
),
active_customers AS (
    SELECT DISTINCT
        m.month_start,
        s.customer_id
    FROM months m
    JOIN sa_subscriptions s
      ON s.start_date <=
         (m.month_start + INTERVAL '1 month' - INTERVAL '1 day')::date
     AND (s.end_date IS NULL OR s.end_date >
         (m.month_start + INTERVAL '1 month' - INTERVAL '1 day')::date)
)
SELECT
    m.month_start,
    COUNT(a.customer_id) AS active_paid_customers
FROM months m
LEFT JOIN active_customers a USING (month_start)
GROUP BY m.month_start
ORDER BY m.month_start;
*/

-- ============================================================================
-- Q02. Calculate month-end MRR for January through June 2026.
-- MRR is the sum of monthly prices for subscriptions active at month-end.
-- ============================================================================

/*
WITH months AS (
    SELECT gs::date AS month_start
    FROM generate_series(
        DATE '2026-01-01', DATE '2026-06-01', INTERVAL '1 month'
    ) AS gs
),
month_end_mrr AS (
    SELECT
        m.month_start,
        COALESCE(SUM(s.monthly_price), 0)::numeric(12, 2) AS mrr
    FROM months m
    LEFT JOIN sa_subscriptions s
      ON s.start_date <=
         (m.month_start + INTERVAL '1 month' - INTERVAL '1 day')::date
     AND (s.end_date IS NULL OR s.end_date >
         (m.month_start + INTERVAL '1 month' - INTERVAL '1 day')::date)
    GROUP BY m.month_start
)
SELECT month_start, mrr
FROM month_end_mrr
ORDER BY month_start;
*/

-- ============================================================================
-- Q03. Count first-time paid subscribers by the month of their first subscription.
-- Do not count a returning customer's reactivation as a new customer.
-- ============================================================================

/*
WITH first_paid_subscription AS (
    SELECT customer_id, MIN(start_date) AS first_start_date
    FROM sa_subscriptions
    GROUP BY customer_id
)
SELECT
    DATE_TRUNC('month', first_start_date)::date AS acquisition_month,
    COUNT(*) AS first_time_paid_customers
FROM first_paid_subscription
GROUP BY DATE_TRUNC('month', first_start_date)::date
ORDER BY acquisition_month;
*/

-- ============================================================================
-- Q04. Count churned customers by month.
-- A customer churns in a month if they were active at the previous month-end
-- and are not active at the current month-end.
-- ============================================================================

/*
WITH months AS (
    SELECT gs::date AS month_start
    FROM generate_series(
        DATE '2026-01-01', DATE '2026-06-01', INTERVAL '1 month'
    ) AS gs
),
active_customers AS (
    SELECT DISTINCT m.month_start, s.customer_id
    FROM months m
    JOIN sa_subscriptions s
      ON s.start_date <=
         (m.month_start + INTERVAL '1 month' - INTERVAL '1 day')::date
     AND (s.end_date IS NULL OR s.end_date >
         (m.month_start + INTERVAL '1 month' - INTERVAL '1 day')::date)
)
SELECT
    next_month.month_start AS churn_month,
    COUNT(previous.customer_id) AS churned_customers
FROM months previous_month
JOIN months next_month
  ON next_month.month_start = (previous_month.month_start + INTERVAL '1 month')::date
LEFT JOIN active_customers previous
  ON previous.month_start = previous_month.month_start
LEFT JOIN active_customers current
  ON current.month_start = next_month.month_start
 AND current.customer_id = previous.customer_id
WHERE previous.customer_id IS NOT NULL
  AND current.customer_id IS NULL
GROUP BY next_month.month_start
ORDER BY churn_month;
*/

-- ============================================================================
-- Q05. Find reactivated customers by month.
-- A reactivated customer is active this month, inactive last month, and had
-- a paid subscription start before the current month.
-- ============================================================================

/*
WITH months AS (
    SELECT gs::date AS month_start
    FROM generate_series(
        DATE '2026-01-01', DATE '2026-06-01', INTERVAL '1 month'
    ) AS gs
),
active_customers AS (
    SELECT DISTINCT m.month_start, s.customer_id
    FROM months m
    JOIN sa_subscriptions s
      ON s.start_date <=
         (m.month_start + INTERVAL '1 month' - INTERVAL '1 day')::date
     AND (s.end_date IS NULL OR s.end_date >
         (m.month_start + INTERVAL '1 month' - INTERVAL '1 day')::date)
),
first_subscription AS (
    SELECT customer_id, MIN(start_date) AS first_start_date
    FROM sa_subscriptions
    GROUP BY customer_id
)
SELECT
    current.month_start AS reactivation_month,
    current.customer_id
FROM active_customers current
JOIN first_subscription f USING (customer_id)
LEFT JOIN active_customers previous
  ON previous.month_start = (current.month_start - INTERVAL '1 month')::date
 AND previous.customer_id = current.customer_id
WHERE previous.customer_id IS NULL
  AND f.first_start_date < current.month_start
ORDER BY reactivation_month, current.customer_id;
*/

-- ============================================================================
-- Q06. Build a cohort retention report by signup month and months since signup.
-- Retention = active customers in a cohort at month-end / original cohort size.
-- ============================================================================

/*
WITH months AS (
    SELECT gs::date AS month_start
    FROM generate_series(
        DATE '2026-01-01', DATE '2026-06-01', INTERVAL '1 month'
    ) AS gs
),
cohorts AS (
    SELECT
        DATE_TRUNC('month', signup_date)::date AS cohort_month,
        COUNT(*) AS cohort_size
    FROM sa_customers
    GROUP BY DATE_TRUNC('month', signup_date)::date
),
cohort_activity AS (
    SELECT
        DATE_TRUNC('month', c.signup_date)::date AS cohort_month,
        m.month_start,
        (
          (EXTRACT(YEAR FROM m.month_start) - EXTRACT(YEAR FROM c.signup_date)) * 12
          + EXTRACT(MONTH FROM m.month_start) - EXTRACT(MONTH FROM c.signup_date)
        )::integer AS months_since_signup,
        COUNT(DISTINCT c.customer_id) AS active_customers
    FROM months m
    JOIN sa_customers c
      ON DATE_TRUNC('month', c.signup_date)::date <= m.month_start
    JOIN sa_subscriptions s
      ON s.customer_id = c.customer_id
     AND s.start_date <=
         (m.month_start + INTERVAL '1 month' - INTERVAL '1 day')::date
     AND (s.end_date IS NULL OR s.end_date >
         (m.month_start + INTERVAL '1 month' - INTERVAL '1 day')::date)
    GROUP BY
        DATE_TRUNC('month', c.signup_date)::date,
        m.month_start,
        months_since_signup
)
SELECT
    a.cohort_month,
    a.months_since_signup,
    c.cohort_size,
    a.active_customers,
    ROUND(100.0 * a.active_customers / NULLIF(c.cohort_size, 0), 2)
        AS retention_pct
FROM cohort_activity a
JOIN cohorts c USING (cohort_month)
ORDER BY a.cohort_month, a.months_since_signup;
*/

-- ============================================================================
-- Q07. Show month-over-month MRR change and percentage growth.
-- LAG reads the previous row after monthly MRR has been aggregated.
-- ============================================================================

/*
WITH months AS (
    SELECT gs::date AS month_start
    FROM generate_series(
        DATE '2026-01-01', DATE '2026-06-01', INTERVAL '1 month'
    ) AS gs
),
monthly_mrr AS (
    SELECT
        m.month_start,
        COALESCE(SUM(s.monthly_price), 0)::numeric(12, 2) AS mrr
    FROM months m
    LEFT JOIN sa_subscriptions s
      ON s.start_date <=
         (m.month_start + INTERVAL '1 month' - INTERVAL '1 day')::date
     AND (s.end_date IS NULL OR s.end_date >
         (m.month_start + INTERVAL '1 month' - INTERVAL '1 day')::date)
    GROUP BY m.month_start
),
with_previous AS (
    SELECT
        month_start,
        mrr,
        LAG(mrr) OVER (ORDER BY month_start) AS previous_mrr
    FROM monthly_mrr
)
SELECT
    month_start,
    mrr,
    previous_mrr,
    mrr - previous_mrr AS mrr_change,
    ROUND(
        100.0 * (mrr - previous_mrr) / NULLIF(previous_mrr, 0),
        2
    ) AS mrr_growth_pct
FROM with_previous
ORDER BY month_start;
*/

-- ============================================================================
-- Q08. Compare active subscribers and MRR by plan at June 2026 month-end.
-- Group only after applying the month-end active-subscription condition.
-- ============================================================================

/*
WITH snapshot AS (
    SELECT DATE '2026-06-30' AS snapshot_date
)
SELECT
    s.plan_name,
    COUNT(DISTINCT s.customer_id) AS active_customers,
    SUM(s.monthly_price)::numeric(12, 2) AS plan_mrr,
    ROUND(
        100.0 * SUM(s.monthly_price)
        / NULLIF(SUM(SUM(s.monthly_price)) OVER (), 0),
        2
    ) AS mrr_share_pct
FROM sa_subscriptions s
CROSS JOIN snapshot d
WHERE s.start_date <= d.snapshot_date
  AND (s.end_date IS NULL OR s.end_date > d.snapshot_date)
GROUP BY s.plan_name
ORDER BY plan_mrr DESC, s.plan_name;
*/

-- ============================================================================
-- PERFORMANCE NOTES / INTERVIEW DISCUSSION
-- ============================================================================
-- 1. For production-sized tables, consider storing month-end snapshots rather
--    than recomputing every historical month for every dashboard request.
-- 2. Avoid DATE_TRUNC(start_date) in a selective WHERE clause when a direct
--    range predicate can be used; direct ranges are usually more index-friendly.
-- 3. The start_date index may help some access patterns, but the end_date NULL
--    condition can still limit index usefulness. Validate with real plans.
-- 4. Indexes are not automatically faster for small tables. Compare plans using:
--       EXPLAIN (ANALYZE, BUFFERS) <query>;
-- 5. Define churn, reactivation, cohort membership, and end-date semantics with
--    the business before productionizing metrics. Different definitions change
--    the numbers.
-- 6. MRR is not the same as billed revenue or recognized revenue; discounts,
--    taxes, proration, and plan changes need explicit business rules.
