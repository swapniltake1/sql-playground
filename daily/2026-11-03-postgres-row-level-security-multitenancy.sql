/*
===============================================================================
Daily SQL Practice — 2026-11-03
Topic: PostgreSQL Row-Level Security (RLS) for Multi-Tenant Analytics
Target: PostgreSQL 14+

PROBLEM STATEMENT
A SaaS analytics platform stores orders for multiple tenants in shared tables.
Build tenant isolation at the database layer, ensure reads and writes cannot
cross tenant boundaries, and keep tenant context safe when connections are
reused from a pool.

Run as a database owner/administrator in a disposable practice database.
This script recreates the isolated tenant_demo schema. The demo role is
NOLOGIN; grant it to a dedicated application login in a real test environment.

IMPORTANT SECURITY NOTE
The custom setting app.tenant_id below is a context carrier, not proof of
identity. A user who can issue arbitrary SQL can set a custom GUC themselves.
In production, set it only from trusted server-side authentication middleware,
or use a stronger identity-to-tenant mechanism. Superusers and roles with
BYPASSRLS always bypass row security.

===============================================================================
*/

-- ----------------------------------------------------------------------------
-- 0. Isolated schema, non-bypass test role, tables, and realistic sample data
-- ----------------------------------------------------------------------------

DROP SCHEMA IF EXISTS tenant_demo CASCADE;
CREATE SCHEMA tenant_demo;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_roles
        WHERE rolname = 'tenant_demo_app'
    ) THEN
        EXECUTE
            'CREATE ROLE tenant_demo_app NOLOGIN NOSUPERUSER NOBYPASSRLS';
    ELSE
        EXECUTE
            'ALTER ROLE tenant_demo_app NOSUPERUSER NOBYPASSRLS';
    END IF;
END
$$;

CREATE TABLE tenant_demo.customers (
    tenant_id       uuid        NOT NULL,
    customer_id     bigint      NOT NULL,
    customer_name   text        NOT NULL,
    segment          text        NOT NULL,
    PRIMARY KEY (tenant_id, customer_id)
);

CREATE TABLE tenant_demo.orders (
    tenant_id          uuid           NOT NULL,
    order_id           bigint         NOT NULL,
    customer_id        bigint         NOT NULL,
    external_order_ref text           NOT NULL,
    order_ts           timestamptz    NOT NULL,
    status             text           NOT NULL
        CHECK (status IN ('OPEN', 'PAID', 'CANCELLED')),
    amount             numeric(12, 2) NOT NULL CHECK (amount >= 0),
    PRIMARY KEY (tenant_id, order_id),
    UNIQUE (tenant_id, external_order_ref),
    FOREIGN KEY (tenant_id, customer_id)
        REFERENCES tenant_demo.customers (tenant_id, customer_id)
);

INSERT INTO tenant_demo.customers
    (tenant_id, customer_id, customer_name, segment)
VALUES
    ('11111111-1111-4111-8111-111111111111', 101, 'Anaya Retail', 'ENTERPRISE'),
    ('11111111-1111-4111-8111-111111111111', 102, 'Beacon Foods', 'SMB'),
    ('22222222-2222-4222-8222-222222222222', 201, 'Cedar Stores', 'ENTERPRISE'),
    ('22222222-2222-4222-8222-222222222222', 202, 'Delta Health', 'HEALTHCARE');

INSERT INTO tenant_demo.orders
    (tenant_id, order_id, customer_id, external_order_ref,
     order_ts, status, amount)
VALUES
    ('11111111-1111-4111-8111-111111111111', 5001, 101, 'A-5001',
     '2026-11-01 09:15:00+05:30', 'PAID', 1250.00),
    ('11111111-1111-4111-8111-111111111111', 5002, 101, 'A-5002',
     '2026-11-02 10:30:00+05:30', 'OPEN', 450.00),
    ('11111111-1111-4111-8111-111111111111', 5003, 102, 'A-5003',
     '2026-11-02 14:45:00+05:30', 'PAID', 820.00),
    -- The same order_id is valid for a different tenant.
    ('22222222-2222-4222-8222-222222222222', 5001, 201, 'B-5001',
     '2026-11-01 11:00:00+05:30', 'PAID', 2100.00),
    ('22222222-2222-4222-8222-222222222222', 5002, 202, 'B-5002',
     '2026-11-02 12:00:00+05:30', 'CANCELLED', 300.00),
    ('22222222-2222-4222-8222-222222222222', 5003, 201, 'B-5003',
     '2026-11-03 08:00:00+05:30', 'OPEN', 975.00);

-- RLS is enabled and forced so the table owner is subject to policies too.
-- Superusers and BYPASSRLS roles remain exempt.
ALTER TABLE tenant_demo.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_demo.customers FORCE ROW LEVEL SECURITY;
ALTER TABLE tenant_demo.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_demo.orders FORCE ROW LEVEL SECURITY;

CREATE POLICY customers_tenant_isolation
ON tenant_demo.customers
FOR ALL
TO tenant_demo_app
USING (
    tenant_id =
    NULLIF(current_setting('app.tenant_id', true), '')::uuid
)
WITH CHECK (
    tenant_id =
    NULLIF(current_setting('app.tenant_id', true), '')::uuid
);

CREATE POLICY orders_tenant_isolation
ON tenant_demo.orders
FOR ALL
TO tenant_demo_app
USING (
    tenant_id =
    NULLIF(current_setting('app.tenant_id', true), '')::uuid
)
WITH CHECK (
    tenant_id =
    NULLIF(current_setting('app.tenant_id', true), '')::uuid
);

REVOKE ALL ON tenant_demo.customers, tenant_demo.orders FROM PUBLIC;
GRANT USAGE ON SCHEMA tenant_demo TO tenant_demo_app;
GRANT SELECT, INSERT, UPDATE, DELETE
ON tenant_demo.customers, tenant_demo.orders
TO tenant_demo_app;

-- ----------------------------------------------------------------------------
-- Q1. Problem: Return only the current tenant's orders.
-- Expected: tenant A sees order IDs 5001, 5002, and 5003 (three rows).
-- ----------------------------------------------------------------------------

SET ROLE tenant_demo_app;
BEGIN;
SET LOCAL app.tenant_id = '11111111-1111-4111-8111-111111111111';

SELECT order_id, customer_id, status, amount
FROM tenant_demo.orders
ORDER BY order_id;

-- Assertion: fail fast if the tenant boundary returns an unexpected row count.
DO $$
DECLARE
    v_count bigint;
BEGIN
    SELECT count(*) INTO v_count
    FROM tenant_demo.orders;

    IF v_count <> 3 THEN
        RAISE EXCEPTION 'Q1 expected 3 tenant-A orders, found %', v_count;
    END IF;
END
$$;

COMMIT;
RESET ROLE;

-- Explanation:
-- The policy predicate is injected by PostgreSQL even though the query has no
-- explicit tenant_id filter. Keep an explicit tenant predicate in application
-- SQL when useful for clarity and plan stability, but do not rely on it as the
-- security boundary; RLS is the enforcement layer.

-- ----------------------------------------------------------------------------
-- Q2. Problem: Prove that a missing tenant context fails closed.
-- Expected: zero visible orders and zero visible customers.
-- ----------------------------------------------------------------------------

SET ROLE tenant_demo_app;
BEGIN;

SELECT
    (SELECT count(*) FROM tenant_demo.orders)    AS visible_orders,
    (SELECT count(*) FROM tenant_demo.customers) AS visible_customers;

-- Expected output: 0 | 0
DO $$
DECLARE
    v_orders bigint;
    v_customers bigint;
BEGIN
    SELECT count(*) INTO v_orders FROM tenant_demo.orders;
    SELECT count(*) INTO v_customers FROM tenant_demo.customers;

    IF v_orders <> 0 OR v_customers <> 0 THEN
        RAISE EXCEPTION
            'Q2 expected fail-closed access; orders %, customers %',
            v_orders, v_customers;
    END IF;
END
$$;

ROLLBACK;
RESET ROLE;

-- Explanation:
-- current_setting(..., true) returns NULL when the setting is absent.
-- tenant_id = NULL evaluates to UNKNOWN, so no row passes the policy.

-- ----------------------------------------------------------------------------
-- Q3. Problem: Enforce tenant ownership for INSERT and UPDATE.
-- Expected: tenant A cannot insert a row carrying tenant B's tenant_id.
-- ----------------------------------------------------------------------------

-- This intentionally failing statement is shown as an interview test.
-- Run it separately inside a transaction; PostgreSQL should raise an RLS
-- WITH CHECK violation. The matching customer exists, so the FK is not the
-- reason for rejection.
--
-- SET ROLE tenant_demo_app;
-- BEGIN;
-- SET LOCAL app.tenant_id = '11111111-1111-4111-8111-111111111111';
-- INSERT INTO tenant_demo.orders
--     (tenant_id, order_id, customer_id, external_order_ref,
--      order_ts, status, amount)
-- VALUES
--     ('22222222-2222-4222-8222-222222222222', 5999, 201, 'B-5999',
--      '2026-11-03 09:00:00+05:30', 'OPEN', 100.00);
-- -- Expected: new row violates row-level security policy for table "orders".
-- ROLLBACK;
-- RESET ROLE;

-- Optimized/valid write path: derive tenant_id from trusted request context,
-- and still let WITH CHECK validate it at the database boundary.
SET ROLE tenant_demo_app;
BEGIN;
SET LOCAL app.tenant_id = '11111111-1111-4111-8111-111111111111';

INSERT INTO tenant_demo.orders
    (tenant_id, order_id, customer_id, external_order_ref,
     order_ts, status, amount)
VALUES
    ('11111111-1111-4111-8111-111111111111', 5004, 102, 'A-5004',
     '2026-11-03 09:30:00+05:30', 'OPEN', 275.00);

-- Expected: one row inserted for tenant A.
SELECT count(*) AS tenant_a_orders_after_insert
FROM tenant_demo.orders;

ROLLBACK;
RESET ROLE;

-- Explanation:
-- USING controls which existing rows can be seen/targeted.
-- WITH CHECK controls the new row version produced by INSERT or UPDATE.
-- The transaction is rolled back so the sample remains deterministic.

-- ----------------------------------------------------------------------------
-- Q4. Problem: Join tenant-scoped orders to customers and aggregate by segment.
-- Expected for tenant A: ENTERPRISE = 2 orders / 1700.00;
--                        SMB        = 1 order  /  820.00.
-- ----------------------------------------------------------------------------

SET ROLE tenant_demo_app;
BEGIN;
SET LOCAL app.tenant_id = '11111111-1111-4111-8111-111111111111';

SELECT
    c.segment,
    count(*) AS order_count,
    sum(o.amount) AS gross_amount
FROM tenant_demo.orders AS o
JOIN tenant_demo.customers AS c
  ON c.tenant_id = o.tenant_id
 AND c.customer_id = o.customer_id
WHERE o.status <> 'CANCELLED'
GROUP BY c.segment
ORDER BY c.segment;

COMMIT;
RESET ROLE;

-- Optimization explanation:
-- Join on the full tenant-aware key, not customer_id alone. Both tables have
-- composite primary keys beginning with tenant_id. RLS filters each relation;
-- the explicit tenant-aware join also prevents accidental cross-tenant matches.

-- ----------------------------------------------------------------------------
-- Q5. Problem: Set tenant context safely when connections are pooled.
-- Expected: the setting is local to this transaction and resets at COMMIT.
-- ----------------------------------------------------------------------------

SET ROLE tenant_demo_app;
BEGIN;

-- true = transaction-local; equivalent to SET LOCAL for this custom setting.
SELECT set_config(
    'app.tenant_id',
    '22222222-2222-4222-8222-222222222222',
    true
) AS applied_tenant_context;

SELECT order_id, status, amount
FROM tenant_demo.orders
ORDER BY order_id;

COMMIT;

-- A new transaction on the same session has no tenant context.
BEGIN;
SELECT count(*) AS rows_without_context
FROM tenant_demo.orders; -- Expected: 0
ROLLBACK;
RESET ROLE;

-- Performance/reliability explanation:
-- Prefer SET LOCAL or set_config(..., true) inside an explicit transaction.
-- A session-level SET can leak one request's tenant context to the next user
-- when a connection pool reuses the same backend connection. Ensure the
-- context-setting statement and protected queries use the same transaction.

-- ----------------------------------------------------------------------------
-- Q6. Problem: Inspect policy composition and explain permissive vs restrictive.
-- Expected: one tenant-isolation policy per table, marked PERMISSIVE by default.
-- ----------------------------------------------------------------------------

SELECT
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual,
    with_check
FROM pg_policies
WHERE schemaname = 'tenant_demo'
ORDER BY tablename, policyname;

-- Important interview trap:
-- PostgreSQL combines applicable PERMISSIVE policies with OR. Adding a second
-- permissive policy such as:
--
--   CREATE POLICY orders_open_rows
--   ON tenant_demo.orders FOR SELECT TO tenant_demo_app
--   USING (status = 'OPEN');
--
-- would allow rows satisfying tenant_isolation OR status = 'OPEN', potentially
-- exposing OPEN rows belonging to other tenants.
--
-- If an additional condition must narrow access, use a RESTRICTIVE policy
-- (which is ANDed with permissive policies), for example:
--
--   CREATE POLICY orders_open_only
--   ON tenant_demo.orders AS RESTRICTIVE
--   FOR SELECT TO tenant_demo_app
--   USING (status = 'OPEN');
--
-- Drop that optional policy after the demonstration:
--   DROP POLICY orders_open_only ON tenant_demo.orders;

-- ----------------------------------------------------------------------------
-- Q7. Problem: Add indexes for tenant-scoped time-range and status queries.
-- Expected: query results remain unchanged; inspect the actual plan at scale.
-- ----------------------------------------------------------------------------

CREATE INDEX orders_tenant_status_ts_idx
ON tenant_demo.orders (tenant_id, status, order_ts DESC)
INCLUDE (order_id, customer_id, amount);

CREATE INDEX customers_tenant_segment_idx
ON tenant_demo.customers (tenant_id, segment, customer_id);

SET ROLE tenant_demo_app;
BEGIN;
SET LOCAL app.tenant_id = '11111111-1111-4111-8111-111111111111';

EXPLAIN (ANALYZE, BUFFERS)
SELECT order_id, customer_id, order_ts, amount
FROM tenant_demo.orders
WHERE status = 'PAID'
  AND order_ts >= timestamptz '2026-11-01 00:00:00+05:30'
  AND order_ts <  timestamptz '2026-11-04 00:00:00+05:30'
ORDER BY order_ts DESC;

COMMIT;
RESET ROLE;

-- Optimization explanation:
-- Equality columns precede the timestamp range/order column. INCLUDE can make
-- the query eligible for an index-only scan when visibility-map conditions
-- permit it. RLS contributes a tenant_id predicate to the plan.
--
-- Do not assume an index is beneficial for six rows. Benchmark with realistic
-- cardinality, tenant skew, write volume, and EXPLAIN (ANALYZE, BUFFERS).
-- Too many indexes increase INSERT/UPDATE cost and storage.

-- ----------------------------------------------------------------------------
-- Q8. Problem: Validate tenant-aware referential integrity and key design.
-- Expected: no orphan rows. The same order_id may exist in two tenants, but
-- a customer reference must match both tenant_id and customer_id.
-- ----------------------------------------------------------------------------

-- The composite FK prevents an order for tenant A from referencing tenant B's
-- customer, even if the customer_id value happens to be the same.
SELECT
    o.tenant_id,
    o.order_id,
    o.customer_id
FROM tenant_demo.orders AS o
LEFT JOIN tenant_demo.customers AS c
  ON c.tenant_id = o.tenant_id
 AND c.customer_id = o.customer_id
WHERE c.customer_id IS NULL;

-- Expected: zero rows.

-- Demonstrate tenant-aware key reuse:
SELECT tenant_id, order_id, external_order_ref
FROM tenant_demo.orders
WHERE order_id = 5001
ORDER BY tenant_id;

-- Expected: two rows, one for each tenant. This is valid because the primary
-- key is (tenant_id, order_id), not order_id alone.

-- ----------------------------------------------------------------------------
-- PERFORMANCE & PRODUCTION NOTES
-- ----------------------------------------------------------------------------
-- 1. Index tenant_id first for the dominant equality-scoped access pattern;
--    append common filters/order columns based on measured workload.
-- 2. Use composite PKs, UNIQUE constraints, and FKs that include tenant_id.
-- 3. Keep RLS predicates simple, immutable where possible, and inexpensive.
--    Avoid per-row network calls or volatile lookup functions in policy logic.
-- 4. RLS is defense in depth, not authentication. Never trust a tenant ID
--    supplied directly by an untrusted browser/client.
-- 5. Ensure application roles are neither SUPERUSER nor BYPASSRLS and do not
--    own protected tables. FORCE ROW LEVEL SECURITY also subjects table owners
--    to policies, but cannot constrain superusers/BYPASSRLS roles.
-- 6. Review views, SECURITY DEFINER functions, materialized views, exports,
--    background jobs, and ETL service accounts separately; they can create
--    alternate access paths if granted excessive privileges.
-- 7. Test with the exact runtime role and pooled-connection lifecycle.
-- 8. For very large tenants, evaluate partitioning only after measuring skew,
--    pruning behavior, operational complexity, and cross-tenant query needs.

-- ----------------------------------------------------------------------------
-- INTERVIEW FOLLOW-UPS
-- ----------------------------------------------------------------------------
-- 1. What is the difference between ENABLE ROW LEVEL SECURITY and FORCE ROW
--    LEVEL SECURITY?
-- 2. Why do permissive policies combine with OR while restrictive policies
--    combine with AND?
-- 3. Can a tenant application safely set app.tenant_id itself? Why or why not?
-- 4. How can a pooled connection leak tenant context between requests?
-- 5. Why should tenant_id be included in joins, unique keys, and foreign keys?
-- 6. Which roles bypass RLS, and how should production privileges be audited?
-- 7. How can RLS affect query plans, prepared statements, and index selection?
-- 8. How would you test RLS for views, SECURITY DEFINER functions, and ETL jobs?

-- End of practice.
