# Isolation Levels - Session A / Session B Walkthrough

These walkthroughs run the scenarios in `02_isolation_levels.sql` by hand in two DBeaver editors. The automated version (`run_concurrency_demos.sh`) runs the same blocks with fixed timing and saves the output to `evidence/2a_*.txt` to `evidence/2e_*.txt`.

## Setup in DBeaver

1. Right-click the `hospital_db` connection and choose **SQL Editor > New SQL script**. Do this twice and name the tabs **Session A** and **Session B**. Each editor is a separate database connection (DBeaver's default "separate connection per editor").
2. Leave **both** tabs in **Auto-Commit** mode and start every transaction with an explicit `BEGIN` (or `BEGIN ISOLATION LEVEL ...`). The transaction then stays open until you run `COMMIT` or `ROLLBACK`. Do not switch to Manual Commit: DBeaver then opens its own transaction first, so `BEGIN ISOLATION LEVEL ...` only raises "there is already a transaction in progress" and the session stays at READ COMMITTED.
3. Arrange the tabs side by side (drag one tab to the right edge) so both are visible in the screenshots.
4. Run one statement at a time with **Ctrl+Enter** (Cmd+Enter on Mac), with the cursor on the statement. Skip the `pg_sleep` lines; you control the timing yourself.

PostgreSQL's default level is READ COMMITTED. PostgreSQL never allows dirty reads, even at READ UNCOMMITTED, which it treats as READ COMMITTED.

## 2a. READ COMMITTED: no dirty read, but a non-repeatable read

| Step | Session A | Session B | What you should see |
|---|---|---|---|
| 1 | `BEGIN ISOLATION LEVEL READ COMMITTED;` | | |
| 2 | `UPDATE patient SET phone = '+2348099999999' WHERE patient_id = 1;` | | A has changed the row but not committed |
| 3 | | `BEGIN ISOLATION LEVEL READ COMMITTED;` | |
| 4 | | `SELECT phone FROM patient WHERE patient_id = 1;` | **+2348010104729** (old). B cannot see A's uncommitted change: **no dirty read** |
| 5 | *Screenshot 1* | *Screenshot 1* | |
| 6 | `COMMIT;` | | |
| 7 | | `SELECT phone FROM patient WHERE patient_id = 1;` | **+2348099999999** (new), inside the same B transaction: a **non-repeatable read** |
| 8 | | `COMMIT;` | *Screenshot 2* |
| 9 | | `UPDATE patient SET phone = '+2348010104729' WHERE patient_id = 1; COMMIT;` | reset |

**Why:** under READ COMMITTED, every statement takes a fresh snapshot of committed data. Uncommitted rows are never visible, but a later statement in the same transaction can see rows committed in between.

Save the screenshots as `screenshots/01_isolation_read_committed.png`. Two images side by side in one file is fine.

## 2b. REPEATABLE READ: stable snapshot, lost update refused

| Step | Session A | Session B | What you should see |
|---|---|---|---|
| 1 | | `BEGIN ISOLATION LEVEL REPEATABLE READ;` | |
| 2 | | `SELECT phone FROM patient WHERE patient_id = 1;` | old phone. **B's snapshot is taken now**, at its first query |
| 3 | `BEGIN; UPDATE patient SET phone = '+2348099999999' WHERE patient_id = 1; COMMIT;` | | A's change is committed |
| 4 | | `SELECT phone FROM patient WHERE patient_id = 1;` | still the **old** phone: the read is repeatable |
| 5 | | `UPDATE patient SET address = 'Plot 14, Garki, Abuja' WHERE patient_id = 1;` | `ERROR: could not serialize access due to concurrent update` |
| 6 | | `ROLLBACK;` | |
| 7 | | `SELECT phone FROM patient WHERE patient_id = 1;` | new phone (new transaction, new snapshot) |
| 8 | | reset the phone as in 2a | |

**Why:** REPEATABLE READ keeps one snapshot for the whole transaction. If B were allowed to update a row that changed after its snapshot, it would overwrite A's work without having seen it (a lost update). PostgreSQL refuses, and the application must retry.

Screenshot step 4 and step 5: `screenshots/02_isolation_repeatable_read.png`.

## 2c. SERIALIZABLE: two nurses, one free bed

The Children's Ward (ward 2) has 8 beds. Both nurses look for the first free bed at the same moment and try to admit a patient into it.

```sql
-- the "first free bed" query used by both sessions
SELECT min(b) AS first_free_bed
FROM generate_series(1, (SELECT total_beds FROM ward WHERE ward_id = 2)) AS b
WHERE b NOT IN (SELECT bed_number FROM admission WHERE ward_id = 2 AND discharged_at IS NULL);
```

| Step | Session A | Session B | What you should see |
|---|---|---|---|
| 1 | `BEGIN ISOLATION LEVEL SERIALIZABLE;` | `BEGIN ISOLATION LEVEL SERIALIZABLE;` | |
| 2 | run the first-free-bed query | run the first-free-bed query | both see bed **1** |
| 3 | `INSERT INTO admission (patient_id, ward_id, bed_number) VALUES (45, 2, 1);` | | succeeds |
| 4 | | `INSERT INTO admission (patient_id, ward_id, bed_number) VALUES (46, 2, 1);` | `ERROR: could not serialize access due to read/write dependencies among transactions` (SQLSTATE 40001), "The transaction might succeed if retried" |
| 5 | `COMMIT;` | `ROLLBACK;` | |
| 6 | | `BEGIN ISOLATION LEVEL SERIALIZABLE;`, re-run the query (now bed **2**), insert patient 46 into bed 2, `COMMIT;` | the retry succeeds |
| 7 | | `DELETE FROM admission WHERE patient_id IN (45, 46) AND discharged_at IS NULL; COMMIT;` | reset |

**Why:** both transactions read "which beds are free" and then wrote a decision based on it. PostgreSQL's Serializable Snapshot Isolation (SSI) tracks those read/write dependencies and refuses one of the transactions as soon as the pattern could produce a result that no serial order would. Under READ COMMITTED, B would instead wait on A's row and then fail with a `unique_violation` from the partial unique index `uq_admission_open_bed`. In both cases the bed is protected, but SERIALIZABLE reports it as a retryable error (40001), which an application can handle generically.

Screenshot step 4: `screenshots/03_isolation_serializable.png`.

## 2d / 2e. Write skew: why SERIALIZABLE matters when no constraint exists

Dr. Okafor runs a one-patient emergency clinic in 60 days' time. The "only one booking" rule lives in application logic (check the count, then book), not in a constraint.

- **2d (READ COMMITTED):** both receptionists check the count (0), both book. Result: **2 bookings**. Neither transaction saw the other's uncommitted insert, and no row was updated twice, so no lock or constraint stopped it. This anomaly is called **write skew**.
- **2e (SERIALIZABLE):** same steps. Session B's `COMMIT` fails with `could not serialize access due to read/write dependencies among transactions`. Result: **1 booking**.

To run it by hand, use the `2d` / `2e` blocks in `02_isolation_levels.sql`, executing the SELECT in both sessions before either INSERT.

This is the strongest argument for SERIALIZABLE on booking and bed-allocation transactions. For rules that span many rows, REPEATABLE READ is not enough, because the transactions write different rows.

## Results from the automated run

| Scenario | Level | Observed | Evidence |
|---|---|---|---|
| 2a | READ COMMITTED | B read the old phone while A was uncommitted, then the new phone in the same transaction | `evidence/2a_read_committed.txt` |
| 2b | REPEATABLE READ | B read the old phone twice, then got `could not serialize access due to concurrent update` | `evidence/2b_repeatable_read.txt` |
| 2c | SERIALIZABLE | Both saw bed 1. B got SQLSTATE 40001 "Canceled on identification as a pivot, during write". The retry took bed 2 | `evidence/2c_serializable_last_bed.txt` |
| 2d | READ COMMITTED | Clinic ended with **2** bookings | `evidence/2d_read_committed_write_skew.txt` |
| 2e | SERIALIZABLE | B's commit refused, clinic has **1** booking | `evidence/2e_serializable_write_skew.txt` |
