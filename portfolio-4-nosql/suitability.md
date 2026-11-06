# Suitability: MongoDB vs PostgreSQL at MIVA Teaching Hospital

The hospital does not need to choose one database. Each part of the system goes where its access pattern and its consistency needs fit best.

## Why documents suit patient records

- **One read opens the whole chart.** A consultation starts with "show me everything about this patient". In PostgreSQL that is a join across `patient`, `appointment`, `diagnosis`, `prescription`, `staff`, `lab_order` and `lab_result`. In MongoDB, Q1 is a single `findOne` on the unique `patient_id` index: 1 key examined, 1 document examined (`evidence/queries_output.txt`).
- **The data is naturally hierarchical.** Patient > visits > diagnosis and prescriptions is a tree, and it is always read top-down from the patient. Embedding stores it the way it is used.
- **Clinical data varies.** Antenatal visits record gestational age, paediatric visits record head circumference, and an FBC has four numeric results while a malaria test has a species and a density. In `lab_results`, each `test_type` has its own `results` shape (the bonus query lists them). Relationally, this forces a choice between one text column (as `lab_result.result_value` is in Portfolio 1), many nullable columns, or an entity-attribute-value table. All three are awkward to query.
- **Atomic updates still exist where they matter.** Recording a visit is one `$push` on one document (Q2). MongoDB guarantees single-document atomicity, so the chart can never hold half a visit.
- **Schema is still enforced where it matters.** The `$jsonSchema` validator rejected a record with no date of birth and an invalid gender (`evidence/seed_output.txt`, error code 121).

## Why relational still wins for billing

- **Money needs multi-row ACID guarantees.** A payment touches `payment`, `invoice.status` and `audit_log` together. Portfolio 3 shows PostgreSQL rolling all of them back on an overpayment, and serialising two cashiers with a row lock. MongoDB has multi-document transactions, but they are an add-on with extra cost and limits. In PostgreSQL this is the default behaviour.
- **Referential integrity.** `invoice_item -> invoice` cascades, `payment -> invoice` is restricted, and a payment can never reference an invoice that does not exist. MongoDB has no foreign keys, so the application would have to enforce all of this.
- **Cross-account aggregation.** "Revenue per department per month" and "the 10 largest outstanding balances" scan many invoices, payments and staff rows together. SQL joins, window functions and materialised views (Portfolio 2) are built for this. In MongoDB, the same reports need `$lookup` chains across collections.
- **Auditors expect it.** Financial records with fixed columns, constraints and an append-only audit log are easier to defend in a financial audit or a data-protection review (NDPA 2023) than free-form documents.

## When to reach for each

| Use PostgreSQL when... | Use MongoDB when... |
|---|---|
| several entities must change together, all or nothing (billing, dispensing stock, bed allocation) | one aggregate (a patient chart) is read and written as a unit |
| rules span tables (foreign keys, a payment can't exceed the invoice total, a bed can hold one current patient) | the structure varies per record (lab results, visit vitals) |
| reporting joins many entities (revenue, occupancy, workload) | reads are mostly "get everything about X by its id" |
| the schema is stable and well understood | the schema is still evolving, or new test types arrive often |

At MIVA Teaching Hospital, scheduling, beds, pharmacy stock and billing stay in PostgreSQL. The patient chart and lab results live in MongoDB, linked by `patient_id`. The cost of this split is that the two stores must be kept in step (for example, a patient's phone number exists in both). In production, that would be handled by making PostgreSQL the system of record for demographics and propagating changes to MongoDB through change data capture, rather than writing to both stores from the application.
