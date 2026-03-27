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
