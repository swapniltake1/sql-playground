/*
===============================================================================
Practice: FX As-Of Joins, Stale-Rate Controls & Multi-Currency Valuation
Dialect: PostgreSQL 14+
Run: psql -f daily/2026-10-31-0458-fx-asof-valuation.sql

Scenario
--------
A payments platform stores transactions in their original currencies. Finance
needs reproducible USD reporting using the latest approved FX observation on or
before each transaction date. Providers can publish competing observations;
weekends and holidays can leave rates stale; some currencies have no quote.

Rate convention: 1 unit of base_ccy = rate units of quote_ccy.
All sample rates quote into USD. Amounts are signed (refunds are negative).
===============================================================================
*/

DROP VIEW IF EXISTS canonical_fx_rates;
DROP TABLE IF EXISTS fx_transactions;
DROP TABLE IF EXISTS fx_rate_observations;

CREATE TABLE fx_rate_observations (
    rate_id           BIGINT PRIMARY KEY,
    base_ccy          CHAR(3) NOT NULL,
    quote_ccy         CHAR(3) NOT NULL,
    rate_date         DATE NOT NULL,
    rate              NUMERIC(18, 8) NOT NULL CHECK (rate > 0),
    provider          TEXT NOT NULL,
    provider_priority INTEGER NOT NULL, -- lower number is preferred
    observed_at       TIMESTAMP NOT NULL,
    CHECK (base_ccy <> quote_ccy)
);

CREATE TABLE fx_transactions (
    transaction_id BIGINT PRIMARY KEY,
    account_id     BIGINT NOT NULL,
    booked_at      TIMESTAMP NOT NULL,
    currency       CHAR(3) NOT NULL,
    amount         NUMERIC(18, 2) NOT NULL,
    status         TEXT NOT NULL CHECK (status IN ('POSTED', 'PENDING', 'REVERSED'))
);

INSERT INTO fx_rate_observations
(rate_id, base_ccy, quote_ccy, rate_date, rate, provider, provider_priority, observed_at)
VALUES
-- EUR has competing provider observations on 29 Oct; the BANK quote is an outlier.
(1, 'EUR', 'USD', DATE '2026-10-28', 1.16000000, 'ECB',  1, TIMESTAMP '2026-10-28 16:05:00'),
(2, 'EUR', 'USD', DATE '2026-10-29', 1.16500000, 'ECB',  1, TIMESTAMP '2026-10-29 16:05:00'),
(3, 'EUR', 'USD', DATE '2026-10-29', 1.25000000, 'BANK', 2, TIMESTAMP '2026-10-29 17:10:00'),
(4, 'EUR', 'USD', DATE '2026-10-30', 1.17000000, 'ECB',  1, TIMESTAMP '2026-10-30 16:05:00'),
(5, 'GBP', 'USD', DATE '2026-10-28', 1.34000000, 'ECB',  1, TIMESTAMP '2026-10-28 16:05:00'),
(6, 'GBP', 'USD', DATE '2026-10-30', 1.35000000, 'ECB',  1, TIMESTAMP '2026-10-30 16:05:00'),
(7, 'INR', 'USD', DATE '2026-10-27', 0.01190000, 'ECB', 1, TIMESTAMP '2026-10-27 16:05:00'),
(8, 'INR', 'USD', DATE '2026-10-29', 0.01200000, 'ECB', 1, TIMESTAMP '2026-10-29 16:05:00'),
(9, 'JPY', 'USD', DATE '2026-10-25', 0.00670000, 'ECB', 1, TIMESTAMP '2026-10-25 16:05:00'),
(10,'CAD', 'USD', DATE '2026-10-30', 0.72000000, 'ECB', 1, TIMESTAMP '2026-10-30 16:05:00');

INSERT INTO fx_transactions
(transaction_id, account_id, booked_at, currency, amount, status)
VALUES
(1001, 501, TIMESTAMP '2026-10-29 09:15:00', 'EUR',   100.00, 'POSTED'),
(1002, 501, TIMESTAMP '2026-10-30 11:30:00', 'EUR',   250.00, 'POSTED'),
(1003, 502, TIMESTAMP '2026-10-31 08:10:00', 'EUR',    50.00, 'POSTED'),
(1004, 502, TIMESTAMP '2026-10-31 09:20:00', 'GBP',   100.00, 'POSTED'),
(1005, 503, TIMESTAMP '2026-10-31 10:00:00', 'INR', 10000.00, 'POSTED'),
(1006, 503, TIMESTAMP '2026-10-31 10:15:00', 'JPY', 10000.00, 'POSTED'),
(1007, 504, TIMESTAMP '2026-10-31 11:00:00', 'AUD',   100.00, 'POSTED'), -- no quote
(1008, 504, TIMESTAMP '2026-10-31 12:00:00', 'USD',   500.00, 'POSTED'), -- identity rate
(1009, 502, TIMESTAMP '2026-10-31 13:00:00', 'GBP',   -20.00, 'POSTED'), -- refund
(1010, 502, TIMESTAMP '2026-10-31 14:00:00', 'GBP',    50.00, 'PENDING'); -- exclude

/*
Q1. Canonicalize provider observations.
Problem: one currency/date can have several provider rows and later replays.
Return exactly one approved observation per pair/date, preferring the lowest
provider_priority and then the latest observation from that provider.

Solution: DISTINCT ON is concise in PostgreSQL. The ORDER BY must begin with
the DISTINCT ON keys and fully define the winner for deterministic results.
*/
CREATE OR REPLACE VIEW canonical_fx_rates AS
SELECT DISTINCT ON (base_ccy, quote_ccy, rate_date)
       rate_id, base_ccy, quote_ccy, rate_date, rate,
       provider, provider_priority, observed_at
FROM fx_rate_observations
ORDER BY base_ccy, quote_ccy, rate_date,
         provider_priority ASC, observed_at DESC, rate_id DESC;

-- Q1 check: EUR on 29 Oct should select the ECB rate 1.165, not BANK 1.250.
SELECT base_ccy, rate_date, rate, provider
FROM canonical_fx_rates
WHERE base_ccy = 'EUR'
ORDER BY rate_date;

/*
Q2. Perform a transaction-date as-of join.
Problem: select the latest canonical rate whose rate_date is not after the
transaction's booking date. Preserve transactions even when no rate exists.
USD is the reporting currency and uses an identity rate of 1.
*/
WITH valued AS (
    SELECT t.transaction_id, t.account_id, t.booked_at::date AS txn_date,
           t.currency, t.amount, t.status,
           CASE WHEN t.currency = 'USD' THEN 1::NUMERIC
                ELSE r.rate END AS usd_rate,
           CASE WHEN t.currency = 'USD' THEN t.booked_at::date
                ELSE r.rate_date END AS applied_rate_date,
           r.provider
    FROM fx_transactions AS t
    LEFT JOIN LATERAL (
        SELECT c.rate, c.rate_date, c.provider
        FROM canonical_fx_rates AS c
        WHERE c.base_ccy = t.currency
          AND c.quote_ccy = 'USD'
          AND c.rate_date <= t.booked_at::date
        ORDER BY c.rate_date DESC
        LIMIT 1
    ) AS r ON t.currency <> 'USD'
    WHERE t.status = 'POSTED'
)
SELECT transaction_id, account_id, txn_date, currency, amount,
       usd_rate, applied_rate_date,
       ROUND(amount * usd_rate, 2) AS amount_usd,
       provider
FROM valued
ORDER BY transaction_id;

/*
Q3. Detect missing and stale rates.
Problem: finance accepts a rate only when it is no more than two calendar days
older than the transaction date. Return missing/stale exceptions separately.
Do not silently convert a missing rate to zero.
*/
WITH rate_lookup AS (
    SELECT t.transaction_id, t.currency, t.booked_at::date AS txn_date,
           CASE WHEN t.currency = 'USD' THEN 1::NUMERIC ELSE r.rate END AS rate,
           CASE WHEN t.currency = 'USD' THEN t.booked_at::date ELSE r.rate_date END AS rate_date
    FROM fx_transactions AS t
    LEFT JOIN LATERAL (
        SELECT rate, rate_date
        FROM canonical_fx_rates
        WHERE base_ccy = t.currency
          AND quote_ccy = 'USD'
          AND rate_date <= t.booked_at::date
        ORDER BY rate_date DESC
        LIMIT 1
    ) AS r ON t.currency <> 'USD'
    WHERE t.status = 'POSTED'
)
SELECT transaction_id, currency, txn_date, rate_date,
       txn_date - rate_date AS rate_age_days,
       CASE
         WHEN rate IS NULL THEN 'MISSING_RATE'
         WHEN txn_date - rate_date > 2 THEN 'STALE_RATE'
       END AS exception_type
FROM rate_lookup
WHERE rate IS NULL OR txn_date - rate_date > 2
ORDER BY transaction_id;

/*
Q4. Build a daily account/currency valuation.
Problem: calculate original-currency net movement and its USD equivalent at
the transaction-date rate. Keep the grouping grain explicit.
*/
WITH valued AS (
    SELECT t.account_id, t.booked_at::date AS txn_date, t.currency,
           t.amount,
           CASE WHEN t.currency = 'USD' THEN 1::NUMERIC ELSE r.rate END AS usd_rate
    FROM fx_transactions AS t
    LEFT JOIN LATERAL (
        SELECT rate
        FROM canonical_fx_rates
        WHERE base_ccy = t.currency
          AND quote_ccy = 'USD'
          AND rate_date <= t.booked_at::date
        ORDER BY rate_date DESC
        LIMIT 1
    ) AS r ON t.currency <> 'USD'
    WHERE t.status = 'POSTED'
)
SELECT account_id, txn_date, currency,
       SUM(amount) AS net_amount_native,
       CASE WHEN COUNT(usd_rate) = COUNT(*)
            THEN ROUND(SUM(amount * usd_rate), 2)
       END AS net_amount_usd,
       COUNT(*) FILTER (WHERE usd_rate IS NULL) AS unvalued_rows
FROM valued
GROUP BY account_id, txn_date, currency
ORDER BY account_id, txn_date, currency;

/*
Q5. Revalue month-end open positions.
Problem: net all posted movements through 31 Oct by account/currency, then use
the latest canonical rate on or before month-end. This differs from summing
transaction-date USD values: month-end revaluation applies one closing rate
to the remaining native-currency position.
*/
WITH positions AS (
    SELECT account_id, currency, SUM(amount) AS closing_native_balance
    FROM fx_transactions
    WHERE status = 'POSTED'
      AND booked_at < TIMESTAMP '2026-11-01 00:00:00'
    GROUP BY account_id, currency
)
SELECT p.account_id, p.currency, p.closing_native_balance,
       CASE WHEN p.currency = 'USD' THEN 1::NUMERIC ELSE r.rate END AS closing_rate,
       CASE WHEN p.currency = 'USD' THEN ROUND(p.closing_native_balance, 2)
            WHEN r.rate IS NOT NULL THEN ROUND(p.closing_native_balance * r.rate, 2)
       END AS closing_balance_usd,
       r.rate_date AS applied_rate_date
FROM positions AS p
LEFT JOIN LATERAL (
    SELECT rate, rate_date
    FROM canonical_fx_rates
    WHERE base_ccy = p.currency
      AND quote_ccy = 'USD'
      AND rate_date <= DATE '2026-10-31'
    ORDER BY rate_date DESC
    LIMIT 1
) AS r ON p.currency <> 'USD'
ORDER BY p.account_id, p.currency;

/*
Q6. Detect provider dispersion before canonicalization.
Problem: identify pair/date groups where provider observations differ by more
than 1% of their average. This is a control, not an instruction to average
quotes: provider methodology and priority still determine the approved rate.
*/
SELECT base_ccy, quote_ccy, rate_date,
       MIN(rate) AS min_rate, MAX(rate) AS max_rate,
       ROUND(100 * (MAX(rate) - MIN(rate)) / NULLIF(AVG(rate), 0), 3) AS dispersion_pct,
       COUNT(DISTINCT provider) AS provider_count
FROM fx_rate_observations
GROUP BY base_ccy, quote_ccy, rate_date
HAVING (MAX(rate) - MIN(rate)) / NULLIF(AVG(rate), 0) > 0.01
ORDER BY rate_date, base_ccy;

/*
Q7. Monitor canonical daily rate jumps.
Problem: calculate day-over-day percentage changes for each currency. A gap in
calendar dates is allowed; this compares consecutive available observations.
*/
WITH changes AS (
    SELECT base_ccy, quote_ccy, rate_date, rate,
           LAG(rate) OVER (
               PARTITION BY base_ccy, quote_ccy
               ORDER BY rate_date
           ) AS previous_rate
    FROM canonical_fx_rates
)
SELECT base_ccy, rate_date, previous_rate, rate,
       ROUND(100 * (rate / NULLIF(previous_rate, 0) - 1), 3) AS change_pct
FROM changes
WHERE previous_rate IS NOT NULL
  AND ABS(rate / NULLIF(previous_rate, 0) - 1) > 0.005
ORDER BY base_ccy, rate_date;

/*
Q8. Performance lab: index the as-of lookup and posted transaction scan.
These are candidate indexes. Benchmark against representative data volumes;
the tiny practice dataset will not demonstrate meaningful speedups.
*/
-- CREATE INDEX ix_fx_asof_lookup
--     ON fx_rate_observations
--        (base_ccy, quote_ccy, rate_date DESC,
--         provider_priority, observed_at DESC);
--
-- CREATE INDEX ix_fx_txn_posted_currency_booked
--     ON fx_transactions (currency, booked_at, account_id)
--     WHERE status = 'POSTED';
--
-- EXPLAIN (ANALYZE, BUFFERS)
-- SELECT t.transaction_id, r.rate
-- FROM fx_transactions AS t
-- LEFT JOIN LATERAL (
--     SELECT rate
--     FROM canonical_fx_rates
--     WHERE base_ccy = t.currency
--       AND quote_ccy = 'USD'
--       AND rate_date <= t.booked_at::date
--     ORDER BY rate_date DESC
--     LIMIT 1
-- ) AS r ON t.currency <> 'USD'
-- WHERE t.status = 'POSTED';

-- Expected spot checks:
-- * Q1: EUR/2026-10-29 selects ECB at 1.165.
-- * Q3: JPY is stale (6 days); AUD has no rate; USD is exempt.
-- * Q6: EUR/2026-10-29 flags provider dispersion because BANK is 1.250.
-- * Q5: month-end valuation is based on closing native balances, not daily FX.
--
-- Performance notes:
-- 1. Keep the as-of predicate sargable: rate_date <= transaction_date.
-- 2. The lateral lookup benefits from an index beginning with currency pair
--    and descending rate_date; verify the actual plan before retaining it.
-- 3. Canonicalization is a separate logical step. For large histories, persist
--    approved daily rates in a compact table rather than repeatedly sorting
--    raw provider observations in a view.
-- 4. Do not coalesce missing FX rates to zero. Route them to an exception queue.
-- 5. Define the business calendar, rate cutoff, provider priority, and stale
--    threshold centrally; they are accounting policy, not query constants.
