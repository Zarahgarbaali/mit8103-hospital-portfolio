-- MIVA Teaching Hospital - baseline indexes
--
-- PostgreSQL indexes primary keys and UNIQUE constraints automatically, but
-- not foreign keys. Without these, every join from a child table and every
-- ON DELETE RESTRICT check on a parent row falls back to a sequential scan.
--
-- Already covered, so not repeated here:
--   prescription(diagnosis_id)  -> leading column of UNIQUE (diagnosis_id, medication_id)
--   lab_result(lab_order_id)    -> UNIQUE
--
-- admission has partial unique indexes in schema.sql, but those only contain
-- open admissions, so full indexes are still needed for the foreign keys.

BEGIN;

CREATE INDEX IF NOT EXISTS idx_staff_department        ON staff(department_id);

CREATE INDEX IF NOT EXISTS idx_appointment_patient     ON appointment(patient_id);
-- Hot path: a doctor's day list. Also serves the doctor_id foreign key.
CREATE INDEX IF NOT EXISTS idx_appointment_doctor_date ON appointment(doctor_id, scheduled_for);

CREATE INDEX IF NOT EXISTS idx_diagnosis_appointment   ON diagnosis(appointment_id);

CREATE INDEX IF NOT EXISTS idx_prescription_medication ON prescription(medication_id);

CREATE INDEX IF NOT EXISTS idx_lab_order_patient       ON lab_order(patient_id);
CREATE INDEX IF NOT EXISTS idx_lab_order_test          ON lab_order(lab_test_id);
CREATE INDEX IF NOT EXISTS idx_lab_order_ordered_by    ON lab_order(ordered_by);

CREATE INDEX IF NOT EXISTS idx_lab_result_recorded_by  ON lab_result(recorded_by);

CREATE INDEX IF NOT EXISTS idx_ward_department         ON ward(department_id);

CREATE INDEX IF NOT EXISTS idx_admission_patient       ON admission(patient_id);
CREATE INDEX IF NOT EXISTS idx_admission_ward          ON admission(ward_id);

CREATE INDEX IF NOT EXISTS idx_invoice_patient         ON invoice(patient_id);
CREATE INDEX IF NOT EXISTS idx_invoice_item_invoice    ON invoice_item(invoice_id);
CREATE INDEX IF NOT EXISTS idx_payment_invoice         ON payment(invoice_id);

-- Look up the history of one row: WHERE table_name = 'admission' AND row_id = 7
CREATE INDEX IF NOT EXISTS idx_audit_log_row           ON audit_log(table_name, row_id);

COMMIT;
