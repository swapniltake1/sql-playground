-- Example 1. Products never sold
-- Find products that have never been sold.
SELECT p.product_id
FROM Products p
LEFT JOIN Sales s ON p.product_id = s.product_id
WHERE s.product_id IS NULL;

-- Example 2. Most selling product
-- Identify the product with the highest total quantity sold.
SELECT product_id, SUM(quantity) total
FROM Sales
GROUP BY product_id
ORDER BY total DESC
FETCH FIRST 1 ROW ONLY;

-- Example 3. Revenue + orders per region
-- Calculate total revenue and number of orders per region.
SELECT region,
SUM(total_amount),
COUNT(*)
FROM Orders
GROUP BY region;

-- Example 4. Customers with >5 orders
-- Count customers who have placed more than 5 orders.
SELECT COUNT(*)
FROM (
    SELECT customer_id
    FROM Orders
    GROUP BY customer_id
    HAVING COUNT(*) > 5
) t;

-- Example 5. Orders above average
-- Find orders with total amount above the overall average.
SELECT *
FROM Orders
WHERE total_amount > (SELECT AVG(total_amount) FROM Orders);

-- 🔹 WINDOW FUNCTION ZONE

-- Example 6. Rank employees
-- Rank employees within each department by salary in descending order.
SELECT employee_id, department_id, salary,
RANK() OVER (PARTITION BY department_id ORDER BY salary DESC)
FROM Employee;

-- Example 7. Moving average
-- Calculate the moving average of total amount over the last 3 orders by date.
SELECT order_date,
SUM(total_amount) OVER (
ORDER BY order_date ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)
FROM Orders;

-- Example 8. Cumulative revenue
-- Compute the cumulative sum of total amount ordered by date.
SELECT order_date,
SUM(total_amount) OVER (ORDER BY order_date)
FROM Orders;