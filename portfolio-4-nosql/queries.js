// MIVA Teaching Hospital - MongoDB queries
//   docker exec hospital_mongo mongosh -u hospital_admin -p hospital_pass \
//     --authenticationDatabase admin --quiet hospital /workspace/portfolio-4-nosql/queries.js
//
// Run seed.js and indexes.js first.

const DAY = 24 * 3600 * 1000;

function header(title) {
  print("");
  print("=".repeat(78));
  print(title);
  print("=".repeat(78));
}

// Summarise an explain() plan: winning stage chain, index used, docs examined
function planSummary(explain) {
  const stages = [];
  let s = explain.queryPlanner.winningPlan;
  while (s) {
    stages.push(s.indexName ? `${s.stage}(${s.indexName})` : s.stage);
    s = s.inputStage;
  }
  const ex = explain.executionStats;
  return `plan: ${stages.join(" <- ")} | keys examined: ${ex.totalKeysExamined}, docs examined: ${ex.totalDocsExamined}, returned: ${ex.nReturned}`;
}

// ---------------------------------------------------------------------------
header("Q1. Open a patient's full chart by patient_id (one read, no joins)");
// Business reason: the doctor opens the chart at the start of a consultation.
printjson(db.patient_records.findOne({ patient_id: 1 }, { _id: 0 }));
print(planSummary(db.patient_records.find({ patient_id: 1 }).explain("executionStats")));

// ---------------------------------------------------------------------------
header("Q2. Append a new visit with $push (atomic single-document update)");
// Business reason: Dr. Okafor records today's consultation for patient 1.
// $pull first so the script can be re-run without duplicating the demo visit.
db.patient_records.updateOne({ patient_id: 1 }, { $pull: { visits: { visit_id: "v-1-demo" } } });
const pushResult = db.patient_records.updateOne(
  { patient_id: 1 },
  {
    $push: {
      visits: {
        visit_id: "v-1-demo",
        date: new Date(),
        doctor: { staff_id: 1, name: "Dr. Chinedu Okafor", department: "General Medicine" },
        reason: "Fever and headache",
        vitals: { bp: "122/80", temp_c: 38.9, pulse: 98, weight_kg: 64.0 },
        diagnosis: { icd: "B54", notes: "Uncomplicated malaria, MP positive" },
        prescriptions: [
          { drug: "Artemether/Lumefantrine 80/480mg", dosage: "1 tablet twice daily", duration_days: 3 },
          { drug: "Paracetamol 500mg", dosage: "1g three times daily", duration_days: 3 },
        ],
      },
    },
    $set: { updated_at: new Date() },
  }
);
printjson({ matched: pushResult.matchedCount, modified: pushResult.modifiedCount });
printjson(db.patient_records.findOne(
  { patient_id: 1 },
  { _id: 0, full_name: 1, visit_count: { $size: "$visits" }, latest_visit: { $arrayElemAt: ["$visits", -1] } }
));

// ---------------------------------------------------------------------------
header("Q3. All patients allergic to penicillin (multikey index on an array)");
// Business reason: the pharmacy checks who must not receive amoxicillin.
db.patient_records
  .find({ allergies: "penicillin" }, { _id: 0, patient_id: 1, full_name: 1, allergies: 1, "contact.phone": 1 })
  .sort({ patient_id: 1 })
  .forEach((d) => printjson(d));
print(planSummary(db.patient_records.find({ allergies: "penicillin" }).explain("executionStats")));

// ---------------------------------------------------------------------------
header("Q4. Aggregation: number of visits per doctor across all patients");
// Business reason: clinical workload report for the medical director.
db.patient_records.aggregate([
  { $unwind: "$visits" },
  { $group: {
      _id: "$visits.doctor.name",
      department: { $first: "$visits.doctor.department" },
      visits: { $sum: 1 },
      patients: { $addToSet: "$patient_id" } } },
  { $project: { _id: 0, doctor: "$_id", department: 1, visits: 1, distinct_patients: { $size: "$patients" } } },
  { $sort: { visits: -1, doctor: 1 } },
]).forEach((d) => printjson(d));

// ---------------------------------------------------------------------------
header("Q5. Aggregation: average haemoglobin across FBC results in the last 30 days");
// Business reason: the lab monitors population anaemia levels month by month.
db.lab_results.aggregate([
  { $match: { test_type: "full_blood_count", status: "complete",
              ordered_at: { $gte: new Date(Date.now() - 30 * DAY) } } },
  { $group: { _id: null,
              avg_hb: { $avg: "$results.hb" },
              min_hb: { $min: "$results.hb" },
              max_hb: { $max: "$results.hb" },
              below_12: { $sum: { $cond: [{ $lt: ["$results.hb", 12] }, 1, 0] } },
              n: { $sum: 1 } } },
  { $project: { _id: 0, avg_hb: { $round: ["$avg_hb", 2] }, min_hb: 1, max_hb: 1, below_12: 1, n: 1 } },
]).forEach((d) => printjson(d));

// ---------------------------------------------------------------------------
header("Q6. $lookup: each patient's most recent lab test with the patient's name");
// Business reason: the ward round list shows the latest result next to each name.
db.lab_results.aggregate([
  { $sort: { patient_id: 1, ordered_at: -1 } },
  { $group: { _id: "$patient_id", latest: { $first: "$$ROOT" } } },
  { $lookup: {
      from: "patient_records",
      localField: "_id",
      foreignField: "patient_id",
      as: "patient",
      pipeline: [{ $project: { _id: 0, full_name: 1, blood_group: 1 } }] } },
  { $unwind: "$patient" },
  { $project: {
      _id: 0,
      patient_id: "$_id",
      full_name: "$patient.full_name",
      test_type: "$latest.test_type",
      ordered_at: "$latest.ordered_at",
      status: "$latest.status",
      results: "$latest.results" } },
  { $sort: { ordered_at: -1 } },
  { $limit: 10 },
]).forEach((d) => printjson(d));

// ---------------------------------------------------------------------------
header("Bonus. Same flexible collection, different result shapes per test type");
db.lab_results.aggregate([
  { $match: { status: "complete" } },
  { $group: { _id: "$test_type", n: { $sum: 1 }, example_fields: { $first: { $objectToArray: "$results" } } } },
  { $project: { _id: 0, test_type: "$_id", n: 1, fields: "$example_fields.k" } },
  { $sort: { test_type: 1 } },
]).forEach((d) => printjson(d));
