-- Daily SQL Practice — 2026-11-11
-- Topic: Industrial machine telemetry, calibration, monitoring and anomaly detection
-- PostgreSQL 14+
--
-- Run in a disposable database. The script creates an isolated sample schema.
-- All timestamps are explicit instants with an Asia/Kolkata offset.
-- Solutions are executable; try each problem before running its solution.

DROP VIEW IF EXISTS canonical_telemetry_readings;
DROP TABLE IF EXISTS maintenance_windows;
DROP TABLE IF EXISTS telemetry_readings;
DROP TABLE IF EXISTS sensor_calibrations;
DROP TABLE IF EXISTS telemetry_assets;

CREATE TABLE telemetry_assets (
    asset_id       text PRIMARY KEY,
    plant_code     text NOT NULL,
    asset_type     text NOT NULL,
    criticality    text NOT NULL CHECK (criticality IN ('low','medium','high','critical'))
);

CREATE TABLE sensor_calibrations (
    calibration_id bigint PRIMARY KEY,
    asset_id       text NOT NULL REFERENCES telemetry_assets(asset_id),
    sensor_code    text NOT NULL,
    valid_from     timestamptz NOT NULL,
    valid_to       timestamptz NOT NULL,
    multiplier     numeric(12,6) NOT NULL,
    offset_value   numeric(12,6) NOT NULL,
    CHECK (valid_to > valid_from)
);

CREATE TABLE telemetry_readings (
    reading_id      bigint PRIMARY KEY,
    source_event_id text NOT NULL,
    asset_id        text NOT NULL REFERENCES telemetry_assets(asset_id),
    sensor_code     text NOT NULL,
    observed_at     timestamptz NOT NULL,
    ingested_at     timestamptz NOT NULL,
    raw_value       numeric(14,4) NOT NULL,
    quality_status  text NOT NULL CHECK (quality_status IN ('good','suspect','invalid'))
);

CREATE TABLE maintenance_windows (
    window_id   bigint PRIMARY KEY,
    asset_id    text NOT NULL REFERENCES telemetry_assets(asset_id),
    starts_at   timestamptz NOT NULL,
    ends_at     timestamptz NOT NULL,
    reason      text NOT NULL,
    CHECK (ends_at > starts_at)
);

INSERT INTO telemetry_assets VALUES
('P-01','PLANT-A','centrifugal_pump','critical'),
('C-02','PLANT-A','air_compressor','high');

INSERT INTO sensor_calibrations VALUES
(101,'P-01','vibration_mm_s',
 TIMESTAMPTZ '2026-11-01 00:00:00+05:30',
 TIMESTAMPTZ '2026-11-11 09:00:00+05:30',1.000000,0.000000),
(102,'P-01','vibration_mm_s',
 TIMESTAMPTZ '2026-11-11 09:00:00+05:30',
 TIMESTAMPTZ 'infinity',1.050000,0.200000),
(103,'P-01','temperature_c',
 TIMESTAMPTZ '2026-11-01 00:00:00+05:30',
 TIMESTAMPTZ '2026-11-11 09:00:00+05:30',1.000000,0.000000),
(104,'P-01','temperature_c',
 TIMESTAMPTZ '2026-11-11 09:00:00+05:30',
 TIMESTAMPTZ 'infinity',1.000000,-1.000000),
(105,'C-02','vibration_mm_s',
 TIMESTAMPTZ '2026-11-01 00:00:00+05:30',
 TIMESTAMPTZ 'infinity',1.000000,0.000000);

INSERT INTO maintenance_windows VALUES
(1,'P-01',
 TIMESTAMPTZ '2026-11-11 09:45:00+05:30',
 TIMESTAMPTZ '2026-11-11 10:15:00+05:30',
 'planned bearing inspection');

INSERT INTO telemetry_readings VALUES
(1,'p01-vib-0800','P-01','vibration_mm_s','2026-11-11 08:00:00+05:30','2026-11-11 08:00:03+05:30',4.0,'good'),
(2,'p01-vib-0815','P-01','vibration_mm_s','2026-11-11 08:15:00+05:30','2026-11-11 08:15:02+05:30',4.1,'good'),
(3,'p01-vib-0830','P-01','vibration_mm_s','2026-11-11 08:30:00+05:30','2026-11-11 08:30:02+05:30',4.0,'good'),
(4,'p01-vib-0845','P-01','vibration_mm_s','2026-11-11 08:45:00+05:30','2026-11-11 08:45:02+05:30',4.2,'good'),
(5,'p01-vib-0900','P-01','vibration_mm_s','2026-11-11 09:00:00+05:30','2026-11-11 09:00:02+05:30',4.1,'good'),
(6,'p01-vib-0915','P-01','vibration_mm_s','2026-11-11 09:15:00+05:30','2026-11-11 09:16:00+05:30',10.2,'good'),
(7,'p01-vib-0915','P-01','vibration_mm_s','2026-11-11 09:15:00+05:30','2026-11-11 09:17:00+05:30',9.8,'good'),
(8,'p01-vib-0930','P-01','vibration_mm_s','2026-11-11 09:30:00+05:30','2026-11-11 09:30:02+05:30',4.2,'good'),
(9,'p01-vib-0945','P-01','vibration_mm_s','2026-11-11 09:45:00+05:30','2026-11-11 09:45:02+05:30',12.5,'good'),
(10,'p01-vib-1000','P-01','vibration_mm_s','2026-11-11 10:00:00+05:30','2026-11-11 10:00:02+05:30',4.0,'good'),
(11,'p01-vib-1015','P-01','vibration_mm_s','2026-11-11 10:15:00+05:30','2026-11-11 10:15:02+05:30',4.1,'good'),
(12,'p01-vib-1030','P-01','vibration_mm_s','2026-11-11 10:30:00+05:30','2026-11-11 10:30:02+05:30',4.0,'good'),
(13,'p01-vib-1045','P-01','vibration_mm_s','2026-11-11 10:45:00+05:30','2026-11-11 10:45:02+05:30',4.1,'good'),
(14,'p01-vib-1115','P-01','vibration_mm_s','2026-11-11 11:15:00+05:30','2026-11-11 11:15:02+05:30',4.2,'good'),

(15,'p01-temp-0800','P-01','temperature_c','2026-11-11 08:00:00+05:30','2026-11-11 08:00:03+05:30',70.0,'good'),
(16,'p01-temp-0815','P-01','temperature_c','2026-11-11 08:15:00+05:30','2026-11-11 08:15:03+05:30',71.0,'good'),
(17,'p01-temp-0830','P-01','temperature_c','2026-11-11 08:30:00+05:30','2026-11-11 08:30:03+05:30',72.0,'good'),
(18,'p01-temp-0845','P-01','temperature_c','2026-11-11 08:45:00+05:30','2026-11-11 08:45:03+05:30',72.0,'good'),
(19,'p01-temp-0900','P-01','temperature_c','2026-11-11 09:00:00+05:30','2026-11-11 09:00:03+05:30',73.0,'good'),
(20,'p01-temp-0915','P-01','temperature_c','2026-11-11 09:15:00+05:30','2026-11-11 09:15:03+05:30',74.0,'good'),
(21,'p01-temp-0930','P-01','temperature_c','2026-11-11 09:30:00+05:30','2026-11-11 09:30:03+05:30',75.0,'good'),
(22,'p01-temp-0945','P-01','temperature_c','2026-11-11 09:45:00+05:30','2026-11-11 09:45:03+05:30',76.0,'good'),
(23,'p01-temp-1015','P-01','temperature_c','2026-11-11 10:15:00+05:30','2026-11-11 10:15:03+05:30',73.0,'good'),
(24,'p01-temp-1030','P-01','temperature_c','2026-11-11 10:30:00+05:30','2026-11-11 10:30:03+05:30',72.0,'suspect'),
(25,'p01-temp-1045','P-01','temperature_c','2026-11-11 10:45:00+05:30','2026-11-11 10:45:03+05:30',72.0,'good'),

(26,'c02-vib-0800','C-02','vibration_mm_s','2026-11-11 08:00:00+05:30','2026-11-11 08:00:04+05:30',2.0,'good'),
(27,'c02-vib-0815','C-02','vibration_mm_s','2026-11-11 08:15:00+05:30','2026-11-11 08:15:04+05:30',2.1,'good'),
(28,'c02-vib-0830','C-02','vibration_mm_s','2026-11-11 08:30:00+05:30','2026-11-11 08:30:04+05:30',2.0,'good'),
(29,'c02-vib-0845','C-02','vibration_mm_s','2026-11-11 08:45:00+05:30','2026-11-11 08:45:04+05:30',2.2,'good'),
(30,'c02-vib-0900','C-02','vibration_mm_s','2026-11-11 09:00:00+05:30','2026-11-11 09:00:04+05:30',2.1,'good'),
(31,'c02-vib-0915','C-02','vibration_mm_s','2026-11-11 09:15:00+05:30','2026-11-11 09:15:04+05:30',2.0,'good'),
(32,'c02-vib-0930','C-02','vibration_mm_s','2026-11-11 09:30:00+05:30','2026-11-11 09:30:04+05:30',2.2,'good'),
(33,'c02-vib-0945','C-02','vibration_mm_s','2026-11-11 09:45:00+05:30','2026-11-11 09:45:04+05:30',2.1,'good'),
(34,'c02-vib-1000','C-02','vibration_mm_s','2026-11-11 10:00:00+05:30','2026-11-11 10:00:04+05:30',2.0,'good'),
(35,'c02-vib-1015','C-02','vibration_mm_s','2026-11-11 10:15:00+05:30','2026-11-11 10:15:04+05:30',2.1,'good');

-- A reusable canonical view keeps the latest ingested copy of each source event.
-- A deterministic tie-breaker prevents unstable results when ingestion times match.
CREATE OR REPLACE VIEW canonical_telemetry_readings AS
SELECT reading_id, source_event_id, asset_id, sensor_code, observed_at,
       ingested_at, raw_value, quality_status
FROM (
    SELECT r.*,
           ROW_NUMBER() OVER (
               PARTITION BY asset_id, sensor_code, source_event_id
               ORDER BY ingested_at DESC, reading_id DESC
           ) AS event_rank
    FROM telemetry_readings r
) ranked
WHERE event_rank = 1;

-- Q1. Find replayed source events and show which physical row wins canonicalization.
-- Solution:
SELECT asset_id, sensor_code, source_event_id,
       COUNT(*) AS received_copies,
       (ARRAY_AGG(reading_id ORDER BY ingested_at DESC, reading_id DESC))[1] AS chosen_reading_id
FROM telemetry_readings
GROUP BY asset_id, sensor_code, source_event_id
HAVING COUNT(*) > 1;

-- Optimization: partition by the business event key, not by every payload column.
-- The ordering includes a stable unique tie-breaker so retries are deterministic.

-- Q2. Convert raw measurements to engineering units using the calibration effective
--     at the event time. Preserve readings that have no matching calibration.
-- Solution:
SELECT r.reading_id, r.asset_id, r.sensor_code, r.observed_at,
       r.raw_value, c.calibration_id,
       CASE WHEN c.calibration_id IS NULL THEN NULL
            ELSE r.raw_value * c.multiplier + c.offset_value END AS calibrated_value
FROM canonical_telemetry_readings r
LEFT JOIN LATERAL (
    SELECT sc.calibration_id, sc.multiplier, sc.offset_value
    FROM sensor_calibrations sc
    WHERE sc.asset_id = r.asset_id
      AND sc.sensor_code = r.sensor_code
      AND sc.valid_from <= r.observed_at
      AND r.observed_at < sc.valid_to
    ORDER BY sc.valid_from DESC
    LIMIT 1
) c ON true
ORDER BY r.asset_id, r.sensor_code, r.observed_at;

-- Optimization: LATERAL performs an indexed as-of lookup for each reading and avoids
-- joining every historical calibration row. The half-open interval prevents a reading
-- at a calibration boundary from matching both the old and new calibration.

-- Q3. Separate readings collected during planned maintenance from operational data.
--     Return the reading and maintenance reason without multiplying rows.
-- Solution:
SELECT r.reading_id, r.asset_id, r.sensor_code, r.observed_at,
       r.raw_value, m.reason
FROM canonical_telemetry_readings r
JOIN maintenance_windows m
  ON m.asset_id = r.asset_id
 AND r.observed_at >= m.starts_at
 AND r.observed_at <  m.ends_at
ORDER BY r.asset_id, r.observed_at;

-- Optimization: the half-open range is index-friendly and makes adjacent maintenance
-- windows unambiguous. Use EXISTS instead of a join when only a suppression flag is needed.

-- Q4. Detect telemetry gaps longer than the expected 15-minute cadence.
--     Do not compare rows across different assets or sensor streams.
-- Solution:
WITH ordered AS (
    SELECT asset_id, sensor_code, observed_at,
           LAG(observed_at) OVER (
               PARTITION BY asset_id, sensor_code
               ORDER BY observed_at
           ) AS previous_observed_at
    FROM canonical_telemetry_readings
    WHERE quality_status = 'good'
)
SELECT asset_id, sensor_code, previous_observed_at, observed_at,
       observed_at - previous_observed_at AS gap_duration
FROM ordered
WHERE previous_observed_at IS NOT NULL
  AND observed_at - previous_observed_at > INTERVAL '15 minutes'
ORDER BY asset_id, sensor_code, observed_at;

-- Optimization: filter unusable quality states before the window and partition by the
-- complete stream key. LAG avoids a self-join and sorts only within each stream.

-- Q5. Build a leakage-safe one-hour rolling baseline for each sensor. The current
--     observation must not contribute to its own baseline; ignore bad-quality and
--     maintenance-window readings.
-- Solution:
WITH calibrated AS (
    SELECT r.asset_id, r.sensor_code, r.observed_at,
           r.raw_value * c.multiplier + c.offset_value AS value
    FROM canonical_telemetry_readings r
    JOIN LATERAL (
        SELECT multiplier, offset_value
        FROM sensor_calibrations sc
        WHERE sc.asset_id = r.asset_id
          AND sc.sensor_code = r.sensor_code
          AND sc.valid_from <= r.observed_at
          AND r.observed_at < sc.valid_to
        ORDER BY sc.valid_from DESC
        LIMIT 1
    ) c ON true
    WHERE r.quality_status = 'good'
      AND NOT EXISTS (
          SELECT 1
          FROM maintenance_windows m
          WHERE m.asset_id = r.asset_id
            AND r.observed_at >= m.starts_at
            AND r.observed_at <  m.ends_at
      )
),
baseline AS (
    SELECT *,
           COUNT(*) OVER w AS prior_sample_count,
           AVG(value) OVER w AS prior_1h_avg,
           STDDEV_SAMP(value) OVER w AS prior_1h_stddev
    FROM calibrated
    WINDOW w AS (
        PARTITION BY asset_id, sensor_code
        ORDER BY observed_at
        RANGE BETWEEN INTERVAL '1 hour' PRECEDING
                  AND INTERVAL '1 microsecond' PRECEDING
    )
)
SELECT asset_id, sensor_code, observed_at, value,
       prior_sample_count, ROUND(prior_1h_avg,4) AS prior_1h_avg,
       ROUND(prior_1h_stddev,4) AS prior_1h_stddev
FROM baseline
ORDER BY asset_id, sensor_code, observed_at;

-- Optimization: a time-based RANGE frame models elapsed time rather than assuming a
-- fixed row count. The frame ends just before the current instant to prevent target
-- leakage. For very large streams, persist calibrated canonical events by time partition.

-- Q6. Flag high-side anomalies when a reading exceeds its prior one-hour mean by
--     more than three sample standard deviations; require at least three prior samples.
-- Solution:
WITH calibrated AS (
    SELECT r.asset_id, r.sensor_code, r.observed_at,
           r.raw_value * c.multiplier + c.offset_value AS value
    FROM canonical_telemetry_readings r
    JOIN LATERAL (
        SELECT multiplier, offset_value
        FROM sensor_calibrations sc
        WHERE sc.asset_id = r.asset_id
          AND sc.sensor_code = r.sensor_code
          AND sc.valid_from <= r.observed_at
          AND r.observed_at < sc.valid_to
        ORDER BY sc.valid_from DESC
        LIMIT 1
    ) c ON true
    WHERE r.quality_status = 'good'
      AND NOT EXISTS (
          SELECT 1 FROM maintenance_windows m
          WHERE m.asset_id = r.asset_id
            AND r.observed_at >= m.starts_at
            AND r.observed_at < m.ends_at
      )
),
scored AS (
    SELECT *,
           COUNT(*) OVER w AS prior_n,
           AVG(value) OVER w AS baseline_avg,
           STDDEV_SAMP(value) OVER w AS baseline_sd
    FROM calibrated
    WINDOW w AS (
        PARTITION BY asset_id, sensor_code
        ORDER BY observed_at
        RANGE BETWEEN INTERVAL '1 hour' PRECEDING
                  AND INTERVAL '1 microsecond' PRECEDING
    )
)
SELECT asset_id, sensor_code, observed_at, ROUND(value,4) AS value,
       ROUND(baseline_avg,4) AS baseline_avg,
       ROUND(baseline_sd,4) AS baseline_sd,
       ROUND((value - baseline_avg) / NULLIF(baseline_sd,0),2) AS z_score
FROM scored
WHERE prior_n >= 3
  AND baseline_sd > 0
  AND value > baseline_avg + 3 * baseline_sd
ORDER BY observed_at DESC;

-- Optimization: compute the window statistics once in a CTE and filter afterward.
-- NULLIF protects the score from division by zero; the sample-count guard avoids
-- unstable alerts from tiny baselines. Production thresholds need domain calibration.

-- Q7. Produce 15-minute operational rollups with counts by quality state.
--     Exclude planned maintenance but retain suspect/invalid counts for observability.
-- Solution:
SELECT r.asset_id, r.sensor_code,
       date_bin(INTERVAL '15 minutes', r.observed_at,
                TIMESTAMPTZ '2000-01-01 00:00:00+00') AS bucket_start,
       COUNT(*) AS received_readings,
       COUNT(*) FILTER (WHERE r.quality_status = 'good') AS good_readings,
       COUNT(*) FILTER (WHERE r.quality_status = 'suspect') AS suspect_readings,
       COUNT(*) FILTER (WHERE r.quality_status = 'invalid') AS invalid_readings,
       ROUND(AVG(r.raw_value) FILTER (WHERE r.quality_status = 'good'),4) AS avg_raw_value
FROM canonical_telemetry_readings r
WHERE NOT EXISTS (
    SELECT 1 FROM maintenance_windows m
    WHERE m.asset_id = r.asset_id
      AND r.observed_at >= m.starts_at
      AND r.observed_at < m.ends_at
)
GROUP BY r.asset_id, r.sensor_code, bucket_start
ORDER BY r.asset_id, r.sensor_code, bucket_start;

-- Optimization: date_bin assigns timestamps to fixed-width buckets without generating
-- a calendar first. FILTER keeps quality-specific aggregates in one grouped scan.

-- Q8. Measure 15-minute telemetry coverage for every observed asset/sensor stream
--     between 08:00 and 11:15. Return missing slots as well as the coverage percentage.
-- Solution:
WITH streams AS (
    SELECT DISTINCT asset_id, sensor_code
    FROM canonical_telemetry_readings
),
expected_slots AS (
    SELECT s.asset_id, s.sensor_code, slot
    FROM streams s
    CROSS JOIN generate_series(
        TIMESTAMPTZ '2026-11-11 08:00:00+05:30',
        TIMESTAMPTZ '2026-11-11 11:15:00+05:30',
        INTERVAL '15 minutes'
    ) AS g(slot)
    WHERE NOT EXISTS (
        SELECT 1
        FROM maintenance_windows m
        WHERE m.asset_id = s.asset_id
          AND slot >= m.starts_at
          AND slot <  m.ends_at
    )
),
coverage AS (
    SELECT e.asset_id, e.sensor_code,
           COUNT(*) AS expected_slots,
           COUNT(r.reading_id) FILTER (WHERE r.quality_status = 'good') AS good_slots,
           ARRAY_AGG(e.slot ORDER BY e.slot)
               FILTER (WHERE r.reading_id IS NULL OR r.quality_status <> 'good') AS missing_or_bad_slots
    FROM expected_slots e
    LEFT JOIN canonical_telemetry_readings r
      ON r.asset_id = e.asset_id
     AND r.sensor_code = e.sensor_code
     AND r.observed_at = e.slot
    GROUP BY e.asset_id, e.sensor_code
)
SELECT asset_id, sensor_code, expected_slots, good_slots,
       ROUND(100.0 * good_slots / NULLIF(expected_slots,0),2) AS good_coverage_pct,
       missing_or_bad_slots
FROM coverage
ORDER BY asset_id, sensor_code;

-- Optimization: build the small expected time spine once, then equality-join on the
-- timestamp key. For production, derive expected cadence and active periods from a
-- sensor registry rather than assuming every sensor has the same 15-minute schedule.

-- Q9. Return the latest canonical reading per asset and sensor, including its quality.
-- Solution:
SELECT DISTINCT ON (asset_id, sensor_code)
       asset_id, sensor_code, observed_at, raw_value, quality_status, reading_id
FROM canonical_telemetry_readings
ORDER BY asset_id, sensor_code, observed_at DESC, ingested_at DESC, reading_id DESC;

-- Optimization: DISTINCT ON is concise and efficient with a matching B-tree index.
-- The ordering makes the selected latest row deterministic.

-- Q10. Detect overlapping calibration periods for the same asset/sensor stream.
--      Overlaps can cause ambiguous as-of joins and must be resolved before production.
-- Solution:
SELECT a.asset_id, a.sensor_code,
       a.calibration_id AS calibration_a,
       b.calibration_id AS calibration_b,
       a.valid_from AS a_valid_from, a.valid_to AS a_valid_to,
       b.valid_from AS b_valid_from, b.valid_to AS b_valid_to
FROM sensor_calibrations a
JOIN sensor_calibrations b
  ON b.asset_id = a.asset_id
 AND b.sensor_code = a.sensor_code
 AND b.calibration_id > a.calibration_id
 AND a.valid_from < b.valid_to
 AND b.valid_from < a.valid_to
ORDER BY a.asset_id, a.sensor_code, a.calibration_id, b.calibration_id;

-- Optimization: the strict overlap predicate implements half-open interval logic.
-- An exclusion constraint on (asset_id, sensor_code, tstzrange(valid_from, valid_to))
-- can enforce non-overlap in production when the required GiST operator class is used.

-- Suggested production indexes (benchmark with representative volumes):
-- CREATE INDEX telemetry_stream_time_idx
--     ON telemetry_readings (asset_id, sensor_code, observed_at DESC);
-- CREATE INDEX telemetry_event_dedupe_idx
--     ON telemetry_readings
--        (asset_id, sensor_code, source_event_id, ingested_at DESC, reading_id DESC);
-- CREATE INDEX calibration_asof_idx
--     ON sensor_calibrations (asset_id, sensor_code, valid_from DESC)
--     INCLUDE (valid_to, multiplier, offset_value);
-- CREATE INDEX maintenance_asset_start_idx
--     ON maintenance_windows (asset_id, starts_at, ends_at);

-- Performance and production notes:
-- 1. Deduplicate before calculating metrics; replayed events otherwise inflate counts
--    and distort rolling averages. Keep the raw landing table for auditability.
-- 2. Use event time (observed_at) for windows and ingestion time only for replay choice
--    and latency monitoring. Late-arriving events may require controlled recomputation.
-- 3. Apply calibration as of event time and retain the calibration_id used for lineage.
--    Validate that effective periods are gap-free and non-overlapping per sensor.
-- 4. Exclude maintenance windows from operational anomaly scoring, but keep a separate
--    maintenance-quality report so suppressed measurements are not silently discarded.
-- 5. For large histories, partition readings by observed_at (for example, monthly RANGE)
--    and consider BRIN on observed_at for append-heavy, physically time-correlated data.
-- 6. Avoid wrapping observed_at in date_trunc/date casts in selective WHERE predicates;
--    use explicit half-open timestamp bounds to preserve index range scans.
-- 7. Inspect EXPLAIN (ANALYZE, BUFFERS), sort spills, partition pruning and actual row
--    counts. The sample is intentionally small, so indexes may cost more than they save.
-- 8. A three-standard-deviation rule is an interview exercise, not a universal safety
--    threshold. Production alerting needs per-sensor limits, persistence/hysteresis,
--    seasonality, sensor drift handling and operator review.
