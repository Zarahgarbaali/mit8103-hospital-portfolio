-- MIVA Teaching Hospital - discharge_patient stored procedure
--
--   docker exec -i hospital_pg psql -U hospital_admin -d hospital_db -X -e \
--     -f /workspace/portfolio-3-transactions-concurrency/05_discharge_procedure.sql
--
-- Discharging is two writes that must succeed or fail together: close the
-- admission (frees the bed) and record who did it in audit_log. Putting both
-- in one procedure means every caller gets the same rules and the same audit
-- trail, and a failure in either step rolls back both.

\set ON_ERROR_STOP off

CREATE OR REPLACE PROCEDURE discharge_patient(p_admission_id BIGINT)
LANGUAGE plpgsql AS $$
DECLARE
    v_old admission%ROWTYPE;
    v_new admission%ROWTYPE;
BEGIN
    -- Lock the row first: if two nurses discharge the same patient at the
    -- same time, the second waits here and then sees discharged_at is set.
    SELECT * INTO v_old
    FROM admission
    WHERE admission_id = p_admission_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Admission % not found', p_admission_id
            USING ERRCODE = 'no_data_found';
    END IF;

    IF v_old.discharged_at IS NOT NULL THEN
        RAISE EXCEPTION 'Admission % already discharged at %', p_admission_id, v_old.discharged_at
            USING ERRCODE = 'check_violation';
    END IF;

    UPDATE admission
    SET discharged_at = now()
    WHERE admission_id = p_admission_id
    RETURNING * INTO v_new;

    INSERT INTO audit_log (table_name, row_id, action, changed_by, changed_at, old_data, new_data)
    VALUES ('admission', p_admission_id, 'discharge', current_user, now(),
            to_jsonb(v_old), to_jsonb(v_new));
END;
$$;

-- ---------------------------------------------------------------------------
-- Demo
-- ---------------------------------------------------------------------------

\echo '--- 1. Ward occupancy before'
SELECT w.name, w.total_beds, count(a.admission_id) AS occupied
FROM ward w LEFT JOIN admission a ON a.ward_id = w.ward_id AND a.discharged_at IS NULL
GROUP BY w.ward_id, w.name, w.total_beds ORDER BY w.ward_id;

-- Pick the longest-staying open admission
SELECT admission_id AS adm_id
FROM admission WHERE discharged_at IS NULL
ORDER BY admitted_at LIMIT 1 \gset

SELECT a.admission_id, p.first_name || ' ' || p.last_name AS patient, w.name AS ward,
       a.bed_number, a.admitted_at, a.discharged_at
FROM admission a JOIN patient p USING (patient_id) JOIN ward w USING (ward_id)
WHERE a.admission_id = :adm_id;

\echo '--- 2. Discharge succeeds'
CALL discharge_patient(:adm_id);

SELECT admission_id, bed_number, admitted_at, discharged_at
FROM admission WHERE admission_id = :adm_id;

SELECT audit_id, table_name, row_id, action, changed_by, changed_at,
       old_data ->> 'discharged_at' AS old_discharged_at,
       new_data ->> 'discharged_at' AS new_discharged_at
FROM audit_log WHERE table_name = 'admission' AND row_id = :adm_id;

\echo '--- 3. Discharging the same admission again is refused'
CALL discharge_patient(:adm_id);

\echo '--- 4. An admission that does not exist is refused'
CALL discharge_patient(999999999);

\echo '--- 5. Inside a caller transaction that rolls back, the discharge and its audit row both disappear'
SELECT admission_id AS adm2_id
FROM admission WHERE discharged_at IS NULL
ORDER BY admitted_at LIMIT 1 \gset
BEGIN;
CALL discharge_patient(:adm2_id);
SELECT admission_id, discharged_at IS NOT NULL AS discharged_inside_txn
FROM admission WHERE admission_id = :adm2_id;
ROLLBACK;
SELECT admission_id, discharged_at IS NOT NULL AS discharged_after_rollback,
       (SELECT count(*) FROM audit_log WHERE table_name = 'admission' AND row_id = :adm2_id) AS audit_rows
FROM admission WHERE admission_id = :adm2_id;

\echo '--- 6. Ward occupancy after: one bed freed'
SELECT w.name, w.total_beds, count(a.admission_id) AS occupied
FROM ward w LEFT JOIN admission a ON a.ward_id = w.ward_id AND a.discharged_at IS NULL
GROUP BY w.ward_id, w.name, w.total_beds ORDER BY w.ward_id;
