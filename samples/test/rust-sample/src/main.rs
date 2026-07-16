use std::sync::Arc;

use rust_sample::{app, AppState};

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt::init();

    let state = Arc::new(AppState::default());
    let router = app(state);

    let port: u16 = std::env::var("PORT")
        .ok()
        .and_then(|p| p.parse().ok())
        .unwrap_or(8080);
    let addr = format!("0.0.0.0:{port}");
    let listener = tokio::net::TcpListener::bind(&addr).await.unwrap();

    tracing::info!("Server started at http://localhost:{port}/");
    axum::serve(listener, router).await.unwrap();
}
