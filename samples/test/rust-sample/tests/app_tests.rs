//! HTTP endpoint tests via axum + tower oneshot (uses tower/http-body-util, test-only deps).

use std::sync::Arc;

use axum::body::Body;
use http::{Request, StatusCode};
use http_body_util::BodyExt;
use pretty_assertions::assert_eq;
use tower::ServiceExt;

use rust_sample::{app, AppState};

async fn body_json(response: axum::response::Response) -> serde_json::Value {
    let bytes = response.into_body().collect().await.unwrap().to_bytes();
    serde_json::from_slice(&bytes).unwrap()
}

async fn get(path: &str) -> axum::response::Response {
    let state = Arc::new(AppState::default());
    let router = app(state);
    router
        .oneshot(
            Request::builder()
                .uri(path)
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap()
}

#[tokio::test]
async fn root_serves_html() {
    let response = get("/").await;
    assert_eq!(response.status(), StatusCode::OK);
    let bytes = response.into_body().collect().await.unwrap().to_bytes();
    let html = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(html.contains("Rust Sample Web App"));
}

#[tokio::test]
async fn health_returns_healthy_status() {
    let response = get("/health").await;
    assert_eq!(response.status(), StatusCode::OK);
    let body = body_json(response).await;
    assert_eq!(body, serde_json::json!({"status": "healthy"}));
}

#[tokio::test]
async fn greeting_default_name() {
    let response = get("/api/greeting").await;
    assert_eq!(response.status(), StatusCode::OK);
    let body = body_json(response).await;
    assert_eq!(body["content"], "Hello, World!");
    assert!(body["id"].as_u64().unwrap() >= 1);
}

#[tokio::test]
async fn greeting_capitalizes_provided_name() {
    let response = get("/api/greeting?name=ada").await;
    assert_eq!(response.status(), StatusCode::OK);
    let body = body_json(response).await;
    assert_eq!(body["content"], "Hello, Ada!");
}

#[tokio::test]
async fn greeting_blank_name_falls_back_to_world() {
    let response = get("/api/greeting?name=%20%20").await;
    assert_eq!(response.status(), StatusCode::OK);
    let body = body_json(response).await;
    assert_eq!(body["content"], "Hello, World!");
}
