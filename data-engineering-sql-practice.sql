-- SQL PLAYGROUND: DATA ENGINEERING SQL PRACTICE
-- Dialect: PostgreSQL
-- Prerequisite: Run this file from top to bottom. It creates its own tables and sample data.
-- Learning goals: deduplication, incremental loads, data quality, SCD Type 2 concepts,
-- late-arriving data, reconciliation, NULL handling, and window functions.
--
-- PRACTICE METHOD
-- 1. Run sections 1-2 to create tables and insert sample data.
-- 2. Attempt Q01-Q20 without uncommenting the answer key.
-- 3. Check the commented solutions at the end.
-- 4. Inspect edge cases such as duplicate events, NULL values, and failed records.

-- =========================================================
-- 1. SETUP
-- =========================================================

DROP TABLE IF EXISTS de_orders;
DROP TABLE IF EXISTS de_customers;
DROP TABLE IF EXISTS de_pipeline_runs;

CREATE TABLE de_customers (
    customer_id   INT NOT NULL,
    customer_name VARCHAR(100),
    email         VARCHAR(150),
    city          VARCHAR(80),
    updated_at    TIMESTAMP NOT NULL,
    source_system VARCHAR(30) NOT NULL
);

CREATE TABLE de_orders (
    order_id       INT NOT NULL,
    customer_id    INT NOT NULL,
    order_timestamp TIMESTAMP NOT NULL,
    amount         NUMERIC(12,2),
    order_status   VARCHAR(20),
    source_updated_at TIMESTAMP NOT NULL,
    ingested_at    TIMESTAMP NOT NULL
);

CREATE TABLE de_pipeline_runs (
    run_id        INT PRIMARY KEY,
    pipeline_name VARCHAR(100) NOT NULL,
    start_time    TIMESTAMP NOT NULL,
    end_time      TIMESTAMP,
    rows_read     INT NOT NULL,
    rows_written  INT NOT NULL,
    run_status    VARCHAR(20) NOT NULL
);

-- =========================================================
-- 2. SAMPLE DATA
-- =========================================================

-- Deliberate duplicate customer records: same customer_id, different update timestamps.
INSERT INTO de_customers VALUES
(1, 'Aarav Shah', 'aarav@example.com', 'Pune', '2024-10-01 09:00:00', 'CRM'),
(2, 'Meera Patil', 'meera@example.com', 'Mumbai', '2024-10-02 10:00:00', 'CRM'),
(3, 'Rohan Kulkarni', 'rohan@example.com', 'Pune', '2024-10-02 11:00:00', 'CRM'),
(1, 'Aarav Shah', 'aarav.shah@example.com', 'Pune', '2024-10-05 14:30:00', 'CRM'),
(4, 'Sara Khan', NULL, 'Nashik', '2024-10-04 08:15:00', 'CRM'),
(5, 'Dev Joshi', 'dev@example.com', NULL, '2024-10-06 12:00:00', 'CRM'),
(6, 'Anaya Desai', 'anaya@example.com', 'Nagpur', '2024-10-07 16:45:00', 'CRM');

-- Deliberate duplicate order_id 1002; newest source_updated_at should win.
INSERT INTO de_orders VALUES
(1001, 1, '2024-10-01 10:00:00', 1200.00, 'COMPLETED', '2024-10-01 10:05:00', '2024-10-01 10:10:00'),
(1002, 2, '2024-10-02 11:00:00', 2500.00, 'PENDING',   '2024-10-02 11:10:00', '2024-10-02 11:12:00'),
(1003, 3, '2024-10-03 12:00:00', 800.00,  'COMPLETED', '2024-10-03 12:05:00', '2024-10-03 12:08:00'),
(1002, 2, '2024-10-02 11:00:00', 2500.00, 'COMPLETED', '2024-10-04 09:30:00', '2024-10-04 09:35:00'),
(1004, 4, '2024-10-04 13:00:00', NULL,    'COMPLETED', '2024-10-04 13:05:00', '2024-10-04 13:07:00'),
(1005, 1, '2024-10-05 14:00:00', 5600.00, 'CANCELLED', '2024-10-05 14:05:00', '2024-10-05 14:06:00'),
(1006, 6, '2024-10-06 15:00:00', 3200.00, 'COMPLETED', '2024-10-06 15:05:00', '2024-10-08 08:00:00'),
(1007, 8, '2024-10-07 16:00:00', 900.00,  'COMPLETED', '2024-10-07 16:05:00', '2024-10-07 16:10:00');

INSERT INTO de_pipeline_runs VALUES
(1, 'orders_ingestion', '2024-10-01 01:00:00', '2024-10-01 01:05:00', 1000, 995, 'SUCCESS'),
(2, 'orders_ingestion', '2024-10-02 01:00:00', '2024-10-02 01:09:00', 1100, 1100, 'SUCCESS'),
(3, 'customers_ingestion', '2024-10-02 02:00:00', '2024-10-02 02:03:00', 200, 0, 'FAILED'),
(4, 'orders_ingestion', '2024-10-03 01:00:00', '2024-10-03 01:12:00', 1200, 1188, 'SUCCESS'),
(5, 'customers_ingestion', '2024-10-04 02:00:00', NULL, 250, 0, 'RUNNING'),
(6, 'orders_ingestion', '2024-10-05 01:00:00', '2024-10-05 01:06:00', 1250, 1240, 'SUCCESS');

-- =========================================================
-- 3. QUESTIONS (TRY FIRST)
-- =========================================================
-- Q01 [Deduplication] Return one latest record per customer_id using updated_at.
-- Q02 [Deduplication] Return one latest record per order_id using source_updated_at.
-- Q03 [Data quality] Find customer records with missing email or city.
-- Q04 [Data quality] Find orders with NULL or non-positive amounts.
-- Q05 [Referential integrity] Find orders whose customer_id does not exist in de_customers.
-- Q06 [Aggregation] Calculate completed order count and revenue by order_status.
-- Q07 [Incremental load] Return orders updated after 2024-10-03 00:00:00.
-- Q08 [Late-arriving data] Find orders whose source update occurred at least 24 hours before ingestion.
-- Q09 [Window function] Number each customer's orders from newest to oldest.
-- Q10 [Running metric] Calculate cumulative completed-order revenue by order_timestamp.
-- Q11 [Pipeline monitoring] Calculate success/failure counts for each pipeline_name.
-- Q12 [Pipeline monitoring] Find pipeline runs where rows_read differs from rows_written.
-- Q13 [Pipeline monitoring] Calculate run duration in seconds for completed runs.
-- Q14 [Data quality] Calculate the percentage of customer rows with a non-NULL email.
-- Q15 [Business logic] Find customers whose completed-order revenue exceeds 2,000.
-- Q16 [Incremental load] Return the latest source_updated_at timestamp per order_id.
-- Q17 [SCD concept] Show old and new city values for customers whose city changed between versions.
-- Q18 [NULL handling] Count distinct non-NULL customer emails in the raw customer table.
-- Q19 [Top-N] Find the two highest-revenue customers, based on deduplicated completed orders.
-- Q20 [Reconciliation] Compare raw order row count with deduplicated order count.

-- =========================================================
-- 4. ANSWER KEY (UNCOMMENT ONE QUERY AT A TIME)
-- =========================================================

-- A01: Latest customer version per customer_id.
-- WITH ranked AS (
--   SELECT c.*,
--          ROW_NUMBER() OVER (
--            PARTITION BY customer_id ORDER BY updated_at DESC
--          ) AS rn
--   FROM de_customers c
-- )
-- SELECT customer_id, customer_name, email, city, updated_at
-- FROM ranked
-- WHERE rn = 1
-- ORDER BY customer_id;

-- A02: Latest order version per order_id.
-- WITH ranked AS (
--   SELECT o.*,
--          ROW_NUMBER() OVER (
--            PARTITION BY order_id ORDER BY source_updated_at DESC, ingested_at DESC
--          ) AS rn
--   FROM de_orders o
-- )
-- SELECT order_id, customer_id, order_timestamp, amount, order_status, source_updated_at
-- FROM ranked
-- WHERE rn = 1
-- ORDER BY order_id;

-- A03
-- SELECT * FROM de_customers
-- WHERE email IS NULL OR city IS NULL;

-- A04
-- SELECT * FROM de_orders
-- WHERE amount IS NULL OR amount <= 0;

-- A05: Use the deduplicated customer keys to avoid treating an older version as a separate customer.
-- WITH latest_customers AS (
--   SELECT customer_id,
--          ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY updated_at DESC) AS rn
--   FROM de_customers
-- )
-- SELECT o.*
-- FROM de_orders o
-- LEFT JOIN latest_customers c ON c.customer_id = o.customer_id AND c.rn = 1
-- WHERE c.customer_id IS NULL;

-- A06
-- SELECT order_status, COUNT(*) AS order_count, SUM(amount) AS total_amount
-- FROM de_orders
-- GROUP BY order_status
-- ORDER BY order_status;
-- Note: this is a raw-row report. Deduplicate orders first if reporting final order state.

-- A07
-- SELECT *
-- FROM de_orders
-- WHERE source_updated_at > TIMESTAMP '2024-10-03 00:00:00'
-- ORDER BY source_updated_at;

-- A08
-- SELECT order_id, source_updated_at, ingested_at,
--        ingested_at - source_updated_at AS ingestion_delay
-- FROM de_orders
-- WHERE ingested_at >= source_updated_at + INTERVAL '24 hours'
-- ORDER BY ingestion_delay DESC;

-- A09
-- SELECT order_id, customer_id, order_timestamp, amount,
--        ROW_NUMBER() OVER (
--          PARTITION BY customer_id ORDER BY order_timestamp DESC, order_id DESC
--        ) AS order_recency
-- FROM de_orders
-- ORDER BY customer_id, order_recency;

-- A10
-- WITH deduplicated AS (
--   SELECT o.*,
--          ROW_NUMBER() OVER (
--            PARTITION BY order_id ORDER BY source_updated_at DESC, ingested_at DESC
--          ) AS rn
--   FROM de_orders o
-- ),
-- completed_orders AS (
--   SELECT * FROM deduplicated WHERE rn = 1 AND order_status = 'COMPLETED'
-- )
-- SELECT order_id, order_timestamp, amount,
--        SUM(COALESCE(amount, 0)) OVER (
--          ORDER BY order_timestamp, order_id
--          ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
--        ) AS cumulative_revenue
-- FROM completed_orders
-- ORDER BY order_timestamp, order_id;

-- A11
-- SELECT pipeline_name,
--        COUNT(*) FILTER (WHERE run_status = 'SUCCESS') AS successful_runs,
--        COUNT(*) FILTER (WHERE run_status = 'FAILED') AS failed_runs,
--        COUNT(*) FILTER (WHERE run_status = 'RUNNING') AS running_runs
-- FROM de_pipeline_runs
-- GROUP BY pipeline_name
-- ORDER BY pipeline_name;
-- Portable alternative: use SUM(CASE WHEN run_status = 'SUCCESS' THEN 1 ELSE 0 END).

-- A12
-- SELECT run_id, pipeline_name, rows_read, rows_written,
--        rows_read - rows_written AS row_difference
-- FROM de_pipeline_runs
-- WHERE rows_read <> rows_written
-- ORDER BY run_id;

-- A13
-- SELECT run_id, pipeline_name,
--        EXTRACT(EPOCH FROM (end_time - start_time)) AS duration_seconds
-- FROM de_pipeline_runs
-- WHERE end_time IS NOT NULL
-- ORDER BY run_id;

-- A14
-- SELECT ROUND(
--   100.0 * COUNT(email) / NULLIF(COUNT(*), 0), 2
-- ) AS percent_with_email
-- FROM de_customers;

-- A15
-- WITH latest_orders AS (
--   SELECT o.*,
--          ROW_NUMBER() OVER (
--            PARTITION BY order_id ORDER BY source_updated_at DESC, ingested_at DESC
--          ) AS rn
--   FROM de_orders o
-- )
-- SELECT c.customer_id, c.customer_name, SUM(o.amount) AS completed_revenue
-- FROM latest_orders o
-- JOIN (
--   SELECT customer_id, customer_name,
--          ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY updated_at DESC) AS rn
--   FROM de_customers
-- ) c ON c.customer_id = o.customer_id AND c.rn = 1
-- WHERE o.rn = 1 AND o.order_status = 'COMPLETED'
-- GROUP BY c.customer_id, c.customer_name
-- HAVING SUM(o.amount) > 2000
-- ORDER BY completed_revenue DESC;

-- A16
-- SELECT order_id, MAX(source_updated_at) AS latest_source_update
-- FROM de_orders
-- GROUP BY order_id
-- ORDER BY order_id;

-- A17: Compare adjacent customer versions. A changed city can indicate a dimension update.
-- WITH versions AS (
--   SELECT customer_id, customer_name, city, updated_at,
--          LAG(city) OVER (PARTITION BY customer_id ORDER BY updated_at) AS previous_city
--   FROM de_customers
-- )
-- SELECT customer_id, customer_name, previous_city, city AS new_city, updated_at
-- FROM versions
-- WHERE previous_city IS NOT NULL AND city IS DISTINCT FROM previous_city
-- ORDER BY customer_id, updated_at;

-- A18
-- SELECT COUNT(DISTINCT email) AS distinct_non_null_emails
-- FROM de_customers;

-- A19: Deduplicate both orders and customer versions before aggregating.
-- WITH latest_orders AS (
--   SELECT o.*,
--          ROW_NUMBER() OVER (
--            PARTITION BY order_id ORDER BY source_updated_at DESC, ingested_at DESC
--          ) AS rn
--   FROM de_orders o
-- ),
-- latest_customers AS (
--   SELECT customer_id, customer_name,
--          ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY updated_at DESC) AS rn
--   FROM de_customers
-- ),
-- revenue AS (
--   SELECT c.customer_id, c.customer_name, SUM(o.amount) AS completed_revenue
--   FROM latest_orders o
--   JOIN latest_customers c ON c.customer_id = o.customer_id AND c.rn = 1
--   WHERE o.rn = 1 AND o.order_status = 'COMPLETED'
--   GROUP BY c.customer_id, c.customer_name
-- )
-- SELECT * FROM revenue
-- ORDER BY completed_revenue DESC, customer_id
-- LIMIT 2;

-- A20
-- SELECT
--   (SELECT COUNT(*) FROM de_orders) AS raw_order_rows,
--   (SELECT COUNT(DISTINCT order_id) FROM de_orders) AS distinct_order_ids,
--   (SELECT COUNT(*) FROM (
--      SELECT order_id,
--             ROW_NUMBER() OVER (
--               PARTITION BY order_id ORDER BY source_updated_at DESC, ingested_at DESC
--             ) AS rn
--      FROM de_orders
--    ) x WHERE rn = 1) AS deduplicated_order_rows;

-- END OF DATA ENGINEERING PRACTICE FILE
