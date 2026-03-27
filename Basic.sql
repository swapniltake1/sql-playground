-- Example 1. Find duplicate records
-- Identify records that appear more than once based on specified columns.
SELECT column1, column2, COUNT(*)
FROM your_table
GROUP BY column1, column2
HAVING COUNT(*) > 1;

-- Example 2. Second highest salary
-- Find the second highest salary from the Employee table.
SELECT MAX(salary)
FROM Employee
WHERE salary < (SELECT MAX(salary) FROM Employee);

-- Example 3. Employees without department
-- List employees who are not assigned to any department.
SELECT e.*
FROM Employee e
LEFT JOIN Department d
ON e.department_id = d.department_id
WHERE d.department_id IS NULL;

-- Example 4. Total revenue per product
-- Calculate the total revenue for each product.
SELECT product_id,
SUM(quantity * price) AS total_revenue
FROM Sales
GROUP BY product_id;

-- Example 5. Top 3 highest paid
-- Retrieve the top 3 highest paid employees.
SELECT *
FROM Employee
ORDER BY salary DESC
FETCH FIRST 3 ROWS ONLY;

-- Example 6. Customers who never returned
-- Find customers who have placed orders but never returned any items.
SELECT DISTINCT c.customer_id
FROM Customers c
JOIN Orders o ON c.customer_id = o.customer_id
WHERE c.customer_id NOT IN (SELECT customer_id FROM Returns);

-- Example 7. Orders per customer
-- Count the number of orders placed by each customer.
SELECT customer_id, COUNT(*)
FROM Orders
GROUP BY customer_id;

-- Example 8. Employees joined in 2023
-- List employees who were hired in the year 2023.
SELECT *
FROM Employee
WHERE YEAR(hire_date) = 2023;

-- Example 9. Avg order value per customer
-- Calculate the average order value for each customer.
SELECT customer_id, AVG(total_amount)
FROM Orders
GROUP BY customer_id;

-- Example 10. Latest order per customer
-- Find the most recent order date for each customer.
SELECT customer_id, MAX(order_date)
FROM Orders
GROUP BY customer_id;