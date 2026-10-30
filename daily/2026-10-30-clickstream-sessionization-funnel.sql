-- =============================================================================
-- Daily SQL Practice — 2026-10-30
-- Topic: Clickstream Sessionization, Event Deduplication & Conversion Funnels
-- Engine: PostgreSQL 14+
--
-- Run this file in a fresh PostgreSQL session (or rerun it in the same session).
-- The setup creates a TEMP table, so it does not alter permanent application data.
-- All timestamps are UTC to keep date-based results deterministic.
--
-- Workflow:
--   1. Run the setup section.
--   2. Attempt each numbered problem.
--   3. Review the commented answer key.
--   4. Run the Q2 view-building solution before attempting Q3-Q8.
-- =============================================================================

SET TIME ZONE 'UTC';

-- Remove only this session's temporary table when rerunning the script.
DO $$
BEGIN
    IF to_regclass('pg_temp.web_events') IS NOT NULL THEN
        EXECUTE 'DROP TABLE pg_temp.web_events';
    END IF;
END
$$;

CREATE TEMP TABLE web_events (
    ingest_id   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    event_id    TEXT NOT NULL,             -- Logical event identifier; replays can duplicate it
    user_id     BIGINT NOT NULL,
    event_type  TEXT NOT NULL CHECK (
        event_type IN (
            'page_view',
            'product_view',
            'add_to_cart',
            'purchase',
            'recommendation_view'
        )
    ),
    event_ts    TIMESTAMPTZ NOT NULL,       -- When the user action actually happened
    ingested_at TIMESTAMPTZ NOT NULL,       -- When the platform received the event
    page_path   TEXT,
    campaign_id TEXT,
    event_value NUMERIC(12, 2)
);

INSERT INTO web_events
    (event_id, user_id, event_type, event_ts, ingested_at, page_path, campaign_id, event_value)
VALUES
    -- User 101: one converting session, one non-converting session, then a return next day.
    ('evt-101', 101, 'page_view',
     '2026-10-15 09:00:00+00', '2026-10-15 09:00:04+00', '/', 'paid_search', NULL),
    ('evt-102', 101, 'product_view',
     '2026-10-15 09:05:00+00', '2026-10-15 09:05:03+00', '/products/42', NULL, NULL),
    ('evt-103', 101, 'add_to_cart',
     '2026-10-15 09:12:00+00', '2026-10-15 09:12:02+00', '/cart', NULL, NULL),
    -- Duplicate delivery of evt-103: the later ingestion copy should win.
    ('evt-103', 101, 'add_to_cart',
     '2026-10-15 09:12:00+00', '2026-10-15 09:40:00+00', '/cart', NULL, NULL),
    ('evt-104', 101, 'purchase',
     '2026-10-15 09:25:00+00', '2026-10-15 09:25:05+00', '/checkout', NULL, 1499.00),
    ('evt-105', 101, 'page_view',
     '2026-10-15 10:00:00+00', '2026-10-15 10:00:03+00', '/', 'email_oct', NULL),
    ('evt-106', 101, 'product_view',
     '2026-10-15 10:10:00+00', '2026-10-15 10:10:04+00', '/products/17', NULL, NULL),
    ('evt-107', 101, 'page_view',
     '2026-10-16 10:00:00+00', '2026-10-16 10:00:02+00', '/', 'email_oct', NULL),
    ('evt-108', 101, 'purchase',
     '2026-10-16 10:20:00+00', '2026-10-16 10:20:04+00', '/checkout', NULL, 799.00),

    -- User 202: a 30-minute boundary remains in the same session; the next event starts one.
    ('evt-201', 202, 'page_view',
     '2026-10-15 09:10:00+00', '2026-10-15 09:10:02+00', '/', 'organic', NULL),
    ('evt-202', 202, 'product_view',
     '2026-10-15 09:40:00+00', '2026-10-15 09:40:02+00', '/products/88', NULL, NULL),
    ('evt-203', 202, 'add_to_cart',
     '2026-10-15 10:11:00+00', '2026-10-15 10:11:03+00', '/cart', NULL, NULL),
    ('evt-204', 202, 'purchase',
     '2026-10-15 10:20:00+00', '2026-10-15 10:20:05+00', '/checkout', NULL, 299.00),

    -- User 303: full funnel; evt-302 arrives more than a day after event time.
    ('evt-301', 303, 'page_view',
     '2026-10-15 10:00:00+00', '2026-10-15 10:00:03+00', '/', 'paid_search', NULL),
    ('evt-302', 303, 'recommendation_view',
     '2026-10-15 10:15:00+00', '2026-10-16 12:00:00+00', '/recommendations', NULL, NULL),
    ('evt-303', 303, 'product_view',
     '2026-10-15 10:20:00+00', '2026-10-15 10:20:03+00', '/products/55', NULL, NULL),
    ('evt-304', 303, 'add_to_cart',
     '2026-10-15 10:40:00+00', '2026-10-15 10:40:03+00', '/cart', NULL, NULL),
    ('evt-305', 303, 'purchase',
     '2026-10-15 10:55:00+00', '2026-10-15 10:55:04+00', '/checkout', NULL, 2499.00),

    -- User 404: the product view occurs 31 minutes after the page view.
    ('evt-401', 404, 'page_view',
     '2026-10-15 11:00:00+00', '2026-10-15 11:00:03+00', '/', 'referral', NULL),
    ('evt-402', 404, 'product_view',
     '2026-10-15 11:31:00+00', '2026-10-15 11:31:04+00', '/products/12', NULL, NULL);

-- Quick setup checks:
SELECT COUNT(*) AS raw_event_rows FROM web_events; -- Expected: 20
SELECT COUNT(DISTINCT event_id) AS distinct_event_ids FROM web_events; -- Expected: 19

-- =============================================================================
-- Q1. Event deduplication
-- For each event_id, retain exactly one record: the most recently ingested copy.
-- Use ingest_id as a deterministic tie-breaker when ingested_at is identical.
-- Also identify which logical event was delivered more than once.
-- =============================================================================

-- Problem query:
-- SELECT event_id, COUNT(*) AS copies
-- FROM web_events
-- GROUP BY event_id
-- HAVING COUNT(*) > 1
-- ORDER BY copies DESC, event_id;

-- Optimized solution:
 /*
WITH ranked_events AS (
    SELECT
        e.*,
        ROW_NUMBER() OVER (
            PARTITION BY event_id
            ORDER BY ingested_at DESC, ingest_id DESC
        ) AS row_num,
        COUNT(*) OVER (PARTITION BY event_id) AS delivery_count
    FROM web_events AS e
)
SELECT
    event_id,
    user_id,
    event_type,
    event_ts,
    ingested_at,
    delivery_count
FROM ranked_events
WHERE row_num = 1
ORDER BY event_ts, user_id, event_id;
*/

-- Why this works:
-- ROW_NUMBER gives one deterministic winner per logical event. The ingestion
-- timestamp is the business rule; ingest_id resolves ties. Avoid DISTINCT over
-- every column: it does not define which replay should win when payloads differ.

-- =============================================================================
-- Q2. Sessionize each user's events using a 30-minute inactivity threshold.
-- A gap of exactly 30 minutes stays in the current session; a gap greater than
-- 30 minutes starts a new session. Make the ordering deterministic.
--
-- Run the solution below once after attempting the question. It creates two
-- reusable TEMP views used by Q3-Q8.
-- =============================================================================

-- Optimized solution and reusable views:
 /*
CREATE OR REPLACE TEMP VIEW deduped_events AS
SELECT
    ingest_id,
    event_id,
    user_id,
    event_type,
    event_ts,
    ingested_at,
    page_path,
    campaign_id,
    event_value
FROM (
    SELECT
        e.*,
        ROW_NUMBER() OVER (
            PARTITION BY event_id
            ORDER BY ingested_at DESC, ingest_id DESC
        ) AS row_num
    FROM web_events AS e
) AS ranked
WHERE row_num = 1;

CREATE OR REPLACE TEMP VIEW sessionized_events AS
WITH ordered_events AS (
    SELECT
        e.*,
        LAG(event_ts) OVER (
            PARTITION BY user_id
            ORDER BY event_ts, event_id
        ) AS previous_event_ts
    FROM deduped_events AS e
),
session_boundaries AS (
    SELECT
        *,
        CASE
            WHEN previous_event_ts IS NULL
              OR event_ts > previous_event_ts + INTERVAL '30 minutes'
            THEN 1
            ELSE 0
        END AS starts_new_session
    FROM ordered_events
),
numbered_events AS (
    SELECT
        *,
        SUM(starts_new_session) OVER (
            PARTITION BY user_id
            ORDER BY event_ts, event_id
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS session_no
    FROM session_boundaries
)
SELECT
    *,
    MIN(event_ts) OVER (PARTITION BY user_id, session_no) AS session_start,
    MAX(event_ts) OVER (PARTITION BY user_id, session_no) AS session_end
FROM numbered_events;

SELECT DISTINCT
    user_id,
    session_no,
    session_start,
    session_end
FROM sessionized_events
ORDER BY user_id, session_no;
*/

-- Optimization notes:
-- * LAG avoids a self-join to find the previous event.
-- * The cumulative SUM converts boundary flags into session numbers.
-- * The explicit ROWS frame and event_id tie-breaker make the result stable.
-- * For production-scale data, process a sufficient lookback window or persist
--   per-user session state; a daily batch boundary can split a real session.

-- =============================================================================
-- Q3. Daily active users (DAU)
-- Return one row per UTC event date with distinct active users.
-- Use the deduplicated event view so replayed deliveries do not inflate counts.
-- =============================================================================

-- Optimized solution (requires the Q2 views):
 /*
SELECT
    event_ts::DATE AS activity_date,
    COUNT(DISTINCT user_id) AS daily_active_users
FROM deduped_events
GROUP BY event_ts::DATE
ORDER BY activity_date;
*/

-- Expected spot checks: 2026-10-15 has 4 active users; 2026-10-16 has 1.
-- For a large partitioned fact table, filter event_ts with a half-open range
-- (>= start AND < next_start) rather than applying DATE() in the WHERE clause.

-- =============================================================================
-- Q4. Ordered conversion funnel by session
-- Count sessions reaching page_view -> product_view -> add_to_cart -> purchase.
-- Each step must occur at or after the previous step in the same session.
-- =============================================================================

-- Optimized solution (LATERAL lookups enforce step order):
 /*
WITH sessions AS (
    SELECT DISTINCT user_id, session_no
    FROM sessionized_events
)
SELECT
    COUNT(*) FILTER (WHERE p.page_at IS NOT NULL) AS sessions_with_page_view,
    COUNT(*) FILTER (WHERE pr.product_at IS NOT NULL) AS sessions_with_product_view,
    COUNT(*) FILTER (WHERE c.cart_at IS NOT NULL) AS sessions_with_add_to_cart,
    COUNT(*) FILTER (WHERE pu.purchase_at IS NOT NULL) AS completed_funnels
FROM sessions AS s
LEFT JOIN LATERAL (
    SELECT MIN(e.event_ts) AS page_at
    FROM sessionized_events AS e
    WHERE e.user_id = s.user_id
      AND e.session_no = s.session_no
      AND e.event_type = 'page_view'
) AS p ON TRUE
LEFT JOIN LATERAL (
    SELECT MIN(e.event_ts) AS product_at
    FROM sessionized_events AS e
    WHERE e.user_id = s.user_id
      AND e.session_no = s.session_no
      AND e.event_type = 'product_view'
      AND e.event_ts >= p.page_at
) AS pr ON p.page_at IS NOT NULL
LEFT JOIN LATERAL (
    SELECT MIN(e.event_ts) AS cart_at
    FROM sessionized_events AS e
    WHERE e.user_id = s.user_id
      AND e.session_no = s.session_no
      AND e.event_type = 'add_to_cart'
      AND e.event_ts >= pr.product_at
) AS c ON pr.product_at IS NOT NULL
LEFT JOIN LATERAL (
    SELECT MIN(e.event_ts) AS purchase_at
    FROM sessionized_events AS e
    WHERE e.user_id = s.user_id
      AND e.session_no = s.session_no
      AND e.event_type = 'purchase'
      AND e.event_ts >= c.cart_at
) AS pu ON c.cart_at IS NOT NULL;
*/

-- Expected spot check: completed_funnels = 2.
-- A simple COUNT(DISTINCT user_id) per event_type is not a funnel: it ignores
-- ordering and can combine events from separate sessions.

-- =============================================================================
-- Q5. Session-level purchase count and revenue
-- Return only sessions containing a purchase, with purchase count and revenue.
-- Rank the highest-value sessions first.
-- =============================================================================

-- Optimized solution:
 /*
SELECT
    user_id,
    session_no,
    MIN(session_start) AS session_start,
    COUNT(*) FILTER (WHERE event_type = 'purchase') AS purchase_count,
    COALESCE(
        SUM(event_value) FILTER (WHERE event_type = 'purchase'),
        0
    ) AS session_revenue
FROM sessionized_events
GROUP BY user_id, session_no
HAVING COUNT(*) FILTER (WHERE event_type = 'purchase') > 0
ORDER BY session_revenue DESC, user_id, session_no;
*/

-- Expected spot check: total purchase revenue across all sessions = 5,096.00.
-- FILTER keeps purchase-only aggregation explicit and avoids multiplying
-- revenue through joins to one-to-many event detail.

-- =============================================================================
-- Q6. Detect late-arriving events
-- Find events ingested on 2026-10-16 whose event time is more than one hour
-- earlier than ingestion time. Report the delay in minutes.
-- =============================================================================

-- Optimized solution:
 /*
SELECT
    event_id,
    user_id,
    event_type,
    event_ts,
    ingested_at,
    ROUND(
        (EXTRACT(EPOCH FROM (ingested_at - event_ts)) / 60)::NUMERIC,
        1
    ) AS arrival_delay_minutes
FROM web_events
WHERE ingested_at >= TIMESTAMPTZ '2026-10-16 00:00:00+00'
  AND ingested_at <  TIMESTAMPTZ '2026-10-17 00:00:00+00'
  AND event_ts < ingested_at - INTERVAL '1 hour'
ORDER BY ingested_at;
*/

-- Expected spot check: evt-302 is the late-arriving event.
-- Filter the ingestion timestamp with a half-open range so an index or
-- ingestion-date partition can be considered before evaluating the delay.

-- =============================================================================
-- Q7. First-touch campaign performance by session
-- Attribute each session to its earliest non-NULL campaign_id. Sessions with no
-- campaign touch are 'unattributed'. Calculate session conversion and revenue.
-- =============================================================================

-- Optimized solution:
 /*
WITH first_campaign_touch AS (
    SELECT DISTINCT ON (user_id, session_no)
        user_id,
        session_no,
        campaign_id
    FROM sessionized_events
    WHERE campaign_id IS NOT NULL
    ORDER BY user_id, session_no, event_ts, ingest_id
),
session_metrics AS (
    SELECT
        user_id,
        session_no,
        BOOL_OR(event_type = 'purchase') AS converted,
        COALESCE(
            SUM(event_value) FILTER (WHERE event_type = 'purchase'),
            0
        ) AS revenue
    FROM sessionized_events
    GROUP BY user_id, session_no
)
SELECT
    COALESCE(c.campaign_id, 'unattributed') AS campaign_id,
    COUNT(*) AS sessions,
    COUNT(*) FILTER (WHERE m.converted) AS converted_sessions,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE m.converted) / NULLIF(COUNT(*), 0),
        2
    ) AS session_conversion_pct,
    SUM(m.revenue) AS attributed_revenue
FROM session_metrics AS m
LEFT JOIN first_campaign_touch AS c
    ON c.user_id = m.user_id
   AND c.session_no = m.session_no
GROUP BY COALESCE(c.campaign_id, 'unattributed')
ORDER BY attributed_revenue DESC, campaign_id;
*/

-- Why this works:
-- DISTINCT ON with a matching ORDER BY selects one deterministic first touch.
-- The session metrics are aggregated before the campaign join, preventing
-- event-level joins from duplicating session revenue.

-- =============================================================================
-- Q8. 1-to-7-day returning users and query-plan tuning
-- Count users with another session at least 24 hours, but less than 8 days,
-- after their first-ever session start.
-- Then inspect candidate indexes for user-time and ingestion-time workloads.
-- =============================================================================

-- Returning-user solution:
 /*
WITH session_starts AS (
    SELECT DISTINCT user_id, session_no, session_start
    FROM sessionized_events
),
first_sessions AS (
    SELECT
        user_id,
        MIN(session_start) AS first_session_start
    FROM session_starts
    GROUP BY user_id
)
SELECT COUNT(*) AS users_returning_in_1_to_7_days
FROM first_sessions AS f
WHERE EXISTS (
    SELECT 1
    FROM session_starts AS s
    WHERE s.user_id = f.user_id
      AND s.session_start >= f.first_session_start + INTERVAL '1 day'
      AND s.session_start <  f.first_session_start + INTERVAL '8 days'
);
*/

-- Expected spot check: users_returning_in_1_to_7_days = 1 (user 101).

-- Candidate indexes to benchmark on a realistically sized dataset:
 /*
CREATE INDEX IF NOT EXISTS idx_web_events_event_dedup
    ON web_events (event_id, ingested_at DESC, ingest_id DESC);

CREATE INDEX IF NOT EXISTS idx_web_events_user_event_time
    ON web_events (user_id, event_ts)
    INCLUDE (event_id, event_type, ingested_at, ingest_id);

CREATE INDEX IF NOT EXISTS idx_web_events_ingested_at
    ON web_events (ingested_at);

ANALYZE web_events;

EXPLAIN (ANALYZE, BUFFERS)
SELECT event_id, event_type, event_ts, ingested_at
FROM (
    SELECT
        event_id,
        event_type,
        event_ts,
        ingested_at,
        ROW_NUMBER() OVER (
            PARTITION BY event_id
            ORDER BY ingested_at DESC, ingest_id DESC
        ) AS row_num
    FROM web_events
    WHERE user_id = 101
      AND event_ts >= TIMESTAMPTZ '2026-10-15 00:00:00+00'
      AND event_ts <  TIMESTAMPTZ '2026-10-17 00:00:00+00'
) AS ranked
WHERE row_num = 1;

EXPLAIN (ANALYZE, BUFFERS)
SELECT event_id, user_id, event_type, event_ts
FROM web_events
WHERE ingested_at >= TIMESTAMPTZ '2026-10-16 00:00:00+00'
  AND ingested_at <  TIMESTAMPTZ '2026-10-17 00:00:00+00'
ORDER BY ingested_at;
*/

-- Performance checklist:
-- 1. Keep event-time and ingestion-time semantics separate. Event time is used
--    for sessions and business reporting; ingestion time is used for watermarks
--    and incremental extraction.
-- 2. Use half-open timestamp ranges to avoid boundary overlap and preserve
--    index/partition pruning opportunities.
-- 3. Sessionization requires ordering by user_id and event_ts. At scale, sort
--    and shuffle cost can dominate; distribute work by user and carry session
--    state across processing windows.
-- 4. Indexes improve selected access paths but add storage and write overhead.
--    On this tiny TEMP dataset PostgreSQL may correctly choose sequential scans.
-- 5. Compare EXPLAIN (ANALYZE, BUFFERS) before and after each index on production-
--    shaped data. Do not assume an index is beneficial from its definition alone.
-- 6. For append-heavy clickstream warehouses, consider date partitioning by
--    event_ts, late-arrival correction windows, and periodic deduplication.

-- =============================================================================
-- Interview follow-ups
-- 1. How would you handle a late event that bridges two previously separate
--    sessions? Would you recompute only one user, a time range, or a full day?
-- 2. How would the session key remain stable when new events arrive out of order?
-- 3. How would you implement a 30-minute inactivity rule in Structured Streaming?
-- 4. What changes if event_id is only unique within a source system?
-- 5. How would you validate funnel correctness when events can be missing,
--    duplicated, or delivered out of order?
-- =============================================================================
