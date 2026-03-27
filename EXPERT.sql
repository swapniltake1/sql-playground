-- Example 1. Pareto (80%)
-- Calculate the Pareto principle: identify products contributing to 80% of total revenue using cumulative sum.
WITH sales_cte AS (
SELECT product_id, SUM(quantity * price) revenue
FROM Sales GROUP BY product_id
),
total AS (
SELECT SUM(revenue) total FROM sales_cte
)
SELECT *
FROM (
SELECT s.*,
SUM(revenue) OVER (ORDER BY revenue DESC) running
FROM sales_cte s
) t
WHERE running <= (SELECT total * 0.8 FROM total);

-- Example 2. Login streaks
-- Find users with login streaks of at least 3 consecutive days.
WITH cte AS (
SELECT user_id, login_date,
DATEDIFF(DAY,
ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY login_date),
login_date) grp
FROM Logins
)
SELECT user_id, COUNT(*) streak
FROM cte
GROUP BY user_id, grp
HAVING COUNT(*) >= 3;

-- Example 3. Cohort analysis
-- Perform cohort analysis: count customers by cohort month and order month.
WITH c AS (
SELECT customer_id,
DATE_TRUNC('month', MIN(order_date)) cohort
FROM Orders GROUP BY customer_id
)
SELECT c.cohort, DATE_TRUNC('month', o.order_date),
COUNT(DISTINCT o.customer_id)
FROM c
JOIN Orders o ON c.customer_id = o.customer_id
GROUP BY 1,2;

-- Example 4. Gini coefficient
-- Calculate the Gini coefficient for salary distribution.
WITH cte AS (
SELECT salary,
SUM(salary) OVER (ORDER BY salary) cum_income,
COUNT(*) OVER() n
FROM Employee
)
SELECT 1 - (2 * SUM(cum_income / SUM(salary) OVER () * (1.0/n)))
FROM cte;

-- Example 5. Top 10% revenue customers
-- Calculate the percentage of revenue from top 10% customers.
WITH cte AS (
SELECT customer_id, SUM(total_amount) revenue
FROM Orders GROUP BY customer_id
),
ranked AS (
SELECT *, NTILE(10) OVER (ORDER BY revenue DESC) d
FROM cte
)
SELECT SUM(revenue) * 100.0 / (SELECT SUM(revenue) FROM cte)
FROM ranked
WHERE d = 1;

-- Example 6. Bottom 10% customers
-- Identify customers in the bottom 10% by revenue.
WITH cte AS (
SELECT customer_id, SUM(total_amount) revenue
FROM Orders GROUP BY customer_id
)
SELECT *
FROM cte
WHERE revenue < (
SELECT PERCENTILE_CONT(0.1)
WITHIN GROUP (ORDER BY revenue)
FROM cte
);