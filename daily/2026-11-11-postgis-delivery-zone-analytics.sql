-- Daily SQL Practice — 2026-11-11
-- Topic: PostGIS delivery zones, nearest hubs, geofences, and spatial aggregation
-- PostgreSQL 14+ with PostGIS 3.x
--
-- Run in a disposable database with permission to install PostGIS.
-- Execute Q1 and Q2 first; Q3-Q10 use the normalized geo_deliveries table.
-- Coordinates are longitude/latitude in EPSG:4326 (Pune-like sample geography).

CREATE EXTENSION IF NOT EXISTS postgis;

DROP TABLE IF EXISTS geo_driver_pings CASCADE;
DROP TABLE IF EXISTS geo_deliveries CASCADE;
DROP TABLE IF EXISTS geo_delivery_stage CASCADE;
DROP TABLE IF EXISTS geo_hubs CASCADE;
DROP TABLE IF EXISTS geo_service_zones CASCADE;

CREATE TABLE geo_service_zones (
    zone_id       integer PRIMARY KEY,
    zone_name     text NOT NULL,
    priority      integer NOT NULL,
    geom          geometry(MultiPolygon, 4326) NOT NULL
);

CREATE TABLE geo_hubs (
    hub_id        integer PRIMARY KEY,
    hub_name      text NOT NULL,
    geom          geometry(Point, 4326) NOT NULL
);

-- Raw landing table: coordinates have not yet been validated or converted.
CREATE TABLE geo_delivery_stage (
    delivery_id   bigint PRIMARY KEY,
    created_at    timestamptz NOT NULL,
    delivered_at  timestamptz,
    longitude     numeric(10,6),
    latitude      numeric(10,6),
    status        text NOT NULL,
    delivery_fee  numeric(10,2) NOT NULL
);

CREATE TABLE geo_deliveries (
    delivery_id   bigint PRIMARY KEY,
    created_at    timestamptz NOT NULL,
    delivered_at  timestamptz,
    customer_geom geometry(Point, 4326) NOT NULL,
    status        text NOT NULL,
    delivery_fee  numeric(10,2) NOT NULL
);

CREATE TABLE geo_driver_pings (
    ping_id       bigint PRIMARY KEY,
    driver_id     bigint NOT NULL,
    ping_ts       timestamptz NOT NULL,
    geom          geometry(Point, 4326) NOT NULL,
    speed_kph     numeric(6,2)
);

INSERT INTO geo_service_zones (zone_id, zone_name, priority, geom) VALUES
(1, 'West', 10, ST_Multi(ST_GeomFromText(
    'POLYGON((73.80 18.50,73.87 18.50,73.87 18.56,73.80 18.56,73.80 18.50))', 4326))),
(2, 'Central', 20, ST_Multi(ST_GeomFromText(
    'POLYGON((73.86 18.50,73.93 18.50,73.93 18.56,73.86 18.56,73.86 18.50))', 4326))),
(3, 'South', 30, ST_Multi(ST_GeomFromText(
    'POLYGON((73.82 18.45,73.89 18.45,73.89 18.51,73.82 18.51,73.82 18.45))', 4326)));

INSERT INTO geo_hubs (hub_id, hub_name, geom) VALUES
(1, 'West Fulfilment Hub',  ST_SetSRID(ST_MakePoint(73.81, 18.53), 4326)),
(2, 'East Fulfilment Hub',  ST_SetSRID(ST_MakePoint(73.92, 18.53), 4326)),
(3, 'South Fulfilment Hub', ST_SetSRID(ST_MakePoint(73.85, 18.46), 4326));

INSERT INTO geo_delivery_stage VALUES
(1001, '2026-11-11 08:10:00+05:30', '2026-11-11 08:42:00+05:30', 73.830000, 18.530000, 'delivered', 42.50),
(1002, '2026-11-11 08:20:00+05:30', '2026-11-11 09:05:00+05:30', 73.880000, 18.540000, 'delivered', 55.00),
(1003, '2026-11-11 09:05:00+05:30', NULL,                         73.910000, 18.530000, 'out_for_delivery', 38.00),
(1004, '2026-11-11 09:45:00+05:30', '2026-11-11 10:20:00+05:30', 73.850000, 18.480000, 'delivered', 47.00),
(1005, '2026-11-11 10:10:00+05:30', NULL,                         73.790000, 18.540000, 'cancelled', 0.00),
(1006, '2026-11-11 11:00:00+05:30', '2026-11-11 11:45:00+05:30', 73.870000, 18.490000, 'delivered', 49.00),
(1007, '2026-11-11 12:15:00+05:30', NULL,                         73.900000, 18.480000, 'assigned', 41.00),
(1008, '2026-11-11 13:00:00+05:30', '2026-11-11 13:30:00+05:30', 73.840000, 18.560000, 'delivered', 44.00),
(1009, '2026-11-11 14:00:00+05:30', NULL,                         999.000000, 18.530000, 'assigned', 35.00);

INSERT INTO geo_driver_pings VALUES
(1, 201, '2026-11-11 07:55:00+05:30', ST_SetSRID(ST_MakePoint(73.790,18.530),4326), 18.0),
(2, 201, '2026-11-11 08:00:00+05:30', ST_SetSRID(ST_MakePoint(73.810,18.530),4326), 22.0),
(3, 201, '2026-11-11 08:05:00+05:30', ST_SetSRID(ST_MakePoint(73.840,18.540),4326), 27.0),
(4, 201, '2026-11-11 08:10:00+05:30', ST_SetSRID(ST_MakePoint(73.880,18.540),4326), 31.0),
(5, 201, '2026-11-11 08:15:00+05:30', ST_SetSRID(ST_MakePoint(73.840,18.540),4326), 25.0),
(6, 201, '2026-11-11 08:20:00+05:30', ST_SetSRID(ST_MakePoint(73.790,18.530),4326), 16.0),
(7, 202, '2026-11-11 09:00:00+05:30', ST_SetSRID(ST_MakePoint(73.900,18.540),4326), 19.0),
(8, 202, '2026-11-11 09:05:00+05:30', ST_SetSRID(ST_MakePoint(73.860,18.540),4326), 24.0),
(9, 202, '2026-11-11 09:10:00+05:30', ST_SetSRID(ST_MakePoint(73.860,18.490),4326), 29.0);

-- Spatial indexes: build them before loading the normalized delivery rows.
CREATE INDEX geo_service_zones_geom_gix ON geo_service_zones USING GIST (geom);
CREATE INDEX geo_hubs_geom_gix ON geo_hubs USING GIST (geom);
CREATE INDEX geo_hubs_geography_gix ON geo_hubs USING GIST ((geom::geography));
CREATE INDEX geo_deliveries_geom_gix ON geo_deliveries USING GIST (customer_geom);
CREATE INDEX geo_driver_pings_geom_gix ON geo_driver_pings USING GIST (geom);
CREATE INDEX geo_driver_pings_driver_time_idx
    ON geo_driver_pings (driver_id, ping_ts, ping_id);

-- Q1. Landing-data validation
-- Problem: Find rows with missing or out-of-range longitude/latitude before
--          constructing spatial objects. Do not let invalid coordinates enter
--          the curated delivery table.
-- Solution:
SELECT delivery_id, longitude, latitude,
       CASE
         WHEN longitude IS NULL OR latitude IS NULL THEN 'missing_coordinate'
         WHEN longitude NOT BETWEEN -180 AND 180 THEN 'longitude_out_of_range'
         WHEN latitude NOT BETWEEN -90 AND 90 THEN 'latitude_out_of_range'
       END AS validation_error
FROM geo_delivery_stage
WHERE longitude IS NULL
   OR latitude IS NULL
   OR longitude NOT BETWEEN -180 AND 180
   OR latitude NOT BETWEEN -90 AND 90
ORDER BY delivery_id;

-- Optimization: simple numeric predicates are cheaper than invoking geometry
-- constructors for every staged row. Keep validation in the landing layer and
-- reject invalid records before spatial processing.

-- Q2. Idempotent normalization from longitude/latitude to a spatial point
-- Problem: Load valid stage rows into geo_deliveries. Re-running the load must
--          not create duplicates, and coordinates must use longitude first.
-- Solution:
INSERT INTO geo_deliveries (
    delivery_id, created_at, delivered_at, customer_geom, status, delivery_fee
)
SELECT delivery_id, created_at, delivered_at,
       ST_SetSRID(
           ST_MakePoint(longitude::double precision, latitude::double precision),
           4326
       ),
       status, delivery_fee
FROM geo_delivery_stage
WHERE longitude IS NOT NULL
  AND latitude IS NOT NULL
  AND longitude BETWEEN -180 AND 180
  AND latitude BETWEEN -90 AND 90
ON CONFLICT (delivery_id) DO UPDATE
SET created_at = EXCLUDED.created_at,
    delivered_at = EXCLUDED.delivered_at,
    customer_geom = EXCLUDED.customer_geom,
    status = EXCLUDED.status,
    delivery_fee = EXCLUDED.delivery_fee;

-- Optimization: construct the point once at ingestion and persist it in the
-- curated table. The conflict key makes replay safe. ST_SetSRID labels the
-- coordinate reference system; it does not transform coordinate values.

-- Q3. Deterministic point-in-polygon service-zone assignment
-- Problem: Assign each delivery to at most one service zone. Some polygons
--          intentionally overlap; choose the lowest priority value, then zone_id.
-- Solution:
SELECT d.delivery_id, assigned.zone_id, assigned.zone_name
FROM geo_deliveries d
LEFT JOIN LATERAL (
    SELECT z.zone_id, z.zone_name
    FROM geo_service_zones z
    WHERE z.geom && d.customer_geom
      AND ST_Covers(z.geom, d.customer_geom)
    ORDER BY z.priority, z.zone_id
    LIMIT 1
) assigned ON TRUE
ORDER BY d.delivery_id;

-- Optimization: the && bounding-box operator narrows candidates through the
-- GiST index; ST_Covers performs the exact test and includes polygon boundaries.
-- LATERAL with LIMIT 1 avoids emitting duplicate deliveries in overlapping zones.

-- Q4. Deliveries outside every active service zone
-- Problem: Return deliveries that cannot be assigned to any configured zone.
-- Solution:
SELECT d.delivery_id, ST_AsText(d.customer_geom) AS customer_location
FROM geo_deliveries d
WHERE NOT EXISTS (
    SELECT 1
    FROM geo_service_zones z
    WHERE z.geom && d.customer_geom
      AND ST_Covers(z.geom, d.customer_geom)
)
ORDER BY d.delivery_id;

-- Optimization: NOT EXISTS is an anti-semi join and can stop after the first
-- matching zone. The bounding-box predicate keeps the exact geometry test selective.

-- Q5. Nearest fulfilment hub within five kilometres
-- Problem: Find the nearest hub for each delivery when one is within 5,000 metres.
--          Return the exact spheroidal distance in metres.
-- Solution:
SELECT d.delivery_id, nearest.hub_id, nearest.hub_name,
       ROUND(nearest.distance_m::numeric, 1) AS distance_m
FROM geo_deliveries d
LEFT JOIN LATERAL (
    SELECT h.hub_id, h.hub_name,
           ST_Distance(h.geom::geography, d.customer_geom::geography) AS distance_m
    FROM geo_hubs h
    WHERE ST_DWithin(h.geom::geography, d.customer_geom::geography, 5000)
    ORDER BY h.geom::geography <-> d.customer_geom::geography
    LIMIT 1
) nearest ON TRUE
ORDER BY d.delivery_id;

-- Optimization: ST_DWithin is index-aware and applies a radius filter before
-- ranking. The geography GiST expression index supports metre-based searches;
-- the geography KNN operator (<->) finds a nearest candidate efficiently.
-- ST_Distance is calculated only for the selected hub and uses spheroidal distance.

-- Q6. Detect overlapping service zones and quantify the shared area
-- Problem: Find each overlapping zone pair and report shared area in square metres.
--          Ignore pairs that only touch at a boundary (zero area).
-- Solution:
SELECT a.zone_id AS zone_a, b.zone_id AS zone_b,
       ROUND(ST_Area(ST_Intersection(a.geom, b.geom)::geography)::numeric, 1)
           AS overlap_area_m2
FROM geo_service_zones a
JOIN geo_service_zones b
  ON a.zone_id < b.zone_id
 AND a.geom && b.geom
 AND ST_Intersects(a.geom, b.geom)
WHERE ST_Area(ST_Intersection(a.geom, b.geom)::geography) > 0
ORDER BY zone_a, zone_b;

-- Optimization: zone_id < zone_id evaluates each unordered pair once. Bounding
-- boxes and ST_Intersects prune non-overlapping candidates before intersection.
-- Geography area avoids treating square degrees as square metres.

-- Q7. Daily zone-level delivery and fee metrics
-- Problem: Aggregate deliveries by India-local business date and their single
--          priority-selected zone. Include unassigned deliveries in a separate
--          'UNASSIGNED' group rather than dropping them.
-- Solution:
WITH assigned AS (
    SELECT d.delivery_id, d.created_at, d.status, d.delivery_fee,
           z.zone_id, z.zone_name
    FROM geo_deliveries d
    LEFT JOIN LATERAL (
        SELECT sz.zone_id, sz.zone_name
        FROM geo_service_zones sz
        WHERE sz.geom && d.customer_geom
          AND ST_Covers(sz.geom, d.customer_geom)
        ORDER BY sz.priority, sz.zone_id
        LIMIT 1
    ) z ON TRUE
)
SELECT (created_at AT TIME ZONE 'Asia/Kolkata')::date AS business_date,
       COALESCE(zone_name, 'UNASSIGNED') AS zone_name,
       COUNT(*) AS delivery_count,
       COUNT(*) FILTER (WHERE status = 'delivered') AS delivered_count,
       SUM(delivery_fee) AS total_delivery_fees
FROM assigned
GROUP BY (created_at AT TIME ZONE 'Asia/Kolkata')::date,
         COALESCE(zone_name, 'UNASSIGNED')
ORDER BY business_date, zone_name;

-- Optimization: resolve one zone per delivery before aggregation to prevent
-- double counting from polygon overlaps. Convert timestamps to the reporting
-- timezone explicitly instead of relying on the database session timezone.

-- Q8. Detect driver geofence entry and exit transitions for the West zone
-- Problem: For each driver, emit only state changes as the ordered GPS pings
--          cross the West service-zone boundary. The first observed point is
--          a baseline, not an inferred transition.
-- Solution:
WITH classified AS (
    SELECT p.ping_id, p.driver_id, p.ping_ts,
           ST_Covers(z.geom, p.geom) AS is_inside
    FROM geo_driver_pings p
    JOIN geo_service_zones z ON z.zone_id = 1
    WHERE z.geom && p.geom
       OR ST_Covers(z.geom, p.geom) = FALSE
),
with_previous AS (
    SELECT *,
           LAG(is_inside) OVER (
               PARTITION BY driver_id
               ORDER BY ping_ts, ping_id
           ) AS previous_inside
    FROM classified
)
SELECT driver_id, ping_id, ping_ts,
       CASE WHEN is_inside THEN 'ENTER' ELSE 'EXIT' END AS transition
FROM with_previous
WHERE previous_inside IS NOT NULL
  AND previous_inside IS DISTINCT FROM is_inside
ORDER BY driver_id, ping_ts, ping_id;

-- Optimization: classify each ping once, then use LAG over the driver's
-- time-ordered stream. The ping_id tie-breaker makes ordering deterministic.
-- For large fleets, first restrict the ping time range and use a spatial
-- candidate filter; retain outside points because they are needed for exits.

-- Q9. Reconstruct driver tracks and calculate travelled distance
-- Problem: Build an ordered LineString per driver and calculate track length
--          in metres. Also report observation count and the observed time span.
-- Solution:
WITH tracks AS (
    SELECT driver_id,
           ST_MakeLine(geom ORDER BY ping_ts, ping_id) AS track_geom,
           COUNT(*) AS ping_count,
           MIN(ping_ts) AS first_ping,
           MAX(ping_ts) AS last_ping
    FROM geo_driver_pings
    GROUP BY driver_id
)
SELECT driver_id, ping_count, first_ping, last_ping,
       ROUND(ST_Length(track_geom::geography)::numeric, 1) AS track_length_m
FROM tracks
ORDER BY driver_id;

-- Optimization: ordered aggregation constructs one line per driver in one pass.
-- Cast the resulting line to geography for metre-based length. GPS noise,
-- sampling gaps, and road-network snapping are separate production concerns.

-- Q10. Build a 500-metre delivery-density grid
-- Problem: Count deliveries in projected 500m grid cells and return each cell's
--          grid anchor in WGS84 for mapping. Use a suitable local metric CRS.
-- Solution:
WITH projected AS (
    SELECT ST_SnapToGrid(ST_Transform(customer_geom, 32643), 500.0) AS grid_cell
    FROM geo_deliveries
)
SELECT ST_AsText(ST_Transform(grid_cell, 4326)) AS grid_anchor_wkt,
       COUNT(*) AS delivery_count
FROM projected
GROUP BY grid_cell
ORDER BY delivery_count DESC, grid_anchor_wkt;

-- Optimization: transform each point once in the CTE and aggregate by a snapped
-- metric grid. EPSG:32643 is appropriate for this Pune-like sample area; select
-- the correct projected CRS for the actual operating region.

-- Performance checklist:
-- 1. Run ANALYZE after bulk loads so the planner has current spatial statistics.
-- 2. Use GiST for geometry predicates and ST_DWithin for radius searches;
--    avoid ST_Distance(...) <= radius as the primary filter.
-- 3. Keep indexed columns in their stored CRS. If transforming in predicates is
--    unavoidable, consider a matching functional GiST index.
-- 4. Use geography for global/metre-based distance and area; use a suitable
--    projected geometry CRS for repeated local analytics and grid operations.
-- 5. Keep an explicit deterministic tie-breaker for overlapping zones and KNN
--    results where equal-distance candidates are possible.
-- 6. For very large append-only GPS tables, evaluate time partitioning and BRIN
--    indexes on ping_ts in addition to GiST; prune by time before spatial work.
-- 7. Benchmark realistic distributions with EXPLAIN (ANALYZE, BUFFERS). A spatial
--    index may not help when most rows match or the table is very small.
-- 8. Validate polygon topology and SRIDs at ingestion; ST_IsValid and ST_SRID
--    checks are preferable to discovering bad geometries in reporting queries.
