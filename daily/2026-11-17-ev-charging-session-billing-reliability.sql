-- ============================================================================
-- Daily SQL Practice: 2026-11-17
-- Topic: EV Charging Network Operations, Session Billing & Roaming Settlement
-- Platform: PostgreSQL 14+
--
-- Run this script in a disposable database. It recreates only ev_practice.
-- All timestamps are UTC. Currency amounts are INR and are stored as NUMERIC.
-- The data deliberately contains replays, a corrected session, a voided
-- session, an orphan meter record, a tariff overlap, and a high-energy session.
-- ============================================================================

DROP SCHEMA IF EXISTS ev_practice CASCADE;
CREATE SCHEMA ev_practice;
SET search_path TO ev_practice, public;

-- 1. Reference and operational tables
CREATE TABLE charging_site (
    site_id          INTEGER PRIMARY KEY,
    site_name        TEXT NOT NULL,
    city             TEXT NOT NULL,
    max_site_kw      NUMERIC(10,2) NOT NULL CHECK (max_site_kw > 0)
);

CREATE TABLE charger (
    charger_id       INTEGER PRIMARY KEY,
    site_id          INTEGER NOT NULL REFERENCES charging_site(site_id),
    connector_type   TEXT NOT NULL,
    max_kw           NUMERIC(10,2) NOT NULL CHECK (max_kw > 0),
    commissioned_on  DATE NOT NULL,
    charger_status   TEXT NOT NULL CHECK (charger_status IN ('ACTIVE','RETIRED'))
);

-- Each row is a complete source snapshot. A higher source_version supersedes
-- a lower version. A latest VOID row must suppress the earlier UPSERT row.
CREATE TABLE session_delivery (
    delivery_id       BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    session_id        TEXT NOT NULL,
    source_version    INTEGER NOT NULL CHECK (source_version > 0),
    action            TEXT NOT NULL CHECK (action IN ('UPSERT','VOID')),
    charger_id        INTEGER REFERENCES charger(charger_id),
    started_at        TIMESTAMPTZ,
    energy_ended_at   TIMESTAMPTZ,
    unplugged_at      TIMESTAMPTZ,
    received_at       TIMESTAMPTZ NOT NULL
);

-- Cumulative meter values are delivered independently of session snapshots.
-- reading_key identifies one logical meter observation across replays/versions.
CREATE TABLE meter_reading_delivery (
    reading_delivery_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    reading_key         TEXT NOT NULL,
    session_id          TEXT NOT NULL,
    reading_at          TIMESTAMPTZ NOT NULL,
    cumulative_kwh      NUMERIC(14,3) NOT NULL,
    source_version      INTEGER NOT NULL CHECK (source_version > 0),
    action              TEXT NOT NULL CHECK (action IN ('UPSERT','VOID')),
    received_at         TIMESTAMPTZ NOT NULL
);

CREATE TABLE tariff_rate (
    rate_id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    site_id           INTEGER NOT NULL REFERENCES charging_site(site_id),
    connector_type    TEXT NOT NULL,
    valid_from        TIMESTAMPTZ NOT NULL,
    valid_to          TIMESTAMPTZ NOT NULL,
    energy_rate       NUMERIC(12,4) NOT NULL CHECK (energy_rate >= 0),
    idle_rate_min     NUMERIC(12,4) NOT NULL CHECK (idle_rate_min >= 0),
    grace_minutes     INTEGER NOT NULL CHECK (grace_minutes >= 0),
    fixed_fee         NUMERIC(12,2) NOT NULL CHECK (fixed_fee >= 0),
    currency          CHAR(3) NOT NULL,
    CHECK (valid_to > valid_from)
);

CREATE TABLE charger_unavailability (
    outage_id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    charger_id        INTEGER NOT NULL REFERENCES charger(charger_id),
    outage_type       TEXT NOT NULL,
    started_at        TIMESTAMPTZ NOT NULL,
    ended_at          TIMESTAMPTZ,
    unavailable_range TSTZRANGE GENERATED ALWAYS AS
        (tstzrange(started_at,
                   COALESCE(ended_at, 'infinity'::timestamptz),
                   '[)')) STORED,
    CHECK (ended_at IS NULL OR ended_at > started_at)
);

CREATE TABLE roaming_cdr_delivery (
    cdr_delivery_id   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    partner_cdr_ref   TEXT NOT NULL,
    session_id        TEXT NOT NULL,
    source_version    INTEGER NOT NULL CHECK (source_version > 0),
    action            TEXT NOT NULL CHECK (action IN ('UPSERT','VOID')),
    partner_kwh       NUMERIC(14,3) NOT NULL,
    partner_amount    NUMERIC(14,2) NOT NULL,
    currency          CHAR(3) NOT NULL,
    received_at       TIMESTAMPTZ NOT NULL
);

CREATE TABLE payment_delivery (
    payment_delivery_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    payment_ref         TEXT NOT NULL,
    session_id          TEXT NOT NULL,
    source_version      INTEGER NOT NULL CHECK (source_version > 0),
    action              TEXT NOT NULL CHECK (action IN ('UPSERT','VOID')),
    payment_status      TEXT NOT NULL CHECK (payment_status IN ('SETTLED','REFUNDED','PENDING')),
    amount              NUMERIC(14,2) NOT NULL,
    currency            CHAR(3) NOT NULL,
    received_at         TIMESTAMPTZ NOT NULL
);

-- 2. Realistic synthetic reference data
INSERT INTO charging_site (site_id, site_name, city, max_site_kw) VALUES
    (1, 'Central Mall Charging Plaza', 'Pune', 250.00),
    (2, 'Airport Fast-Charge Hub', 'Pune', 180.00),
    (3, 'Tech Park AC Charging', 'Pimpri-Chinchwad', 60.00);

INSERT INTO charger
    (charger_id, site_id, connector_type, max_kw, commissioned_on, charger_status)
VALUES
    (101, 1, 'CCS2', 150.00, DATE '2025-04-01', 'ACTIVE'),
    (102, 1, 'CCS2', 150.00, DATE '2025-04-01', 'ACTIVE'),
    (201, 2, 'CCS2',  60.00, DATE '2025-08-15', 'ACTIVE'),
    (301, 3, 'TYPE2', 22.00, DATE '2025-01-10', 'ACTIVE');

INSERT INTO session_delivery
    (session_id, source_version, action, charger_id,
     started_at, energy_ended_at, unplugged_at, received_at)
VALUES
    -- S-1001 original delivery, replay, then a corrected end/unplug time.
    ('S-1001', 1, 'UPSERT', 101,
     '2026-11-17 08:00+00', '2026-11-17 09:00+00', '2026-11-17 09:15+00',
     '2026-11-17 09:01+00'),
    ('S-1001', 1, 'UPSERT', 101,
     '2026-11-17 08:00+00', '2026-11-17 09:00+00', '2026-11-17 09:15+00',
     '2026-11-17 09:03+00'),
    ('S-1001', 2, 'UPSERT', 101,
     '2026-11-17 08:00+00', '2026-11-17 09:02+00', '2026-11-17 09:18+00',
     '2026-11-17 09:06+00'),
    ('S-1002', 1, 'UPSERT', 102,
     '2026-11-17 08:50+00', '2026-11-17 09:30+00', '2026-11-17 09:40+00',
     '2026-11-17 09:41+00'),
    ('S-1003', 1, 'UPSERT', 201,
     '2026-11-17 08:30+00', '2026-11-17 09:30+00', '2026-11-17 09:40+00',
     '2026-11-17 09:42+00'),
    ('S-1004', 1, 'UPSERT', 201,
     '2026-11-17 10:00+00', '2026-11-17 10:45+00', '2026-11-17 10:50+00',
     '2026-11-17 10:51+00'),
    ('S-1005', 1, 'UPSERT', 301,
     '2026-11-17 11:00+00', '2026-11-17 12:00+00', '2026-11-17 12:05+00',
     '2026-11-17 12:06+00'),
    ('S-1006', 1, 'UPSERT', 301,
     '2026-11-17 12:15+00', '2026-11-17 13:00+00', '2026-11-17 13:05+00',
     '2026-11-17 13:06+00'),
    -- A later void must remove this session from the canonical result.
    ('S-1007', 1, 'UPSERT', 101,
     '2026-11-17 14:00+00', '2026-11-17 14:20+00', '2026-11-17 14:25+00',
     '2026-11-17 14:26+00'),
    ('S-1007', 2, 'VOID', 101,
     NULL, NULL, NULL, '2026-11-17 14:40+00');

INSERT INTO meter_reading_delivery
    (reading_key, session_id, reading_at, cumulative_kwh,
     source_version, action, received_at)
VALUES
    ('R-1001-START', 'S-1001', '2026-11-17 08:00+00', 100.000, 1, 'UPSERT', '2026-11-17 08:01+00'),
    ('R-1001-START', 'S-1001', '2026-11-17 08:00+00', 100.000, 1, 'UPSERT', '2026-11-17 08:04+00'),
    ('R-1001-END',   'S-1001', '2026-11-17 09:02+00', 118.600, 1, 'UPSERT', '2026-11-17 09:03+00'),
    ('R-1001-END',   'S-1001', '2026-11-17 09:02+00', 118.800, 2, 'UPSERT', '2026-11-17 09:08+00'),
    ('R-1002-START', 'S-1002', '2026-11-17 08:50+00', 200.000, 1, 'UPSERT', '2026-11-17 08:51+00'),
    ('R-1002-END',   'S-1002', '2026-11-17 09:30+00', 212.500, 1, 'UPSERT', '2026-11-17 09:31+00'),
    ('R-1003-START', 'S-1003', '2026-11-17 08:30+00', 500.000, 1, 'UPSERT', '2026-11-17 08:31+00'),
    ('R-1003-END',   'S-1003', '2026-11-17 09:30+00', 521.000, 1, 'UPSERT', '2026-11-17 09:31+00'),
    ('R-1004-START', 'S-1004', '2026-11-17 10:00+00', 600.000, 1, 'UPSERT', '2026-11-17 10:01+00'),
    ('R-1004-END',   'S-1004', '2026-11-17 10:45+00', 615.200, 1, 'UPSERT', '2026-11-17 10:46+00'),
    ('R-1005-START', 'S-1005', '2026-11-17 11:00+00',  50.000, 1, 'UPSERT', '2026-11-17 11:01+00'),
    ('R-1005-END',   'S-1005', '2026-11-17 12:00+00',  66.000, 1, 'UPSERT', '2026-11-17 12:01+00'),
    ('R-1006-START', 'S-1006', '2026-11-17 12:15+00',  80.000, 1, 'UPSERT', '2026-11-17 12:16+00'),
    ('R-1006-END',   'S-1006', '2026-11-17 13:00+00', 102.000, 1, 'UPSERT', '2026-11-17 13:01+00'),
    -- Deliberate orphan reading for the quality-control exercise.
    ('R-ORPHAN',     'S-9999', '2026-11-17 13:30+00',  12.000, 1, 'UPSERT', '2026-11-17 13:31+00');

INSERT INTO tariff_rate
    (site_id, connector_type, valid_from, valid_to,
     energy_rate, idle_rate_min, grace_minutes, fixed_fee, currency)
VALUES
    (1, 'CCS2', '2026-01-01 00:00+00', '2027-01-01 00:00+00',
     8.5000, 1.2000, 10, 2.00, 'INR'),
    -- Intentional overlap; latest valid_from is used provisionally by Q3/Q4.
    (1, 'CCS2', '2026-11-01 00:00+00', '2026-12-01 00:00+00',
     8.7500, 1.2000, 10, 2.00, 'INR'),
    (2, 'CCS2', '2026-01-01 00:00+00', '2027-01-01 00:00+00',
     9.0000, 1.5000, 5, 3.00, 'INR'),
    (3, 'TYPE2', '2026-01-01 00:00+00', '2027-01-01 00:00+00',
     7.2500, 0.5000, 5, 1.50, 'INR');

INSERT INTO charger_unavailability (charger_id, outage_type, started_at, ended_at) VALUES
    (101, 'PLANNED_MAINTENANCE', '2026-11-17 09:15+00', '2026-11-17 09:45+00'),
    (201, 'POWER_MODULE_FAULT',  '2026-11-17 10:30+00', '2026-11-17 11:15+00'),
    (301, 'CONNECTOR_REPAIR',    '2026-11-17 12:00+00', '2026-11-17 12:30+00');

INSERT INTO roaming_cdr_delivery
    (partner_cdr_ref, session_id, source_version, action,
     partner_kwh, partner_amount, currency, received_at)
VALUES
    ('RC-1001', 'S-1001', 1, 'UPSERT', 18.800, 173.70, 'INR', '2026-11-17 10:00+00'),
    ('RC-1003', 'S-1003', 1, 'UPSERT', 21.000, 192.00, 'INR', '2026-11-17 10:05+00'),
    ('RC-1003', 'S-1003', 1, 'UPSERT', 21.000, 192.00, 'INR', '2026-11-17 10:07+00'),
    ('RC-1004', 'S-1004', 1, 'UPSERT', 15.200, 135.00, 'INR', '2026-11-17 11:00+00'),
    ('RC-ORPHAN', 'S-9999', 1, 'UPSERT', 4.000, 30.00, 'INR', '2026-11-17 14:00+00');

INSERT INTO payment_delivery
    (payment_ref, session_id, source_version, action, payment_status,
     amount, currency, received_at)
VALUES
    ('PAY-1001', 'S-1001', 1, 'UPSERT', 'SETTLED', 173.70, 'INR', '2026-11-17 09:30+00'),
    ('PAY-1001', 'S-1001', 1, 'UPSERT', 'SETTLED', 173.70, 'INR', '2026-11-17 09:32+00'),
    ('PAY-1002', 'S-1002', 1, 'UPSERT', 'SETTLED', 111.38, 'INR', '2026-11-17 09:50+00'),
    ('PAY-1003', 'S-1003', 1, 'UPSERT', 'SETTLED', 192.00, 'INR', '2026-11-17 09:55+00'),
    ('PAY-1004', 'S-1004', 1, 'UPSERT', 'SETTLED', 135.00, 'INR', '2026-11-17 11:10+00'),
    -- S-1005 deliberately has no payment; S-1006 is underpaid.
    ('PAY-1006', 'S-1006', 1, 'UPSERT', 'SETTLED', 160.00, 'INR', '2026-11-17 13:20+00');

-- 3. Candidate indexes. The delivery indexes retain VOID rows so a latest VOID
--    can suppress an earlier UPSERT during canonicalization.
CREATE INDEX ix_session_delivery_canonical
    ON session_delivery (session_id, source_version DESC, received_at DESC, delivery_id DESC);

CREATE INDEX ix_meter_delivery_canonical
    ON meter_reading_delivery (reading_key, source_version DESC,
                               received_at DESC, reading_delivery_id DESC);
CREATE INDEX ix_meter_delivery_session_time
    ON meter_reading_delivery (session_id, reading_at);

CREATE INDEX ix_tariff_asof
    ON tariff_rate (site_id, connector_type, valid_from DESC)
    INCLUDE (valid_to, energy_rate, idle_rate_min, grace_minutes, fixed_fee, currency);

CREATE INDEX ix_unavailability_range
    ON charger_unavailability USING GIST (unavailable_range);

CREATE INDEX ix_roaming_cdr_canonical
    ON roaming_cdr_delivery (partner_cdr_ref, source_version DESC,
                             received_at DESC, cdr_delivery_id DESC);
CREATE INDEX ix_payment_canonical
    ON payment_delivery (payment_ref, source_version DESC,
                         received_at DESC, payment_delivery_id DESC);

ANALYZE;

-- ============================================================================
-- PROBLEM 1 — Canonicalize replayed and corrected charging sessions
-- ============================================================================
-- Requirement:
-- Return one current row per session. A later source_version wins; for an
-- identical version, the latest received delivery wins. A winning VOID must
-- remove the session rather than allowing an older UPSERT to reappear.

-- Optimized solution:
WITH ranked AS (
    SELECT d.*,
           ROW_NUMBER() OVER (
               PARTITION BY session_id
               ORDER BY source_version DESC, received_at DESC, delivery_id DESC
           ) AS rn
    FROM session_delivery AS d
)
SELECT session_id, charger_id, started_at, energy_ended_at, unplugged_at
FROM ranked
WHERE rn = 1
  AND action = 'UPSERT'
ORDER BY session_id;

-- Why this is optimized:
-- Rank once at the business key and use a deterministic tie-breaker. Apply the
-- action filter only after ranking; filtering VOID rows earlier would resurrect
-- stale sessions. The composite index supports the partition/order pattern.

-- ============================================================================
-- PROBLEM 2 — Reconstruct delivered energy from corrected meter readings
-- ============================================================================
-- Requirement:
-- Deduplicate meter observations by reading_key, then calculate session kWh
-- from the earliest and latest valid cumulative meter readings.

-- Optimized solution:
WITH ranked AS (
    SELECT m.*,
           ROW_NUMBER() OVER (
               PARTITION BY reading_key
               ORDER BY source_version DESC, received_at DESC,
                        reading_delivery_id DESC
           ) AS rn
    FROM meter_reading_delivery AS m
),
canonical AS (
    SELECT *
    FROM ranked
    WHERE rn = 1
      AND action = 'UPSERT'
),
first_read AS (
    SELECT DISTINCT ON (session_id)
           session_id, reading_at, cumulative_kwh
    FROM canonical
    ORDER BY session_id, reading_at, reading_key
),
last_read AS (
    SELECT DISTINCT ON (session_id)
           session_id, reading_at, cumulative_kwh
    FROM canonical
    ORDER BY session_id, reading_at DESC, reading_key DESC
),
session_ranked AS (
    SELECT s.*,
           ROW_NUMBER() OVER (
               PARTITION BY session_id
               ORDER BY source_version DESC, received_at DESC, delivery_id DESC
           ) AS rn
    FROM session_delivery AS s
),
sessions AS (
    SELECT session_id
    FROM session_ranked
    WHERE rn = 1 AND action = 'UPSERT'
)
SELECT s.session_id,
       f.reading_at AS first_meter_at,
       l.reading_at AS last_meter_at,
       l.cumulative_kwh - f.cumulative_kwh AS energy_kwh
FROM sessions AS s
LEFT JOIN first_read AS f USING (session_id)
LEFT JOIN last_read  AS l USING (session_id)
ORDER BY s.session_id;

-- Why this is optimized:
-- DISTINCT ON is concise for first/last row retrieval when supported by an
-- appropriate ordering index. Canonicalize each reading key before selecting
-- endpoints; otherwise a replay or correction can inflate or distort kWh.

-- ============================================================================
-- PROBLEM 3 — Resolve the tariff effective at session start
-- ============================================================================
-- Requirement:
-- Select exactly one tariff for each canonical session using half-open
-- validity [valid_from, valid_to). The latest valid_from is the temporary
-- precedence rule while tariff overlaps are investigated separately in Q9.

-- Optimized solution:
WITH ranked AS (
    SELECT s.*,
           ROW_NUMBER() OVER (
               PARTITION BY session_id
               ORDER BY source_version DESC, received_at DESC, delivery_id DESC
           ) AS rn
    FROM session_delivery AS s
),
sessions AS (
    SELECT s.session_id, s.charger_id, s.started_at, c.site_id, c.connector_type
    FROM ranked AS s
    JOIN charger AS c ON c.charger_id = s.charger_id
    WHERE s.rn = 1 AND s.action = 'UPSERT'
)
SELECT s.session_id, t.rate_id, t.energy_rate, t.idle_rate_min,
       t.grace_minutes, t.fixed_fee, t.currency
FROM sessions AS s
LEFT JOIN LATERAL (
    SELECT r.*
    FROM tariff_rate AS r
    WHERE r.site_id = s.site_id
      AND r.connector_type = s.connector_type
      AND s.started_at >= r.valid_from
      AND s.started_at <  r.valid_to
    ORDER BY r.valid_from DESC, r.rate_id DESC
    LIMIT 1
) AS t ON TRUE
ORDER BY s.session_id;

-- Why this is optimized:
-- The LATERAL lookup performs a bounded effective-date search per session.
-- The index begins with equality keys and then valid_from DESC. Keep the
-- timestamp predicate half-open and avoid casting started_at to DATE.

-- ============================================================================
-- PROBLEM 4 — Rate a session with energy, idle and fixed fees
-- ============================================================================
-- Requirement:
-- Calculate energy from canonical meter endpoints, add idle fees only after
-- the tariff grace period, and round the final INR amount to two decimals.

-- Optimized solution:
WITH meter_ranked AS (
    SELECT m.*,
           ROW_NUMBER() OVER (
               PARTITION BY reading_key
               ORDER BY source_version DESC, received_at DESC,
                        reading_delivery_id DESC
           ) AS rn
    FROM meter_reading_delivery AS m
),
meter_canonical AS (
    SELECT *
    FROM meter_ranked
    WHERE rn = 1 AND action = 'UPSERT'
),
meter_first AS (
    SELECT DISTINCT ON (session_id)
           session_id, cumulative_kwh
    FROM meter_canonical
    ORDER BY session_id, reading_at, reading_key
),
meter_last AS (
    SELECT DISTINCT ON (session_id)
           session_id, cumulative_kwh
    FROM meter_canonical
    ORDER BY session_id, reading_at DESC, reading_key DESC
),
session_ranked AS (
    SELECT s.*,
           ROW_NUMBER() OVER (
               PARTITION BY session_id
               ORDER BY source_version DESC, received_at DESC, delivery_id DESC
           ) AS rn
    FROM session_delivery AS s
),
sessions AS (
    SELECT s.session_id, s.charger_id, s.started_at,
           s.energy_ended_at, s.unplugged_at,
           c.site_id, c.connector_type
    FROM session_ranked AS s
    JOIN charger AS c ON c.charger_id = s.charger_id
    WHERE s.rn = 1 AND s.action = 'UPSERT'
),
energy AS (
    SELECT s.*,
           CASE WHEN ml.cumulative_kwh >= mf.cumulative_kwh
                THEN ml.cumulative_kwh - mf.cumulative_kwh
           END AS energy_kwh
    FROM sessions AS s
    LEFT JOIN meter_first AS mf USING (session_id)
    LEFT JOIN meter_last  AS ml USING (session_id)
)
SELECT e.session_id,
       e.energy_kwh,
       t.currency,
       ROUND((
           e.energy_kwh * t.energy_rate
           + GREATEST(
                 0::NUMERIC,
                 EXTRACT(EPOCH FROM (e.unplugged_at - e.energy_ended_at))::NUMERIC
                     / 60 - t.grace_minutes
             ) * t.idle_rate_min
           + t.fixed_fee
       ), 2) AS billed_amount
FROM energy AS e
LEFT JOIN LATERAL (
    SELECT r.*
    FROM tariff_rate AS r
    WHERE r.site_id = e.site_id
      AND r.connector_type = e.connector_type
      AND e.started_at >= r.valid_from
      AND e.started_at <  r.valid_to
    ORDER BY r.valid_from DESC, r.rate_id DESC
    LIMIT 1
) AS t ON TRUE
ORDER BY e.session_id;

-- Why this is optimized:
-- Canonicalize and reduce meter readings to two endpoints before joining to
-- tariff data. NUMERIC avoids binary floating-point currency drift. Invalid or
-- missing meter endpoints remain NULL instead of being silently billed as 0.

-- ============================================================================
-- PROBLEM 5 — Charger availability after overlapping outage intervals
-- ============================================================================
-- Requirement:
-- For 17-Nov-2026 UTC, calculate downtime and availability per charger.
-- Merge overlapping outage/maintenance intervals before summing durations so
-- the same unavailable minute is never counted twice.

-- Optimized solution:
WITH params AS (
    SELECT TIMESTAMPTZ '2026-11-17 00:00+00' AS from_ts,
           TIMESTAMPTZ '2026-11-18 00:00+00' AS to_ts
),
clipped AS (
    SELECT u.charger_id,
           tstzrange(
               GREATEST(u.started_at, p.from_ts),
               LEAST(COALESCE(u.ended_at, p.to_ts), p.to_ts),
               '[)'
           ) AS outage_range
    FROM charger_unavailability AS u
    CROSS JOIN params AS p
    WHERE u.unavailable_range && tstzrange(p.from_ts, p.to_ts, '[)')
),
merged AS (
    SELECT charger_id, range_agg(outage_range) AS outage_ranges
    FROM clipped
    GROUP BY charger_id
),
downtime AS (
    SELECT m.charger_id,
           SUM(EXTRACT(EPOCH FROM (UPPER(x.r) - LOWER(x.r)))) AS downtime_seconds
    FROM merged AS m
    CROSS JOIN LATERAL unnest(m.outage_ranges) AS x(r)
    GROUP BY m.charger_id
)
SELECT c.charger_id,
       COALESCE(d.downtime_seconds, 0) / 3600.0 AS downtime_hours,
       ROUND(
           100.0 * (86400 - COALESCE(d.downtime_seconds, 0)) / 86400,
           2
       ) AS availability_pct
FROM charger AS c
LEFT JOIN downtime AS d USING (charger_id)
ORDER BY c.charger_id;

-- Why this is optimized:
-- The GiST index supports range-overlap filtering. range_agg merges intersecting
-- ranges (PostgreSQL 14 multiranges), preventing double-counting. Clip open or
-- long-running outages to the reporting window before aggregation.

-- ============================================================================
-- PROBLEM 6 — Hourly connector occupancy and utilization
-- ============================================================================
-- Requirement:
-- Calculate hourly plug-occupancy utilization for each charger between 08:00
-- and 14:00 UTC. Count from plug-in through unplug, not only energy transfer.
-- Union overlapping session ranges before calculating utilization.

-- Optimized solution:
WITH session_ranked AS (
    SELECT s.*,
           ROW_NUMBER() OVER (
               PARTITION BY session_id
               ORDER BY source_version DESC, received_at DESC, delivery_id DESC
           ) AS rn
    FROM session_delivery AS s
),
sessions AS (
    SELECT charger_id, started_at, unplugged_at
    FROM session_ranked
    WHERE rn = 1 AND action = 'UPSERT'
      AND started_at IS NOT NULL AND unplugged_at > started_at
),
occupied AS (
    SELECT charger_id,
           range_agg(tstzrange(started_at, unplugged_at, '[)')) AS occupied_ranges
    FROM sessions
    GROUP BY charger_id
),
slots AS (
    SELECT slot_start,
           tstzrange(gs, gs + INTERVAL '1 hour', '[)') AS slot_range
    FROM generate_series(
        TIMESTAMPTZ '2026-11-17 08:00+00',
        TIMESTAMPTZ '2026-11-17 13:00+00',
        INTERVAL '1 hour'
    ) AS series(slot_start)
)
SELECT c.charger_id,
       s.slot_start,
       ROUND(
           100.0 * COALESCE(
               SUM(EXTRACT(EPOCH FROM (
                   UPPER(o.r * s.slot_range) - LOWER(o.r * s.slot_range)
               ))),
               0
           ) / 3600,
           2
       ) AS plug_utilization_pct
FROM charger AS c
CROSS JOIN slots AS s
LEFT JOIN occupied AS a ON a.charger_id = c.charger_id
LEFT JOIN LATERAL unnest(a.occupied_ranges) AS o(r)
       ON o.r && s.slot_range
GROUP BY c.charger_id, s.slot_start
ORDER BY c.charger_id, s.slot_start;

-- Why this is optimized:
-- Generate only the six reporting buckets, not every minute. Range union
-- prevents utilization exceeding 100% when bad source data overlaps sessions.
-- For large reporting windows, persist hourly aggregates rather than expanding
-- every raw session on every dashboard refresh.

-- ============================================================================
-- PROBLEM 7 — Reconcile roaming partner CDRs to operator sessions and charges
-- ============================================================================
-- Requirement:
-- Deduplicate partner CDRs, then compare partner kWh and amount with the
-- operator's canonical meter-derived energy and tariff-rated charge.

-- Optimized solution:
WITH cdr_ranked AS (
    SELECT r.*,
           ROW_NUMBER() OVER (
               PARTITION BY partner_cdr_ref
               ORDER BY source_version DESC, received_at DESC, cdr_delivery_id DESC
           ) AS rn
    FROM roaming_cdr_delivery AS r
),
cdr AS (
    SELECT *
    FROM cdr_ranked
    WHERE rn = 1 AND action = 'UPSERT'
),
session_ranked AS (
    SELECT s.*,
           ROW_NUMBER() OVER (
               PARTITION BY session_id
               ORDER BY source_version DESC, received_at DESC, delivery_id DESC
           ) AS rn
    FROM session_delivery AS s
),
sessions AS (
    SELECT s.session_id, s.charger_id, s.started_at, s.energy_ended_at,
           s.unplugged_at, ch.site_id, ch.connector_type
    FROM session_ranked AS s
    JOIN charger AS ch USING (charger_id)
    WHERE s.rn = 1 AND s.action = 'UPSERT'
),
meter_ranked AS (
    SELECT m.*,
           ROW_NUMBER() OVER (
               PARTITION BY reading_key
               ORDER BY source_version DESC, received_at DESC,
                        reading_delivery_id DESC
           ) AS rn
    FROM meter_reading_delivery AS m
),
meter_canonical AS (
    SELECT *
    FROM meter_ranked
    WHERE rn = 1 AND action = 'UPSERT'
),
meter_first AS (
    SELECT DISTINCT ON (session_id) session_id, cumulative_kwh
    FROM meter_canonical
    ORDER BY session_id, reading_at, reading_key
),
meter_last AS (
    SELECT DISTINCT ON (session_id) session_id, cumulative_kwh
    FROM meter_canonical
    ORDER BY session_id, reading_at DESC, reading_key DESC
),
rated AS (
    SELECT s.session_id,
           ml.cumulative_kwh - mf.cumulative_kwh AS operator_kwh,
           ROUND((
               (ml.cumulative_kwh - mf.cumulative_kwh) * t.energy_rate
               + GREATEST(
                     0::NUMERIC,
                     EXTRACT(EPOCH FROM (s.unplugged_at - s.energy_ended_at))::NUMERIC
                         / 60 - t.grace_minutes
                 ) * t.idle_rate_min
               + t.fixed_fee
           ), 2) AS operator_amount,
           t.currency
    FROM sessions AS s
    JOIN meter_first AS mf USING (session_id)
    JOIN meter_last  AS ml USING (session_id)
    LEFT JOIN LATERAL (
        SELECT r.*
        FROM tariff_rate AS r
        WHERE r.site_id = s.site_id
          AND r.connector_type = s.connector_type
          AND s.started_at >= r.valid_from
          AND s.started_at <  r.valid_to
        ORDER BY r.valid_from DESC, r.rate_id DESC
        LIMIT 1
    ) AS t ON TRUE
)
SELECT COALESCE(c.session_id, r.session_id) AS session_id,
       c.partner_kwh,
       r.operator_kwh,
       c.partner_amount,
       r.operator_amount,
       COALESCE(c.currency, r.currency) AS currency,
       CASE
           WHEN r.session_id IS NULL THEN 'ORPHAN_PARTNER_CDR'
           WHEN c.session_id IS NULL THEN 'MISSING_PARTNER_CDR'
           WHEN ABS(c.partner_kwh - r.operator_kwh) > 0.100 THEN 'ENERGY_MISMATCH'
           WHEN c.partner_amount <> r.operator_amount THEN 'AMOUNT_MISMATCH'
           ELSE 'MATCHED'
       END AS reconciliation_status
FROM cdr AS c
FULL OUTER JOIN rated AS r
  ON r.session_id = c.session_id
 AND r.currency = c.currency
ORDER BY session_id;

-- Why this is optimized:
-- Deduplicate each source at its own natural key before the FULL OUTER JOIN.
-- This prevents replay fanout and preserves missing rows on either side.
-- Compare at session + currency grain; never aggregate unlike currencies.

-- ============================================================================
-- PROBLEM 8 — Estimate concurrent connected load and site-limit breaches
-- ============================================================================
-- Requirement:
-- Use session start/end events to calculate connected charger nameplate load
-- over time. At equal timestamps, process end events before start events.

-- Optimized solution:
WITH session_ranked AS (
    SELECT s.*,
           ROW_NUMBER() OVER (
               PARTITION BY session_id
               ORDER BY source_version DESC, received_at DESC, delivery_id DESC
           ) AS rn
    FROM session_delivery AS s
),
sessions AS (
    SELECT s.session_id, s.started_at, s.unplugged_at,
           c.site_id, c.max_kw
    FROM session_ranked AS s
    JOIN charger AS c USING (charger_id)
    WHERE s.rn = 1 AND s.action = 'UPSERT'
      AND s.started_at IS NOT NULL AND s.unplugged_at > s.started_at
),
events AS (
    SELECT site_id, started_at AS event_at, max_kw AS delta_kw,
           1 AS event_order, session_id
    FROM sessions
    UNION ALL
    SELECT site_id, unplugged_at AS event_at, -max_kw AS delta_kw,
           0 AS event_order, session_id
    FROM sessions
),
timeline AS (
    SELECT e.*,
           SUM(delta_kw) OVER (
               PARTITION BY site_id
               ORDER BY event_at, event_order, session_id
               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
           ) AS connected_kw
    FROM events AS e
)
SELECT s.site_id, s.site_name, s.max_site_kw,
       MAX(t.connected_kw) AS peak_connected_kw,
       MAX(t.connected_kw) > s.max_site_kw AS exceeds_site_limit
FROM timeline AS t
JOIN charging_site AS s USING (site_id)
GROUP BY s.site_id, s.site_name, s.max_site_kw
ORDER BY s.site_id;

-- Why this is optimized:
-- Convert intervals into two events and use one ordered running sum instead of
-- comparing every session pair. End-before-start ordering avoids a false peak
-- when one session ends exactly as another begins. Nameplate load is a
-- conservative planning proxy, not a measured real-time power reading.

-- ============================================================================
-- PROBLEM 9 — Build an operational and tariff data-quality exception feed
-- ============================================================================
-- Requirement:
-- Flag sessions whose meter-derived energy exceeds charger capability, orphan
-- meter readings, and overlapping effective-dated tariffs.

-- Optimized solution:
WITH session_ranked AS (
    SELECT s.*,
           ROW_NUMBER() OVER (
               PARTITION BY session_id
               ORDER BY source_version DESC, received_at DESC, delivery_id DESC
           ) AS rn
    FROM session_delivery AS s
),
sessions AS (
    SELECT s.session_id, s.charger_id, s.started_at, s.energy_ended_at,
           s.unplugged_at, c.max_kw
    FROM session_ranked AS s
    JOIN charger AS c USING (charger_id)
    WHERE s.rn = 1 AND s.action = 'UPSERT'
),
meter_ranked AS (
    SELECT m.*,
           ROW_NUMBER() OVER (
               PARTITION BY reading_key
               ORDER BY source_version DESC, received_at DESC,
                        reading_delivery_id DESC
           ) AS rn
    FROM meter_reading_delivery AS m
),
meter_canonical AS (
    SELECT *
    FROM meter_ranked
    WHERE rn = 1 AND action = 'UPSERT'
),
meter_first AS (
    SELECT DISTINCT ON (session_id) session_id, cumulative_kwh
    FROM meter_canonical
    ORDER BY session_id, reading_at, reading_key
),
meter_last AS (
    SELECT DISTINCT ON (session_id) session_id, cumulative_kwh
    FROM meter_canonical
    ORDER BY session_id, reading_at DESC, reading_key DESC
),
energy AS (
    SELECT s.*,
           ml.cumulative_kwh - mf.cumulative_kwh AS energy_kwh
    FROM sessions AS s
    LEFT JOIN meter_first AS mf USING (session_id)
    LEFT JOIN meter_last  AS ml USING (session_id)
),
exceptions AS (
    SELECT e.session_id AS object_key,
           'ENERGY_EXCEEDS_CHARGER_CAPABILITY' AS issue_type,
           FORMAT('meter_kwh=%s, allowed_kwh=%s',
                  e.energy_kwh,
                  ROUND(e.max_kw * EXTRACT(EPOCH FROM
                      (e.energy_ended_at - e.started_at)) / 3600 * 1.10, 3)
           ) AS issue_detail
    FROM energy AS e
    WHERE e.energy_kwh IS NOT NULL
      AND e.energy_kwh >
          e.max_kw * EXTRACT(EPOCH FROM
              (e.energy_ended_at - e.started_at)) / 3600 * 1.10

    UNION ALL

    SELECT m.session_id, 'ORPHAN_METER_SESSION',
           'Meter observation has no canonical charging session'
    FROM meter_canonical AS m
    WHERE NOT EXISTS (
        SELECT 1 FROM sessions AS s WHERE s.session_id = m.session_id
    )

    UNION ALL

    SELECT a.site_id::TEXT || ':' || a.rate_id || '/' || b.rate_id,
           'OVERLAPPING_TARIFF_WINDOWS',
           FORMAT('site=%s connector=%s', a.site_id, a.connector_type)
    FROM tariff_rate AS a
    JOIN tariff_rate AS b
      ON b.site_id = a.site_id
     AND b.connector_type = a.connector_type
     AND b.rate_id > a.rate_id
     AND tstzrange(a.valid_from, a.valid_to, '[)')
         && tstzrange(b.valid_from, b.valid_to, '[)')
)
SELECT object_key, issue_type, issue_detail
FROM exceptions
ORDER BY issue_type, object_key;

-- Why this is optimized:
-- Use NOT EXISTS for orphan detection and a range-overlap predicate for
-- effective-dated conflicts. Keep each exception at a stable business key so
-- it can be written idempotently to a quarantine or observability table.

-- ============================================================================
-- PROBLEM 10 — Reconcile billed sessions to settled payments
-- ============================================================================
-- Requirement:
-- Compare the operator's expected amount with settled payment totals. Preserve
-- unpaid sessions and payments that cannot be matched to a billable session.

-- Optimized solution:
WITH session_ranked AS (
    SELECT s.*,
           ROW_NUMBER() OVER (
               PARTITION BY session_id
               ORDER BY source_version DESC, received_at DESC, delivery_id DESC
           ) AS rn
    FROM session_delivery AS s
),
sessions AS (
    SELECT s.session_id, s.charger_id, s.started_at,
           s.energy_ended_at, s.unplugged_at,
           c.site_id, c.connector_type
    FROM session_ranked AS s
    JOIN charger AS c USING (charger_id)
    WHERE s.rn = 1 AND s.action = 'UPSERT'
),
meter_ranked AS (
    SELECT m.*,
           ROW_NUMBER() OVER (
               PARTITION BY reading_key
               ORDER BY source_version DESC, received_at DESC,
                        reading_delivery_id DESC
           ) AS rn
    FROM meter_reading_delivery AS m
),
meter_canonical AS (
    SELECT *
    FROM meter_ranked
    WHERE rn = 1 AND action = 'UPSERT'
),
meter_first AS (
    SELECT DISTINCT ON (session_id) session_id, cumulative_kwh
    FROM meter_canonical
    ORDER BY session_id, reading_at, reading_key
),
meter_last AS (
    SELECT DISTINCT ON (session_id) session_id, cumulative_kwh
    FROM meter_canonical
    ORDER BY session_id, reading_at DESC, reading_key DESC
),
billed AS (
    SELECT s.session_id, t.currency,
           ROUND((
               (ml.cumulative_kwh - mf.cumulative_kwh) * t.energy_rate
               + GREATEST(
                     0::NUMERIC,
                     EXTRACT(EPOCH FROM (s.unplugged_at - s.energy_ended_at))::NUMERIC
                         / 60 - t.grace_minutes
                 ) * t.idle_rate_min
               + t.fixed_fee
           ), 2) AS expected_amount
    FROM sessions AS s
    JOIN meter_first AS mf USING (session_id)
    JOIN meter_last  AS ml USING (session_id)
    LEFT JOIN LATERAL (
        SELECT r.*
        FROM tariff_rate AS r
        WHERE r.site_id = s.site_id
          AND r.connector_type = s.connector_type
          AND s.started_at >= r.valid_from
          AND s.started_at <  r.valid_to
        ORDER BY r.valid_from DESC, r.rate_id DESC
        LIMIT 1
    ) AS t ON TRUE
),
payment_ranked AS (
    SELECT p.*,
           ROW_NUMBER() OVER (
               PARTITION BY payment_ref
               ORDER BY source_version DESC, received_at DESC,
                        payment_delivery_id DESC
           ) AS rn
    FROM payment_delivery AS p
),
payments AS (
    SELECT *
    FROM payment_ranked
    WHERE rn = 1 AND action = 'UPSERT'
),
payment_totals AS (
    SELECT session_id, currency,
           SUM(amount) FILTER (WHERE payment_status = 'SETTLED') AS settled_amount
    FROM payments
    GROUP BY session_id, currency
)
SELECT COALESCE(b.session_id, p.session_id) AS session_id,
       COALESCE(b.currency, p.currency) AS currency,
       b.expected_amount,
       p.settled_amount,
       CASE
           WHEN b.session_id IS NULL THEN 'PAYMENT_WITHOUT_BILL'
           WHEN p.session_id IS NULL THEN 'PAYMENT_MISSING'
           WHEN b.expected_amount <> p.settled_amount THEN 'AMOUNT_MISMATCH'
           ELSE 'RECONCILED'
       END AS reconciliation_status
FROM billed AS b
FULL OUTER JOIN payment_totals AS p
  ON p.session_id = b.session_id
 AND p.currency = b.currency
ORDER BY session_id;

-- Why this is optimized:
-- Canonicalize payment references before aggregation, then reconcile at
-- session + currency grain. FULL OUTER JOIN exposes both missing payments and
-- unmatched payments. In production, use a small tolerance only if the
-- settlement contract explicitly permits rounding differences.

-- ============================================================================
-- PERFORMANCE LAB
-- ============================================================================
-- 1. Run EXPLAIN (ANALYZE, BUFFERS) for Q1, Q3, Q5, Q7 and Q10.
-- 2. Compare the session canonicalization plan before/after the composite index.
-- 3. Check whether Q5 uses ix_unavailability_range for the range-overlap filter.
-- 4. On large history tables, partition deliveries by received_at month and
--    keep reporting predicates directly on the partition key.
-- 5. Do not create a partial index restricted to action='UPSERT' for the
--    canonicalization query: the latest VOID row must remain visible.
-- 6. For high-volume meter data, consider a BRIN index on reading_at only when
--    physical row order correlates with event time; retain the B-tree business
--    key index for deterministic replay resolution.
-- 7. Pre-aggregate to session grain before joining roaming, payment, or tariff
--    sources. Joining raw deliveries first can multiply amounts and kWh.
-- 8. Keep money in NUMERIC and retain currency in every aggregation key.
-- 9. Persist hourly utilization and site-load summaries for dashboards; avoid
--    repeatedly expanding years of raw sessions with generate_series.
-- 10. Refresh statistics after bulk loads and validate plans against realistic
--     row counts; a sequential scan can be optimal for small partitions.

-- Expected spot checks:
-- * Q1 returns S-1001 through S-1006; S-1007 is absent because its latest row is VOID.
-- * Q2 returns 18.800 kWh for S-1001 after the corrected meter endpoint.
-- * Q5 reports 0.50 downtime hours for charger 101, 0.75 for 201, and 0.50 for 301.
-- * Q8 flags Central Mall because two 150 kW sessions overlap against a 250 kW limit.
-- * Q9 flags S-1006 energy capability, the orphan S-9999 meter row, and the site-1 tariff overlap.
-- * Q7/Q10 expose the deliberately inconsistent roaming/payment records.

-- Production discussion:
-- * Define whether the billable interval ends at energy_ended_at or unplugged_at.
--   This script bills energy to energy_ended_at and idle time after it.
-- * Confirm whether tariff changes apply at session start or are prorated across
--   a session that crosses an effective-date boundary.
-- * Treat estimated nameplate load separately from measured demand-response data.
-- * Persist source lineage and canonicalization decisions for every settlement.
