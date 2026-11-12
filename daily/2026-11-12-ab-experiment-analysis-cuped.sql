-- Daily SQL Practice — 2026-11-12
-- Topic: A/B Experiment Analysis, Sample Ratio Mismatch, and CUPED
-- PostgreSQL 14+
--
-- Run in a disposable practice database. The setup is self-contained.
-- All monetary values are in one reporting currency for this experiment.
-- The intentionally skewed 16:4 assignment split is included so the SRM
-- diagnostic returns an alert; investigate SRM before interpreting outcomes.

DROP VIEW IF EXISTS canonical_exposures;
DROP VIEW IF EXISTS canonical_outcomes;
DROP TABLE IF EXISTS raw_outcomes;
DROP TABLE IF EXISTS raw_exposures;
DROP TABLE IF EXISTS user_preperiod_metrics;
DROP TABLE IF EXISTS experiment_assignments;
DROP TABLE IF EXISTS experiment_variants;

CREATE TABLE experiment_variants (
    experiment_id  text NOT NULL,
    variant        text NOT NULL,
    allocation_pct numeric(5,4) NOT NULL CHECK (allocation_pct > 0 AND allocation_pct <= 1),
    PRIMARY KEY (experiment_id, variant)
);

CREATE TABLE experiment_assignments (
    experiment_id text NOT NULL,
    user_id       text NOT NULL,
    variant       text NOT NULL,
    assigned_at   timestamptz NOT NULL,
    PRIMARY KEY (experiment_id, user_id),
    FOREIGN KEY (experiment_id, variant)
        REFERENCES experiment_variants (experiment_id, variant)
);

CREATE TABLE user_preperiod_metrics (
    experiment_id       text NOT NULL,
    user_id             text NOT NULL,
    pre_period_revenue  numeric(12,2) NOT NULL,
    pre_period_sessions integer NOT NULL CHECK (pre_period_sessions >= 0),
    measured_from       date NOT NULL,
    measured_to         date NOT NULL,
    PRIMARY KEY (experiment_id, user_id),
    FOREIGN KEY (experiment_id, user_id)
        REFERENCES experiment_assignments (experiment_id, user_id),
    CHECK (measured_from <= measured_to)
);

-- Raw event tables intentionally allow duplicate event_key values.
-- event_key is the producer's idempotency key; ingest_id breaks timestamp ties.
CREATE TABLE raw_exposures (
    ingest_id     bigint PRIMARY KEY,
    event_key     text NOT NULL,
    experiment_id text NOT NULL,
    user_id       text NOT NULL,
    variant       text NOT NULL,
    exposed_at    timestamptz NOT NULL,
    page_name     text NOT NULL,
    ingested_at   timestamptz NOT NULL,
    FOREIGN KEY (experiment_id, user_id)
        REFERENCES experiment_assignments (experiment_id, user_id)
);

CREATE TABLE raw_outcomes (
    ingest_id     bigint PRIMARY KEY,
    event_key     text NOT NULL,
    experiment_id text NOT NULL,
    user_id       text NOT NULL,
    event_type    text NOT NULL CHECK (
        event_type IN ('purchase', 'refund', 'checkout_error', 'checkout_attempt')
    ),
    event_value   numeric(12,2),
    latency_ms    integer CHECK (latency_ms IS NULL OR latency_ms >= 0),
    occurred_at   timestamptz NOT NULL,
    ingested_at   timestamptz NOT NULL,
    FOREIGN KEY (experiment_id, user_id)
        REFERENCES experiment_assignments (experiment_id, user_id),
    CHECK (
        (event_type IN ('purchase', 'refund') AND event_value IS NOT NULL)
        OR
        (event_type IN ('checkout_error', 'checkout_attempt') AND event_value IS NULL)
    )
);

INSERT INTO experiment_variants (experiment_id, variant, allocation_pct) VALUES
('checkout_v2', 'control',   0.5000),
('checkout_v2', 'treatment', 0.5000);

INSERT INTO experiment_assignments
    (experiment_id, user_id, variant, assigned_at)
VALUES
('checkout_v2','u01','control',  '2026-11-01 09:00:00+00'),
('checkout_v2','u02','control',  '2026-11-01 09:01:00+00'),
('checkout_v2','u03','control',  '2026-11-01 09:02:00+00'),
('checkout_v2','u04','control',  '2026-11-01 09:03:00+00'),
('checkout_v2','u05','control',  '2026-11-01 09:04:00+00'),
('checkout_v2','u06','control',  '2026-11-01 09:05:00+00'),
('checkout_v2','u07','control',  '2026-11-01 09:06:00+00'),
('checkout_v2','u08','control',  '2026-11-01 09:07:00+00'),
('checkout_v2','u09','control',  '2026-11-01 09:08:00+00'),
('checkout_v2','u10','control',  '2026-11-01 09:09:00+00'),
('checkout_v2','u11','control',  '2026-11-01 09:10:00+00'),
('checkout_v2','u12','control',  '2026-11-01 09:11:00+00'),
('checkout_v2','u13','control',  '2026-11-01 09:12:00+00'),
('checkout_v2','u14','control',  '2026-11-01 09:13:00+00'),
('checkout_v2','u15','control',  '2026-11-01 09:14:00+00'),
('checkout_v2','u16','control',  '2026-11-01 09:15:00+00'),
('checkout_v2','u17','treatment','2026-11-01 09:16:00+00'),
('checkout_v2','u18','treatment','2026-11-01 09:17:00+00'),
('checkout_v2','u19','treatment','2026-11-01 09:18:00+00'),
('checkout_v2','u20','treatment','2026-11-01 09:19:00+00');

INSERT INTO user_preperiod_metrics
    (experiment_id, user_id, pre_period_revenue, pre_period_sessions, measured_from, measured_to)
VALUES
('checkout_v2','u01',100.00,8, DATE '2026-10-18',DATE '2026-10-31'),
('checkout_v2','u02', 60.00,5, DATE '2026-10-18',DATE '2026-10-31'),
('checkout_v2','u03',  0.00,1, DATE '2026-10-18',DATE '2026-10-31'),
('checkout_v2','u04', 50.00,4, DATE '2026-10-18',DATE '2026-10-31'),
('checkout_v2','u05', 90.00,7, DATE '2026-10-18',DATE '2026-10-31'),
('checkout_v2','u06', 20.00,2, DATE '2026-10-18',DATE '2026-10-31'),
('checkout_v2','u07', 70.00,6, DATE '2026-10-18',DATE '2026-10-31'),
('checkout_v2','u08', 10.00,2, DATE '2026-10-18',DATE '2026-10-31'),
('checkout_v2','u09', 80.00,6, DATE '2026-10-18',DATE '2026-10-31'),
('checkout_v2','u10',  0.00,0, DATE '2026-10-18',DATE '2026-10-31'),
('checkout_v2','u11', 40.00,3, DATE '2026-10-18',DATE '2026-10-31'),
('checkout_v2','u12', 25.00,2, DATE '2026-10-18',DATE '2026-10-31'),
('checkout_v2','u13', 30.00,3, DATE '2026-10-18',DATE '2026-10-31'),
('checkout_v2','u14', 35.00,3, DATE '2026-10-18',DATE '2026-10-31'),
('checkout_v2','u15', 15.00,1, DATE '2026-10-18',DATE '2026-10-31'),
('checkout_v2','u16',  5.00,1, DATE '2026-10-18',DATE '2026-10-31'),
('checkout_v2','u17', 95.00,7, DATE '2026-10-18',DATE '2026-10-31'),
('checkout_v2','u18',100.00,8, DATE '2026-10-18',DATE '2026-10-31'),
('checkout_v2','u19', 20.00,2, DATE '2026-10-18',DATE '2026-10-31'),
('checkout_v2','u20', 75.00,6, DATE '2026-10-18',DATE '2026-10-31');

INSERT INTO raw_exposures
    (ingest_id,event_key,experiment_id,user_id,variant,exposed_at,page_name,ingested_at)
VALUES
(1,'ex-u01','checkout_v2','u01','control',  '2026-11-01 10:00+00','checkout_v1','2026-11-01 10:00:03+00'),
(2,'ex-u01','checkout_v2','u01','control',  '2026-11-01 10:00+00','checkout_v2','2026-11-01 10:05:00+00'),
(3,'ex-u02','checkout_v2','u02','control',  '2026-11-01 10:02+00','checkout_v2','2026-11-01 10:02:03+00'),
(4,'ex-u02-wrong','checkout_v2','u02','treatment','2026-11-01 10:03+00','checkout_v2','2026-11-01 10:03:03+00'),
(5,'ex-u03','checkout_v2','u03','control',  '2026-11-01 10:04+00','checkout_v2','2026-11-01 10:04:03+00'),
(6,'ex-u04','checkout_v2','u04','control',  '2026-11-01 10:06+00','checkout_v2','2026-11-01 10:06:03+00'),
(7,'ex-u05','checkout_v2','u05','treatment','2026-11-01 10:08+00','checkout_v2','2026-11-01 10:08:03+00'),
(8,'ex-u06','checkout_v2','u06','control',  '2026-11-01 10:10+00','checkout_v2','2026-11-01 10:10:03+00'),
(9,'ex-u07','checkout_v2','u07','control',  '2026-11-01 10:12+00','checkout_v2','2026-11-01 10:12:03+00'),
(10,'ex-u08','checkout_v2','u08','control', '2026-11-01 10:14+00','checkout_v2','2026-11-01 10:14:03+00'),
(11,'ex-u09','checkout_v2','u09','control', '2026-11-01 10:16+00','checkout_v2','2026-11-01 10:16:03+00'),
(12,'ex-u10','checkout_v2','u10','control', '2026-11-01 10:18+00','checkout_v2','2026-11-01 10:18:03+00'),
(13,'ex-u11','checkout_v2','u11','control', '2026-11-01 10:20+00','checkout_v2','2026-11-01 10:20:03+00'),
(14,'ex-u12','checkout_v2','u12','control', '2026-11-01 10:22+00','checkout_v2','2026-11-01 10:22:03+00'),
(15,'ex-u13','checkout_v2','u13','control', '2026-11-01 10:24+00','checkout_v2','2026-11-01 10:24:03+00'),
(16,'ex-u14','checkout_v2','u14','control', '2026-11-01 10:26+00','checkout_v2','2026-11-01 10:26:03+00'),
(17,'ex-u15','checkout_v2','u15','control', '2026-11-01 10:28+00','checkout_v2','2026-11-01 10:28:03+00'),
(18,'ex-u17','checkout_v2','u17','treatment','2026-11-01 10:32+00','checkout_v2','2026-11-01 10:32:03+00'),
(19,'ex-u18','checkout_v2','u18','treatment','2026-11-01 10:34+00','checkout_v2','2026-11-01 10:34:03+00'),
(20,'ex-u19','checkout_v2','u19','treatment','2026-11-01 10:36+00','checkout_v2','2026-11-01 10:36:03+00');
-- u16 and u20 intentionally have no exposure event.

INSERT INTO raw_outcomes
    (ingest_id,event_key,experiment_id,user_id,event_type,event_value,latency_ms,occurred_at,ingested_at)
VALUES
(1, 'out-u01-buy','checkout_v2','u01','purchase',115.00,NULL,'2026-11-02 11:00+00','2026-11-02 11:01+00'),
(2, 'out-u01-buy','checkout_v2','u01','purchase',120.00,NULL,'2026-11-02 11:00+00','2026-11-02 11:10+00'),
(3, 'out-u01-attempt','checkout_v2','u01','checkout_attempt',NULL,420,'2026-11-02 10:59+00','2026-11-02 11:00+00'),
(4, 'out-u02-buy','checkout_v2','u02','purchase',80.00,NULL,'2026-11-02 12:00+00','2026-11-02 12:01+00'),
(5, 'out-u02-refund','checkout_v2','u02','refund',-10.00,NULL,'2026-11-03 09:00+00','2026-11-03 09:01+00'),
(6, 'out-u03-error','checkout_v2','u03','checkout_error',NULL,NULL,'2026-11-02 13:00+00','2026-11-02 13:01+00'),
(7, 'out-u03-attempt','checkout_v2','u03','checkout_attempt',NULL,900,'2026-11-02 12:59+00','2026-11-02 13:00+00'),
(8, 'out-u04-buy','checkout_v2','u04','purchase',60.00,NULL,'2026-11-03 10:00+00','2026-11-03 10:01+00'),
(9, 'out-u04-attempt','checkout_v2','u04','checkout_attempt',NULL,390,'2026-11-03 09:59+00','2026-11-03 10:00+00'),
(10,'out-u05-buy','checkout_v2','u05','purchase',100.00,NULL,'2026-11-03 11:00+00','2026-11-03 11:01+00'),
(11,'out-u05-refund','checkout_v2','u05','refund',-20.00,NULL,'2026-11-04 09:00+00','2026-11-04 09:01+00'),
(12,'out-u05-attempt','checkout_v2','u05','checkout_attempt',NULL,750,'2026-11-03 10:59+00','2026-11-03 11:00+00'),
(13,'out-u06-attempt','checkout_v2','u06','checkout_attempt',NULL,500,'2026-11-03 12:00+00','2026-11-03 12:01+00'),
(14,'out-u07-buy','checkout_v2','u07','purchase',75.00,NULL,'2026-11-04 10:00+00','2026-11-04 10:01+00'),
(15,'out-u07-attempt','checkout_v2','u07','checkout_attempt',NULL,480,'2026-11-04 09:59+00','2026-11-04 10:00+00'),
(16,'out-u08-error','checkout_v2','u08','checkout_error',NULL,NULL,'2026-11-04 11:00+00','2026-11-04 11:01+00'),
(17,'out-u08-attempt','checkout_v2','u08','checkout_attempt',NULL,1200,'2026-11-04 10:59+00','2026-11-04 11:00+00'),
(18,'out-u09-buy','checkout_v2','u09','purchase',90.00,NULL,'2026-11-05 10:00+00','2026-11-05 10:01+00'),
(19,'out-u09-attempt','checkout_v2','u09','checkout_attempt',NULL,550,'2026-11-05 09:59+00','2026-11-05 10:00+00'),
(20,'out-u11-buy','checkout_v2','u11','purchase',50.00,NULL,'2026-11-05 11:00+00','2026-11-05 11:01+00'),
(21,'out-u13-attempt','checkout_v2','u13','checkout_attempt',NULL,620,'2026-11-05 12:00+00','2026-11-05 12:01+00'),
(22,'out-u14-buy','checkout_v2','u14','purchase',45.00,NULL,'2026-11-06 10:00+00','2026-11-06 10:01+00'),
(23,'out-u17-buy','checkout_v2','u17','purchase',110.00,NULL,'2026-11-02 11:30+00','2026-11-02 11:31+00'),
(24,'out-u17-attempt','checkout_v2','u17','checkout_attempt',NULL,400,'2026-11-02 11:29+00','2026-11-02 11:30+00'),
(25,'out-u18-buy','checkout_v2','u18','purchase',130.00,NULL,'2026-11-03 12:00+00','2026-11-03 12:01+00'),
(26,'out-u18-refund','checkout_v2','u18','refund',-15.00,NULL,'2026-11-04 09:30+00','2026-11-04 09:31+00'),
(27,'out-u18-attempt','checkout_v2','u18','checkout_attempt',NULL,650,'2026-11-03 11:59+00','2026-11-03 12:00+00'),
(28,'out-u19-error','checkout_v2','u19','checkout_error',NULL,NULL,'2026-11-04 13:00+00','2026-11-04 13:01+00'),
(29,'out-u19-attempt','checkout_v2','u19','checkout_attempt',NULL,980,'2026-11-04 12:59+00','2026-11-04 13:00+00'),
(30,'out-u20-buy','checkout_v2','u20','purchase',90.00,NULL,'2026-11-06 12:00+00','2026-11-06 12:01+00'),
(31,'out-u20-attempt','checkout_v2','u20','checkout_attempt',NULL,500,'2026-11-06 11:59+00','2026-11-06 12:00+00');

-- Candidate indexes for the canonicalization and analysis patterns below.
-- They are useful at scale; benchmark rather than assuming they help tiny tables.
CREATE INDEX raw_exposures_dedupe_idx
    ON raw_exposures (experiment_id, event_key, ingested_at DESC, ingest_id DESC);
CREATE INDEX raw_outcomes_dedupe_idx
    ON raw_outcomes (experiment_id, event_key, ingested_at DESC, ingest_id DESC);
CREATE INDEX raw_outcomes_user_time_idx
    ON raw_outcomes (experiment_id, user_id, occurred_at)
    INCLUDE (event_type, event_value, latency_ms);
CREATE INDEX assignments_experiment_variant_idx
    ON experiment_assignments (experiment_id, variant, user_id);

-- Q1. Canonicalize replayed exposure and outcome events. Also list event keys
--     delivered more than once so ingestion quality can be monitored.
-- Optimized solution:
CREATE OR REPLACE VIEW canonical_exposures AS
SELECT DISTINCT ON (experiment_id, event_key)
       ingest_id, event_key, experiment_id, user_id, variant,
       exposed_at, page_name, ingested_at
FROM raw_exposures
ORDER BY experiment_id, event_key, ingested_at DESC, ingest_id DESC;

CREATE OR REPLACE VIEW canonical_outcomes AS
SELECT DISTINCT ON (experiment_id, event_key)
       ingest_id, event_key, experiment_id, user_id, event_type,
       event_value, latency_ms, occurred_at, ingested_at
FROM raw_outcomes
ORDER BY experiment_id, event_key, ingested_at DESC, ingest_id DESC;

SELECT 'exposure' AS event_stream, experiment_id, event_key, COUNT(*) AS deliveries
FROM raw_exposures
GROUP BY experiment_id, event_key
HAVING COUNT(*) > 1
UNION ALL
SELECT 'outcome', experiment_id, event_key, COUNT(*)
FROM raw_outcomes
GROUP BY experiment_id, event_key
HAVING COUNT(*) > 1
ORDER BY event_stream, event_key;

-- Why this is optimized:
-- DISTINCT ON selects one deterministic winner per idempotency key. The matching
-- composite indexes support the required ordering and avoid a separate wide sort
-- when the planner can use an index scan. Keep the tie-breaker deterministic.

-- Q2. Measure assignment-to-exposure coverage by assigned variant. Include users
--     who were assigned but never emitted a canonical exposure event.
-- Optimized solution:
WITH exposure_counts AS (
    SELECT experiment_id, user_id, COUNT(*) AS canonical_exposure_events
    FROM canonical_exposures
    GROUP BY experiment_id, user_id
)
SELECT a.variant,
       COUNT(*) AS assigned_users,
       COUNT(*) FILTER (WHERE e.user_id IS NOT NULL) AS exposed_users,
       COUNT(*) FILTER (WHERE e.user_id IS NULL) AS missing_exposure_users,
       SUM(COALESCE(e.canonical_exposure_events, 0)) AS exposure_events
FROM experiment_assignments a
LEFT JOIN exposure_counts e
  ON e.experiment_id = a.experiment_id
 AND e.user_id = a.user_id
WHERE a.experiment_id = 'checkout_v2'
GROUP BY a.variant
ORDER BY a.variant;

-- Why this is optimized:
-- Aggregate the many exposure events to one row per user before joining to the
-- assignment table. This prevents join fanout and preserves the randomized-user
-- denominator. The LEFT JOIN intentionally retains missing exposures.

-- Q3. Run a sample-ratio-mismatch (SRM) chi-square check against configured
--     allocation. For this two-variant example, 3.841 is the 5% critical value
--     for one degree of freedom.
-- Optimized solution:
WITH observed AS (
    SELECT experiment_id, variant, COUNT(*)::numeric AS observed_users
    FROM experiment_assignments
    WHERE experiment_id = 'checkout_v2'
    GROUP BY experiment_id, variant
),
total AS (
    SELECT COUNT(*)::numeric AS total_users
    FROM experiment_assignments
    WHERE experiment_id = 'checkout_v2'
),
expected AS (
    SELECT v.variant,
           COALESCE(o.observed_users, 0) AS observed_users,
           t.total_users * v.allocation_pct AS expected_users
    FROM experiment_variants v
    CROSS JOIN total t
    LEFT JOIN observed o
      ON o.experiment_id = v.experiment_id
     AND o.variant = v.variant
    WHERE v.experiment_id = 'checkout_v2'
),
statistic AS (
    SELECT SUM(POWER(observed_users - expected_users, 2)
               / NULLIF(expected_users, 0)) AS chi_square
    FROM expected
)
SELECT e.variant, e.observed_users, e.expected_users,
       s.chi_square,
       CASE WHEN s.chi_square > 3.841 THEN 'SRM_ALERT'
            ELSE 'no_srm_signal_at_5pct' END AS srm_status
FROM expected e
CROSS JOIN statistic s
ORDER BY e.variant;

-- Expected spot check: 16 control and 4 treatment assignments versus 10/10
-- expected gives chi-square = 7.2, so this sample should raise SRM_ALERT.
-- Why this is optimized: count assignments once per variant and reuse the small
-- aggregate. Do not use exposure counts for SRM; randomization is assessed on
-- assigned units. For more than two arms, use the correct df = arms - 1 critical
-- value or a statistical library rather than hard-coding 3.841.

-- Q4. Calculate intention-to-treat conversion rate and net revenue per assigned
--     user. A user remains in their assigned arm even if exposure is missing.
-- Optimized solution:
WITH per_user AS (
    SELECT a.experiment_id, a.user_id, a.variant,
           COALESCE(BOOL_OR(o.event_type = 'purchase'), FALSE) AS converted,
           COALESCE(SUM(o.event_value)
               FILTER (WHERE o.event_type IN ('purchase', 'refund')), 0) AS net_revenue
    FROM experiment_assignments a
    LEFT JOIN canonical_outcomes o
      ON o.experiment_id = a.experiment_id
     AND o.user_id = a.user_id
    WHERE a.experiment_id = 'checkout_v2'
    GROUP BY a.experiment_id, a.user_id, a.variant
)
SELECT variant,
       COUNT(*) AS assigned_users,
       COUNT(*) FILTER (WHERE converted) AS converted_users,
       ROUND(COUNT(*) FILTER (WHERE converted)::numeric
             / NULLIF(COUNT(*), 0), 4) AS conversion_rate,
       ROUND(SUM(net_revenue) / NULLIF(COUNT(*), 0), 2) AS revenue_per_assigned_user
FROM per_user
GROUP BY variant
ORDER BY variant;

-- Why this is optimized:
-- Reduce outcomes to one row per randomized user before computing arm metrics.
-- The assignment table is the denominator for an intention-to-treat estimate;
-- filtering to exposed or converted users would introduce post-randomization bias.
-- Refunds are negative amounts and are netted into user-level revenue.

-- Q5. Show cumulative first-time converters by variant and their conversion rate
--     over the experiment days. Repeated purchases must not count as new converters.
-- Optimized solution:
WITH first_purchase AS (
    SELECT experiment_id, user_id, MIN(occurred_at::date) AS first_purchase_date
    FROM canonical_outcomes
    WHERE experiment_id = 'checkout_v2'
      AND event_type = 'purchase'
    GROUP BY experiment_id, user_id
),
daily_new_converters AS (
    SELECT a.variant, f.first_purchase_date, COUNT(*) AS new_converters
    FROM first_purchase f
    JOIN experiment_assignments a
      ON a.experiment_id = f.experiment_id
     AND a.user_id = f.user_id
    GROUP BY a.variant, f.first_purchase_date
),
cumulative AS (
    SELECT variant, first_purchase_date, new_converters,
           SUM(new_converters) OVER (
               PARTITION BY variant
               ORDER BY first_purchase_date
               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
           ) AS cumulative_converters
    FROM daily_new_converters
),
denominators AS (
    SELECT variant, COUNT(*) AS assigned_users
    FROM experiment_assignments
    WHERE experiment_id = 'checkout_v2'
    GROUP BY variant
)
SELECT c.variant, c.first_purchase_date, c.new_converters,
       c.cumulative_converters, d.assigned_users,
       ROUND(c.cumulative_converters::numeric
             / NULLIF(d.assigned_users, 0), 4) AS cumulative_conversion_rate
FROM cumulative c
JOIN denominators d USING (variant)
ORDER BY c.variant, c.first_purchase_date;

-- Why this is optimized:
-- MIN(date) collapses all purchase events to the first conversion per user before
-- the running sum. The window then processes only the much smaller daily series.
-- Dates with zero new converters are omitted; join to a calendar table if a dense
-- daily chart is required.

-- Q6. Apply CUPED to net revenue per assigned user using pre-period revenue as
--     a covariate. Estimate one pooled theta and compare adjusted arm means.
-- Optimized solution:
WITH user_level AS (
    SELECT a.variant, a.user_id, p.pre_period_revenue,
           COALESCE(SUM(o.event_value)
               FILTER (WHERE o.event_type IN ('purchase', 'refund')), 0) AS net_revenue
    FROM experiment_assignments a
    JOIN user_preperiod_metrics p
      ON p.experiment_id = a.experiment_id
     AND p.user_id = a.user_id
    LEFT JOIN canonical_outcomes o
      ON o.experiment_id = a.experiment_id
     AND o.user_id = a.user_id
    WHERE a.experiment_id = 'checkout_v2'
    GROUP BY a.variant, a.user_id, p.pre_period_revenue
),
pooled_stats AS (
    SELECT AVG(pre_period_revenue) AS mean_pre_period_revenue,
           COVAR_SAMP(net_revenue, pre_period_revenue)
             / NULLIF(VAR_SAMP(pre_period_revenue), 0) AS theta
    FROM user_level
),
adjusted AS (
    SELECT u.variant,
           u.net_revenue
             - s.theta * (u.pre_period_revenue - s.mean_pre_period_revenue)
             AS cuped_adjusted_revenue
    FROM user_level u
    CROSS JOIN pooled_stats s
)
SELECT variant,
       ROUND(AVG(cuped_adjusted_revenue), 2) AS cuped_adjusted_mean_revenue
FROM adjusted
GROUP BY variant
ORDER BY variant;

-- Why this is optimized:
-- Compute one row per assigned user and one pooled theta, then apply the scalar
-- adjustment. CUPED can reduce variance when the pre-period covariate is predictive.
-- Use a pre-treatment covariate only, validate the analysis population, and use a
-- statistical package for confidence intervals and hypothesis tests. The sample is
-- intentionally tiny and SRM-affected; do not interpret its arm difference as causal.

-- Q7. Calculate guardrails by assigned variant: checkout-error users per assigned
--     user, refunding purchasers among purchasers, and P95 checkout-attempt latency.
-- Optimized solution:
WITH user_flags AS (
    SELECT a.variant, a.user_id,
           COALESCE(BOOL_OR(o.event_type = 'purchase'), FALSE) AS purchased,
           COALESCE(BOOL_OR(o.event_type = 'refund'), FALSE) AS refunded,
           COALESCE(BOOL_OR(o.event_type = 'checkout_error'), FALSE) AS checkout_error
    FROM experiment_assignments a
    LEFT JOIN canonical_outcomes o
      ON o.experiment_id = a.experiment_id
     AND o.user_id = a.user_id
    WHERE a.experiment_id = 'checkout_v2'
    GROUP BY a.variant, a.user_id
),
guardrails AS (
    SELECT variant,
           COUNT(*) AS assigned_users,
           COUNT(*) FILTER (WHERE checkout_error) AS error_users,
           COUNT(*) FILTER (WHERE purchased) AS purchasing_users,
           COUNT(*) FILTER (WHERE purchased AND refunded) AS refunded_purchasers
    FROM user_flags
    GROUP BY variant
),
latency AS (
    SELECT a.variant,
           PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY o.latency_ms) AS p95_latency_ms
    FROM canonical_outcomes o
    JOIN experiment_assignments a
      ON a.experiment_id = o.experiment_id
     AND a.user_id = o.user_id
    WHERE o.experiment_id = 'checkout_v2'
      AND o.event_type = 'checkout_attempt'
      AND o.latency_ms IS NOT NULL
    GROUP BY a.variant
)
SELECT g.variant, g.assigned_users,
       ROUND(g.error_users::numeric / NULLIF(g.assigned_users, 0), 4) AS error_user_rate,
       ROUND(g.refunded_purchasers::numeric
             / NULLIF(g.purchasing_users, 0), 4) AS refunding_purchaser_rate,
       ROUND(l.p95_latency_ms::numeric, 1) AS p95_latency_ms
FROM guardrails g
LEFT JOIN latency l USING (variant)
ORDER BY g.variant;

-- Why this is optimized:
-- Boolean flags reduce multiple events to one row per user for rate denominators.
-- P95 is calculated only over checkout-attempt events, not the full event stream.
-- For large experiments, consider pre-aggregating user-level metrics by experiment
-- and analysis window, while preserving the assignment grain.

-- Q8. Detect exposure contamination: users exposed to multiple variants, users
--     whose observed variant differs from assignment, and users never exposed.
-- Optimized solution:
WITH exposure_by_user AS (
    SELECT experiment_id, user_id,
           COUNT(*) AS exposure_events,
           COUNT(DISTINCT variant) AS distinct_exposed_variants,
           ARRAY_AGG(DISTINCT variant ORDER BY variant) AS exposed_variants
    FROM canonical_exposures
    WHERE experiment_id = 'checkout_v2'
    GROUP BY experiment_id, user_id
)
SELECT a.user_id, a.variant AS assigned_variant,
       COALESCE(e.exposure_events, 0) AS exposure_events,
       COALESCE(e.distinct_exposed_variants, 0) AS distinct_exposed_variants,
       e.exposed_variants,
       CASE
           WHEN e.user_id IS NULL THEN 'not_exposed'
           WHEN e.distinct_exposed_variants > 1 THEN 'multiple_variants'
           WHEN e.exposed_variants[1] <> a.variant THEN 'variant_mismatch'
           ELSE 'clean'
       END AS exposure_quality
FROM experiment_assignments a
LEFT JOIN exposure_by_user e
  ON e.experiment_id = a.experiment_id
 AND e.user_id = a.user_id
WHERE a.experiment_id = 'checkout_v2'
ORDER BY a.user_id;

-- Why this is optimized:
-- Canonicalize and aggregate exposures once per user before joining. The assignment
-- table remains the complete population, so absent exposure rows are visible.
-- Investigate contamination separately; do not silently reassign users by exposure.

-- Q9. Check pre-period revenue balance with standardized mean difference (SMD).
--     This is a descriptive randomization diagnostic, not a substitute for SRM.
-- Optimized solution:
WITH arm_stats AS (
    SELECT
        COUNT(*) FILTER (WHERE a.variant = 'control')::numeric AS n_control,
        COUNT(*) FILTER (WHERE a.variant = 'treatment')::numeric AS n_treatment,
        AVG(p.pre_period_revenue) FILTER (WHERE a.variant = 'control') AS mean_control,
        AVG(p.pre_period_revenue) FILTER (WHERE a.variant = 'treatment') AS mean_treatment,
        VAR_SAMP(p.pre_period_revenue) FILTER (WHERE a.variant = 'control') AS var_control,
        VAR_SAMP(p.pre_period_revenue) FILTER (WHERE a.variant = 'treatment') AS var_treatment
    FROM experiment_assignments a
    JOIN user_preperiod_metrics p
      ON p.experiment_id = a.experiment_id
     AND p.user_id = a.user_id
    WHERE a.experiment_id = 'checkout_v2'
),
pooled AS (
    SELECT *,
           SQRT(
               ((n_control - 1) * var_control
                + (n_treatment - 1) * var_treatment)
               / NULLIF(n_control + n_treatment - 2, 0)
           ) AS pooled_standard_deviation
    FROM arm_stats
)
SELECT n_control, n_treatment, mean_control, mean_treatment,
       ROUND(ABS(mean_treatment - mean_control)
             / NULLIF(pooled_standard_deviation, 0), 4) AS absolute_smd
FROM pooled;

-- Why this is optimized:
-- Conditional aggregates compute both arm summaries in a single pass over the
-- one-row-per-user assignment/pre-period join. SMD is scale-free and useful for
-- balance diagnostics, but small samples naturally show noisy differences.

-- Performance and production notes:
-- 1. Preserve randomization unit grain (user, account, household, etc.) in every
--    denominator. If assignment is by account, aggregate outcomes to account first.
-- 2. Use an immutable event idempotency key and deterministic ingestion tie-breaker.
--    If corrections are append-only, retain raw history and expose a canonical view.
-- 3. Keep event timestamps in timestamptz; define the experiment analysis window and
--    attribution rules explicitly, including late-arriving events and refund windows.
-- 4. For very large event tables, partition by occurred_at and consider BRIN for
--    append-correlated time scans. Keep experiment_id/user_id B-tree access paths
--    for per-user joins; validate with EXPLAIN (ANALYZE, BUFFERS).
-- 5. Refresh planner statistics after large loads. Avoid indexing every metric column;
--    measure write overhead and index usage before retaining candidate indexes.
-- 6. Check SRM, exposure integrity, and pre-period balance before reading treatment
--    lift. Pre-register primary metrics, guardrails, attribution windows, and stopping
--    rules. Do not repeatedly peek at significance without a sequential-testing plan.
-- 7. CUPED reduces variance only when the pre-period covariate is predictive and
--    unaffected by treatment. Use a common, pre-specified covariate and report
--    uncertainty intervals from a validated statistical workflow.
-- 8. This sample intentionally has 20 users and a 16:4 split despite 50:50 allocation.
--    It is a query-practice dataset, not evidence that the treatment is effective.
