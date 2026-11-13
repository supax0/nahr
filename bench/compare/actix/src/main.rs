// actix-web: GET /plain answers "ok".
// COMPARE_PORT (8090), COMPARE_WORKERS (0 = every core).
use actix_web::{get, App, HttpResponse, HttpServer};

#[get("/plain")]
async fn plain() -> HttpResponse {
    HttpResponse::Ok().content_type("text/plain; charset=utf-8").body("ok")
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    let port = std::env::var("COMPARE_PORT").unwrap_or_else(|_| "8090".into());
    let workers: usize = std::env::var("COMPARE_WORKERS")
        .ok()
        .and_then(|v| v.parse().ok())
        .filter(|n| *n > 0)
        .unwrap_or_else(|| std::thread::available_parallelism().map(|n| n.get()).unwrap_or(1));
    HttpServer::new(|| App::new().service(plain))
        .workers(workers)
        .bind(format!("127.0.0.1:{port}"))?
        .run()
        .await
}
