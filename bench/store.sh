#!/usr/bin/env bash
# The store example (examples/ar/store.sn) under load from a separate
# process, with every response body checked.
#
#   SULTANC_ROOT="$PWD/sultanc" nahr/bench/store.sh
#
# The store is built with LLVM and started on its own; the load comes from
# bench/load.c (nahr_load) in another process, over keep-alive connections.
# For each scenario the unloaded response is first compared with
# bench/store-expected/<scenario>.json (the catalog is the same in every
# run), then every response under load is compared with it byte for byte: a
# 2xx with another body counts as wrong, not as a success. The report gives
# how many connections were established, so a run that opened fewer
# connections than asked is visible.
#
# Settings (environment):
#   CONNECTIONS="16 64 256"  LOAD_THREADS=4  DURATION=10  WARMUP=2
#   WORKERS=0 (server event-loop workers, 0 = one per core)  PORT=8095
#   SCENARIOS="product browse search"
#
# Pin the server and the load generator to separate cores when the machine
# allows it (Linux: SERVER_CPUS=0-5 LOAD_CPUS=6-11, used with taskset), so
# they do not take CPU time from each other.
#
# This measures one implementation. Comparing with another framework needs
# the same application written in it and run under this same script.
set -euo pipefail

bench_dir=$(cd "$(dirname "$0")" && pwd)
nahr_dir=$(dirname "$bench_dir")
: "${SULTANC_ROOT:?set SULTANC_ROOT to the SultanC checkout}"
compiler=${SULTANC:-$SULTANC_ROOT/build/sultanc}
CONNECTIONS=${CONNECTIONS:-"16 64 256"}
LOAD_THREADS=${LOAD_THREADS:-4}
DURATION=${DURATION:-10}
WARMUP=${WARMUP:-2}
WORKERS=${WORKERS:-0}
PORT=${PORT:-8095}
SCENARIOS=${SCENARIOS:-"product browse search"}

out=${OUT:-$bench_dir/results}/store-$(date +%Y%m%d-%H%M%S)
mkdir -p "$out/bin"
cpus=$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo "?")
echo "Nahr store benchmark  $(date)  host=$(uname -sm)  cpus=$cpus"
echo "  duration=${DURATION}s warmup=${WARMUP}s connections=[$CONNECTIONS] load-threads=$LOAD_THREADS server-workers=$WORKERS"

echo "building..."
(cd "$SULTANC_ROOT" && "$compiler" "$nahr_dir/examples/ar/store.sn" --package-graph "$nahr_dir/examples/package-graph.toml" -b llvm -O2 -o "$out/bin/store") > "$out/build.log" 2>&1 \
    || { cat "$out/build.log"; exit 1; }
cc -O2 -pthread -o "$out/bin/nahr_load" "$bench_dir/load.c" >> "$out/build.log" 2>&1 || { cat "$out/build.log"; exit 1; }

# Runs the command in place of the shell (exec), so the PID of `pin ... &`
# is the program's own and the trap below stops the program itself.
pin() { # $1 cpu list, rest: command
    local cpu_list=$1; shift
    if [ -n "$cpu_list" ] && command -v taskset >/dev/null 2>&1; then exec taskset -c "$cpu_list" "$@"; else exec "$@"; fi
}

if curl -s -o /dev/null "http://127.0.0.1:$PORT/"; then
    echo "port $PORT is already in use; stop that server or set PORT"; exit 1
fi
NAHR_PORT=$PORT NAHR_ACCESS_LOG=0 NO_COLOR=1 NAHR_WORKERS=$WORKERS \
    pin "${SERVER_CPUS:-}" "$out/bin/store" > "$out/server.log" 2>&1 &
server=$!
trap 'kill "$server" 2>/dev/null; wait "$server" 2>/dev/null || true' EXIT INT TERM
for _ in $(seq 1 100); do
    curl -s -o /dev/null "http://127.0.0.1:$PORT/api/categories" && break
    kill -0 "$server" 2>/dev/null || { echo "the store did not start:"; cat "$out/server.log"; exit 1; }
    sleep 0.1
done

path_of() {
    case $1 in
        product) echo "/api/products/4242" ;;
        browse) echo "/api/products?category=%D8%A5%D9%84%D9%83%D8%AA%D8%B1%D9%88%D9%86%D9%8A%D8%A7%D8%AA&sort=cheapest&page=5" ;;
        search) echo "/api/products?q=%D9%82%D9%87%D9%88%D8%A9%20%D8%B9%D8%B1%D8%A8%D9%8A%D8%A9&sort=rating" ;;
        *) echo "unknown scenario $1" >&2; exit 2 ;;
    esac
}

csv=$out/results.csv
echo "scenario,method,path,connections,seconds,requests,req_per_s,req_per_ms,p50_ms,p90_ms,p99_ms,p999_ms,max_ms,non_2xx,socket_errors,reconnects,mb_per_s,wrong_body,connected" > "$csv"
printf '\n  %-8s %6s %12s %9s %9s %8s %8s %10s\n' scenario conns "valid req/s" "p50 ms" "p99 ms" wrong errors connected
status=0
for scenario in $SCENARIOS; do
    path=$(path_of "$scenario")
    expected=$bench_dir/store-expected/$scenario.json
    # The unloaded answer must be the expected one before anything is measured.
    if ! curl -s "http://127.0.0.1:$PORT$path" | cmp -s - "$expected"; then
        echo "  $scenario: the response differs from $expected; not measuring it"
        status=1; continue
    fi
    for c in $CONNECTIONS; do
        line=$(pin "${LOAD_CPUS:-}" "$out/bin/nahr_load" -o csv -c "$c" -t "$LOAD_THREADS" -d "$DURATION" -w "$WARMUP" \
            -e "$expected" "http://127.0.0.1:$PORT$path")
        echo "$scenario,$line" >> "$csv"
        echo "$line" | awk -F, -v s="$scenario" '{
            valid = $5 - $13 - $17
            printf "  %-8s %6s %12.0f %9.3f %9.3f %8s %8s %6s/%s\n", s, $3, valid / $4, $8, $10, $17, $14, $18, $3 }'
        echo "$line" | awk -F, '$17 + 0 > 0 || $18 + 0 < $3 + 0 { exit 1 }' || status=1
    done
done
echo
if [ $status = 0 ]; then
    echo "every response body matched; every connection was established"
else
    echo "! some responses were wrong or some connections were not established: see above"
fi
echo "csv: $csv"
exit $status
