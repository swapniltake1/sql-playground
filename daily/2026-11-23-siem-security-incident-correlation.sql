-- Daily SQL Practice — 2026-11-23
-- Topic: Defensive SIEM Event Correlation, Threat Intelligence & Incident SLAs
-- PostgreSQL 14+
--
-- Run independently in a disposable database. This script recreates only the
-- dedicated siem_practice schema. Solutions are commented so each problem can
-- be attempted before reviewing the reference approach.
--
-- Learning goals:
--   * canonicalize replayed, corrected, and tombstoned telemetry
--   * enrich events with point-in-time asset ownership
--   * detect authentication bursts with event-time windows
--   * correlate detections with effective-dated CIDR indicators
--   * persist alerts idempotently and sessionize them into incidents
--   * monitor response SLAs, ingestion lag, and payload quality

DROP SCHEMA IF EXISTS siem_practice CASCADE;
CREATE SCHEMA siem_practice;
SET search_path = siem_practice, public;
SET TIME ZONE 'UTC';

-- ---------------------------------------------------------------------------
-- 1. Independent practice schema
-- ---------------------------------------------------------------------------

CREATE TABLE asset_history (
    asset_id       BIGINT NOT NULL,
    hostname       TEXT NOT NULL,
    owner_team     TEXT NOT NULL,
    environment    TEXT NOT NULL,
    criticality    TEXT NOT NULL CHECK (criticality IN ('LOW','MEDIUM','HIGH','CRITICAL')),
    valid_from     TIMESTAMPTZ NOT NULL,
    valid_to       TIMESTAMPTZ,
    PRIMARY KEY (asset_id, valid_from),
    CHECK (valid_to IS NULL OR valid_to > valid_from)
);

-- Deliberately no FK from raw_events.asset_id: an unknown asset is a valid
-- landing-zone condition that Q10 must detect rather than reject at ingestion.
CREATE TABLE raw_events (
    event_id          BIGINT PRIMARY KEY,
    source_system     TEXT NOT NULL,
    source_event_key  TEXT NOT NULL,
    revision          INTEGER NOT NULL CHECK (revision > 0),
    asset_id          BIGINT,
    actor             TEXT,
    event_type        TEXT NOT NULL,
    outcome           TEXT,
    src_ip            INET,
    event_ts          TIMESTAMPTZ NOT NULL,
    ingested_at       TIMESTAMPTZ NOT NULL,
    severity          SMALLINT CHECK (severity BETWEEN 1 AND 10),
    payload           JSONB NOT NULL DEFAULT '{}'::jsonb,
    is_tombstone      BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE threat_indicators (
    indicator_id       BIGINT PRIMARY KEY,
    indicator_name     TEXT NOT NULL,
    indicator_network  CIDR NOT NULL,
    confidence         SMALLINT NOT NULL CHECK (confidence BETWEEN 0 AND 100),
    valid_from         TIMESTAMPTZ NOT NULL,
    valid_to           TIMESTAMPTZ NOT NULL,
    CHECK (valid_to > valid_from)
);

CREATE TABLE alerts (
    alert_id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    dedupe_key      TEXT NOT NULL UNIQUE,
    rule_name       TEXT NOT NULL,
    actor           TEXT,
    src_ip          INET,
    asset_id        BIGINT,
    first_event_ts  TIMESTAMPTZ NOT NULL,
    last_event_ts   TIMESTAMPTZ NOT NULL,
    hit_count       INTEGER NOT NULL CHECK (hit_count > 0),
    severity        SMALLINT NOT NULL CHECK (severity BETWEEN 1 AND 10),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (last_event_ts >= first_event_ts)
);

CREATE TABLE incident_cases (
    case_id          BIGINT PRIMARY KEY,
    incident_key     TEXT NOT NULL UNIQUE,
    opened_at        TIMESTAMPTZ NOT NULL,
    acknowledged_at  TIMESTAMPTZ,
    resolved_at      TIMESTAMPTZ,
    severity         TEXT NOT NULL CHECK (severity IN ('LOW','MEDIUM','HIGH','CRITICAL')),
    status           TEXT NOT NULL CHECK (status IN ('OPEN','IN_PROGRESS','RESOLVED')),
    owner_team       TEXT NOT NULL,
    CHECK (acknowledged_at IS NULL OR acknowledged_at >= opened_at),
    CHECK (resolved_at IS NULL OR resolved_at >= opened_at)
);

-- ---------------------------------------------------------------------------
-- 2. Synthetic reference data
-- ---------------------------------------------------------------------------

INSERT INTO asset_history
    (asset_id, hostname, owner_team, environment, criticality, valid_from, valid_to)
VALUES
    (101, 'auth-gateway-01', 'SecOps', 'PROD', 'CRITICAL',
     '2026-01-01 00:00+00', NULL),
    (102, 'vpn-edge-02', 'Network Security', 'PROD', 'CRITICAL',
     '2026-01-01 00:00+00', NULL),
    (103, 'build-runner-07', 'DevOps', 'PROD', 'HIGH',
     '2026-01-01 00:00+00', '2026-11-23 12:00+00'),
    (103, 'build-runner-07', 'Platform Engineering', 'PROD', 'HIGH',
     '2026-11-23 12:00+00', NULL),
    (104, 'sales-laptop-44', 'Workplace IT', 'CORP', 'MEDIUM',
     '2026-01-01 00:00+00', NULL),
    (105, 'customer-db-01', 'Data Platform', 'PROD', 'CRITICAL',
     '2026-01-01 00:00+00', NULL);

INSERT INTO raw_events
    (event_id, source_system, source_event_key, revision, asset_id, actor,
     event_type, outcome, src_ip, event_ts, ingested_at, severity, payload, is_tombstone)
VALUES
    (1, 'EDR', 'auth-001', 1, 102, 'alice', 'AUTH', 'FAIL', '198.51.100.23',
     '2026-11-23 09:00:00+00', '2026-11-23 09:00:05+00', 5,
     '{"source":"linux","process":"sshd","event_version":1}', FALSE),
    (2, 'EDR', 'auth-002', 1, 102, 'alice', 'AUTH', 'FAIL', '198.51.100.23',
     '2026-11-23 09:02:00+00', '2026-11-23 09:02:03+00', 5,
     '{"source":"linux","process":"sshd","event_version":1}', FALSE),
    (3, 'EDR', 'auth-003', 1, 102, 'alice', 'AUTH', 'FAIL', '198.51.100.23',
     '2026-11-23 09:04:00+00', '2026-11-23 09:04:02+00', 5,
     '{"source":"linux","process":"sshd","event_version":1}', FALSE),
    -- Same logical event and revision delivered again: keep the latest ingest.
    (4, 'EDR', 'auth-003', 1, 102, 'alice', 'AUTH', 'FAIL', '198.51.100.23',
     '2026-11-23 09:04:00+00', '2026-11-23 09:10:00+00', 5,
     '{"source":"linux","process":"sshd","event_version":1}', FALSE),
    -- A higher revision corrects the event timestamp.
    (5, 'EDR', 'auth-003', 2, 102, 'alice', 'AUTH', 'FAIL', '198.51.100.23',
     '2026-11-23 09:04:30+00', '2026-11-23 09:12:00+00', 5,
     '{"source":"linux","process":"sshd","event_version":2}', FALSE),
    (6, 'EDR', 'auth-004', 1, 102, 'alice', 'AUTH', 'FAIL', '198.51.100.23',
     '2026-11-23 09:06:00+00', '2026-11-23 09:06:04+00', 5,
     '{"source":"linux","process":"sshd","event_version":1}', FALSE),
    (7, 'EDR', 'auth-005', 1, 102, 'alice', 'AUTH', 'FAIL', '198.51.100.23',
     '2026-11-23 09:08:00+00', '2026-11-23 09:08:03+00', 6,
     '{"source":"linux","process":"sshd","event_version":1}', FALSE),
    (8, 'EDR', 'auth-006', 1, 102, 'alice', 'AUTH', 'SUCCESS', '198.51.100.23',
     '2026-11-23 09:10:00+00', '2026-11-23 09:10:02+00', 4,
     '{"source":"linux","process":"sshd","event_version":1}', FALSE),
    (9, 'EDR', 'proc-001', 1, 103, 'svc-deploy', 'PROCESS', 'EXEC',
     '203.0.113.66', '2026-11-23 10:00:00+00', '2026-11-23 10:00:04+00', 7,
     '{"source":"linux","process":"curl","event_version":1}', FALSE),
    (10, 'NETFLOW', 'net-001', 1, 103, 'svc-deploy', 'NETWORK', 'CONNECT',
     '203.0.113.66', '2026-11-23 10:05:00+00', '2026-11-23 10:05:08+00', 6,
     '{"source":"netflow","destination_port":443,"event_version":1}', FALSE),
    (11, 'EDR', 'auth-007', 1, 102, 'bob', 'AUTH', 'FAIL', '198.51.100.44',
     '2026-11-23 10:30:00+00', '2026-11-23 10:30:03+00', 4,
     '{"source":"linux","process":"sshd","event_version":1}', FALSE),
    (12, 'EDR', 'auth-008', 1, 102, 'bob', 'AUTH', 'FAIL', '198.51.100.44',
     '2026-11-23 10:32:00+00', '2026-11-23 10:32:03+00', 4,
     '{"source":"linux","process":"sshd","event_version":1}', FALSE),
    -- Late arrival: event time is 08:55 but ingestion occurs after 11:00.
    (13, 'EDR', 'auth-late-001', 1, 101, 'dave', 'AUTH', 'FAIL', '198.51.100.99',
     '2026-11-23 08:55:00+00', '2026-11-23 11:30:00+00', 5,
     '{"source":"linux","process":"sshd","event_version":1}', FALSE),
    -- This logical event is removed by a later tombstone revision.
    (14, 'EDR', 'heartbeat-old-001', 1, 101, 'agent-101', 'HEARTBEAT', 'OK',
     '192.0.2.10', '2026-11-23 08:30:00+00', '2026-11-23 08:30:02+00', 1,
     '{"source":"agent","event_version":1}', FALSE),
    (15, 'EDR', 'heartbeat-old-001', 2, 101, 'agent-101', 'HEARTBEAT', 'OK',
     '192.0.2.10', '2026-11-23 08:30:00+00', '2026-11-23 09:20:00+00', 1,
     '{"source":"agent","event_version":2}', TRUE),
    -- Unknown asset is intentionally accepted by the landing table.
    (16, 'EDR', 'proc-orphan-001', 1, 999, 'mallory', 'PROCESS', 'EXEC',
     '192.0.2.77', '2026-11-23 11:00:00+00', '2026-11-23 11:00:03+00', 8,
     '{"source":"linux","process":"unknown","event_version":1}', FALSE),
    -- Malformed actor and payload are intentional quality exceptions.
    (17, 'EDR', 'proc-bad-001', 1, 101, ' ', 'PROCESS', 'EXEC', NULL,
     '2026-11-23 11:05:00+00', '2026-11-23 11:05:03+00', 3,
     '{"process":"bash","event_version":"v1"}', FALSE),
    -- Same indicator network, but this event occurs after its validity window.
    (18, 'EDR', 'proc-expired-ioc-001', 1, 103, 'svc-deploy', 'PROCESS', 'EXEC',
     '203.0.113.66', '2026-11-23 10:45:00+00', '2026-11-23 10:45:03+00', 5,
     '{"source":"linux","process":"python","event_version":1}', FALSE),
    (19, 'EDR', 'proc-002', 1, 103, 'svc-deploy', 'PROCESS', 'EXEC',
     '203.0.113.66', '2026-11-23 10:20:00+00', '2026-11-23 10:20:04+00', 6,
     '{"source":"linux","process":"python","event_version":1}', FALSE),
    -- Demonstrates point-in-time ownership after the asset team transfer.
    (20, 'EDR', 'proc-post-transfer-001', 1, 103, 'ci-bot', 'PROCESS', 'EXEC',
     '192.0.2.20', '2026-11-23 13:00:00+00', '2026-11-23 13:00:02+00', 2,
     '{"source":"linux","process":"runner","event_version":1}', FALSE);

INSERT INTO threat_indicators
    (indicator_id, indicator_name, indicator_network, confidence, valid_from, valid_to)
VALUES
    (1, 'Known command-and-control range', '203.0.113.64/27', 96,
     '2026-11-23 09:00:00+00', '2026-11-23 10:30:00+00'),
    -- Intentional duplicate network with overlapping validity for Q11.
    (2, 'Temporary vendor feed duplicate', '203.0.113.64/27', 82,
     '2026-11-23 10:00:00+00', '2026-11-23 11:00:00+00'),
    (3, 'Known password-spray source', '198.51.100.23/32', 91,
     '2026-11-23 08:30:00+00', '2026-11-23 09:15:00+00'),
    (4, 'Expired scanner indicator', '203.0.113.66/32', 70,
     '2026-11-22 00:00:00+00', '2026-11-23 08:00:00+00');

INSERT INTO incident_cases
    (case_id, incident_key, opened_at, acknowledged_at, resolved_at,
     severity, status, owner_team)
VALUES
    (7001, 'INC-2026-001', '2026-11-23 09:12:00+00', '2026-11-23 09:18:00+00',
     '2026-11-23 11:00:00+00', 'CRITICAL', 'RESOLVED', 'SecOps'),
    (7002, 'INC-2026-002', '2026-11-23 10:05:00+00', '2026-11-23 10:12:00+00',
     NULL, 'HIGH', 'IN_PROGRESS', 'Platform Engineering'),
    (7003, 'INC-2026-003', '2026-11-23 11:00:00+00', '2026-11-23 12:05:00+00',
     '2026-11-23 13:30:00+00', 'MEDIUM', 'RESOLVED', 'Workplace IT'),
    (7004, 'INC-2026-004', '2026-11-23 13:00:00+00', NULL,
     NULL, 'LOW', 'OPEN', 'Network Security');

-- ---------------------------------------------------------------------------
-- 3. Numbered problems and commented reference solutions
-- ---------------------------------------------------------------------------

-- Q1. Canonicalize replayed, corrected, and tombstoned events.
-- For each (source_system, source_event_key), select the highest revision;
-- break ties by latest ingestion and event_id. A winning tombstone removes
-- the logical event. Return one current event per surviving logical key.
--
-- Optimization: rank only the narrow landing columns needed for ordering,
-- then join wide JSONB payloads after rn=1 when processing large event tables.
-- Do not filter tombstones before ranking: doing so can resurrect an old row.
--
-- WITH ranked AS (
--   SELECT e.*,
--          ROW_NUMBER() OVER (
--            PARTITION BY source_system, source_event_key
--            ORDER BY revision DESC, ingested_at DESC, event_id DESC
--          ) AS rn
--   FROM raw_events e
-- ),
-- canonical AS (
--   SELECT *
--   FROM ranked
--   WHERE rn = 1
--     AND NOT is_tombstone
-- )
-- SELECT event_id, source_system, source_event_key, revision,
--        actor, event_type, outcome, src_ip, event_ts, ingested_at
-- FROM canonical
-- ORDER BY event_ts, event_id;
--
-- Expected checks: auth-003 resolves to event_id 5 (revision 2);
-- heartbeat-old-001 is absent because its winning revision is a tombstone.

-- Q2. Enrich canonical events with the asset owner, environment, and criticality
-- that were effective at event time. Preserve events whose asset history is
-- missing so that downstream quality controls can report them.
--
-- Optimization: LATERAL ... ORDER BY valid_from DESC LIMIT 1 performs a
-- parameterized top-1 lookup. A composite (asset_id, valid_from DESC) index
-- can avoid scanning every historical row for each event.
--
-- WITH ranked AS (
--   SELECT e.*,
--          ROW_NUMBER() OVER (
--            PARTITION BY source_system, source_event_key
--            ORDER BY revision DESC, ingested_at DESC, event_id DESC
--          ) AS rn
--   FROM raw_events e
-- ),
-- canonical AS (
--   SELECT * FROM ranked WHERE rn = 1 AND NOT is_tombstone
-- )
-- SELECT e.event_id, e.actor, e.event_ts, e.asset_id,
--        a.hostname, a.owner_team, a.environment, a.criticality
-- FROM canonical e
-- LEFT JOIN LATERAL (
--   SELECT h.hostname, h.owner_team, h.environment, h.criticality
--   FROM asset_history h
--   WHERE h.asset_id = e.asset_id
--     AND h.valid_from <= e.event_ts
--     AND (h.valid_to > e.event_ts OR h.valid_to IS NULL)
--   ORDER BY h.valid_from DESC
--   LIMIT 1
-- ) a ON TRUE
-- ORDER BY e.event_ts, e.event_id;
--
-- Expected check: asset 103 belongs to DevOps for its 10:00 events and
-- Platform Engineering for the 13:00 event.

-- Q3. Detect authentication bursts: at least five failed authentications from
-- the same actor and source IP in the trailing ten minutes at each event time.
--
-- Optimization: RANGE uses event-time distance, unlike ROWS which counts
-- physical rows. Deduplicate first so replayed deliveries do not inflate
-- velocity. Keep the window input restricted to AUTH failures.
--
-- WITH ranked AS (
--   SELECT e.*,
--          ROW_NUMBER() OVER (
--            PARTITION BY source_system, source_event_key
--            ORDER BY revision DESC, ingested_at DESC, event_id DESC
--          ) AS rn
--   FROM raw_events e
-- ),
-- canonical_failures AS (
--   SELECT *
--   FROM ranked
--   WHERE rn = 1 AND NOT is_tombstone
--     AND event_type = 'AUTH'
--     AND outcome = 'FAIL'
--     AND actor IS NOT NULL
--     AND src_ip IS NOT NULL
-- ),
-- scored AS (
--   SELECT f.*,
--          COUNT(*) OVER (
--            PARTITION BY actor, src_ip
--            ORDER BY event_ts
--            RANGE BETWEEN INTERVAL '10 minutes' PRECEDING AND CURRENT ROW
--          ) AS failures_in_10m
--   FROM canonical_failures f
-- )
-- SELECT actor, src_ip, event_id, event_ts, failures_in_10m
-- FROM scored
-- WHERE failures_in_10m >= 5
-- ORDER BY actor, src_ip, event_ts;
--
-- Expected check: alice from 198.51.100.23 crosses the threshold at 09:08 UTC.
-- Bob has only two failures and should not be returned.

-- Q4. For each actor/IP pair that crosses the Q3 threshold, find the first
-- successful authentication within 15 minutes after the first threshold
-- crossing. Return pairs with and without a subsequent success.
--
-- Optimization: LATERAL with ORDER BY/LIMIT 1 stops at the first qualifying
-- success when an index supports (actor, src_ip, event_ts). Avoid a broad
-- self-join that materializes every possible failure/success pair.
--
-- WITH ranked AS (
--   SELECT e.*,
--          ROW_NUMBER() OVER (
--            PARTITION BY source_system, source_event_key
--            ORDER BY revision DESC, ingested_at DESC, event_id DESC
--          ) AS rn
--   FROM raw_events e
-- ),
-- failures AS (
--   SELECT *
--   FROM ranked
--   WHERE rn = 1 AND NOT is_tombstone
--     AND event_type = 'AUTH' AND outcome = 'FAIL'
--     AND actor IS NOT NULL AND src_ip IS NOT NULL
-- ),
-- scored AS (
--   SELECT f.*,
--          COUNT(*) OVER (
--            PARTITION BY actor, src_ip
--            ORDER BY event_ts
--            RANGE BETWEEN INTERVAL '10 minutes' PRECEDING AND CURRENT ROW
--          ) AS fail_count
--   FROM failures f
-- ),
-- first_crossing AS (
--   SELECT DISTINCT ON (actor, src_ip)
--          actor, src_ip, event_ts AS threshold_ts
--   FROM scored
--   WHERE fail_count >= 5
--   ORDER BY actor, src_ip, event_ts
-- )
-- SELECT f.actor, f.src_ip, f.threshold_ts, s.event_ts AS success_ts,
--        s.event_id AS success_event_id
-- FROM first_crossing f
-- LEFT JOIN LATERAL (
--   SELECT e.event_id, e.event_ts
--   FROM ranked r
--   JOIN raw_events e ON e.event_id = r.event_id
--   WHERE r.rn = 1 AND NOT r.is_tombstone
--     AND r.event_type = 'AUTH' AND r.outcome = 'SUCCESS'
--     AND r.actor = f.actor AND r.src_ip = f.src_ip
--     AND r.event_ts > f.threshold_ts
--     AND r.event_ts <= f.threshold_ts + INTERVAL '15 minutes'
--   ORDER BY r.event_ts, r.event_id
--   LIMIT 1
-- ) s ON TRUE;
--
-- Expected check: alice's burst is followed by a success at 09:10 UTC.

-- Q5. Match canonical events to effective-dated threat-intelligence CIDR
-- indicators. Only match an indicator when event_ts is inside [valid_from,
-- valid_to). Preserve confidence and indicator identity for explainability.
--
-- Optimization: apply the time predicate in the join and keep the event set
-- canonical. For large feeds, pre-filter indicators to the batch time range;
-- network containment and temporal validity are separate dimensions.
--
-- WITH ranked AS (
--   SELECT e.*,
--          ROW_NUMBER() OVER (
--            PARTITION BY source_system, source_event_key
--            ORDER BY revision DESC, ingested_at DESC, event_id DESC
--          ) AS rn
--   FROM raw_events e
-- ),
-- canonical AS (
--   SELECT * FROM ranked WHERE rn = 1 AND NOT is_tombstone
-- )
-- SELECT e.event_id, e.actor, e.src_ip, e.event_ts,
--        i.indicator_id, i.indicator_name, i.indicator_network, i.confidence
-- FROM canonical e
-- JOIN threat_indicators i
--   ON e.src_ip <<= i.indicator_network
--  AND e.event_ts >= i.valid_from
--  AND e.event_ts < i.valid_to
-- ORDER BY e.event_ts, i.indicator_id;
--
-- Expected checks: 203.0.113.66 matches the active range at 10:00 and 10:05;
-- the 10:45 event does not match the expired indicator.

-- Q6. Persist brute-force and threat-intelligence alerts idempotently.
-- Re-running this complete practice batch must not create duplicate alert rows.
-- For this snapshot-style example, conflict handling widens the observed time
-- range and keeps the maximum count/severity; it does not add counts blindly.
--
-- Optimization: aggregate detections to one row per dedupe_key before INSERT.
-- ON CONFLICT uses the unique key as the concurrency-safe idempotency guard.
-- A production incremental pipeline should also persist processed event IDs
-- or source offsets so genuinely new events can be added exactly once.
--
-- WITH ranked AS (
--   SELECT e.*,
--          ROW_NUMBER() OVER (
--            PARTITION BY source_system, source_event_key
--            ORDER BY revision DESC, ingested_at DESC, event_id DESC
--          ) AS rn
--   FROM raw_events e
-- ),
-- canonical AS (
--   SELECT * FROM ranked WHERE rn = 1 AND NOT is_tombstone
-- ),
-- auth_failures AS (
--   SELECT *
--   FROM canonical
--   WHERE event_type = 'AUTH' AND outcome = 'FAIL'
--     AND actor IS NOT NULL AND src_ip IS NOT NULL
-- ),
-- scored AS (
--   SELECT f.*,
--          COUNT(*) OVER (
--            PARTITION BY actor, src_ip
--            ORDER BY event_ts
--            RANGE BETWEEN INTERVAL '10 minutes' PRECEDING AND CURRENT ROW
--          ) AS failures_in_10m
--   FROM auth_failures f
-- ),
-- brute_force AS (
--   SELECT
--     'BRUTE_FORCE|' || actor || '|' || src_ip::text || '|' ||
--       to_char(date_trunc('hour', event_ts), 'YYYYMMDDHH24') AS dedupe_key,
--     'BRUTE_FORCE'::text AS rule_name,
--     actor,
--     src_ip,
--     MIN(asset_id) AS asset_id,
--     MIN(event_ts) AS first_event_ts,
--     MAX(event_ts) AS last_event_ts,
--     MAX(failures_in_10m)::integer AS hit_count,
--     8::smallint AS severity
--   FROM scored
--   WHERE failures_in_10m >= 5
--   GROUP BY actor, src_ip, date_trunc('hour', event_ts)
-- ),
-- ioc_hits AS (
--   SELECT
--     'IOC|' || i.indicator_id::text || '|' || e.source_system || '|' ||
--       e.source_event_key AS dedupe_key,
--     'THREAT_INTEL'::text AS rule_name,
--     e.actor,
--     e.src_ip,
--     e.asset_id,
--     e.event_ts AS first_event_ts,
--     e.event_ts AS last_event_ts,
--     1::integer AS hit_count,
--     CASE WHEN i.confidence >= 90 THEN 9
--          WHEN i.confidence >= 75 THEN 7
--          ELSE 5 END::smallint AS severity
--   FROM canonical e
--   JOIN threat_indicators i
--     ON e.src_ip <<= i.indicator_network
--    AND e.event_ts >= i.valid_from
--    AND e.event_ts < i.valid_to
-- ),
-- candidates AS (
--   SELECT * FROM brute_force
--   UNION ALL
--   SELECT * FROM ioc_hits
-- )
-- INSERT INTO alerts
--   (dedupe_key, rule_name, actor, src_ip, asset_id,
--    first_event_ts, last_event_ts, hit_count, severity)
-- SELECT dedupe_key, rule_name, actor, src_ip, asset_id,
--        first_event_ts, last_event_ts, hit_count, severity
-- FROM candidates
-- ON CONFLICT (dedupe_key) DO UPDATE
-- SET first_event_ts = LEAST(alerts.first_event_ts, EXCLUDED.first_event_ts),
--     last_event_ts  = GREATEST(alerts.last_event_ts, EXCLUDED.last_event_ts),
--     hit_count      = GREATEST(alerts.hit_count, EXCLUDED.hit_count),
--     severity       = GREATEST(alerts.severity, EXCLUDED.severity),
--     updated_at     = GREATEST(alerts.updated_at, EXCLUDED.updated_at)
-- RETURNING alert_id, dedupe_key, rule_name, hit_count, severity;
--
-- Run Q6 before Q7. Execute it twice to confirm alert row counts do not grow
-- on the second run.

-- Q7. Sessionize persisted alerts into incident candidates. Alerts for the
-- same actor and IP belong to one candidate incident when the next alert starts
-- no more than 30 minutes after the previous alert ends.
--
-- Optimization: LAG plus a cumulative SUM labels sessions in one ordered pass.
-- This avoids a recursive self-join for a simple inactivity-gap problem.
--
-- WITH ordered AS (
--   SELECT a.*,
--          LAG(last_event_ts) OVER (
--            PARTITION BY actor, src_ip
--            ORDER BY first_event_ts, alert_id
--          ) AS previous_last_ts
--   FROM alerts a
-- ),
-- boundaries AS (
--   SELECT *,
--          CASE
--            WHEN previous_last_ts IS NULL
--              OR first_event_ts > previous_last_ts + INTERVAL '30 minutes'
--            THEN 1 ELSE 0
--          END AS starts_new_incident
--   FROM ordered
-- ),
-- sessioned AS (
--   SELECT *,
--          SUM(starts_new_incident) OVER (
--            PARTITION BY actor, src_ip
--            ORDER BY first_event_ts, alert_id
--            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
--          ) AS incident_session
--   FROM boundaries
-- )
-- SELECT
--   md5(concat_ws('|', COALESCE(actor, '<unknown>'),
--                 COALESCE(src_ip::text, '<no-ip>'),
--                 MIN(first_event_ts)::text)) AS incident_candidate_key,
--   actor,
--   src_ip,
--   MIN(first_event_ts) AS opened_at,
--   MAX(last_event_ts) AS last_activity_at,
--   COUNT(*) AS alert_count,
--   MAX(severity) AS max_severity
-- FROM sessioned
-- GROUP BY actor, src_ip, incident_session
-- ORDER BY opened_at;
--
-- Note: session keys based on the first event can change if an earlier
-- late-arriving alert is discovered. Production case management should retain
-- a durable incident ID and explicitly merge/re-key sessions when needed.

-- Q8. Measure mean time to acknowledge (MTTA) and resolve (MTTR), and flag
-- severity-specific SLA breaches. SLA targets: Critical 5m, High 15m,
-- Medium 60m, Low 240m. Open cases have no resolution duration yet.
--
-- Optimization: calculate each interval once in a CTE, then reuse it for
-- metrics and breach flags. Keep timestamps as timestamptz until presentation.
--
-- WITH durations AS (
--   SELECT c.*,
--          EXTRACT(EPOCH FROM (acknowledged_at - opened_at)) / 60.0 AS mtta_min,
--          EXTRACT(EPOCH FROM (resolved_at - opened_at)) / 60.0 AS mttr_min,
--          CASE severity
--            WHEN 'CRITICAL' THEN 5
--            WHEN 'HIGH' THEN 15
--            WHEN 'MEDIUM' THEN 60
--            ELSE 240
--          END AS ack_sla_min
--   FROM incident_cases c
-- )
-- SELECT case_id, incident_key, severity, status, owner_team,
--        ROUND(mtta_min::numeric, 2) AS mtta_min,
--        ROUND(mttr_min::numeric, 2) AS mttr_min,
--        CASE
--          WHEN acknowledged_at IS NULL
--            THEN now() > opened_at + ack_sla_min * INTERVAL '1 minute'
--          ELSE mtta_min > ack_sla_min
--        END AS ack_sla_breached
-- FROM durations
-- ORDER BY opened_at;
--
-- Expected checks: INC-2026-001 breaches the 5-minute Critical target;
-- INC-2026-003 breaches the 60-minute Medium target.

-- Q9. Quantify event-time to ingestion-time lag by source and event type.
-- Report volume, P95 lag, maximum lag, and count of events arriving over
-- 30 minutes late. Use canonical rows so replay deliveries are not counted.
--
-- Optimization: aggregate once at the reporting grain. For very large event
-- stores, compute these metrics from bounded ingestion partitions and persist
-- hourly summaries instead of repeatedly scanning all historical telemetry.
--
-- WITH ranked AS (
--   SELECT e.*,
--          ROW_NUMBER() OVER (
--            PARTITION BY source_system, source_event_key
--            ORDER BY revision DESC, ingested_at DESC, event_id DESC
--          ) AS rn
--   FROM raw_events e
-- ),
-- canonical AS (
--   SELECT * FROM ranked WHERE rn = 1 AND NOT is_tombstone
-- ),
-- lagged AS (
--   SELECT source_system, event_type, event_id,
--          EXTRACT(EPOCH FROM (ingested_at - event_ts)) / 60.0 AS lag_minutes
--   FROM canonical
-- )
-- SELECT source_system, event_type,
--        COUNT(*) AS event_count,
--        ROUND(percentile_cont(0.95) WITHIN GROUP (ORDER BY lag_minutes)::numeric, 2)
--          AS p95_lag_minutes,
--        ROUND(MAX(lag_minutes)::numeric, 2) AS max_lag_minutes,
--        COUNT(*) FILTER (WHERE lag_minutes > 30) AS over_30m_late
-- FROM lagged
-- GROUP BY source_system, event_type
-- ORDER BY over_30m_late DESC, p95_lag_minutes DESC;

-- Q10. Produce a unified data-quality exception feed for canonical events:
-- blank actor, missing source field, non-numeric event_version, missing IP
-- on AUTH events, and asset IDs with no effective history at event time.
--
-- Optimization: canonicalize once, then use UNION ALL for independent checks.
-- UNION ALL avoids a global sort/distinct; exception types are intentionally
-- allowed to produce multiple rows for one bad event.
--
-- WITH ranked AS (
--   SELECT e.*,
--          ROW_NUMBER() OVER (
--            PARTITION BY source_system, source_event_key
--            ORDER BY revision DESC, ingested_at DESC, event_id DESC
--          ) AS rn
--   FROM raw_events e
-- ),
-- canonical AS (
--   SELECT * FROM ranked WHERE rn = 1 AND NOT is_tombstone
-- ),
-- exceptions AS (
--   SELECT event_id, 'BLANK_ACTOR'::text AS exception_type,
--          'actor is NULL or whitespace'::text AS detail
--   FROM canonical
--   WHERE NULLIF(BTRIM(actor), '') IS NULL
--
--   UNION ALL
--
--   SELECT event_id, 'MISSING_SOURCE',
--          'payload.source is missing or blank'
--   FROM canonical
--   WHERE NOT (payload ? 'source')
--      OR NULLIF(BTRIM(payload ->> 'source'), '') IS NULL
--
--   UNION ALL
--
--   SELECT event_id, 'INVALID_EVENT_VERSION',
--          'payload.event_version must be a JSON number'
--   FROM canonical
--   WHERE jsonb_typeof(payload -> 'event_version') IS DISTINCT FROM 'number'
--
--   UNION ALL
--
--   SELECT e.event_id, 'AUTH_WITHOUT_SOURCE_IP',
--          'AUTH event has no source IP'
--   FROM canonical e
--   WHERE e.event_type = 'AUTH' AND e.src_ip IS NULL
--
--   UNION ALL
--
--   SELECT e.event_id, 'UNKNOWN_ASSET',
--          'no asset-history row is effective at event time'
--   FROM canonical e
--   WHERE e.asset_id IS NOT NULL
--     AND NOT EXISTS (
--       SELECT 1
--       FROM asset_history h
--       WHERE h.asset_id = e.asset_id
--         AND h.valid_from <= e.event_ts
--         AND (h.valid_to > e.event_ts OR h.valid_to IS NULL)
--     )
-- )
-- SELECT exception_type, event_id, detail
-- FROM exceptions
-- ORDER BY exception_type, event_id;

-- Q11. Find overlapping validity windows for duplicate threat-indicator
-- networks. Overlapping active windows can create duplicate or contradictory
-- matches and should be resolved during feed normalization.
--
-- Optimization: compare each pair once with indicator_id ordering. The
-- half-open tstzrange intersection excludes adjacent windows that merely
-- touch at an endpoint.
--
-- SELECT a.indicator_id AS indicator_a,
--        b.indicator_id AS indicator_b,
--        a.indicator_network,
--        tstzrange(a.valid_from, a.valid_to, '[)')
--          * tstzrange(b.valid_from, b.valid_to, '[)') AS overlap_period
-- FROM threat_indicators a
-- JOIN threat_indicators b
--   ON a.indicator_id < b.indicator_id
--  AND a.indicator_network = b.indicator_network
--  AND tstzrange(a.valid_from, a.valid_to, '[)')
--      && tstzrange(b.valid_from, b.valid_to, '[)')
-- ORDER BY a.indicator_id, b.indicator_id;
--
-- Expected check: indicators 1 and 2 overlap for the same CIDR.

-- ---------------------------------------------------------------------------
-- 4. Performance lab and production notes
-- ---------------------------------------------------------------------------

-- Candidate indexes. Benchmark each against representative data volume;
-- small synthetic tables may correctly use sequential scans.
--
-- CREATE INDEX raw_events_canonical_order_idx
--   ON raw_events
--      (source_system, source_event_key,
--       revision DESC, ingested_at DESC, event_id DESC);
--
-- CREATE INDEX raw_events_auth_velocity_idx
--   ON raw_events (actor, src_ip, event_ts)
--   WHERE event_type = 'AUTH' AND outcome = 'FAIL';
--
-- CREATE INDEX asset_history_asof_idx
--   ON asset_history (asset_id, valid_from DESC)
--   INCLUDE (valid_to, hostname, owner_team, environment, criticality);
--
-- CREATE INDEX raw_events_ingestion_time_idx
--   ON raw_events (ingested_at)
--   INCLUDE (source_system, event_type, event_ts);
--
-- CREATE INDEX raw_events_payload_gin_idx
--   ON raw_events USING GIN (payload jsonb_path_ops);
--
-- CREATE INDEX incident_cases_sla_idx
--   ON incident_cases (severity, opened_at DESC)
--   INCLUDE (acknowledged_at, resolved_at, status, owner_team);
--
-- CREATE INDEX alerts_actor_ip_time_idx
--   ON alerts (actor, src_ip, first_event_ts);
--
-- Suggested experiments:
--   1. Run EXPLAIN (ANALYZE, BUFFERS) for Q1 before and after the canonical
--      ordering index. Inspect sort method, memory, rows removed, and buffers.
--   2. Compare Q2 with and without asset_history_asof_idx at realistic history
--      depth. Check whether the LATERAL lookup becomes an index scan.
--   3. Compare Q3's RANGE frame to a self-join on a large auth-failure stream.
--      Keep the same event-time semantics when comparing result sets.
--   4. Test Q5 with an indicator feed containing many CIDRs and validity rows.
--      If network containment dominates, evaluate a normalized prefix lookup
--      or a supported network operator index for the deployed PostgreSQL build.
--   5. Partition raw_events by ingestion date for retention and bounded scans.
--      Keep event-time and ingestion-time predicates distinct: late arrivals
--      can land in a recent ingestion partition with an old event_ts.
--   6. Do not add every suggested index automatically. Measure write overhead,
--      index size, selectivity, and actual production query plans.
--
-- Production design notes:
--   * Persist source offsets / processed-event IDs for exactly-once effects;
--     a unique alert fingerprint alone does not make an external notification
--     exactly once.
--   * Use event time for detection windows and ingestion time for pipeline
--     freshness, replay boundaries, and retention operations.
--   * Preserve raw evidence and canonicalization lineage for auditability.
--   * Define indicator precedence, confidence policy, and expiry semantics.
--   * Treat alert severity as explainable rule output, not an autonomous
--     conclusion. Keep analyst disposition and false-positive feedback.
--   * Use stable incident IDs in case management; late data may require
--     merging previously separated sessions.
--   * Apply least-privilege access and retention controls to actor/IP data.
--
-- Expected spot checks:
--   * Q1 keeps event_id 5 for auth-003 and removes heartbeat-old-001.
--   * Q3 detects alice's five failures in ten minutes, but not bob's pair.
--   * Q4 finds alice's success at 09:10 UTC.
--   * Q5 excludes the 10:45 event because the indicator expired at 10:30.
--   * Q8 flags the Critical and Medium acknowledgement SLA examples.
--   * Q10 reports the orphan asset and malformed proc-bad-001 payload.
--
-- End of practice.
