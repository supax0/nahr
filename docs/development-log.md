# Development log

Notes kept while Nahr was ported to and tested against successive SultanC
trees: what changed in Nahr on each tree, and the compiler and standard
library issues found along the way, numbered for the SultanC maintainers
(see "SultanC findings"). For a summary of Nahr's features, see the
[changelog](../CHANGELOG.md).

## Port to the 2026-11-05 SultanC tree

## Language updates

- Renames applied with the compiler's own `tools/rename/rename_tokens.py`
  (waves 1, 2, 3 with segments, 7): `طالما`, `اختياري`/`موجود`,
  `طبيعي`/`ط8…ط64` (identifiers too: `استخرج_معامل_مسار_طبيعي`), and the
  entry function `الرئيسية`. The example's home handler, previously also named
  `الرئيسية`, is now `الصفحة_الأولى`.
- Ownership: reads that moved owned values out of borrows (`*ref`,
  `(*ref).field`) now clone; the copy-out/append/write-back vector pattern
  became direct appends.
- Syntax: record and vector literals only appear as `let` initializers; a
  generic alias is `عام نوع name<T> = …`.
- `json.sn`, `form.sn` and `extension.sn` moved into `json/`, `form/` and
  `extension/context.sn`, since from-imports resolve package directories.

## Redesign: configuration as data (API change)

The checker lets closures capture only plain values (numbers, booleans,
function values). Nahr's extractors, middleware chain, CORS and OpenAPI
handlers captured text, vectors or `&router`, so:

- `معالج<S>`, `مستخرج<S, T>`, `وسيط<S>` and `وسيط_مسار<S>` are records: a run
  function plus `المعطيات: متجه نص`, with offsets for combined extractors.
- The router owns all route handlers; the closure given to `std.http` captures
  only the route index.
- Global `next` is `&التالي<S>` with `تابع`; route `next` is
  `&التالي_مسار<S>` with `تابع_مسار`.
- Route registration takes a `معالج<S>`: wrap plain functions with
  `من_دالة(f)`.
- New helpers: `مستخرج_من_دالة`, `مستخرج_بمعطى`, `استخرج`,
  `وسيط_من_دالة`, `وسيط_بمعطيات`, `وسيط_مسار_من_دالة`, `معالج_بمعطيات`,
  `حالة_الموجه`.

## Behaviour fixes

- **Routing:** HEAD falls back to GET, and 405 `Allow` lists HEAD. Merge and
  nest are atomic. `"/api"` + `"/"` serves `"/api"`. Lifecycle hooks received
  the internal router state instead of the application state.
- **Path parameters:** percent-decoded and UTF-8 checked, so Arabic paths work.
  `معامل_مسار` now returns `نتيجة` (`مفقود` / `ترميز_غير_صالح` /
  `عدد_غير_صالح`); `معامل_مسار_خام` returns the raw value.
- **CORS:** origin allow-list. `*` with credentials is rejected
  (`سياسة_الأصول` now returns `نتيجة`). No headers for disallowed origins,
  `Vary: Origin` when reflecting, `max-age`, and expose headers.
- **Compression:**
  - Real Accept-Encoding parsing (`q=0`, `*`, multiple lines).
  - Skips HEAD, 204, 206 and 304 responses, `no-transform`, and media that is
    already compressed.
  - Merges into `Vary` instead of overwriting it.
  - Weakens strong ETags.
- **Bearer:** case-insensitive scheme, extra spaces allowed, RFC 6750 token
  syntax, and `error="invalid_request"` / `"invalid_token"` challenges.
- **Bodies:**
  - A missing or unexpected Content-Type is 415.
  - Oversized multipart bodies are 413.
  - Validation counts characters, not bytes.
- **Cookies:** `SameSite=None` without `Secure` is refused.
- **Files:** `رد_ملف_من_دليل` blocks traversal and maps not-found to 404 and
  permission errors to 403.
- **OpenAPI:**
  - The document declares `3.2.0`; there is no 3.2.1.
  - `اربط_موثقا` nests a sub-router together with its document.
  - The JSON is serialized once, when the handler is created.
  - The docs page loads a relative or configurable spec URL, and HTML-escapes it.
- **WebSocket:**
  - Close codes and close reasons are validated.
  - Message size is bounded (64 MiB by default), and `رمز_إغلاق_لخطأ` gives
    1002/1007/1009.
  - Unsupported versions get 426 with `Sec-WebSocket-Version: 13`.
- **SSE:** fields are re-validated when encoding, which blocks injection through
  public fields.

## Decorators

- New handler decorators in `nahr.middleware`: `@محمي`/`@protected`,
  `@بحد_جسم`/`@body_limited`, `@مضغوط`/`@gzipped`, `@مراقب`/`@observed`.
- `اضغط_الاستجابة` (`compress_response`) is the gzip step shared by the `ضغط`
  middleware and `@مضغوط`.
- The OpenAPI English alias `response` (add a response to an operation) is now
  `add_response`. Under the old name it collided with the `response` type, and
  selective imports have no `as`.

## Additions

- `nahr.json` gets a streaming JSON writer and typed responses:
  - `كاتب_جسون` with comma handling and escaping.
  - `رد_جسون_بـ(status, &value, encoder)` and `اكتب_مصفوفة_بـ`.
  - `وثيقة_جسون_إلى_نص` serializes std.json documents. `رد_جسون` and the
    OpenAPI output now use it.
- `أخطاء_جسون` / `json_errors` gives every error a JSON body, and
  `حول_الأخطاء` / `map_errors` lets an app rewrite error responses.
- `معرف_الطلب` / `request_id` adds an `X-Request-Id` to every request (the
  client's own when valid, otherwise a UUID v4).
- `اربط_ملفات` / `serve_dir` mounts a folder, with weak ETags and 304 replies.
- The `من_سياق` request context borrows the request instead of copying it,
  body included.
- The docs page is now a plain list in the system font, with light and dark
  modes and no cards.

## On the 2026-11-06 tree

- `شغل_متوازيا` / `serve_parallel` and `شغل_على_متوازيا` run a thread pool on
  std.thread and std.sync: workers share the listener and the router (Arc), and
  each connection gets read/write timeouts. 4 requests that each sleep 1 s take
  1.02 s on 4 workers.
- `شغل_آمنا_على` (HTTPS from a PKCS#12 file) and `شغل_آمنا_على_متوازيا`. HTTP/2
  works with no change, as h2c with prior knowledge and over TLS through ALPN.
- `حد_المعدل` / `rate_limit` is a fixed-window rate limiter with 429 and
  Retry-After. Its counters sit in an Arc-and-Mutex the middleware closure
  captures, which the new owned-capture rule allows.
- Nahr now needs the 2026-11-06 tree: it uses `std.thread`, `std.sync` and
  `std.tls`.

## On the 2026-11-08 fix1 tree

- `شغل_على_بأحداث` / `serve_on_evented` serves Nahr on std's new event-driven
  server (`شغل_خادم_ويب_بأحداث`). With one thread pinned to one core, 32 and
  256 connections are all served fairly (p50 3.1 ms and 25.8 ms at about
  10 req/ms). The old server served one connection and left the others
  waiting.
- The bench server has `NAHR_BENCH_EVENTED=1`, and `run.sh` runs
  `MODES="serial pool evented"`.
- Measured with the new allocator lock (Linux, 2 CPUs): 32 workers on a 10 ms
  handler give **3.01 req/ms at p50 10.5 ms**, against 0.44 req/ms at p50
  67 ms before. So the lock fix works.

## On the 2026-11-10 nahr12 tree

nahr12 cuts std's allocation cost, which was most of every request, and the
middleware stack's own work. All 25 checks pass.

Measured on Linux x86_64 (4 CPUs), LLVM backend, against nahr11 built the
same way:

| | nahr11 | nahr12 |
|---|---|---|
| callgrind, one evented worker, `GET /plain`, std alone | 47.5k instructions | 31.9k |
| the same through Nahr | 70.2k | 45.1k |
| in-process `GET /plain` | 735 ns, 11 allocations | 453 ns, 10 |
| in-process `GET /plain` with the middleware stack | 3,601 ns, 35 allocations | 1,766 ns, 25 |
| HTTP, 2 workers, 32 connections, std alone | 42 req/ms | 102 |
| HTTP, the same through Nahr | 26 req/ms (p99 2.1 ms) | 80 (p99 0.7 ms) |
| HTTP, Nahr with the middleware stack | 16 req/ms (p99 3.5 ms) | 62 (p99 0.8 ms) |
| HTTP, `/large` (64 KiB) / with gzip | 12.7 / 9.5 req/ms | 29.1 / 25.3 |

In std (`std/os/allocation.sn`, `std/text/from_bytes.sn`, `std/http/*`):

- **The allocator's thread cache now serves reallocation.** The compiler
  creates and grows every vector through reallocation, which always took the
  global lock and the shared free lists, so the per-thread cache served almost
  nothing. Reallocation from 0, within a block's capacity, and between small
  sizes now stays in the cache.
- **The main thread has a cache too.** The evented server runs one of its
  workers on the main thread, which took the locked path for every
  allocation and contended with the other workers: most of the drop at 32
  connections on one machine.
- **Copies are one allocation and one block copy:** byte copies use
  `extend_from`, text copies reserve their exact size, and text built from a
  vector is handed over instead of copied twice.
- **Header removal (and so `ضع_رأس_ويب`) works in place** instead of
  rebuilding the header list with a copy of every other header; header-name
  comparison skips case folding for equal bytes.
- Field accessors (`طريقة_طلب_ويب` and others) and the UUID functions read
  through the reference instead of copying the whole record first.
- `deflate` inserts hashes only for the last positions of a long match, as
  zlib's `max_insert_length`.

In the compiler (`compiler/msir/lowering/ownership_glue.sn`): `clone` of a
vector or text reserves the copy's length first, so it no longer
reallocates as it grows.

In Nahr:

- **`request_id`** makes IDs without a system call: a 64-bit key from the
  OS CSPRNG taken once, a counter, and the splitmix64 finalizer, in the UUID
  version 4 layout. They are unique within the process but predictable (the
  finalizer can be inverted, so one ID gives the key): for tracing only, not
  a token (tower-http asks the OS for 16
  bytes per request instead). `new_request_id` / `معرف_طلب_جديد` is public.
- **`rate_limit`** keeps its keys in a hash map (std's text index map) with
  one slot per key: a request is one lookup, whatever the number of clients,
  instead of a rebuild of the whole table with a copy of every entry.
  Expired keys are swept once per window.
- `bench/compare/axum`: the benchmark's endpoints in axum, to compare on the
  same machine with the same load tool.

Found with nahr12 (for the compiler owner):

29. **A record literal as a module-level initializer crashes the parser**
    (`SULTANC-ICE-PARSER-NO-RESULT`, no location):
    `دع س: متغير ذرة_ط64 = { القيمة: 0 };` at top level. It should be a
    diagnostic or be supported.
30. **Copying borrowed text into bytes is a byte loop** (about 10
    instructions per byte even with the capacity reserved), because
    `extend_from` accepts only a byte vector as its source. A 64 KiB text body
    costs about 650k instructions to turn into a response; Rust copies it with
    one memcpy. `extend_from` from `&text` (or a `&text` to `&vector u8`
    view) would make it a block copy; the interpreter's inline text needs a
    path of its own there.
31. A blocking handler (`/sleep`) still stalls its evented worker and every
    connection on it. A worker-side pool for handlers marked blocking (tokio's
    `spawn_blocking`) needs std's evented server to accept a response later,
    from another thread.


Found with nahr12 (std), from the Mac benchmark against axum (same machine,
same load tool, `/plain`, 32 connections): axum 264 req/ms, std's server
alone 64, Nahr 57. At 2 connections all three are equal (92-95).

Checked on the 2026-11-12 3b441bc (test-mode) tree:

- The tests are `@@اختبار` functions now, run by `sultanc test` through
  `tests/tests.sn` (one build, a process per test, a named failure with the
  check that failed). 16 of 17 pass, compiled and in the interpreter; the
  10 examples build. `tests/run.sh` keeps `NAHR_INTERP` and adds
  `NAHR_TEST_FILTER`.

42. **`sultanc test` does not run definition-time decorators.** An ordinary
    build runs every `@@decorator` before `main`; the entry `sultanc test`
    synthesizes runs the tests without them, compiled and with
    `--interpret`. A program whose `@@register` increments a counter sees 1
    in `main` and 0 in a test. Nahr's `المسارات_المزخرفة` fails because of it
    (no decorated route was registered); it passes when the decorators run.
- Still open: 40 (295 bytes per `GET /plain`), 41 (immediate restart on the
  same port fails).

Checked on the 2026-11-12 0e3479d (completion) tree (all 27 checks pass):

- Module spellings moved from the package graph (`[[alias]]`, now an
  unknown field) to root files: `src/nahr.sn` declares the Arabic names of
  Nahr's directories (`module routing { ar: توجيه };`); the generated graphs
  keep the package's own name `نهر`.
- Fixed: 39. Jisr imports C structs used only through pointers as opaque
  types (`public type sqlite3 = opaque;`): `sqlite3_close(statement)` is now
  SULTANC-CALL-ARGUMENT-TYPE-MISMATCH, typed handles work compiled and
  in the interpreter, and `sqlite3.h` gives one warning (`sqlite3_version`,
  a C array variable) instead of 14.
- Speed unchanged; binaries about 26% larger (the in-process benchmark
  569 KB, 451 KB on e8d68f0), likely the new debug information.
- Still open: 40 (295 bytes per `GET /plain`), 41 (immediate restart on the
  same port fails).

Checked on the 2026-11-12 7b00d69 (pkg-graph) tree (all 27 checks pass):

- SultanC no longer reads `Supax.toml`; a package graph is passed with
  `--package-graph`. Nahr keeps its `Supax.toml` files for Supax and ships
  generated graphs for building with sultanc alone (`examples/`, `tests/`,
  `bench/package-graph.toml`, from `tools/package_graphs.py`); every script
  and documented command passes them.
- 39 half done: the language has opaque types (`type T = opaque;`), but Jisr
  still imports `sqlite3*` and `sqlite3_stmt*` as `u64` and prints 14
  warnings for `sqlite3.h`.

41. **A server restarted right after the previous one stopped cannot bind**
    ("address already in use"), with or without load; half a second later
    it can. New since the port probe for item 33
    (`شغل_خادم_ويب_بأحداث`, std/http/server.sn): the plain bind of the probe
    fails while the previous process's sockets are still closing, and the
    "is anything listening?" check does not tell that case apart. The
    benchmark gives each server start its own port meanwhile. uvicorn, Go
    and actix restart on the same port at once (SO_REUSEADDR).

Checked on the 2026-11-12 e8d68f0 tree (all 27 checks pass):

- Fixed: 38. `sultanc run -l sqlite3 x.sn` calls a Jisr-imported library in
  the interpreter (open, exec, prepare, step, column all work).
- About the same speed: 31.2k instructions per `GET /plain` on one evented
  worker (31.5k); in-process 300 ns (about 330 on the previous tree in the
  same session).
- 39 changed form: `import "sqlite3.h"` now prints 14 warnings
  (SULTANC-C-UNSUPPORTED-TYPE) for the opaque structs `sqlite3_stmt`,
  `sqlite3_blob`, `sqlite3_context`… and for `va_list`, and the handles are
  still `u64`. An opaque struct used only through a pointer is ordinary C
  (the library hides its layout), so it should import as a distinct opaque
  type with no warning, as Zig's translate-c gives `opaque {}` and bindgen
  a zero-size struct.
- Still open: 40 (295 bytes per `GET /plain`).

Checked on the 2026-11-12 2bf240e tree (all 27 checks pass):

- A little faster (the MSIR optimization pipeline): in-process `GET /plain`
  about 425 ns (465 before), `/params` 1,060 ns (1,235), `/json` 805 ns
  (860); 31.5k instructions per request on one evented worker (32.3k),
  std's server alone 29.7k (30.6k).
- Still open: 38 (`sultanc run` rejects `-l`; a Jisr-imported library cannot
  be called in the interpreter), 39 (opaque handles are `u64`), 40 (295
  bytes per `GET /plain`, unchanged).

Checked on the 2026-11-12 f3b41b4 tree (all 27 checks pass):

- Fixed: the interpreter starts threads (37): under `sultanc run` the store
  runs its load test (4/4 connections, every body checked) and Ctrl+C shuts
  down gracefully (Shutting down → Finished).
- Fixed: Jisr calls C variadic functions (`sqlite3_mprintf...N` call shapes).
- Interpreter: text functions about twice as fast again
  (`استبدل_في_النص` 50 µs, `قسم_النص` 77 µs).
- Speed about the same: `GET /plain` 32.3k instructions per request on one
  evented worker (34.1k on the previous tree), std's server alone 30.6k.
- Still open: 38 (the interpreter finds a C function only with a library in
  its declaration, and `sultanc run` takes no `-l`, so a Jisr import such
  as `sqlite3.h` cannot be called there), 39 (opaque handles are all `u64`).

40. **Each request allocates more bytes** (same number of allocations): the
    in-process benchmark gives 295 bytes per `GET /plain` (119 on the
    previous tree), 479 for `/json` (291), 747 with the middleware stack
    (507). Likely a size-class or reserve change in std/os/allocation.sn
    or in vector growth.

Checked on the 2026-11-11 machine_interp_jisr tree (all 27 checks pass):

- The new interpreter is 7 to 20 times faster (counting loop 187 ns per
  iteration, was 1,419; `استبدل_في_النص` 0.09 ms, was 1.9 ms; the store's
  catalog builds 1,000 products in 0.9 s, was 14 s).
- Jisr: `import "sqlite3.h"` turns SQLite's header into a SultanC module;
  open, `CREATE`, `INSERT`, `prepare`/`step`/`column_int` all work with
  `-b llvm -l sqlite3`.

37. **The interpreter cannot start threads** (`أطلق` returns an error).
    Nahr blocked SIGINT/SIGTERM and then failed to start its signal
    watcher, so Ctrl+C did nothing under `sultanc run`. Nahr now unblocks
    the signals when the watcher cannot start (Ctrl+C then ends the process
    at once), and the store's load test answers 503 instead of starting.
    Threads in the interpreter would also let the evented server and live
    sessions run as compiled.
38. **The interpreter cannot call C** (`SULTANC-INTERPRETER-UNSUPPORTED-
    EXTERNAL-CALL` on `sqlite3_libversion_number`): Jisr-imported functions
    work only compiled.
39. Jisr notes from `sqlite3.h`: every opaque handle (`sqlite3*`,
    `sqlite3_stmt*`, …) becomes `u64`, so a statement can be passed where a
    database is expected with no error; a distinct opaque pointer type per C
    struct (Zig's `*opaque{}`, Rust's `#[repr(C)] struct X { _p: [u8; 0] }`)
    would keep them apart. Variadic functions (`sqlite3_mprintf`,
    `sqlite3_config`, …) are skipped on x86_64.

36. **The interpreter (`sultanc run`) is 1,000 to 8,000 times slower than
    LLVM** (interp tree, same program, 2-core Linux): a counting loop takes
    1.4 µs per iteration, `استبدل_في_النص` on 40 bytes 1.9 ms (LLVM 224 ns),
    `قسم_النص` 2.3 ms (512 ns), a text-map insert 0.41 ms (249 ns). The store
    example's catalog (100,000 products) would take about 20 minutes to
    build; 1,000 products take 14 s. For reference, CPython runs a counting
    loop at about 30 ns per iteration.

34. **std text search is about 2 ns per byte.** `يحتوي_نصا` calls
    `يطابق_شريحتين` at every position: 100,000 product names (about 45 bytes
    each) take about 10 ms. A first-byte scan (memchr) before comparing, or
    Two-Way as Rust's `str::contains`, would make it several times faster.
    The store example uses an inverted index instead (0.6 ms).
35. **`اكتب_تي_سي_بي` copies its whole buffer on every call**
    (`دع البيانات: متجه ط8 = *المحتوى;` in std/net/tcp.sn): one allocation
    and copy per write. It should pass the reference through.

33. **A second server starts silently on a port that is already in use.**
    The evented server binds with SO_REUSEPORT, so on Linux a second copy
    of the same program (same user) binds 127.0.0.1:8000 too and the kernel
    splits connections between the old and the new process. uvicorn, Go and
    actix fail with "address already in use". Seen while testing the demo:
    three copies served one port. std could probe the port without
    SO_REUSEPORT before binding its shards, or hold an exclusive lock.

32. **On macOS (and Windows) every worker thread allocates under the global
    allocator lock.** `std/os/allocation.sn` finds a thread's cache from the
    address of a local (`مخبأ_من_عنوان_مكدس_مخصص`): only stacks inside std's
    thread-stack slots, or the main thread's window, have a cache. Linux
    threads get slot stacks; Darwin threads come from `pthread_create` with
    an OS-owned stack (`std/os/platform/unix/apple/darwin/threads.sn`), so
    every allocation of every worker except the main thread's takes the one
    allocator lock. With about 10 allocations per request and 11 workers,
    the workers queue on that lock: the server does no better at 32
    connections than at 2. Forcing std's macOS acceptor path on Linux (where
    threads have slot stacks) scales normally, so the acceptor is not the
    cause. Fix: give Darwin threads a slot stack (`pthread_attr_setstack`
    with std's slot mapping), or find the cache through thread-local storage
    (`pthread_getspecific` is a register read on Darwin; Windows has TLS
    slots).

## On the 2026-11-09 nahr11 tree

nahr11 fixes items 27 (router splits the path once) and adds a macOS
acceptor that hands each connection to the least-loaded worker (item 28).
All 25 checks pass; Nahr builds for arm64-darwin.

- callgrind, one evented worker, `GET /plain`: Nahr 49.8k instructions per
  request, std's server alone 47.5k (Nahr was 75.5k on nahr9): Nahr now
  adds about 5% over a bare std server.
- In-process on an M-series Mac: `GET /plain` 571 ns, 11 allocations,
  208 bytes (was 955 ns, 30, 701).
- Over HTTP on the Mac, Nahr matches std alone: 86.6 vs 87.1 req/ms at 2
  connections, 49 vs 52 at 32.

## On the 2026-11-09 nahr8 tree

nahr8 fixes items 20 (allocator crash) and 24 (macOS `open`). All 25 checks
pass; pool and evented servers run; Nahr builds for arm64-darwin with LLVM.

Found with nahr8 (std):

25. **macOS evented server gets slower with more connections** (M-series,
    11 workers: `/plain` 48 req/ms at 2 connections, 34 at 32, p99 3.3 ms).
    Without a balancing SO_REUSEPORT, `std/http/server.sn` shares one
    listener, kqueue and connection table between every worker, so they
    contend on it. Go, tokio and libuv give each worker its own kqueue and
    hand accepted sockets to them (one acceptor, or each worker accepting
    from the shared listener into its own kqueue).
26. **gzip is slow and allocation-heavy:** compressing the 64 KiB body takes
    3.3 ms on an M-series Mac (about 20 MB/s), 396 allocations and 1.1 MB
    allocated for one response. zlib level 6 does this in well under 1 ms.
    `std` deflate should reuse its window and hash tables and write into
    one growing buffer.

27. **std's router splits the request path once per route.** Profiled with
    callgrind (one evented worker, `GET /plain`): Nahr spends 75.5k
    instructions per request against 47.5k for std's server alone
    (`bench/std_server.sn`); routing is 34k of it, 26.5k in
    `طابق_أجزاء_مسار_ويب` (`std/http/router.sn`), which `قسم_النص`-splits
    the path again for each of the router's routes, with reallocations
    (`أعد_تخصيص_كتلة_مخصص` and `حرر_كتلة_مخصص` are 28k of self cost).
    Splitting once in `وجه_طلب_ويب`, or a radix tree as axum's matchit,
    removes most of it.
28. macOS evented accept: confirmed in std with `MODES=std` (std alone:
    90 req/ms at 2 connections, 52 at 32). The accept loop drains the
    shared listener, so one worker takes every connection.

## On the 2026-11-09 nahr7 tree

Built from the WebAssembly seed with LLVM 20, then rebuilt with itself (the
seed-built compiler binds the allocator's plain entry points; the self-built
one its per-thread caches, about 12% faster on Nahr's in-process path). All
25 checks pass (17 test programs, 8 examples).

New in Nahr, from the nahr7 features:

- **Graceful shutdown** on Ctrl+C / SIGTERM, uvicorn's lines (`Started server
  process [pid]`, `Shutting down`, `Finished server process [pid]`), a second
  Ctrl+C to force quit; the client address in access lines; colors only when
  standard error is a terminal.
- **Live WebSocket and SSE / streamed responses** through std's connection
  hand-over, on every server; each session runs on its own thread.
- **`@@` route decorators**, **`@@json` helpers** (415/422 like FastAPI),
  **embedded files** (`embed_file`), **handler timeouts**
  (`NAHR_HANDLER_TIMEOUT_MS`), **rate limits per client address**.
- Serial and HTTPS-serial serving now share the pool's accept loop.
- The in-process benchmark reports allocations and bytes per request.

Speed (one core, `GET /plain`, LLVM, req/s; same machine, same load tool):

| | 1 conn | 32 | 256 |
|---|---|---|---|
| Nahr | 16–17k | 62–74k | 88–95k |
| Go net/http | 14.6k | 73.5k | 72.5k |
| axum | 16.8k | 156.5k | 154.8k |

LLVM builds now take about 20 s (the verify-each fix). In-process with LLVM:
`GET /plain` 1.6 µs, about 30 allocations and 700 bytes per request (54 and
1.8 KB with the middleware stack).

Found in nahr7 (std):

20. **Crash: the per-thread allocator cache traps on any worker thread.**
    `std/os/allocation.sn`, in `خصص_بمخبأ_مخصص`, decrements a counter with
    `زد_كلمة_مخبأ(عدد_مخبأ_الخيط(المخبأ, الفئة), ~(0 مثل ط64));` — adding
    `~0` wraps, and checked arithmetic traps (SIGILL) the first time a
    thread takes a block from its cache. Every multi-threaded Nahr server
    built from nahr7 dies on its first request. A subtraction fixes it
    (`اكتب_كلمة_مخصص(ع, اقرأ_كلمة_مخصص(ع) - 1)`); Nahr was tested with that
    one-line patch in a scratch copy.
21. **The main thread's allocation counter stays 0**
    (`عدد_تخصيصات_الخيط`), while its free and byte counters count. The
    benchmark counts frees instead.
22. **A long hand-over callback holds its event-loop shard.** The callback
    runs on the worker that owns the connection's listener and poller
    (SO_REUSEPORT shard), so new connections assigned to that shard wait
    until it returns (a browser's EventSource waited behind its own
    WebSocket). Nahr runs each live session on its own thread; std could do
    the same, or document it.
23. Seen once, not reproduced in later runs: the first SIGINT to an evented
    server was not taken by the waiting signal thread; a second one was.

24. **Build break, macOS + LLVM:** every program that imports std fails with
    `SULTANC-TARGET-ABI-UNAVAILABLE` on arm64-darwin and x86_64-darwin (fix7c
    builds them). `std/os/platform/unix/apple/darwin/file_descriptors.sn` now
    declares two externs bound to the C symbol `open` with different
    signatures (`open(path, flags)` and the 9-argument variadic
    `open_بوضع_داروين = «open»`); the LLVM provider refuses two declarations
    of one symbol. Making `open` an ordinary function that calls
    `افتح_بوضع_داروين(path, flags, 0)` fixes it (tested in a scratch copy).

## On the 2026-11-09 fix7c tree

- Built from the new WebAssembly seed (with LLVM 20). `إذا` is the only
  spelling of `if`; `لو` is now a syntax error, so this Nahr needs fix7c or
  later.
- All 21 checks pass with no compiler or std patches; the poll.sn build break
  (finding 12) is fixed.
- Still open: findings 14 (router copies its state), 15 (no non-blocking
  sockets on macOS), 16 (no file embedding), 18 (ICE on enum aliases) and 19
  (no peer address, pid, signals or isatty). Speed is unchanged.

## HTML, CSS and JavaScript

- **Templates** (`nahr.template`): Jinja syntax with auto-escaping, layouts
  (extends/block), includes, loops with `loop` variables, filters, whitespace
  control, strict mode, folder loading with file:line errors, auto-reload, and
  template responses.
- **Static files:** `index.html` for folders, a trailing-slash redirect,
  `charset=utf-8` on text types, precompressed `.br`/`.gz`, Cache-Control
  (separately for pages and assets), a single-page-app fallback, and serving
  the site root. `serve_dir` keeps its signature and gains the defaults.
- **Example site** (`examples/ar/site.sn`, `examples/en/site.sn`,
  `examples/site/`): bilingual pages from one set of templates, CSS with
  logical properties for RTL and LTR, JavaScript calling a JSON API, a form
  with Post/Redirect/Get, and a template 404 page.
- **Fix: shared state.** The router now keeps the application state behind an
  Arc. Before, every request worked on a copy (see finding 14): an atomic
  counter in the state never moved past one, and a `Mutex` in the state did
  not exclude other requests. `tests/state.sn` covers it.
- `if` is now written `إذا` everywhere (was `لو`).
- **Diagnostics** (`nahr.log`): uvicorn's line format (`INFO:     …`), colored
  levels and status codes, startup lines (routes, middleware, serving mode,
  URL), the route table at debug level, one access line per request with its
  duration, readable bind errors (errno explained), template errors as ERROR
  lines, and environment settings (level, access log, color, time). The
  event-driven server falls back to the thread pool, with a warning, where std
  cannot make sockets non-blocking (macOS today).
- `serve_error_text` / `وصف_خطأ_تشغيل` describes why serving failed; the
  benchmark prints it and the runner reports a crash or exit code.

## Benchmark

- `bench/` holds a stress test and benchmark. `run.sh` builds the benchmark
  server, an in-process benchmark and a C load generator (`load.c`, keep-alive,
  latency histogram). It then runs every endpoint single-threaded and on the
  pool, with and without the middleware stack, and writes `report.md` and
  `results.csv`. See `bench/README.md`.

## Tests and examples

- Examples in both languages: `examples/ar/{hello,api,site}.sn` and
  `examples/en/{hello,api,site}.sn`. Each api example uses decorators.
- `tests/run.sh` runs 17 test programs and builds the 8 examples. All 25 pass
  (Linux x86_64, compiled); the template, static and state tests also pass
  with `NAHR_INTERP=1`.
- Both api examples also serve `/info` as typed JSON, return JSON errors, and
  send request IDs. The api example also builds for
  macOS arm64.

## SultanC findings (for the compiler owner)

1. **Resolved in 2026-11-06:** closures now move the owned values they capture,
   so configuration could live in closures again. Nahr keeps its record design,
   which works and is stable, and uses captures where they help (the rate
   limiter).
2. A generic named function cannot be used as a function value whose expected
   type fixes its type parameters. It needs a non-capturing closure wrapper.
3. Type arguments are not inferred from an enclosing call, and there is no
   explicit `f<T>(…)` call syntax, so extractors must be bound with typed `let`s.
4. Generic function bodies are only checked when instantiated. Nahr's
   lifecycle bug compiled until a test called it.
5. Selective imports have no `as` (`from m import a as b`). The parser
   rejects it.
6. Decorators run at call time only, so FastAPI-style `@get("/path")` route
   registration is impossible without a definition-time feature (attribute
   macros or a registration table).
7. Record and vector literals are rejected in `:=`, `return`, call arguments and
   record fields.
8. **std bug:** `«…»` literals are raw (`«\\n»` is three characters), but
   `std/json/escape.sn` writes its escapes with them. So
   `ألحق_سلسلة_جسون` / `جسون_إلى_نص` emit `\\n` for a newline, `\\\"` for
   a quote and four backslashes for one backslash. Example: `["x\ny"]` parses
   and then stringifies to `["x\\ny"]`. Nahr uses its own escaper meanwhile.
   The fix is to use `"…"` literals in escape.sn, or byte values.
9. std: `أول_رأس_طلب_ويب` / `أول_رأس_استجابة_ويب` copy the whole message
   (`دع القيمة = *الطلب`) on every header lookup. Nahr calls
   `أول_قيمة_رأس_ويب` on `.الرؤوس` instead.
10. **std, new:** allocation-heavy work slows down when it runs on several
    threads. In one test, a request that allocates in a loop takes 0.30 s
    alone and 1.31 s for two at once; pure arithmetic scales (0.32 s vs
    0.35 s). That fits the global compare-and-swap lock in
    `std/os/allocation.sn`. std's TLS handshakes allocate heavily, so parallel
    HTTPS barely gains. Per-thread caches or arenas are the usual fix.
10b. **Root cause of 10 (found with the benchmark):** the allocator lock in
    `std/os/allocation.sn` (`اقفل_المخصص`, lines 334 and 373) is a bare spin
    loop: compare-and-swap in a loop, with no pause, yield or futex wait.
    With more threads than CPUs, the thread holding the lock gets
    preempted while the others spin until the scheduler runs it again.
    Measured on 2 CPUs with 32 workers, a handler that sleeps 10 ms has p50
    67 ms and p99 148 ms instead of 10 ms. The process uses 146% CPU while
    every worker sits in `nanosleep`, and throughput is 0.5 req/ms instead of
    3.2. std's own `Mutex` already spins briefly and then waits on a futex;
    the allocator could reuse that, or keep per-thread caches.
10c. **Where a request's time goes** (callgrind, `GET /plain` in-process,
    about 106,000 instructions per request): std's allocator takes 55%; std
    text compare, from_bytes, substring, transform, range and search take
    about 22%; std http headers and router about 8%; Nahr's own code is under
    1% (about 500 instructions). Speeding up the allocator speeds up every
    Nahr app.
12. **std, fix1 tree, build break:** `std/os/poll.sn` line 72 declares
    `دع البايت: ط8 = 0;` without `متغير` and assigns to it on the next lines.
    Every program that imports std.http fails with
    SULTANC-MUTABILITY-WRITE-TO-IMMUTABLE. Nahr was measured on a scratch
    copy with that one word added.
13. **std, next target, per-request cost of the HTTP path:** callgrind on the
    event-driven server under `GET /plain` load spends 55% of all
    instructions in the allocator, plus std text/from_bytes, headers,
    http1/common, model and request_parser. Nahr's files don't reach the top
    18. An HTTP request costs about 4–5× Nahr's in-process dispatch, so std's
    parse/model/serialize path allocates heavily per request. Per-thread
    allocation caches, plus fewer copies in the request model and header
    handling, are the levers.
14. **std, correctness and speed:** `وجه_طلب_ويب` in `std/http/router.sn`
    starts with `دع حالة_الموجه: موجه_ويب<S> = *الموجه;` and
    `دع قيمة_الطلب = *الطلب;`, so every request copies the whole router (its
    state and every route) and the request. Handlers get a reference to the
    copy: an atomic or a Mutex's lock word stored in the state changes only
    the copy, so counters reset and the Mutex does not exclude concurrent
    requests. Taking references (`دع حالة_الموجه: &موجه_ويب<S> = الموجه;`)
    fixes both and removes a per-request copy. Nahr works around it by keeping
    its state behind an Arc.
15. **std, macOS:** `اضبط_مقبس_نظام_غير_حاصر` returns ENOTSUP (errno 45) on
    purpose, because Darwin's `fcntl` is variadic and SultanC's arm64 extern
    calls cannot pass Apple's variadic stack arguments. So the event-driven
    server cannot start on macOS. Fixes: Apple arm64 variadic calls in the
    compiler (they also unblock `ioctl` and `open` with a mode), or a std
    fallback to the thread pool there.
16. **Compiler, missing:** no way to embed files at compile time (Go's
    `embed`, Rust's `include_bytes!`). Templates and static files are read
    from disk at startup, so a deployed binary needs its folder next to it.
17. **Compiler, compile time:** the LLVM backend is about 60× slower than
    native. fix7c, 2-core Linux x86_64: `server/server.sn` 10 s native, 9 min
    52 s LLVM. On an 11-core Apple Silicon Mac, `examples/ar/site.sn` with LLVM
    took 3 min 16 s. **Cause:** `compiler/backend/provider/llvm/ffi/passes.sn`
    sets `LLVMPassBuilderOptionsSetVerifyEach(خ, 1)`, which re-verifies the
    module after every pass of the O2 pipeline (a compiler-debugging setting;
    clang and rustc verify once). gdb sampling put 40% of the build in
    `VerifierPass`. With 0 instead (the module is still verified once before
    the passes), `server/server.sn` builds in 17 s instead of 9 min 52 s, and
    the binary runs at the same speed.
18. **Compiler crash (ICE):** `عام نوع log_level = مستوى_سجل;` followed by
    `عام مرادف log_level.debug = مستوى_سجل.تصحيح;` gives SULTANC-ICE-CONTEXT
    ("name binding conflict while collecting declarations"). With
    `عام مرادف log_level = …` it works. It should be a normal diagnostic.
19. **std, for diagnostics:** std.http does not give a handler or service the
    client's address; there is no process id, no signal handling (so no
    graceful shutdown or "Shutting down" line on Ctrl+C), and no isatty for
    color detection. uvicorn, Go and axum servers all use these.
11. **std, unchanged:** the HTTP server still closes the connection after a
    101 or a successful CONNECT (`انتقال_بروتوكول_غير_مدعوم`), and the service
    still returns a buffered response. So there is no live WebSocket or
    streamed SSE yet.

## Kept for later (needs the compiler or std)

- **Live SSE streaming and live WebSocket sessions.** std.http needs a
  streaming response writer and a hand-over of the connection after 101. The
  2026-11-06 server still closes the connection there.
- **Per-request deadlines** (a handler that runs too long). The pool already
  sets per-connection socket timeouts, but stopping a running handler needs
  cancellation hooks.
- **`@جلب(«/path»)`-style route registration.** This needs definition-time
  decorators.
- **OpenAPI generated from handler signatures.** This needs compile-time
  reflection over function types.
- **Extractors written inline in calls**, without typed `let`s. This needs
  nested type inference or explicit `f<T>()` call syntax.
- **Templates and static files inside the binary.** This needs compile-time
  file embedding (finding 16).
- **Multi-language rejection messages.** This needs the planned user-facing
  message system. Until then, `حول_الأخطاء` can rewrite them.
