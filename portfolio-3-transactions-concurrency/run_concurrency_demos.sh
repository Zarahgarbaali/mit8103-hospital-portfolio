#!/usr/bin/env bash
# Run the two-session demos in 02_isolation_levels.sql, 03_deadlock.sql and
# 04_row_locking.sql and save each session's output to evidence/.
#
# Usage: ./run_concurrency_demos.sh            (all scenarios)
#        ./run_concurrency_demos.sh 2c 3a      (selected scenarios)
#
# Each scenario's "-- @<id>-A" block is started first and its "-- @<id>-B"
# block 0.5 s later, as two separate database connections.

set -uo pipefail
cd "$(dirname "$0")"
mkdir -p evidence

file_for() {
    case $1 in
        2*) echo 02_isolation_levels.sql ;;
        3*) echo 03_deadlock.sql ;;
        4*) echo 04_row_locking.sql ;;
    esac
}

title_for() {
    case $1 in
        2a) echo read_committed ;;
        2b) echo repeatable_read ;;
        2c) echo serializable_last_bed ;;
        2d) echo read_committed_write_skew ;;
        2e) echo serializable_write_skew ;;
        3a) echo deadlock ;;
        3b) echo deadlock_avoided ;;
        4a) echo for_update_last_pack ;;
        4b) echo for_update_nowait ;;
        4c) echo skip_locked_work_queue ;;
    esac
}

block() {
    awk -v m="-- @$2" '$0 == m {f = 1; next} /^-- @/ {f = 0} f' "$1"
}

# psql needs a terminal to keep its result and error output in order, so the
# block is copied into the container and run with -t.
run_session() {
    local name=$1 sql=$2
    docker exec -i hospital_pg sh -c "cat > /tmp/${name}.sql" <<< "$sql"
    docker exec -t hospital_pg psql -U hospital_admin -d hospital_db -X -e -P pager=off \
        -f "/tmp/${name}.sql" 2>&1 | tr -d '\r'
}

if [ $# -eq 0 ]; then
    set -- 2a 2b 2c 2d 2e 3a 3b 4a 4b 4c
fi

for id in "$@"; do
    file=$(file_for "$id")
    title=$(title_for "$id")
    out="evidence/${id}_${title}.txt"
    a_log=$(mktemp)
    b_log=$(mktemp)

    run_session "s${id}a" "$(block "$file" "${id}-A")" > "$a_log" &
    sleep 0.5
    run_session "s${id}b" "$(block "$file" "${id}-B")" > "$b_log"
    wait

    {
        echo "# ${file} scenario ${id} (${title}), run $(date '+%Y-%m-%d %H:%M:%S %Z')"
        echo
        echo "## Session A"
        echo
        cat "$a_log"
        echo
        echo "## Session B (started 0.5 s after Session A)"
        echo
        cat "$b_log"
    } > "$out"
    rm -f "$a_log" "$b_log"
    echo "scenario ${id} -> ${out}"
done
