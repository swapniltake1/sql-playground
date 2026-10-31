-- PostgreSQL 14+
-- Topic: Time-zone-aware event reporting across daylight-saving transitions.
-- Run in one PostgreSQL session. All tables are temporary and isolated.
-- Session output is fixed to UTC so displayed instants are reproducible.

SET TIME ZONE 'UTC';

-- ============================================================
-- SETUP: tenant time zones and meter events
-- ============================================================

CREATE TEMP TABLE tz_tenant (
    tenant_id   text PRIMARY KEY,
    tenant_name text NOT NULL,
    time_zone   text NOT NULL
);

CREATE TEMP TABLE tz_meter_event (
    event_id    bigint PRIMARY KEY,
    tenant_id   text NOT NULL REFERENCES tz_tenant(tenant_id),
    meter_id    text NOT NULL,
    event_ts    timestamptz NOT NULL, -- the absolute instant, not a local wall clock
    ingested_at timestamptz NOT NULL,
    kwh         numeric(12,3) NOT NULL CHECK (kwh >= 0)
);

INSERT INTO tz_tenant (tenant_id, tenant_name, time_zone) VALUES
('TENANT_NY',  'New York utility', 'America/New_York'),
('TENANT_LON', 'London utility',   'Europe/London'),
('TENANT_IN',  'Pune utility',     'Asia/Kolkata');

-- Explicit offsets preserve the two distinct instants that share a local
-- 01:15 wall-clock value when daylight saving time ends.
INSERT INTO tz_meter_event
    (event_id, tenant_id, meter_id, event_ts, ingested_at, kwh)
VALUES
-- New York: DST ends on 2026-11-01. The 01:15 hour occurs twice.
(1001, 'TENANT_NY', 'NY-MTR-01', TIMESTAMPTZ '2026-11-01 00:30:00-04',
                              TIMESTAMPTZ '2026-11-01 04:31:00+00', 1.200),
(1002, 'TENANT_NY', 'NY-MTR-01', TIMESTAMPTZ '2026-11-01 01:15:00-04',
                              TIMESTAMPTZ '2026-11-01 05:16:00+00', 1.300),
(1003, 'TENANT_NY', 'NY-MTR-01', TIMESTAMPTZ '2026-11-01 01:15:00-05',
                              TIMESTAMPTZ '2026-11-01 06:16:00+00', 1.400),
(1004, 'TENANT_NY', 'NY-MTR-01', TIMESTAMPTZ '2026-11-01 02:15:00-05',
                              TIMESTAMPTZ '2026-11-01 07:16:00+00', 1.100),

-- New York: DST starts on 2026-03-08. Local time jumps from 01:59 to 03:00.
(1005, 'TENANT_NY', 'NY-MTR-02', TIMESTAMPTZ '2026-03-08 01:30:00-05',
                              TIMESTAMPTZ '2026-03-08 06:31:00+00', 0.800),
(1006, 'TENANT_NY', 'NY-MTR-02', TIMESTAMPTZ '2026-03-08 03:30:00-04',
                              TIMESTAMPTZ '2026-03-08 07:31:00+00', 0.900),

-- London: DST ends on 2026-10-25, independently of the US transition date.
(2001, 'TENANT_LON', 'LON-MTR-01', TIMESTAMPTZ '2026-10-25 00:30:00+01',
                                TIMESTAMPTZ '2026-10-24 23:31:00+00', 2.100),
(2002, 'TENANT_LON', 'LON-MTR-01', TIMESTAMPTZ '2026-10-25 01:15:00+01',
                                TIMESTAMPTZ '2026-10-25 00:16:00+00', 2.200),
(2003, 'TENANT_LON', 'LON-MTR-01', TIMESTAMPTZ '2026-10-25 01:15:00+00',
                                TIMESTAMPTZ '2026-10-25 01:16:00+00', 2.300),
(2004, 'TENANT_LON', 'LON-MTR-01', TIMESTAMPTZ '2026-10-25 02:15:00+00',
                                TIMESTAMPTZ '2026-10-25 02:16:00+00', 2.400),

-- India has no DST transition; its offset remains +05:30.
(3001, 'TENANT_IN', 'PUN-MTR-01', TIMESTAMPTZ '2026-11-01 01:00:00+05:30',
                              TIMESTAMPTZ '2026-10-31 19:31:00+00', 0.500),
(3002, 'TENANT_IN', 'PUN-MTR-01', TIMESTAMPTZ '2026-11-01 02:00:00+05:30',
                              TIMESTAMPTZ '2026-10-31 20:31:00+00', 0.600);

-- Candidate access path for tenant-scoped event-time filtering.
-- On this tiny sample PostgreSQL may correctly prefer a sequential scan.
CREATE INDEX tz_meter_event_tenant_ts_idx
    ON tz_meter_event (tenant_id, event_ts)
    INCLUDE (meter_id, kwh);

ANALYZE tz_meter_event;

-- ============================================================
-- Q1. Convert event instants into each tenant's local date/time.
-- Problem: Do not lose the absolute instant when two local wall-clock
-- values look identical during the autumn DST transition.
-- ============================================================

-- Solution:
SELECT
    e.tenant_id,
    e.event_id,
    e.event_ts,
    e.event_ts AT TIME ZONE 'UTC' AS utc_wall_time,
    e.event_ts AT TIME ZONE t.time_zone AS tenant_local_time,
    (e.event_ts AT TIME ZONE t.time_zone)::date AS tenant_local_date,
    t.time_zone
FROM tz_meter_event e
JOIN tz_tenant t USING (tenant_id)
WHERE e.tenant_id = 'TENANT_NY'
  AND e.event_ts >= TIMESTAMPTZ '2026-11-01 00:00:00+00'
  AND e.event_ts <  TIMESTAMPTZ '2026-11-02 12:00:00+00'
ORDER BY e.event_ts;

-- Explanation: event_ts remains a unique instant. The local timestamp is
-- a presentation/reporting value and must not replace the original instant.


-- ============================================================
-- Q2. Aggregate consumption by tenant-local calendar day.
-- Problem: Produce the correct business date for tenants in different zones.
-- ============================================================

-- Solution:
SELECT
    e.tenant_id,
    (e.event_ts AT TIME ZONE t.time_zone)::date AS local_business_date,
    COUNT(*) AS event_count,
    SUM(e.kwh) AS total_kwh
FROM tz_meter_event e
JOIN tz_tenant t USING (tenant_id)
GROUP BY
    e.tenant_id,
    (e.event_ts AT TIME ZONE t.time_zone)::date
ORDER BY e.tenant_id, local_business_date;

-- Explanation: Convert the instant with the tenant's IANA time-zone name
-- before deriving the date. A direct event_ts::date uses the session zone.


-- ============================================================
-- Q3. Filter one tenant-local business date without wrapping the
-- indexed event_ts column in a function.
-- Problem: Return New York events for local date 2026-11-01.
-- ============================================================

-- Optimized solution: calculate the two local-midnight boundaries once.
WITH bounds AS (
    SELECT
        tenant_id,
        (DATE '2026-11-01'::timestamp AT TIME ZONE time_zone) AS utc_start,
        (DATE '2026-11-02'::timestamp AT TIME ZONE time_zone) AS utc_end
    FROM tz_tenant
    WHERE tenant_id = 'TENANT_NY'
)
SELECT
    e.event_id,
    e.event_ts,
    e.kwh
FROM bounds b
JOIN tz_meter_event e
  ON e.tenant_id = b.tenant_id
 AND e.event_ts >= b.utc_start
 AND e.event_ts <  b.utc_end
ORDER BY e.event_ts;

-- Expected: four rows. The UTC interval is 2026-11-01 04:00 through
-- 2026-11-02 05:00, a 25-hour local business day.


-- ============================================================
-- Q4. Keep repeated local hours separate.
-- Problem: A local 01:00 bucket can represent two different UTC hours.
-- ============================================================

-- Solution: aggregate on an explicit UTC-hour key, then add the local label.
WITH hourly AS (
    SELECT
        e.tenant_id,
        date_trunc('hour', e.event_ts AT TIME ZONE 'UTC') AS utc_hour,
        date_trunc('hour', e.event_ts AT TIME ZONE t.time_zone) AS local_hour,
        COUNT(*) AS event_count,
        SUM(e.kwh) AS total_kwh
    FROM tz_meter_event e
    JOIN tz_tenant t USING (tenant_id)
    WHERE e.tenant_id IN ('TENANT_NY', 'TENANT_LON')
    GROUP BY
        e.tenant_id,
        date_trunc('hour', e.event_ts AT TIME ZONE 'UTC'),
        date_trunc('hour', e.event_ts AT TIME ZONE t.time_zone)
)
SELECT
    tenant_id,
    utc_hour,
    local_hour,
    event_count,
    total_kwh
FROM hourly
WHERE (tenant_id = 'TENANT_NY'  AND local_hour::date = DATE '2026-11-01')
   OR (tenant_id = 'TENANT_LON' AND local_hour::date = DATE '2026-10-25')
ORDER BY tenant_id, utc_hour;

-- Explanation: grouping only by local_hour would merge both occurrences
-- of 01:00. Keep the UTC bucket as the key and local_hour as a display label.


-- ============================================================
-- Q5. Build a complete local hourly calendar for the New York fall-back day.
-- Problem: Return all elapsed UTC hours, including hours with no events.
-- ============================================================

-- Solution:
WITH tenant_day AS (
    SELECT
        tenant_id,
        time_zone,
        (DATE '2026-11-01'::timestamp AT TIME ZONE time_zone) AS utc_start,
        (DATE '2026-11-02'::timestamp AT TIME ZONE time_zone) AS utc_end
    FROM tz_tenant
    WHERE tenant_id = 'TENANT_NY'
),
hour_spine AS (
    SELECT
        d.tenant_id,
        d.time_zone,
        h.utc_hour
    FROM tenant_day d
    CROSS JOIN LATERAL generate_series(
        d.utc_start,
        d.utc_end - INTERVAL '1 hour',
        INTERVAL '1 hour'
    ) AS h(utc_hour)
),
hourly_events AS (
    SELECT
        e.tenant_id,
        date_trunc('hour', e.event_ts AT TIME ZONE 'UTC')
            AT TIME ZONE 'UTC' AS utc_hour,
        COUNT(*) AS event_count,
        SUM(e.kwh) AS total_kwh
    FROM tenant_day d
    JOIN tz_meter_event e
      ON e.tenant_id = d.tenant_id
     AND e.event_ts >= d.utc_start
     AND e.event_ts <  d.utc_end
    GROUP BY
        e.tenant_id,
        date_trunc('hour', e.event_ts AT TIME ZONE 'UTC')
            AT TIME ZONE 'UTC'
)
SELECT
    s.tenant_id,
    s.utc_hour AT TIME ZONE 'UTC' AS utc_hour,
    s.utc_hour AT TIME ZONE s.time_zone AS local_hour,
    COALESCE(h.event_count, 0) AS event_count,
    COALESCE(h.total_kwh, 0::numeric) AS total_kwh
FROM hour_spine s
LEFT JOIN hourly_events h
  ON h.tenant_id = s.tenant_id
 AND h.utc_hour = s.utc_hour
ORDER BY s.utc_hour;

-- Expected: 25 rows. Two rows display local 01:00, but their UTC hours differ.


-- ============================================================
-- Q6. Calculate elapsed hours in local calendar days across DST changes.
-- Problem: Demonstrate 23-hour and 25-hour days without hard-coding them.
-- ============================================================

-- Solution:
WITH sample_days (tenant_id, local_day) AS (
    VALUES
        ('TENANT_NY',  DATE '2026-03-08'), -- spring forward
        ('TENANT_NY',  DATE '2026-11-01'), -- fall back
        ('TENANT_LON', DATE '2026-10-25')  -- fall back in the UK
),
day_bounds AS (
    SELECT
        d.tenant_id,
        d.local_day,
        t.time_zone,
        d.local_day::timestamp AT TIME ZONE t.time_zone AS utc_start,
        (d.local_day + 1)::timestamp AT TIME ZONE t.time_zone AS utc_end
    FROM sample_days d
    JOIN tz_tenant t USING (tenant_id)
)
SELECT
    tenant_id,
    local_day,
    time_zone,
    utc_start,
    utc_end,
    EXTRACT(EPOCH FROM (utc_end - utc_start)) / 3600 AS elapsed_hours
FROM day_bounds
ORDER BY tenant_id, local_day;

-- Expected elapsed_hours: New York 2026-03-08 = 23;
-- New York 2026-11-01 = 25; London 2026-10-25 = 25.


-- ============================================================
-- Q7. Zero-fill daily tenant reporting over a date range.
-- Problem: Include dates with no events and respect each tenant's zone.
-- ============================================================

-- Solution:
WITH selected_tenants AS (
    SELECT tenant_id, time_zone
    FROM tz_tenant
    WHERE tenant_id IN ('TENANT_NY', 'TENANT_LON', 'TENANT_IN')
),
date_spine AS (
    SELECT
        t.tenant_id,
        t.time_zone,
        d.local_day::date AS local_day
    FROM selected_tenants t
    CROSS JOIN LATERAL generate_series(
        DATE '2026-10-24',
        DATE '2026-11-02',
        INTERVAL '1 day'
    ) AS d(local_day)
),
daily_events AS (
    SELECT
        e.tenant_id,
        (e.event_ts AT TIME ZONE t.time_zone)::date AS local_day,
        COUNT(*) AS event_count,
        SUM(e.kwh) AS total_kwh
    FROM tz_meter_event e
    JOIN selected_tenants t USING (tenant_id)
    GROUP BY
        e.tenant_id,
        (e.event_ts AT TIME ZONE t.time_zone)::date
)
SELECT
    s.tenant_id,
    s.local_day,
    COALESCE(d.event_count, 0) AS event_count,
    COALESCE(d.total_kwh, 0::numeric) AS total_kwh
FROM date_spine s
LEFT JOIN daily_events d
  ON d.tenant_id = s.tenant_id
 AND d.local_day = s.local_day
ORDER BY s.tenant_id, s.local_day;

-- Optimization: aggregate the event fact once, then join it to the small
-- date spine. For large ranges, persist a calendar dimension instead of
-- generating the same dates for every report.


-- ============================================================
-- Q8. Detect ambiguous local wall-clock hours during fall-back.
-- Problem: Find local hours that map to more than one distinct UTC hour.
-- ============================================================

-- Solution:
WITH event_hours AS (
    SELECT
        e.tenant_id,
        (e.event_ts AT TIME ZONE t.time_zone)::date AS local_day,
        date_trunc('hour', e.event_ts AT TIME ZONE t.time_zone) AS local_hour,
        date_trunc('hour', e.event_ts AT TIME ZONE 'UTC') AS utc_hour
    FROM tz_meter_event e
    JOIN tz_tenant t USING (tenant_id)
)
SELECT
    tenant_id,
    local_day,
    local_hour,
    COUNT(DISTINCT utc_hour) AS distinct_utc_hours
FROM event_hours
GROUP BY tenant_id, local_day, local_hour
HAVING COUNT(DISTINCT utc_hour) > 1
ORDER BY tenant_id, local_day, local_hour;

-- Expected: New York 2026-11-01 01:00 and London 2026-10-25 01:00.
-- These are not duplicate events: they are two real elapsed hours sharing
-- the same local wall-clock label.


-- ============================================================
-- ASSERTIONS: protect the most important DST assumptions.
-- ============================================================

DO $$
DECLARE
    ny_fall_hours numeric;
    ny_spring_hours numeric;
    london_fall_hours numeric;
    ny_fall_events integer;
BEGIN
    SELECT
        EXTRACT(EPOCH FROM (
            (DATE '2026-11-02'::timestamp AT TIME ZONE time_zone)
            - (DATE '2026-11-01'::timestamp AT TIME ZONE time_zone)
        )) / 3600
    INTO ny_fall_hours
    FROM tz_tenant
    WHERE tenant_id = 'TENANT_NY';

    SELECT
        EXTRACT(EPOCH FROM (
            (DATE '2026-03-09'::timestamp AT TIME ZONE time_zone)
            - (DATE '2026-03-08'::timestamp AT TIME ZONE time_zone)
        )) / 3600
    INTO ny_spring_hours
    FROM tz_tenant
    WHERE tenant_id = 'TENANT_NY';

    SELECT
        EXTRACT(EPOCH FROM (
            (DATE '2026-10-26'::timestamp AT TIME ZONE time_zone)
            - (DATE '2026-10-25'::timestamp AT TIME ZONE time_zone)
        )) / 3600
    INTO london_fall_hours
    FROM tz_tenant
    WHERE tenant_id = 'TENANT_LON';

    SELECT COUNT(*)
    INTO ny_fall_events
    FROM tz_meter_event
    WHERE tenant_id = 'TENANT_NY'
      AND event_ts >= TIMESTAMPTZ '2026-11-01 04:00:00+00'
      AND event_ts <  TIMESTAMPTZ '2026-11-02 05:00:00+00';

    IF ny_fall_hours <> 25
       OR ny_spring_hours <> 23
       OR london_fall_hours <> 25
       OR ny_fall_events <> 4 THEN
        RAISE EXCEPTION
            'DST assertion failed: NY fall %, NY spring %, London fall %, NY events %',
            ny_fall_hours, ny_spring_hours, london_fall_hours, ny_fall_events;
    END IF;

    RAISE NOTICE
        'DST assertions passed: NY fall=25h, NY spring=23h, London fall=25h, NY fall events=4';
END $$;

-- ============================================================
-- PERFORMANCE NOTES
-- ============================================================
-- 1. Keep event_ts as TIMESTAMPTZ and store the tenant's IANA time-zone name.
--    Do not persist only a local timestamp; it can be ambiguous at fall-back.
-- 2. For a tenant-local date filter, convert local midnight boundaries to
--    TIMESTAMPTZ once, then filter event_ts with >= and <. This is SARGable.
-- 3. A B-tree index on (tenant_id, event_ts) supports tenant-scoped time ranges.
--    INCLUDE columns can enable index-only scans when visibility permits.
-- 4. Avoid WHERE (event_ts AT TIME ZONE time_zone)::date = ... on a large fact
--    table unless you have a matching expression index or a stored reporting key.
-- 5. For partitioning, prefer UTC event-time ranges. A tenant-local day can be
--    23, 24, or 25 elapsed hours and tenants do not share one local boundary.
-- 6. Keep both UTC bucket keys and local display labels in hourly aggregates.
-- 7. Benchmark with representative volume using:
--    EXPLAIN (ANALYZE, BUFFERS)
--    and compare index scans, rows removed by filter, and buffer reads.
-- 8. Time-zone rules can change by legislation. Keep PostgreSQL tzdata current
--    and treat the IANA zone name as configuration, not a fixed numeric offset.

-- Interview follow-ups:
-- - Why is TIMESTAMPTZ preferable to storing a local TIMESTAMP for event time?
-- - How would you build a multi-tenant hourly SLA dashboard across DST?
-- - Why should local-date predicates be converted into UTC range boundaries?
-- - What changes when a tenant changes its configured time zone?
-- - Would you partition by ingestion time or event time for late-arriving data?
-- - How would you test reports after an operating system / tzdata update?
