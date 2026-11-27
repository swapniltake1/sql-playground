# SQL Playground

A curated SQL practice repository focused on **interview preparation** and **hands-on query building** from basic to expert level.

This project is designed for learners, job seekers, and practitioners who want to strengthen practical SQL problem-solving using real interview-style question patterns.

## What You’ll Find

- **Basic SQL questions**: grouping, filtering, joins, aggregates, top-N queries.
- **Intermediate SQL questions**: business-style analytics, nested queries, and window functions.
- **Advanced SQL questions**: CTE-based logic, customer behavior analysis, and time-based problems.
- **Expert SQL questions**: Pareto analysis, cohort analysis, distribution metrics, and percentile-based segmentation.
- **Practice schema**: a starter database structure to test and run all query patterns.
- **Optional data loading script**: Python helper to populate fake data for practice.

## Repository Structure

- `MASTER_PRACTICE_DATABASE.sql` — base schema (Employee, Orders, Sales, Products, etc.)
- `Basic.sql` — beginner-friendly interview questions
- `INTERMEDIATE.sql` — medium complexity interview questions
- `ADVANCED.sql` — high-complexity SQL scenarios
- `EXPERT.sql` — expert-level analytics-style SQL questions
- `load_fake_data.py` — helper script for generating/loading sample data
- `all qustions.pdf` — compiled question set in PDF format

## How to Use

1. **Create a database** in your preferred SQL engine (PostgreSQL/MySQL/SQL Server/Oracle-compatible with minor syntax adjustments).
2. Run `MASTER_PRACTICE_DATABASE.sql` to create the required tables.
3. (Optional) Use `load_fake_data.py` to insert sample/fake data.
4. Start solving queries in this order:
   - `Basic.sql`
   - `INTERMEDIATE.sql`
   - `ADVANCED.sql`
   - `EXPERT.sql`
5. Compare your approach with the provided sample query patterns.

## Recommended Practice Plan

- **Week 1:** Basic + fundamentals revision (joins, group by, subqueries)
- **Week 2:** Intermediate + window functions
- **Week 3:** Advanced + business case questions
- **Week 4:** Expert + timed mock interview practice

## Interview Topics Covered

- Duplicate detection
- Top-N and ranking problems
- Missing/unsold entity detection
- Revenue and order analytics
- Moving averages and cumulative metrics
- Customer churn and first-order analysis
- Cohort analysis
- Pareto principle (80/20)
- Percentile and segmentation logic

## Notes

- SQL syntax can vary slightly by database system.
- Some queries may require small adjustments for your SQL dialect (e.g., `FETCH FIRST`, `DATEDIFF`, `INTERVAL`, `DATE_TRUNC`, `PERCENTILE_CONT`).
- Focus on understanding the logic behind each query, not just memorizing syntax.

## Contributing

Contributions are welcome.
If you want to add more interview questions, optimized solutions, or database-specific variants, feel free to open a pull request.

## License

Use this repository for learning and interview preparation.
Add a formal license file (`LICENSE`) if you plan to distribute this project publicly.


## Banking SQL Practice

Practice SQL with a realistic banking dataset covering customers, accounts, and transactions.

- [Banking SQL Practice Q01-Q15](banking-sql-practice-questions.sql) — setup script, sample data, questions, and commented solutions.
- [Extra Banking SQL Practice Q16-Q40](extra-banking-sql-practice-questions.sql) — 25 additional questions and commented answer queries.

**How to run:** First run `banking-sql-practice-questions.sql` in PostgreSQL to create and seed the tables. Then try the questions in `extra-banking-sql-practice-questions.sql`. Solutions are commented out so you can attempt each query before checking the answer.

The exercises cover filtering, joins, aggregation, CTEs, subqueries, anti-joins, window functions, ranking, running totals, and banking analytics. SQL dialect differences may require small syntax adjustments.


### Data Engineering SQL Practice

- [Data Engineering SQL Practice](data-engineering-sql-practice.sql) — 20 hands-on questions using sample customer, order, and pipeline-run data.
- Topics include deduplication with `ROW_NUMBER()`, incremental-load filters, late-arriving data, NULL checks, referential integrity, pipeline monitoring, data reconciliation, and SCD-style change detection.

Run this file independently in PostgreSQL. It creates its own `de_customers`, `de_orders`, and `de_pipeline_runs` tables. The answer key is commented out so you can try each question first.


### Daily SQL Practice — 2026-10-27

- [SQL Optimization Practice — 2026-10-27](daily/2026-10-27-sql-optimization-practice.sql) — 10 problems with optimized PostgreSQL solutions and performance notes.
- Topics: SARGable date filters, `LEFT JOIN` correctness, `EXISTS` / `NOT EXISTS`, conditional aggregation, window functions, top-N per city, and query-plan basics.
- Run the file in PostgreSQL. It creates its own isolated tables; solutions are commented out so you can attempt the questions first.


### Daily SQL Practice — 2026-10-27: Subscription Cohort Analytics

- [Subscription Cohort & Revenue Analytics](daily/2026-10-27-subscription-cohort-analytics.sql) — eight interview-style problems covering month-end subscriber snapshots, MRR, first-time subscribers, churn, reactivation, cohort retention, revenue growth, and plan mix.
- Includes independent PostgreSQL sample tables and data, commented solutions, optimization rationale, index considerations, and performance-analysis notes.
- Run the file in PostgreSQL. Solutions are commented out so you can attempt each question before reviewing the answer.


### Daily SQL Practice — 2026-10-28: Inventory Ledger Analytics

- [Inventory Ledger Reconciliation & Stock Movement Analytics](daily/2026-10-28-inventory-ledger-analytics.sql) — 12 interview-style exercises using warehouse, product, movement-ledger, and physical-snapshot data.
- Topics include signed stock movements, deterministic running balances, negative-stock detection, ledger-to-snapshot reconciliation, anti-joins, top-N shipments per warehouse, seven-calendar-day rolling totals, SARGable timestamp filters, and query-plan analysis.
- Includes independent PostgreSQL setup and sample data, commented solutions, optimization rationale, index candidates, expected spot checks, and interview follow-up questions.

Run this file independently in PostgreSQL 14+. Attempt each question before reviewing its commented solution. Index recommendations are candidates to benchmark with `EXPLAIN (ANALYZE, BUFFERS)`, not guaranteed improvements for the small sample dataset.

### Daily SQL Practice — 2026-10-30: Clickstream Sessionization & Funnel Analytics

- [Clickstream Sessionization & Funnel Analytics](daily/2026-10-30-clickstream-sessionization-funnel.sql) — eight PostgreSQL interview exercises covering replay-safe event deduplication, 30-minute inactivity sessions, DAU, ordered conversion funnels, session revenue, late-arriving events, first-touch campaign attribution, and 1-to-7-day returning users.
- Includes an isolated clickstream event dataset, commented solutions, expected spot checks, index candidates, EXPLAIN guidance, and production-scale performance considerations.

Run the file in PostgreSQL 14+. Execute the Q2 view-building solution before Q3-Q8; all answer queries and optional index statements are commented out so you can attempt each problem first.

### Hourly Data Engineering Practice — 2026-10-30 23:00

- [Customer CDC to SCD Type 2 Dimension](daily/2026-10-30-2300-customer-scd2-cdc.sql) — PostgreSQL exercises on idempotent CDC ingestion, event deduplication, effective-dated dimension updates, soft deletes, point-in-time fact joins, and history integrity checks.
- Includes isolated customer dimension and CDC staging data, commented solutions, transaction-safe batch application, index candidates, and EXPLAIN/performance guidance.

### Hourly Data Engineering Practice — 2026-10-31 00:03

- [Pipeline SLA Observability, Retry Analysis & Data Freshness](daily/2026-10-31-0003-pipeline-sla-observability.sql) — eight PostgreSQL exercises covering latest-attempt status, retry recovery, scheduler delay, execution-duration SLAs, source-watermark freshness, logical-run reliability, zero-row success anomalies, and an operations health view.
- Includes isolated pipeline SLA configuration and attempt history, optimized window/aggregate queries, candidate indexes, EXPLAIN guidance, and production monitoring follow-ups.

Run independently in PostgreSQL 14+. The sample timestamps are fixed for reproducibility; benchmark suggested indexes with representative history volumes.


### Hourly Data Engineering Practice — 2026-10-31 01:04

- [Join Fanout Prevention & Pre-Aggregated Fact Analytics](daily/2026-10-31-0104-join-fanout-preaggregation.sql) — seven PostgreSQL exercises showing how joining multiple one-to-many fact tables inflates measures, and how to restore correct order/customer grain by aggregating lines, captured payments, and shipments independently before joining.
- Includes isolated customer/order/line/payment/shipment sample data, reconciliation and orphan checks, ranking, partial-index candidates, and EXPLAIN (ANALYZE, BUFFERS) performance guidance.

Run independently in PostgreSQL 14+. The first exercise demonstrates the fanout; subsequent solutions use one-row-per-order aggregates to prevent double counting.


### Hourly Data Engineering Practice — 2026-10-31 02:00

- [Recursive BOM Explosion, Material Requirements & Cost Roll-Up](daily/2026-10-31-0200-recursive-bom-cost-rollup.sql) — eight PostgreSQL exercises using effective-dated multi-level bills of materials and production orders. Topics include recursive quantity multiplication, leaf-material demand, partial cost completeness, missing component masters, future-revision cycle detection, procurement roll-ups, and index/plan analysis.
- Includes isolated parts, BOM, and production-order sample data; path-based recursion guards; commented problem/solution sections; and production notes on shared subassemblies, effective-date overlaps, closure tables, and cycle remediation.

Run independently in PostgreSQL 14+. The future PANEL-12 to FRAME-10 edge is intentionally invalid and is used only by Q6 to demonstrate cycle detection for the 2 Nov 2026 as-of date.


### Hourly Data Engineering Practice — 2026-10-31 03:01

- [Double-Entry Ledger Controls & Trial-Balance Reconciliation](daily/2026-10-31-0301-double-entry-ledger-controls.sql) — eight PostgreSQL exercises covering journal-entry balancing, debit/credit-normal trial balances, deterministic general-ledger running balances, replayed source references, unknown/inactive accounts, empty entries, batch reconciliation, and a consolidated control-exception feed.
- Includes isolated chart-of-accounts, journal-header, and journal-line sample data with intentional control failures, optimized posted-only aggregation, candidate indexes, currency-grain cautions, and EXPLAIN (ANALYZE, BUFFERS) performance guidance.

Run independently in PostgreSQL 14+. The sample intentionally contains an unbalanced posted entry, a replayed POS source reference, an unknown account, an inactive account, and an empty posted entry so the control queries return meaningful exceptions.

### Daily SQL Practice — 2026-10-31 (03:58)

- [Data Vault Hub, Link & Satellite Loads](daily/2026-10-31-0358-data-vault-hub-link-satellite-loads.sql) — practical PostgreSQL exercises for replay-safe Data Vault 2.0 loading.
- Topics: canonical event deduplication, deterministic hash keys, Hub and Link loading, hashdiff-based Satellite historization, current-state and point-in-time queries, and structural controls.

### Hourly Data Engineering Practice — 2026-10-31 04:58

- [FX As-Of Joins, Stale Rates & Multi-Currency Valuation](daily/2026-10-31-0458-fx-asof-valuation.sql) — eight PostgreSQL exercises covering provider quote canonicalization, transaction-date as-of joins, missing/stale-rate controls, daily USD translation, month-end revaluation, provider dispersion, rate-jump monitoring, and index/plan analysis.
- Includes isolated FX observation and transaction tables, competing provider quotes, a missing AUD quote, a stale JPY quote, signed refunds, commented problem/solution explanations, expected spot checks, and performance notes. Run independently in PostgreSQL 14+.


### Hourly Data Engineering Practice — 2026-10-31 06:00

- [Data Contract Compatibility Audit & JSONB Payload Validation](daily/2026-10-31-0600-data-contract-compatibility-audit.sql) — eight PostgreSQL exercises covering adjacent-version field diffs, compatibility classification, unexpected payload keys, missing required values, JSON type mismatches, event-level quality reporting, CI/CD release gating, and index/plan analysis.
- Includes isolated versioned event-contract snapshots and intentionally invalid incoming payloads, a reusable field-diff view, expected spot checks, conservative compatibility rules, and production performance notes. Run independently in PostgreSQL 14+.


### Hourly Data Engineering Practice — 2026-10-31 07:02

- [Promotion Eligibility, Stacking Rules & Discount Allocation](daily/2026-10-31-0702-promotion-stacking-discount-allocation.sql) — eight PostgreSQL exercises using retail orders, product scope, promotion validity windows, priority groups, and coupon redemptions. Topics include eligible-subtotal calculation, deterministic one-per-stack-group selection, redemption auditing, cent-exact proportional discount allocation, post-discount contribution margin, campaign performance, and overlapping-promotion detection.
- Includes isolated sample schema/data, optimized LATERAL/EXISTS and window-function solutions, expected spot checks, candidate indexes, and performance notes. Run independently in PostgreSQL 14+.


### Hourly Data Engineering Practice — 2026-10-31 07:55

- [Inventory Movement Roll-Forward, Replay Safety & Stock Controls](daily/2026-10-31-0755-inventory-movement-rollforward.sql) — eight PostgreSQL exercises covering replay-safe movement canonicalization, as-of stock balances, deterministic negative-stock detection, dense daily closing snapshots, physical-count reconciliation, duplicate source-event audits, slow-moving inventory, reorder points, and inventory valuation.
- Includes isolated product, warehouse, opening-balance, movement-ledger, and physical-count sample data; optimized window/aggregate solutions; expected balance spot checks; index and partitioning guidance; and production interview follow-ups. Run independently in PostgreSQL 14+.


### Daily SQL Practice — 2026-10-31: Time-Zone-Aware Event Reporting Across DST

- [Time-Zone-Aware Event Reporting Across DST](daily/2026-10-31-timezone-aware-dst-reporting.sql) — eight PostgreSQL exercises using multi-tenant meter events and IANA time-zone configuration. Topics include UTC-to-local conversion, tenant-local business dates, SARGable local-day filters, repeated fall-back hours, DST-aware hourly spines, 23/25-hour calendar days, zero-filled daily reporting, and ambiguous-hour detection.
- Includes isolated PostgreSQL 14+ sample tables for New York, London, and India; explicit-offset event timestamps; optimized UTC-boundary predicates; expected DST assertions; index/partitioning guidance; and interview follow-ups.

Run independently in PostgreSQL 14+. The sample demonstrates New York's 23-hour spring-forward day and 25-hour fall-back day, plus London's 25-hour fall-back day. Keep UTC instants as the event-time source of truth and use tenant IANA zones for reporting.


### Daily SQL Practice — 2026-11-02: Card Fraud Velocity & Alerting

- [Card Fraud Velocity, Peer Baselines & Idempotent Alerting](daily/2026-11-02-card-fraud-velocity-monitoring.sql) — eight PostgreSQL exercises covering rolling 10-minute card velocity, category-level P95 amount outliers, cross-border approvals, repeated authorization detection, explainable rule scoring, hourly status controls, and idempotent alert persistence.
- Includes isolated card, merchant, and transaction sample data; executable solutions; expected spot checks; a rule-hit view; an idempotent alert sink with reconciliation; index/partitioning candidates; EXPLAIN guidance; and production-scale interview follow-ups.

Run independently in PostgreSQL 14+. All sample event timestamps are explicit UTC instants. The rule score is illustrative only; production thresholds and weights require calibration and governance.


### Daily SQL Practice — 2026-11-02: PostgreSQL Partition Pruning & Retention

- [PostgreSQL Declarative Partitioning, Pruning & Retention](daily/2026-11-02-postgres-partition-pruning-retention.sql) — eight practical PostgreSQL exercises covering monthly range partitions, partition-pruned time filters, tenant/day roll-ups, latest-row access, replay-safe inserts, prevalidated partition attachment, partition catalog/storage monitoring, cross-partition event-ID replay detection, and retention by detaching expired partitions.
- Includes isolated event-log setup with October and November partitions, realistic multi-tenant sample events, a staged December partition, executable solutions, expected assertions, B-tree/BRIN trade-offs, EXPLAIN guidance, and production interview follow-ups.

Run independently in PostgreSQL 14+. Execute Q1-Q8 in order; Q5 attaches the December staging table and Q8 detaches October. The composite key (event_ts, event_id) is partition-compatible but does not enforce global event_id uniqueness across partitions.

### Daily SQL Practice — 2026-11-03: PostgreSQL Multi-Tenant Row-Level Security

- [PostgreSQL Row-Level Security for Multi-Tenant Analytics](daily/2026-11-03-postgres-row-level-security-multitenancy.sql) — eight practical exercises covering tenant-scoped reads and writes, fail-closed behavior when tenant context is absent, safe transaction-local context for pooled connections, policy composition (PERMISSIVE versus RESTRICTIVE), tenant-aware joins and keys, and RLS-aware indexing.
- Includes isolated PostgreSQL sample customers and orders for two tenants, composite tenant keys and foreign keys, RLS policies with `USING` / `WITH CHECK`, expected assertions, query-plan exercises, security caveats, and production performance notes. Run independently in PostgreSQL 14+ as a database owner/administrator in a disposable practice database.



### Daily SQL Practice — 2026-11-06: Source-to-Target Reconciliation

- [Source-to-Target Reconciliation, Control Totals & Exception Reporting](daily/2026-11-06-source-target-reconciliation-control-totals.sql) — eight PostgreSQL exercises covering deterministic CDC event deduplication, source/target row and amount control totals, missing/extra key detection, attribute-level mismatch checks, replay detection, exception summaries, and version-aware idempotent upserts with delete tombstones.
- Includes isolated banking transaction batches, intentional duplicate/replay and target-side exceptions, commented reference solutions, expected reconciliation checks, index candidates, currency-grain safeguards, and production batch-watermark guidance. Run independently in PostgreSQL 14+.

### Daily SQL Practice — 2026-11-06: Transactional Outbox & Reliable Event Delivery

- [Transactional Outbox, Concurrent Delivery, Retries & Idempotent Consumers](daily/2026-11-06-transactional-outbox-delivery.sql) — eight PostgreSQL exercises covering atomic business/event writes, concurrent publisher claims with `FOR UPDATE SKIP LOCKED`, lease recovery, broker acknowledgements, capped exponential retry, dead-letter handling, consumer inbox idempotency, backlog observability, and bounded retention cleanup.
- Includes isolated order/outbox sample tables with ready, leased, retry-wait, published, and exhausted events; runnable SQL solutions; expected control assertions; partial-index and query-plan guidance; and production interview follow-ups. Run independently in PostgreSQL 14+ in a disposable database.


### Daily SQL Practice — 2026-11-11: Marketplace Seller Payout Reconciliation

- [Marketplace Seller Payout Reconciliation, Reserves & Settlement Controls](daily/2026-11-11-marketplace-seller-payout-reconciliation.sql) — eight PostgreSQL exercises covering payout-grain financial aggregation, safe handling of one-to-many joins, duplicate source-event detection, seller ranking by currency and period, post-payment adjustment audits, full-outer-join bank reconciliation, reserve threshold checks, and latest payout state.
- Includes isolated seller payout, item, adjustment, and bank settlement sample data; reference solutions; integer-minor-unit and currency-grain safeguards; candidate indexes; and EXPLAIN guidance. Run independently in PostgreSQL 14+.


### Daily SQL Practice — 2026-11-11: Machine Telemetry Anomaly Detection

- [Industrial Machine Telemetry, Calibration & Anomaly Detection](daily/2026-11-11-machine-telemetry-anomaly-detection.sql) — ten PostgreSQL exercises covering replay-safe sensor-event deduplication, effective-dated calibration lookups, maintenance-window suppression, telemetry gap detection, leakage-safe rolling baselines, statistical anomaly flags, 15-minute rollups, expected-slot coverage, latest sensor state, and calibration-overlap controls.
- Includes isolated pump/compressor telemetry, calibration history, maintenance windows, intentional replay and quality exceptions, executable solutions, optimization explanations, index candidates, and production performance notes. Run independently in PostgreSQL 14+.


### Daily SQL Practice — 2026-11-11: PostGIS Delivery-Zone Analytics

- [PostGIS Delivery Zones, Nearest Hubs, Geofences & Spatial Aggregation](daily/2026-11-11-postgis-delivery-zone-analytics.sql) — ten PostgreSQL/PostGIS exercises covering coordinate validation and normalization, deterministic point-in-polygon assignment, unassigned-delivery detection, geography-based nearest-hub search, service-zone overlap measurement, local-day zone metrics, driver geofence transitions, GPS track reconstruction, and 500-metre density grids.
- Includes isolated landing and curated delivery tables, sample Pune-like geometries, driver GPS pings, GiST indexes, executable solutions, optimization explanations, and spatial performance guidance. Requires PostgreSQL 14+ and PostGIS 3.x. Run Q1-Q2 before Q3-Q10.

### Daily SQL Practice — 2026-11-12: A/B Experiment Analysis & CUPED

- [A/B Experiment Analysis, Sample Ratio Mismatch & CUPED](daily/2026-11-12-ab-experiment-analysis-cuped.sql) — nine PostgreSQL exercises covering replay-safe exposure/outcome deduplication, assignment-to-exposure coverage, chi-square sample-ratio-mismatch detection, intention-to-treat conversion and revenue metrics, cumulative first-purchase conversion, CUPED variance reduction, checkout/refund guardrails, cross-variant contamination, and pre-period balance diagnostics.
- Includes isolated experiment assignment, variant allocation, pre-period covariate, raw exposure, and raw outcome tables; intentionally duplicated event deliveries and an intentionally skewed 16:4 assignment split; executable solutions; optimization explanations; index candidates; expected SRM spot check; and production performance/statistical-design notes. Run independently in PostgreSQL 14+. The sample is for SQL practice only and must not be used to infer treatment effectiveness.



### Daily SQL Practice — 2026-11-12: SaaS Entitlements & Usage Metering

- [SaaS Entitlements, Usage Metering, Quotas & Invoice Controls](daily/2026-11-12-saas-entitlement-usage-metering.sql) — ten PostgreSQL exercises covering replay-safe usage-event deduplication, billing-period attribution, quota consumption, effective-dated feature entitlements, unauthorized usage detection, integer-minor-unit overage calculation, late-arrival monitoring, plan-level utilization benchmarks, billing-period gap/overlap controls, and idempotent invoice-usage snapshots.
- Includes isolated multi-tenant organizations, Starter/Growth plans, subscription periods, effective-dated entitlements, intentionally duplicated and late usage deliveries, out-of-period and unentitled events, commented reference solutions, optimization explanations, candidate indexes, and production performance/interview notes. Run independently in PostgreSQL 14+.

### Daily SQL Practice — 2026-11-13: Loan Delinquency Vintage & Roll-Rate Analytics

- [Loan Delinquency Vintage Curves & Roll-Rate Analytics](daily/2026-11-13-loan-delinquency-vintage-roll-rates.sql) — nine PostgreSQL exercises covering replay-safe monthly snapshot canonicalization, latest portfolio DPD buckets, origination-vintage curves, month-over-month roll-rate transitions, cure rates, weighted collections efficiency, branch risk concentration, missing snapshot detection, and source-data quality controls.
- Includes isolated loan-account and raw snapshot sample data with corrected/replayed deliveries, a missing month, and an intentional orphan record; commented reference solutions, expected spot checks, optimization explanations, index candidates, and EXPLAIN/performance guidance. Run independently in PostgreSQL 14+.

### Daily SQL Practice — 2026-11-14: Airline Network Operations

- [Airline Operations: Flight Delays, Turnarounds & Connection Risk](daily/2026-11-14-airline-operations-delay-connection-risk.sql) — nine PostgreSQL exercises covering replay-safe flight-event canonicalization, route-level departure/arrival on-time performance, airport delay percentiles, aircraft turnaround and delay propagation, passenger connection feasibility, gate-occupancy conflicts, aircraft rotation validation, cancellation impact, and event consistency checks.
- Includes an isolated airline schedule and operations-event dataset with corrected/replayed status updates, an intentionally short aircraft turn, overlapping gate assignments, passenger connections, and a contradictory cancellation/departure record. Commented reference solutions explain window functions, filtered aggregates, range-overlap indexing, deterministic deduplication, and production performance considerations. Run independently in PostgreSQL 14+.

### Daily SQL Practice — 2026-11-14: Telecom Roaming Usage Mediation & Revenue Assurance

- [Telecom Roaming Usage Mediation & Revenue Assurance](daily/2026-11-14-telecom-roaming-revenue-assurance.sql) — nine PostgreSQL exercises covering replay-safe CDR canonicalization, late-arriving usage and watermark lag, subscriber-local daily data caps, effective-dated tariff rating, partner/service revenue ranking, roaming settlement reconciliation, session sequence gaps, tariff overlap and coverage controls, and canonical source-data quality exceptions.
- Includes isolated subscriber, roaming-partner, tariff, CDR landing, and partner-statement sample data with intentional replays, corrections, a voided record, late usage, tariff overlap, an unrated service, and malformed source data. Commented reference solutions explain DISTINCT ON, LATERAL, window functions, FULL OUTER JOIN, BRIN/B-tree/GiST index choices, and production performance considerations. Run independently in PostgreSQL 14+.


### Daily SQL Practice — 2026-11-15: Cloud FinOps Cost Allocation & Anomaly Detection

- [Cloud FinOps: Cost Allocation, Budget Forecasting & Anomaly Detection](daily/2026-11-15-cloud-finops-cost-allocation-anomalies.sql) — nine PostgreSQL exercises covering replay-safe billing-line canonicalization, effective-dated resource-tag attribution, monthly service spend, budget run-rate forecasting, hourly commitment coverage, unallocated-cost exceptions, cost-center concentration, invoice control reconciliation, and seven-day spend anomaly detection.
- Includes isolated cloud-account, resource-tag, billing-delivery, budget, commitment, and invoice-control data with duplicate deliveries, a corrected charge, a voided line, a cost-center ownership change, unallocated usage, and a deliberate invoice variance. Solutions explain DISTINCT ON, LATERAL lookups, SARGable time filters, pre-aggregation, window frames, and B-tree/BRIN indexing. Run independently in PostgreSQL 14+.


### Daily SQL Practice — 2026-11-15: Privacy Consent & Data Erasure Governance

- [Privacy Consent, Data Subject Requests & Erasure Governance](daily/2026-11-15-privacy-consent-data-erasure-governance.sql) — ten PostgreSQL exercises covering replay-safe consent canonicalization, as-of consent decisions, purpose-specific processing gates, DSAR SLA reporting, legal-hold-aware erasure worklists, idempotent downstream job dispatch, erasure completion reconciliation, retention-expiry candidates, privacy-governance exception reporting, and overlapping legal-hold detection.
- Includes an isolated synthetic privacy schema, duplicate and corrected consent deliveries, orphan-event and incomplete-erasure exceptions, effective-dated legal holds, downstream job retries, optimized reference SQL, index rationale, and EXPLAIN/performance guidance. Run independently in PostgreSQL 14+ in a disposable database; the script recreates its dedicated `privacy_practice` schema.

### Daily SQL Practice — 2026-11-16: Insurance Claims & Reinsurance

- [Insurance Claims Adjudication, Reserve Development & Reinsurance](daily/2026-11-16-insurance-claims-reserving-reinsurance.sql) — ten PostgreSQL exercises covering replay-safe claim-event canonicalization, policy/coverage validation as of loss date, current adjuster assignment, paid/reserve/recovery reconstruction, large-loss concentration, reserve development triangles, excess-of-loss recoverables, effective-date overlap detection, notification SLA/claim aging, and a consolidated data-quality exception feed.
- Includes an isolated synthetic insurance schema with corrected and voided financial events, expired-policy and uncovered-loss cases, monthly reserve snapshots, an intentional negative reserve/payment, orphan records, and overlapping treaty terms. Solutions explain window functions, filtered aggregates, LATERAL lookups, half-open validity periods, indexing trade-offs, and EXPLAIN (ANALYZE, BUFFERS) performance analysis. Run independently in PostgreSQL 14+.

### Daily SQL Practice — 2026-11-16: Manufacturing Lot Traceability & Quality Yield

- [Manufacturing Lot Traceability, Quality Yield & Recall Readiness](daily/2026-11-16-manufacturing-lot-traceability-quality-yield.sql) — ten PostgreSQL exercises covering replay-safe MES genealogy canonicalization, first-pass yield, defect Pareto, multi-level component quantity explosion, forward recall traceability, landing-data quality controls, work-order attainment, cycle-time percentiles, genealogy cycle detection, and finished-lot release screening.
- Includes an isolated synthetic manufacturing schema with corrected/replayed genealogy events, a deliberate genealogy cycle, an orphan component, invalid consumption quantity, revised/voided inspections, and malformed quality records. Solutions explain deterministic window-based canonicalization, recursive CTE path guards, pre-aggregation to prevent fanout, anti-joins, candidate indexes, and EXPLAIN (ANALYZE, BUFFERS) performance analysis. Run independently in PostgreSQL 14+.



### Daily SQL Practice — 2026-11-17: EV Charging Network Operations

- [EV Charging Network: Session Billing, Charger Reliability & Roaming Settlement](daily/2026-11-17-ev-charging-session-billing-reliability.sql) — ten PostgreSQL exercises covering replay-safe session canonicalization, corrected cumulative meter readings, effective-dated tariff lookup, energy and idle-fee rating, charger downtime and availability, hourly connector utilization, roaming CDR reconciliation, concurrent site-load estimation, operational/tariff data-quality exceptions, and payment settlement reconciliation.
- Includes an isolated synthetic EV charging schema with duplicate deliveries, a corrected session and meter reading, a voided session, an orphan meter observation, overlapping tariff windows, charger outages, roaming discrepancies, and payment exceptions. Solutions explain deterministic window-based deduplication, DISTINCT ON, LATERAL as-of lookups, NUMERIC billing, range_agg/multiranges, GiST range indexing, running-sum event sweeps, and EXPLAIN (ANALYZE, BUFFERS) guidance. Run independently in PostgreSQL 14+.

### Daily SQL Practice — 2026-11-17: Public Transit GTFS Service Reliability

- [Public Transit GTFS, AVL & APC: Service Reliability and Headway Analytics](daily/2026-11-17-public-transit-gtfs-service-reliability.sql) — ten PostgreSQL exercises covering versioned AVL/APC event canonicalization, route on-time performance, headway bunching and gaps, missed timepoints, dwell/running-time outliers, passenger-load reconstruction, route reliability percentiles, telemetry coverage, APC quality exceptions, and vehicle-block recovery.
- Includes an isolated synthetic transit schema with replayed/corrected/voided telemetry, a missing stop arrival, an orphan trip, an impossible dwell interval, and passenger-count exceptions. Solutions explain window functions, schedule-spine LEFT JOINs, event canonicalization, ordered-set aggregates, and index/partition trade-offs. Run independently in PostgreSQL 14+.


### Daily SQL Practice — 2026-11-23: Payment Settlement Reconciliation

- [Payment Settlement Reconciliation & Allocation](daily/2026-11-23-payment-settlement-reconciliation.sql) — eight PostgreSQL exercises covering header/detail controls, missing bank/payment events, capture/refund variance, partial settlement, duplicate references, and currency-aware reconciliation.
- Includes isolated sample tables, commented reference solutions, index candidates, idempotent batch-watermark guidance, and expected spot checks. Run independently in PostgreSQL 14+.

### Daily SQL Practice — 2026-11-23: SIEM Security Incident Correlation

- [Defensive SIEM Event Correlation, Threat Intelligence & Incident SLAs](daily/2026-11-23-siem-security-incident-correlation.sql) — eleven PostgreSQL exercises covering replay-safe event canonicalization, point-in-time asset ownership, ten-minute authentication velocity, failed-login-to-success correlation, effective-dated CIDR threat-intelligence matching, idempotent alert upserts, alert-to-incident sessionization, severity-based MTTA/MTTR SLAs, ingestion-lag percentiles, JSONB/asset data-quality exceptions, and overlapping indicator-window detection.
- Includes an isolated synthetic SIEM schema with corrected and replayed events, a winning tombstone, late telemetry, an orphan asset, malformed payloads, effective-dated asset ownership, overlapping/expired threat indicators, and incident response cases. Commented reference solutions explain window frames, LATERAL lookups, CIDR containment, ON CONFLICT idempotency, sessionization, indexing trade-offs, and EXPLAIN (ANALYZE, BUFFERS) performance analysis. Run independently in PostgreSQL 14+; execute Q6 before Q7.

### Daily SQL Practice — 2026-11-25: Construction Project Controls & Earned Value

- [Construction Project Controls: Earned Value, Change Orders & Schedule Risk](daily/2026-11-25-construction-project-controls-earned-value.sql) — ten PostgreSQL exercises covering corrected progress-event canonicalization, approved baseline/BAC reconstruction, time-phased PV and earned-value metrics (EV, AC, CPI, SPI), EAC/ETC/VAC forecasting, change-order exposure and aging, PO/invoice/actual-cost reconciliation, dependency-cycle detection, schedule variance, monthly cash-flow outlook, and a consolidated controls exception register.
- Includes an isolated synthetic construction schema with two capital projects, versioned baselines, corrected and voided progress events, approved/pending/rejected change orders, purchase commitments, supplier invoices, posted/pending costs, and intentionally malformed schedule dependencies. Reference solutions explain tombstone-safe deduplication, grain-safe pre-aggregation, recursive graph validation, date-prorated planned value, partial indexes, and EXPLAIN (ANALYZE, BUFFERS) performance analysis. Run independently in PostgreSQL 14+.


### Daily SQL Practice — 2026-11-25: Data Center Capacity & Carbon-Aware Scheduling

- [Data Center Capacity Planning, Energy Observability & Carbon-Aware Scheduling](daily/2026-11-25-data-center-capacity-carbon-aware-scheduling.sql) — ten PostgreSQL exercises covering replay-safe rack telemetry canonicalization, latest rack utilization and headroom, sustained overload detection, hourly IT/facility energy reconstruction, workload carbon estimates, low-carbon scheduling candidates, rack admission-control checks, workload runtime percentiles, energy anomaly detection, and site-meter reconciliation.
- Includes an isolated synthetic data-center schema with multiple sites/grid zones, rack capacity, queued/running workloads, replayed and corrected telemetry, a tombstone, site meter intervals, and carbon-intensity forecasts. Solutions explain revision-aware deduplication, window functions, grain-safe pre-aggregation, forecast version selection, partial/composite indexes, and EXPLAIN (ANALYZE, BUFFERS) performance analysis. Run independently in PostgreSQL 14+.


### Daily SQL Practice — 2026-11-26: Subscription Coverage Gaps & Overlaps

- [Subscription Coverage Gaps, Overlaps & Point-in-Time Status](daily/2026-11-26-subscription-coverage-gaps-and-overlaps.sql) — PostgreSQL exercises for effective-dated subscription history. Covers half-open interval semantics, adjacent periods, gaps, nested overlaps, point-in-time plan lookup, active-period ambiguity, narrow window projections, and index/constraint strategies.
- Includes isolated sample data with intentional gap/overlap cases, seven interview follow-ups, and guidance on why a running maximum of prior end dates detects nested overlaps that a simple LAG can miss.

Run independently in PostgreSQL 14+. The setup creates its own subscription_periods table.


### Daily SQL Practice — 2026-11-27: Public Procurement Tender Evaluation & Contract Controls

- [Public Procurement: Tender Evaluation, Contract Controls & Vendor Performance](daily/2026-11-27-public-procurement-tender-evaluation-contract-controls.sql) — ten PostgreSQL exercises covering revision-aware bid canonicalization, tender responsiveness, weighted technical/price scoring, deterministic award ranking, point-in-time vendor registration, approved/pending change-order exposure, PO/receipt/invoice three-way matching, milestone schedule variance, supplier spend concentration, and procurement/payment control exceptions.
- Includes an isolated synthetic procurement schema with replayed, corrected, and tombstoned bids; vendor registration history; tenders and contracts; change orders; purchase orders, receipts and invoices; milestone and payment data. Solutions explain tombstone-safe window deduplication, EXISTS-based eligibility, window scoring/ranking, grain-safe pre-aggregation, partial/composite indexes, and EXPLAIN (ANALYZE, BUFFERS) performance analysis. Run independently in PostgreSQL 14+.
