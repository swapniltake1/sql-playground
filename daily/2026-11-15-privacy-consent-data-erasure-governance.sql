) expresses interval intersection directly. For a large
-- hold table, a GiST index over a generated range can accelerate overlap
-- searches. The self-join uses hold_id ordering to emit each pair once.
-- -----------------------------------------------------------------------------

SELECT h1.subject_id,
       h1.asset_id,
       h1.hold_id AS hold_id_1,
       h2.hold_id AS hold_id_2,
       h1.hold_reason AS reason_1,
       h2.hold_reason AS reason_2,
       tstzrange(
           h1.valid_from, COALESCE(h1.valid_to, 'infinity'::timestamptz), '[)'
       ) * tstzrange(
           h2.valid_from, COALESCE(h2.valid_to, 'infinity'::timestamptz), '[)'
       ) AS overlap_window
FROM privacy_legal_hold AS h1
JOIN privacy_legal_hold AS h2
  ON h2.subject_id = h1.subject_id
 AND h2.asset_id IS NOT DISTINCT FROM h1.asset_id
 AND h2.hold_id > h1.hold_id
 AND tstzrange(
         h1.valid_from, COALESCE(h1.valid_to, 'infinity'::timestamptz), '[)'
     )
     &&
     tstzrange(
         h2.valid_from, COALESCE(h2.valid_to, 'infinity'::timestamptz), '[)'
     )
ORDER BY h1.subject_id, h1.asset_id, h1.hold_id, h2.hold_id;

-- =============================================================================
-- PERFORMANCE LAB AND PRODUCTION DESIGN NOTES
-- =============================================================================
--
-- A. Capture plans using representative cardinalities:
--
--    EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
--    SELECT ...;
--
-- B. Indexing:
--    * Consent canonicalization: source_event_id, revision DESC, received_at.
--    * Current consent lookup: subject_id, purpose, channel, occurred_at DESC.
--    * Live subject records: partial index where erased_at IS NULL.
--    * DSAR operations: partial due-date index for incomplete requests.
--    * Erasure idempotency: UNIQUE (request_id, asset_id) is a correctness
--      constraint, not merely a performance optimization.
--    * Legal holds: benchmark B-tree equality/range filtering against GiST
--      range indexing for the actual hold-query workload.
--
-- C. Event-time correctness:
--    * Keep occurred_at (business event time) separate from received_at
--      (ingestion time). Late arrivals should not silently rewrite history.
--    * Define an explicit policy for backdated consent corrections and
--      re-evaluate affected processing decisions where required.
--
-- D. Erasure orchestration:
--    * Treat external deletion as an asynchronous distributed workflow.
--    * Use durable idempotency keys, bounded retries, leases, and dead-letter
--      handling. Never assume a successful API response proves every replica,
--      cache, backup, or derived store has been handled.
--    * Keep legal holds and statutory retention exceptions in an auditable
--      policy layer. A hold should suppress only the legally scoped data.
--
-- E. Privacy engineering:
--    * A pseudonymous UUID is still personal data if a re-identification map
--      exists. Restrict and audit access to the mapping.
--    * Minimize payloads in logs and exception feeds. Do not log raw personal
--      attributes merely to make a deletion job easier to debug.
--    * Model backups, search indexes, caches, feature stores, exports, and
--      downstream vendors explicitly in the asset registry.
--    * Retention and erasure rules depend on jurisdiction, purpose, contract,
--      and legal advice. The sample policy values are fictional.
--
-- F. Questions for interview discussion:
--    1. How would you process a late-arriving withdrawal after a campaign ran?
--    2. How would you prove deletion across Kafka, object storage, and replicas?
--    3. How would you prevent a worker from deleting data after a new legal hold?
--    4. What is the correct transaction boundary for claiming a job and calling
--       an external vendor API?
--    5. How would you partition a consent ledger while preserving subject-level
--       audit and correction history?
--
-- End of practice.
-- =============================================================================
