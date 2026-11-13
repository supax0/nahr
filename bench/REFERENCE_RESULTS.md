# Reference run

Linux x86_64, 2 CPUs (cloud VM), the SultanC tree of 2026-11-06 with its native backend, load generator on the same machine (2 threads), 3 s per run. An early baseline, kept for reference: later trees and the LLVM backend are considerably faster, so run `bench/run.sh` for current numbers.

## In-process (Nahr dispatch, one thread, no sockets)

| scenario | requests | ns/request | requests/ms (1 thread) | 4xx/5xx |
|---|---|---|---|---|
| GET /plain | 50000 | 15183 | 65 | 0 |
| GET /json | 50000 | 22092 | 45 | 0 |
| GET /params/7?q=a | 50000 | 29543 | 33 | 0 |
| POST /echo | 50000 | 16755 | 59 | 0 |
| GET /large (64 KiB) | 1000 | 971135 | 1 | 0 |
| GET /missing (404) | 50000 | 17480 | 57 | 50000 |
| GET /plain +middleware | 50000 | 37907 | 26 | 0 |
| GET /json +middleware | 50000 | 41953 | 23 | 0 |
| GET /params/7?q=a +middleware | 50000 | 51930 | 19 | 0 |
| POST /echo +middleware | 50000 | 45041 | 22 | 0 |
| GET /large (64 KiB) +middleware | 1000 | 3163428 | 0 | 0 |
| GET /missing (404) +middleware | 50000 | 62263 | 16 | 50000 |

## Over HTTP (keep-alive, nahr_load)

req/ms is completed requests per millisecond; latency in ms.

| mode | middleware | request | connections | req/ms | p50 | p90 | p99 | p99.9 | max | non-2xx | socket errors |
|---|---|---|---|---|---|---|---|---|---|---|---|
| serial | off | GET /plain | 2 | 10.14 | 0.084 | 0.100 | 0.140 | 0.370 | 6.4 | 0 | 0 |
| serial | off | GET /plain | 16 | 10.13 | 0.084 | 0.100 | 0.128 | 0.288 | 1.2 | 0 | 0 |
| serial | off | GET /plain | 64 | 9.51 | 0.087 | 0.118 | 0.159 | 0.302 | 1.7 | 0 | 0 |
| serial | off | GET /json | 2 | 9.53 | 0.090 | 0.116 | 0.163 | 0.378 | 2.0 | 0 | 0 |
| serial | off | GET /json | 16 | 9.34 | 0.092 | 0.108 | 0.162 | 0.511 | 2.4 | 0 | 0 |
| serial | off | GET /json | 64 | 8.91 | 0.095 | 0.121 | 0.160 | 0.308 | 1.4 | 0 | 0 |
| serial | off | GET /params/7?q=a | 2 | 8.71 | 0.102 | 0.124 | 0.171 | 0.383 | 2.1 | 0 | 0 |
| serial | off | GET /params/7?q=a | 16 | 8.19 | 0.107 | 0.131 | 0.191 | 0.528 | 7.7 | 0 | 0 |
| serial | off | GET /params/7?q=a | 64 | 8.85 | 0.099 | 0.119 | 0.162 | 0.305 | 3.3 | 0 | 0 |
| serial | off | POST /echo | 2 | 9.08 | 0.095 | 0.115 | 0.149 | 0.255 | 2.8 | 0 | 0 |
| serial | off | POST /echo | 16 | 8.69 | 0.101 | 0.131 | 0.182 | 0.421 | 2.4 | 0 | 0 |
| serial | off | POST /echo | 64 | 8.21 | 0.107 | 0.129 | 0.178 | 0.950 | 2.1 | 0 | 0 |
| serial | off | GET /large | 2 | 1.26 | 0.743 | 0.900 | 1.378 | 4.979 | 13.8 | 0 | 0 |
| serial | off | GET /large | 16 | 1.28 | 0.744 | 0.959 | 1.464 | 2.174 | 3.8 | 0 | 0 |
| serial | off | GET /large | 64 | 1.35 | 0.711 | 0.829 | 1.293 | 1.522 | 2.9 | 0 | 0 |
| serial | off | GET /sleep | 2 | 0.10 | 10.300 | 10.400 | 10.800 | 13.000 | 19.0 | 0 | 0 |
| serial | off | GET /sleep | 16 | 0.10 | 10.300 | 10.400 | 11.000 | 12.100 | 12.6 | 0 | 0 |
| serial | off | GET /sleep | 64 | 0.10 | 10.400 | 10.500 | 10.600 | 10.800 | 12.1 | 0 | 0 |
| serial | off | GET /cpu | 2 | 0.55 | 1.705 | 1.946 | 3.090 | 3.605 | 643.7 | 0 | 0 |
| serial | off | GET /cpu | 16 | 0.56 | 1.773 | 2.026 | 2.843 | 3.541 | 4.0 | 0 | 0 |
| serial | off | GET /cpu | 64 | 0.55 | 1.772 | 2.000 | 3.927 | 4.207 | 4.4 | 0 | 0 |
| serial | off | GET /alloc | 2 | 1.90 | 0.490 | 0.569 | 0.829 | 3.138 | 7.4 | 0 | 0 |
| serial | off | GET /alloc | 16 | 1.56 | 0.603 | 0.711 | 0.973 | 1.911 | 3.8 | 0 | 0 |
| serial | off | GET /alloc | 64 | 1.90 | 0.485 | 0.647 | 0.790 | 2.533 | 4.6 | 0 | 0 |
| serial | on | GET /plain | 2 | 7.56 | 0.112 | 0.141 | 0.197 | 0.566 | 5.9 | 0 | 0 |
| serial | on | GET /plain | 16 | 6.32 | 0.140 | 0.176 | 0.245 | 0.649 | 2.4 | 0 | 0 |
| serial | on | GET /plain | 64 | 6.65 | 0.135 | 0.163 | 0.238 | 0.525 | 1.5 | 0 | 0 |
| serial | on | GET /json | 2 | 6.56 | 0.138 | 0.173 | 0.243 | 0.633 | 8.4 | 0 | 0 |
| serial | on | GET /json | 16 | 6.40 | 0.138 | 0.166 | 0.242 | 0.499 | 3.3 | 0 | 0 |
| serial | on | GET /json | 64 | 6.03 | 0.140 | 0.188 | 0.279 | 0.971 | 4.1 | 0 | 0 |
| serial | on | GET /params/7?q=a | 2 | 5.53 | 0.154 | 0.207 | 0.308 | 1.186 | 2.9 | 0 | 0 |
| serial | on | GET /params/7?q=a | 16 | 5.67 | 0.154 | 0.212 | 0.353 | 0.818 | 2.4 | 0 | 0 |
| serial | on | GET /params/7?q=a | 64 | 5.78 | 0.150 | 0.201 | 0.299 | 0.982 | 3.4 | 0 | 0 |
| serial | on | POST /echo | 2 | 5.82 | 0.155 | 0.182 | 0.254 | 0.684 | 2.3 | 0 | 0 |
| serial | on | POST /echo | 16 | 5.64 | 0.160 | 0.188 | 0.270 | 0.436 | 2.3 | 0 | 0 |
| serial | on | POST /echo | 64 | 5.82 | 0.156 | 0.178 | 0.265 | 0.502 | 2.9 | 0 | 0 |
| serial | on | GET /large | 2 | 0.33 | 2.895 | 3.298 | 4.659 | 4.961 | 7.0 | 0 | 0 |
| serial | on | GET /large | 16 | 0.33 | 2.915 | 3.270 | 4.794 | 5.670 | 8.3 | 0 | 0 |
| serial | on | GET /large | 64 | 0.31 | 3.033 | 4.070 | 5.468 | 5.890 | 6.1 | 0 | 0 |
| serial | on | GET /sleep | 2 | 0.09 | 10.400 | 10.500 | 10.900 | 11.800 | 14.2 | 0 | 0 |
| serial | on | GET /sleep | 16 | 0.09 | 10.400 | 10.500 | 10.800 | 12.200 | 12.3 | 0 | 0 |
| serial | on | GET /sleep | 64 | 0.09 | 10.400 | 10.500 | 10.900 | 11.100 | 11.2 | 0 | 0 |
| serial | on | GET /cpu | 2 | 0.46 | 1.913 | 2.482 | 3.714 | 5.048 | 653.4 | 0 | 0 |
| serial | on | GET /cpu | 16 | 0.48 | 1.923 | 2.908 | 4.237 | 4.653 | 5.9 | 0 | 0 |
| serial | on | GET /cpu | 64 | 0.46 | 1.919 | 3.259 | 3.923 | 5.840 | 7.6 | 0 | 0 |
| serial | on | GET /alloc | 2 | 1.33 | 0.708 | 0.895 | 1.051 | 2.483 | 3.1 | 0 | 0 |
| serial | on | GET /alloc | 16 | 1.28 | 0.706 | 0.923 | 1.559 | 3.345 | 10.9 | 0 | 0 |
| serial | on | GET /alloc | 64 | 1.31 | 0.702 | 0.900 | 1.361 | 2.993 | 36.7 | 0 | 0 |
| pool | off | GET /plain | 2 | 8.22 | 0.206 | 0.349 | 0.473 | 1.596 | 6.9 | 0 | 0 |
| pool | off | GET /plain | 16 | 5.68 | 0.326 | 0.463 | 0.816 | 2.141 | 5.5 | 0 | 0 |
| pool | off | GET /plain | 64 | 5.99 | 0.306 | 0.415 | 0.850 | 3.870 | 10.6 | 0 | 0 |
| pool | off | GET /json | 2 | 5.58 | 0.349 | 0.460 | 0.783 | 2.377 | 6.9 | 0 | 0 |
| pool | off | GET /json | 16 | 6.01 | 0.328 | 0.394 | 0.519 | 1.338 | 6.2 | 0 | 0 |
| pool | off | GET /json | 64 | 6.09 | 0.316 | 0.415 | 0.564 | 1.008 | 2.8 | 0 | 0 |
| pool | off | GET /params/7?q=a | 2 | 4.82 | 0.411 | 0.554 | 0.719 | 1.627 | 3.3 | 0 | 0 |
| pool | off | GET /params/7?q=a | 16 | 4.87 | 0.400 | 0.537 | 0.718 | 2.766 | 7.7 | 0 | 0 |
| pool | off | GET /params/7?q=a | 64 | 4.54 | 0.427 | 0.523 | 0.754 | 1.531 | 2.6 | 0 | 0 |
| pool | off | POST /echo | 2 | 4.84 | 0.395 | 0.528 | 0.767 | 1.487 | 6.6 | 0 | 0 |
| pool | off | POST /echo | 16 | 4.74 | 0.405 | 0.498 | 0.687 | 1.382 | 2.4 | 0 | 0 |
| pool | off | POST /echo | 64 | 4.63 | 0.406 | 0.523 | 0.858 | 2.686 | 4.2 | 0 | 0 |
| pool | off | GET /large | 2 | 2.13 | 0.844 | 1.340 | 1.926 | 3.034 | 6.1 | 0 | 0 |
| pool | off | GET /large | 16 | 2.13 | 0.868 | 1.157 | 1.660 | 2.793 | 7.9 | 0 | 0 |
| pool | off | GET /large | 64 | 2.29 | 0.824 | 1.046 | 1.681 | 3.587 | 12.1 | 0 | 0 |
| pool | off | GET /sleep | 2 | 0.19 | 10.400 | 10.500 | 10.900 | 14.300 | 14.4 | 0 | 0 |
| pool | off | GET /sleep | 16 | 0.19 | 10.400 | 10.500 | 10.600 | 10.900 | 12.7 | 0 | 0 |
| pool | off | GET /sleep | 64 | 0.19 | 10.400 | 10.500 | 10.700 | 11.000 | 11.1 | 0 | 0 |
| pool | off | GET /cpu | 2 | 1.14 | 1.700 | 2.064 | 3.352 | 3.901 | 7.1 | 0 | 0 |
| pool | off | GET /cpu | 16 | 1.12 | 1.682 | 2.255 | 3.741 | 5.473 | 6.8 | 0 | 0 |
| pool | off | GET /cpu | 64 | 1.03 | 1.795 | 2.499 | 3.687 | 4.699 | 6.3 | 0 | 0 |
| pool | off | GET /alloc | 2 | 0.77 | 2.531 | 3.163 | 3.792 | 4.712 | 5.5 | 0 | 0 |
| pool | off | GET /alloc | 16 | 0.77 | 2.519 | 3.188 | 3.826 | 5.430 | 7.6 | 0 | 0 |
| pool | off | GET /alloc | 64 | 0.71 | 2.755 | 3.419 | 4.284 | 7.801 | 9.4 | 0 | 0 |
| pool | on | GET /plain | 2 | 3.90 | 0.502 | 0.635 | 1.079 | 2.925 | 11.5 | 0 | 0 |
| pool | on | GET /plain | 16 | 3.71 | 0.512 | 0.693 | 0.882 | 2.453 | 10.3 | 0 | 0 |
| pool | on | GET /plain | 64 | 3.76 | 0.511 | 0.625 | 0.853 | 2.085 | 8.0 | 0 | 0 |
| pool | on | GET /json | 2 | 3.60 | 0.555 | 0.651 | 0.884 | 2.719 | 5.2 | 0 | 0 |
| pool | on | GET /json | 16 | 3.54 | 0.556 | 0.660 | 0.993 | 2.212 | 3.2 | 0 | 0 |
| pool | on | GET /json | 64 | 3.73 | 0.528 | 0.636 | 0.918 | 2.587 | 4.4 | 0 | 0 |
| pool | on | GET /params/7?q=a | 2 | 3.24 | 0.611 | 0.727 | 1.023 | 1.981 | 3.2 | 0 | 0 |
| pool | on | GET /params/7?q=a | 16 | 3.12 | 0.619 | 0.759 | 1.155 | 2.280 | 3.8 | 0 | 0 |
| pool | on | GET /params/7?q=a | 64 | 3.19 | 0.607 | 0.744 | 1.000 | 2.512 | 10.5 | 0 | 0 |
| pool | on | POST /echo | 2 | 3.03 | 0.630 | 0.897 | 1.651 | 3.414 | 8.8 | 0 | 0 |
| pool | on | POST /echo | 16 | 3.03 | 0.653 | 0.791 | 0.991 | 2.625 | 3.8 | 0 | 0 |
| pool | on | POST /echo | 64 | 3.04 | 0.644 | 0.785 | 1.063 | 2.339 | 10.2 | 0 | 0 |
| pool | on | GET /large | 2 | 0.56 | 3.466 | 4.096 | 5.941 | 8.484 | 9.2 | 0 | 0 |
| pool | on | GET /large | 16 | 0.59 | 3.449 | 3.649 | 4.059 | 6.754 | 7.8 | 0 | 0 |
| pool | on | GET /large | 64 | 0.56 | 3.487 | 4.260 | 5.938 | 6.430 | 7.1 | 0 | 0 |
| pool | on | GET /sleep | 2 | 0.19 | 10.500 | 10.700 | 11.600 | 14.100 | 14.2 | 0 | 0 |
| pool | on | GET /sleep | 16 | 0.19 | 10.500 | 10.600 | 12.000 | 14.200 | 24.0 | 0 | 0 |
| pool | on | GET /sleep | 64 | 0.19 | 10.500 | 10.700 | 12.400 | 13.600 | 13.6 | 0 | 0 |
| pool | on | GET /cpu | 2 | 1.04 | 1.851 | 2.228 | 3.663 | 4.394 | 27.2 | 0 | 0 |
| pool | on | GET /cpu | 16 | 1.06 | 1.834 | 2.169 | 3.669 | 4.269 | 6.0 | 0 | 0 |
| pool | on | GET /cpu | 64 | 1.05 | 1.856 | 2.205 | 3.513 | 5.410 | 10.4 | 0 | 0 |
| pool | on | GET /alloc | 2 | 0.72 | 2.830 | 3.379 | 5.519 | 8.307 | 14.1 | 0 | 0 |
| pool | on | GET /alloc | 16 | 0.69 | 2.901 | 3.201 | 4.280 | 5.923 | 6.9 | 0 | 0 |
| pool | on | GET /alloc | 64 | 0.68 | 2.897 | 3.375 | 4.278 | 5.442 | 6.9 | 0 | 0 |

## Peak per endpoint

| request | best req/ms | at | p99 there |
|---|---|---|---|
| GET /alloc | 1.90 | serial, middleware off, 2 connections | 0.829 ms |
| GET /cpu | 1.14 | pool, middleware off, 2 connections | 3.352 ms |
| POST /echo | 9.08 | serial, middleware off, 2 connections | 0.149 ms |
| GET /json | 9.53 | serial, middleware off, 2 connections | 0.163 ms |
| GET /large | 2.29 | pool, middleware off, 64 connections | 1.681 ms |
| GET /params/7?q=a | 8.85 | serial, middleware off, 64 connections | 0.162 ms |
| GET /plain | 10.14 | serial, middleware off, 2 connections | 0.140 ms |
| GET /sleep | 0.19 | pool, middleware off, 16 connections | 10.600 ms |
