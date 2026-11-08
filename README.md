# MIT 8103 Advanced Database Systems - Hospital Portfolio

**Student:** Zarah Garba Ali
**Student ID:** 301918521
**Programme:** Master of Information Technology, MIVA Open University
**Cohort:** September 2026
**Case Study:** MIVA Teaching Hospital (simulated)

## Case study

MIVA Teaching Hospital is a simulated mid-size general hospital in Abuja, Nigeria. It offers outpatient consultations, inpatient admissions, laboratory diagnostics, pharmacy dispensing and billing, and runs 24/7 across five departments. The database serves receptionists, doctors, nurses, lab technicians, pharmacists, billing officers and administrators. It stores patients, staff, departments, appointments, diagnoses, prescriptions, lab orders and results, medications and stock, wards and admissions, invoices, payments and an audit log. The full case study statement is in [portfolio-1-database-design/README.md](portfolio-1-database-design/README.md).

The same hospital, the same patients and the same doctors are used in all five portfolios.

## Portfolios

| # | Folder | Summary |
|---|---|---|
| 1 | [portfolio-1-database-design](portfolio-1-database-design/) | ER model (DBML + Mermaid), 16-table PostgreSQL schema with CHECK / UNIQUE / FK constraints, partial unique indexes and business-rule triggers, reproducible seed data, 12 constraint tests, normalisation to BCNF |
| 2 | [portfolio-2-query-optimisation](portfolio-2-query-optimisation/) | 10 queries, ~1.5 M-row bulk load, before/after `EXPLAIN (ANALYZE, BUFFERS)`, range / covering / partial indexes (Q2 6.7x faster), a materialised view (102 ms to 0.03 ms), and a measured write-cost trade-off |
| 3 | [portfolio-3-transactions-concurrency](portfolio-3-transactions-concurrency/) | COMMIT / ROLLBACK / SAVEPOINT, READ COMMITTED vs REPEATABLE READ vs SERIALIZABLE (including write skew), deadlock and lock ordering, `FOR UPDATE` / `NOWAIT` / `SKIP LOCKED`, and a discharge stored procedure with an audit trail. All two-session scenarios were run concurrently and logged |
| 4 | [portfolio-4-nosql](portfolio-4-nosql/) | MongoDB document model: patient charts with embedded visits, lab results with a flexible shape per test type, `$jsonSchema` validation, multikey indexes, 6 queries (find, `$push`, aggregation, `$lookup`), and a suitability analysis against PostgreSQL |
| 5 | [portfolio-5-distributed-cloud](portfolio-5-distributed-cloud/) | 3-node MongoDB replica set: replication, automatic failover, rejoin and catch-up, a minority partition refusing writes (CAP), and a discussion of sharding, consistency and PostgreSQL streaming replication |
| - | [docs](docs/) | LMS submission document |

## Repository layout

```
advanced-database-portfolio/
├── docker/                               Postgres 16 + Mongo 7 for portfolios 1-4
│   ├── docker-compose.yml
│   └── evidence/
├── portfolio-1-database-design/          er_diagram.dbml, schema.sql, indexes.sql, seed.sql,
│                                         constraint_tests.sql, normalisation.md, evidence/
├── portfolio-2-query-optimisation/       queries.sql, bulk_load.sql, indexes.sql, capture_plans.sh,
│                                         execution_plans/{before,after}/, materialized_view.sql,
│                                         write_cost_test.sql, performance_analysis.md, evidence/
├── portfolio-3-transactions-concurrency/ 01-05 *.sql, 02_isolation_levels.md,
│                                         run_concurrency_demos.sh, evidence/
├── portfolio-4-nosql/                    schema.md, seed.js, indexes.js, queries.js,
│                                         suitability.md, evidence/
├── portfolio-5-distributed-cloud/        docker/docker-compose.yml, replica_demo.sh,
│                                         discussion.md, evidence/
├── docs/                                 lms_submission.md
└── README.md
```

Every portfolio folder has its own README explaining what was built, how it was tested, and where the evidence is.

## How to run

Requirements: Docker Desktop. DBeaver and MongoDB Compass are optional, for browsing.

### Portfolios 1-4: PostgreSQL 16 and MongoDB 7

```bash
cd docker
docker compose up -d          # hospital_pg on :5432, hospital_mongo on :27017
cd ..

# Portfolio 1
docker exec -i hospital_pg psql -U hospital_admin -d hospital_db -v ON_ERROR_STOP=1 -f /workspace/portfolio-1-database-design/schema.sql
docker exec -i hospital_pg psql -U hospital_admin -d hospital_db -v ON_ERROR_STOP=1 -f /workspace/portfolio-1-database-design/indexes.sql
docker exec -i hospital_pg psql -U hospital_admin -d hospital_db -v ON_ERROR_STOP=1 -f /workspace/portfolio-1-database-design/seed.sql

# Portfolio 2 (see its README for the full sequence)
docker exec -i hospital_pg psql -U hospital_admin -d hospital_db -v ON_ERROR_STOP=1 -f /workspace/portfolio-2-query-optimisation/bulk_load.sql
./portfolio-2-query-optimisation/capture_plans.sh before
docker exec -i hospital_pg psql -U hospital_admin -d hospital_db -v ON_ERROR_STOP=1 -f /workspace/portfolio-2-query-optimisation/indexes.sql
./portfolio-2-query-optimisation/capture_plans.sh after

# Portfolio 3
./portfolio-3-transactions-concurrency/run_concurrency_demos.sh

# Portfolio 4
docker exec hospital_mongo mongosh -u hospital_admin -p hospital_pass --authenticationDatabase admin --quiet hospital /workspace/portfolio-4-nosql/seed.js
docker exec hospital_mongo mongosh -u hospital_admin -p hospital_pass --authenticationDatabase admin --quiet hospital /workspace/portfolio-4-nosql/indexes.js
docker exec hospital_mongo mongosh -u hospital_admin -p hospital_pass --authenticationDatabase admin --quiet hospital /workspace/portfolio-4-nosql/queries.js
```

The repository is mounted read-only at `/workspace` inside both containers, so scripts run in place.

| Tool | Connection |
|---|---|
| DBeaver | PostgreSQL, `localhost:5432`, database `hospital_db`, user `hospital_admin`, password `hospital_pass` |
| MongoDB Compass | `mongodb://hospital_admin:hospital_pass@localhost:27017/?authSource=admin` |

### Portfolio 5: replica set

```bash
cd portfolio-5-distributed-cloud/docker
docker compose up -d          # mongo1 :27018, mongo2 :27019, mongo3 :27020
cd ..
./replica_demo.sh init
./replica_demo.sh status
./replica_demo.sh write-read
./replica_demo.sh failover
./replica_demo.sh rejoin
./replica_demo.sh minority
```

The credentials above are local development defaults for containers bound to this machine. They are not secrets.

## Stack

PostgreSQL 16, MongoDB 7, Docker, DBeaver, MongoDB Compass, dbdiagram.io. Developed on a MacBook M1 (macOS).

## Declaration of AI and Tool Use

I, Zarah Garba Ali (Student ID 301918521), used Cursor and Claude to support this work in the following ways: understanding concepts, drafting initial SQL and Mongo scripts which I then edited and tested, explaining execution plans, and reviewing my writeups for clarity. All design decisions — the choice of case study, the schema design, the index choices, the isolation walkthroughs, the Mongo modelling, and the replica set setup — are my own. The technical reflection was drafted with AI assistance from my work in this repository, and I reviewed and edited it so that it reflects my own experience. All code was executed, verified, and in several places rewritten by me after testing. No AI-generated text was submitted without review.
