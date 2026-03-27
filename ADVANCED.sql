-- Example 1. Consecutive purchases
-- Find customers who made purchases on consecutive days.
WITH cte AS (
SELECT customer_id, order_date,
LAG(order_date) OVER (PARTITION BY customer_id ORDER BY order_date) prev
FROM Orders
)
SELECT *
FROM cte
WHERE DATEDIFF(DAY, prev, order_date) = 1;

-- Example 2. Churned customers
-- Identify customers who haven't placed an order in the last 6 months.
SELECT customer_id
FROM Orders
GROUP BY customer_id
HAVING MAX(order_date) < CURRENT_DATE - INTERVAL '6 MONTH';

-- Example 3. Revenue from new customers
-- Calculate total revenue from first-time customer orders.
WITH first_orders AS (
SELECT customer_id, MIN(order_date) first_order
FROM Orders GROUP BY customer_id
)
SELECT SUM(o.total_amount)
FROM Orders o
JOIN first_orders f
ON o.customer_id = f.customer_id
AND o.order_date = f.first_order;