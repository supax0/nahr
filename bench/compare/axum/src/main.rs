// The endpoints of nahr/bench/server.sn in axum, to compare against Nahr on
// the same machine with the same load tool (nahr/bench/load.c).
//
//   AXUM_PORT=8091  AXUM_WORKERS=2  AXUM_MIDDLEWARE=1 (request id + gzip)
//
//   GET /plain   "ok"
//   GET /json    {"name":"nahr","id":42}
//   GET /large   64 KiB of text (with middleware: gzip of it)
use axum::{extract::State, http::HeaderName, routing::get, Json, Router};
use serde::Serialize;
use std::sync::Arc;
use tower_http::{
    compression::CompressionLayer,
    request_id::{MakeRequestUuid, PropagateRequestIdLayer, SetRequestIdLayer},
};

#[derive(Serialize)]
struct Item {
    name: &'static str,
    id: i64,
}

async fn plain() -> &'static str {
    "ok"
}

async fn json() -> Json<Item> {
    Json(Item { name: "nahr", id: 42 })
}

// A copy of the shared body per response, as Nahr's text_response makes.
async fn large(State(body): State<Arc<String>>) -> String {
    (*body).clone()
}

fn main() {
    let port = std::env::var("AXUM_PORT").unwrap_or_else(|_| "8091".into());
    let workers: usize = std::env::var("AXUM_WORKERS")
        .ok()
        .and_then(|v| v.parse().ok())
        .filter(|n| *n > 0)
        .unwrap_or_else(|| std::thread::available_parallelism().map(|n| n.get()).unwrap_or(1));
    let middleware = std::env::var("AXUM_MIDDLEWARE").map(|v| v == "1").unwrap_or(false);
    let runtime = tokio::runtime::Builder::new_multi_thread()
        .worker_threads(workers)
        .enable_all()
        .build()
        .expect("runtime");
    runtime.block_on(async move {
        let body = Arc::new("0123456789abcdef".repeat(4096));
        let mut app = Router::new()
            .route("/plain", get(plain))
            .route("/json", get(json))
            .route("/large", get(large))
            .with_state(body);
        if middleware {
            let header = HeaderName::from_static("x-request-id");
            app = app
                .layer(CompressionLayer::new())
                .layer(PropagateRequestIdLayer::new(header.clone()))
                .layer(SetRequestIdLayer::new(header, MakeRequestUuid));
        }
        let listener = tokio::net::TcpListener::bind(format!("127.0.0.1:{port}"))
            .await
            .expect("bind");
        axum::serve(listener, app).await.expect("serve");
    });
}
