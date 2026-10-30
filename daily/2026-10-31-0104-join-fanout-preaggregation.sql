-- =============================================================================
-- Topic: Join Fanout Prevention with Pre-Aggregated Fact Tables
-- Dialect: PostgreSQL 14+
-- Run this file independently. All objects use the jfp_ prefix.
--
-- Scenario:
-- An order can have many lines, payments, and shipments. Joining all three
-- one-to-many tables before aggregation multiplies rows and inflates sums.
-- The reliable pattern is to aggregate each child to one row per order first.
-- =============================================================================

DROP TABLE IF EXISTS jfp_shipments;
DROP TABLE IF EXISTS jfp_payments;
DROP TABLE IF EXISTS jfp_order_lines;
DROP TABLE IF EXISTS jfp_orders;
DROP TABLE IF EXISTS jfp_customers;

CREATE TABLE jfp_customers (
    customer_id   BIGINT PRIMARY KEY,
    customer_name TEXT NOT NULL,
    region        TEXT NOT NULL
);

CREATE TABLE jfp_orders (
    order_id     BIGINT PRIMARY KEY,
    customer_id  BIGINT NOT NULL REFERENCES jfp_customers(customer_id),
    order_ts     TIMESTAMP NOT NULL,
    order_status TEXT NOT NULL
);

CREATE TABLE jfp_order_lines (
    line_id    BIGINT PRIMARY KEY,
    order_id   BIGINT NOT NULL REFERENCES jfp_orders(order_id),
    sku        TEXT NOT NULL,
    quantity   INTEGER NOT NULL CHECK (quantity > 0),
    unit_price NUMERIC(12, 2) NOT NULL CHECK (unit_price >= 0)
);

CREATE TABLE jfp_payments (
    payment_id BIGINT PRIMARY KEY,
    order_id   BIGINT NOT NULL REFERENCES jfp_orders(order_id),
    payment_ts TIMESTAMP NOT NULL,
    amount     NUMERIC(12, 2) NOT NULL CHECK (amount >= 0),
    status     TEXT NOT NULL
);

CREATE TABLE jfp_shipments (
    shipment_id BIGINT PRIMARY KEY,
    order_id    BIGINT NOT NULL REFERENCES jfp_orders(order_id),
    shipped_at  TIMESTAMP NOT NULL,
    freight_cost NUMERIC(12, 2) NOT NULL CHECK (freight_cost >= 0)
);

INSERT INTO jfp_customers VALUES
    (1, 'Asha Kulkarni', 'West'),
    (2, 'Rahul Mehta', 'North'),
    (3, 'Neha Patil', 'South');

INSERT INTO jfp_orders VALUES
    (1001, 1, '2026-10-01 10:15:00', 'completed'),
    (1002, 1, '2026-10-02 11:30:00', 'completed'),
    (1003, 2, '2026-10-02 14:00:00', 'completed'),
    (1004, 3, '2026-10-03 09:00:00', 'cancelled');

INSERT INTO jfp_order_lines VALUES
    (1, 1001, 'SKU-A', 2, 100.00),
    (2, 1001, 'SKU-B', 1,  50.00),
    (3, 1002, 'SKU-C', 1,  80.00),
    (4, 1002, 'SKU-D', 3,  20.00),
    (5, 1003, 'SKU-E', 2,  40.00),
    (6, 1004, 'SKU-F', 1, 500.00);

INSERT INTO jfp_payments VALUES
    (5001, 1001, '2026-10-01 10:20:00', 150.00, 'captured'),
    (5002, 1001, '2026-10-01 10:25:00',  50.00, 'captured'),
    (5003, 1002, '2026-10-02 11:40:00', 140.00, 'captured'),
    (5004, 1003, '2026-10-02 14:10:00',  80.00, 'pending'),
    (5005, 1004, '2026-10-03 09:05:00', 500.00, 'captured');

INSERT INTO jfp_shipments VALUES
    (7001, 1001, '2026-10-01 16:00:00', 12.50),
    (7002, 1001, '2026-10-02 08:00:00',  8.00),
    (7003, 1002, '2026-10-03 12:00:00', 10.00),
    (7004, 1003, '2026-10-04 15:00:00',  7.50);

-- -----------------------------------------------------------------------------
-- Q1. Prove the fanout.
-- For order 1001 there are 2 lines x 2 captured payments x 2 shipments.
-- Run the query and compare joined_rows with the source child-table counts.
-- -----------------------------------------------------------------------------

SELECT
    o.order_id,
    COUNT(*) AS joined_rows,
    COUNT(DISTINCT ol.line_id) AS distinct_lines,
    COUNT(DISTINCT p.payment_id) AS distinct_captured_payments,
    COUNT(DISTINCT s.shipment_id) AS distinct_shipments,
    SUM(ol.quantity * ol.unit_price) AS WRONG_line_revenue,
    SUM(p.amount) AS WRONG_captured_amount,
    SUM(s.freight_cost) AS WRONG_freight_cost
FROM jfp_orders o
JOIN jfp_order_lines ol ON ol.order_id = o.order_id
JOIN jfp_payments p
  ON p.order_id = o.order_id
 AND p.status = 'captured'
JOIN jfp_shipments s ON s.order_id = o.order_id
WHERE o.order_id = 1001
GROUP BY o.order_id;

-- Expected for order 1001: joined_rows = 8, distinct counts = 2 each.
-- Correct values are line revenue 250.00, captured amount 200.00,
-- and freight cost 20.50. The naive sums above are multiplied by four.

-- -----------------------------------------------------------------------------
-- Q2. Build one order-level row by aggregating each child independently.
-- Optimized pattern: each CTE returns at most one row per order_id.
-- -----------------------------------------------------------------------------

WITH line_metrics AS (
    SELECT
        order_id,
        COUNT(*) AS line_count,
        SUM(quantity * unit_price) AS merchandise_amount
    FROM jfp_order_lines
    GROUP BY order_id
),
payment_metrics AS (
    SELECT
        order_id,
        COUNT(*) FILTER (WHERE status = 'captured') AS captured_payment_count,
        SUM(amount) FILTER (WHERE status = 'captured') AS captured_amount
    FROM jfp_payments
    GROUP BY order_id
),
shipment_metrics AS (
    SELECT
        order_id,
        COUNT(*) AS shipment_count,
        SUM(freight_cost) AS freight_cost
    FROM jfp_shipments
    GROUP BY order_id
)
SELECT
    o.order_id,
    o.customer_id,
    o.order_status,
    COALESCE(l.line_count, 0) AS line_count,
    COALESCE(l.merchandise_amount, 0)::NUMERIC(12, 2) AS merchandise_amount,
    COALESCE(p.captured_payment_count, 0) AS captured_payment_count,
    COALESCE(p.captured_amount, 0)::NUMERIC(12, 2) AS captured_amount,
    COALESCE(s.shipment_count, 0) AS shipment_count,
    COALESCE(s.freight_cost, 0)::NUMERIC(12, 2) AS freight_cost
FROM jfp_orders o
LEFT JOIN line_metrics l ON l.order_id = o.order_id
LEFT JOIN payment_metrics p ON p.order_id = o.order_id
LEFT JOIN shipment_metrics s ON s.order_id = o.order_id
ORDER BY o.order_id;

-- Optimization explanation:
-- * Each many-side table is reduced to order grain before it is joined.
-- * LEFT JOIN preserves orders with no lines, payments, or shipments.
-- * FILTER keeps payment status logic inside its own aggregate.
-- * COALESCE gives stable zero values for missing child records.

-- -----------------------------------------------------------------------------
-- Q3. Produce a customer-level completed-order summary without fanout.
-- The order_fact CTE is guaranteed to contain one row per order.
-- -----------------------------------------------------------------------------

WITH line_metrics AS (
    SELECT order_id, SUM(quantity * unit_price) AS merchandise_amount
    FROM jfp_order_lines
    GROUP BY order_id
),
payment_metrics AS (
    SELECT
        order_id,
        SUM(amount) FILTER (WHERE status = 'captured') AS captured_amount
    FROM jfp_payments
    GROUP BY order_id
),
shipment_metrics AS (
    SELECT order_id, SUM(freight_cost) AS freight_cost
    FROM jfp_shipments
    GROUP BY order_id
),
order_fact AS (
    SELECT
        o.order_id,
        o.customer_id,
        COALESCE(l.merchandise_amount, 0) AS merchandise_amount,
        COALESCE(p.captured_amount, 0) AS captured_amount,
        COALESCE(s.freight_cost, 0) AS freight_cost
    FROM jfp_orders o
    LEFT JOIN line_metrics l ON l.order_id = o.order_id
    LEFT JOIN payment_metrics p ON p.order_id = o.order_id
    LEFT JOIN shipment_metrics s ON s.order_id = o.order_id
    WHERE o.order_status = 'completed'
)
SELECT
    c.customer_id,
    c.customer_name,
    COUNT(f.order_id) AS completed_orders,
    SUM(f.merchandise_amount) AS merchandise_revenue,
    SUM(f.captured_amount) AS captured_cash,
    SUM(f.freight_cost) AS freight_cost
FROM jfp_customers c
LEFT JOIN order_fact f ON f.customer_id = c.customer_id
GROUP BY c.customer_id, c.customer_name
ORDER BY merchandise_revenue DESC NULLS LAST;

-- -----------------------------------------------------------------------------
-- Q4. Find child records that do not resolve to a parent order.
-- The declared foreign keys prevent these examples, but the anti-join pattern
-- is useful when validating raw landing/staging tables before constraints exist.
-- -----------------------------------------------------------------------------

SELECT 'order_line' AS source_name, ol.line_id::TEXT AS source_key
FROM jfp_order_lines ol
WHERE NOT EXISTS (
    SELECT 1
    FROM jfp_orders o
    WHERE o.order_id = ol.order_id
)
UNION ALL
SELECT 'payment', p.payment_id::TEXT
FROM jfp_payments p
WHERE NOT EXISTS (
    SELECT 1
    FROM jfp_orders o
    WHERE o.order_id = p.order_id
)
UNION ALL
SELECT 'shipment', s.shipment_id::TEXT
FROM jfp_shipments s
WHERE NOT EXISTS (
    SELECT 1
    FROM jfp_orders o
    WHERE o.order_id = s.order_id
);

-- -----------------------------------------------------------------------------
-- Q5. Reconcile completed-order merchandise value against captured payments.
-- This flags underpayment, overpayment, and missing captured payments.
-- -----------------------------------------------------------------------------

WITH order_amounts AS (
    SELECT order_id, SUM(quantity * unit_price) AS merchandise_amount
    FROM jfp_order_lines
    GROUP BY order_id
),
captured AS (
    SELECT order_id, SUM(amount) AS captured_amount
    FROM jfp_payments
    WHERE status = 'captured'
    GROUP BY order_id
)
SELECT
    o.order_id,
    COALESCE(a.merchandise_amount, 0) AS merchandise_amount,
    COALESCE(c.captured_amount, 0) AS captured_amount,
    COALESCE(c.captured_amount, 0)
      - COALESCE(a.merchandise_amount, 0) AS payment_variance,
    CASE
        WHEN COALESCE(c.captured_amount, 0) = 0 THEN 'NO_CAPTURE'
        WHEN COALESCE(c.captured_amount, 0) < COALESCE(a.merchandise_amount, 0)
            THEN 'UNDERPAID'
        WHEN COALESCE(c.captured_amount, 0) > COALESCE(a.merchandise_amount, 0)
            THEN 'OVERPAID'
        ELSE 'MATCHED'
    END AS reconciliation_status
FROM jfp_orders o
LEFT JOIN order_amounts a ON a.order_id = o.order_id
LEFT JOIN captured c ON c.order_id = o.order_id
WHERE o.order_status = 'completed'
ORDER BY o.order_id;

-- Expected: order 1001 UNDERPAID (200 vs 250), order 1002 MATCHED (140 vs 140),
-- and order 1003 NO_CAPTURE (pending payment is intentionally excluded).

-- -----------------------------------------------------------------------------
-- Q6. Rank customers by completed merchandise revenue.
-- Aggregate to customer grain before ranking; do not rank raw order-line rows.
-- -----------------------------------------------------------------------------

WITH customer_revenue AS (
    SELECT
        o.customer_id,
        SUM(ol.quantity * ol.unit_price) AS revenue
    FROM jfp_orders o
    JOIN jfp_order_lines ol ON ol.order_id = o.order_id
    WHERE o.order_status = 'completed'
    GROUP BY o.customer_id
)
SELECT
    c.customer_id,
    c.customer_name,
    cr.revenue,
    DENSE_RANK() OVER (ORDER BY cr.revenue DESC) AS revenue_rank
FROM customer_revenue cr
JOIN jfp_customers c ON c.customer_id = cr.customer_id
ORDER BY revenue_rank, c.customer_id;

-- -----------------------------------------------------------------------------
-- Q7. Performance investigation and candidate indexes.
-- Run EXPLAIN (ANALYZE, BUFFERS) before and after adding indexes using realistic
-- row volumes. The tiny sample is for correctness, not index benchmarking.
-- -----------------------------------------------------------------------------

-- CREATE INDEX jfp_orders_status_customer_idx
--     ON jfp_orders (order_status, customer_id);
--
-- CREATE INDEX jfp_order_lines_order_idx
--     ON jfp_order_lines (order_id) INCLUDE (quantity, unit_price);
--
-- CREATE INDEX jfp_payments_captured_order_idx
--     ON jfp_payments (order_id) INCLUDE (amount)
--     WHERE status = 'captured';
--
-- CREATE INDEX jfp_shipments_order_idx
--     ON jfp_shipments (order_id) INCLUDE (freight_cost);
--
-- EXPLAIN (ANALYZE, BUFFERS)
-- WITH line_metrics AS (
--     SELECT order_id, SUM(quantity * unit_price) AS merchandise_amount
--     FROM jfp_order_lines
--     GROUP BY order_id
-- )
-- SELECT * FROM line_metrics WHERE order_id BETWEEN 1000 AND 2000;

-- Performance notes:
-- 1. Establish the grain of every input before joining multiple one-to-many facts.
-- 2. Aggregate only the columns needed by the next stage; avoid SELECT *.
-- 3. A partial index can help captured-payment lookups when that status is selective.
-- 4. For very large facts, consider date partitioning and partition pruning.
-- 5. Compare estimated versus actual rows to spot cardinality errors and fanout.
-- 6. Do not assume a CTE is always materialized; PostgreSQL may inline eligible CTEs.
-- 7. For repeated reporting, persist a tested order-grain fact table or materialized
--    view and define its refresh/reconciliation strategy explicitly.

-- Interview follow-ups:
-- * How would you handle refunds and chargebacks without double-counting cash?
-- * What if payments arrive before the order record in a raw ingestion layer?
-- * How would you validate that an order-grain fact remains unique by order_id?
-- * When would you use a materialized view instead of recomputing these aggregates?
