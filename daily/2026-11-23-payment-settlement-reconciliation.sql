-- Daily SQL Practice — 2026-11-23
-- Topic: Payment Settlement Reconciliation & Allocation
-- PostgreSQL 14+
-- Run this file independently. Answers are provided as commented reference queries.

DROP TABLE IF EXISTS settlement_allocations;
DROP TABLE IF EXISTS settlement_lines;
DROP TABLE IF EXISTS payment_events;
DROP TABLE IF EXISTS bank_settlements;
DROP TABLE IF EXISTS payment_orders;

CREATE TABLE payment_orders (
    order_id BIGINT PRIMARY KEY,
    customer_id BIGINT NOT NULL,
    order_ts TIMESTAMPTZ NOT NULL,
    currency CHAR(3) NOT NULL,
    expected_amount NUMERIC(12,2) NOT NULL CHECK (expected_amount >= 0)
);

CREATE TABLE payment_events (
    event_id BIGINT PRIMARY KEY,
    order_id BIGINT NOT NULL REFERENCES payment_orders(order_id),
    provider_ref TEXT NOT NULL,
    event_type TEXT NOT NULL CHECK (event_type IN ('CAPTURE','REFUND','VOID')),
    event_status TEXT NOT NULL CHECK (event_status IN ('SUCCEEDED','FAILED','PENDING')),
    amount NUMERIC(12,2) NOT NULL CHECK (amount >= 0),
    event_ts TIMESTAMPTZ NOT NULL,
    ingested_at TIMESTAMPTZ NOT NULL,
    UNIQUE (provider_ref, event_type, event_id)
);

CREATE TABLE bank_settlements (
    settlement_id BIGINT PRIMARY KEY,
    provider_ref TEXT NOT NULL,
    currency CHAR(3) NOT NULL,
    gross_amount NUMERIC(12,2) NOT NULL,
    fee_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
    net_amount NUMERIC(12,2) NOT NULL,
    settled_at TIMESTAMPTZ NOT NULL,
    bank_batch_id TEXT NOT NULL
);

CREATE TABLE settlement_lines (
    line_id BIGINT PRIMARY KEY,
    settlement_id BIGINT NOT NULL REFERENCES bank_settlements(settlement_id),
    provider_ref TEXT NOT NULL,
    currency CHAR(3) NOT NULL,
    line_amount NUMERIC(12,2) NOT NULL,
    line_type TEXT NOT NULL CHECK (line_type IN ('CAPTURE','REFUND','FEE','ADJUSTMENT'))
);

CREATE TABLE settlement_allocations (
    settlement_id BIGINT NOT NULL REFERENCES bank_settlements(settlement_id),
    event_id BIGINT NOT NULL REFERENCES payment_events(event_id),
    allocated_amount NUMERIC(12,2) NOT NULL,
    PRIMARY KEY (settlement_id, event_id)
);

INSERT INTO payment_orders VALUES
(1001, 501, '2026-11-20 10:00+00', 'INR', 1200.00),
(1002, 502, '2026-11-20 11:00+00', 'INR', 850.00),
(1003, 503, '2026-11-21 09:00+00', 'INR', 1500.00),
(1004, 504, '2026-11-21 12:00+00', 'USD', 50.00);

INSERT INTO payment_events VALUES
(1,1001,'PAY-A','CAPTURE','SUCCEEDED',1200,'2026-11-20 10:02+00','2026-11-20 10:03+00'),
(2,1002,'PAY-B','CAPTURE','SUCCEEDED',850,'2026-11-20 11:05+00','2026-11-20 11:06+00'),
(3,1003,'PAY-C','CAPTURE','SUCCEEDED',1500,'2026-11-21 09:05+00','2026-11-21 09:06+00'),
(4,1001,'PAY-A-R1','REFUND','SUCCEEDED',200,'2026-11-21 08:00+00','2026-11-21 08:01+00'),
(5,1004,'PAY-D','CAPTURE','SUCCEEDED',50,'2026-11-21 12:05+00','2026-11-21 12:06+00'),
(6,1002,'PAY-B-RETRY','CAPTURE','FAILED',850,'2026-11-20 11:04+00','2026-11-20 11:07+00');

INSERT INTO bank_settlements VALUES
(9001,'PAY-A','INR',1200,24,1176,'2026-11-21 02:00+00','BATCH-01'),
(9002,'PAY-B','INR',850,17,833,'2026-11-21 02:00+00','BATCH-01'),
(9003,'PAY-C','INR',1450,29,1421,'2026-11-22 02:00+00','BATCH-02'),
(9004,'PAY-X','INR',300,6,294,'2026-11-22 02:00+00','BATCH-02'),
(9005,'PAY-D','USD',50,1,49,'2026-11-22 02:00+00','BATCH-02');

INSERT INTO settlement_lines VALUES
(1,9001,'PAY-A','INR',1200,'CAPTURE'),
(2,9001,'PAY-A','INR',24,'FEE'),
(3,9002,'PAY-B','INR',850,'CAPTURE'),
(4,9002,'PAY-B','INR',17,'FEE'),
(5,9003,'PAY-C','INR',1450,'CAPTURE'),
(6,9003,'PAY-C','INR',29,'FEE'),
(7,9004,'PAY-X','INR',300,'CAPTURE'),
(8,9004,'PAY-X','INR',6,'FEE'),
(9,9005,'PAY-D','USD',50,'CAPTURE'),
(10,9005,'PAY-D','USD',1,'FEE');

-- Q1. Reconcile bank header arithmetic: gross - fees must equal net.
-- SELECT settlement_id, gross_amount, fee_amount, net_amount,
--        gross_amount - fee_amount AS calculated_net
-- FROM bank_settlements
-- WHERE gross_amount - fee_amount <> net_amount;

-- Q2. Find bank settlements with no successful payment event, and successful
-- payment events that have not appeared in a bank settlement.
-- WITH successful AS (
--   SELECT provider_ref, currency, SUM(
--     CASE event_type WHEN 'REFUND' THEN -amount ELSE amount END
--   ) AS expected_gross
--   FROM payment_events
--   WHERE event_status = 'SUCCEEDED'
--   GROUP BY provider_ref, currency
-- )
-- SELECT 'BANK_WITHOUT_EVENT' AS exception_type, b.provider_ref, b.currency
-- FROM bank_settlements b
-- LEFT JOIN successful s USING (provider_ref, currency)
-- WHERE s.provider_ref IS NULL
-- UNION ALL
-- SELECT 'EVENT_NOT_SETTLED', s.provider_ref, s.currency
-- FROM successful s
-- LEFT JOIN bank_settlements b USING (provider_ref, currency)
-- WHERE b.provider_ref IS NULL;

-- Q3. Compare provider gross settlement to successful capture/refund events.
-- Aggregate events before joining to prevent join fanout.
-- WITH expected AS (
--   SELECT provider_ref, o.currency,
--          SUM(CASE WHEN e.event_type='REFUND' THEN -e.amount ELSE e.amount END) AS expected_gross
--   FROM payment_events e JOIN payment_orders o USING (order_id)
--   WHERE e.event_status='SUCCEEDED'
--   GROUP BY provider_ref, o.currency
-- ), actual AS (
--   SELECT provider_ref, currency, SUM(gross_amount) AS settled_gross
--   FROM bank_settlements GROUP BY provider_ref, currency
-- )
-- SELECT COALESCE(e.provider_ref,a.provider_ref) AS provider_ref,
--        COALESCE(e.currency,a.currency) AS currency,
--        e.expected_gross, a.settled_gross,
--        COALESCE(a.settled_gross,0)-COALESCE(e.expected_gross,0) AS variance
-- FROM expected e FULL JOIN actual a USING (provider_ref,currency)
-- WHERE COALESCE(e.expected_gross,0) <> COALESCE(a.settled_gross,0);

-- Q4. Identify under-settled captures. A partial settlement is not necessarily
-- a failed payment; compare at provider_ref + currency grain.
-- WITH captures AS (
--   SELECT e.provider_ref, o.currency, SUM(e.amount) AS captured
--   FROM payment_events e JOIN payment_orders o USING(order_id)
--   WHERE e.event_type='CAPTURE' AND e.event_status='SUCCEEDED'
--   GROUP BY e.provider_ref,o.currency
-- ), settled AS (
--   SELECT provider_ref,currency,SUM(gross_amount) AS settled
--   FROM bank_settlements GROUP BY provider_ref,currency
-- )
-- SELECT c.*, COALESCE(s.settled,0) AS settled,
--        c.captured-COALESCE(s.settled,0) AS outstanding
-- FROM captures c LEFT JOIN settled s USING(provider_ref,currency)
-- WHERE c.captured > COALESCE(s.settled,0);

-- Q5. Find settlement batches whose detail lines do not reconcile to header gross/fees.
-- SELECT b.settlement_id, b.gross_amount, b.fee_amount, b.net_amount,
--        SUM(l.line_amount) FILTER (WHERE l.line_type='CAPTURE') AS line_gross,
--        SUM(l.line_amount) FILTER (WHERE l.line_type='FEE') AS line_fees
-- FROM bank_settlements b
-- LEFT JOIN settlement_lines l USING(settlement_id)
-- GROUP BY b.settlement_id
-- HAVING COALESCE(SUM(l.line_amount) FILTER (WHERE l.line_type='CAPTURE'),0) <> b.gross_amount
--     OR COALESCE(SUM(l.line_amount) FILTER (WHERE l.line_type='FEE'),0) <> b.fee_amount;

-- Q6. Rank unresolved settlement exceptions by absolute financial exposure.
-- WITH variance AS (
--   SELECT b.settlement_id,b.provider_ref,b.currency,
--          b.gross_amount-COALESCE(e.expected_gross,0) AS variance
--   FROM bank_settlements b
--   LEFT JOIN (
--     SELECT e.provider_ref,o.currency,
--            SUM(CASE WHEN e.event_type='REFUND' THEN -e.amount ELSE e.amount END) expected_gross
--     FROM payment_events e JOIN payment_orders o USING(order_id)
--     WHERE e.event_status='SUCCEEDED'
--     GROUP BY e.provider_ref,o.currency
--   ) e USING(provider_ref,currency)
-- )
-- SELECT *, DENSE_RANK() OVER(ORDER BY ABS(variance) DESC) AS exposure_rank
-- FROM variance WHERE variance <> 0;

-- Q7. Detect duplicate provider references within a bank batch.
-- SELECT bank_batch_id, provider_ref, currency, COUNT(*) AS row_count
-- FROM bank_settlements
-- GROUP BY bank_batch_id,provider_ref,currency
-- HAVING COUNT(*) > 1;

-- Q8. Produce a daily reconciliation control summary by currency.
-- WITH event_totals AS (
--   SELECT o.currency,
--          SUM(CASE WHEN e.event_type='REFUND' THEN -e.amount ELSE e.amount END) AS event_gross
--   FROM payment_events e JOIN payment_orders o USING(order_id)
--   WHERE e.event_status='SUCCEEDED'
--   GROUP BY o.currency
-- ), bank_totals AS (
--   SELECT currency,SUM(gross_amount) AS bank_gross,
--          SUM(fee_amount) AS bank_fees,SUM(net_amount) AS bank_net
--   FROM bank_settlements GROUP BY currency
-- )
-- SELECT COALESCE(e.currency,b.currency) AS currency,
--        e.event_gross,b.bank_gross,b.bank_fees,b.bank_net,
--        COALESCE(b.bank_gross,0)-COALESCE(e.event_gross,0) AS gross_variance
-- FROM event_totals e FULL JOIN bank_totals b USING(currency);

-- Optimization notes:
-- 1. Keep reconciliation joins at provider_ref + currency grain; aggregate first.
-- 2. Consider indexes on payment_events(provider_ref, event_status, event_type)
--    INCLUDE (amount, order_id), bank_settlements(provider_ref, currency),
--    and settlement_lines(settlement_id, line_type).
-- 3. For large append-only event tables, partition by event_ts and constrain the
--    timestamp range in each batch; avoid wrapping indexed timestamps in DATE().
-- 4. Use NUMERIC for money, retain currency in every grouping/join key, and
--    persist a batch_id/watermark so retries are idempotent.
-- 5. Validate index value with EXPLAIN (ANALYZE, BUFFERS) on representative volumes.

-- Expected spot checks:
-- Q1 returns no rows. Q2 identifies PAY-X and the refund/capture event-side gaps
-- according to provider reference. Q3 exposes PAY-C's 50 INR short settlement.
-- Q5 returns no rows for the supplied balanced detail lines.
