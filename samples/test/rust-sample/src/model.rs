use serde::{Deserialize, Serialize};

/// Simple value object returned by the greeting endpoint.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct Greeting {
    pub id: u64,
    pub content: String,
}

impl Greeting {
    pub fn new(id: u64, content: impl Into<String>) -> Self {
        Greeting {
            id,
            content: content.into(),
        }
    }
}

/// Liveness/readiness-style health payload.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct Health {
    pub status: String,
}

impl Health {
    pub fn healthy() -> Self {
        Health {
            status: "healthy".to_string(),
        }
    }
}

/// Uppercase the first character of `s`, leaving the rest untouched.
pub fn capitalize(s: &str) -> String {
    let mut chars = s.chars();
    match chars.next() {
        None => String::new(),
        Some(first) => first.to_uppercase().collect::<String>() + chars.as_str(),
    }
}

/// Build a greeting message for the provided name (blank falls back to World).
pub fn format_greeting(name: &str) -> String {
    let cleaned = name.trim();
    let name = if cleaned.is_empty() { "World" } else { cleaned };
    format!("Hello, {}!", capitalize(name))
}
