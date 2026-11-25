-- =============================================================================
-- Daily SQL Practice — 2026-11-25
-- Data Center Capacity Planning, Energy Observability & Carbon-Aware Scheduling
-- PostgreSQL 14+
--
-- Run independently in a disposable database. This script creates its own
-- dc_practice schema and intentionally includes replayed telemetry, a meter
-- variance, rack pressure, flexible workloads, and incomplete observations.
--
-- Suggested workflow: read each problem, attempt it, then inspect the solution.
-- Indexes are candidates: benchmark them with representative production volumes.
-- =============================================================================

DROP SCHEMA IF EXISTS dc_practice CASCADE;
CREATE SCHEMA dc_practice;
SET search_path = dc_practice, public;

-- -----------------------------------------------------------------------------
-- 0. Independent sample schema
-- -----------------------------------------------------------------------------

CREATE TABLE sites (
    site_id              text PRIMARY KEY,
    region               text NOT NULL,
    pue                  numeric(5,3) NOT NULL CHECK (pue >= 1.0),
    grid_zone            text NOT NULL
);

CREATE TABLE racks (
    rack_id              text PRIMARY KEY,
    site_id              text NOT NULL REFERENCES sites(site_id),
    capacity_kw          numeric(10,2) NOT NULL CHECK (capacity_kw > 0)
);

CREATE TABLE workloads (
    workload_id          text PRIMARY KEY,
    team_name            text NOT NULL,
    rack_id              text NOT NULL REFERENCES racks(rack_id),
    requested_kw         numeric(10,2) NOT NULL CHECK (requested_kw >= 0),
    priority              smallint NOT NULL CHECK (priority BETWEEN 1 AND 5),
    workload_status      text NOT NULL CHECK
                         (workload_status IN ('queued','running','completed','cancelled')),
    submitted_at         timestamptz NOT NULL,
    started_at           timestamptz,
    completed_at         timestamptz,
    flexible             boolean NOT NULL DEFAULT false,
    earliest_start       timestamptz,
    latest_start         timestamptz,
    estimated_minutes    integer CHECK (estimated_minutes > 0)
);

CREATE TABLE rack_telemetry_raw (
    event_id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    source_event_id      text NOT NULL,
    rack_id              text NOT NULL REFERENCES racks(rack_id),
    sampled_at           timestamptz NOT NULL,
    revision_no           integer NOT NULL,
    it_load_kw           numeric(10,3) NOT NULL,
    cooling_load_kw      numeric(10,3) NOT NULL DEFAULT 0,
    is_tombstone         boolean NOT NULL DEFAULT false,
    ingested_at          timestamptz NOT NULL
);

CREATE TABLE site_meter_raw (
    meter_event_id       bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    site_id              text NOT NULL REFERENCES sites(site_id),
    interval_start       timestamptz NOT NULL,
    interval_end         timestamptz NOT NULL,
    energy_kwh           numeric(12,3) NOT NULL,
    received_at          timestamptz NOT NULL,
    CHECK (interval_end > interval_start)
);

CREATE TABLE grid_forecast (
    grid_zone            text NOT NULL,
    forecast_hour        timestamptz NOT NULL,
    carbon_g_per_kwh     numeric(10,2) NOT NULL CHECK (carbon_g_per_kwh >= 0),
    forecast_version     integer NOT NULL,
    PRIMARY KEY (grid_zone, forecast_hour, forecast_version)
);

INSERT INTO sites VALUES
('SFO-1','US-West',1.28,'CAISO'),
('FRA-1','EU-Central',1.34,'DE-LU');

INSERT INTO racks VALUES
('R-A1','SFO-1',20.00),
('R-A2','SFO-1',16.00),
('R-B1','FRA-1',18.00);

INSERT INTO workloads VALUES
('W-100','payments','R-A1',7.00,1,'running','2026-11-24 18:00+00','2026-11-24 18:10+00',NULL,false,NULL,NULL,180),
('W-101','search','R-A1',5.50,2,'running','2026-11-24 19:00+00','2026-11-24 19:05+00',NULL,false,NULL,NULL,240),
('W-102','ml-platform','R-A2',8.00,3,'queued','2026-11-25 06:00+00',NULL,NULL,true,'2026-11-25 08:00+00','2026-11-25 14:00+00',120),
('W-103','analytics','R-B1',6.00,4,'queued','2026-11-25 06:10+00',NULL,NULL,true,'2026-11-25 09:00+00','2026-11-25 17:00+00',180),
('W-104','identity','R-B1',4.00,1,'running','2026-11-24 20:00+00','2026-11-24 20:02+00',NULL,false,NULL,NULL,90),
('W-105','batch-etl','R-A2',3.00,5,'completed','2026-11-24 01:00+00','2026-11-24 01:10+00','2026-11-24 03:10+00',true,'2026-11-24 01:00+00','2026-11-24 08:00+00',120);

-- One telemetry observation per rack/hour, plus a replay, a correction and
-- a tombstone. Canonicalization must use source_event_id and revision_no.
INSERT INTO rack_telemetry_raw
(source_event_id,rack_id,sampled_at,revision_no,it_load_kw,cooling_load_kw,is_tombstone,ingested_at)
VALUES
('A1-06','R-A1','2026-11-25 06:00+00',1,13.0,3.0,false,'2026-11-25 06:01+00'),
('A1-06','R-A1','2026-11-25 06:00+00',1,13.0,3.0,false,'2026-11-25 06:04+00'), -- replay
('A1-07','R-A1','2026-11-25 07:00+00',1,17.0,3.4,false,'2026-11-25 07:02+00'),
('A1-07','R-A1','2026-11-25 07:00+00',2,18.5,3.8,false,'2026-11-25 07:12+00'), -- correction
('A1-08','R-A1','2026-11-25 08:00+00',1,19.2,4.0,false,'2026-11-25 08:03+00'),
('A2-06','R-A2','2026-11-25 06:00+00',1,8.0,2.0,false,'2026-11-25 06:01+00'),
('A2-07','R-A2','2026-11-25 07:00+00',1,9.0,2.1,false,'2026-11-25 07:01+00'),
('A2-08','R-A2','2026-11-25 08:00+00',1,10.0,2.2,false,'2026-11-25 08:01+00'),
('B1-06','R-B1','2026-11-25 06:00+00',1,9.0,2.8,false,'2026-11-25 06:01+00'),
('B1-07','R-B1','2026-11-25 07:00+00',1,11.0,3.0,false,'2026-11-25 07:01+00'),
('B1-08','R-B1','2026-11-25 08:00+00',1,12.0,3.2,false,'2026-11-25 08:01+00'),
('B1-09','R-B1','2026-11-25 09:00+00',1,12.5,3.3,false,'2026-11-25 09:01+00'),
('B1-10','R-B1','2026-11-25 10:00+00',1,12.0,3.2,false,'2026-11-25 10:01+00'),
('B1-11','R-B1','2026-11-25 11:00+00',1,0.0,0.0,true,'2026-11-25 11:02+00'); -- tombstone

INSERT INTO site_meter_raw(site_id,interval_start,interval_end,energy_kwh,received_at)
VALUES
('SFO-1','2026-11-25 06:00+00','2026-11-25 07:00+00',28.2,'2026-11-25 07:05+00'),
('SFO-1','2026-11-25 07:00+00','2026-11-25 08:00+00',31.0,'2026-11-25 08:05+00'),
('FRA-1','2026-11-25 06:00+00','2026-11-25 07:00+00',15.8,'2026-11-25 07:05+00'),
('FRA-1','2026-11-25 07:00+00','2026-11-25 08:00+00',18.2,'2026-11-25 08:05+00');

INSERT INTO grid_forecast VALUES
('CAISO','2026-11-25 08:00+00',180,1),
('CAISO','2026-11-25 09:00+00',150,1),
('CAISO','2026-11-25 10:00+00',120,1),
('CAISO','2026-11-25 11:00+00',210,1),
('CAISO','2026-11-25 12:00+00',260,1),
('DE-LU','2026-11-25 08:00+00',310,1),
('DE-LU','2026-11-25 09:00+00',280,1),
('DE-LU','2026-11-25 10:00+00',240,1),
('DE-LU','2026-11-25 11:00+00',190,1),
('DE-LU','2026-11-25 12:00+00',170,1);

-- -----------------------------------------------------------------------------
-- Problems and optimized reference solutions
-- -----------------------------------------------------------------------------

-- Q1. Canonicalize rack telemetry.
-- Problem: keep the highest revision for each source event, break ties by
-- latest ingestion, and remove events whose winning revision is a tombstone.
-- Optimization: rank once in a narrow CTE; filter tombstones after ranking so
-- an older non-deleted revision cannot incorrectly reappear.
WITH ranked AS (
    SELECT t.*,
           ROW_NUMBER() OVER (
               PARTITION BY source_event_id
               ORDER BY revision_no DESC, ingested_at DESC, event_id DESC
           ) AS rn
    FROM rack_telemetry_raw AS t
)
SELECT source_event_id, rack_id, sampled_at, it_load_kw, cooling_load_kw
FROM ranked
WHERE rn = 1
  AND NOT is_tombstone
ORDER BY rack_id, sampled_at;

-- Q2. Calculate latest rack utilization and available headroom.
-- Problem: for each rack, report the latest valid load, utilization percentage,
-- and remaining kW. Do not count duplicate deliveries or tombstoned events.
-- Optimization: canonicalize first, then use DISTINCT ON for latest-per-rack;
-- the ORDER BY matches the recommended composite index below.
WITH ranked AS (
    SELECT t.*,
           ROW_NUMBER() OVER (
               PARTITION BY source_event_id
               ORDER BY revision_no DESC, ingested_at DESC, event_id DESC
           ) AS rn
    FROM rack_telemetry_raw t
),
canonical AS (
    SELECT * FROM ranked WHERE rn = 1 AND NOT is_tombstone
),
latest AS (
    SELECT DISTINCT ON (rack_id)
           rack_id, sampled_at, it_load_kw
    FROM canonical
    ORDER BY rack_id, sampled_at DESC
)
SELECT r.rack_id, r.capacity_kw, l.sampled_at, l.it_load_kw,
       ROUND(100.0 * l.it_load_kw / r.capacity_kw, 2) AS utilization_pct,
       ROUND(r.capacity_kw - l.it_load_kw, 2) AS headroom_kw
FROM racks r
LEFT JOIN latest l USING (rack_id)
ORDER BY utilization_pct DESC NULLS LAST;

-- Q3. Find sustained rack overloads.
-- Problem: flag racks with at least two consecutive observed hours above 85%.
-- Optimization: calculate the threshold once per row and use LAG rather than
-- self-joining telemetry to the previous hour. Gaps are not treated as adjacent.
WITH ranked AS (
    SELECT t.*,
           ROW_NUMBER() OVER (
               PARTITION BY source_event_id
               ORDER BY revision_no DESC, ingested_at DESC, event_id DESC
           ) rn
    FROM rack_telemetry_raw t
),
canonical AS (
    SELECT * FROM ranked WHERE rn=1 AND NOT is_tombstone
),
util AS (
    SELECT c.rack_id, c.sampled_at,
           c.it_load_kw / r.capacity_kw AS utilization,
           LAG(c.sampled_at) OVER w AS prior_sample_at,
           LAG(c.it_load_kw / r.capacity_kw) OVER w AS prior_utilization
    FROM canonical c
    JOIN racks r USING (rack_id)
    WINDOW w AS (PARTITION BY c.rack_id ORDER BY c.sampled_at)
)
SELECT rack_id, sampled_at, ROUND(100*utilization,2) AS utilization_pct
FROM util
WHERE utilization > 0.85
  AND prior_utilization > 0.85
  AND sampled_at = prior_sample_at + INTERVAL '1 hour'
ORDER BY rack_id, sampled_at;

-- Q4. Reconstruct hourly site energy and estimated facility energy.
-- Problem: convert rack IT kW samples into hourly IT kWh, then apply site PUE
-- to estimate facility energy. Use consecutive readings only.
-- Optimization: use LAG over each rack's ordered readings; aggregate to site
-- only after deriving each rack interval to preserve the correct grain.
WITH ranked AS (
    SELECT t.*,
           ROW_NUMBER() OVER (
               PARTITION BY source_event_id
               ORDER BY revision_no DESC, ingested_at DESC, event_id DESC
           ) rn
    FROM rack_telemetry_raw t
),
canonical AS (
    SELECT * FROM ranked WHERE rn=1 AND NOT is_tombstone
),
intervals AS (
    SELECT c.rack_id, c.sampled_at,
           LAG(c.sampled_at) OVER w AS prior_at,
           LAG(c.it_load_kw) OVER w AS prior_kw,
           c.it_load_kw
    FROM canonical c
    WINDOW w AS (PARTITION BY c.rack_id ORDER BY c.sampled_at)
),
rack_energy AS (
    SELECT i.rack_id, r.site_id, i.sampled_at,
           ((i.prior_kw + i.it_load_kw) / 2.0)
             * EXTRACT(EPOCH FROM (i.sampled_at-i.prior_at))/3600.0 AS it_kwh
    FROM intervals i
    JOIN racks r USING (rack_id)
    WHERE i.prior_at IS NOT NULL
      AND i.sampled_at-i.prior_at = INTERVAL '1 hour'
)
SELECT s.site_id, e.sampled_at,
       ROUND(SUM(e.it_kwh),3) AS it_energy_kwh,
       ROUND(SUM(e.it_kwh)*s.pue,3) AS estimated_facility_kwh
FROM rack_energy e
JOIN sites s USING (site_id)
GROUP BY s.site_id, e.sampled_at, s.pue
ORDER BY s.site_id, e.sampled_at;

-- Q5. Estimate carbon emissions for completed/running workloads.
-- Problem: attribute each workload's estimated energy to its site grid zone,
-- using the latest forecast version for the workload's scheduled hour.
-- Optimization: select one forecast row per zone/hour before joining; aggregate
-- at workload grain and apply PUE once. This is an estimate, not a meter reading.
WITH forecast_ranked AS (
    SELECT f.*,
           ROW_NUMBER() OVER (
               PARTITION BY grid_zone, forecast_hour
               ORDER BY forecast_version DESC
           ) rn
    FROM grid_forecast f
),
latest_forecast AS (
    SELECT * FROM forecast_ranked WHERE rn=1
)
SELECT w.workload_id, w.team_name, s.site_id,
       f.carbon_g_per_kwh,
       ROUND(w.requested_kw * COALESCE(w.estimated_minutes,60)/60.0,3)
           AS estimated_it_kwh,
       ROUND(w.requested_kw * COALESCE(w.estimated_minutes,60)/60.0
             * s.pue * f.carbon_g_per_kwh,2) AS estimated_carbon_g
FROM workloads w
JOIN racks r USING (rack_id)
JOIN sites s USING (site_id)
LEFT JOIN latest_forecast f
  ON f.grid_zone=s.grid_zone
 AND f.forecast_hour=date_trunc('hour', COALESCE(w.started_at,w.submitted_at))
WHERE w.workload_status IN ('running','completed')
ORDER BY estimated_carbon_g DESC NULLS LAST;

-- Q6. Rank feasible low-carbon start hours for flexible workloads.
-- Problem: for each flexible queued workload, rank forecast hours inside its
-- permitted window by carbon intensity. Return the lowest-carbon candidate.
-- Optimization: filter the forecast window in the join; use ROW_NUMBER per
-- workload, with forecast_hour as a deterministic tie-breaker.
WITH forecast_ranked AS (
    SELECT f.*,
           ROW_NUMBER() OVER (
               PARTITION BY grid_zone, forecast_hour
               ORDER BY forecast_version DESC
           ) AS version_rank
    FROM grid_forecast f
),
candidate_hours AS (
    SELECT w.workload_id, w.team_name, w.priority,
           f.forecast_hour, f.carbon_g_per_kwh,
           w.requested_kw * w.estimated_minutes / 60.0
             * s.pue * f.carbon_g_per_kwh AS estimated_carbon_g
    FROM workloads w
    JOIN racks r USING (rack_id)
    JOIN sites s USING (site_id)
    JOIN forecast_ranked f
      ON f.grid_zone=s.grid_zone
     AND f.forecast_hour >= date_trunc('hour',w.earliest_start)
     AND f.forecast_hour <= date_trunc('hour',w.latest_start)
     AND f.version_rank=1
    WHERE w.workload_status='queued'
      AND w.flexible
),
ranked AS (
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY workload_id
               ORDER BY estimated_carbon_g, forecast_hour
           ) AS choice_rank
    FROM candidate_hours
)
SELECT workload_id, team_name, priority, forecast_hour,
       ROUND(carbon_g_per_kwh,2) AS grid_intensity_g_per_kwh,
       ROUND(estimated_carbon_g,2) AS estimated_carbon_g
FROM ranked
WHERE choice_rank=1
ORDER BY priority, workload_id;

-- Q7. Detect queued workloads that cannot fit on their assigned rack.
-- Problem: compare running workload commitments plus each queued workload
-- against rack capacity. The query is an admission-control screen, not a
-- concurrency-safe reservation transaction.
-- Optimization: aggregate running commitments once per rack before joining
-- queued jobs; avoid a many-to-many workload self-join.
WITH running_load AS (
    SELECT rack_id, SUM(requested_kw) AS committed_kw
    FROM workloads
    WHERE workload_status='running'
    GROUP BY rack_id
)
SELECT w.workload_id, w.rack_id, r.capacity_kw,
       COALESCE(rl.committed_kw,0) AS running_kw,
       w.requested_kw AS requested_kw,
       COALESCE(rl.committed_kw,0)+w.requested_kw AS projected_kw,
       CASE WHEN COALESCE(rl.committed_kw,0)+w.requested_kw <= r.capacity_kw
            THEN 'FEASIBLE' ELSE 'CAPACITY_BREACH' END AS admission_result
FROM workloads w
JOIN racks r USING (rack_id)
LEFT JOIN running_load rl USING (rack_id)
WHERE w.workload_status='queued'
ORDER BY w.rack_id, w.priority, w.workload_id;

-- Q8. Report workload runtime percentiles by team.
-- Problem: compare completed workload durations by team and identify teams
-- whose P95 runtime exceeds 180 minutes.
-- Optimization: calculate duration once in a base CTE; ordered-set percentile
-- aggregates are computed at team grain rather than per workload.
WITH durations AS (
    SELECT team_name,
           EXTRACT(EPOCH FROM (completed_at-started_at))/60.0 AS runtime_minutes
    FROM workloads
    WHERE workload_status='completed'
      AND started_at IS NOT NULL
      AND completed_at IS NOT NULL
      AND completed_at >= started_at
)
SELECT team_name, COUNT(*) AS completed_workloads,
       ROUND(AVG(runtime_minutes),2) AS avg_runtime_minutes,
       ROUND((PERCENTILE_CONT(0.95) WITHIN GROUP
              (ORDER BY runtime_minutes))::numeric,2) AS p95_runtime_minutes,
       COUNT(*) FILTER (WHERE runtime_minutes > 180) AS over_180_min
FROM durations
GROUP BY team_name
ORDER BY p95_runtime_minutes DESC;

-- Q9. Identify unusual rack energy readings against a per-rack baseline.
-- Problem: flag hourly IT load observations more than two standard deviations
-- above that rack's observed mean. Use sample standard deviation and require
-- at least three observations.
-- Optimization: compute the baseline with window aggregates over canonical
-- rows; avoid rescanning raw telemetry for every observation.
WITH ranked AS (
    SELECT t.*,
           ROW_NUMBER() OVER (
               PARTITION BY source_event_id
               ORDER BY revision_no DESC, ingested_at DESC, event_id DESC
           ) rn
    FROM rack_telemetry_raw t
),
canonical AS (
    SELECT * FROM ranked WHERE rn=1 AND NOT is_tombstone
),
baseline AS (
    SELECT rack_id, sampled_at, it_load_kw,
           COUNT(*) OVER (PARTITION BY rack_id) AS observation_count,
           AVG(it_load_kw) OVER (PARTITION BY rack_id) AS mean_kw,
           STDDEV_SAMP(it_load_kw) OVER (PARTITION BY rack_id) AS sd_kw
    FROM canonical
)
SELECT rack_id, sampled_at, it_load_kw,
       ROUND(mean_kw,3) AS baseline_mean_kw,
       ROUND(sd_kw,3) AS baseline_sd_kw
FROM baseline
WHERE observation_count >= 3
  AND sd_kw > 0
  AND it_load_kw > mean_kw + 2*sd_kw
ORDER BY rack_id, sampled_at;

-- Q10. Reconcile site meter energy against rack-derived facility energy.
-- Problem: compare each site's meter interval to the sum of rack IT kWh times
-- PUE for the same interval. Report absolute and percentage variance.
-- Optimization: aggregate rack energy to site/hour first, then join the meter;
-- this avoids multiplying meter rows by rack rows.
WITH ranked AS (
    SELECT t.*,
           ROW_NUMBER() OVER (
               PARTITION BY source_event_id
               ORDER BY revision_no DESC, ingested_at DESC, event_id DESC
           ) rn
    FROM rack_telemetry_raw t
),
canonical AS (
    SELECT * FROM ranked WHERE rn=1 AND NOT is_tombstone
),
ordered AS (
    SELECT c.rack_id, c.sampled_at, c.it_load_kw,
           LAG(c.sampled_at) OVER w AS prior_at,
           LAG(c.it_load_kw) OVER w AS prior_kw
    FROM canonical c
    WINDOW w AS (PARTITION BY c.rack_id ORDER BY c.sampled_at)
),
site_hour AS (
    SELECT r.site_id, o.prior_at AS interval_start, o.sampled_at AS interval_end,
           SUM((o.prior_kw+o.it_load_kw)/2.0
               * EXTRACT(EPOCH FROM (o.sampled_at-o.prior_at))/3600.0
               * s.pue) AS estimated_facility_kwh
    FROM ordered o
    JOIN racks r USING (rack_id)
    JOIN sites s USING (site_id)
    WHERE o.prior_at IS NOT NULL
      AND o.sampled_at-o.prior_at=INTERVAL '1 hour'
    GROUP BY r.site_id, o.prior_at, o.sampled_at
)
SELECT m.site_id, m.interval_start, m.interval_end,
       m.energy_kwh AS metered_kwh,
       ROUND(h.estimated_facility_kwh,3) AS estimated_facility_kwh,
       ROUND(m.energy_kwh-h.estimated_facility_kwh,3) AS variance_kwh,
       ROUND(100.0*(m.energy_kwh-h.estimated_facility_kwh)
             / NULLIF(m.energy_kwh,0),2) AS variance_pct
FROM site_meter_raw m
LEFT JOIN site_hour h
  ON h.site_id=m.site_id
 AND h.interval_start=m.interval_start
 AND h.interval_end=m.interval_end
ORDER BY m.site_id, m.interval_start;

-- -----------------------------------------------------------------------------
-- Performance lab: candidate indexes (benchmark, do not blindly deploy)
-- -----------------------------------------------------------------------------

-- Supports source-event revision canonicalization.
CREATE INDEX ix_dc_telemetry_event_revision
    ON rack_telemetry_raw
       (source_event_id, revision_no DESC, ingested_at DESC, event_id DESC);

-- Supports rack timeline access and latest-per-rack queries.
CREATE INDEX ix_dc_telemetry_rack_sample
    ON rack_telemetry_raw (rack_id, sampled_at DESC)
    INCLUDE (it_load_kw, cooling_load_kw, source_event_id, revision_no, is_tombstone);

-- Partial index for active operational workloads.
CREATE INDEX ix_dc_workloads_running_rack
    ON workloads (rack_id) INCLUDE (requested_kw)
    WHERE workload_status='running';

-- Supports flexible queued workload window scans.
CREATE INDEX ix_dc_workloads_flexible_queue
    ON workloads (priority, earliest_start, latest_start)
    WHERE workload_status='queued' AND flexible;

-- Forecast lookup by zone and hour, latest version included in ordering.
CREATE INDEX ix_dc_forecast_zone_hour_version
    ON grid_forecast (grid_zone, forecast_hour, forecast_version DESC)
    INCLUDE (carbon_g_per_kwh);

-- Suggested experiments:
-- EXPLAIN (ANALYZE, BUFFERS) each solution before/after indexes.
-- For large append-only telemetry, evaluate monthly RANGE partitioning on
-- sampled_at and BRIN (sampled_at); retain a B-tree for selective rack access.
-- Keep canonicalization source_event_id stable across replay/revision deliveries.
-- Consider a materialized hourly canonical telemetry table for repeated reports.
-- Do not use a sampled kW reading as interval energy unless the sampling and
-- interpolation assumptions are explicit. Meter reconciliation must align
-- interval boundaries, timezone, units, and PUE version.
-- Carbon scheduling is advisory: enforce priority, deadline, capacity,
-- redundancy, and data-residency constraints before moving real workloads.

-- -----------------------------------------------------------------------------
-- Expected spot checks (approximate, based on supplied sample data)
-- -----------------------------------------------------------------------------
-- Q1: the replayed A1-06 appears once; A1-07 uses revision 2; B1-11 is absent.
-- Q2: R-A1 latest canonical load is 19.2 kW / 20 kW = 96% utilization.
-- Q3: R-A1 has consecutive >85% observations at 07:00 and 08:00 UTC.
-- Q6: flexible queued workloads receive the lowest-intensity in-window forecast
--     hour available for their site's grid zone.
-- Q7: W-102 is screened against R-A2's 16 kW capacity; W-103 against R-B1.
-- Q10: meter and rack-derived energy can differ because sample readings are
--      interpolated and PUE is applied; investigate rather than force equality.
