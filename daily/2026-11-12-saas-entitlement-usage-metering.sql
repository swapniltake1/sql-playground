-- Daily SQL Practice — 2026-11-12
-- Topic: SaaS Entitlements, Usage Metering, Quotas & Invoice Controls
-- PostgreSQL 14+
--
-- Run this file in a disposable practice database. The setup is active; all
-- numbered answer queries are commented out so you can attempt each problem first.
--
-- Business scenario:
-- A multi-tenant SaaS platform bills customers for API calls and export jobs.
-- Plans define included units and optional overage rates. Raw usage can be
-- delivered more than once, arrive late, fall outside a billing period, or
-- reference a feature that the customer's plan does not provide.

-- ---------------------------------------------------------------------------
-- 0. ISOLATED SCHEMA AND REALISTIC SAMPLE DATA
-- ---------------------------------------------------------------------------

DROP TABLE IF EXISTS usage_invoice_lines;
DROP TABLE IF EXISTS usage_events_raw;
DROP TABLE IF EXISTS plan_entitlements;
DROP TABLE IF EXISTS subscription_periods;
DROP TABLE IF EXISTS subscriptions;
DROP TABLE IF EXISTS plans;
DROP TABLE IF EXISTS organizations;

CREATE TABLE organizations (
    org_id           bigint PRIMARY KEY,
    org_name         text NOT NULL,
    billing_timezone text NOT NULL,
    created_at       timestamptz NOT NULL
);

CREATE TABLE plans (
    plan_id   bigint PRIMARY KEY,
    plan_code text NOT NULL UNIQUE,
    plan_name text NOT NULL
);

CREATE TABLE subscriptions (
    subscription_id bigint PRIMARY KEY,
    org_id          bigint NOT NULL REFERENCES organizations(org_id),
    status          text NOT NULL CHECK (status IN ('trialing','active','past_due','canceled')),
    currency        char(3) NOT NULL,
    started_at      timestamptz NOT NULL,
    canceled_at     timestamptz
);

-- Periods are half-open: [period_start, period_end).
-- Split periods whenever a plan or entitlement change becomes effective.
CREATE TABLE subscription_periods (
    period_id    bigint PRIMARY KEY,
    subscription_id bigint NOT NULL REFERENCES subscriptions(subscription_id),
    plan_id      bigint NOT NULL REFERENCES plans(plan_id),
    period_start timestamptz NOT NULL,
    period_end   timestamptz NOT NULL,
    period_status text NOT NULL CHECK (period_status IN ('open','closed')),
    UNIQUE (subscription_id, period_start),
    CHECK (period_end > period_start)
);

-- Entitlement validity is also half-open. Billing periods must not cross
-- an entitlement boundary; create separate periods at such a boundary.
CREATE TABLE plan_entitlements (
    entitlement_id    bigint PRIMARY KEY,
    plan_id           bigint NOT NULL REFERENCES plans(plan_id),
    feature_code      text NOT NULL,
    valid_from        timestamptz NOT NULL,
    valid_to          timestamptz NOT NULL,
    included_units    bigint NOT NULL CHECK (included_units >= 0),
    overage_allowed   boolean NOT NULL,
    overage_rate_minor bigint NOT NULL CHECK (overage_rate_minor >= 0),
    UNIQUE (plan_id, feature_code, valid_from),
    CHECK (valid_to > valid_from)
);

-- Raw landing table intentionally has no uniqueness constraint on
-- source_event_id: duplicate deliveries must remain observable.
CREATE TABLE usage_events_raw (
    ingest_id       bigint PRIMARY KEY,
    source_event_id text NOT NULL,
    subscription_id bigint NOT NULL REFERENCES subscriptions(subscription_id),
    feature_code    text NOT NULL,
    occurred_at     timestamptz NOT NULL,
    ingested_at     timestamptz NOT NULL,
    quantity        bigint NOT NULL CHECK (quantity > 0),
    payload_hash    text NOT NULL
);

CREATE TABLE usage_invoice_lines (
    period_id                 bigint NOT NULL REFERENCES subscription_periods(period_id),
    feature_code              text NOT NULL,
    currency                  char(3) NOT NULL,
    used_units                bigint NOT NULL,
    included_units            bigint NOT NULL,
    billable_overage_units    bigint NOT NULL,
    overage_amount_minor      bigint NOT NULL,
    calculated_at             timestamptz NOT NULL,
    PRIMARY KEY (period_id, feature_code),
    CHECK (used_units >= 0),
    CHECK (included_units >= 0),
    CHECK (billable_overage_units >= 0),
    CHECK (overage_amount_minor >= 0)
);

INSERT INTO organizations VALUES
(1, 'Northstar Analytics', 'Asia/Kolkata',       '2025-04-10 09:00+05:30'),
(2, 'Blue Oak Commerce',   'America/Los_Angeles','2025-06-18 10:00-07'),
(3, 'Riverbend Health',    'Asia/Kolkata',       '2025-08-02 12:00+05:30'),
(4, 'Alpine Research',     'Europe/Berlin',      '2025-02-14 08:30+01');

INSERT INTO plans VALUES
(1, 'STARTER', 'Starter'),
(2, 'GROWTH',  'Growth');

INSERT INTO subscriptions VALUES
(101, 1, 'active',   'INR', '2026-01-01 00:00+00', NULL),
(102, 2, 'active',   'USD', '2026-02-01 00:00+00', NULL),
(103, 3, 'active',   'INR', '2026-03-01 00:00+00', NULL),
(104, 4, 'canceled', 'EUR', '2025-10-01 00:00+00', '2026-11-01 00:00+00');

INSERT INTO subscription_periods VALUES
(1000, 101, 1, '2026-10-01 00:00+00', '2026-11-01 00:00+00', 'closed'),
(1001, 101, 1, '2026-11-01 00:00+00', '2026-12-01 00:00+00', 'open'),
(1002, 102, 2, '2026-11-01 00:00+00', '2026-12-01 00:00+00', 'open'),
(1003, 103, 1, '2026-11-02 00:00+00', '2026-12-01 00:00+00', 'open'),
(1004, 103, 1, '2026-10-01 00:00+00', '2026-11-01 00:00+00', 'closed'),
(1005, 104, 1, '2026-10-01 00:00+00', '2026-11-01 00:00+00', 'closed');

INSERT INTO plan_entitlements VALUES
(1, 1, 'api_calls',   '2026-01-01 00:00+00', '2027-01-01 00:00+00', 1000, false,  0),
(2, 1, 'export_jobs', '2026-01-01 00:00+00', '2027-01-01 00:00+00',    5, false,  0),
(3, 2, 'api_calls',   '2026-01-01 00:00+00', '2027-01-01 00:00+00', 5000, true,   2),
(4, 2, 'export_jobs', '2026-01-01 00:00+00', '2027-01-01 00:00+00',   20, true,  50);

INSERT INTO usage_events_raw VALUES
(1,  'evt-099', 101, 'api_calls',   '2026-10-31 23:45+00', '2026-10-31 23:50+00',   20, 'h099'),
(2,  'evt-101', 101, 'api_calls',   '2026-11-02 08:00+00', '2026-11-02 08:00+05:30', 400, 'h101'),
(3,  'evt-102', 101, 'api_calls',   '2026-11-03 09:00+00', '2026-11-03 09:02+00',   350, 'h102'),
(4,  'evt-102', 101, 'api_calls',   '2026-11-03 09:00+00', '2026-11-04 08:00+00',   350, 'h102'),
(5,  'evt-103', 101, 'api_calls',   '2026-11-05 11:00+00', '2026-11-05 11:01+00',   300, 'h103'),
(6,  'evt-104', 101, 'api_calls',   '2026-11-06 10:00+00', '2026-11-10 12:00+00',   200, 'h104'),
(7,  'evt-105', 101, 'export_jobs', '2026-11-07 12:00+00', '2026-11-07 12:01+00',     6, 'h105'),
(8,  'evt-106', 101, 'export_jobs', '2026-11-08 12:00+00', '2026-11-08 12:01+00',     2, 'h106'),
(9,  'evt-107', 101, 'experimental_calls', '2026-11-09 12:00+00', '2026-11-09 12:01+00', 10, 'h107'),
(10, 'evt-201', 102, 'api_calls',   '2026-11-02 09:00+00', '2026-11-02 09:01+00',  2500, 'h201'),
(11, 'evt-202', 102, 'api_calls',   '2026-11-05 09:00+00', '2026-11-05 09:01+00',  1800, 'h202'),
(12, 'evt-203', 102, 'api_calls',   '2026-11-10 09:00+00', '2026-11-10 09:01+00',  1500, 'h203'),
(13, 'evt-204', 102, 'export_jobs', '2026-11-10 10:00+00', '2026-11-10 10:01+00',    25, 'h204'),
(14, 'evt-301', 103, 'api_calls',   '2026-11-03 09:00+00', '2026-11-03 09:01+00',   600, 'h301'),
(15, 'evt-302', 103, 'api_calls',   '2026-11-05 09:00+00', '2026-11-05 09:01+00',   300, 'h302'),
(16, 'evt-303', 103, 'export_jobs', '2026-11-06 09:00+00', '2026-11-06 09:01+00',     3, 'h303'),
(17, 'evt-401', 104, 'api_calls',   '2026-11-02 10:00+00', '2026-11-02 10:01+00',    50, 'h401');

-- ---------------------------------------------------------------------------
-- Q1. PROBLEM — Canonicalize replayed usage events.
-- Return one row per source_event_id, keeping the latest accepted delivery.
-- Also expose delivery_count so duplicate traffic can be measured.
--
-- OPTIMIZED SOLUTION:
-- WITH ranked AS (
--     SELECT u.*,
--            COUNT(*) OVER (PARTITION BY source_event_id) AS delivery_count,
--            ROW_NUMBER() OVER (
--                PARTITION BY source_event_id
--                ORDER BY ingested_at DESC, ingest_id DESC
--            ) AS rn
--     FROM usage_events_raw u
-- )
-- SELECT ingest_id, source_event_id, subscription_id, feature_code,
--        occurred_at, ingested_at, quantity, delivery_count
-- FROM ranked
-- WHERE rn = 1
-- ORDER BY source_event_id;
--
-- WHY THIS SHAPE:
-- Deduplicate before aggregating money or usage. A stable tie-breaker makes the
-- winner deterministic. In a production pipeline, persist canonical events
-- behind a UNIQUE(source_event_id) constraint after resolving correction policy.

-- ---------------------------------------------------------------------------
-- Q2. PROBLEM — Find canonical events that match zero or multiple billing periods.
-- Use half-open period boundaries so an event at midnight belongs to one period.
--
-- OPTIMIZED SOLUTION:
-- WITH ranked AS (
--     SELECT u.*,
--            ROW_NUMBER() OVER (
--                PARTITION BY source_event_id
--                ORDER BY ingested_at DESC, ingest_id DESC
--            ) AS rn
--     FROM usage_events_raw u
-- ),
-- canonical AS (
--     SELECT * FROM ranked WHERE rn = 1
-- )
-- SELECT c.source_event_id, c.subscription_id, c.occurred_at,
--        COUNT(sp.period_id) AS matching_periods
-- FROM canonical c
-- LEFT JOIN subscription_periods sp
--   ON sp.subscription_id = c.subscription_id
--  AND c.occurred_at >= sp.period_start
--  AND c.occurred_at <  sp.period_end
-- GROUP BY c.source_event_id, c.subscription_id, c.occurred_at
-- HAVING COUNT(sp.period_id) <> 1
-- ORDER BY c.source_event_id;
--
-- WHY THIS SHAPE:
-- The half-open predicate avoids double assignment at adjacent period boundaries.
-- The LEFT JOIN preserves events with no matching period; COUNT(period_id) also
-- exposes overlaps. Repair period integrity before trusting downstream totals.

-- ---------------------------------------------------------------------------
-- Q3. PROBLEM — Aggregate canonical usage at billing-period and feature grain.
-- Return used units and event count for every matched subscription period/feature.
--
-- OPTIMIZED SOLUTION:
-- WITH ranked AS (
--     SELECT u.*,
--            ROW_NUMBER() OVER (
--                PARTITION BY source_event_id
--                ORDER BY ingested_at DESC, ingest_id DESC
--            ) AS rn
--     FROM usage_events_raw u
-- ),
-- canonical AS (
--     SELECT * FROM ranked WHERE rn = 1
-- ),
-- matched AS (
--     SELECT sp.period_id, s.org_id, s.currency,
--            c.feature_code, c.source_event_id, c.quantity
--     FROM canonical c
--     JOIN subscription_periods sp
--       ON sp.subscription_id = c.subscription_id
--      AND c.occurred_at >= sp.period_start
--      AND c.occurred_at <  sp.period_end
--     JOIN subscriptions s
--       ON s.subscription_id = sp.subscription_id
-- )
-- SELECT period_id, org_id, currency, feature_code,
--        SUM(quantity) AS used_units,
--        COUNT(*) AS canonical_event_count
-- FROM matched
-- GROUP BY period_id, org_id, currency, feature_code
-- ORDER BY period_id, feature_code;
--
-- WHY THIS SHAPE:
-- Deduplicate first, then aggregate once at the billing grain. Joining raw events
-- directly to entitlement history or other one-to-many tables can multiply units.
-- Q2 must return no exceptions before using this result for invoicing.

-- ---------------------------------------------------------------------------
-- Q4. PROBLEM — Calculate quota consumption for every entitled feature, including
-- features with zero usage. Show included units, overage units and blocked units.
--
-- OPTIMIZED SOLUTION:
-- WITH ranked AS (
--     SELECT u.*,
--            ROW_NUMBER() OVER (
--                PARTITION BY source_event_id
--                ORDER BY ingested_at DESC, ingest_id DESC
--            ) AS rn
--     FROM usage_events_raw u
-- ),
-- canonical AS (
--     SELECT * FROM ranked WHERE rn = 1
-- ),
-- usage_by_feature AS (
--     SELECT sp.period_id, c.feature_code, SUM(c.quantity) AS used_units
--     FROM canonical c
--     JOIN subscription_periods sp
--       ON sp.subscription_id = c.subscription_id
--      AND c.occurred_at >= sp.period_start
--      AND c.occurred_at <  sp.period_end
--     GROUP BY sp.period_id, c.feature_code
-- )
-- SELECT sp.period_id, s.org_id, s.currency, pe.feature_code,
--        COALESCE(u.used_units, 0) AS used_units,
--        pe.included_units,
--        GREATEST(COALESCE(u.used_units, 0) - pe.included_units, 0)
--            AS units_over_included,
--        CASE WHEN pe.overage_allowed
--             THEN GREATEST(COALESCE(u.used_units, 0) - pe.included_units, 0)
--             ELSE 0 END AS billable_overage_units,
--        CASE WHEN NOT pe.overage_allowed
--             THEN GREATEST(COALESCE(u.used_units, 0) - pe.included_units, 0)
--             ELSE 0 END AS blocked_or_unbillable_units
-- FROM subscription_periods sp
-- JOIN subscriptions s ON s.subscription_id = sp.subscription_id
-- JOIN plan_entitlements pe
--   ON pe.plan_id = sp.plan_id
--  AND pe.valid_from <= sp.period_start
--  AND pe.valid_to   > sp.period_start
-- LEFT JOIN usage_by_feature u
--   ON u.period_id = sp.period_id
--  AND u.feature_code = pe.feature_code
-- ORDER BY sp.period_id, pe.feature_code;
--
-- WHY THIS SHAPE:
-- Start from entitlements and LEFT JOIN pre-aggregated usage to retain zero-use
-- features. This assumes billing periods are split at plan/entitlement changes.
-- Do not silently apply a mid-period entitlement change to an entire month.

-- ---------------------------------------------------------------------------
-- Q5. PROBLEM — Identify usage that cannot be authorized by a subscription period
-- and plan entitlement. Include both out-of-period and unknown-feature events.
--
-- OPTIMIZED SOLUTION:
-- WITH ranked AS (
--     SELECT u.*,
--            ROW_NUMBER() OVER (
--                PARTITION BY source_event_id
--                ORDER BY ingested_at DESC, ingest_id DESC
--            ) AS rn
--     FROM usage_events_raw u
-- ),
-- canonical AS (
--     SELECT * FROM ranked WHERE rn = 1
-- ),
-- matched AS (
--     SELECT c.*, sp.period_id, sp.plan_id
--     FROM canonical c
--     LEFT JOIN subscription_periods sp
--       ON sp.subscription_id = c.subscription_id
--      AND c.occurred_at >= sp.period_start
--      AND c.occurred_at <  sp.period_end
-- )
-- SELECT m.source_event_id, m.subscription_id, m.feature_code,
--        m.occurred_at, m.period_id,
--        CASE WHEN m.period_id IS NULL THEN 'no_billing_period'
--             ELSE 'feature_not_entitled_at_event_time' END AS exception_type
-- FROM matched m
-- LEFT JOIN plan_entitlements pe
--   ON pe.plan_id = m.plan_id
--  AND pe.feature_code = m.feature_code
--  AND pe.valid_from <= m.occurred_at
--  AND pe.valid_to   > m.occurred_at
-- WHERE m.period_id IS NULL
--    OR pe.entitlement_id IS NULL
-- ORDER BY m.source_event_id;
--
-- WHY THIS SHAPE:
-- An anti-join pattern finds unauthorized usage without discarding the reason.
-- Keep the event-time entitlement predicate explicit for auditability. Q2 should
-- be used to detect overlapping periods, which otherwise can duplicate matches.

-- ---------------------------------------------------------------------------
-- Q6. PROBLEM — Produce invoice-ready overage amounts by period, feature and currency.
-- Keep all amounts in integer minor units; do not mix currencies in one aggregate.
--
-- OPTIMIZED SOLUTION:
-- WITH ranked AS (
--     SELECT u.*,
--            ROW_NUMBER() OVER (
--                PARTITION BY source_event_id
--                ORDER BY ingested_at DESC, ingest_id DESC
--            ) AS rn
--     FROM usage_events_raw u
-- ),
-- canonical AS (
--     SELECT * FROM ranked WHERE rn = 1
-- ),
-- usage_by_feature AS (
--     SELECT sp.period_id, c.feature_code, SUM(c.quantity) AS used_units
--     FROM canonical c
--     JOIN subscription_periods sp
--       ON sp.subscription_id = c.subscription_id
--      AND c.occurred_at >= sp.period_start
--      AND c.occurred_at <  sp.period_end
--     GROUP BY sp.period_id, c.feature_code
-- )
-- SELECT sp.period_id, s.currency, pe.feature_code,
--        COALESCE(u.used_units, 0) AS used_units,
--        GREATEST(COALESCE(u.used_units, 0) - pe.included_units, 0)
--            AS billable_overage_units,
--        GREATEST(COALESCE(u.used_units, 0) - pe.included_units, 0)
--            * pe.overage_rate_minor AS overage_amount_minor
-- FROM subscription_periods sp
-- JOIN subscriptions s ON s.subscription_id = sp.subscription_id
-- JOIN plan_entitlements pe
--   ON pe.plan_id = sp.plan_id
--  AND pe.valid_from <= sp.period_start
--  AND pe.valid_to > sp.period_start
-- LEFT JOIN usage_by_feature u
--   ON u.period_id = sp.period_id
--  AND u.feature_code = pe.feature_code
-- WHERE pe.overage_allowed
-- ORDER BY sp.period_id, pe.feature_code;
--
-- WHY THIS SHAPE:
-- Aggregate usage before applying the rate. Integer minor units avoid floating-
-- point rounding drift. Features without overage permission must be handled as
-- quota exceptions, not silently charged at a zero or default rate.

-- ---------------------------------------------------------------------------
-- Q7. PROBLEM — Measure late-arriving usage by organization and feature.
-- Treat delivery more than 15 minutes after event time as late.
--
-- OPTIMIZED SOLUTION:
-- WITH ranked AS (
--     SELECT u.*,
--            ROW_NUMBER() OVER (
--                PARTITION BY source_event_id
--                ORDER BY ingested_at DESC, ingest_id DESC
--            ) AS rn
--     FROM usage_events_raw u
-- ),
-- canonical AS (
--     SELECT * FROM ranked WHERE rn = 1
-- )
-- SELECT s.org_id, c.feature_code,
--        COUNT(*) AS late_event_count,
--        SUM(c.quantity) AS late_units,
--        ROUND(AVG(EXTRACT(EPOCH FROM (c.ingested_at - c.occurred_at)) / 60.0), 2)
--            AS average_delivery_delay_minutes,
--        MAX(c.ingested_at - c.occurred_at) AS maximum_delivery_delay
-- FROM canonical c
-- JOIN subscriptions s ON s.subscription_id = c.subscription_id
-- WHERE c.ingested_at > c.occurred_at + INTERVAL '15 minutes'
-- GROUP BY s.org_id, c.feature_code
-- ORDER BY late_units DESC;
--
-- WHY THIS SHAPE:
-- Deduplication prevents retries from inflating late-event metrics. Event-time and
-- ingestion-time are separate clocks: use occurred_at for billing attribution and
-- ingested_at for operational freshness. For large raw tables, partition by the
-- ingestion date for pipeline monitoring and retain the original event timestamp.

-- ---------------------------------------------------------------------------
-- Q8. PROBLEM — Compare feature utilization against the median for the same plan
-- and feature. Rank subscriptions from highest to lowest utilization.
--
-- OPTIMIZED SOLUTION:
-- WITH ranked AS (
--     SELECT u.*,
--            ROW_NUMBER() OVER (
--                PARTITION BY source_event_id
--                ORDER BY ingested_at DESC, ingest_id DESC
--            ) AS rn
--     FROM usage_events_raw u
-- ),
-- canonical AS (
--     SELECT * FROM ranked WHERE rn = 1
-- ),
-- usage_by_feature AS (
--     SELECT sp.period_id, c.feature_code, SUM(c.quantity) AS used_units
--     FROM canonical c
--     JOIN subscription_periods sp
--       ON sp.subscription_id = c.subscription_id
--      AND c.occurred_at >= sp.period_start
--      AND c.occurred_at <  sp.period_end
--     GROUP BY sp.period_id, c.feature_code
-- ),
-- utilization AS (
--     SELECT sp.period_id, p.plan_code, pe.feature_code,
--            COALESCE(u.used_units, 0)::numeric
--                / NULLIF(pe.included_units, 0) AS utilization_ratio
--     FROM subscription_periods sp
--     JOIN plans p ON p.plan_id = sp.plan_id
--     JOIN plan_entitlements pe
--       ON pe.plan_id = sp.plan_id
--      AND pe.valid_from <= sp.period_start
--      AND pe.valid_to > sp.period_start
--     LEFT JOIN usage_by_feature u
--       ON u.period_id = sp.period_id
--      AND u.feature_code = pe.feature_code
-- ),
-- medians AS (
--     SELECT plan_code, feature_code,
--            percentile_cont(0.5) WITHIN GROUP (
--                ORDER BY utilization_ratio::double precision
--            ) AS median_utilization
--     FROM utilization
--     WHERE utilization_ratio IS NOT NULL
--     GROUP BY plan_code, feature_code
-- )
-- SELECT u.*, m.median_utilization,
--        DENSE_RANK() OVER (
--            PARTITION BY u.plan_code, u.feature_code
--            ORDER BY u.utilization_ratio DESC
--        ) AS utilization_rank
-- FROM utilization u
-- JOIN medians m USING (plan_code, feature_code)
-- ORDER BY u.plan_code, u.feature_code, utilization_rank;
--
-- WHY THIS SHAPE:
-- Calculate one utilization row per subscription-period-feature before ranking.
-- Compute the median once per plan/feature instead of repeating a correlated
-- percentile calculation for every subscription.

-- ---------------------------------------------------------------------------
-- Q9. PROBLEM — Detect gaps and overlaps between consecutive billing periods.
-- Return only subscriptions whose period sequence is not contiguous.
--
-- OPTIMIZED SOLUTION:
-- WITH ordered_periods AS (
--     SELECT sp.*,
--            LAG(period_end) OVER (
--                PARTITION BY subscription_id
--                ORDER BY period_start, period_id
--            ) AS previous_period_end
--     FROM subscription_periods sp
-- )
-- SELECT subscription_id, period_id, previous_period_end,
--        period_start, period_end,
--        CASE WHEN period_start < previous_period_end THEN 'overlap'
--             WHEN period_start > previous_period_end THEN 'gap'
--        END AS integrity_issue
-- FROM ordered_periods
-- WHERE previous_period_end IS NOT NULL
--   AND period_start <> previous_period_end
-- ORDER BY subscription_id, period_start;
--
-- WHY THIS SHAPE:
-- LAG compares each period with its immediate predecessor in one ordered pass.
-- A unique start-time constraint does not prevent overlapping ranges; validate
-- range integrity separately or use a PostgreSQL exclusion constraint.

-- ---------------------------------------------------------------------------
-- Q10. PROBLEM — Build an idempotent invoice-usage snapshot.
-- Insert one row per entitled period/feature and update only when calculated
-- quantities or charges actually change. Re-running the solution is safe.
--
-- OPTIMIZED SOLUTION:
-- WITH ranked AS (
--     SELECT u.*,
--            ROW_NUMBER() OVER (
--                PARTITION BY source_event_id
--                ORDER BY ingested_at DESC, ingest_id DESC
--            ) AS rn
--     FROM usage_events_raw u
-- ),
-- canonical AS (
--     SELECT * FROM ranked WHERE rn = 1
-- ),
-- usage_by_feature AS (
--     SELECT sp.period_id, c.feature_code, SUM(c.quantity) AS used_units
--     FROM canonical c
--     JOIN subscription_periods sp
--       ON sp.subscription_id = c.subscription_id
--      AND c.occurred_at >= sp.period_start
--      AND c.occurred_at <  sp.period_end
--     GROUP BY sp.period_id, c.feature_code
-- ),
-- calculated AS (
--     SELECT sp.period_id, pe.feature_code, s.currency,
--            COALESCE(u.used_units, 0) AS used_units,
--            pe.included_units,
--            CASE WHEN pe.overage_allowed
--                 THEN GREATEST(COALESCE(u.used_units, 0) - pe.included_units, 0)
--                 ELSE 0 END AS billable_overage_units,
--            CASE WHEN pe.overage_allowed
--                 THEN GREATEST(COALESCE(u.used_units, 0) - pe.included_units, 0)
--                      * pe.overage_rate_minor
--                 ELSE 0 END AS overage_amount_minor
--     FROM subscription_periods sp
--     JOIN subscriptions s ON s.subscription_id = sp.subscription_id
--     JOIN plan_entitlements pe
--       ON pe.plan_id = sp.plan_id
--      AND pe.valid_from <= sp.period_start
--      AND pe.valid_to > sp.period_start
--     LEFT JOIN usage_by_feature u
--       ON u.period_id = sp.period_id
--      AND u.feature_code = pe.feature_code
-- )
-- INSERT INTO usage_invoice_lines AS stored (
--     period_id, feature_code, currency, used_units, included_units,
--     billable_overage_units, overage_amount_minor, calculated_at
-- )
-- SELECT period_id, feature_code, currency, used_units, included_units,
--        billable_overage_units, overage_amount_minor, now()
-- FROM calculated
-- ON CONFLICT (period_id, feature_code) DO UPDATE
-- SET currency = EXCLUDED.currency,
--     used_units = EXCLUDED.used_units,
--     included_units = EXCLUDED.included_units,
--     billable_overage_units = EXCLUDED.billable_overage_units,
--     overage_amount_minor = EXCLUDED.overage_amount_minor,
--     calculated_at = EXCLUDED.calculated_at
-- WHERE (stored.currency, stored.used_units, stored.included_units,
--        stored.billable_overage_units, stored.overage_amount_minor)
--   IS DISTINCT FROM
--       (EXCLUDED.currency, EXCLUDED.used_units, EXCLUDED.included_units,
--        EXCLUDED.billable_overage_units, EXCLUDED.overage_amount_minor);
--
-- WHY THIS SHAPE:
-- The primary key enforces one invoice line per period and feature. ON CONFLICT
-- makes the snapshot replay-safe, while IS DISTINCT FROM avoids needless writes
-- and WAL churn when a recalculation produces identical values.

-- ---------------------------------------------------------------------------
-- PERFORMANCE NOTES AND PRODUCTION FOLLOW-UPS
-- ---------------------------------------------------------------------------
-- 1. Candidate indexes (benchmark on representative volume; do not blindly add all):
--    CREATE INDEX ON usage_events_raw
--        (source_event_id, ingested_at DESC, ingest_id DESC);
--    CREATE INDEX ON usage_events_raw
--        (subscription_id, occurred_at)
--        INCLUDE (feature_code, quantity, source_event_id, ingested_at);
--    CREATE INDEX ON subscription_periods
--        (subscription_id, period_start)
--        INCLUDE (period_end, plan_id, period_status);
--    CREATE INDEX ON plan_entitlements
--        (plan_id, feature_code, valid_from DESC)
--        INCLUDE (valid_to, included_units, overage_allowed, overage_rate_minor);
--
-- 2. Keep event-time predicates half-open and avoid wrapping occurred_at in
--    DATE(), AT TIME ZONE, or another function in the WHERE clause. Convert to
--    tenant-local dates only after applying UTC bounds where possible.
--
-- 3. For high-volume ingestion, partition raw events by ingested_at or occurred_at
--    according to dominant retention and query patterns. PostgreSQL partitioned
--    uniqueness generally must include the partition key; design replay protection
--    accordingly, often with a separate unpartitioned event-key registry.
--
-- 4. Keep raw deliveries immutable for audit, but publish a canonical event layer
--    with a documented correction policy. "Latest ingestion wins" is only a sample
--    rule; production systems may need source sequence numbers or version semantics.
--
-- 5. Ensure subscription periods and entitlement validity windows do not overlap.
--    Align period boundaries to plan changes; otherwise split usage at the exact
--    effective timestamp and apply prorating rules explicitly.
--
-- 6. Store currency amounts as integer minor units and group by currency. Define
--    rounding, tax, credit, refund, and invoice-finalization policies separately.
--
-- 7. Run EXPLAIN (ANALYZE, BUFFERS) for Q1-Q10 with realistic cardinalities.
--    Inspect sort spills, rows removed by filters, join fanout, buffer reads, and
--    whether period/event indexes are actually selected by the planner.
--
-- 8. Production interview follow-ups:
--    * How would you process late events after an invoice has been finalized?
--    * How would you model prepaid credits and expiring promotional allowances?
--    * How would you enforce non-overlapping entitlement ranges per plan/feature?
--    * How would you reconcile raw event counts with canonical and billed units?
--    * How would you support corrections without mutating the original event?
