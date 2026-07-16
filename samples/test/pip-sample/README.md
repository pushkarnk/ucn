# pip-sample

A minimal pip-based Python web application built with **FastAPI** that ships with
**extra test-only dependencies** (pytest, httpx, pytest-mock) that are not needed
at runtime.

## Stack

- **Python 3.10+**
- **FastAPI**, **Uvicorn**, **Pydantic** — runtime libraries
- **pytest**, **httpx**, **pytest-mock** — test-only libraries (`.[test]` extra)

## Layout

```
pyproject.toml                 project metadata, runtime + optional test deps
src/sampleapp/app.py           FastAPI app and entry point
src/sampleapp/models.py        Pydantic models
tests/test_app.py              HTTP endpoint tests (TestClient / httpx)
tests/test_models.py           unit tests for models
ucn.yaml                       cloud-native demo config (setup runs tests)
```

## Test

```bash
python3 -m venv .venv
.venv/bin/pip install -e '.[test]'
.venv/bin/pytest -v
```

## Run

```bash
python3 -m venv .venv
.venv/bin/pip install -e .
.venv/bin/sampleapp            # override the port with: PORT=9090 .venv/bin/sampleapp
```

Then open <http://localhost:8080/> or:

```bash
curl 'http://localhost:8080/api/greeting?name=ada'
# {"id":1,"content":"Hello, Ada!"}

curl 'http://localhost:8080/health'
# {"status":"healthy"}
```
