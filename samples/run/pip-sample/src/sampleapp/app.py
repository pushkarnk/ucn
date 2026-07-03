"""Minimal sample web app with a few PyPI dependencies."""

import os

import httpx
from fastapi import FastAPI
from pydantic import BaseModel

app = FastAPI(title="sampleapp")


class Echo(BaseModel):
    message: str


@app.get("/")
def root():
    return {"status": "Hello, Ubuntu!", "service": "sampleapp"}


@app.post("/echo")
def echo(body: Echo):
    return {"echo": body.message}


@app.get("/ip")
def my_ip():
    # Exercises an outbound dependency (httpx)
    r = httpx.get("https://api.ipify.org?format=json", timeout=5)
    return r.json()


def main():
    import uvicorn

    port = int(os.environ.get("PORT", "8080"))
    uvicorn.run(app, host="0.0.0.0", port=port)


if __name__ == "__main__":
    main()
