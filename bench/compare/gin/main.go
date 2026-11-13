// Gin in release mode, no middleware: GET /plain answers "ok".
// COMPARE_PORT (8090), COMPARE_WORKERS (GOMAXPROCS; 0 = every core).
package main

import (
	"os"
	"runtime"
	"strconv"

	"github.com/gin-gonic/gin"
)

func main() {
	if n, err := strconv.Atoi(os.Getenv("COMPARE_WORKERS")); err == nil && n > 0 {
		runtime.GOMAXPROCS(n)
	}
	port := os.Getenv("COMPARE_PORT")
	if port == "" {
		port = "8090"
	}
	gin.SetMode(gin.ReleaseMode)
	r := gin.New()
	r.GET("/plain", func(c *gin.Context) { c.String(200, "ok") })
	if err := r.Run("127.0.0.1:" + port); err != nil {
		panic(err)
	}
}
