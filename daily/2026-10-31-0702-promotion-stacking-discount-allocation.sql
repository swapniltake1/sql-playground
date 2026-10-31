-- =============================================================================
-- Daily Data Engineering Practice | 2026-10-31 07:02 IST
-- Topic: Promotion Eligibility, Stacking Rules & Discount Allocation
-- Engine: PostgreSQL 14+
--
-- Run independently. The setup is isolated and repeatable.
-- Exercises are numbered; solutions are executable so you can inspect each result.
-- Business policy for this lab:
--   * A promotion is active for [starts_at, ends_at).
--   * At most one promotion is selected per order + stack_group (highest priority).
--   * A promotion with no product mapping applies to every line.
--   * A mapped promotion applies only to mapped products.
--   * Percentage discounts are calculated on that promotion's eligible subtotal.
--   * Different stack groups are additive in this exercise. Production systems
--     should explicitly define sequential-vs-additive stacking and a total cap.
-- =============================================================================

DROP TABLE IF EXISTS promo_redemptions;
DROP TABLE IF EXISTS promotion_products;
DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS promotions;
DROP TABLE IF EXISTS products;

CREATE TABLE products (
    product_id      BIGINT PRIMARY KEY,
    product_name    TEXT NOT NULL,
    category        TEXT NOT NULL,
    list_price      NUMERIC(12,2) NOT NULL CHECK (list_price >= 0),
    unit_cost       NUMERIC(12,2) NOT NULL CHECK (unit_cost >= 0)
);

CREATE TABLE orders (
    order_id        BIGINT PRIMARY KEY,
    customer_id     BIGINT NOT NULL,
    ordered_at      TIMESTAMPTZ NOT NULL,
    order_status    TEXT NOT NULL CHECK (order_status IN ('PAID', 'CANCELLED', 'PENDING'))
);

CREATE TABLE order_items (
    order_id        BIGINT NOT NULL REFERENCES orders(order_id),
    line_id         INTEGER NOT NULL,
    product_id      BIGINT NOT NULL REFERENCES products(product_id),
    quantity        INTEGER NOT NULL CHECK (quantity > 0),
    unit_price      NUMERIC(12,2) NOT NULL CHECK (unit_price >= 0),
    PRIMARY KEY (order_id, line_id)
);

CREATE TABLE promotions (
    promotion_id    BIGINT PRIMARY KEY,
    promotion_code  TEXT NOT NULL UNIQUE,
    promotion_name  TEXT NOT NULL,
    stack_group     TEXT NOT NULL,
    priority        INTEGER NOT NULL,
    starts_at       TIMESTAMPTZ NOT NULL,
    ends_at         TIMESTAMPTZ NOT NULL,
    discount_type   TEXT NOT NULL CHECK (discount_type IN ('PERCENT', 'FIXED')),
    discount_value  NUMERIC(10,2) NOT NULL CHECK (discount_value > 0),
    min_subtotal    NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (min_subtotal >= 0),
    CHECK (starts_at < ends_at),
    CHECK (discount_type <> 'PERCENT' OR discount_value <= 100)
);

CREATE TABLE promotion_products (
    promotion_id    BIGINT NOT NULL REFERENCES promotions(promotion_id),
    product_id      BIGINT NOT NULL REFERENCES products(product_id),
    PRIMARY KEY (promotion_id, product_id)
);

CREATE TABLE promo_redemptions (
    redemption_id   BIGINT PRIMARY KEY,
    order_id        BIGINT NOT NULL REFERENCES orders(order_id),
    promotion_id    BIGINT NOT NULL REFERENCES promotions(promotion_id),
    redeemed_at     TIMESTAMPTZ NOT NULL,
    source_channel  TEXT NOT NULL
);

INSERT INTO products VALUES
(1, 'Laptop Pro 14', 'ELECTRONICS', 1000.00, 700.00),
(2, 'Wireless Mouse', 'ELECTRONICS',   50.00,  20.00),
(3, 'Ergonomic Chair', 'HOME',        200.00, 120.00),
(4, 'Standing Desk',   'HOME',        300.00, 180.00),
(5, 'Ceramic Mug',     'HOME',         20.00,   5.00);

INSERT INTO orders VALUES
(1001, 501, '2026-10-30 10:00:00+05:30', 'PAID'),
(1002, 502, '2026-10-30 12:00:00+05:30', 'PAID'),
(1003, 503, '2026-10-30 13:00:00+05:30', 'PAID'),
(1004, 504, '2026-10-31 07:00:00+05:30', 'PAID'),
(1005, 505, '2026-10-31 07:30:00+05:30', 'CANCELLED');

INSERT INTO order_items VALUES
(1001, 1, 1, 1, 1000.00), (1001, 2, 2, 2, 50.00),
(1002, 1, 3, 1,  200.00), (1002, 2, 4, 1, 300.00),
(1003, 1, 1, 1, 1000.00), (1003, 2, 5, 2,  20.00),
(1004, 1, 2, 2,   50.00), (1004, 2, 3, 1, 200.00),
(1005, 1, 4, 1,  300.00);

INSERT INTO promotions VALUES
(10, 'WELCOME10', 'Welcome 10 percent', 'CUSTOMER', 10,
 '2026-10-01 00:00:00+05:30', '2026-11-01 00:00:00+05:30', 'PERCENT', 10,  50),
(11, 'VIP20', 'VIP 20 percent', 'CUSTOMER', 20,
 '2026-10-01 00:00:00+05:30', '2026-11-01 00:00:00+05:30', 'PERCENT', 20, 500),
(20, 'ELEC15', 'Electronics 15 percent', 'CATEGORY', 15,
 '2026-10-01 00:00:00+05:30', '2026-11-01 00:00:00+05:30', 'PERCENT', 15, 100),
(21, 'HOME5', 'Home fixed discount', 'CATEGORY', 5,
 '2026-10-01 00:00:00+05:30', '2026-11-01 00:00:00+05:30', 'FIXED', 5, 100),
(30, 'AUTUMN30', 'Expired autumn campaign', 'CATEGORY', 30,
 '2026-10-01 00:00:00+05:30', '2026-10-30 00:00:00+05:30', 'PERCENT', 30, 100);

INSERT INTO promotion_products VALUES
(20, 1), (20, 2),
(21, 3), (21, 4);

INSERT INTO promo_redemptions VALUES
(1, 1001, 11, '2026-10-30 10:01:00+05:30', 'WEB'),
(2, 1001, 20, '2026-10-30 10:01:00+05:30', 'WEB'),
(3, 1001, 30, '2026-10-30 10:01:00+05:30', 'WEB'), -- expired
(4, 1002, 11, '2026-10-30 12:01:00+05:30', 'APP'),
(5, 1002, 21, '2026-10-30 12:01:00+05:30', 'APP'),
(6, 1002, 10, '2026-10-30 12:01:00+05:30', 'APP'), -- lower priority in same group
(7, 1003, 11, '2026-10-30 13:01:00+05:30', 'WEB'),
(8, 1003, 20, '2026-10-30 13:01:00+05:30', 'WEB'),
(9, 1004, 10, '2026-10-31 07:01:00+05:30', 'APP'),
(10, 1004, 20, '2026-10-31 07:01:00+05:30', 'APP'),
(11, 1004, 21, '2026-10-31 07:01:00+05:30', 'APP'), -- lower priority in CATEGORY
(12, 1005, 21, '2026-10-31 07:31:00+05:30', 'WEB'); -- cancelled order

-- Q1. Establish the order grain before applying any promotion.
-- Problem: Return one row per paid order with gross merchandise subtotal.
-- Optimization: Aggregate line items once; do not join raw lines to redemptions.
SELECT o.order_id,
       SUM(oi.quantity * oi.unit_price)::NUMERIC(12,2) AS gross_subtotal
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
WHERE o.order_status = 'PAID'
GROUP BY o.order_id
ORDER BY o.order_id;

-- Q2. Build the eligible-promotion set.
-- Problem: A promo must be active, meet its minimum, and match at least one
-- eligible line. An unmapped promo applies to all products.
-- Optimization: LATERAL computes the eligible subtotal once per order/promo;
-- EXISTS avoids multiplying line rows through a mapping join.
CREATE TEMP VIEW eligible_promotions AS
SELECT o.order_id,
       p.promotion_id,
       p.promotion_code,
       p.stack_group,
       p.priority,
       p.discount_type,
       p.discount_value,
       b.eligible_subtotal
FROM orders o
CROSS JOIN promotions p
CROSS JOIN LATERAL (
    SELECT SUM(oi.quantity * oi.unit_price)::NUMERIC(12,2) AS eligible_subtotal
    FROM order_items oi
    WHERE oi.order_id = o.order_id
      AND (
          NOT EXISTS (
              SELECT 1 FROM promotion_products pp
              WHERE pp.promotion_id = p.promotion_id
          )
          OR EXISTS (
              SELECT 1
              FROM promotion_products pp
              WHERE pp.promotion_id = p.promotion_id
                AND pp.product_id = oi.product_id
          )
      )
) b
WHERE o.order_status = 'PAID'
  AND o.ordered_at >= p.starts_at
  AND o.ordered_at <  p.ends_at
  AND b.eligible_subtotal >= p.min_subtotal;

SELECT * FROM eligible_promotions
ORDER BY order_id, stack_group, priority DESC;

-- Q3. Apply the deterministic stacking policy.
-- Problem: Select one promotion per order + stack_group using highest priority.
-- A stable promotion_id tie-breaker makes reruns deterministic.
-- Optimization: ROW_NUMBER is evaluated only over eligible candidates.
CREATE TEMP VIEW selected_promotions AS
WITH ranked AS (
    SELECT ep.*,
           ROW_NUMBER() OVER (
               PARTITION BY order_id, stack_group
               ORDER BY priority DESC, promotion_id
           ) AS priority_rank
    FROM eligible_promotions ep
)
SELECT order_id,
       promotion_id,
       promotion_code,
       stack_group,
       eligible_subtotal,
       discount_type,
       discount_value,
       CASE
           WHEN discount_type = 'PERCENT'
               THEN ROUND(eligible_subtotal * discount_value / 100.0, 2)
           ELSE LEAST(eligible_subtotal, discount_value)
       END::NUMERIC(12,2) AS discount_amount
FROM ranked
WHERE priority_rank = 1;

SELECT * FROM selected_promotions
ORDER BY order_id, stack_group;

-- Q4. Audit submitted coupon redemptions against the selected policy result.
-- Problem: Distinguish accepted, superseded/stack-blocked, expired, and
-- ineligible redemptions. A redemption is accepted only when it was selected.
-- Optimization: LEFT JOIN preserves failed redemptions for audit reporting.
SELECT r.redemption_id,
       r.order_id,
       p.promotion_code,
       CASE
           WHEN o.order_status <> 'PAID' THEN 'REJECTED_ORDER_NOT_PAID'
           WHEN o.ordered_at < p.starts_at OR o.ordered_at >= p.ends_at
               THEN 'REJECTED_OUTSIDE_VALIDITY'
           WHEN s.promotion_id IS NULL THEN 'NOT_SELECTED_OR_NOT_ELIGIBLE'
           ELSE 'ACCEPTED'
       END AS redemption_result
FROM promo_redemptions r
JOIN orders o ON o.order_id = r.order_id
JOIN promotions p ON p.promotion_id = r.promotion_id
LEFT JOIN selected_promotions s
       ON s.order_id = r.order_id
      AND s.promotion_id = r.promotion_id
ORDER BY r.redemption_id;

-- Q5. Allocate each selected discount to eligible order lines.
-- Problem: Allocate proportionally to eligible line value. The final line
-- absorbs any cent-rounding remainder so allocated cents equal promo cents.
-- Optimization: Keep allocation at (order_id, promotion_id, line_id) grain;
-- aggregate only after the exact per-promotion allocation is complete.
WITH eligible_lines AS (
    SELECT s.order_id,
           s.promotion_id,
           s.discount_amount,
           s.eligible_subtotal,
           oi.line_id,
           oi.product_id,
           oi.quantity,
           oi.unit_price,
           (oi.quantity * oi.unit_price)::NUMERIC(12,2) AS line_subtotal
    FROM selected_promotions s
    JOIN order_items oi ON oi.order_id = s.order_id
    WHERE
        NOT EXISTS (
            SELECT 1 FROM promotion_products pp
            WHERE pp.promotion_id = s.promotion_id
        )
        OR EXISTS (
            SELECT 1 FROM promotion_products pp
            WHERE pp.promotion_id = s.promotion_id
              AND pp.product_id = oi.product_id
        )
),
rounded_shares AS (
    SELECT *,
           ROUND(discount_amount * line_subtotal / eligible_subtotal, 2)
               AS rounded_share,
           ROW_NUMBER() OVER (
               PARTITION BY order_id, promotion_id
               ORDER BY line_id DESC
           ) AS remainder_row
    FROM eligible_lines
),
allocated AS (
    SELECT *,
           CASE WHEN remainder_row = 1
                THEN discount_amount
                     - (SUM(rounded_share) OVER (
                           PARTITION BY order_id, promotion_id
                       ) - rounded_share)
                ELSE rounded_share
           END::NUMERIC(12,2) AS allocated_discount
    FROM rounded_shares
)
SELECT order_id, promotion_id, line_id, product_id,
       line_subtotal, allocated_discount
FROM allocated
ORDER BY order_id, promotion_id, line_id;

-- Q6. Calculate post-discount revenue and contribution margin by category.
-- Problem: Reconcile allocated discounts to line-level net revenue and COGS.
-- Optimization: Aggregate allocations to line grain before joining products;
-- avoid a many-to-many join between lines and promotions.
WITH allocated AS (
    WITH eligible_lines AS (
        SELECT s.order_id, s.promotion_id, s.discount_amount,
               s.eligible_subtotal, oi.line_id, oi.product_id,
               (oi.quantity * oi.unit_price)::NUMERIC(12,2) AS line_subtotal
        FROM selected_promotions s
        JOIN order_items oi ON oi.order_id = s.order_id
        WHERE NOT EXISTS (
                  SELECT 1 FROM promotion_products pp
                  WHERE pp.promotion_id = s.promotion_id
              )
           OR EXISTS (
                  SELECT 1 FROM promotion_products pp
                  WHERE pp.promotion_id = s.promotion_id
                    AND pp.product_id = oi.product_id
              )
    ),
    shares AS (
        SELECT *,
               ROUND(discount_amount * line_subtotal / eligible_subtotal, 2)
                   AS rounded_share,
               ROW_NUMBER() OVER (
                   PARTITION BY order_id, promotion_id ORDER BY line_id DESC
               ) AS remainder_row
        FROM eligible_lines
    )
    SELECT order_id, line_id,
           CASE WHEN remainder_row = 1
                THEN discount_amount
                     - (SUM(rounded_share) OVER (
                           PARTITION BY order_id, promotion_id
                       ) - rounded_share)
                ELSE rounded_share
           END AS allocated_discount
    FROM shares
),
discount_by_line AS (
    SELECT order_id, line_id, SUM(allocated_discount) AS total_discount
    FROM allocated
    GROUP BY order_id, line_id
),
line_economics AS (
    SELECT oi.order_id, oi.line_id, p.category,
           oi.quantity * oi.unit_price AS gross_revenue,
           oi.quantity * p.unit_cost AS cost_of_goods,
           COALESCE(d.total_discount, 0) AS discount
    FROM order_items oi
    JOIN orders o ON o.order_id = oi.order_id AND o.order_status = 'PAID'
    JOIN products p ON p.product_id = oi.product_id
    LEFT JOIN discount_by_line d
      ON d.order_id = oi.order_id AND d.line_id = oi.line_id
)
SELECT category,
       SUM(gross_revenue) AS gross_revenue,
       SUM(discount) AS allocated_discount,
       SUM(gross_revenue - discount) AS net_revenue,
       SUM(cost_of_goods) AS cost_of_goods,
       SUM(gross_revenue - discount - cost_of_goods) AS contribution_margin
FROM line_economics
GROUP BY category
ORDER BY category;

-- Q7. Measure selected campaign performance and preserve zero-redemption promos.
-- Problem: Return orders, discount value, and average discount by campaign.
-- Optimization: LEFT JOIN from promotions so unused campaigns remain visible.
SELECT p.promotion_code,
       COUNT(s.order_id) AS selected_orders,
       COALESCE(SUM(s.discount_amount), 0)::NUMERIC(12,2) AS total_discount,
       ROUND(AVG(s.discount_amount), 2) AS avg_discount
FROM promotions p
LEFT JOIN selected_promotions s ON s.promotion_id = p.promotion_id
GROUP BY p.promotion_id, p.promotion_code
ORDER BY selected_orders DESC, p.promotion_code;

-- Q8. Detect overlapping promotions that can compete in the same stack group.
-- Problem: Find time-overlapping promotions with intersecting product scope.
-- An empty mapping means global scope. Half-open time intervals avoid treating
-- an end instant as overlapping the next campaign's start instant.
-- Optimization: Compare each unordered pair once and use EXISTS for scope.
SELECT a.promotion_code AS promotion_a,
       b.promotion_code AS promotion_b,
       a.stack_group,
       GREATEST(a.starts_at, b.starts_at) AS overlap_start,
       LEAST(a.ends_at, b.ends_at) AS overlap_end
FROM promotions a
JOIN promotions b
  ON a.promotion_id < b.promotion_id
 AND a.stack_group = b.stack_group
 AND a.starts_at < b.ends_at
 AND b.starts_at < a.ends_at
WHERE
    (
        NOT EXISTS (SELECT 1 FROM promotion_products x
                    WHERE x.promotion_id = a.promotion_id)
        OR NOT EXISTS (SELECT 1 FROM promotion_products y
                       WHERE y.promotion_id = b.promotion_id)
        OR EXISTS (
            SELECT 1
            FROM promotion_products x
            JOIN promotion_products y ON y.product_id = x.product_id
            WHERE x.promotion_id = a.promotion_id
              AND y.promotion_id = b.promotion_id
        )
    )
ORDER BY a.stack_group, overlap_start;

-- PERFORMANCE LAB
-- Candidate indexes; validate against production cardinality and write volume.
-- CREATE INDEX ix_orders_paid_time ON orders (ordered_at, order_id)
--     WHERE order_status = 'PAID';
-- CREATE INDEX ix_order_items_order_product
--     ON order_items (order_id, product_id) INCLUDE (quantity, unit_price);
-- CREATE INDEX ix_promo_active_group
--     ON promotions (stack_group, starts_at, ends_at);
-- CREATE INDEX ix_promotion_products_product
--     ON promotion_products (product_id, promotion_id);
-- CREATE INDEX ix_redemptions_order_promo
--     ON promo_redemptions (order_id, promotion_id);
--
-- Inspect the candidate-generation query with:
-- EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
-- SELECT ... -- use the Q2 SELECT body with representative larger data.
--
-- Performance notes:
-- 1. Keep validity predicates SARGable: ordered_at >= starts_at AND ordered_at < ends_at.
-- 2. Avoid joining raw redemptions to order lines before aggregation; that creates fanout.
-- 3. Promotion scope lookups benefit from both (promotion_id, product_id) and
--    (product_id, promotion_id) access paths when the workload needs both directions.
-- 4. For very large workloads, pre-filter active promotions by campaign date and
--    persist an order/promotion candidate table for downstream allocation.
-- 5. This lab uses additive discounts across stack groups. Production must specify
--    whether discounts compound sequentially, are additive, or are capped at line/order
--    value; enforce that policy before allocating to lines.
--
-- Expected spot checks:
-- * Paid gross subtotals: 1001=1100, 1002=500, 1003=1040, 1004=300.
-- * Selected CUSTOMER promos: VIP20 for 1001/1002/1003; WELCOME10 for 1004.
-- * Selected CATEGORY promos: ELEC15 for 1001/1003/1004; HOME5 for 1002.
-- * AUTUMN30 is expired; order 1005 is cancelled and has no eligible selection.
-- * Q4 should identify expired, superseded, and cancelled-order redemptions.
