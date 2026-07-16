# rust-sample

A minimal Cargo-based Rust web application built on **axum** + **tokio** that
ships with **extra test-only dependencies** (`tower`, `http-body-util`,
`pretty_assertions`) that are not needed at runtime.

## Stack

- **axum**, **tokio**, **serde** / **serde_json**, **tracing** — runtime crates
- **tower**, **http-body-util**, **http**, **pretty_assertions** — test-only crates (`[dev-dependencies]`)

## Layout

```
Cargo.toml                 package metadata, runtime + dev-dependencies
src/main.rs                server setup, routes, handlers
src/model.rs               Greeting / Health value objects + helpers
src/lib.rs                 library surface used by integration tests
static/index.html          tiny HTML/JS front end (embedded at compile time)
tests/app_tests.rs         HTTP endpoint tests (tower oneshot)
tests/model_tests.rs       unit tests for models
ucn.yaml                   cloud-native demo config (setup runs tests)
```

## Test

```bash
cargo test
```

## Run

```bash
cargo run          # override the port with: PORT=9090 cargo run
```

Then open <http://localhost:8080/> and click **Greet**, or call the API:

```bash
curl 'http://localhost:8080/api/greeting?name=ada'
# {"id":1,"content":"Hello, Ada!"}

curl 'http://localhost:8080/health'
# {"status":"healthy"}
```
