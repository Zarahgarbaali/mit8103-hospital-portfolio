# MongoDB Document Model - MIVA Teaching Hospital

Database: `hospital` on the `hospital_mongo` container (MongoDB 7).

The relational model (Portfolio 1) spreads one patient's chart across `patient`, `appointment`, `diagnosis`, `prescription`, `lab_order` and `lab_result`. Opening a chart there means a six-table join. In MongoDB, the chart is modelled the way doctors actually read it: one document per patient, with visits embedded.

Patients keep the same `patient_id`, names, dates of birth and phone numbers as in PostgreSQL, so the two models describe the same hospital.

## Collection 1: `patient_records`

One document per patient. Visits, diagnoses and prescriptions are **embedded**, because they are always read with the patient, belong to exactly one patient, and are never queried without the patient.

```json
{
  "_id": "ObjectId(...)",
  "patient_id": 1,
  "full_name": "Amina Eze",
  "dob": "ISODate('2000-11-07')",
  "gender": "F",
  "blood_group": "A+",
  "contact": { "phone": "+2348010104729", "address": "Plot 14, Asokoro, Abuja" },
  "allergies": ["penicillin", "sulfonamides"],
  "chronic_conditions": ["asthma"],
  "insurance": { "provider": "NHIA", "member_no": "NHIA-0000001" },
  "visits": [
    {
      "visit_id": "v-1-01",
      "date": "ISODate('2026-10-04T09:30:00Z')",
      "doctor": { "staff_id": 1, "name": "Dr. Chinedu Okafor", "department": "General Medicine" },
      "reason": "Fever and headache",
      "vitals": { "bp": "128/82", "temp_c": 38.4, "pulse": 96, "weight_kg": 64 },
      "diagnosis": { "icd": "B54", "notes": "Uncomplicated malaria, MP positive" },
      "prescriptions": [
        { "drug": "Artemether/Lumefantrine 80/480mg", "dosage": "1 tablet twice daily", "duration_days": 3 },
        { "drug": "Paracetamol 500mg", "dosage": "1g three times daily", "duration_days": 3 }
      ]
    }
  ],
  "created_at": "ISODate(...)",
  "updated_at": "ISODate(...)"
}
```

Design notes:

- **Embedding (one-to-few).** A patient has a handful of visits a year. Embedding them keeps the whole chart in one document, read in one round trip and written atomically (a single-document update in MongoDB is atomic).
- **Extended reference for the doctor.** `visits.doctor` copies `staff_id`, name and department instead of only storing an id. The chart can then be displayed without a second lookup. The cost is that a doctor's name change would need a multi-document update. That is acceptable because staff names almost never change, and old visits *should* show the department the doctor had at the time.
- **Flexible fields.** Not every patient has `insurance` or `emergency_contact`. Paediatric visits add `vitals.head_circumference_cm`, and antenatal visits add `vitals.gestational_age_weeks`. In PostgreSQL these would be nullable columns or extra tables. Here they are simply present when relevant.
- **Arrays for multi-valued attributes.** `allergies` and `chronic_conditions` are arrays, which would violate 1NF in the relational model. A multikey index makes "every patient allergic to penicillin" a single index lookup.
- **Real dates.** Dates are stored as BSON `Date`, not strings, so range queries and `$gte` comparisons work correctly.
- **Growth bound.** MongoDB documents are capped at 16 MB. A visit is about 0.5 kB, so a patient would need tens of thousands of visits to reach the cap. A long-stay inpatient's hourly observations, by contrast, would go in a separate collection (the bucket pattern), not into this array.

### Validation

`seed.js` creates the collection with a `$jsonSchema` validator. `patient_id`, `full_name`, `dob`, `gender` and `visits` are required, `gender` must be `M` or `F`, and every visit must have a `visit_id`, `date` and `doctor`. MongoDB is schema-flexible, not schema-less: the core of the record is still enforced.

## Collection 2: `lab_results`

One document per test. Lab results are **referenced** (by `patient_id`), not embedded, because:

- they are written by a different team (the lab) at a different time from the consultation,
- they are queried across patients ("average haemoglobin this month"), not just per patient,
- some tests produce large or many-valued results, which would bloat the chart document.

The `results` and `reference_ranges` sub-documents have a **different shape for each test type**. This is where the document model pays off most: in PostgreSQL, `lab_result.result_value` had to be a single text column.

```json
{ "patient_id": 1, "test_type": "full_blood_count", "ordered_by": "Dr. Chinedu Okafor",
  "ordered_at": "ISODate(...)", "status": "complete",
  "results": { "wbc": 6.8, "rbc": 4.9, "hb": 14.2, "platelets": 250 },
  "reference_ranges": { "wbc": "4.0-11.0", "rbc": "4.2-5.9", "hb": "12.0-17.5", "platelets": "150-400" } }

{ "patient_id": 2, "test_type": "malaria_parasite", "ordered_by": "Dr. Fatima Bello",
  "ordered_at": "ISODate(...)", "status": "complete",
  "results": { "mp": "positive", "species": "P. falciparum", "parasite_density_per_ul": 4200 } }

{ "patient_id": 7, "test_type": "lipid_profile", "ordered_by": "Dr. Ibrahim Musa",
  "ordered_at": "ISODate(...)", "status": "complete",
  "results": { "total_cholesterol": 5.9, "hdl": 1.1, "ldl": 3.9, "triglycerides": 1.8 },
  "reference_ranges": { "total_cholesterol": "<5.2", "hdl": ">1.0", "ldl": "<3.4", "triglycerides": "<1.7" } }
```

Tests that are still pending have `status: "pending"` and no `results` field at all.

## Indexes (`indexes.js`)

| Index | Serves |
|---|---|
| `patient_records { patient_id: 1 }` unique | Q1, Q2 and the `$lookup` in Q6. Also enforces one chart per patient |
| `patient_records { "visits.date": -1 }` | "recent visits" queries (multikey) |
| `patient_records { allergies: 1 }` | Q3 (multikey) |
| `lab_results { patient_id: 1, ordered_at: -1 }` | a patient's latest results, and Q6 |
| `lab_results { test_type: 1 }` | Q5 |

## Mapping from the relational model

| PostgreSQL (Portfolio 1) | MongoDB |
|---|---|
| `patient` row | `patient_records` document (top level) |
| `appointment` + `diagnosis` | `visits[]` element with an embedded `diagnosis` |
| `prescription` | `visits[].prescriptions[]` |
| `staff` (doctor) | `visits[].doctor` extended reference |
| `lab_order` + `lab_result` | `lab_results` document with a variable `results` shape |
| no equivalent | `allergies[]`, `chronic_conditions[]`, `insurance`, `emergency_contact` |
| `invoice`, `invoice_item`, `payment` | **not moved**: billing stays relational (see `suitability.md`) |
