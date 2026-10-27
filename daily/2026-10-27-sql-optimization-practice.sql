-- SQL PLAYGROUND | DAILY PRACTICE | 2026-10-27
-- Topic: SQL problem-solving with optimized solutions
-- Dialect: PostgreSQL
--
-- HOW TO USE
-- 1. Run this file in PostgreSQL. It creates isolated daily-practice tables.
-- 2. Try each problem before looking at the solution.
-- 3. Compare the baseline approach with the optimized approach and review the notes.
-- 4. Use EXPLAIN (ANALYZE, BUFFERS) to compare plans on larger datasets.
--
-- Optimization reminder:
-- A query is not automatically faster just because it is shorter or uses a CTE.
-- Verify indexes, cardinality, query plans, and correctness against your data.

-- =========================================================
-- 1. SETUP AND SAMPLE DATA
-- =========================================================

DROP TABLE IF EXISTS daily_orders_20261027;
DROP TABLE IF EXISTS daily_customers_20261027;

CREATE TABLE daily_customers_20261027 (
    customer_id   INT PRIMARY KEY,
    customer_name VARCHAR(100) NOT NULL,
    city          VARCHAR(50) NOT NULL
);

CREATE TABLE daily_orders_20261027 (
    order_id       BIGINT PRIMARY KEY,
    customer_id    INT NOT NULL,
    order_date     DATE NOT NULL,
    order_status   VARCHAR(20) NOT NULL,
    amount         NUMERIC(12,2) NOT NULL CHECK (amount >= 0),
    updated_at     TIMESTAMP NOT NULL
);

INSERT INTO daily_customers_20261027 VALUES
(1, 'Aarav Shah', 'Pune'),
(2, 'Meera Patil', 'Mumbai'),
(3, 'Rohan Kulkarni', 'Pune'),
(4, 'Sara Khan', 'Nashik'),
(5, 'Dev Joshi', 'Mumbai'),
(6, 'Anaya Desai', 'Nagpur');

INSERT INTO daily_orders_20261027 VALUES
(2001, 1, '2026-10-01', 'COMPLETED', 1200.00, '2026-10-01 10:00:00'),
(2002, 1, '2026-10-02', 'CANCELLED',  700.00, '2026-10-02 11:00:00'),
(2003, 2, '2026-10-02', 'COMPLETED', 3500.00, '2026-10-02 12:00:00'),
(2004, 3, '2026-10-03', 'COMPLETED', 2200.00, '2026-10-03 09:00:00'),
(2005, 2, '2026-10-05', 'PENDING',   1600.00, '2026-10-05 14:00:00'),
(2006, 4, '2026-10-06', 'COMPLETED', 4800.00, '2026-10-06 15:00:00'),
(2007, 1, '2026-10-07', 'COMPLETED',  900.00, '2026-10-07 16:00:00'),
(2008, 5, '2026-10-07', 'COMPLETED', 3100.00, '2026-10-07 17:00:00'),
(2009, 3, '2026-10-08', 'CANCELLED', 5000.00, '2026-10-08 18:00:00'),
(2010, 6, '2026-10-09', 'COMPLETED', 2700.00, '2026-10-09 19:00:00'),
(2011, 4, '2026-10-10', 'COMPLETED', 1800.00, '2026-10-10 20:00:00'),
(2012, 2, '2026-10-11', 'COMPLETED', 2400.00, '2026-10-11 21:00:00');

-- Optional indexes to test after exploring the questions.
-- CREATE INDEX idx_daily_orders_status_date
--     ON daily_orders_20261027 (order_status, order_date);
-- CREATE INDEX idx_daily_orders_customer_status
--     ON daily_orders_20261027 (customer_id, order_status);
-- For this tiny sample dataset, PostgreSQL may correctly choose sequential scans.
-- Index benefits usually become visible with larger tables and selective filters.

-- =========================================================
-- 2. PROBLEMS — TRY BEFORE READING SOLUTIONS
-- =========================================================

-- Q01 | Filtering
-- Return completed orders placed between 2026-10-05 and 2026-10-10 inclusive.
--
-- Q02 | Aggregation
-- Calculate completed-order revenue for every customer, including customers with zero.
--
-- Q03 | Top-N per group
-- Return the two highest-revenue customers in each city. Revenue is based on completed orders.
--
-- Q04 | Anti-join
-- Find customers who have never placed a completed order.
--
-- Q05 | Window function
-- For every completed order, show the customer's order amount and cumulative completed revenue
-- ordered by date.
--
-- Q06 | Optimization / SARGability
-- Filter orders for October 2026. Avoid applying a date function to the order_date column.
--
-- Q07 | EXISTS
-- Find customers with at least one completed order above 2,000.
--
-- Q08 | Conditional aggregation
-- Return one row per customer with completed, cancelled, and pending order counts.
--
-- Q09 | Latest record
-- Return the most recent order for each customer, regardless of status.
--
-- Q10 | Query review
-- Find the flaw in this query and replace it with a correct, efficient version:
-- SELECT c.customer_id, c.customer_name, SUM(o.amount) AS revenue
-- FROM daily_customers_20261027 c
-- LEFT JOIN daily_orders_20261027 o ON o.customer_id = c.customer_id
-- WHERE o.order_status = 'COMPLETED'
-- GROUP BY c.customer_id, c.customer_name;
-- Requirement: customers with zero completed orders must remain in the output.

-- =========================================================
-- 3. SOLUTIONS AND OPTIMIZATION NOTES
-- =========================================================

-- A01 | Straightforward, index-friendly date range.
-- SELECT order_id, customer_id, order_date, amount
-- FROM daily_orders_20261027
-- WHERE order_status = 'COMPLETED'
--   AND order_date >= DATE '2026-10-05'
--   AND order_date <  DATE '2026-10-11'
-- ORDER BY order_date, order_id;
-- Optimization note: a half-open range also works for timestamps and avoids missing
-- rows with times later in the final day. The filter can use a suitable composite index.

-- A02 | LEFT JOIN preserves customers with no completed orders.
-- SELECT c.customer_id, c.customer_name,
--        COALESCE(SUM(o.amount), 0) AS completed_revenue
-- FROM daily_customers_20261027 c
-- LEFT JOIN daily_orders_20261027 o
--   ON o.customer_id = c.customer_id
--  AND o.order_status = 'COMPLETED'
-- GROUP BY c.customer_id, c.customer_name
-- ORDER BY completed_revenue DESC, c.customer_id;
-- Optimization note: keep the order-status predicate in ON, not WHERE, or the LEFT JOIN
-- behaves like an inner join for that condition. The customer_id/status index may help
-- when the production table is large and the filter is selective.

-- A03 | Aggregate first, then rank the much smaller customer result.
-- WITH customer_revenue AS (
--   SELECT c.customer_id, c.customer_name, c.city,
--          COALESCE(SUM(o.amount), 0) AS revenue
--   FROM daily_customers_20261027 c
--   LEFT JOIN daily_orders_20261027 o
--     ON o.customer_id = c.customer_id
--    AND o.order_status = 'COMPLETED'
--   GROUP BY c.customer_id, c.customer_name, c.city
-- ),
-- ranked AS (
--   SELECT *, ROW_NUMBER() OVER (
--     PARTITION BY city ORDER BY revenue DESC, customer_id
--   ) AS rn
--   FROM customer_revenue
-- )
-- SELECT customer_id, customer_name, city, revenue
-- FROM ranked
-- WHERE rn <= 2
-- ORDER BY city, revenue DESC;
-- Optimization note: ROW_NUMBER returns exactly two rows per city when available.
-- Use RANK instead if ties at the cutoff should all be returned.

-- A04 | NOT EXISTS is a clear anti-join and avoids duplicate customer rows.
-- SELECT c.customer_id, c.customer_name
-- FROM daily_customers_20261027 c
-- WHERE NOT EXISTS (
--   SELECT 1
--   FROM daily_orders_20261027 o
--   WHERE o.customer_id = c.customer_id
--     AND o.order_status = 'COMPLETED'
-- )
-- ORDER BY c.customer_id;
-- Optimization note: an index beginning with (customer_id, order_status) can support
-- the existence check. PostgreSQL may implement this as an anti-join.

-- A05 | Explicit ROWS frame makes cumulative behavior deterministic.
-- SELECT order_id, customer_id, order_date, amount,
--        SUM(amount) OVER (
--          PARTITION BY customer_id
--          ORDER BY order_date, order_id
--          ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
--        ) AS cumulative_completed_revenue
-- FROM daily_orders_20261027
-- WHERE order_status = 'COMPLETED'
-- ORDER BY customer_id, order_date, order_id;
-- Optimization note: the unique order_id tie-breaker makes ordering stable when dates match.

-- A06 | SARGable date filter.
-- SELECT order_id, order_date, amount
-- FROM daily_orders_20261027
-- WHERE order_date >= DATE '2026-10-01'
--   AND order_date <  DATE '2026-11-01'
-- ORDER BY order_date;
-- Avoid: WHERE DATE_TRUNC('month', order_date) = TIMESTAMP '2026-10-01 00:00:00'
-- because wrapping the column in a function can prevent use of a regular index on order_date.
-- A matching expression index can change that, but a range predicate is often simpler.

-- A07 | EXISTS stops needing to return every matching order.
-- SELECT c.customer_id, c.customer_name
-- FROM daily_customers_20261027 c
-- WHERE EXISTS (
--   SELECT 1
--   FROM daily_orders_20261027 o
--   WHERE o.customer_id = c.customer_id
--     AND o.order_status = 'COMPLETED'
--     AND o.amount > 2000
-- )
-- ORDER BY c.customer_id;

-- A08 | Conditional aggregation scans the order rows once for all three metrics.
-- SELECT c.customer_id, c.customer_name,
--        COUNT(*) FILTER (WHERE o.order_status = 'COMPLETED') AS completed_count,
--        COUNT(*) FILTER (WHERE o.order_status = 'CANCELLED') AS cancelled_count,
--        COUNT(*) FILTER (WHERE o.order_status = 'PENDING') AS pending_count
-- FROM daily_customers_20261027 c
-- LEFT JOIN daily_orders_20261027 o ON o.customer_id = c.customer_id
-- GROUP BY c.customer_id, c.customer_name
-- ORDER BY c.customer_id;
-- Note: COUNT(*) counts the null-extended LEFT JOIN row. To avoid counting it as a status,
-- FILTER conditions above work because NULL does not match any listed status.
-- Portable alternative: SUM(CASE WHEN o.order_status = 'COMPLETED' THEN 1 ELSE 0 END).

-- A09 | Window ranking is portable and returns all columns from the chosen latest row.
-- WITH ranked AS (
--   SELECT o.*,
--          ROW_NUMBER() OVER (
--            PARTITION BY customer_id ORDER BY order_date DESC, updated_at DESC, order_id DESC
--          ) AS rn
--   FROM daily_orders_20261027 o
-- )
-- SELECT order_id, customer_id, order_date, order_status, amount
-- FROM ranked
-- WHERE rn = 1
-- ORDER BY customer_id;
-- PostgreSQL alternative: DISTINCT ON (customer_id) with matching ORDER BY can be concise;
-- benchmark both on the real data and indexes before choosing.

-- A10 | Corrected query: keep the status condition in the LEFT JOIN.
-- SELECT c.customer_id, c.customer_name,
--        COALESCE(SUM(o.amount), 0) AS revenue
-- FROM daily_customers_20261027 c
-- LEFT JOIN daily_orders_20261027 o
--   ON o.customer_id = c.customer_id
--  AND o.order_status = 'COMPLETED'
-- GROUP BY c.customer_id, c.customer_name
-- ORDER BY revenue DESC, c.customer_id;
-- Why: filtering o.order_status in WHERE removes NULL-extended rows and drops customers
-- with no completed orders. This fix preserves them and reports zero instead of NULL.

-- =========================================================
-- 4. PERFORMANCE CHECKLIST
-- =========================================================
-- 1. Start with EXPLAIN (ANALYZE, BUFFERS) SELECT ...;
-- 2. Compare estimated rows with actual rows; large differences can indicate stale statistics.
-- 3. Avoid SELECT * in production-facing queries when only a few columns are needed.
-- 4. Filter early when it reduces the amount of data processed without changing semantics.
-- 5. Index join keys and common filter combinations only when workload justifies the cost.
-- 6. Indexes increase storage and write overhead; do not add every possible index.
-- 7. Use half-open timestamp ranges (>= start AND < next_period_start) for reliable boundaries.
-- 8. Validate result correctness before comparing speed.
-- 9. Run ANALYZE after loading representative data if query plans look unexpected.
-- 10. Small sample tables are for learning; they are too small to prove index performance.

-- END OF DAILY PRACTICE: 2026-10-27
