/*
===============================================================================
DAILY SQL PRACTICE — 2026-10-28
Topic: Inventory Ledger Reconciliation & Stock Movement Analytics
Dialect: PostgreSQL 14+
===============================================================================

HOW TO USE
1. Run this entire file in a PostgreSQL database.
2. Read each problem and attempt the query before uncommenting its solution.
3. The sample tables are prefixed with inv_ so they do not collide with other
   practice files in this repository.

BUSINESS SCENARIO
A retailer tracks receipts, shipments, and stock adjustments across warehouses.
The inventory ledger is the source of truth; periodic physical snapshots are
used to detect discrepancies.

SIGN CONVENTION
OPENING, RECEIPT, ADJUSTMENT_IN => positive quantity
SHIPMENT, ADJUSTMENT_OUT       => negative quantity

Performance notes are educational, not a promise that an index will help the
small sample dataset. Use EXPLAIN (ANALYZE, BUFFERS) on representative volumes.
===============================================================================
*/

DROP TABLE IF EXISTS inv_snapshots;
DROP TABLE IF EXISTS inv_movements;
DROP TABLE IF EXISTS inv_products;
DROP TABLE IF EXISTS inv_warehouses;

CREATE TABLE inv_warehouses (
    warehouse_id   INT PRIMARY KEY,
    warehouse_name TEXT NOT NULL
);

CREATE TABLE inv_products (
    product_id   INT PRIMARY KEY,
    sku          TEXT NOT NULL UNIQUE,
    product_name TEXT NOT NULL,
    category     TEXT NOT NULL
);

CREATE TABLE inv_movements (
    movement_id   BIGINT PRIMARY KEY,
    warehouse_id  INT NOT NULL REFERENCES inv_warehouses(warehouse_id),
    product_id    INT NOT NULL REFERENCES inv_products(product_id),
    movement_ts   TIMESTAMP NOT NULL,
    movement_type TEXT NOT NULL CHECK (
        movement_type IN (
            'OPENING', 'RECEIPT', 'SHIPMENT',
            'ADJUSTMENT_IN', 'ADJUSTMENT_OUT'
        )
    ),
    quantity      NUMERIC(12, 2) NOT NULL CHECK (quantity > 0),
    reference_no  TEXT NOT NULL
);

CREATE TABLE inv_snapshots (
    warehouse_id  INT NOT NULL REFERENCES inv_warehouses(warehouse_id),
    product_id    INT NOT NULL REFERENCES inv_products(product_id),
    snapshot_as_of TIMESTAMP NOT NULL,
    snapshot_qty  NUMERIC(12, 2) NOT NULL,
    PRIMARY KEY (warehouse_id, product_id, snapshot_as_of)
);

INSERT INTO inv_warehouses VALUES
    (1, 'Pune Central'),
    (2, 'Mumbai West'),
    (3, 'Nashik North');

INSERT INTO inv_products VALUES
    (101, 'SKU-101', 'Wireless Mouse', 'Accessories'),
    (102, 'SKU-102', 'Mechanical Keyboard', 'Accessories'),
    (103, 'SKU-103', 'USB-C Dock', 'Accessories'),
    (104, 'SKU-104', 'Laptop Stand', 'Office'),
    (105, 'SKU-105', 'Monitor 24 inch', 'Displays'),
    (106, 'SKU-106', 'Webcam HD', 'Accessories');

INSERT INTO inv_movements VALUES
-- movement_id, warehouse_id, product_id, timestamp, type, quantity, reference
(1001, 1, 101, '2026-10-25 08:00:00', 'OPENING',       50, 'OPEN-PUN-101'),
(1002, 1, 101, '2026-10-25 10:15:00', 'SHIPMENT',      12, 'ORD-5001'),
(1003, 1, 101, '2026-10-26 09:30:00', 'RECEIPT',       20, 'PO-7001'),
(1004, 1, 101, '2026-10-26 14:10:00', 'SHIPMENT',      18, 'ORD-5002'),
(1005, 1, 101, '2026-10-27 11:00:00', 'ADJUSTMENT_OUT', 2, 'COUNT-901'),
(1006, 1, 102, '2026-10-25 08:05:00', 'OPENING',       30, 'OPEN-PUN-102'),
(1007, 1, 102, '2026-10-26 13:00:00', 'SHIPMENT',      10, 'ORD-5010'),
(1008, 1, 102, '2026-10-27 16:00:00', 'RECEIPT',       15, 'PO-7010'),
(1009, 1, 103, '2026-10-25 08:10:00', 'OPENING',       10, 'OPEN-PUN-103'),
(1010, 1, 103, '2026-10-26 15:00:00', 'SHIPMENT',      13, 'ORD-5020'),
(1011, 1, 104, '2026-10-25 08:20:00', 'OPENING',       25, 'OPEN-PUN-104'),
(1012, 1, 104, '2026-10-27 10:00:00', 'RECEIPT',        5, 'PO-7040'),
(1013, 2, 101, '2026-10-25 08:00:00', 'OPENING',       40, 'OPEN-MUM-101'),
(1014, 2, 101, '2026-10-26 12:00:00', 'SHIPMENT',      16, 'ORD-5101'),
(1015, 2, 101, '2026-10-27 09:45:00', 'RECEIPT',       10, 'PO-7101'),
(1016, 2, 102, '2026-10-25 08:10:00', 'OPENING',       12, 'OPEN-MUM-102'),
(1017, 2, 102, '2026-10-27 15:30:00', 'SHIPMENT',      14, 'ORD-5110'),
(1018, 2, 105, '2026-10-25 08:30:00', 'OPENING',        8, 'OPEN-MUM-105'),
(1019, 2, 105, '2026-10-26 11:00:00', 'RECEIPT',        4, 'PO-7150'),
(1020, 3, 104, '2026-10-25 08:20:00', 'OPENING',       18, 'OPEN-NAS-104'),
(1021, 3, 104, '2026-10-26 10:20:00', 'SHIPMENT',       3, 'ORD-5204'),
(1022, 3, 106, '2026-10-26 09:00:00', 'OPENING',       20, 'OPEN-NAS-106'),
(1023, 3, 106, '2026-10-27 14:00:00', 'SHIPMENT',       6, 'ORD-5210'),
(1024, 1, 103, '2026-10-27 17:00:00', 'RECEIPT',        8, 'PO-7020');

INSERT INTO inv_snapshots VALUES
-- snapshot quantities reflect physical counts at the end of 2026-10-26
(1, 101, '2026-10-26 23:59:59', 40),
(1, 102, '2026-10-26 23:59:59', 20),
(1, 103, '2026-10-26 23:59:59', 10),
(1, 104, '2026-10-26 23:59:59', 25),
(2, 101, '2026-10-26 23:59:59', 24),
(2, 102, '2026-10-26 23:59:59', 12),
(2, 105, '2026-10-26 23:59:59', 12),
(3, 104, '2026-10-26 23:59:59', 15),
(3, 106, '2026-10-26 23:59:59', 14);

-- Candidate indexes: evaluate against production-like data, not this tiny seed.
CREATE INDEX idx_inv_movements_product_time
    ON inv_movements (warehouse_id, product_id, movement_ts, movement_id);

CREATE INDEX idx_inv_movements_shipments
    ON inv_movements (warehouse_id, product_id, movement_ts)
    WHERE movement_type = 'SHIPMENT';

ANALYZE inv_movements;

-- =============================================================================
-- Q01. Convert each movement to a signed quantity.
-- Return movement id, warehouse, product, timestamp, type, and signed quantity.
-- =============================================================================
-- SELECT movement_id, warehouse_id, product_id, movement_ts, movement_type,
--        CASE
--          WHEN movement_type IN ('OPENING', 'RECEIPT', 'ADJUSTMENT_IN')
--            THEN quantity
--          ELSE -quantity
--        END AS signed_quantity
-- FROM inv_movements
-- ORDER BY warehouse_id, product_id, movement_ts, movement_id;
--
-- Why: centralize the business sign convention so all downstream balances use
-- the same logic. In production, consider a generated/stored signed column or a
-- normalized ledger model if this expression is repeated across many queries.

-- =============================================================================
-- Q02. Calculate the running on-hand balance after every movement for each
-- warehouse/product pair. Make the ordering deterministic.
-- =============================================================================
-- WITH signed AS (
--   SELECT m.*,
--          CASE WHEN movement_type IN ('OPENING', 'RECEIPT', 'ADJUSTMENT_IN')
--               THEN quantity ELSE -quantity END AS signed_quantity
--   FROM inv_movements AS m
-- )
-- SELECT warehouse_id, product_id, movement_ts, movement_id, movement_type,
--        signed_quantity,
--        SUM(signed_quantity) OVER (
--          PARTITION BY warehouse_id, product_id
--          ORDER BY movement_ts, movement_id
--          ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
--        ) AS running_on_hand
-- FROM signed
-- ORDER BY warehouse_id, product_id, movement_ts, movement_id;
--
-- Optimization: the explicit ROWS frame avoids the peer-group behavior of the
-- default RANGE frame. movement_id breaks timestamp ties. The window still
-- requires ordering; the composite index may help some plans but does not
-- guarantee that a sort will be eliminated.

-- =============================================================================
-- Q03. Return the latest ledger balance per warehouse/product.
-- =============================================================================
-- WITH balances AS (
--   SELECT warehouse_id, product_id, movement_ts, movement_id,
--          SUM(CASE
--                WHEN movement_type IN ('OPENING', 'RECEIPT', 'ADJUSTMENT_IN')
--                  THEN quantity ELSE -quantity
--              END) OVER (
--                PARTITION BY warehouse_id, product_id
--                ORDER BY movement_ts, movement_id
--                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
--              ) AS on_hand,
--          ROW_NUMBER() OVER (
--            PARTITION BY warehouse_id, product_id
--            ORDER BY movement_ts DESC, movement_id DESC
--          ) AS rn
--   FROM inv_movements
-- )
-- SELECT warehouse_id, product_id, movement_ts AS last_movement_ts, on_hand
-- FROM balances
-- WHERE rn = 1
-- ORDER BY warehouse_id, product_id;
--
-- Optimization: calculate the balance and latest-row marker in one pass over
-- the base relation. The two window orderings may still require separate sorts.
-- For frequent dashboards, maintain a transactionally correct balance table
-- rather than recalculating the entire ledger on every request.

-- =============================================================================
-- Q04. Summarize daily receipts, shipments, adjustments, and net movement by
-- warehouse and product.
-- =============================================================================
-- SELECT warehouse_id, product_id, movement_ts::date AS movement_date,
--        SUM(quantity) FILTER (
--          WHERE movement_type IN ('OPENING', 'RECEIPT', 'ADJUSTMENT_IN')
--        ) AS positive_qty,
--        SUM(quantity) FILTER (WHERE movement_type = 'SHIPMENT') AS shipped_qty,
--        SUM(quantity) FILTER (
--          WHERE movement_type IN ('ADJUSTMENT_IN', 'ADJUSTMENT_OUT')
--        ) AS adjustment_units,
--        SUM(CASE
--              WHEN movement_type IN ('OPENING', 'RECEIPT', 'ADJUSTMENT_IN')
--                THEN quantity ELSE -quantity
--            END) AS net_movement
-- FROM inv_movements
-- GROUP BY warehouse_id, product_id, movement_ts::date
-- ORDER BY warehouse_id, product_id, movement_date;
--
-- Note: positive_qty includes opening balances; use a separate metric if the
-- business definition of "receipts" must exclude opening stock.

-- =============================================================================
-- Q05. Find every movement after which the running balance becomes negative.
-- =============================================================================
-- WITH ledger AS (
--   SELECT movement_id, warehouse_id, product_id, movement_ts, movement_type,
--          SUM(CASE
--                WHEN movement_type IN ('OPENING', 'RECEIPT', 'ADJUSTMENT_IN')
--                  THEN quantity ELSE -quantity
--              END) OVER (
--                PARTITION BY warehouse_id, product_id
--                ORDER BY movement_ts, movement_id
--                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
--              ) AS on_hand
--   FROM inv_movements
-- )
-- SELECT *
-- FROM ledger
-- WHERE on_hand < 0
-- ORDER BY warehouse_id, product_id, movement_ts, movement_id;
--
-- Why: checking only the final balance can hide a temporary stockout. A running
-- window identifies the exact transaction that first caused the breach.

-- =============================================================================
-- Q06. Find products that have never had a shipment in any warehouse.
-- =============================================================================
-- SELECT p.product_id, p.sku, p.product_name
-- FROM inv_products AS p
-- WHERE NOT EXISTS (
--   SELECT 1
--   FROM inv_movements AS m
--   WHERE m.product_id = p.product_id
--     AND m.movement_type = 'SHIPMENT'
-- )
-- ORDER BY p.product_id;
--
-- Optimization: NOT EXISTS expresses an anti-join and avoids duplicate product
-- rows that a regular join could produce. The partial shipment index is a
-- candidate for this predicate, though the planner may prefer a sequential scan
-- when the table is small.

-- =============================================================================
-- Q07. Reconcile the ledger balance at each snapshot timestamp against the
-- physical snapshot. Report only mismatches.
-- =============================================================================
-- WITH ledger_at_snapshot AS (
--   SELECT s.warehouse_id, s.product_id, s.snapshot_as_of, s.snapshot_qty,
--          COALESCE(SUM(
--            CASE
--              WHEN m.movement_type IN ('OPENING', 'RECEIPT', 'ADJUSTMENT_IN')
--                THEN m.quantity
--              ELSE -m.quantity
--            END
--          ), 0) AS ledger_qty
--   FROM inv_snapshots AS s
--   LEFT JOIN inv_movements AS m
--     ON m.warehouse_id = s.warehouse_id
--    AND m.product_id = s.product_id
--    AND m.movement_ts <= s.snapshot_as_of
--   GROUP BY s.warehouse_id, s.product_id, s.snapshot_as_of, s.snapshot_qty
-- )
-- SELECT *, ledger_qty - snapshot_qty AS variance
-- FROM ledger_at_snapshot
-- WHERE ledger_qty <> snapshot_qty
-- ORDER BY warehouse_id, product_id;
--
-- Optimization: restrict movement rows by warehouse, product, and timestamp
-- using the composite index candidate. For large snapshot histories, precompute
-- balances by snapshot date or process only changed product/warehouse pairs.
-- This assumes the ledger contains all movements since the opening entry.

-- =============================================================================
-- Q08. Find the top two products by shipped units in each warehouse.
-- Ties should share a rank, so a warehouse may return more than two rows.
-- =============================================================================
-- WITH shipped AS (
--   SELECT warehouse_id, product_id, SUM(quantity) AS shipped_units
--   FROM inv_movements
--   WHERE movement_type = 'SHIPMENT'
--   GROUP BY warehouse_id, product_id
-- ),
-- ranked AS (
--   SELECT s.*,
--          DENSE_RANK() OVER (
--            PARTITION BY warehouse_id
--            ORDER BY shipped_units DESC
--          ) AS shipment_rank
--   FROM shipped AS s
-- )
-- SELECT r.warehouse_id, w.warehouse_name, r.product_id, p.product_name,
--        r.shipped_units, r.shipment_rank
-- FROM ranked AS r
-- JOIN inv_warehouses AS w USING (warehouse_id)
-- JOIN inv_products AS p USING (product_id)
-- WHERE shipment_rank <= 2
-- ORDER BY r.warehouse_id, shipment_rank, r.product_id;
--
-- Optimization: filter to shipments before grouping and join descriptive
-- dimensions after aggregation to reduce rows flowing through the joins.

-- =============================================================================
-- Q09. Build a seven-calendar-day rolling shipment total per warehouse/product,
-- including dates with no shipments. Use the 2026-10-21 through 2026-10-28
-- reporting window.
-- =============================================================================
-- WITH daily AS (
--   SELECT warehouse_id, product_id, movement_ts::date AS movement_date,
--          SUM(quantity) AS shipped_units
--   FROM inv_movements
--   WHERE movement_type = 'SHIPMENT'
--     AND movement_ts >= TIMESTAMP '2026-10-21 00:00:00'
--     AND movement_ts <  TIMESTAMP '2026-10-29 00:00:00'
--   GROUP BY warehouse_id, product_id, movement_ts::date
-- ),
-- active_pairs AS (
--   SELECT DISTINCT warehouse_id, product_id
--   FROM inv_movements
-- ),
-- calendar AS (
--   SELECT d::date AS movement_date
--   FROM generate_series(
--     DATE '2026-10-21', DATE '2026-10-28', INTERVAL '1 day'
--   ) AS g(d)
-- ),
-- dense_daily AS (
--   SELECT a.warehouse_id, a.product_id, c.movement_date,
--          COALESCE(d.shipped_units, 0) AS shipped_units
--   FROM active_pairs AS a
--   CROSS JOIN calendar AS c
--   LEFT JOIN daily AS d
--     ON d.warehouse_id = a.warehouse_id
--    AND d.product_id = a.product_id
--    AND d.movement_date = c.movement_date
-- ),
-- rolling AS (
--   SELECT *,
--          SUM(shipped_units) OVER (
--            PARTITION BY warehouse_id, product_id
--            ORDER BY movement_date
--            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
--          ) AS shipped_units_7d
--   FROM dense_daily
-- )
-- SELECT *
-- FROM rolling
-- WHERE movement_date >= DATE '2026-10-25'
-- ORDER BY warehouse_id, product_id, movement_date;
--
-- Important: ROWS BETWEEN 6 PRECEDING AND CURRENT ROW represents seven days
-- only because the calendar is dense (one row per calendar day and pair).
-- The half-open timestamp filter is index-friendly; filtering on
-- movement_ts::date would generally prevent a plain timestamp index from
-- being used as a range condition.

-- =============================================================================
-- Q10. Return shipment quantities in a user-supplied time range using a
-- SARGable timestamp predicate.
-- =============================================================================
-- SELECT warehouse_id, product_id, SUM(quantity) AS shipped_units
-- FROM inv_movements
-- WHERE movement_type = 'SHIPMENT'
--   AND movement_ts >= TIMESTAMP '2026-10-25 00:00:00'
--   AND movement_ts <  TIMESTAMP '2026-10-28 00:00:00'
-- GROUP BY warehouse_id, product_id
-- ORDER BY warehouse_id, shipped_units DESC;
--
-- Prefer this half-open range to WHERE movement_ts::date BETWEEN ...:
-- it includes the full final day when the upper bound is next midnight and
-- keeps the indexed column unwrapped by a function.

-- =============================================================================
-- Q11. Compare total signed ledger quantity with the latest on-hand balance
-- computed from the running ledger; explain why opening rows matter.
-- =============================================================================
-- WITH signed AS (
--   SELECT warehouse_id, product_id,
--          CASE WHEN movement_type IN ('OPENING', 'RECEIPT', 'ADJUSTMENT_IN')
--               THEN quantity ELSE -quantity END AS signed_qty
--   FROM inv_movements
-- ),
-- totals AS (
--   SELECT warehouse_id, product_id, SUM(signed_qty) AS total_signed_qty
--   FROM signed
--   GROUP BY warehouse_id, product_id
-- ),
-- latest AS (
--   SELECT warehouse_id, product_id, on_hand
--   FROM (
--     SELECT warehouse_id, product_id,
--            SUM(signed_qty) OVER (
--              PARTITION BY warehouse_id, product_id
--              ORDER BY movement_ts, movement_id
--              ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
--            ) AS on_hand,
--            ROW_NUMBER() OVER (
--              PARTITION BY warehouse_id, product_id
--              ORDER BY movement_ts DESC, movement_id DESC
--            ) AS rn
--     FROM (
--       SELECT warehouse_id, product_id, movement_ts, movement_id,
--              CASE WHEN movement_type IN ('OPENING', 'RECEIPT', 'ADJUSTMENT_IN')
--                   THEN quantity ELSE -quantity END AS signed_qty
--       FROM inv_movements
--     ) AS x
--   ) AS y
--   WHERE rn = 1
-- )
-- SELECT t.warehouse_id, t.product_id, t.total_signed_qty, l.on_hand,
--        t.total_signed_qty - l.on_hand AS difference
-- FROM totals AS t
-- JOIN latest AS l USING (warehouse_id, product_id)
-- WHERE t.total_signed_qty <> l.on_hand;
--
-- Expected result: no rows. Both calculations use the same signed movement
-- ledger; opening entries establish the starting quantity and must be included.

-- =============================================================================
-- Q12. Performance investigation exercise.
-- Compare a date-cast filter against a half-open range on a large copy of the
-- movement table. Capture actual rows, buffers, and execution time.
-- =============================================================================
-- EXPLAIN (ANALYZE, BUFFERS)
-- SELECT *
-- FROM inv_movements
-- WHERE movement_ts::date = DATE '2026-10-27';
--
-- EXPLAIN (ANALYZE, BUFFERS)
-- SELECT *
-- FROM inv_movements
-- WHERE movement_ts >= TIMESTAMP '2026-10-27 00:00:00'
--   AND movement_ts <  TIMESTAMP '2026-10-28 00:00:00';
--
-- Interview discussion:
-- * Why can the second predicate use a regular B-tree timestamp index more
--   directly?
-- * Why might PostgreSQL still choose a sequential scan?
-- * How would table size, selectivity, statistics, and cache state affect the
--   plan?
-- * What is the difference between an index scan and a bitmap heap scan?

-- =============================================================================
-- PERFORMANCE CHECKLIST
-- 1. Always make window ordering deterministic with a unique tie-breaker.
-- 2. Filter early when it reduces input without changing semantics.
-- 3. Aggregate before joining dimensions when detail columns are not required.
-- 4. Keep timestamp predicates half-open and avoid casting the indexed column.
-- 5. Use NOT EXISTS for anti-join intent; validate NULL behavior.
-- 6. Indexes add write/storage costs. Validate with EXPLAIN (ANALYZE, BUFFERS).
-- 7. For high-volume ledgers, consider incremental balance snapshots, partitioning
--    by a suitable date key, and late-arriving/correcting-event handling.
-- 8. Do not confuse physical stock snapshots with ledger-derived quantities:
--    document the snapshot cutoff and reconciliation rules.
--
-- EXPECTED SPOT CHECKS FROM THE SEEDED DATA
-- * Warehouse 1 / product 101 running balance ends at 38.
-- * Warehouse 1 / product 103 ends at 5 (10 - 13 + 8).
-- * Q05 should identify warehouse 1 / product 103 as negative after movement
--   1010, before the later receipt.
-- * Q07 should report any physical snapshot quantities that differ from the
--   ledger quantity at the stated cutoff.
--
-- INTERVIEW FOLLOW-UPS
-- 1. How would you process late-arriving stock movements without double-counting?
-- 2. How would you make the ledger append-only and audit-friendly?
-- 3. When would a materialized view or incremental aggregate be appropriate?
-- 4. How would you handle concurrent updates to a stock balance?
-- 5. What would change if movements arrive as a Spark stream?
===============================================================================
