# Portfolio 3 - Transactions and Concurrency

ACID transactions, isolation levels, deadlocks and row locking on the **MIVA Teaching Hospital** database (PostgreSQL 16). Every two-session scenario was run for real, as two concurrent connections, and its output saved in `evidence/`.

## Files

| File | What it shows |
|---|---|
| `01_commit_rollback.sql` | A payment that COMMITs, a dispense that fails a CHECK and is rolled back, a SAVEPOINT that keeps the good half of a transaction, and an overpayment that rolls back the whole transaction |
| `02_isolation_levels.sql` | Five two-session scenarios across READ COMMITTED, REPEATABLE READ and SERIALIZABLE |
| `02_isolation_levels.md` | Step-by-step Session A / Session B walkthrough for DBeaver |
| `03_deadlock.sql` | Two sessions locking patients 1 and 2 in opposite order, and the lock-ordering fix |
| `04_row_locking.sql` | `FOR UPDATE` on the last pack of insulin, `NOWAIT`, and `SKIP LOCKED` as a lab work queue |
| `05_discharge_procedure.sql` | `discharge_patient()` PL/pgSQL procedure with audit logging |
| `run_concurrency_demos.sh` | Runs each scenario's Session A and Session B blocks as two concurrent connections |
| `evidence/` | Output of every run |
| `screenshots/` | DBeaver screenshots of the manual two-tab runs |

## Results

### Atomicity: commit and rollback (`01_commit_rollback.sql`)

| Scenario | Result |
|---|---|
| Full payment | Payment, invoice status change (by trigger) and audit row all committed together |
| Dispense 10 Tramadol with 3 in stock | `CHECK (stock_quantity >= 0)` fails, the audit row written earlier in the same transaction is rolled back too, and stock stays at 3 |
| SAVEPOINT | A negative lab charge fails, `ROLLBACK TO SAVEPOINT` keeps the consultation line, and the invoice commits with a total of 16,000 |
| Overpayment | The second payment trips the `apply_payment` trigger. `COMMIT` on the aborted transaction becomes `ROLLBACK`, so the first payment is undone too |

### Isolation (`02_isolation_levels.sql`, walkthrough in `02_isolation_levels.md`)

| Scenario | Anomaly tested | Observed |
|---|---|---|
| 2a READ COMMITTED | dirty read / non-repeatable read | B never saw A's uncommitted phone (no dirty read), but saw the new phone later in the same transaction (non-repeatable read) |
| 2b REPEATABLE READ | non-repeatable read / lost update | B saw the old phone both times. B's update of the changed row failed with `could not serialize access due to concurrent update` |
| 2c SERIALIZABLE | two nurses, one free bed | Both saw bed 1 free. B got SQLSTATE 40001 "Canceled on identification as a pivot", and the retry took bed 2 |
| 2d READ COMMITTED | write skew | A one-booking clinic ended with **2 bookings** |
| 2e SERIALIZABLE | write skew | B's `COMMIT` was refused, and the clinic has **1 booking** |

### Deadlock (`03_deadlock.sql`)

A locked patient 1 and then requested patient 2. B locked patient 2 and then requested patient 1. After `deadlock_timeout` (1 s), PostgreSQL reported:

```
ERROR:  deadlock detected
DETAIL: Process 3191 waits for ShareLock on transaction 1079; blocked by process 3205.
```

PostgreSQL does not pick a victim by age. The backend whose deadlock check finds the cycle cancels its own transaction, and that is the one that started waiting first. In this run that was Session A (the older transaction), and Session B then completed. The fix (scenario 3b) is to lock every needed row up front in a fixed order (`ORDER BY patient_id FOR UPDATE`). B then simply waits about 0.5 s for A, and no deadlock occurs.

### Row locking (`04_row_locking.sql`)

| Scenario | Observed |
|---|---|
| 4a `FOR UPDATE`, one pack left | B requested the lock at 00:48:46.729 and got it at 00:48:48.111, right after A committed. B then saw stock 0, and its guarded `UPDATE ... WHERE stock_quantity >= 1` updated 0 rows, so nothing was double-dispensed |
| 4b `FOR UPDATE NOWAIT` | B failed immediately with `could not obtain lock on row in relation "medication"` instead of queueing |
| 4c `FOR UPDATE SKIP LOCKED` | Two lab technicians asking for "the oldest pending order" got two different orders (12544 and 72647) without waiting: a safe work queue |

### Stored procedure (`05_discharge_procedure.sql`)

`discharge_patient(p_admission_id)` locks the admission row, refuses with a clear error if the admission is missing or already discharged, sets `discharged_at`, and writes an `audit_log` row with the before and after images (`old_data` / `new_data` as JSONB). The demo shows a successful discharge, both refusal cases, and a discharge inside a caller transaction that is rolled back, which leaves no discharge and no audit row.

## How to run

With the Docker stack running and Portfolios 1 and 2 loaded:

```bash
# Single-session scripts
docker exec -i hospital_pg psql -U hospital_admin -d hospital_db -X -e -f /workspace/portfolio-3-transactions-concurrency/01_commit_rollback.sql
docker exec -i hospital_pg psql -U hospital_admin -d hospital_db -X -e -f /workspace/portfolio-3-transactions-concurrency/05_discharge_procedure.sql

# All two-session scenarios (about 30 s), output in evidence/
./portfolio-3-transactions-concurrency/run_concurrency_demos.sh

# Or a single scenario
./portfolio-3-transactions-concurrency/run_concurrency_demos.sh 3a
```

Every scenario cleans up after itself: phone numbers, bed admissions, demo appointments and stock levels are restored.

## Screenshots (manual DBeaver runs)

- `screenshots/01_isolation_read_committed.png`
- `screenshots/02_isolation_repeatable_read.png`
- `screenshots/03_isolation_serializable.png`
- `screenshots/04_deadlock.png`
- `screenshots/05_row_lock_blocking.png`
- `screenshots/06_row_lock_released.png`
