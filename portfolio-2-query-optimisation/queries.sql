-- MIVA Teaching Hospital - 10 operational and reporting queries
--
-- Each query starts with a "-- @Qn" marker line; capture_plans.sh uses these
-- markers to pull out one query at a time and run EXPLAIN ANALYZE on it.
-- Example values (doctor 1, ICD code B54, etc.) are fixed so results and
-- plans are comparable between runs.

-- @Q1
-- Business reason: the doctor's day list that a receptionist prints every morning.
SELECT a.appointment_id,
       a.scheduled_for,
       p.first_name || ' ' || p.last_name AS patient,
       a.status,
       a.reason
FROM appointment a
JOIN patient p ON p.patient_id = a.patient_id
WHERE a.doctor_id = 1
  AND a.scheduled_for >= current_date - 17
  AND a.scheduled_for <  current_date - 16
ORDER BY a.scheduled_for;

-- @Q2
-- Business reason: the pharmacy restocks its fastest-moving drugs first.
SELECT m.medication_id,
       m.name,
       count(*) AS times_prescribed
FROM prescription pr
JOIN medication m ON m.medication_id = pr.medication_id
WHERE pr.issued_at >= now() - interval '30 days'
GROUP BY m.medication_id, m.name
ORDER BY times_prescribed DESC, m.name
LIMIT 5;

-- @Q3
-- Business reason: management compares month-to-date revenue across departments.
-- Each invoice is attributed to the department of the doctor on its consultation line.
SELECT d.department_id,
       d.name AS department,
       count(*)            AS invoices,
       sum(i.total_amount) AS revenue
FROM invoice i
JOIN invoice_item ii ON ii.invoice_id = i.invoice_id AND ii.item_type = 'consultation'
JOIN appointment  a  ON a.appointment_id = ii.reference_id
JOIN staff        s  ON s.staff_id = a.doctor_id
JOIN department   d  ON d.department_id = s.department_id
WHERE i.issued_at >= date_trunc('month', now())
  AND i.issued_at <  date_trunc('month', now()) + interval '1 month'
  AND i.status <> 'cancelled'
GROUP BY d.department_id, d.name
ORDER BY revenue DESC;

-- @Q4
-- Business reason: frequent attenders are flagged for a care-coordination review.
SELECT p.patient_id,
       p.first_name,
       p.last_name,
       count(*) AS appointments_6m
FROM appointment a
JOIN patient p ON p.patient_id = a.patient_id
WHERE a.scheduled_for >= now() - interval '6 months'
  AND a.scheduled_for <  now()
  AND a.status <> 'cancelled'
GROUP BY p.patient_id, p.first_name, p.last_name
HAVING count(*) > 3
ORDER BY appointments_6m DESC, p.patient_id;

-- @Q5
-- Business reason: the lab manager chases test orders that have waited over 24 hours.
SELECT lo.lab_order_id,
       p.first_name || ' ' || p.last_name   AS patient,
       lt.name                              AS test,
       'Dr. ' || s.first_name || ' ' || s.last_name AS ordered_by,
       lo.ordered_at,
       date_trunc('minute', now() - lo.ordered_at) AS waiting
FROM lab_order lo
JOIN patient  p  ON p.patient_id = lo.patient_id
JOIN lab_test lt ON lt.lab_test_id = lo.lab_test_id
JOIN staff    s  ON s.staff_id = lo.ordered_by
WHERE lo.status = 'pending'
  AND lo.ordered_at < now() - interval '24 hours'
ORDER BY lo.ordered_at;

-- @Q6
-- Business reason: the bed manager needs live occupancy before accepting a transfer.
SELECT w.ward_id,
       w.name,
       w.total_beds,
       count(a.admission_id)                AS occupied,
       w.total_beds - count(a.admission_id) AS free,
       round(100.0 * count(a.admission_id) / w.total_beds, 1) AS occupancy_pct
FROM ward w
LEFT JOIN admission a ON a.ward_id = w.ward_id AND a.discharged_at IS NULL
GROUP BY w.ward_id, w.name, w.total_beds
ORDER BY w.ward_id;

-- @Q7
-- Business reason: a malaria treatment audit lists patients diagnosed with B54
-- who were prescribed Artemether/Lumefantrine for that diagnosis.
SELECT DISTINCT p.patient_id,
       p.first_name,
       p.last_name,
       d.recorded_at::date AS diagnosed_on
FROM diagnosis    d
JOIN prescription pr ON pr.diagnosis_id = d.diagnosis_id
JOIN medication   m  ON m.medication_id = pr.medication_id
JOIN appointment  a  ON a.appointment_id = d.appointment_id
JOIN patient      p  ON p.patient_id = a.patient_id
WHERE d.icd_code = 'B54'
  AND m.name = 'Artemether/Lumefantrine 80/480mg'
ORDER BY diagnosed_on DESC, p.patient_id;

-- @Q8
-- Business reason: clinical leads monitor how long each doctor takes to record a diagnosis.
SELECT s.staff_id,
       'Dr. ' || s.first_name || ' ' || s.last_name AS doctor,
       count(*) AS diagnoses,
       date_trunc('second', avg(d.recorded_at - a.scheduled_for)) AS avg_time_to_diagnosis
FROM diagnosis   d
JOIN appointment a ON a.appointment_id = d.appointment_id
JOIN staff       s ON s.staff_id = a.doctor_id
GROUP BY s.staff_id, s.first_name, s.last_name
ORDER BY avg_time_to_diagnosis;

-- @Q9
-- Business reason: the billing office calls the 10 patients who owe the most.
SELECT p.patient_id,
       p.first_name || ' ' || p.last_name           AS patient,
       p.phone,
       sum(i.total_amount)                           AS billed,
       sum(COALESCE(pay.paid, 0))                    AS paid,
       sum(i.total_amount - COALESCE(pay.paid, 0))   AS outstanding
FROM invoice i
JOIN patient p ON p.patient_id = i.patient_id
LEFT JOIN (SELECT invoice_id, sum(amount) AS paid
           FROM payment GROUP BY invoice_id) pay ON pay.invoice_id = i.invoice_id
WHERE i.status IN ('unpaid', 'partially_paid')
GROUP BY p.patient_id, p.first_name, p.last_name, p.phone
ORDER BY outstanding DESC
LIMIT 10;

-- @Q10
-- Business reason: each head of department sees which doctors carry the most completed consultations.
SELECT d.name AS department,
       'Dr. ' || s.first_name || ' ' || s.last_name AS doctor,
       count(*) AS completed_appointments,
       RANK() OVER (PARTITION BY d.department_id ORDER BY count(*) DESC) AS rank_in_department
FROM appointment a
JOIN staff      s ON s.staff_id = a.doctor_id
JOIN department d ON d.department_id = s.department_id
WHERE a.status = 'completed'
GROUP BY d.department_id, d.name, s.staff_id, s.first_name, s.last_name
ORDER BY d.name, rank_in_department;
