-- MIVA Teaching Hospital - bulk load for performance testing
--
-- The Portfolio 1 seed (50 patients, 100 appointments) is far too small to
-- show the effect of an index: every table fits in one or two 8 kB pages, so
-- the planner correctly chooses a sequential scan whatever indexes exist.
-- This script adds about two years of hospital activity ON TOP of the seed,
-- so that the before/after plans in execution_plans/ are meaningful.
--
-- Run after portfolio-1 schema.sql, indexes.sql and seed.sql:
--   docker exec -i hospital_pg psql -U hospital_admin -d hospital_db \
--     -v ON_ERROR_STOP=1 -f /workspace/portfolio-2-query-optimisation/bulk_load.sql
--
-- Adds roughly: 40 doctors, 20,000 patients, 300,000 appointments,
-- 160,000 diagnoses and prescriptions, 100,000 lab orders and results,
-- 30,000 discharged admissions, 160,000 invoices with items and payments.

SET client_min_messages = warning;

BEGIN;

SELECT setseed(0.84);

-- 40 more doctors spread across the four clinical departments.
INSERT INTO staff (first_name, last_name, role, department_id, phone, email, hired_at)
SELECT (ARRAY['Adaobi','Musa','Tolulope','Sani','Chiamaka','Bello','Olayinka','Garba',
              'Nkiru','Lanre'])[1 + g % 10],
       (ARRAY['Okoro','Adamu','Oyewole','Mustapha','Nwankwo','Idris','Fashola','Onu'])[1 + g % 8],
       'doctor',
       1 + g % 4,
       '+2348032' || lpad(g::text, 6, '0'),
       'doctor' || g || '@mivahospital.ng',
       now() - (365 + g * 30) * interval '1 day'
FROM generate_series(1, 40) AS g;

-- 20,000 more patients.
INSERT INTO patient (first_name, last_name, dob, gender, phone, address, blood_group, registered_at)
SELECT (ARRAY['Amina','Chukwuemeka','Folasade','Abubakar','Zainab','Olumide','Halima',
              'Ikenna','Nkechi','Sadiq','Temitope','Babatunde','Ifeoma','Usman'])[1 + g % 14],
       (ARRAY['Yusuf','Adebayo','Okonkwo','Ibrahim','Nwachukwu','Mohammed','Ogunbiyi',
              'Eze','Abdullahi','Olawale','Chukwu','Suleiman','Bello','Afolabi'])[1 + (g * 7) % 14],
       DATE '1945-01-01' + floor(random() * 28000)::int,
       CASE WHEN g % 2 = 0 THEN 'F' ELSE 'M' END,
       '+23490' || lpad(g::text, 8, '0'),
       'Abuja',
       (ARRAY['O+','O+','O+','A+','A+','B+','B+','AB+','O-'])[1 + floor(random() * 9)::int],
       now() - random() * interval '1095 days'
FROM generate_series(1, 20000) AS g;

-- 300,000 appointments from two years ago to one month ahead.
-- Numbered lookups, so a random number 1..N maps to a real id even when the
-- sequences have gaps (rolled-back inserts still consume sequence values).
CREATE TEMP TABLE bulk_doctor ON COMMIT DROP AS
SELECT row_number() OVER (ORDER BY staff_id) AS n, staff_id
FROM staff WHERE role = 'doctor';

CREATE TEMP TABLE bulk_patient ON COMMIT DROP AS
SELECT row_number() OVER (ORDER BY patient_id) AS n, patient_id
FROM patient;

INSERT INTO appointment (patient_id, doctor_id, scheduled_for, status, reason, created_at)
SELECT bp.patient_id, bd.staff_id, x.ts,
       CASE WHEN x.ts > now() THEN 'booked'
            WHEN x.g % 10 = 0 THEN 'cancelled'
            WHEN x.g % 10 = 5 THEN 'no_show'
            ELSE 'completed' END,
       'Bulk visit',
       x.ts - interval '3 days'
FROM (
    SELECT g,
           1 + floor(random() * (SELECT count(*) FROM bulk_patient))::int AS patient_n,
           1 + floor(random() * (SELECT count(*) FROM bulk_doctor))::int  AS doctor_n,
           date_trunc('day', now() - interval '730 days' + random() * interval '760 days')
               + (8 + floor(random() * 9)::int) * interval '1 hour'
               + (floor(random() * 4)::int * 15) * interval '1 minute' AS ts
    FROM generate_series(1, 300000) AS g
) x
JOIN bulk_patient bp ON bp.n = x.patient_n
JOIN bulk_doctor  bd ON bd.n = x.doctor_n;

-- Diagnoses for about 75% of completed bulk appointments. 30 ICD codes, so
-- one code (e.g. B54) is roughly 3% of diagnoses: selective enough for an index.
CREATE TEMP TABLE bulk_icd ON COMMIT DROP AS
SELECT row_number() OVER () AS n, icd, med
FROM (VALUES
    ('B54', 2), ('J00', 1), ('I10', 4), ('E11.9', 5), ('A01.0', 6), ('K29.7', 7),
    ('N39.0', 8), ('J18.9', 3), ('A09', 10), ('M54.5', 11), ('L30.9', 12), ('O99.0', 27),
    ('J45.9', 20), ('R50.9', 1), ('K59.0', 30), ('B82.9', 25), ('H10.9', 22), ('J02.9', 23),
    ('N76.0', 26), ('E86', 10), ('I50.9', 16), ('M79.1', 14), ('R51', 1), ('T14.1', 3),
    ('A06.0', 15), ('D50.9', 27), ('E78.5', 17), ('G43.9', 14), ('L02.9', 24), ('K21.9', 7)
) AS v(icd, med);

INSERT INTO diagnosis (appointment_id, icd_code, notes, recorded_at)
SELECT a.appointment_id, c.icd, 'Bulk diagnosis',
       a.scheduled_for + interval '15 minutes' + random() * interval '45 minutes'
FROM (
    SELECT appointment_id, scheduled_for, 1 + floor(random() * 30)::int AS icd_n
    FROM appointment
    WHERE reason = 'Bulk visit' AND status = 'completed'
) a
JOIN bulk_icd c ON c.n = a.icd_n
WHERE random() < 0.75;

-- One prescription per bulk diagnosis, drug matched to the ICD code.
INSERT INTO prescription (diagnosis_id, medication_id, dosage, duration_days, issued_at)
SELECT d.diagnosis_id, c.med, 'As directed', 5, d.recorded_at + interval '5 minutes'
FROM diagnosis d
JOIN bulk_icd c ON c.icd = d.icd_code
WHERE d.notes = 'Bulk diagnosis';

-- 100,000 lab orders: almost all completed, a few hundred still pending.
INSERT INTO lab_order (patient_id, lab_test_id, ordered_by, ordered_at, status)
SELECT bp.patient_id, x.lab_test_id, bd.staff_id, x.ordered_at, x.status
FROM (
    SELECT 1 + floor(random() * (SELECT count(*) FROM bulk_patient))::int AS patient_n,
           1 + floor(random() * 20)::int AS lab_test_id,
           1 + floor(random() * (SELECT count(*) FROM bulk_doctor))::int AS doctor_n,
           CASE WHEN g % 200 = 0 THEN now() - random() * interval '3 days'
                ELSE now() - interval '3 days' - random() * interval '727 days' END AS ordered_at,
           CASE WHEN g % 200 = 0 THEN 'pending'
                WHEN g % 500 = 1 THEN 'cancelled'
                ELSE 'completed' END AS status
    FROM generate_series(1, 100000) AS g
) x
JOIN bulk_patient bp ON bp.n = x.patient_n
JOIN bulk_doctor  bd ON bd.n = x.doctor_n;

INSERT INTO lab_result (lab_order_id, result_value, reference_range, recorded_at, recorded_by)
SELECT lo.lab_order_id, 'See report', NULL, lo.ordered_at + interval '6 hours',
       10 + (lo.lab_order_id % 2)
FROM lab_order lo
LEFT JOIN lab_result lr ON lr.lab_order_id = lo.lab_order_id
WHERE lo.status = 'completed' AND lr.lab_order_id IS NULL;

-- 30,000 historical admissions, all discharged (open beds are still the 8 from the seed).
INSERT INTO admission (patient_id, ward_id, bed_number, admitted_at, discharged_at)
SELECT bp.patient_id, x.ward_id, 1 + floor(random() * 8)::int, x.admitted_at,
       x.admitted_at + interval '1 day' + random() * interval '9 days'
FROM (
    SELECT 1 + floor(random() * (SELECT count(*) FROM bulk_patient))::int AS patient_n,
           1 + floor(random() * 4)::int AS ward_id,
           now() - interval '15 days' - random() * interval '715 days' AS admitted_at
    FROM generate_series(1, 30000)
) x
JOIN bulk_patient bp ON bp.n = x.patient_n;

-- Billing for every bulk appointment that has a diagnosis. The per-row
-- billing triggers are switched off for the load and the totals and statuses
-- are set in bulk instead (ALTER TABLE is transactional, so a failure rolls
-- this back too).
ALTER TABLE invoice_item DISABLE TRIGGER trg_invoice_item_total;
ALTER TABLE payment      DISABLE TRIGGER trg_payment_apply;

CREATE TEMP TABLE bulk_bill ON COMMIT DROP AS
SELECT a.appointment_id, a.patient_id, a.scheduled_for + interval '1 hour' AS issued_at,
       s.department_id, pr.prescription_id, m.name AS drug, m.unit_price
FROM appointment  a
JOIN diagnosis    d  ON d.appointment_id = a.appointment_id
JOIN prescription pr ON pr.diagnosis_id = d.diagnosis_id
JOIN medication   m  ON m.medication_id = pr.medication_id
JOIN staff        s  ON s.staff_id = a.doctor_id
WHERE d.notes = 'Bulk diagnosis';

ALTER TABLE bulk_bill ADD COLUMN invoice_id BIGINT;
UPDATE bulk_bill SET invoice_id = nextval('invoice_invoice_id_seq');

INSERT INTO invoice (invoice_id, patient_id, issued_at, total_amount, status)
SELECT invoice_id, patient_id, issued_at, 0, 'unpaid' FROM bulk_bill;

INSERT INTO invoice_item (invoice_id, description, item_type, reference_id, amount)
SELECT invoice_id, 'Consultation', 'consultation', appointment_id,
       CASE department_id WHEN 1 THEN 10000 WHEN 2 THEN 8000 WHEN 3 THEN 12000 ELSE 15000 END
FROM bulk_bill
UNION ALL
SELECT invoice_id, drug || ' x 10', 'medication', prescription_id, unit_price * 10
FROM bulk_bill;

UPDATE invoice i
SET total_amount = t.total
FROM (SELECT ii.invoice_id, sum(ii.amount) AS total
      FROM invoice_item ii JOIN bulk_bill b ON b.invoice_id = ii.invoice_id
      GROUP BY ii.invoice_id) t
WHERE i.invoice_id = t.invoice_id;

-- 80% paid in full, 10% half paid, 10% unpaid.
INSERT INTO payment (invoice_id, amount, method, paid_at)
SELECT i.invoice_id,
       CASE WHEN i.invoice_id % 10 = 1 THEN round(i.total_amount * 0.5, 2) ELSE i.total_amount END,
       (ARRAY['cash','card','transfer','hmo'])[1 + (i.invoice_id % 4)::int],
       i.issued_at + random() * interval '2 days'
FROM invoice i
JOIN bulk_bill b ON b.invoice_id = i.invoice_id
WHERE i.invoice_id % 10 <> 0;

UPDATE invoice i
SET status = CASE WHEN i.invoice_id % 10 = 0 THEN 'unpaid'
                  WHEN i.invoice_id % 10 = 1 THEN 'partially_paid'
                  ELSE 'paid' END
FROM bulk_bill b
WHERE b.invoice_id = i.invoice_id;

ALTER TABLE invoice_item ENABLE TRIGGER trg_invoice_item_total;
ALTER TABLE payment      ENABLE TRIGGER trg_payment_apply;

COMMIT;

VACUUM ANALYZE;
