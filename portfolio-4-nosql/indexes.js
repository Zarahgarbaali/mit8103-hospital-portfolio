// MIVA Teaching Hospital - MongoDB indexes
//   docker exec hospital_mongo mongosh -u hospital_admin -p hospital_pass \
//     --authenticationDatabase admin --quiet hospital /workspace/portfolio-4-nosql/indexes.js

// One chart per patient; serves Q1, Q2 and the $lookup in Q6
db.patient_records.createIndex({ patient_id: 1 }, { unique: true, name: "uq_patient_id" });

// Multikey index over every embedded visit date: "who was seen recently"
db.patient_records.createIndex({ "visits.date": -1 }, { name: "idx_visits_date" });

// Multikey index over the allergies array: Q3
db.patient_records.createIndex({ allergies: 1 }, { name: "idx_allergies" });

// A patient's results, newest first: Q6 and the chart's lab tab
db.lab_results.createIndex({ patient_id: 1, ordered_at: -1 }, { name: "idx_patient_ordered_at" });

// Results by test type across all patients: Q5
db.lab_results.createIndex({ test_type: 1 }, { name: "idx_test_type" });

print("patient_records indexes:");
db.patient_records.getIndexes().forEach((ix) => print(`  ${ix.name}  ${JSON.stringify(ix.key)}${ix.unique ? "  unique" : ""}`));
print("lab_results indexes:");
db.lab_results.getIndexes().forEach((ix) => print(`  ${ix.name}  ${JSON.stringify(ix.key)}`));
