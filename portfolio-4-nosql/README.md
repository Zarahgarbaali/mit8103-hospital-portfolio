# Portfolio 4 - NoSQL and Advanced Data Models

A document model of **MIVA Teaching Hospital** patient charts and lab results in MongoDB 7. It uses the same patients (ids 1-20, names, phones) and doctors as the PostgreSQL portfolios.

## Files

| File | Purpose |
|---|---|
| `schema.md` | Design of `patient_records` (embedded visits) and `lab_results` (referenced, flexible `results`), with the mapping from the relational model |
| `seed.js` | Creates both collections, a `$jsonSchema` validator, 20 patient charts and about 50 lab results (seeded PRNG, so the data is reproducible) |
| `indexes.js` | Unique, compound and multikey indexes |
| `queries.js` | The 6 queries plus a bonus, with `explain()` summaries |
| `suitability.md` | Why documents suit patient records and why billing stays relational |
| `evidence/` | Output of `seed.js`, `indexes.js` and `queries.js` |
| `screenshots/` | MongoDB Compass views |

## Data model at a glance

```mermaid
flowchart LR
    subgraph patient_records [patient_records document]
        P["patient_id, full_name, dob, gender, blood_group"]
        C["contact: phone, address"]
        AL["allergies array, chronic_conditions array"]
        V["visits array"]
        V --> VD["doctor: staff_id, name, department"]
        V --> VX["vitals: shape varies by visit type"]
        V --> DG["diagnosis: icd, notes"]
        V --> RX["prescriptions array"]
    end
    subgraph lab_results [lab_results document]
        L["patient_id, test_type, ordered_at, status"]
        R["results: shape varies by test_type"]
    end
    L -.->|"patient_id reference"| P
```

## The 6 queries

| # | Query | Technique | Result |
|---|---|---|---|
| 1 | Full chart by `patient_id` | `findOne` | `IXSCAN(uq_patient_id)`: 1 key, 1 document examined |
| 2 | Record a new visit | `$push` + `$set`, atomic single-document update | matched 1, modified 1 |
| 3 | Patients allergic to penicillin | match on an array field | `IXSCAN(idx_allergies)`, multikey: 7 keys, 7 documents, 7 returned |
| 4 | Visits per doctor | `$unwind` + `$group` + `$addToSet` | workload per doctor with distinct patient counts |
| 5 | Average haemoglobin, FBC, last 30 days | `$match` + `$group` with `$avg`, `$min`, `$max`, conditional `$sum` | 10 tests, average 13.38 g/dL, 3 below 12 |
| 6 | Latest lab test per patient with name | `$sort` + `$group $first` + `$lookup` (with a sub-pipeline) | top 10 most recent, including pending tests with no `results` field |
| bonus | Result fields per test type | `$objectToArray` | shows the different `results` shapes in one collection |

## How to run

With `docker/docker-compose.yml` running:

```bash
M="docker exec hospital_mongo mongosh -u hospital_admin -p hospital_pass --authenticationDatabase admin --quiet hospital"

$M /workspace/portfolio-4-nosql/seed.js      # drops and recreates both collections
$M /workspace/portfolio-4-nosql/indexes.js   # run after every seed (drop removes indexes)
$M /workspace/portfolio-4-nosql/queries.js
```

(In zsh, use a function instead of `$M`: `m() { docker exec hospital_mongo mongosh ... hospital "$@"; }`.)

MongoDB Compass connection string: `mongodb://hospital_admin:hospital_pass@localhost:27017/?authSource=admin`, database `hospital`.

## How it was tested

1. `seed.js` inserted 20 patients (57 visits) and 51 lab results. Re-running it gives the same counts, because the PRNG is seeded.
2. The validator rejected an invalid document (missing `dob`, gender `X`) with error 121 (`DocumentValidationFailure`).
3. Every query in `queries.js` ran. Q1 and Q3 `explain("executionStats")` confirm index scans with keys examined = documents returned (`evidence/queries_output.txt`).

## Screenshots

- `screenshots/01_patient_document.png` - one patient document with `visits` expanded
- `screenshots/02_aggregation_avg_hb.png` - Q5 pipeline in the Compass Aggregations tab
- `screenshots/03_indexes.png` - `patient_records` Indexes tab
