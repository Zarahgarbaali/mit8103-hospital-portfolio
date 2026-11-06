# Performance Analysis - MIVA Teaching Hospital

## Test setup

- PostgreSQL 16.15 in Docker on a MacBook M1 (8 GB), default configuration (`shared_buffers = 128MB`).
- Data: the Portfolio 1 seed plus `bulk_load.sql`, which adds about two years of activity:

  | table | rows |
  |---|---|
  | appointment | 300,100 |
  | invoice_item | 345,575 |
  | invoice | 172,764 |
  | diagnosis | 172,774 |
  | prescription | 172,794 |
  | payment | 155,483 |
  | lab_order | 100,048 |
  | admission | 30,020 |
  | patient | 20,050 |

- **Before** = the Portfolio 1 schema with its foreign key indexes only. **After** = plus `indexes.sql`.
- `capture_plans.sh` runs each query once to warm the cache, then three times under `EXPLAIN (ANALYZE, BUFFERS)`. The table shows the median of the three runs. Full plans are in `execution_plans/before/` and `execution_plans/after/`.
- Cost is the planner's estimated total cost of the top plan node, in arbitrary planner units. Time is measured execution time.

## Results

| Query | Rows | Cost before | Cost after | Time before | Time after | Index used (after) |
|-------|------|-------------|------------|-------------|------------|--------------------|
| Q1 doctor's day list | 5 | 128 | 115 | 0.07 ms | 0.07 ms | `idx_appointment_doctor_date` (from P1) |
| **Q2** top 5 drugs, 30 days | 5 | 4,435 | **293** | 13.6 ms | **2.0 ms** | `idx_prescription_issued_at` (index-only) |
| **Q3** department revenue, this month | 4 | 12,570 | **6,406** | 16.1 ms | **9.2 ms** | `idx_invoice_issued_at` + `uq_invoice_item_consultation` (partial) |
| **Q4** frequent attenders, 6 months | 8,317 | 12,786 | **5,174** | 66.0 ms | **39.6 ms** | `idx_appointment_scheduled_for` (covering, index-only) |
| **Q5** pending lab orders > 24 h | 325 | 3,749 | **1,607** | 9.2 ms | **6.0 ms** | `idx_lab_order_pending` (partial) |
| Q6 ward occupancy | 4 | 14 | 14 | 0.08 ms | 0.11 ms | `uq_admission_open_patient` (partial, from P1) |
| **Q7** B54 + antimalarial audit | 5,820 | 5,367 | **4,392** | 31.6 ms | **27.4 ms** | `idx_diagnosis_icd_code` |
| Q8 time to diagnosis per doctor | 46 | 11,400 | 11,400 | 71.8 ms | 68.8 ms | none (full aggregate) |
| Q9 top 10 outstanding balances | 10 | 25,054 | 24,147 | 136.6 ms | 133.0 ms | `idx_invoice_open_balance` (partial) |
| **Q10** doctor rank per department | 46 | 7,551 | 7,555 | 38.7 ms | 40.2 ms | none (full aggregate) |
| Monthly revenue, live vs materialised view | 48 | - | - | 102.3 ms | **0.03 ms** | `mv_monthly_department_revenue` |

## What changed and why

**Range filters on time columns gave the biggest wins.** Before the new indexes, Q2 ran a parallel sequential scan over all 172k prescriptions and threw away 96% of them (`Rows Removed by Filter: 82852` per worker). `idx_prescription_issued_at` is a B-tree on `issued_at` that also INCLUDEs `medication_id`. With it, the planner reads only the last 30 days of index entries and answers from the index alone (an index-only scan), never visiting the table. That makes the query 6.7x faster. Q4 shows the same pattern. The covering index `appointment(scheduled_for) INCLUDE (patient_id, status)` turned a 300k-row sequential scan into an index-only scan with `Heap Fetches: 0`, and the remaining time is the hash join and aggregation over 65k qualifying rows.

**Partial indexes index only the rows a query asks for.** `idx_lab_order_pending` contains only rows `WHERE status = 'pending'`: about 500 of 100k lab orders, in a 32 kB index. A full index on `(status, ordered_at)` would also hold the 99k completed orders that no query looks up this way. Q5's sequential scan of lab_order became an index range scan. Q6 shows that partial indexes can also enforce rules. `uq_admission_open_bed` and `uq_admission_open_patient` from Portfolio 1 already exist as partial unique indexes `WHERE discharged_at IS NULL` (16 kB each), and the baseline plan uses one of them. The suggested extra `admission(ward_id) WHERE discharged_at IS NULL` index would duplicate them, so it was not created.

**An index can make a plan worse until the right companion index exists.** After adding only `idx_invoice_issued_at`, Q3 went from 16 ms to about 19 ms. The planner used the new index to find the month's 1,428 invoices, but then switched to a parallel hash join that scanned all 172k consultation lines in `invoice_item`. Adding `uq_invoice_item_consultation`, a partial unique index on `invoice_item(invoice_id) INCLUDE (reference_id) WHERE item_type = 'consultation'`, gave the planner a cheap path from each invoice to its consultation, and Q3 dropped to 9 ms. The same index also enforces the billing rule "one consultation line per invoice", which is what makes the revenue figures safe from double counting.

**Some queries cannot be fixed with an index.** Q8 and Q10 aggregate every diagnosis or every completed appointment, so most of the table has to be read whatever indexes exist. A test partial index `appointment(doctor_id) WHERE status = 'completed'` was used by Q10 (index-only scan, estimated cost down from 7,551 to 5,478), but the measured time did not change (38 ms either way), because the time goes into the joins and aggregation, not the scan. It was not kept. Q9 is similar: `idx_invoice_open_balance` cut its invoice scan from 16 ms to 6 ms, but 61 ms of the 133 ms is spent aggregating all 155k payments. A `LATERAL` rewrite that sums payments only for the open invoices was tested and was slower (153 ms, partly JIT compilation overhead). The real fix for Q9 would be a design change: store `amount_paid` on `invoice` and maintain it in the existing `apply_payment` trigger. For whole-table reporting like Q8, Q10 and monthly revenue, the right tool is a materialised view. `mv_monthly_department_revenue` answers in 0.03 ms instead of 102 ms (`evidence/materialized_view_demo.txt`), and the demo cross-checks that its total matches the live query exactly.

**Estimated cost and measured time do not always move together.** Q7's cost fell 18%, but its time varied between 26 and 43 ms across runs. The planner also underestimates Q7's result (192 rows estimated, 5,821 actual), because it assumes the diagnosis code and the medication are independent, when in fact B54 is almost always treated with Artemether/Lumefantrine. PostgreSQL's extended statistics cannot capture a correlation that spans two tables, so this estimate stays wrong. The plan is still reasonable at this data size.

## Trade-offs

Indexes speed up reads but are not free:

- **Slower writes.** `write_cost_test.sql` inserts 50,000 appointments with and without the three secondary indexes on `appointment`. The insert took **864 ms with the indexes and 650 ms without, about 33% slower**, because every index has to be updated for every new row (`evidence/write_cost_test.txt`). Appointments are written all day by receptionists, so an index there must justify itself on the read side.
- **Disk and memory.** After the optimisation indexes, `appointment` has 31 MB of indexes for 27 MB of table. The covering index alone is 14 MB, because INCLUDE copies `patient_id` and `status` into every leaf entry. Indexes compete with table pages for the 128 MB buffer cache.
- **Maintenance.** Rolled-back inserts and updates leave dead entries in every index. After the write test, the appointment indexes had grown from 31 MB to 45 MB, and only a `REINDEX` returned them to 31 MB (`VACUUM` reclaims table space but does not shrink index files).
- **Staleness.** The materialised view is up to 24 hours stale between nightly refreshes. The live Q3 remains available for anyone who needs today's figure.

Each index in `indexes.sql` is therefore tied to a named query with a measured benefit. The two candidates without a measurable benefit (the Q10 partial index and the redundant admission index) were left out.
