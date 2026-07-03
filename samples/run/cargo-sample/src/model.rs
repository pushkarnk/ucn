use serde::Serialize;

/// Simple value object returned by the greeting endpoint.
#[derive(Debug, Clone, Serialize)]
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

/// Uppercase the first character of `s`, leaving the rest untouched.
/// Mirrors Apache Commons `StringUtils.capitalize`.
pub fn capitalize(s: &str) -> String {
    let mut chars = s.chars();
    match chars.next() {
        None => String::new(),
        Some(first) => first.to_uppercase().collect::<String>() + chars.as_str(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn exposes_id_and_content() {
        let g = Greeting::new(1, "Hello, World!");
        assert_eq!(g.id, 1);
        assert_eq!(g.content, "Hello, World!");
    }

    #[test]
    fn capitalize_uppercases_first_char() {
        assert_eq!(capitalize("ada"), "Ada");
        assert_eq!(capitalize(""), "");
        assert_eq!(capitalize("World"), "World");
    }
}
