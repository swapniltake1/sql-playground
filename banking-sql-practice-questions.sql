-- SQL PLAYGROUND: BANKING TRANSACTIONS PRACTICE
-- Dialect: PostgreSQL-compatible SQL (most queries work with minor changes elsewhere)
--
-- HOW TO PRACTICE
-- 1. Run the setup section to create sample data.
-- 2. Solve each question in the "QUESTIONS" section without looking at the answer key.
-- 3. Check your work in the "ANSWER KEY" section.
-- 4. For each query, think about NULLs, duplicates, ties, and date boundaries.
--
-- Scenario: A small bank wants to analyze customers, accounts, and transactions.
-- This file is self-contained and does not depend on MASTER_PRACTICE_DATABASE.sql.

-- =========================================================
-- 1. SETUP: DROP AND CREATE TABLES
-- =========================================================

DROP TABLE IF EXISTS bank_transactions;
DROP TABLE IF EXISTS bank_accounts;
DROP TABLE IF EXISTS bank_customers;

CREATE TABLE bank_customers (
    customer_id   INT PRIMARY KEY,
    customer_name VARCHAR(100) NOT NULL,
    city          VARCHAR(80) NOT NULL,
    signup_date   DATE NOT NULL
);

CREATE TABLE bank_accounts (
    account_id   INT PRIMARY KEY,
    customer_id  INT NOT NULL REFERENCES bank_customers(customer_id),
    account_type VARCHAR(30) NOT NULL,
    balance      DECIMAL(12, 2) NOT NULL CHECK (balance >= 0),
    opened_date  DATE NOT NULL,
    status       VARCHAR(20) NOT NULL
);

CREATE TABLE bank_transactions (
    transaction_id   INT PRIMARY KEY,
    account_id       INT NOT NULL REFERENCES bank_accounts(account_id),
    transaction_date DATE NOT NULL,
    transaction_type VARCHAR(20) NOT NULL,
    amount           DECIMAL(12, 2) NOT NULL CHECK (amount > 0),
    status           VARCHAR(20) NOT NULL
);

-- =========================================================
-- 2. SAMPLE DATA
-- =========================================================

INSERT INTO bank_customers (customer_id, customer_name, city, signup_date) VALUES
(1, 'Aarav Shah',    'Pune',      '2024-01-10'),
(2, 'Meera Patil',   'Mumbai',    '2024-02-15'),
(3, 'Rohan Kulkarni','Pune',      '2024-03-20'),
(4, 'Sara Khan',     'Nashik',    '2024-04-05'),
(5, 'Dev Joshi',     'Mumbai',    '2024-05-12'),
(6, 'Anaya Desai',   'Nagpur',    '2024-06-01'),
(7, 'Kabir More',    'Pune',      '2024-07-18'),
(8, 'Isha Rao',      'Nashik',    '2024-08-22');

INSERT INTO bank_accounts (account_id, customer_id, account_type, balance, opened_date, status) VALUES
(101, 1, 'SAVINGS',  25000.00, '2024-01-12', 'ACTIVE'),
(102, 1, 'CURRENT',  80000.00, '2024-02-01', 'ACTIVE'),
(103, 2, 'SAVINGS',  42000.00, '2024-02-17', 'ACTIVE'),
(104, 3, 'SAVINGS',  18000.00, '2024-03-22', 'ACTIVE'),
(105, 3, 'CURRENT',  65000.00, '2024-04-10', 'INACTIVE'),
(106, 4, 'SAVINGS',  32000.00, '2024-04-08', 'ACTIVE'),
(107, 5, 'SAVINGS',   9000.00, '2024-05-14', 'ACTIVE'),
(108, 6, 'SAVINGS',  57000.00, '2024-06-03', 'ACTIVE'),
(109, 7, 'SAVINGS',  15000.00, '2024-07-20', 'ACTIVE');

INSERT INTO bank_transactions
(transaction_id, account_id, transaction_date, transaction_type, amount, status) VALUES
(1001, 101, '2024-09-01', 'DEPOSIT',    5000.00, 'SUCCESS'),
(1002, 101, '2024-09-02', 'WITHDRAWAL', 1200.00, 'SUCCESS'),
(1003, 102, '2024-09-03', 'DEPOSIT',   15000.00, 'SUCCESS'),
(1004, 103, '2024-09-03', 'WITHDRAWAL', 2000.00, 'FAILED'),
(1005, 103, '2024-09-05', 'DEPOSIT',    7000.00, 'SUCCESS'),
(1006, 104, '2024-09-06', 'DEPOSIT',    3000.00, 'SUCCESS'),
(1007, 104, '2024-09-07', 'WITHDRAWAL', 1000.00, 'SUCCESS'),
(1008, 106, '2024-09-08', 'DEPOSIT',    4500.00, 'SUCCESS'),
(1009, 107, '2024-09-09', 'WITHDRAWAL',  500.00, 'SUCCESS'),
(1010, 108, '2024-09-10', 'DEPOSIT',    9000.00, 'SUCCESS'),
(1011, 108, '2024-09-11', 'WITHDRAWAL', 3000.00, 'SUCCESS'),
(1012, 109, '2024-09-12', 'DEPOSIT',    2500.00, 'PENDING'),
(1013, 102, '2024-09-13', 'WITHDRAWAL', 6000.00, 'SUCCESS'),
(1014, 101, '2024-09-14', 'DEPOSIT',    2000.00, 'SUCCESS'),
(1015, 103, '2024-09-15', 'DEPOSIT',    4000.00, 'SUCCESS'),
(1016, 106, '2024-09-16', 'WITHDRAWAL', 1500.00, 'SUCCESS'),
(1017, 102, '2024-09-17', 'DEPOSIT',   10000.00, 'FAILED'),
(1018, 108, '2024-09-18', 'DEPOSIT',    6500.00, 'SUCCESS');

-- Quick check:
-- SELECT * FROM bank_customers;
-- SELECT * FROM bank_accounts;
-- SELECT * FROM bank_transactions;

-- =========================================================
-- 3. QUESTIONS — TRY THESE FIRST!
-- =========================================================
-- Q01 [Easy | SELECT, WHERE]
-- List all active accounts with a balance greater than 20,000.
--
-- Q02 [Easy | GROUP BY]
-- Show the number of customers in each city, sorted from highest to lowest.
--
-- Q03 [Easy | JOIN]
-- Display each account with the account holder's name, account type, and balance.
--
-- Q04 [Easy | Aggregate, CASE]
-- For each transaction status, show the transaction count and total amount.
--
-- Q05 [Medium | JOIN, GROUP BY]
-- Calculate the total successful deposit amount for each customer. Include customers
-- who have no successful deposits, with a total of zero.
--
-- Q06 [Medium | HAVING]
-- Find customers whose combined account balance is greater than 50,000.
--
-- Q07 [Medium | LEFT JOIN, NULL]
-- Find customers who do not have any bank account.
--
-- Q08 [Medium | Conditional aggregation]
-- For each account, calculate successful deposit total and successful withdrawal total.
--
-- Q09 [Medium | CTE]
-- Find the three customers with the highest total successful transaction amount
-- (deposits and withdrawals both count as transaction activity).
--
-- Q10 [Hard | Window function]
-- Rank accounts by balance within each account type. Highest balance should rank first.
--
-- Q11 [Hard | Window function, date]
-- For every successful transaction, show its amount and the running total for that
-- account in transaction-date order.
--
-- Q12 [Hard | Anti-join]
-- Find active accounts that have no successful transactions.
--
-- Q13 [Hard | CTE, aggregation]
-- Find each city's total balance across active accounts and return cities with
-- active-account balance above 50,000.
--
-- Q14 [Hard | ROW_NUMBER]
-- Return the latest successful transaction for each account. Keep only one row per account.
--
-- Q15 [Challenge | business logic]
-- For each customer, show total balance in active accounts, number of successful
-- transactions, and total amount of successful deposits. Keep customers with at least
-- one active account, and sort by successful deposit amount descending.

-- =========================================================
-- 4. ANSWER KEY — CHECK AFTER TRYING
-- =========================================================

-- A01
-- SELECT account_id, customer_id, account_type, balance
-- FROM bank_accounts
-- WHERE status = 'ACTIVE' AND balance > 20000
-- ORDER BY balance DESC;

-- A02
-- SELECT city, COUNT(*) AS customer_count
-- FROM bank_customers
-- GROUP BY city
-- ORDER BY customer_count DESC, city;

-- A03
-- SELECT a.account_id, c.customer_name, a.account_type, a.balance
-- FROM bank_accounts AS a
-- JOIN bank_customers AS c ON c.customer_id = a.customer_id
-- ORDER BY a.account_id;

-- A04
-- SELECT status, COUNT(*) AS transaction_count, SUM(amount) AS total_amount
-- FROM bank_transactions
-- GROUP BY status
-- ORDER BY status;

-- A05
-- SELECT c.customer_id, c.customer_name,
--        COALESCE(SUM(t.amount), 0) AS successful_deposit_total
-- FROM bank_customers AS c
-- LEFT JOIN bank_accounts AS a ON a.customer_id = c.customer_id
-- LEFT JOIN bank_transactions AS t
--   ON t.account_id = a.account_id
--  AND t.transaction_type = 'DEPOSIT'
--  AND t.status = 'SUCCESS'
-- GROUP BY c.customer_id, c.customer_name
-- ORDER BY successful_deposit_total DESC, c.customer_id;

-- A06
-- SELECT c.customer_id, c.customer_name, SUM(a.balance) AS total_balance
-- FROM bank_customers AS c
-- JOIN bank_accounts AS a ON a.customer_id = c.customer_id
-- GROUP BY c.customer_id, c.customer_name
-- HAVING SUM(a.balance) > 50000
-- ORDER BY total_balance DESC;

-- A07
-- SELECT c.customer_id, c.customer_name
-- FROM bank_customers AS c
-- LEFT JOIN bank_accounts AS a ON a.customer_id = c.customer_id
-- WHERE a.account_id IS NULL;

-- A08
-- SELECT a.account_id,
--        COALESCE(SUM(CASE WHEN t.transaction_type = 'DEPOSIT'
--                           AND t.status = 'SUCCESS' THEN t.amount ELSE 0 END), 0)
--          AS successful_deposits,
--        COALESCE(SUM(CASE WHEN t.transaction_type = 'WITHDRAWAL'
--                           AND t.status = 'SUCCESS' THEN t.amount ELSE 0 END), 0)
--          AS successful_withdrawals
-- FROM bank_accounts AS a
-- LEFT JOIN bank_transactions AS t ON t.account_id = a.account_id
-- GROUP BY a.account_id
-- ORDER BY a.account_id;

-- A09
-- WITH customer_activity AS (
--   SELECT c.customer_id, c.customer_name, SUM(t.amount) AS activity_amount
--   FROM bank_customers AS c
--   JOIN bank_accounts AS a ON a.customer_id = c.customer_id
--   JOIN bank_transactions AS t ON t.account_id = a.account_id
--   WHERE t.status = 'SUCCESS'
--   GROUP BY c.customer_id, c.customer_name
-- )
-- SELECT customer_id, customer_name, activity_amount
-- FROM customer_activity
-- ORDER BY activity_amount DESC, customer_id
-- FETCH FIRST 3 ROWS ONLY;
-- Note: use LIMIT 3 in PostgreSQL/MySQL, or FETCH FIRST 3 ROWS ONLY in many other engines.

-- A10
-- SELECT account_id, customer_id, account_type, balance,
--        RANK() OVER (PARTITION BY account_type ORDER BY balance DESC) AS balance_rank
-- FROM bank_accounts
-- ORDER BY account_type, balance_rank;

-- A11
-- SELECT transaction_id, account_id, transaction_date, amount,
--        SUM(amount) OVER (
--          PARTITION BY account_id
--          ORDER BY transaction_date, transaction_id
--          ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
--        ) AS running_transaction_total
-- FROM bank_transactions
-- WHERE status = 'SUCCESS'
-- ORDER BY account_id, transaction_date, transaction_id;

-- A12
-- SELECT a.account_id, a.customer_id, a.balance
-- FROM bank_accounts AS a
-- WHERE a.status = 'ACTIVE'
--   AND NOT EXISTS (
--     SELECT 1
--     FROM bank_transactions AS t
--     WHERE t.account_id = a.account_id
--       AND t.status = 'SUCCESS'
--   );

-- A13
-- SELECT c.city, SUM(a.balance) AS active_balance
-- FROM bank_customers AS c
-- JOIN bank_accounts AS a ON a.customer_id = c.customer_id
-- WHERE a.status = 'ACTIVE'
-- GROUP BY c.city
-- HAVING SUM(a.balance) > 50000
-- ORDER BY active_balance DESC;

-- A14
-- WITH ranked_transactions AS (
--   SELECT t.*,
--          ROW_NUMBER() OVER (
--            PARTITION BY account_id
--            ORDER BY transaction_date DESC, transaction_id DESC
--          ) AS row_num
--   FROM bank_transactions AS t
--   WHERE status = 'SUCCESS'
-- )
-- SELECT transaction_id, account_id, transaction_date, transaction_type, amount
-- FROM ranked_transactions
-- WHERE row_num = 1
-- ORDER BY account_id;

-- A15
-- SELECT c.customer_id,
--        c.customer_name,
--        SUM(DISTINCT CASE WHEN a.status = 'ACTIVE' THEN a.balance END) AS active_balance,
--        COUNT(DISTINCT CASE WHEN t.status = 'SUCCESS' THEN t.transaction_id END)
--          AS successful_transaction_count,
--        COALESCE(SUM(CASE WHEN t.status = 'SUCCESS'
--                           AND t.transaction_type = 'DEPOSIT'
--                          THEN t.amount ELSE 0 END), 0) AS successful_deposit_total
-- FROM bank_customers AS c
-- JOIN bank_accounts AS a ON a.customer_id = c.customer_id
-- LEFT JOIN bank_transactions AS t ON t.account_id = a.account_id
-- GROUP BY c.customer_id, c.customer_name
-- HAVING SUM(CASE WHEN a.status = 'ACTIVE' THEN 1 ELSE 0 END) > 0
-- ORDER BY successful_deposit_total DESC, c.customer_id;
--
-- Important learning note for A15:
-- SUM(DISTINCT balance) can undercount if a customer has two active accounts with
-- the same balance. A safer production pattern is to aggregate accounts and
-- transactions separately in CTEs, then join the per-customer results.
-- Production-safe alternative:
-- WITH active_balances AS (
--   SELECT customer_id, SUM(balance) AS active_balance
--   FROM bank_accounts
--   WHERE status = 'ACTIVE'
--   GROUP BY customer_id
-- ),
-- transaction_metrics AS (
--   SELECT a.customer_id,
--          COUNT(CASE WHEN t.status = 'SUCCESS' THEN 1 END) AS successful_transaction_count,
--          COALESCE(SUM(CASE WHEN t.status = 'SUCCESS'
--                             AND t.transaction_type = 'DEPOSIT'
--                            THEN t.amount ELSE 0 END), 0) AS successful_deposit_total
--   FROM bank_accounts AS a
--   LEFT JOIN bank_transactions AS t ON t.account_id = a.account_id
--   GROUP BY a.customer_id
-- )
-- SELECT c.customer_id, c.customer_name, ab.active_balance,
--        tm.successful_transaction_count, tm.successful_deposit_total
-- FROM bank_customers AS c
-- JOIN active_balances AS ab ON ab.customer_id = c.customer_id
-- JOIN transaction_metrics AS tm ON tm.customer_id = c.customer_id
-- ORDER BY tm.successful_deposit_total DESC, c.customer_id;

-- END OF PRACTICE FILE
