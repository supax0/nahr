# Other frameworks

The same `GET /plain` → `ok` in other frameworks, run by `bench/run.sh`
under the same load tool, on the same machine, with the same worker count:

| mode | framework | needs |
|---|---|---|
| `axum` | axum 0.7 on tokio (Rust) | cargo |
| `actix` | actix-web 4 (Rust) | cargo |
| `go` | Go's net/http | go |
| `gin` | Gin 1.10 (Go) | go |
| `fastapi` | FastAPI on uvicorn with uvloop/httptools (Python) | python3 |
| `node` | Node's http module, one process per core (cluster) | node |
| `std` | SultanC std's HTTP server alone, no Nahr code | |

```bash
BACKEND=llvm MODES="axum actix go gin fastapi node std evented" ENDPOINTS=plain \
  CONNECTIONS="2 32" SULTANC_ROOT="$PWD/sultanc" nahr/bench/run.sh quick
```

A mode whose tool is missing is skipped. The first run builds the Rust and Go
servers and makes a virtualenv for FastAPI. The run ends with a ranking.

Each server reads `COMPARE_PORT` and `COMPARE_WORKERS` (0 = every core); axum
also reads its older `AXUM_*` names and has an optional middleware stack (see
`axum/README.md`). Only `/plain` is compared: the other endpoints are Nahr's.
