-- MIVA Teaching Hospital - constraint tests
--
-- Each block tries to break one rule and must be rejected. Every block is
-- wrapped in BEGIN/ROLLBACK so the seed data is never changed.
-- Run WITHOUT ON_ERROR_STOP so all tests execute:
--   docker exec -i hospital_pg psql -U hospital_admin -d hospital_db \
--     -f /workspace/portfolio-1-database-design/constraint_tests.sql

\echo '--- T1 CHECK: gender must be M or F'
BEGIN;
INSERT INTO patient (first_name, last_name, dob, gender, phone)
VALUES ('Test', 'Patient', '1990-01-01', 'X', '+2340000000001');
ROLLBACK;

\echo '--- T2 UNIQUE: two patients cannot share a phone number'
BEGIN;
INSERT INTO patient (first_name, last_name, dob, gender, phone)
SELECT 'Test', 'Duplicate', '1990-01-01', 'F', phone FROM patient WHERE patient_id = 1;
ROLLBACK;

\echo '--- T3 FOREIGN KEY: appointment for a patient that does not exist'
BEGIN;
INSERT INTO appointment (patient_id, doctor_id, scheduled_for)
VALUES (999999, 1, now() + interval '1 day');
ROLLBACK;

\echo '--- T4 TRIGGER: appointment doctor_id must be a doctor (staff 7 is a nurse)'
BEGIN;
INSERT INTO appointment (patient_id, doctor_id, scheduled_for)
VALUES (1, 7, now() + interval '1 day');
ROLLBACK;

\echo '--- T5 ON DELETE RESTRICT: cannot delete a patient who has medical records'
BEGIN;
DELETE FROM patient WHERE patient_id = (SELECT patient_id FROM appointment LIMIT 1);
ROLLBACK;

\echo '--- T6 PARTIAL UNIQUE: a bed already holding a patient cannot be reused'
BEGIN;
INSERT INTO admission (patient_id, ward_id, bed_number)
SELECT 50, ward_id, bed_number FROM admission WHERE discharged_at IS NULL LIMIT 1;
ROLLBACK;

\echo '--- T7 TRIGGER: bed number must exist in the ward'
BEGIN;
INSERT INTO admission (patient_id, ward_id, bed_number) VALUES (50, 2, 99);
ROLLBACK;

\echo '--- T8 CHECK: discharge cannot be before admission'
BEGIN;
UPDATE admission SET discharged_at = admitted_at - interval '1 hour'
WHERE admission_id = 1;
ROLLBACK;

\echo '--- T9 CHECK: medication stock cannot go negative'
BEGIN;
UPDATE medication SET stock_quantity = stock_quantity - 10000 WHERE medication_id = 1;
ROLLBACK;

\echo '--- T10 TRIGGER: payment cannot exceed the invoice total'
BEGIN;
INSERT INTO payment (invoice_id, amount, method)
SELECT invoice_id, total_amount + 1, 'cash' FROM invoice WHERE status = 'unpaid' LIMIT 1;
ROLLBACK;

\echo '--- T11 CASCADE: deleting an unpaid invoice removes its items (and nothing else)'
BEGIN;
SELECT invoice_id, (SELECT count(*) FROM invoice_item ii WHERE ii.invoice_id = i.invoice_id) AS items_before
FROM invoice i WHERE status = 'unpaid' ORDER BY invoice_id LIMIT 1 \gset
DELETE FROM invoice WHERE invoice_id = :invoice_id;
SELECT :items_before AS items_before,
       (SELECT count(*) FROM invoice_item WHERE invoice_id = :invoice_id) AS items_after;
ROLLBACK;

\echo '--- T12 TRIGGER: invoice total follows its items'
BEGIN;
SELECT invoice_id AS inv, total_amount AS before_total FROM invoice ORDER BY invoice_id LIMIT 1 \gset
INSERT INTO invoice_item (invoice_id, description, item_type, amount)
VALUES (:inv, 'Test item', 'consultation', 2500);
SELECT :before_total AS before_total, total_amount AS after_total FROM invoice WHERE invoice_id = :inv;
ROLLBACK;
