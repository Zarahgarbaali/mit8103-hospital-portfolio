# Portfolio 2 - Query Processing and Optimisation

Ten operational and reporting queries for **MIVA Teaching Hospital**. Each is measured with `EXPLAIN (ANALYZE, BUFFERS)` before and after targeted indexing, plus a materialised view for whole-table reporting.

## Files

| File | Purpose |
|---|---|
| `queries.sql` | The 10 queries, each with its business reason |
| `bulk_load.sql` | Adds about 2 years of activity (300k appointments, 170k invoices, ...) on top of the P1 seed so plans are realistic |
| `capture_plans.sh` | Runs every query under `EXPLAIN (ANALYZE, BUFFERS)`: one warm-up run, then 3 measured runs (median reported) |
| `execution_plans/before/` | Plans with only the Portfolio 1 foreign key indexes, plus `summary.txt` |
| `execution_plans/after/` | Plans after `indexes.sql`, plus `summary.txt` and `index_sizes.txt` |
| `indexes.sql` | Optimisation indexes: range, covering and partial |
| `materialized_view.sql` | `mv_monthly_department_revenue` and its refresh strategy |
| `materialized_view_demo.sql` | Live aggregate vs view, a cross-check, and a concurrent refresh |
| `write_cost_test.sql` | Measures the insert slowdown caused by indexes |
| `performance_analysis.md` | Results table and discussion |
| `evidence/` | Query results on the seed data, materialised view demo output, write cost output |
| `screenshots/` | DBeaver result grid and plan screenshots |

## The 10 queries

1. A doctor's appointments for one day, ordered by time
2. Top 5 most prescribed medications in the last 30 days
3. Each department's invoice revenue for the current month
4. Patients with more than 3 appointments in the last 6 months
5. Pending lab orders older than 24 hours, with the ordering doctor
6. Current ward occupancy (occupied vs total beds)
7. Patients diagnosed with B54 (malaria) and prescribed Artemether/Lumefantrine
8. Average time from appointment to diagnosis, per doctor
9. The 10 patients with the highest outstanding balance
10. Window function: `RANK()` of doctors by completed appointments within each department

## Headline results

| Query | Before | After | How |
|---|---|---|---|
| Q2 | 13.6 ms | 2.0 ms | Index-only scan on `prescription(issued_at) INCLUDE (medication_id)` |
| Q3 | 16.1 ms | 9.2 ms | `invoice(issued_at)` + partial unique `invoice_item(invoice_id) WHERE item_type = 'consultation'` |
| Q4 | 66.0 ms | 39.6 ms | Covering index, index-only scan with 0 heap fetches |
| Q5 | 9.2 ms | 6.0 ms | Partial index `lab_order(ordered_at) WHERE status = 'pending'` (32 kB) |
| Monthly revenue | 102 ms | 0.03 ms | Materialised view |

Q8, Q9 and Q10 aggregate most of a table and gain little from indexes. Why, and what would help instead, is discussed in `performance_analysis.md`, along with the write-side cost: inserts were 33% slower with the extra indexes.

## How to run

With the Docker stack running and Portfolio 1 loaded (`schema.sql`, `indexes.sql`, `seed.sql`):

```bash
# 1. Query results on the small seed (optional)
docker exec -i hospital_pg psql -U hospital_admin -d hospital_db -f /workspace/portfolio-2-query-optimisation/queries.sql

# 2. Realistic volumes (about 25 s)
docker exec -i hospital_pg psql -U hospital_admin -d hospital_db -v ON_ERROR_STOP=1 -f /workspace/portfolio-2-query-optimisation/bulk_load.sql

# 3. Baseline plans
./portfolio-2-query-optimisation/capture_plans.sh before

# 4. Indexes, then the plans again
docker exec -i hospital_pg psql -U hospital_admin -d hospital_db -v ON_ERROR_STOP=1 -f /workspace/portfolio-2-query-optimisation/indexes.sql
./portfolio-2-query-optimisation/capture_plans.sh after

# 5. Materialised view and write-cost test
docker exec -i hospital_pg psql -U hospital_admin -d hospital_db -f /workspace/portfolio-2-query-optimisation/materialized_view.sql
docker exec -i hospital_pg psql -U hospital_admin -d hospital_db -f /workspace/portfolio-2-query-optimisation/materialized_view_demo.sql
docker exec -i hospital_pg psql -U hospital_admin -d hospital_db -f /workspace/portfolio-2-query-optimisation/write_cost_test.sql
```

Timestamps in the data are generated relative to `now()`, so "last 30 days" and "this month" always return rows. Exact timings will differ from machine to machine, but the relative before/after differences should hold.

## Evidence

- `evidence/query_results_seed.txt` - output of all 10 queries on the 50-patient seed
- `execution_plans/before/*.txt`, `execution_plans/after/*.txt` - full plans with buffers and timings
- `evidence/materialized_view_demo.txt` - 102 ms live vs 0.03 ms from the view, totals cross-checked
- `evidence/write_cost_test.txt` - 864 ms vs 650 ms for 50k inserts
- `screenshots/01_query2_result.png` - Q2 result grid in DBeaver
- `screenshots/02_query4_plan.png` - Q4 `EXPLAIN ANALYZE` in DBeaver
