-- MIVA Teaching Hospital - optimisation indexes for queries.sql
--
-- Applied on top of the Portfolio 1 foreign key indexes, after bulk_load.sql:
--   docker exec -i hospital_pg psql -U hospital_admin -d hospital_db \
--     -v ON_ERROR_STOP=1 -f /workspace/portfolio-2-query-optimisation/indexes.sql
--
-- Each index names the query it was designed for. See performance_analysis.md
-- for the before/after plans.

-- ---------------------------------------------------------------------------
-- Range indexes on time columns
-- ---------------------------------------------------------------------------

-- Q2: "last 30 days" of prescriptions is ~4% of the table. INCLUDE puts
-- medication_id in the index leaf, so the query never visits the heap.
CREATE INDEX IF NOT EXISTS idx_prescription_issued_at
    ON prescription(issued_at) INCLUDE (medication_id);

-- Q3: month-to-date invoices.
CREATE INDEX IF NOT EXISTS idx_invoice_issued_at
    ON invoice(issued_at);

-- Q4: last 6 months of appointments, grouped by patient. Covering index so
-- the filter and the GROUP BY can be answered from the index alone.
CREATE INDEX IF NOT EXISTS idx_appointment_scheduled_for
    ON appointment(scheduled_for) INCLUDE (patient_id, status);

-- Q7: one ICD code is ~3% of diagnoses.
CREATE INDEX IF NOT EXISTS idx_diagnosis_icd_code
    ON diagnosis(icd_code);


ANALYZE prescription, invoice, appointment, diagnosis;
