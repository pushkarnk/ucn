mod model;

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;

use axum::{
    extract::{Query, State},
    response::Html,
    routing::get,
    Json, Router,
};
use serde::Deserialize;

use model::{capitalize, Greeting};

const DEFAULT_NAME: &str = "World";
const INDEX_HTML: &str = include_str!("../static/index.html");

/// Shared application state: a monotonically increasing greeting counter.
#[derive(Default)]
struct AppState {
    counter: AtomicU64,
}

#[derive(Debug, Deserialize)]
struct GreetingParams {
    name: Option<String>,
}

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt::init();

    let state = Arc::new(AppState::default());

    let app = Router::new()
        .route("/", get(index))
        .route("/api/greeting", get(greeting))
        .with_state(state);

    let port: u16 = std::env::var("PORT").ok().and_then(|p| p.parse().ok()).unwrap_or(8080);
    let addr = format!("0.0.0.0:{port}");
    let listener = tokio::net::TcpListener::bind(&addr).await.unwrap();

    tracing::info!("Server started at http://localhost:{port}/");
    axum::serve(listener, app).await.unwrap();
}

/// Serves the bundled HTML front end.
async fn index() -> Html<&'static str> {
    Html(INDEX_HTML)
}

/// Returns a JSON greeting. Try `/api/greeting` or `/api/greeting?name=Ada`.
async fn greeting(
    State(state): State<Arc<AppState>>,
    Query(params): Query<GreetingParams>,
) -> Json<Greeting> {
    let name = params
        .name
        .filter(|n| !n.trim().is_empty())
        .unwrap_or_else(|| DEFAULT_NAME.to_string());

    let id = state.counter.fetch_add(1, Ordering::SeqCst) + 1;
    let greeting = Greeting::new(id, format!("Bonjour, {}!", capitalize(&name)));

    tracing::info!(id = greeting.id, name = %name, "Serving greeting");
    Json(greeting)
}
