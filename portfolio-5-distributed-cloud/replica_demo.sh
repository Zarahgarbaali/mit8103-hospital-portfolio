#!/usr/bin/env bash
# Replica set demo for MIVA Teaching Hospital (hospitalRS).
#
# Usage, in order, after "docker compose up -d" in ./docker:
#   ./replica_demo.sh init        initiate hospitalRS and wait for a primary
#   ./replica_demo.sh status      rs.status() baseline   -> evidence/01_rs_status.txt
#   ./replica_demo.sh write-read  write on primary, read on secondary -> 02, 03
#   ./replica_demo.sh failover    stop the primary, show the election -> 04
#   ./replica_demo.sh rejoin      restart it and show it catch up     -> 05
#   ./replica_demo.sh minority    stop two members: no primary, no writes -> 06

set -euo pipefail
cd "$(dirname "$0")"
mkdir -p evidence

RS_URI="mongodb://mongo1:27018,mongo2:27019,mongo3:27020/?replicaSet=hospitalRS"

# Run JS on one member (container name, port)
on_member() {
    docker exec "$1" mongosh --port "$2" --quiet --eval "$3"
}

# Run JS through a replica-set connection (finds the primary itself)
on_set() {
    local via=$1; shift
    docker exec "$via" mongosh "$RS_URI" --quiet --eval "$1"
}

STATUS_JS='
const s = rs.status();
print(`replica set: ${s.set}   reported by: ${db.getMongo().host}   at: ${s.date.toISOString()}`);
print("member          state                     health  optime (last applied write)   sync source / message");
s.members.forEach(m => print(
  `${m.name.padEnd(15)} ${m.stateStr.padEnd(25)} ${String(m.health).padEnd(7)} ${(m.optimeDate ? m.optimeDate.toISOString() : "-").padEnd(29)} ${m.syncSourceHost || m.lastHeartbeatMessage || ""}`));
const p = s.members.find(m => m.stateStr === "PRIMARY");
print(`primary: ${p ? p.name : "NONE"}   term: ${s.term}`);
'

primary_container() {
    for spec in mongo1:27018 mongo2:27019 mongo3:27020; do
        local c=${spec%%:*} port=${spec##*:}
        if docker exec "$c" mongosh --port "$port" --quiet --eval 'db.hello().isWritablePrimary' 2>/dev/null | grep -q true; then
            echo "$c:$port"
            return
        fi
    done
}

wait_for_primary() {
    for _ in $(seq 1 30); do
        p=$(primary_container)
        [ -n "$p" ] && { echo "$p"; return; }
        sleep 1
    done
    echo "no primary after 30 s" >&2
    return 1
}

case "${1:-}" in
init)
    on_member mongo1 27018 '
      try {
        rs.initiate({
          _id: "hospitalRS",
          members: [
            { _id: 0, host: "mongo1:27018", priority: 2 },
            { _id: 1, host: "mongo2:27019", priority: 1 },
            { _id: 2, host: "mongo3:27020", priority: 1 }
          ]
        });
        print("rs.initiate: ok");
      } catch (e) {
        print(`rs.initiate: ${e.codeName}`);
      }'
    echo "primary: $(wait_for_primary)"
    ;;

status)
    {
        echo "\$ docker ps (replica set members)"
        docker ps --filter name=mongo --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' | grep -v hospital_mongo
        echo
        echo "\$ rs.status() on mongo1"
        on_member mongo1 27018 "$STATUS_JS"
        echo
        echo "\$ rs.conf().members"
        on_member mongo1 27018 'rs.conf().members.forEach(m => print(`${m.host}  priority=${m.priority}  votes=${m.votes}`))'
    } | tee evidence/01_rs_status.txt
    ;;

write-read)
    {
        echo "\$ insert 5 patient records through the replica-set connection (lands on the primary), writeConcern majority"
        on_set mongo1 '
          db = db.getSiblingDB("hospital");
          db.patient_records.drop();
          const r = db.patient_records.insertMany([
            { patient_id: 1, full_name: "Amina Eze",           blood_group: "A+", ward: "Medical Ward A" },
            { patient_id: 2, full_name: "Chukwuemeka Danladi", blood_group: "O+", ward: "Surgical Ward" },
            { patient_id: 3, full_name: "Folasade Umar",       blood_group: "A+", ward: "Maternity Ward" },
            { patient_id: 4, full_name: "Abubakar Balogun",    blood_group: "B+", ward: "Medical Ward A" },
            { patient_id: 5, full_name: "Chiamaka Mohammed",   blood_group: "O-", ward: "Children'"'"'s Ward" }
          ], { writeConcern: { w: "majority", wtimeout: 5000 } });
          print(`inserted ${Object.keys(r.insertedIds).length} documents, acknowledged=${r.acknowledged}`);
          print(`written via: ${db.hello().me} (isWritablePrimary=${db.hello().isWritablePrimary})`);'
    } | tee evidence/02_write_primary.txt
    {
        echo "\$ read from mongo2 directly with readPreference secondary"
        on_member mongo2 27019 '
          db = db.getSiblingDB("hospital");
          db.getMongo().setReadPref("secondary");
          print(`connected to: ${db.hello().me}  isWritablePrimary=${db.hello().isWritablePrimary}  secondary=${db.hello().secondary}`);
          print(`patient_records count on secondary: ${db.patient_records.countDocuments({})}`);
          db.patient_records.find({}, { _id: 0, patient_id: 1, full_name: 1 }).sort({ patient_id: 1 }).forEach(d => printjson(d));'
        echo
        echo "\$ the same count from mongo3"
        on_member mongo3 27020 '
          db = db.getSiblingDB("hospital");
          db.getMongo().setReadPref("secondary");
          print(`connected to: ${db.hello().me}  count: ${db.patient_records.countDocuments({})}`);'
        echo
        echo "\$ try to write directly on a secondary (must be refused)"
        on_member mongo2 27019 '
          try {
            db.getSiblingDB("hospital").patient_records.insertOne({ patient_id: 99, full_name: "Should fail" });
            print("UNEXPECTED: write accepted on a secondary");
          } catch (e) { print(`refused: ${e.codeName} - ${e.message}`); }'
        echo
        echo "\$ replication lag (rs.printSecondaryReplicationInfo on the primary)"
        on_set mongo1 'rs.printSecondaryReplicationInfo()'
    } | tee evidence/03_read_secondary.txt
    ;;

failover)
    old=$(primary_container)
    old_c=${old%%:*}
    {
        echo "primary before failover: $old"
        echo "\$ docker stop $old_c   ($(date '+%H:%M:%S'))"
        docker stop "$old_c" >/dev/null
        echo "waiting 20 s for the remaining members to detect the failure and elect a new primary"
        sleep 20
        new=$(wait_for_primary)
        echo
        echo "\$ rs.status() on ${new%%:*}   ($(date '+%H:%M:%S'))"
        on_member "${new%%:*}" "${new##*:}" "$STATUS_JS"
        echo
        echo "\$ the hospital keeps writing: admit patient 6 through the replica-set connection"
        on_member "${new%%:*}" "${new##*:}" '
          const r = db.getSiblingDB("hospital").patient_records.insertOne(
            { patient_id: 6, full_name: "Olumide Adeleke", blood_group: "O+", ward: "Surgical Ward" },
            { writeConcern: { w: "majority", wtimeout: 5000 } });
          print(`insert acknowledged=${r.acknowledged} on ${db.hello().me}; count now ${db.getSiblingDB("hospital").patient_records.countDocuments({})}`);'
    } | tee evidence/04_failover_rs_status.txt
    ;;

rejoin)
    {
        echo "\$ docker start mongo1   ($(date '+%H:%M:%S'))"
        docker start mongo1 >/dev/null
        echo "waiting 15 s for mongo1 to rejoin and catch up from the oplog"
        sleep 15
        new=$(wait_for_primary)
        echo
        echo "\$ rs.status() on ${new%%:*}"
        on_member "${new%%:*}" "${new##*:}" "$STATUS_JS"
        echo
        echo "\$ mongo1 has replicated the write made while it was down"
        on_member mongo1 27018 '
          db = db.getSiblingDB("hospital");
          db.getMongo().setReadPref("secondary");
          print(`mongo1 state: ${rs.status().myState === 1 ? "PRIMARY" : "SECONDARY"}   patient_records count: ${db.patient_records.countDocuments({})}`);
          printjson(db.patient_records.findOne({ patient_id: 6 }, { _id: 0 }));'
        echo
        echo "note: mongo1 has priority 2, so after catching up it calls an election and takes the primary role back"
        sleep 15
        on_member mongo1 27018 "$STATUS_JS"
    } | tee evidence/05_rejoin_rs_status.txt
    ;;

minority)
    {
        echo "\$ docker stop mongo2 mongo3: mongo1 is now alone, a minority of 1 out of 3   ($(date '+%H:%M:%S'))"
        docker stop mongo2 mongo3 >/dev/null
        sleep 15
        echo
        echo "\$ rs.status() on mongo1"
        on_member mongo1 27018 "$STATUS_JS"
        echo
        echo "\$ attempt a write on mongo1"
        on_member mongo1 27018 '
          try {
            db.getSiblingDB("hospital").patient_records.insertOne({ patient_id: 7, full_name: "Zainab Oyelaran" });
            print("UNEXPECTED: write accepted without a majority");
          } catch (e) { print(`refused: ${e.codeName} - ${e.message}`); }'
        echo
        echo "\$ reads are still possible with readPreference secondary (possibly stale)"
        on_member mongo1 27018 '
          db = db.getSiblingDB("hospital");
          db.getMongo().setReadPref("secondaryPreferred");
          print(`count readable on the isolated member: ${db.patient_records.countDocuments({})}`);'
        echo
        echo "\$ docker start mongo2 mongo3   ($(date '+%H:%M:%S'))"
        docker start mongo2 mongo3 >/dev/null
        new=$(wait_for_primary)
        sleep 5
        echo "primary restored: $new"
        on_member "${new%%:*}" "${new##*:}" "$STATUS_JS"
    } | tee evidence/06_minority_no_primary.txt
    ;;

*)
    sed -n '2,12p' "$0"
    exit 1
    ;;
esac
