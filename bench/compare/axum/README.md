# axum comparison

The same endpoints as `../../server.sn` (`/plain`, `/json`, `/large`) in
axum 0.7 on tokio, with an optional middleware stack (tower-http request ID
and gzip, the nearest equivalents of Nahr's `request_id` and `compression`).
Nahr's stack also has `json_errors` and a rate limiter, so with middleware
axum does a little less work.

```bash
cd nahr/bench/compare/axum && cargo build --release
```

Run both servers with the same worker count and the same load tool:

```bash
AXUM_PORT=8091 AXUM_WORKERS=2 nahr/bench/compare/axum/target/release/axum_bench &
NAHR_BENCH_PORT=8090 NAHR_BENCH_WORKERS=2 NAHR_BENCH_EVENTED=1 ./nahr_bench_server &
nahr_load -c 32 -t 8 -d 5 -w 1 http://127.0.0.1:8091/plain
nahr_load -c 32 -t 8 -d 5 -w 1 http://127.0.0.1:8090/plain
```

Use enough load threads (`-t`) that the load tool is not the limit: on one
machine the client and the server share the CPUs.
