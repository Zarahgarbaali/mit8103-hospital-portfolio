# Distributed Database Discussion - MIVA Teaching Hospital

This discussion is based on the three-node MongoDB replica set `hospitalRS` built in `docker/docker-compose.yml` and exercised by `replica_demo.sh`. Every claim below points to an evidence file.

## 1. Replication

`hospitalRS` has three data-bearing members: `mongo1` (priority 2, the preferred primary), `mongo2` and `mongo3`. All writes go to the primary, which records them in its **oplog** (operations log). The secondaries continuously pull the oplog and replay it.

- **Write on primary, read on secondary.** Five patient records were inserted through the replica-set connection with `writeConcern: { w: "majority" }`. Reading directly from `mongo2` and `mongo3` with `readPreference: secondary` returned all five, and `rs.printSecondaryReplicationInfo()` reported a lag of 0 seconds (`evidence/02_write_primary.txt`, `evidence/03_read_secondary.txt`).
- **Secondaries are read-only.** A direct insert on `mongo2` was refused with `NotWritablePrimary` (`evidence/03_read_secondary.txt`).
- **Automatic failover.** `docker stop mongo1` removed the primary. Within the 20-second wait, `mongo2` and `mongo3` held an election and `mongo2` became PRIMARY in term 99. A new admission (patient 6) was then written with majority acknowledgement (`evidence/04_failover_rs_status.txt`).
- **Rejoin and catch-up.** After `docker start mongo1`, it came back as SECONDARY, replayed the oplog entries it had missed (it then held patient 6), and about 10 seconds after starting, because of its higher priority, it called an election and became PRIMARY again in term 100 (`evidence/05_rejoin_rs_status.txt`). The term counter is high because the set had been running for a day and held over 30 elections per member on its own (visible in the container logs), most likely whenever the Mac slept or Docker paused and heartbeats timed out. This is a real-world reminder that elections are routine events, not rare emergencies.

**Synchronous vs asynchronous.** MongoDB replication itself is **asynchronous**: the primary does not wait for secondaries before applying a write. The client chooses how long to wait with the write concern. `w: 1` returns as soon as the primary has the write. `w: "majority"` (the default since MongoDB 5.0, and used in this demo) waits until a majority of members have it, which makes the write durable across a failover. MongoDB keeps the replication mechanism asynchronous so that one slow or distant secondary cannot stall every write in the hospital. Durability is then a per-operation choice, not a global cost. For billing, majority writes are mandatory. For something like a bed-board refresh, `w: 1` would be acceptable.

## 2. Sharding (conceptual)

Sharding was not deployed. It needs config servers (themselves a replica set), one or more `mongos` routers, and several shard replica sets, which is beyond one laptop. For MIVA Teaching Hospital, the design would be:

- **What to shard:** `patient_records` and `lab_results`, the two collections that grow without limit. Small reference data (doctors, wards) stays unsharded on the primary shard.
- **Candidate key A, `{ patient_id: "hashed" }`.** Hashing spreads patients evenly over shards, so no shard becomes a hotspot even though new patients get increasing ids. The most common query, "open this patient's chart", includes `patient_id`, so `mongos` sends it to exactly one shard. The cost is that department-wide queries (all paediatric patients) must be sent to every shard (scatter-gather).
- **Candidate key B, `{ department_id: 1, patient_id: 1 }`.** Queries for one department stay on one shard, which suits departmental reporting, and could be combined with zone sharding to keep each department's data on hardware in its own building. The risks are an uneven key (General Medicine is far busier than Obstetrics), which creates a hotspot shard, and patients who move between departments.
- **Trade-off:** query locality against even distribution. For a single hospital, where the patient chart is the dominant access path, **hashed `patient_id`** is the safer choice. Key B would only pay off in a multi-site network where each site mainly queries its own patients.
- `lab_results` would use the same `patient_id` hashed key, so a patient's chart and lab results live on the same shard and the Q6 `$lookup` stays local.

## 3. CAP applied to the hospital

The CAP theorem says that during a network **partition** (P), a distributed system must choose between **consistency** (C: every read sees the latest write) and **availability** (A: every request gets an answer).

A MongoDB replica set with majority write concern behaves as **CP**. Only a member that can see a majority of the voting members can be primary. `evidence/06_minority_no_primary.txt` shows this directly. With `mongo2` and `mongo3` stopped, `mongo1` could only see itself (1 of 3), so it stepped down to SECONDARY, the set reported `primary: NONE`, and a write was refused with `NotWritablePrimary`. As soon as the other two members returned, a primary was elected again (term 101).

What that means for the admissions desk: suppose the hospital ran one member in the main building and two in the annex, and the link between them failed.

- **Annex side (majority, 2 of 3):** elects a primary and keeps admitting patients normally.
- **Main building side (minority, 1 of 3):** loses write availability. The admissions desk there can still *read* charts (with `readPreference: secondaryPreferred`; the demo read 6 records from the isolated member), but it cannot admit a patient or allocate a bed until the link returns.

This is the correct choice for a hospital. If both sides could accept writes, both could give "the last free bed" in the Children's Ward to different patients. That is the same conflict Portfolio 3 prevented inside one database with SERIALIZABLE isolation. In a partition, the safe fallback is a paper admission form, entered once the link returns. An AP system (for example Cassandra with `ONE` consistency) would keep both sides writable and reconcile later, which is fine for appointment reminders or audit telemetry, but not for bed allocation or payments.

## 4. Consistency models

- **Strong consistency on the primary.** Reads from the primary (the default `readPreference: primary`) always see the latest acknowledged write. Combined with `readConcern: "majority"`, they see only data that cannot be rolled back after a failover.
- **Eventual consistency on secondaries.** `readPreference: secondary` reads a copy that may lag behind. In `evidence/03_read_secondary.txt` the lag was 0 seconds and the secondaries returned all five records. That is still *eventual* consistency: under load or after a network blip, a secondary could briefly return a chart that is missing the latest visit. The isolated-member read in the CAP demo is the extreme case: still readable, but with no guarantee that it is current.
- **Causal consistency.** MongoDB sessions can guarantee read-your-own-writes even on secondaries (`causalConsistency: true`), which suits a doctor who writes a note and immediately re-opens the chart.
- **Hospital policy:** clinical writes and anything read in order to make a decision (bed availability, stock, allergies before prescribing) use the primary with majority read and write concerns. Dashboards and reports may read from secondaries, which offloads the primary at the cost of a few seconds' staleness.

## 5. PostgreSQL streaming replication (conceptual)

PostgreSQL, which holds billing and scheduling, would be replicated with **streaming replication**:

- On the primary, set `wal_level = replica` (writes enough information into the write-ahead log for a standby to replay it), `max_wal_senders` (the number of standbys and backup connections allowed), and a replication role in `pg_hba.conf`.
- Bootstrap a standby with `pg_basebackup -h primary -D /var/lib/postgresql/data -R -X stream`. `-R` writes `primary_conninfo` and the `standby.signal` file, so the copy starts as a standby that continuously streams and replays WAL. With `hot_standby = on`, it serves read-only queries.
- **Synchronous or asynchronous is a configuration choice.** By default replication is asynchronous: commits return before the standby has the WAL, so a primary crash can lose the last few transactions. Setting `synchronous_standby_names` (and `synchronous_commit = on` or `remote_apply`) makes each commit wait for the standby. Nothing is lost, but every commit pays a network round trip, and if the synchronous standby is down, commits block. For payments, a synchronous standby in the same data centre is justified. A remote disaster-recovery standby would be asynchronous.
- Unlike a MongoDB replica set, PostgreSQL does not elect a new primary by itself. Failover needs an external tool such as Patroni (with etcd), or a manual `pg_promote()`.

## 6. Why local Docker for this submission

- **Reproducible:** `docker compose up -d` and `./replica_demo.sh init` rebuild the identical three-node set on any machine with Docker. There are no cloud accounts or credentials to share with the assessor.
- **Verifiable:** every result is a text file in `evidence/` produced by a script in this repository, so the assessor can re-run it and compare.
- **Controllable failures:** stopping a container is a precise, repeatable way to simulate a crashed server or a network partition, which a free cloud tier usually does not allow.
- **Honest limitation:** all three members share one laptop, one disk and one network stack. The demo proves the replication *protocol* (elections, catch-up, majority rules), not real-world latency or hardware independence. A production deployment would place members in separate failure domains, for example a managed service such as MongoDB Atlas across three availability zones.
