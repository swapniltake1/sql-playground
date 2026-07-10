-- Practical SQL Interview Question
-- Scenario: Find Duplicate Email Addresses

-- Create Table
CREATE TABLE employees (
    emp_id INT,
    emp_name VARCHAR(100),
    email VARCHAR(100),
    department VARCHAR(50)
);

-- Sample Data
INSERT INTO employees VALUES
(1, 'John', 'john@gmail.com', 'IT'),
(2, 'Alice', 'alice@gmail.com', 'HR'),
(3, 'John', 'john@gmail.com', 'IT'),
(4, 'Bob', 'bob@gmail.com', 'Sales');

-- Interview Question:
-- Find all duplicate email addresses.

SELECT email,
       COUNT(*) AS duplicate_count
FROM employees
GROUP BY email
HAVING COUNT(*) > 1;

-- Display complete duplicate records

SELECT *
FROM employees
WHERE email IN (
    SELECT email
    FROM employees
    GROUP BY email
    HAVING COUNT(*) > 1
);

-- Delete duplicate records while keeping the smallest emp_id

DELETE FROM employees
WHERE emp_id NOT IN (
    SELECT MIN(emp_id)
    FROM employees
    GROUP BY email
);
