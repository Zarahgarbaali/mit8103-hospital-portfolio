-- MIVA Teaching Hospital - deadlock and how to avoid it
--
-- Story: a records clerk (A) and a ward nurse (B) both update the files of
-- patients 1 and 2, e.g. while merging duplicate contact details. A works
-- 1 then 2, B works 2 then 1.
--
-- Automated run (writes evidence/3a_*.txt, 3b_*.txt):
--   ./portfolio-3-transactions-concurrency/run_concurrency_demos.sh 3a 3b
--
-- Manual run in DBeaver (two editors, Manual Commit):
--   A: BEGIN; UPDATE patient 1
--   B: BEGIN; UPDATE patient 2
--   A: UPDATE patient 2   -> A waits for B
--   B: UPDATE patient 1   -> about 1 s later one session gets "deadlock detected"
--
-- "SET address = address" changes nothing but still takes the row lock, so
-- the demo leaves the data untouched.

-- @3a-A
\echo '[A] lock patient 1, then patient 2'
BEGIN;
UPDATE patient SET address = address WHERE patient_id = 1
RETURNING patient_id, to_char(clock_timestamp(), 'HH24:MI:SS.MS') AS a_locked_at;
SELECT pg_sleep(1);
SELECT to_char(clock_timestamp(), 'HH24:MI:SS.MS') AS a_requests_patient_2;
UPDATE patient SET address = address WHERE patient_id = 2
RETURNING patient_id, to_char(clock_timestamp(), 'HH24:MI:SS.MS') AS a_locked_at;
COMMIT;
SELECT to_char(clock_timestamp(), 'HH24:MI:SS.MS') AS at, 'A finished' AS event;

-- @3a-B
\echo '[B] lock patient 2, then patient 1 (opposite order)'
BEGIN;
UPDATE patient SET address = address WHERE patient_id = 2
RETURNING patient_id, to_char(clock_timestamp(), 'HH24:MI:SS.MS') AS b_locked_at;
SELECT pg_sleep(1);
SELECT to_char(clock_timestamp(), 'HH24:MI:SS.MS') AS b_requests_patient_1;
UPDATE patient SET address = address WHERE patient_id = 1
RETURNING patient_id, to_char(clock_timestamp(), 'HH24:MI:SS.MS') AS b_locked_at;
COMMIT;
SELECT to_char(clock_timestamp(), 'HH24:MI:SS.MS') AS at, 'B finished' AS event;
SHOW deadlock_timeout;

-- @3b-A
\echo '[A] FIX: lock every row needed up front, in a fixed order (lowest patient_id first)'
BEGIN;
SELECT patient_id, to_char(clock_timestamp(), 'HH24:MI:SS.MS') AS a_locked_at
FROM patient WHERE patient_id IN (1, 2) ORDER BY patient_id FOR UPDATE;
SELECT pg_sleep(1);
UPDATE patient SET address = address WHERE patient_id = 1;
UPDATE patient SET address = address WHERE patient_id = 2;
COMMIT;
SELECT to_char(clock_timestamp(), 'HH24:MI:SS.MS') AS at, 'A finished' AS event;

-- @3b-B
\echo '[B] FIX: same lock order, even though B logically starts with patient 2'
BEGIN;
SELECT to_char(clock_timestamp(), 'HH24:MI:SS.MS') AS b_requests_locks;
SELECT patient_id, to_char(clock_timestamp(), 'HH24:MI:SS.MS') AS b_locked_at
FROM patient WHERE patient_id IN (1, 2) ORDER BY patient_id FOR UPDATE;
SELECT to_char(clock_timestamp(), 'HH24:MI:SS.MS') AS b_got_locks;
UPDATE patient SET address = address WHERE patient_id = 2;
UPDATE patient SET address = address WHERE patient_id = 1;
COMMIT;
SELECT to_char(clock_timestamp(), 'HH24:MI:SS.MS') AS at, 'B finished, no deadlock' AS event;
