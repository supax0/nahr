/* Nahr load generator: HTTP/1.1 keep-alive load with latency percentiles.
 *
 *   cc -O2 -pthread -o nahr_load load.c
 *   ./nahr_load -c 64 -t 2 -d 10 -m GET -b "" http://127.0.0.1:8090/plain
 *
 * -c connections (spread over -t threads), -d seconds, -m method, -b body,
 * -H "name: value" (repeatable), -w seconds of warm-up excluded from results,
 * -o csv prints one CSV line. Each connection sends one request, reads the
 * full response (Content-Length or chunked), records the latency, and repeats.
 * A connection the server closes is reopened and counted.
 *
 * -e FILE checks every response body against FILE byte for byte (bodies up
 * to 128 KiB with Content-Length); a 2xx response with another body counts
 * as "wrong body", not as a success. The report also says how many of the
 * connections were established, so a run that silently opened fewer
 * connections than asked is visible.
 */
#define _GNU_SOURCE
#include <arpa/inet.h>
#include <errno.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <signal.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

#ifndef MSG_NOSIGNAL
#define MSG_NOSIGNAL 0 /* macOS: SIGPIPE is ignored in main */
#endif

/* Latency histogram: 1 us buckets up to 10 ms, then 100 us buckets to 10 s. */
#define FINE 10000
#define COARSE 100000
typedef struct { uint64_t fine[FINE]; uint64_t coarse[COARSE]; uint64_t over; } hist_t;

static void hist_add(hist_t *h, uint64_t ns) {
    uint64_t us = ns / 1000;
    if (us < FINE) h->fine[us]++;
    else if (us / 100 < COARSE) h->coarse[us / 100]++;
    else h->over++;
}
static void hist_merge(hist_t *a, const hist_t *b) {
    for (int i = 0; i < FINE; i++) a->fine[i] += b->fine[i];
    for (int i = 0; i < COARSE; i++) a->coarse[i] += b->coarse[i];
    a->over += b->over;
}
static double hist_pct(const hist_t *h, uint64_t total, double p) {
    if (!total) return 0;
    uint64_t want = (uint64_t)(p * (double)total), seen = 0;
    if (want == 0) want = 1;
    for (int i = 0; i < FINE; i++) { seen += h->fine[i]; if (seen >= want) return i / 1000.0; }
    for (int i = 0; i < COARSE; i++) { seen += h->coarse[i]; if (seen >= want) return i / 10.0; }
    return 10000.0;
}

static char host[300] = "127.0.0.1", port[16] = "80", path[2048] = "/";
static char method[16] = "GET", body[65536] = "", headers[8192] = "";
static int conns = 16, threads = 2, csv = 0;
static double duration = 10, warmup = 1;
static char request[90000];
static size_t request_len;
static struct addrinfo *addr;
static atomic_int running = 1, measuring = 0;
static char *expected; static size_t expected_len; /* -e */
static atomic_int established = 0;

typedef struct {
    int id, nconn;
    uint64_t ok, non2xx, wrong, errors, reconnects, bytes;
    uint64_t max_ns;
    hist_t *hist;
} worker_t;

static uint64_t now_ns(void) {
    struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t);
    return (uint64_t)t.tv_sec * 1000000000ull + (uint64_t)t.tv_nsec;
}

static int open_conn(void) {
    int fd = socket(addr->ai_family, SOCK_STREAM, 0);
    if (fd < 0) return -1;
    int one = 1;
    setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);
    struct timeval tv = { 5, 0 };
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof tv);
    if (connect(fd, addr->ai_addr, addr->ai_addrlen) < 0) { close(fd); return -1; }
    return fd;
}

/* Reads one response. Returns status, or -1 on error; *closed set when the
 * server asked to close (Connection: close) or closed. */
typedef struct { char buf[1 << 17]; size_t len; } rbuf_t;

static int read_response(int fd, rbuf_t *r, uint64_t *bytes, int *closed, int *body_ok) {
    *closed = 0; *body_ok = expected == NULL;
    size_t head_end = 0;
    for (;;) {
        if (r->len >= 4) {
            char *p = memmem(r->buf, r->len, "\r\n\r\n", 4);
            if (p) { head_end = (size_t)(p - r->buf) + 4; break; }
        }
        if (r->len == sizeof r->buf) return -1;
        ssize_t n = recv(fd, r->buf + r->len, sizeof r->buf - r->len, 0);
        if (n <= 0) return -1;
        r->len += (size_t)n;
    }
    int status = 0;
    if (r->len < 12 || sscanf(r->buf, "HTTP/%*d.%*d %d", &status) != 1) return -1;
    long clen = -1; int chunked = 0;
    char *line = r->buf;
    while (line < r->buf + head_end) {
        char *eol = memmem(line, (size_t)(r->buf + head_end - line), "\r\n", 2);
        if (!eol) break;
        size_t ll = (size_t)(eol - line);
        if (ll > 15 && strncasecmp(line, "content-length:", 15) == 0) clen = strtol(line + 15, 0, 10);
        else if (ll > 18 && strncasecmp(line, "transfer-encoding:", 18) == 0 && memmem(line, ll, "chunked", 7)) chunked = 1;
        else if (ll > 11 && strncasecmp(line, "connection:", 11) == 0 && memmem(line, ll, "close", 5)) *closed = 1;
        line = eol + 2;
    }
    size_t need;
    if (chunked) {
        /* Read until the terminating 0-size chunk. */
        for (;;) {
            if (memmem(r->buf + head_end, r->len - head_end, "\r\n0\r\n\r\n", 7) ||
                (r->len - head_end >= 5 && memcmp(r->buf + head_end, "0\r\n\r\n", 5) == 0)) break;
            if (r->len == sizeof r->buf) return -1;
            ssize_t n = recv(fd, r->buf + r->len, sizeof r->buf - r->len, 0);
            if (n <= 0) return -1;
            r->len += (size_t)n;
        }
        char *end = memmem(r->buf + head_end, r->len - head_end, "0\r\n\r\n", 5);
        need = (size_t)(end - r->buf) + 5;
    } else if (clen >= 0) {
        need = head_end + (size_t)clen;
        int fits = need <= sizeof r->buf;
        while (r->len < need) {
            if (need > sizeof r->buf) {
                /* Large body: drain without keeping it. */
                ssize_t n = recv(fd, r->buf, sizeof r->buf, 0);
                if (n <= 0) return -1;
                need -= (size_t)n; if (need < r->len) need = r->len;
                continue;
            }
            ssize_t n = recv(fd, r->buf + r->len, sizeof r->buf - r->len, 0);
            if (n <= 0) return -1;
            r->len += (size_t)n;
        }
        if (expected && fits)
            *body_ok = (size_t)clen == expected_len && memcmp(r->buf + head_end, expected, expected_len) == 0;
    } else {
        /* No length: body ends at close. */
        for (;;) {
            if (r->len == sizeof r->buf) r->len = head_end;
            ssize_t n = recv(fd, r->buf + r->len, sizeof r->buf - r->len, 0);
            if (n <= 0) break;
            r->len += (size_t)n;
        }
        *closed = 1; need = r->len;
    }
    *bytes += need;
    memmove(r->buf, r->buf + need, r->len - need);
    r->len -= need;
    return status;
}

static void *work(void *arg) {
    worker_t *w = arg;
    int fds[1024]; rbuf_t *bufs = calloc((size_t)w->nconn, sizeof(rbuf_t));
    for (int i = 0; i < w->nconn; i++) { fds[i] = open_conn(); if (fds[i] >= 0) atomic_fetch_add(&established, 1); }
    /* Each connection keeps one request in flight; poll for readiness. */
    uint64_t sent_at[1024];
    struct pollfd pfd[1024];
    for (int i = 0; i < w->nconn; i++) {
        if (fds[i] >= 0 && send(fds[i], request, request_len, MSG_NOSIGNAL) == (ssize_t)request_len) sent_at[i] = now_ns();
        else { if (fds[i] >= 0) close(fds[i]); fds[i] = -1; }
    }
    while (atomic_load(&running)) {
        int n = 0;
        for (int i = 0; i < w->nconn; i++) { pfd[i].fd = fds[i]; pfd[i].events = POLLIN; pfd[i].revents = 0; n++; }
        int ready = poll(pfd, (nfds_t)n, 100);
        for (int i = 0; i < w->nconn; i++) {
            if (fds[i] < 0) {
                /* Reconnect a dropped connection. */
                fds[i] = open_conn();
                if (fds[i] < 0) { if (atomic_load(&measuring)) w->errors++; usleep(1000); continue; }
                bufs[i].len = 0;
                if (atomic_load(&measuring)) w->reconnects++;
                if (send(fds[i], request, request_len, MSG_NOSIGNAL) != (ssize_t)request_len) { close(fds[i]); fds[i] = -1; continue; }
                sent_at[i] = now_ns();
                continue;
            }
            if (ready <= 0 || !(pfd[i].revents & (POLLIN | POLLHUP | POLLERR))) continue;
            int closed = 0, body_ok = 1;
            int status = read_response(fds[i], &bufs[i], &w->bytes, &closed, &body_ok);
            uint64_t t = now_ns();
            int m = atomic_load(&measuring);
            if (status < 0) {
                if (m) w->errors++;
                close(fds[i]); fds[i] = -1; continue;
            }
            if (m) {
                uint64_t lat = t - sent_at[i];
                hist_add(w->hist, lat);
                if (lat > w->max_ns) w->max_ns = lat;
                if (status < 200 || status >= 300) w->non2xx++;
                else if (!body_ok) w->wrong++;
                else w->ok++;
            }
            if (closed) { close(fds[i]); fds[i] = -1; continue; }
            if (send(fds[i], request, request_len, MSG_NOSIGNAL) != (ssize_t)request_len) { close(fds[i]); fds[i] = -1; continue; }
            sent_at[i] = now_ns();
        }
    }
    for (int i = 0; i < w->nconn; i++) if (fds[i] >= 0) close(fds[i]);
    free(bufs);
    return 0;
}

static void usage(void) {
    fprintf(stderr, "usage: nahr_load [-c conns] [-t threads] [-d secs] [-w warmup] [-m method] [-b body] [-H header]... [-e expected-body-file] [-o csv] http://host:port/path\n");
    exit(2);
}

int main(int argc, char **argv) {
    int opt;
    signal(SIGPIPE, SIG_IGN);
    while ((opt = getopt(argc, argv, "c:t:d:w:m:b:H:o:e:")) != -1) {
        switch (opt) {
        case 'c': conns = atoi(optarg); break;
        case 't': threads = atoi(optarg); break;
        case 'd': duration = atof(optarg); break;
        case 'w': warmup = atof(optarg); break;
        case 'm': snprintf(method, sizeof method, "%s", optarg); break;
        case 'b': snprintf(body, sizeof body, "%s", optarg); break;
        case 'H': strncat(headers, optarg, sizeof headers - strlen(headers) - 3); strcat(headers, "\r\n"); break;
        case 'o': csv = strcmp(optarg, "csv") == 0; break;
        case 'e': {
            FILE *f = fopen(optarg, "rb");
            if (!f) { fprintf(stderr, "cannot read %s\n", optarg); return 1; }
            fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
            expected = malloc((size_t)n + 1); expected_len = fread(expected, 1, (size_t)n, f); fclose(f);
            break;
        }
        default: usage();
        }
    }
    if (optind >= argc || strncmp(argv[optind], "http://", 7) != 0) usage();
    const char *u = argv[optind] + 7;
    const char *slash = strchr(u, '/');
    size_t hp = slash ? (size_t)(slash - u) : strlen(u);
    char hostport[300]; snprintf(hostport, sizeof hostport, "%.*s", (int)hp, u);
    snprintf(path, sizeof path, "%s", slash ? slash : "/");
    char *colon = strrchr(hostport, ':');
    if (colon) { *colon = 0; snprintf(port, sizeof port, "%s", colon + 1); }
    snprintf(host, sizeof host, "%s", hostport);
    if (threads < 1) threads = 1;
    if (conns < threads) conns = threads;
    if (conns > threads * 1024) conns = threads * 1024;

    struct addrinfo hints = { 0 }; hints.ai_socktype = SOCK_STREAM;
    if (getaddrinfo(host, port, &hints, &addr) != 0) { fprintf(stderr, "cannot resolve %s\n", host); return 1; }
    size_t blen = strlen(body);
    request_len = (size_t)snprintf(request, sizeof request,
        "%s %s HTTP/1.1\r\nHost: %s:%s\r\nUser-Agent: nahr_load\r\n%s%s\r\n%s",
        method, path, host, port, headers,
        blen ? "Content-Type: text/plain\r\n" : "", "");
    if (blen) {
        /* Content-Length goes before the blank line. */
        request_len -= 2;
        request_len += (size_t)snprintf(request + request_len, sizeof request - request_len,
            "Content-Length: %zu\r\n\r\n%s", blen, body);
    }

    pthread_t th[256]; worker_t ws[256];
    if (threads > 256) threads = 256;
    for (int i = 0; i < threads; i++) {
        memset(&ws[i], 0, sizeof ws[i]);
        ws[i].id = i;
        ws[i].nconn = conns / threads + (i < conns % threads);
        ws[i].hist = calloc(1, sizeof(hist_t));
        pthread_create(&th[i], 0, work, &ws[i]);
    }
    if (warmup > 0) usleep((useconds_t)(warmup * 1e6));
    atomic_store(&measuring, 1);
    uint64_t t0 = now_ns();
    usleep((useconds_t)(duration * 1e6));
    atomic_store(&measuring, 0);
    uint64_t t1 = now_ns();
    atomic_store(&running, 0);
    for (int i = 0; i < threads; i++) pthread_join(th[i], 0);

    hist_t *all = calloc(1, sizeof(hist_t));
    uint64_t ok = 0, non2xx = 0, wrong = 0, errors = 0, reconnects = 0, bytes = 0, max_ns = 0;
    for (int i = 0; i < threads; i++) {
        hist_merge(all, ws[i].hist);
        ok += ws[i].ok; non2xx += ws[i].non2xx; wrong += ws[i].wrong; errors += ws[i].errors;
        reconnects += ws[i].reconnects; bytes += ws[i].bytes;
        if (ws[i].max_ns > max_ns) max_ns = ws[i].max_ns;
    }
    uint64_t total = ok + non2xx + wrong;
    double secs = (double)(t1 - t0) / 1e9;
    double rps = (double)total / secs;
    if (csv) {
        printf("%s,%s,%d,%.2f,%llu,%.0f,%.2f,%.3f,%.3f,%.3f,%.3f,%.3f,%llu,%llu,%llu,%.2f,%llu,%d\n",
            method, path, conns, secs, (unsigned long long)total, rps, rps / 1000.0,
            hist_pct(all, total, 0.50), hist_pct(all, total, 0.90), hist_pct(all, total, 0.99),
            hist_pct(all, total, 0.999), (double)max_ns / 1e6,
            (unsigned long long)non2xx, (unsigned long long)errors, (unsigned long long)reconnects,
            (double)bytes / secs / 1e6, (unsigned long long)wrong, atomic_load(&established));
    } else {
        printf("%s %s  connections=%d threads=%d  %.1fs\n", method, path, conns, threads, secs);
        printf("  connections  %d of %d established\n", atomic_load(&established), conns);
        if (expected)
            printf("  requests     %llu  (%llu 2xx with the expected body, %llu 2xx with a wrong body, %llu other)\n",
                (unsigned long long)total, (unsigned long long)ok, (unsigned long long)wrong, (unsigned long long)non2xx);
        else
            printf("  requests     %llu  (%llu 2xx, %llu other; bodies not checked)\n", (unsigned long long)total, (unsigned long long)ok, (unsigned long long)non2xx);
        printf("  throughput   %.0f req/s   %.2f req/ms   %.2f MB/s\n", rps, rps / 1000.0, (double)bytes / secs / 1e6);
        printf("  latency ms   p50 %.3f   p90 %.3f   p99 %.3f   p99.9 %.3f   max %.3f\n",
            hist_pct(all, total, 0.50), hist_pct(all, total, 0.90), hist_pct(all, total, 0.99),
            hist_pct(all, total, 0.999), (double)max_ns / 1e6);
        printf("  errors       %llu socket errors, %llu reconnects\n", (unsigned long long)errors, (unsigned long long)reconnects);
    }
    return 0;
}
