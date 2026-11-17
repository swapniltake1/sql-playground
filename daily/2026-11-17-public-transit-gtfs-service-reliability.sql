/*
===============================================================================
PUBLIC TRANSIT GTFS + AVL + APC: SERVICE RELIABILITY & HEADWAY ANALYTICS
Date: 2026-11-17
Dialect: PostgreSQL 14+
Run: Execute this file in a disposable PostgreSQL database.

Scenario
--------
A city transit operator combines GTFS-like scheduled stop times with automatic
vehicle-location (AVL) events and automatic passenger-counting (APC) events.
The landing feeds contain replayed deliveries, a corrected timestamp, a voided
event, a missing timepoint, an orphan trip, and an impossible dwell interval.

Learning goals
--------------
- Canonicalize versioned event feeds without resurrecting voided events.
- Measure schedule adherence, headway regularity, dwell and running time.
- Find missed timepoints and quantify trip-level service coverage.
- Reconstruct passenger loads and flag APC quality exceptions.
- Evaluate vehicle-block recovery between consecutive trips.

All timestamps below are UTC instants for reproducibility. In production,
retain source instants and apply the agency's IANA time zone only for reporting.
===============================================================================
*/

DROP SCHEMA IF EXISTS transit_practice CASCADE;
CREATE SCHEMA transit_practice;
SET search_path = transit_practice, public;

-- ---------------------------------------------------------------------------
-- 0. Independent practice schema
-- ---------------------------------------------------------------------------

CREATE TABLE agencies (
    agency_id       text PRIMARY KEY,
    agency_name     text NOT NULL
);

CREATE TABLE routes (
    route_id        text PRIMARY KEY,
    agency_id       text NOT NULL REFERENCES agencies(agency_id),
    route_short_name text NOT NULL,
    route_type      smallint NOT NULL
);

CREATE TABLE stops (
    stop_id         text PRIMARY KEY,
    stop_name       text NOT NULL
);

CREATE TABLE trips (
    trip_id         text PRIMARY KEY,
    route_id        text NOT NULL REFERENCES routes(route_id),
    direction_id    smallint NOT NULL,
    service_date    date NOT NULL,
    block_id        text NOT NULL
);

CREATE TABLE vehicle_assignments (
    trip_id             text PRIMARY KEY REFERENCES trips(trip_id),
    vehicle_id          text NOT NULL,
    passenger_capacity  integer NOT NULL CHECK (passenger_capacity > 0)
);

CREATE TABLE scheduled_stop_times (
    trip_id             text NOT NULL REFERENCES trips(trip_id),
    stop_sequence       integer NOT NULL CHECK (stop_sequence > 0),
    stop_id             text NOT NULL REFERENCES stops(stop_id),
    scheduled_arrival   timestamptz NOT NULL,
    scheduled_departure timestamptz NOT NULL,
    PRIMARY KEY (trip_id, stop_sequence),
    CHECK (scheduled_departure >= scheduled_arrival)
);

-- Landing table deliberately has no FK to trips/scheduled_stop_times:
-- malformed and orphan source records must remain observable for controls.
CREATE TABLE avl_event_landing (
    landing_id       bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    logical_event_id text NOT NULL,
    event_version    integer NOT NULL CHECK (event_version > 0),
    trip_id          text NOT NULL,
    stop_sequence    integer NOT NULL,
    stop_id          text NOT NULL,
    event_type       text NOT NULL CHECK (event_type IN ('ARRIVAL', 'DEPARTURE')),
    event_ts         timestamptz NOT NULL,
    received_at      timestamptz NOT NULL,
    is_void          boolean NOT NULL DEFAULT false,
    vehicle_id       text
);

CREATE TABLE apc_event_landing (
    landing_id       bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    logical_event_id text NOT NULL,
    event_version    integer NOT NULL CHECK (event_version > 0),
    trip_id          text NOT NULL,
    stop_sequence    integer NOT NULL,
    stop_id          text NOT NULL,
    boardings        integer NOT NULL,
    alightings       integer NOT NULL,
    received_at      timestamptz NOT NULL,
    is_void          boolean NOT NULL DEFAULT false
);

-- ---------------------------------------------------------------------------
-- 1. Reference data and scheduled service
-- ---------------------------------------------------------------------------

INSERT INTO agencies VALUES
('AG1', 'MetroLink Transit');

INSERT INTO routes VALUES
('R10', 'AG1', 'River Loop', 3),
('R20', 'AG1', 'Crosstown', 3);

INSERT INTO stops VALUES
('S1', 'Central Terminal'),
('S2', 'Museum'),
('S3', 'University'),
('S4', 'Depot'),
('S5', 'Market Square');

INSERT INTO trips VALUES
('T100', 'R10', 0, DATE '2026-11-17', 'B501'),
('T101', 'R10', 0, DATE '2026-11-17', 'B502'),
('T102', 'R10', 0, DATE '2026-11-17', 'B501'),
('T200', 'R20', 1, DATE '2026-11-17', 'B601'),
('T201', 'R20', 1, DATE '2026-11-17', 'B602');

INSERT INTO vehicle_assignments VALUES
('T100', 'BUS-11', 40),
('T101', 'BUS-12', 30),
('T102', 'BUS-11', 40),
('T200', 'BUS-21', 35),
('T201', 'BUS-22', 30);

INSERT INTO scheduled_stop_times VALUES
-- R10: Central -> Museum -> University -> Depot
('T100', 1, 'S1', TIMESTAMPTZ '2026-11-17 08:00:00+00', TIMESTAMPTZ '2026-11-17 08:01:00+00'),
('T100', 2, 'S2', TIMESTAMPTZ '2026-11-17 08:10:00+00', TIMESTAMPTZ '2026-11-17 08:11:00+00'),
('T100', 3, 'S3', TIMESTAMPTZ '2026-11-17 08:20:00+00', TIMESTAMPTZ '2026-11-17 08:21:00+00'),
('T100', 4, 'S4', TIMESTAMPTZ '2026-11-17 08:30:00+00', TIMESTAMPTZ '2026-11-17 08:31:00+00'),

('T101', 1, 'S1', TIMESTAMPTZ '2026-11-17 08:05:00+00', TIMESTAMPTZ '2026-11-17 08:06:00+00'),
('T101', 2, 'S2', TIMESTAMPTZ '2026-11-17 08:15:00+00', TIMESTAMPTZ '2026-11-17 08:16:00+00'),
('T101', 3, 'S3', TIMESTAMPTZ '2026-11-17 08:25:00+00', TIMESTAMPTZ '2026-11-17 08:26:00+00'),
('T101', 4, 'S4', TIMESTAMPTZ '2026-11-17 08:35:00+00', TIMESTAMPTZ '2026-11-17 08:36:00+00'),

('T102', 1, 'S1', TIMESTAMPTZ '2026-11-17 09:00:00+00', TIMESTAMPTZ '2026-11-17 09:01:00+00'),
('T102', 2, 'S2', TIMESTAMPTZ '2026-11-17 09:10:00+00', TIMESTAMPTZ '2026-11-17 09:11:00+00'),
('T102', 3, 'S3', TIMESTAMPTZ '2026-11-17 09:20:00+00', TIMESTAMPTZ '2026-11-17 09:21:00+00'),
('T102', 4, 'S4', TIMESTAMPTZ '2026-11-17 09:30:00+00', TIMESTAMPTZ '2026-11-17 09:31:00+00'),

-- R20: Depot -> University -> Market Square
('T200', 1, 'S4', TIMESTAMPTZ '2026-11-17 08:00:00+00', TIMESTAMPTZ '2026-11-17 08:01:00+00'),
('T200', 2, 'S3', TIMESTAMPTZ '2026-11-17 08:12:00+00', TIMESTAMPTZ '2026-11-17 08:13:00+00'),
('T200', 3, 'S5', TIMESTAMPTZ '2026-11-17 08:24:00+00', TIMESTAMPTZ '2026-11-17 08:25:00+00'),

('T201', 1, 'S4', TIMESTAMPTZ '2026-11-17 08:06:00+00', TIMESTAMPTZ '2026-11-17 08:07:00+00'),
('T201', 2, 'S3', TIMESTAMPTZ '2026-11-17 08:18:00+00', TIMESTAMPTZ '2026-11-17 08:19:00+00'),
('T201', 3, 'S5', TIMESTAMPTZ '2026-11-17 08:30:00+00', TIMESTAMPTZ '2026-11-17 08:31:00+00');

-- ---------------------------------------------------------------------------
-- 2. AVL landing events
-- Intentional cases:
--   * T100/S2 arrival is replayed and then corrected in version 2.
--   * T101/S3 departure is voided by the latest version.
--   * T201/S3 departure precedes its arrival (impossible dwell).
--   * T200/S5 has no AVL arrival/departure.
--   * T999 is an orphan trip.
-- ---------------------------------------------------------------------------

INSERT INTO avl_event_landing
(logical_event_id, event_version, trip_id, stop_sequence, stop_id,
 event_type, event_ts, received_at, is_void, vehicle_id)
VALUES
('T100-S1-A', 1, 'T100', 1, 'S1', 'ARRIVAL',   TIMESTAMPTZ '2026-11-17 08:01:00+00', TIMESTAMPTZ '2026-11-17 08:01:10+00', false, 'BUS-11'),
('T100-S1-D', 1, 'T100', 1, 'S1', 'DEPARTURE', TIMESTAMPTZ '2026-11-17 08:02:00+00', TIMESTAMPTZ '2026-11-17 08:02:10+00', false, 'BUS-11'),
('T100-S2-A', 1, 'T100', 2, 'S2', 'ARRIVAL',   TIMESTAMPTZ '2026-11-17 08:11:30+00', TIMESTAMPTZ '2026-11-17 08:11:40+00', false, 'BUS-11'),
('T100-S2-A', 1, 'T100', 2, 'S2', 'ARRIVAL',   TIMESTAMPTZ '2026-11-17 08:11:30+00', TIMESTAMPTZ '2026-11-17 08:12:00+00', false, 'BUS-11'),
('T100-S2-A', 2, 'T100', 2, 'S2', 'ARRIVAL',   TIMESTAMPTZ '2026-11-17 08:12:00+00', TIMESTAMPTZ '2026-11-17 08:13:00+00', false, 'BUS-11'),
('T100-S2-D', 1, 'T100', 2, 'S2', 'DEPARTURE', TIMESTAMPTZ '2026-11-17 08:13:00+00', TIMESTAMPTZ '2026-11-17 08:13:10+00', false, 'BUS-11'),
('T100-S3-A', 1, 'T100', 3, 'S3', 'ARRIVAL',   TIMESTAMPTZ '2026-11-17 08:23:00+00', TIMESTAMPTZ '2026-11-17 08:23:10+00', false, 'BUS-11'),
('T100-S3-D', 1, 'T100', 3, 'S3', 'DEPARTURE', TIMESTAMPTZ '2026-11-17 08:24:00+00', TIMESTAMPTZ '2026-11-17 08:24:10+00', false, 'BUS-11'),
('T100-S4-A', 1, 'T100', 4, 'S4', 'ARRIVAL',   TIMESTAMPTZ '2026-11-17 08:34:00+00', TIMESTAMPTZ '2026-11-17 08:34:10+00', false, 'BUS-11'),
('T100-S4-D', 1, 'T100', 4, 'S4', 'DEPARTURE', TIMESTAMPTZ '2026-11-17 08:35:00+00', TIMESTAMPTZ '2026-11-17 08:35:10+00', false, 'BUS-11'),

('T101-S1-A', 1, 'T101', 1, 'S1', 'ARRIVAL',   TIMESTAMPTZ '2026-11-17 08:08:00+00', TIMESTAMPTZ '2026-11-17 08:08:10+00', false, 'BUS-12'),
('T101-S1-D', 1, 'T101', 1, 'S1', 'DEPARTURE', TIMESTAMPTZ '2026-11-17 08:09:00+00', TIMESTAMPTZ '2026-11-17 08:09:10+00', false, 'BUS-12'),
('T101-S2-A', 1, 'T101', 2, 'S2', 'ARRIVAL',   TIMESTAMPTZ '2026-11-17 08:18:00+00', TIMESTAMPTZ '2026-11-17 08:18:10+00', false, 'BUS-12'),
('T101-S2-D', 1, 'T101', 2, 'S2', 'DEPARTURE', TIMESTAMPTZ '2026-11-17 08:19:00+00', TIMESTAMPTZ '2026-11-17 08:19:10+00', false, 'BUS-12'),
('T101-S3-A', 1, 'T101', 3, 'S3', 'ARRIVAL',   TIMESTAMPTZ '2026-11-17 08:30:00+00', TIMESTAMPTZ '2026-11-17 08:30:10+00', false, 'BUS-12'),
('T101-S3-D', 1, 'T101', 3, 'S3', 'DEPARTURE', TIMESTAMPTZ '2026-11-17 08:31:00+00', TIMESTAMPTZ '2026-11-17 08:31:10+00', false, 'BUS-12'),
('T101-S3-D', 2, 'T101', 3, 'S3', 'DEPARTURE', TIMESTAMPTZ '2026-11-17 08:31:00+00', TIMESTAMPTZ '2026-11-17 08:32:00+00', true,  'BUS-12'),
('T101-S4-A', 1, 'T101', 4, 'S4', 'ARRIVAL',   TIMESTAMPTZ '2026-11-17 08:41:00+00', TIMESTAMPTZ '2026-11-17 08:41:10+00', false, 'BUS-12'),
('T101-S4-D', 1, 'T101', 4, 'S4', 'DEPARTURE', TIMESTAMPTZ '2026-11-17 08:42:00+00', TIMESTAMPTZ '2026-11-17 08:42:10+00', false, 'BUS-12'),

('T200-S1-A', 1, 'T200', 1, 'S4', 'ARRIVAL',   TIMESTAMPTZ '2026-11-17 08:02:00+00', TIMESTAMPTZ '2026-11-17 08:02:10+00', false, 'BUS-21'),
('T200-S1-D', 1, 'T200', 1, 'S4', 'DEPARTURE', TIMESTAMPTZ '2026-11-17 08:03:00+00', TIMESTAMPTZ '2026-11-17 08:03:10+00', false, 'BUS-21'),
('T200-S2-A', 1, 'T200', 2, 'S3', 'ARRIVAL',   TIMESTAMPTZ '2026-11-17 08:14:00+00', TIMESTAMPTZ '2026-11-17 08:14:10+00', false, 'BUS-21'),
('T200-S2-D', 1, 'T200', 2, 'S3', 'DEPARTURE', TIMESTAMPTZ '2026-11-17 08:15:00+00', TIMESTAMPTZ '2026-11-17 08:15:10+00', false, 'BUS-21'),

('T201-S1-A', 1, 'T201', 1, 'S4', 'ARRIVAL',   TIMESTAMPTZ '2026-11-17 08:07:00+00', TIMESTAMPTZ '2026-11-17 08:07:10+00', false, 'BUS-22'),
('T201-S1-D', 1, 'T201', 1, 'S4', 'DEPARTURE', TIMESTAMPTZ '2026-11-17 08:08:00+00', TIMESTAMPTZ '2026-11-17 08:08:10+00', false, 'BUS-22'),
('T201-S2-A', 1, 'T201', 2, 'S3', 'ARRIVAL',   TIMESTAMPTZ '2026-11-17 08:20:00+00', TIMESTAMPTZ '2026-11-17 08:20:10+00', false, 'BUS-22'),
('T201-S2-D', 1, 'T201', 2, 'S3', 'DEPARTURE', TIMESTAMPTZ '2026-11-17 08:19:00+00', TIMESTAMPTZ '2026-11-17 08:20:20+00', false, 'BUS-22'),
('T201-S3-A', 1, 'T201', 3, 'S5', 'ARRIVAL',   TIMESTAMPTZ '2026-11-17 08:32:00+00', TIMESTAMPTZ '2026-11-17 08:32:10+00', false, 'BUS-22'),
('T201-S3-D', 1, 'T201', 3, 'S5', 'DEPARTURE', TIMESTAMPTZ '2026-11-17 08:33:00+00', TIMESTAMPTZ '2026-11-17 08:33:10+00', false, 'BUS-22'),

('T102-S1-A', 1, 'T102', 1, 'S1', 'ARRIVAL',   TIMESTAMPTZ '2026-11-17 09:03:00+00', TIMESTAMPTZ '2026-11-17 09:03:10+00', false, 'BUS-11'),
('T102-S1-D', 1, 'T102', 1, 'S1', 'DEPARTURE', TIMESTAMPTZ '2026-11-17 09:04:00+00', TIMESTAMPTZ '2026-11-17 09:04:10+00', false, 'BUS-11'),

('ORPHAN-E1', 1, 'T999', 1, 'S1', 'ARRIVAL', TIMESTAMPTZ '2026-11-17 08:45:00+00', TIMESTAMPTZ '2026-11-17 08:45:10+00', false, 'BUS-99');

-- ---------------------------------------------------------------------------
-- 3. APC landing events (boardings/alightings are stop-level deltas)
-- Intentional cases: duplicate + correction at T100/S2, negative load at
-- T201/S5, and an orphan T999 observation.
-- ---------------------------------------------------------------------------

INSERT INTO apc_event_landing
(logical_event_id, event_version, trip_id, stop_sequence, stop_id,
 boardings, alightings, received_at, is_void)
VALUES
('APC-T100-1', 1, 'T100', 1, 'S1', 8, 0, TIMESTAMPTZ '2026-11-17 08:02:00+00', false),
('APC-T100-2', 1, 'T100', 2, 'S2', 3, 1, TIMESTAMPTZ '2026-11-17 08:13:00+00', false),
('APC-T100-2', 1, 'T100', 2, 'S2', 3, 1, TIMESTAMPTZ '2026-11-17 08:13:20+00', false),
('APC-T100-2', 2, 'T100', 2, 'S2', 4, 1, TIMESTAMPTZ '2026-11-17 08:14:00+00', false),
('APC-T100-3', 1, 'T100', 3, 'S3', 1, 3, TIMESTAMPTZ '2026-11-17 08:24:00+00', false),
('APC-T100-4', 1, 'T100', 4, 'S4', 0, 9, TIMESTAMPTZ '2026-11-17 08:35:00+00', false),

('APC-T101-1', 1, 'T101', 1, 'S1', 5, 0, TIMESTAMPTZ '2026-11-17 08:09:00+00', false),
('APC-T101-2', 1, 'T101', 2, 'S2', 2, 1, TIMESTAMPTZ '2026-11-17 08:19:00+00', false),
('APC-T101-3', 1, 'T101', 3, 'S3', 0, 2, TIMESTAMPTZ '2026-11-17 08:31:00+00', false),
('APC-T101-4', 1, 'T101', 4, 'S4', 0, 4, TIMESTAMPTZ '2026-11-17 08:42:00+00', false),

('APC-T200-1', 1, 'T200', 1, 'S4', 10, 0, TIMESTAMPTZ '2026-11-17 08:03:00+00', false),
('APC-T200-2', 1, 'T200', 2, 'S3', 1, 3, TIMESTAMPTZ '2026-11-17 08:15:00+00', false),
('APC-T200-3', 1, 'T200', 3, 'S5', 0, 4, TIMESTAMPTZ '2026-11-17 08:25:00+00', false),

('APC-T201-1', 1, 'T201', 1, 'S4', 7, 0, TIMESTAMPTZ '2026-11-17 08:08:00+00', false),
('APC-T201-2', 1, 'T201', 2, 'S3', 2, 1, TIMESTAMPTZ '2026-11-17 08:21:00+00', false),
('APC-T201-3', 1, 'T201', 3, 'S5', 0, 15, TIMESTAMPTZ '2026-11-17 08:33:00+00', false),

('APC-T102-1', 1, 'T102', 1, 'S1', 3, 0, TIMESTAMPTZ '2026-11-17 09:04:00+00', false),
('APC-ORPHAN', 1, 'T999', 1, 'S1', 1, 0, TIMESTAMPTZ '2026-11-17 08:46:00+00', false);

ANALYZE agencies;
ANALYZE routes;
ANALYZE stops;
ANALYZE trips;
ANALYZE vehicle_assignments;
ANALYZE scheduled_stop_times;
ANALYZE avl_event_landing;
ANALYZE apc_event_landing;

-- ===========================================================================
-- PROBLEM 1
-- Canonicalize the AVL feed to one row per logical event. The newest version
-- wins; within a version, latest received_at wins. A winning void suppresses
-- the logical event completely.
--
-- Optimization: rank once by the logical key and apply is_void only AFTER
-- rn = 1. Filtering void rows before ranking could incorrectly resurrect v1.
-- ===========================================================================

WITH ranked AS (
    SELECT a.*,
           ROW_NUMBER() OVER (
               PARTITION BY logical_event_id
               ORDER BY event_version DESC, received_at DESC, landing_id DESC
           ) AS rn
    FROM avl_event_landing a
)
SELECT logical_event_id, event_version, trip_id, stop_sequence, stop_id,
       event_type, event_ts, received_at, vehicle_id
FROM ranked
WHERE rn = 1
  AND is_void = false
ORDER BY trip_id, stop_sequence, event_type;

-- ===========================================================================
-- PROBLEM 2
-- Calculate route-level arrival punctuality. Treat an arrival from 60 seconds
-- early through 300 seconds late as on time. Report count, average delay,
-- P95 delay and on-time percentage.
--
-- Optimization: canonicalize before joining; aggregate at route grain rather
-- than carrying event-level detail into downstream reports.
-- ===========================================================================

WITH ranked AS (
    SELECT a.*,
           ROW_NUMBER() OVER (
               PARTITION BY logical_event_id
               ORDER BY event_version DESC, received_at DESC, landing_id DESC
           ) AS rn
    FROM avl_event_landing a
),
canonical_arrivals AS (
    SELECT trip_id, stop_sequence, stop_id, event_ts
    FROM ranked
    WHERE rn = 1 AND is_void = false AND event_type = 'ARRIVAL'
),
delays AS (
    SELECT t.route_id,
           t.trip_id,
           s.stop_id,
           EXTRACT(EPOCH FROM (a.event_ts - s.scheduled_arrival)) AS delay_seconds
    FROM canonical_arrivals a
    JOIN scheduled_stop_times s
      ON s.trip_id = a.trip_id
     AND s.stop_sequence = a.stop_sequence
     AND s.stop_id = a.stop_id
    JOIN trips t ON t.trip_id = a.trip_id
    WHERE t.service_date = DATE '2026-11-17'
)
SELECT r.route_short_name,
       COUNT(*) AS observed_arrivals,
       ROUND(AVG(d.delay_seconds)::numeric, 1) AS avg_delay_seconds,
       ROUND((PERCENTILE_CONT(0.95) WITHIN GROUP
              (ORDER BY d.delay_seconds))::numeric, 1) AS p95_delay_seconds,
       ROUND(
           100.0 * COUNT(*) FILTER
               (WHERE d.delay_seconds BETWEEN -60 AND 300) / NULLIF(COUNT(*), 0),
           1
       ) AS on_time_pct
FROM delays d
JOIN routes r ON r.route_id = d.route_id
GROUP BY r.route_short_name
ORDER BY r.route_short_name;

-- ===========================================================================
-- PROBLEM 3
-- At each route/direction/stop, calculate actual headway between consecutive
-- arrivals and compare it with the scheduled headway. Flag bunching (<50% of
-- scheduled gap) and excessive gaps (>150%).
--
-- Optimization: LAG is partitioned by the natural service key. Keep the
-- service-date predicate on trips and avoid a self-join between every pair
-- of arrivals.
-- ===========================================================================

WITH ranked AS (
    SELECT a.*,
           ROW_NUMBER() OVER (
               PARTITION BY logical_event_id
               ORDER BY event_version DESC, received_at DESC, landing_id DESC
           ) AS rn
    FROM avl_event_landing a
),
arrivals AS (
    SELECT t.route_id, t.direction_id, a.stop_id, a.trip_id,
           a.event_ts AS actual_arrival, s.scheduled_arrival
    FROM ranked a
    JOIN trips t ON t.trip_id = a.trip_id
    JOIN scheduled_stop_times s
      ON s.trip_id = a.trip_id
     AND s.stop_sequence = a.stop_sequence
     AND s.stop_id = a.stop_id
    WHERE a.rn = 1
      AND a.is_void = false
      AND a.event_type = 'ARRIVAL'
      AND t.service_date = DATE '2026-11-17'
),
with_previous AS (
    SELECT *,
           LAG(actual_arrival) OVER (
               PARTITION BY route_id, direction_id, stop_id
               ORDER BY actual_arrival, trip_id
           ) AS previous_actual_arrival,
           LAG(scheduled_arrival) OVER (
               PARTITION BY route_id, direction_id, stop_id
               ORDER BY actual_arrival, trip_id
           ) AS previous_scheduled_arrival
    FROM arrivals
),
headways AS (
    SELECT *,
           EXTRACT(EPOCH FROM (actual_arrival - previous_actual_arrival))
               AS actual_headway_seconds,
           EXTRACT(EPOCH FROM (scheduled_arrival - previous_scheduled_arrival))
               AS scheduled_headway_seconds
    FROM with_previous
)
SELECT route_id, direction_id, stop_id, trip_id,
       actual_arrival, actual_headway_seconds, scheduled_headway_seconds,
       CASE
           WHEN scheduled_headway_seconds IS NULL THEN 'FIRST OBSERVATION'
           WHEN actual_headway_seconds < scheduled_headway_seconds * 0.50 THEN 'BUNCHING'
           WHEN actual_headway_seconds > scheduled_headway_seconds * 1.50 THEN 'EXCESSIVE GAP'
           ELSE 'WITHIN BAND'
       END AS headway_status
FROM headways
ORDER BY route_id, stop_id, actual_arrival;

-- ===========================================================================
-- PROBLEM 4
-- Find scheduled timepoints with no valid canonical AVL arrival. Include
-- trips with partial telemetry; do not turn the LEFT JOIN into an inner join.
--
-- Optimization: start from the complete schedule spine and use a LEFT JOIN
-- against the small canonical arrival set. This preserves missing service.
-- ===========================================================================

WITH ranked AS (
    SELECT a.*,
           ROW_NUMBER() OVER (
               PARTITION BY logical_event_id
               ORDER BY event_version DESC, received_at DESC, landing_id DESC
           ) AS rn
    FROM avl_event_landing a
),
canonical_arrivals AS (
    SELECT logical_event_id, trip_id, stop_sequence, stop_id
    FROM ranked
    WHERE rn = 1 AND is_void = false AND event_type = 'ARRIVAL'
)
SELECT s.trip_id, t.route_id, s.stop_sequence, s.stop_id,
       s.scheduled_arrival
FROM scheduled_stop_times s
JOIN trips t ON t.trip_id = s.trip_id
LEFT JOIN canonical_arrivals a
  ON a.trip_id = s.trip_id
 AND a.stop_sequence = s.stop_sequence
 AND a.stop_id = s.stop_id
WHERE t.service_date = DATE '2026-11-17'
  AND a.logical_event_id IS NULL
ORDER BY t.route_id, s.trip_id, s.stop_sequence;

-- ===========================================================================
-- PROBLEM 5
-- Calculate dwell time (departure - arrival) and running time (next stop
-- arrival - current stop departure). Return negative or unusually long values.
--
-- Optimization: pivot arrival/departure with FILTER, then LEAD over the full
-- scheduled stop spine. Missing events remain NULL instead of shifting the
-- next observed stop into the wrong sequence.
-- ===========================================================================

WITH ranked AS (
    SELECT a.*,
           ROW_NUMBER() OVER (
               PARTITION BY logical_event_id
               ORDER BY event_version DESC, received_at DESC, landing_id DESC
           ) AS rn
    FROM avl_event_landing a
),
canonical AS (
    SELECT trip_id, stop_sequence, event_type, event_ts
    FROM ranked
    WHERE rn = 1 AND is_void = false
),
actual_by_stop AS (
    SELECT trip_id, stop_sequence,
           MAX(event_ts) FILTER (WHERE event_type = 'ARRIVAL') AS actual_arrival,
           MAX(event_ts) FILTER (WHERE event_type = 'DEPARTURE') AS actual_departure
    FROM canonical
    GROUP BY trip_id, stop_sequence
),
stop_grid AS (
    SELECT s.trip_id, s.stop_sequence, s.stop_id,
           a.actual_arrival, a.actual_departure,
           LEAD(a.actual_arrival) OVER (
               PARTITION BY s.trip_id ORDER BY s.stop_sequence
           ) AS next_actual_arrival
    FROM scheduled_stop_times s
    LEFT JOIN actual_by_stop a
      ON a.trip_id = s.trip_id
     AND a.stop_sequence = s.stop_sequence
),
durations AS (
    SELECT *,
           EXTRACT(EPOCH FROM (actual_departure - actual_arrival)) AS dwell_seconds,
           EXTRACT(EPOCH FROM (next_actual_arrival - actual_departure)) AS running_seconds
    FROM stop_grid
)
SELECT trip_id, stop_sequence, stop_id,
       actual_arrival, actual_departure,
       dwell_seconds, running_seconds
FROM durations
WHERE dwell_seconds < 0
   OR dwell_seconds > 600
   OR running_seconds < 0
   OR running_seconds > 1800
ORDER BY trip_id, stop_sequence;

-- ===========================================================================
-- PROBLEM 6
-- Reconstruct onboard passenger load after each stop from canonical APC
-- boardings/alightings. Compare the load with the assigned vehicle capacity.
--
-- Optimization: deduplicate logical APC observations before the running sum.
-- The explicit ROWS frame avoids peer-group behavior if ordering keys tie.
-- ===========================================================================

WITH ranked AS (
    SELECT p.*,
           ROW_NUMBER() OVER (
               PARTITION BY logical_event_id
               ORDER BY event_version DESC, received_at DESC, landing_id DESC
           ) AS rn
    FROM apc_event_landing p
),
canonical_apc AS (
    SELECT trip_id, stop_sequence, stop_id, boardings, alightings
    FROM ranked
    WHERE rn = 1 AND is_void = false
),
loads AS (
    SELECT p.*,
           SUM(boardings - alightings) OVER (
               PARTITION BY trip_id
               ORDER BY stop_sequence
               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
           ) AS onboard_after_stop
    FROM canonical_apc p
)
SELECT l.trip_id, l.stop_sequence, l.stop_id,
       l.boardings, l.alightings, l.onboard_after_stop,
       v.vehicle_id, v.passenger_capacity,
       CASE
           WHEN l.onboard_after_stop < 0 THEN 'NEGATIVE LOAD'
           WHEN l.onboard_after_stop > v.passenger_capacity THEN 'OVER CAPACITY'
           ELSE 'WITHIN CAPACITY'
       END AS load_status
FROM loads l
LEFT JOIN vehicle_assignments v ON v.trip_id = l.trip_id
ORDER BY l.trip_id, l.stop_sequence;

-- ===========================================================================
-- PROBLEM 7
-- Produce a route-level reliability summary using arrival delay distribution,
-- including median, P95 and the share within the -60/+300 second window.
--
-- Optimization: compute one row per observed arrival first, then use ordered-
-- set aggregates once at route grain. Percentiles are expensive at scale;
-- consider pre-aggregated time buckets for operational dashboards.
-- ===========================================================================

WITH ranked AS (
    SELECT a.*,
           ROW_NUMBER() OVER (
               PARTITION BY logical_event_id
               ORDER BY event_version DESC, received_at DESC, landing_id DESC
           ) AS rn
    FROM avl_event_landing a
),
delay_rows AS (
    SELECT t.route_id,
           EXTRACT(EPOCH FROM (a.event_ts - s.scheduled_arrival)) AS delay_seconds
    FROM ranked a
    JOIN trips t ON t.trip_id = a.trip_id
    JOIN scheduled_stop_times s
      ON s.trip_id = a.trip_id
     AND s.stop_sequence = a.stop_sequence
     AND s.stop_id = a.stop_id
    WHERE a.rn = 1
      AND a.is_void = false
      AND a.event_type = 'ARRIVAL'
      AND t.service_date = DATE '2026-11-17'
)
SELECT r.route_short_name,
       COUNT(*) AS arrival_count,
       ROUND(AVG(d.delay_seconds)::numeric, 1) AS mean_delay_seconds,
       ROUND((PERCENTILE_CONT(0.50) WITHIN GROUP
              (ORDER BY d.delay_seconds))::numeric, 1) AS median_delay_seconds,
       ROUND((PERCENTILE_CONT(0.95) WITHIN GROUP
              (ORDER BY d.delay_seconds))::numeric, 1) AS p95_delay_seconds,
       ROUND(100.0 * COUNT(*) FILTER
             (WHERE d.delay_seconds BETWEEN -60 AND 300) / NULLIF(COUNT(*), 0), 1)
             AS on_time_percentage
FROM delay_rows d
JOIN routes r ON r.route_id = d.route_id
GROUP BY r.route_short_name
ORDER BY r.route_short_name;

-- ===========================================================================
-- PROBLEM 8
-- Calculate stop-time telemetry coverage for every trip: expected stops,
-- observed canonical arrivals, missing arrivals and coverage percentage.
--
-- Optimization: aggregate from the schedule spine so trips with zero or
-- partial AVL observations are retained. Count a non-null event key, not '*'.
-- ===========================================================================

WITH ranked AS (
    SELECT a.*,
           ROW_NUMBER() OVER (
               PARTITION BY logical_event_id
               ORDER BY event_version DESC, received_at DESC, landing_id DESC
           ) AS rn
    FROM avl_event_landing a
),
canonical_arrivals AS (
    SELECT logical_event_id, trip_id, stop_sequence, stop_id
    FROM ranked
    WHERE rn = 1 AND is_void = false AND event_type = 'ARRIVAL'
)
SELECT t.trip_id, t.route_id,
       COUNT(*) AS expected_stop_count,
       COUNT(a.logical_event_id) AS observed_arrival_count,
       COUNT(*) - COUNT(a.logical_event_id) AS missing_arrival_count,
       ROUND(100.0 * COUNT(a.logical_event_id) / NULLIF(COUNT(*), 0), 1)
           AS telemetry_coverage_pct
FROM trips t
JOIN scheduled_stop_times s ON s.trip_id = t.trip_id
LEFT JOIN canonical_arrivals a
  ON a.trip_id = s.trip_id
 AND a.stop_sequence = s.stop_sequence
 AND a.stop_id = s.stop_id
WHERE t.service_date = DATE '2026-11-17'
GROUP BY t.trip_id, t.route_id
ORDER BY t.route_id, t.trip_id;

-- ===========================================================================
-- PROBLEM 9
-- Find APC exceptions: orphan trip/stop references, negative source counts,
-- and a cumulative onboard load below zero. Keep malformed landing records
-- visible rather than dropping them through inner joins.
--
-- Optimization: use a single canonicalization pass and a LEFT JOIN to the
-- schedule. The cumulative load is calculated at trip/sequence grain.
-- ===========================================================================

WITH ranked AS (
    SELECT p.*,
           ROW_NUMBER() OVER (
               PARTITION BY logical_event_id
               ORDER BY event_version DESC, received_at DESC, landing_id DESC
           ) AS rn
    FROM apc_event_landing p
),
canonical AS (
    SELECT *
    FROM ranked
    WHERE rn = 1 AND is_void = false
),
load_calc AS (
    SELECT c.*,
           SUM(boardings - alightings) OVER (
               PARTITION BY trip_id
               ORDER BY stop_sequence
               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
           ) AS onboard_after_stop
    FROM canonical c
),
checked AS (
    SELECT l.*,
           t.trip_id AS known_trip_id,
           s.trip_id AS known_stop_time
    FROM load_calc l
    LEFT JOIN trips t ON t.trip_id = l.trip_id
    LEFT JOIN scheduled_stop_times s
      ON s.trip_id = l.trip_id
     AND s.stop_sequence = l.stop_sequence
     AND s.stop_id = l.stop_id
)
SELECT logical_event_id, trip_id, stop_sequence, stop_id,
       boardings, alightings, onboard_after_stop,
       CASE
           WHEN known_trip_id IS NULL THEN 'UNKNOWN TRIP'
           WHEN known_stop_time IS NULL THEN 'STOP/TIMEPOINT MISMATCH'
           WHEN boardings < 0 OR alightings < 0 THEN 'NEGATIVE APC COUNT'
           WHEN onboard_after_stop < 0 THEN 'NEGATIVE ONBOARD LOAD'
       END AS exception_type
FROM checked
WHERE known_trip_id IS NULL
   OR known_stop_time IS NULL
   OR boardings < 0
   OR alightings < 0
   OR onboard_after_stop < 0
ORDER BY trip_id, stop_sequence;

-- ===========================================================================
-- PROBLEM 10
-- For each vehicle block, calculate recovery time from one trip's final
-- observed arrival to the next trip's first observed departure. Flag a layover
-- shorter than 10 minutes.
--
-- Optimization: identify first/last scheduled stop with ROW_NUMBER, aggregate
-- edge events once, then use LEAD within block. This avoids a many-to-many
-- self-join of every stop on adjacent trips.
-- ===========================================================================

WITH ranked_events AS (
    SELECT a.*,
           ROW_NUMBER() OVER (
               PARTITION BY logical_event_id
               ORDER BY event_version DESC, received_at DESC, landing_id DESC
           ) AS rn
    FROM avl_event_landing a
),
canonical AS (
    SELECT trip_id, stop_sequence, event_type, event_ts
    FROM ranked_events
    WHERE rn = 1 AND is_void = false
),
ranked_stops AS (
    SELECT s.*,
           ROW_NUMBER() OVER (
               PARTITION BY trip_id ORDER BY stop_sequence
           ) AS first_stop_rank,
           ROW_NUMBER() OVER (
               PARTITION BY trip_id ORDER BY stop_sequence DESC
           ) AS last_stop_rank
    FROM scheduled_stop_times s
),
trip_edges AS (
    SELECT t.block_id, t.trip_id,
           MAX(s.scheduled_departure) FILTER (WHERE s.first_stop_rank = 1)
               AS first_scheduled_departure,
           MAX(s.scheduled_arrival) FILTER (WHERE s.last_stop_rank = 1)
               AS last_scheduled_arrival,
           MAX(c.event_ts) FILTER (
               WHERE s.first_stop_rank = 1 AND c.event_type = 'DEPARTURE'
           ) AS actual_first_departure,
           MAX(c.event_ts) FILTER (
               WHERE s.last_stop_rank = 1 AND c.event_type = 'ARRIVAL'
           ) AS actual_last_arrival
    FROM trips t
    JOIN ranked_stops s ON s.trip_id = t.trip_id
    LEFT JOIN canonical c
      ON c.trip_id = s.trip_id
     AND c.stop_sequence = s.stop_sequence
    WHERE t.service_date = DATE '2026-11-17'
    GROUP BY t.block_id, t.trip_id
),
ordered_blocks AS (
    SELECT *,
           LEAD(actual_first_departure) OVER (
               PARTITION BY block_id
               ORDER BY first_scheduled_departure, trip_id
           ) AS next_trip_actual_departure
    FROM trip_edges
),
recovery AS (
    SELECT *,
           EXTRACT(EPOCH FROM
               (next_trip_actual_departure - actual_last_arrival)
           ) AS recovery_seconds
    FROM ordered_blocks
)
SELECT block_id, trip_id, actual_last_arrival,
       next_trip_actual_departure, recovery_seconds,
       CASE
           WHEN recovery_seconds IS NULL THEN 'INCOMPLETE EDGE DATA'
           WHEN recovery_seconds < 600 THEN 'INSUFFICIENT RECOVERY'
           ELSE 'RECOVERY OK'
       END AS recovery_status
FROM recovery
WHERE next_trip_actual_departure IS NOT NULL
ORDER BY block_id, first_scheduled_departure;

-- ===========================================================================
-- PERFORMANCE LAB
-- Run representative exercises before and after testing these candidate
-- indexes. Do not assume an index helps the tiny sample dataset.
--
-- CREATE INDEX ix_avl_logical_version
--     ON avl_event_landing
--        (logical_event_id, event_version DESC, received_at DESC, landing_id DESC);
--
-- CREATE INDEX ix_avl_trip_stop_type
--     ON avl_event_landing (trip_id, stop_sequence, event_type);
--
-- CREATE INDEX ix_apc_logical_version
--     ON apc_event_landing
--        (logical_event_id, event_version DESC, received_at DESC, landing_id DESC);
--
-- CREATE INDEX ix_schedule_trip_sequence
--     ON scheduled_stop_times (trip_id, stop_sequence)
--     INCLUDE (stop_id, scheduled_arrival, scheduled_departure);
--
-- CREATE INDEX ix_trip_service_route
--     ON trips (service_date, route_id, direction_id, trip_id);
--
-- EXPLAIN (ANALYZE, BUFFERS)
-- <paste one solution query here>;
--
-- Performance notes:
-- 1. Keep the latest-version/void decision in one reusable canonicalization
--    view or materialized staging table for repeated operational reports.
-- 2. Do not filter is_void = false before ROW_NUMBER: a newer void must cancel
--    an older active version.
-- 3. For large AVL/APC landing tables, partition by service_date or ingestion
--    date only after validating retention and cross-partition replay strategy.
-- 4. A global logical_event_id uniqueness constraint may not be enforceable
--    with a partition key that is absent from the unique key.
-- 5. Keep event_ts predicates as timestamp ranges; avoid DATE(event_ts) in
--    high-volume filters so ordinary timestamp indexes remain usable.
-- 6. Consider BRIN on append-correlated event_ts/received_at for very large,
--    physically ordered landing tables; retain B-tree for selective lookups.
-- 7. Window functions need sort memory. Inspect Sort Method, spills, buffers,
--    and actual row counts; increase work_mem only at a scoped/session level
--    after measuring concurrent workload impact.
-- 8. GTFS stop_sequence is the stable within-trip ordering key. Do not order
--    by stop name or timestamp when reconstructing a scheduled trip.
-- 9. APC running load assumes counts are deltas at each stop. Validate source
--    semantics before treating the result as an absolute passenger count.
-- 10. Headway regularity is often more meaningful than schedule deviation on
--     high-frequency routes; apply route-specific thresholds in production.

-- Expected spot checks:
-- * Q1 returns the corrected T100-S2-A at 08:12 and omits voided T101-S3-D.
-- * Q4 identifies T200/S5 and T102/S2-S4 as missing AVL arrivals.
-- * Q5 flags T201/S3 because departure precedes arrival.
-- * Q6/Q9 identify a negative onboard load for T201.
-- * Q9 identifies the orphan APC observation for T999.
-- * Q10 reports a B501 recovery interval between T100 and T102.
--
-- Interview follow-ups:
-- - How would you handle a correction received after a dashboard was published?
-- - How would you distinguish a cancelled trip from a trip with missing AVL?
-- - How would you model stop-level headway targets that vary by time of day?
-- - How would you reconcile APC counts with farebox taps and manual surveys?
-- - How would you keep block recovery calculations correct across midnight?
