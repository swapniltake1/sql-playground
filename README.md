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
