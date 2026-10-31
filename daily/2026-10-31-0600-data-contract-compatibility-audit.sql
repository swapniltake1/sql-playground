/*
===============================================================================
DATA ENGINEERING PRACTICE
Topic: Data Contract Compatibility Auditing with PostgreSQL JSONB
File: 2026-10-31-0600-data-contract-compatibility-audit.sql
Dialect: PostgreSQL 14+

Scenario
--------
An event platform publishes versioned JSON contracts. Producers sometimes add
fields, remove fields, change types, or send payloads that do not match the
registered version. Build a lightweight release gate and row-level validator.

Run this file independently. All tables and sample rows are isolated.
===============================================================================
*/

DROP VIEW IF EXISTS v_contract_field_diff CASCADE;
DROP TABLE IF EXISTS incoming_contract_events CASCADE;
DROP TABLE IF EXISTS contract_versions CASCADE;

CREATE TABLE contract_versions (
    contract_name  text        NOT NULL,
    version        integer     NOT NULL CHECK (version > 0),
    registered_at  timestamptz NOT NULL,
    schema_doc     jsonb       NOT NULL
        CHECK (jsonb_typeof(schema_doc -> 'fields') = 'object'),
    PRIMARY KEY (contract_name, version)
);

CREATE TABLE incoming_contract_events (
    event_id          text        PRIMARY KEY,
    contract_name     text        NOT NULL,
    declared_version  integer     NOT NULL,
    received_at       timestamptz NOT NULL,
    payload           jsonb       NOT NULL CHECK (jsonb_typeof(payload) = 'object'),
    FOREIGN KEY (contract_name, declared_version)
        REFERENCES contract_versions (contract_name, version)
);

INSERT INTO contract_versions
    (contract_name, version, registered_at, schema_doc)
VALUES
(
    'orders.event', 1, '2026-10-01 09:00:00+00',
    '{
      "fields": {
        "event_id":    {"type": "string",  "nullable": false},
        "customer_id": {"type": "string",  "nullable": false},
        "amount":      {"type": "number",  "nullable": false},
        "currency":    {"type": "string",  "nullable": false},
        "event_ts":    {"type": "string",  "nullable": false}
      }
    }'::jsonb
),
(
    'orders.event', 2, '2026-10-15 09:00:00+00',
    '{
      "fields": {
        "event_id":     {"type": "string",  "nullable": false},
        "customer_id":  {"type": "string",  "nullable": false},
        "amount":       {"type": "number",  "nullable": false},
        "currency":     {"type": "string",  "nullable": false},
        "event_ts":     {"type": "string",  "nullable": false},
        "source_system":{"type": "string",  "nullable": true}
      }
    }'::jsonb
),
(
    'orders.event', 3, '2026-10-31 05:30:00+00',
    '{
      "fields": {
        "event_id":     {"type": "string",  "nullable": false},
        "customer_id":  {"type": "string",  "nullable": false},
        "amount":       {"type": "string",  "nullable": false},
        "event_ts":     {"type": "string",  "nullable": false},
        "source_system":{"type": "string",  "nullable": true},
        "discount_code":{"type": "string",  "nullable": false}
      }
    }'::jsonb
);

INSERT INTO incoming_contract_events
    (event_id, contract_name, declared_version, received_at, payload)
VALUES
(
    'evt-1001', 'orders.event', 2, '2026-10-31 05:40:00+00',
    '{"event_id":"evt-1001","customer_id":"C-101","amount":125.50,
      "currency":"INR","event_ts":"2026-10-31T05:39:58Z",
      "source_system":"mobile"}'::jsonb
),
(
    'evt-1002', 'orders.event', 2, '2026-10-31 05:41:00+00',
    '{"event_id":"evt-1002","customer_id":"C-102","currency":"INR",
      "event_ts":"2026-10-31T05:40:58Z","source_system":"web"}'::jsonb
),
(
    'evt-1003', 'orders.event', 2, '2026-10-31 05:42:00+00',
    '{"event_id":"evt-1003","customer_id":"C-103","amount":99.00,
      "currency":"INR","event_ts":"2026-10-31T05:41:58Z",
      "source_system":"partner","campaign_id":"DIWALI26"}'::jsonb
),
(
    'evt-1004', 'orders.event', 2, '2026-10-31 05:43:00+00',
    '{"event_id":"evt-1004","customer_id":"C-104","amount":"125.50",
      "currency":"INR","event_ts":"2026-10-31T05:42:58Z",
      "source_system":"mobile"}'::jsonb
),
(
    'evt-1005', 'orders.event', 2, '2026-10-31 05:44:00+00',
    '{"event_id":"evt-1005","customer_id":"C-105","amount":0,
      "currency":"INR","event_ts":"2026-10-31T05:43:58Z",
      "source_system":null}'::jsonb
),
(
    'evt-1006', 'orders.event', 2, '2026-10-31 05:45:00+00',
    '{"event_id":"evt-1006","customer_id":"C-106","amount":null,
      "currency":"INR","event_ts":"2026-10-31T05:44:58Z",
      "source_system":"batch"}'::jsonb
);

/*
Reusable field-level diff:
- ADDED / REMOVED
- TYPE_CHANGED
- NULLABILITY_TIGHTENED / NULLABILITY_RELAXED
Unchanged fields are retained for auditability but filtered in Q1.
*/
CREATE OR REPLACE VIEW v_contract_field_diff AS
WITH version_docs AS (
    SELECT
        contract_name,
        version,
        schema_doc AS current_doc,
        LAG(schema_doc) OVER (
            PARTITION BY contract_name ORDER BY version
        ) AS previous_doc
    FROM contract_versions
),
current_fields AS (
    SELECT
        v.contract_name,
        v.version,
        f.key AS field_name,
        f.value AS field_def
    FROM version_docs v
    CROSS JOIN LATERAL jsonb_each(v.current_doc -> 'fields') AS f(key, value)
    WHERE v.previous_doc IS NOT NULL
),
previous_fields AS (
    SELECT
        v.contract_name,
        v.version,
        f.key AS field_name,
        f.value AS field_def
    FROM version_docs v
    CROSS JOIN LATERAL jsonb_each(v.previous_doc -> 'fields') AS f(key, value)
    WHERE v.previous_doc IS NOT NULL
)
SELECT
    COALESCE(c.contract_name, p.contract_name) AS contract_name,
    COALESCE(c.version, p.version) AS version,
    COALESCE(c.field_name, p.field_name) AS field_name,
    p.field_def AS previous_field,
    c.field_def AS current_field,
    CASE
        WHEN p.field_name IS NULL THEN 'ADDED'
        WHEN c.field_name IS NULL THEN 'REMOVED'
        WHEN c.field_def ->> 'type' IS DISTINCT FROM p.field_def ->> 'type'
            THEN 'TYPE_CHANGED'
        WHEN COALESCE((p.field_def ->> 'nullable')::boolean, true)
             AND NOT COALESCE((c.field_def ->> 'nullable')::boolean, true)
            THEN 'NULLABILITY_TIGHTENED'
        WHEN NOT COALESCE((p.field_def ->> 'nullable')::boolean, true)
             AND COALESCE((c.field_def ->> 'nullable')::boolean, true)
            THEN 'NULLABILITY_RELAXED'
        ELSE 'UNCHANGED'
    END AS change_type
FROM current_fields c
FULL OUTER JOIN previous_fields p
    ON p.contract_name = c.contract_name
   AND p.version = c.version
   AND p.field_name = c.field_name;


/*-----------------------------------------------------------------------------
Q1. Produce a field-level diff between each adjacent contract version.

Problem:
Show only fields that changed. Preserve both the previous and current field
definitions so reviewers can see exactly what changed.

Optimized solution:
----------------------------------------------------------------------------*/
SELECT
    contract_name,
    version,
    field_name,
    change_type,
    previous_field,
    current_field
FROM v_contract_field_diff
WHERE change_type <> 'UNCHANGED'
ORDER BY version, field_name;

/*
Explanation:
The LAG window function compares each version with its immediate predecessor.
The JSONB expansion happens once in the reusable view, rather than repeating
schema parsing in every downstream exercise.
*/


/*-----------------------------------------------------------------------------
Q2. Classify each version change using a conservative compatibility policy.

Policy for this exercise:
- Removed field, changed type, or tightened nullability => BREAKING.
- Added required field => BREAKING for existing producers.
- Added nullable field only => ADDITIVE_OPTIONAL.
- Otherwise => NO_BREAKING_CHANGE.

Problem:
Build a release-review summary for versions 2 and 3.
----------------------------------------------------------------------------*/
SELECT
    contract_name,
    version,
    CASE
        WHEN COUNT(*) FILTER (
            WHERE change_type IN (
                'REMOVED', 'TYPE_CHANGED', 'NULLABILITY_TIGHTENED'
            )
        ) > 0
        OR COUNT(*) FILTER (
            WHERE change_type = 'ADDED'
              AND COALESCE((current_field ->> 'nullable')::boolean, true) = false
        ) > 0
            THEN 'BREAKING'
        WHEN COUNT(*) FILTER (WHERE change_type = 'ADDED') > 0
            THEN 'ADDITIVE_OPTIONAL'
        ELSE 'NO_BREAKING_CHANGE'
    END AS compatibility_result,
    COUNT(*) FILTER (WHERE change_type = 'ADDED') AS fields_added,
    COUNT(*) FILTER (WHERE change_type = 'REMOVED') AS fields_removed,
    COUNT(*) FILTER (WHERE change_type = 'TYPE_CHANGED') AS types_changed
FROM v_contract_field_diff
GROUP BY contract_name, version
ORDER BY contract_name, version;

/*
Expected spot check:
- Version 2 is ADDITIVE_OPTIONAL (source_system is nullable).
- Version 3 is BREAKING (currency removed, amount type changed, and a required
  discount_code field was added).

Compatibility direction is policy-specific. A production schema registry must
state whether it enforces backward, forward, or full compatibility.
*/


/*-----------------------------------------------------------------------------
Q3. Find payload keys that are not registered in the event's declared version.

Problem:
Identify producer fields that have not been added to the contract. Do not
mistake a registered field with a JSON null value for an unknown field.
----------------------------------------------------------------------------*/
SELECT
    e.event_id,
    p.key AS unexpected_field
FROM incoming_contract_events e
JOIN contract_versions cv
  ON cv.contract_name = e.contract_name
 AND cv.version = e.declared_version
CROSS JOIN LATERAL jsonb_object_keys(e.payload) AS p(key)
LEFT JOIN LATERAL jsonb_each(cv.schema_doc -> 'fields') AS f(key, field_def)
  ON f.key = p.key
WHERE f.key IS NULL
ORDER BY e.event_id, p.key;

/*
Expected spot check:
evt-1003 contains the unregistered campaign_id key.
The anti-join avoids expanding or comparing the full payload repeatedly.
*/


/*-----------------------------------------------------------------------------
Q4. Find missing or JSON-null values for required fields.

Problem:
Return one row per event and required field that is absent or explicitly null.
Nullable fields such as source_system must not be reported.
----------------------------------------------------------------------------*/
SELECT
    e.event_id,
    f.field_name AS missing_required_field
FROM incoming_contract_events e
JOIN contract_versions cv
  ON cv.contract_name = e.contract_name
 AND cv.version = e.declared_version
CROSS JOIN LATERAL jsonb_each(cv.schema_doc -> 'fields')
    AS f(field_name, field_def)
WHERE COALESCE((f.field_def ->> 'nullable')::boolean, true) = false
  AND (
        NOT (e.payload ? f.field_name)
        OR e.payload -> f.field_name = 'null'::jsonb
      )
ORDER BY e.event_id, f.field_name;

/*
Expected spot checks:
- evt-1002 is missing amount.
- evt-1006 has an explicit JSON null for amount.
- evt-1005 is valid with respect to source_system nullability.
*/


/*-----------------------------------------------------------------------------
Q5. Detect values whose JSON type does not match the registered field type.

Supported types in this exercise: string, number, integer, boolean.
Unknown type declarations fail closed and require an explicit validator.
----------------------------------------------------------------------------*/
SELECT
    e.event_id,
    f.field_name,
    f.field_def ->> 'type' AS expected_type,
    jsonb_typeof(e.payload -> f.field_name) AS actual_json_type,
    e.payload -> f.field_name AS actual_value
FROM incoming_contract_events e
JOIN contract_versions cv
  ON cv.contract_name = e.contract_name
 AND cv.version = e.declared_version
CROSS JOIN LATERAL jsonb_each(cv.schema_doc -> 'fields')
    AS f(field_name, field_def)
WHERE e.payload ? f.field_name
  AND e.payload -> f.field_name <> 'null'::jsonb
  AND NOT (
      CASE f.field_def ->> 'type'
          WHEN 'string' THEN
              jsonb_typeof(e.payload -> f.field_name) = 'string'
          WHEN 'number' THEN
              jsonb_typeof(e.payload -> f.field_name) = 'number'
          WHEN 'integer' THEN
              jsonb_typeof(e.payload -> f.field_name) = 'number'
              AND ((e.payload -> f.field_name) #>> '{}') ~ '^-?[0-9]+$'
          WHEN 'boolean' THEN
              jsonb_typeof(e.payload -> f.field_name) = 'boolean'
          ELSE false
      END
  )
ORDER BY e.event_id, f.field_name;

/*
Expected spot check:
evt-1004 sends amount as a JSON string even though version 2 declares number.
For production, add domain validators for decimal precision, timestamp format,
enum membership, string length, and cross-field business rules.
*/


/*-----------------------------------------------------------------------------
Q6. Build one consolidated event-level contract-quality report.

Problem:
For every incoming event, report missing required fields, unexpected fields,
and type mismatches. Keep clean events in the output with zero counts.
----------------------------------------------------------------------------*/
WITH field_checks AS (
    SELECT
        e.event_id,
        COUNT(*) FILTER (
            WHERE COALESCE((f.field_def ->> 'nullable')::boolean, true) = false
              AND (
                    NOT (e.payload ? f.field_name)
                    OR e.payload -> f.field_name = 'null'::jsonb
                  )
        ) AS missing_required_fields,
        COUNT(*) FILTER (
            WHERE e.payload ? f.field_name
              AND e.payload -> f.field_name <> 'null'::jsonb
              AND NOT (
                  CASE f.field_def ->> 'type'
                      WHEN 'string' THEN
                          jsonb_typeof(e.payload -> f.field_name) = 'string'
                      WHEN 'number' THEN
                          jsonb_typeof(e.payload -> f.field_name) = 'number'
                      WHEN 'integer' THEN
                          jsonb_typeof(e.payload -> f.field_name) = 'number'
                          AND ((e.payload -> f.field_name) #>> '{}') ~ '^-?[0-9]+$'
                      WHEN 'boolean' THEN
                          jsonb_typeof(e.payload -> f.field_name) = 'boolean'
                      ELSE false
                  END
              )
        ) AS type_mismatches
    FROM incoming_contract_events e
    JOIN contract_versions cv
      ON cv.contract_name = e.contract_name
     AND cv.version = e.declared_version
    CROSS JOIN LATERAL jsonb_each(cv.schema_doc -> 'fields')
        AS f(field_name, field_def)
    GROUP BY e.event_id
),
extra_checks AS (
    SELECT
        e.event_id,
        COUNT(*) AS unexpected_fields
    FROM incoming_contract_events e
    JOIN contract_versions cv
      ON cv.contract_name = e.contract_name
     AND cv.version = e.declared_version
    CROSS JOIN LATERAL jsonb_object_keys(e.payload) AS p(key)
    LEFT JOIN LATERAL jsonb_each(cv.schema_doc -> 'fields') AS f(key, field_def)
      ON f.key = p.key
    WHERE f.key IS NULL
    GROUP BY e.event_id
)
SELECT
    e.event_id,
    COALESCE(fc.missing_required_fields, 0) AS missing_required_fields,
    COALESCE(ec.unexpected_fields, 0) AS unexpected_fields,
    COALESCE(fc.type_mismatches, 0) AS type_mismatches,
    CASE
        WHEN COALESCE(fc.missing_required_fields, 0)
           + COALESCE(ec.unexpected_fields, 0)
           + COALESCE(fc.type_mismatches, 0) = 0
        THEN 'VALID'
        ELSE 'QUARANTINE'
    END AS validation_status
FROM incoming_contract_events e
LEFT JOIN field_checks fc ON fc.event_id = e.event_id
LEFT JOIN extra_checks ec ON ec.event_id = e.event_id
ORDER BY e.event_id;


/*-----------------------------------------------------------------------------
Q7. Implement a release gate for proposed contract version 3.

Problem:
Block deployment when the proposed version contains a breaking change under
the policy in Q2. Return a single decision suitable for CI/CD consumption.
----------------------------------------------------------------------------*/
SELECT
    'orders.event' AS contract_name,
    3 AS proposed_version,
    CASE
        WHEN EXISTS (
            SELECT 1
            FROM v_contract_field_diff
            WHERE contract_name = 'orders.event'
              AND version = 3
              AND change_type IN (
                  'REMOVED', 'TYPE_CHANGED', 'NULLABILITY_TIGHTENED'
              )
        )
        OR EXISTS (
            SELECT 1
            FROM v_contract_field_diff
            WHERE contract_name = 'orders.event'
              AND version = 3
              AND change_type = 'ADDED'
              AND COALESCE((current_field ->> 'nullable')::boolean, true) = false
        )
        THEN 'BLOCK_RELEASE'
        ELSE 'ALLOW_RELEASE'
    END AS release_decision;


/*-----------------------------------------------------------------------------
Q8. Review indexing and scale-out choices.

Problem:
Inspect representative access paths and explain which index supports each
filter. Enable these indexes only after measuring representative workloads.
----------------------------------------------------------------------------*/
-- CREATE INDEX ix_contract_versions_name_version
--     ON contract_versions (contract_name, version DESC);

-- CREATE INDEX ix_incoming_contract_version_received
--     ON incoming_contract_events
--        (contract_name, declared_version, received_at DESC);

-- Useful for containment predicates such as payload @> '{"currency":"INR"}'.
-- It does not automatically accelerate jsonb_object_keys/jsonb_each expansion.
-- CREATE INDEX ix_incoming_payload_gin
--     ON incoming_contract_events USING GIN (payload jsonb_path_ops);

-- Example plan inspection:
-- EXPLAIN (ANALYZE, BUFFERS)
-- SELECT event_id
-- FROM incoming_contract_events
-- WHERE contract_name = 'orders.event'
--   AND declared_version = 2
--   AND received_at >= timestamptz '2026-10-31 00:00:00+00';

 /*
PERFORMANCE AND PRODUCTION NOTES
--------------------------------
1. Keep contract_name/version relational and indexed; do not discover the
   applicable schema by scanning every registered JSON document.
2. Validate only the arriving micro-batch. Persist validation results so
   downstream quarantine and monitoring jobs do not parse the payload again.
3. JSONB GIN indexes help containment/path predicates, not every lateral
   expansion. Benchmark with EXPLAIN (ANALYZE, BUFFERS) and realistic volumes.
4. For high-throughput systems, normalize schema fields into a child table
   keyed by (contract_name, version, field_name), or cache compiled validators.
5. Partition a large event table by received_at and retain raw payloads for
   replay. Store validator version and validation timestamp for auditability.
6. Define compatibility direction explicitly. Optional additions, defaults,
   enum changes, decimal precision, and timestamp formats need contract-specific
   rules; the simplified policy above is intentionally conservative.

INTERVIEW FOLLOW-UPS
--------------------
- How would you enforce backward versus forward compatibility?
- How should a producer roll out a required field without breaking consumers?
- When would you use Avro/Protobuf plus a schema registry instead of JSONB?
- How would you quarantine invalid events while preserving replayability?
- Which metrics would you publish for contract drift and producer adoption?
===============================================================================
*/
