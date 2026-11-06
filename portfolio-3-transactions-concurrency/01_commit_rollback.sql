-- MIVA Teaching Hospital - COMMIT, ROLLBACK and SAVEPOINT
--
-- Single-session script. Run with psql (it uses \gset to carry ids between
-- statements):
--   docker exec -i hospital_pg psql -U hospital_admin -d hospital_db -X -e \
--     -f /workspace/portfolio-3-transactions-concurrency/01_commit_rollback.sql
--
-- In DBeaver: switch the editor to Manual Commit mode, replace :invoice_id
-- with a real unpaid invoice id, and run one statement at a time (Ctrl+Enter).

\set ON_ERROR_STOP off

-- ===========================================================================
-- Scenario 1: a cashier takes a full payment -> COMMIT
-- The INSERT fires trg_payment_apply, which locks the invoice row and marks it
-- paid. Both changes become visible together, or not at all.
-- ===========================================================================

SELECT invoice_id, total_amount, status
FROM invoice
WHERE status = 'unpaid'
ORDER BY invoice_id
LIMIT 1 \gset

\echo '--- 1a. Before: the invoice is unpaid'
SELECT invoice_id, total_amount, status FROM invoice WHERE invoice_id = :invoice_id;

BEGIN;
INSERT INTO payment (invoice_id, amount, method)
VALUES (:invoice_id, :total_amount, 'transfer')
RETURNING payment_id, invoice_id, amount, method;

INSERT INTO audit_log (table_name, row_id, action, new_data)
VALUES ('invoice', :invoice_id, 'payment', jsonb_build_object('amount', :total_amount, 'method', 'transfer'));
COMMIT;

\echo '--- 1b. After COMMIT: payment stored, invoice paid, audit row written'
SELECT invoice_id, total_amount, status FROM invoice WHERE invoice_id = :invoice_id;
SELECT count(*) AS payments_for_invoice FROM payment WHERE invoice_id = :invoice_id;
SELECT table_name, row_id, action, new_data FROM audit_log
WHERE table_name = 'invoice' AND row_id = :invoice_id;

-- ===========================================================================
-- Scenario 2: a pharmacist dispenses more Tramadol than is in stock -> ROLLBACK
-- The audit row is written first, then the stock update violates
-- CHECK (stock_quantity >= 0). The whole transaction is aborted, so the audit
-- row is never stored either: no record of a dispense that did not happen.
-- ===========================================================================

\echo '--- 2a. Before: Tramadol stock'
SELECT medication_id, name, stock_quantity FROM medication WHERE name = 'Tramadol 50mg';
SELECT count(*) AS dispense_audit_rows FROM audit_log WHERE action = 'dispense';

BEGIN;
INSERT INTO audit_log (table_name, row_id, action, new_data)
SELECT 'medication', medication_id, 'dispense', jsonb_build_object('quantity', 10)
FROM medication WHERE name = 'Tramadol 50mg';

UPDATE medication
SET stock_quantity = stock_quantity - 10
WHERE name = 'Tramadol 50mg';

-- Any statement in an aborted transaction is refused:
SELECT 'this will not run' AS note;
ROLLBACK;

\echo '--- 2b. After ROLLBACK: stock unchanged, no audit row'
SELECT medication_id, name, stock_quantity FROM medication WHERE name = 'Tramadol 50mg';
SELECT count(*) AS dispense_audit_rows FROM audit_log WHERE action = 'dispense';

-- ===========================================================================
-- Scenario 3: SAVEPOINT - keep the good part of a transaction
-- A billing officer adds a consultation fee and then a lab charge with a
-- typo (negative amount). Rolling back to the savepoint discards only the
-- bad line; the consultation fee is committed.
-- ===========================================================================

\echo '--- 3a. Before: a fresh invoice for patient 3'
BEGIN;
INSERT INTO invoice (patient_id) VALUES (3) RETURNING invoice_id AS new_invoice_id \gset

INSERT INTO invoice_item (invoice_id, description, item_type, amount)
VALUES (:new_invoice_id, 'Consultation - General Medicine', 'consultation', 10000);

SAVEPOINT before_lab_charge;

INSERT INTO invoice_item (invoice_id, description, item_type, amount)
VALUES (:new_invoice_id, 'Lab - Full Blood Count', 'lab_test', -6000);

ROLLBACK TO SAVEPOINT before_lab_charge;

INSERT INTO invoice_item (invoice_id, description, item_type, amount)
VALUES (:new_invoice_id, 'Lab - Full Blood Count', 'lab_test', 6000);
COMMIT;

\echo '--- 3b. After COMMIT: two valid lines, total maintained by the trigger'
SELECT invoice_id, total_amount, status FROM invoice WHERE invoice_id = :new_invoice_id;
SELECT description, item_type, amount FROM invoice_item WHERE invoice_id = :new_invoice_id ORDER BY invoice_item_id;

-- ===========================================================================
-- Scenario 4: atomicity across a failed overpayment
-- Two payment rows in one transaction; the second takes the invoice over its
-- total, so the trigger raises and the first payment is rolled back too.
-- ===========================================================================

\echo '--- 4a. Before'
SELECT invoice_id, total_amount, status,
       (SELECT COALESCE(sum(amount), 0) FROM payment p WHERE p.invoice_id = i.invoice_id) AS paid
FROM invoice i WHERE invoice_id = :new_invoice_id;

BEGIN;
INSERT INTO payment (invoice_id, amount, method) VALUES (:new_invoice_id, 10000, 'cash');
INSERT INTO payment (invoice_id, amount, method) VALUES (:new_invoice_id, 10000, 'card');
COMMIT;

\echo '--- 4b. After: COMMIT on an aborted transaction is a ROLLBACK; nothing was paid'
SELECT invoice_id, total_amount, status,
       (SELECT COALESCE(sum(amount), 0) FROM payment p WHERE p.invoice_id = i.invoice_id) AS paid
FROM invoice i WHERE invoice_id = :new_invoice_id;
