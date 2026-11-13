#!/bin/sh
# Nahr stress test and benchmark.
#
#   SULTANC_ROOT="$PWD/sultanc" nahr/bench/run.sh            # full matrix
#   SULTANC_ROOT="$PWD/sultanc" nahr/bench/run.sh quick      # short run
#
# Steps:
#   1. builds the benchmark server, the in-process benchmark and the C load
#      generator (cc);
#   2. in-process: Nahr's own cost per request on one thread, no sockets;
#   3. over HTTP: every endpoint, single-thread and thread pool, with and
#      without the middleware stack, at several connection counts.
#
# Settings (environment):
#   DURATION=5  WARMUP=1  CONNECTIONS="1 16 64"  LOAD_THREADS=2
#   WORKERS=0 (pool size, 0 = one per CPU)  ENDPOINTS="plain json params echo large sleep cpu alloc"
#   PORT=8090  OUT=nahr/bench/results  MODES="serial pool evented"
#   Other frameworks, /plain only (bench/compare; each skipped if its tool
#   is missing): axum actix (cargo), go gin (go), fastapi (python3; a venv
#   is made the first time), node (node).
#   MODES=std adds std's event-driven server with no Nahr code
#   (bench/std_server.sn; every path answers "ok"), to tell a std
#   slowdown from a Nahr one.
#
# Results: OUT/<time>/report.md (tables) and results.csv (one row per run).
# The load generator runs on the same machine and takes CPU from the server;
# for numbers closer to production, run nahr_load from another machine.
set -u
bench_dir=$(cd "$(dirname "$0")" && pwd)
: "${SULTANC_ROOT:?set SULTANC_ROOT to the SultanC repository}"
compiler=${SULTANC:-$SULTANC_ROOT/build/sultanc}
# quick changes only the settings you did not set yourself.
if [ "${1:-}" = quick ]; then
    DURATION=${DURATION:-2}; WARMUP=${WARMUP:-0.5}; CONNECTIONS=${CONNECTIONS:-"1 32"}
    ENDPOINTS=${ENDPOINTS:-"plain json params large sleep"}
fi
DURATION=${DURATION:-5}
WARMUP=${WARMUP:-1}
CONNECTIONS=${CONNECTIONS:-"1 16 64"}
LOAD_THREADS=${LOAD_THREADS:-2}
WORKERS=${WORKERS:-0}
PORT=${PORT:-8090}
# Each server start takes the next port: a server started on the port the
# previous one just left can fail to bind for a moment (CHANGES item 41).
next_port=$PORT
BACKEND=${BACKEND:-native}
ENDPOINTS=${ENDPOINTS:-"plain json params echo large sleep cpu alloc"}
stamp=$(date +%Y%m%d-%H%M%S)
out=${OUT:-$bench_dir/results}/$stamp
mkdir -p "$out"
bin=$out/bin
mkdir -p "$bin"

cpus=$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo "?")
echo "Nahr benchmark  $(date)  host=$(uname -sm)  cpus=$cpus"
echo "  duration=${DURATION}s warmup=${WARMUP}s connections=[$CONNECTIONS] load-threads=$LOAD_THREADS workers=$WORKERS backend=$BACKEND"

echo "building..."
(cd "$SULTANC_ROOT" && "$compiler" "$bench_dir/server.sn" --package-graph "$bench_dir/package-graph.toml" -b "$BACKEND" -o "$bin/server") > "$out/build.log" 2>&1 || { cat "$out/build.log"; exit 1; }
(cd "$SULTANC_ROOT" && "$compiler" "$bench_dir/inprocess.sn" --package-graph "$bench_dir/package-graph.toml" -b "$BACKEND" -o "$bin/inprocess") >> "$out/build.log" 2>&1 || { cat "$out/build.log"; exit 1; }
case " ${MODES:-} " in *" std "*)
    (cd "$SULTANC_ROOT" && "$compiler" "$bench_dir/std_server.sn" --package-graph "$bench_dir/package-graph.toml" -b "$BACKEND" -o "$bin/std_server") >> "$out/build.log" 2>&1 || { cat "$out/build.log"; exit 1; } ;;
esac
# Other frameworks (bench/compare): each answers GET /plain with "ok".
# A mode whose toolchain is missing is skipped with a note.
compare_dir=$bench_dir/compare
drop_mode() { MODES=$(echo " $MODES " | sed "s/ $1 / /"); }
needs() { # $1 mode, $2 tool
    command -v "$2" >/dev/null 2>&1 && return 0
    echo "  $1: $2 is not installed, skipping"; drop_mode "$1"; return 1
}
build_compare() { # $1 mode, $2.. command
    m=$1; shift
    if ! ( "$@" ) >> "$out/build.log" 2>&1; then
        echo "  $m: build failed, skipping (see $out/build.log)"; drop_mode "$m"
    fi
}
for m in ${MODES:-}; do
    case $m in
    axum|actix)
        needs $m cargo && echo "building ${m} (cargo; the first time takes a few minutes)..." &&
            build_compare $m sh -c "cd '$compare_dir/$m' && cargo build --release -q" ;;
    go|gin)
        needs $m go && echo "building ${m}..." &&
            build_compare $m sh -c "cd '$compare_dir/$m' && go build -o '$bin/${m}_bench' ." ;;
    fastapi)
        if needs fastapi python3; then
            echo "preparing fastapi (a virtualenv in bench/compare/fastapi/.venv the first time)..."
            build_compare fastapi sh -c "cd '$compare_dir/fastapi' && { [ -x .venv/bin/uvicorn ] || { python3 -m venv .venv && .venv/bin/pip install -q -r requirements.txt; }; }"
        fi ;;
    node) needs node node ;;
    esac
done
cc -O2 -pthread -o "$bin/nahr_load" "$bench_dir/load.c" >> "$out/build.log" 2>&1 || { cat "$out/build.log"; exit 1; }

report=$out/report.md
{
    echo "# Nahr benchmark $stamp"
    echo
    echo "- host: $(uname -sm), $cpus CPUs"
    echo "- compiler: $SULTANC_ROOT"
    echo "- backend: $BACKEND"
    echo "- load: $LOAD_THREADS client threads on the same machine, ${DURATION}s per run after ${WARMUP}s warm-up"
    echo
    echo "## In-process (Nahr dispatch, one thread, no sockets)"
    echo
} > "$report"
echo "in-process..."
"$bin/inprocess" | tee -a "$report"

csv=$out/results.csv
printf 'ok' > "$out/expect-plain"
printf 'hello nahr' > "$out/expect-echo"
echo "mode,middleware,method,path,connections,seconds,requests,req_per_s,req_per_ms,p50_ms,p90_ms,p99_ms,p999_ms,max_ms,non_2xx,socket_errors,reconnects,mb_per_s,wrong_body,connected" > "$csv"

server_pid=""
start_server() {
    # $1 = serial|pool  $2 = 0|1 (middleware)
    PORT=$next_port; next_port=$((next_port + 1))
    serial=0; [ "$1" = serial ] && serial=1
    evented=0; [ "$1" = evented ] && evented=1
    program="$bin/server"
    case $1 in
    std) program="$bin/std_server" ;;
    axum) program="$compare_dir/axum/target/release/axum_bench" ;;
    actix) program="$compare_dir/actix/target/release/actix_bench" ;;
    go|gin) program="$bin/${1}_bench" ;;
    node) program=node; set -- "$1" "$2" "$compare_dir/node/server.js" ;;
    fastapi)
        uv_workers=$WORKERS; [ "$uv_workers" = 0 ] && uv_workers=$cpus
        program="$compare_dir/fastapi/.venv/bin/uvicorn"
        set -- "$1" "$2" --app-dir "$compare_dir/fastapi" app:app --host 127.0.0.1 --port "$PORT" \
            --workers "$uv_workers" --log-level warning --no-access-log ;;
    esac
    mode_name=$1; mode_mw=$2; shift 2
    COMPARE_PORT=$PORT COMPARE_WORKERS=$WORKERS \
    AXUM_PORT=$PORT AXUM_WORKERS=$WORKERS AXUM_MIDDLEWARE=$mode_mw \
    NAHR_ACCESS_LOG=0 NO_COLOR=1 NAHR_BENCH_SERIAL=$serial NAHR_BENCH_EVENTED=$evented NAHR_BENCH_MIDDLEWARE=$mode_mw NAHR_BENCH_WORKERS=$WORKERS NAHR_BENCH_PORT=$PORT \
        "$program" "$@" > "$out/server-$mode_name-$mode_mw.log" 2>&1 &
    server_pid=$!
    i=0
    while [ $i -lt 100 ]; do
        if curl -s -o /dev/null "http://127.0.0.1:$PORT/plain" 2>/dev/null; then return 0; fi
        if ! kill -0 "$server_pid" 2>/dev/null; then
            wait "$server_pid"; status=$?
            server_pid=""
            if [ $status -gt 128 ]; then
                echo "  server crashed (signal $((status - 128))); skipping this mode."
            else
                echo "  server exited with code $status; skipping this mode."
            fi
            sed 's/^/    /' "$out/server-$mode_name-$mode_mw.log" | tail -n 15
            return 1
        fi
        sleep 0.1; i=$((i + 1))
    done
    echo "  server did not answer in 10 s; skipping this mode. Its log ($out/server-$mode_name-$mode_mw.log):"
    sed 's/^/    /' "$out/server-$mode_name-$mode_mw.log" | tail -n 15
    stop_server
    return 1
}
stop_server() {
    [ -n "$server_pid" ] && kill "$server_pid" 2>/dev/null && wait "$server_pid" 2>/dev/null
    server_pid=""
}
trap 'stop_server' EXIT INT TERM

run_one() {
    # $1 mode  $2 middleware  $3 endpoint  $4 connections
    case $3 in
        params) path="/params/7?q=a"; method=GET; body="" ;;
        echo) path="/echo"; method=POST; body="hello nahr" ;;
        *) path="/$3"; method=GET; body="" ;;
    esac
    hdr=""
    [ "$2" = 1 ] && hdr="Accept-Encoding: gzip"
    # Bodies every server answers the same way are checked byte for byte
    # (-e): a 2xx with another body is counted as "wrong", not as a success.
    # With gzip the body is compressed, so it is not checked.
    expect=""
    if [ "$2" = 0 ]; then
        case $3 in
            plain) expect="$out/expect-plain" ;;
            echo) expect="$out/expect-echo" ;;
        esac
    fi
    set -- "$@" "-o" "csv" "-c" "$4" "-t" "$LOAD_THREADS" "-d" "$DURATION" "-w" "$WARMUP" "-m" "$method" "-b" "$body"
    [ -n "$hdr" ] && set -- "$@" "-H" "$hdr"
    [ -n "$expect" ] && set -- "$@" "-e" "$expect"
    mode_name=$1; mode_mw=$2; shift 4
    line=$("$bin/nahr_load" "$@" "http://127.0.0.1:$PORT$path")
    echo "$mode_name,$mode_mw,$line" >> "$csv"
    echo "$line" | awk -F, -v m="$mode_name" -v mw="$mode_mw" -v checked="$expect" '{
        printf "  %-6s mw=%s %-5s %-15s c=%-4s %9.2f req/ms  p50 %7.3f  p99 %8.3f ms  err %s/%s", m, mw, $1, $2, $3, $7, $8, $10, $13, $14
        printf "  conn %s/%s", $18, $3
        if (checked != "") printf "  body %s", ($17 == 0 ? "ok" : $17 " wrong")
        printf "\n" }'
}

for mode in ${MODES:-serial pool evented}; do
    case $mode in serial|pool|evented) middlewares="0 1" ;; *) middlewares="0" ;; esac
    for mw in $middlewares; do
        echo "HTTP: mode=$mode middleware=$mw"
        start_server "$mode" "$mw" || continue
        case $mode in serial|pool|evented) endpoints=$ENDPOINTS ;; *) endpoints=plain ;; esac
        for ep in $endpoints; do
            for c in $CONNECTIONS; do
                run_one "$mode" "$mw" "$ep" "$c"
            done
        done
        stop_server
    done
done

{
    echo
    echo "## Over HTTP (keep-alive, nahr_load)"
    echo
    echo "req/ms is completed requests per millisecond; latency in ms."
    echo
    echo "| mode | middleware | request | connections | req/ms | p50 | p90 | p99 | p99.9 | max | non-2xx | socket errors |"
    echo "|---|---|---|---|---|---|---|---|---|---|---|---|"
    tail -n +2 "$csv" | awk -F, '{ printf "| %s | %s | %s %s | %s | %.2f | %.3f | %.3f | %.3f | %.3f | %.1f | %s | %s |\n", $1, ($2=="1"?"on":"off"), $3, $4, $5, $9, $10, $11, $12, $13, $14, $15, $16 }'
    echo
    echo "## Peak per endpoint"
    echo
    echo "| request | best req/ms | at | p99 there |"
    echo "|---|---|---|---|"
    tail -n +2 "$csv" | sort -t, -k4,4 -k9,9gr | awk -F, '!seen[$4]++ { printf "| %s %s | %.2f | %s, middleware %s, %s connections | %.3f ms |\n", $3, $4, $9, $1, ($2=="1"?"on":"off"), $5, $12 }'
} >> "$report"

# Ranking: GET /plain without middleware, per server, by its most
# connections; requests per second rounded to the thousand.
summary=$(tail -n +2 "$csv" | awk -F, '$4=="/plain" && $2=="0" {
        name=$1; if (name=="evented"||name=="pool"||name=="serial") name="Nahr (" name ")"
        else if (name=="std") name="SultanC std alone"
        if (!(name in seen)) { seen[name]=1; cmax[name]=$5+0; best[name]=$8+0; p99[name]=$12; cmin[name]=$5+0; low[name]=$8+0 }
        if ($5+0 > cmax[name]) { cmax[name]=$5+0; best[name]=$8+0; p99[name]=$12 }
        if ($5+0 < cmin[name]) { cmin[name]=$5+0; low[name]=$8+0 }
    } END { for (n in best) printf "%d\t%s\t%d\t%d\t%d\t%s\n", best[n], n, low[n], cmin[n], cmax[n], p99[n] }' | sort -t"$(printf '\t')" -k1,1nr)
if [ -n "$summary" ]; then
    echo
    echo "Ranking (GET /plain, requests per second):"
    printf '  %-4s %-22s %14s %14s %10s\n' "#" "server" "few conns" "many conns" "p99 (ms)"
    echo "$summary" | awk -F'\t' '{ printf "  %-4d %-22s %8d (c=%-3d) %8d (c=%-3d) %10s\n", NR, $2, $3, $4, $1, $5, $6 }'
    bad=$(tail -n +2 "$csv" | awk -F, '$4=="/plain" && $2=="0" && ($19+0 > 0 || $20+0 < $5+0) { print $1 }' | sort -u | tr '\n' ' ')
    if [ -n "$bad" ]; then
        echo "  ! not comparable (wrong bodies or connections not all established): $bad"
    else
        echo "  every /plain body checked byte for byte; every connection established"
    fi
fi
echo
echo "report:  $report"
echo "csv:     $csv"
