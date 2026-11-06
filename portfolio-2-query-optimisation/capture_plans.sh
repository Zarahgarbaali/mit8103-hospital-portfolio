#!/usr/bin/env bash
# Capture EXPLAIN (ANALYZE, BUFFERS) for every query in queries.sql.
#
# Usage: ./capture_plans.sh before   (or: after)
#
# For each query: one warm-up run (so every plan is measured with a warm
# cache), then three EXPLAIN ANALYZE runs. The plan file keeps the last run;
# summary.txt records the planner's total cost and the median execution time.

set -euo pipefail
cd "$(dirname "$0")"

label="${1:?usage: $0 before|after}"
out="execution_plans/${label}"
mkdir -p "$out"

psql_cmd=(docker exec -i hospital_pg psql -U hospital_admin -d hospital_db -X -q -v ON_ERROR_STOP=1)

summary="$out/summary.txt"
printf '%-5s %-14s %-12s %s\n' "query" "total_cost" "median_ms" "indexes_used" > "$summary"

for n in 1 2 3 4 5 6 7 8 9 10; do
    sql=$(awk -v q="-- @Q${n}" '$0 == q {f = 1; next} /^-- @Q[0-9]+$/ {f = 0} f' queries.sql)

    "${psql_cmd[@]}" -o /dev/null <<< "$sql"

    times=()
    for run in 1 2 3; do
        plan=$("${psql_cmd[@]}" -At <<< "EXPLAIN (ANALYZE, BUFFERS) ${sql}")
        times+=("$(grep -oE 'Execution Time: [0-9.]+' <<< "$plan" | awk '{print $3}')")
    done
    median=$(printf '%s\n' "${times[@]}" | sort -n | sed -n '2p')
    cost=$(head -1 <<< "$plan" | grep -oE 'cost=[0-9.]+\.\.[0-9.]+' | sed 's/.*\.\.//')
    indexes=$(grep -oE '(Index|Index Only|Bitmap Index) Scan (Backward )?(using|on) [a-z_0-9]+' <<< "$plan" \
              | awk '{print $NF}' | sort -u | paste -sd, - || true)

    file=$(printf '%s/q%02d.txt' "$out" "$n")
    {
        echo "-- Q${n} (${label} optimisation indexes), captured $(date '+%Y-%m-%d %H:%M %Z')"
        echo "-- execution times of 3 runs (ms): ${times[*]}"
        echo
        echo "$sql"
        echo
        echo "$plan"
    } > "$file"

    printf '%-5s %-14s %-12s %s\n' "Q${n}" "$cost" "$median" "${indexes:--}" >> "$summary"
    echo "Q${n}: cost=${cost} median=${median}ms indexes=${indexes:--}"
done
