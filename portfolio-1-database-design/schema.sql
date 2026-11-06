-- MIVA Teaching Hospital - relational schema (PostgreSQL 16)
--
-- Run from the repo root:
--   docker exec -i hospital_pg psql -U hospital_admin -d hospital_db \
--     -v ON_ERROR_STOP=1 -f /workspace/portfolio-1-database-design/schema.sql
--
-- Design rules:
--   * BIGSERIAL keys on high-volume tables, SERIAL on small lookup tables
--   * TIMESTAMPTZ on every time column (the hospital runs 24/7)
--   * ON DELETE RESTRICT on anything that points at a patient or a clinical
--     record, so medical history can never be lost by a cascading delete
--   * ON DELETE CASCADE only on invoice_item, which has no meaning without
--     its invoice

SET client_min_messages = warning;

BEGIN;

DROP TABLE IF EXISTS audit_log, payment, invoice_item, invoice, admission, ward,
    lab_result, lab_order, lab_test, prescription, medication, diagnosis,
    appointment, staff, department, patient CASCADE;
DROP FUNCTION IF EXISTS check_staff_role() CASCADE;
DROP FUNCTION IF EXISTS check_bed_in_ward() CASCADE;
DROP FUNCTION IF EXISTS refresh_invoice_total() CASCADE;
DROP FUNCTION IF EXISTS apply_payment() CASCADE;

-- ---------------------------------------------------------------------------
-- People and organisation
-- ---------------------------------------------------------------------------

CREATE TABLE patient (
    patient_id     BIGSERIAL PRIMARY KEY,
    first_name     VARCHAR(50)  NOT NULL,
    last_name      VARCHAR(50)  NOT NULL,
    dob            DATE         NOT NULL CHECK (dob > DATE '1900-01-01'),
    gender         CHAR(1)      NOT NULL CHECK (gender IN ('M', 'F')),
    phone          VARCHAR(20)  NOT NULL UNIQUE,
    address        TEXT,
    blood_group    VARCHAR(3)
                   CHECK (blood_group IN ('A+','A-','B+','B-','AB+','AB-','O+','O-')),
    registered_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE TABLE department (
    department_id  SERIAL PRIMARY KEY,
    name           VARCHAR(80)  NOT NULL UNIQUE,
    location       VARCHAR(120)
);

CREATE TABLE staff (
    staff_id       BIGSERIAL PRIMARY KEY,
    first_name     VARCHAR(50)  NOT NULL,
    last_name      VARCHAR(50)  NOT NULL,
    role           VARCHAR(20)  NOT NULL
                   CHECK (role IN ('doctor','nurse','lab_technician','pharmacist',
                                   'receptionist','billing_officer','administrator')),
    department_id  INT          NOT NULL REFERENCES department(department_id) ON DELETE RESTRICT,
    phone          VARCHAR(20)  NOT NULL UNIQUE,
    email          VARCHAR(120) NOT NULL UNIQUE CHECK (email LIKE '%_@_%._%'),
    hired_at       TIMESTAMPTZ  NOT NULL
);

-- ---------------------------------------------------------------------------
-- Outpatient care: appointments, diagnoses, prescriptions
-- ---------------------------------------------------------------------------

CREATE TABLE appointment (
    appointment_id   BIGSERIAL PRIMARY KEY,
    patient_id       BIGINT NOT NULL REFERENCES patient(patient_id) ON DELETE RESTRICT,
    doctor_id        BIGINT NOT NULL REFERENCES staff(staff_id) ON DELETE RESTRICT,
    scheduled_for    TIMESTAMPTZ NOT NULL,
    status           VARCHAR(20) NOT NULL DEFAULT 'booked'
                     CHECK (status IN ('booked','completed','cancelled','no_show')),
    reason           TEXT,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT appointment_future_ok CHECK (scheduled_for > '2000-01-01')
);

CREATE TABLE diagnosis (
    diagnosis_id     BIGSERIAL PRIMARY KEY,
    appointment_id   BIGINT NOT NULL REFERENCES appointment(appointment_id) ON DELETE RESTRICT,
    icd_code         VARCHAR(10) NOT NULL
                     CHECK (icd_code ~ '^[A-Z][0-9]{2}(\.[0-9A-Z]{1,4})?$'),
    notes            TEXT,
    recorded_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE medication (
    medication_id    SERIAL PRIMARY KEY,
    name             VARCHAR(100) NOT NULL UNIQUE,
    manufacturer     VARCHAR(100),
    unit_price       NUMERIC(10,2) NOT NULL CHECK (unit_price >= 0),
    stock_quantity   INT NOT NULL DEFAULT 0 CHECK (stock_quantity >= 0),
    reorder_level    INT NOT NULL DEFAULT 0 CHECK (reorder_level >= 0)
);

CREATE TABLE prescription (
    prescription_id  BIGSERIAL PRIMARY KEY,
    diagnosis_id     BIGINT NOT NULL REFERENCES diagnosis(diagnosis_id) ON DELETE RESTRICT,
    medication_id    INT    NOT NULL REFERENCES medication(medication_id) ON DELETE RESTRICT,
    dosage           VARCHAR(60) NOT NULL,
    duration_days    INT NOT NULL CHECK (duration_days BETWEEN 1 AND 365),
    issued_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT prescription_one_drug_per_diagnosis UNIQUE (diagnosis_id, medication_id)
);

-- ---------------------------------------------------------------------------
-- Laboratory
-- ---------------------------------------------------------------------------

CREATE TABLE lab_test (
    lab_test_id      SERIAL PRIMARY KEY,
    name             VARCHAR(100) NOT NULL UNIQUE,
    standard_cost    NUMERIC(10,2) NOT NULL CHECK (standard_cost >= 0)
);

CREATE TABLE lab_order (
    lab_order_id     BIGSERIAL PRIMARY KEY,
    patient_id       BIGINT NOT NULL REFERENCES patient(patient_id) ON DELETE RESTRICT,
    lab_test_id      INT    NOT NULL REFERENCES lab_test(lab_test_id) ON DELETE RESTRICT,
    ordered_by       BIGINT NOT NULL REFERENCES staff(staff_id) ON DELETE RESTRICT,
    ordered_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    status           VARCHAR(20) NOT NULL DEFAULT 'pending'
                     CHECK (status IN ('pending','in_progress','completed','cancelled'))
);

CREATE TABLE lab_result (
    lab_result_id    BIGSERIAL PRIMARY KEY,
    lab_order_id     BIGINT NOT NULL UNIQUE REFERENCES lab_order(lab_order_id) ON DELETE RESTRICT,
    result_value     TEXT   NOT NULL,
    reference_range  VARCHAR(60),
    recorded_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    recorded_by      BIGINT NOT NULL REFERENCES staff(staff_id) ON DELETE RESTRICT
);

-- ---------------------------------------------------------------------------
-- Inpatient care
-- ---------------------------------------------------------------------------

CREATE TABLE ward (
    ward_id          SERIAL PRIMARY KEY,
    name             VARCHAR(80) NOT NULL UNIQUE,
    department_id    INT NOT NULL REFERENCES department(department_id) ON DELETE RESTRICT,
    total_beds       INT NOT NULL CHECK (total_beds > 0)
);

CREATE TABLE admission (
    admission_id     BIGSERIAL PRIMARY KEY,
    patient_id       BIGINT NOT NULL REFERENCES patient(patient_id) ON DELETE RESTRICT,
    ward_id          INT    NOT NULL REFERENCES ward(ward_id) ON DELETE RESTRICT,
    bed_number       INT    NOT NULL CHECK (bed_number > 0),
    admitted_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    discharged_at    TIMESTAMPTZ,
    CONSTRAINT admission_discharge_after_admit
        CHECK (discharged_at IS NULL OR discharged_at >= admitted_at)
);

-- A bed can hold only one current patient, and a patient can only be on one
-- bed at a time. Both rules apply to open admissions only, so they are
-- partial unique indexes rather than plain UNIQUE constraints.
CREATE UNIQUE INDEX uq_admission_open_bed
    ON admission(ward_id, bed_number) WHERE discharged_at IS NULL;
CREATE UNIQUE INDEX uq_admission_open_patient
    ON admission(patient_id) WHERE discharged_at IS NULL;

-- ---------------------------------------------------------------------------
-- Billing
-- ---------------------------------------------------------------------------

CREATE TABLE invoice (
    invoice_id       BIGSERIAL PRIMARY KEY,
    patient_id       BIGINT NOT NULL REFERENCES patient(patient_id) ON DELETE RESTRICT,
    issued_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    total_amount     NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (total_amount >= 0),
    status           VARCHAR(20) NOT NULL DEFAULT 'unpaid'
                     CHECK (status IN ('unpaid','partially_paid','paid','cancelled'))
);

CREATE TABLE invoice_item (
    invoice_item_id  BIGSERIAL PRIMARY KEY,
    invoice_id       BIGINT NOT NULL REFERENCES invoice(invoice_id) ON DELETE CASCADE,
    description      VARCHAR(200) NOT NULL,
    item_type        VARCHAR(20)  NOT NULL
                     CHECK (item_type IN ('consultation','medication','lab_test','admission')),
    reference_id     BIGINT,
    amount           NUMERIC(12,2) NOT NULL CHECK (amount >= 0)
);

CREATE TABLE payment (
    payment_id       BIGSERIAL PRIMARY KEY,
    invoice_id       BIGINT NOT NULL REFERENCES invoice(invoice_id) ON DELETE RESTRICT,
    amount           NUMERIC(12,2) NOT NULL CHECK (amount > 0),
    method           VARCHAR(20) NOT NULL CHECK (method IN ('cash','card','transfer','hmo')),
    paid_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- Audit
-- ---------------------------------------------------------------------------

CREATE TABLE audit_log (
    audit_id         BIGSERIAL PRIMARY KEY,
    table_name       VARCHAR(60) NOT NULL,
    row_id           BIGINT      NOT NULL,
    action           VARCHAR(30) NOT NULL,
    changed_by       TEXT        NOT NULL DEFAULT current_user,
    changed_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    old_data         JSONB,
    new_data         JSONB
);

-- ---------------------------------------------------------------------------
-- Business rules that a CHECK constraint cannot express
-- ---------------------------------------------------------------------------

-- Usage: check_staff_role('<fk column>', '<required role>')
-- e.g. appointment.doctor_id must point at a doctor, not a nurse.
CREATE FUNCTION check_staff_role() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_staff_id BIGINT := (to_jsonb(NEW) ->> TG_ARGV[0])::BIGINT;
    v_role     TEXT;
BEGIN
    SELECT role INTO v_role FROM staff WHERE staff_id = v_staff_id;
    IF v_role IS DISTINCT FROM TG_ARGV[1] THEN
        RAISE EXCEPTION '%.% must reference a %, staff % is %',
            TG_TABLE_NAME, TG_ARGV[0], TG_ARGV[1], v_staff_id, COALESCE(v_role, 'missing');
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_appointment_doctor_role
    BEFORE INSERT OR UPDATE OF doctor_id ON appointment
    FOR EACH ROW EXECUTE FUNCTION check_staff_role('doctor_id', 'doctor');

CREATE TRIGGER trg_lab_order_doctor_role
    BEFORE INSERT OR UPDATE OF ordered_by ON lab_order
    FOR EACH ROW EXECUTE FUNCTION check_staff_role('ordered_by', 'doctor');

CREATE TRIGGER trg_lab_result_technician_role
    BEFORE INSERT OR UPDATE OF recorded_by ON lab_result
    FOR EACH ROW EXECUTE FUNCTION check_staff_role('recorded_by', 'lab_technician');

-- bed_number must exist in the ward (1..total_beds).
CREATE FUNCTION check_bed_in_ward() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_total INT;
BEGIN
    SELECT total_beds INTO v_total FROM ward WHERE ward_id = NEW.ward_id;
    IF NEW.bed_number > v_total THEN
        RAISE EXCEPTION 'Ward % only has % beds, bed % does not exist',
            NEW.ward_id, v_total, NEW.bed_number;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_admission_bed_in_ward
    BEFORE INSERT OR UPDATE OF ward_id, bed_number ON admission
    FOR EACH ROW EXECUTE FUNCTION check_bed_in_ward();

-- invoice.total_amount is a stored derived value; this keeps it equal to the
-- sum of its items so reports never read a stale total.
CREATE FUNCTION refresh_invoice_total() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        UPDATE invoice
        SET total_amount = (SELECT COALESCE(SUM(amount), 0)
                            FROM invoice_item WHERE invoice_id = NEW.invoice_id)
        WHERE invoice_id = NEW.invoice_id;
    END IF;
    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        UPDATE invoice
        SET total_amount = (SELECT COALESCE(SUM(amount), 0)
                            FROM invoice_item WHERE invoice_id = OLD.invoice_id)
        WHERE invoice_id = OLD.invoice_id;
    END IF;
    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_invoice_item_total
    AFTER INSERT OR UPDATE OR DELETE ON invoice_item
    FOR EACH ROW EXECUTE FUNCTION refresh_invoice_total();

-- A payment may not take an invoice past its total. The invoice row is locked
-- first so two cashiers paying the same invoice are serialised.
CREATE FUNCTION apply_payment() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_total NUMERIC(12,2);
    v_paid  NUMERIC(12,2);
BEGIN
    SELECT total_amount INTO v_total
    FROM invoice WHERE invoice_id = NEW.invoice_id
    FOR UPDATE;

    SELECT COALESCE(SUM(amount), 0) INTO v_paid
    FROM payment WHERE invoice_id = NEW.invoice_id;

    IF v_paid > v_total THEN
        RAISE EXCEPTION 'Payment rejected: invoice % total is %, payments would reach %',
            NEW.invoice_id, v_total, v_paid;
    END IF;

    UPDATE invoice
    SET status = CASE WHEN v_paid = v_total THEN 'paid' ELSE 'partially_paid' END
    WHERE invoice_id = NEW.invoice_id;

    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_payment_apply
    AFTER INSERT ON payment
    FOR EACH ROW EXECUTE FUNCTION apply_payment();

COMMIT;
