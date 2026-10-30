-- ============================================================================
-- Pipeline SLA Observability, Retry Analysis & Data Freshness
-- PostgreSQL 14+
--
-- Scenario:
-- A data platform runs several scheduled ingestion pipelines. Each logical run
-- can have multiple attempts. Operations needs to distinguish final outcomes
-- from failed retries, measure start/execution SLAs, detect stale source
-- watermarks, and identify suspicious successful runs with no output.
--
-- Run this file independently. It creates an isolated practice schema in the
-- current database. The sample timestamps are intentionally fixed so results
-- are reproducible.
-- ============================================================================

DROP TABLE IF EXISTS de_pipeline_run_attempts;
DROP TABLE IF EXISTS de_pipeline_sla;

CREATE TABLE de_pipeline_sla (
    pipeline_name              text PRIMARY KEY,
    max_start_delay_minutes    integer NOT NULL CHECK (max_start_delay_minutes >= 0),
    max_duration_minutes       integer NOT NULL CHECK (max_duration_minutes > 0),
    max_freshness_lag_minutes  integer NOT NULL CHECK (max_freshness_lag_minutes > 0),
    min_expected_rows          bigint NOT NULL CHECK (min_expected_rows >= 0)
);

CREATE TABLE de_pipeline_run_attempts (
    attempt_id          bigint PRIMARY KEY,
    logical_run_id      text NOT NULL,
    pipeline_name       text NOT NULL REFERENCES de_pipeline_sla(pipeline_name),
    attempt_no          integer NOT NULL CHECK (attempt_no > 0),
    scheduled_at        timestamptz NOT NULL,
    started_at          timestamptz NOT NULL,
    ended_at            timestamptz NOT NULL,
    status              text NOT NULL CHECK (status IN ('SUCCEEDED', 'FAILED')),
    source_watermark_at timestamptz,
    rows_written        bigint NOT NULL CHECK (rows_written >= 0),
    error_code          text,
    CHECK (ended_at >= started_at),
    UNIQUE (logical_run_id, attempt_no)
);

INSERT INTO de_pipeline_sla
    (pipeline_name, max_start_delay_minutes, max_duration_minutes,
     max_freshness_lag_minutes, min_expected_rows)
VALUES
    ('orders_ingest',   5, 12, 20, 100),
    ('payments_ingest', 3, 10, 15,  50),
    ('customer_dim',    5,  8, 30,  10);

INSERT INTO de_pipeline_run_attempts
    (attempt_id, logical_run_id, pipeline_name, attempt_no,
     scheduled_at, started_at, ended_at, status,
     source_watermark_at, rows_written, error_code)
VALUES
    -- Logical run O-100: first attempt fails, retry succeeds.
    (1, 'O-100', 'orders_ingest', 1,
     '2026-10-31 00:00+00', '2026-10-31 00:02+00', '2026-10-31 00:04+00',
     'FAILED', '2026-10-30 23:55+00', 0, 'SOURCE_TIMEOUT'),
    (2, 'O-100', 'orders_ingest', 2,
     '2026-10-31 00:00+00', '2026-10-31 00:08+00', '2026-10-31 00:18+00',
     'SUCCEEDED', '2026-10-31 00:05+00', 1200, NULL),

    (3, 'P-100', 'payments_ingest', 1,
     '2026-10-31 00:00+00', '2026-10-31 00:01+00', '2026-10-31 00:07+00',
     'SUCCEEDED', '2026-10-31 00:06+00', 200, NULL),
    (4, 'C-100', 'customer_dim', 1,
     '2026-10-31 00:00+00', '2026-10-31 00:10+00', '2026-10-31 00:13+00',
     'SUCCEEDED', '2026-10-30 23:59+00', 100, NULL),

    (5, 'O-101', 'orders_ingest', 1,
     '2026-10-31 01:00+00', '2026-10-31 01:04+00', '2026-10-31 01:20+00',
     'SUCCEEDED', '2026-10-31 00:50+00', 1300, NULL),

    -- Logical run P-101 exhausts both attempts and remains failed.
    (6, 'P-101', 'payments_ingest', 1,
     '2026-10-31 01:00+00', '2026-10-31 01:01+00', '2026-10-31 01:05+00',
     'FAILED', '2026-10-31 01:00+00', 0, 'API_THROTTLED'),
    (7, 'P-101', 'payments_ingest', 2,
     '2026-10-31 01:00+00', '2026-10-31 01:07+00', '2026-10-31 01:10+00',
     'FAILED', '2026-10-31 01:00+00', 0, 'API_THROTTLED'),

    (8, 'C-101', 'customer_dim', 1,
     '2026-10-31 01:00+00', '2026-10-31 01:01+00', '2026-10-31 01:04+00',
     'SUCCEEDED', '2026-10-31 00:58+00', 102, NULL),

    -- O-102 succeeds technically but writes zero rows: a business anomaly.
    (9, 'O-102', 'orders_ingest', 1,
     '2026-10-31 02:00+00', '2026-10-31 02:00+00', '2026-10-31 02:06+00',
     'SUCCEEDED', '2026-10-31 01:59+00', 0, NULL),
    (10, 'P-102', 'payments_ingest', 1,
     '2026-10-31 02:00+00', '2026-10-31 02:09+00', '2026-10-31 02:30+00',
     'SUCCEEDED', '2026-10-31 02:01+00', 220, NULL),
    (11, 'C-102', 'customer_dim', 1,
     '2026-10-31 02:00+00', '2026-10-31 02:00+00', '2026-10-31 02:02+00',
     'SUCCEEDED', '2026-10-31 01:55+00', 103, NULL);

-- ============================================================================
-- Q1. What is the final outcome and latest attempt for every logical run?
-- Problem: Do not count an earlier failed attempt as a failed logical run when
-- a later retry succeeded.
-- Optimized solution: Rank only within each logical run and keep rn = 1.
-- ============================================================================

WITH ranked_attempts AS (
    SELECT
        a.*,
        ROW_NUMBER() OVER (
            PARTITION BY logical_run_id
            ORDER BY attempt_no DESC, ended_at DESC, attempt_id DESC
        ) AS rn
    FROM de_pipeline_run_attempts AS a
)
SELECT
    logical_run_id,
    pipeline_name,
    attempt_no AS final_attempt_no,
    status AS final_status,
    rows_written,
    error_code
FROM ranked_attempts
WHERE rn = 1
ORDER BY pipeline_name, logical_run_id;

-- ============================================================================
-- Q2. Which logical runs recovered after one or more failed attempts?
-- Problem: Quantify retry recovery without treating attempts as separate runs.
-- Optimized solution: Aggregate once at logical_run_id grain.
-- Expected: O-100 recovered; P-101 did not.
-- ============================================================================

WITH attempt_summary AS (
    SELECT
        logical_run_id,
        pipeline_name,
        COUNT(*) AS attempt_count,
        COUNT(*) FILTER (WHERE status = 'FAILED') AS failed_attempts,
        MAX(attempt_no) AS final_attempt_no,
        (ARRAY_AGG(status ORDER BY attempt_no DESC))[1] AS final_status
    FROM de_pipeline_run_attempts
    GROUP BY logical_run_id, pipeline_name
)
SELECT
    logical_run_id,
    pipeline_name,
    attempt_count,
    failed_attempts,
    final_status,
    (failed_attempts > 0 AND final_status = 'SUCCEEDED') AS recovered_after_retry
FROM attempt_summary
WHERE attempt_count > 1
ORDER BY logical_run_id;

-- ============================================================================
-- Q3. Which latest attempts breached start-delay or execution-duration SLAs?
-- Problem: Separate queue/scheduler delay from actual processing time.
-- Optimized solution: Filter to the latest attempt before joining the small SLA
-- dimension; calculate durations from timestamps without wrapping filter keys.
-- ============================================================================

WITH latest_attempt AS (
    SELECT DISTINCT ON (logical_run_id)
        logical_run_id, pipeline_name, scheduled_at, started_at, ended_at, status
    FROM de_pipeline_run_attempts
    ORDER BY logical_run_id, attempt_no DESC, ended_at DESC
),
measured AS (
    SELECT
        r.*,
        s.max_start_delay_minutes,
        s.max_duration_minutes,
        ROUND(EXTRACT(EPOCH FROM (r.started_at - r.scheduled_at)) / 60.0, 2)
            AS start_delay_minutes,
        ROUND(EXTRACT(EPOCH FROM (r.ended_at - r.started_at)) / 60.0, 2)
            AS duration_minutes
    FROM latest_attempt AS r
    JOIN de_pipeline_sla AS s USING (pipeline_name)
)
SELECT
    logical_run_id,
    pipeline_name,
    status,
    start_delay_minutes,
    duration_minutes,
    (start_delay_minutes > max_start_delay_minutes) AS start_sla_breached,
    (duration_minutes > max_duration_minutes) AS duration_sla_breached
FROM measured
WHERE start_delay_minutes > max_start_delay_minutes
   OR duration_minutes > max_duration_minutes
ORDER BY pipeline_name, logical_run_id;

-- ============================================================================
-- Q4. Which latest successful runs are serving stale source data?
-- Problem: A job can finish successfully while its source watermark is old.
-- Optimized solution: Compare the watermark to the run's completion time and
-- the pipeline-specific freshness threshold.
-- ============================================================================

WITH latest_success AS (
    SELECT DISTINCT ON (logical_run_id)
        logical_run_id, pipeline_name, ended_at, source_watermark_at, status
    FROM de_pipeline_run_attempts
    ORDER BY logical_run_id, attempt_no DESC, ended_at DESC
)
SELECT
    r.logical_run_id,
    r.pipeline_name,
    r.ended_at,
    r.source_watermark_at,
    ROUND(EXTRACT(EPOCH FROM (r.ended_at - r.source_watermark_at)) / 60.0, 2)
        AS freshness_lag_minutes,
    s.max_freshness_lag_minutes
FROM latest_success AS r
JOIN de_pipeline_sla AS s USING (pipeline_name)
WHERE r.status = 'SUCCEEDED'
  AND r.source_watermark_at IS NOT NULL
  AND r.ended_at - r.source_watermark_at
      > s.max_freshness_lag_minutes * INTERVAL '1 minute'
ORDER BY freshness_lag_minutes DESC;

-- ============================================================================
-- Q5. What is the final logical-run success rate for each pipeline?
-- Problem: Calculate reliability at logical-run grain, not attempt grain.
-- Optimized solution: Rank attempts once, then aggregate the reduced result.
-- ============================================================================

WITH latest_attempt AS (
    SELECT
        logical_run_id,
        pipeline_name,
        status,
        ROW_NUMBER() OVER (
            PARTITION BY logical_run_id
            ORDER BY attempt_no DESC, ended_at DESC
        ) AS rn
    FROM de_pipeline_run_attempts
),
pipeline_health AS (
    SELECT
        pipeline_name,
        COUNT(*) AS logical_runs,
        COUNT(*) FILTER (WHERE status = 'SUCCEEDED') AS successful_runs,
        COUNT(*) FILTER (WHERE status = 'FAILED') AS failed_runs
    FROM latest_attempt
    WHERE rn = 1
    GROUP BY pipeline_name
)
SELECT
    pipeline_name,
    logical_runs,
    successful_runs,
    failed_runs,
    ROUND(100.0 * successful_runs / NULLIF(logical_runs, 0), 2)
        AS success_rate_pct
FROM pipeline_health
ORDER BY success_rate_pct, pipeline_name;

-- ============================================================================
-- Q6. Which successful runs violated the minimum-output expectation?
-- Problem: Technical success is not sufficient when a pipeline unexpectedly
-- writes no rows or fewer rows than its agreed baseline.
-- Optimized solution: Join the latest logical-run result to the SLA config.
-- ============================================================================

WITH latest_attempt AS (
    SELECT DISTINCT ON (logical_run_id)
        logical_run_id, pipeline_name, status, rows_written, ended_at
    FROM de_pipeline_run_attempts
    ORDER BY logical_run_id, attempt_no DESC, ended_at DESC
)
SELECT
    r.logical_run_id,
    r.pipeline_name,
    r.rows_written,
    s.min_expected_rows,
    CASE
        WHEN r.rows_written = 0 THEN 'ZERO_ROW_SUCCESS'
        ELSE 'BELOW_EXPECTED_VOLUME'
    END AS anomaly_type
FROM latest_attempt AS r
JOIN de_pipeline_sla AS s USING (pipeline_name)
WHERE r.status = 'SUCCEEDED'
  AND r.rows_written < s.min_expected_rows
ORDER BY r.pipeline_name, r.logical_run_id;

-- ============================================================================
-- Q7. Which pipelines have the highest retry pressure?
-- Problem: Report retry volume and recovery rate by pipeline.
-- Optimized solution: Aggregate attempt counts per logical run first, then
-- summarize at pipeline grain to avoid multiplying logical-run metrics.
-- ============================================================================

WITH per_run AS (
    SELECT
        logical_run_id,
        pipeline_name,
        COUNT(*) AS attempts,
        COUNT(*) FILTER (WHERE status = 'FAILED') AS failed_attempts,
        (ARRAY_AGG(status ORDER BY attempt_no DESC))[1] AS final_status
    FROM de_pipeline_run_attempts
    GROUP BY logical_run_id, pipeline_name
)
SELECT
    pipeline_name,
    COUNT(*) AS logical_runs,
    SUM(GREATEST(attempts - 1, 0)) AS extra_attempts,
    COUNT(*) FILTER (WHERE failed_attempts > 0) AS runs_with_failures,
    COUNT(*) FILTER (
        WHERE failed_attempts > 0 AND final_status = 'SUCCEEDED'
    ) AS recovered_runs,
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE failed_attempts > 0 AND final_status = 'SUCCEEDED'
        ) / NULLIF(COUNT(*) FILTER (WHERE failed_attempts > 0), 0),
        2
    ) AS retry_recovery_pct
FROM per_run
GROUP BY pipeline_name
ORDER BY extra_attempts DESC, pipeline_name;

-- ============================================================================
-- Q8. Build a compact operations view for the most recent logical run per
-- pipeline, combining final status, runtime, freshness and row volume.
-- Problem: Provide one actionable record per pipeline for a monitoring board.
-- Optimized solution: Rank once, join one-row-per-pipeline SLA configuration.
-- ============================================================================

WITH latest_pipeline_run AS (
    SELECT
        a.*,
        ROW_NUMBER() OVER (
            PARTITION BY pipeline_name
            ORDER BY scheduled_at DESC, attempt_no DESC, ended_at DESC
        ) AS rn
    FROM de_pipeline_run_attempts AS a
)
SELECT
    r.pipeline_name,
    r.logical_run_id,
    r.status,
    r.ended_at,
    ROUND(EXTRACT(EPOCH FROM (r.ended_at - r.started_at)) / 60.0, 2)
        AS runtime_minutes,
    ROUND(EXTRACT(EPOCH FROM (r.ended_at - r.source_watermark_at)) / 60.0, 2)
        AS freshness_lag_minutes,
    r.rows_written,
    CASE
        WHEN r.status = 'FAILED' THEN 'INVESTIGATE_FAILURE'
        WHEN r.rows_written < s.min_expected_rows THEN 'CHECK_DATA_VOLUME'
        WHEN r.ended_at - r.source_watermark_at
             > s.max_freshness_lag_minutes * INTERVAL '1 minute'
            THEN 'CHECK_SOURCE_FRESHNESS'
        ELSE 'HEALTHY'
    END AS operations_action
FROM latest_pipeline_run AS r
JOIN de_pipeline_sla AS s USING (pipeline_name)
WHERE r.rn = 1
ORDER BY r.pipeline_name;

-- ============================================================================
-- Performance lab
--
-- Candidate indexes (benchmark against realistic volume; these are not
-- guaranteed wins for the tiny seed dataset):
--
-- CREATE INDEX ix_attempts_run_latest
--     ON de_pipeline_run_attempts (logical_run_id, attempt_no DESC, ended_at DESC)
--     INCLUDE (pipeline_name, status, rows_written, source_watermark_at);
--
-- CREATE INDEX ix_attempts_pipeline_schedule
--     ON de_pipeline_run_attempts (pipeline_name, scheduled_at DESC);
--
-- CREATE INDEX ix_attempts_failed
--     ON de_pipeline_run_attempts (pipeline_name, scheduled_at DESC)
--     WHERE status = 'FAILED';
--
-- EXPLAIN (ANALYZE, BUFFERS)
-- SELECT ...;
--
-- Notes:
-- 1. Keep one row per attempt and derive one row per logical run for reliability.
-- 2. Use deterministic tie-breakers in ROW_NUMBER()/DISTINCT ON.
-- 3. Persist SLA thresholds as data instead of scattering hard-coded CASE values.
-- 4. Store source watermarks separately from job completion timestamps; they
--    measure data freshness, not compute duration.
-- 5. For large histories, consider time partitioning by scheduled_at and
--    retention/rollup policies. Keep logical-run attempt groups queryable across
--    partition boundaries.
-- 6. Avoid indexing every metric column. Validate candidate indexes with
--    EXPLAIN (ANALYZE, BUFFERS) on representative data and write patterns.
--
-- Interview follow-ups:
-- - How would you model a run that is still RUNNING and has no ended_at?
-- - How do you avoid alert storms when retries are expected?
-- - How would you calculate p95 duration and freshness by pipeline/day?
-- - What changes when run history is partitioned by month?
-- - How would you reconcile orchestration metadata with source-system offsets?
-- ============================================================================
