pub mod model;

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;

use axum::{
    extract::{Query, State},
    response::Html,
    routing::get,
    Json, Router,
};
use serde::Deserialize;

use model::{format_greeting, Greeting, Health};

const INDEX_HTML: &str = include_str!("../static/index.html");

/// Shared application state: a monotonically increasing greeting counter.
#[derive(Default)]
pub struct AppState {
    counter: AtomicU64,
}

#[derive(Debug, Deserialize)]
struct GreetingParams {
    name: Option<String>,
}

/// Builds the application router (shared by `main` and integration tests).
pub fn app(state: Arc<AppState>) -> Router {
    Router::new()
        .route("/", get(index))
        .route("/health", get(health))
        .route("/api/greeting", get(greeting))
        .with_state(state)
}

/// Serves the bundled HTML front end.
async fn index() -> Html<&'static str> {
    Html(INDEX_HTML)
}

/// Liveness/readiness-style health check.
async fn health() -> Json<Health> {
    Json(Health::healthy())
}

/// Returns a JSON greeting. Try `/api/greeting` or `/api/greeting?name=Ada`.
async fn greeting(
    State(state): State<Arc<AppState>>,
    Query(params): Query<GreetingParams>,
) -> Json<Greeting> {
    let name = params.name.unwrap_or_else(|| "World".to_string());
    let id = state.counter.fetch_add(1, Ordering::SeqCst) + 1;
    let greeting = Greeting::new(id, format_greeting(&name));

    tracing::info!(id = greeting.id, name = %name, "Serving greeting");
    Json(greeting)
}
