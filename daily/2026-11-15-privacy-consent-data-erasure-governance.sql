-- =============================================================================
-- Daily SQL Practice — 2026-11-15
-- Topic: Privacy Consent, Data Subject Requests & Erasure Governance
-- Dialect: PostgreSQL 14+
--
-- Scenario: a multi-system platform must preserve consent history, enforce
-- purpose-specific processing gates, coordinate downstream erasure, respect
-- legal holds, and prove that completed requests are actually complete.
--
-- Synthetic data only. This script recreates the dedicated privacy_practice
-- schema; run it in a disposable database. It is a learning exercise, not a
-- production legal/compliance implementation.
-- =============================================================================

DROP SCHEMA IF EXISTS privacy_practice CASCADE;
CREATE SCHEMA privacy_practice;
SET search_path = privacy_practice, public;
SET TIME ZONE 'UTC';

-- 1. Schema and realistic sample data
CREATE TABLE privacy_subject (
    subject_id text PRIMARY KEY,
    created_at timestamptz NOT NULL
);

CREATE TABLE privacy_asset (
    asset_id text PRIMARY KEY,
    system_name text NOT NULL UNIQUE,
    retention_days integer NOT NULL CHECK (retention_days > 0),
    supports_delete boolean NOT NULL,
    description text NOT NULL
);

CREATE TABLE privacy_processing_activity (
    activity_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    asset_id text NOT NULL REFERENCES privacy_asset(asset_id),
    purpose text NOT NULL,
    channel text NOT NULL,
    lawful_basis text NOT NULL CHECK (lawful_basis IN
        ('consent','contract','legal_obligation','legitimate_interest')),
    is_active boolean NOT NULL DEFAULT true,
    UNIQUE (asset_id, purpose, channel)
);

-- Landing table intentionally has no subject FK so malformed events can be
-- quarantined and audited rather than rejected during ingestion.
CREATE TABLE privacy_consent_event_landing (
    event_id bigint PRIMARY KEY,
    source_event_id text NOT NULL,
    revision integer NOT NULL CHECK (revision > 0),
    subject_id text NOT NULL,
    purpose text NOT NULL,
    channel text NOT NULL,
    action text NOT NULL CHECK (action IN ('grant','withdraw')),
    occurred_at timestamptz NOT NULL,
    received_at timestamptz NOT NULL,
    payload_hash text NOT NULL
);

CREATE TABLE privacy_subject_record (
    record_id bigint PRIMARY KEY,
    subject_id text NOT NULL REFERENCES privacy_subject(subject_id),
    asset_id text NOT NULL REFERENCES privacy_asset(asset_id),
    source_record_key text NOT NULL,
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL,
    erased_at timestamptz,
    payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    UNIQUE (asset_id, source_record_key),
    CHECK (erased_at IS NULL OR erased_at >= created_at)
);

CREATE TABLE privacy_dsr_request (
    request_id text PRIMARY KEY,
    subject_id text NOT NULL REFERENCES privacy_subject(subject_id),
    request_type text NOT NULL CHECK (request_type IN
        ('access','rectification','erasure','restriction')),
    requested_at timestamptz NOT NULL,
    due_at timestamptz NOT NULL,
    status text NOT NULL CHECK (status IN
        ('requested','in_progress','completed','rejected')),
    completed_at timestamptz,
    CHECK (due_at >= requested_at),
    CHECK (completed_at IS NULL OR completed_at >= requested_at)
);

-- NULL asset_id means a subject-wide hold. Validity is [valid_from, valid_to).
CREATE TABLE privacy_legal_hold (
    hold_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    subject_id text NOT NULL REFERENCES privacy_subject(subject_id),
    asset_id text REFERENCES privacy_asset(asset_id),
    hold_reason text NOT NULL,
    valid_from timestamptz NOT NULL,
    valid_to timestamptz,
    CHECK (valid_to IS NULL OR valid_to > valid_from)
);

CREATE TABLE privacy_erasure_job (
    job_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    request_id text NOT NULL REFERENCES privacy_dsr_request(request_id),
    asset_id text NOT NULL REFERENCES privacy_asset(asset_id),
    status text NOT NULL CHECK (status IN
        ('queued','running','succeeded','failed','skipped')),
    attempt_count integer NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
    requested_at timestamptz NOT NULL,
    started_at timestamptz,
    completed_at timestamptz,
    external_ref text,
    UNIQUE (request_id, asset_id),
    CHECK (completed_at IS NULL OR started_at IS NOT NULL)
);

-- The mapping is still sensitive personal data: a pseudonym is not anonymous
-- while this table can relink it to a person.
CREATE TABLE privacy_analytics_subject_map (
    subject_id text PRIMARY KEY REFERENCES privacy_subject(subject_id),
    analytics_subject_id uuid NOT NULL UNIQUE,
    created_at timestamptz NOT NULL
);

INSERT INTO privacy_subject VALUES
('S-100','2024-02-01 10:00+00'),
('S-101','2024-03-15 11:00+00'),
('S-102','2024-05-20 09:30+00'),
('S-103','2024-07-04 14:15+00'),
('S-104','2025-01-10 08:45+00');

INSERT INTO privacy_asset VALUES
('crm','Customer CRM',365,true,'Customer profile and service preferences'),
('email','Campaign Platform',90,true,'Marketing audience and delivery metadata'),
('web_analytics','Web Analytics Store',30,true,'Product interaction events'),
('billing','Finance Ledger',2555,false,'Invoices retained under statutory schedule'),
('support','Customer Support',730,true,'Support cases and correspondence');

INSERT INTO privacy_processing_activity
(asset_id,purpose,channel,lawful_basis,is_active) VALUES
('crm','customer_service','service','contract',true),
('crm','marketing_email','email','consent',true),
('email','marketing_email','email','consent',true),
('web_analytics','product_analytics','web','consent',true),
('billing','invoice_processing','billing','legal_obligation',true),
('support','customer_support','support','contract',true);

-- c-001 is a replay; c-007 revision 2 corrects revision 1; c-009 is orphaned.
INSERT INTO privacy_consent_event_landing VALUES
(9001,'c-001',1,'S-100','marketing_email','email','grant','2026-11-01 09:00+00','2026-11-01 09:00:04+00','h-c001'),
(9002,'c-001',1,'S-100','marketing_email','email','grant','2026-11-01 09:00+00','2026-11-01 09:02:10+00','h-c001'),
(9003,'c-002',1,'S-100','marketing_email','email','withdraw','2026-11-12 10:00+00','2026-11-12 10:00:03+00','h-c002'),
(9004,'c-003',1,'S-100','product_analytics','web','grant','2026-11-02 08:00+00','2026-11-02 08:00:05+00','h-c003'),
(9005,'c-004',1,'S-101','marketing_email','email','grant','2026-11-04 12:00+00','2026-11-04 12:00:04+00','h-c004'),
(9006,'c-005',1,'S-101','marketing_email','email','withdraw','2026-11-08 16:30+00','2026-11-08 16:30:02+00','h-c005'),
(9007,'c-006',1,'S-102','product_analytics','web','grant','2026-11-10 07:15+00','2026-11-10 07:15:02+00','h-c006'),
(9008,'c-007',1,'S-103','marketing_email','email','grant','2026-11-09 10:00+00','2026-11-09 10:00:03+00','h-c007-v1'),
(9009,'c-007',2,'S-103','marketing_email','email','withdraw','2026-11-09 10:00+00','2026-11-10 06:20+00','h-c007-v2'),
(9010,'c-008',1,'S-104','product_analytics','web','grant','2026-11-13 13:00+00','2026-11-13 13:00:02+00','h-c008'),
(9011,'c-009',1,'S-999','product_analytics','web','grant','2026-11-13 15:00+00','2026-11-13 15:00:03+00','h-c009');

INSERT INTO privacy_subject_record VALUES
(1,'S-100','crm','crm-100','2026-01-10 10:00+00','2026-11-14 09:00+00','2026-11-14 09:00+00','{"segment":"standard"}'),
(2,'S-100','email','email-100','2026-09-01 10:00+00','2026-11-13 10:00+00',NULL,'{"list":"monthly"}'),
(3,'S-100','web_analytics','web-100','2026-10-01 10:00+00','2026-11-13 10:00+00',NULL,'{"page_views":18}'),
(4,'S-100','billing','bill-100','2024-05-01 10:00+00','2026-11-01 10:00+00',NULL,'{"invoice_count":3}'),
(5,'S-101','crm','crm-101','2026-05-01 10:00+00','2026-11-14 10:00+00','2026-11-14 10:00+00','{"segment":"premium"}'),
(6,'S-101','email','email-101','2026-06-01 10:00+00','2026-11-14 10:05+00','2026-11-14 10:05+00','{"list":"weekly"}'),
(7,'S-101','support','case-101','2026-01-01 10:00+00','2026-11-14 10:10+00',NULL,'{"case_count":1}'),
(8,'S-102','web_analytics','web-102','2026-11-10 10:00+00','2026-11-10 10:00+00',NULL,'{"page_views":4}'),
(9,'S-102','support','case-102','2026-11-10 10:30+00','2026-11-10 10:30+00',NULL,'{"case_count":1}'),
(10,'S-103','crm','crm-103','2025-10-01 10:00+00','2026-11-12 10:00+00',NULL,'{"segment":"standard"}'),
(11,'S-103','billing','bill-103','2024-01-01 10:00+00','2026-11-12 10:00+00',NULL,'{"invoice_count":8}'),
(12,'S-103','support','case-103','2025-01-01 10:00+00','2026-11-12 10:00+00',NULL,'{"case_count":2}'),
(13,'S-104','billing','bill-104','2026-11-01 10:00+00','2026-11-14 10:00+00',NULL,'{"invoice_count":1}'),
(14,'S-104','web_analytics','web-104','2026-09-01 10:00+00','2026-11-14 10:00+00',NULL,'{"page_views":32}');

INSERT INTO privacy_dsr_request VALUES
('DSR-100','S-100','erasure','2026-11-13 08:00+00','2026-11-23 08:00+00','in_progress',NULL),
('DSR-101','S-101','erasure','2026-11-01 09:00+00','2026-11-15 09:00+00','completed','2026-11-14 10:30+00'),
('DSR-102','S-102','access','2026-11-05 12:00+00','2026-11-12 12:00+00','in_progress',NULL),
('DSR-103','S-103','erasure','2026-11-12 07:00+00','2026-11-22 07:00+00','requested',NULL),
('DSR-104','S-104','access','2026-11-13 11:00+00','2026-11-23 11:00+00','completed','2026-11-14 08:00+00');

-- Two overlapping S-103 billing holds intentionally exercise Q10.
INSERT INTO privacy_legal_hold
(subject_id,asset_id,hold_reason,valid_from,valid_to) VALUES
('S-103','billing','Open statutory audit','2026-11-01 00:00+00','2026-12-01 00:00+00'),
('S-103','billing','Related litigation hold','2026-11-20 00:00+00','2027-01-15 00:00+00');

INSERT INTO privacy_erasure_job
(request_id,asset_id,status,attempt_count,requested_at,started_at,completed_at,external_ref) VALUES
('DSR-100','crm','succeeded',1,'2026-11-13 08:05+00','2026-11-13 08:10+00','2026-11-14 09:00+00','crm-task-700'),
('DSR-100','email','queued',0,'2026-11-13 08:05+00',NULL,NULL,NULL),
('DSR-100','web_analytics','failed',2,'2026-11-13 08:05+00','2026-11-13 08:10+00','2026-11-13 08:12+00','web-task-701'),
('DSR-101','crm','succeeded',1,'2026-11-01 09:05+00','2026-11-01 09:10+00','2026-11-14 10:00+00','crm-task-702'),
('DSR-101','email','succeeded',1,'2026-11-01 09:05+00','2026-11-01 09:10+00','2026-11-14 10:05+00','email-task-703'),
('DSR-101','support','succeeded',1,'2026-11-01 09:05+00','2026-11-01 09:10+00','2026-11-14 10:10+00','support-task-704'),
('DSR-103','crm','queued',0,'2026-11-12 07:05+00',NULL,NULL,NULL),
('DSR-103','support','queued',0,'2026-11-12 07:05+00',NULL,NULL,NULL);

INSERT INTO privacy_analytics_subject_map VALUES
('S-100','11111111-1111-4111-8111-111111111100','2026-01-01 00:00+00'),
('S-102','22222222-2222-4222-8222-222222222200','2026-01-01 00:00+00'),
('S-104','44444444-4444-4444-8444-444444444400','2026-01-01 00:00+00');

-- 2. Candidate indexes: validate with real cardinalities; tiny sample tables
-- may correctly use sequential scans.
CREATE INDEX ix_consent_source_revision
    ON privacy_consent_event_landing
       (source_event_id,revision DESC,received_at DESC,event_id DESC);
CREATE INDEX ix_consent_subject_purpose_channel_time
    ON privacy_consent_event_landing (subject_id,purpose,channel,occurred_at DESC)
    INCLUDE (action,received_at,source_event_id,revision);
CREATE INDEX ix_subject_record_live_subject_asset
    ON privacy_subject_record (subject_id,asset_id) WHERE erased_at IS NULL;
CREATE INDEX ix_subject_record_live_created
    ON privacy_subject_record (created_at,asset_id) WHERE erased_at IS NULL;
CREATE INDEX ix_dsr_open_due
    ON privacy_dsr_request (due_at,request_type) WHERE completed_at IS NULL;
CREATE INDEX ix_erasure_job_request_status
    ON privacy_erasure_job (request_id,status);
CREATE INDEX ix_legal_hold_subject_asset_start
    ON privacy_legal_hold (subject_id,asset_id,valid_from);

-- =============================================================================
-- PROBLEMS AND OPTIMIZED REFERENCE SOLUTIONS
-- =============================================================================

-- Problem 1. Canonicalize consent events across retries and corrections.
-- Requirement: one row per source_event_id; highest revision wins, then latest
-- received delivery. DISTINCT ON is deterministic and avoids a self-join.
CREATE OR REPLACE VIEW privacy_canonical_consent_event AS
SELECT DISTINCT ON (source_event_id)
       event_id,source_event_id,revision,subject_id,purpose,channel,action,
       occurred_at,received_at,payload_hash
FROM privacy_consent_event_landing
ORDER BY source_event_id,revision DESC,received_at DESC,event_id DESC;

-- Spot check: 11 landing deliveries collapse to 9 source events.
SELECT COUNT(*) AS canonical_event_count
FROM privacy_canonical_consent_event;

-- Problem 2. Find latest consent per subject/purpose/channel as of an instant.
-- Filter before DISTINCT ON; event time is business order, received time breaks
-- ties. MAX(event_time) followed by a join can multiply tied rows.
SELECT DISTINCT ON (subject_id,purpose,channel)
       subject_id,purpose,channel,action AS latest_action,
       occurred_at AS decision_at,source_event_id
FROM privacy_canonical_consent_event
WHERE occurred_at <= TIMESTAMPTZ '2026-11-15 12:00+00'
ORDER BY subject_id,purpose,channel,occurred_at DESC,received_at DESC,source_event_id DESC;

-- Problem 3. Apply purpose-specific consent gates to active processing.
-- LATERAL top-1 lookup can use the subject/purpose/channel/time index. Missing
-- consent fails closed; other lawful bases require their own documented tests.
SELECT s.subject_id,pa.asset_id,pa.purpose,pa.channel,pa.lawful_basis,
       c.action AS latest_consent_action,
       CASE WHEN pa.lawful_basis <> 'consent' THEN true
            WHEN c.action = 'grant' THEN true ELSE false END AS passes_consent_gate
FROM privacy_subject AS s
CROSS JOIN privacy_processing_activity AS pa
LEFT JOIN LATERAL (
    SELECT ce.action
    FROM privacy_canonical_consent_event AS ce
    WHERE ce.subject_id=s.subject_id
      AND ce.purpose=pa.purpose
      AND ce.channel=pa.channel
      AND ce.occurred_at <= TIMESTAMPTZ '2026-11-15 12:00+00'
    ORDER BY ce.occurred_at DESC,ce.received_at DESC,ce.source_event_id DESC
    LIMIT 1
) AS c ON true
WHERE pa.is_active
ORDER BY s.subject_id,pa.asset_id,pa.purpose;

-- Problem 4. Build DSAR volume, overdue, and median completion-time metrics.
-- FILTER computes several measures in one grouped pass; the partial due-date
-- index supports the separate open-request operations queue.
SELECT request_type,
       COUNT(*) AS total_requests,
       COUNT(*) FILTER (WHERE status='requested') AS requested_count,
       COUNT(*) FILTER (WHERE status='in_progress') AS in_progress_count,
       COUNT(*) FILTER (WHERE status='completed') AS completed_count,
       COUNT(*) FILTER (
           WHERE completed_at IS NULL AND status IN ('requested','in_progress')
             AND due_at < TIMESTAMPTZ '2026-11-15 12:00+00'
       ) AS overdue_open_count,
       ROUND((
           percentile_cont(0.5) WITHIN GROUP (
               ORDER BY EXTRACT(EPOCH FROM (completed_at-requested_at))/3600.0
           ) FILTER (WHERE completed_at IS NOT NULL)
       )::numeric,2) AS median_completion_hours
FROM privacy_dsr_request
GROUP BY request_type
ORDER BY request_type;

SELECT request_id,subject_id,request_type,requested_at,due_at,status,
       due_at-TIMESTAMPTZ '2026-11-15 12:00+00' AS time_to_due
FROM privacy_dsr_request
WHERE completed_at IS NULL AND status IN ('requested','in_progress')
ORDER BY due_at,requested_at;

-- Problem 5. Build an erasure worklist for deletable, unheld assets.
-- DISTINCT collapses multiple records in one asset to one job. NOT EXISTS is a
-- null-safe anti-join for legal holds and already queued/running/successful work.
WITH candidates AS (
    SELECT DISTINCT d.request_id,d.subject_id,r.asset_id,d.requested_at
    FROM privacy_dsr_request AS d
    JOIN privacy_subject_record AS r
      ON r.subject_id=d.subject_id AND r.erased_at IS NULL
    JOIN privacy_asset AS a ON a.asset_id=r.asset_id AND a.supports_delete
    WHERE d.request_type='erasure' AND d.status IN ('requested','in_progress')
      AND NOT EXISTS (
          SELECT 1 FROM privacy_legal_hold AS h
          WHERE h.subject_id=d.subject_id
            AND (h.asset_id IS NULL OR h.asset_id=r.asset_id)
            AND h.valid_from <= d.requested_at
            AND (h.valid_to IS NULL OR d.requested_at < h.valid_to)
      )
      AND NOT EXISTS (
          SELECT 1 FROM privacy_erasure_job AS j
          WHERE j.request_id=d.request_id AND j.asset_id=r.asset_id
            AND j.status IN ('queued','running','succeeded')
      )
)
SELECT request_id,subject_id,asset_id,requested_at
FROM candidates
ORDER BY request_id,asset_id;
-- Expected: DSR-100/web_analytics is eligible for retry; DSR-103/billing is
-- excluded (non-deletable asset and active legal hold).

-- Problem 6. Dispatch jobs idempotently; retry a previously failed job.
-- UNIQUE(request_id,asset_id) is the concurrency-safe idempotency boundary.
-- A production worker should claim with FOR UPDATE SKIP LOCKED and a lease,
-- then call external systems outside the database transaction.
WITH candidates AS (
    SELECT DISTINCT d.request_id,r.asset_id,d.requested_at
    FROM privacy_dsr_request AS d
    JOIN privacy_subject_record AS r
      ON r.subject_id=d.subject_id AND r.erased_at IS NULL
    JOIN privacy_asset AS a ON a.asset_id=r.asset_id AND a.supports_delete
    WHERE d.request_type='erasure' AND d.status IN ('requested','in_progress')
      AND NOT EXISTS (
          SELECT 1 FROM privacy_legal_hold AS h
          WHERE h.subject_id=d.subject_id
            AND (h.asset_id IS NULL OR h.asset_id=r.asset_id)
            AND h.valid_from <= d.requested_at
            AND (h.valid_to IS NULL OR d.requested_at < h.valid_to)
      )
      AND NOT EXISTS (
          SELECT 1 FROM privacy_erasure_job AS j
          WHERE j.request_id=d.request_id AND j.asset_id=r.asset_id
            AND j.status IN ('queued','running','succeeded')
      )
)
INSERT INTO privacy_erasure_job
(request_id,asset_id,status,attempt_count,requested_at)
SELECT request_id,asset_id,'queued',0,requested_at
FROM candidates
ON CONFLICT (request_id,asset_id) DO UPDATE
SET status='queued',
    attempt_count=privacy_erasure_job.attempt_count+1,
    requested_at=EXCLUDED.requested_at,
    started_at=NULL,completed_at=NULL,external_ref=NULL
WHERE privacy_erasure_job.status='failed'
RETURNING request_id,asset_id,status,attempt_count;
-- Intentional DML: this retries DSR-100/web_analytics and increments attempts.

-- Problem 7. Reconcile expected asset scope with downstream completion.
-- Aggregate at request/asset grain first to prevent record-to-job join fanout.
-- A successful job is not proof until every expected live record is erased.
WITH expected_asset AS (
    SELECT DISTINCT d.request_id,d.subject_id,r.asset_id
    FROM privacy_dsr_request AS d
    JOIN privacy_subject_record AS r
      ON r.subject_id=d.subject_id AND r.erased_at IS NULL
    JOIN privacy_asset AS a ON a.asset_id=r.asset_id AND a.supports_delete
    WHERE d.request_type='erasure'
      AND NOT EXISTS (
          SELECT 1 FROM privacy_legal_hold AS h
          WHERE h.subject_id=d.subject_id
            AND (h.asset_id IS NULL OR h.asset_id=r.asset_id)
            AND h.valid_from <= d.requested_at
            AND (h.valid_to IS NULL OR d.requested_at < h.valid_to)
      )
),
asset_status AS (
    SELECT e.request_id,e.subject_id,e.asset_id,j.status AS job_status,
           COUNT(r.record_id) FILTER (WHERE r.erased_at IS NULL) AS live_records
    FROM expected_asset AS e
    LEFT JOIN privacy_erasure_job AS j
      ON j.request_id=e.request_id AND j.asset_id=e.asset_id
    LEFT JOIN privacy_subject_record AS r
      ON r.subject_id=e.subject_id AND r.asset_id=e.asset_id AND r.erased_at IS NULL
    GROUP BY e.request_id,e.subject_id,e.asset_id,j.status
)
SELECT request_id,COUNT(*) AS expected_assets,
       COUNT(*) FILTER (WHERE job_status='succeeded') AS succeeded_jobs,
       COUNT(*) FILTER (WHERE job_status IS DISTINCT FROM 'succeeded'
                         OR live_records>0) AS assets_not_proven_erased,
       BOOL_AND(job_status='succeeded' AND live_records=0) AS fully_proven
FROM asset_status
GROUP BY request_id
ORDER BY request_id;

-- Problem 8. Find records beyond their asset-specific retention period.
-- Candidate report only; no destructive DELETE is executed. Keep created_at
-- bare in the predicate. Row-varying retention_days can limit one global
-- timestamp index; policy cohorts or partition-level retention may scale better.
SELECT r.record_id,r.subject_id,r.asset_id,a.system_name,r.created_at,
       a.retention_days,
       TIMESTAMPTZ '2026-11-15 12:00+00'
         - make_interval(days=>a.retention_days) AS retention_cutoff
FROM privacy_subject_record AS r
JOIN privacy_asset AS a ON a.asset_id=r.asset_id
WHERE r.erased_at IS NULL AND a.supports_delete
  AND r.created_at < TIMESTAMPTZ '2026-11-15 12:00+00'
                       - make_interval(days=>a.retention_days)
  AND NOT EXISTS (
      SELECT 1 FROM privacy_legal_hold AS h
      WHERE h.subject_id=r.subject_id
        AND (h.asset_id IS NULL OR h.asset_id=r.asset_id)
        AND h.valid_from <= TIMESTAMPTZ '2026-11-15 12:00+00'
        AND (h.valid_to IS NULL OR TIMESTAMPTZ '2026-11-15 12:00+00' < h.valid_to)
  )
  AND NOT EXISTS (
      SELECT 1 FROM privacy_dsr_request AS d
      WHERE d.subject_id=r.subject_id AND d.request_type='erasure'
        AND d.status IN ('requested','in_progress') AND d.completed_at IS NULL
  )
ORDER BY r.created_at,r.record_id;
-- Expected: S-104/web_analytics is past its 30-day policy. S-103 is excluded
-- while its erasure request is active.

-- Problem 9. Consolidate privacy-governance exceptions without hiding provenance.
-- UNION ALL avoids unnecessary sort/deduplication; each branch is independently
-- filterable and can be materialized for monitoring if freshness permits.
WITH latest_consent AS (
    SELECT DISTINCT ON (subject_id,purpose,channel)
           subject_id,purpose,channel,action
    FROM privacy_canonical_consent_event
    WHERE occurred_at <= TIMESTAMPTZ '2026-11-15 12:00+00'
    ORDER BY subject_id,purpose,channel,occurred_at DESC,received_at DESC,source_event_id DESC
),
exceptions AS (
    SELECT 'HIGH'::text AS severity,'ORPHAN_CONSENT_SUBJECT'::text AS exception_type,
           ce.subject_id,ce.source_event_id AS object_key,
           'Consent event references an unknown subject'::text AS details
    FROM privacy_canonical_consent_event AS ce
    WHERE NOT EXISTS (SELECT 1 FROM privacy_subject s WHERE s.subject_id=ce.subject_id)

    UNION ALL

    SELECT 'HIGH','CONSENT_REQUIRED_BUT_NOT_GRANTED',s.subject_id,
           pa.asset_id||':'||pa.purpose,'Latest consent is absent or withdrawn'
    FROM privacy_subject AS s
    CROSS JOIN privacy_processing_activity AS pa
    LEFT JOIN latest_consent AS lc
      ON lc.subject_id=s.subject_id AND lc.purpose=pa.purpose AND lc.channel=pa.channel
    WHERE pa.is_active AND pa.lawful_basis='consent'
      AND lc.action IS DISTINCT FROM 'grant'

    UNION ALL

    SELECT 'HIGH','COMPLETED_ERASURE_HAS_LIVE_RECORD',d.subject_id,
           d.request_id||':'||r.asset_id,
           'Completed request still has a live record in a deletable asset'
    FROM privacy_dsr_request AS d
    JOIN privacy_subject_record AS r
      ON r.subject_id=d.subject_id AND r.erased_at IS NULL
    JOIN privacy_asset AS a ON a.asset_id=r.asset_id AND a.supports_delete
    WHERE d.request_type='erasure' AND d.status='completed' AND d.completed_at IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM privacy_legal_hold AS h
          WHERE h.subject_id=d.subject_id
            AND (h.asset_id IS NULL OR h.asset_id=r.asset_id)
            AND h.valid_from <= d.requested_at
            AND (h.valid_to IS NULL OR d.requested_at < h.valid_to)
      )

    UNION ALL

    SELECT 'MEDIUM','SUCCESSFUL_JOB_WITH_LIVE_RECORD',d.subject_id,
           j.request_id||':'||j.asset_id,
           'Downstream job succeeded but one or more records remain live'
    FROM privacy_erasure_job AS j
    JOIN privacy_dsr_request AS d ON d.request_id=j.request_id
    WHERE j.status='succeeded'
      AND EXISTS (
          SELECT 1 FROM privacy_subject_record AS r
          WHERE r.subject_id=d.subject_id AND r.asset_id=j.asset_id AND r.erased_at IS NULL
      )
)
SELECT severity,exception_type,subject_id,object_key,details
FROM exceptions
ORDER BY CASE severity WHEN 'HIGH' THEN 1 ELSE 2 END,
         exception_type,subject_id,object_key;

-- Problem 10. Detect overlapping legal holds for identical subject/asset scope.
-- tstzrange && expresses interval overlap. A GiST index on a generated range
-- can help at scale; hold_id ordering emits each overlapping pair once.
SELECT h1.subject_id,h1.asset_id,h1.hold_id AS hold_id_1,h2.hold_id AS hold_id_2,
       h1.hold_reason AS reason_1,h2.hold_reason AS reason_2,
       tstzrange(h1.valid_from,COALESCE(h1.valid_to,'infinity'::timestamptz),'[)')
       * tstzrange(h2.valid_from,COALESCE(h2.valid_to,'infinity'::timestamptz),'[)')
         AS overlap_window
FROM privacy_legal_hold AS h1
JOIN privacy_legal_hold AS h2
  ON h2.subject_id=h1.subject_id
 AND h2.asset_id IS NOT DISTINCT FROM h1.asset_id
 AND h2.hold_id>h1.hold_id
 AND tstzrange(h1.valid_from,COALESCE(h1.valid_to,'infinity'::timestamptz),'[)')
     && tstzrange(h2.valid_from,COALESCE(h2.valid_to,'infinity'::timestamptz),'[)')
ORDER BY h1.subject_id,h1.asset_id,h1.hold_id,h2.hold_id;

-- =============================================================================
-- PERFORMANCE LAB AND PRODUCTION NOTES
-- =============================================================================
-- Capture plans on representative data:
--   EXPLAIN (ANALYZE, BUFFERS, VERBOSE) SELECT ...;
--
-- Index candidates:
-- * Consent canonicalization: source_event_id, revision DESC, received_at.
-- * Latest consent: subject_id, purpose, channel, occurred_at DESC.
-- * Live records: partial index on (subject_id,asset_id) WHERE erased_at IS NULL.
-- * DSAR queue: partial due_at index for incomplete requests.
-- * Erasure idempotency: UNIQUE(request_id,asset_id) is a correctness control.
-- * Legal holds: benchmark B-tree predicates versus GiST range indexing.
--
-- Production considerations:
-- * Preserve occurred_at (business time) separately from received_at (ingest time).
-- * Define how backdated corrections trigger re-evaluation of prior decisions.
-- * Treat deletion as an asynchronous distributed workflow with idempotency keys,
--   bounded retries, leases, dead-letter handling, and auditable acknowledgements.
-- * Re-check legal holds immediately before destructive work; a hold may arrive
--   after the worklist was generated.
-- * A successful vendor API response does not prove deletion from replicas,
--   backups, caches, search indexes, feature stores, exports, or derived tables.
-- * A pseudonymous UUID remains personal data if a relinking map exists.
-- * Minimize payloads in logs. Retention rules depend on jurisdiction and legal
--   advice; the policy values in this exercise are fictional.
--
-- Interview follow-ups:
-- 1. How should a late-arriving withdrawal affect an already-sent campaign?
-- 2. How can deletion be proven across Kafka, object storage, and replicas?
-- 3. How do you stop a worker from deleting data after a new legal hold?
-- 4. Where is the transaction boundary around claiming a job and calling a vendor?
-- 5. How would you partition a consent ledger while preserving correction history?
-- =============================================================================
