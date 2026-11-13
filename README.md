# Nahr

**Nahr** (نهر, "river") is a web framework for [SultanC](https://github.com/sultan-language/sultanc),
the Arabic-first systems language. It brings the model of axum and FastAPI to
SultanC: typed extractors, middleware, router composition, OpenAPI, templates,
WebSocket and server-sent events, and an in-process test client.

Every public name exists in Arabic and in English, and the two can be mixed in
one program. Nahr runs on SultanC's standard `std.http` server: HTTP parsing,
HTTP/2 and TLS stay in the standard library, and Nahr adds the application
layer on top.

> **Status:** early development (`0.1.0-dev`). The API may still change.
> Nahr follows SultanC's main branch and needs a SultanC tree from
> 2026-11-12 or later.

## Contents

- [Features](#features)
- [Quick start](#quick-start)
- [The showcase: a store over 100,000 products](#the-showcase-a-store-over-100000-products)
- [Examples](#examples)
- [Performance](#performance)
- [Tests](#tests)
- [Project layout](#project-layout)
- [Documentation](#documentation)
- [Known limitations](#known-limitations)

## Features

- **Routing:** every HTTP method, path parameters and wildcards, HEAD and 405
  handled for you, `merge` and `nest` that never leave a router half-changed.
- **Typed extractors:** path, query, headers, JSON, forms, multipart and bearer
  tokens, each answering the right status (400, 401, 413, 415, 422) before the
  handler runs.
- **Decorators:** `@protected`, `@gzipped`, `@body_limited`, `@observed` on a
  handler, and FastAPI-style routes declared on the function with `@@get_route`.
- **Middleware:** CORS, gzip, body limits, rate limits, request IDs, JSON
  errors, and your own, globally or per route.
- **JSON:** derived encoders and decoders (`@@json`) with FastAPI-style 422
  errors, and a streaming writer.
- **HTML:** Jinja-syntax templates with auto-escaping and inheritance, static
  files with ETags and precompressed variants, and assets embedded in the
  binary.
- **Live connections:** WebSocket (RFC 6455) and server-sent events, on every
  server mode.
- **OpenAPI 3.2:** documented routes registered through the normal router, and
  a docs page.
- **Serving:** an event-driven server (epoll / kqueue), a thread pool, HTTPS,
  and HTTP/2, with uvicorn-style logs and graceful shutdown on Ctrl+C.
- **Testing:** requests dispatched in-process, without sockets.

## Quick start

Nahr is built with the SultanC compiler. Put both checkouts side by side:

```text
work/
├── sultanc/    the SultanC repository, built (./build.sh)
└── nahr/       this repository
```

A complete application, in either language:

<table>
<tr><th>Arabic</th><th>English</th></tr>
<tr>
<td>

```sultan
من نهر.توجيه استورد موجه, أنشئ_موجها, جلب;
من نهر.معالجة استورد طلب, من_دالة;
من نهر.استخراج استورد معاملات_مسار;
من نهر.ردود استورد استجابة;
من نهر.جسم استورد رد_نصي;
من نهر.تشغيل استورد شغل_على;

عرف الصفحة_الأولى(الحالة: &عدد, الطلب: &طلب,
                  المعاملات: &معاملات_مسار): استجابة {
    دع النص: نص = «أهلا من نهر»;
    أرجع رد_نصي(200, &النص);
}

عرف الرئيسية(): عدد {
    دع الموجه: متغير موجه<عدد> = أنشئ_موجها(0);
    دع المسار: نص = «/»;
    طابق جلب(&متغير الموجه, &المسار, من_دالة(الصفحة_الأولى)) مع
    | نتيجة.خطأ(_) -> { أرجع 1; }
    | نتيجة.نجح(_) -> { };
    دع العنوان: نص = «127.0.0.1:8000»;
    طابق شغل_على(&العنوان, &الموجه) مع
    | نتيجة.خطأ(_) -> { أرجع 2; }
    | نتيجة.نجح(الرمز) -> { أرجع الرمز; };
}
```

</td>
<td>

```sultan
from nahr.routing import router, new_router, get;
from nahr.handler import request, from_fn;
from nahr.extract import path_params;
from nahr.response import response;
from nahr.body import text_response;
from nahr.serve import serve_on;

def home(state: &int, req: &request,
         params: &path_params): response {
    let body: string = "Hello from Nahr";
    return text_response(200, &body);
}

def main(): int {
    let app: mutable router<int> = new_router(0);
    let path: string = "/";
    match get(&mutable app, &path, from_fn(home)) with
    | result.err(_) -> { return 1; }
    | result.ok(_) -> { };
    let address: string = "127.0.0.1:8000";
    match serve_on(&address, &app) with
    | result.err(_) -> { return 2; }
    | result.ok(code) -> { return code; };
}
```

</td>
</tr>
</table>

Build and run it from the `work/` folder:

```bash
(cd sultanc && ./build/sultanc "$OLDPWD/nahr/examples/en/hello.sn" \
    --package-graph "$OLDPWD/nahr/examples/package-graph.toml" -o "$OLDPWD/hello")
./hello                 # http://127.0.0.1:8000
```

The compiler runs inside `sultanc/`, where it finds its standard library.
`--package-graph` tells it where the `nahr` package is; Supax, SultanC's
package manager, writes this graph itself
([details](docs/guide.md#building-without-supax)).

To run a program in the interpreter instead, without building it:

```bash
(cd sultanc && ./build/sultanc run --package-graph "$OLDPWD/nahr/examples/package-graph.toml" \
    "$OLDPWD/nahr/examples/en/hello.sn")
```

## The showcase: a store over 100,000 products

`examples/ar/store.sn` is a complete application, organized as a small
project:

| File | |
|---|---|
| `store.sn` | builds the catalog, registers the routes, starts the server |
| `store/catalog.sn` | 100,000 products in memory, an inverted index, search with Arabic normalization |
| `store/api.sn` | the HTTP handlers |
| `store/loadtest.sn` | a load generator with a latency histogram |
| `store/page.html` | the page: the store and a live load-test panel |

Every request filters, sorts and pages the catalog (search, category, price
range, four orders), in about a millisecond, reported in a `Server-Timing`
header. Invalid input answers 422. From the page, a load test sends requests
over many keep-alive connections and streams requests per second, p50 and p99
over server-sent events. Every response is checked byte for byte against the
expected body.

```bash
(cd sultanc && ./build/sultanc "$OLDPWD/nahr/examples/ar/store.sn" \
    --package-graph "$OLDPWD/nahr/examples/package-graph.toml" -b llvm -o "$OLDPWD/store")
./store                 # http://127.0.0.1:8000
```

| Route | |
|---|---|
| `GET /api/products` | `q`, `category`, `min`, `max`, `sort` (`newest`, `cheapest`, `priciest`, `rating`), `page`, `size` |
| `GET /api/products/{id}` | one product, 404 if absent |
| `GET /api/categories` | categories with their counts |
| `POST /api/load-test` | starts a load test (`product`, `browse` or `search`) |
| `GET /api/load-test/events` | the running test's report, as server-sent events |

The in-page test shares the server's process, so it is a live view, not a
benchmark. `bench/store.sh` loads the store from a separate process with the
same body checks, and reports how many connections were actually established.

## Examples

| Example | Shows |
|---|---|
| `ar/hello.sn`, `en/hello.sn` | the smallest application |
| `ar/api.sn`, `en/api.sn` | extractors, decorators, CORS, JSON errors, request IDs, OpenAPI |
| `ar/site.sn`, `en/site.sn` | a website: templates, static files, a form with Post/Redirect/Get, a JSON API |
| `ar/live.sn`, `en/live.sn` | WebSocket echo and server-sent events from a browser page |
| `ar/demo.sn` | a chat room and a live server dashboard in one binary |
| `ar/store.sn` | the showcase above |

Each file starts with the command that builds it. Use `-b llvm` for optimized
builds.

## Performance

Measured on one machine with the same load generator (`bench/load.c`) for
every server, `GET /plain` over keep-alive connections:

- At low connection counts, Nahr matches axum and Go's `net/http`.
- At high connection counts, Nahr is on par with Go's `net/http`, and behind
  axum and actix. The gap is in SultanC's standard HTTP server: Nahr runs
  within about 2% of `std.http` alone, so improvements there apply to Nahr
  directly.

Results depend on the machine, so the benchmark is meant to be run, not
quoted:

```bash
SULTANC_ROOT="$PWD/sultanc" nahr/bench/run.sh quick                    # Nahr only
MODES="evented std axum actix go gin fastapi node" \
    SULTANC_ROOT="$PWD/sultanc" nahr/bench/run.sh                      # with other frameworks
SULTANC_ROOT="$PWD/sultanc" nahr/bench/store.sh                        # the store, under load
```

Every run validates response bodies, not only status codes, and prints a
ranking at the end. The comparison servers and what each one needs are in
[`bench/compare`](bench/compare/README.md); the method is in
[`bench/README.md`](bench/README.md).

## Tests

```bash
SULTANC_ROOT="$PWD/sultanc" nahr/tests/run.sh
```

The tests are `@@اختبار` (`@@test`) functions, run by `sultanc test`: they
are built once, and each runs in its own process. They cover routing,
middleware, decorators, extractors, WebSocket and SSE, OpenAPI, templates,
static files, rate limits, the English names, and every public generic
function. The script then builds all ten examples.

| Variable | |
|---|---|
| `NAHR_INTERP=1` | run the tests in the interpreter |
| `NAHR_TEST_FILTER=text` | run only the tests whose name contains `text` |

A failure names the test, the location and the check that failed:

```text
نجح التوجيه
فشل المسارات_المزخرفة: أرجع خطأ
    --> tests/decorated_routes.sn:43:5
    لم يتحقق: عدد_المسارات_المزخرفة() != 3
```

## Project layout

```text
nahr/
├── src/            the framework, one directory per package (nahr.routing, nahr.json, ...)
│   └── nahr.sn     the package root: the Arabic names of the directories
├── examples/       ar/ and en/ examples, and the site's templates and static files
├── tests/          the test suite and tests/run.sh
├── bench/          load generator, benchmark servers, comparisons, bench/run.sh
├── docs/           the guide
├── tools/          package_graphs.py
└── Supax.toml      the package manifest
```

## Documentation

- [Guide](docs/guide.md): every package, extractors, middleware, templates,
  static files, live connections, OpenAPI, serving and logging.
- [Benchmark](bench/README.md): what is measured and how.
- [Changelog](CHANGELOG.md), and the [development log](docs/development-log.md)
  with the SultanC issues found while building Nahr.

## Known limitations

- The interpreter runs one OS thread: use `serve_on` / `شغل_على` under
  `sultanc run`, and a small catalog for the store (`NAHR_PRODUCTS=500`).
- On Windows, the event-driven server serves one connection at a time until
  SultanC's standard library supports IOCP.
- A handler that blocks holds its event-loop worker; start more workers than
  cores when handlers wait on I/O.
- `sultanc test` does not yet run definition-time decorators (`@@`), so the
  decorated-routes test fails under it while the feature works in programs.
