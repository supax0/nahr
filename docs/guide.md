# Nahr guide

The full reference for Nahr's packages. The [README](../README.md) covers
installation, the examples and the project layout.

Most snippets use the Arabic names. Every public name has an English twin
(`نهر.توجيه` / `nahr.routing`, `جلب` / `get`), and both can be mixed in one
program.

## Contents

- [Packages](#packages)
- [Routing](#routing)
- [Configuration as data](#configuration-as-data)
- [Typed handlers](#typed-handlers)
- [Decorators](#decorators)
- [Middleware](#middleware)
- [Errors as JSON, request IDs](#errors-as-json-request-ids)
- [Rate limiting](#rate-limiting)
- [JSON](#json)
- [Derived JSON (`@@json`)](#derived-json-json)
- [HTML templates](#html-templates)
- [Static files](#static-files)
- [Files](#files)
- [Files in the binary](#files-in-the-binary)
- [WebSocket and SSE](#websocket-and-sse)
- [OpenAPI](#openapi)
- [Serving: threads, HTTPS, HTTP/2](#serving-threads-https-http2)
- [Diagnostics](#diagnostics)
- [Building without Supax](#building-without-supax)

## Packages

| English | Arabic | Contents |
|---|---|---|
| `nahr.routing` | `نهر.توجيه` | router, method helpers, global middleware, merge/nest |
| `nahr.handler` | `نهر.معالجة` | handler type and adapters, extractor-driven handlers |
| `nahr.extract` | `نهر.استخراج` | path, query, header, body, bearer, multipart extractors |
| `nahr.response` | `نهر.ردود` | response type, headers, results, files |
| `nahr.body` | `نهر.جسم` | text/HTML/bytes/empty/redirect responses |
| `nahr.middleware` | `نهر.وسطاء` | route middleware, CORS, gzip, body limit, bearer, observer |
| `nahr.json` / `nahr.form` | `نهر.جسون` / `نهر.نموذج` | typed JSON and form extraction |
| `nahr.extension` | `نهر.سياق` | request-local context attributes |
| `nahr.cookies` / `nahr.session` | `نهر.كعكات` / `نهر.جلسات` | cookies, application-backed sessions |
| `nahr.validation` | `نهر.تحقق` | validation helpers and validated extractors |
| `nahr.openapi` | `نهر.توثيق` | OpenAPI 3.2.0 model, documented routes, JSON, docs page |
| `nahr.sse` | `نهر.أحداث` | SSE event encoding, buffered event-stream responses |
| `nahr.websocket` | `نهر.مقبس_ويب` | RFC 6455 handshake, frames, message assembly |
| `nahr.template` | `نهر.قوالب` | HTML templates (Jinja syntax) with auto-escaping |
| `nahr.log` | `نهر.سجلات` | uvicorn-style diagnostics: levels, colors, access lines |
| `nahr.live` | `نهر.مباشر` | live WebSocket connections and streamed responses |
| `nahr.serve` | `نهر.تشغيل` | serving over `std.http`, lifecycle hooks, capabilities |
| `nahr.error_handling` | `نهر.أخطاء` | application error conversion |
| `nahr.testing` | `نهر.اختبار` | in-process requests, no sockets |

## Routing

GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS, CONNECT and TRACE helpers. A HEAD
request falls back to the GET route, and a 405 lists `HEAD` next to `GET`.
`ادمج` (merge) and `اربط` (nest) copy routes atomically: a conflict leaves the
router unchanged. Nesting `"/"` under `"/api"` serves `"/api"`.

## Configuration as data

SultanC closures may capture only plain values: numbers, booleans and
function values. A closure cannot hold a text name, a vector or a reference.
Nahr is built around that rule:

- A **handler** (`معالج<S>`) is a record: a run function plus a vector of text
  arguments. `من_دالة(f)` wraps the canonical
  `f(&S, &طلب, &معاملات_مسار): استجابة`; `من_بسيط`, `من_حالة`, `من_طلب`,
  `من_مسار` and `من_سياق` adapt simpler shapes. The context of `من_سياق`
  borrows the request and its parameters; only the attributes are owned.
- An **extractor** (`مستخرج<S, T>`) is the same kind of record. A parameter or
  header name is the extractor's argument, not a captured value.
  `مع_استخراج`, `مع_استخراجين` and `مع_ثلاثة_استخراجات` concatenate the
  extractors' arguments and hand each extractor its offset.
- **Middleware** is also a record. Global middleware (`وسيط<S>`) receives
  `&التالي<S>` and continues with `تابع(التالي, الطلب)`; route middleware
  (`وسيط_مسار<S>`) receives `&التالي_مسار<S>` and continues with
  `تابع_مسار`. `وسيط_من_دالة` and `وسيط_مسار_من_دالة` wrap plain functions;
  `وسيط_بمعطيات` builds configured middleware.
- The **router** owns every route's handler. The closure it registers with
  `std.http` captures only the route's index.

Function values (decoders, validators, loaders, observers) are plain, so
extractors and middleware built from them work as before.

## Typed handlers

Extractors are ordinary typed functions. They produce the value a handler
needs, or the HTTP response that ends the request before the handler runs.

```sultan
من نهر.معالجة استورد مع_استخراجين;
من نهر.استخراج استورد
    مستخرج,
    استخرج_معامل_مسار_طبيعي,
    استخرج_معامل_استعلام_مطلوب;

ليكن id: نص = «id»;
ليكن q: نص = «q»;
ليكن المعرف: مستخرج<عدد, طبيعي> = استخرج_معامل_مسار_طبيعي(&id);
ليكن البحث: مستخرج<عدد, نص> = استخرج_معامل_استعلام_مطلوب(&q);
ليكن المعالج: معالج<عدد> = مع_استخراجين(المعرف, البحث, ابحث_عن_مستخدم);
```

Bind extractors with their types, as above. SultanC infers a generic call's
type arguments from its own arguments or from a typed binding, not from an
enclosing call, so `مع_استخراجين(استخرج_…(&id), …)` written inline does not
type-check.

Path parameters are percent-decoded and checked as UTF-8
(`/users/%D8%B9%D9%84%D9%8A` gives `علي`); `معامل_مسار_خام` returns the raw
segment. Query values are decoded by std. A missing or unexpected
Content-Type on JSON, form and multipart bodies is 415, other body failures
are 400, and oversized multipart bodies are 413.

## Decorators

SultanC decorators wrap a function, so Nahr's handler decorators protect,
limit, compress or observe one handler wherever it is registered:

```sultan
@مضغوط
@محمي(رمز_مقبول)
عرف التقرير(الحالة: &عدد, الطلب: &طلب, المعاملات: &معاملات_مسار): استجابة { … }
```

```sultan
@gzipped
@protected(token_ok)
def report(state: &int, req: &request, params: &path_params): response { … }
```

| Arabic | English | Effect |
|---|---|---|
| `@محمي(مدقق)` | `@protected(validator)` | bearer token required, 401 otherwise |
| `@بحد_جسم(حد)` | `@body_limited(limit)` | 413 above the limit |
| `@مضغوط` | `@gzipped` | gzip the reply (1 KiB or more) |
| `@مراقب(دالة)` | `@observed(fn)` | call fn with the request and reply |

They apply to the canonical handler shape (state, request, path parameters)
and stack from the declaration outwards: in the example, the token is checked
first and the reply is then compressed.

### Routes on the function (`@@`)

Definition-time decorators (`@@`) run once before `main`, so a route can be
declared on its handler, as FastAPI's `@app.get`:

```sultan
@@مسار_جلب(«/users/{id}»)
عرف مستخدم(الطلب: &طلب, المعاملات: &معاملات_مسار): استجابة { … }
```

```sultan
@@get_route("/users/{id}")
def user(req: &request, params: &path_params): response { … }
```

Then `أضف_المسارات_المزخرفة(&متغير الموجه)` / `add_decorated_routes(&mutable app)`
registers them in declaration order. Also `@@مسار_إرسال` / `@@post_route`, PUT,
PATCH, DELETE, and `@@مسار(«METHOD», «/path»)` / `@@route`. A decorator can't be
generic, so these handlers take the request and its path parameters but not
the router's state; handlers that need the state are registered with
`جلب`/`get`.

## Middleware

```sultan
استخدم_وسيطا(&متغير الموجه, الوسيط);              // global, registration order
ليكن _عدد: طبيعي = استخدم_وسيطا_للمسارات(&متغير الموجه, &الحماية);
```

Route middleware wraps the routes registered so far (as axum's
`route_layer`), so register the protected routes first.

- **CORS** (`سياسة_الأصول`): an origin allow-list or `*`; returns an error
  for `*` with credentials instead of reflecting every origin. Reflected
  origins add `Vary: Origin`; preflights answer 204 with methods, headers and
  `Access-Control-Max-Age`.
- **gzip** (`ضغط`): honours `q=0`, `*`, and every Accept-Encoding line; skips
  HEAD, 1xx/204/206/304, `Cache-Control: no-transform`, encoded and
  already-compressed media; adds to `Vary` without dropping other entries,
  and weakens strong ETags.
- **Body limit** (`حد_الجسم`): 413 above the limit. std has already read the
  body by then, so lower the server's own limit in `إعداد` to bound memory.
- **Bearer** (`يتطلب_حاملا`, `استخرج_رمز_حامل`): case-insensitive scheme,
  RFC 6750 token syntax, and `error="invalid_request"` / `"invalid_token"`
  challenges.

## Errors as JSON, request IDs

- `أخطاء_جسون` / `json_errors` turns every text/plain error response,
  including 404/405 from routing and extractor rejections, into
  `{"error":{"status":404,"message":"Not Found"}}`, keeping headers such as
  `Allow` and `WWW-Authenticate`. Register it first so it sees every response.
- `حول_الأخطاء` / `map_errors` calls your own function on every response with
  status 400 or above.
- `معرف_الطلب` / `request_id` keeps a usable incoming `X-Request-Id` or
  generates a UUID-shaped ID (unique, with no system call per request), gives it
  to the handler on the request, and returns it on the response. These IDs are
  for tracing and are predictable; don't use them as tokens.

## Rate limiting

```sultan
ليكن المفتاح: مفتاح_معدل<عدد> = مفتاح_بالرأس(&«x-api-key»);
ليكن الحد: وسيط<عدد> = حد_المعدل(100, 60, المفتاح);   // 100 per minute per key
استخدم_وسيطا(&متغير الموجه, الحد);
```

Fixed windows. Over the limit, a request gets 429 with `Retry-After`. The
counters live in the middleware and are shared by all worker threads.
`مفتاح_بالعنوان` / `client_address_key` gives one budget per client IP
address; `مفتاح_عام` / `global_key` one budget for every request;
`مفتاح_بالرأس` / `header_key` one per header value (an API key). Behind a
reverse proxy every request comes from the proxy, so key on the header it sets
(x-forwarded-for) instead.

## JSON

`nahr.json` reads JSON bodies through your decoder (`استخرج_جسونا`) and writes
JSON with a streaming writer that inserts commas and escapes strings:

```sultan
نوع مستخدم = { الاسم: نص, العمر: عدد };

عرف رمز_مستخدم(المستخدم: &مستخدم, الكاتب: &متغير كاتب_جسون): فراغ {
    ابدأ_كائنا(الكاتب);
    اكتب_حقلا_نصيا(الكاتب, &الاسم_مفتاح, &(*المستخدم).الاسم);
    اكتب_حقلا_عدديا(الكاتب, &العمر_مفتاح, (*المستخدم).العمر);
    أنه_كائنا(الكاتب);
}

أرجع رد_جسون_بـ(200, &المستخدم, رمز_مستخدم);
```

`اكتب_مصفوفة_بـ` writes vectors with the same encoder. A writer used wrongly
(unbalanced containers, a value where a key belongs, invalid UTF-8) answers
500 rather than sending broken JSON. `وثيقة_جسون_إلى_نص` and `رد_جسون`
serialize std.json documents with the same escaping.

## Derived JSON (`@@json`)

`@@json` on a type makes the compiler generate `to_json__T` and
`from_json__T`. Nahr puts them on requests and responses:

```sultan
@@json
type item = { name: string, price: int, tags: vector string, note: option string };

match read_json_with(req, from_json__item) with
| result.ok(value) -> { return json_response_of(201, &value, to_json__item); }
| result.err(rejection) -> { return rejection; };
```

A non-JSON Content-Type is 415; a body that does not decode is 422 with
`{"detail": "price: expected an integer"}` (the field path), as FastAPI answers
validation errors.

## HTML templates

`نهر.قوالب` / `nahr.template` renders HTML with Jinja's syntax, the one
FastAPI and Flask use (and axum through minijinja). Output is HTML-escaped
unless a value is marked safe, as in Jinja's autoescape and Go's
html/template.

```jinja
{% extends "base.html" %}
{% block content %}
  <h1>{{ title }}</h1>
  {%- for p in products %}
  <p>{{ loop.index }}. {{ p.name }}: {{ p.price }}</p>
  {%- else %}
  <p>Nothing yet.</p>
  {%- endfor %}
  {% include "partials/footer.html" %}
{% endblock %}
```

- Tags: `{{ }}`, `{% if %}/{% elif %}/{% else %}/{% endif %}`,
  `{% for x in xs %}…{% else %}…{% endfor %}` (with `loop.index`, `index0`,
  `first`, `last`, `length`, `revindex`), `{% include %}`, `{% extends %}` and
  `{% block %}` (any depth), `{# #}`, and `{%-`/`-%}` whitespace trimming.
- Expressions: paths (`user.name`, `items.0`), strings, integers,
  `true`/`false`/`none`, `not`/`and`/`or`, `== != < <= > >=`, parentheses.
- Filters: `safe`, `escape`/`e`, `length`, `default(x)`, `join(sep)`,
  `upper`, `lower`, `trim`.
- Values: SultanC has no reflection, so a handler builds a context:

```sultan
ليكن السياق: متغير سياق_قالب = [];
عين_قيمة(&متغير السياق, «title», قيمة_نص(«المتجر»));
عين_قيمة(&متغير السياق, «products», قائمة_بـ(&المنتجات, قيمة_منتج));
أرجع رد_قالب(&(*الحالة).القوالب, «shop.html», &السياق);
```

- Loading: `حمل_قوالب(«templates»)` / `load_templates` parses every file
  under the folder once (subfolders give names like `pages/home.html`). A
  syntax error names the file and line. Set `إعادة_التحميل` to read the folder
  again on every render while developing, and `صارم` to make undefined names an
  error (Jinja's StrictUndefined).
- Responses: `رد_قالب` / `template_response` answers 200 with
  `text/html; charset=utf-8`; `رد_قالب_بحالة` takes a status. A render error
  is logged to stderr and answered 500.

## Static files

```sultan
اربط_ملفات(&متغير الموجه, &«/static», &«./public»)
```

registers `GET /static/{*path}` with the defaults: `index.html` for a
folder, a 301 to add a missing trailing slash, `charset=utf-8` on text types,
a weak ETag and 304, and 404 for missing files and for paths that could leave
the folder. `اربط_ملفات_بإعداد` / `serve_dir_with` takes `إعداد_ملفات` /
`static_config`, after tower-http's ServeDir and FastAPI's StaticFiles:

| field | |
|---|---|
| `الفهرس` | the folder's index file, `index.html`; empty: folders are 404 |
| `التخزين` | Cache-Control for every file, e.g. `public, max-age=31536000, immutable` |
| `تخزين_الصفحات` | Cache-Control for HTML instead, e.g. `no-cache` |
| `مضغوطة` | serve `file.br` / `file.gz` when the client accepts them |
| `البديل` | a file served with 200 when no file matches (single-page apps) |

Mounting at `«/»` serves a whole site.

## Files

`رد_ملف_من_دليل(&الدليل, &النسبي)` serves a request-supplied path from inside a
directory: absolute paths, `..`, backslashes and NUL are 404, missing files
are 404, permission failures 403. `رد_ملف` reads an exact path and is not for
request-supplied paths.

## Files in the binary

`ضمن_ملف(«path»)` / `embed_file("path")` (the compiler reads the file at build
time) gives a binary that carries its assets, as Go's `embed`:

```sultan
اربط_ملفا_مضمنا_بتخزين(&متغير الموجه, &«/static/app.js», ضمن_ملف(«public/app.js»), «public, max-age=3600»);
أضف_قالبا(&متغير القوالب, «base.html», ضمن_ملف(«templates/base.html»));
```

Embedded routes send the content type of the path's extension, a weak ETag and

## WebSocket and SSE

Live routes keep their connection after the head, as FastAPI's
`@app.websocket` and `StreamingResponse`, axum's `WebSocketUpgrade` and `Sse`:

```sultan
اربط_مقبس_ويب(&متغير الموجه, &«/ws», صدى);       // websocket_route
اربط_أحداث(&متغير الموجه, &«/events», نبضات);    // sse_route
اربط_تدفقا(&متغير الموجه, &«GET», &«/export.csv», &«text/csv», صدّر);  // stream_route
```

```sultan
def echo(state: &app, req: &request, params: &path_params, conn: &mutable websocket_connection): void {
    match websocket_receive(conn) with
    | result.ok(message) -> {
        let text: string = message_text(&message);
        let sent: bool = websocket_send_text(conn, &text);
    }
    | result.err(_) -> { };
}
```

- The route answers like any other, so middleware runs first (auth can refuse
  the upgrade). After the 101 or the streamed head, std hands the socket over
  and the handler runs on a thread of its own, so the server's workers stay
  free; Nahr closes the socket when the handler returns.
- `استقبل_رسالة_مقبس` / `websocket_receive` answers pings, echoes a close and
  reassembles fragments; `أرسل_نصا_مقبس`, `أرسل_بايتات_مقبس`, `أغلق_مقبسا`
  send. `أرسل_حدثا` / `stream_send_event` sends one SSE event, `أرسل_جزءا` /
  `stream_send` any chunk; each answers false once the client is gone.
- Works on every server: one thread, the pool, the event loop, and HTTPS.
  `examples/ar/live.sn` and `examples/en/live.sn` use both from a browser page.
- Underneath: handshake validation and the RFC 6455 accept key, frame rules
  (reserved bits, masking, control frames, close codes and UTF-8 reasons),
  bounded message assembly, and SSE events that refuse CR/LF/NUL in single-line
  fields.

## OpenAPI

Documented routes register through the normal router with `سجل_موثقا`
(`documented_route`); metadata never creates a second routing pipeline.
`اربط_موثقا` (`nest_documented`) nests a sub-router and its document with the
same prefix, so the published paths are the served paths. The document is
serialized as OpenAPI 3.2.0. `معالج_المخطط` serializes once when created;
`معالج_صفحة_التوثيق` serves a docs page that loads `openapi.json` relative to
itself (`معالج_صفحة_توثيق_بمخطط` takes another URL). CONNECT and other
non-fixed methods use 3.2's `additionalOperations`.

## Serving: threads, HTTPS, HTTP/2

| Arabic | English | |
|---|---|---|
| `شغل_على(&العنوان, &الموجه)` | `serve_on` | one connection at a time |
| `شغل_على_بأحداث(&العنوان, الموجه, الخيوط)` | `serve_on_evented` | **recommended:** std's event-driven server (epoll/kqueue), thousands of connections |
| `شغل_على_متوازيا(&العنوان, الموجه, العمال)` | `serve_on_parallel` | a pool of OS threads (0 = one per CPU) |
| `شغل_آمنا_على(&العنوان, &ملف_p12, &كلمة_المرور, &الموجه)` | `serve_tls_on` | HTTPS |
| `شغل_آمنا_على_متوازيا(…, الموجه, العمال)` | `serve_tls_on_parallel` | HTTPS on a thread pool |

- **Event-driven (recommended):** every connection waits non-blocking in one
  poller, and worker threads (0 = one per CPU) take connections as they become
  ready, so idle keep-alive clients cost no thread. A blocking handler holds
  only its own worker, so use more workers than CPUs when handlers wait on
  I/O. Windows falls back to one connection at a time until std has IOCP.
- **Thread pool:** the workers share one listening socket, and each accepts and
  serves its own connections. The router moves into an Arc, so pass it by
  value. `إعداد_توازي` / `parallel_config` sets the worker count and the
  per-connection read and write timeouts (30 s by default), so an idle
  keep-alive client is dropped instead of holding a worker.
- **Shared state:** handlers then run on several threads at once with the same
  `&S`. Anything in `S` that changes must be a std.sync type (atomics, `قفل`).
- **HTTP/2:** std's server answers HTTP/2 with prior knowledge (h2c) and, over
  TLS, whatever ALPN picks (`h2` or `http/1.1`). Nahr needs no change for
  either.
- **HTTPS identity:** read from a PKCS#12 file (`.p12` / `.pfx`).
- **Interpreter:** it runs one OS thread, so use `شغل_على` under
  `sultanc run`.
- **What the pool speeds up:** it helps handlers that wait (I/O, sleeping,
  other services). CPU work that allocates heavily, including std's TLS
  handshakes, currently contends on std's allocator and gains little from more
  threads.

## Diagnostics

Every server prints uvicorn's lines (uvicorn is the server FastAPI runs on)
to standard error, with the level colored when standard error is a terminal:

```text
INFO:     Started server process [4182]
INFO:     Nahr: 7 routes, 2 middleware, a pool of 2 threads
INFO:     Nahr running on http://127.0.0.1:8000 (Press CTRL+C to quit)
INFO:     127.0.0.1:50254 - "GET / HTTP/1.1" 200 OK 1.57ms
INFO:     127.0.0.1:50268 - "POST /notes HTTP/1.1" 303 See Other 0.07ms
INFO:     127.0.0.1:50280 - "GET /missing HTTP/1.1" 404 Not Found 0.61ms
INFO:     Shutting down (Ctrl+C)
INFO:     Waiting for requests in progress to finish. (CTRL+C to force quit)
INFO:     Finished server process [4182]
ERROR:    could not serve on 127.0.0.1:8000: address already in use (errno 98); is another server running on this port?
ERROR:    template error: pages/shop.html:12: unknown filter: price
```

Access lines add the time the request took, as tower-http's trace layer does
for axum. With `NAHR_LOG_LEVEL=debug` the route table is printed at startup.

**Graceful shutdown.** Ctrl+C or SIGTERM stops accepting connections, lets the
requests in progress finish (their responses close the connection), and the
serve function returns, as uvicorn and Go's `Server.Shutdown` do; a second
Ctrl+C quits at once. Live sessions (WebSocket, streams) end with the
process. A program that starts its own threads before serving should call
`فعل_الإيقاف_الآمن` / `enable_graceful_shutdown` first in `main`.

Settings come from the environment:

| variable | |
|---|---|
| `NAHR_LOG_LEVEL` | `debug`, `info` (default), `warning`, `error` |
| `NAHR_ACCESS_LOG` | `0` turns access lines off (uvicorn's `--no-access-log`) |
| `NAHR_LOG_COLOR` | `auto` (default), `always`, `never`; `NO_COLOR` also turns colors off |
| `NAHR_LOG_TIME` | `1` starts lines with the UTC time (RFC 3339), as Go's log does |
| `NAHR_GRACEFUL` | `0` leaves Ctrl+C to end the process at once |
| `NAHR_HANDLER_TIMEOUT_MS` | a handler running longer gets 503 and its request is cancelled |

Applications log with `سجل_معلومة` / `log_info`, `سجل_تحذير` / `log_warning`,
`سجل_عطل` / `log_error` and `سجل_تصحيح` / `log_debug`. Access lines cost about
13% of throughput on a trivial route; the benchmark turns them off. A handler
can check `ألغي_الطلب` / `request_cancelled` between steps when a timeout is
set.

## Building without Supax

The compiler does not read `Supax.toml`: Supax, the package manager, turns
the manifests into a package graph and passes it to the compiler with
`--package-graph`. To build with `sultanc` alone, pass the graph Nahr ships
for its examples (the tests and the benchmark have their own, and their
scripts pass them):

```bash
(cd sultanc && ./build/sultanc "$OLDPWD/nahr/examples/en/hello.sn" \
    --package-graph "$OLDPWD/nahr/examples/package-graph.toml" -o "$OLDPWD/hello")
```

The graphs say where the `nahr` package is (`src/`) and its Arabic name
`نهر`. They are generated from the `Supax.toml` files by
`python3 tools/package_graphs.py`; run it after changing a manifest. The
Arabic names of Nahr's directories (`نهر.توجيه` for `nahr.routing`) are
declared in the package's root file, `src/nahr.sn`
(`module routing { ar: توجيه };`), which the compiler reads in every build.
Without a graph, `import nahr.…` fails with
`SULTANC-MODULE-NOT-FOUND`.
