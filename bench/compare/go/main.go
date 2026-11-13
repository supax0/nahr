// net/http with the standard library only: GET /plain answers "ok".
// COMPARE_PORT (8090), COMPARE_WORKERS (GOMAXPROCS; 0 = every core).
package main

import (
	"net/http"
	"os"
	"runtime"
	"strconv"
)

func main() {
	if n, err := strconv.Atoi(os.Getenv("COMPARE_WORKERS")); err == nil && n > 0 {
		runtime.GOMAXPROCS(n)
	}
	port := os.Getenv("COMPARE_PORT")
	if port == "" {
		port = "8090"
	}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /plain", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		w.Write([]byte("ok"))
	})
	if err := http.ListenAndServe("127.0.0.1:"+port, mux); err != nil {
		panic(err)
	}
}
