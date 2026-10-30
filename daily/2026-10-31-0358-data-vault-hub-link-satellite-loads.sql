-- Data Vault 2.0: idempotent Hub, Link, and Satellite loading
-- Dialect: PostgreSQL 14+
-- Run this file in one session. It creates isolated dv_* practice tables.
--
-- Scenario:
-- A CRM source sends customer/account relationship events. The landing table can
-- contain replayed deliveries. Build deterministic hash keys, load Hubs and Links
-- once, and historize attribute changes in Satellites using hashdiffs.
--
-- Production note: this is a teaching-sized full-history batch. For incremental
-- batches, compare the first incoming hashdiff for each business key with the
-- latest persisted satellite hashdiff before deciding whether to insert it.

DROP TABLE IF EXISTS dv_sat_account;
DROP TABLE IF EXISTS dv_sat_customer;
DROP TABLE IF EXISTS dv_link_customer_account;
DROP TABLE IF EXISTS dv_hub_account;
DROP TABLE IF EXISTS dv_hub_customer;
DROP TABLE IF EXISTS dv_raw_customer_account_events;

CREATE TABLE dv_raw_customer_account_events (
    event_id       text        NOT NULL,
    source_system  text        NOT NULL,
    customer_bk    text        NOT NULL,
    account_bk     text        NOT NULL,
    customer_name  text,
    customer_email text,
    account_type   text,
    event_ts       timestamptz NOT NULL,
    ingested_at    timestamptz NOT NULL,
    record_source  text        NOT NULL,
    is_deleted     boolean     NOT NULL DEFAULT false
);

INSERT INTO dv_raw_customer_account_events VALUES
('evt-001','CRM','C100','A900','Asha Rao','asha@example.com','SAVINGS',
 '2026-10-30 09:00:00+05:30','2026-10-30 09:00:08+05:30','crm.customer_account',false),
('evt-002','CRM','C100','A900','Asha Rao','asha.rao@example.com','SAVINGS',
 '2026-10-30 10:00:00+05:30','2026-10-30 10:00:06+05:30','crm.customer_account',false),
('evt-003','CRM','C100','A901','Asha Rao','asha.rao@example.com','CURRENT',
 '2026-10-30 10:30:00+05:30','2026-10-30 10:30:05+05:30','crm.customer_account',false),
('evt-004','CRM','C101','A902','Bharat Shah','bharat@example.com','SAVINGS',
 '2026-10-30 09:15:00+05:30','2026-10-30 09:15:07+05:30','crm.customer_account',false),
('evt-005','CRM','C101','A902','Bharat Shah','b.shah@example.com','SAVINGS',
 '2026-10-30 11:00:00+05:30','2026-10-30 11:00:04+05:30','crm.customer_account',false),
('evt-006','CRM','C102','A903','Chitra Nair','chitra@example.com','CURRENT',
 '2026-10-30 09:20:00+05:30','2026-10-30 09:20:03+05:30','crm.customer_account',false),
('evt-007','CRM','C102','A903','Chitra Nair','chitra@example.com','CURRENT',
 '2026-10-30 12:00:00+05:30','2026-10-30 12:00:03+05:30','crm.customer_account',true),
('evt-008','CRM','C103','A904','Dev Kulkarni','dev@example.com','SALARY',
 '2026-10-30 09:25:00+05:30','2026-10-30 09:25:03+05:30','crm.customer_account',false),
-- A replay of evt-002 arrived later. The canonicalization step must retain one row.
('evt-002','CRM','C100','A900','Asha Rao','asha.rao@example.com','SAVINGS',
 '2026-10-30 10:00:00+05:30','2026-10-30 10:05:45+05:30','crm.customer_account',false);

-- Canonical delivery set: one copy of each source event, keeping its latest delivery.
DROP TABLE IF EXISTS canonical_events;
CREATE TEMP TABLE canonical_events AS
SELECT DISTINCT ON (source_system, event_id)
       event_id, source_system, customer_bk, account_bk,
       customer_name, customer_email, account_type,
       event_ts, ingested_at, record_source, is_deleted
FROM dv_raw_customer_account_events
ORDER BY source_system, event_id, ingested_at DESC;

-- Data Vault core tables.
CREATE TABLE dv_hub_customer (
    customer_hk   char(32) PRIMARY KEY,
    source_system text NOT NULL,
    customer_bk   text NOT NULL,
    load_dts      timestamptz NOT NULL,
    record_source text NOT NULL,
    UNIQUE (source_system, customer_bk)
);

CREATE TABLE dv_hub_account (
    account_hk    char(32) PRIMARY KEY,
    source_system text NOT NULL,
    account_bk    text NOT NULL,
    load_dts      timestamptz NOT NULL,
    record_source text NOT NULL,
    UNIQUE (source_system, account_bk)
);

CREATE TABLE dv_link_customer_account (
    link_hk       char(32) PRIMARY KEY,
    customer_hk   char(32) NOT NULL REFERENCES dv_hub_customer(customer_hk),
    account_hk    char(32) NOT NULL REFERENCES dv_hub_account(account_hk),
    load_dts      timestamptz NOT NULL,
    record_source text NOT NULL,
    UNIQUE (customer_hk, account_hk)
);

CREATE TABLE dv_sat_customer (
    customer_hk   char(32) NOT NULL REFERENCES dv_hub_customer(customer_hk),
    event_id      text NOT NULL,
    load_dts      timestamptz NOT NULL,
    effective_dts timestamptz NOT NULL,
    hashdiff      char(32) NOT NULL,
    customer_name text,
    customer_email text,
    is_deleted    boolean NOT NULL,
    record_source text NOT NULL,
    PRIMARY KEY (customer_hk, event_id)
);

CREATE TABLE dv_sat_account (
    account_hk    char(32) NOT NULL REFERENCES dv_hub_account(account_hk),
    event_id      text NOT NULL,
    load_dts      timestamptz NOT NULL,
    effective_dts timestamptz NOT NULL,
    hashdiff      char(32) NOT NULL,
    account_type  text,
    is_deleted    boolean NOT NULL,
    record_source text NOT NULL,
    PRIMARY KEY (account_hk, event_id)
);

-- 1. Inspect replayed deliveries and the canonical event set.
-- Expected: evt-002 has two landing rows but one canonical row.
SELECT source_system, event_id, COUNT(*) AS delivery_count
FROM dv_raw_customer_account_events
GROUP BY source_system, event_id
HAVING COUNT(*) > 1;

SELECT COUNT(*) AS canonical_event_count FROM canonical_events;

-- 2. Load customer and account Hubs.
-- Hash keys include source system so identical business keys from two systems
-- remain distinct. ON CONFLICT makes the load repeatable.
INSERT INTO dv_hub_customer
    (customer_hk, source_system, customer_bk, load_dts, record_source)
SELECT md5(source_system || '|' || customer_bk),
       source_system, customer_bk, MIN(ingested_at), MIN(record_source)
FROM canonical_events
GROUP BY source_system, customer_bk
ON CONFLICT (customer_hk) DO NOTHING;

INSERT INTO dv_hub_account
    (account_hk, source_system, account_bk, load_dts, record_source)
SELECT md5(source_system || '|' || account_bk),
       source_system, account_bk, MIN(ingested_at), MIN(record_source)
FROM canonical_events
GROUP BY source_system, account_bk
ON CONFLICT (account_hk) DO NOTHING;

-- 3. Load the relationship Link once per customer/account pair.
INSERT INTO dv_link_customer_account
    (link_hk, customer_hk, account_hk, load_dts, record_source)
SELECT DISTINCT
       md5(c.source_system || '|' || c.customer_bk || '|' || c.account_bk),
       hc.customer_hk,
       ha.account_hk,
       c.ingested_at,
       c.record_source
FROM canonical_events c
JOIN dv_hub_customer hc
  ON hc.source_system = c.source_system
 AND hc.customer_bk = c.customer_bk
JOIN dv_hub_account ha
  ON ha.source_system = c.source_system
 AND ha.account_bk = c.account_bk
ON CONFLICT (link_hk) DO NOTHING;

-- 4. Load customer Satellite rows only when tracked attributes change.
-- LAG compares adjacent source events in effective-time order. The event_id
-- primary key protects against replaying the same source event.
WITH customer_changes AS (
    SELECT c.*,
           md5(concat_ws('|',
               COALESCE(c.customer_name, '<NULL>'),
               COALESCE(c.customer_email, '<NULL>'),
               c.is_deleted::text
           )) AS hashdiff,
           LAG(md5(concat_ws('|',
               COALESCE(c.customer_name, '<NULL>'),
               COALESCE(c.customer_email, '<NULL>'),
               c.is_deleted::text
           ))) OVER (
               PARTITION BY c.source_system, c.customer_bk
               ORDER BY c.event_ts, c.ingested_at, c.event_id
           ) AS previous_hashdiff
    FROM canonical_events c
)
INSERT INTO dv_sat_customer
    (customer_hk, event_id, load_dts, effective_dts, hashdiff,
     customer_name, customer_email, is_deleted, record_source)
SELECT md5(source_system || '|' || customer_bk),
       event_id, ingested_at, event_ts, hashdiff,
       customer_name, customer_email, is_deleted, record_source
FROM customer_changes
WHERE previous_hashdiff IS DISTINCT FROM hashdiff
   OR previous_hashdiff IS NULL
ON CONFLICT (customer_hk, event_id) DO NOTHING;

-- 5. Load account Satellite history using its own hashdiff.
WITH account_changes AS (
    SELECT c.*,
           md5(concat_ws('|',
               COALESCE(c.account_type, '<NULL>'),
               c.is_deleted::text
           )) AS hashdiff,
           LAG(md5(concat_ws('|',
               COALESCE(c.account_type, '<NULL>'),
               c.is_deleted::text
           ))) OVER (
               PARTITION BY c.source_system, c.account_bk
               ORDER BY c.event_ts, c.ingested_at, c.event_id
           ) AS previous_hashdiff
    FROM canonical_events c
)
INSERT INTO dv_sat_account
    (account_hk, event_id, load_dts, effective_dts, hashdiff,
     account_type, is_deleted, record_source)
SELECT md5(source_system || '|' || account_bk),
       event_id, ingested_at, event_ts, hashdiff,
       account_type, is_deleted, record_source
FROM account_changes
WHERE previous_hashdiff IS DISTINCT FROM hashdiff
   OR previous_hashdiff IS NULL
ON CONFLICT (account_hk, event_id) DO NOTHING;

-- 6. Build a current-state customer view from the latest effective Satellite row.
-- DISTINCT ON is concise in PostgreSQL; ROW_NUMBER() is a portable alternative.
SELECT DISTINCT ON (hc.customer_hk)
       hc.source_system,
       hc.customer_bk,
       s.customer_name,
       s.customer_email,
       s.is_deleted,
       s.effective_dts AS current_effective_dts
FROM dv_hub_customer hc
JOIN dv_sat_customer s USING (customer_hk)
ORDER BY hc.customer_hk, s.effective_dts DESC, s.load_dts DESC, s.event_id DESC;

-- 7. Reconstruct customer attributes as of a historical business timestamp.
SELECT DISTINCT ON (hc.customer_hk)
       hc.customer_bk, s.customer_name, s.customer_email, s.is_deleted
FROM dv_hub_customer hc
JOIN dv_sat_customer s USING (customer_hk)
WHERE s.effective_dts <= TIMESTAMPTZ '2026-10-30 10:15:00+05:30'
ORDER BY hc.customer_hk, s.effective_dts DESC, s.load_dts DESC, s.event_id DESC;

-- 8. Run structural controls: orphan Satellites, duplicate relationships,
-- and raw events whose Hub/Link business keys were not loaded.
SELECT 'customer_satellite_without_hub' AS check_name, COUNT(*) AS failures
FROM dv_sat_customer s
LEFT JOIN dv_hub_customer h USING (customer_hk)
WHERE h.customer_hk IS NULL
UNION ALL
SELECT 'account_satellite_without_hub', COUNT(*)
FROM dv_sat_account s
LEFT JOIN dv_hub_account h USING (account_hk)
WHERE h.account_hk IS NULL
UNION ALL
SELECT 'raw_event_without_link', COUNT(*)
FROM canonical_events c
LEFT JOIN dv_link_customer_account l
  ON l.link_hk = md5(c.source_system || '|' || c.customer_bk || '|' || c.account_bk)
WHERE l.link_hk IS NULL;

-- Repeatability check: re-run the Hub, Link, and Satellite INSERT statements.
-- Their unique keys / ON CONFLICT clauses should prevent duplicate rows.

-- Performance and production notes:
-- * Compute normalized business keys and hashdiffs once in a staging layer.
-- * Standardize trimming, case, Unicode normalization, NULL sentinels, and column
--   order before hashing; changing the recipe changes every downstream hash.
-- * MD5 is used here for compact deterministic examples, not security. Consider
--   SHA-256 or a binary hash representation when collision risk policy requires it.
-- * Index satellite access paths for PIT queries:
--     CREATE INDEX ON dv_sat_customer (customer_hk, effective_dts DESC, load_dts DESC);
--     CREATE INDEX ON dv_sat_account  (account_hk, effective_dts DESC, load_dts DESC);
-- * Index raw replay detection:
--     CREATE INDEX ON dv_raw_customer_account_events
--       (source_system, event_id, ingested_at DESC);
-- * For incremental batches, seed each business key's first incoming LAG comparison
--   with its latest persisted hashdiff; otherwise an unchanged first row may be added.
-- * Partition large Satellites by load date only when retention/volume justifies it;
--   retain business-key indexes for point-in-time lookups.
