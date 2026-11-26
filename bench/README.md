# Nahr benchmark and stress test

Measures what Nahr can handle at two levels.

1. **In-process** (`inprocess.sn`): Nahr's dispatch cost per request on one
   thread, through the test client, with no sockets. It shows what the
   framework and std cost per request.
2. **Over HTTP** (`server.sn` + `load.c`): real throughput and latency with
   keep-alive connections, for every endpoint, single-thread and thread pool,
   with and without the middleware stack, at several connection counts.

## Run

From the folder that holds `nahr` and `sultanc`:

```bash
SULTANC_ROOT="$PWD/sultanc" nahr/bench/run.sh          # full matrix (~10 min)
SULTANC_ROOT="$PWD/sultanc" nahr/bench/run.sh quick    # ~1 min
```

The runner needs `cc` and `curl`. It builds everything into the results folder
and writes:

- `nahr/bench/results/<time>/report.md`: in-process table, every HTTP run,
  and the peak per endpoint;
- `nahr/bench/results/<time>/results.csv`: one row per HTTP run.

Settings are environment variables:

| variable | default | |
|---|---|---|
| `DURATION` | 5 | seconds measured per run |
| `WARMUP` | 1 | seconds before measuring |
| `CONNECTIONS` | `1 16 64` | keep-alive connections per run (at least one per load thread) |
| `LOAD_THREADS` | 2 | load-generator threads |
| `WORKERS` | 0 | server pool size (0 = one per CPU) |
| `ENDPOINTS` | all | `plain json params echo large sleep cpu alloc` |
| `PORT` | 8090 | |
| `MODES` | `serial pool evented` | add `axum actix go gin fastapi node` for the same `/plain` in other frameworks (`compare/README.md`), add `std` for std's event-driven server with no Nahr code (`std_server.sn`, `/plain` only): if `std` slows down the same way as `evented`, the cause is in std, not Nahr |
| `BACKEND` | native | `native` or `llvm` (the compiler must be built with `--enable-llvm`); every Nahr server is built with `-O2` |

## Endpoints

| endpoint | measures |
|---|---|
| `GET /plain` | the floor: routing plus a 2-byte reply |
| `GET /json` | JSON writer |
| `GET /params/7?q=a` | two extractors (uint path parameter, query) |
| `POST /echo` | text body extractor |
| `GET /large` | 64 KiB body (with middleware: gzip of it) |
| `GET /sleep` | a handler that waits 10 ms, like a database call |
| `GET /cpu` | ~1 ms of arithmetic, no allocation |
| `GET /alloc` | allocation-heavy handler |

The middleware stack is `json_errors` + `request_id` + `rate_limit` (with a
limit too high to trigger, so only its cost counts) + `compression(1024)`.

## The load generator

`load.c` keeps each connection's request in flight and reads the full response
(Content-Length or chunked). It records latency in a 1 µs histogram up to
10 ms and a 100 µs one above. It works on its own too:

```bash
cc -O2 -pthread -o nahr_load nahr/bench/load.c
./nahr_load -c 64 -t 4 -d 10 http://127.0.0.1:8090/plain
./nahr_load -c 16 -m POST -b "hello" http://127.0.0.1:8090/echo
```

It prints requests, req/s, req/ms, MB/s, latency (p50, p90, p99, p99.9, max)
and socket errors. `-o csv` gives one CSV line.

## Reading the numbers

- The load generator runs on the same machine as the server and takes CPU from
  it. On a 2-CPU machine it can take half the CPU, so for production numbers
  run `nahr_load` from a second machine.
- `req/ms` counts completed requests per millisecond: 6.5 req/ms is 6,500
  req/s.
- The in-process numbers are the most stable. Use them to compare Nahr
  versions; use the HTTP numbers for capacity.

## Checked responses

`nahr_load -e FILE` compares every response body with FILE byte for byte;
a 2xx with another body is counted as wrong, not as a success. `run.sh`
checks `/plain` and `/echo` this way for every server (the bodies are the
same in all of them), and every run reports how many connections were
established (`conn 32/32`). The ranking says when a result is not
comparable.

## The store under load

`store.sh` builds `examples/ar/store.sn`, starts it, and loads it from a
separate process with checked bodies: one product, a category page (a scan
of 100,000 products), and a text search. Expected bodies are in
`store-expected/` (the catalog is the same in every run); the unloaded
answer is compared first.

```bash
SULTANC_ROOT="$PWD/sultanc" nahr/bench/store.sh
CONNECTIONS="16 64" SERVER_CPUS=0-5 LOAD_CPUS=6-11 SULTANC_ROOT="$PWD/sultanc" nahr/bench/store.sh   # Linux, pinned
```

It measures Nahr alone. A comparison with another framework needs the same
store written in it and run under the same script; until then, compare
frameworks only with `run.sh` (`/plain`).
