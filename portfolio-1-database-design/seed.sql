-- MIVA Teaching Hospital - reproducible seed data
--
-- Run after schema.sql and indexes.sql:
--   docker exec -i hospital_pg psql -U hospital_admin -d hospital_db \
--     -v ON_ERROR_STOP=1 -f /workspace/portfolio-1-database-design/seed.sql
--
-- setseed() fixes the random() sequence, so every run produces the same
-- patients, codes and amounts. Timestamps are relative to now() so that
-- "last 30 days" and "this month" reports always have data to show.
--
-- Volumes: 50 patients, 15 staff, 5 departments, 30 medications, 20 lab
-- tests, 100 appointments, 60 diagnoses, 80 prescriptions, 48 lab orders
-- (40 with results, 8 still open), 4 wards, 20 admissions, 50 invoices.

SET client_min_messages = warning;

BEGIN;

SELECT setseed(0.42);

TRUNCATE audit_log, payment, invoice_item, invoice, admission, ward,
    lab_result, lab_order, lab_test, prescription, medication, diagnosis,
    appointment, staff, department, patient RESTART IDENTITY CASCADE;

-- ---------------------------------------------------------------------------
-- Departments and staff
-- ---------------------------------------------------------------------------

INSERT INTO department (name, location) VALUES
    ('General Medicine',           'Block A, Ground Floor'),
    ('Paediatrics',                'Block B, First Floor'),
    ('Obstetrics and Gynaecology', 'Block C, First Floor'),
    ('Surgery',                    'Block D, Second Floor'),
    ('Clinical Support Services',  'Block E, Ground Floor');

-- staff_id 1-6 are doctors; the order matters for the rest of this script.
INSERT INTO staff (first_name, last_name, role, department_id, phone, email, hired_at) VALUES
    ('Chinedu',   'Okafor',    'doctor',          1, '+2348031000001', 'c.okafor@mivahospital.ng',    '2016-03-14 08:00+01'),
    ('Fatima',    'Bello',     'doctor',          1, '+2348031000002', 'f.bello@mivahospital.ng',     '2018-07-02 08:00+01'),
    ('Oluwaseun', 'Adeyemi',   'doctor',          2, '+2348031000003', 'o.adeyemi@mivahospital.ng',   '2017-01-09 08:00+01'),
    ('Ngozi',     'Eze',       'doctor',          3, '+2348031000004', 'n.eze@mivahospital.ng',       '2019-05-20 08:00+01'),
    ('Ibrahim',   'Musa',      'doctor',          4, '+2348031000005', 'i.musa@mivahospital.ng',      '2015-11-02 08:00+01'),
    ('Emeka',     'Nwosu',     'doctor',          4, '+2348031000006', 'e.nwosu@mivahospital.ng',     '2021-02-15 08:00+01'),
    ('Aisha',     'Abdullahi', 'nurse',           1, '+2348031000007', 'a.abdullahi@mivahospital.ng', '2019-09-01 08:00+01'),
    ('Blessing',  'Okon',      'nurse',           2, '+2348031000008', 'b.okon@mivahospital.ng',      '2020-04-13 08:00+01'),
    ('Hauwa',     'Danjuma',   'nurse',           3, '+2348031000009', 'h.danjuma@mivahospital.ng',   '2022-01-10 08:00+01'),
    ('Tunde',     'Bakare',    'lab_technician',  5, '+2348031000010', 't.bakare@mivahospital.ng',    '2018-10-08 08:00+01'),
    ('Grace',     'Effiong',   'lab_technician',  5, '+2348031000011', 'g.effiong@mivahospital.ng',   '2023-03-06 08:00+01'),
    ('Yusuf',     'Lawal',     'pharmacist',      5, '+2348031000012', 'y.lawal@mivahospital.ng',     '2017-06-19 08:00+01'),
    ('Chioma',    'Obi',       'receptionist',    5, '+2348031000013', 'c.obi@mivahospital.ng',       '2022-08-01 08:00+01'),
    ('Kehinde',   'Ogunleye',  'billing_officer', 5, '+2348031000014', 'k.ogunleye@mivahospital.ng',  '2020-11-23 08:00+01'),
    ('Maryam',    'Sani',      'administrator',   5, '+2348031000015', 'm.sani@mivahospital.ng',      '2014-02-03 08:00+01');

-- ---------------------------------------------------------------------------
-- Patients
-- ---------------------------------------------------------------------------

INSERT INTO patient (first_name, last_name, dob, gender, phone, address, blood_group, registered_at)
SELECT
    CASE WHEN g % 2 = 1
         THEN (ARRAY['Amina','Folasade','Chiamaka','Zainab','Adaeze','Halima','Funmilayo',
                     'Nkechi','Hadiza','Temitope','Ifeoma','Khadija','Bukola','Uchenna',
                     'Rukayat','Ebere','Safiya','Yetunde','Obiageli','Asmau','Damilola',
                     'Chinwe','Bilkisu','Omolara','Nneka'])[(g + 1) / 2]
         ELSE (ARRAY['Chukwuemeka','Abubakar','Olumide','Ikenna','Sadiq','Babatunde',
                     'Obinna','Usman','Adewale','Chidi','Aminu','Segun','Kelechi',
                     'Danladi','Femi','Nnamdi','Bashir','Rotimi','Uzoma','Haruna',
                     'Gbenga','Ifeanyi','Jamilu','Kayode','Ekene'])[g / 2]
    END,
    (ARRAY['Yusuf','Adebayo','Okonkwo','Ibrahim','Nwachukwu','Mohammed','Ogunbiyi',
           'Eze','Abdullahi','Olawale','Chukwu','Suleiman','Adeleke','Onyeka','Danladi',
           'Bello','Afolabi','Uche','Aliyu','Oyelaran','Nnadi','Umar','Ajayi','Obi',
           'Lawal','Akinola','Igwe','Shehu','Balogun','Okeke'])[1 + (g * 7) % 30],
    DATE '1950-01-01' + floor(random() * 25000)::int,
    CASE WHEN g % 2 = 1 THEN 'F' ELSE 'M' END,
    '+23480' || lpad((10000000 + g * 104729)::text, 8, '0'),
    'Plot ' || (1 + (g * 13) % 200) || ', '
        || (ARRAY['Garki','Wuse II','Maitama','Asokoro','Gwarinpa','Kubwa','Apo','Lugbe',
                  'Jabi','Utako','Karu','Nyanya','Lokogoma','Galadimawa','Kado','Life Camp',
                  'Durumi','Gudu','Jahi','Katampe'])[1 + (g * 3) % 20]
        || ', Abuja',
    (ARRAY['O+','O+','O+','O+','A+','A+','B+','B+','AB+','O-','A-','B-'])[1 + floor(random() * 12)::int],
    now() - random() * interval '730 days'
FROM generate_series(1, 50) AS g
ORDER BY g;

-- ---------------------------------------------------------------------------
-- Catalogues: medications and lab tests
-- ---------------------------------------------------------------------------

INSERT INTO medication (name, manufacturer, unit_price, stock_quantity, reorder_level) VALUES
    ('Paracetamol 500mg',                'Emzor Pharmaceuticals',   50.00, 2000, 300),
    ('Artemether/Lumefantrine 80/480mg', 'Fidson Healthcare',     2500.00,  400, 100),
    ('Amoxicillin 500mg',                'May and Baker Nigeria', 1200.00,  600, 150),
    ('Amlodipine 5mg',                   'Swiss Pharma Nigeria',   800.00,  500, 100),
    ('Metformin 500mg',                  'Emzor Pharmaceuticals',  600.00,  700, 150),
    ('Ciprofloxacin 500mg',              'Fidson Healthcare',     1500.00,  300,  80),
    ('Omeprazole 20mg',                  'Juhel Nigeria',          900.00,  350,  80),
    ('Nitrofurantoin 100mg',             'Neimeth International', 1100.00,  120,  50),
    ('Ceftriaxone 1g injection',         'GSK Nigeria',           3500.00,  150,  60),
    ('Oral Rehydration Salts',           'Emzor Pharmaceuticals',  300.00,  900, 200),
    ('Diclofenac 50mg',                  'Fidson Healthcare',      400.00,  450, 100),
    ('Hydrocortisone cream 1%',          'GSK Nigeria',           1800.00,   60,  30),
    ('Folic acid 5mg',                   'Emzor Pharmaceuticals',  200.00, 1000, 200),
    ('Ibuprofen 400mg',                  'May and Baker Nigeria',  350.00,  800, 150),
    ('Metronidazole 400mg',              'Juhel Nigeria',          500.00,  500, 100),
    ('Lisinopril 10mg',                  'Swiss Pharma Nigeria',  1000.00,   40,  80),
    ('Losartan 50mg',                    'Fidson Healthcare',     1300.00,  200,  60),
    ('Glibenclamide 5mg',                'Neimeth International',  450.00,   25,  50),
    ('Insulin glargine 100IU/ml',        'Sanofi Nigeria',       12000.00,   30,  20),
    ('Salbutamol inhaler 100mcg',        'GSK Nigeria',           3000.00,   15,  25),
    ('Prednisolone 5mg',                 'Emzor Pharmaceuticals',  300.00,  400, 100),
    ('Cetirizine 10mg',                  'Juhel Nigeria',          250.00,  600, 100),
    ('Azithromycin 500mg',               'Fidson Healthcare',     2200.00,  180,  50),
    ('Co-trimoxazole 960mg',             'May and Baker Nigeria',  400.00,  350,  80),
    ('Albendazole 400mg',                'Emzor Pharmaceuticals',  300.00,  250,  60),
    ('Fluconazole 150mg',                'Neimeth International',  700.00,   90,  40),
    ('Ferrous sulphate 200mg',           'Emzor Pharmaceuticals',  150.00, 1200, 200),
    ('Vitamin C 100mg',                  'Emzor Pharmaceuticals',  100.00, 1500, 300),
    ('Tramadol 50mg',                    'Swiss Pharma Nigeria',   900.00,    3,  30),
    ('Zinc sulphate 20mg',               'Juhel Nigeria',          250.00,  500, 100);

-- Seed-only lookup: how each test's result is generated.
CREATE TEMP TABLE seed_lab (
    name TEXT, cost NUMERIC, kind TEXT,
    lo NUMERIC, hi NUMERIC, unit TEXT, ref TEXT,
    normal_txt TEXT, abnormal_txt TEXT
) ON COMMIT DROP;

INSERT INTO seed_lab VALUES
    ('Full Blood Count',                        6000, 'num',  9.0,  16.5, 'g/dL Hb', '12.0-17.5 g/dL', NULL, NULL),
    ('Malaria Parasite Test',                   2500, 'qual', NULL, NULL, NULL, 'Negative',       'Negative',      'Positive (+)'),
    ('Widal Test',                              3000, 'qual', NULL, NULL, NULL, 'Below 1:80',     'Titre 1:40',    'Titre 1:160'),
    ('Fasting Blood Sugar',                     2000, 'num',  3.5,  12.0, 'mmol/L',  '3.9-5.6 mmol/L', NULL, NULL),
    ('HbA1c',                                   8000, 'num',  4.5,  11.0, '%',       '4.0-5.6 %',      NULL, NULL),
    ('Lipid Profile',                           9000, 'num',  3.0,   7.5, 'mmol/L total cholesterol', 'Below 5.2 mmol/L', NULL, NULL),
    ('Liver Function Test',                    10000, 'num', 10.0, 120.0, 'U/L ALT', '7-56 U/L',       NULL, NULL),
    ('Electrolytes, Urea and Creatinine',       9500, 'num', 50.0, 180.0, 'umol/L creatinine', '60-110 umol/L', NULL, NULL),
    ('Urinalysis',                              1500, 'qual', NULL, NULL, NULL, 'Normal',         'Normal',        'Protein trace, nitrite positive'),
    ('HIV Screening',                           3000, 'qual', NULL, NULL, NULL, 'Non-reactive',   'Non-reactive',  'Reactive, refer for confirmation'),
    ('Hepatitis B Surface Antigen',             3000, 'qual', NULL, NULL, NULL, 'Negative',       'Negative',      'Positive'),
    ('Hepatitis C Antibody',                    3500, 'qual', NULL, NULL, NULL, 'Negative',       'Negative',      'Positive'),
    ('Pregnancy Test',                          2500, 'qual', NULL, NULL, NULL, 'Negative',       'Negative',      'Positive'),
    ('Blood Group and Genotype',                3000, 'qual', NULL, NULL, NULL, 'N/A',            'O+ / AA',       'O+ / AS'),
    ('Stool Microscopy, Culture and Sensitivity', 5000, 'qual', NULL, NULL, NULL, 'No growth',   'No growth',     'Salmonella spp. isolated'),
    ('Urine Microscopy, Culture and Sensitivity', 5000, 'qual', NULL, NULL, NULL, 'No growth',   'No growth',     'E. coli >100,000 CFU/ml'),
    ('Thyroid Function Test',                  15000, 'num',  0.2,   6.0, 'mIU/L TSH', '0.4-4.0 mIU/L', NULL, NULL),
    ('Prostate Specific Antigen',              12000, 'num',  0.5,   8.0, 'ng/mL',   'Below 4.0 ng/mL', NULL, NULL),
    ('Erythrocyte Sedimentation Rate',          2000, 'num',  2.0,  60.0, 'mm/hr',   '0-20 mm/hr',     NULL, NULL),
    ('Serum Potassium',                         6500, 'num',  2.8,   6.0, 'mmol/L',  '3.5-5.1 mmol/L', NULL, NULL);

INSERT INTO lab_test (name, standard_cost)
SELECT name, cost FROM seed_lab;

-- ---------------------------------------------------------------------------
-- Appointments (past ones are mostly completed; future ones are booked)
-- ---------------------------------------------------------------------------

INSERT INTO appointment (patient_id, doctor_id, scheduled_for, status, reason, created_at)
SELECT
    s.patient_id,
    s.doctor_id,
    s.scheduled_for,
    CASE WHEN s.scheduled_for > now() THEN 'booked'
         WHEN s.g % 10 = 0            THEN 'cancelled'
         WHEN s.g % 10 = 5            THEN 'no_show'
         ELSE 'completed'
    END,
    s.reason,
    s.scheduled_for - interval '3 days'
FROM (
    SELECT
        g,
        -- power() skews towards lower ids, so some patients are frequent visitors
        1 + floor(power(random(), 1.6) * 50)::int AS patient_id,
        1 + floor(random() * 6)::int              AS doctor_id,
        date_trunc('day', now() - interval '180 days' + random() * interval '194 days')
            + (8 + floor(random() * 9)::int) * interval '1 hour'
            + (floor(random() * 4)::int * 15) * interval '1 minute' AS scheduled_for,
        (ARRAY['Fever and headache','Routine check-up','Persistent cough',
               'Blood pressure review','Abdominal pain','Antenatal visit',
               'Follow-up after treatment','Skin rash','Back pain',
               'Diabetes review','Painful urination','Diarrhoea and vomiting'])
            [1 + floor(random() * 12)::int] AS reason
    FROM generate_series(1, 100) AS g
) s
ORDER BY s.g;

-- ---------------------------------------------------------------------------
-- Diagnoses and prescriptions
-- ---------------------------------------------------------------------------

CREATE TEMP TABLE seed_icd (
    n INT, icd TEXT, notes TEXT, drug TEXT, dosage TEXT, days INT
) ON COMMIT DROP;

INSERT INTO seed_icd VALUES
    ( 1, 'B54',   'Uncomplicated malaria, MP positive',      'Artemether/Lumefantrine 80/480mg', '1 tablet twice daily',          3),
    ( 2, 'J00',   'Acute nasopharyngitis (common cold)',     'Paracetamol 500mg',                '1g three times daily',          3),
    ( 3, 'I10',   'Essential hypertension',                  'Amlodipine 5mg',                   '5mg once daily',               30),
    ( 4, 'E11.9', 'Type 2 diabetes without complications',   'Metformin 500mg',                  '500mg twice daily',            30),
    ( 5, 'A01.0', 'Typhoid fever',                           'Ciprofloxacin 500mg',              '500mg twice daily',             7),
    ( 6, 'K29.7', 'Gastritis, unspecified',                  'Omeprazole 20mg',                  '20mg once daily before food',  14),
    ( 7, 'N39.0', 'Urinary tract infection',                 'Nitrofurantoin 100mg',             '100mg twice daily',             5),
    ( 8, 'J18.9', 'Community-acquired pneumonia',            'Amoxicillin 500mg',                '500mg three times daily',       7),
    ( 9, 'A09',   'Infectious gastroenteritis',              'Oral Rehydration Salts',           '1 sachet after each loose stool', 3),
    (10, 'M54.5', 'Low back pain',                           'Diclofenac 50mg',                  '50mg twice daily after food',   5),
    (11, 'L30.9', 'Dermatitis, unspecified',                 'Hydrocortisone cream 1%',          'Apply thinly twice daily',     10),
    (12, 'O99.0', 'Anaemia complicating pregnancy',          'Ferrous sulphate 200mg',           '200mg twice daily',            30);

-- One diagnosis for each of the first 60 completed appointments.
INSERT INTO diagnosis (appointment_id, icd_code, notes, recorded_at)
SELECT a.appointment_id, c.icd, c.notes,
       a.scheduled_for + interval '15 minutes' + random() * interval '45 minutes'
FROM (
    SELECT appointment_id, scheduled_for,
           row_number() OVER (ORDER BY appointment_id) AS rn
    FROM appointment
    WHERE status = 'completed'
    ORDER BY appointment_id
    LIMIT 60
) a
JOIN seed_icd c ON c.n = 1 + (a.rn * 5) % 12
ORDER BY a.appointment_id;

-- Main drug for every diagnosis (60 rows).
INSERT INTO prescription (diagnosis_id, medication_id, dosage, duration_days, issued_at)
SELECT d.diagnosis_id, m.medication_id, c.dosage, c.days, d.recorded_at + interval '5 minutes'
FROM diagnosis d
JOIN seed_icd   c ON c.icd = d.icd_code
JOIN medication m ON m.name = c.drug
ORDER BY d.diagnosis_id;

-- Paracetamol for symptom relief on 20 diagnoses that did not already get it.
INSERT INTO prescription (diagnosis_id, medication_id, dosage, duration_days, issued_at)
SELECT d.diagnosis_id,
       (SELECT medication_id FROM medication WHERE name = 'Paracetamol 500mg'),
       '1g three times daily as needed', 3,
       d.recorded_at + interval '6 minutes'
FROM diagnosis d
WHERE d.icd_code <> 'J00'
ORDER BY d.diagnosis_id
LIMIT 20;

-- ---------------------------------------------------------------------------
-- Lab orders and results
-- ---------------------------------------------------------------------------

-- 1-40 completed, 41-46 pending, 47-48 in progress.
INSERT INTO lab_order (patient_id, lab_test_id, ordered_by, ordered_at, status)
SELECT
    1 + floor(random() * 50)::int,
    1 + floor(random() * 20)::int,
    1 + floor(random() * 6)::int,
    CASE WHEN g <= 40 THEN now() - interval '1 day' - random() * interval '59 days'
         ELSE now() - (g - 40) * interval '8 hours'
    END,
    CASE WHEN g <= 40 THEN 'completed'
         WHEN g <= 46 THEN 'pending'
         ELSE 'in_progress'
    END
FROM generate_series(1, 48) AS g
ORDER BY g;

INSERT INTO lab_result (lab_order_id, result_value, reference_range, recorded_at, recorded_by)
SELECT
    o.lab_order_id,
    CASE WHEN s.kind = 'num'
         THEN round(s.lo + random()::numeric * (s.hi - s.lo), 1)::text || ' ' || s.unit
         WHEN random() < 0.25 THEN s.abnormal_txt
         ELSE s.normal_txt
    END,
    s.ref,
    o.ordered_at + interval '2 hours' + random() * interval '22 hours',
    10 + floor(random() * 2)::int
FROM lab_order o
JOIN lab_test t ON t.lab_test_id = o.lab_test_id
JOIN seed_lab s ON s.name = t.name
WHERE o.status = 'completed'
ORDER BY o.lab_order_id;

-- ---------------------------------------------------------------------------
-- Wards and admissions
-- ---------------------------------------------------------------------------

INSERT INTO ward (name, department_id, total_beds) VALUES
    ('Medical Ward A',  1, 10),
    ('Children''s Ward', 2,  8),
    ('Maternity Ward',  3,  8),
    ('Surgical Ward',   4, 10);

-- 20 different patients (17 is coprime with 50). 1-12 discharged, 13-20 still on the ward.
INSERT INTO admission (patient_id, ward_id, bed_number, admitted_at, discharged_at)
SELECT
    1 + (g * 17) % 50,
    1 + (g - 1) % 4,
    1 + (g - 1) / 4,
    s.admitted_at,
    CASE WHEN g <= 12 THEN s.admitted_at + interval '1 day' + random() * interval '6 days' END
FROM generate_series(1, 20) AS g
CROSS JOIN LATERAL (
    SELECT CASE WHEN g <= 12 THEN now() - interval '10 days' - random() * interval '50 days'
                ELSE now() - interval '2 hours' - random() * interval '5 days'
           END AS admitted_at
) s
ORDER BY g;

-- ---------------------------------------------------------------------------
-- Billing: invoices, items, payments
-- ---------------------------------------------------------------------------

-- One invoice for each of the first 50 completed appointments.
CREATE TEMP TABLE seed_invoice ON COMMIT DROP AS
SELECT row_number() OVER (ORDER BY appointment_id) AS n, appointment_id, patient_id, doctor_id,
       scheduled_for + interval '1 hour' AS issued_at
FROM appointment
WHERE status = 'completed'
ORDER BY appointment_id
LIMIT 50;

INSERT INTO invoice (patient_id, issued_at)
SELECT patient_id, issued_at FROM seed_invoice ORDER BY n;

-- Consultation fee, priced by the doctor's department.
-- reference_id = appointment_id
INSERT INTO invoice_item (invoice_id, description, item_type, reference_id, amount)
SELECT i.invoice_id, 'Consultation - ' || d.name, 'consultation', si.appointment_id,
       CASE d.department_id WHEN 1 THEN 10000 WHEN 2 THEN 8000
                            WHEN 3 THEN 12000 ELSE 15000 END
FROM seed_invoice si
JOIN invoice    i ON i.invoice_id = si.n
JOIN staff      s ON s.staff_id = si.doctor_id
JOIN department d ON d.department_id = s.department_id
ORDER BY i.invoice_id;

-- Drugs prescribed at that appointment. reference_id = prescription_id
INSERT INTO invoice_item (invoice_id, description, item_type, reference_id, amount)
SELECT i.invoice_id, m.name || ' x ' || (p.duration_days * 2), 'medication', p.prescription_id,
       m.unit_price * p.duration_days * 2
FROM seed_invoice si
JOIN invoice      i  ON i.invoice_id = si.n
JOIN diagnosis    dg ON dg.appointment_id = si.appointment_id
JOIN prescription p  ON p.diagnosis_id = dg.diagnosis_id
JOIN medication   m  ON m.medication_id = p.medication_id
ORDER BY i.invoice_id, p.prescription_id;

-- Completed lab tests, billed on the patient's invoice closest in time.
-- reference_id = lab_order_id
INSERT INTO invoice_item (invoice_id, description, item_type, reference_id, amount)
SELECT DISTINCT ON (o.lab_order_id)
       i.invoice_id, 'Lab - ' || t.name, 'lab_test', o.lab_order_id, t.standard_cost
FROM lab_order o
JOIN lab_test  t ON t.lab_test_id = o.lab_test_id
JOIN invoice   i ON i.patient_id = o.patient_id
WHERE o.status = 'completed'
ORDER BY o.lab_order_id, abs(extract(epoch FROM i.issued_at - o.ordered_at));

-- Payments: every 5th invoice is unpaid, the next is half paid, the rest are
-- paid in full. The payment trigger sets invoice.status.
INSERT INTO payment (invoice_id, amount, method, paid_at)
SELECT i.invoice_id,
       CASE WHEN i.invoice_id % 5 = 1 THEN round(i.total_amount * 0.5, 2)
            ELSE i.total_amount END,
       (ARRAY['cash','card','transfer','hmo'])[1 + (i.invoice_id % 4)::int],
       i.issued_at + random() * interval '3 days'
FROM invoice i
WHERE i.invoice_id % 5 <> 0
ORDER BY i.invoice_id;

COMMIT;

-- Make sure the planner has statistics for the fresh data.
ANALYZE;
