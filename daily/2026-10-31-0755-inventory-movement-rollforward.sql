-- PostgreSQL 14+
-- Topic: Inventory movement roll-forward, replay-safe ledger, and stock controls
-- Run this file in one PostgreSQL session. All setup tables are TEMP tables.

-- ============================================================
-- SETUP: isolated retail inventory model
-- ============================================================

CREATE TEMP TABLE inv_product (
    product_id      text PRIMARY KEY,
    product_name    text NOT NULL,
    unit_cost       numeric(12,2) NOT NULL CHECK (unit_cost >= 0),
    safety_stock    numeric(12,2) NOT NULL DEFAULT 0,
    lead_time_days  integer NOT NULL CHECK (lead_time_days >= 0)
);

CREATE TEMP TABLE inv_warehouse (
    warehouse_id    text PRIMARY KEY,
    warehouse_name  text NOT NULL,
    city            text NOT NULL
);

-- Opening quantity is the trusted ledger balance at 2026-10-01 00:00.
CREATE TEMP TABLE inv_opening_balance (
    product_id      text NOT NULL REFERENCES inv_product(product_id),
    warehouse_id    text NOT NULL REFERENCES inv_warehouse(warehouse_id),
    opening_at      timestamp NOT NULL,
    opening_qty     numeric(14,2) NOT NULL,
    PRIMARY KEY (product_id, warehouse_id)
);

-- quantity_delta is signed: receipts/returns are positive; shipments/damage are negative.
-- source_system + source_ref is the source event's idempotency key.
CREATE TEMP TABLE inv_movement (
    movement_id     bigint PRIMARY KEY,
    source_system   text NOT NULL,
    source_ref      text NOT NULL,
    product_id      text NOT NULL REFERENCES inv_product(product_id),
    warehouse_id    text NOT NULL REFERENCES inv_warehouse(warehouse_id),
    occurred_at     timestamp NOT NULL,
    ingested_at     timestamp NOT NULL,
    movement_type   text NOT NULL,
    quantity_delta  numeric(14,2) NOT NULL,
    CHECK (movement_type IN
        ('RECEIPT', 'SHIPMENT', 'CUSTOMER_RETURN', 'DAMAGE', 'ADJUSTMENT'))
);

CREATE TEMP TABLE inv_physical_count (
    product_id      text NOT NULL,
    warehouse_id    text NOT NULL,
    counted_at      timestamp NOT NULL,
    counted_qty     numeric(14,2) NOT NULL,
    count_reference text NOT NULL,
    PRIMARY KEY (product_id, warehouse_id, counted_at)
);

INSERT INTO inv_product VALUES
('P-100', 'Wireless keyboard', 1250.00, 25, 5),
('P-200', 'USB-C dock',        4200.00, 10, 7),
('P-300', 'Laptop stand',      850.00, 15, 4);

INSERT INTO inv_warehouse VALUES
('WH-PUN', 'Pune distribution centre', 'Pune'),
('WH-MUM', 'Mumbai fulfilment centre', 'Mumbai');

INSERT INTO inv_opening_balance VALUES
('P-100', 'WH-PUN', TIMESTAMP '2026-10-01 00:00:00', 100),
('P-100', 'WH-MUM', TIMESTAMP '2026-10-01 00:00:00',  40),
('P-200', 'WH-PUN', TIMESTAMP '2026-10-01 00:00:00',  20),
('P-300', 'WH-PUN', TIMESTAMP '2026-10-01 00:00:00',   5);

INSERT INTO inv_movement VALUES
(1001, 'ERP', 'ASN-1001',     'P-100', 'WH-PUN', TIMESTAMP '2026-10-02 09:00', TIMESTAMP '2026-10-02 09:03', 'RECEIPT',          50),
(1002, 'OMS', 'SHIP-1001',   'P-100', 'WH-PUN', TIMESTAMP '2026-10-03 10:00', TIMESTAMP '2026-10-03 10:02', 'SHIPMENT',        -30),
(1003, 'POS', 'RETURN-1001', 'P-100', 'WH-PUN', TIMESTAMP '2026-10-04 12:00', TIMESTAMP '2026-10-04 12:05', 'CUSTOMER_RETURN',   5),
(1004, 'WMS', 'DAMAGE-1001', 'P-100', 'WH-PUN', TIMESTAMP '2026-10-05 15:00', TIMESTAMP '2026-10-05 15:02', 'DAMAGE',           -3),
(1005, 'OMS', 'SHIP-1002',   'P-100', 'WH-PUN', TIMESTAMP '2026-10-06 10:00', TIMESTAMP '2026-10-06 10:04', 'SHIPMENT',       -125),
(1006, 'OMS', 'SHIP-2001',   'P-200', 'WH-PUN', TIMESTAMP '2026-10-02 08:00', TIMESTAMP '2026-10-02 08:02', 'SHIPMENT',        -22),
(1007, 'ERP', 'ASN-2001',    'P-200', 'WH-PUN', TIMESTAMP '2026-10-03 08:00', TIMESTAMP '2026-10-03 08:03', 'RECEIPT',           10),
(1008, 'ERP', 'ASN-3001',    'P-300', 'WH-PUN', TIMESTAMP '2026-10-07 09:00', TIMESTAMP '2026-10-07 09:02', 'RECEIPT',            2),
(1009, 'OMS', 'SHIP-3001',   'P-300', 'WH-PUN', TIMESTAMP '2026-10-08 11:00', TIMESTAMP '2026-10-08 11:02', 'SHIPMENT',         -1),
-- Intentional replay of movement 1009. The later ingestion is the canonical copy.
(1010, 'OMS', 'SHIP-3001',   'P-300', 'WH-PUN', TIMESTAMP '2026-10-08 11:00', TIMESTAMP '2026-10-08 11:15', 'SHIPMENT',         -1),
(1011, 'OMS', 'SHIP-1003',   'P-100', 'WH-MUM', TIMESTAMP '2026-10-03 13:00', TIMESTAMP '2026-10-03 13:02', 'SHIPMENT',        -10),
(1012, 'ERP', 'ASN-1002',    'P-100', 'WH-MUM', TIMESTAMP '2026-10-04 08:00', TIMESTAMP '2026-10-04 08:03', 'RECEIPT',           25);

INSERT INTO inv_physical_count VALUES
('P-100', 'WH-PUN', TIMESTAMP '2026-10-09 18:00',  2, 'COUNT-PUN-100'),
('P-100', 'WH-MUM', TIMESTAMP '2026-10-09 18:00', 54, 'COUNT-MUM-100'),
('P-200', 'WH-PUN', TIMESTAMP '2026-10-09 18:00',  8, 'COUNT-PUN-200'),
('P-300', 'WH-PUN', TIMESTAMP '2026-10-09 18:00',  6, 'COUNT-PUN-300');

-- ============================================================
-- COMMON PATTERN
-- Canonicalize replayed source events before summing the ledger.
-- Reuse this pattern in each independent exercise below.
-- ============================================================

-- 1. PROBLEM: Calculate the as-of closing balance at each product/warehouse grain.
--    A naive SUM(quantity_delta) double-counts replayed source events.
--    SOLUTION:
WITH params AS (
    SELECT TIMESTAMP '2026-10-10 00:00:00' AS as_of_ts
),
ranked_movements AS (
    SELECT m.*,
           ROW_NUMBER() OVER (
               PARTITION BY source_system, source_ref
               ORDER BY ingested_at DESC, movement_id DESC
           ) AS replay_rank
    FROM inv_movement m
    CROSS JOIN params p
    WHERE m.occurred_at < p.as_of_ts
),
movement_totals AS (
    SELECT product_id, warehouse_id, SUM(quantity_delta) AS net_movement
    FROM ranked_movements
    WHERE replay_rank = 1
    GROUP BY product_id, warehouse_id
)
SELECT o.product_id,
       o.warehouse_id,
       o.opening_qty,
       COALESCE(mt.net_movement, 0) AS net_movement,
       o.opening_qty + COALESCE(mt.net_movement, 0) AS closing_qty
FROM inv_opening_balance o
LEFT JOIN movement_totals mt
  ON mt.product_id = o.product_id
 AND mt.warehouse_id = o.warehouse_id
ORDER BY o.product_id, o.warehouse_id;

-- EXPECTED SPOT CHECKS:
-- P-100 / WH-PUN = -3; P-100 / WH-MUM = 55;
-- P-200 / WH-PUN = 8;  P-300 / WH-PUN = 6.
--
-- OPTIMIZATION:
-- Filter the event-time range before the window and aggregate. Canonicalize once
-- in the ingestion layer in production, then persist a unique source event key.
-- Do not use DISTINCT on the final quantity: different legitimate movements can
-- have identical values.

-- 2. PROBLEM: Find every ledger point where stock becomes negative.
--    The ordering must be deterministic when two events share a timestamp.
--    SOLUTION:
WITH params AS (
    SELECT TIMESTAMP '2026-10-10 00:00:00' AS as_of_ts
),
ranked AS (
    SELECT m.*,
           ROW_NUMBER() OVER (
               PARTITION BY source_system, source_ref
               ORDER BY ingested_at DESC, movement_id DESC
           ) AS replay_rank
    FROM inv_movement m
    CROSS JOIN params p
    WHERE m.occurred_at < p.as_of_ts
),
ledger_events AS (
    SELECT product_id, warehouse_id, opening_at AS event_ts,
           0::bigint AS movement_id, opening_qty AS quantity_delta,
           'OPENING'::text AS event_type
    FROM inv_opening_balance
    UNION ALL
    SELECT product_id, warehouse_id, occurred_at,
           movement_id, quantity_delta, movement_type
    FROM ranked
    WHERE replay_rank = 1
),
running AS (
    SELECT *,
           SUM(quantity_delta) OVER (
               PARTITION BY product_id, warehouse_id
               ORDER BY event_ts, movement_id
               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
           ) AS running_qty
    FROM ledger_events
)
SELECT product_id, warehouse_id, event_ts, event_type,
       quantity_delta, running_qty
FROM running
WHERE running_qty < 0
ORDER BY product_id, warehouse_id, event_ts, movement_id;

-- EXPECTED: P-200 / WH-PUN becomes negative after its first shipment;
-- P-100 / WH-PUN becomes negative after shipment SHIP-1002.
--
-- OPTIMIZATION:
-- The explicit ROWS frame avoids peer-group surprises from the default RANGE
-- frame. Keep movement_id in the ordering key. For very large histories, maintain
-- periodic trusted balance snapshots and replay only movements after the snapshot.

-- 3. PROBLEM: Produce daily closing balances, including dates with no movement.
--    This is useful for daily inventory snapshots and downstream trend reports.
--    SOLUTION:
WITH params AS (
    SELECT DATE '2026-10-01' AS start_date,
           DATE '2026-10-09' AS end_date
),
pairs AS (
    SELECT product_id, warehouse_id, opening_qty
    FROM inv_opening_balance
),
calendar AS (
    SELECT generate_series(p.start_date, p.end_date, INTERVAL '1 day')::date AS snapshot_date
    FROM params p
),
ranked AS (
    SELECT m.*,
           ROW_NUMBER() OVER (
               PARTITION BY source_system, source_ref
               ORDER BY ingested_at DESC, movement_id DESC
           ) AS replay_rank
    FROM inv_movement m
    CROSS JOIN params p
    WHERE m.occurred_at >= p.start_date::timestamp
      AND m.occurred_at < (p.end_date + 1)::timestamp
),
daily_delta AS (
    SELECT product_id, warehouse_id, occurred_at::date AS movement_date,
           SUM(quantity_delta) AS net_delta
    FROM ranked
    WHERE replay_rank = 1
    GROUP BY product_id, warehouse_id, occurred_at::date
),
dense_daily AS (
    SELECT pa.product_id, pa.warehouse_id, c.snapshot_date,
           pa.opening_qty,
           COALESCE(dd.net_delta, 0) AS net_delta
    FROM pairs pa
    CROSS JOIN calendar c
    LEFT JOIN daily_delta dd
      ON dd.product_id = pa.product_id
     AND dd.warehouse_id = pa.warehouse_id
     AND dd.movement_date = c.snapshot_date
),
balances AS (
    SELECT *,
           opening_qty
           + SUM(net_delta) OVER (
               PARTITION BY product_id, warehouse_id
               ORDER BY snapshot_date
               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
             ) AS closing_qty
    FROM dense_daily
)
SELECT product_id, warehouse_id, snapshot_date, net_delta, closing_qty
FROM balances
ORDER BY product_id, warehouse_id, snapshot_date;

-- OPTIMIZATION:
-- Densify only the required product/warehouse/date domain. For a large enterprise
-- calendar, persist a date dimension and avoid an unrestricted Cartesian product.
-- Partition the movement fact by occurred_at and retain half-open date predicates.

-- 4. PROBLEM: Reconcile the ledger balance to the latest physical count.
--    Return only variances outside a configurable tolerance.
--    SOLUTION:
WITH params AS (
    SELECT TIMESTAMP '2026-10-10 00:00:00' AS as_of_ts,
           0.01::numeric AS tolerance
),
ranked AS (
    SELECT m.*,
           ROW_NUMBER() OVER (
               PARTITION BY source_system, source_ref
               ORDER BY ingested_at DESC, movement_id DESC
           ) AS replay_rank
    FROM inv_movement m
    CROSS JOIN params p
    WHERE m.occurred_at < p.as_of_ts
),
ledger AS (
    SELECT o.product_id, o.warehouse_id,
           o.opening_qty + COALESCE(SUM(r.quantity_delta)
               FILTER (WHERE r.replay_rank = 1), 0) AS ledger_qty
    FROM inv_opening_balance o
    LEFT JOIN ranked r
      ON r.product_id = o.product_id
     AND r.warehouse_id = o.warehouse_id
    GROUP BY o.product_id, o.warehouse_id, o.opening_qty
),
latest_count AS (
    SELECT DISTINCT ON (product_id, warehouse_id)
           product_id, warehouse_id, counted_at, counted_qty, count_reference
    FROM inv_physical_count
    ORDER BY product_id, warehouse_id, counted_at DESC, count_reference DESC
)
SELECT l.product_id, l.warehouse_id, l.ledger_qty,
       c.counted_qty, l.ledger_qty - c.counted_qty AS variance_qty,
       c.count_reference
FROM ledger l
JOIN latest_count c USING (product_id, warehouse_id)
CROSS JOIN params p
WHERE ABS(l.ledger_qty - c.counted_qty) > p.tolerance
ORDER BY ABS(l.ledger_qty - c.counted_qty) DESC;

-- EXPECTED: P-100 / WH-PUN and P-100 / WH-MUM are exceptions.
-- P-200 and P-300 reconcile after replay removal.
--
-- OPTIMIZATION:
-- Select the latest count with DISTINCT ON backed by
-- (product_id, warehouse_id, counted_at DESC). Keep the tolerance numeric;
-- do not cast quantities to floating point.

-- 5. PROBLEM: Quantify replayed source events before they corrupt inventory.
--    SOLUTION:
SELECT source_system, source_ref,
       COUNT(*) AS physical_copies,
       COUNT(DISTINCT (product_id, warehouse_id, occurred_at,
                       movement_type, quantity_delta)) AS distinct_payloads,
       MIN(ingested_at) AS first_seen_at,
       MAX(ingested_at) AS last_seen_at
FROM inv_movement
GROUP BY source_system, source_ref
HAVING COUNT(*) > 1
ORDER BY physical_copies DESC, source_system, source_ref;

-- EXPECTED: OMS / SHIP-3001 has two physical copies but one distinct payload.
--
-- OPTIMIZATION:
-- Monitor duplicate rates by source and ingestion batch. A unique constraint on
-- (source_system, source_ref) is appropriate only after the ingestion process
-- defines how corrections and source-side revisions are represented.

-- 6. PROBLEM: Identify positive-stock items with no movement in the last 7 days.
--    This is a slow-moving inventory signal, not proof that the item is obsolete.
--    SOLUTION:
WITH params AS (
    SELECT TIMESTAMP '2026-10-10 00:00:00' AS as_of_ts
),
ranked AS (
    SELECT m.*,
           ROW_NUMBER() OVER (
               PARTITION BY source_system, source_ref
               ORDER BY ingested_at DESC, movement_id DESC
           ) AS replay_rank
    FROM inv_movement m
    CROSS JOIN params p
    WHERE m.occurred_at < p.as_of_ts
),
balances AS (
    SELECT o.product_id, o.warehouse_id,
           o.opening_qty + COALESCE(SUM(r.quantity_delta)
               FILTER (WHERE r.replay_rank = 1), 0) AS closing_qty,
           MAX(r.occurred_at) FILTER (WHERE r.replay_rank = 1) AS last_movement_at
    FROM inv_opening_balance o
    LEFT JOIN ranked r
      ON r.product_id = o.product_id
     AND r.warehouse_id = o.warehouse_id
    GROUP BY o.product_id, o.warehouse_id, o.opening_qty
)
SELECT b.product_id, b.warehouse_id, b.closing_qty, b.last_movement_at,
       p.as_of_ts - b.last_movement_at AS inactivity_interval
FROM balances b
CROSS JOIN params p
WHERE b.closing_qty > 0
  AND (b.last_movement_at IS NULL
       OR b.last_movement_at < p.as_of_ts - INTERVAL '7 days')
ORDER BY b.closing_qty DESC;

-- OPTIMIZATION:
-- Maintain last_movement_at as a derived aggregate if this report is frequent.
-- A MAX() over the full ledger is expensive when repeatedly recalculated.

-- 7. PROBLEM: Calculate a simple reorder point using the last seven calendar
--    days of outbound demand, lead time, and safety stock.
--    Zero-movement days must remain in the daily average.
--    SOLUTION:
WITH params AS (
    SELECT DATE '2026-10-10' AS as_of_date
),
calendar AS (
    SELECT generate_series(
        (SELECT as_of_date - 7 FROM params),
        (SELECT as_of_date - 1 FROM params),
        INTERVAL '1 day'
    )::date AS demand_date
),
pairs AS (
    SELECT o.product_id, o.warehouse_id
    FROM inv_opening_balance o
),
ranked AS (
    SELECT m.*,
           ROW_NUMBER() OVER (
               PARTITION BY source_system, source_ref
               ORDER BY ingested_at DESC, movement_id DESC
           ) AS replay_rank
    FROM inv_movement m
    CROSS JOIN params p
    WHERE m.occurred_at >= (p.as_of_date - 7)::timestamp
      AND m.occurred_at < p.as_of_date::timestamp
),
daily_outbound AS (
    SELECT product_id, warehouse_id, occurred_at::date AS demand_date,
           SUM(-quantity_delta) AS outbound_qty
    FROM ranked
    WHERE replay_rank = 1
      AND quantity_delta < 0
      AND movement_type IN ('SHIPMENT', 'DAMAGE')
    GROUP BY product_id, warehouse_id, occurred_at::date
),
average_demand AS (
    SELECT pa.product_id, pa.warehouse_id,
           AVG(COALESCE(d.outbound_qty, 0)) AS avg_daily_outbound
    FROM pairs pa
    CROSS JOIN calendar c
    LEFT JOIN daily_outbound d
      ON d.product_id = pa.product_id
     AND d.warehouse_id = pa.warehouse_id
     AND d.demand_date = c.demand_date
    GROUP BY pa.product_id, pa.warehouse_id
),
current_balance AS (
    SELECT o.product_id, o.warehouse_id,
           o.opening_qty + COALESCE(SUM(r.quantity_delta)
               FILTER (WHERE r.replay_rank = 1), 0) AS closing_qty
    FROM inv_opening_balance o
    LEFT JOIN (
        SELECT m.*,
               ROW_NUMBER() OVER (
                   PARTITION BY source_system, source_ref
                   ORDER BY ingested_at DESC, movement_id DESC
               ) AS replay_rank
        FROM inv_movement m
        CROSS JOIN params p
        WHERE m.occurred_at < p.as_of_date::timestamp
    ) r
      ON r.product_id = o.product_id
     AND r.warehouse_id = o.warehouse_id
    GROUP BY o.product_id, o.warehouse_id, o.opening_qty
)
SELECT b.product_id, b.warehouse_id, b.closing_qty,
       ROUND(a.avg_daily_outbound, 2) AS avg_daily_outbound,
       p.safety_stock,
       p.lead_time_days,
       ROUND(a.avg_daily_outbound * p.lead_time_days + p.safety_stock, 2)
           AS reorder_point,
       b.closing_qty <=
           a.avg_daily_outbound * p.lead_time_days + p.safety_stock
           AS reorder_recommended
FROM current_balance b
JOIN average_demand a USING (product_id, warehouse_id)
JOIN inv_product p USING (product_id)
ORDER BY reorder_recommended DESC, b.product_id, b.warehouse_id;

-- OPTIMIZATION:
-- The calendar join is intentional: omitting zero-demand days inflates average
-- demand. In production, use a curated demand calendar and a forecast model rather
-- than treating a seven-day mean as a complete replenishment policy.

-- 8. PROBLEM: Value closing inventory and expose negative quantities explicitly.
--    SOLUTION:
WITH params AS (
    SELECT TIMESTAMP '2026-10-10 00:00:00' AS as_of_ts
),
ranked AS (
    SELECT m.*,
           ROW_NUMBER() OVER (
               PARTITION BY source_system, source_ref
               ORDER BY ingested_at DESC, movement_id DESC
           ) AS replay_rank
    FROM inv_movement m
    CROSS JOIN params p
    WHERE m.occurred_at < p.as_of_ts
),
balances AS (
    SELECT o.product_id, o.warehouse_id,
           o.opening_qty + COALESCE(SUM(r.quantity_delta)
               FILTER (WHERE r.replay_rank = 1), 0) AS closing_qty
    FROM inv_opening_balance o
    LEFT JOIN ranked r
      ON r.product_id = o.product_id
     AND r.warehouse_id = o.warehouse_id
    GROUP BY o.product_id, o.warehouse_id, o.opening_qty
)
SELECT b.product_id, b.warehouse_id, b.closing_qty, p.unit_cost,
       b.closing_qty * p.unit_cost AS inventory_value,
       CASE WHEN b.closing_qty < 0 THEN 'CONTROL_EXCEPTION'
            ELSE 'OK' END AS stock_status
FROM balances b
JOIN inv_product p USING (product_id)
ORDER BY inventory_value DESC;

-- ============================================================
-- PERFORMANCE NOTES
-- ============================================================
-- 1. For a persistent fact table, consider:
--    CREATE INDEX ON inventory_movement
--      (source_system, source_ref, ingested_at DESC, movement_id DESC);
--    CREATE INDEX ON inventory_movement
--      (product_id, warehouse_id, occurred_at, movement_id)
--      INCLUDE (quantity_delta, movement_type, source_system, source_ref);
-- 2. Partition large movement facts by occurred_at (monthly/weekly as justified)
--    and keep predicates half-open: occurred_at >= start AND occurred_at < end.
-- 3. Deduplicate at the ingestion boundary and persist canonical event identity;
--    repeatedly ranking the entire history is a teaching pattern, not an ideal
--    production architecture.
-- 4. Maintain periodic balance snapshots so historical roll-forwards scan only
--    the delta since the latest trusted snapshot.
-- 5. Validate every index with EXPLAIN (ANALYZE, BUFFERS) on representative data.
--    Tiny temporary tables may correctly use sequential scans.
-- 6. Business policy must define negative stock, returns, transfers, back-dated
--    corrections, unit-of-measure conversions, and count-adjustment approvals.
--
-- INTERVIEW FOLLOW-UPS
-- - How would you process a late movement after a daily snapshot was published?
-- - How would you model warehouse transfers without double-counting global stock?
-- - How would you make source-event ingestion idempotent under retries?
-- - When would you use a periodic snapshot fact versus a transaction fact?
