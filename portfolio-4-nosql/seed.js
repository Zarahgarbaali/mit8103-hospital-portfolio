// MIVA Teaching Hospital - MongoDB seed
//
// Run from the repo root:
//   docker exec hospital_mongo mongosh -u hospital_admin -p hospital_pass \
//     --authenticationDatabase admin --quiet hospital /workspace/portfolio-4-nosql/seed.js
//
// Creates patient_records (20 patients, same ids/names/phones as the
// PostgreSQL seed) and lab_results. A seeded PRNG makes every run produce the
// same documents; dates are relative to "now" so 30-day queries return data.

const DAY = 24 * 3600 * 1000;
const now = Date.now();

// mulberry32: tiny deterministic PRNG so the seed is reproducible
let state = 42;
function rand() {
  state |= 0; state = (state + 0x6D2B79F5) | 0;
  let t = Math.imul(state ^ (state >>> 15), 1 | state);
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
}
const pick = (arr) => arr[Math.floor(rand() * arr.length)];
const between = (lo, hi, dp = 1) => Number((lo + rand() * (hi - lo)).toFixed(dp));

// Same 20 patients as portfolio-1 seed.sql (patient_id 1-20)
const patients = [
  [1,  "Amina Eze",           "2000-11-07", "F", "A+", "+2348010104729", "Plot 14, Asokoro, Abuja"],
  [2,  "Chukwuemeka Danladi", "1954-05-28", "M", "O+", "+2348010209458", "Plot 27, Apo, Abuja"],
  [3,  "Folasade Umar",       "1983-08-07", "F", "A+", "+2348010314187", "Plot 40, Utako, Abuja"],
  [4,  "Abubakar Balogun",    "2001-08-09", "M", "B+", "+2348010418916", "Plot 53, Lokogoma, Abuja"],
  [5,  "Chiamaka Mohammed",   "2007-05-21", "F", "O-", "+2348010523645", "Plot 66, Life Camp, Abuja"],
  [6,  "Olumide Adeleke",     "1963-04-15", "M", "O+", "+2348010628374", "Plot 79, Jahi, Abuja"],
  [7,  "Zainab Oyelaran",     "1955-08-14", "F", "O-", "+2348010733103", "Plot 92, Wuse II, Abuja"],
  [8,  "Ikenna Igwe",         "1971-09-16", "M", "A+", "+2348010837832", "Plot 105, Gwarinpa, Abuja"],
  [9,  "Adaeze Ibrahim",      "2016-11-13", "F", "A-", "+2348010942561", "Plot 118, Lugbe, Abuja"],
  [10, "Sadiq Chukwu",        "1974-04-22", "M", "A+", "+2348011047290", "Plot 131, Karu, Abuja"],
  [11, "Halima Uche",         "1964-02-08", "F", "B+", "+2348011152019", "Plot 144, Galadimawa, Abuja"],
  [12, "Babatunde Lawal",     "1976-12-10", "M", "O+", "+2348011256748", "Plot 157, Durumi, Abuja"],
  [13, "Funmilayo Adebayo",   "2008-06-20", "F", "B-", "+2348011361477", "Plot 170, Katampe, Abuja"],
  [14, "Obinna Abdullahi",    "1962-05-24", "M", "O-", "+2348011466206", "Plot 183, Maitama, Abuja"],
  [15, "Nkechi Bello",        "1966-01-20", "F", "B+", "+2348011570935", "Plot 196, Kubwa, Abuja"],
  [16, "Usman Ajayi",         "1951-06-01", "M", "O+", "+2348011675664", "Plot 9, Jabi, Abuja"],
  [17, "Hadiza Okeke",        "1971-07-12", "F", "O+", "+2348011780393", "Plot 22, Nyanya, Abuja"],
  [18, "Adewale Ogunbiyi",    "2014-09-18", "M", "O+", "+2348011885122", "Plot 35, Kado, Abuja"],
  [19, "Temitope Onyeka",     "1993-04-09", "F", "O+", "+2348011989851", "Plot 48, Gudu, Abuja"],
  [20, "Chidi Nnadi",         "1984-06-22", "M", "A-", "+2348012094580", "Plot 61, Garki, Abuja"],
];

// Same doctors as staff_id 1-6 in PostgreSQL
const doctors = [
  { staff_id: 1, name: "Dr. Chinedu Okafor",    department: "General Medicine" },
  { staff_id: 2, name: "Dr. Fatima Bello",      department: "General Medicine" },
  { staff_id: 3, name: "Dr. Oluwaseun Adeyemi", department: "Paediatrics" },
  { staff_id: 4, name: "Dr. Ngozi Eze",         department: "Obstetrics and Gynaecology" },
  { staff_id: 5, name: "Dr. Ibrahim Musa",      department: "Surgery" },
  { staff_id: 6, name: "Dr. Emeka Nwosu",       department: "Surgery" },
];

// Same ICD-10 codes and first-line drugs as the relational seed
const conditions = [
  { icd: "B54",   notes: "Uncomplicated malaria, MP positive", reason: "Fever and headache",
    rx: [["Artemether/Lumefantrine 80/480mg", "1 tablet twice daily", 3], ["Paracetamol 500mg", "1g three times daily", 3]] },
  { icd: "J00",   notes: "Acute nasopharyngitis (common cold)", reason: "Persistent cough",
    rx: [["Paracetamol 500mg", "1g three times daily", 3]] },
  { icd: "I10",   notes: "Essential hypertension", reason: "Blood pressure review",
    rx: [["Amlodipine 5mg", "5mg once daily", 30]] },
  { icd: "E11.9", notes: "Type 2 diabetes without complications", reason: "Diabetes review",
    rx: [["Metformin 500mg", "500mg twice daily", 30]] },
  { icd: "A01.0", notes: "Typhoid fever", reason: "Fever and abdominal pain",
    rx: [["Ciprofloxacin 500mg", "500mg twice daily", 7]] },
  { icd: "K29.7", notes: "Gastritis, unspecified", reason: "Abdominal pain",
    rx: [["Omeprazole 20mg", "20mg once daily before food", 14]] },
  { icd: "N39.0", notes: "Urinary tract infection", reason: "Painful urination",
    rx: [["Nitrofurantoin 100mg", "100mg twice daily", 5]] },
  { icd: "M54.5", notes: "Low back pain", reason: "Back pain",
    rx: [["Diclofenac 50mg", "50mg twice daily after food", 5]] },
];

const allergyOptions = [[], [], ["penicillin"], ["sulfonamides"], ["penicillin", "sulfonamides"],
                        ["nsaids"], ["latex"], [], ["shellfish"], ["penicillin"]];
const chronicOptions = [[], [], ["hypertension"], ["type 2 diabetes"], ["asthma"],
                        ["hypertension", "type 2 diabetes"], ["sickle cell trait"], []];

function ageAt(dobIso) {
  return (now - Date.parse(dobIso)) / (365.25 * DAY);
}

function buildVisit(gender, dob, baseWeight) {
  const age = ageAt(dob);
  let doctor;
  if (age < 16)                          doctor = doctors[2];
  else if (gender === "F" && rand() < 0.3) doctor = doctors[3];
  else                                    doctor = pick([doctors[0], doctors[1], doctors[4], doctors[5]]);

  const cond = pick(conditions);
  const date = new Date(now - Math.floor(rand() * 180) * DAY);
  date.setUTCHours(8 + Math.floor(rand() * 9), [0, 15, 30, 45][Math.floor(rand() * 4)], 0, 0);

  const vitals = {
    bp: `${Math.round(between(105, 160, 0))}/${Math.round(between(65, 100, 0))}`,
    temp_c: between(36.2, 39.2),
    pulse: Math.round(between(60, 110, 0)),
    weight_kg: Number((baseWeight + between(-1.5, 1.5)).toFixed(1)),
  };
  if (age < 5) vitals.head_circumference_cm = between(44, 52);
  if (doctor.staff_id === 4) vitals.gestational_age_weeks = Math.round(between(10, 38, 0));

  return {
    visit_id: null,  // numbered in date order once all of a patient's visits exist
    date,
    doctor,
    reason: doctor.staff_id === 4 ? "Antenatal visit" : cond.reason,
    vitals,
    diagnosis: { icd: cond.icd, notes: cond.notes },
    prescriptions: cond.rx.map(([drug, dosage, duration_days]) => ({ drug, dosage, duration_days })),
  };
}

// ---------------------------------------------------------------------------
// patient_records
// ---------------------------------------------------------------------------

db.patient_records.drop();
db.createCollection("patient_records", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["patient_id", "full_name", "dob", "gender", "visits"],
      properties: {
        patient_id: { bsonType: ["int", "long"], minimum: 1 },
        full_name:  { bsonType: "string", minLength: 2 },
        dob:        { bsonType: "date" },
        gender:     { enum: ["M", "F"] },
        allergies:  { bsonType: "array", items: { bsonType: "string" } },
        visits: {
          bsonType: "array",
          items: {
            bsonType: "object",
            required: ["visit_id", "date", "doctor"],
            properties: { date: { bsonType: "date" } },
          },
        },
      },
    },
  },
  validationAction: "error",
});

const records = patients.map(([id, name, dob, gender, blood, phone, address]) => {
  const visitCount = 1 + Math.floor(rand() * 5);
  const baseWeight = ageAt(dob) < 16 ? between(15, 45) : between(52, 98);
  const visits = [];
  for (let n = 1; n <= visitCount; n++) visits.push(buildVisit(gender, dob, baseWeight));
  visits.sort((a, b) => a.date - b.date);
  visits.forEach((v, i) => { v.visit_id = `v-${id}-${String(i + 1).padStart(2, "0")}`; });

  const doc = {
    patient_id: id,
    full_name: name,
    dob: new Date(dob),
    gender,
    blood_group: blood,
    contact: { phone, address },
    allergies: pick(allergyOptions),
    chronic_conditions: ageAt(dob) < 16 ? [] : pick(chronicOptions),
    visits,
    created_at: new Date(now - (200 + id * 10) * DAY),
    updated_at: visits.length ? visits[visits.length - 1].date : new Date(now),
  };
  if (rand() < 0.5) doc.insurance = { provider: pick(["NHIA", "Hygeia HMO", "AXA Mansard"]), member_no: `M-${String(100000 + id * 37)}` };
  if (ageAt(dob) < 18) doc.emergency_contact = { relationship: "parent", phone: `+234803${String(5000000 + id * 913).padStart(7, "0")}` };
  return doc;
});

// Patient 1 matches the example in schema.md, and guarantees the allergy
// query in queries.js has at least one match.
records[0].allergies = ["penicillin", "sulfonamides"];
records[0].chronic_conditions = ["asthma"];

const res1 = db.patient_records.insertMany(records);
print(`patient_records inserted: ${Object.keys(res1.insertedIds).length}`);

// ---------------------------------------------------------------------------
// lab_results - one document per test, result shape depends on test_type
// ---------------------------------------------------------------------------

db.lab_results.drop();

const labBuilders = {
  full_blood_count: () => ({
    results: { wbc: between(3.5, 12.5), rbc: between(3.8, 5.9), hb: between(9.5, 16.8), platelets: Math.round(between(120, 420, 0)) },
    reference_ranges: { wbc: "4.0-11.0", rbc: "4.2-5.9", hb: "12.0-17.5", platelets: "150-400" },
  }),
  malaria_parasite: () => (rand() < 0.4
    ? { results: { mp: "positive", species: "P. falciparum", parasite_density_per_ul: Math.round(between(800, 9000, 0)) } }
    : { results: { mp: "negative" } }),
  lipid_profile: () => ({
    results: { total_cholesterol: between(3.6, 7.2), hdl: between(0.8, 1.9), ldl: between(1.8, 4.9), triglycerides: between(0.7, 2.6) },
    reference_ranges: { total_cholesterol: "<5.2", hdl: ">1.0", ldl: "<3.4", triglycerides: "<1.7" },
  }),
  fasting_blood_sugar: () => ({
    results: { glucose_mmol_l: between(3.9, 11.5) },
    reference_ranges: { glucose_mmol_l: "3.9-5.6" },
  }),
  urinalysis: () => ({
    results: { protein: pick(["negative", "trace", "1+"]), glucose: pick(["negative", "negative", "1+"]),
               nitrite: pick(["negative", "positive"]), leukocytes: pick(["negative", "trace", "2+"]), ph: between(5, 7.5) },
  }),
};
const testTypes = Object.keys(labBuilders);

const labs = [];
for (const rec of records) {
  const count = 2 + Math.floor(rand() * 2);
  for (let k = 0; k < count; k++) {
    // Every third patient's first test is a recent FBC, so Q5 has data
    const type = (k === 0 && rec.patient_id % 3 === 0) ? "full_blood_count" : pick(testTypes);
    const daysAgo = (k === 0 && rec.patient_id % 3 === 0) ? Math.floor(rand() * 25) : Math.floor(rand() * 120);
    const orderedAt = new Date(now - daysAgo * DAY - Math.floor(rand() * 8) * 3600 * 1000);
    const lastVisit = rec.visits[rec.visits.length - 1];
    const doc = {
      patient_id: rec.patient_id,
      test_type: type,
      ordered_by: lastVisit.doctor.name,
      ordered_at: orderedAt,
      status: "complete",
      ...labBuilders[type](),
    };
    labs.push(doc);
  }
}
// Two tests still waiting in the lab: no results field at all
labs.push({ patient_id: 4, test_type: "lipid_profile", ordered_by: "Dr. Fatima Bello",
            ordered_at: new Date(now - 6 * 3600 * 1000), status: "pending" });
labs.push({ patient_id: 11, test_type: "full_blood_count", ordered_by: "Dr. Chinedu Okafor",
            ordered_at: new Date(now - 2 * 3600 * 1000), status: "pending" });

const res2 = db.lab_results.insertMany(labs);
print(`lab_results inserted: ${Object.keys(res2.insertedIds).length}`);

// ---------------------------------------------------------------------------
// Validation check: a document missing required fields is rejected
// ---------------------------------------------------------------------------
try {
  db.patient_records.insertOne({ patient_id: 999, full_name: "No DOB", gender: "X", visits: [] });
  print("validation: UNEXPECTED - invalid document was accepted");
} catch (e) {
  print(`validation: invalid document rejected (${e.codeName || e.code})`);
}

print(`patients with at least one visit: ${db.patient_records.countDocuments({ "visits.0": { $exists: true } })}`);
print(`total visits: ${db.patient_records.aggregate([{ $project: { n: { $size: "$visits" } } }, { $group: { _id: null, n: { $sum: "$n" } } }]).toArray()[0].n}`);
