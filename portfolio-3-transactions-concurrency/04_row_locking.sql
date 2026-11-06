-- MIVA Teaching Hospital - row-level locking in the pharmacy and the lab
--
-- Automated run (writes evidence/4a_*.txt to 4c_*.txt):
--   ./portfolio-3-transactions-concurrency/run_concurrency_demos.sh 4a 4b 4c
--
-- Manual run in DBeaver: two editors, Manual Commit, run A's steps up to the
-- pg_sleep, then B's steps, then finish A. See README.md for screenshots.
--
--   4a SELECT ... FOR UPDATE: two pharmacists, one pack of insulin left
--   4b FOR UPDATE NOWAIT:     the second pharmacist is told immediately
--   4c FOR UPDATE SKIP LOCKED: two lab technicians take different orders

-- @4a-A
\echo '[A] setup: only one pack of insulin glargine left'
UPDATE medication SET stock_quantity = 1 WHERE name = 'Insulin glargine 100IU/ml';
\echo '[A] pharmacist A locks the stock row, checks it, and dispenses'
BEGIN;
SELECT medication_id, name, stock_quantity AS a_sees,
       to_char(clock_timestamp(), 'HH24:MI:SS.MS') AS at
FROM medication WHERE name = 'Insulin glargine 100IU/ml'
FOR UPDATE;
SELECT pg_sleep(2);
UPDATE medication SET stock_quantity = stock_quantity - 1
WHERE name = 'Insulin glargine 100IU/ml' AND stock_quantity >= 1
RETURNING stock_quantity AS left_after_a, to_char(clock_timestamp(), 'HH24:MI:SS.MS') AS at;
INSERT INTO audit_log (table_name, row_id, action, new_data)
SELECT 'medication', medication_id, 'dispense', jsonb_build_object('quantity', 1, 'by', 'pharmacist A')
FROM medication WHERE name = 'Insulin glargine 100IU/ml';
COMMIT;
SELECT to_char(clock_timestamp(), 'HH24:MI:SS.MS') AS at, 'A committed' AS event;

-- @4a-B
\echo '[B] pharmacist B tries to lock the same row 0.5 s later'
BEGIN;
SELECT to_char(clock_timestamp(), 'HH24:MI:SS.MS') AS b_requests_lock;
-- Blocks here until A commits, then sees A's committed value (0)
SELECT medication_id, name, stock_quantity AS b_sees
FROM medication WHERE name = 'Insulin glargine 100IU/ml'
FOR UPDATE;
SELECT to_char(clock_timestamp(), 'HH24:MI:SS.MS') AS b_got_lock;
-- The guarded update dispenses nothing: UPDATE 0 means "out of stock"
UPDATE medication SET stock_quantity = stock_quantity - 1
WHERE name = 'Insulin glargine 100IU/ml' AND stock_quantity >= 1
RETURNING stock_quantity AS left_after_b;
COMMIT;
\echo '[B] reset stock to the seed value'
UPDATE medication SET stock_quantity = 30 WHERE name = 'Insulin glargine 100IU/ml';
DELETE FROM audit_log WHERE action = 'dispense' AND new_data ->> 'by' = 'pharmacist A';

-- @4b-A
\echo '[A] pharmacist A locks the salbutamol row and holds it for 2 s'
BEGIN;
SELECT medication_id, name, stock_quantity, to_char(clock_timestamp(), 'HH24:MI:SS.MS') AS at
FROM medication WHERE name = 'Salbutamol inhaler 100mcg'
FOR UPDATE;
SELECT pg_sleep(2);
COMMIT;

-- @4b-B
\echo '[B] pharmacist B asks for the same row with NOWAIT: fails at once instead of queueing'
BEGIN;
SELECT to_char(clock_timestamp(), 'HH24:MI:SS.MS') AS b_requests_lock;
SELECT medication_id, name, stock_quantity
FROM medication WHERE name = 'Salbutamol inhaler 100mcg'
FOR UPDATE NOWAIT;
ROLLBACK;
SELECT to_char(clock_timestamp(), 'HH24:MI:SS.MS') AS b_told_at;

-- @4c-A
\echo '[A] lab technician A claims the oldest pending lab order'
BEGIN;
SELECT lab_order_id, ordered_at, to_char(clock_timestamp(), 'HH24:MI:SS.MS') AS a_claimed_at
FROM lab_order
WHERE status = 'pending'
ORDER BY ordered_at
LIMIT 1
FOR UPDATE SKIP LOCKED;
SELECT pg_sleep(2);
ROLLBACK;

-- @4c-B
\echo '[B] lab technician B claims "the oldest pending order" 0.5 s later: gets the NEXT one, without waiting'
BEGIN;
SELECT lab_order_id, ordered_at, to_char(clock_timestamp(), 'HH24:MI:SS.MS') AS b_claimed_at
FROM lab_order
WHERE status = 'pending'
ORDER BY ordered_at
LIMIT 1
FOR UPDATE SKIP LOCKED;
ROLLBACK;
