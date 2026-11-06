-- MIVA Teaching Hospital - isolation levels with two concurrent sessions
--
-- Each scenario has a Session A block and a Session B block, marked with
-- "-- @<scenario>-A" and "-- @<scenario>-B". Session B starts 0.5 s after A.
-- The pg_sleep() calls fix the interleaving so the demo is repeatable.
--
-- Automated run (writes evidence/02*.txt):
--   ./portfolio-3-transactions-concurrency/run_concurrency_demos.sh
--
-- Manual run in DBeaver: open two SQL editors on hospital_db (Session A and
-- Session B), switch both to Manual Commit, and follow 02_isolation_levels.md.
-- You can skip the pg_sleep lines and simply run the steps in the order given.
--
-- Scenarios:
--   2a READ COMMITTED  - no dirty reads, but a non-repeatable read
--   2b REPEATABLE READ - stable snapshot, and a lost update is refused
--   2c SERIALIZABLE    - two nurses admitting into the same free bed
--   2d READ COMMITTED  - write skew: a one-booking clinic gets two bookings
--   2e SERIALIZABLE    - the same write skew is detected and refused
--
-- Patient 1 seed phone is +2348010104729; each scenario restores it.

-- @2a-A
\echo '[A] READ COMMITTED: change patient 1 phone and keep the transaction open'
BEGIN ISOLATION LEVEL READ COMMITTED;
UPDATE patient SET phone = '+2348099999999' WHERE patient_id = 1;
SELECT to_char(clock_timestamp(), 'HH24:MI:SS.MS') AS at, phone AS a_sees_own_change
FROM patient WHERE patient_id = 1;
SELECT pg_sleep(2);
COMMIT;
SELECT to_char(clock_timestamp(), 'HH24:MI:SS.MS') AS at, 'A committed' AS event;

-- @2a-B
\echo '[B] READ COMMITTED: read the same row twice inside one transaction'
BEGIN ISOLATION LEVEL READ COMMITTED;
-- A has not committed yet: B must NOT see the new phone (no dirty read)
SELECT to_char(clock_timestamp(), 'HH24:MI:SS.MS') AS at, phone AS b_first_read
FROM patient WHERE patient_id = 1;
SELECT pg_sleep(2.5);
-- A has committed: each statement takes a new snapshot, so B now sees the
-- new phone inside the same transaction (non-repeatable read)
SELECT to_char(clock_timestamp(), 'HH24:MI:SS.MS') AS at, phone AS b_second_read
FROM patient WHERE patient_id = 1;
COMMIT;
UPDATE patient SET phone = '+2348010104729' WHERE patient_id = 1;

-- @2b-A
\echo '[A] change patient 1 phone and commit after 2 s'
BEGIN ISOLATION LEVEL READ COMMITTED;
UPDATE patient SET phone = '+2348099999999' WHERE patient_id = 1;
SELECT pg_sleep(2);
COMMIT;
SELECT to_char(clock_timestamp(), 'HH24:MI:SS.MS') AS at, 'A committed' AS event;

-- @2b-B
\echo '[B] REPEATABLE READ: the snapshot is fixed at the first query'
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT to_char(clock_timestamp(), 'HH24:MI:SS.MS') AS at, phone AS b_first_read
FROM patient WHERE patient_id = 1;
SELECT pg_sleep(2.5);
-- A has committed, but B still sees its original snapshot (repeatable read)
SELECT to_char(clock_timestamp(), 'HH24:MI:SS.MS') AS at, phone AS b_second_read
FROM patient WHERE patient_id = 1;
-- B tries to update a row that changed after its snapshot: refused instead
-- of silently overwriting A's work (lost update prevention)
UPDATE patient SET address = 'Plot 14, Garki, Abuja' WHERE patient_id = 1;
ROLLBACK;
-- A new transaction sees A's committed change
SELECT to_char(clock_timestamp(), 'HH24:MI:SS.MS') AS at, phone AS b_after_new_transaction
FROM patient WHERE patient_id = 1;
UPDATE patient SET phone = '+2348010104729' WHERE patient_id = 1;

-- @2c-A
\echo '[A] SERIALIZABLE: nurse A finds the first free bed in the Children''s Ward and admits patient 45'
BEGIN ISOLATION LEVEL SERIALIZABLE;
SELECT to_char(clock_timestamp(), 'HH24:MI:SS.MS') AS at, min(b) AS a_first_free_bed
FROM generate_series(1, (SELECT total_beds FROM ward WHERE ward_id = 2)) AS b
WHERE b NOT IN (SELECT bed_number FROM admission WHERE ward_id = 2 AND discharged_at IS NULL);
SELECT pg_sleep(1);
INSERT INTO admission (patient_id, ward_id, bed_number)
SELECT 45, 2, min(b)
FROM generate_series(1, (SELECT total_beds FROM ward WHERE ward_id = 2)) AS b
WHERE b NOT IN (SELECT bed_number FROM admission WHERE ward_id = 2 AND discharged_at IS NULL)
RETURNING admission_id, patient_id, bed_number, to_char(clock_timestamp(), 'HH24:MI:SS.MS') AS at;
SELECT pg_sleep(1);
COMMIT;
SELECT to_char(clock_timestamp(), 'HH24:MI:SS.MS') AS at, 'A committed' AS event;

-- @2c-B
\echo '[B] SERIALIZABLE: nurse B looks at the same ward at the same moment and admits patient 46'
BEGIN ISOLATION LEVEL SERIALIZABLE;
SELECT to_char(clock_timestamp(), 'HH24:MI:SS.MS') AS at, min(b) AS b_first_free_bed
FROM generate_series(1, (SELECT total_beds FROM ward WHERE ward_id = 2)) AS b
WHERE b NOT IN (SELECT bed_number FROM admission WHERE ward_id = 2 AND discharged_at IS NULL);
SELECT pg_sleep(1);
-- Same bed as A. B waits for A's uncommitted row, then fails when A commits.
INSERT INTO admission (patient_id, ward_id, bed_number)
SELECT 46, 2, min(b)
FROM generate_series(1, (SELECT total_beds FROM ward WHERE ward_id = 2)) AS b
WHERE b NOT IN (SELECT bed_number FROM admission WHERE ward_id = 2 AND discharged_at IS NULL)
RETURNING admission_id, patient_id, bed_number;
ROLLBACK;
\echo '[B] retry: the application re-runs the whole transaction and gets the next bed'
BEGIN ISOLATION LEVEL SERIALIZABLE;
INSERT INTO admission (patient_id, ward_id, bed_number)
SELECT 46, 2, min(b)
FROM generate_series(1, (SELECT total_beds FROM ward WHERE ward_id = 2)) AS b
WHERE b NOT IN (SELECT bed_number FROM admission WHERE ward_id = 2 AND discharged_at IS NULL)
RETURNING admission_id, patient_id, bed_number, to_char(clock_timestamp(), 'HH24:MI:SS.MS') AS at;
COMMIT;
SELECT patient_id, ward_id, bed_number FROM admission
WHERE patient_id IN (45, 46) AND discharged_at IS NULL ORDER BY patient_id;
DELETE FROM admission WHERE patient_id IN (45, 46) AND discharged_at IS NULL;

-- @2d-A
\echo '[A] READ COMMITTED: Dr. Okafor''s emergency clinic in 60 days takes ONE booking. Receptionist A checks, then books patient 45'
BEGIN ISOLATION LEVEL READ COMMITTED;
SELECT to_char(clock_timestamp(), 'HH24:MI:SS.MS') AS at, count(*) AS a_sees_booked
FROM appointment
WHERE doctor_id = 1 AND scheduled_for >= current_date + 60 AND scheduled_for < current_date + 61;
SELECT pg_sleep(1);
INSERT INTO appointment (patient_id, doctor_id, scheduled_for, reason)
SELECT 45, 1, current_date + 60 + time '09:00', 'Isolation demo: emergency clinic'
WHERE (SELECT count(*) FROM appointment
       WHERE doctor_id = 1 AND scheduled_for >= current_date + 60 AND scheduled_for < current_date + 61) < 1
RETURNING appointment_id, patient_id, to_char(clock_timestamp(), 'HH24:MI:SS.MS') AS at;
SELECT pg_sleep(1);
COMMIT;
SELECT to_char(clock_timestamp(), 'HH24:MI:SS.MS') AS at, 'A committed' AS event;

-- @2d-B
\echo '[B] READ COMMITTED: receptionist B checks the same clinic, then books patient 46'
BEGIN ISOLATION LEVEL READ COMMITTED;
SELECT to_char(clock_timestamp(), 'HH24:MI:SS.MS') AS at, count(*) AS b_sees_booked
FROM appointment
WHERE doctor_id = 1 AND scheduled_for >= current_date + 60 AND scheduled_for < current_date + 61;
SELECT pg_sleep(1);
-- A's booking is not committed yet, so B's check also sees 0 and B books too
INSERT INTO appointment (patient_id, doctor_id, scheduled_for, reason)
SELECT 46, 1, current_date + 60 + time '09:15', 'Isolation demo: emergency clinic'
WHERE (SELECT count(*) FROM appointment
       WHERE doctor_id = 1 AND scheduled_for >= current_date + 60 AND scheduled_for < current_date + 61) < 1
RETURNING appointment_id, patient_id, to_char(clock_timestamp(), 'HH24:MI:SS.MS') AS at;
SELECT pg_sleep(1);
COMMIT;
SELECT pg_sleep(0.5);
\echo '[B] result: the one-booking clinic now has two bookings (write skew)'
SELECT count(*) AS bookings_for_clinic
FROM appointment
WHERE doctor_id = 1 AND scheduled_for >= current_date + 60 AND scheduled_for < current_date + 61;
DELETE FROM appointment WHERE reason = 'Isolation demo: emergency clinic';

-- @2e-A
\echo '[A] SERIALIZABLE: same clinic, same check-then-book logic, patient 45'
BEGIN ISOLATION LEVEL SERIALIZABLE;
SELECT to_char(clock_timestamp(), 'HH24:MI:SS.MS') AS at, count(*) AS a_sees_booked
FROM appointment
WHERE doctor_id = 1 AND scheduled_for >= current_date + 60 AND scheduled_for < current_date + 61;
SELECT pg_sleep(1);
INSERT INTO appointment (patient_id, doctor_id, scheduled_for, reason)
SELECT 45, 1, current_date + 60 + time '09:00', 'Isolation demo: emergency clinic'
WHERE (SELECT count(*) FROM appointment
       WHERE doctor_id = 1 AND scheduled_for >= current_date + 60 AND scheduled_for < current_date + 61) < 1
RETURNING appointment_id, patient_id, to_char(clock_timestamp(), 'HH24:MI:SS.MS') AS at;
SELECT pg_sleep(1);
COMMIT;
SELECT to_char(clock_timestamp(), 'HH24:MI:SS.MS') AS at, 'A committed' AS event;

-- @2e-B
\echo '[B] SERIALIZABLE: receptionist B, patient 46'
BEGIN ISOLATION LEVEL SERIALIZABLE;
SELECT to_char(clock_timestamp(), 'HH24:MI:SS.MS') AS at, count(*) AS b_sees_booked
FROM appointment
WHERE doctor_id = 1 AND scheduled_for >= current_date + 60 AND scheduled_for < current_date + 61;
SELECT pg_sleep(1);
INSERT INTO appointment (patient_id, doctor_id, scheduled_for, reason)
SELECT 46, 1, current_date + 60 + time '09:15', 'Isolation demo: emergency clinic'
WHERE (SELECT count(*) FROM appointment
       WHERE doctor_id = 1 AND scheduled_for >= current_date + 60 AND scheduled_for < current_date + 61) < 1
RETURNING appointment_id, patient_id, to_char(clock_timestamp(), 'HH24:MI:SS.MS') AS at;
SELECT pg_sleep(1);
-- A committed first; PostgreSQL's serializable snapshot isolation detects the
-- read/write dependency cycle and refuses B
COMMIT;
SELECT pg_sleep(0.5);
\echo '[B] result: the clinic has exactly one booking'
SELECT count(*) AS bookings_for_clinic
FROM appointment
WHERE doctor_id = 1 AND scheduled_for >= current_date + 60 AND scheduled_for < current_date + 61;
DELETE FROM appointment WHERE reason = 'Isolation demo: emergency clinic';
