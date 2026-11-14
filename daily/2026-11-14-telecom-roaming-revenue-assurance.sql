-- ============================================================================
-- TELECOM ROAMING USAGE MEDIATION & REVENUE ASSURANCE
-- PostgreSQL 14+
--
-- Scenario:
-- A mobile operator ingests roaming call-detail records (CDRs) from partner
-- networks. Deliveries may be replayed, corrected, delayed, or malformed.
-- The mediation team must canonicalize records, calculate local-day usage,
-- rate usage against effective-dated tariffs, reconcile partner statements,
-- and identify sequence, tariff, and source-data exceptions.
--
-- Run independently in a disposable PostgreSQL database.
-- Sample activity is centered on 2026-11-14. Event timestamps are timestamptz.
-- Solutions are commented out so each problem can be attempted first.
--
-- Business rules used in this lab:
-- * One canonical CDR per source_system + source_record_id.
-- * Highest source_version wins; source_updated_at and ingestion time break ties.
-- * Tariff validity is [valid_from, valid_to): start inclusive, end exclusive.
-- * Usage quantity is MB for DATA, seconds for VOICE, and messages for SMS.
-- * Rating rounds billable units up to the tariff's billing-unit quantity.
-- * Monthly partner reconciliation uses UTC calendar months and tariff currency.
-- * Subscriber daily caps use each subscriber's configured billing time zone.
-- ============================================================================

DROP VIEW IF EXISTS v_rated_cdr;
DROP VIEW IF EXISTS v_canonical_cdr;
DROP TABLE IF EXISTS partner_settlement_line;
DROP TABLE IF EXISTS raw_cdr;
DROP TABLE IF EXISTS roaming_tariff;
DROP TABLE IF EXISTS roaming_partner;
DROP TABLE IF EXISTS subscriber;

CREATE TABLE subscriber (
    subscriber_id       bigint PRIMARY KEY,
    msisdn               text NOT NULL UNIQUE,
    plan_code            text NOT NULL,
    billing_timezone     text NOT NULL,
    daily_data_cap_mb    numeric(12,3) NOT NULL
                         CHECK (daily_data_cap_mb > 0)
);

CREATE TABLE roaming_partner (
    partner_id             bigint PRIMARY KEY,
    partner_name           text NOT NULL,
    country_code           char(2) NOT NULL,
    settlement_currency    char(3) NOT NULL
);

-- Deliberately no exclusion constraint: Q8 audits overlapping tariff windows.
CREATE TABLE roaming_tariff (
    tariff_id             bigint PRIMARY KEY,
    partner_id            bigint NOT NULL
                          REFERENCES roaming_partner(partner_id),
    service_type          text NOT NULL
                          CHECK (service_type IN ('DATA', 'VOICE', 'SMS')),
    valid_from            timestamptz NOT NULL,
    valid_to              timestamptz NOT NULL,
    billing_unit_qty      numeric(12,3) NOT NULL
                          CHECK (billing_unit_qty > 0),
    unit_price            numeric(14,6) NOT NULL
                          CHECK (unit_price >= 0),
    currency              char(3) NOT NULL,
    CHECK (valid_to > valid_from)
);

-- This is a landing table: subscriber/partner references and several payload
-- checks are intentionally not enforced here so malformed source rows remain
-- queryable for revenue-assurance controls.
CREATE TABLE raw_cdr (
    cdr_id                 bigint PRIMARY KEY,
    source_system          text NOT NULL,
    source_record_id       text NOT NULL,
    source_version         integer NOT NULL,
    source_updated_at      timestamptz NOT NULL,
    ingested_at            timestamptz NOT NULL,
    subscriber_id          bigint,
    partner_id             bigint,
    service_type           text,
    event_start            timestamptz,
    event_end              timestamptz,
    quantity               numeric(14,3),
    unit_code              text,
    session_id             text,
    sequence_no            bigint,
    record_status           text,
    is_chargeable           boolean
);

CREATE TABLE partner_settlement_line (
    statement_line_id      bigint PRIMARY KEY,
    partner_id             bigint NOT NULL,
    billing_period         date NOT NULL,
    service_type           text NOT NULL,
    currency               char(3) NOT NULL,
    reported_quantity      numeric(16,3) NOT NULL,
    reported_amount        numeric(16,2) NOT NULL,
    statement_reference    text NOT NULL
);

INSERT INTO subscriber
    (subscriber_id, msisdn, plan_code, billing_timezone, daily_data_cap_mb)
VALUES
    (101, '+919800000101', 'ROAM-500', 'Asia/Kolkata', 500.000),
    (102, '+447700900102', 'ROAM-BIZ', 'Europe/London', 1500.000),
    (103, '+12025550103',  'ROAM-100', 'America/New_York', 100.000);

INSERT INTO roaming_partner
    (partner_id, partner_name, country_code, settlement_currency)
VALUES
    (10, 'Merlion Mobile', 'SG', 'SGD'),
    (20, 'Northstar Wireless', 'GB', 'GBP'),
    (30, 'Pacific Connect', 'US', 'USD');

INSERT INTO roaming_tariff
    (tariff_id, partner_id, service_type, valid_from, valid_to,
     billing_unit_qty, unit_price, currency)
VALUES
    -- Singapore DATA: a new rate takes effect at noon Singapore time.
    (1001, 10, 'DATA',
     TIMESTAMPTZ '2026-11-01 00:00:00+08',
     TIMESTAMPTZ '2026-11-14 12:00:00+08', 1.000, 0.012000, 'SGD'),
    (1002, 10, 'DATA',
     TIMESTAMPTZ '2026-11-14 12:00:00+08',
     TIMESTAMPTZ '2026-12-01 00:00:00+08', 1.000, 0.015000, 'SGD'),
    (1003, 10, 'VOICE',
     TIMESTAMPTZ '2026-11-01 00:00:00+08',
     TIMESTAMPTZ '2026-12-01 00:00:00+08', 60.000, 0.080000, 'SGD'),
    (1004, 10, 'SMS',
     TIMESTAMPTZ '2026-11-01 00:00:00+08',
     TIMESTAMPTZ '2026-12-01 00:00:00+08', 1.000, 0.050000, 'SGD'),

    (2001, 20, 'DATA',
     TIMESTAMPTZ '2026-11-01 00:00:00+00',
     TIMESTAMPTZ '2026-12-01 00:00:00+00', 1.000, 0.020000, 'GBP'),
    -- Intentional one-day overlap with tariff 2001; Q4 selects the later start.
    (2002, 20, 'DATA',
     TIMESTAMPTZ '2026-11-14 00:00:00+00',
     TIMESTAMPTZ '2026-11-15 00:00:00+00', 1.000, 0.018000, 'GBP'),
    (2003, 20, 'VOICE',
     TIMESTAMPTZ '2026-11-01 00:00:00+00',
     TIMESTAMPTZ '2026-12-01 00:00:00+00', 60.000, 0.040000, 'GBP'),

    (3001, 30, 'DATA',
     TIMESTAMPTZ '2026-11-01 00:00:00-05',
     TIMESTAMPTZ '2026-12-01 00:00:00-05', 1.000, 0.025000, 'USD'),
    (3002, 30, 'SMS',
     TIMESTAMPTZ '2026-11-01 00:00:00-05',
     TIMESTAMPTZ '2026-12-01 00:00:00-05', 1.000, 0.030000, 'USD');

INSERT INTO raw_cdr
    (cdr_id, source_system, source_record_id, source_version,
     source_updated_at, ingested_at, subscriber_id, partner_id,
     service_type, event_start, event_end, quantity, unit_code,
     session_id, sequence_no, record_status, is_chargeable)
VALUES
    -- Same source record delivered twice, then corrected in source version 2.
    (1, 'SG-MEDIATOR', 'SG-DATA-001', 1,
     TIMESTAMPTZ '2026-11-14 09:16:00+08',
     TIMESTAMPTZ '2026-11-14 09:17:00+08',
     101, 10, 'DATA',
     TIMESTAMPTZ '2026-11-14 09:00:00+08',
     TIMESTAMPTZ '2026-11-14 09:15:00+08',
     350.000, 'MB', 'DATA-77', 1, 'ACTIVE', true),
    (2, 'SG-MEDIATOR', 'SG-DATA-001', 1,
     TIMESTAMPTZ '2026-11-14 09:16:00+08',
     TIMESTAMPTZ '2026-11-14 09:19:00+08',
     101, 10, 'DATA',
     TIMESTAMPTZ '2026-11-14 09:00:00+08',
     TIMESTAMPTZ '2026-11-14 09:15:00+08',
     350.000, 'MB', 'DATA-77', 1, 'ACTIVE', true),
    (3, 'SG-MEDIATOR', 'SG-DATA-001', 2,
     TIMESTAMPTZ '2026-11-14 09:25:00+08',
     TIMESTAMPTZ '2026-11-14 09:26:00+08',
     101, 10, 'DATA',
     TIMESTAMPTZ '2026-11-14 09:00:00+08',
     TIMESTAMPTZ '2026-11-14 09:15:00+08',
     352.000, 'MB', 'DATA-77', 1, 'ACTIVE', true),

    (4, 'SG-MEDIATOR', 'SG-VOICE-010', 1,
     TIMESTAMPTZ '2026-11-14 10:32:00+08',
     TIMESTAMPTZ '2026-11-14 10:33:00+08',
     101, 10, 'VOICE',
     TIMESTAMPTZ '2026-11-14 10:30:00+08',
     TIMESTAMPTZ '2026-11-14 10:33:00+08',
     180.000, 'SECOND', 'CALL-77', 1, 'ACTIVE', true),

    -- DATA-77 deliberately skips sequence 2 and repeats sequence 3.
    (5, 'SG-MEDIATOR', 'SG-DATA-002', 1,
     TIMESTAMPTZ '2026-11-14 13:16:00+08',
     TIMESTAMPTZ '2026-11-14 13:17:00+08',
     101, 10, 'DATA',
     TIMESTAMPTZ '2026-11-14 13:00:00+08',
     TIMESTAMPTZ '2026-11-14 13:15:00+08',
     200.000, 'MB', 'DATA-77', 3, 'ACTIVE', true),
    (6, 'SG-MEDIATOR', 'SG-DATA-003', 1,
     TIMESTAMPTZ '2026-11-14 14:01:00+08',
     TIMESTAMPTZ '2026-11-14 14:02:00+08',
     101, 10, 'DATA',
     TIMESTAMPTZ '2026-11-14 14:00:00+08',
     TIMESTAMPTZ '2026-11-14 14:01:00+08',
     20.000, 'MB', 'DATA-77', 3, 'ACTIVE', true),
    (7, 'SG-MEDIATOR', 'SG-DATA-004', 1,
     TIMESTAMPTZ '2026-11-14 15:16:00+08',
     TIMESTAMPTZ '2026-11-14 15:17:00+08',
     101, 10, 'DATA',
     TIMESTAMPTZ '2026-11-14 15:00:00+08',
     TIMESTAMPTZ '2026-11-14 15:15:00+08',
     120.000, 'MB', 'DATA-77', 4, 'ACTIVE', true),

    (8, 'UK-MEDIATOR', 'UK-DATA-001', 1,
     TIMESTAMPTZ '2026-11-14 08:12:00+00',
     TIMESTAMPTZ '2026-11-14 08:13:00+00',
     102, 20, 'DATA',
     TIMESTAMPTZ '2026-11-14 08:00:00+00',
     TIMESTAMPTZ '2026-11-14 08:10:00+00',
     120.000, 'MB', 'UK-DATA-1', 1, 'ACTIVE', true),
    (9, 'UK-MEDIATOR', 'UK-VOICE-001', 1,
     TIMESTAMPTZ '2026-11-14 08:26:00+00',
     TIMESTAMPTZ '2026-11-14 08:27:00+00',
     102, 20, 'VOICE',
     TIMESTAMPTZ '2026-11-14 08:20:00+00',
     TIMESTAMPTZ '2026-11-14 08:25:00+00',
     95.000, 'SECOND', 'UK-CALL-1', 1, 'ACTIVE', true),

    (10, 'UK-MEDIATOR', 'UK-DATA-LATE-001', 1,
     TIMESTAMPTZ '2026-11-13 22:11:00+00',
     TIMESTAMPTZ '2026-11-14 08:00:00+00',
     102, 20, 'DATA',
     TIMESTAMPTZ '2026-11-13 22:00:00+00',
     TIMESTAMPTZ '2026-11-13 22:10:00+00',
     75.000, 'MB', 'UK-DATA-OLD', 8, 'ACTIVE', true),

    -- Latest version is VOID, so this record must not be rated or counted.
    (11, 'SG-MEDIATOR', 'SG-DATA-VOID-01', 1,
     TIMESTAMPTZ '2026-11-14 16:06:00+08',
     TIMESTAMPTZ '2026-11-14 16:07:00+08',
     101, 10, 'DATA',
     TIMESTAMPTZ '2026-11-14 16:00:00+08',
     TIMESTAMPTZ '2026-11-14 16:05:00+08',
     10.000, 'MB', 'DATA-VOID', 1, 'ACTIVE', true),
    (12, 'SG-MEDIATOR', 'SG-DATA-VOID-01', 2,
     TIMESTAMPTZ '2026-11-14 16:10:00+08',
     TIMESTAMPTZ '2026-11-14 16:11:00+08',
     101, 10, 'DATA',
     TIMESTAMPTZ '2026-11-14 16:00:00+08',
     TIMESTAMPTZ '2026-11-14 16:05:00+08',
     10.000, 'MB', 'DATA-VOID', 1, 'VOID', false),

    (13, 'US-MEDIATOR', 'US-SMS-001', 1,
     TIMESTAMPTZ '2026-11-14 19:02:00-05',
     TIMESTAMPTZ '2026-11-14 19:03:00-05',
     103, 30, 'SMS',
     TIMESTAMPTZ '2026-11-14 19:00:00-05',
     TIMESTAMPTZ '2026-11-14 19:00:01-05',
     3.000, 'MESSAGE', 'US-SMS-1', 1, 'ACTIVE', true),

    -- No tariff exists for partner 30 VOICE: Q8 must report this CDR as unrated.
    (14, 'US-MEDIATOR', 'US-VOICE-001', 1,
     TIMESTAMPTZ '2026-11-14 19:10:00-05',
     TIMESTAMPTZ '2026-11-14 19:11:00-05',
     103, 30, 'VOICE',
     TIMESTAMPTZ '2026-11-14 19:10:00-05',
     TIMESTAMPTZ '2026-11-14 19:11:00-05',
     60.000, 'SECOND', 'US-CALL-1', 1, 'ACTIVE', true),

    -- Intentionally malformed landing row; it has no master-data references.
    (15, 'UNKNOWN-FEED', 'BAD-ROW-001', 1,
     TIMESTAMPTZ '2026-11-14 18:00:00+08',
     TIMESTAMPTZ '2026-11-14 18:01:00+08',
     999, 999, 'VIDEO',
     TIMESTAMPTZ '2026-11-14 18:00:00+08',
     TIMESTAMPTZ '2026-11-14 17:55:00+08',
     -5.000, 'GB', 'BAD-SESSION', 1, 'ACTIVE', true);

INSERT INTO partner_settlement_line
    (statement_line_id, partner_id, billing_period, service_type, currency,
     reported_quantity, reported_amount, statement_reference)
VALUES
    (9001, 10, DATE '2026-11-01', 'DATA',  'SGD', 680.000, 8.50, 'SG-NOV-DATA'),
    (9002, 10, DATE '2026-11-01', 'VOICE', 'SGD', 180.000, 0.24, 'SG-NOV-VOICE'),
    (9003, 20, DATE '2026-11-01', 'DATA',  'GBP', 190.000, 3.50, 'UK-NOV-DATA');

-- Indexes reflect the principal lookup and ordering patterns. They are
-- candidates to benchmark, not a guarantee that every sample query will use them.
CREATE INDEX ix_raw_cdr_canonical
    ON raw_cdr
       (source_system, source_record_id, source_version DESC,
        source_updated_at DESC, ingested_at DESC, cdr_id DESC);

CREATE INDEX ix_raw_cdr_session_sequence
    ON raw_cdr
       (subscriber_id, partner_id, session_id, event_start, sequence_no)
    INCLUDE (cdr_id, source_system, source_record_id);

CREATE INDEX ix_raw_cdr_event_start_brin
    ON raw_cdr USING brin (event_start)
    WITH (pages_per_range = 64);

CREATE INDEX ix_roaming_tariff_lookup
    ON roaming_tariff (partner_id, service_type, valid_from DESC)
    INCLUDE (valid_to, billing_unit_qty, unit_price, currency);

CREATE INDEX ix_roaming_tariff_window
    ON roaming_tariff
    USING gist (tstzrange(valid_from, valid_to, '[)'));

CREATE INDEX ix_settlement_reconciliation
    ON partner_settlement_line
       (partner_id, billing_period, service_type, currency);

-- Canonical source record: highest version wins; timestamps and immutable ID
-- provide deterministic tie-breaks for replayed deliveries.
CREATE OR REPLACE VIEW v_canonical_cdr AS
SELECT DISTINCT ON (source_system, source_record_id)
       cdr_id,
       source_system,
       source_record_id,
       source_version,
       source_updated_at,
       ingested_at,
       subscriber_id,
       partner_id,
       service_type,
       event_start,
       event_end,
       quantity,
       unit_code,
       session_id,
       sequence_no,
       record_status,
       is_chargeable
FROM raw_cdr
ORDER BY source_system,
         source_record_id,
         source_version DESC,
         source_updated_at DESC,
         ingested_at DESC,
         cdr_id DESC;

-- Rate each active, chargeable canonical CDR against the tariff that was
-- effective at event_start. The LATERAL lookup returns at most one tariff.
CREATE OR REPLACE VIEW v_rated_cdr AS
SELECT c.cdr_id,
       c.source_system,
       c.source_record_id,
       c.subscriber_id,
       c.partner_id,
       c.service_type,
       c.event_start,
       c.event_end,
       c.quantity,
       c.unit_code,
       t.tariff_id,
       t.billing_unit_qty,
       t.unit_price,
       t.currency,
       CEIL(c.quantity / t.billing_unit_qty) AS billable_units,
       ROUND(
           (CEIL(c.quantity / t.billing_unit_qty) * t.unit_price)::numeric,
           2
       ) AS line_charge
FROM v_canonical_cdr c
LEFT JOIN LATERAL (
    SELECT t.tariff_id,
           t.billing_unit_qty,
           t.unit_price,
           t.currency
    FROM roaming_tariff t
    WHERE t.partner_id = c.partner_id
      AND t.service_type = c.service_type
      AND c.event_start >= t.valid_from
      AND c.event_start <  t.valid_to
    ORDER BY t.valid_from DESC, t.tariff_id DESC
    LIMIT 1
) t ON true
WHERE c.record_status = 'ACTIVE'
  AND c.is_chargeable IS TRUE
  AND c.quantity > 0;

-- ============================================================================
-- PROBLEM 1 — Replay and correction audit
-- Return source keys delivered more than once, delivery counts, number of
-- source versions, and the canonical CDR selected for each source key.
--
-- OPTIMIZED SOLUTION:
-- SELECT r.source_system,
--        r.source_record_id,
--        COUNT(*) AS delivery_count,
--        COUNT(DISTINCT r.source_version) AS source_version_count,
--        c.cdr_id AS canonical_cdr_id,
--        c.source_version AS canonical_version,
--        c.record_status AS canonical_status,
--        c.quantity AS canonical_quantity
-- FROM raw_cdr r
-- JOIN v_canonical_cdr c
--   ON c.source_system = r.source_system
--  AND c.source_record_id = r.source_record_id
-- GROUP BY r.source_system, r.source_record_id,
--          c.cdr_id, c.source_version, c.record_status, c.quantity
-- HAVING COUNT(*) > 1
-- ORDER BY r.source_system, r.source_record_id;
--
-- EXPECTED SPOT CHECK:
-- SG-DATA-001 has three deliveries; version 2 / CDR 3 wins with 352 MB.
-- SG-DATA-VOID-01 has two deliveries; version 2 / CDR 12 wins with VOID.
--
-- WHY THIS IS OPTIMIZED:
-- DISTINCT ON expresses PostgreSQL's ordered first-row-per-key operation.
-- The composite index follows the partition key and winner ordering, allowing
-- an ordered index path. The small fixture may still favor a sequential scan.
-- Keep VOID filtering after canonicalization; filtering raw rows first could
-- resurrect an older ACTIVE version and incorrectly bill a voided record.
--
-- ============================================================================
-- PROBLEM 2 — Late-arriving CDRs and watermark backlog
-- Find canonical active CDRs ingested more than six hours after event_end.
-- Report arrival lag and the UTC event month that may need to be restated.
--
-- OPTIMIZED SOLUTION:
-- SELECT c.cdr_id,
--        c.source_system,
--        c.source_record_id,
--        c.subscriber_id,
--        c.event_end,
--        c.ingested_at,
--        ROUND(
--          (EXTRACT(EPOCH FROM (c.ingested_at - c.event_end)) / 3600.0)::numeric,
--          2
--        ) AS arrival_lag_hours,
--        date_trunc('month', c.event_start AT TIME ZONE 'UTC')::date
--          AS affected_utc_billing_month
-- FROM v_canonical_cdr c
-- WHERE c.record_status = 'ACTIVE'
--   AND c.event_end IS NOT NULL
--   AND c.ingested_at > c.event_end + INTERVAL '6 hours'
-- ORDER BY c.ingested_at DESC;
--
-- EXPECTED SPOT CHECK:
-- UK-DATA-LATE-001 is approximately 9 hours 50 minutes late.
--
-- WHY THIS IS OPTIMIZED:
-- Canonicalize before measuring lateness so a replay does not create multiple
-- backlog alerts. Compare timestamps directly; avoid wrapping event_end in
-- DATE() or DATE_TRUNC() in the predicate. A production pipeline should store
-- per-source watermarks and reprocess only affected event-time partitions.
--
-- ============================================================================
-- PROBLEM 3 — Subscriber-local daily data usage and cap utilization
-- Aggregate canonical active, chargeable DATA in MB by each subscriber's
-- billing-local calendar day. Show cap utilization and excess MB.
--
-- OPTIMIZED SOLUTION:
-- WITH daily_usage AS (
--     SELECT c.subscriber_id,
--            (c.event_start AT TIME ZONE s.billing_timezone)::date
--              AS billing_date,
--            s.plan_code,
--            s.daily_data_cap_mb,
--            SUM(c.quantity) AS data_mb
--     FROM v_canonical_cdr c
--     JOIN subscriber s ON s.subscriber_id = c.subscriber_id
--     WHERE c.record_status = 'ACTIVE'
--       AND c.is_chargeable IS TRUE
--       AND c.service_type = 'DATA'
--       AND c.unit_code = 'MB'
--       AND c.event_start >= TIMESTAMPTZ '2026-11-13 00:00:00+00'
--       AND c.event_start <  TIMESTAMPTZ '2026-11-16 00:00:00+00'
--     GROUP BY c.subscriber_id,
--              (c.event_start AT TIME ZONE s.billing_timezone)::date,
--              s.plan_code,
--              s.daily_data_cap_mb
-- )
-- SELECT subscriber_id,
--        billing_date,
--        plan_code,
--        data_mb,
--        daily_data_cap_mb,
--        ROUND(100.0 * data_mb / NULLIF(daily_data_cap_mb, 0), 2)
--          AS cap_utilization_pct,
--        GREATEST(data_mb - daily_data_cap_mb, 0) AS excess_mb
-- FROM daily_usage
-- ORDER BY subscriber_id, billing_date;
--
-- EXPECTED SPOT CHECK:
-- Subscriber 101 has 692 MB on 14 Nov in Asia/Kolkata time, exceeding the
-- 500 MB daily cap by 192 MB. The VOID CDR contributes zero usage.
--
-- WHY THIS IS OPTIMIZED:
-- Filter the raw event-time range before timezone conversion and aggregate
-- once at subscriber/day grain. The timestamp predicate is SARGable and can
-- use a B-tree or BRIN access path. The selected UTC window deliberately
-- covers the local dates in this fixture; production jobs should derive
-- UTC boundaries per billing timezone or join a timezone-aware calendar.
--
-- ============================================================================
-- PROBLEM 4 — Effective-dated tariff selection and CDR rating
-- Return rated CDRs with billable units and charge. A partial final billing
-- unit is rounded up (for example, 95 seconds at 60 seconds per unit = 2 units).
--
-- OPTIMIZED SOLUTION:
-- SELECT cdr_id,
--        subscriber_id,
--        partner_id,
--        service_type,
--        event_start,
--        quantity,
--        unit_code,
--        tariff_id,
--        billable_units,
--        currency,
--        line_charge
-- FROM v_rated_cdr
-- WHERE tariff_id IS NOT NULL
-- ORDER BY partner_id, event_start, cdr_id;
--
-- EXPECTED SPOT CHECKS:
-- * SG-DATA-001 uses the pre-noon Singapore tariff: 352 x SGD 0.012 = 4.22.
-- * SG-DATA-002 uses the post-noon tariff: 200 x SGD 0.015 = 3.00.
-- * UK-DATA-001 selects tariff 2002 during the intentional overlap.
-- * UK-VOICE-001 bills 2 x 60-second units: GBP 0.08.
--
-- WHY THIS IS OPTIMIZED:
-- LEFT JOIN LATERAL performs a bounded top-one tariff lookup per CDR and
-- preserves unrated rows for the coverage audit. Equality predicates lead the
-- tariff index, followed by descending valid_from. The explicit half-open
-- interval avoids double matching at adjacent tariff boundaries. LIMIT 1 is
-- deterministic because tariff_id is the final tie-breaker, but overlapping
-- tariffs remain a data-governance exception rather than a valid business rule.
--
-- ============================================================================
-- PROBLEM 5 — Partner revenue and subscriber contribution
-- Aggregate rated usage by partner, service, currency, and subscriber. Rank
-- subscribers within each partner/service by rated amount.
--
-- OPTIMIZED SOLUTION:
-- WITH subscriber_revenue AS (
--     SELECT partner_id,
--            service_type,
--            currency,
--            subscriber_id,
--            COUNT(*) AS cdr_count,
--            SUM(quantity) AS usage_quantity,
--            SUM(line_charge) AS rated_amount
--     FROM v_rated_cdr
--     WHERE tariff_id IS NOT NULL
--     GROUP BY partner_id, service_type, currency, subscriber_id
-- )
-- SELECT partner_id,
--        service_type,
--        currency,
--        subscriber_id,
--        cdr_count,
--        usage_quantity,
--        rated_amount,
--        DENSE_RANK() OVER (
--            PARTITION BY partner_id, service_type, currency
--            ORDER BY rated_amount DESC
--        ) AS revenue_rank
-- FROM subscriber_revenue
-- ORDER BY partner_id, service_type, revenue_rank, subscriber_id;
--
-- WHY THIS IS OPTIMIZED:
-- Reduce CDRs to subscriber/service grain before applying the ranking window.
-- This shrinks the window's sort input and avoids ranking every raw CDR. Keep
-- currency in the partition key: comparing SGD, GBP, and USD without FX
-- conversion would produce a meaningless cross-currency ranking.
--
-- ============================================================================
-- PROBLEM 6 — Roaming partner settlement reconciliation
-- Reconcile rated usage against partner statement lines at partner, UTC month,
-- service, and currency grain. Preserve usage-only and statement-only groups.
--
-- OPTIMIZED SOLUTION:
-- WITH rated AS (
--     SELECT partner_id,
--            date_trunc('month', event_start AT TIME ZONE 'UTC')::date
--              AS billing_period,
--            service_type,
--            currency,
--            SUM(quantity) AS rated_quantity,
--            SUM(line_charge) AS rated_amount
--     FROM v_rated_cdr
--     WHERE tariff_id IS NOT NULL
--     GROUP BY partner_id,
--              date_trunc('month', event_start AT TIME ZONE 'UTC')::date,
--              service_type,
--              currency
-- )
-- SELECT COALESCE(r.partner_id, p.partner_id) AS partner_id,
--        COALESCE(r.billing_period, p.billing_period) AS billing_period,
--        COALESCE(r.service_type, p.service_type) AS service_type,
--        COALESCE(r.currency, p.currency) AS currency,
--        COALESCE(r.rated_quantity, 0) AS rated_quantity,
--        COALESCE(p.reported_quantity, 0) AS reported_quantity,
--        COALESCE(r.rated_quantity, 0)
--          - COALESCE(p.reported_quantity, 0) AS quantity_variance,
--        COALESCE(r.rated_amount, 0) AS rated_amount,
--        COALESCE(p.reported_amount, 0) AS reported_amount,
--        COALESCE(r.rated_amount, 0)
--          - COALESCE(p.reported_amount, 0) AS amount_variance,
--        CASE
--          WHEN r.partner_id IS NULL THEN 'STATEMENT_WITHOUT_USAGE'
--          WHEN p.partner_id IS NULL THEN 'USAGE_WITHOUT_STATEMENT'
--          WHEN r.rated_quantity <> p.reported_quantity
--            OR r.rated_amount <> p.reported_amount THEN 'VARIANCE'
--          ELSE 'MATCHED'
--        END AS reconciliation_status
-- FROM rated r
-- FULL OUTER JOIN (
--     SELECT partner_id, billing_period, service_type, currency,
--            SUM(reported_quantity) AS reported_quantity,
--            SUM(reported_amount) AS reported_amount
--     FROM partner_settlement_line
--     GROUP BY partner_id, billing_period, service_type, currency
-- ) p
--   ON p.partner_id = r.partner_id
--  AND p.billing_period = r.billing_period
--  AND p.service_type = r.service_type
--  AND p.currency = r.currency
-- ORDER BY 1, 2, 3, 4;
--
-- EXPECTED SPOT CHECKS:
-- Partner 10 DATA has rated quantity 692 MB and a statement quantity of 680 MB.
-- Partner 20 DATA has rated quantity 195 MB and a statement quantity of 190 MB.
-- Partner 30 SMS is usage without a statement line.
--
-- WHY THIS IS OPTIMIZED:
-- Aggregate both sides to the exact reconciliation grain before the FULL JOIN.
-- This prevents statement detail from multiplying CDRs. The composite
-- settlement index supports period/partner lookups. Never reconcile amounts
-- across currencies without a governed FX source, rate timestamp, and rounding
-- policy. Tolerance rules should be explicit rather than hidden in the join.
--
-- ============================================================================
-- PROBLEM 7 — Session sequence gaps and duplicate sequence numbers
-- Within each subscriber/partner/session, find sequence numbers that repeat
-- or jump forward. Use event time and CDR ID for deterministic ordering.
--
-- OPTIMIZED SOLUTION:
-- WITH ordered_cdr AS (
--     SELECT c.subscriber_id,
--            c.partner_id,
--            c.session_id,
--            c.cdr_id,
--            c.event_start,
--            c.sequence_no,
--            LAG(c.sequence_no) OVER (
--                PARTITION BY c.subscriber_id, c.partner_id, c.session_id
--                ORDER BY c.event_start, c.sequence_no, c.cdr_id
--            ) AS prior_sequence_no
--     FROM v_canonical_cdr c
--     WHERE c.record_status = 'ACTIVE'
--       AND c.session_id IS NOT NULL
--       AND c.sequence_no IS NOT NULL
-- )
-- SELECT subscriber_id,
--        partner_id,
--        session_id,
--        cdr_id,
--        prior_sequence_no,
--        sequence_no,
--        CASE
--          WHEN sequence_no = prior_sequence_no THEN 'DUPLICATE_SEQUENCE'
--          WHEN sequence_no > prior_sequence_no + 1 THEN 'SEQUENCE_GAP'
--        END AS sequence_exception
-- FROM ordered_cdr
-- WHERE prior_sequence_no IS NOT NULL
--   AND sequence_no <= prior_sequence_no + 1
-- ORDER BY subscriber_id, partner_id, session_id, event_start, cdr_id;
--
-- EXPECTED SPOT CHECK:
-- Session DATA-77 has a gap from sequence 1 to 3 and a repeated sequence 3.
--
-- WHY THIS IS OPTIMIZED:
-- LAG detects adjacent sequence anomalies in one ordered pass. The session
-- index follows the partition keys and event ordering. Do not infer a missing
-- CDR from a sequence gap until source-specific reset, wraparound, and
-- out-of-order delivery semantics have been defined.
--
-- ============================================================================
-- PROBLEM 8 — Tariff overlap and unrated usage controls
-- A. Find overlapping tariff windows for the same partner and service.
-- B. Find active chargeable canonical CDRs for which no effective tariff exists.
--
-- OPTIMIZED SOLUTION — A: OVERLAPPING WINDOWS
-- SELECT a.partner_id,
--        a.service_type,
--        a.tariff_id AS tariff_a,
--        b.tariff_id AS tariff_b,
--        GREATEST(a.valid_from, b.valid_from) AS overlap_start,
--        LEAST(a.valid_to, b.valid_to) AS overlap_end
-- FROM roaming_tariff a
-- JOIN roaming_tariff b
--   ON b.partner_id = a.partner_id
--  AND b.service_type = a.service_type
--  AND b.tariff_id > a.tariff_id
--  AND tstzrange(a.valid_from, a.valid_to, '[)')
--      && tstzrange(b.valid_from, b.valid_to, '[)')
-- ORDER BY a.partner_id, a.service_type, a.tariff_id, b.tariff_id;
--
-- EXPECTED SPOT CHECK:
-- Partner 20 DATA tariffs 2001 and 2002 overlap on 14 Nov 2026.
--
-- OPTIMIZED SOLUTION — B: UNRATED CDRS
-- SELECT c.cdr_id,
--        c.source_system,
--        c.source_record_id,
--        c.partner_id,
--        c.service_type,
--        c.event_start,
--        c.quantity,
--        c.unit_code
-- FROM v_canonical_cdr c
-- LEFT JOIN LATERAL (
--     SELECT t.tariff_id
--     FROM roaming_tariff t
--     WHERE t.partner_id = c.partner_id
--       AND t.service_type = c.service_type
--       AND c.event_start >= t.valid_from
--       AND c.event_start <  t.valid_to
--     ORDER BY t.valid_from DESC, t.tariff_id DESC
--     LIMIT 1
-- ) t ON true
-- WHERE c.record_status = 'ACTIVE'
--   AND c.is_chargeable IS TRUE
--   AND c.quantity > 0
--   AND t.tariff_id IS NULL
-- ORDER BY c.partner_id, c.event_start;
--
-- EXPECTED SPOT CHECK:
-- US-VOICE-001 is chargeable but has no partner 30 VOICE tariff.
--
-- WHY THIS IS OPTIMIZED:
-- The GiST range index supports overlap predicates; the partner/service B-tree
-- narrows candidates for effective-date lookups. The greater-than tariff ID
-- condition emits each unordered overlap pair once. Keep the uncovered-usage
-- anti-lookup separate from rated revenue so missing tariffs are visible and
-- never silently treated as zero-priced service.
--
-- ============================================================================
-- PROBLEM 9 — Canonical CDR data-quality exception feed
-- Return canonical rows with missing master data, unsupported service/unit
-- combinations, invalid time order, non-positive quantity, or invalid status.
--
-- OPTIMIZED SOLUTION:
-- WITH checked AS (
--     SELECT c.cdr_id,
--            c.source_system,
--            c.source_record_id,
--            c.subscriber_id,
--            c.partner_id,
--            c.service_type,
--            c.event_start,
--            c.event_end,
--            c.quantity,
--            c.unit_code,
--            c.record_status,
--            ARRAY_REMOVE(ARRAY[
--                CASE WHEN s.subscriber_id IS NULL
--                     THEN 'UNKNOWN_SUBSCRIBER' END,
--                CASE WHEN p.partner_id IS NULL
--                     THEN 'UNKNOWN_PARTNER' END,
--                CASE WHEN c.service_type NOT IN ('DATA', 'VOICE', 'SMS')
--                       OR c.service_type IS NULL
--                     THEN 'UNSUPPORTED_SERVICE' END,
--                CASE WHEN c.service_type = 'DATA'
--                           AND c.unit_code IS DISTINCT FROM 'MB'
--                     THEN 'DATA_UNIT_MISMATCH' END,
--                CASE WHEN c.service_type = 'VOICE'
--                           AND c.unit_code IS DISTINCT FROM 'SECOND'
--                     THEN 'VOICE_UNIT_MISMATCH' END,
--                CASE WHEN c.service_type = 'SMS'
--                           AND c.unit_code IS DISTINCT FROM 'MESSAGE'
--                     THEN 'SMS_UNIT_MISMATCH' END,
--                CASE WHEN c.event_start IS NULL OR c.event_end IS NULL
--                     THEN 'MISSING_EVENT_TIME' END,
--                CASE WHEN c.event_start IS NOT NULL
--                           AND c.event_end IS NOT NULL
--                           AND c.event_end < c.event_start
--                     THEN 'END_BEFORE_START' END,
--                CASE WHEN c.quantity IS NULL OR c.quantity <= 0
--                     THEN 'NON_POSITIVE_OR_NULL_QUANTITY' END,
--                CASE WHEN c.record_status NOT IN ('ACTIVE', 'VOID')
--                       OR c.record_status IS NULL
--                     THEN 'INVALID_RECORD_STATUS' END
--            ], NULL) AS exception_codes
--     FROM v_canonical_cdr c
--     LEFT JOIN subscriber s ON s.subscriber_id = c.subscriber_id
--     LEFT JOIN roaming_partner p ON p.partner_id = c.partner_id
-- )
-- SELECT cdr_id,
--        source_system,
--        source_record_id,
--        subscriber_id,
--        partner_id,
--        exception_codes
-- FROM checked
-- WHERE CARDINALITY(exception_codes) > 0
-- ORDER BY cdr_id;
--
-- EXPECTED SPOT CHECK:
-- BAD-ROW-001 returns unknown subscriber, unknown partner, unsupported service,
-- end-before-start, and non-positive-quantity exceptions.
--
-- WHY THIS IS OPTIMIZED:
-- Validate after canonicalization so replayed versions do not inflate counts.
-- LEFT JOIN preserves orphan landing records; INNER JOIN would hide them.
-- ARRAY_REMOVE builds multiple rule results in one projection rather than
-- scanning the landing table once per exception type.
--
-- ============================================================================
-- PERFORMANCE LAB
--
-- 1. Compare DISTINCT ON in v_canonical_cdr with:
--      ROW_NUMBER() OVER (
--        PARTITION BY source_system, source_record_id
--        ORDER BY source_version DESC, source_updated_at DESC,
--                 ingested_at DESC, cdr_id DESC
--      )
--    Keep rn = 1 and verify identical winning CDR IDs, including VOID records.
--
-- 2. Benchmark representative queries with:
--      EXPLAIN (ANALYZE, BUFFERS)
--    Inspect sort spill, rows removed by filters, heap fetches, shared reads,
--    and whether the canonical, session, BRIN, or tariff indexes are selected.
--
-- 3. Keep event-time filters SARGable. Prefer:
--      event_start >= TIMESTAMPTZ '2026-11-14 00:00:00+00'
--      AND event_start <  TIMESTAMPTZ '2026-11-15 00:00:00+00'
--    over DATE(event_start) or DATE_TRUNC() on the indexed column.
--
-- 4. For large CDR volumes, partition the landing table by event or ingestion
--    time according to the operational retention/replay model. Do not assume
--    event-time partitioning alone can prune a late-arriving ingestion scan.
--
-- 5. Consider a persisted canonical CDR table with a unique source key and
--    incremental merge logic. A new source version must replace the prior
--    canonical version atomically; a VOID winner must remain visible to prevent
--    older ACTIVE versions from being reintroduced.
--
-- 6. Store rated amounts in currency minor units or a governed numeric scale.
--    Define whether rounding occurs per CDR, per invoice line, or after monthly
--    aggregation; those policies can produce different settlement totals.
--
-- 7. Treat partner tariff overlaps, missing tariffs, currency mismatches,
--    sequence resets, and source watermark movement as operational controls.
--    A technically successful load is not proof of complete or billable usage.
-- ============================================================================
