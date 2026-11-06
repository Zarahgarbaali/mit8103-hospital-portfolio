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

-- ---------------------------------------------------------------------------
-- Partial indexes: only the rows a hot query actually asks for
-- ---------------------------------------------------------------------------

-- Q5: pending lab orders are ~0.5% of lab_order. The index holds only those
-- rows, so it stays tiny however many completed orders pile up. status is not
-- a key column because the WHERE clause already fixes it to 'pending'.
CREATE INDEX IF NOT EXISTS idx_lab_order_pending
    ON lab_order(ordered_at) WHERE status = 'pending';

-- Q3 and the revenue materialised view: every invoice has exactly one
-- consultation line. As a UNIQUE partial index this both enforces that rule
-- (so revenue can never be double counted) and gives the join a narrow,
-- index-only path from invoice to its appointment.
CREATE UNIQUE INDEX IF NOT EXISTS uq_invoice_item_consultation
    ON invoice_item(invoice_id) INCLUDE (reference_id) WHERE item_type = 'consultation';

-- Q9: only unpaid and partially paid invoices carry a balance (~20% of rows).
CREATE INDEX IF NOT EXISTS idx_invoice_open_balance
    ON invoice(patient_id) INCLUDE (total_amount)
    WHERE status IN ('unpaid', 'partially_paid');

-- Q6 needs no new index: uq_admission_open_bed and uq_admission_open_patient
-- (portfolio-1 schema.sql) are already partial indexes on
-- WHERE discharged_at IS NULL, and the baseline plan uses one of them. A
-- separate (ward_id) WHERE discharged_at IS NULL index would duplicate them.

VACUUM ANALYZE prescription, invoice, invoice_item, appointment, diagnosis, lab_order;
