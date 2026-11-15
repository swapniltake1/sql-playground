-- ============================================================================
-- 2026-11-15 | Cloud FinOps: Cost Allocation, Budget Forecasting & Anomalies
-- Engine: PostgreSQL 14+
--
-- Scenario:
-- A cloud platform team receives duplicated/corrected billing deliveries,
-- applies effective-dated resource ownership tags, monitors monthly budgets,
-- evaluates commitment coverage, and reconciles provider invoice controls.
--
-- Run this file independently in a disposable PostgreSQL database.
-- The sample is fixed for November 2026 so results are reproducible.
-- ============================================================================

DROP VIEW IF EXISTS canonical_billing_line_items;
DROP TABLE IF EXISTS invoice_control_totals;
DROP TABLE IF EXISTS commitment_purchases;
DROP TABLE IF EXISTS monthly_service_budgets;
DROP TABLE IF EXISTS billing_line_item_deliveries;
DROP TABLE IF EXISTS resource_tag_history;
DROP TABLE IF EXISTS cloud_accounts;

-- ----------------------------------------------------------------------------
-- 0. Schema and realistic sample data
-- ----------------------------------------------------------------------------

CREATE TABLE cloud_accounts (
    account_id       text PRIMARY KEY,
    account_name     text NOT NULL,
    business_unit    text NOT NULL
);

CREATE TABLE resource_tag_history (
    tag_version_id   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    resource_id      text NOT NULL,
    valid_from       date NOT NULL,
    valid_to         date,
    owner_team       text,
    cost_center      text,
    environment      text,
    CHECK (valid_to IS NULL OR valid_to > valid_from)
);

-- Each delivery is immutable. A provider may resend the same source line,
-- publish a later correction, or void a previously delivered line.
CREATE TABLE billing_line_item_deliveries (
    delivery_id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    source_line_item_id  text NOT NULL,
    source_version       integer NOT NULL,
    source_updated_at    timestamptz NOT NULL,
    ingested_at          timestamptz NOT NULL,
    line_status          text NOT NULL CHECK (line_status IN ('ACTIVE', 'VOID')),
    invoice_month        date NOT NULL,
    usage_start          timestamptz NOT NULL,
    account_id           text NOT NULL REFERENCES cloud_accounts(account_id),
    service              text NOT NULL,
    region               text NOT NULL,
    resource_id          text,
    usage_type           text NOT NULL,
    usage_quantity       numeric(18,4) NOT NULL,
    net_cost             numeric(18,4) NOT NULL,
    currency             char(3) NOT NULL,
    commitment_eligible  boolean NOT NULL DEFAULT false
);

CREATE TABLE monthly_service_budgets (
    budget_month    date NOT NULL,
    account_id      text NOT NULL REFERENCES cloud_accounts(account_id),
    service         text NOT NULL,
    currency        char(3) NOT NULL,
    budget_amount   numeric(18,4) NOT NULL CHECK (budget_amount >= 0),
    PRIMARY KEY (budget_month, account_id, service, currency)
);

CREATE TABLE commitment_purchases (
    commitment_id             text PRIMARY KEY,
    account_id                text NOT NULL REFERENCES cloud_accounts(account_id),
    service                   text NOT NULL,
    region                    text NOT NULL,
    starts_at                 timestamptz NOT NULL,
    ends_at                   timestamptz NOT NULL,
    hourly_commitment_amount  numeric(18,4) NOT NULL CHECK (hourly_commitment_amount >= 0),
    currency                  char(3) NOT NULL,
    CHECK (ends_at > starts_at)
);

CREATE TABLE invoice_control_totals (
    invoice_month       date NOT NULL,
    account_id          text NOT NULL REFERENCES cloud_accounts(account_id),
    currency            char(3) NOT NULL,
    expected_line_count bigint NOT NULL,
    expected_net_cost   numeric(18,4) NOT NULL,
    PRIMARY KEY (invoice_month, account_id, currency)
);

INSERT INTO cloud_accounts (account_id, account_name, business_unit) VALUES
    ('acct-platform',  'Core Platform',       'Technology'),
    ('acct-analytics', 'Analytics Warehouse', 'Data'),
    ('acct-commerce',  'Commerce Runtime',    'Business');

-- Cost-center ownership changes on 10 November. valid_to is exclusive.
INSERT INTO resource_tag_history
    (resource_id, valid_from, valid_to, owner_team, cost_center, environment)
VALUES
    ('res-api-01',       DATE '2026-10-01', NULL,                 'platform-sre', 'CC-PLATFORM', 'prod'),
    ('res-cache-01',     DATE '2026-10-01', NULL,                 'platform-sre', 'CC-PLATFORM', 'dev'),
    ('res-web-01',       DATE '2026-10-01', NULL,                 'commerce-app', 'CC-COMMERCE', 'prod'),
    ('res-warehouse-01',DATE '2026-10-01', DATE '2026-11-10',    'data-platform','CC-DATA-ENG','prod'),
    ('res-warehouse-01',DATE '2026-11-10', NULL,                 'data-platform','CC-ANALYTICS','prod');

-- Platform compute: one row per day. The 15 November amount is corrected
-- from 82.00 to 88.00. A 3 November delivery is replayed unchanged.
INSERT INTO billing_line_item_deliveries
    (source_line_item_id, source_version, source_updated_at, ingested_at,
     line_status, invoice_month, usage_start, account_id, service, region,
     resource_id, usage_type, usage_quantity, net_cost, currency,
     commitment_eligible)
VALUES
    ('li-p-001', 1, TIMESTAMPTZ '2026-11-01 10:05:00+00', TIMESTAMPTZ '2026-11-01 10:12:00+00', 'ACTIVE', DATE '2026-11-01', TIMESTAMPTZ '2026-11-01 10:00:00+00', 'acct-platform', 'compute', 'ap-south-1', 'res-api-01', 'instance_hours', 2, 12.00, 'USD', true),
    ('li-p-002', 1, TIMESTAMPTZ '2026-11-02 10:05:00+00', TIMESTAMPTZ '2026-11-02 10:12:00+00', 'ACTIVE', DATE '2026-11-01', TIMESTAMPTZ '2026-11-02 10:00:00+00', 'acct-platform', 'compute', 'ap-south-1', 'res-api-01', 'instance_hours', 2, 12.50, 'USD', true),
    ('li-p-003', 1, TIMESTAMPTZ '2026-11-03 10:05:00+00', TIMESTAMPTZ '2026-11-03 10:12:00+00', 'ACTIVE', DATE '2026-11-01', TIMESTAMPTZ '2026-11-03 10:00:00+00', 'acct-platform', 'compute', 'ap-south-1', 'res-api-01', 'instance_hours', 2, 12.80, 'USD', true),
    ('li-p-003', 1, TIMESTAMPTZ '2026-11-03 10:05:00+00', TIMESTAMPTZ '2026-11-03 11:20:00+00', 'ACTIVE', DATE '2026-11-01', TIMESTAMPTZ '2026-11-03 10:00:00+00', 'acct-platform', 'compute', 'ap-south-1', 'res-api-01', 'instance_hours', 2, 12.80, 'USD', true),
    ('li-p-004', 1, TIMESTAMPTZ '2026-11-04 10:05:00+00', TIMESTAMPTZ '2026-11-04 10:12:00+00', 'ACTIVE', DATE '2026-11-01', TIMESTAMPTZ '2026-11-04 10:00:00+00', 'acct-platform', 'compute', 'ap-south-1', 'res-api-01', 'instance_hours', 2, 12.60, 'USD', true),
    ('li-p-005', 1, TIMESTAMPTZ '2026-11-05 10:05:00+00', TIMESTAMPTZ '2026-11-05 10:12:00+00', 'ACTIVE', DATE '2026-11-01', TIMESTAMPTZ '2026-11-05 10:00:00+00', 'acct-platform', 'compute', 'ap-south-1', 'res-api-01', 'instance_hours', 2, 12.90, 'USD', true),
    ('li-p-006', 1, TIMESTAMPTZ '2026-11-06 10:05:00+00', TIMESTAMPTZ '2026-11-06 10:12:00+00', 'ACTIVE', DATE '2026-11-01', TIMESTAMPTZ '2026-11-06 10:00:00+00', 'acct-platform', 'compute', 'ap-south-1', 'res-api-01', 'instance_hours', 2, 12.70, 'USD', true),
    ('li-p-007', 1, TIMESTAMPTZ '2026-11-07 10:05:00+00', TIMESTAMPTZ '2026-11-07 10:12:00+00', 'ACTIVE', DATE '2026-11-01', TIMESTAMPTZ '2026-11-07 10:00:00+00', 'acct-platform', 'compute', 'ap-south-1', 'res-api-01', 'instance_hours', 2, 12.80, 'USD', true),
    ('li-p-008', 1, TIMESTAMPTZ '2026-11-08 10:05:00+00', TIMESTAMPTZ '2026-11-08 10:12:00+00', 'ACTIVE', DATE '2026-11-01', TIMESTAMPTZ '2026-11-08 10:00:00+00', 'acct-platform', 'compute', 'ap-south-1', 'res-api-01', 'instance_hours', 2, 12.60, 'USD', true),
    ('li-p-009', 1, TIMESTAMPTZ '2026-11-09 10:05:00+00', TIMESTAMPTZ '2026-11-09 10:12:00+00', 'ACTIVE', DATE '2026-11-01', TIMESTAMPTZ '2026-11-09 10:00:00+00', 'acct-platform', 'compute', 'ap-south-1', 'res-api-01', 'instance_hours', 2, 12.90, 'USD', true),
    ('li-p-010', 1, TIMESTAMPTZ '2026-11-10 10:05:00+00', TIMESTAMPTZ '2026-11-10 10:12:00+00', 'ACTIVE', DATE '2026-11-01', TIMESTAMPTZ '2026-11-10 10:00:00+00', 'acct-platform', 'compute', 'ap-south-1', 'res-api-01', 'instance_hours', 2, 12.70, 'USD', true),
    ('li-p-011', 1, TIMESTAMPTZ '2026-11-11 10:05:00+00', TIMESTAMPTZ '2026-11-11 10:12:00+00', 'ACTIVE', DATE '2026-11-01', TIMESTAMPTZ '2026-11-11 10:00:00+00', 'acct-platform', 'compute', 'ap-south-1', 'res-api-01', 'instance_hours', 2, 12.80, 'USD', true),
    ('li-p-012', 1, TIMESTAMPTZ '2026-11-12 10:05:00+00', TIMESTAMPTZ '2026-11-12 10:12:00+00', 'ACTIVE', DATE '2026-11-01', TIMESTAMPTZ '2026-11-12 10:00:00+00', 'acct-platform', 'compute', 'ap-south-1', 'res-api-01', 'instance_hours', 2, 12.60, 'USD', true),
    ('li-p-013', 1, TIMESTAMPTZ '2026-11-13 10:05:00+00', TIMESTAMPTZ '2026-11-13 10:12:00+00', 'ACTIVE', DATE '2026-11-01', TIMESTAMPTZ '2026-11-13 10:00:00+00', 'acct-platform', 'compute', 'ap-south-1', 'res-api-01', 'instance_hours', 2, 12.90, 'USD', true),
    ('li-p-014', 1, TIMESTAMPTZ '2026-11-14 10:05:00+00', TIMESTAMPTZ '2026-11-14 10:12:00+00', 'ACTIVE', DATE '2026-11-01', TIMESTAMPTZ '2026-11-14 10:00:00+00', 'acct-platform', 'compute', 'ap-south-1', 'res-api-01', 'instance_hours', 2, 12.70, 'USD', true),
    ('li-p-015', 1, TIMESTAMPTZ '2026-11-15 10:05:00+00', TIMESTAMPTZ '2026-11-15 10:12:00+00', 'ACTIVE', DATE '2026-11-01', TIMESTAMPTZ '2026-11-15 10:00:00+00', 'acct-platform', 'compute', 'ap-south-1', 'res-api-01', 'instance_hours', 2, 82.00, 'USD', true),
    ('li-p-015', 2, TIMESTAMPTZ '2026-11-15 11:00:00+00', TIMESTAMPTZ '2026-11-15 11:05:00+00', 'ACTIVE', DATE '2026-11-01', TIMESTAMPTZ '2026-11-15 10:00:00+00', 'acct-platform', 'compute', 'ap-south-1', 'res-api-01', 'instance_hours', 2, 88.00, 'USD', true),
    ('li-p-016', 1, TIMESTAMPTZ '2026-11-15 12:05:00+00', TIMESTAMPTZ '2026-11-15 12:12:00+00', 'ACTIVE', DATE '2026-11-01', TIMESTAMPTZ '2026-11-15 12:00:00+00', 'acct-platform', 'storage', 'ap-south-1', 'res-cache-01', 'gb_month', 40, 3.25, 'USD', false),
    ('li-p-017', 1, TIMESTAMPTZ '2026-11-15 13:05:00+00', TIMESTAMPTZ '2026-11-15 13:12:00+00', 'ACTIVE', DATE '2026-11-01', TIMESTAMPTZ '2026-11-15 13:00:00+00', 'acct-platform', 'data_transfer', 'ap-south-1', NULL, 'egress_gb', 50, 4.50, 'USD', false),
    ('li-p-018', 1, TIMESTAMPTZ '2026-11-12 15:05:00+00', TIMESTAMPTZ '2026-11-12 15:12:00+00', 'ACTIVE', DATE '2026-11-01', TIMESTAMPTZ '2026-11-12 15:00:00+00', 'acct-platform', 'compute', 'ap-south-1', 'res-api-01', 'provider_credit', 1, -1.50, 'USD', false),
    ('li-p-019', 1, TIMESTAMPTZ '2026-11-15 14:05:00+00', TIMESTAMPTZ '2026-11-15 14:12:00+00', 'ACTIVE', DATE '2026-11-01', TIMESTAMPTZ '2026-11-15 14:00:00+00', 'acct-platform', 'compute', 'ap-south-1', 'res-retired-99', 'instance_hours', 1, 7.75, 'USD', true),
    ('li-p-020', 1, TIMESTAMPTZ '2026-11-15 12:05:00+00', TIMESTAMPTZ '2026-11-15 12:12:00+00', 'ACTIVE', DATE '2026-11-01', TIMESTAMPTZ '2026-11-15 12:00:00+00', 'acct-platform', 'storage', 'ap-south-1', 'res-cache-01', 'gb_month', 10, 5.00, 'USD', false),
    ('li-p-020', 2, TIMESTAMPTZ '2026-11-15 12:20:00+00', TIMESTAMPTZ '2026-11-15 12:25:00+00', 'VOID',   DATE '2026-11-01', TIMESTAMPTZ '2026-11-15 12:00:00+00', 'acct-platform', 'storage', 'ap-south-1', 'res-cache-01', 'gb_month', 10, 5.00, 'USD', false);

-- Analytics warehouse usage spans the cost-center change on 10 November.
INSERT INTO billing_line_item_deliveries
    (source_line_item_id, source_version, source_updated_at, ingested_at,
     line_status, invoice_month, usage_start, account_id, service, region,
     resource_id, usage_type, usage_quantity, net_cost, currency,
     commitment_eligible)
VALUES
    ('li-a-001', 1, TIMESTAMPTZ '2026-11-09 10:05:00+00', TIMESTAMPTZ '2026-11-09 10:12:00+00', 'ACTIVE', DATE '2026-11-01', TIMESTAMPTZ '2026-11-09 10:00:00+00', 'acct-analytics', 'managed_db', 'ap-south-1', 'res-warehouse-01', 'db_instance_hours', 1, 17.50, 'USD', true),
    ('li-a-002', 1, TIMESTAMPTZ '2026-11-11 10:05:00+00', TIMESTAMPTZ '2026-11-11 10:12:00+00', 'ACTIVE', DATE '2026-11-01', TIMESTAMPTZ '2026-11-11 10:00:00+00', 'acct-analytics', 'managed_db', 'ap-south-1', 'res-warehouse-01', 'db_instance_hours', 1, 18.00, 'USD', true),
    ('li-a-003', 1, TIMESTAMPTZ '2026-11-12 10:05:00+00', TIMESTAMPTZ '2026-11-12 10:12:00+00', 'ACTIVE', DATE '2026-11-01', TIMESTAMPTZ '2026-11-12 10:00:00+00', 'acct-analytics', 'managed_db', 'ap-south-1', 'res-warehouse-01', 'db_instance_hours', 1, 18.50, 'USD', true),
    ('li-a-004', 1, TIMESTAMPTZ '2026-11-13 10:05:00+00', TIMESTAMPTZ '2026-11-13 10:12:00+00', 'ACTIVE', DATE '2026-11-01', TIMESTAMPTZ '2026-11-13 10:00:00+00', 'acct-analytics', 'managed_db', 'ap-south-1', 'res-warehouse-01', 'db_instance_hours', 1, 19.00, 'USD', true),
    ('li-a-005', 1, TIMESTAMPTZ '2026-11-14 10:05:00+00', TIMESTAMPTZ '2026-11-14 10:12:00+00', 'ACTIVE', DATE '2026-11-01', TIMESTAMPTZ '2026-11-14 10:00:00+00', 'acct-analytics', 'managed_db', 'ap-south-1', 'res-warehouse-01', 'db_instance_hours', 1, 18.80, 'USD', true),
    ('li-a-006', 1, TIMESTAMPTZ '2026-11-15 10:05:00+00', TIMESTAMPTZ '2026-11-15 10:12:00+00', 'ACTIVE', DATE '2026-11-01', TIMESTAMPTZ '2026-11-15 10:00:00+00', 'acct-analytics', 'managed_db', 'ap-south-1', 'res-warehouse-01', 'db_instance_hours', 1, 20.20, 'USD', true);

INSERT INTO billing_line_item_deliveries
    (source_line_item_id, source_version, source_updated_at, ingested_at,
     line_status, invoice_month, usage_start, account_id, service, region,
     resource_id, usage_type, usage_quantity, net_cost, currency,
     commitment_eligible)
VALUES
    ('li-c-001', 1, TIMESTAMPTZ '2026-11-15 09:05:00+00', TIMESTAMPTZ '2026-11-15 09:12:00+00', 'ACTIVE', DATE '2026-11-01', TIMESTAMPTZ '2026-11-15 09:00:00+00', 'acct-commerce', 'compute', 'ap-south-1', 'res-web-01', 'instance_hours', 1, 6.00, 'USD', true);

INSERT INTO monthly_service_budgets
    (budget_month, account_id, service, currency, budget_amount)
VALUES
    (DATE '2026-11-01', 'acct-platform',  'compute',       'USD', 350.00),
    (DATE '2026-11-01', 'acct-platform',  'storage',       'USD',  30.00),
    (DATE '2026-11-01', 'acct-platform',  'data_transfer', 'USD',  40.00),
    (DATE '2026-11-01', 'acct-analytics', 'managed_db',    'USD', 100.00),
    (DATE '2026-11-01', 'acct-commerce',  'compute',       'USD',  80.00);

INSERT INTO commitment_purchases
    (commitment_id, account_id, service, region, starts_at, ends_at,
     hourly_commitment_amount, currency)
VALUES
    ('commit-platform-compute', 'acct-platform', 'compute', 'ap-south-1',
     TIMESTAMPTZ '2026-11-01 00:00:00+00', TIMESTAMPTZ '2026-12-01 00:00:00+00',
     10.00, 'USD'),
    ('commit-analytics-db', 'acct-analytics', 'managed_db', 'ap-south-1',
     TIMESTAMPTZ '2026-11-01 00:00:00+00', TIMESTAMPTZ '2026-12-01 00:00:00+00',
     5.00, 'USD');

-- The expected count is correct; the provider control amount is intentionally
-- one dollar below the canonical ledger total so Q8 returns an exception.
INSERT INTO invoice_control_totals
    (invoice_month, account_id, currency, expected_line_count, expected_net_cost)
VALUES
    (DATE '2026-11-01', 'acct-platform', 'USD', 19, 278.50);

-- Canonical view: one latest provider version per stable source line ID.
-- A latest VOID row suppresses the earlier ACTIVE version.
CREATE OR REPLACE VIEW canonical_billing_line_items AS
SELECT DISTINCT ON (source_line_item_id)
       delivery_id,
       source_line_item_id,
       source_version,
       source_updated_at,
       ingested_at,
       line_status,
       invoice_month,
       usage_start,
       account_id,
       service,
       region,
       resource_id,
       usage_type,
       usage_quantity,
       net_cost,
       currency,
       commitment_eligible
FROM billing_line_item_deliveries
ORDER BY source_line_item_id,
         source_updated_at DESC,
         source_version DESC,
         ingested_at DESC,
         delivery_id DESC;

-- ----------------------------------------------------------------------------
-- 1. Problem: Canonicalize provider replays, corrections, and voids.
--
-- Return one current row per source_line_item_id. The replay of li-p-003 must
-- count once; li-p-015 must use version 2; li-p-020 must be excluded.
-- ----------------------------------------------------------------------------

-- SOLUTION
SELECT source_line_item_id, source_version, line_status, net_cost, ingested_at
FROM canonical_billing_line_items
WHERE line_status = 'ACTIVE'
ORDER BY source_line_item_id;

-- Optimization:
-- DISTINCT ON is concise for PostgreSQL when its ORDER BY matches a B-tree
-- index. The final delivery_id tie-breaker makes the winner deterministic.
-- Filter VOID only after selecting the latest version; filtering first could
-- incorrectly resurrect an older ACTIVE version of a voided source line.

-- ----------------------------------------------------------------------------
-- 2. Problem: Resolve the resource owner and cost center as of usage time.
--
-- Return the effective tag for every active billing line. A resource can move
-- cost centers during the month; usage before and after 10 November must use
-- different tag versions. Keep untagged and resource-less rows visible.
-- ----------------------------------------------------------------------------

-- SOLUTION
SELECT
    b.source_line_item_id,
    b.usage_start,
    b.account_id,
    b.service,
    b.resource_id,
    t.owner_team,
    t.cost_center,
    t.environment
FROM canonical_billing_line_items AS b
LEFT JOIN LATERAL (
    SELECT h.owner_team, h.cost_center, h.environment
    FROM resource_tag_history AS h
    WHERE h.resource_id = b.resource_id
      AND h.valid_from <= b.usage_start::date
      AND (h.valid_to IS NULL OR b.usage_start::date < h.valid_to)
    ORDER BY h.valid_from DESC, h.tag_version_id DESC
    LIMIT 1
) AS t ON true
WHERE b.line_status = 'ACTIVE'
ORDER BY b.usage_start, b.source_line_item_id;

-- Optimization:
-- LATERAL performs an indexed top-one lookup per resource instead of joining
-- every historical tag version and ranking the expanded result. Half-open
-- validity intervals avoid assigning an event to two adjacent versions.
-- For high-volume workloads, validate tag-period non-overlap at ingestion.

-- ----------------------------------------------------------------------------
-- 3. Problem: Produce monthly spend by account, service, and currency.
--
-- Include credits as negative spend. Do not combine different currencies.
-- Use a half-open UTC range for November 2026.
-- ----------------------------------------------------------------------------

-- SOLUTION
SELECT
    b.account_id,
    b.service,
    b.currency,
    date_trunc('month', b.usage_start)::date AS usage_month,
    COUNT(*) AS line_count,
    SUM(b.net_cost) AS net_spend
FROM canonical_billing_line_items AS b
WHERE b.line_status = 'ACTIVE'
  AND b.usage_start >= TIMESTAMPTZ '2026-11-01 00:00:00+00'
  AND b.usage_start <  TIMESTAMPTZ '2026-12-01 00:00:00+00'
GROUP BY b.account_id, b.service, b.currency,
         date_trunc('month', b.usage_start)::date
ORDER BY b.account_id, b.service, b.currency;

-- Optimization:
-- The timestamp predicate is SARGable and can use a range index or partition
-- pruning. Avoid WHERE date(usage_start) = ... because applying a function to
-- the indexed column can prevent a normal timestamp index from being used.

-- ----------------------------------------------------------------------------
-- 4. Problem: Calculate month-to-date budget variance and a simple run-rate.
--
-- As of 15 November 2026, show actual spend, budget consumed, projected
-- month-end spend, and projected over/under budget by account and service.
-- ----------------------------------------------------------------------------

-- SOLUTION
WITH params AS (
    SELECT DATE '2026-11-15' AS as_of_date
),
mtd AS (
    SELECT
        b.account_id,
        b.service,
        b.currency,
        SUM(b.net_cost) AS mtd_spend
    FROM canonical_billing_line_items AS b
    CROSS JOIN params AS p
    WHERE b.line_status = 'ACTIVE'
      AND b.usage_start >= date_trunc('month', p.as_of_date)::date
      AND b.usage_start <  (p.as_of_date + 1)::timestamp
    GROUP BY b.account_id, b.service, b.currency
)
SELECT
    m.account_id,
    m.service,
    m.currency,
    m.mtd_spend,
    bud.budget_amount,
    ROUND(100.0 * m.mtd_spend / NULLIF(bud.budget_amount, 0), 2)
        AS budget_consumed_pct,
    ROUND(
        m.mtd_spend
        / (EXTRACT(DAY FROM p.as_of_date))
        * EXTRACT(DAY FROM (
            date_trunc('month', p.as_of_date) + INTERVAL '1 month - 1 day'
          )),
        2
    ) AS projected_month_end_spend,
    ROUND(
        m.mtd_spend
        / EXTRACT(DAY FROM p.as_of_date)
        * EXTRACT(DAY FROM (
            date_trunc('month', p.as_of_date) + INTERVAL '1 month - 1 day'
          ))
        - bud.budget_amount,
        2
    ) AS projected_budget_variance
FROM mtd AS m
JOIN monthly_service_budgets AS bud
  ON bud.budget_month = date_trunc('month', (SELECT as_of_date FROM params))::date
 AND bud.account_id = m.account_id
 AND bud.service = m.service
 AND bud.currency = m.currency
CROSS JOIN params AS p
ORDER BY projected_budget_variance DESC;

-- Optimization:
-- Aggregate billing rows once at the account/service/currency grain before
-- joining the small budget table. NULLIF protects division. This straight-line
-- run-rate is a baseline, not a forecast model: seasonality and billing lag
-- should be handled separately in production.

-- ----------------------------------------------------------------------------
-- 5. Problem: Measure hourly commitment utilization and uncovered eligible cost.
--
-- Aggregate eligible usage to hour first, then compare it with active
-- commitment capacity for the same account/service/region/currency.
-- ----------------------------------------------------------------------------

-- SOLUTION
WITH eligible_hourly_usage AS (
    SELECT
        b.account_id,
        b.service,
        b.region,
        b.currency,
        date_trunc('hour', b.usage_start) AS usage_hour,
        SUM(GREATEST(b.net_cost, 0)) AS eligible_usage_cost
    FROM canonical_billing_line_items AS b
    WHERE b.line_status = 'ACTIVE'
      AND b.commitment_eligible
      AND b.usage_start >= TIMESTAMPTZ '2026-11-01 00:00:00+00'
      AND b.usage_start <  TIMESTAMPTZ '2026-12-01 00:00:00+00'
    GROUP BY b.account_id, b.service, b.region, b.currency,
             date_trunc('hour', b.usage_start)
),
hourly_capacity AS (
    SELECT
        u.account_id,
        u.service,
        u.region,
        u.currency,
        u.usage_hour,
        u.eligible_usage_cost,
        COALESCE(SUM(c.hourly_commitment_amount), 0) AS commitment_capacity
    FROM eligible_hourly_usage AS u
    LEFT JOIN commitment_purchases AS c
      ON c.account_id = u.account_id
     AND c.service = u.service
     AND c.region = u.region
     AND c.currency = u.currency
     AND c.starts_at <= u.usage_hour
     AND c.ends_at > u.usage_hour
    GROUP BY u.account_id, u.service, u.region, u.currency,
             u.usage_hour, u.eligible_usage_cost
)
SELECT
    account_id,
    service,
    region,
    usage_hour,
    eligible_usage_cost,
    commitment_capacity,
    LEAST(eligible_usage_cost, commitment_capacity) AS estimated_covered_cost,
    GREATEST(eligible_usage_cost - commitment_capacity, 0) AS uncovered_cost,
    ROUND(
        100.0 * LEAST(eligible_usage_cost, commitment_capacity)
        / NULLIF(commitment_capacity, 0),
        2
    ) AS commitment_utilization_pct
FROM hourly_capacity
ORDER BY usage_hour, account_id, service;

-- Optimization:
-- Pre-aggregation prevents multiplying usage rows when multiple commitments
-- are active in the same hour. SUM of active commitment capacity is explicit;
-- finance teams should separately model commitment fees, amortization,
-- sharing rules, and provider-specific coverage priority.

-- ----------------------------------------------------------------------------
-- 6. Problem: Find unallocated cloud spend.
--
-- Flag active line items with no resource ID, no effective tag, or a missing
-- cost center. Keep the cost amount so the FinOps queue can be prioritized.
-- ----------------------------------------------------------------------------

-- SOLUTION
SELECT
    b.source_line_item_id,
    b.account_id,
    b.service,
    b.usage_start,
    b.resource_id,
    b.net_cost,
    CASE
        WHEN b.resource_id IS NULL THEN 'MISSING_RESOURCE_ID'
        WHEN t.tag_version_id IS NULL THEN 'NO_EFFECTIVE_TAG'
        WHEN NULLIF(BTRIM(t.cost_center), '') IS NULL THEN 'MISSING_COST_CENTER'
    END AS allocation_exception
FROM canonical_billing_line_items AS b
LEFT JOIN LATERAL (
    SELECT h.tag_version_id, h.cost_center
    FROM resource_tag_history AS h
    WHERE h.resource_id = b.resource_id
      AND h.valid_from <= b.usage_start::date
      AND (h.valid_to IS NULL OR b.usage_start::date < h.valid_to)
    ORDER BY h.valid_from DESC, h.tag_version_id DESC
    LIMIT 1
) AS t ON true
WHERE b.line_status = 'ACTIVE'
  AND (
      b.resource_id IS NULL
      OR t.tag_version_id IS NULL
      OR NULLIF(BTRIM(t.cost_center), '') IS NULL
  )
ORDER BY b.net_cost DESC;

-- Optimization:
-- The predicates are evaluated after one latest-tag lookup per billing line.
-- A production pipeline should quarantine unallocated rows and publish both
-- allocated and unallocated totals so missing tags cannot silently disappear.

-- ----------------------------------------------------------------------------
-- 7. Problem: Rank cost-center spend and calculate each center's share.
--
-- Attribute November cost using the effective tag at usage time. Report
-- unallocated spend as its own bucket and rank within each account/currency.
-- ----------------------------------------------------------------------------

-- SOLUTION
WITH attributed AS (
    SELECT
        b.account_id,
        b.currency,
        COALESCE(t.cost_center, 'UNALLOCATED') AS cost_center,
        SUM(b.net_cost) AS net_spend
    FROM canonical_billing_line_items AS b
    LEFT JOIN LATERAL (
        SELECT h.cost_center
        FROM resource_tag_history AS h
        WHERE h.resource_id = b.resource_id
          AND h.valid_from <= b.usage_start::date
          AND (h.valid_to IS NULL OR b.usage_start::date < h.valid_to)
        ORDER BY h.valid_from DESC, h.tag_version_id DESC
        LIMIT 1
    ) AS t ON true
    WHERE b.line_status = 'ACTIVE'
      AND b.usage_start >= TIMESTAMPTZ '2026-11-01 00:00:00+00'
      AND b.usage_start <  TIMESTAMPTZ '2026-12-01 00:00:00+00'
    GROUP BY b.account_id, b.currency, COALESCE(t.cost_center, 'UNALLOCATED')
),
ranked AS (
    SELECT
        a.*,
        SUM(a.net_spend) OVER (
            PARTITION BY a.account_id, a.currency
        ) AS account_total,
        DENSE_RANK() OVER (
            PARTITION BY a.account_id, a.currency
            ORDER BY a.net_spend DESC
        ) AS cost_center_rank
    FROM attributed AS a
)
SELECT
    account_id,
    currency,
    cost_center,
    net_spend,
    cost_center_rank,
    ROUND(100.0 * net_spend / NULLIF(account_total, 0), 2) AS spend_share_pct
FROM ranked
ORDER BY account_id, cost_center_rank, cost_center;

-- Optimization:
-- Aggregate to the reporting grain before applying window functions. This
-- keeps the window sort proportional to the number of cost centers rather
-- than the raw billing-line count. Preserve negative credits in net spend.

-- ----------------------------------------------------------------------------
-- 8. Problem: Reconcile canonical billing rows to provider invoice controls.
--
-- Compare line count and net amount by invoice month, account, and currency.
-- FULL OUTER JOIN is required to expose controls with no source rows and
-- source rows with no control record.
-- ----------------------------------------------------------------------------

-- SOLUTION
WITH source_totals AS (
    SELECT
        b.invoice_month,
        b.account_id,
        b.currency,
        COUNT(*) AS actual_line_count,
        SUM(b.net_cost) AS actual_net_cost
    FROM canonical_billing_line_items AS b
    WHERE b.line_status = 'ACTIVE'
    GROUP BY b.invoice_month, b.account_id, b.currency
),
reconciliation AS (
    SELECT
        COALESCE(s.invoice_month, c.invoice_month) AS invoice_month,
        COALESCE(s.account_id, c.account_id) AS account_id,
        COALESCE(s.currency, c.currency) AS currency,
        COALESCE(s.actual_line_count, 0) AS actual_line_count,
        COALESCE(c.expected_line_count, 0) AS expected_line_count,
        COALESCE(s.actual_net_cost, 0) AS actual_net_cost,
        COALESCE(c.expected_net_cost, 0) AS expected_net_cost
    FROM source_totals AS s
    FULL OUTER JOIN invoice_control_totals AS c
      ON c.invoice_month = s.invoice_month
     AND c.account_id = s.account_id
     AND c.currency = s.currency
)
SELECT
    *,
    actual_line_count - expected_line_count AS line_count_delta,
    actual_net_cost - expected_net_cost AS net_cost_delta,
    CASE
        WHEN actual_line_count <> expected_line_count
          OR ABS(actual_net_cost - expected_net_cost) > 0.01
        THEN 'EXCEPTION'
        ELSE 'MATCH'
    END AS reconciliation_status
FROM reconciliation
ORDER BY invoice_month, account_id, currency;

-- Optimization:
-- Aggregate each side to the exact reconciliation key before joining. This
-- avoids detail-level fanout and makes missing-on-either-side cases visible.
-- Tolerance is currency-specific in production; do not hard-code 0.01 for
-- currencies with different minor-unit rules.

-- ----------------------------------------------------------------------------
-- 9. Problem: Detect daily spend anomalies against the prior seven calendar days.
--
-- Build a dense date spine so ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING means
-- seven calendar days, even when a service has no usage on a particular day.
-- Flag 15 November's platform-compute spike.
-- ----------------------------------------------------------------------------

-- SOLUTION
WITH daily_spend AS (
    SELECT
        b.account_id,
        b.service,
        b.usage_start::date AS usage_day,
        SUM(b.net_cost) AS daily_cost
    FROM canonical_billing_line_items AS b
    WHERE b.line_status = 'ACTIVE'
      AND b.usage_start >= TIMESTAMPTZ '2026-11-01 00:00:00+00'
      AND b.usage_start <  TIMESTAMPTZ '2026-11-16 00:00:00+00'
    GROUP BY b.account_id, b.service, b.usage_start::date
),
account_services AS (
    SELECT DISTINCT account_id, service
    FROM daily_spend
),
calendar AS (
    SELECT
        k.account_id,
        k.service,
        g.day::date AS usage_day
    FROM account_services AS k
    CROSS JOIN generate_series(
        DATE '2026-11-01',
        DATE '2026-11-15',
        INTERVAL '1 day'
    ) AS g(day)
),
dense_daily AS (
    SELECT
        c.account_id,
        c.service,
        c.usage_day,
        COALESCE(d.daily_cost, 0) AS daily_cost
    FROM calendar AS c
    LEFT JOIN daily_spend AS d
      ON d.account_id = c.account_id
     AND d.service = c.service
     AND d.usage_day = c.usage_day
),
scored AS (
    SELECT
        d.*,
        COUNT(*) OVER (
            PARTITION BY account_id, service
            ORDER BY usage_day
            ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING
        ) AS baseline_days,
        AVG(daily_cost) OVER (
            PARTITION BY account_id, service
            ORDER BY usage_day
            ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING
        ) AS baseline_avg,
        STDDEV_SAMP(daily_cost) OVER (
            PARTITION BY account_id, service
            ORDER BY usage_day
            ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING
        ) AS baseline_stddev
    FROM dense_daily AS d
)
SELECT
    account_id,
    service,
    usage_day,
    daily_cost,
    ROUND(baseline_avg, 2) AS baseline_avg,
    ROUND(baseline_stddev, 2) AS baseline_stddev,
    ROUND(
        (daily_cost - baseline_avg) / NULLIF(baseline_stddev, 0),
        2
    ) AS z_score
FROM scored
WHERE usage_day = DATE '2026-11-15'
  AND baseline_days = 7
  AND daily_cost > baseline_avg + 3 * COALESCE(baseline_stddev, 0)
  AND daily_cost > baseline_avg * 2
ORDER BY daily_cost DESC;

-- Optimization:
-- Daily aggregation happens before the date spine and window calculation.
-- The spine is bounded to the report window and only includes observed
-- account/service pairs. For large estates, persist daily aggregates rather
-- than rebuilding a dense account x service x calendar product on every run.
-- A z-score is a triage signal, not proof of waste or a billing defect.

-- ----------------------------------------------------------------------------
-- 10. Performance lab: candidate indexes and plan inspection
-- ----------------------------------------------------------------------------

-- Run these separately in a maintenance window. CREATE INDEX CONCURRENTLY
-- cannot run inside an explicit transaction block.

-- Supports deterministic latest-version retrieval by stable provider ID.
-- CREATE INDEX CONCURRENTLY ix_billing_latest_delivery
--     ON billing_line_item_deliveries
--        (source_line_item_id, source_updated_at DESC,
--         source_version DESC, ingested_at DESC, delivery_id DESC);

-- Supports time-bounded account/service investigations.
-- CREATE INDEX CONCURRENTLY ix_billing_usage_account_service
--     ON billing_line_item_deliveries
--        (usage_start, account_id, service)
--     INCLUDE (net_cost, currency, region, resource_id, line_status);

-- Supports effective-dated resource-tag lookups.
-- CREATE INDEX CONCURRENTLY ix_resource_tag_asof
--     ON resource_tag_history (resource_id, valid_from DESC, tag_version_id DESC)
--     INCLUDE (valid_to, owner_team, cost_center, environment);

-- Supports commitment-window candidate lookup.
-- CREATE INDEX CONCURRENTLY ix_commitment_lookup
--     ON commitment_purchases (account_id, service, region, starts_at, ends_at);

-- On very large append-only billing tables, benchmark a BRIN index on
-- usage_start when physical row order correlates with event time. Consider
-- monthly range partitioning for retention and partition pruning.

-- Compare plans with representative production-scale data:
-- EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
-- SELECT account_id, service, SUM(net_cost)
-- FROM billing_line_item_deliveries
-- WHERE usage_start >= TIMESTAMPTZ '2026-11-01 00:00:00+00'
--   AND usage_start <  TIMESTAMPTZ '2026-12-01 00:00:00+00'
-- GROUP BY account_id, service;

-- Useful production notes:
-- 1. Keep raw deliveries immutable; canonicalization must choose the latest
--    version first and only then suppress a latest VOID record.
-- 2. Keep all monetary calculations at (amount, currency) grain until an
--    explicit FX conversion policy and rate timestamp are applied.
-- 3. Validate non-overlapping resource-tag validity ranges. An exclusion
--    constraint over daterange(resource_id, validity) with GiST can help.
-- 4. Separate usage cost, commitment amortization, credits, taxes, and support
--    fees. Provider invoice semantics differ and should be documented.
-- 5. Use half-open time predicates [start, end) consistently for UTC windows.
-- 6. Run ANALYZE after bulk loads; compare estimated versus actual row counts.
-- 7. Benchmark indexes with realistic cardinality and skew. More indexes slow
--    ingestion and increase storage; a small seed dataset proves no benefit.
-- 8. For incremental FinOps pipelines, persist a source watermark and reprocess
--    a bounded late-arrival window; reconcile the reopened invoice periods.

-- Expected spot checks:
-- - Q1 returns one active row for li-p-003 and version 2 / 88.00 for li-p-015.
-- - Q1 excludes li-p-020 because its latest provider version is VOID.
-- - Q2 attributes res-warehouse-01 on 9 Nov to CC-DATA-ENG and on 11 Nov
--   to CC-ANALYTICS.
-- - Q6 identifies the resource-less transfer line and res-retired-99.
-- - Q8 reports a 1.00 USD difference for acct-platform.
-- - Q9 flags acct-platform / compute on 15 Nov because the daily cost is
--   materially above its preceding seven-calendar-day baseline.
