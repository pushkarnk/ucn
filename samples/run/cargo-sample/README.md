# cargo-sample

A minimal Rust web application built on **axum** + **tokio**.

## Stack

- **axum** — web framework / routing
- **tokio** — async runtime
- **serde** / **serde_json** — JSON serialization
- **tracing** / **tracing-subscriber** — logging

## Layout

```
src/main.rs            server setup, routes, handlers
src/model.rs           Greeting value object + unit tests
static/index.html      tiny HTML/JS front end (embedded at compile time)
```

## Build & test

```bash
cargo build
cargo test
```

## Run locally

```bash
cargo run          # override the port with: PORT=9090 cargo run
```

Then open <http://localhost:8080/> and click **Greet**, or call the API directly:

```bash
curl 'http://localhost:8080/api/greeting?name=ada'
# {"id":1,"content":"Hello, Ada!"}
```
