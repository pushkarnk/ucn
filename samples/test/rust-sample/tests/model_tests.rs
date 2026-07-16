//! Unit tests for domain models (uses pretty_assertions, a test-only dependency).

use pretty_assertions::assert_eq;
use rust_sample::model::{capitalize, format_greeting, Greeting, Health};

#[test]
fn greeting_exposes_id_and_content() {
    let g = Greeting::new(1, "Hello, World!");
    assert_eq!(g.id, 1);
    assert_eq!(g.content, "Hello, World!");
}

#[test]
fn greeting_preserves_assigned_values() {
    for (id, content) in [
        (1u64, "Hello, Ada!"),
        (42, "Hello, World!"),
        (100, "Bonjour, Guest!"),
    ] {
        let g = Greeting::new(id, content);
        assert_eq!(g.id, id);
        assert_eq!(g.content, content);
    }
}

#[test]
fn health_reports_healthy() {
    assert_eq!(Health::healthy().status, "healthy");
}

#[test]
fn capitalize_uppercases_first_char() {
    assert_eq!(capitalize("ada"), "Ada");
    assert_eq!(capitalize(""), "");
    assert_eq!(capitalize("World"), "World");
}

#[test]
fn format_greeting_default_and_custom() {
    assert_eq!(format_greeting(""), "Hello, World!");
    assert_eq!(format_greeting("  "), "Hello, World!");
    assert_eq!(format_greeting("ada"), "Hello, Ada!");
}
