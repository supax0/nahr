// Node's own http module, one process per worker (cluster): GET /plain
// answers "ok". COMPARE_PORT (8090), COMPARE_WORKERS (0 = every core).
const cluster = require("node:cluster");
const http = require("node:http");
const os = require("node:os");

const port = Number(process.env.COMPARE_PORT || 8090);
const wanted = Number(process.env.COMPARE_WORKERS || 0);
const workers = wanted > 0 ? wanted : os.availableParallelism();

if (cluster.isPrimary && workers > 1) {
  for (let i = 0; i < workers; i++) cluster.fork();
  process.on("SIGTERM", () => {
    for (const id in cluster.workers) cluster.workers[id].kill();
    process.exit(0);
  });
} else {
  http
    .createServer((req, res) => {
      if (req.method === "GET" && req.url === "/plain") {
        res.writeHead(200, { "content-type": "text/plain; charset=utf-8", "content-length": "2" });
        res.end("ok");
      } else {
        res.writeHead(404).end();
      }
    })
    .listen(port, "127.0.0.1");
}
