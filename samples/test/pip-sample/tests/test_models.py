"""Unit tests for domain models (uses pytest, a test-only dependency)."""

import pytest

from sampleapp.models import Echo, Greeting, Health


def test_greeting_exposes_id_and_content():
    greeting = Greeting(id=1, content="Hello, World!")
    assert greeting.id == 1
    assert greeting.content == "Hello, World!"


@pytest.mark.parametrize(
    "greeting_id,content",
    [
        (1, "Hello, Ada!"),
        (42, "Hello, World!"),
        (100, "Bonjour, Guest!"),
    ],
)
def test_greeting_preserves_assigned_values(greeting_id, content):
    greeting = Greeting(id=greeting_id, content=content)
    assert greeting.id == greeting_id
    assert greeting.content == content


def test_health_default_status():
    assert Health().status == "healthy"


def test_echo_rejects_empty_message():
    with pytest.raises(Exception):
        Echo(message="")
