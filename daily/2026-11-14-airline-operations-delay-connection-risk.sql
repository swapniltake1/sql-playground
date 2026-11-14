-- ============================================================================
-- AIRLINE NETWORK OPERATIONS: FLIGHT DELAYS, TURNAROUNDS & CONNECTION RISK
-- PostgreSQL 14+
--
-- Scenario:
-- An airline operations team receives flight-status events from airline and
-- airport feeds. Events can be replayed or corrected. The team needs reliable
-- on-time-performance metrics, aircraft rotation checks, passenger connection
-- risk, gate-conflict detection, and cancellation impact analysis.
--
-- Run this file independently in a disposable PostgreSQL database.
-- The sample operating date is 2026-11-14 (timestamps use Asia/Kolkata offsets).
-- Solutions are commented out so each problem can be attempted first.
--
-- Grain and definitions:
-- * One row in flight_schedule represents one scheduled flight leg.
-- * A canonical status event is one row per flight_id + event_type.
-- * Departure/arrival punctuality means no more than 15 minutes late.
-- * Minimum connection time (MCT) is airport-specific and illustrative.
-- * Minimum aircraft turn time is aircraft-type-specific and illustrative.
-- ============================================================================

DROP VIEW IF EXISTS v_flight_actuals;
DROP VIEW IF EXISTS v_canonical_flight_event;
DROP TABLE IF EXISTS passenger_connection;
DROP TABLE IF EXISTS gate_assignment;
DROP TABLE IF EXISTS flight_status_event;
DROP TABLE IF EXISTS flight_schedule;
DROP TABLE IF EXISTS aircraft;
DROP TABLE IF EXISTS airport;

CREATE TABLE airport (
    airport_code              text PRIMARY KEY,
    airport_name              text NOT NULL,
    city                      text NOT NULL,
    timezone_name             text NOT NULL,
    min_connection_minutes    integer NOT NULL CHECK (min_connection_minutes > 0)
);

CREATE TABLE aircraft (
    tail_number       text PRIMARY KEY,
    aircraft_type     text NOT NULL,
    min_turn_minutes  integer NOT NULL CHECK (min_turn_minutes > 0)
);

CREATE TABLE flight_schedule (
    flight_id             bigint PRIMARY KEY,
    airline_code          text NOT NULL,
    flight_number         text NOT NULL,
    operating_date        date NOT NULL,
    origin                text NOT NULL REFERENCES airport(airport_code),
    destination           text NOT NULL REFERENCES airport(airport_code),
    scheduled_departure   timestamptz NOT NULL,
    scheduled_arrival     timestamptz NOT NULL,
    tail_number           text NOT NULL REFERENCES aircraft(tail_number),
    seat_capacity         integer NOT NULL CHECK (seat_capacity > 0),
    CHECK (origin <> destination),
    CHECK (scheduled_arrival > scheduled_departure)
);

CREATE TABLE flight_status_event (
    event_id             bigint PRIMARY KEY,
    flight_id            bigint NOT NULL REFERENCES flight_schedule(flight_id),
    event_type           text NOT NULL
                         CHECK (event_type IN ('DEPARTED', 'ARRIVED', 'CANCELLED')),
    event_time           timestamptz NOT NULL,
    source_updated_at    timestamptz NOT NULL,
    source_priority      smallint NOT NULL,
    source_sequence      integer NOT NULL,
    ingested_at          timestamptz NOT NULL,
    source_event_key     text NOT NULL
);

CREATE TABLE gate_assignment (
    gate_assignment_id  bigint PRIMARY KEY,
    airport_code        text NOT NULL REFERENCES airport(airport_code),
    gate_code           text NOT NULL,
    flight_id           bigint NOT NULL REFERENCES flight_schedule(flight_id),
    planned_start       timestamptz NOT NULL,
    planned_end         timestamptz NOT NULL,
    CHECK (planned_end > planned_start)
);

CREATE TABLE passenger_connection (
    connection_id       bigint PRIMARY KEY,
    passenger_id        text NOT NULL,
    inbound_flight_id   bigint NOT NULL REFERENCES flight_schedule(flight_id),
    outbound_flight_id  bigint NOT NULL REFERENCES flight_schedule(flight_id),
    connection_airport  text NOT NULL REFERENCES airport(airport_code),
    CHECK (inbound_flight_id <> outbound_flight_id)
);

INSERT INTO airport
    (airport_code, airport_name, city, timezone_name, min_connection_minutes)
VALUES
    ('BOM', 'Chhatrapati Shivaji Maharaj International', 'Mumbai',
     'Asia/Kolkata', 45),
    ('DEL', 'Indira Gandhi International', 'Delhi',
     'Asia/Kolkata', 45),
    ('BLR', 'Kempegowda International', 'Bengaluru',
     'Asia/Kolkata', 45),
    ('HYD', 'Rajiv Gandhi International', 'Hyderabad',
     'Asia/Kolkata', 35),
    ('PNQ', 'Pune Airport', 'Pune',
     'Asia/Kolkata', 30);

INSERT INTO aircraft (tail_number, aircraft_type, min_turn_minutes)
VALUES
    ('VT-ABC', 'A320', 45),
    ('VT-XYZ', 'ATR72', 30),
    ('VT-PQR', 'A320', 45);

INSERT INTO flight_schedule
    (flight_id, airline_code, flight_number, operating_date,
     origin, destination, scheduled_departure, scheduled_arrival,
     tail_number, seat_capacity)
VALUES
    (1001, 'IX', 'IX101', DATE '2026-11-14', 'BOM', 'DEL',
     TIMESTAMPTZ '2026-11-14 06:00:00+05:30',
     TIMESTAMPTZ '2026-11-14 08:10:00+05:30', 'VT-ABC', 180),
    (1002, 'IX', 'IX102', DATE '2026-11-14', 'DEL', 'BLR',
     TIMESTAMPTZ '2026-11-14 09:00:00+05:30',
     TIMESTAMPTZ '2026-11-14 11:45:00+05:30', 'VT-ABC', 180),
    (1003, 'IX', 'IX103', DATE '2026-11-14', 'BLR', 'BOM',
     TIMESTAMPTZ '2026-11-14 13:00:00+05:30',
     TIMESTAMPTZ '2026-11-14 14:40:00+05:30', 'VT-ABC', 180),
    -- Deliberately short turn after flight 1003: 40 minutes versus 45 required.
    (1004, 'IX', 'IX104', DATE '2026-11-14', 'BOM', 'PNQ',
     TIMESTAMPTZ '2026-11-14 15:20:00+05:30',
     TIMESTAMPTZ '2026-11-14 16:30:00+05:30', 'VT-ABC', 180),

    (2001, 'QP', 'QP201', DATE '2026-11-14', 'PNQ', 'HYD',
     TIMESTAMPTZ '2026-11-14 07:00:00+05:30',
     TIMESTAMPTZ '2026-11-14 08:15:00+05:30', 'VT-XYZ', 72),
    (2002, 'QP', 'QP202', DATE '2026-11-14', 'HYD', 'PNQ',
     TIMESTAMPTZ '2026-11-14 09:00:00+05:30',
     TIMESTAMPTZ '2026-11-14 10:20:00+05:30', 'VT-XYZ', 72),

    (3001, 'IX', 'IX301', DATE '2026-11-14', 'DEL', 'HYD',
     TIMESTAMPTZ '2026-11-14 08:30:00+05:30',
     TIMESTAMPTZ '2026-11-14 10:45:00+05:30', 'VT-PQR', 180),
    (3002, 'IX', 'IX302', DATE '2026-11-14', 'HYD', 'DEL',
     TIMESTAMPTZ '2026-11-14 12:00:00+05:30',
     TIMESTAMPTZ '2026-11-14 14:15:00+05:30', 'VT-PQR', 180),
    (3003, 'IX', 'IX303', DATE '2026-11-14', 'DEL', 'BOM',
     TIMESTAMPTZ '2026-11-14 15:00:00+05:30',
     TIMESTAMPTZ '2026-11-14 17:10:00+05:30', 'VT-PQR', 180);

-- Event priority: 1 is the preferred airline operations feed; larger values
-- are lower-priority sources. Later source updates win before ingestion tie-breaks.
INSERT INTO flight_status_event
    (event_id, flight_id, event_type, event_time, source_updated_at,
     source_priority, source_sequence, ingested_at, source_event_key)
VALUES
    -- Flight 1001 has an old event, a correction, and a replay of that correction.
    (1, 1001, 'DEPARTED',
     TIMESTAMPTZ '2026-11-14 06:15:00+05:30',
     TIMESTAMPTZ '2026-11-14 06:16:00+05:30', 2, 1,
     TIMESTAMPTZ '2026-11-14 06:17:00+05:30', 'OPS-1001-DEP-1'),
    (2, 1001, 'DEPARTED',
     TIMESTAMPTZ '2026-11-14 06:18:00+05:30',
     TIMESTAMPTZ '2026-11-14 06:19:00+05:30', 1, 2,
     TIMESTAMPTZ '2026-11-14 06:20:00+05:30', 'OPS-1001-DEP-2'),
    (3, 1001, 'DEPARTED',
     TIMESTAMPTZ '2026-11-14 06:18:00+05:30',
     TIMESTAMPTZ '2026-11-14 06:19:00+05:30', 1, 2,
     TIMESTAMPTZ '2026-11-14 06:22:00+05:30', 'OPS-1001-DEP-2'),
    (4, 1001, 'ARRIVED',
     TIMESTAMPTZ '2026-11-14 08:35:00+05:30',
     TIMESTAMPTZ '2026-11-14 08:36:00+05:30', 1, 3,
     TIMESTAMPTZ '2026-11-14 08:37:00+05:30', 'OPS-1001-ARR-1'),

    (5, 1002, 'DEPARTED',
     TIMESTAMPTZ '2026-11-14 09:25:00+05:30',
     TIMESTAMPTZ '2026-11-14 09:26:00+05:30', 1, 1,
     TIMESTAMPTZ '2026-11-14 09:27:00+05:30', 'OPS-1002-DEP-1'),
    (6, 1002, 'ARRIVED',
     TIMESTAMPTZ '2026-11-14 12:00:00+05:30',
     TIMESTAMPTZ '2026-11-14 12:01:00+05:30', 1, 2,
     TIMESTAMPTZ '2026-11-14 12:02:00+05:30', 'OPS-1002-ARR-1'),

    (7, 1003, 'DEPARTED',
     TIMESTAMPTZ '2026-11-14 13:08:00+05:30',
     TIMESTAMPTZ '2026-11-14 13:09:00+05:30', 1, 1,
     TIMESTAMPTZ '2026-11-14 13:10:00+05:30', 'OPS-1003-DEP-1'),
    (8, 1003, 'ARRIVED',
     TIMESTAMPTZ '2026-11-14 14:50:00+05:30',
     TIMESTAMPTZ '2026-11-14 14:51:00+05:30', 1, 2,
     TIMESTAMPTZ '2026-11-14 14:52:00+05:30', 'OPS-1003-ARR-1'),

    (9, 2001, 'DEPARTED',
     TIMESTAMPTZ '2026-11-14 07:02:00+05:30',
     TIMESTAMPTZ '2026-11-14 07:03:00+05:30', 1, 1,
     TIMESTAMPTZ '2026-11-14 07:04:00+05:30', 'OPS-2001-DEP-1'),
    (10, 2001, 'ARRIVED',
     TIMESTAMPTZ '2026-11-14 08:25:00+05:30',
     TIMESTAMPTZ '2026-11-14 08:26:00+05:30', 1, 2,
     TIMESTAMPTZ '2026-11-14 08:27:00+05:30', 'OPS-2001-ARR-1'),
    (11, 2002, 'DEPARTED',
     TIMESTAMPTZ '2026-11-14 09:12:00+05:30',
     TIMESTAMPTZ '2026-11-14 09:13:00+05:30', 1, 1,
     TIMESTAMPTZ '2026-11-14 09:14:00+05:30', 'OPS-2002-DEP-1'),
    (12, 2002, 'ARRIVED',
     TIMESTAMPTZ '2026-11-14 10:35:00+05:30',
     TIMESTAMPTZ '2026-11-14 10:36:00+05:30', 1, 2,
     TIMESTAMPTZ '2026-11-14 10:37:00+05:30', 'OPS-2002-ARR-1'),

    (13, 3001, 'DEPARTED',
     TIMESTAMPTZ '2026-11-14 08:50:00+05:30',
     TIMESTAMPTZ '2026-11-14 08:51:00+05:30', 1, 1,
     TIMESTAMPTZ '2026-11-14 08:52:00+05:30', 'OPS-3001-DEP-1'),
    (14, 3001, 'ARRIVED',
     TIMESTAMPTZ '2026-11-14 11:10:00+05:30',
     TIMESTAMPTZ '2026-11-14 11:11:00+05:30', 1, 2,
     TIMESTAMPTZ '2026-11-14 11:12:00+05:30', 'OPS-3001-ARR-1'),

    -- Deliberately contradictory feed records for Q9 quality-control practice.
    (15, 3002, 'CANCELLED',
     TIMESTAMPTZ '2026-11-14 11:40:00+05:30',
     TIMESTAMPTZ '2026-11-14 11:41:00+05:30', 1, 1,
     TIMESTAMPTZ '2026-11-14 11:42:00+05:30', 'OPS-3002-CXL-1'),
    (16, 3002, 'DEPARTED',
     TIMESTAMPTZ '2026-11-14 12:10:00+05:30',
     TIMESTAMPTZ '2026-11-14 12:11:00+05:30', 2, 1,
     TIMESTAMPTZ '2026-11-14 12:12:00+05:30', 'AIRPORT-3002-DEP-1'),

    (17, 3003, 'DEPARTED',
     TIMESTAMPTZ '2026-11-14 15:35:00+05:30',
     TIMESTAMPTZ '2026-11-14 15:36:00+05:30', 1, 1,
     TIMESTAMPTZ '2026-11-14 15:37:00+05:30', 'OPS-3003-DEP-1'),
    (18, 3003, 'ARRIVED',
     TIMESTAMPTZ '2026-11-14 17:50:00+05:30',
     TIMESTAMPTZ '2026-11-14 17:51:00+05:30', 1, 2,
     TIMESTAMPTZ '2026-11-14 17:52:00+05:30', 'OPS-3003-ARR-1');

INSERT INTO gate_assignment
    (gate_assignment_id, airport_code, gate_code, flight_id, planned_start, planned_end)
VALUES
    (5001, 'DEL', 'D2', 1001,
     TIMESTAMPTZ '2026-11-14 08:00:00+05:30',
     TIMESTAMPTZ '2026-11-14 08:50:00+05:30'),
    (5002, 'DEL', 'D2', 1002,
     TIMESTAMPTZ '2026-11-14 08:35:00+05:30',
     TIMESTAMPTZ '2026-11-14 09:20:00+05:30'),
    (5003, 'HYD', 'H1', 2001,
     TIMESTAMPTZ '2026-11-14 08:00:00+05:30',
     TIMESTAMPTZ '2026-11-14 08:45:00+05:30'),
    (5004, 'HYD', 'H1', 2002,
     TIMESTAMPTZ '2026-11-14 08:40:00+05:30',
     TIMESTAMPTZ '2026-11-14 09:25:00+05:30');

INSERT INTO passenger_connection
    (connection_id, passenger_id, inbound_flight_id, outbound_flight_id, connection_airport)
VALUES
    (7001, 'PAX-001', 1001, 1002, 'DEL'),
    (7002, 'PAX-002', 1001, 1002, 'DEL'),
    (7003, 'PAX-003', 2001, 2002, 'HYD'),
    (7004, 'PAX-004', 1002, 1003, 'BLR'),
    (7005, 'PAX-005', 3001, 3002, 'HYD'),
    (7006, 'PAX-006', 3001, 3002, 'HYD');

-- Indexes align with common access paths. Benchmark before retaining them
-- on a high-write production event stream.
CREATE INDEX ix_flight_schedule_rotation
    ON flight_schedule (tail_number, scheduled_departure)
    INCLUDE (flight_id, origin, destination, scheduled_arrival);

CREATE INDEX ix_flight_schedule_route_day
    ON flight_schedule (operating_date, airline_code, origin, destination);

CREATE INDEX ix_flight_event_canonical
    ON flight_status_event
       (flight_id, event_type, source_updated_at DESC,
        source_priority, source_sequence DESC, ingested_at DESC, event_id DESC);

CREATE INDEX ix_passenger_connection_flights
    ON passenger_connection (inbound_flight_id, outbound_flight_id);

CREATE INDEX ix_gate_assignment_location
    ON gate_assignment (airport_code, gate_code);

-- The range expression allows GiST overlap searches. A separate B-tree index
-- supports airport/gate equality predicates.
CREATE INDEX ix_gate_assignment_window
    ON gate_assignment
    USING gist (tstzrange(planned_start, planned_end, '[)'));

-- One deterministic winner per flight and event type:
-- latest source update, preferred source, latest source sequence, latest
-- ingestion, then immutable event ID.
CREATE OR REPLACE VIEW v_canonical_flight_event AS
SELECT DISTINCT ON (flight_id, event_type)
       event_id,
       flight_id,
       event_type,
       event_time,
       source_updated_at,
       source_priority,
       source_sequence,
       ingested_at,
       source_event_key
FROM flight_status_event
ORDER BY flight_id,
         event_type,
         source_updated_at DESC,
         source_priority ASC,
         source_sequence DESC,
         ingested_at DESC,
         event_id DESC;

CREATE OR REPLACE VIEW v_flight_actuals AS
SELECT flight_id,
       MAX(event_time) FILTER (WHERE event_type = 'DEPARTED') AS actual_departure,
       MAX(event_time) FILTER (WHERE event_type = 'ARRIVED') AS actual_arrival,
       BOOL_OR(event_type = 'CANCELLED') AS is_cancelled
FROM v_canonical_flight_event
GROUP BY flight_id;

-- ============================================================================
-- PROBLEM 1 — Replay and correction audit
-- Return flight/event-type keys with multiple source deliveries, the raw
-- delivery count, and the canonical event selected by the deterministic rule.
--
-- OPTIMIZED SOLUTION:
-- SELECT r.flight_id,
--        r.event_type,
--        COUNT(*) AS source_deliveries,
--        c.event_id AS canonical_event_id,
--        c.event_time AS canonical_event_time,
--        c.source_event_key
-- FROM flight_status_event r
-- JOIN v_canonical_flight_event c
--   ON c.flight_id = r.flight_id
--  AND c.event_type = r.event_type
-- GROUP BY r.flight_id, r.event_type,
--          c.event_id, c.event_time, c.source_event_key
-- HAVING COUNT(*) > 1
-- ORDER BY r.flight_id, r.event_type;
--
-- EXPECTED SPOT CHECK:
-- Flight 1001 / DEPARTED has three deliveries. Event 3 wins because its source
-- update and priority tie event 2, while its ingestion timestamp is later.
--
-- WHY THIS IS OPTIMIZED:
-- DISTINCT ON expresses PostgreSQL's ordered first-row-per-group operation.
-- The index begins with the grouping key and follows the winner ordering, so
-- PostgreSQL can consider an ordered index path instead of an unrelated sort.
-- The planner may still prefer a sequential scan for this deliberately small
-- sample; inspect the actual plan rather than assuming index usage.

-- ============================================================================
-- PROBLEM 2 — Route-level departure and arrival on-time performance
-- For each operating date, airline, and route, report scheduled flights,
-- cancellations, completed flights, departure OTP, and arrival OTP.
-- A flight is on time when it is no more than 15 minutes late.
--
-- OPTIMIZED SOLUTION:
-- WITH outcomes AS (
--     SELECT f.operating_date,
--            f.airline_code,
--            f.origin,
--            f.destination,
--            f.flight_id,
--            f.scheduled_departure,
--            f.scheduled_arrival,
--            a.actual_departure,
--            a.actual_arrival,
--            COALESCE(a.is_cancelled, false) AS is_cancelled
--     FROM flight_schedule f
--     LEFT JOIN v_flight_actuals a ON a.flight_id = f.flight_id
-- )
-- SELECT operating_date,
--        airline_code,
--        origin,
--        destination,
--        COUNT(*) AS scheduled_flights,
--        COUNT(*) FILTER (WHERE is_cancelled) AS cancelled_flights,
--        COUNT(*) FILTER (
--            WHERE NOT is_cancelled
--              AND actual_departure IS NOT NULL
--              AND actual_arrival IS NOT NULL
--        ) AS completed_flights,
--        ROUND(
--            100.0 * COUNT(*) FILTER (
--                WHERE NOT is_cancelled
--                  AND actual_departure IS NOT NULL
--                  AND actual_departure <= scheduled_departure + INTERVAL '15 minutes'
--            )
--            / NULLIF(COUNT(*) FILTER (
--                WHERE NOT is_cancelled AND actual_departure IS NOT NULL
--            ), 0),
--            2
--        ) AS departure_otp_pct,
--        ROUND(
--            100.0 * COUNT(*) FILTER (
--                WHERE NOT is_cancelled
--                  AND actual_arrival IS NOT NULL
--                  AND actual_arrival <= scheduled_arrival + INTERVAL '15 minutes'
--            )
--            / NULLIF(COUNT(*) FILTER (
--                WHERE NOT is_cancelled AND actual_arrival IS NOT NULL
--            ), 0),
--            2
--        ) AS arrival_otp_pct
-- FROM outcomes
-- GROUP BY operating_date, airline_code, origin, destination
-- ORDER BY operating_date, airline_code, origin, destination;
--
-- WHY THIS IS OPTIMIZED:
-- The actuals view reduces status events to one row per flight before joining,
-- preventing replayed events from multiplying scheduled-flight counts.
-- Scheduled timestamps are projected once and compared directly; there are no
-- correlated lookups. FILTER aggregates calculate all route metrics in one
-- grouped pass. Keep cancellations separate from missing telemetry so an
-- unreported flight is not silently classified as either cancelled or completed.

-- PROBLEM 3 — Airport departure-delay distribution
-- For each origin airport, calculate completed-flight count, average positive
-- departure delay, median delay, and P95 delay in minutes.
--
-- OPTIMIZED SOLUTION:
-- WITH departure_delay AS (
--     SELECT f.origin AS airport_code,
--            GREATEST(
--                EXTRACT(EPOCH FROM (a.actual_departure - f.scheduled_departure))
--                / 60.0,
--                0
--            ) AS delay_minutes
--     FROM flight_schedule f
--     JOIN v_flight_actuals a ON a.flight_id = f.flight_id
--     WHERE NOT COALESCE(a.is_cancelled, false)
--       AND a.actual_departure IS NOT NULL
-- )
-- SELECT airport_code,
--        COUNT(*) AS departed_flights,
--        ROUND(AVG(delay_minutes)::numeric, 2) AS avg_delay_minutes,
--        ROUND(
--            PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY delay_minutes)::numeric,
--            2
--        ) AS median_delay_minutes,
--        ROUND(
--            PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY delay_minutes)::numeric,
--            2
--        ) AS p95_delay_minutes
-- FROM departure_delay
-- GROUP BY airport_code
-- ORDER BY p95_delay_minutes DESC;
--
-- WHY THIS IS OPTIMIZED:
-- Calculate delay once in a narrow CTE and reuse it for all distribution
-- statistics. The canonical actuals relation ensures one departure per flight.
-- Ordered-set percentiles require sorting within each group; on large datasets,
-- pre-aggregate by airport/day or use an approved approximate percentile
-- implementation when exact P95 is not a reporting requirement.

-- ============================================================================
-- PROBLEM 4 — Actual aircraft turnaround and delay propagation
-- For consecutive operated legs on the same aircraft, calculate actual
-- turnaround minutes and the change between inbound arrival delay and the
-- next flight's departure delay.
--
-- OPTIMIZED SOLUTION:
-- WITH legs AS (
--     SELECT f.flight_id,
--            f.tail_number,
--            f.origin,
--            f.destination,
--            f.scheduled_departure,
--            f.scheduled_arrival,
--            a.actual_departure,
--            a.actual_arrival,
--            COALESCE(a.is_cancelled, false) AS is_cancelled
--     FROM flight_schedule f
--     LEFT JOIN v_flight_actuals a ON a.flight_id = f.flight_id
-- ),
-- chained AS (
--     SELECT *,
--            LAG(flight_id) OVER w AS prior_flight_id,
--            LAG(destination) OVER w AS prior_destination,
--            LAG(scheduled_arrival) OVER w AS prior_scheduled_arrival,
--            LAG(actual_arrival) OVER w AS prior_actual_arrival,
--            LAG(is_cancelled) OVER w AS prior_cancelled
--     FROM legs
--     WINDOW w AS (
--         PARTITION BY tail_number
--         ORDER BY scheduled_departure, flight_id
--     )
-- )
-- SELECT tail_number,
--        prior_flight_id,
--        flight_id AS next_flight_id,
--        ROUND(
--            (EXTRACT(EPOCH FROM (actual_departure - prior_actual_arrival))
--             / 60.0)::numeric,
--            2
--        ) AS actual_turn_minutes,
--        ROUND(
--            (EXTRACT(EPOCH FROM (actual_arrival - scheduled_arrival))
--             / 60.0)::numeric,
--            2
--        ) AS current_arrival_delay_minutes,
--        ROUND(
--            (
--              EXTRACT(EPOCH FROM (actual_departure - scheduled_departure))
--              / 60.0
--              -
--              EXTRACT(EPOCH FROM (prior_actual_arrival - prior_scheduled_arrival))
--              / 60.0
--            )::numeric,
--            2
--        ) AS delay_change_minutes
-- FROM chained
-- WHERE prior_flight_id IS NOT NULL
--   AND prior_destination = origin
--   AND prior_actual_arrival IS NOT NULL
--   AND actual_departure IS NOT NULL
--   AND NOT is_cancelled
--   AND NOT COALESCE(prior_cancelled, false)
-- ORDER BY tail_number, scheduled_departure;
--
-- EXPECTED SPOT CHECK:
-- VT-ABC has a 50-minute actual turn from flight 1001 to 1002 and a 68-minute
-- actual turn from flight 1002 to 1003.
--
-- WHY THIS IS OPTIMIZED:
-- One ordered window pass calculates all prior-leg attributes. Partitioning by
-- tail_number and ordering by scheduled_departure matches the rotation index.
-- Airport continuity and cancellation checks prevent unrelated or cancelled
-- legs from being treated as valid turnarounds.

-- ============================================================================
-- PROBLEM 5 — Passenger connection feasibility
-- Classify each booked connection using the airport's MCT and actual inbound
-- arrival/outbound departure. Distinguish cancellation, missing telemetry,
-- feasible connections, and missed connections.
--
-- OPTIMIZED SOLUTION:
-- SELECT pc.connection_id,
--        pc.passenger_id,
--        pc.connection_airport,
--        pc.inbound_flight_id,
--        pc.outbound_flight_id,
--        ap.min_connection_minutes,
--        ia.actual_arrival AS inbound_actual_arrival,
--        oa.actual_departure AS outbound_actual_departure,
--        ROUND(
--            (
--              EXTRACT(EPOCH FROM (
--                  oa.actual_departure
--                  - ia.actual_arrival
--                  - make_interval(mins => ap.min_connection_minutes)
--              )) / 60.0
--            )::numeric,
--            2
--        ) AS actual_slack_minutes,
--        CASE
--          WHEN COALESCE(ia.is_cancelled, false)
--            OR COALESCE(oa.is_cancelled, false)
--            THEN 'DISRUPTED_CANCELLED'
--          WHEN ia.actual_arrival IS NULL OR oa.actual_departure IS NULL
--            THEN 'PENDING_TELEMETRY'
--          WHEN ia.actual_arrival
--                 + make_interval(mins => ap.min_connection_minutes)
--               <= oa.actual_departure
--            THEN 'FEASIBLE'
--          ELSE 'MISSED'
--        END AS connection_result
-- FROM passenger_connection pc
-- JOIN airport ap ON ap.airport_code = pc.connection_airport
-- LEFT JOIN v_flight_actuals ia ON ia.flight_id = pc.inbound_flight_id
-- LEFT JOIN v_flight_actuals oa ON oa.flight_id = pc.outbound_flight_id
-- ORDER BY pc.connection_id;
--
-- WHY THIS IS OPTIMIZED:
-- Each connection row joins to two one-row-per-flight actuals relations and one
-- airport row. No event-level join is performed, so multiple status deliveries
-- cannot multiply passenger counts. In production, calculate connection
-- outcomes at passenger/booking grain before rolling up by airport or route.

-- ============================================================================
-- PROBLEM 6 — Overlapping gate assignments
-- Find pairs of different flights assigned to the same airport and gate whose
-- planned occupancy intervals overlap. Intervals use [start, end), so a flight
-- ending exactly when another starts is not a conflict.
--
-- OPTIMIZED SOLUTION:
-- SELECT a.airport_code,
--        a.gate_code,
--        a.flight_id AS flight_a,
--        b.flight_id AS flight_b,
--        GREATEST(a.planned_start, b.planned_start) AS overlap_start,
--        LEAST(a.planned_end, b.planned_end) AS overlap_end,
--        ROUND(
--            (
--              EXTRACT(EPOCH FROM (
--                  LEAST(a.planned_end, b.planned_end)
--                  - GREATEST(a.planned_start, b.planned_start)
--              )) / 60.0
--            )::numeric,
--            2
--        ) AS overlap_minutes
-- FROM gate_assignment a
-- JOIN gate_assignment b
--   ON b.airport_code = a.airport_code
--  AND b.gate_code = a.gate_code
--  AND b.gate_assignment_id > a.gate_assignment_id
--  AND tstzrange(a.planned_start, a.planned_end, '[)')
--      && tstzrange(b.planned_start, b.planned_end, '[)')
-- ORDER BY a.airport_code, a.gate_code, a.flight_id, b.flight_id;
--
-- EXPECTED SPOT CHECK:
-- DEL/D2 has an overlap between flights 1001 and 1002.
-- HYD/H1 has an overlap between flights 2001 and 2002.
--
-- WHY THIS IS OPTIMIZED:
-- The greater-than ID condition emits each unordered pair once and avoids
-- self-pairs. The equality index narrows the airport/gate candidate set, while
-- the GiST range index supports interval-overlap evaluation. For very large
-- schedules, constrain the operating-time window before generating pairs.

-- ============================================================================
-- PROBLEM 7 — Scheduled aircraft rotation feasibility
-- Identify consecutive scheduled legs that either do not connect at the same
-- airport or leave less than the aircraft type's minimum turn time.
--
-- OPTIMIZED SOLUTION:
-- WITH ordered_legs AS (
--     SELECT f.flight_id,
--            f.tail_number,
--            f.origin,
--            f.destination,
--            f.scheduled_departure,
--            f.scheduled_arrival,
--            a.min_turn_minutes,
--            LAG(f.flight_id) OVER w AS prior_flight_id,
--            LAG(f.destination) OVER w AS prior_destination,
--            LAG(f.scheduled_arrival) OVER w AS prior_scheduled_arrival
--     FROM flight_schedule f
--     JOIN aircraft a ON a.tail_number = f.tail_number
--     WINDOW w AS (
--         PARTITION BY f.tail_number
--         ORDER BY f.scheduled_departure, f.flight_id
--     )
-- )
-- SELECT tail_number,
--        prior_flight_id,
--        flight_id AS next_flight_id,
--        prior_destination,
--        origin AS next_origin,
--        min_turn_minutes,
--        ROUND(
--            (
--              EXTRACT(EPOCH FROM
--                (scheduled_departure - prior_scheduled_arrival)) / 60.0
--            )::numeric,
--            2
--        ) AS scheduled_turn_minutes,
--        CASE
--          WHEN prior_destination IS DISTINCT FROM origin
--            THEN 'AIRPORT_CONTINUITY_BREAK'
--          WHEN scheduled_departure
--                 < prior_scheduled_arrival
--                   + make_interval(mins => min_turn_minutes)
--            THEN 'INSUFFICIENT_TURN'
--        END AS exception_type
-- FROM ordered_legs
-- WHERE prior_flight_id IS NOT NULL
--   AND (
--       prior_destination IS DISTINCT FROM origin
--       OR scheduled_departure
--            < prior_scheduled_arrival + make_interval(mins => min_turn_minutes)
--   )
-- ORDER BY tail_number, scheduled_departure;
--
-- EXPECTED SPOT CHECK:
-- Flight 1004 is flagged: flight 1003 is scheduled to arrive at BOM at 14:40,
-- but flight 1004 departs BOM at 15:20, leaving 40 minutes against a 45-minute
-- minimum turn.
--
-- WHY THIS IS OPTIMIZED:
-- LAG evaluates each aircraft's schedule once in deterministic order. The
-- rotation index supports the partition/order pattern. Do not compare only
-- flight numbers or operating dates; use actual timestamps because overnight
-- rotations can cross calendar boundaries.

-- ============================================================================
-- PROBLEM 8 — Downstream exposure after a cancellation
-- For each cancelled flight, find later flights assigned to the same aircraft
-- within 12 hours. Show whether the next leg departs and whether its origin is
-- consistent with the cancelled leg's destination.
--
-- OPTIMIZED SOLUTION:
-- WITH cancelled AS (
--     SELECT f.flight_id,
--            f.tail_number,
--            f.origin,
--            f.destination,
--            f.scheduled_departure,
--            f.scheduled_arrival
--     FROM flight_schedule f
--     JOIN v_flight_actuals a ON a.flight_id = f.flight_id
--     WHERE a.is_cancelled
-- )
-- SELECT c.flight_id AS cancelled_flight_id,
--        c.tail_number,
--        n.flight_id AS downstream_flight_id,
--        n.origin AS downstream_origin,
--        n.scheduled_departure AS downstream_scheduled_departure,
--        na.actual_departure AS downstream_actual_departure,
--        CASE
--          WHEN n.origin = c.destination THEN 'AIRCRAFT_POSITION_CONTINUOUS'
--          ELSE 'POSITIONING_GAP'
--        END AS aircraft_position_check,
--        CASE
--          WHEN na.actual_departure IS NULL THEN 'NO_DEPARTURE_RECORDED'
--          WHEN na.actual_departure > n.scheduled_departure + INTERVAL '15 minutes'
--            THEN 'DEPARTED_LATE'
--          ELSE 'DEPARTED_WITHIN_15_MINUTES'
--        END AS downstream_status
-- FROM cancelled c
-- JOIN flight_schedule n
--   ON n.tail_number = c.tail_number
--  AND n.scheduled_departure > c.scheduled_departure
--  AND n.scheduled_departure <= c.scheduled_departure + INTERVAL '12 hours'
-- LEFT JOIN v_flight_actuals na ON na.flight_id = n.flight_id
-- ORDER BY c.flight_id, n.scheduled_departure;
--
-- EXPECTED SPOT CHECK:
-- Cancellation of flight 3002 exposes downstream flight 3003 on VT-PQR.
--
-- WHY THIS IS OPTIMIZED:
-- The cancellation set is reduced before joining to the same-tail schedule.
-- The rotation index supports the tail-number and departure-time range. A
-- 12-hour horizon bounds candidate rows; production recovery logic should
-- extend this into a dependency graph when aircraft swaps and ferry legs occur.

-- ============================================================================
-- PROBLEM 9 — Flight-event consistency exceptions
-- Return flights with contradictory cancellation/operation events, an arrival
-- without a departure, or an arrival timestamp that is not after departure.
--
-- OPTIMIZED SOLUTION:
-- WITH checks AS (
--     SELECT f.flight_id,
--            a.actual_departure,
--            a.actual_arrival,
--            COALESCE(a.is_cancelled, false) AS is_cancelled,
--            ARRAY_REMOVE(ARRAY[
--                CASE
--                  WHEN COALESCE(a.is_cancelled, false)
--                   AND (a.actual_departure IS NOT NULL
--                        OR a.actual_arrival IS NOT NULL)
--                  THEN 'CANCELLED_AND_OPERATED'
--                END,
--                CASE
--                  WHEN a.actual_arrival IS NOT NULL
--                   AND a.actual_departure IS NULL
--                  THEN 'ARRIVAL_WITHOUT_DEPARTURE'
--                END,
--                CASE
--                  WHEN a.actual_arrival IS NOT NULL
--                   AND a.actual_departure IS NOT NULL
--                   AND a.actual_arrival <= a.actual_departure
--                  THEN 'ARRIVAL_NOT_AFTER_DEPARTURE'
--                END
--            ], NULL) AS exception_codes
--     FROM flight_schedule f
--     LEFT JOIN v_flight_actuals a ON a.flight_id = f.flight_id
-- )
-- SELECT flight_id, actual_departure, actual_arrival, exception_codes
-- FROM checks
-- WHERE CARDINALITY(exception_codes) > 0
-- ORDER BY flight_id;
--
-- EXPECTED SPOT CHECK:
-- Flight 3002 is intentionally marked both CANCELLED and DEPARTED and should
-- return CANCELLED_AND_OPERATED.
--
-- WHY THIS IS OPTIMIZED:
-- Validate the canonical event set, not raw deliveries, so replays do not
-- inflate exception counts. The LEFT JOIN preserves scheduled flights with
-- missing telemetry. ARRAY_REMOVE builds multiple exception codes in one
-- projection rather than running a separate UNION query for every rule.

-- ============================================================================
-- PERFORMANCE LAB
--
-- 1. Compare the DISTINCT ON canonical view with a ROW_NUMBER() alternative:
--      ROW_NUMBER() OVER (
--        PARTITION BY flight_id, event_type
--        ORDER BY source_updated_at DESC, source_priority ASC,
--                 source_sequence DESC, ingested_at DESC, event_id DESC
--      )
--    Keep rn = 1 and verify that both approaches select identical event IDs.
--
-- 2. Run representative queries with:
--      EXPLAIN (ANALYZE, BUFFERS)
--    Inspect sort nodes, rows removed by filters, heap fetches, shared reads,
--    and whether the rotation, event, or GiST range indexes are selected.
--
-- 3. Keep timestamp predicates SARGable. Prefer:
--      scheduled_departure >= TIMESTAMPTZ '2026-11-14 00:00:00+05:30'
--      AND scheduled_departure <  TIMESTAMPTZ '2026-11-15 00:00:00+05:30'
--    over applying DATE(), DATE_TRUNC(), or timezone conversion to the indexed
--    scheduled_departure column in the WHERE clause.
--
-- 4. For high-volume event feeds, consider date-based partitioning on an
--    immutable event/ingestion date, replay retention policies, and an
--    incrementally maintained canonical flight-event table with a unique key
--    on (flight_id, event_type). Late corrections must invalidate/rebuild the
--    affected canonical key.
--
-- 5. Avoid joining raw status events directly to passenger connections,
--    gate assignments, or scheduled flights. Canonicalize to one row per
--    flight/event type and then one row per flight before analytical joins.
--
-- 6. Exact P95 and pairwise overlap checks can become expensive at scale.
--    Restrict the time window, pre-aggregate operational dashboards, and use
--    approximate quantiles only when metric governance permits them.
--
-- 7. Keep business definitions explicit: departure event versus off-block,
--    arrival event versus on-block, OTP tolerance, MCT, minimum turn time,
--    cancellations, diversions, and aircraft swaps are not interchangeable.
--    Production data models should preserve the source event and correction
--    history even when the reporting layer exposes a canonical state.
-- ============================================================================