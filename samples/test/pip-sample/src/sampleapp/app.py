"""Minimal sample web app with runtime PyPI dependencies and a separate test suite."""

import os
from itertools import count

from fastapi import FastAPI, Query

from sampleapp.models import Echo, Greeting, Health

app = FastAPI(title="sampleapp")
_greeting_ids = count(1)


def format_greeting(name: str) -> str:
    cleaned = (name or "World").strip() or "World"
    return f"Hello, {cleaned.capitalize()}!"


@app.get("/")
def root():
    return {"status": "Hello, Ubuntu!", "service": "sampleapp"}


@app.get("/health", response_model=Health)
def health():
    return Health(status="healthy")


@app.get("/api/greeting", response_model=Greeting)
def greeting(name: str = Query(default="World")):
    return Greeting(id=next(_greeting_ids), content=format_greeting(name))


@app.post("/echo")
def echo(body: Echo):
    return {"echo": body.message}


def main():
    import uvicorn

    port = int(os.environ.get("PORT", "8080"))
    uvicorn.run(app, host="0.0.0.0", port=port)


if __name__ == "__main__":
    main()
