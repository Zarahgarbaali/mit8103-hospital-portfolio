-- Measure what indexes cost on the write side.
-- Inserts 50,000 appointments twice, once with the appointment indexes and
-- once with them dropped. Both runs are rolled back, so nothing is changed.
--   docker exec -i hospital_pg psql -U hospital_admin -d hospital_db \
--     -f /workspace/portfolio-2-query-optimisation/write_cost_test.sql

\timing on

\echo '--- A. Insert 50,000 appointments WITH idx_appointment_patient, idx_appointment_doctor_date, idx_appointment_scheduled_for'
BEGIN;
INSERT INTO appointment (patient_id, doctor_id, scheduled_for, status, reason)
SELECT 1 + g % 50, 1 + g % 6, now() + (g % 500) * interval '1 hour', 'booked', 'Write cost test'
FROM generate_series(1, 50000) AS g;
ROLLBACK;

\echo '--- B. Same insert WITHOUT the three secondary indexes'
BEGIN;
DROP INDEX idx_appointment_patient, idx_appointment_doctor_date, idx_appointment_scheduled_for;
INSERT INTO appointment (patient_id, doctor_id, scheduled_for, status, reason)
SELECT 1 + g % 50, 1 + g % 6, now() + (g % 500) * interval '1 hour', 'booked', 'Write cost test'
FROM generate_series(1, 50000) AS g;
ROLLBACK;

\echo '--- C. Disk used by appointment: table vs its indexes'
SELECT pg_size_pretty(pg_relation_size('appointment'))       AS table_size,
       pg_size_pretty(pg_indexes_size('appointment'))        AS all_indexes_size,
       pg_size_pretty(pg_relation_size('idx_appointment_scheduled_for')) AS covering_index_size;
