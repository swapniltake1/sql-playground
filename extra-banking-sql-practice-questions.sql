-- SQL PLAYGROUND: EXTRA BANKING SQL PRACTICE
-- Questions Q16-Q40. Run banking-sql-practice-questions.sql first to create and seed the tables.
-- Dialect: PostgreSQL. Most examples are adaptable to other SQL engines.
-- Try the questions before checking the answer key at the bottom.

-- =========================================================
-- QUESTIONS
-- =========================================================
-- Q16 [Easy] List distinct customer cities in alphabetical order.
-- Q17 [Easy] Find transactions from 2024-09-05 through 2024-09-12 inclusive.
-- Q18 [Easy] Find customer names containing the letter 'a', case-insensitively.
-- Q19 [Easy] Count accounts by account status.
-- Q20 [Medium] Calculate the total balance by account type for ACTIVE accounts only.
-- Q21 [Medium] Label account balances HIGH (>= 50000), MEDIUM (>= 20000), or LOW.
-- Q22 [Medium] Find accounts whose balance is above the average account balance.
-- Q23 [Medium] Find customers who have an account but have no successful transactions.
-- Q24 [Medium] Show each customer and their account count, including customers with zero accounts.
-- Q25 [Medium] Count successful transactions per transaction date.
-- Q26 [Hard] Return all accounts tied for the second-highest distinct balance.
-- Q27 [Hard] For each successful transaction, show the previous successful transaction amount for that account.
-- Q28 [Hard] Show each account's percentage contribution to the total balance of all accounts.
-- Q29 [Hard] Calculate the sum of the current and immediately previous successful transaction per account.
-- Q30 [Hard] For each customer, calculate successful deposits, successful withdrawals, and net transaction flow.
-- Q31 [Hard] Find customers who signed up before 2024-06-01 and opened an account after 2024-06-01.
-- Q32 [Challenge] Return the two highest-balance accounts for each account type.
-- Q33 [Challenge] Find transactions over 5000 that did not succeed.
-- Q34 [Challenge] Show active-account balance by city and each city's percentage of total active balance.
-- Q35 [Challenge] Compare each account's stored balance with its net successful transaction flow.
-- Q36 [Easy] Find the earliest and latest transaction dates in the dataset.
-- Q37 [Medium] Find customers with at least two accounts.
-- Q38 [Medium] Find the average successful transaction amount by transaction type.
-- Q39 [Hard] Calculate each customer's most recent successful transaction date.
-- Q40 [Challenge] Return the top customer by successful deposit amount in each city. Return ties.

-- =========================================================
-- ANSWER KEY
-- =========================================================

-- A16
-- SELECT DISTINCT city FROM bank_customers ORDER BY city;

-- A17
-- SELECT *
-- FROM bank_transactions
-- WHERE transaction_date >= DATE '2024-09-05'
--   AND transaction_date < DATE '2024-09-13'
-- ORDER BY transaction_date, transaction_id;

-- A18 (PostgreSQL)
-- SELECT customer_id, customer_name
-- FROM bank_customers
-- WHERE customer_name ILIKE '%a%'
-- ORDER BY customer_name;
-- Portable alternative: WHERE LOWER(customer_name) LIKE '%a%'

-- A19
-- SELECT status, COUNT(*) AS account_count
-- FROM bank_accounts
-- GROUP BY status
-- ORDER BY status;

-- A20
-- SELECT account_type, SUM(balance) AS active_balance
-- FROM bank_accounts
-- WHERE status = 'ACTIVE'
-- GROUP BY account_type
-- ORDER BY active_balance DESC;

-- A21
-- SELECT account_id, balance,
--        CASE WHEN balance >= 50000 THEN 'HIGH'
--             WHEN balance >= 20000 THEN 'MEDIUM'
--             ELSE 'LOW' END AS balance_category
-- FROM bank_accounts
-- ORDER BY balance DESC;

-- A22
-- SELECT account_id, customer_id, balance
-- FROM bank_accounts
-- WHERE balance > (SELECT AVG(balance) FROM bank_accounts)
-- ORDER BY balance DESC;

-- A23
-- SELECT c.customer_id, c.customer_name
-- FROM bank_customers c
-- WHERE EXISTS (
--   SELECT 1 FROM bank_accounts a WHERE a.customer_id = c.customer_id
-- )
-- AND NOT EXISTS (
--   SELECT 1
--   FROM bank_accounts a
--   JOIN bank_transactions t ON t.account_id = a.account_id
--   WHERE a.customer_id = c.customer_id AND t.status = 'SUCCESS'
-- );

-- A24
-- SELECT c.customer_id, c.customer_name, COUNT(a.account_id) AS account_count
-- FROM bank_customers c
-- LEFT JOIN bank_accounts a ON a.customer_id = c.customer_id
-- GROUP BY c.customer_id, c.customer_name
-- ORDER BY account_count DESC, c.customer_id;

-- A25
-- SELECT transaction_date, COUNT(*) AS successful_count
-- FROM bank_transactions
-- WHERE status = 'SUCCESS'
-- GROUP BY transaction_date
-- ORDER BY transaction_date;

-- A26
-- WITH ranked AS (
--   SELECT account_id, balance, DENSE_RANK() OVER (ORDER BY balance DESC) AS rnk
--   FROM bank_accounts
-- )
-- SELECT account_id, balance FROM ranked WHERE rnk = 2 ORDER BY account_id;

-- A27
-- SELECT transaction_id, account_id, transaction_date, amount,
--        LAG(amount) OVER (
--          PARTITION BY account_id ORDER BY transaction_date, transaction_id
--        ) AS previous_successful_amount
-- FROM bank_transactions
-- WHERE status = 'SUCCESS'
-- ORDER BY account_id, transaction_date, transaction_id;

-- A28
-- SELECT account_id, customer_id, balance,
--        ROUND(100.0 * balance / NULLIF(SUM(balance) OVER (), 0), 2) AS percent_of_total
-- FROM bank_accounts
-- ORDER BY balance DESC;

-- A29
-- SELECT transaction_id, account_id, transaction_date, amount,
--        SUM(amount) OVER (
--          PARTITION BY account_id
--          ORDER BY transaction_date, transaction_id
--          ROWS BETWEEN 1 PRECEDING AND CURRENT ROW
--        ) AS two_transaction_total
-- FROM bank_transactions
-- WHERE status = 'SUCCESS'
-- ORDER BY account_id, transaction_date, transaction_id;

-- A30
-- SELECT c.customer_id, c.customer_name,
--   COALESCE(SUM(CASE WHEN t.status = 'SUCCESS' AND t.transaction_type = 'DEPOSIT'
--                     THEN t.amount ELSE 0 END), 0) AS deposits,
--   COALESCE(SUM(CASE WHEN t.status = 'SUCCESS' AND t.transaction_type = 'WITHDRAWAL'
--                     THEN t.amount ELSE 0 END), 0) AS withdrawals,
--   COALESCE(SUM(CASE
--     WHEN t.status = 'SUCCESS' AND t.transaction_type = 'DEPOSIT' THEN t.amount
--     WHEN t.status = 'SUCCESS' AND t.transaction_type = 'WITHDRAWAL' THEN -t.amount
--     ELSE 0 END), 0) AS net_flow
-- FROM bank_customers c
-- LEFT JOIN bank_accounts a ON a.customer_id = c.customer_id
-- LEFT JOIN bank_transactions t ON t.account_id = a.account_id
-- GROUP BY c.customer_id, c.customer_name
-- ORDER BY c.customer_id;

-- A31
-- SELECT DISTINCT c.customer_id, c.customer_name
-- FROM bank_customers c
-- JOIN bank_accounts a ON a.customer_id = c.customer_id
-- WHERE c.signup_date < DATE '2024-06-01'
--   AND a.opened_date > DATE '2024-06-01'
-- ORDER BY c.customer_id;

-- A32
-- WITH ranked AS (
--   SELECT account_id, customer_id, account_type, balance,
--          ROW_NUMBER() OVER (
--            PARTITION BY account_type ORDER BY balance DESC, account_id
--          ) AS rn
--   FROM bank_accounts
-- )
-- SELECT account_id, customer_id, account_type, balance
-- FROM ranked WHERE rn <= 2
-- ORDER BY account_type, balance DESC;

-- A33
-- SELECT transaction_id, account_id, amount, status
-- FROM bank_transactions
-- WHERE amount > 5000 AND status <> 'SUCCESS'
-- ORDER BY amount DESC;

-- A34
-- WITH city_balances AS (
--   SELECT c.city, SUM(a.balance) AS active_balance
--   FROM bank_customers c
--   JOIN bank_accounts a ON a.customer_id = c.customer_id
--   WHERE a.status = 'ACTIVE'
--   GROUP BY c.city
-- )
-- SELECT city, active_balance,
--        ROUND(100.0 * active_balance / NULLIF(SUM(active_balance) OVER (), 0), 2)
--          AS percent_of_active_balance
-- FROM city_balances
-- ORDER BY active_balance DESC;

-- A35
-- SELECT a.account_id, a.balance AS stored_balance,
--        COALESCE(SUM(CASE
--          WHEN t.status = 'SUCCESS' AND t.transaction_type = 'DEPOSIT' THEN t.amount
--          WHEN t.status = 'SUCCESS' AND t.transaction_type = 'WITHDRAWAL' THEN -t.amount
--          ELSE 0 END), 0) AS net_successful_flow
-- FROM bank_accounts a
-- LEFT JOIN bank_transactions t ON t.account_id = a.account_id
-- GROUP BY a.account_id, a.balance
-- ORDER BY a.account_id;
-- Note: this is a comparison metric, not a full reconciliation, because opening balances
-- and other balance adjustments are not represented in this sample dataset.

-- A36
-- SELECT MIN(transaction_date) AS earliest_date, MAX(transaction_date) AS latest_date
-- FROM bank_transactions;

-- A37
-- SELECT c.customer_id, c.customer_name, COUNT(a.account_id) AS account_count
-- FROM bank_customers c
-- JOIN bank_accounts a ON a.customer_id = c.customer_id
-- GROUP BY c.customer_id, c.customer_name
-- HAVING COUNT(a.account_id) >= 2
-- ORDER BY account_count DESC, c.customer_id;

-- A38
-- SELECT transaction_type, AVG(amount) AS average_successful_amount
-- FROM bank_transactions
-- WHERE status = 'SUCCESS'
-- GROUP BY transaction_type
-- ORDER BY transaction_type;

-- A39
-- SELECT c.customer_id, c.customer_name, MAX(t.transaction_date) AS latest_successful_date
-- FROM bank_customers c
-- JOIN bank_accounts a ON a.customer_id = c.customer_id
-- JOIN bank_transactions t ON t.account_id = a.account_id
-- WHERE t.status = 'SUCCESS'
-- GROUP BY c.customer_id, c.customer_name
-- ORDER BY latest_successful_date DESC;

-- A40
-- WITH customer_deposits AS (
--   SELECT c.customer_id, c.customer_name, c.city,
--          COALESCE(SUM(CASE WHEN t.status = 'SUCCESS'
--                             AND t.transaction_type = 'DEPOSIT'
--                            THEN t.amount ELSE 0 END), 0) AS deposit_total
--   FROM bank_customers c
--   LEFT JOIN bank_accounts a ON a.customer_id = c.customer_id
--   LEFT JOIN bank_transactions t ON t.account_id = a.account_id
--   GROUP BY c.customer_id, c.customer_name, c.city
-- ),
-- ranked AS (
--   SELECT *, RANK() OVER (PARTITION BY city ORDER BY deposit_total DESC) AS city_rank
--   FROM customer_deposits
-- )
-- SELECT customer_id, customer_name, city, deposit_total
-- FROM ranked
-- WHERE city_rank = 1
-- ORDER BY city, customer_name;

-- END OF EXTRA PRACTICE
