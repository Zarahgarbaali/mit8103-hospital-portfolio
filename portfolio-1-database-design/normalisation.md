# Normalisation - MIVA Teaching Hospital

The schema in `schema.sql` is in Boyce-Codd Normal Form (BCNF), with two deliberate, controlled exceptions listed at the end. This page explains how each normal form is satisfied.

## Starting point: the paper clinic card

Before the database, a consultation at the hospital was recorded on one card, roughly:

| Card no. | Patient | Phone | Doctor | Department | Date | Diagnosis | Drugs |
|---|---|---|---|---|---|---|---|
| 0042 | Amina Eze | 0801... | Dr. Okafor | General Medicine | 04/10 | B54 Malaria | Artemether/Lumefantrine, Paracetamol |

This card has every classic anomaly:

- **Update anomaly:** if Amina changes her phone number, every card she has ever had must be edited.
- **Insert anomaly:** a new drug cannot be recorded until someone is prescribed it.
- **Delete anomaly:** throwing away the last card for a doctor loses the fact that the doctor works in General Medicine.

The 16 tables remove these anomalies step by step.

## First Normal Form (1NF): atomic values, no repeating groups

- Every column holds a single value. The "Drugs" list on the card becomes one `prescription` row per drug, linked to the `diagnosis`.
- The patient's name is split into `first_name` and `last_name`, so searching by surname needs no string parsing.
- There are no comma-separated lists anywhere in the schema. The one place where a free-form structure is needed, the before and after image of a changed row, uses `audit_log.old_data` / `new_data` as `JSONB`. This is an audit snapshot that is never queried as a relational attribute, so it does not break 1NF for the operational data.
- Every table has a primary key, so every row is uniquely identifiable.

## Second Normal Form (2NF): no partial dependencies

2NF only matters when a table has a composite key: a non-key column must depend on the whole key, not part of it.

- Every table uses a single-column surrogate primary key (`patient_id`, `appointment_id`, and so on), so a partial dependency on "part of the key" cannot exist.
- The one natural composite key is `(diagnosis_id, medication_id)` on `prescription` (declared `UNIQUE`). The non-key columns `dosage`, `duration_days` and `issued_at` describe that specific drug for that specific diagnosis, so they depend on the full pair. The drug's `unit_price` and `manufacturer` depend only on `medication_id`, which is why they live in `medication` and not in `prescription`.

## Third Normal Form (3NF): no transitive dependencies

A non-key column must depend on the key and nothing but the key.

- `staff` stores `department_id`, not the department name or location. If it stored `department_name`, then `staff_id -> department_id -> department_name` would be a transitive dependency, and renaming a department would mean updating every staff row.
- `appointment` stores `doctor_id` only. The doctor's department is reached through `staff`, not copied onto the appointment.
- `ward` stores `department_id`. The ward's location is derived from its department.
- `lab_result` does not repeat the test name or the patient. It points to its `lab_order`, which in turn points to `lab_test` and `patient`.
- The standard price of a test lives in `lab_test.standard_cost`. The amount actually billed is stored separately in `invoice_item.amount`, because it is a fact about the invoice at the time it was raised (prices change, and old invoices must not).

## Boyce-Codd Normal Form (BCNF): every determinant is a candidate key

BCNF is stricter than 3NF: for every functional dependency `X -> Y`, `X` must be a candidate key. Two tables are worth walking through because they carry the most clinical meaning.

### `prescription`

Columns: `prescription_id, diagnosis_id, medication_id, dosage, duration_days, issued_at`

Functional dependencies:

1. `prescription_id -> diagnosis_id, medication_id, dosage, duration_days, issued_at`
2. `(diagnosis_id, medication_id) -> prescription_id, dosage, duration_days, issued_at` (enforced by the `prescription_one_drug_per_diagnosis` unique constraint)

Both determinants, `prescription_id` and `(diagnosis_id, medication_id)`, are candidate keys. Is there a hidden dependency such as `medication_id -> dosage`? No. Paracetamol is "1g three times daily" for a cold but "1g as needed" for back pain, so dosage depends on the diagnosis-drug pair, not on the drug alone. The table is in BCNF.

### `appointment`

Columns: `appointment_id, patient_id, doctor_id, scheduled_for, status, reason, created_at`

Functional dependencies:

1. `appointment_id -> patient_id, doctor_id, scheduled_for, status, reason, created_at`

Possible extra dependencies, and why they don't hold:

- `(doctor_id, scheduled_for) -> patient_id`? In a strict one-patient-per-slot clinic this could be true, and then `(doctor_id, scheduled_for)` would be a second candidate key, which still satisfies BCNF. In this hospital a doctor can see an emergency patient at the same time as a booked one, so it is not enforced, and the only determinant remains the primary key.
- `doctor_id -> department`? This dependency is real, which is exactly why the department is not stored on `appointment`. It lives on `staff`.

The table is in BCNF.

### Other tables

Every other table has a single determinant (its surrogate key) plus the `UNIQUE` natural keys (`patient.phone`, `staff.email`, `staff.phone`, `medication.name`, `lab_test.name`, `ward.name`, `department.name`, `lab_result.lab_order_id`). Each of these is itself a candidate key, so BCNF holds.

## Deliberate, controlled exceptions

| Where | What | Why it is acceptable |
|---|---|---|
| `invoice.total_amount` | A derived value (sum of `invoice_item.amount`) | Billing reports and the "outstanding balance" query read it constantly. The `trg_invoice_item_total` trigger recalculates it on every item insert, update or delete, so it cannot drift. `constraint_tests.sql` test T12 shows this. |
| `invoice_item.reference_id` | A polymorphic reference: an appointment, prescription, lab order or admission depending on `item_type` | One item table keeps invoices simple. The cost is that this column cannot have a single foreign key. The alternative is four nullable foreign key columns with a CHECK that exactly one is set. That would be stricter, but it was judged unnecessary here because invoice items are created by the billing process, not typed by hand. |

Business rules that cannot be expressed as column constraints are enforced with triggers: an appointment's `doctor_id` must point at a doctor, `lab_result.recorded_by` must be a lab technician, a bed must exist in its ward, and payments cannot exceed the invoice total.
